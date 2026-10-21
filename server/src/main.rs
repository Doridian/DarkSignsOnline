//! The Dark Signs Online game server: the API the clients talk to and the
//! website's account pages, answering at the `.php` paths the PHP server it
//! replaces answered at, so neither the clients nor any link has to change,
//! and the website's static files and the browser client beside them.
//!
//! It is the whole site. Anything in front of it -- nginx for TLS, say -- is
//! a reverse proxy and nothing more: see `DSO_TRUSTED_PROXIES`.

mod api;
mod ctx;
mod mail;
mod php;
mod request;
mod site;
mod www;

use std::convert::Infallible;
use std::net::IpAddr;
use std::path::PathBuf;
use std::sync::Arc;
use std::time::Duration;

use bytes::Bytes;
use http_body_util::{BodyExt, Full, Limited};
use hyper::body::Incoming;
use hyper::header::{HeaderMap, HeaderValue};
use hyper::server::conn::http1;
use hyper::service::service_fn;
use hyper::{Request as HttpRequest, Response, StatusCode};
use hyper_util::rt::{TokioIo, TokioTimer};
use mysql_async::prelude::Queryable;
use rsa::RsaPrivateKey;
use rsa::pkcs1::DecodeRsaPrivateKey;
use rsa::pkcs8::DecodePrivateKey;
use tokio::net::{TcpListener, UnixListener};
use tokio::signal::unix::{SignalKind, signal};

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
    /// The static files, if there are any to serve.
    pub www: Option<PathBuf>,
    /// Who may say, in `X-Real-IP`, who is on the other end.
    pub trusted_proxies: Vec<Cidr>,
}

/// An address and how many of its leading bits a peer has to share with it.
#[derive(Debug, PartialEq)]
pub struct Cidr(IpAddr, u8);

impl Cidr {
    fn parse(s: &str) -> Result<Cidr, String> {
        let (addr, bits) = match s.split_once('/') {
            Some((a, b)) => (a, Some(b)),
            None => (s, None),
        };
        let addr: IpAddr = addr.parse().map_err(|e| format!("{s}: {e}"))?;
        let max = if addr.is_ipv4() { 32 } else { 128 };
        let bits = match bits {
            Some(b) => b
                .parse()
                .ok()
                .filter(|&b| b <= max)
                .ok_or_else(|| format!("{s}: bad prefix length"))?,
            None => max,
        };
        Ok(Cidr(addr, bits))
    }

    fn contains(&self, ip: IpAddr) -> bool {
        let mask = |bits: u8, width: u8| if bits == 0 { 0 } else { u128::MAX << (width - bits) };
        match (self.0, ip.to_canonical()) {
            (IpAddr::V4(net), IpAddr::V4(ip)) => {
                let m = mask(self.1, 32) as u32;
                u32::from(net) & m == u32::from(ip) & m
            }
            (IpAddr::V6(net), IpAddr::V6(ip)) => {
                let m = mask(self.1, 128);
                u128::from(net) & m == u128::from(ip) & m
            }
            _ => false,
        }
    }
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

