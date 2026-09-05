//! String built-ins.
//!
//! VBScript strings are UTF-16, which the `*B` variants expose directly, so
//! those functions work on the little-endian byte image of the string.

use std::cmp::Ordering;
use std::rc::Rc;

use crate::error::{err, VbResult};
use crate::value::{compare_str, Value};

pub fn utf16(s: &str) -> Vec<u16> {
    s.encode_utf16().collect()
}

pub fn from_utf16(v: &[u16]) -> String {
    String::from_utf16_lossy(v)
}

/// The little-endian byte image, as `LenB` and friends see it.
pub fn bytes_of(s: &str) -> Vec<u8> {
    let mut out = Vec::with_capacity(s.len() * 2);
    for u in s.encode_utf16() {
        out.push((u & 0xFF) as u8);
        out.push((u >> 8) as u8);
    }
    out
}

pub fn from_bytes(b: &[u8]) -> String {
    let mut units = Vec::with_capacity(b.len().div_ceil(2));
    let mut i = 0;
    while i < b.len() {
        let lo = b[i] as u16;
        let hi = *b.get(i + 1).unwrap_or(&0) as u16;
        units.push(lo | (hi << 8));
        i += 2;
    }
    from_utf16(&units)
}

pub fn len(v: &Value) -> VbResult<Value> {
    if v.is_null() {
        return Ok(Value::Null);
    }
    Ok(Value::I4(utf16(&v.to_vb_string()?).len() as i32))
}

pub fn lenb(v: &Value) -> VbResult<Value> {
    if v.is_null() {
        return Ok(Value::Null);
    }
    Ok(Value::I4(bytes_of(&v.to_vb_string()?).len() as i32))
}

pub fn left(v: &Value, n: i32, byte_mode: bool) -> VbResult<Value> {
    // The count is validated before the subject, so `Left(Null, -1)` is an
    // invalid argument rather than Null.
    if n < 0 {
        return Err(err::invalid_call());
    }
    if v.is_null() {
        return Ok(Value::Null);
    }
    let s = v.to_vb_string()?;
    Ok(Value::str(if byte_mode {
        let b = bytes_of(&s);
        from_bytes(&b[..(n as usize).min(b.len())])
    } else {
        let u = utf16(&s);
        from_utf16(&u[..(n as usize).min(u.len())])
    }))
}

pub fn right(v: &Value, n: i32, byte_mode: bool) -> VbResult<Value> {
    if n < 0 {
        return Err(err::invalid_call());
    }
    if v.is_null() {
        return Ok(Value::Null);
    }
    let s = v.to_vb_string()?;
    Ok(Value::str(if byte_mode {
        let b = bytes_of(&s);
        let take = (n as usize).min(b.len());
        from_bytes(&b[b.len() - take..])
    } else {
        let u = utf16(&s);
        let take = (n as usize).min(u.len());
        from_utf16(&u[u.len() - take..])
    }))
}

pub fn mid(v: &Value, start: i32, count: Option<i32>, byte_mode: bool) -> VbResult<Value> {
    // Positions are checked before the subject, so `Mid(Null, -1, -1)` is an
    // invalid argument rather than Null.
    if start < 1 {
        return Err(err::invalid_call());
    }
    if let Some(c) = count {
        if c < 0 {
            return Err(err::invalid_call());
        }
    }
    if v.is_null() {
        return Ok(Value::Null);
    }
    let s = v.to_vb_string()?;
    let take_from = |units: &[u16]| -> Vec<u16> {
        let from = (start as usize - 1).min(units.len());
        let avail = units.len() - from;
        let take = count.map(|c| (c as usize).min(avail)).unwrap_or(avail);
        units[from..from + take].to_vec()
    };
    Ok(Value::str(if byte_mode {
        let b = bytes_of(&s);
        let from = (start as usize - 1).min(b.len());
        let avail = b.len() - from;
        let take = count.map(|c| (c as usize).min(avail)).unwrap_or(avail);
        from_bytes(&b[from..from + take])
    } else {
        from_utf16(&take_from(&utf16(&s)))
    }))
}

