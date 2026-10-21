//! The game's API, one module per endpoint, each named for the PHP script it
//! replaces and answering at the same `/api/<name>.php` path.
//!
//! This module is what those scripts shared: `function_cors.php` (the
//! headers), `function.php` (the account) and `function_base.php` (the
//! helpers).

mod auth;
mod chat;
mod domain_close;
mod domain_connect;
mod domain_download;
mod domain_filesystem;
mod domain_meta;
mod domain_register;
mod domain_token;
mod domain_unregister;
mod domain_upload;
mod dsmail;
mod file_database;
mod get_user_stats;
mod libraries;
mod lookup;
mod my_domains;
mod ping;
mod textspace;
mod transfer;

use rand::RngExt;

use crate::ctx::{Ctx, Halt, Rec, Res, TEXT_PLAIN, i, s};
use crate::php::{self, Zv};

pub const BANK_USER_ID: i64 = 42;

/// Run the endpoint at `name`, or `None` if there is no such endpoint.
pub async fn dispatch(name: &str, ctx: &mut Ctx) -> Option<Res> {
    Some(match name {
        "auth" => auth::run(ctx).await,
        "chat" => chat::run(ctx).await,
        "domain_close" => domain_close::run(ctx).await,
        "domain_connect" => domain_connect::run(ctx).await,
        "domain_download" => domain_download::run(ctx).await,
        "domain_filesystem" => domain_filesystem::run(ctx).await,
        "domain_meta" => domain_meta::run(ctx).await,
        "domain_register" => domain_register::run(ctx).await,
        "domain_token" => domain_token::run(ctx).await,
        "domain_token_public" => domain_token::run_public(ctx),
        "domain_unregister" => domain_unregister::run(ctx).await,
        "domain_upload" => domain_upload::run(ctx).await,
        "dsmail" => dsmail::run(ctx).await,
        "file_database" => file_database::run(ctx).await,
        "get_user_stats" => get_user_stats::run(ctx).await,
        "libraries" => libraries::run(ctx).await,
        "lookup" => lookup::run(ctx).await,
        "my_domains" => my_domains::run(ctx).await,
        "ping" => ping::run(ctx).await,
        "textspace" => textspace::run(ctx).await,
        "time" => time(ctx),
        "transfer" => transfer::run(ctx).await,
        "z_online" => z_online(ctx),
        _ => return None,
    })
}

/// The headers every endpoint answers with.
///
/// The allowed headers have to be named rather than wildcarded: `*` does not
/// cover Authorization -- the Fetch standard excludes it -- so a browser
/// client sending Basic auth would fail the preflight. DSO-Protocol-Version
/// is a custom header, so it is not safelisted either. There is deliberately
/// no Access-Control-Allow-Credentials: a browser rejects it alongside a
/// wildcard origin, and the clients send Authorization as an ordinary header.
///
/// A preflight is answered here and goes no further.
pub fn cors(ctx: &mut Ctx) -> Res {
    ctx.content_type = TEXT_PLAIN;
    ctx.header("Access-Control-Allow-Origin", "*");
    ctx.header("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
    ctx.header(
        "Access-Control-Allow-Headers",
        "Authorization, Content-Type, DSO-Protocol-Version",
    );
    ctx.header("Access-Control-Expose-Headers", "*");
    ctx.header("Access-Control-Max-Age", "86400");
    if ctx.req.method.eq_ignore_ascii_case("OPTIONS") {
        return Err(Halt::Exit);
    }
    Ok(())
}

fn login_failure(ctx: &mut Ctx, code: &str) -> Res {
    ctx.header("WWW-Authenticate", "Basic realm=\"DSO API\"");
    ctx.status = 401;
    ctx.die(code)
}

/// `function.php`: the headers, then an account or a 401.
///
/// 1002 is a bad username or password, 1003 an account that exists but has
/// not been activated.
pub async fn authenticate(ctx: &mut Ctx) -> Res {
    cors(ctx)?;
    let Some((user, pass)) = ctx.req.basic_auth() else {
        return login_failure(ctx, "1002");
    };
    if Zv::Str(user.clone()).is_empty() || Zv::Str(pass.clone()).is_empty() {
        return login_failure(ctx, "1002");
    }
    let row = ctx
        .query_one("SELECT * FROM users WHERE username=?", vec![s(&Zv::Str(user))])
        .await?;
    let Some(row) = row else {
        return login_failure(ctx, "1002");
    };
    let hash = row.get("password").to_bytes();
    // bcrypt is deliberately slow; keep it off the threads serving requests.
    let ok = tokio::task::spawn_blocking(move || {
        let hash = String::from_utf8_lossy(&hash).into_owned();
        bcrypt::verify(&pass, &hash).unwrap_or(false)
    })
    .await
    .unwrap_or(false);
    if !ok {
        return login_failure(ctx, "1002");
    }
    if row.get("active").to_int() <= 0 {
        return login_failure(ctx, "1003");
    }
    ctx.user = Some(row);
    Ok(())
}

/// `time.php`: the server's clock, and the browser client's ping. No
/// account and no database, which is what makes it cheap enough to ask
/// every few seconds.
fn time(ctx: &mut Ctx) -> Res {
    cors(ctx)?;
    let now = now().to_string();
    ctx.die(now)
}

/// `z_online.php`: the legacy client's update check. The browser client is
/// served from this site, so nothing is ever out of date.
fn z_online(ctx: &mut Ctx) -> Res {
    cors(ctx)?;
    ctx.die("0000OK")
}

pub fn now() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map_or(0, |d| d.as_secs() as i64)
}

