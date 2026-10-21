//! `lookup.php`: who registered a domain, and when.

use super::{authenticate, get_domain_info, id_to_user};
use crate::ctx::{Ctx, Res};
use crate::php;

pub async fn run(ctx: &mut Ctx) -> Res {
    authenticate(ctx).await?;
    ctx.print_returnwith("2000", 1);

    let d = php::trim(&ctx.req.request("d").to_bytes()).to_vec();
    let Some(info) = get_domain_info(ctx, &d).await? else {
        return ctx.die("not found");
    };
    let date = php::date("Y-m-d H:i:s", info.get("time").to_int());
    let owner = id_to_user(ctx, &info.get("owner")).await?;
    ctx.echo(d);
    ctx.echo(" was created by ");
    ctx.echo(owner);
    ctx.echo(" on ");
    ctx.echo(date);
    Ok(())
}
