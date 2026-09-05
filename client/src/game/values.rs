//! Value helpers the host API exposes: formatting, conversion and the
//! console's escaping rules.

use crate::value::Value;

/// Inserted between the braces of an escaped `{{`/`}}` so the console does
/// not read it back as markup. The VB6 client uses BEL for this.
pub const INVISIBLE_CHAR: char = '\u{7}';

/// `BoolToString` — despite the name, parses a word into a boolean.
pub fn parse_bool(text: &str) -> Result<bool, String> {
    match text.trim().to_ascii_lowercase().as_str() {
        "on" | "true" | "yes" => Ok(true),
        "off" | "false" | "no" => Ok(false),
        other => Err(format!("Invalid value for boolean: {other}")),
    }
}

/// `TrimWithNewline` — trims spaces, tabs, CR and LF from both ends.
pub fn trim_with_newline(s: &str) -> &str {
    s.trim_matches(|c| c == ' ' || c == '\t' || c == '\r' || c == '\n')
}

/// `IsHex` — true when every character is a hexadecimal digit. An empty
/// string qualifies, matching the VB6 loop that never runs.
pub fn is_hex(s: &str) -> bool {
    s.chars().all(|c| c.is_ascii_hexdigit())
}

/// `FormatKB` — the Win32 `StrFormatByteSize` rendering, which shows three
/// significant digits and keeps whole bytes below 1 KB.
pub fn format_kb(bytes: i64) -> String {
    const UNITS: [&str; 5] = ["KB", "MB", "GB", "TB", "PB"];
    if bytes < 0 {
        // The API takes an unsigned size; negatives wrap the same way.
        return format_kb(bytes as u32 as i64);
    }
    if bytes == 1 {
        return "1 byte".into();
    }
    if bytes < 1024 {
        return format!("{bytes} bytes");
    }

    let mut value = bytes as f64;
    let mut unit = 0;
    value /= 1024.0;
    while value >= 1024.0 && unit + 1 < UNITS.len() {
        value /= 1024.0;
        unit += 1;
    }

    // Three significant digits: 1.00 KB, 10.0 KB, 100 KB.
    let text = if value < 10.0 {
        format!("{:.2}", truncate_to(value, 2))
    } else if value < 100.0 {
        format!("{:.1}", truncate_to(value, 1))
    } else {
        format!("{:.0}", value.trunc())
    };
    format!("{text} {}", UNITS[unit])
}

/// `StrFormatByteSize` truncates rather than rounds, so 1.999 KB shows as
/// 1.99 KB.
fn truncate_to(v: f64, decimals: u32) -> f64 {
    let scale = 10f64.powi(decimals as i32);
    (v * scale).trunc() / scale
}

/// `RGBJoin` — pack three components the way VB's `RGB` does, with red in
/// the low byte.
pub fn rgb_join(r: i64, g: i64, b: i64) -> i32 {
    let clamp = |v: i64| v.clamp(0, 255) as i32;
    clamp(r) | (clamp(g) << 8) | (clamp(b) << 16)
}

/// `RGBSplit` — the inverse of [`rgb_join`].
pub fn rgb_split(color: i32) -> [i32; 3] {
    [color & 0xFF, (color >> 8) & 0xFF, (color >> 16) & 0xFF]
}

/// `URLEncode` — percent-encoding with spaces as `+`, matching
/// `UrlEscape` followed by the client's plus/space swap.
pub fn url_encode(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    for b in s.as_bytes() {
        match b {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'_' | b'.' | b'!' | b'~' | b'*'
            | b'\'' | b'(' | b')' => out.push(*b as char),
            // The client escapes `+` before turning spaces into `+`, so a
            // literal plus survives the round trip.
            b'+' => out.push_str("%2B"),
            b' ' => out.push('+'),
            other => out.push_str(&format!("%{other:02X}")),
        }
    }
    out
}

/// `ConsoleEscape` — make text safe to print by breaking up the `{{` and
/// `}}` markup delimiters.
pub fn console_escape(s: &str) -> String {
    let stripped: String = s.chars().filter(|c| *c != INVISIBLE_CHAR).collect();
    stripped
        .replace("}}", &format!("}}{INVISIBLE_CHAR}}}"))
        .replace("{{", &format!("{{{INVISIBLE_CHAR}{{"))
}

/// `ConsoleUnescape` — drop the invisible characters again.
pub fn console_unescape(s: &str) -> String {
    s.chars().filter(|c| *c != INVISIBLE_CHAR).collect()
}

/// Remove `{{...}}` markup, leaving the text the user actually sees. The
/// real console measures this in pixels; a headless one counts characters.
pub fn strip_markup(s: &str) -> String {
    let mut out = String::new();
    let chars: Vec<char> = s.chars().collect();
    let mut i = 0;
    while i < chars.len() {
        if chars[i] == '{' && chars.get(i + 1) == Some(&'{') {
            // Skip to the closing `}}`, or to the end if it never closes.
            match find_close(&chars, i + 2) {
                Some(end) => {
                    i = end + 2;
                    continue;
                }
                None => break,
            }
        }
        out.push(chars[i]);
        i += 1;
    }
    out
}

