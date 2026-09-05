//! Built-in functions and constants.

pub mod conv;
pub mod datetime;
pub mod format;
pub mod strings;

use std::cell::RefCell;
use std::rc::Rc;

use crate::error::{err, VbError, VbResult};
use crate::interp::{ArgVal, Interp};
use crate::objects::dictionary::Dictionary;
use crate::objects::regexp::RegExpObj;
use crate::objects::ObjKind;
use crate::value::*;

use format::USE_DEFAULT;

/// The locale scripts start in, and the one `SetLocale` with no argument or
/// with 0 restores.
pub const DEFAULT_LOCALE: i32 = 1033;

/// Positional arguments, where `None` marks an elided slot.
pub struct Args(Vec<Option<Value>>);

impl Args {
    fn get(&self, i: usize) -> Option<&Value> {
        self.0.get(i).and_then(|o| o.as_ref())
    }
    fn req(&self, i: usize) -> VbResult<&Value> {
        self.get(i).ok_or_else(err::wrong_arg_count)
    }
    fn count(&self) -> usize {
        self.0.len()
    }
    /// An integer option argument, defaulting when absent.
    fn int_or(&self, i: usize, default: i32) -> VbResult<i32> {
        match self.get(i) {
            None => Ok(default),
            Some(v) => {
                if v.is_null() {
                    return Err(err::invalid_use_of_null());
                }
                let n = v.to_f64()?;
                if n < i32::MIN as f64 || n > i32::MAX as f64 {
                    return Err(err::overflow());
                }
                Ok(round_half_even(n) as i32)
            }
        }
    }
    fn str_or(&self, i: usize, default: &str) -> VbResult<Rc<str>> {
        match self.get(i) {
            None => Ok(Rc::from(default)),
            Some(v) => v.to_vb_string(),
        }
    }
}

/// Every name the interpreter handles itself.
const NAMES: &[&str] = &[
    // conversion
    "cbool", "cbyte", "ccur", "cdate", "cdbl", "cint", "clng", "csng", "cstr",
    "int", "fix", "round", "sgn", "abs", "hex", "oct", "cverr",
    "asc", "ascb", "ascw", "chr", "chrb", "chrw",
    // strings
    "len", "lenb", "left", "leftb", "right", "rightb", "mid", "midb",
    "instr", "instrb", "instrrev", "lcase", "ucase", "ltrim", "rtrim", "trim",
    "space", "string", "strcomp", "strreverse", "replace", "split", "join",
    "filter", "escape", "unescape",
    // math
    "atn", "cos", "sin", "tan", "exp", "log", "sqr", "rnd", "randomize",
    // date and time
    "date", "time", "now", "timer", "dateserial", "datevalue", "timeserial",
    "timevalue", "year", "month", "day", "hour", "minute", "second",
    "weekday", "monthname", "weekdayname", "dateadd", "datediff", "datepart",
    // information
    "vartype", "typename", "isarray", "isdate", "isempty", "isnull",
    "isnumeric", "isobject", "lbound", "ubound", "array",
    "eval", "execute", "executeglobal", "getref", "createobject", "getobject",
    "getlocale", "setlocale", "rgb",
    "scriptengine", "scriptenginemajorversion", "scriptengineminorversion",
    "scriptenginebuildversion",
    "formatnumber", "formatcurrency", "formatpercent", "formatdatetime",
    "msgbox", "inputbox",
];

pub fn is_builtin(name: &str) -> bool {
    NAMES.contains(&name)
}

