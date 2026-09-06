//! DSMail: the inbox, its local copy, and what goes over the wire.
//!
//! The server hands out mail incrementally — a request asks for everything
//! newer than the highest id already held — so the client keeps its own copy
//! in `/system/mail.dat` and that file is what the reader displays. It also
//! carries the read flag, which the server does not track at all.
//!
//! Both formats are `:--:`-separated, and both are the original client's.
//! Only the parsing lives here; who writes the file and who draws the list
//! belong to the front end.

use super::crypto;
use super::protocol::{strip_code, summary};
use super::values;

/// Where the client keeps its copy of the inbox.
pub const STORE_PATH: &str = "/system/mail.dat";

/// Separates the fields of a record, in both formats.
const SEPARATOR: &str = ":--:";

/// Ids arrive as `X_<n>`, which is also how the store holds them.
const ID_PREFIX: &str = "X_";

/// One message.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Message {
    pub id: i64,
    /// `name@domain`, which the server composes; a player's own mail comes
    /// from `<username>@users`.
    pub from: String,
    pub subject: String,
    pub body: String,
    /// As the server formatted it: `dd.mm.yyyy HH:MM:SS`.
    pub date: String,
    /// The client's own flag. A message arrives unread.
    pub unread: bool,
}

/// Parse an `action=inbox` answer.
///
/// The endpoint writes one record per line and ends with a blank one, so a
/// line that is not a record is the blank one.
pub fn parse_inbox(body: &str) -> Vec<Message> {
    strip_code(body)
        .lines()
        .filter_map(|line| parse_record(line.trim_end_matches('\r')))
        .collect()
}

/// Parse `/system/mail.dat`, which is the same record with the read flag in
/// front of it.
pub fn parse_store(text: &str) -> Vec<Message> {
    text.lines()
        .filter_map(|line| {
            let line = line.trim_end_matches('\r');
            let (flag, rest) = line.split_once(SEPARATOR)?;
            let mut message = parse_record(rest)?;
            // Anything but a plain "0" counts as unread, which is how the
            // original writes it: a fetched line starts at "1".
            message.unread = flag.trim() != "0";
            Some(message)
        })
        .collect()
}

/// Render `/system/mail.dat`.
pub fn render_store(messages: &[Message]) -> String {
    let mut out = String::new();
    for m in messages {
        out.push_str(if m.unread { "1" } else { "0" });
        out.push_str(SEPARATOR);
        out.push_str(ID_PREFIX);
        out.push_str(&m.id.to_string());
        out.push_str(SEPARATOR);
        out.push_str(&m.from);
        out.push_str(SEPARATOR);
        out.push_str(&crypto::encode_base64(m.subject.as_bytes()));
        out.push_str(SEPARATOR);
        out.push_str(&crypto::encode_base64(m.body.as_bytes()));
        out.push_str(SEPARATOR);
        out.push_str(&m.date);
        out.push_str("\r\n");
    }
    out
}

/// The id to ask the server for everything after.
pub fn highest_id(messages: &[Message]) -> i64 {
    messages.iter().map(|m| m.id).max().unwrap_or(0)
}

/// Fold newly arrived messages into the stored ones.
///
/// Returns how many were actually new. The server answers a `last=` request
/// with only newer ids, but a second window asking at the same moment can
/// still bring back one that is already held, and re-adding it would both
/// duplicate the row and resurrect its read flag.
pub fn merge(store: &mut Vec<Message>, incoming: Vec<Message>) -> usize {
    let mut added = 0;
    for message in incoming {
        if store.iter().any(|m| m.id == message.id) {
            continue;
        }
        store.push(message);
        added += 1;
    }
    store.sort_by_key(|m| m.id);
    added
}

/// The request body that asks for everything after `last`.
pub fn inbox_body(last: i64) -> String {
    format!("action=inbox&last={last}")
}

/// The request body that sends a message.
///
/// `to` is a comma-separated list of usernames; the server refuses more than
/// ten and refuses one it cannot find, in both cases by answering with the
/// complaint rather than a status.
pub fn send_body(to: &str, subject: &str, body: &str) -> String {
    format!(
        "action=send&to={}&subject={}&message={}",
        values::url_encode(to.trim()),
        values::url_encode(subject),
        values::url_encode(body)
    )
}

/// What `action=send` said. `Ok(())` only for the word the server uses to
/// mean it worked.
///
/// Anything else is the endpoint's own complaint, and is shown as it came.
pub fn send_result(body: &str) -> Result<(), String> {
    let text = strip_code(body);
    if text.trim() == "success" {
        return Ok(());
    }
    match summary(text) {
        // An empty body means the request never reached the handler, which
        // is worth saying rather than showing a blank complaint.
        complaint if complaint.is_empty() => Err("The server gave no answer.".into()),
        complaint => Err(complaint),
    }
}

/// `X_<id>:--:<from>:--:<subject>:--:<body>:--:<date>`, with the subject and
/// body base64'd.
fn parse_record(line: &str) -> Option<Message> {
    let fields: Vec<&str> = line.split(SEPARATOR).collect();
    if fields.len() != 5 {
        return None;
    }
    let id = fields[0].strip_prefix(ID_PREFIX)?.trim().parse().ok()?;
    Some(Message {
        id,
        from: fields[1].trim().to_string(),
        subject: decode_text(fields[2]),
        body: decode_text(fields[3]),
        date: fields[4].trim().to_string(),
        unread: true,
    })
}

