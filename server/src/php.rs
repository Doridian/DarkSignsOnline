//! The parts of PHP's semantics the endpoints were written against.
//!
//! The server this replaces was PHP, and the clients were written against
//! what it actually did rather than what it meant to do: `(int)"12abc"` is
//! 12, `empty("0")` is true, a request variable called `a.b` arrives as
//! `a_b`, and base64 that is not quite base64 decodes anyway. Each function
//! here is a port of the corresponding piece of php-src 8.4, named for it, so
//! that the endpoints can be read side by side with the PHP they replace.

use std::fmt::Write as _;

/// A PHP value, as far as the endpoints ever look at one: request variables
/// are strings or missing, database columns are ints, strings or NULL.
#[derive(Clone, Debug, PartialEq)]
pub enum Zv {
    Null,
    Int(i64),
    Str(Vec<u8>),
}

impl Zv {
    pub fn str(s: impl AsRef<[u8]>) -> Zv {
        Zv::Str(s.as_ref().to_vec())
    }

    /// `empty($x)`.
    pub fn is_empty(&self) -> bool {
        match self {
            Zv::Null => true,
            Zv::Int(i) => *i == 0,
            Zv::Str(s) => s.is_empty() || s == b"0",
        }
    }

    pub fn is_null(&self) -> bool {
        matches!(self, Zv::Null)
    }

    /// `(int)$x`.
    pub fn to_int(&self) -> i64 {
        match self {
            Zv::Null => 0,
            Zv::Int(i) => *i,
            Zv::Str(s) => intval(s),
        }
    }

    /// `(float)$x`.
    pub fn to_float(&self) -> f64 {
        match self {
            Zv::Null => 0.0,
            Zv::Int(i) => *i as f64,
            Zv::Str(s) => strtod_prefix(s),
        }
    }

    /// The string an `echo` or a `.` makes of it.
    pub fn to_bytes(&self) -> Vec<u8> {
        match self {
            Zv::Null => Vec::new(),
            Zv::Int(i) => i.to_string().into_bytes(),
            Zv::Str(s) => s.clone(),
        }
    }

    /// `$x === 'literal'`.
    pub fn is_str(&self, s: &[u8]) -> bool {
        matches!(self, Zv::Str(v) if v == s)
    }
}

/// `trim()` with its default character list.
pub fn trim(s: &[u8]) -> &[u8] {
    const WS: &[u8] = b" \t\n\r\0\x0B";
    let start = s.iter().position(|c| !WS.contains(c)).unwrap_or(s.len());
    let end = s.iter().rposition(|c| !WS.contains(c)).map_or(start, |i| i + 1);
    &s[start..end]
}

/// `strtolower()`. ASCII only, since PHP 8.2 stopped consulting the locale.
pub fn strtolower(s: &[u8]) -> Vec<u8> {
    s.to_ascii_lowercase()
}

/// `strtoupper()`, likewise.
pub fn strtoupper(s: &[u8]) -> Vec<u8> {
    s.to_ascii_uppercase()
}

/// The byte at `i`, or the NUL terminator every zend_string carries. Ports of
/// C code that reads one past the end rely on finding that NUL there.
fn at(s: &[u8], i: usize) -> u8 {
    s.get(i).copied().unwrap_or(0)
}

fn is_ws(c: u8) -> bool {
    matches!(c, b' ' | b'\t' | b'\n' | b'\r' | 0x0B | 0x0C)
}