/// Named constants. Returns `None` for anything that is not one.
pub fn constant(name: &str) -> Option<Value> {
    Some(match name {
        // VarType codes
        "vbempty" => Value::I2(0),
        "vbnull" => Value::I2(1),
        "vbinteger" => Value::I2(2),
        "vblong" => Value::I2(3),
        "vbsingle" => Value::I2(4),
        "vbdouble" => Value::I2(5),
        "vbcurrency" => Value::I2(6),
        "vbdate" => Value::I2(7),
        "vbstring" => Value::I2(8),
        "vbobject" => Value::I2(9),
        "vberror" => Value::I2(10),
        "vbboolean" => Value::I2(11),
        "vbvariant" => Value::I2(12),
        "vbdataobject" => Value::I2(13),
        "vbdecimal" => Value::I2(14),
        "vbbyte" => Value::I2(17),
        "vbarray" => Value::I2(8192),

        // Days and weeks
        "vbusesystemdayofweek" => Value::I2(0),
        "vbsunday" => Value::I2(1),
        "vbmonday" => Value::I2(2),
        "vbtuesday" => Value::I2(3),
        "vbwednesday" => Value::I2(4),
        "vbthursday" => Value::I2(5),
        "vbfriday" => Value::I2(6),
        "vbsaturday" => Value::I2(7),
        "vbusesystem" => Value::I2(0),
        "vbfirstjan1" => Value::I2(1),
        "vbfirstfourdays" => Value::I2(2),
        "vbfirstfullweek" => Value::I2(3),

        // MsgBox
        "vbokonly" => Value::I2(0),
        "vbokcancel" => Value::I2(1),
        "vbabortretryignore" => Value::I2(2),
        "vbyesnocancel" => Value::I2(3),
        "vbyesno" => Value::I2(4),
        "vbretrycancel" => Value::I2(5),
        "vbcritical" => Value::I2(16),
        "vbquestion" => Value::I2(32),
        "vbexclamation" => Value::I2(48),
        "vbinformation" => Value::I2(64),
        "vbdefaultbutton1" => Value::I2(0),
        "vbdefaultbutton2" => Value::I2(256),
        "vbdefaultbutton3" => Value::I2(512),
        "vbdefaultbutton4" => Value::I2(768),
        "vbapplicationmodal" => Value::I2(0),
        "vbsystemmodal" => Value::I2(4096),
        "vbmsgboxhelpbutton" => Value::I4(16384),
        "vbmsgboxsetforeground" => Value::I4(65536),
        "vbmsgboxright" => Value::I4(524288),
        "vbmsgboxrtlreading" => Value::I4(1048576),
        "vbok" => Value::I2(1),
        "vbcancel" => Value::I2(2),
        "vbabort" => Value::I2(3),
        "vbretry" => Value::I2(4),
        "vbignore" => Value::I2(5),
        "vbyes" => Value::I2(6),
        "vbno" => Value::I2(7),

        "vbusedefault" => Value::I2(-2),
        "vbtrue" => Value::I2(-1),
        "vbfalse" => Value::I2(0),

        "vbbinarycompare" => Value::I2(0),
        "vbtextcompare" => Value::I2(1),
        "vbdatabasecompare" => Value::I2(2),

        "vbgeneraldate" => Value::I2(0),
        "vblongdate" => Value::I2(1),
        "vbshortdate" => Value::I2(2),
        "vblongtime" => Value::I2(3),
        "vbshorttime" => Value::I2(4),

        "vbobjecterror" => Value::I4(0x8004_0000u32 as i32),

        // Colours
        "vbblack" => Value::I4(0x000000),
        "vbred" => Value::I4(0x0000FF),
        "vbgreen" => Value::I4(0x00FF00),
        "vbyellow" => Value::I4(0x00FFFF),
        "vbblue" => Value::I4(0xFF0000),
        "vbmagenta" => Value::I4(0xFF00FF),
        "vbcyan" => Value::I4(0xFFFF00),
        "vbwhite" => Value::I4(0xFFFFFF),

        // String constants
        "vbcr" => Value::str("\r"),
        "vblf" => Value::str("\n"),
        "vbcrlf" => Value::str("\r\n"),
        "vbnewline" => Value::str("\r\n"),
        "vbformfeed" => Value::str("\u{000C}"),
        "vbnullchar" => Value::str("\0"),
        "vbnullstring" => Value::str(""),
        "vbtab" => Value::str("\t"),
        "vbverticaltab" => Value::str("\u{000B}"),

        _ => return None,
    })
}

