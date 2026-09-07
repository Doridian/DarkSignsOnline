//! Chat: what a line looks like on the wire, and what a typed one means.
//!
//! The original client got this from IRC — a TLS socket to
//! `irc.libera.chat:6697` and `#darksignsonline` — which a browser cannot
//! open at all. The room is the game server's own now, reached through
//! `chat.php`, but everything above the transport is kept: a line is still
//! `<who> text`, `/me` is still an emote, and `ChatSend` and `ChatView` are
//! still the two things a script can do with it.
//!
//! The server hands lines out incrementally, the way `dsmail.php` does, so
//! the client asks for whatever is newer than the highest id it holds.

use super::crypto;
use super::protocol::summary;
use super::server::ServerResponse;
use super::values;

/// Separates the fields of a record, as everywhere else in this API.
const SEPARATOR: &str = ":--:";

/// Ids arrive as `X_<n>`.
const ID_PREFIX: &str = "X_";

/// The longest message the original would send. It truncated rather than
/// refusing -- 32764 would overflow the VB6 string it built -- and so does
/// this. The server has a shorter limit of its own and applies it too.
pub const MAX_LENGTH: usize = 32763;

/// One thing somebody said.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Line {
    pub id: i64,
    /// The account that said it. Identity is the game account now, where on
    /// IRC it was a nickname the player could change.
    pub from: String,
    pub text: String,
    /// A `/me`, which the original sent as a CTCP `ACTION`.
    pub action: bool,
    /// As the server formatted it: `dd.mm.yyyy HH:MM:SS`.
    pub date: String,
}

impl Line {
    /// The line as the original's chat pane wrote it: `<nick>  text` for a
    /// message and `* nick text` for an emote.
    pub fn render(&self) -> String {
        match self.action {
            true => format!("* {} {}", self.from, self.text),
            false => format!("<{}>  {}", self.from, self.text),
        }
    }
}

/// What a typed line turned out to mean.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Entry {
    /// Say it.
    Say(String),
    /// Say it as an emote: `/me`.
    Emote(String),
    /// Type nothing, get nothing. The original exits its handler here.
    Nothing,
    /// A `/word` that is not one of ours, named so it can be complained
    /// about the way the original did: "Command not found."
    Unknown(String),
}

/// Read a line the player typed at the chat box.
///
/// The rules are the original's `cmdChat_Click`: a leading `/` introduces a
/// command, `//` escapes it so a message can start with a slash, and `/me`
/// is an emote. `/nick` and `/msg` are gone with IRC — a name here is the
/// account's and cannot be changed, and there is nobody to open a query
/// with — so both land in [`Entry::Unknown`] rather than pretending.
pub fn parse_entry(typed: &str) -> Entry {
    let trimmed = typed.trim();
    if trimmed.is_empty() {
        return Entry::Nothing;
    }
    let Some(rest) = trimmed.strip_prefix('/') else {
        return Entry::Say(trimmed.to_string());
    };
    // `//` is one literal slash: everything after the first is the message.
    if let Some(literal) = rest.strip_prefix('/') {
        return match literal.trim() {
            "" => Entry::Nothing,
            text => Entry::Say(format!("/{text}")),
        };
    }
    let (word, argument) = match rest.split_once(char::is_whitespace) {
        Some((word, argument)) => (word, argument.trim()),
        None => (rest, ""),
    };
    match word.to_ascii_lowercase().as_str() {
        "me" => match argument {
            "" => Entry::Nothing,
            text => Entry::Emote(text.to_string()),
        },
        other => Entry::Unknown(other.to_string()),
    }
}

/// Trim and truncate a message the way `ChatSend` did, or `None` when
/// nothing is left to send.
pub fn clean(message: &str) -> Option<String> {
    // The original truncates before it trims, so a long message that ends in
    // whitespace still comes out trimmed.
    let cut = match message.char_indices().nth(MAX_LENGTH) {
        Some((byte, _)) => &message[..byte],
        None => message,
    };
    match values::trim_with_newline(cut) {
        "" => None,
        text => Some(text.to_string()),
    }
}

/// The id to ask the server for everything after.
pub fn highest_id(lines: &[Line]) -> i64 {
    lines.iter().map(|l| l.id).max().unwrap_or(0)
}

/// The request that asks for everything after `last`.
///
/// `last = 0` means the client holds nothing, and the server answers that
/// with a backlog rather than with the whole history of the room.
pub fn read_path(last: i64) -> String {
    format!("chat.php?action=read&last={last}")
}

