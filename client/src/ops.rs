//! Arithmetic, comparison and logical operators with VBScript's promotion
//! rules. The result type of `a + b` depends on both operand types, and
//! overflow widens rather than failing, so each operator carries a small
//! type lattice with it.

use std::cmp::Ordering;
use std::rc::Rc;

use crate::ast::BinOp;
use crate::error::{err, VbResult};
use crate::value::*;

/// Rank in the numeric promotion lattice.
#[derive(Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Debug)]
enum NT {
    UI1,
    I2,
    I4,
    R4,
    R8,
    Cy,
    Date,
}

fn num_type(v: &Value) -> Option<NT> {
    Some(match v {
        Value::Empty => NT::I2,
        Value::Bool(_) => NT::I2,
        Value::UI1(_) => NT::UI1,
        Value::I2(_) => NT::I2,
        Value::I4(_) => NT::I4,
        Value::R4(_) => NT::R4,
        Value::R8(_) => NT::R8,
        Value::Cy(_) => NT::Cy,
        Value::Date(_) => NT::Date,
        Value::ErrCode(_) => NT::I4,
        _ => return None,
    })
}

/// The type an arithmetic result takes, given both operand types.
fn promote(a: NT, b: NT) -> NT {
    use NT::*;
    // A Date operand makes the result a Date, so date arithmetic stays in
    // date space.
    if a == Date || b == Date {
        return Date;
    }
    match (a, b) {
        (Cy, Cy) => Cy,
        // Currency mixed with a floating type loses its fixed point.
        (Cy, R4) | (R4, Cy) | (Cy, R8) | (R8, Cy) => R8,
        (Cy, _) | (_, Cy) => Cy,
        // Long combined with Single needs more range than Single provides.
        (I4, R4) | (R4, I4) => R8,
        _ => a.max(b),
    }
}

/// Build a value of type `t` from an exact f64, widening on overflow the way
/// VBScript does (Integer to Long, Long to Double).
fn make_num(t: NT, v: f64) -> VbResult<Value> {
    use NT::*;
    Ok(match t {
        UI1 => {
            if (0.0..=255.0).contains(&v) {
                Value::UI1(round_half_even(v) as u8)
            } else {
                // Byte arithmetic widens to Integer, then to Long.
                return make_num(I2, v);
            }
        }
        I2 => {
            if v >= i16::MIN as f64 && v <= i16::MAX as f64 {
                Value::I2(v as i16)
            } else {
                return make_num(I4, v);
            }
        }
        I4 => {
            if v >= i32::MIN as f64 && v <= i32::MAX as f64 {
                Value::I4(v as i32)
            } else {
                Value::R8(v)
            }
        }
        R4 => {
            let f = v as f32;
            if f.is_finite() {
                Value::R4(f)
            } else {
                Value::R8(v)
            }
        }
        R8 => Value::R8(v),
        Cy => {
            let scaled = round_half_even(v * CY_SCALE as f64);
            if scaled.abs() > i64::MAX as f64 {
                return Err(err::overflow());
            }
            Value::Cy(scaled as i64)
        }
        Date => {
            if !(-657_434.0..=2_958_465.999_999_999).contains(&v) {
                return Err(err::overflow());
            }
            Value::Date(v)
        }
    })
}

/// Currency keeps exact fixed-point results for + and -, so those bypass f64.
fn cy_exact(op: BinOp, a: i64, b: i64) -> Option<VbResult<Value>> {
    let r = match op {
        BinOp::Add => a.checked_add(b),
        BinOp::Sub => a.checked_sub(b),
        _ => return None,
    };
    Some(match r {
        Some(v) => Ok(Value::Cy(v)),
        None => Err(err::overflow()),
    })
}

/// Is this value a string that does *not* look like a number? Such a value
/// makes `+` concatenate rather than add.
fn is_stringy(v: &Value) -> bool {
    matches!(v, Value::Str(_))
}

pub fn add(a: &Value, b: &Value) -> VbResult<Value> {
    if a.is_null() || b.is_null() {
        return Ok(Value::Null);
    }
    // Two strings concatenate; a string plus a number adds numerically.
    match (is_stringy(a), is_stringy(b)) {
        (true, true) => return concat(a, b),
        // Empty behaves as "" next to a string.
        (true, false) if b.is_empty() => return concat(a, b),
        (false, true) if a.is_empty() => return concat(a, b),
        _ => {}
    }
    arith(BinOp::Add, a, b)
}

pub fn concat(a: &Value, b: &Value) -> VbResult<Value> {
    // Unlike `+`, `&` treats Null as an empty string unless both are Null.
    if a.is_null() && b.is_null() {
        return Ok(Value::Null);
    }
    let x = if a.is_null() { Rc::from("") } else { a.to_vb_string()? };
    let y = if b.is_null() { Rc::from("") } else { b.to_vb_string()? };
    let mut s = String::with_capacity(x.len() + y.len());
    s.push_str(&x);
    s.push_str(&y);
    Ok(Value::Str(Rc::from(s.as_str())))
}

