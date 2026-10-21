//! `chat.php`: the room the original client got from IRC.
//!
//! Reading is public and saying something is not. That split is the point
//! of the ordering below: authenticating is a bcrypt, and a client watching
//! the room asks again every second or so, so the read is answered before
//! any account is looked at.

use super::{authenticate, cors, now};
use crate::ctx::{Ctx, Rec, Res, s};
use crate::php;

/// How many lines a client with nothing yet is given as backlog.
const CHAT_BACKLOG: i64 = 100;
/// The most a single fetch hands back, however far behind the caller is.
const CHAT_MAX_FETCH: i64 = 500;
/// A chat line is one line, and not a long one.
const CHAT_MAX_LENGTH: usize = 1024;
/// A loose limit, meant for a script stuck calling `ChatSend` in a loop
/// rather than for a determined flooder.
const CHAT_RATE_SECONDS: i64 = 10;
const CHAT_RATE_LIMIT: i64 = 10;

/// Reduce a message to the one line it is allowed to be: runs of control
/// characters become a space, and the result is trimmed and capped.
///
/// A message that is not UTF-8 comes out empty, which is how the PHP's
/// fallback for that case behaved (it fell back on the NULL the failed
/// replacement returned), and so is refused as saying nothing.
fn chat_clean(msg: &[u8]) -> Vec<u8> {
    let Ok(msg) = std::str::from_utf8(msg) else {
        return Vec::new();
    };
    let mut out = String::with_capacity(msg.len());
    let mut in_run = false;
    for c in msg.chars() {
        if c < ' ' || c == '\x7F' {
            if !in_run {
                out.push(' ');
            }
            in_run = true;
        } else {
            out.push(c);
            in_run = false;
        }
    }
    let trimmed = std::str::from_utf8(php::trim(out.as_bytes())).expect("trimming ASCII keeps UTF-8");
    trimmed.chars().take(CHAT_MAX_LENGTH).collect::<String>().into_bytes()
}

/// One record, in the `:--:` format the rest of the API uses. The stamp is
/// UTC, so the client can show it on the reader's own clock.
fn chat_record(row: &Rec, out: &mut Vec<u8>) {
    out.extend_from_slice(b"X_");
    out.extend_from_slice(&row.get("id").to_bytes());
    out.extend_from_slice(b":--:");
    out.extend_from_slice(&row.get("username").to_bytes());
    out.extend_from_slice(if row.get("action").is_empty() {
        b":--:0"
    } else {
        b":--:1"
    });
    out.extend_from_slice(b":--:");
    out.extend_from_slice(&php::dso_b64_encode(&row.get("message").to_bytes()));
    out.extend_from_slice(b":--:");
    out.extend_from_slice(php::date("d.m.Y H:i:s", row.get("time").to_int()).as_bytes());
    out.extend_from_slice(b"\r\n");
}

pub async fn run(ctx: &mut Ctx) -> Res {
    cors(ctx)?;
    let action = ctx.req.request("action");

    if action.is_str(b"read") {
        let last = ctx.req.request("last").to_int();
        let rows = if last > 0 {
            // Caught up already, or nearly: everything newer, oldest first.
            ctx.query(
                "SELECT c.id, c.action, c.message, c.time, u.username
                 FROM chat c JOIN users u ON u.id = c.user
                 WHERE c.id > ? ORDER BY c.id ASC LIMIT ?",
                vec![last.into(), CHAT_MAX_FETCH.into()],
            )
            .await?
        } else {
            // The backlog a client opens with: the *last* hundred, taken
            // newest-first and turned back around into the order said.
            let mut rows = ctx
                .query(
                    "SELECT c.id, c.action, c.message, c.time, u.username
                     FROM chat c JOIN users u ON u.id = c.user
                     ORDER BY c.id DESC LIMIT ?",
                    vec![CHAT_BACKLOG.into()],
                )
                .await?;
            rows.reverse();
            rows
        };
        let mut out = Vec::new();
        for row in &rows {
            chat_record(row, &mut out);
        }
        return ctx.die(out);
    }

    // Everything past here needs an account.
    authenticate(ctx).await?;

    if action.is_str(b"send") {
        let msg = chat_clean(&ctx.req.request("message").to_bytes());
        if msg.is_empty() {
            return ctx.die_error("Nothing to say.", 400);
        }
        // `/me`, which the original sent as a CTCP ACTION.
        let is_action = i64::from(!ctx.req.request("emote").is_empty());
        let uid = ctx.user_id().to_int();

        let recent = ctx
            .query_one(
                "SELECT COUNT(*) FROM chat WHERE user = ? AND time > ?",
                vec![uid.into(), (now() - CHAT_RATE_SECONDS).into()],
            )
            .await?
            .map_or(0, |r| r.idx(0).to_int());
        if recent >= CHAT_RATE_LIMIT {
            return ctx.die_error("You are talking too fast.", 429);
        }

        let (_, id) = ctx
            .exec(
                "INSERT INTO chat (user, action, message, time) VALUES (?, ?, ?, ?)",
                vec![uid.into(), is_action.into(), s(&php::Zv::Str(msg)), now().into()],
            )
            .await?;
        // The id the line got, so a sender knows which line it reads back
        // is its own.
        return ctx.die(format!("X_{id}"));
    }

    ctx.die_error("No request sent", 400)
}

#[cfg(test)]
mod tests {
    use super::chat_clean;

    #[test]
    fn one_clean_line() {
        assert_eq!(chat_clean(b"  hi\r\n\tthere\x7F "), b"hi there");
        assert_eq!(chat_clean(b"\xff"), b"");
        assert_eq!(chat_clean("é".repeat(2000).as_bytes()).len(), 2048);
    }
}