/// Invoke a built-in. `Ok(None)` means the name is not a built-in.
pub fn call(it: &mut Interp, name: &str, raw: &mut [ArgVal]) -> VbResult<Option<Value>> {
    if !is_builtin(name) {
        return Ok(None);
    }
    // Arguments arrive as variants; object arguments use their default value
    // except where the function inspects the object itself.
    let keep_objects = matches!(
        name,
        "typename" | "vartype" | "isobject" | "isarray" | "isempty" | "isnull"
            | "lbound" | "ubound" | "join" | "filter" | "getref" | "isdate"
            | "isnumeric" | "array"
    );
    let mut args: Vec<Option<Value>> = Vec::with_capacity(raw.len());
    for a in raw.iter() {
        if a.is_missing() {
            args.push(None);
            continue;
        }
        let v = a.value();
        let v = if keep_objects { v } else { it.deref_value(v)? };
        args.push(Some(v));
    }
    let a = Args(args);
    dispatch(it, name, &a).map(Some)
}

fn dispatch(it: &mut Interp, name: &str, a: &Args) -> VbResult<Value> {
    use datetime as dt;
    match name {
        // ---- conversion -------------------------------------------------
        "cbool" => conv::cbool(a.req(0)?),
        "cbyte" => conv::cbyte(a.req(0)?),
        "ccur" => conv::ccur(a.req(0)?),
        "cdbl" => conv::cdbl(a.req(0)?),
        "cint" => conv::cint(a.req(0)?),
        "clng" => conv::clng(a.req(0)?),
        "csng" => conv::csng(a.req(0)?),
        "cstr" => conv::cstr(a.req(0)?),
        "cdate" => {
            let v = a.req(0)?;
            if v.is_null() {
                return Err(err::invalid_use_of_null());
            }
            Ok(Value::Date(dt::to_date(v)?))
        }
        "int" => conv::int(a.req(0)?),
        "fix" => conv::fix(a.req(0)?),
        "round" => conv::round(a.req(0)?, a.int_or(1, 0)?),
        "sgn" => conv::sgn(a.req(0)?),
        "abs" => conv::abs(a.req(0)?),
        "hex" => conv::hex(a.req(0)?),
        "oct" => conv::oct(a.req(0)?),
        "cverr" => Ok(Value::ErrCode(a.int_or(0, 0)?)),
        "asc" => conv::asc(a.req(0)?, false),
        "ascw" => conv::asc(a.req(0)?, true),
        "ascb" => strings::ascb(a.req(0)?),
        "chr" => conv::chr(a.req(0)?, false),
        "chrw" => conv::chr(a.req(0)?, true),
        "chrb" => strings::chrb(a.req(0)?),

        // ---- strings ----------------------------------------------------
        "len" => strings::len(a.req(0)?),
        "lenb" => strings::lenb(a.req(0)?),
        "left" => strings::left(a.req(0)?, a.int_or(1, 0)?, false),
        "leftb" => strings::left(a.req(0)?, a.int_or(1, 0)?, true),
        "right" => strings::right(a.req(0)?, a.int_or(1, 0)?, false),
        "rightb" => strings::right(a.req(0)?, a.int_or(1, 0)?, true),
        "mid" | "midb" => {
            // Argument checks run left to right over length, then start,
            // and only afterwards is a Null subject turned into Null.
            let count = match a.get(2) {
                None => None,
                Some(v) if v.is_null() => return Err(err::invalid_use_of_null()),
                Some(_) => Some(a.int_or(2, 0)?),
            };
            let start = match a.get(1) {
                Some(v) if v.is_null() => return Err(err::invalid_use_of_null()),
                _ => a.int_or(1, 1)?,
            };
            strings::mid(a.req(0)?, start, count, name == "midb")
        }
        "instr" | "instrb" => {
            // With three or more arguments the first is the start position.
            let (start, s1, s2, cmp) = if a.count() >= 3 {
                (a.int_or(0, 1)?, a.req(1)?, a.req(2)?, a.int_or(3, 0)?)
            } else {
                (1, a.req(0)?, a.req(1)?, 0)
            };
            if name == "instr" {
                strings::instr(start, s1, s2, cmp)
            } else {
                strings::instrb(start, s1, s2, cmp)
            }
        }
        "instrrev" => strings::instrrev(a.req(0)?, a.req(1)?, a.int_or(2, -1)?, a.int_or(3, 0)?),
        "lcase" => strings::lcase(a.req(0)?),
        "ucase" => strings::ucase(a.req(0)?),
        "ltrim" => strings::trim(a.req(0)?, true, false),
        "rtrim" => strings::trim(a.req(0)?, false, true),
        "trim" => strings::trim(a.req(0)?, true, true),
        "space" => strings::space(a.int_or(0, 0)?),
        "string" => strings::string_fn(a.int_or(0, 0)?, a.req(1)?),
        "strcomp" => {
            if a.count() > 3 {
                return Err(err::wrong_arg_count());
            }
            strings::strcomp(a.req(0)?, a.req(1)?, a.int_or(2, 0)?)
        }
        "strreverse" => strings::strreverse(a.req(0)?),
        "replace" => strings::replace(
            a.req(0)?,
            a.req(1)?,
            a.req(2)?,
            a.int_or(3, 1)?,
            a.int_or(4, -1)?,
            a.int_or(5, 0)?,
        ),
        "split" => {
            let parts = strings::split(
                a.req(0)?,
                a.get(1).unwrap_or(&Value::Str(Rc::from(" "))),
                a.int_or(2, -1)?,
                a.int_or(3, 0)?,
            )?;
            Ok(Value::Array(Rc::new(VbArray::from_values(parts))))
        }
        "join" => {
            if a.count() > 2 {
                return Err(err::wrong_arg_count());
            }
            // Join reports a Null argument as an invalid use of Null.
            if a.req(0)?.is_null() {
                return Err(err::invalid_use_of_null());
            }
            let v = as_array(it, a.req(0)?.clone())?;
            let items = array_items(&v)?;
            // A Null delimiter is rejected outright.
            let delim = match a.get(1) {
                Some(d) if d.is_null() => return Err(err::invalid_use_of_null()),
                _ => a.str_or(1, " ")?,
            };
            strings::join(&items, &delim)
        }
        "filter" => {
            if a.req(0)?.is_null() {
                return Err(err::invalid_use_of_null());
            }
            let v = as_array(it, a.req(0)?.clone())?;
            let items = array_items(&v)?;
            let out = strings::filter(
                &items,
                a.req(1)?,
                match a.get(2) {
                    None => true,
                    Some(v) => v.to_bool()?,
                },
                a.int_or(3, 0)?,
            )?;
            Ok(Value::Array(Rc::new(VbArray::from_values(out))))
        }
        "escape" => strings::escape(a.req(0)?),
        "unescape" => strings::unescape(a.req(0)?),

        // ---- math -------------------------------------------------------
        "atn" => math1(a.req(0)?, f64::atan),
        "cos" => math1(a.req(0)?, f64::cos),
        "sin" => math1(a.req(0)?, f64::sin),
        "tan" => math1(a.req(0)?, f64::tan),
        "exp" => math1(a.req(0)?, f64::exp),
        "log" => {
            let v = a.req(0)?;
            if v.is_null() {
                return Ok(Value::Null);
            }
            let n = v.to_f64()?;
            if n <= 0.0 {
                return Err(err::invalid_call());
            }
            Ok(Value::R8(n.ln()))
        }
        "sqr" => {
            let v = a.req(0)?;
            if v.is_null() {
                return Ok(Value::Null);
            }
            let n = v.to_f64()?;
            if n < 0.0 {
                return Err(err::invalid_call());
            }
            Ok(Value::R8(n.sqrt()))
        }
        "rnd" => {
            let n = match a.get(0) {
                None => 1.0,
                Some(v) => v.to_f64()?,
            };
            Ok(Value::R4(it_rnd(it, n)))
        }
        "randomize" => {
            let seed = match a.get(0) {
                None => host_now(it) * 86400.0,
                Some(v) => v.to_f64()?,
            };
            // Randomize mixes into the current state rather than replacing
            // it, so the sequence depends on where the generator already was.
            it.rng = (it.rng ^ (seed as i64 as u32)) & 0x00FF_FFFF;
            Ok(Value::Empty)
        }

        // ---- date and time ----------------------------------------------
        "date" => Ok(Value::Date(host_now(it).floor())),
        "time" => {
            let n = host_now(it);
            Ok(Value::Date(n - n.floor()))
        }
        "now" => {
            // `Now` is accurate to the second.
            let n = host_now(it);
            Ok(Value::Date((n * 86400.0).round() / 86400.0))
        }
        "timer" => {
            let n = host_now(it);
            Ok(Value::R4(((n - n.floor()) * 86400.0) as f32))
        }
        "dateserial" => {
            let (y, m, d) = (a.req(0)?, a.req(1)?, a.req(2)?);
            // Unlike DateDiff, DateSerial rejects Null rather than
            // propagating it.
            if y.is_null() || m.is_null() || d.is_null() {
                return Err(err::invalid_use_of_null());
            }
            Ok(Value::Date(dt::date_serial(y.to_f64()?, m.to_f64()?, d.to_f64()?)?))
        }
        "timeserial" => {
            let (h, m, s) = (a.req(0)?, a.req(1)?, a.req(2)?);
            if h.is_null() || m.is_null() || s.is_null() {
                return Err(err::invalid_use_of_null());
            }
            Ok(Value::Date(dt::time_serial(h.to_f64()?, m.to_f64()?, s.to_f64()?)?))
        }
        "datevalue" => {
            let v = a.req(0)?;
            if v.is_null() {
                return Err(err::invalid_use_of_null());
            }
            // DateValue parses text; a bare number is not a date to it.
            Ok(Value::Date(text_date(v)?.trunc()))
        }
        "timevalue" => {
            let v = a.req(0)?;
            if v.is_null() {
                return Err(err::invalid_use_of_null());
            }
            let (_, frac) = dt::split(text_date(v)?);
            Ok(Value::Date(frac))
        }
        "year" | "month" | "day" | "hour" | "minute" | "second" => {
            let v = a.req(0)?;
            if v.is_null() {
                return Ok(Value::Null);
            }
            let d = dt::to_date(v)?;
            let (y, m, dd) = dt::to_ymd(d);
            let (h, mi, s) = dt::to_hms(d);
            Ok(Value::I2(match name {
                "year" => y as i16,
                "month" => m as i16,
                "day" => dd as i16,
                "hour" => h as i16,
                "minute" => mi as i16,
                _ => s as i16,
            }))
        }
        "weekday" => {
            // The first-day-of-week argument is validated first, so
            // `Weekday(Null, -1)` reports the bad argument, not Null.
            let fdow = a.int_or(1, 1)?;
            if !(0..=7).contains(&fdow) {
                return Err(err::invalid_call());
            }
            let v = a.req(0)?;
            if v.is_null() {
                return Ok(Value::Null);
            }
            Ok(Value::I2(dt::weekday(dt::to_date(v)?, fdow)? as i16))
        }
        "monthname" => {
            // The abbreviate flag is validated before the month number.
            let abbr = match a.get(1) {
                None => false,
                Some(v) if v.is_null() => return Err(err::invalid_use_of_null()),
                Some(v) => v.to_bool()?,
            };
            if a.req(0)?.is_null() {
                return Err(err::invalid_use_of_null());
            }
            Ok(Value::Str(dt::month_name(a.int_or(0, 1)?, abbr)?))
        }
        "weekdayname" => {
            let abbr = match a.get(1) {
                None => false,
                Some(v) if v.is_null() => return Err(err::invalid_use_of_null()),
                Some(v) => v.to_bool()?,
            };
            if a.req(0)?.is_null() {
                return Err(err::invalid_use_of_null());
            }
            Ok(Value::Str(dt::weekday_name(a.int_or(0, 1)?, abbr, a.int_or(2, 1)?)?))
        }
        "dateadd" => {
            let (iv, n, d) = (a.req(0)?, a.req(1)?, a.req(2)?);
            if iv.is_null() || n.is_null() {
                return Err(err::invalid_use_of_null());
            }
            if d.is_null() {
                return Ok(Value::Null);
            }
            let interval = dt::parse_interval(&iv.to_vb_string()?)?;
            Ok(Value::Date(dt::date_add(interval, n.to_f64()?, dt::to_date(d)?)?))
        }
        "datediff" => {
            let (iv, d1, d2) = (a.req(0)?, a.req(1)?, a.req(2)?);
            if iv.is_null() {
                return Err(err::invalid_use_of_null());
            }
            if d1.is_null() || d2.is_null() {
                return Ok(Value::Null);
            }
            let interval = dt::parse_interval(&iv.to_vb_string()?)?;
            let r = dt::date_diff(
                interval,
                dt::to_date(d1)?,
                dt::to_date(d2)?,
                a.int_or(3, 1)?,
                a.int_or(4, 1)?,
            )?;
            Ok(if r.abs() <= i32::MAX as f64 {
                Value::I4(r as i32)
            } else {
                Value::R8(r)
            })
        }
        "datepart" => {
            let (iv, d) = (a.req(0)?, a.req(1)?);
            if iv.is_null() {
                return Err(err::invalid_use_of_null());
            }
            if d.is_null() {
                return Ok(Value::Null);
            }
            let interval = dt::parse_interval(&iv.to_vb_string()?)?;
            let r = dt::date_part(interval, dt::to_date(d)?, a.int_or(2, 1)?, a.int_or(3, 1)?)?;
            Ok(Value::I2(r as i16))
        }

        // ---- information -------------------------------------------------
        "vartype" => Ok(Value::I2(a.req(0)?.vartype() as i16)),
        "typename" => Ok(Value::str(type_name(a.req(0)?))),
        "isarray" => Ok(Value::Bool(a.req(0)?.is_array())),
        "isempty" => Ok(Value::Bool(a.req(0)?.is_empty())),
        "isnull" => Ok(Value::Bool(a.req(0)?.is_null())),
        "isobject" => Ok(Value::Bool(a.req(0)?.is_object())),
        "isnumeric" => {
            let v = a.req(0)?.clone();
            // An object is numeric when its default property is; one without
            // a usable default simply is not.
            let v = match v {
                Value::Obj(_) => match it.deref_value(v) {
                    Ok(inner) => inner,
                    Err(_) => return Ok(Value::Bool(false)),
                },
                other => other,
            };
            Ok(Value::Bool(match &v {
                Value::Str(s) => parse_number(s).is_some(),
                Value::Obj(_) | Value::Array(_) | Value::Null => false,
                _ => true,
            }))
        }
        "isdate" => {
            // Numbers are convertible to dates but are not dates themselves.
            Ok(Value::Bool(match a.req(0)? {
                Value::Date(_) => true,
                Value::Str(s) => datetime::parse_date(s).is_some(),
                _ => false,
            }))
        }
        "lbound" | "ubound" => {
            if a.count() > 2 {
                return Err(err::wrong_arg_count());
            }
            let v = a.req(0)?.clone();
            let v = as_array(it, v)?;
            let arr = match &v {
                Value::Array(x) => x,
                _ => return Err(err::type_mismatch()),
            };
            let d = a.int_or(1, 1)?;
            if d < 1 {
                return Err(err::invalid_call());
            }
            if !arr.is_sized() || d as usize > arr.dims.len() {
                return Err(err::subscript());
            }
            Ok(Value::I4(if name == "lbound" {
                0
            } else {
                arr.dims[d as usize - 1] as i32 - 1
            }))
        }
        "array" => {
            let items: Vec<Value> =
                a.0.iter().map(|o| o.clone().unwrap_or(Value::Empty)).collect();
            Ok(Value::Array(Rc::new(VbArray::from_values(items))))
        }
        "eval" => {
            // Null and Empty pass straight through rather than being
            // compiled as source text.
            match a.req(0)? {
                Value::Null => Ok(Value::Null),
                Value::Empty => Ok(Value::Empty),
                v => {
                    let src = v.to_vb_string()?;
                    it.eval_source(&src)
                }
            }
        }
        "execute" | "executeglobal" => {
            // Only source text can be executed.
            let src = match a.req(0)? {
                Value::Str(s) => s.clone(),
                _ => return Err(err::type_mismatch()),
            };
            it.execute(&src, name == "executeglobal")?;
            Ok(Value::Empty)
        }
        "getref" => {
            // The argument must be a procedure name, given as a string.
            let n = match a.req(0)? {
                Value::Str(s) => s.clone(),
                _ => return Err(err::type_mismatch()),
            };
            let key: Rc<str> = n.to_ascii_lowercase().into();
            if let Some(f) = it.funcs.get(&key) {
                return Ok(Value::Obj(Some(ObjKind::FuncRef(f.clone()))));
            }
            if is_builtin(&key) {
                return Ok(Value::Obj(Some(ObjKind::BuiltinRef(key))));
            }
            Err(err::invalid_call())
        }
        "createobject" | "getobject" => {
            let progid = a.req(0)?.to_vb_string()?;
            create_object(it, &progid)
        }
        "getlocale" => Ok(Value::I4(it.locale)),
        "setlocale" => {
            let prev = it.locale;
            match a.get(0) {
                // No argument restores the system default.
                None => it.locale = DEFAULT_LOCALE,
                Some(v) => {
                    let n = match v {
                        // A string is either a locale name or its numeric id.
                        Value::Str(s) => lcid_from_name(s)
                            .or_else(|| parse_number(s).map(|n| n as i32))
                            .ok_or_else(err::invalid_call)?,
                        _ => a.int_or(0, DEFAULT_LOCALE)?,
                    };
                    if n == 0 {
                        it.locale = DEFAULT_LOCALE;
                    } else if !(1..=0xFFFF).contains(&n) {
                        // Not a locale identifier at all.
                        return Err(VbError::code(447));
                    } else {
                        it.locale = n;
                    }
                }
            }
            crate::locale::set(it.locale);
            Ok(Value::I4(prev))
        }
        "rgb" => {
            let r = clamp_byte(a.int_or(0, 0)?)?;
            let g = clamp_byte(a.int_or(1, 0)?)?;
            let b = clamp_byte(a.int_or(2, 0)?)?;
            Ok(Value::I4(r | (g << 8) | (b << 16)))
        }
        "scriptengine" => Ok(Value::str("VBScript")),
        "scriptenginemajorversion" => Ok(Value::I4(5)),
        "scriptengineminorversion" => Ok(Value::I4(8)),
        "scriptenginebuildversion" => Ok(Value::I4(16996)),

        "formatnumber" => format::format_number(
            a.req(0)?,
            a.int_or(1, USE_DEFAULT)?,
            a.int_or(2, USE_DEFAULT)?,
            a.int_or(3, USE_DEFAULT)?,
            a.int_or(4, USE_DEFAULT)?,
        ),
        "formatcurrency" => format::format_currency(
            a.req(0)?,
            a.int_or(1, USE_DEFAULT)?,
            a.int_or(2, USE_DEFAULT)?,
            a.int_or(3, USE_DEFAULT)?,
            a.int_or(4, USE_DEFAULT)?,
        ),
        "formatpercent" => format::format_percent(
            a.req(0)?,
            a.int_or(1, USE_DEFAULT)?,
            a.int_or(2, USE_DEFAULT)?,
            a.int_or(3, USE_DEFAULT)?,
            a.int_or(4, USE_DEFAULT)?,
        ),
        "formatdatetime" => format::format_datetime(a.req(0)?, a.int_or(1, 0)?),

        "msgbox" => {
            let text = a.req(0)?.to_vb_string()?;
            let host = it.host.clone();
            host.echo(&text);
            Ok(Value::I2(1))
        }
        "inputbox" => Ok(Value::str("")),

        _ => Err(err::sub_not_defined(name)),
    }
}