/// `(int)$string`: `_is_numeric_string_ex` with errors allowed, then
/// `zend_dval_to_lval_cap` for anything that came out as a double.
pub fn intval(s: &[u8]) -> i64 {
    const MAX_LENGTH_OF_LONG: usize = 20;
    const LONG_MIN_DIGITS: &[u8] = b"9223372036854775808";

    if s.is_empty() {
        return 0;
    }
    let mut str_start = 0;
    while is_ws(at(s, str_start)) {
        str_start += 1;
    }
    let mut ptr = str_start;
    let neg = at(s, ptr) == b'-';
    if neg || at(s, ptr) == b'+' {
        ptr += 1;
    }

    let as_double = |s: &[u8]| dval_to_lval_cap(strtod_prefix(&s[str_start..]));

    if at(s, ptr).is_ascii_digit() {
        while at(s, ptr) == b'0' {
            ptr += 1;
        }
        let mut digits = 0usize;
        let mut tmp: u64 = 0;
        while digits < MAX_LENGTH_OF_LONG {
            let c = at(s, ptr);
            if c.is_ascii_digit() {
                tmp = tmp.wrapping_mul(10).wrapping_add(u64::from(c - b'0'));
                digits += 1;
                ptr += 1;
                continue;
            } else if c == b'.' {
                return as_double(s);
            } else if c == b'e' || c == b'E' {
                let mut e = ptr + 1;
                if at(s, e) == b'-' || at(s, e) == b'+' {
                    ptr = e;
                    e += 1;
                }
                if at(s, e).is_ascii_digit() {
                    return as_double(s);
                }
            }
            break;
        }
        if digits >= MAX_LENGTH_OF_LONG {
            return as_double(s);
        }
        if digits == MAX_LENGTH_OF_LONG - 1 {
            // strcmp against the digits of LONG_MIN, from where the digits
            // began to the terminator, trailing garbage and all.
            let from = &s[ptr - digits..];
            let cmp = cstr_cmp(from, LONG_MIN_DIGITS);
            if !(cmp == std::cmp::Ordering::Less || (cmp == std::cmp::Ordering::Equal && neg)) {
                return as_double(s);
            }
        }
        if neg {
            tmp = tmp.wrapping_neg();
        }
        tmp as i64
    } else if at(s, ptr) == b'.' && at(s, ptr + 1).is_ascii_digit() {
        as_double(s)
    } else {
        0
    }
}

fn cstr_cmp(a: &[u8], b: &[u8]) -> std::cmp::Ordering {
    let cut = |s: &[u8]| s.iter().position(|&c| c == 0).map_or(s, |i| &s[..i]).to_vec();
    cut(a).cmp(&cut(b))
}

fn dval_to_lval_cap(d: f64) -> i64 {
    if !d.is_finite() {
        0
    } else if !(-9.223_372_036_854_776e18..9.223_372_036_854_776e18).contains(&d) {
        if d > 0.0 { i64::MAX } else { i64::MIN }
    } else {
        d as i64
    }
}

/// `zend_strtod` on the longest prefix that is a decimal number, with no
/// leading whitespace skipped. Anything else is 0.
pub fn strtod_prefix(s: &[u8]) -> f64 {
    let mut i = 0;
    if matches!(at(s, i), b'+' | b'-') {
        i += 1;
    }
    let int_start = i;
    while at(s, i).is_ascii_digit() {
        i += 1;
    }
    let mut mantissa_digits = i - int_start;
    if at(s, i) == b'.' {
        let frac_start = i + 1;
        let mut j = frac_start;
        while at(s, j).is_ascii_digit() {
            j += 1;
        }
        if mantissa_digits > 0 || j > frac_start {
            mantissa_digits += j - frac_start;
            i = j;
        }
    }
    if mantissa_digits == 0 {
        return 0.0;
    }
    if matches!(at(s, i), b'e' | b'E') {
        let mut j = i + 1;
        if matches!(at(s, j), b'+' | b'-') {
            j += 1;
        }
        if at(s, j).is_ascii_digit() {
            while at(s, j).is_ascii_digit() {
                j += 1;
            }
            i = j;
        }
    }
    std::str::from_utf8(&s[..i])
        .ok()
        .and_then(|t| t.parse::<f64>().ok())
        .unwrap_or(0.0)
}

