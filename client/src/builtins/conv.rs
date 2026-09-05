//! Type-conversion built-ins.

use std::rc::Rc;

use crate::error::{err, VbResult};
use crate::value::{parse_number, round_half_even, Value, CY_SCALE};

/// Largest magnitude a Currency can hold.
const CY_MAX: f64 = 922_337_203_685_477.6;

/// Numeric value for a conversion function: `Null` propagates, and a string
/// that does not parse is a type mismatch rather than zero.
fn num(v: &Value) -> VbResult<Option<f64>> {
    match v {
        // Every Cxxx conversion rejects Null rather than passing it through.
        Value::Null => Err(err::invalid_use_of_null()),
        Value::Str(s) => match parse_number(s) {
            Some(n) => Ok(Some(n)),
            None => Err(err::type_mismatch()),
        },
        _ => Ok(Some(v.to_f64()?)),
    }
}

pub fn cint(v: &Value) -> VbResult<Value> {
    let n = match num(v)? {
        None => return Ok(Value::Null),
        Some(n) => n,
    };
    let r = round_half_even(n);
    if r < i16::MIN as f64 || r > i16::MAX as f64 {
        return Err(err::overflow());
    }
    Ok(Value::I2(r as i16))
}

pub fn clng(v: &Value) -> VbResult<Value> {
    let n = match num(v)? {
        None => return Ok(Value::Null),
        Some(n) => n,
    };
    let r = round_half_even(n);
    if r < i32::MIN as f64 || r > i32::MAX as f64 {
        return Err(err::overflow());
    }
    Ok(Value::I4(r as i32))
}

pub fn cbyte(v: &Value) -> VbResult<Value> {
    // True is -1, whose byte pattern is 255.
    if let Value::Bool(b) = v {
        return Ok(Value::UI1(if *b { 255 } else { 0 }));
    }
    let n = match num(v)? {
        None => return Ok(Value::Null),
        Some(n) => n,
    };
    let r = round_half_even(n);
    if !(0.0..=255.0).contains(&r) {
        return Err(err::overflow());
    }
    Ok(Value::UI1(r as u8))
}

pub fn cbool(v: &Value) -> VbResult<Value> {
    match v {
        Value::Null => Err(err::invalid_use_of_null()),
        Value::Str(s) => {
            // The literal words convert, optionally in the `#TRUE#` form
            // that Automation also accepts.
            let t = s.trim();
            let t = t.strip_prefix('#').and_then(|r| r.strip_suffix('#')).unwrap_or(t);
            if t.eq_ignore_ascii_case("true") {
                return Ok(Value::Bool(true));
            }
            if t.eq_ignore_ascii_case("false") {
                return Ok(Value::Bool(false));
            }
            match parse_number(s) {
                Some(n) => Ok(Value::Bool(n != 0.0)),
                None => Err(err::type_mismatch()),
            }
        }
        _ => Ok(Value::Bool(v.to_f64()? != 0.0)),
    }
}

pub fn csng(v: &Value) -> VbResult<Value> {
    let n = match num(v)? {
        None => return Ok(Value::Null),
        Some(n) => n,
    };
    let f = n as f32;
    if !f.is_finite() {
        return Err(err::overflow());
    }
    Ok(Value::R4(f))
}

pub fn cdbl(v: &Value) -> VbResult<Value> {
    match num(v)? {
        None => Ok(Value::Null),
        Some(n) => Ok(Value::R8(n)),
    }
}

pub fn ccur(v: &Value) -> VbResult<Value> {
    let n = match num(v)? {
        None => return Ok(Value::Null),
        Some(n) => n,
    };
    if !n.is_finite() || n.abs() > CY_MAX {
        return Err(err::overflow());
    }
    // Currency keeps exactly four decimal places.
    let scaled = round_half_even(n * CY_SCALE as f64);
    Ok(Value::Cy(scaled as i64))
}

pub fn cstr(v: &Value) -> VbResult<Value> {
    match v {
        Value::Null => Err(err::invalid_use_of_null()),
        _ => Ok(Value::Str(v.to_vb_string()?)),
    }
}

/// `Int` rounds toward negative infinity and keeps the operand's type.
pub fn int(v: &Value) -> VbResult<Value> {
    same_type_round(v, f64::floor)
}

/// `Fix` truncates toward zero.
pub fn fix(v: &Value) -> VbResult<Value> {
    same_type_round(v, f64::trunc)
}

fn same_type_round(v: &Value, f: fn(f64) -> f64) -> VbResult<Value> {
    match v {
        Value::Null => Ok(Value::Null),
        Value::Empty => Ok(Value::I2(0)),
        Value::I2(_) | Value::I4(_) | Value::UI1(_) => Ok(v.clone()),
        Value::Bool(b) => Ok(Value::I2(if *b { -1 } else { 0 })),
        Value::R4(x) => Ok(Value::R4(f(*x as f64) as f32)),
        Value::R8(x) => Ok(Value::R8(f(*x))),
        Value::Date(x) => Ok(Value::Date(f(*x))),
        Value::Cy(x) => {
            let n = *x as f64 / CY_SCALE as f64;
            Ok(Value::Cy((f(n) * CY_SCALE as f64) as i64))
        }
        Value::Str(s) => {
            let n = parse_number(s).ok_or_else(err::type_mismatch)?;
            Ok(Value::R8(f(n)))
        }
        _ => Err(err::type_mismatch()),
    }
}

