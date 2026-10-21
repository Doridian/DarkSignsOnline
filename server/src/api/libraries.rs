//! `libraries.php`: shared script libraries, addressed by the SHA-256 of
//! their contents.

use super::{authenticate, now};
use crate::ctx::{Ctx, Res, s};
use crate::php::{self, Zv};

pub async fn run(ctx: &mut Ctx) -> Res {
    authenticate(ctx).await?;

    let getlib = Zv::str(php::trim(&ctx.req.request("get").to_bytes()));
    if !getlib.is_empty() {
        let Some(lib) = ctx
            .query_one("SELECT data FROM libraries WHERE hash = ?", vec![s(&getlib)])
            .await?
        else {
            return ctx.die_error("not found", 404);
        };
        return ctx.die(lib.get("data").to_bytes());
    }

    let putlib = Zv::str(php::trim(&ctx.req.request("put").to_bytes()));
    if !putlib.is_empty() {
        let data = ctx.req.request("data");
        let myhash = php::sha256_hex(&data.to_bytes());
        let putlib = putlib.to_bytes();
        if myhash.as_bytes() != putlib {
            let mut msg = b"hash mismatch (got ".to_vec();
            msg.extend_from_slice(&putlib);
            msg.extend_from_slice(format!("; expected {myhash})").as_bytes());
            return ctx.die_error(msg, 409);
        }
        ctx.exec(
            "INSERT INTO libraries (hash, data, owner, time) VALUES (?, ?, ?, ?);",
            vec![putlib.into(), s(&data), ctx.user_id().to_int().into(), now().into()],
        )
        .await?;
        return ctx.die("OK");
    }

    ctx.die_error("bad request", 400)
}
