//! `auth.php`: check the credentials, and hand back the IP of the player's
//! own `<name>.usr` domain, making it first if this is their first login.

use super::{authenticate, cat, get_domain_by_id, get_domain_info, make_new_domain};
use crate::ctx::{Ctx, Res};
use crate::php::Zv;

pub async fn run(ctx: &mut Ctx) -> Res {
    authenticate(ctx).await?;
    ctx.echo("1001");

    let name = cat(&[&ctx.user_field("username").to_bytes(), b".usr"]);
    let mut d = get_domain_info(ctx, &name).await?;
    if d.is_none() {
        let uid = ctx.user_id().to_int();
        let id = make_new_domain(ctx, "DOMAIN", &Zv::Null, uid, &name, 0).await?;
        d = get_domain_by_id(ctx, id).await?;
    }
    let ip = d.map_or(Zv::Null, |d| d.get("ip"));
    ctx.echo(ip.to_bytes());
    Ok(())
}
