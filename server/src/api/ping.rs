//! `ping.php`: does a domain exist, and is anything listening on a port.

use super::{authenticate, get_domain_info};
use crate::ctx::{Ctx, Res};

pub async fn run(ctx: &mut Ctx) -> Res {
    authenticate(ctx).await?;

    let domain = ctx.req.request("domain").to_bytes();
    let port = ctx.req.request("port").to_int();
    let Some(info) = get_domain_info(ctx, &domain).await? else {
        return ctx.die("0");
    };
    if port == 0 {
        return ctx.die("1");
    }
    let rows = ctx
        .query(
            "SELECT domain FROM domain_scripts WHERE domain=? AND port=? AND ver=?;",
            vec![info.get("id").to_int().into(), port.into(), ctx.ver.into()],
        )
        .await?;
    ctx.die(if rows.is_empty() { "0" } else { "1" })
}