/// `DateValue`/`TimeValue` accept only text and dates, never a serial number.
fn text_date(v: &Value) -> VbResult<f64> {
    match v {
        Value::Date(d) => Ok(*d),
        Value::Str(s) => datetime::parse_date(s).ok_or_else(err::type_mismatch),
        _ => Err(err::type_mismatch()),
    }
}

/// The current time as an OLE date, read from the host so a browser build
/// can supply its own clock.
fn host_now(it: &Interp) -> f64 {
    datetime::ole_from_unix_millis(it.host.now_unix_millis())
}

fn clamp_byte(v: i32) -> VbResult<i32> {
    if v < 0 {
        return Err(err::invalid_call());
    }
    Ok(v.min(255))
}

fn math1(v: &Value, f: fn(f64) -> f64) -> VbResult<Value> {
    if v.is_null() {
        return Ok(Value::Null);
    }
    Ok(Value::R8(f(v.to_f64()?)))
}

/// The classic VB linear congruential generator, whose state is 24 bits.
fn it_rnd(it: &mut Interp, n: f64) -> f32 {
    // Zero repeats the current value without advancing the sequence.
    if n == 0.0 {
        return it.rng as f32 / 16_777_216.0;
    }
    if n < 0.0 {
        // A negative argument reseeds from its own bit pattern, so the same
        // argument always yields the same number.
        it.rng = (n as f32).to_bits() & 0x00FF_FFFF;
    }
    it.rng = it.rng.wrapping_mul(0x43FD_43FD).wrapping_add(0x00C3_9EC3) & 0x00FF_FFFF;
    it.rng as f32 / 16_777_216.0
}

