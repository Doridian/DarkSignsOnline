//! `VBScript.RegExp`, backed by the `regex` crate.

use std::rc::Rc;

use crate::error::{VbError, VbResult};
use crate::value::Value;

pub struct RegExpObj {
    pub pattern: Rc<str>,
    pub global: bool,
    pub ignore_case: bool,
    pub multiline: bool,
    /// Compiled lazily and invalidated whenever a flag or the pattern changes.
    compiled: Option<regex::Regex>,
    compiled_key: Option<(Rc<str>, bool, bool)>,
}

pub struct MatchObj {
    pub value: Rc<str>,
    /// Character offset of the match within the subject.
    pub first_index: i32,
    pub length: i32,
    pub submatches: Rc<Vec<Value>>,
}

impl Default for RegExpObj {
    fn default() -> RegExpObj {
        RegExpObj::new()
    }
}

impl RegExpObj {
    pub fn new() -> RegExpObj {
        RegExpObj {
            pattern: Rc::from(""),
            global: false,
            ignore_case: false,
            multiline: false,
            compiled: None,
            compiled_key: None,
        }
    }

    fn regex(&mut self) -> VbResult<&regex::Regex> {
        let key = (self.pattern.clone(), self.ignore_case, self.multiline);
        if self.compiled_key.as_ref() != Some(&key) {
            let translated = translate_pattern(&self.pattern);
            let mut b = regex::RegexBuilder::new(&translated);
            b.case_insensitive(self.ignore_case);
            b.multi_line(self.multiline);
            // JScript's `.` excludes newlines, matching the crate's default.
            let re = b
                .build()
                .map_err(|_| VbError::new(5017, "Syntax error in regular expression"))?;
            self.compiled = Some(re);
            self.compiled_key = Some(key);
        }
        Ok(self.compiled.as_ref().unwrap())
    }

    pub fn test(&mut self, subject: &str) -> VbResult<bool> {
        Ok(self.regex()?.is_match(subject))
    }

    pub fn execute(&mut self, subject: &str) -> VbResult<Vec<Rc<MatchObj>>> {
        let global = self.global;
        let re = self.regex()?;
        // Byte offsets must be reported as character offsets.
        let char_index = CharIndex::new(subject);
        let mut out = Vec::new();
        for caps in re.captures_iter(subject) {
            let whole = caps.get(0).unwrap();
            let subs: Vec<Value> = (1..caps.len())
                .map(|i| match caps.get(i) {
                    Some(m) => Value::str(m.as_str()),
                    // An unmatched group reports as Empty, not "".
                    None => Value::Empty,
                })
                .collect();
            let start = char_index.at(whole.start());
            let end = char_index.at(whole.end());
            out.push(Rc::new(MatchObj {
                value: Rc::from(whole.as_str()),
                first_index: start as i32,
                length: (end - start) as i32,
                submatches: Rc::new(subs),
            }));
            if !global {
                break;
            }
        }
        Ok(out)
    }

    pub fn replace(&mut self, subject: &str, replacement: &str) -> VbResult<String> {
        let global = self.global;
        let re = self.regex()?;
        let mut out = String::with_capacity(subject.len());
        let mut last = 0usize;
        for caps in re.captures_iter(subject) {
            let whole = caps.get(0).unwrap();
            out.push_str(&subject[last..whole.start()]);
            expand(&mut out, replacement, subject, &caps);
            last = whole.end();
            if !global {
                break;
            }
        }
        out.push_str(&subject[last..]);
        Ok(out)
    }
}

/// Maps byte offsets in a string to character offsets.
struct CharIndex {
    /// `map[byte_offset]` = number of characters before it.
    map: Vec<usize>,
}

