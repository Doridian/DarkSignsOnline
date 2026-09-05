//! Locale-dependent number and date conventions.
//!
//! VBScript's LCID is engine-wide ambient state that `SetLocale` changes, and
//! it reaches formatting code that has no other connection to the
//! interpreter, so it lives in a thread-local rather than being threaded
//! through every conversion.

use std::cell::Cell;

thread_local! {
    static LCID: Cell<i32> = const { Cell::new(DEFAULT_LCID) };
}

pub const DEFAULT_LCID: i32 = 1033;

/// The order in which a locale writes the parts of a numeric date.
#[derive(Clone, Copy, PartialEq, Eq)]
pub enum DateOrder {
    /// month/day/year, as in en-US
    Mdy,
    /// day.month.year, as in de-DE
    Dmy,
}

pub struct Conventions {
    pub decimal: char,
    pub thousands: char,
    pub date_order: DateOrder,
}

pub fn set(lcid: i32) {
    LCID.with(|c| c.set(lcid));
}

pub fn get() -> i32 {
    LCID.with(|c| c.get())
}

pub fn conventions() -> Conventions {
    for_lcid(get())
}

pub fn for_lcid(lcid: i32) -> Conventions {
    match lcid {
        // German, French, Italian, Spanish and the other comma-decimal
        // locales, which also write dates day-first.
        1031 | 1036 | 1040 | 3082 | 1043 | 2070 | 1045 | 1053 => Conventions {
            decimal: ',',
            thousands: if lcid == 1036 { ' ' } else { '.' },
            date_order: DateOrder::Dmy,
        },
        // en-GB shares Anglo number formatting but writes dates day-first.
        2057 => Conventions {
            decimal: '.',
            thousands: ',',
            date_order: DateOrder::Dmy,
        },
        _ => Conventions {
            decimal: '.',
            thousands: ',',
            date_order: DateOrder::Mdy,
        },
    }
}

/// Rewrite a number rendered with `.` and `,` into the current locale's
/// separators.
pub fn localize_number(s: &str) -> String {
    let c = conventions();
    if c.decimal == '.' && c.thousands == ',' {
        return s.to_string();
    }
    s.chars()
        .map(|ch| match ch {
            '.' => c.decimal,
            ',' => c.thousands,
            other => other,
        })
        .collect()
}