/// Base64 as the server writes it: the URL-safe alphabet with the padding
/// stripped. Trailing `=` is tolerated anyway, since it costs nothing and a
/// padded encoder somewhere else should not lose a message body.
fn decode_text(field: &str) -> String {
    let trimmed = field.trim().trim_end_matches('=');
    match crypto::decode_base64(trimmed) {
        Ok(bytes) => String::from_utf8_lossy(&bytes).into_owned(),
        // A body that will not decode is still worth showing as something.
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
    fn an_inbox_answer_becomes_messages() {
        let body = format!(
            "7000X_7:--:alice@users:--:{}:--:{}:--:05.09.2026 11:22:33\r\n",
            encoded("Hello"),
            encoded("first line\r\nsecond line"),
        );
        let messages = parse_inbox(&body);
        assert_eq!(messages.len(), 1);
        assert_eq!(messages[0].id, 7);
        assert_eq!(messages[0].from, "alice@users");
        assert_eq!(messages[0].subject, "Hello");
        assert_eq!(messages[0].body, "first line\r\nsecond line");
        assert_eq!(messages[0].date, "05.09.2026 11:22:33");
        assert!(messages[0].unread, "mail arrives unread");
    }

    #[test]
    fn the_blank_line_at_the_end_is_not_a_message() {
        let body = format!(
            "7000X_7:--:a@users:--:{}:--:{}:--:x\r\n\r\n",
            encoded("s"),
            encoded("b"),
        );
        assert_eq!(parse_inbox(&body).len(), 1);
    }

    #[test]
    fn the_store_survives_a_round_trip_with_its_read_flags() {
        let messages = vec![
            Message {
                id: 1,
                from: "alice@users".into(),
                subject: "Read this".into(),
                body: "body one".into(),
                date: "05.09.2026 11:22:33".into(),
                unread: false,
            },
            Message {
                id: 2,
                from: "bob@users".into(),
                subject: "New".into(),
                body: "body two".into(),
                date: "05.09.2026 12:00:00".into(),
                unread: true,
            },
        ];
        assert_eq!(parse_store(&render_store(&messages)), messages);
    }

    #[test]
    fn a_stored_line_is_the_wire_record_with_a_flag_in_front() {
        // The format is the original client's, so it is pinned literally: a
        // `mail.dat` written by the desktop client has to still read here.
        let rendered = render_store(&[Message {
            id: 3,
            from: "carol@users".into(),
            subject: "Hi".into(),
            body: "there".into(),
            date: "05.09.2026 09:00:00".into(),
            unread: true,
        }]);
        assert_eq!(
            rendered,
            format!(
                "1:--:X_3:--:carol@users:--:{}:--:{}:--:05.09.2026 09:00:00\r\n",
                encoded("Hi"),
                encoded("there")
            )
        );
    }

    #[test]
    fn merging_keeps_the_read_flag_of_a_message_already_held() {
        let mut store = parse_store(&render_store(&[Message {
            id: 4,
            from: "dave@users".into(),
            subject: "Old".into(),
            body: "old body".into(),
            date: "05.09.2026 08:00:00".into(),
            unread: false,
        }]));
        let incoming = parse_inbox(&format!(
            "7000X_4:--:dave@users:--:{}:--:{}:--:05.09.2026 08:00:00\r\nX_5:--:erin@users:--:{}:--:{}:--:05.09.2026 09:00:00\r\n",
            encoded("Old"),
            encoded("old body"),
            encoded("New"),
            encoded("new body"),
        ));
        assert_eq!(merge(&mut store, incoming), 1, "only id 5 is new");
        assert_eq!(store.len(), 2);
        assert!(!store[0].unread, "a re-sent message stays read");
        assert!(store[1].unread);
        assert_eq!(highest_id(&store), 5);
    }

    #[test]
    fn an_empty_inbox_asks_from_zero() {
        assert_eq!(highest_id(&[]), 0);
        assert_eq!(inbox_body(0), "action=inbox&last=0");
    }

    #[test]
    fn a_send_encodes_its_fields() {
        assert_eq!(
            send_body(" alice ", "Re: hi", "line one\r\nline two"),
            "action=send&to=alice&subject=Re%3A+hi&message=line+one%0D%0Aline+two"
        );
    }

    #[test]
    fn only_the_servers_own_word_counts_as_sent() {
        assert_eq!(send_result("7000success"), Ok(()));
        assert_eq!(
            send_result("7000Unknown name: nobody"),
            Err("Unknown name: nobody".into())
        );
        assert!(send_result("7000").is_err(), "a bare code is not a success");
    }

    #[test]
    fn a_complaint_keeps_its_own_words() {
        assert_eq!(
            send_result("7000Unknown name: nobody"),
            Err("Unknown name: nobody".into())
        );
        // A long one is cut short rather than filling the status line.
        let complaint = send_result(&format!("7000{}", "word ".repeat(100))).unwrap_err();
        assert!(complaint.ends_with('…'), "got {complaint:?}");
    }
}
