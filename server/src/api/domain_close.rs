//! `domain_close.php`: take down the script on one of your ports.

use super::{authenticate, get_domain_info, upper};
use crate::ctx::{Ctx, Res};
use crate::php;

pub async fn run(ctx: &mut Ctx) -> Res {
    authenticate(ctx).await?;
    ctx.print_returnwith("2000", 1);

    let d = php::trim(&ctx.req.request("d").to_bytes()).to_vec();
    let port = ctx.req.request("port").to_int();
    let Some(info) = get_domain_info(ctx, &d).await? else {
        return ctx.die_error("Domain does not exist.", 404);
    };
    if ctx.user_id() != info.get("owner") {
        return ctx.die_error("Restricted access.", 403);
    }

    let (affected, _) = ctx
        .exec(
            "DELETE FROM domain_scripts WHERE domain=? AND port=? AND ver=?;",
            vec![info.get("id").to_int().into(), port.into(), ctx.ver.into()],
        )
        .await?;
    if affected > 0 {
        let msg = [
            &b"Port successfully closed.: "[..],
            &upper(&d),
            format!(":{port}").as_bytes(),
        ]
        .concat();
        ctx.die(msg)
    } else {
        ctx.die("No script is active on this port.")
    }
}
