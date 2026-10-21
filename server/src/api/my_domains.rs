//! `my_domains.php`: the player's domains, IPs, or a domain's subdomains.

use super::{authenticate, get_domain_info};
use crate::ctx::{Ctx, Res, s};
use crate::php::{self, Zv};

pub async fn run(ctx: &mut Ctx) -> Res {
    authenticate(ctx).await?;
    ctx.print_returnwith("2001", 1);

    let ty = php::strtoupper(php::trim(&ctx.req.get("type").to_bytes()));
    let rows = match &ty[..] {
        b"DOMAIN" | b"IP" => {
            ctx.query(
                "SELECT host, ip FROM domains WHERE owner = ? AND regtype = ?",
                vec![ctx.user_id().to_int().into(), s(&Zv::Str(ty))],
            )
            .await?
        }
        b"SUBDOMAIN" => {
            let domain = ctx.req.get("domain").to_bytes();
            let Some(info) = get_domain_info(ctx, &domain).await? else {
                return ctx.die("Domain not found.");
            };
            if info.get("owner") != ctx.user_id() {
                return ctx.die("Permission denied.");
            }
            ctx.query(
                "SELECT host, ip FROM domains WHERE regtype = \"SUBDOMAIN\" AND parent = ?",
                vec![info.get("id").to_int().into()],
            )
            .await?
        }
        _ => return ctx.die("Invalid type paramater."),
    };
    for row in rows {
        ctx.echo(b"IP: ");
        ctx.echo(row.get("ip").to_bytes());
        ctx.echo(b"; Host: ");
        ctx.echo(row.get("host").to_bytes());
        ctx.echo(b"\r\n");
    }
    Ok(())
}
