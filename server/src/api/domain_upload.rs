//! `domain_upload.php`: put a script on one of your ports.

use super::{authenticate, get_domain_info, now};
use crate::ctx::{Ctx, Res};
use crate::php;

pub async fn run(ctx: &mut Ctx) -> Res {
    authenticate(ctx).await?;
    if ctx.ver < 2 {
        ctx.echo("2003");
    }

    let port = ctx.req.post("port").to_int();
    if !(1..=65535).contains(&port) {
        return ctx.die_error("Port number must be between 1 and 65535.", 400);
    }
    let d = ctx.req.post("d").to_bytes();
    let Some(info) = get_domain_info(ctx, &d).await? else {
        return ctx.die_error("Domain does not exist.", 404);
    };
    if ctx.user_id() != info.get("owner") {
        return ctx.die_error("Restricted access.", 403);
    }

    let code = php::line_endings_to_dos(&php::dso_b64_decode(&ctx.req.post("filedata").to_bytes()));
    let ip = ctx.req.remote_addr.clone();
    let time = now();
    ctx.exec(
        "INSERT INTO domain_scripts (domain, port, code, ip, time, ver) VALUES (?, ?, ?, ?, ?, ?) ON DUPLICATE KEY UPDATE code=?, ip=?, time=?;",
        vec![
            info.get("id").to_int().into(),
            port.into(),
            code.clone().into(),
            ip.clone().into(),
            time.into(),
            ctx.ver.into(),
            code.into(),
            ip.into(),
            time.into(),
        ],
    )
    .await?;
    ctx.die("success")
}