/// The request body that says something.
pub fn send_body(message: &str, action: bool) -> String {
    format!(
        "action=send&emote={}&message={}",
        u8::from(action),
        values::url_encode(message)
    )
}

/// Parse an `action=read` answer: one record per line, oldest first.
pub fn parse_log(body: &str) -> Vec<Line> {
    body.lines()
        .filter_map(|line| parse_record(line.trim_end_matches('\r')))
        .collect()
}

/// What `action=send` said: the id the line was given, or the complaint to
/// show the player instead.
///
/// The endpoint says why it refused in plain words -- "You are talking too
/// fast." -- so most of the time the complaint is its own. A 401 is the
/// exception, because that is `function.php` answering rather than
/// `chat.php`, and all it says is the code `1002`.
pub fn send_result(response: &ServerResponse) -> Result<i64, String> {
    let text = response.body.trim();
    if response.is_success() {
        if let Some(id) = text.strip_prefix(ID_PREFIX).and_then(|n| n.parse().ok()) {
            return Ok(id);
        }
    }
    if response.code == 401 {
        return Err("You are not signed in.".into());
    }
    Err(match summary(text) {
        complaint if complaint.is_empty() => match response.code {
            0 => "Could not reach the server.".into(),
            code => format!("The server answered {code}."),
        },
        complaint => complaint,
    })
}

/// Fold newly arrived lines into the ones already held, returning how many
/// were new.
///
/// Two consoles can poll at the same moment and both be handed a line, so
/// arrival alone does not make it new.
pub fn merge(held: &mut Vec<Line>, incoming: Vec<Line>) -> usize {
    let mut added = 0;
    for line in incoming {
        if held.iter().any(|l| l.id == line.id) {
            continue;
        }
        held.push(line);
        added += 1;
    }
    held.sort_by_key(|l| l.id);
    added
}

/// `X_<id>:--:<from>:--:<0|1>:--:<text>:--:<date>`, with the text base64'd.
fn parse_record(line: &str) -> Option<Line> {
    let fields: Vec<&str> = line.split(SEPARATOR).collect();
    if fields.len() != 5 {
        return None;
    }
    let id = fields[0].strip_prefix(ID_PREFIX)?.trim().parse().ok()?;
    Some(Line {
        id,
        from: fields[1].trim().to_string(),
        action: fields[2].trim() == "1",
        text: decode_text(fields[3]),
        date: fields[4].trim().to_string(),
    })
}

