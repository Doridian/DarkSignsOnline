//! `textspace.php`: numbered channels of text, newest upload wins.
//!
//! This one still answers in the legacy shape whatever the protocol version:
//! 4501 in front of a download, 4500 in front of everything else.

use super::{authenticate, now};
use crate::ctx::{Ctx, Res, s};
use crate::php::Zv;

pub async fn run(ctx: &mut Ctx) -> Res {
    authenticate(ctx).await?;

    let download = ctx.req.request("download");
    if !download.is_empty() {
        let chan = download.to_int();
        if chan < 1 {
            return ctx.die_error("4501", 404);
        }
        let row = ctx
            .query_one(
                "SELECT `text` FROM textspace WHERE chan = ? ORDER BY id DESC LIMIT 1",
                vec![chan.into()],
            )
            .await?;
        let Some(row) = row else {
            return ctx.die("4501");
        };
        ctx.echo("4501");
        return ctx.die(row.get("text").to_bytes());
    }

    let upload = ctx.req.request("upload");
    if !upload.is_empty() {
        let chan = upload.to_int();
        if chan <= 1 {
            return ctx.die_error("4500Invalid channel.", 400);
        }
        let data = match ctx.req.request("textdata") {
            Zv::Null => Zv::str(""),
            v => v,
        };
        ctx.exec(
            "INSERT INTO textspace (`chan`, `owner`, `lastupdate`, `text`, `deleted`) VALUES (?, ?, ?, ?, 0)",
            vec![chan.into(), ctx.user_id().to_int().into(), now().into(), s(&data)],
        )
        .await?;
        return ctx.die(format!("4500Updated: {chan}!"));
    }

    ctx.die_error("4500Invalid action.", 400)
}