fn find_close(chars: &[char], from: usize) -> Option<usize> {
    (from..chars.len().saturating_sub(1))
        .find(|&j| chars[j] == '}' && chars[j + 1] == '}')
}

/// `Coalesce` — the first argument that is not `Empty`, or `Null`.
pub fn coalesce(args: &[Value]) -> Value {
    args.iter()
        .find(|v| !v.is_empty())
        .cloned()
        .unwrap_or(Value::Null)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_boolean_words() {
        for yes in ["on", "TRUE", " yes ", "Yes"] {
            assert_eq!(parse_bool(yes), Ok(true), "{yes}");
        }
        for no in ["off", "FALSE", " no "] {
            assert_eq!(parse_bool(no), Ok(false), "{no}");
        }
        assert!(parse_bool("maybe").is_err());
        assert!(parse_bool("1").is_err(), "only words are accepted");
    }

    #[test]
    fn trims_newlines_as_well_as_spaces() {
        assert_eq!(trim_with_newline(" \r\n\tx y\t\r\n "), "x y");
        assert_eq!(trim_with_newline(" \r\n "), "");
        assert_eq!(trim_with_newline(""), "");
    }

    #[test]
    fn recognises_hex_strings() {
        assert!(is_hex("deadBEEF00"));
        assert!(is_hex(""), "the VB6 loop never runs, so empty is hex");
        assert!(!is_hex("dead beef"));
        assert!(!is_hex("xyz"));
    }

    #[test]
    fn formats_byte_sizes_with_three_significant_digits() {
        assert_eq!(format_kb(0), "0 bytes");
        assert_eq!(format_kb(1), "1 byte");
        assert_eq!(format_kb(999), "999 bytes");
        assert_eq!(format_kb(1023), "1023 bytes");
        assert_eq!(format_kb(1024), "1.00 KB");
        assert_eq!(format_kb(1536), "1.50 KB");
        assert_eq!(format_kb(10 * 1024), "10.0 KB");
        assert_eq!(format_kb(100 * 1024), "100 KB");
        assert_eq!(format_kb(1024 * 1024), "1.00 MB");
        assert_eq!(format_kb(1024 * 1024 * 1024), "1.00 GB");
    }

    #[test]
    fn byte_sizes_truncate_rather_than_round() {
        // 2047 bytes is 1.9990 KB, which must not become 2.00 KB.
        assert_eq!(format_kb(2047), "1.99 KB");
    }

    #[test]
    fn rgb_packs_red_in_the_low_byte() {
        assert_eq!(rgb_join(255, 0, 0), 0x0000FF);
        assert_eq!(rgb_join(0, 255, 0), 0x00FF00);
        assert_eq!(rgb_join(0, 0, 255), 0xFF0000);
        assert_eq!(rgb_split(0xFF8040), [0x40, 0x80, 0xFF]);
        // Round trip.
        for c in [0, 0x123456, 0xFFFFFF] {
            let [r, g, b] = rgb_split(c);
            assert_eq!(rgb_join(r as i64, g as i64, b as i64), c);
        }
    }

    #[test]
    fn rgb_clamps_out_of_range_components() {
        assert_eq!(rgb_join(300, -5, 255), 0xFF00FF);
    }

    #[test]
    fn url_encoding_matches_the_client() {
        assert_eq!(url_encode("hello world"), "hello+world");
        assert_eq!(url_encode("a+b"), "a%2Bb");
        assert_eq!(url_encode("a/b?c=d&e"), "a%2Fb%3Fc%3Dd%26e");
        assert_eq!(url_encode("safe-_.!~*'()"), "safe-_.!~*'()");
        assert_eq!(url_encode(""), "");
    }

    #[test]
    fn console_escaping_breaks_up_markup_delimiters() {
        let escaped = console_escape("{{red}}");
        assert!(escaped.contains(INVISIBLE_CHAR));
        // The escaped form no longer reads as a tag.
        assert!(!escaped.contains("{{"));
        assert!(!escaped.contains("}}"));
        // Unescaping restores the original text.
        assert_eq!(console_unescape(&escaped), "{{red}}");
    }

    #[test]
    fn console_escaping_drops_pre_existing_invisible_characters() {
        let sneaky = format!("{{{INVISIBLE_CHAR}{{red}}}}");
        let escaped = console_escape(&sneaky);
        assert!(!escaped.contains("{{"));
    }

    #[test]
    fn markup_is_stripped_for_measurement() {
        assert_eq!(strip_markup("{{red}}hello{{white}}"), "hello");
        assert_eq!(strip_markup("no markup"), "no markup");
        assert_eq!(strip_markup("a{{b}}c{{d}}e"), "ace");
        // An unterminated tag swallows the rest, as the console does.
        assert_eq!(strip_markup("text{{unclosed"), "text");
    }

    #[test]
    fn coalesce_picks_the_first_non_empty_argument() {
        assert_eq!(coalesce(&[Value::Empty, Value::I2(5)]).to_f64().unwrap(), 5.0);
        assert!(matches!(coalesce(&[]), Value::Null));
        assert!(matches!(coalesce(&[Value::Empty]), Value::Null));
        // Null is a value, so it wins over a later argument.
        assert!(matches!(coalesce(&[Value::Null, Value::I2(1)]), Value::Null));
    }
}
