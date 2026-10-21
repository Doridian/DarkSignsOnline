//! `dsmail.php`: in-game mail.
//!
//! The inbox is incremental, like chat: the client keeps its own copy and
//! asks for whatever is newer than the last id it holds. Every answer still
//! carries the legacy 7000 prefix, whatever the protocol version.

use super::{authenticate, get_domain_info, now, user_to_id};
use crate::ctx::{Ctx, Res, i, s};
use crate::php::{self, Zv};

fn or_empty(z: Zv) -> Zv {
    if z.is_null() { Zv::str("") } else { z }
}

pub async fn run(ctx: &mut Ctx) -> Res {
    authenticate(ctx).await?;
    ctx.print_returnwith("7000", -1);

    let action = ctx.req.request("action");
    let uid = ctx.user_id();

    if action.is_str(b"inbox") {
        let last = ctx.req.request("last").to_int();
        let rows = ctx
            .query(
                "SELECT id, from_addr, subject, message, time FROM dsmail WHERE to_user = ? AND id > ? ORDER BY id ASC",
                vec![i(&uid), last.into()],
            )
            .await?;
        for mail in rows {
            let mut line = b"X_".to_vec();
            line.extend_from_slice(&mail.get("id").to_bytes());
            line.extend_from_slice(b":--:");
            line.extend_from_slice(&mail.get("from_addr").to_bytes());
            line.extend_from_slice(b":--:");
            line.extend_from_slice(&php::dso_b64_encode(&mail.get("subject").to_bytes()));
            line.extend_from_slice(b":--:");
            line.extend_from_slice(&php::dso_b64_encode(&mail.get("message").to_bytes()));
            line.extend_from_slice(b":--:");
            line.extend_from_slice(php::date("d.m.Y H:i:s", mail.get("time").to_int()).as_bytes());
            line.extend_from_slice(b"\r\n");
            ctx.echo(line);
        }
        return Ok(());
    }

    if action.is_str(b"send") {
        let to = or_empty(ctx.req.request("to")).to_bytes();
        let sub = Zv::str(php::first_line(&ctx.req.request("subject").to_bytes()));
        let msg = or_empty(ctx.req.request("message"));
        let names = php::explode(b",", &to);
        if names.len() > 10 {
            return ctx.die_error("Cant send mail to more than 10 people.", 400);
        }
        let mut ids = Vec::new();
        for name in names {
            let id = user_to_id(ctx, &Zv::str(name)).await?;
            if id == -1 {
                return ctx.die_error([b"Unknown name: ", name].concat(), 400);
            }
            ids.push(id);
        }
        let hash = php::sha256_hex(&msg.to_bytes());
        let from = [&ctx.user_field("username").to_bytes()[..], b"@users"].concat();
        for id in ids {
            ctx.exec(
                "INSERT IGNORE INTO dsmail (from_addr, to_user, subject, message, time, message_hash) VALUES (?, ?, ?, ?, ?, ?)",
                vec![from.clone().into(), id.into(), s(&sub), s(&msg), now().into(), hash.clone().into()],
            )
            .await?;
        }
        return ctx.die("success");
    }

    if action.is_str(b"script_send_to_self") {
        // A server script mailing whoever is connected to it, from an
        // address on a domain belonging to the same owner as the server.
        let mut server = or_empty(ctx.req.request("server")).to_bytes();
        if Zv::Str(server.clone()).is_empty() {
            server = [&ctx.user_field("username").to_bytes()[..], b".usr"].concat();
        }
        let Some(server_info) = get_domain_info(ctx, &server).await? else {
            return ctx.die_error("Invalid server", 400);
        };
        let from = or_empty(ctx.req.request("from")).to_bytes();
        let subject = Zv::str(php::first_line(&ctx.req.request("subject").to_bytes()));
        let message = or_empty(ctx.req.request("message"));

        let parts = php::explode(b"@", &from);
        if parts.len() != 2 {
            return ctx.die_error("Invalid email", 400);
        }
        let (name, domain) = (parts[0], parts[1]);
        let info = get_domain_info(ctx, domain).await?;
        if info.is_none_or(|d| d.get("owner") != server_info.get("owner")) {
            let msg = [b"Server owner not matched (", domain, b" vs ", &server, b")"].concat();
            return ctx.die_error(msg, 400);
        }
        let valid = |c: &u8| c.is_ascii_alphanumeric() || *c == b'_' || *c == b'-';
        if !name.iter().all(valid) || name.len() > 32 {
            return ctx.die_error("Invalid from name", 400);
        }

        let hash = php::sha256_hex(&message.to_bytes());
        ctx.exec(
            "REPLACE INTO dsmail (from_addr, to_user, subject, message, message_hash, time) VALUES (?, ?, ?, ?, ?, ?)",
            vec![
                from.into(),
                i(&uid),
                s(&subject),
                s(&message),
                hash.into(),
                now().into(),
            ],
        )
        .await?;
        return ctx.die("OK");
    }

    ctx.die_error("No request sent", 400)
}