pub fn arith(op: BinOp, a: &Value, b: &Value) -> VbResult<Value> {
    if a.is_null() || b.is_null() {
        return Ok(Value::Null);
    }
    // Each operand is classified on its own; a numeric string participates
    // as a Double.
    let ta = numeric_or_str(a)?;
    let tb = numeric_or_str(b)?;
    let mut t = promote(ta, tb);

    if t == NT::Cy {
        if let (Value::Cy(x), Value::Cy(y)) = (a, b) {
            if let Some(r) = cy_exact(op, *x, *y) {
                return r;
            }
        }
    }

    let x = a.to_f64()?;
    let y = b.to_f64()?;

    let v = match op {
        BinOp::Add => x + y,
        BinOp::Sub => x - y,
        BinOp::Mul => x * y,
        _ => unreachable!("arith called with {op:?}"),
    };

    // Multiplying two dates yields a number, not a date.
    if t == NT::Date && op == BinOp::Mul {
        t = NT::R8;
    }
    // Subtracting one date from another gives an interval, not a date.
    if op == BinOp::Sub && ta == NT::Date && tb == NT::Date {
        t = NT::R8;
    }
    make_num(t, v)
}

fn num_type_of_str(v: &Value) -> VbResult<NT> {
    match v {
        Value::Unsupported(_) => Err(crate::error::VbError::code(458)),
        Value::Str(s) => {
            let n = parse_number(s).ok_or_else(err::type_mismatch)?;
            // A numeric string participates as a Double.
            let _ = n;
            Ok(NT::R8)
        }
        Value::Obj(_) => Err(err::object_no_value()),
        Value::Array(_) => Err(err::type_mismatch()),
        _ => Err(err::type_mismatch()),
    }
}

pub fn divide(a: &Value, b: &Value) -> VbResult<Value> {
    if a.is_null() || b.is_null() {
        return Ok(Value::Null);
    }
    let x = a.to_f64()?;
    let y = b.to_f64()?;
    if y == 0.0 {
        return Err(err::div_zero());
    }
    // Floating division always produces a Double, except that two Singles
    // stay Single.
    let (ta, tb) = (numeric_or_str(a)?, numeric_or_str(b)?);
    let t = if ta == NT::R4 && tb == NT::R4 { NT::R4 } else { NT::R8 };
    make_num(t, x / y)
}

fn numeric_or_str(v: &Value) -> VbResult<NT> {
    match num_type(v) {
        Some(t) => Ok(t),
        None => num_type_of_str(v),
    }
}

/// `\` truncates both operands to integers and divides.
pub fn int_divide(a: &Value, b: &Value) -> VbResult<Value> {
    if a.is_null() || b.is_null() {
        return Ok(Value::Null);
    }
    let x = to_i32_rounded(a)?;
    let y = to_i32_rounded(b)?;
    if y == 0 {
        return Err(err::div_zero());
    }
    let r = (x as i64) / (y as i64);
    narrow_int_result(a, b, r)
}

pub fn modulo(a: &Value, b: &Value) -> VbResult<Value> {
    if a.is_null() || b.is_null() {
        return Ok(Value::Null);
    }
    let x = to_i32_rounded(a)?;
    let y = to_i32_rounded(b)?;
    if y == 0 {
        return Err(err::div_zero());
    }
    let r = (x as i64) % (y as i64);
    narrow_int_result(a, b, r)
}

/// `\` and `Mod` give an Integer when both operands are Integer-sized.
fn narrow_int_result(a: &Value, b: &Value, r: i64) -> VbResult<Value> {
    let small = matches!(numeric_or_str(a), Ok(NT::UI1) | Ok(NT::I2))
        && matches!(numeric_or_str(b), Ok(NT::UI1) | Ok(NT::I2));
    if small && r >= i16::MIN as i64 && r <= i16::MAX as i64 {
        Ok(Value::I2(r as i16))
    } else if r >= i32::MIN as i64 && r <= i32::MAX as i64 {
        Ok(Value::I4(r as i32))
    } else {
        Err(err::overflow())
    }
}

pub fn power(a: &Value, b: &Value) -> VbResult<Value> {
    if a.is_null() || b.is_null() {
        return Ok(Value::Null);
    }
    let x = a.to_f64()?;
    let y = b.to_f64()?;
    Ok(Value::R8(x.powf(y)))
}

pub fn negate(a: &Value) -> VbResult<Value> {
    if a.is_null() {
        return Ok(Value::Null);
    }
    match a {
        // Negating keeps the operand's type, widening only on overflow.
        Value::Cy(v) => v.checked_neg().map(Value::Cy).ok_or_else(err::overflow),
        Value::Empty => Ok(Value::I2(0)),
        _ => {
            let t = numeric_or_str(a)?;
            let t = if t == NT::Date { NT::R8 } else { t };
            make_num(t, -a.to_f64()?)
        }
    }
}

/// Round to i32 for the bitwise and integer-division operators.
pub fn to_i32_rounded(v: &Value) -> VbResult<i32> {
    let f = match v {
        Value::Str(s) => parse_number(s).ok_or_else(err::type_mismatch)?,
        _ => v.to_f64()?,
    };
    let r = round_half_even(f);
    if r < i32::MIN as f64 || r > i32::MAX as f64 {
        return Err(err::overflow());
    }
    Ok(r as i32)
}

