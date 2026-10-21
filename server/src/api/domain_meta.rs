//! `domain_meta.php`: a domain's IP, or the name an IP goes by.

use super::{authenticate, get_domain_info, get_ip_domain};
use crate::ctx::{Ctx, Res};

pub async fn run(ctx: &mut Ctx) -> Res {
    authenticate(ctx).await?;

    let getip = ctx.req.request("getip");
    if !getip.is_empty() {
        let Some(info) = get_domain_info(ctx, &getip.to_bytes()).await? else {
            return ctx.die_error("not found", 404);
        };
        return ctx.die(info.get("ip").to_bytes());
    }

    let getdomain = ctx.req.request("getdomain");
    if !getdomain.is_empty() {
        let dom = get_ip_domain(ctx, &getdomain.to_bytes()).await?;
        if crate::php::Zv::Str(dom.clone()).is_empty() {
            return ctx.die_error("not found", 404);
        }
        return ctx.die(dom);
    }
    Ok(())
}