/// `base64_encode()`.
pub fn base64_encode(data: &[u8]) -> Vec<u8> {
    const ALPHABET: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let mut out = Vec::with_capacity(data.len().div_ceil(3) * 4);
    for chunk in data.chunks(3) {
        let b = [chunk[0], *chunk.get(1).unwrap_or(&0), *chunk.get(2).unwrap_or(&0)];
        let n = (u32::from(b[0]) << 16) | (u32::from(b[1]) << 8) | u32::from(b[2]);
        out.push(ALPHABET[(n >> 18) as usize & 63]);
        out.push(ALPHABET[(n >> 12) as usize & 63]);
        out.push(if chunk.len() > 1 {
            ALPHABET[(n >> 6) as usize & 63]
        } else {
            b'='
        });
        out.push(if chunk.len() > 2 {
            ALPHABET[n as usize & 63]
        } else {
            b'='
        });
    }
    out
}

/// `base64_decode()` in its default, non-strict mode: padding and anything
/// outside the alphabet are skipped wherever they appear, and a trailing
/// partial sextet is dropped. It never fails.
pub fn base64_decode(data: &[u8]) -> Vec<u8> {
    let mut out = Vec::with_capacity(data.len() / 4 * 3);
    let mut acc: u32 = 0;
    let mut n = 0;
    for &c in data {
        let v = match c {
            b'A'..=b'Z' => c - b'A',
            b'a'..=b'z' => c - b'a' + 26,
            b'0'..=b'9' => c - b'0' + 52,
            b'+' => 62,
            b'/' => 63,
            _ => continue,
        };
        acc = (acc << 6) | u32::from(v);
        n += 1;
        if n == 4 {
            out.extend_from_slice(&[(acc >> 16) as u8, (acc >> 8) as u8, acc as u8]);
            acc = 0;
            n = 0;
        }
    }
    match n {
        2 => out.push((acc >> 4) as u8),
        3 => out.extend_from_slice(&[(acc >> 10) as u8, (acc >> 2) as u8]),
        _ => {}
    }
    out
}

/// The wire format's base64: the URL-safe alphabet with the padding stripped.
pub fn dso_b64_encode(data: &[u8]) -> Vec<u8> {
    base64_encode(data)
        .into_iter()
        .filter(|&c| c != b'=')
        .map(|c| match c {
            b'+' => b'-',
            b'/' => b'_',
            c => c,
        })
        .collect()
}

pub fn dso_b64_decode(data: &[u8]) -> Vec<u8> {
    let std: Vec<u8> = data
        .iter()
        .map(|&c| match c {
            b'-' => b'+',
            b'_' => b'/',
            c => c,
        })
        .collect();
    base64_decode(&std)
}

/// `hash('sha256', ...)`, lower-case hex.
pub fn sha256_hex(data: &[u8]) -> String {
    use sha2::Digest;
    let mut out = String::with_capacity(64);
    for b in sha2::Sha256::digest(data) {
        let _ = write!(out, "{b:02x}");
    }
    out
}

/// `preg_replace("/(\r\n|\r|\n)/", "\r\n", $str)`.
pub fn line_endings_to_dos(s: &[u8]) -> Vec<u8> {
    let mut out = Vec::with_capacity(s.len());
    let mut i = 0;
    while i < s.len() {
        match s[i] {
            b'\r' => {
                out.extend_from_slice(b"\r\n");
                if at(s, i + 1) == b'\n' {
                    i += 1;
                }
            }
            b'\n' => out.extend_from_slice(b"\r\n"),
            c => out.push(c),
        }
        i += 1;
    }
    out
}

/// `explode()` with no limit.
pub fn explode<'a>(sep: &[u8], s: &'a [u8]) -> Vec<&'a [u8]> {
    let mut parts = Vec::new();
    let mut rest = s;
    while let Some(i) = find(rest, sep) {
        parts.push(&rest[..i]);
        rest = &rest[i + sep.len()..];
    }
    parts.push(rest);
    parts
}

/// `strpos()`.
pub fn find(hay: &[u8], needle: &[u8]) -> Option<usize> {
    if needle.is_empty() {
        return Some(0);
    }
    hay.windows(needle.len()).position(|w| w == needle)
}

