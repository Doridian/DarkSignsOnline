//! Date and time built-ins.
//!
//! Dates are OLE Automation dates: a count of days since 1899-12-30, where
//! the integer part is the day and the *absolute* fractional part is the time
//! of day. That sign convention means -1.25 is 1899-12-29 06:00, not 18:00.

use std::rc::Rc;

use crate::error::{err, VbResult};
use crate::value::{round_half_even, Value};

/// OLE day number of the Unix epoch, 1970-01-01.
const UNIX_EPOCH_OLE: i64 = 25569;

pub const MONTHS: [&str; 12] = [
    "January", "February", "March", "April", "May", "June", "July", "August",
    "September", "October", "November", "December",
];
pub const MONTHS_ABBR: [&str; 12] = [
    "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
];
pub const WEEKDAYS: [&str; 7] = [
    "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday",
];
pub const WEEKDAYS_ABBR: [&str; 7] = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];

/// Days from 1970-01-01 to the given civil date (Howard Hinnant's algorithm).
pub fn days_from_civil(y: i32, m: i32, d: i32) -> i64 {
    let y = if m <= 2 { y - 1 } else { y } as i64;
    let era = if y >= 0 { y } else { y - 399 } / 400;
    let yoe = y - era * 400;
    let mp = ((m + 9) % 12) as i64;
    let doy = (153 * mp + 2) / 5 + d as i64 - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    era * 146097 + doe - 719468
}

pub fn civil_from_days(z: i64) -> (i32, i32, i32) {
    let z = z + 719468;
    let era = if z >= 0 { z } else { z - 146096 } / 146097;
    let doe = z - era * 146097;
    let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
    let y = yoe + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    ((if m <= 2 { y + 1 } else { y }) as i32, m as i32, d as i32)
}

/// Split an OLE date into its day number and time-of-day in days.
pub fn split(v: f64) -> (i64, f64) {
    let day = v.trunc();
    let mut frac = (v - day).abs();
    // Guard against a rounding artefact producing a full day.
    if frac >= 1.0 {
        frac = 0.0;
    }
    (day as i64, frac)
}

pub fn to_ymd(v: f64) -> (i32, i32, i32) {
    let (day, _) = split(v);
    civil_from_days(day - UNIX_EPOCH_OLE)
}

/// Hours, minutes, seconds of an OLE date.
pub fn to_hms(v: f64) -> (i32, i32, i32) {
    let (_, frac) = split(v);
    // Seconds are stored approximately, so round to the nearest second.
    let total = round_half_even(frac * 86400.0) as i64;
    let total = total.clamp(0, 86400);
    let (total, carry) = if total == 86400 { (0, 1) } else { (total, 0) };
    let _ = carry;
    ((total / 3600) as i32, ((total / 60) % 60) as i32, (total % 60) as i32)
}

pub fn from_ymd(y: i32, m: i32, d: i32) -> f64 {
    (days_from_civil(y, m, d) + UNIX_EPOCH_OLE) as f64
}

/// Combine a day number and a time-of-day, honouring the sign convention.
pub fn combine(days: f64, time: f64) -> f64 {
    if days < 0.0 {
        days - time
    } else {
        days + time
    }
}

/// 1 = Sunday, matching `vbSunday`.
pub fn weekday_of(v: f64) -> i32 {
    let (day, _) = split(v);
    // OLE day 0 (1899-12-30) was a Saturday.
    (((day % 7) + 7 + 6) % 7 + 1) as i32
}

pub fn now_ole() -> f64 {
    let d = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default();
    UNIX_EPOCH_OLE as f64 + d.as_secs_f64() / 86400.0
}

// ---- formatting ----------------------------------------------------------

pub fn format_time_12h(v: f64, with_seconds: bool) -> String {
    let (h, m, s) = to_hms(v);
    let ampm = if h < 12 { "AM" } else { "PM" };
    let h12 = match h % 12 {
        0 => 12,
        x => x,
    };
    if with_seconds {
        format!("{h12}:{m:02}:{s:02} {ampm}")
    } else {
        format!("{h12}:{m:02} {ampm}")
    }
}

pub fn format_short_date(v: f64) -> String {
    let (y, m, d) = to_ymd(v);
    format!("{m}/{d}/{y}")
}

pub fn format_long_date(v: f64) -> String {
    let (y, m, d) = to_ymd(v);
    let wd = weekday_of(v);
    format!("{}, {} {}, {}", WEEKDAYS[(wd - 1) as usize], MONTHS[(m - 1) as usize], d, y)
}

