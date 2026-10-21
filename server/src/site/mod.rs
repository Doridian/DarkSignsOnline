//! The website: the news page, the terms, and the account pages that sign
//! players up, verify their address and reset their password.
//!
//! The HTML around each page is the PHP's own, taken out of the old scripts
//! verbatim into `templates/`, one file per run of literal HTML.

use rand::RngExt as _;

use crate::api::{make_keycode, make_new_domain, now};
use crate::ctx::{Ctx, Res, s};
use crate::php::{self, Zv};

macro_rules! template {
    ($name:literal) => {
        include_bytes!(concat!("templates/", $name, ".html"))
    };
}

/// `htmlspecialchars()` with `ENT_QUOTES`.
pub fn escape(s: &[u8]) -> Vec<u8> {
    let mut out = Vec::with_capacity(s.len());
    for &c in s {
        match c {
            b'&' => out.extend_from_slice(b"&amp;"),
            b'<' => out.extend_from_slice(b"&lt;"),
            b'>' => out.extend_from_slice(b"&gt;"),
            b'"' => out.extend_from_slice(b"&quot;"),
            b'\'' => out.extend_from_slice(b"&#039;"),
            c => out.push(c),
        }
    }
    out
}

fn top(ctx: &mut Ctx, title: Option<&str>) {
    ctx.echo(template!("top.0"));
    if let Some(title) = title {
        ctx.echo(" - ");
        ctx.echo(escape(title.as_bytes()));
    }
    ctx.echo(template!("top.1"));
}

/// The footer, which names the commit the site was built from.
fn bottom(ctx: &mut Ctx) {
    let rev = escape(php::trim(ctx.app.gitrev.as_bytes()));
    ctx.echo(template!("bottom.0"));
    ctx.echo(b"<a href=\"https://github.com/Doridian/DarkSignsOnline/tree/");
    ctx.echo(&rev);
    ctx.echo(b"/server\">");
    ctx.echo(&rev);
    ctx.echo(b"</a>");
    ctx.echo(template!("bottom.1"));
}

/// `die_frontend_msg()`: one message in big orange letters, then the footer.
/// `msg` is HTML.
fn die_msg(ctx: &mut Ctx, msg: impl AsRef<[u8]>, submsg: &str) -> Res {
    ctx.echo(b"<center><br><br><font size=\"4\" color=\"orange\" face=\"arial\"><b>");
    ctx.echo(msg);
    ctx.echo(b"</b>");
    if !submsg.is_empty() {
        ctx.echo(b"<br>");
        ctx.echo(submsg);
    }
    ctx.echo(b"</font></center>");
    bottom(ctx);
    Err(crate::ctx::Halt::Exit)
}

/// Run the page at `name`, or `None` if there is no such page.
pub async fn dispatch(name: &str, ctx: &mut Ctx) -> Option<Res> {
    Some(match name {
        "index" => {
            top(ctx, None);
            ctx.echo(template!("index.0"));
            bottom(ctx);
            Ok(())
        }
        "termsofuse" => {
            top(ctx, Some("Terms of Use"));
            ctx.echo(template!("termsofuse.0"));
            bottom(ctx);
            Ok(())
        }
        "verify" => verify(ctx).await,
        "create_account" => create_account(ctx).await,
        "forgot_password" => forgot_password(ctx).await,
        "forgot_password2" => forgot_password2(ctx).await,
        _ => return None,
    })
}

async fn verify(ctx: &mut Ctx) -> Res {
    top(ctx, Some("E-Mail Verification"));
    let code = ctx.req.request("code");
    if code.is_empty() {
        return die_msg(ctx, "Error, no verification code provided.", "");
    }
    let (affected, _) = ctx
        .exec(
            "UPDATE users SET active = 1, emailverifycode = \"\" WHERE emailverifycode = ? AND active = 0",
            vec![s(&code)],
        )
        .await?;
    if affected == 0 {
        return die_msg(ctx, "Error, invalid verification code.", "");
    }
    die_msg(ctx, "E-Mail verification completed", "You can now log in.")
}

/// `password_hash($password, PASSWORD_DEFAULT)` as PHP 8.4 does it: bcrypt,
/// cost 12, in the `$2y$` spelling.
async fn password_hash(password: Vec<u8>) -> Res<String> {
    tokio::task::spawn_blocking(move || {
        let mut salt = [0u8; 16];
        rand::rng().fill(&mut salt);
        bcrypt::hash_with_salt(&password, 12, salt).map(|h| h.format_for_version(bcrypt::Version::TwoY))
    })
    .await
    .map_err(|e| crate::ctx::Halt::Fatal(format!("hashing: {e}")))?
    .map_err(|e| crate::ctx::Halt::Fatal(format!("hashing: {e}")))
}