fn cmp_mode(compare: i32) -> VbResult<bool> {
    match compare {
        0 => Ok(false),
        1 => Ok(true),
        _ => Err(err::invalid_call()),
    }
}

/// `InStr`, returning a 1-based position or 0.
pub fn instr(start: i32, hay: &Value, needle: &Value, compare: i32) -> VbResult<Value> {
    if hay.is_null() || needle.is_null() {
        return Ok(Value::Null);
    }
    if start < 1 {
        return Err(err::invalid_call());
    }
    let text = cmp_mode(compare)?;
    let h = utf16(&hay.to_vb_string()?);
    let n = utf16(&needle.to_vb_string()?);
    let from = start as usize - 1;
    if from >= h.len() {
        return Ok(Value::I4(0));
    }
    // An empty needle matches at the starting position.
    if n.is_empty() {
        return Ok(Value::I4(start));
    }
    Ok(Value::I4(match find_utf16(&h[from..], &n, text) {
        Some(i) => (from + i + 1) as i32,
        None => 0,
    }))
}

pub fn instrb(start: i32, hay: &Value, needle: &Value, compare: i32) -> VbResult<Value> {
    // Byte positions are simply character positions doubled, minus the
    // one-based offset adjustment.
    let r = instr((start + 1) / 2, hay, needle, compare)?;
    Ok(match r {
        Value::I4(0) => Value::I4(0),
        Value::I4(p) => Value::I4(p * 2 - 1),
        other => other,
    })
}

pub fn instrrev(hay: &Value, needle: &Value, start: i32, compare: i32) -> VbResult<Value> {
    // Unlike InStr, InStrRev rejects Null rather than propagating it.
    if hay.is_null() || needle.is_null() {
        return Err(err::invalid_use_of_null());
    }
    if start == 0 || start < -1 {
        return Err(err::invalid_call());
    }
    let text = cmp_mode(compare)?;
    let h = utf16(&hay.to_vb_string()?);
    let n = utf16(&needle.to_vb_string()?);
    // -1 means "search from the end".
    let end = if start == -1 { h.len() } else { start as usize };
    if end > h.len() {
        return Ok(Value::I4(0));
    }
    if n.is_empty() {
        return Ok(Value::I4(end as i32));
    }
    if n.len() > end {
        return Ok(Value::I4(0));
    }
    for i in (0..=end - n.len()).rev() {
        if eq_utf16(&h[i..i + n.len()], &n, text) {
            return Ok(Value::I4(i as i32 + 1));
        }
    }
    Ok(Value::I4(0))
}

fn eq_utf16(a: &[u16], b: &[u16], text: bool) -> bool {
    if a.len() != b.len() {
        return false;
    }
    if !text {
        return a == b;
    }
    a.iter().zip(b).all(|(x, y)| upper16(*x) == upper16(*y))
}

fn upper16(u: u16) -> u16 {
    char::from_u32(u as u32)
        .map(|c| c.to_ascii_uppercase() as u32 as u16)
        .unwrap_or(u)
}

fn find_utf16(hay: &[u16], needle: &[u16], text: bool) -> Option<usize> {
    if needle.len() > hay.len() {
        return None;
    }
    (0..=hay.len() - needle.len()).find(|&i| eq_utf16(&hay[i..i + needle.len()], needle, text))
}

pub fn ucase(v: &Value) -> VbResult<Value> {
    if v.is_null() {
        return Ok(Value::Null);
    }
    Ok(Value::str(v.to_vb_string()?.to_uppercase()))
}

pub fn lcase(v: &Value) -> VbResult<Value> {
    if v.is_null() {
        return Ok(Value::Null);
    }
    Ok(Value::str(v.to_vb_string()?.to_lowercase()))
}

pub fn trim(v: &Value, left_side: bool, right_side: bool) -> VbResult<Value> {
    if v.is_null() {
        return Ok(Value::Null);
    }
    let s = v.to_vb_string()?;
    // VBScript trims spaces only, not tabs or newlines.
    let mut t: &str = &s;
    if left_side {
        t = t.trim_start_matches(' ');
    }
    if right_side {
        t = t.trim_end_matches(' ');
    }
    Ok(Value::str(t))
}