/// How a `VT_DATE` renders when converted to a string.
pub fn format_date_default(v: f64) -> String {
    let (day, frac) = split(v);
    let has_time = frac != 0.0;
    let has_date = day != 0;
    match (has_date, has_time) {
        (true, false) => format_short_date(v),
        (false, true) => format_time_12h(v, true),
        (false, false) => format_short_date(v),
        (true, true) => format!("{} {}", format_short_date(v), format_time_12h(v, true)),
    }
}

// ---- parsing -------------------------------------------------------------

/// Parse a date/time in the formats VBScript accepts for `#...#` and `CDate`.
pub fn parse_date(text: &str) -> Option<f64> {
    let t = text.trim();
    if t.is_empty() {
        return None;
    }
    // Split into a date part and a time part; either may be absent.
    let mut date: Option<(i32, i32, i32)> = None;
    let mut time: Option<f64> = None;

    // Find an AM/PM marker so it stays with the time component.
    let mut tokens: Vec<&str> = t.split_whitespace().collect();
    let mut ampm: Option<bool> = None;
    if let Some(last) = tokens.last() {
        let l = last.to_ascii_lowercase();
        if l == "am" || l == "a.m." {
            ampm = Some(false);
            tokens.pop();
        } else if l == "pm" || l == "p.m." {
            ampm = Some(true);
            tokens.pop();
        }
    }
    // A trailing AM/PM may also be glued to the time, e.g. "10:00PM".
    if ampm.is_none() {
        if let Some(last) = tokens.last_mut() {
            let l = last.to_ascii_lowercase();
            if l.ends_with("am") && l.len() > 2 {
                ampm = Some(false);
                *last = &last[..last.len() - 2];
            } else if l.ends_with("pm") && l.len() > 2 {
                ampm = Some(true);
                *last = &last[..last.len() - 2];
            }
        }
    }

    for tokgroup in split_date_tokens(&tokens) {
        if tokgroup.contains(':') {
            time = parse_time(&tokgroup, ampm)?.into();
        } else if date.is_none() {
            date = parse_date_part(&tokgroup)?.into();
        } else {
            return None;
        }
    }
    // A bare "3 PM" is a time.
    if date.is_some() && time.is_none() && ampm.is_some() {
        let (y, m, d) = date.unwrap();
        if y == 0 && m == 0 {
            time = parse_time(&d.to_string(), ampm)?.into();
            date = None;
        }
    }
    if date.is_none() && time.is_none() {
        return None;
    }
    let days = match date {
        Some((y, m, d)) => {
            if !valid_ymd(y, m, d) {
                return None;
            }
            from_ymd(y, m, d)
        }
        None => 0.0,
    };
    Some(combine(days, time.unwrap_or(0.0)))
        .filter(|v| (-657_434.0..=2_958_465.999_999_999).contains(v))
}

/// Re-join tokens so "January 1, 2000" stays one date group while a time
/// stays separate.
fn split_date_tokens(tokens: &[&str]) -> Vec<String> {
    let mut date_parts: Vec<String> = Vec::new();
    let mut out: Vec<String> = Vec::new();
    for t in tokens {
        if t.contains(':') {
            out.push((*t).to_string());
        } else {
            date_parts.push(t.trim_end_matches(',').to_string());
        }
    }
    if !date_parts.is_empty() {
        out.insert(0, date_parts.join(" "));
    }
    out
}

fn valid_ymd(y: i32, m: i32, d: i32) -> bool {
    if !(1..=12).contains(&m) || d < 1 {
        return false;
    }
    d <= days_in_month(y, m)
}

pub fn days_in_month(y: i32, m: i32) -> i32 {
    match m {
        1 | 3 | 5 | 7 | 8 | 10 | 12 => 31,
        4 | 6 | 9 | 11 => 30,
        2 => {
            if (y % 4 == 0 && y % 100 != 0) || y % 400 == 0 {
                29
            } else {
                28
            }
        }
        _ => 0,
    }
}

fn month_from_name(s: &str) -> Option<i32> {
    let l = s.to_ascii_lowercase();
    for (i, m) in MONTHS.iter().enumerate() {
        if m.to_ascii_lowercase() == l {
            return Some(i as i32 + 1);
        }
    }
    for (i, m) in MONTHS_ABBR.iter().enumerate() {
        if m.to_ascii_lowercase() == l || format!("{}.", m.to_ascii_lowercase()) == l {
            return Some(i as i32 + 1);
        }
    }
    None
}