/// `filter_var($email, FILTER_VALIDATE_EMAIL)`, by the same regular
/// expression on the same engine.
fn valid_email(email: &[u8]) -> bool {
    use std::sync::LazyLock;
    static RE: LazyLock<pcre2::bytes::Regex> = LazyLock::new(|| {
        pcre2::bytes::RegexBuilder::new()
            .caseless(true)
            .build(
                r#"^(?!(?:(?:\x22?\x5C[\x00-\x7E]\x22?)|(?:\x22?[^\x5C\x22]\x22?)){255,})(?!(?:(?:\x22?\x5C[\x00-\x7E]\x22?)|(?:\x22?[^\x5C\x22]\x22?)){65,}@)(?:(?:[\x21\x23-\x27\x2A\x2B\x2D\x2F-\x39\x3D\x3F\x5E-\x7E]+)|(?:\x22(?:[\x01-\x08\x0B\x0C\x0E-\x1F\x21\x23-\x5B\x5D-\x7F]|(?:\x5C[\x00-\x7F]))*\x22))(?:\.(?:(?:[\x21\x23-\x27\x2A\x2B\x2D\x2F-\x39\x3D\x3F\x5E-\x7E]+)|(?:\x22(?:[\x01-\x08\x0B\x0C\x0E-\x1F\x21\x23-\x5B\x5D-\x7F]|(?:\x5C[\x00-\x7F]))*\x22)))*@(?:(?:(?!.*[^.]{64,})(?:(?:(?:xn--)?[a-z0-9]+(?:-+[a-z0-9]+)*\.){1,126}){1,}(?:(?:[a-z][a-z0-9]*)|(?:(?:xn--)[a-z0-9]+))(?:-+[a-z0-9]+)*)|(?:\[(?:(?:IPv6:(?:(?:[a-f0-9]{1,4}(?::[a-f0-9]{1,4}){7})|(?:(?!(?:.*[a-f0-9][:\]]){7,})(?:[a-f0-9]{1,4}(?::[a-f0-9]{1,4}){0,5})?::(?:[a-f0-9]{1,4}(?::[a-f0-9]{1,4}){0,5})?)))|(?:(?:IPv6:(?:(?:[a-f0-9]{1,4}(?::[a-f0-9]{1,4}){5}:)|(?:(?!(?:.*[a-f0-9]:){5,})(?:[a-f0-9]{1,4}(?::[a-f0-9]{1,4}){0,3})?::(?:[a-f0-9]{1,4}(?::[a-f0-9]{1,4}){0,3}:)?)))?(?:(?:25[0-5])|(?:2[0-4][0-9])|(?:1[0-9]{2})|(?:[1-9]?[0-9]))(?:\.(?:(?:25[0-5])|(?:2[0-4][0-9])|(?:1[0-9]{2})|(?:[1-9]?[0-9]))){3}))\]))$"#,
            )
            .expect("PHP's email regex compiles")
    });
    // The address is trimmed before it gets here, so the `D` flag PHP
    // compiles this with (no match before a final newline) has nothing to
    // act on.
    email.len() <= 320 && RE.is_match(email).unwrap_or(false)
}

async fn create_account(ctx: &mut Ctx) -> Res {
    top(ctx, Some("Create a new account"));

    if !ctx.req.post("username").is_empty() {
        if !ctx.req.post("agreetos").is_str(b"yes") || !ctx.req.post("agecheck").is_str(b"yes") {
            return die_msg(
                ctx,
                "You must agree to the terms of use and confirm you are at least 13 years old.",
                "",
            );
        }
        let username: Vec<u8> = php::strtolower(php::trim(&ctx.req.post("username").to_bytes()))
            .into_iter()
            .map(|c| if c == b' ' { b'-' } else { c })
            .collect();
        let password = ctx.req.post("password").to_bytes();
        let email = php::trim(&ctx.req.post("email").to_bytes()).to_vec();

        if username.len() < 3 {
            return die_msg(ctx, "Your username must be at least 3 characters long.", "");
        }
        if username.len() > 20 {
            return die_msg(ctx, "Your username must be at most 20 characters long.", "");
        }
        if password.len() < 6 {
            return die_msg(ctx, "Your password must be at least 6 characters long.", "");
        }
        if Zv::Str(email.clone()).is_empty() || !valid_email(&email) {
            return die_msg(ctx, "You must enter a valid email address.", "");
        }
        if !username.iter().all(|c| c.is_ascii_alphanumeric() || *c == b'-') {
            return die_msg(ctx, "Error, please don't use invalid characters in your username.", "");
        }

        let pwhash = password_hash(password).await?;

        ctx.begin().await?;
        if ctx
            .query_one("SELECT id from users where email=?", vec![email.clone().into()])
            .await?
            .is_some()
        {
            ctx.rollback().await?;
            let msg = [
                &b"The email address <b>"[..],
                &escape(&email),
                b"</b> already exists in the database. Please try again.",
            ]
            .concat();
            return die_msg(ctx, msg, "");
        }
        if ctx
            .query_one("SELECT id from users where username=?", vec![username.clone().into()])
            .await?
            .is_some()
        {
            ctx.rollback().await?;
            let msg = [
                &b"The username <b>"[..],
                &escape(&username),
                b"</b> already exists in the database. Please try again.",
            ]
            .concat();
            return die_msg(ctx, msg, "");
        }

        let ip = ctx.req.remote_addr.clone();
        let vercode = make_keycode();
        let time = now();
        let (_, userid) = ctx
            .exec(
                "INSERT INTO users (username, password, email, createtime, ip, lastseen, emailverifycode, active, cash) VALUES (?,?,?,?,?,?,?,0,200)",
                vec![
                    username.clone().into(),
                    pwhash.into(),
                    email.clone().into(),
                    time.into(),
                    ip.into(),
                    time.into(),
                    vercode.clone().into(),
                ],
            )
            .await?;
        let usr = [&username[..], b".usr"].concat();
        make_new_domain(ctx, "DOMAIN", &Zv::Null, userid as i64, &usr, 0).await?;
        ctx.commit().await?;

        let name = String::from_utf8_lossy(&username).into_owned();
        crate::mail::send(
            &ctx.app,
            &email,
            &name,
            &format!("{name}, verify your Dark Signs Online Account"),
            &format!(
                "Hi {name},\n\nThank you for creating an account on Dark Signs Online!\n\nClick the link below to activate your account.\n\nhttps://darksignsonline.com/verify.php?code={vercode}\n\nThank you,\n\nThe Dark Signs Online Team\nhttps://darksignsonline.com/"
            ),
        )
        .await?;

        return die_msg(
            ctx,
            "Your account has been created!",
            "Check your E-Mail for more information.",
        );
    }

    ctx.echo(template!("create_account.0"));
    bottom(ctx);
    Ok(())
}