pub fn space(n: i32) -> VbResult<Value> {
    if n < 0 {
        return Err(err::invalid_call());
    }
    Ok(Value::str(" ".repeat(n as usize)))
}

pub fn string_fn(n: i32, ch: &Value) -> VbResult<Value> {
    if n < 0 {
        return Err(err::invalid_call());
    }
    if ch.is_null() {
        return Ok(Value::Null);
    }
    // The character argument may be a code point or a string.
    let c: u16 = match ch {
        Value::Str(s) => match utf16(s).first() {
            Some(u) => *u,
            None => return Err(err::invalid_call()),
        },
        _ => {
            let code = ch.to_f64()?;
            if !(-32768.0..=65535.0).contains(&code) {
                return Err(err::overflow());
            }
            (code as i64 as u16) & 0xFF
        }
    };
    Ok(Value::str(from_utf16(&vec![c; n as usize])))
}

pub fn strreverse(v: &Value) -> VbResult<Value> {
    if v.is_null() {
        return Err(err::invalid_use_of_null());
    }
    let s = v.to_vb_string()?;
    let mut u = utf16(&s);
    u.reverse();
    Ok(Value::str(from_utf16(&u)))
}

pub fn strcomp(a: &Value, b: &Value, compare: i32) -> VbResult<Value> {
    if a.is_null() || b.is_null() {
        return Ok(Value::Null);
    }
    let text = cmp_mode(compare)?;
    let x = a.to_vb_string()?;
    let y = b.to_vb_string()?;
    Ok(Value::I2(match compare_str(&x, &y, text) {
        Ordering::Less => -1,
        Ordering::Equal => 0,
        Ordering::Greater => 1,
    }))
}

pub fn replace(
    expr: &Value,
    find: &Value,
    repl: &Value,
    start: i32,
    count: i32,
    compare: i32,
) -> VbResult<Value> {
    if expr.is_null() || find.is_null() || repl.is_null() {
        return Err(err::invalid_use_of_null());
    }
    if start < 1 || count < -1 {
        return Err(err::invalid_call());
    }
    let text = cmp_mode(compare)?;
    let s = utf16(&expr.to_vb_string()?);
    let f = utf16(&find.to_vb_string()?);
    let r = utf16(&repl.to_vb_string()?);

    let from = (start as usize - 1).min(s.len());
    // The result starts at `start`, dropping anything before it.
    let mut out: Vec<u16> = Vec::new();
    if f.is_empty() || count == 0 {
        return Ok(Value::str(from_utf16(&s[from..])));
    }
    let mut i = from;
    let mut done = 0i32;
    while i < s.len() {
        if (count < 0 || done < count) && i + f.len() <= s.len() && eq_utf16(&s[i..i + f.len()], &f, text)
        {
            out.extend_from_slice(&r);
            i += f.len();
            done += 1;
        } else {
            out.push(s[i]);
            i += 1;
        }
    }
    Ok(Value::str(from_utf16(&out)))
}

pub fn split(expr: &Value, delim: &Value, count: i32, compare: i32) -> VbResult<Vec<Value>> {
    if expr.is_null() {
        return Err(err::invalid_use_of_null());
    }
    if count < -1 {
        return Err(err::invalid_call());
    }
    let text = cmp_mode(compare)?;
    let s = utf16(&expr.to_vb_string()?);
    let d = utf16(&delim.to_vb_string()?);
    if count == 0 {
        return Ok(Vec::new());
    }
    // An empty delimiter yields the whole string as one element.
    if d.is_empty() {
        return Ok(vec![Value::str(from_utf16(&s))]);
    }
    // Splitting an empty string produces no elements at all.
    if s.is_empty() {
        return Ok(Vec::new());
    }
    let mut out = Vec::new();
    let mut i = 0usize;
    let mut piece_start = 0usize;
    while i < s.len() {
        let last = count > 0 && out.len() as i32 == count - 1;
        if !last && i + d.len() <= s.len() && eq_utf16(&s[i..i + d.len()], &d, text) {
            out.push(Value::str(from_utf16(&s[piece_start..i])));
            i += d.len();
            piece_start = i;
        } else {
            i += 1;
        }
    }
    out.push(Value::str(from_utf16(&s[piece_start..])));
    Ok(out)
}

