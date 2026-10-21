//! `domain_unregister.php`: give up a domain you own.

use super::{authenticate, get_domain_info};
use crate::ctx::{Ctx, Res};
use crate::php;

pub async fn run(ctx: &mut Ctx) -> Res {
    authenticate(ctx).await?;
    ctx.print_returnwith("2000", 1);

    let d = php::strtolower(php::trim(&ctx.req.post("d").to_bytes()));
    let Some(info) = get_domain_info(ctx, &d).await? else {
        return ctx.die_error("Domain not found", 404);
    };
    if info.get("owner") != ctx.user_id() {
        return ctx.die_error("Domain not owned by user", 403);
    }
    ctx.exec("DELETE FROM domains WHERE id=?", vec![info.get("id").to_int().into()])
        .await?;
    ctx.die("Domain unregistered")
}