pub fn type_name(v: &Value) -> String {
    match v {
        Value::Empty => "Empty".into(),
        Value::Null => "Null".into(),
        Value::Bool(_) => "Boolean".into(),
        Value::UI1(_) => "Byte".into(),
        Value::I2(_) => "Integer".into(),
        Value::I4(_) => "Long".into(),
        Value::R4(_) => "Single".into(),
        Value::R8(_) => "Double".into(),
        Value::Cy(_) => "Currency".into(),
        Value::Date(_) => "Date".into(),
        Value::Str(_) => "String".into(),
        Value::ErrCode(_) => "Error".into(),
        Value::Obj(None) => "Nothing".into(),
        Value::Obj(Some(o)) => match o {
            ObjKind::RegExp(_) => "IRegExp2".into(),
            ObjKind::Matches(_) => "IMatchCollection2".into(),
            ObjKind::Match(_) => "IMatch2".into(),
            ObjKind::SubMatches(_) => "ISubMatches".into(),
            other => other.type_name(),
        },
        Value::Array(_) => "Variant()".into(),
        Value::Unsupported(_) => "Variant".into(),
    }
}

/// Resolve an object argument to the array its default property yields.
fn as_array(it: &mut Interp, v: Value) -> VbResult<Value> {
    match v {
        Value::Null => Err(err::type_mismatch()),
        Value::Obj(None) => Err(err::object_not_set()),
        Value::Obj(Some(_)) => it.deref_value(v),
        other => Ok(other),
    }
}

