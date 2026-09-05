//! The VBScript `Variant` and its conversion rules.

use std::cell::RefCell;
use std::fmt;
use std::rc::Rc;

use crate::error::{err, VbError, VbResult};
use crate::interp::Interp;
use crate::objects::ObjKind;

// Automation VARTYPE codes, as reported by `VarType`.
pub const VT_EMPTY: i32 = 0;
pub const VT_NULL: i32 = 1;
pub const VT_I2: i32 = 2;
pub const VT_I4: i32 = 3;
pub const VT_R4: i32 = 4;
pub const VT_R8: i32 = 5;
pub const VT_CY: i32 = 6;
pub const VT_DATE: i32 = 7;
pub const VT_BSTR: i32 = 8;
pub const VT_DISPATCH: i32 = 9;
pub const VT_ERROR: i32 = 10;
pub const VT_BOOL: i32 = 11;
pub const VT_VARIANT: i32 = 12;
pub const VT_UI1: i32 = 17;
pub const VT_ARRAY: i32 = 0x2000;

/// Currency is a fixed-point type scaled by 10,000.
pub const CY_SCALE: i64 = 10_000;

#[derive(Clone)]
pub enum Value {
    Empty,
    Null,
    Bool(bool),
    I2(i16),
    I4(i32),
    R4(f32),
    R8(f64),
    /// Currency: the value times 10,000.
    Cy(i64),
    /// OLE automation date: days since 1899-12-30.
    Date(f64),
    UI1(u8),
    Str(Rc<str>),
    /// VT_ERROR, produced by `CVErr` and by missing optional arguments.
    ErrCode(i32),
    /// `Nothing` is `Obj(None)`.
    Obj(Option<ObjKind>),
    Array(Rc<VbArray>),
    /// A value whose Automation type VBScript cannot represent, such as
    /// VT_UI4 from a host object. Reading it is fine; using it in any
    /// expression reports "variable uses an Automation type not supported".
    Unsupported(i32),
}

/// A SAFEARRAY of variants. VBScript arrays always have a lower bound of 0.
#[derive(Clone, Debug)]
pub struct VbArray {
    /// Element count per dimension. Empty means the array is not yet sized.
    pub dims: Vec<usize>,
    pub data: Vec<Value>,
    /// Declared with explicit bounds, so `ReDim` on it is an error.
    pub fixed: bool,
    /// Created by `Dim`/`ReDim` into a variable, so passing that variable
    /// hands over the array itself rather than a copy.
    pub owned: bool,
}

impl VbArray {
    pub fn uninitialized() -> Self {
        VbArray { dims: Vec::new(), data: Vec::new(), fixed: false, owned: false }
    }

    pub fn new(dims: Vec<usize>, fixed: bool) -> Self {
        let total: usize = dims.iter().product();
        VbArray { dims, data: vec![Value::Empty; total], fixed, owned: false }
    }

    pub fn from_values(data: Vec<Value>) -> Self {
        VbArray { dims: vec![data.len()], data, fixed: false, owned: false }
    }

    pub fn is_sized(&self) -> bool {
        !self.dims.is_empty()
    }

    /// Flat offset of an element. A SAFEARRAY is column-major: the first
    /// subscript varies fastest, which is also the order `For Each` walks.
    pub fn offset(&self, idx: &[usize]) -> Option<usize> {
        if idx.len() != self.dims.len() {
            return None;
        }
        offset_in(&self.dims, idx)
    }

    /// Grow or shrink to `dims`, keeping the elements that still fit.
    pub fn redim_preserve(&mut self, dims: Vec<usize>) {
        let total: usize = dims.iter().product();
        let mut data = vec![Value::Empty; total];
        if self.is_sized() && dims.len() == self.dims.len() {
            // Copy the sub-block the two shapes have in common.
            let common: Vec<usize> =
                dims.iter().zip(&self.dims).map(|(a, b)| *a.min(b)).collect();
            if common.iter().all(|&c| c > 0) {
                let mut idx = vec![0usize; dims.len()];
                loop {
                    let src = offset_in(&self.dims, &idx).expect("index within bounds");
                    let dst = offset_in(&dims, &idx).expect("index within bounds");
                    data[dst] = self.data[src].clone();

                    // Step to the next index in the common block.
                    let mut d = 0;
                    loop {
                        if d == common.len() {
                            break;
                        }
                        idx[d] += 1;
                        if idx[d] < common[d] {
                            break;
                        }
                        idx[d] = 0;
                        d += 1;
                    }
                    if d == common.len() {
                        break;
                    }
                }
            }
        }
        self.dims = dims;
        self.data = data;
    }
}