pub fn join(items: &[Value], delim: &str) -> VbResult<Value> {
    let mut out = String::new();
    for (i, v) in items.iter().enumerate() {
        if i > 0 {
            out.push_str(delim);
        }
        // An element that has no string form — Null or a nested array —
        // makes the whole call a type mismatch.
        match v {
            Value::Null | Value::Array(_) => return Err(err::type_mismatch()),
            _ => out.push_str(&v.to_vb_string()?),
        }
    }
    Ok(Value::str(out))
}

pub fn filter(
    items: &[Value],
    needle: &Value,
    include: bool,
    compare: i32,
) -> VbResult<Vec<Value>> {
    let text = cmp_mode(compare)?;
    let n = utf16(&needle.to_vb_string()?);
    let mut out = Vec::new();
    for v in items {
        if v.is_null() {
            return Err(err::invalid_use_of_null());
        }
        let h = utf16(&v.to_vb_string()?);
        let hit = if n.is_empty() { true } else { find_utf16(&h, &n, text).is_some() };
        if hit == include {
            out.push(v.clone());
        }
    }
    Ok(out)
}

/// JScript's `escape`: `%XX` for Latin-1, `%uXXXX` above it.
pub fn escape(v: &Value) -> VbResult<Value> {
    if v.is_null() {
        return Err(err::invalid_use_of_null());
    }
    let s = v.to_vb_string()?;
    let mut out = String::new();
    for u in s.encode_utf16() {
        let c = u as u32;
        let keep = matches!(c,
            0x41..=0x5A | 0x61..=0x7A | 0x30..=0x39)
            || matches!(c as u8 as char, '@' | '*' | '_' | '+' | '-' | '.' | '/')
                && c < 0x80;
        if keep {
            out.push(char::from_u32(c).unwrap());
        } else if c < 0x100 {
            out.push_str(&format!("%{c:02X}"));
        } else {
            out.push_str(&format!("%u{c:04X}"));
        }
    }
    Ok(Value::str(out))
}

pub fn unescape(v: &Value) -> VbResult<Value> {
    if v.is_null() {
        return Err(err::invalid_use_of_null());
    }
    let s = v.to_vb_string()?;
    let u = utf16(&s);
    let mut out: Vec<u16> = Vec::new();
    let mut i = 0;
    while i < u.len() {
        if u[i] == b'%' as u16 {
            // `%uXXXX` first, since it is longer.
            if i + 5 < u.len() && (u[i + 1] == b'u' as u16 || u[i + 1] == b'U' as u16) {
                if let Some(v) = hex4(&u[i + 2..i + 6]) {
                    out.push(v);
                    i += 6;
                    continue;
                }
            }
            if i + 2 < u.len() {
                if let Some(v) = hex4(&u[i + 1..i + 3]) {
                    out.push(v);
                    i += 3;
                    continue;
                }
            }
        }
        out.push(u[i]);
        i += 1;
    }
    Ok(Value::str(from_utf16(&out)))
}

fn hex4(units: &[u16]) -> Option<u16> {
    let mut v: u32 = 0;
    for &u in units {
        let c = char::from_u32(u as u32)?;
        v = v * 16 + c.to_digit(16)?;
    }
    Some(v as u16)
}

pub fn ascb(v: &Value) -> VbResult<Value> {
    if v.is_null() {
        return Err(err::invalid_use_of_null());
    }
    let s = v.to_vb_string()?;
    match bytes_of(&s).first() {
        Some(x) => Ok(Value::UI1(*x)),
        None => Err(err::invalid_call()),
    }
}

pub fn chrb(v: &Value) -> VbResult<Value> {
    if v.is_null() {
        return Ok(Value::Null);
    }
    let n = v.to_f64()?;
    let r = crate::value::round_half_even(n);
    // ChrB takes a byte, so anything outside 0..255 overflows.
    if !(0.0..=255.0).contains(&r) {
        return Err(err::overflow());
    }
    Ok(Value::Str(Rc::from(from_bytes(&[r as u8]).as_str())))
}