async fn forgot_password(ctx: &mut Ctx) -> Res {
    top(ctx, Some("Forgot password"));

    if !ctx.req.post("email").is_empty() && !ctx.req.post("username").is_empty() {
        let username = php::strtolower(php::trim(&ctx.req.post("username").to_bytes()));
        let email = php::trim(&ctx.req.post("email").to_bytes()).to_vec();
        let user = ctx
            .query_one(
                "SELECT id, username FROM users WHERE email=? AND username=?",
                vec![email.clone().into(), username.into()],
            )
            .await?;
        let Some(user) = user else {
            return die_msg(ctx, "Error, no user with this E-Mail and username not found.", "");
        };

        let vercode = make_keycode();
        ctx.exec(
            "INSERT INTO email_codes (user, code, expiry, action) VALUES (?, ?, ?, \"forgot_password\")",
            vec![
                user.get("id").to_int().into(),
                vercode.clone().into(),
                (now() + 3600).into(),
            ],
        )
        .await?;

        // The name as the database has it, not as it was typed.
        let name = String::from_utf8_lossy(&user.get("username").to_bytes()).into_owned();
        crate::mail::send(
            &ctx.app,
            &email,
            &name,
            &format!("Dark Signs Online - Password reset for {name}"),
            &format!(
                "Hi {name},\n\nYou (or someone who knows your E-Mail) has reuqested a password reset for your account, {name}\n\nClick the link below to change your password, or ignore this E-Mail if you didn't initiate this change.\n\nhttps://darksignsonline.com/forgot_password2.php?code={vercode}\n\nThank you,\n\nThe Dark Signs Online Team\nhttps://darksignsonline.com/"
            ),
        )
        .await?;

        return die_msg(
            ctx,
            "E-Mail has been sent!",
            "Check your E-Mail for the password reset link.",
        );
    }

    ctx.echo(template!("forgot_password.0"));
    bottom(ctx);
    Ok(())
}

async fn forgot_password2(ctx: &mut Ctx) -> Res {
    top(ctx, Some("Forgot password"));

    let code = ctx.req.request("code");
    if code.is_empty() {
        return die_msg(ctx, "Error, no code provided.", "");
    }
    let row = ctx
        .query_one(
            "SELECT user FROM email_codes WHERE code = ? AND expiry >= ? AND action=\"forgot_password\"",
            vec![s(&code), now().into()],
        )
        .await?;
    let Some(row) = row else {
        return die_msg(ctx, "Error, invalid or expired code.", "");
    };
    let user_id = row.get("user").to_int();
    let Some(user) = ctx
        .query_one("SELECT username, email FROM users WHERE id = ?", vec![user_id.into()])
        .await?
    else {
        return die_msg(ctx, "Internal error, invalid user.", "");
    };

    let password = ctx.req.post("password");
    if !password.is_empty() {
        let password = password.to_bytes();
        if password.len() < 6 {
            return die_msg(ctx, "Your password must be at least 6 characters long.", "");
        }
        ctx.exec("DELETE FROM email_codes WHERE code=?", vec![s(&code)]).await?;
        let pwhash = password_hash(password).await?;
        ctx.exec(
            "UPDATE users SET password=? WHERE id=?",
            vec![pwhash.into(), user_id.into()],
        )
        .await?;
        return die_msg(ctx, "Password has been changed!", "");
    }

    ctx.echo(template!("forgot_password2.0"));
    ctx.echo(escape(&user.get("username").to_bytes()));
    ctx.echo(template!("forgot_password2.1"));
    ctx.echo(escape(&user.get("email").to_bytes()));
    ctx.echo(template!("forgot_password2.2"));
    ctx.echo(escape(&code.to_bytes()));
    ctx.echo(template!("forgot_password2.3"));
    bottom(ctx);
    Ok(())
}