/// Column-major flat offset for `idx` within an array shaped `dims`.
fn offset_in(dims: &[usize], idx: &[usize]) -> Option<usize> {
    let mut off = 0usize;
    let mut stride = 1usize;
    for (&i, &n) in idx.iter().zip(dims) {
        if i >= n {
            return None;
        }
        off += i * stride;
        stride *= n;
    }
    Some(off)
}

impl fmt::Debug for Value {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Value::Empty => write!(f, "Empty"),
            Value::Null => write!(f, "Null"),
            Value::Bool(b) => write!(f, "Bool({b})"),
            Value::I2(v) => write!(f, "I2({v})"),
            Value::I4(v) => write!(f, "I4({v})"),
            Value::R4(v) => write!(f, "R4({v})"),
            Value::R8(v) => write!(f, "R8({v})"),
            Value::Cy(v) => write!(f, "Cy({})", *v as f64 / CY_SCALE as f64),
            Value::Date(v) => write!(f, "Date({v})"),
            Value::UI1(v) => write!(f, "UI1({v})"),
            Value::Str(s) => write!(f, "Str({s:?})"),
            Value::ErrCode(v) => write!(f, "Error({v})"),
            Value::Obj(None) => write!(f, "Nothing"),
            Value::Obj(Some(o)) => write!(f, "Object({})", o.type_name()),
            Value::Array(a) => write!(f, "Array{:?}", a.dims),
            Value::Unsupported(vt) => write!(f, "Unsupported(VT_{vt})"),
        }
    }
}

impl Value {
    pub fn str(s: impl AsRef<str>) -> Value {
        Value::Str(Rc::from(s.as_ref()))
    }

    /// The VARTYPE reported by `VarType`.
    pub fn vartype(&self) -> i32 {
        match self {
            Value::Empty => VT_EMPTY,
            Value::Null => VT_NULL,
            Value::Bool(_) => VT_BOOL,
            Value::I2(_) => VT_I2,
            Value::I4(_) => VT_I4,
            Value::R4(_) => VT_R4,
            Value::R8(_) => VT_R8,
            Value::Cy(_) => VT_CY,
            Value::Date(_) => VT_DATE,
            Value::UI1(_) => VT_UI1,
            Value::Str(_) => VT_BSTR,
            Value::ErrCode(_) => VT_ERROR,
            Value::Obj(_) => VT_DISPATCH,
            Value::Array(_) => VT_ARRAY | VT_VARIANT,
            Value::Unsupported(vt) => *vt,
        }
    }

    /// Name used by `getVT` in the test harness.
    pub fn vt_name(&self) -> String {
        match self.vartype() {
            VT_EMPTY => "VT_EMPTY".into(),
            VT_NULL => "VT_NULL".into(),
            VT_I2 => "VT_I2".into(),
            VT_I4 => "VT_I4".into(),
            VT_R4 => "VT_R4".into(),
            VT_R8 => "VT_R8".into(),
            VT_CY => "VT_CY".into(),
            VT_DATE => "VT_DATE".into(),
            VT_BSTR => "VT_BSTR".into(),
            VT_DISPATCH => "VT_DISPATCH".into(),
            VT_ERROR => "VT_ERROR".into(),
            VT_BOOL => "VT_BOOL".into(),
            VT_UI1 => "VT_UI1".into(),
            v if v == VT_ARRAY | VT_VARIANT => "VT_ARRAY|VT_VARIANT".into(),
            v => format!("VT_{v}"),
        }
    }

    pub fn is_null(&self) -> bool {
        matches!(self, Value::Null)
    }
    pub fn is_empty(&self) -> bool {
        matches!(self, Value::Empty)
    }
    pub fn is_object(&self) -> bool {
        matches!(self, Value::Obj(_))
    }
    pub fn is_array(&self) -> bool {
        matches!(self, Value::Array(_))
    }
    pub fn is_numeric_type(&self) -> bool {
        matches!(
            self,
            Value::Bool(_) | Value::I2(_) | Value::I4(_) | Value::R4(_)
                | Value::R8(_) | Value::Cy(_) | Value::Date(_) | Value::UI1(_)
                | Value::Empty
        )
    }

    pub fn bool(b: bool) -> Value {
        Value::Bool(b)
    }

    /// Build the narrowest integer variant that holds `v`, as VBScript does
    /// when an arithmetic result is written back to a variant.
    pub fn from_i32_narrow(v: i32) -> Value {
        if v >= i16::MIN as i32 && v <= i16::MAX as i32 {
            Value::I2(v as i16)
        } else {
            Value::I4(v)
        }
    }