        let www = env("DSO_WWW");
        let trusted = std::env::var("DSO_TRUSTED_PROXIES").unwrap_or_else(|_| "127.0.0.0/8 ::1".into());
        let trusted_proxies = trusted
            .split([' ', ','])
            .filter(|s| !s.is_empty())
            .map(Cidr::parse)
            .collect::<Result<_, _>>()
            .map_err(|e| format!("DSO_TRUSTED_PROXIES: {e}"))?;

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
            www: (!www.is_empty()).then(|| www.into()),
            trusted_proxies,
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

/// Which script a path names: `("api", "chat")` for `/api/chat.php`, the
/// paths nginx's `^/(api/)?[a-z0-9_]+\.php$` used to send to PHP.
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

fn not_found() -> Response<Full<Bytes>> {
    // What php-fpm said for a script that was not there.
    let mut resp = Response::new(Full::new(Bytes::from_static(b"File not found.\n")));
    *resp.status_mut() = StatusCode::NOT_FOUND;
    resp.headers_mut()
        .insert("content-type", HeaderValue::from_static(TEXT_HTML));
    resp
}

/// The two headers every response gets, whatever answered it: nothing here
/// is meant to be sniffed into another type or framed by another site.
fn with_site_headers(mut resp: Response<Full<Bytes>>) -> Response<Full<Bytes>> {
    let mut headers = HeaderMap::with_capacity(resp.headers().len() + 2);
    headers.insert("x-content-type-options", HeaderValue::from_static("nosniff"));
    headers.insert("x-frame-options", HeaderValue::from_static("DENY"));
    // Ahead of the rest, as nginx's `add_header` put them in front of what
    // the PHP sent.
    for (name, value) in std::mem::take(resp.headers_mut()) {
        if let Some(name) = name {
            headers.append(name, value);
        }
    }
    *resp.headers_mut() = headers;
    resp
}

/// Who is on the other end: a proxy we trust says, in `X-Real-IP`;
/// otherwise the socket does. A unix socket is only reachable from this
/// machine, so whatever is on it is trusted the same way.
fn remote_addr(app: &App, peer: Option<IpAddr>, headers: &HeaderMap) -> String {
    let trusted = peer.is_none_or(|ip| app.trusted_proxies.iter().any(|c| c.contains(ip)));
    if trusted && let Some(ip) = header_bytes(headers, "x-real-ip") {
        return String::from_utf8_lossy(&ip).into_owned();
    }
    peer.map_or_else(String::new, |ip| ip.to_canonical().to_string())
}

async fn handle(
    app: Arc<App>,
    peer: Option<IpAddr>,
    req: HttpRequest<Incoming>,
) -> Result<Response<Full<Bytes>>, Infallible> {
    Ok(with_site_headers(respond(app, peer, req).await))
}

async fn respond(app: Arc<App>, peer: Option<IpAddr>, req: HttpRequest<Incoming>) -> Response<Full<Bytes>> {
    let path = req.uri().path().to_string();
    if path == "/readyz" {
        let mut resp = Response::new(Full::new(Bytes::from_static(b"OK")));
        resp.headers_mut()
            .insert("content-type", HeaderValue::from_static("text/plain"));
        return resp;
    }
    let Some((api, name)) = route(&path).map(|(api, name)| (api, name.to_string())) else {
        let Some(root) = &app.www else {
            return not_found();
        };
        return www::serve(root, req.method(), &path, req.uri().query())
            .await
            .unwrap_or_else(not_found);
    };

    let (parts, body) = req.into_parts();
    let body = Limited::new(body, POST_MAX_SIZE)
        .collect()
        .await
        .ok()
        .map(|b| b.to_bytes());

    let header = |name| header_bytes(&parts.headers, name);
    let mut request = Request::new(
        parts.method.as_str().to_string(),
        path,
        parts.uri.query(),
        header("content-type").as_deref(),
        body.as_deref(),
    );
    request.protocol_version = header("dso-protocol-version");
    request.authorization = header("authorization");
    request.remote_addr = remote_addr(&app, peer, &parts.headers);

    let mut ctx = Ctx::new(app, request);
    let result = if api {
        api::dispatch(&name, &mut ctx).await
    } else {
        site::dispatch(&name, &mut ctx).await
    };
    ctx.finish().await;

    let Some(result) = result else {
        return not_found();
    };
    if let Err(Halt::Fatal(e)) = result {
        // An uncaught exception: PHP made it a 500 unless a status had
        // already been chosen, and sent whatever had been written.
        eprintln!("{} {}: {e}", ctx.req.method, ctx.req.path);
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
    resp
}

fn serve_conn<S>(app: Arc<App>, peer: Option<IpAddr>, stream: S)
where
    S: tokio::io::AsyncRead + tokio::io::AsyncWrite + Unpin + Send + 'static,
{
    tokio::spawn(async move {
        let service = service_fn(move |req| handle(app.clone(), peer, req));
        // Nothing need be in front of this, so it does not wait forever on a
        // client that never finishes saying what it wants.
        if let Err(e) = http1::Builder::new()
            .timer(TokioTimer::new())
            .header_read_timeout(Duration::from_secs(30))
            .serve_connection(TokioIo::new(stream), service)
            .await
        {
            eprintln!("connection: {e}");
        }
    });
}

/// `DSO_LISTEN` is `host:port` (default `0.0.0.0:8080`) or
/// `unix:/path/to.sock`.
async fn serve(app: Arc<App>) -> std::io::Result<()> {
    let listen = std::env::var("DSO_LISTEN").unwrap_or_else(|_| "0.0.0.0:8080".into());
    match &app.www {
        Some(root) => eprintln!("serving {}", root.display()),
        None => eprintln!("DSO_WWW is not set: serving the API and pages only, no static files"),
    }
    tokio::spawn(tasks(app.clone()));

    let mut term = signal(SignalKind::terminate())?;
    let mut int = signal(SignalKind::interrupt())?;
    let stop = async move {
        tokio::select! {
            _ = term.recv() => {}
            _ = int.recv() => {}
        }
    };
    tokio::pin!(stop);

    if let Some(path) = listen.strip_prefix("unix:") {
        let _ = std::fs::remove_file(path);
        let listener = UnixListener::bind(path)?;
        eprintln!("listening on {listen}");
        loop {
            tokio::select! {
                accepted = listener.accept() => serve_conn(app.clone(), None, accepted?.0),
                () = &mut stop => return Ok(()),
            }
        }
    } else {
        let listener = TcpListener::bind(&listen).await?;
        eprintln!("listening on {listen}");
        loop {
            tokio::select! {
                accepted = listener.accept() => {
                    let (stream, peer) = accepted?;
                    serve_conn(app.clone(), Some(peer.ip()), stream);
                }
                () = &mut stop => return Ok(()),
            }
        }
    }
}

/// What used to be `_tasks.php`, which cron ran every 15 minutes: drop the
/// password reset codes that have expired. The first run is a period after
/// starting, as it was under cron.
async fn tasks(app: Arc<App>) {
    const EVERY: Duration = Duration::from_secs(15 * 60);
    let mut every = tokio::time::interval_at(tokio::time::Instant::now() + EVERY, EVERY);
    every.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Delay);
    loop {
        every.tick().await;
        let result = async {
            let mut conn = app.pool.get_conn().await?;
            conn.exec_drop("DELETE FROM email_codes WHERE expiry < ?", (api::now(),))
                .await?;
            Ok::<_, mysql_async::Error>(conn.affected_rows())
        };
        match result.await {
            Ok(0) => {}
            Ok(n) => eprintln!("removed {n} expired email_codes"),
            Err(e) => eprintln!("tasks: {e}"),
        }
    }
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
    match serve(app).await {
        Ok(()) => std::process::ExitCode::SUCCESS,
        Err(e) => {
            eprintln!("{e}");
            std::process::ExitCode::FAILURE
        }
    }
}

#[cfg(test)]
mod tests {
    use super::{Cidr, route};

