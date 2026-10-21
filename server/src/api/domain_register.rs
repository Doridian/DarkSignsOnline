//! `domain_register.php`: buy a domain, a subdomain of one you own, or an IP.

use super::{BANK_USER_ID, authenticate, get_domain_info, make_new_domain, transaction, valid_ip};
use crate::ctx::{Ctx, Res};
use crate::php::{self, Zv};

/// What each top-level domain costs, in the order the price list shows them.
const PRICES: &[(&str, i64)] = &[
    ("com", 120),
    ("net", 80),
    ("org", 80),
    ("edu", 299),
    ("mil", 1499),
    ("gov", 1499),
    ("dsn", 12999),
    ("ru", 40),
];

/// A fixed IP costs this on top of the domain, and an IP on its own.
const FIXED_IP_PRICE: i64 = 40;
const SUBDOMAIN_PRICE: i64 = 20;

const INSUFFICIENT: &str = "Insufficient balance. Try again when you have more money.";

pub async fn run(ctx: &mut Ctx) -> Res {
    authenticate(ctx).await?;
    let uid = ctx.user_id().to_int();
    let cash = ctx.user_field("cash").to_int();

    let fixedip = ctx.req.request("fixedip");
    if !fixedip.is_empty() && !valid_ip(&fixedip.to_bytes()) {
        return ctx.die_error("Invalid fixed IP.", 400);
    }
    let fixed_extra = if fixedip.is_empty() { 0 } else { FIXED_IP_PRICE };

    ctx.print_returnwith("2000", 1);

    if !ctx.req.request("prices").is_null() {
        let list: Vec<String> = PRICES.iter().map(|(ext, cost)| format!("{ext}: ${cost}")).collect();
        return ctx.die(list.join(", "));
    }

    let d = php::strtolower(&ctx.req.request("d").to_bytes());
    if get_domain_info(ctx, &d).await?.is_some() {
        return ctx.die_error([&b"Domain "[..], &d, b" is already registed."].concat(), 409);
    }

    // The bank's verdict is a status string, and every status string is
    // truthy, so a registration that got this far always goes through. The
    // balance check before it is what actually stands in the way.
    let mut parts = php::explode(b".", &d);
    if parts.len() == 4 && valid_ip(&d) {
        let ipdom = parts
            .iter()
            .map(|p| php::intval(p).to_string())
            .collect::<Vec<_>>()
            .join(".");
        let price = FIXED_IP_PRICE;
        if price > cash {
            return ctx.die_error(INSUFFICIENT, 402);
        }
        ctx.begin().await?;
        transaction(
            ctx,
            uid,
            BANK_USER_ID,
            &Zv::str(format!("IP Registration: {ipdom}")),
            price,
        )
        .await?;
        make_new_domain(ctx, "IP", &Zv::str(&ipdom), uid, b"", 0).await?;
        ctx.commit().await?;
        return ctx.die(format!(
            "Registration complete for {ipdom}, you have been charged ${price}."
        ));
    }

    let complete = |d: &[u8], price: i64| {
        [
            &b"Registration complete for "[..],
            d,
            format!(", you have been charged ${price}").as_bytes(),
        ]
        .concat()
    };

    if parts.len() == 2 {
        let ext = parts[1];
        let Some(&(_, base)) = PRICES.iter().find(|(e, _)| e.as_bytes() == ext) else {
            return ctx.die_error("Invalid domain extension.", 400);
        };
        let price = base + fixed_extra;
        if price > cash {
            return ctx.die_error(INSUFFICIENT, 402);
        }
        ctx.begin().await?;
        let desc = [&b"Domain Registration: "[..], &d].concat();
        transaction(ctx, uid, BANK_USER_ID, &Zv::Str(desc), price).await?;
        make_new_domain(ctx, "DOMAIN", &fixedip, uid, &d, 0).await?;
        ctx.commit().await?;
        return ctx.die(complete(&d, price));
    }

    if parts.len() > 2 {
        let ext = parts.pop().expect("more than two parts");
        let name = parts.pop().expect("more than two parts");
        let root = get_domain_info(ctx, &[name, b".", ext].concat()).await?;
        let root_owner = root.as_ref().map_or(Zv::Null, |r| r.get("owner"));
        let price = SUBDOMAIN_PRICE + fixed_extra;
        if root_owner.to_int() != uid || root_owner.is_null() {
            let msg = [
                &root_owner.to_bytes()[..],
                format!("  {uid}  You must be the owner of the full domain to register a sub domain.").as_bytes(),
            ]
            .concat();
            return ctx.die_error(msg, 403);
        }
        if price > cash {
            return ctx.die_error(INSUFFICIENT, 402);
        }
        let parent = root.map_or(0, |r| r.get("id").to_int());
        ctx.begin().await?;
        let desc = [&b"Subdomain Registration: "[..], &d].concat();
        transaction(ctx, uid, BANK_USER_ID, &Zv::Str(desc), price).await?;
        make_new_domain(ctx, "SUBDOMAIN", &fixedip, uid, &d, parent).await?;
        ctx.commit().await?;
        return ctx.die(complete(&d, price));
    }

    ctx.die_error("Invalid domain name.", 400)
}