pub fn make_keycode() -> String {
    const CHARS: &[u8] = b"0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ";
    let mut rng = rand::rng();
    (0..16)
        .map(|_| CHARS[rng.random_range(0..CHARS.len())] as char)
        .collect()
}

/// `make_new_domain()`: a domain row with a fresh keycode, and a random IP
/// nobody holds unless a fixed one was paid for. Returns the new id.
pub async fn make_new_domain(
    ctx: &mut Ctx,
    regtype: &str,
    fixedip: &Zv,
    userid: i64,
    host: &[u8],
    parent: i64,
) -> Res<u64> {
    let ip = if !fixedip.is_empty() {
        fixedip.to_bytes()
    } else {
        loop {
            let ip = {
                let mut rng = rand::rng();
                format!(
                    "{}.{}.{}.{}",
                    rng.random_range(1..=254),
                    rng.random_range(1..=254),
                    rng.random_range(1..=254),
                    rng.random_range(1..=254)
                )
            };
            let taken = ctx
                .query_one("SELECT id FROM domains WHERE ip = ?", vec![ip.clone().into()])
                .await?;
            if taken.is_none() {
                break ip.into_bytes();
            }
        }
    };
    let userid = if userid <= 0 { ctx.user_id() } else { Zv::Int(userid) };
    let host = Zv::Str(php::strtolower(php::trim(host)));
    let host = if host.is_empty() { Zv::Null } else { host };
    let parent = if parent <= 0 { Zv::Null } else { Zv::Int(parent) };
    let (_, id) = ctx
        .exec(
            "INSERT INTO domains (owner, ip, host, regtype, time, keycode, parent) VALUES (?, ?, ?, ?, ?, ?, ?)",
            vec![
                i(&userid),
                s(&Zv::Str(ip)),
                s(&host),
                regtype.into(),
                now().into(),
                make_keycode().into(),
                i(&parent),
            ],
        )
        .await?;
    Ok(id)
}

/// `getDomainInfo()`: a domain by IP or host name, if exactly one matches.
pub async fn get_domain_info(ctx: &mut Ctx, domain: &[u8]) -> Res<Option<Rec>> {
    let d = s(&Zv::str(domain));
    let mut rows = ctx
        .query(
            "SELECT id, owner, keycode, ip, host, time FROM domains WHERE ip=? OR host=?",
            vec![d.clone(), d],
        )
        .await?;
    Ok(if rows.len() == 1 { rows.pop() } else { None })
}