fn parse_date_part(s: &str) -> Option<(i32, i32, i32)> {
    // Named-month forms: "January 1 2000", "1 January 2000".
    let words: Vec<&str> = s.split_whitespace().collect();
    if words.len() >= 2 {
        if let Some(m) = month_from_name(words[0]) {
            let d: i32 = words[1].parse().ok()?;
            let y: i32 = words.get(2).and_then(|w| w.parse().ok()).unwrap_or_else(current_year);
            return Some((normalize_year(y), m, d));
        }
        if let Some(m) = month_from_name(words[1]) {
            let d: i32 = words[0].parse().ok()?;
            let y: i32 = words.get(2).and_then(|w| w.parse().ok()).unwrap_or_else(current_year);
            return Some((normalize_year(y), m, d));
        }
    }

    let order = crate::locale::conventions().date_order;
    // A day-first locale also accepts the dotted form, 15.03.2026.
    let sep = if s.contains('/') {
        '/'
    } else if s.contains('-') {
        '-'
    } else if s.contains('.') && order == crate::locale::DateOrder::Dmy {
        '.'
    } else {
        return None;
    };
    let parts: Vec<&str> = s.split(sep).collect();
    let nums: Option<Vec<i32>> = parts.iter().map(|p| p.trim().parse::<i32>().ok()).collect();
    let nums = nums?;
    let (first, second) = match order {
        crate::locale::DateOrder::Mdy => (0usize, 1usize),
        crate::locale::DateOrder::Dmy => (1usize, 0usize),
    };
    match nums.len() {
        // ISO order when the first field is a full year.
        3 if parts[0].len() == 4 => Some((nums[0], nums[1], nums[2])),
        3 => Some((normalize_year(nums[2]), nums[first], nums[second])),
        2 => Some((current_year(), nums[first], nums[second])),
        _ => None,
    }
}

/// Two-digit years map into 1930..2029, as VBScript does.
pub fn normalize_year(y: i32) -> i32 {
    if (0..=29).contains(&y) {
        2000 + y
    } else if (30..=99).contains(&y) {
        1900 + y
    } else {
        y
    }
}

fn current_year() -> i32 {
    to_ymd(now_ole()).0
}

fn parse_time(s: &str, ampm: Option<bool>) -> Option<f64> {
    let parts: Vec<&str> = s.split(':').collect();
    if parts.is_empty() || parts.len() > 3 {
        return None;
    }
    let mut h: i32 = parts[0].trim().parse().ok()?;
    let m: i32 = parts.get(1).map(|p| p.trim().parse().ok()).unwrap_or(Some(0))?;
    let sec: f64 = parts.get(2).map(|p| p.trim().parse().ok()).unwrap_or(Some(0.0))?;
    match ampm {
        Some(true) if h < 12 => h += 12,
        Some(false) if h == 12 => h = 0,
        _ => {}
    }
    if !(0..=23).contains(&h) || !(0..=59).contains(&m) || !(0.0..60.0).contains(&sec) {
        return None;
    }
    Some((h as f64 * 3600.0 + m as f64 * 60.0 + sec) / 86400.0)
}

/// `CDate` conversion from any value.
pub fn to_date(v: &Value) -> VbResult<f64> {
    match v {
        Value::Date(d) => Ok(*d),
        // A string that is not a date but is a number is taken as a serial
        // date, which is how CDate behaves.
        Value::Str(s) => parse_date(s)
            .or_else(|| crate::value::parse_number(s).filter(|n| (-657_434.0..=2_958_465.999_999_999).contains(n)))
            .ok_or_else(err::type_mismatch),
        Value::Null => Err(err::invalid_use_of_null()),
        Value::Empty => Ok(0.0),
        Value::Obj(_) | Value::Array(_) => Err(err::type_mismatch()),
        _ => {
            let n = v.to_f64()?;
            if !(-657_434.0..=2_958_465.999_999_999).contains(&n) {
                return Err(err::overflow());
            }
            Ok(n)
        }
    }
}

/// `DateSerial`: out-of-range months and days roll over into adjacent periods.
pub fn date_serial(y: f64, m: f64, d: f64) -> VbResult<f64> {
    let y = round_half_even(y) as i64;
    let m = round_half_even(m) as i64;
    let d = round_half_even(d) as i64;
    let y = if (0..=99).contains(&y) { normalize_year(y as i32) as i64 } else { y };

    // Normalize the month into 1..12, carrying into the year.
    let total_months = y * 12 + (m - 1);
    let ny = total_months.div_euclid(12);
    let nm = total_months.rem_euclid(12) + 1;
    if !(-32768..=32767).contains(&ny) {
        return Err(err::invalid_call());
    }
    let base = days_from_civil(ny as i32, nm as i32, 1);
    let days = base + d - 1 + UNIX_EPOCH_OLE;
    let v = days as f64;
    if !(-657_434.0..=2_958_465.999_999_999).contains(&v) {
        return Err(err::invalid_call());
    }
    Ok(v)
}