/// Cut at the first `\r` and then at the first `\n`, the way the subject
/// and line filters do it.
pub fn first_line(s: &[u8]) -> &[u8] {
    let s = s.iter().position(|&c| c == b'\r').map_or(s, |i| &s[..i]);
    s.iter().position(|&c| c == b'\n').map_or(s, |i| &s[..i])
}

/// `php_url_decode`: `+` is a space and `%XX` a byte; a `%` that is not
/// followed by two hex digits is itself.
pub fn url_decode(s: &[u8]) -> Vec<u8> {
    let mut out = Vec::with_capacity(s.len());
    let mut i = 0;
    while i < s.len() {
        let c = s[i];
        if c == b'+' {
            out.push(b' ');
        } else if c == b'%' && i + 2 < s.len() && s[i + 1].is_ascii_hexdigit() && s[i + 2].is_ascii_hexdigit() {
            out.push(hex(s[i + 1]) << 4 | hex(s[i + 2]));
            i += 2;
        } else {
            out.push(c);
        }
        i += 1;
    }
    out
}

fn hex(c: u8) -> u8 {
    match c {
        b'0'..=b'9' => c - b'0',
        b'a'..=b'f' => c - b'a' + 10,
        _ => c - b'A' + 10,
    }
}

/// The days-since-epoch to civil date conversion behind `date()`/`gmdate()`.
/// The site's PHP never set `date.timezone`, which leaves it UTC, so both
/// spellings mean the same thing here.
fn civil(ts: i64) -> (i64, u32, u32, u32, u32, u32) {
    let days = ts.div_euclid(86400);
    let secs = ts.rem_euclid(86400);
    let z = days + 719_468;
    let era = z.div_euclid(146_097);
    let doe = z - era * 146_097;
    let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146_096) / 365;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = (doy - (153 * mp + 2) / 5 + 1) as u32;
    let m = if mp < 10 { mp + 3 } else { mp - 9 } as u32;
    let y = yoe + era * 400 + i64::from(m <= 2);
    (
        y,
        m,
        d,
        (secs / 3600) as u32,
        (secs / 60 % 60) as u32,
        (secs % 60) as u32,
    )
}

/// `date()` for the handful of format characters the endpoints use.
pub fn date(fmt: &str, ts: i64) -> String {
    let (y, m, d, h, i, s) = civil(ts);
    let mut out = String::new();
    for c in fmt.chars() {
        let _ = match c {
            'd' => write!(out, "{d:02}"),
            'm' => write!(out, "{m:02}"),
            'Y' if y < 0 => write!(out, "-{:04}", -y),
            'Y' => write!(out, "{y:04}"),
            'H' => write!(out, "{h:02}"),
            'i' => write!(out, "{i:02}"),
            's' => write!(out, "{s:02}"),
            c => write!(out, "{c}"),
        };
    }
    out
}

/// `json_encode($string)` with `JSON_UNESCAPED_SLASHES` and nothing else:
/// everything outside ASCII as `\u` escapes, and `None` where PHP gives up
/// on a string that is not UTF-8.
pub fn json_encode_str(s: &[u8]) -> Option<String> {
    let s = std::str::from_utf8(s).ok()?;
    let mut out = String::with_capacity(s.len() + 2);
    out.push('"');
    for c in s.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\u{8}' => out.push_str("\\b"),
            '\u{c}' => out.push_str("\\f"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            c if (c as u32) < 0x20 || (c as u32) > 0x7F => {
                let mut buf = [0u16; 2];
                for unit in c.encode_utf16(&mut buf) {
                    let _ = write!(out, "\\u{unit:04x}");
                }
            }
            c => out.push(c),
        }
    }
    out.push('"');
    Some(out)
}