pub async fn get_domain_by_id(ctx: &mut Ctx, id: u64) -> Res<Option<Rec>> {
    let mut rows = ctx
        .query(
            "SELECT id, owner, keycode, ip, time FROM domains WHERE id=?",
            vec![id.into()],
        )
        .await?;
    Ok(if rows.len() == 1 { rows.pop() } else { None })
}

/// `getIpDomain()`: the host name a domain goes by, or its IP if it has none.
pub async fn get_ip_domain(ctx: &mut Ctx, ip: &[u8]) -> Res<Vec<u8>> {
    let d = s(&Zv::str(ip));
    let Some(row) = ctx
        .query_one("SELECT ip, host FROM domains WHERE ip=? OR host=?", vec![d.clone(), d])
        .await?
    else {
        return Ok(Vec::new());
    };
    let host = row.get("host");
    Ok(if host.is_empty() {
        row.get("ip").to_bytes()
    } else {
        host.to_bytes()
    })
}

pub async fn get_cash(ctx: &mut Ctx, user_id: i64) -> Res<i64> {
    let mut rows = ctx
        .query("SELECT cash FROM users WHERE id=?", vec![user_id.into()])
        .await?;
    Ok(if rows.len() == 1 {
        rows.pop().map_or(0, |r| r.idx(0).to_int())
    } else {
        0
    })
}

/// `transaction()`: move money between accounts and record the attempt,
/// whether or not it went through. Returns the status it recorded.
pub async fn transaction(ctx: &mut Ctx, from_id: i64, to_id: i64, description: &Zv, amount: i64) -> Res<&'static str> {
    let vercode = make_keycode();
    let status = if from_id > 0 && to_id > 0 && from_id != to_id {
        if amount > 0 {
            if get_cash(ctx, from_id).await? < amount {
                "INSUFFICIENT"
            } else {
                let sql = "UPDATE users SET cash=cash+? WHERE id=?";
                ctx.exec(sql, vec![(-amount).into(), from_id.into()]).await?;
                ctx.exec(sql, vec![amount.into(), to_id.into()]).await?;
                "COMPLETE"
            }
        } else {
            "INVALID-AMOUNT"
        }
    } else if from_id <= 0 {
        "INVALID-SENDER"
    } else if to_id <= 0 {
        "INVALID-RECEIVER"
    } else {
        "INVALID-USER"
    };
    let ip = ctx.req.remote_addr.clone();
    ctx.exec(
        "INSERT INTO transactions (fromid, toid, amount, description, vercode, `time`, status, ip) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
        vec![
            from_id.into(),
            to_id.into(),
            amount.to_string().into(),
            s(description),
            vercode.into(),
            now().to_string().into(),
            status.into(),
            ip.into(),
        ],
    )
    .await?;
    Ok(status)
}

pub async fn id_to_user(ctx: &mut Ctx, id: &Zv) -> Res<Vec<u8>> {
    let row = ctx
        .query_one("SELECT username FROM users WHERE id=?", vec![i(id)])
        .await?;
    Ok(row.map_or(Vec::new(), |r| r.get("username").to_bytes()))
}

/// `userToId()`, -1 for nobody.
pub async fn user_to_id(ctx: &mut Ctx, username: &Zv) -> Res<i64> {
    let row = ctx
        .query_one("SELECT id FROM users WHERE username=?", vec![s(username)])
        .await?;
    Ok(row.map_or(-1, |r| r.get("id").to_int()))
}

/// `validIP()`: four dot-separated parts, each `(int)` between 1 and 255.
pub fn valid_ip(ip: &[u8]) -> bool {
    let parts = php::explode(b".", ip);
    parts.len() == 4 && parts.iter().all(|p| (1..256).contains(&php::intval(p)))
}

/// `strtoupper($d)` for the messages that echo a domain back.
pub fn upper(d: &[u8]) -> Vec<u8> {
    php::strtoupper(d)
}

pub fn cat(parts: &[&[u8]]) -> Vec<u8> {
    parts.concat()
}