impl CharIndex {
    fn new(s: &str) -> CharIndex {
        let mut map = vec![0usize; s.len() + 1];
        let mut chars = 0usize;
        for (b, _) in s.char_indices() {
            map[b] = chars;
            chars += 1;
        }
        map[s.len()] = chars;
        // Fill continuation bytes so any offset resolves.
        let mut last = 0;
        for v in map.iter_mut() {
            if *v == 0 && last != 0 {
                *v = last;
            } else {
                last = *v;
            }
        }
        CharIndex { map }
    }
    fn at(&self, byte: usize) -> usize {
        *self.map.get(byte).unwrap_or(&0)
    }
}

/// Convert a JScript pattern to the `regex` crate's dialect. The two are
/// close enough that only a few constructs need rewriting.
fn translate_pattern(p: &str) -> String {
    let mut out = String::with_capacity(p.len() + 8);
    let b: Vec<char> = p.chars().collect();
    let mut i = 0;
    let mut in_class = false;
    while i < b.len() {
        let c = b[i];
        match c {
            '\\' if i + 1 < b.len() => {
                let n = b[i + 1];
                match n {
                    // JScript allows escaping any punctuation; the regex crate
                    // rejects escapes it does not recognize.
                    c2 if !c2.is_ascii_alphanumeric() => {
                        out.push('\\');
                        out.push(c2);
                    }
                    // `\cX` is a control-character escape.
                    'c' if i + 2 < b.len() && b[i + 2].is_ascii_alphabetic() => {
                        let ctl = (b[i + 2].to_ascii_uppercase() as u8 - b'A' + 1) as u32;
                        out.push_str(&format!("\\x{ctl:02x}"));
                        i += 3;
                        continue;
                    }
                    _ => {
                        out.push('\\');
                        out.push(n);
                    }
                }
                i += 2;
                continue;
            }
            '[' if !in_class => {
                in_class = true;
                out.push('[');
            }
            ']' if in_class => {
                in_class = false;
                out.push(']');
            }
            // An empty pattern must still compile.
            _ => out.push(c),
        }
        i += 1;
    }
    out
}

/// Expand one JScript replacement template against a match.
///
/// Supported forms are `$$` (a literal `$`), `` $` `` (the text before the
/// match), `$'` (the text after it), `$&` (the whole match) and `$N` /
/// `$NN` (a capture group). Anything else, including a group number the
/// pattern does not have, is copied through literally.
fn expand(out: &mut String, template: &str, subject: &str, caps: &regex::Captures<'_>) {
    let b: Vec<char> = template.chars().collect();
    let whole = caps.get(0).unwrap();
    let group_count = caps.len() - 1;
    let mut i = 0;
    while i < b.len() {
        if b[i] != '$' || i + 1 >= b.len() {
            out.push(b[i]);
            i += 1;
            continue;
        }
        match b[i + 1] {
            '$' => {
                out.push('$');
                i += 2;
            }
            '&' => {
                out.push_str(whole.as_str());
                i += 2;
            }
            '`' => {
                out.push_str(&subject[..whole.start()]);
                i += 2;
            }
            '\'' => {
                out.push_str(&subject[whole.end()..]);
                i += 2;
            }
            c if c.is_ascii_digit() => {
                // Prefer the two-digit reading when that group exists.
                let two = if i + 2 < b.len() && b[i + 2].is_ascii_digit() {
                    Some(
                        c.to_digit(10).unwrap() as usize * 10
                            + b[i + 2].to_digit(10).unwrap() as usize,
                    )
                } else {
                    None
                };
                let one = c.to_digit(10).unwrap() as usize;
                let (n, width) = match two {
                    Some(t) if t >= 1 && t <= group_count => (t, 3),
                    _ => (one, 2),
                };
                if n >= 1 && n <= group_count {
                    if let Some(m) = caps.get(n) {
                        out.push_str(m.as_str());
                    }
                    i += width;
                } else {
                    // No such group, so the text stays as written.
                    out.push('$');
                    i += 1;
                }
            }
            _ => {
                out.push('$');
                i += 1;
            }
        }
    }
}