    pub fn from_f64(v: f64) -> Value {
        Value::R8(v)
    }

    // ---- conversions -----------------------------------------------------

    /// Numeric value as f64. `Null` is rejected by the caller, not here.
    pub fn to_f64(&self) -> VbResult<f64> {
        Ok(match self {
            Value::Empty => 0.0,
            Value::Bool(b) => if *b { -1.0 } else { 0.0 },
            Value::I2(v) => *v as f64,
            Value::I4(v) => *v as f64,
            Value::UI1(v) => *v as f64,
            Value::R4(v) => *v as f64,
            Value::R8(v) | Value::Date(v) => *v,
            Value::Cy(v) => *v as f64 / CY_SCALE as f64,
            Value::ErrCode(v) => *v as f64,
            Value::Str(s) => parse_number(s).ok_or_else(err::type_mismatch)?,
            Value::Null => return Err(err::invalid_use_of_null()),
            Value::Obj(_) => return Err(err::object_no_value()),
            Value::Array(_) => return Err(err::type_mismatch()),
            Value::Unsupported(_) => return Err(VbError::code(458)),
        })
    }

    /// String form used by `CStr`, `&`, and implicit conversions.
    pub fn to_vb_string(&self) -> VbResult<Rc<str>> {
        Ok(match self {
            Value::Str(s) => s.clone(),
            Value::Empty => Rc::from(""),
            Value::Null => return Err(err::invalid_use_of_null()),
            Value::Bool(b) => Rc::from(if *b { "True" } else { "False" }),
            Value::I2(v) => Rc::from(v.to_string().as_str()),
            Value::I4(v) => Rc::from(v.to_string().as_str()),
            Value::UI1(v) => Rc::from(v.to_string().as_str()),
            Value::R4(v) => Rc::from(format_r4(*v).as_str()),
            Value::R8(v) => Rc::from(format_r8(*v).as_str()),
            Value::Cy(v) => Rc::from(format_currency_plain(*v).as_str()),
            Value::Date(v) => {
                Rc::from(crate::builtins::datetime::format_date_default(*v).as_str())
            }
            Value::ErrCode(v) => Rc::from(format!("Error {v}").as_str()),
            Value::Obj(_) => return Err(err::object_no_value()),
            Value::Array(_) => return Err(err::type_mismatch()),
            Value::Unsupported(_) => return Err(VbError::code(458)),
        })
    }

    /// Truthiness for `If`/`While`. Non-zero is true, matching VB.
    pub fn to_bool(&self) -> VbResult<bool> {
        match self {
            Value::Bool(b) => Ok(*b),
            Value::Null => Err(err::invalid_use_of_null()),
            // A string condition converts the way `CBool` does, so the words
            // "True" and "False" work as well as numeric text.
            Value::Str(s) => {
                let t = s.trim();
                let t = t.strip_prefix('#').and_then(|r| r.strip_suffix('#')).unwrap_or(t);
                if t.eq_ignore_ascii_case("true") {
                    return Ok(true);
                }
                if t.eq_ignore_ascii_case("false") {
                    return Ok(false);
                }
                Ok(parse_number(s).ok_or_else(err::type_mismatch)? != 0.0)
            }
            _ => Ok(self.to_f64()? != 0.0),
        }
    }
}

/// Round-half-to-even, the rule Automation uses for every narrowing cast.
pub fn round_half_even(v: f64) -> f64 {
    let r = v.round();
    if (v - v.trunc()).abs() == 0.5 && r % 2.0 != 0.0 {
        r - v.signum()
    } else {
        r
    }
}