/// The replacement half of `preg_replace()`: `\N`, `$N` and `${N}` (one or
/// two digits) are back-references, a reference to a group that does not
/// exist is empty, and a backslash before `\` or `$` escapes it.
///
/// `groups` holds the match and its captures, `None` for a group that did
/// not take part.
pub fn preg_expand(replacement: &[u8], groups: &[Option<&[u8]>], out: &mut Vec<u8>) {
    let mut walk = 0;
    let mut walk_last: u8 = 0;
    while walk < replacement.len() {
        let c = replacement[walk];
        if c == b'\\' || c == b'$' {
            if walk_last == b'\\' {
                *out.last_mut().expect("walk_last implies a byte was written") = c;
                walk += 1;
                walk_last = 0;
                continue;
            }
            if let Some((backref, next)) = preg_get_backref(replacement, walk) {
                if let Some(Some(g)) = groups.get(backref) {
                    out.extend_from_slice(g);
                }
                walk = next;
                continue;
            }
        }
        out.push(c);
        walk += 1;
        walk_last = c;
    }
}

fn preg_get_backref(s: &[u8], start: usize) -> Option<(usize, usize)> {
    let mut walk = start;
    if at(s, walk + 1) == 0 {
        return None;
    }
    let in_brace = s[walk] == b'$' && at(s, walk + 1) == b'{';
    if in_brace {
        walk += 1;
    }
    walk += 1;
    let mut backref = match at(s, walk) {
        c @ b'0'..=b'9' => usize::from(c - b'0'),
        _ => return None,
    };
    walk += 1;
    if let c @ b'0'..=b'9' = at(s, walk) {
        backref = backref * 10 + usize::from(c - b'0');
        walk += 1;
    }
    if in_brace {
        if at(s, walk) != b'}' {
            return None;
        }
        walk += 1;
    }
    Some((backref, walk))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn intval_matches_php() {
        let cases: &[(&[u8], i64)] = &[
            (b"", 0),
            (b"12", 12),
            (b"  12abc", 12),
            (b"\n\t-7", -7),
            (b"+5", 5),
            (b"abc", 0),
            (b"1e3", 1000),
            (b"1.9", 1),
            (b"-1.9", -1),
            (b".5", 0),
            (b"0x1A", 0),
            (b"007", 7),
            (b"9223372036854775807", i64::MAX),
            (b"9223372036854775808", i64::MAX),
            (b"-9223372036854775808", i64::MIN),
            (b"-9223372036854775809", i64::MIN),
            (b"99999999999999999999999", i64::MAX),
            (b"1e400", 0),
            (b"5e-x", 5),
            (b"1 ", 1),
            (b" ", 0),
        ];
        for (s, want) in cases {
            assert_eq!(intval(s), *want, "intval({:?})", String::from_utf8_lossy(s));
        }
    }

    #[test]
    fn base64_decode_is_lenient() {
        assert_eq!(base64_decode(b"aGVsbG8="), b"hello");
        assert_eq!(base64_decode(b"aGVs bG8"), b"hello");
        assert_eq!(base64_decode(b"aG=Vsb!G8"), b"hello");
        assert_eq!(base64_decode(b"a"), b"");
        assert_eq!(dso_b64_encode(b"\xfb\xff"), b"-_8");
        assert_eq!(dso_b64_decode(b"-_8"), b"\xfb\xff");
    }

    #[test]
    fn replacement_backrefs() {
        let groups: &[Option<&[u8]>] = &[Some(b"FILESERVER("), Some(b"FILESERVER(")];
        let mut out = Vec::new();
        preg_expand(b"$1KEY, a$1b.com, ", groups, &mut out);
        assert_eq!(out, b"FILESERVER(KEY, aFILESERVER(b.com, ");
        out.clear();
        preg_expand(b"\\\\$1 ${1}x $12 \\$1 $", groups, &mut out);
        assert_eq!(out, b"\\FILESERVER( FILESERVER(x  $1 $");
    }

    #[test]
    fn dates_are_utc() {
        assert_eq!(date("d.m.Y H:i:s", 0), "01.01.1970 00:00:00");
        assert_eq!(date("Y-m-d H:i:s", 1_792_584_000), "2026-10-21 12:00:00");
        assert_eq!(date("d.m.Y", 951_782_400), "29.02.2000");
    }
}
