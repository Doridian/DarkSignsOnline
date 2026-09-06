//! The file library and the text space, as `file_database.php` and
//! `textspace.php` speak them.
//!
//! The library is where players publish scripts to one another: a category
//! is listed, a row is downloaded into `/downloads`, and a file of your own
//! is uploaded or withdrawn. The text space is the same window's other half,
//! a numbered scratchpad any player can read and write.
//!
//! Both endpoints still prefix every answer with the four-character status
//! code that protocol 2 otherwise did away with — `file_database.php` asks
//! for it unconditionally and `textspace.php` writes it by hand — so
//! [`strip_code`] comes off the front of everything here.
//!
//! Only the wire format lives in this module. Who draws the window and who
//! writes the downloaded file belong to the front end, the same division
//! [`super::mail`] keeps.

use super::crypto;
use super::protocol::{strip_code, summary};
use super::values;

/// Where a downloaded file lands, as `basWorld` writes it.
pub const DOWNLOAD_DIR: &str = "/downloads";

/// Separates the fields of one record.
const FIELD: &str = ":--:";

/// Separates one record from the next. Each record is terminated by it
/// rather than joined with it, so a listing ends with an empty piece.
const RECORD: &str = ":--:--:";

/// The categories a file can be filed under.
///
/// The server takes the category as free text and matches on it exactly, so
/// this list is the client's alone: `frmLibrary.Form_Load` fills the same
/// eleven, in the same order, and a name that is not one of them lists
/// nothing.
pub const CATEGORIES: [&str; 11] = [
    "Code Bits",
    "Games",
    "Tools (Hacking)",
    "Tools (Misc)",
    "Mystery Box",
    "Operating Systems",
    "Scanners",
    "Templates",
    "Temporary",
    "Malware",
    "Security",
];

/// The highest text-space channel the original offers.
pub const CHANNELS: i64 = 999;

/// One file in the library.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Entry {
    pub id: i64,
    pub title: String,
    pub version: String,
    /// Bytes, as the server measured the stored copy.
    pub size: i64,
    pub author: String,
    /// The name it is saved under, without a directory.
    pub filename: String,
    pub description: String,
    /// `dd.mm.yyyy`, as the server formatted it.
    pub date: String,
    /// `HH:MM:SS`.
    pub time: String,
}

/// One of the player's own uploads, which they may withdraw.
///
/// The server hands these out as a single rendered line rather than as
/// fields, so the label is kept as it arrived and only the id is picked out
/// of it — which is what the original does to decide what to remove.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Upload {
    pub id: i64,
    pub label: String,
}

/// List one category.
pub fn list_path(category: &str) -> String {
    format!(
        "file_database.php?returnwith=4301&getcategory={}",
        values::url_encode(category)
    )
}

/// Fetch one file by id.
pub fn download_path(id: i64) -> String {
    format!("file_database.php?returnwith=4304&getfile={id}")
}

/// The player's own uploads.
pub fn removable_path() -> String {
    "file_database.php?returnwith=4302&getforremoval=a".to_string()
}

/// Withdraw one of them. The server checks the owner, so an id belonging to
/// somebody else simply removes nothing.
pub fn remove_path(id: i64) -> String {
    format!("file_database.php?returnwith=4303&removenow={id}")
}

/// Read one text-space channel.
pub fn textspace_path(channel: i64) -> String {
    format!("textspace.php?download={channel}")
}

/// Write one text-space channel.
///
/// The server refuses channel 1 and below outright; it is readable and not
/// writable, which the window says rather than discovering by trying.
pub fn textspace_body(channel: i64, text: &str) -> String {
    format!(
        "upload={channel}&textdata={}",
        values::url_encode(text)
    )
}

/// The body that publishes a file.
///
/// `filesize` is sent because the original sends it, though the endpoint
/// stores nothing from it: a listing measures the stored copy instead.
pub fn upload_body(
    category: &str,
    title: &str,
    version: &str,
    description: &str,
    filename: &str,
    data: &str,
) -> String {
    format!(
        "returnwith=4300&category={}&title={}&filesize={}&version={}&description={}&shortfilename={}&filedata={}",
        values::url_encode(category),
        values::url_encode(title),
        data.len(),
        values::url_encode(version),
        values::url_encode(description),
        values::url_encode(filename),
        values::url_encode(data)
    )
}

/// What the original checks before it will send an upload.
///
/// The endpoint enforces only the filename; the rest of these are the
/// client's manners, and keeping them means an unusable row never reaches
/// the database in the first place.
pub fn check_upload(
    category: &str,
    title: &str,
    description: &str,
    filename: &str,
) -> Result<(), String> {
    if category.trim().is_empty() {
        return Err("Please select a category.".into());
    }
    if title.trim().len() < 3 {
        return Err("Please enter a longer title.".into());
    }
    if description.trim().len() < 4 {
        return Err("Please enter a longer description.".into());
    }
    // The server refuses these too, with a 400 that says less than this does.
    if filename.is_empty() || filename.contains(['/', '\\', ':']) {
        return Err("That file cannot be published under that name.".into());
    }
    Ok(())
}

