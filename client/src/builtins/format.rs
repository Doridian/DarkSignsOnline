//! `FormatNumber`, `FormatCurrency`, `FormatPercent` and `FormatDateTime`.

use crate::error::{err, VbResult};
use crate::value::{round_half_even, Value};

/// A tri-state option argument: -2 means "use the system default".
pub const USE_DEFAULT: i32 = -2;

fn flag(v: i32, default: bool) -> VbResult<bool> {
    match v {
        USE_DEFAULT => Ok(default),
        0 => Ok(false),
        -1 => Ok(true),
        _ => Err(err::invalid_call()),
    }
}

/// Render with a fixed number of decimals and optional thousands grouping.
fn fixed(n: f64, digits: usize, group: bool) -> String {
    let neg = n < 0.0;
    let a = n.abs();
    // Round to the requested precision before splitting into parts.
    let scale = 10f64.powi(digits as i32);
    let rounded = round_half_even(a * scale) / scale;
    let mut s = format!("{rounded:.digits$}");
    if group {
        let (int_part, frac) = match s.find('.') {
            Some(i) => (s[..i].to_string(), s[i..].to_string()),
            None => (s.clone(), String::new()),
        };
        let mut grouped = String::new();
        for (i, c) in int_part.chars().enumerate() {
            if i > 0 && (int_part.len() - i) % 3 == 0 {
                grouped.push(',');
            }
            grouped.push(c);
        }
        s = grouped + &frac;
    }
    // The digits are assembled with `.` and `,`, then mapped to whatever the
    // locale uses.
    s = crate::locale::localize_number(&s);
    if neg && rounded != 0.0 {
        format!("-{s}")
    } else {
        s
    }
}

/// Drop the "0" before the decimal point when `leading` is off.
fn apply_leading(s: String, leading: bool) -> String {
    if leading {
        return s;
    }
    let dec = crate::locale::conventions().decimal;
    if let Some(rest) = s.strip_prefix(&format!("0{dec}")) {
        return format!("{dec}{rest}");
    }
    if let Some(rest) = s.strip_prefix(&format!("-0{dec}")) {
        return format!("-{dec}{rest}");
    }
    s
}

/// Show a negative value as `(123)` instead of `-123`.
fn apply_parens(s: String, parens: bool) -> String {
    match (parens, s.strip_prefix('-')) {
        (true, Some(rest)) => format!("({rest})"),
        _ => s,
    }
}

pub fn format_number(
    v: &Value,
    digits: i32,
    leading: i32,
    parens: i32,
    group: i32,
) -> VbResult<Value> {
    // A Null value has no numeric form to format.
    if v.is_null() {
        return Err(err::type_mismatch());
    }
    let n = v.to_f64()?;
    let d = if digits == USE_DEFAULT { 2 } else { digits };
    if !(0..=99).contains(&d) {
        return Err(err::invalid_call());
    }
    let s = fixed(n, d as usize, flag(group, true)?);
    let s = apply_leading(s, flag(leading, true)?);
    Ok(Value::str(apply_parens(s, flag(parens, false)?)))
}

pub fn format_currency(
    v: &Value,
    digits: i32,
    leading: i32,
    parens: i32,
    group: i32,
) -> VbResult<Value> {
    // A Null value has no numeric form to format.
    if v.is_null() {
        return Err(err::type_mismatch());
    }
    let n = v.to_f64()?;
    let d = if digits == USE_DEFAULT { 2 } else { digits };
    if !(0..=99).contains(&d) {
        return Err(err::invalid_call());
    }
    let s = fixed(n, d as usize, flag(group, true)?);
    let s = apply_leading(s, flag(leading, true)?);
    // The currency symbol goes inside the sign, and negatives use parens by
    // default in the en-US locale.
    let with_symbol = match s.strip_prefix('-') {
        Some(rest) => format!("-${rest}"),
        None => format!("${s}"),
    };
    let use_parens = if parens == USE_DEFAULT { true } else { flag(parens, true)? };
    Ok(Value::str(apply_parens(with_symbol, use_parens)))
}

pub fn format_percent(
    v: &Value,
    digits: i32,
    leading: i32,
    parens: i32,
    group: i32,
) -> VbResult<Value> {
    if v.is_null() {
        return Err(err::type_mismatch());
    }
    let n = v.to_f64()? * 100.0;
    let d = if digits == USE_DEFAULT { 2 } else { digits };
    if !(0..=99).contains(&d) {
        return Err(err::invalid_call());
    }
    let s = fixed(n, d as usize, flag(group, true)?);
    let s = apply_leading(s, flag(leading, true)?);
    Ok(Value::str(format!("{}%", apply_parens(s, flag(parens, false)?))))
}

pub fn format_datetime(v: &Value, named_format: i32) -> VbResult<Value> {
    use crate::builtins::datetime as dt;
    if v.is_null() {
        return Err(err::type_mismatch());
    }
    let d = dt::to_date(v)?;
    Ok(Value::str(match named_format {
        // General: date and/or time, whichever the value carries.
        0 => dt::format_date_default(d),
        1 => dt::format_long_date(d),
        2 => dt::format_short_date(d),
        3 => dt::format_time_12h(d, true),
        4 => {
            let (h, m, _) = dt::to_hms(d);
            format!("{h:02}:{m:02}")
        }
        _ => return Err(err::invalid_call()),
    }))
}