/// `Round(x[, digits])` uses banker's rounding.
pub fn round(v: &Value, digits: i32) -> VbResult<Value> {
    if v.is_null() {
        return Ok(Value::Null);
    }
    if !(0..=20).contains(&digits) {
        return Err(err::invalid_call());
    }
    match v {
        Value::I2(_) | Value::I4(_) | Value::UI1(_) | Value::Empty | Value::Bool(_) => {
            Ok(v.clone())
        }
        Value::Cy(x) => {
            let scale = 10f64.powi(digits.min(4));
            let n = *x as f64 / CY_SCALE as f64;
            let r = round_half_even(n * scale) / scale;
            Ok(Value::Cy(round_half_even(r * CY_SCALE as f64) as i64))
        }
        _ => {
            let n = v.to_f64()?;
            let scale = 10f64.powi(digits);
            let r = round_half_even(n * scale) / scale;
            match v {
                Value::R4(_) => Ok(Value::R4(r as f32)),
                _ => Ok(Value::R8(r)),
            }
        }
    }
}

pub fn sgn(v: &Value) -> VbResult<Value> {
    if v.is_null() {
        return Err(err::invalid_use_of_null());
    }
    let n = v.to_f64()?;
    Ok(Value::I2(if n > 0.0 {
        1
    } else if n < 0.0 {
        -1
    } else {
        0
    }))
}

pub fn abs(v: &Value) -> VbResult<Value> {
    match v {
        Value::Null => Ok(Value::Null),
        Value::Empty => Ok(Value::I2(0)),
        Value::UI1(_) => Ok(v.clone()),
        Value::Bool(b) => Ok(Value::I2(if *b { 1 } else { 0 })),
        Value::I2(x) => match x.checked_abs() {
            Some(a) => Ok(Value::I2(a)),
            // Abs(-32768) does not fit in an Integer.
            None => Ok(Value::I4(-(*x as i32))),
        },
        Value::I4(x) => match x.checked_abs() {
            Some(a) => Ok(Value::I4(a)),
            None => Ok(Value::R8(-(*x as f64))),
        },
        Value::R4(x) => Ok(Value::R4(x.abs())),
        Value::R8(x) => Ok(Value::R8(x.abs())),
        Value::Date(x) => Ok(Value::Date(x.abs())),
        Value::Cy(x) => match x.checked_abs() {
            Some(a) => Ok(Value::Cy(a)),
            None => Err(err::overflow()),
        },
        Value::Str(s) => {
            let n = parse_number(s).ok_or_else(err::type_mismatch)?;
            Ok(Value::R8(n.abs()))
        }
        _ => Err(err::type_mismatch()),
    }
}

pub fn hex(v: &Value) -> VbResult<Value> {
    if v.is_null() {
        return Ok(Value::Null);
    }
    if v.is_empty() {
        return Ok(Value::str("0"));
    }
    let (n, wide) = int_for_radix(v)?;
    Ok(Value::str(if wide {
        format!("{:X}", n as u32)
    } else {
        format!("{:X}", n as u16)
    }))
}

pub fn oct(v: &Value) -> VbResult<Value> {
    if v.is_null() {
        return Ok(Value::Null);
    }
    if v.is_empty() {
        return Ok(Value::str("0"));
    }
    let (n, wide) = int_for_radix(v)?;
    Ok(Value::str(if wide {
        format!("{:o}", n as u32)
    } else {
        format!("{:o}", n as u16)
    }))
}

/// Hex/Oct print 16 bits for Integer-sized inputs and 32 bits otherwise.
fn int_for_radix(v: &Value) -> VbResult<(i32, bool)> {
    let wide = !matches!(v, Value::I2(_) | Value::UI1(_) | Value::Bool(_));
    let n = match v {
        Value::Str(s) => parse_number(s).ok_or_else(err::type_mismatch)?,
        _ => v.to_f64()?,
    };
    let r = round_half_even(n);
    // The argument is converted to a Long first, so anything outside that
    // range overflows rather than wrapping.
    if r < i32::MIN as f64 || r > i32::MAX as f64 {
        return Err(err::overflow());
    }
    let as_i32 = r as i32;
    // A value outside Integer range must print as 32 bits even if the source
    // type was narrow.
    let wide = wide || as_i32 < i16::MIN as i32 || as_i32 > i16::MAX as i32;
    Ok((as_i32, wide))
}

pub fn asc(v: &Value, wide: bool) -> VbResult<Value> {
    let s = v.to_vb_string()?;
    let c = s.chars().next().ok_or_else(err::invalid_call)?;
    if wide {
        // AscW returns the UTF-16 code unit, signed.
        let u = c as u32;
        let u = if u > 0xFFFF { 0xFFFD } else { u };
        Ok(Value::I2(u as u16 as i16))
    } else {
        let b = if (c as u32) < 256 { c as u32 } else { encode_ansi(c) };
        Ok(Value::I2(b as i16))
    }
}

fn encode_ansi(c: char) -> u32 {
    // Outside Latin-1 there is no single-byte form; report the low byte, as
    // the ANSI code page would after a lossy conversion.
    (c as u32) & 0xFF
}

pub fn chr(v: &Value, wide: bool) -> VbResult<Value> {
    if v.is_null() {
        return Ok(Value::Null);
    }
    let n = match v {
        Value::Str(s) => parse_number(s).ok_or_else(err::type_mismatch)?,
        _ => v.to_f64()?,
    };
    let r = round_half_even(n);
    if wide {
        if !(-32768.0..=65535.0).contains(&r) {
            return Err(err::invalid_call());
        }
        let u = (r as i64 as u16) as u32;
        let c = char::from_u32(u).unwrap_or('\u{FFFD}');
        return Ok(Value::Str(Rc::from(c.to_string().as_str())));
    }
    // On a single-byte code page only 0..255 is a valid character code.
    if !(0.0..=255.0).contains(&r) {
        return Err(err::invalid_call());
    }
    let b = r as u8;
    Ok(Value::Str(Rc::from((b as char).to_string().as_str())))
}