pub fn time_serial(h: f64, m: f64, s: f64) -> VbResult<f64> {
    let total = round_half_even(h) * 3600.0 + round_half_even(m) * 60.0 + round_half_even(s);
    let v = total / 86400.0;
    if !(-657_434.0..=2_958_465.999_999_999).contains(&v) {
        return Err(err::invalid_call());
    }
    Ok(v)
}

/// Interval codes shared by DateAdd, DateDiff and DatePart.
#[derive(Clone, Copy, PartialEq, Eq)]
pub enum Interval {
    Year,
    Quarter,
    Month,
    DayOfYear,
    Day,
    Weekday,
    Week,
    Hour,
    Minute,
    Second,
}

pub fn parse_interval(s: &str) -> VbResult<Interval> {
    Ok(match s.to_ascii_lowercase().as_str() {
        "yyyy" => Interval::Year,
        "q" => Interval::Quarter,
        "m" => Interval::Month,
        "y" => Interval::DayOfYear,
        "d" => Interval::Day,
        "w" => Interval::Weekday,
        "ww" => Interval::Week,
        "h" => Interval::Hour,
        "n" => Interval::Minute,
        "s" => Interval::Second,
        _ => return Err(err::invalid_call()),
    })
}

pub fn date_add(interval: Interval, number: f64, date: f64) -> VbResult<f64> {
    let n = round_half_even(number);
    let (day, frac) = split(date);
    let out = match interval {
        Interval::Year => shift_months(date, n as i64 * 12)?,
        Interval::Quarter => shift_months(date, n as i64 * 3)?,
        Interval::Month => shift_months(date, n as i64)?,
        Interval::Day | Interval::DayOfYear | Interval::Weekday => {
            combine((day as f64) + n, frac)
        }
        Interval::Week => combine((day as f64) + n * 7.0, frac),
        Interval::Hour => date + n / 24.0,
        Interval::Minute => date + n / 1440.0,
        Interval::Second => date + n / 86400.0,
    };
    if !(-657_434.0..=2_958_465.999_999_999).contains(&out) {
        return Err(err::invalid_call());
    }
    Ok(out)
}

/// Month arithmetic clamps the day to the target month's length.
fn shift_months(date: f64, months: i64) -> VbResult<f64> {
    let (y, m, d) = to_ymd(date);
    let (_, frac) = split(date);
    let total = y as i64 * 12 + (m as i64 - 1) + months;
    let ny = total.div_euclid(12) as i32;
    let nm = total.rem_euclid(12) as i32 + 1;
    let nd = d.min(days_in_month(ny, nm));
    Ok(combine(from_ymd(ny, nm, nd), frac))
}

/// An OLE date as a plain count of days, undoing the convention that keeps
/// the time of day positive while the day number goes negative.
fn linear(v: f64) -> f64 {
    let (day, frac) = split(v);
    day as f64 + frac
}

/// Whole seconds since the epoch, rounded to avoid the drift that scaling a
/// fractional day by 86400 otherwise introduces.
fn secs(v: f64) -> i64 {
    round_half_even(linear(v) * 86400.0) as i64
}

pub fn date_diff(
    interval: Interval,
    a: f64,
    b: f64,
    first_day_of_week: i32,
    first_week_of_year: i32,
) -> VbResult<f64> {
    let (ya, ma, _) = to_ymd(a);
    let (yb, mb, _) = to_ymd(b);
    Ok(match interval {
        Interval::Year => (yb - ya) as f64,
        Interval::Quarter => {
            ((yb * 4 + (mb - 1) / 3) - (ya * 4 + (ma - 1) / 3)) as f64
        }
        Interval::Month => ((yb * 12 + mb) - (ya * 12 + ma)) as f64,
        Interval::Day | Interval::DayOfYear => {
            (linear(b).floor() - linear(a).floor()).trunc()
        }
        Interval::Weekday => ((linear(b).floor() - linear(a).floor()) / 7.0).trunc(),
        Interval::Week => {
            // Whole weeks between the week-start days containing each date.
            let sa = week_start(a, first_day_of_week)?;
            let sb = week_start(b, first_day_of_week)?;
            let _ = first_week_of_year;
            ((sb - sa) / 7.0).trunc()
        }
        // Time intervals count boundaries crossed, not elapsed time, so
        // 11:00 to 01:00 the next day is two hours' worth of boundaries.
        Interval::Hour => (secs(b).div_euclid(3600) - secs(a).div_euclid(3600)) as f64,
        Interval::Minute => (secs(b).div_euclid(60) - secs(a).div_euclid(60)) as f64,
        Interval::Second => (secs(b) - secs(a)) as f64,
    })
}