/// Result width of a logical/bitwise operator, which follows the operand
/// types rather than their values.
#[derive(Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
enum LogType {
    UI1,
    Bool,
    I2,
    I4,
}

fn log_type(v: &Value) -> LogType {
    match v {
        Value::UI1(_) => LogType::UI1,
        Value::Bool(_) => LogType::Bool,
        Value::I2(_) => LogType::I2,
        // Empty and everything else are coerced to a Long before the
        // operation, so the result comes out Long.
        _ => LogType::I4,
    }
}

/// All-ones for the result width, as a sign-extended i64.
fn log_mask(t: LogType) -> i64 {
    match t {
        LogType::UI1 => 0xFF,
        LogType::Bool | LogType::I2 => 0xFFFF,
        LogType::I4 => 0xFFFF_FFFF,
    }
}

fn make_log(t: LogType, bits: i64) -> Value {
    let m = log_mask(t);
    let masked = bits & m;
    match t {
        LogType::UI1 => Value::UI1(masked as u8),
        LogType::Bool => Value::Bool(masked != 0),
        LogType::I2 => Value::I2(masked as u16 as i16),
        LogType::I4 => Value::I4(masked as u32 as i32),
    }
}

/// The known operand's bits, narrowed to the result width.
fn log_bits(v: &Value, t: LogType) -> VbResult<i64> {
    let n = match to_i32_rounded(v) {
        Ok(n) => n,
        // A string that is not numeric may still be a Boolean word, which
        // is how `Not "#FALSE#"` works.
        Err(e) => match v {
            Value::Str(_) => {
                if v.to_bool()? {
                    -1
                } else {
                    0
                }
            }
            _ => return Err(e),
        },
    };
    Ok(n as i64 & log_mask(t))
}

pub fn logical(op: BinOp, a: &Value, b: &Value) -> VbResult<Value> {
    // With one side unknown, a bit of the result is only determined when the
    // known side forces it. If any bit stays unknown the whole result is Null.
    if a.is_null() || b.is_null() {
        if a.is_null() && b.is_null() {
            return Ok(Value::Null);
        }
        let (known, null_on_right) = if a.is_null() { (b, false) } else { (a, true) };
        let t = log_type(known);
        let all = log_mask(t);
        let k = log_bits(known, t)?;
        return Ok(match op {
            // 0 forces every bit low; anything else leaves bits unknown.
            BinOp::And => {
                if k == 0 {
                    make_log(t, 0)
                } else {
                    Value::Null
                }
            }
            // All-ones forces every bit high.
            BinOp::Or => {
                if k == all {
                    make_log(t, all)
                } else {
                    Value::Null
                }
            }
            BinOp::Xor | BinOp::Eqv => Value::Null,
            BinOp::Imp => {
                if null_on_right {
                    // `a Imp Null` is `Not a Or Null`. Native VBScript keeps
                    // Byte operands whole and just complements them, rather
                    // than falling back to Null as the wider types do.
                    if t == LogType::UI1 {
                        make_log(t, !k)
                    } else if k == 0 {
                        make_log(t, all)
                    } else {
                        Value::Null
                    }
                } else if k == all {
                    // `Null Imp b` is high wherever b is high.
                    make_log(t, all)
                } else {
                    Value::Null
                }
            }
            _ => unreachable!(),
        });
    }

    // Two Booleans stay Boolean; otherwise the wider operand type wins.
    let t = log_type(a).max(log_type(b));
    let x = log_bits(a, t)?;
    let y = log_bits(b, t)?;
    let r = match op {
        BinOp::And => x & y,
        BinOp::Or => x | y,
        BinOp::Xor => x ^ y,
        BinOp::Eqv => !(x ^ y),
        BinOp::Imp => !x | y,
        _ => unreachable!(),
    };
    Ok(make_log(t, r))
}

pub fn not(a: &Value) -> VbResult<Value> {
    if a.is_null() {
        return Ok(Value::Null);
    }
    let t = log_type(a);
    Ok(make_log(t, !log_bits(a, t)?))
}

/// Relational comparison. Returns `Null` when either side is `Null`.
pub fn compare_op(
    op: BinOp,
    a: &Value,
    b: &Value,
    text_mode: bool,
    lit_a: bool,
    lit_b: bool,
) -> VbResult<Value> {
    let ord = match compare(a, b, text_mode, lit_a, lit_b)? {
        Some(o) => o,
        None => return Ok(Value::Null),
    };
    let r = match op {
        BinOp::Eq => ord == Ordering::Equal,
        BinOp::Ne => ord != Ordering::Equal,
        BinOp::Lt => ord == Ordering::Less,
        BinOp::Le => ord != Ordering::Greater,
        BinOp::Gt => ord == Ordering::Greater,
        BinOp::Ge => ord != Ordering::Less,
        _ => unreachable!(),
    };
    Ok(Value::Bool(r))
}
