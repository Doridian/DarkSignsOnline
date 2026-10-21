//! The Dark Signs Online game server: the API the clients talk to and the
//! website's account pages, answering at the `.php` paths the PHP server it
//! replaces answered at, so neither the clients nor any link has to change.
//!
//! It sits behind nginx, which serves the static files and hands this every
//! request for `/<name>.php` or `/api/<name>.php`.
//!
//! ```text
//! darksignsonline-server          serve (see DSO_LISTEN)
//! darksignsonline-server tasks    the periodic cleanup, then exit
//! ```

mod api;
mod ctx;
mod mail;
mod php;
mod request;
mod site;

use std::convert::Infallible;
use std::sync::Arc;

use bytes::Bytes;
use http_body_util::{BodyExt, Full, Limited};
use hyper::body::Incoming;
use hyper::header::{HeaderMap, HeaderValue};
use hyper::server::conn::http1;
use hyper::service::service_fn;
use hyper::{Request as HttpRequest, Response, StatusCode};
use hyper_util::rt::TokioIo;
use mysql_async::prelude::Queryable;
use rsa::RsaPrivateKey;
use rsa::pkcs1::DecodeRsaPrivateKey;
use rsa::pkcs8::DecodePrivateKey;
use tokio::net::{TcpListener, UnixListener};

use crate::ctx::{Ctx, Halt, TEXT_HTML};
use crate::request::{POST_MAX_SIZE, Request};

pub struct SmtpConfig {
    pub host: String,
    pub port: u16,
    pub from: String,
    pub username: String,
    pub password: String,
}

pub struct App {
    pub pool: mysql_async::Pool,
    pub jwt_key: Option<RsaPrivateKey>,
    pub jwt_public_key: Vec<u8>,
    pub smtp: SmtpConfig,
    pub gitrev: String,
}

fn env(name: &str) -> String {
    std::env::var(name).unwrap_or_default()
}

impl App {
    /// Everything comes from the environment, under the names the PHP
    /// deployment already used. The two JWT keys are PEM, base64-encoded so
    /// they fit in one variable.
    fn from_env() -> Result<App, String> {
        let mut opts = mysql_async::OptsBuilder::default()
            .user(Some(env("MYSQL_USERNAME")))
            .pass(Some(env("MYSQL_PASSWORD")))
            .db_name(Some(env("MYSQL_DATABASE")))
            .setup(vec!["SET NAMES utf8mb4"]);
        let socket = env("MYSQL_SOCKET");
        if !socket.is_empty() {
            opts = opts.socket(Some(socket)).prefer_socket(true);
        } else {
            let port = env("MYSQL_PORT");
            opts = opts
                .ip_or_hostname(env("MYSQL_HOST"))
                .tcp_port(if port.is_empty() {
                    3306
                } else {
                    port.parse().map_err(|e| format!("MYSQL_PORT: {e}"))?
                })
                .prefer_socket(false);
        }

        let private_pem = php::base64_decode(env("JWT_PRIVATE_KEY").as_bytes());
        let jwt_key = if private_pem.is_empty() {
            None
        } else {
            let pem = String::from_utf8(private_pem).map_err(|e| format!("JWT_PRIVATE_KEY: {e}"))?;
            Some(
                RsaPrivateKey::from_pkcs8_pem(&pem)
                    .or_else(|_| RsaPrivateKey::from_pkcs1_pem(&pem))
                    .map_err(|e| format!("JWT_PRIVATE_KEY: {e}"))?,
            )
        };

        let smtp_port = env("SMTP_PORT");
        Ok(App {
            pool: mysql_async::Pool::new(opts),
            jwt_key,
            jwt_public_key: php::base64_decode(env("JWT_PUBLIC_KEY").as_bytes()),
            smtp: SmtpConfig {
                host: env("SMTP_HOST"),
                port: if smtp_port.is_empty() {
                    25
                } else {
                    smtp_port.parse().map_err(|e| format!("SMTP_PORT: {e}"))?
                },
                from: env("SMTP_FROM"),
                username: env("SMTP_USERNAME"),
                password: env("SMTP_PASSWORD"),
            },
            gitrev: std::env::var("DSO_GITREV")
                .ok()
                .or_else(|| option_env!("DSO_GITREV").map(str::to_string))
                .unwrap_or_else(|| "unknown".into()),
        })
    }
}

/// A header's value, repeats joined with `, ` the way nginx joins them for
/// a FastCGI backend.
fn header_bytes(headers: &HeaderMap, name: &str) -> Option<Vec<u8>> {
    let mut values = headers.get_all(name).iter().map(HeaderValue::as_bytes).peekable();
    values.peek()?;
    Some(values.collect::<Vec<_>>().join(&b", "[..]))
}

/// Which script a path names: `("api", "chat")` for `/api/chat.php`. The
/// same paths nginx's `^/(api/)?[a-z0-9_]+\.php$` sends here.
fn route(path: &str) -> Option<(bool, &str)> {
    if path == "/" {
        return Some((false, "index"));
    }
    let rest = path.strip_prefix('/')?;
    let (api, rest) = match rest.strip_prefix("api/") {
        Some(r) => (true, r),
        None => (false, rest),
    };
    let name = rest.strip_suffix(".php")?;
    let valid = !name.is_empty()
        && name
            .bytes()
            .all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == b'_');
    valid.then_some((api, name))
}