/// The name a path is published and saved under: the last component, with
/// no directory left on it.
///
/// Both directions need it — an upload sends it and a download writes it —
/// and a row uploaded before the endpoint checked can still carry a path,
/// which must not be allowed to steer where the file lands.
pub fn short_name(path: &str) -> &str {
    path.rsplit(['/', '\\', ':']).next().unwrap_or("").trim()
}

/// Where a downloaded file is written.
///
/// Folded, because that is the name the filesystem will keep it under and
/// this is also what the page tells the player it saved.
pub fn download_target(filename: &str) -> String {
    format!("{DOWNLOAD_DIR}/{}", super::path::fold_case(short_name(filename)))
}

/// Parse a category listing.
///
/// Anything too short to be a record is skipped, which is both what the
/// original does and what keeps the trailing empty piece — every record is
/// terminated rather than separated — out of the results.
pub fn parse_listing(body: &str) -> Vec<Entry> {
    strip_code(body)
        .split(RECORD)
        .filter(|piece| piece.len() > 5)
        .filter_map(parse_entry)
        .collect()
}

/// `id:--:title:--:version:--:size:--:author:--:filename:--:description:--:date:--:time`,
/// with the title, version and description base64'd.
fn parse_entry(record: &str) -> Option<Entry> {
    let fields: Vec<&str> = record.split(FIELD).collect();
    if fields.len() < 9 {
        return None;
    }
    Some(Entry {
        id: fields[0].trim().parse().ok()?,
        title: decode_text(fields[1]),
        version: decode_text(fields[2]),
        size: fields[3].trim().parse().unwrap_or(0),
        author: fields[4].trim().to_string(),
        filename: short_name(fields[5]).to_string(),
        description: decode_text(fields[6]),
        date: fields[7].trim().to_string(),
        time: fields[8].trim().to_string(),
    })
}

/// Parse the player's own uploads: base64'd lines, each terminated by the
/// field separator, each beginning `<id>: `.
pub fn parse_removable(body: &str) -> Vec<Upload> {
    strip_code(body)
        .split(FIELD)
        .filter_map(|piece| {
            let label = decode_text(piece);
            let (id, rest) = label.split_once(':')?;
            Some(Upload { id: id.trim().parse().ok()?, label: rest.trim().to_string() })
        })
        .collect()
}

/// Parse a download: `<filename>:<contents>`.
///
/// The contents may hold colons of its own, so only the first one separates.
pub fn parse_download(body: &str) -> Result<(String, String), String> {
    let text = strip_code(body);
    match text.split_once(':') {
        Some((name, data)) if !short_name(name).is_empty() => {
            Ok((short_name(name).to_string(), data.to_string()))
        }
        // What the original reports as error 8234: an answer with no
        // filename in front of it, which is how a refusal arrives.
        _ => Err(complaint(text, "File download error! (8234)")),
    }
}

/// Parse a text-space channel. An empty channel is an empty string.
pub fn parse_textspace(body: &str) -> String {
    strip_code(body).to_string()
}

/// What the server said about a write, ready to show as it is.
///
/// These endpoints answer in prose — "Upload complete!", "File ID 7 was
/// removed." — so the message is the result, and the only shaping it needs
/// is having PHP's own diagnostics folded into one line.
pub fn message(body: &str, fallback: &str) -> String {
    complaint(strip_code(body), fallback)
}

/// The readable half of a body, or `fallback` when there is nothing in it.
fn complaint(text: &str, fallback: &str) -> String {
    match summary(text) {
        empty if empty.is_empty() => fallback.to_string(),
        said => said,
    }
}

