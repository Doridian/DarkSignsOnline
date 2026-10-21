//! `domain_download.php`: the source of the script on a port, unless it was
//! uploaded compiled.

use super::{authenticate, get_domain_info, upper};
use crate::ctx::{Ctx, Res};
use crate::php;

const DSO_SCRIPT_CRYPTO_HEADER: &[u8] = b"Option DSciptCompiled\r\n";

pub async fn run(ctx: &mut Ctx) -> Res {
    authenticate(ctx).await?;

    let d = php::trim(&ctx.req.request("d").to_bytes()).to_vec();
    let port = ctx.req.request("port").to_int();
    let filename = ctx.req.request("filename").to_bytes();
    ctx.print_returnwith("2000", 1);

    let Some(info) = get_domain_info(ctx, &d).await? else {
        return ctx.die_error("Domain does not exist.", 404);
    };
    let row = ctx
        .query_one(
            "SELECT code FROM domain_scripts WHERE domain=? AND port=? AND ver=?",
            vec![info.get("id").to_int().into(), port.into(), ctx.ver.into()],
        )
        .await?;
    let where_ = [&upper(&d)[..], format!(":{port}").as_bytes()].concat();
    let Some(row) = row else {
        return ctx.die_error([&b"No Script Found: "[..], &where_].concat(), 404);
    };
    let script = row.get("code").to_bytes();
    let head = &script[..script.len().min(DSO_SCRIPT_CRYPTO_HEADER.len())];
    if head.eq_ignore_ascii_case(DSO_SCRIPT_CRYPTO_HEADER) {
        return ctx.die_error([&b"Cannot Download Compiled Script: "[..], &where_].concat(), 403);
    }
    ctx.die([&filename[..], b":", &script].concat())
}