/// Parse a string as VBScript does for implicit numeric conversion: optional
/// sign, digits, `&H`/`&O` prefixes, and surrounding whitespace.
pub fn parse_number(s: &str) -> Option<f64> {
    let t = s.trim_matches(|c: char| c.is_whitespace() || c == '\u{0}');
    // An empty string has no numeric value; callers report a type mismatch.
    if t.is_empty() {
        return None;
    }
    let (sign, rest) = match t.as_bytes()[0] {
        b'-' => (-1.0, &t[1..]),
        b'+' => (1.0, &t[1..]),
        _ => (1.0, t),
    };
    let rest = rest.trim_start();
    if let Some(hex) = strip_prefix_ci(rest, "&h") {
        let hex = hex.strip_suffix(['&']).unwrap_or(hex);
        let digits: String = hex.chars().take_while(|c| c.is_ascii_hexdigit()).collect();
        if digits.is_empty() {
            return None;
        }
        let v = u64::from_str_radix(&digits, 16).ok()?;
        return Some(sign * (v as u32 as i32) as f64);
    }
    if let Some(oct) = strip_prefix_ci(rest, "&o") {
        let oct = oct.strip_suffix(['&']).unwrap_or(oct);
        let digits: String = oct.chars().take_while(|c| ('0'..='7').contains(c)).collect();
        if digits.is_empty() {
            return None;
        }
        let v = u64::from_str_radix(&digits, 8).ok()?;
        return Some(sign * (v as u32 as i32) as f64);
    }

    // A comma-decimal locale writes 1,5 where en-US writes 1.5.
    let localized;
    let rest = {
        let dec = crate::locale::conventions().decimal;
        if dec != '.' && rest.contains(dec) {
            localized = rest.replace(dec, ".");
            localized.as_str()
        } else {
            rest
        }
    };

    // Take the longest leading run that parses as a decimal number.
    let b = rest.as_bytes();
    let mut i = 0;
    while i < b.len() && b[i].is_ascii_digit() {
        i += 1;
    }
    if i < b.len() && b[i] == b'.' {
        i += 1;
        while i < b.len() && b[i].is_ascii_digit() {
            i += 1;
        }
    }
    if i == 0 || (i == 1 && b[0] == b'.') {
        return None;
    }
    if i < b.len() && (b[i] | 32) == b'e' {
        let save = i;
        i += 1;
        if i < b.len() && (b[i] == b'+' || b[i] == b'-') {
            i += 1;
        }
        if i < b.len() && b[i].is_ascii_digit() {
            while i < b.len() && b[i].is_ascii_digit() {
                i += 1;
            }
        } else {
            i = save;
        }
    }
    // Trailing characters make the whole string invalid, except whitespace.
    if !rest[i..].trim().is_empty() {
        return None;
    }
    rest[..i].parse::<f64>().ok().map(|v| sign * v)
}

fn strip_prefix_ci<'a>(s: &'a str, prefix: &str) -> Option<&'a str> {
    if s.len() >= prefix.len() && s[..prefix.len()].eq_ignore_ascii_case(prefix) {
        Some(&s[prefix.len()..])
    } else {
        None
    }
}

/// C's `%.*G`, which is what Automation uses to render reals.
fn format_g(v: f64, prec: usize) -> String {
    if v == 0.0 {
        return "0".into();
    }
    if v.is_nan() {
        return "-1.#IND".into();
    }
    if v.is_infinite() {
        return if v > 0.0 { "1.#INF".into() } else { "-1.#INF".into() };
    }

    // Determine the decimal exponent after rounding to `prec` significant digits.
    let sci = format!("{:.*e}", prec - 1, v);
    let exp: i32 = sci[sci.find('e').unwrap() + 1..].parse().unwrap();

    if exp < -4 || exp >= prec as i32 {
        let mantissa = &sci[..sci.find('e').unwrap()];
        let mantissa = trim_fraction(mantissa);
        let sign = if exp < 0 { '-' } else { '+' };
        format!("{mantissa}E{sign}{:02}", exp.abs())
    } else {
        let decimals = (prec as i32 - 1 - exp).max(0) as usize;
        trim_fraction(&format!("{:.*}", decimals, v))
    }
}

/// Drop trailing zeros in a fractional part, then a bare trailing point.
fn trim_fraction(s: &str) -> String {
    if !s.contains('.') {
        return s.to_string();
    }
    let t = s.trim_end_matches('0');
    let t = t.strip_suffix('.').unwrap_or(t);
    // "-0" can survive rounding; normalize it away.
    if t == "-0" { "0".into() } else { t.to_string() }
}

pub fn format_r8(v: f64) -> String {
    crate::locale::localize_number(&format_g(v, 15))
}

pub fn format_r4(v: f32) -> String {
    crate::locale::localize_number(&format_g(v as f64, 7))
}

/// The invariant rendering, used where a locale must not intervene.
pub fn format_r8_invariant(v: f64) -> String {
    format_g(v, 15)
}

/// Currency renders with up to 4 decimals and no thousands separators.
pub fn format_currency_plain(scaled: i64) -> String {
    let neg = scaled < 0;
    let a = scaled.unsigned_abs();
    let int = a / CY_SCALE as u64;
    let frac = a % CY_SCALE as u64;
    let mut s = String::new();
    if neg {
        s.push('-');
    }
    s.push_str(&int.to_string());
    if frac != 0 {
        let f = format!("{frac:04}");
        s.push(crate::locale::conventions().decimal);
        s.push_str(f.trim_end_matches('0'));
    }
    s
}

/// A slot holding a variable's value. Shared so `ByRef` parameters can write
/// back through the caller's binding.
pub type Slot = Rc<RefCell<Value>>;

