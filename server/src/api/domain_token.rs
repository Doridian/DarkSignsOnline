//! `domain_token.php`: a short-lived RS256 JWT saying which player is
//! connected to which domain, for a domain's scripts to hand to a service
//! outside the game. `domain_token_public.php` is the key to check it with.

use rsa::pkcs1v15::SigningKey;
use rsa::signature::{SignatureEncoding, Signer};

use super::{authenticate, get_domain_info, now};
use crate::ctx::{Ctx, Halt, Res, TEXT_PLAIN};
use crate::php;

const ISSUER: &str = "https://darksignsonline.com/api/domain_token.php";
const LIFETIME: i64 = 5 * 60;

fn b64url(data: &[u8]) -> String {
    String::from_utf8(php::dso_b64_encode(data)).expect("base64 is ASCII")
}

pub async fn run(ctx: &mut Ctx) -> Res {
    authenticate(ctx).await?;

    let d = php::strtolower(&ctx.req.request("d").to_bytes());
    if php::Zv::Str(d.clone()).is_empty() {
        return ctx.die_error("No domain specified", 400);
    }
    let Some(info) = get_domain_info(ctx, &d).await? else {
        return ctx.die_error("not found", 404);
    };
    if ctx.user_id() != info.get("owner") && ctx.req.request("is_local_script").is_str(b"true") {
        return ctx.die_error("not owned", 403);
    }
    let Some(key) = ctx.app.jwt_key.clone() else {
        return Err(Halt::Fatal("JWT_PRIVATE_KEY is not configured".into()));
    };

    let json = |s: &[u8]| php::json_encode_str(s).ok_or_else(|| Halt::Fatal("token claim is not UTF-8".into()));
    let start = now();
    let payload = format!(
        "{{\"iss\":{},\"aud\":{},\"sub\":{},\"name\":{},\"info\":{},\"iat\":{start},\"exp\":{}}}",
        json(ISSUER.as_bytes())?,
        json(&d)?,
        json(&ctx.user_id().to_bytes())?,
        json(&ctx.user_field("username").to_bytes())?,
        json(&ctx.req.request("info").to_bytes())?,
        start + LIFETIME,
    );
    let signing_input = format!(
        "{}.{}",
        b64url(br#"{"typ":"JWT","alg":"RS256"}"#),
        b64url(payload.as_bytes())
    );
    let signature = SigningKey::<rsa::sha2::Sha256>::new(key).sign(signing_input.as_bytes());
    ctx.echo(format!("{signing_input}.{}", b64url(&signature.to_bytes())));
    Ok(())
}

/// The public half, for verifying. No CORS headers, as before.
pub fn run_public(ctx: &mut Ctx) -> Res {
    ctx.content_type = TEXT_PLAIN;
    let key = ctx.app.jwt_public_key.clone();
    ctx.die(key)
}