fn array_items(v: &Value) -> VbResult<Vec<Value>> {
    match v {
        Value::Array(a) => {
            if !a.is_sized() {
                return Err(err::subscript());
            }
            // These functions work on a list, so a multidimensional array is
            // the wrong shape.
            if a.dims.len() > 1 {
                return Err(err::type_mismatch());
            }
            Ok(a.data.clone())
        }
        _ => Err(err::type_mismatch()),
    }
}

fn create_object(it: &mut Interp, progid: &str) -> VbResult<Value> {
    let p = progid.to_ascii_lowercase();
    match p.as_str() {
        "scripting.dictionary" => Ok(Value::Obj(Some(ObjKind::Dictionary(Rc::new(
            RefCell::new(Dictionary::new()),
        ))))),
        "vbscript.regexp" => Ok(Value::Obj(Some(ObjKind::RegExp(Rc::new(RefCell::new(
            RegExpObj::new(),
        )))))),
        _ => {
            let host = it.host.clone();
            let r = host.create_object(it, progid)?;
            r.ok_or_else(err::cant_create_object)
        }
    }
}

fn lcid_from_name(s: &str) -> Option<i32> {
    Some(match s.to_ascii_lowercase().as_str() {
        "en-us" => 1033,
        "en-gb" => 2057,
        "de-de" => 1031,
        "fr-fr" => 1036,
        "es-es" => 3082,
        "it-it" => 1040,
        "ja-jp" => 1041,
        _ => return None,
    })
}