pub fn slot(v: Value) -> Slot {
    Rc::new(RefCell::new(v))
}

/// Compare two values with VBScript's relational rules. `None` means the
/// comparison involves `Null` and so yields `Null`.
///
/// A string beside a number is the subtle case. Which of the two rules
/// applies depends on the *number's* type: Boolean, Byte and Currency are
/// rendered as text and compared as strings, while the other numeric types
/// pull the string into a number, making a non-numeric string a type
/// mismatch rather than simply unequal — but only when that number came
/// from a source literal. A number reaching the comparison through a
/// variable, an expression or a function result is rendered as text instead,
/// which is why `"abc" = 5` raises while `"abc" = n` (with `n = 5`) is
/// merely false. `lit_a` and `lit_b` say which operands were written as
/// literals.
pub fn compare(
    a: &Value,
    b: &Value,
    text_mode: bool,
    lit_a: bool,
    lit_b: bool,
) -> VbResult<Option<std::cmp::Ordering>> {
    use std::cmp::Ordering;

    // An array has no ordering at all, and that outranks Null propagation.
    if a.is_array() || b.is_array() {
        return Err(err::type_mismatch());
    }
    if matches!(a, Value::Unsupported(_)) || matches!(b, Value::Unsupported(_)) {
        return Err(VbError::code(458));
    }
    if a.is_null() || b.is_null() {
        return Ok(None);
    }

    let a_str = matches!(a, Value::Str(_));
    let b_str = matches!(b, Value::Str(_));

    // Two strings compare as text, and Empty behaves as "" beside a string.
    if (a_str && b_str) || (a_str && b.is_empty()) || (b_str && a.is_empty()) {
        let x = a.to_vb_string()?;
        let y = b.to_vb_string()?;
        return Ok(Some(compare_str(&x, &y, text_mode)));
    }
    if a.is_empty() && b.is_empty() {
        return Ok(Some(Ordering::Equal));
    }

    if a_str || b_str {
        let (num, num_lit, str_lit) =
            if a_str { (b, lit_b, lit_a) } else { (a, lit_a, lit_b) };

        // With neither side written as a literal, a string simply outranks
        // any number, whatever the two values are.
        if !num_lit && !str_lit {
            return Ok(Some(if a_str { Ordering::Greater } else { Ordering::Less }));
        }

        // A literal number pulls the string into a number, so a string that
        // is not numeric is a type mismatch. Boolean, Byte and Currency are
        // the exceptions: they always render as text.
        if !(num_lit && !compares_as_string(num)) {
            let x = a.to_vb_string()?;
            let y = b.to_vb_string()?;
            return Ok(Some(compare_str(&x, &y, text_mode)));
        }
    }

    // Otherwise both sides become numbers; a string that is not a number is
    // a type mismatch.
    let x = a.to_f64()?;
    let y = b.to_f64()?;
    // A Single operand drags the comparison down to Single precision, so
    // `CSng(0.001 * 0.001) = 0.000001` holds.
    if matches!(a, Value::R4(_)) || matches!(b, Value::R4(_)) {
        let (x, y) = (x as f32, y as f32);
        return Ok(Some(x.partial_cmp(&y).unwrap_or(Ordering::Equal)));
    }
    Ok(Some(x.partial_cmp(&y).unwrap_or(Ordering::Equal)))
}

/// Types that a string is compared against textually rather than numerically.
fn compares_as_string(v: &Value) -> bool {
    matches!(v, Value::Bool(_) | Value::UI1(_) | Value::Cy(_))
}

pub fn compare_str(a: &str, b: &str, text_mode: bool) -> std::cmp::Ordering {
    if text_mode {
        let x: Vec<char> = a.chars().flat_map(|c| c.to_uppercase()).collect();
        let y: Vec<char> = b.chars().flat_map(|c| c.to_uppercase()).collect();
        x.cmp(&y)
    } else {
        a.chars().map(|c| c as u32).cmp(b.chars().map(|c| c as u32))
    }
}

impl Interp {
    /// Resolve a value to a plain variant, invoking an object's default
    /// property when one is needed.
    pub fn deref_value(&mut self, v: Value) -> VbResult<Value> {
        match v {
            Value::Obj(Some(o)) => self.object_default_value(&o),
            // Using `Nothing` where a value is needed has nothing to read.
            Value::Obj(None) => Err(err::object_not_set()),
            other => Ok(other),
        }
    }
}

impl From<VbError> for Value {
    fn from(e: VbError) -> Value {
        Value::ErrCode(e.number)
    }
}