    #[test]
    fn routes_the_php_paths() {
        assert_eq!(route("/api/chat.php"), Some((true, "chat")));
        assert_eq!(route("/create_account.php"), Some((false, "create_account")));
        assert_eq!(route("/"), Some((false, "index")));
        assert_eq!(route("/api/Chat.php"), None);
        assert_eq!(route("/game/index.html"), None);
    }

    #[test]
    fn trusted_proxies() {
        let net = |s| Cidr::parse(s).unwrap();
        let ip = |s: &str| s.parse().unwrap();
        assert!(net("127.0.0.0/8").contains(ip("127.1.2.3")));
        assert!(net("127.0.0.0/8").contains(ip("::ffff:127.0.0.1")));
        assert!(!net("127.0.0.0/8").contains(ip("128.0.0.1")));
        assert!(net("::1").contains(ip("::1")));
        assert!(!net("::1").contains(ip("::2")));
        assert!(net("10.1.2.3").contains(ip("10.1.2.3")));
        assert!(!net("10.1.2.3").contains(ip("10.1.2.4")));
        assert!(net("0.0.0.0/0").contains(ip("8.8.8.8")));
        assert!(net("fd00::/8").contains(ip("fd12::1")));
        assert!(Cidr::parse("10.0.0.0/33").is_err());
        assert!(Cidr::parse("nope").is_err());
    }
}