fn week_start(v: f64, first_day_of_week: i32) -> VbResult<f64> {
    let fdw = if first_day_of_week == 0 { 1 } else { first_day_of_week };
    if !(1..=7).contains(&fdw) {
        return Err(err::invalid_call());
    }
    let wd = weekday_of(v);
    let back = (wd - fdw + 7) % 7;
    Ok(v.floor() - back as f64)
}

pub fn date_part(
    interval: Interval,
    v: f64,
    first_day_of_week: i32,
    first_week_of_year: i32,
) -> VbResult<i32> {
    let (y, m, d) = to_ymd(v);
    let (h, mi, s) = to_hms(v);
    Ok(match interval {
        Interval::Year => y,
        Interval::Quarter => (m - 1) / 3 + 1,
        Interval::Month => m,
        Interval::DayOfYear => {
            (days_from_civil(y, m, d) - days_from_civil(y, 1, 1) + 1) as i32
        }
        Interval::Day => d,
        Interval::Weekday => weekday(v, first_day_of_week)?,
        Interval::Week => week_of_year(v, first_day_of_week, first_week_of_year)?,
        Interval::Hour => h,
        Interval::Minute => mi,
        Interval::Second => s,
    })
}

/// `Weekday`, with 1 meaning `first_day_of_week`.
pub fn weekday(v: f64, first_day_of_week: i32) -> VbResult<i32> {
    let fdw = if first_day_of_week == 0 { 1 } else { first_day_of_week };
    if !(1..=7).contains(&fdw) {
        return Err(err::invalid_call());
    }
    Ok((weekday_of(v) - fdw + 7) % 7 + 1)
}

pub fn week_of_year(v: f64, first_day_of_week: i32, first_week_of_year: i32) -> VbResult<i32> {
    let fdw = if first_day_of_week == 0 { 1 } else { first_day_of_week };
    let fwy = if first_week_of_year == 0 { 1 } else { first_week_of_year };
    if !(1..=7).contains(&fdw) || !(1..=3).contains(&fwy) {
        return Err(err::invalid_call());
    }
    let (y, _, _) = to_ymd(v);
    // Locate the day that starts week 1 under the requested rule.
    let jan1 = from_ymd(y, 1, 1);
    let jan1_wd = weekday_of(jan1);
    let offset_to_start = (jan1_wd - fdw + 7) % 7;
    let first_full_week = jan1 + ((7 - offset_to_start) % 7) as f64;
    let week1_start = match fwy {
        // Week 1 is the week containing January 1.
        1 => jan1 - offset_to_start as f64,
        // Week 1 is the first week with at least four days in the new year.
        2 => {
            if offset_to_start <= 3 {
                jan1 - offset_to_start as f64
            } else {
                first_full_week
            }
        }
        // Week 1 is the first entirely-in-year week.
        _ => first_full_week,
    };
    let n = ((v.floor() - week1_start) / 7.0).floor() as i32 + 1;
    if n >= 1 {
        return Ok(n);
    }
    // The date falls in the last week of the previous year.
    let prev = from_ymd(y - 1, 12, 31);
    week_of_year(prev, first_day_of_week, first_week_of_year)
}

pub fn month_name(m: i32, abbreviate: bool) -> VbResult<Rc<str>> {
    if !(1..=12).contains(&m) {
        return Err(err::invalid_call());
    }
    let t = if abbreviate { MONTHS_ABBR[(m - 1) as usize] } else { MONTHS[(m - 1) as usize] };
    Ok(Rc::from(t))
}

pub fn weekday_name(mut d: i32, abbreviate: bool, first_day_of_week: i32) -> VbResult<Rc<str>> {
    let fdw = if first_day_of_week == 0 { 1 } else { first_day_of_week };
    if !(1..=7).contains(&d) || !(1..=7).contains(&fdw) {
        return Err(err::invalid_call());
    }
    // `d` counts from `first_day_of_week`, so shift back to a Sunday base.
    d = (d - 1 + fdw - 1) % 7;
    let t = if abbreviate { WEEKDAYS_ABBR[d as usize] } else { WEEKDAYS[d as usize] };
    Ok(Rc::from(t))
}