async fn handle(app: Arc<App>, peer: String, req: HttpRequest<Incoming>) -> Result<Response<Full<Bytes>>, Infallible> {
    let (parts, body) = req.into_parts();
    let body = Limited::new(body, POST_MAX_SIZE)
        .collect()
        .await
        .ok()
        .map(|b| b.to_bytes());

    let header = |name| header_bytes(&parts.headers, name);
    let mut request = Request::new(
        parts.method.as_str().to_string(),
        parts.uri.path().to_string(),
        parts.uri.query(),
        header("content-type").as_deref(),
        body.as_deref(),
    );
    request.protocol_version = header("dso-protocol-version");
    request.authorization = header("authorization");
    // nginx says who is on the other end; without it, the socket does.
    request.remote_addr = header("x-real-ip").map_or(peer, |ip| String::from_utf8_lossy(&ip).into_owned());

    let mut ctx = Ctx::new(app, request);
    let path = ctx.req.path.clone();
    let result = match route(&path) {
        Some((true, name)) => api::dispatch(name, &mut ctx).await,
        Some((false, name)) => site::dispatch(name, &mut ctx).await,
        None => None,
    };
    ctx.finish().await;

    let Some(result) = result else {
        // What php-fpm said for a script that was not there.
        let mut resp = Response::new(Full::new(Bytes::from_static(b"File not found.\n")));
        *resp.status_mut() = StatusCode::NOT_FOUND;
        resp.headers_mut()
            .insert("content-type", HeaderValue::from_static(TEXT_HTML));
        return Ok(resp);
    };
    if let Err(Halt::Fatal(e)) = result {
        // An uncaught exception: PHP made it a 500 unless a status had
        // already been chosen, and sent whatever had been written.
        eprintln!("{} {path}: {e}", ctx.req.method);
        if ctx.status == 200 {
            ctx.status = 500;
        }
    }

    let mut resp = Response::new(Full::new(Bytes::from(std::mem::take(&mut ctx.out))));
    *resp.status_mut() = StatusCode::from_u16(ctx.status).unwrap_or(StatusCode::INTERNAL_SERVER_ERROR);
    let headers = resp.headers_mut();
    headers.insert("content-type", HeaderValue::from_static(ctx.content_type));
    for (name, value) in ctx.headers.drain(..) {
        if let Ok(value) = HeaderValue::from_str(&value) {
            headers.append(name, value);
        }
    }
    Ok(resp)
}

fn serve_conn<S>(app: Arc<App>, peer: String, stream: S)
where
    S: tokio::io::AsyncRead + tokio::io::AsyncWrite + Unpin + Send + 'static,
{
    tokio::spawn(async move {
        let service = service_fn(move |req| handle(app.clone(), peer.clone(), req));
        if let Err(e) = http1::Builder::new()
            .serve_connection(TokioIo::new(stream), service)
            .await
        {
            eprintln!("connection: {e}");
        }
    });
}

/// `DSO_LISTEN` is `unix:/path/to.sock` or `host:port`; the default is a
/// socket for the nginx on the same machine.
async fn serve(app: Arc<App>) -> std::io::Result<()> {
    let listen = std::env::var("DSO_LISTEN").unwrap_or_else(|_| "unix:/run/darksignsonline/server.sock".into());
    if let Some(path) = listen.strip_prefix("unix:") {
        let _ = std::fs::remove_file(path);
        let listener = UnixListener::bind(path)?;
        eprintln!("listening on {listen}");
        loop {
            let (stream, _) = listener.accept().await?;
            serve_conn(app.clone(), String::new(), stream);
        }
    } else {
        let listener = TcpListener::bind(&listen).await?;
        eprintln!("listening on {listen}");
        loop {
            let (stream, peer) = listener.accept().await?;
            serve_conn(app.clone(), peer.ip().to_string(), stream);
        }
    }
}

/// What used to be `_tasks.php`, run every 15 minutes by cron: drop the
/// password reset codes that have expired.
async fn tasks(app: &App) -> Result<(), mysql_async::Error> {
    let mut conn = app.pool.get_conn().await?;
    conn.exec_drop("DELETE FROM email_codes WHERE expiry < ?", (api::now(),))
        .await?;
    eprintln!("removed {} expired email_codes", conn.affected_rows());
    Ok(())
}

#[tokio::main]
async fn main() -> std::process::ExitCode {
    let app = match App::from_env() {
        Ok(app) => Arc::new(app),
        Err(e) => {
            eprintln!("configuration: {e}");
            return std::process::ExitCode::FAILURE;
        }
    };
    let result = match std::env::args().nth(1).as_deref() {
        None | Some("serve") => serve(app).await.map_err(|e| e.to_string()),
        Some("tasks") => tasks(&app).await.map_err(|e| e.to_string()),
        Some(other) => Err(format!("unknown command {other:?}")),
    };
    match result {
        Ok(()) => std::process::ExitCode::SUCCESS,
        Err(e) => {
            eprintln!("{e}");
            std::process::ExitCode::FAILURE
        }
    }
}

#[cfg(test)]
mod tests {
    use super::route;

    #[test]
    fn routes_the_php_paths() {
        assert_eq!(route("/api/chat.php"), Some((true, "chat")));
        assert_eq!(route("/create_account.php"), Some((false, "create_account")));
        assert_eq!(route("/"), Some((false, "index")));
        assert_eq!(route("/api/Chat.php"), None);
        assert_eq!(route("/game/index.html"), None);
    }
}