/// Base64 as the server writes it: URL-safe and unpadded, though padding is
/// tolerated so an encoder that adds it does not lose a message.
fn decode_text(field: &str) -> String {
    let trimmed = field.trim().trim_end_matches('=');
    match crypto::decode_base64(trimmed) {
        Ok(bytes) => String::from_utf8_lossy(&bytes).into_owned(),
        Err(_) => String::new(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn encoded(text: &str) -> String {
        crypto::encode_base64(text.as_bytes())
    }

    #[test]
    fn a_read_answer_becomes_lines() {
        let body = format!(
            "X_4:--:alice:--:0:--:{}:--:05.09.2026 11:22:33\r\n\
             X_5:--:bob:--:1:--:{}:--:05.09.2026 11:22:40\r\n",
            encoded("hello there"),
            encoded("waves"),
        );
        let lines = parse_log(&body);
        assert_eq!(lines.len(), 2);
        assert_eq!(lines[0].id, 4);
        assert_eq!(lines[0].from, "alice");
        assert_eq!(lines[0].text, "hello there");
        assert!(!lines[0].action);
        assert_eq!(lines[0].date, "05.09.2026 11:22:33");
        assert!(lines[1].action, "the flag is what makes it a /me");
    }

    #[test]
    fn a_line_renders_the_way_the_original_wrote_it() {
        let say = Line {
            id: 1,
            from: "alice".into(),
            text: "hi".into(),
            action: false,
            date: String::new(),
        };
        assert_eq!(say.render(), "<alice>  hi", "two spaces, as in the original");
        assert_eq!(Line { action: true, ..say }.render(), "* alice hi");
    }

    #[test]
    fn a_blank_or_broken_record_is_skipped() {
        assert!(parse_log("\r\n").is_empty());
        assert!(parse_log("not a record").is_empty());
        assert!(parse_log("X_x:--:a:--:0:--:aGk:--:d").is_empty(), "the id has to parse");
    }

    #[test]
    fn the_highest_id_is_what_the_next_fetch_asks_after() {
        assert_eq!(highest_id(&[]), 0, "nothing held asks for the backlog");
        assert_eq!(read_path(0), "chat.php?action=read&last=0");
        let lines = parse_log(&format!("X_9:--:a:--:0:--:{}:--:d\r\n", encoded("x")));
        assert_eq!(highest_id(&lines), 9);
    }

    #[test]
    fn plain_text_is_said_as_it_is() {
        assert_eq!(parse_entry("hello there"), Entry::Say("hello there".into()));
        assert_eq!(parse_entry("  padded  "), Entry::Say("padded".into()));
    }

    #[test]
    fn nothing_typed_sends_nothing() {
        assert_eq!(parse_entry(""), Entry::Nothing);
        assert_eq!(parse_entry("   "), Entry::Nothing);
        assert_eq!(parse_entry("/me"), Entry::Nothing, "an emote needs something to emote");
        assert_eq!(parse_entry("//"), Entry::Nothing);
    }

    #[test]
    fn me_is_an_emote() {
        assert_eq!(parse_entry("/me waves"), Entry::Emote("waves".into()));
        assert_eq!(parse_entry("/ME waves"), Entry::Emote("waves".into()), "case does not matter");
    }

    /// The original's `//` escape, which is the only way to say something
    /// that starts with a slash.
    #[test]
    fn a_doubled_slash_says_one() {
        assert_eq!(parse_entry("//me is a literal"), Entry::Say("/me is a literal".into()));
        assert_eq!(parse_entry("//help"), Entry::Say("/help".into()));
    }

    /// `/nick` and `/msg` were IRC's, and saying so beats sending them as
    /// chat where they would look like a player talking to nobody.
    #[test]
    fn an_unknown_command_is_named_rather_than_said() {
        assert_eq!(parse_entry("/nick bob"), Entry::Unknown("nick".into()));
        assert_eq!(parse_entry("/msg bob hi"), Entry::Unknown("msg".into()));
        assert_eq!(parse_entry("/quit"), Entry::Unknown("quit".into()));
    }

    #[test]
    fn a_message_is_trimmed_and_truncated() {
        assert_eq!(clean("  hi  "), Some("hi".into()));
        assert_eq!(clean("   "), None);
        assert_eq!(clean(""), None);
        let long = "a".repeat(MAX_LENGTH + 100);
        assert_eq!(clean(&long).unwrap().chars().count(), MAX_LENGTH);
    }

    /// Truncation counts characters, not bytes, so a multi-byte message is
    /// not cut in half.
    #[test]
    fn truncation_does_not_split_a_character() {
        let long = "é".repeat(MAX_LENGTH + 10);
        let cut = clean(&long).unwrap();
        assert_eq!(cut.chars().count(), MAX_LENGTH);
    }

    #[test]
    fn a_send_answers_with_the_id_it_was_given() {
        assert_eq!(send_result(&ServerResponse::ok("X_12")), Ok(12));
        assert_eq!(
            send_result(&ServerResponse { code: 429, body: "You are talking too fast.".into() }),
            Err("You are talking too fast.".into()),
        );
    }

    /// A 401 is `function.php` refusing before `chat.php` is reached, and
    /// all it says is `1002`, which is no use to a player.
    #[test]
    fn being_signed_out_is_said_in_words() {
        assert_eq!(
            send_result(&ServerResponse { code: 401, body: "1002".into() }),
            Err("You are not signed in.".into()),
        );
    }

    #[test]
    fn a_silent_failure_still_says_something() {
        assert_eq!(
            send_result(&ServerResponse { code: 0, body: String::new() }),
            Err("Could not reach the server.".into()),
        );
        assert_eq!(
            send_result(&ServerResponse { code: 500, body: String::new() }),
            Err("The server answered 500.".into()),
        );
        // A 200 whose body is not an id is a server that answered something
        // unexpected, not a success.
        assert_eq!(
            send_result(&ServerResponse::ok("what?")),
            Err("what?".into()),
        );
    }

    #[test]
    fn a_send_body_carries_the_emote_flag() {
        assert_eq!(send_body("hi there", false), "action=send&emote=0&message=hi+there");
        assert_eq!(send_body("waves", true), "action=send&emote=1&message=waves");
    }

    #[test]
    fn a_line_already_held_is_not_added_twice() {
        let one = |id: i64| Line {
            id,
            from: "a".into(),
            text: "x".into(),
            action: false,
            date: String::new(),
        };
        let mut held = vec![one(1), one(2)];
        assert_eq!(merge(&mut held, vec![one(2), one(3)]), 1, "only 3 is new");
        assert_eq!(held.iter().map(|l| l.id).collect::<Vec<_>>(), vec![1, 2, 3]);
    }
}