/// Base64 as the server writes it: the URL-safe alphabet, unpadded.
fn decode_text(field: &str) -> String {
    let trimmed = field.trim().trim_end_matches('=');
    if trimmed.is_empty() {
        return String::new();
    }
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

    fn record(id: i64, title: &str, description: &str) -> String {
        format!(
            "{id}:--:{}:--:{}:--:1024:--:alice:--:tool.ds:--:{}:--:05.09.2026:--:11:22:33:--:--:",
            encoded(title),
            encoded("1.2"),
            encoded(description),
        )
    }

    #[test]
    fn a_listing_becomes_entries() {
        let body = format!("4301{}{}", record(7, "Port Scanner", "Scans ports."), record(8, "Cracker", "Cracks."));
        let entries = parse_listing(&body);
        assert_eq!(entries.len(), 2, "the trailing terminator is not a record");
        assert_eq!(
            entries[0],
            Entry {
                id: 7,
                title: "Port Scanner".into(),
                version: "1.2".into(),
                size: 1024,
                author: "alice".into(),
                filename: "tool.ds".into(),
                description: "Scans ports.".into(),
                date: "05.09.2026".into(),
                // The time's own colons survive: only the record separator
                // splits fields.
                time: "11:22:33".into(),
            }
        );
        assert_eq!(entries[1].id, 8);
    }

    #[test]
    fn an_empty_category_lists_nothing() {
        assert!(parse_listing("2000").is_empty());
        assert!(parse_listing("").is_empty());
    }

    #[test]
    fn a_row_that_still_carries_a_path_is_reduced_to_its_name() {
        // Rows predate the endpoint's filename check, so one can hold a path
        // that must not decide where the download is written.
        let body = format!(
            "4301 9:--:{}:--:{}:--:12:--:bob:--:../../system/startup.ds:--:{}:--:05.09.2026:--:01:02:03:--:--:",
            encoded("Sneaky"),
            encoded("1"),
            encoded("."),
        );
        assert_eq!(parse_listing(&body)[0].filename, "startup.ds");
    }

    #[test]
    fn the_players_own_uploads_carry_their_ids() {
        let body = format!(
            "4302{}:--:{}:--:",
            encoded("7: Port Scanner(version 1.2) 05.09.2026"),
            encoded("8: Cracker(version 2) 06.09.2026"),
        );
        assert_eq!(
            parse_removable(&body),
            vec![
                Upload { id: 7, label: "Port Scanner(version 1.2) 05.09.2026".into() },
                Upload { id: 8, label: "Cracker(version 2) 06.09.2026".into() },
            ]
        );
    }

    #[test]
    fn a_download_splits_at_its_first_colon_only() {
        let (name, data) = parse_download("4304notes.ds:Say \"a:b\"").unwrap();
        assert_eq!(name, "notes.ds");
        assert_eq!(data, "Say \"a:b\"");
        assert_eq!(download_target(&name), "/downloads/notes.ds");
        assert_eq!(
            download_target("Port Scanner.DS"),
            "/downloads/port scanner.ds",
            "the name is folded, since that is where the file lands"
        );
    }

    #[test]
    fn a_download_without_a_filename_is_an_error() {
        assert_eq!(parse_download("2000"), Err("File download error! (8234)".into()));
        // A complaint keeps its own words rather than the generic one.
        assert_eq!(parse_download("2000File not found."), Err("File not found.".into()));
    }

    #[test]
    fn a_text_space_channel_is_its_body_without_the_code() {
        assert_eq!(parse_textspace("4501hello\r\nworld"), "hello\r\nworld");
        assert_eq!(parse_textspace("4501"), "", "an unused channel is empty");
    }

    #[test]
    fn a_write_is_reported_in_the_servers_own_words() {
        assert_eq!(message("2000Upload complete!", "Uploaded."), "Upload complete!");
        assert_eq!(message("4500Updated: 7!", "Saved."), "Updated: 7!");
        // A body that is only its status code has nothing to show.
        assert_eq!(message("2000", "Uploaded."), "Uploaded.");
    }

    #[test]
    fn requests_match_the_original_client() {
        assert_eq!(
            list_path("Tools (Hacking)"),
            "file_database.php?returnwith=4301&getcategory=Tools+(Hacking)"
        );
        assert_eq!(download_path(7), "file_database.php?returnwith=4304&getfile=7");
        assert_eq!(remove_path(7), "file_database.php?returnwith=4303&removenow=7");
        assert_eq!(textspace_path(12), "textspace.php?download=12");
        assert_eq!(
            textspace_body(12, "a b"),
            "upload=12&textdata=a+b"
        );
        assert_eq!(
            upload_body("Games", "Snake", "1.0", "A game.", "snake.ds", "Say \"hi\""),
            "returnwith=4300&category=Games&title=Snake&filesize=8&version=1.0\
             &description=A+game.&shortfilename=snake.ds&filedata=Say+%22hi%22"
        );
    }

    #[test]
    fn an_upload_is_checked_the_way_the_original_checks_it() {
        assert_eq!(check_upload("Games", "Snake", "A game.", "snake.ds"), Ok(()));
        assert!(check_upload("", "Snake", "A game.", "snake.ds").is_err());
        assert!(check_upload("Games", "ab", "A game.", "snake.ds").is_err());
        assert!(check_upload("Games", "Snake", "abc", "snake.ds").is_err());
        assert!(check_upload("Games", "Snake", "A game.", "a/b.ds").is_err());
    }

    #[test]
    fn a_name_is_the_last_component_of_a_path() {
        assert_eq!(short_name("/home/tool.ds"), "tool.ds");
        assert_eq!(short_name("\\home\\tool.ds"), "tool.ds");
        assert_eq!(short_name("tool.ds"), "tool.ds");
        assert_eq!(short_name("/home/"), "");
    }
}
