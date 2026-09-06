//! VBScript tokenizer.
//!
//! VBScript is case-insensitive, so every identifier and keyword is compared
//! lowercased. Statements are terminated by a newline or a `:`; both collapse
//! into a single `Newline` token so the parser only deals with one separator.

use std::fmt;

#[derive(Clone, Debug, PartialEq)]
pub enum Tok {
    // literals
    Int(i32),
    /// A numeric literal that must be typed VT_I4 even if it fits in an i16
    /// (`&h10&`, `1000000`), or that came from an octal/hex form.
    Long(i32),
    Real(f64),
    Str(String),
    /// `#1/1/2000#`
    DateLit(f64),

    Ident(String),
    Keyword(Kw),

    // punctuation / operators
    LParen,
    RParen,
    Comma,
    Dot,
    Colon,
    Eq,
    Ne,
    Lt,
    Gt,
    Le,
    Ge,
    Plus,
    Minus,
    Star,
    Slash,
    Backslash,
    Caret,
    Amp,

    Newline,
    Eof,
}

macro_rules! keywords {
    ($($variant:ident => $text:literal),* $(,)?) => {
        #[derive(Copy, Clone, Debug, PartialEq, Eq, Hash)]
        pub enum Kw { $($variant),* }

        impl Kw {
            pub fn from_word(s: &str) -> Option<Kw> {
                match s {
                    $($text => Some(Kw::$variant),)*
                    _ => None,
                }
            }
            pub fn as_str(self) -> &'static str {
                match self { $(Kw::$variant => $text),* }
            }
        }
    };
}

keywords! {
    And => "and", As => "as", ByRef => "byref", ByVal => "byval",
    Call => "call", Case => "case", Class => "class", Const => "const",
    Default => "default", Dim => "dim", Do => "do", Each => "each",
    Else => "else", ElseIf => "elseif", Empty => "empty", End => "end",
    Eqv => "eqv", Erase => "erase", Error => "error", Exit => "exit",
    Explicit => "explicit", False => "false", For => "for", Function => "function",
    Get => "get", GoTo => "goto", If => "if", Imp => "imp", In => "in",
    Is => "is", Let => "let", Loop => "loop", Me => "me", Mod => "mod",
    New => "new", Next => "next", Not => "not", Nothing => "nothing",
    Null => "null", On => "on", Option => "option", Optional => "optional",
    Or => "or", Preserve => "preserve", Private => "private", Property => "property",
    Public => "public", ReDim => "redim", Resume => "resume", Select => "select",
    Set => "set", Step => "step", Stop => "stop", Sub => "sub", Then => "then",
    To => "to", True => "true", Until => "until", Wend => "wend", While => "while",
    With => "with", Xor => "xor",
}

impl fmt::Display for Tok {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Tok::Int(v) | Tok::Long(v) => write!(f, "{v}"),
            Tok::Real(v) => write!(f, "{v}"),
            Tok::Str(s) => write!(f, "\"{s}\""),
            Tok::DateLit(v) => write!(f, "#{v}#"),
            Tok::Ident(s) => write!(f, "{s}"),
            Tok::Keyword(k) => write!(f, "{}", k.as_str()),
            Tok::Newline => write!(f, "<newline>"),
            Tok::Eof => write!(f, "<eof>"),
            t => write!(f, "{}", match t {
                Tok::LParen => "(", Tok::RParen => ")", Tok::Comma => ",",
                Tok::Dot => ".", Tok::Colon => ":", Tok::Eq => "=",
                Tok::Ne => "<>", Tok::Lt => "<", Tok::Gt => ">",
                Tok::Le => "<=", Tok::Ge => ">=", Tok::Plus => "+",
                Tok::Minus => "-", Tok::Star => "*", Tok::Slash => "/",
                Tok::Backslash => "\\", Tok::Caret => "^", Tok::Amp => "&",
                _ => "?",
            }),
        }
    }
}

#[derive(Clone, Debug)]
pub struct Token {
    pub tok: Tok,
    pub line: u32,
    /// Set when the token is an identifier/keyword, preserving the source
    /// spelling for error messages while `tok` holds the lowercased form.
    pub text: Option<String>,
    /// Whether whitespace separated this token from the previous one. The
    /// parser needs this to tell `obj.member` from `Sub .member`, which
    /// differ only by the space.
    pub spaced: bool,
}

pub struct Lexer<'a> {
    src: &'a [u8],
    pos: usize,
    line: u32,
}

#[derive(Debug)]
pub struct LexError {
    pub msg: String,
    pub line: u32,
    /// The error number VBScript reports; 1002 for a plain syntax error and
    /// 1031 for a number the parser cannot represent.
    pub code: i32,
}

type LResult<T> = Result<T, LexError>;

impl<'a> Lexer<'a> {
    pub fn new(src: &'a str) -> Self {
        Lexer { src: src.as_bytes(), pos: 0, line: 1 }
    }

    fn peek(&self) -> u8 {
        *self.src.get(self.pos).unwrap_or(&0)
    }
    fn peek_at(&self, n: usize) -> u8 {
        *self.src.get(self.pos + n).unwrap_or(&0)
    }
    fn bump(&mut self) -> u8 {
        let c = self.peek();
        self.pos += 1;
        c
    }
    fn err<T>(&self, msg: impl Into<String>) -> LResult<T> {
        Err(LexError { msg: msg.into(), line: self.line, code: 1002 })
    }

    pub fn tokenize(mut self) -> LResult<Vec<Token>> {
        let mut out: Vec<Token> = Vec::new();
        loop {
            let t = self.next_token(&out)?;
            let done = t.tok == Tok::Eof;
            // Collapse runs of newlines; a leading newline is dropped too.
            if t.tok == Tok::Newline {
                match out.last().map(|t| &t.tok) {
                    None | Some(Tok::Newline) => continue,
                    _ => {}
                }
            }
            out.push(t);
            if done {
                break;
            }
        }
        Ok(out)
    }

    /// Skip whitespace and comments, reporting whether a line continuation
    /// was among them. A continuation does not separate tokens the way a
    /// plain space does, so `obj _` + newline + `.member` stays one chain.
    fn skip_space_and_comments(&mut self, prev: &[Token]) -> bool {
        let mut continued = false;
        loop {
            match self.peek() {
                b' ' | b'\t' | b'\r' => {
                    self.pos += 1;
                }
                // Line continuation: `_` at end of line joins the next line.
                b'_' if is_eol_after_underscore(self.src, self.pos) => {
                    continued = true;
                    self.pos += 1;
                    while matches!(self.peek(), b' ' | b'\t' | b'\r') {
                        self.pos += 1;
                    }
                    if self.peek() == b'\n' {
                        self.pos += 1;
                        self.line += 1;
                    }
                }
                b'\'' => {
                    while self.peek() != b'\n' && self.pos < self.src.len() {
                        self.pos += 1;
                    }
                }
                // `REM` starts a comment, but only as a standalone word and
                // never straight after a `.`, where it names a member.
                b'r' | b'R' if self.match_rem(prev) => {
                    while self.peek() != b'\n' && self.pos < self.src.len() {
                        self.pos += 1;
                    }
                }
                _ => return continued,
            }
        }
    }

    fn match_rem(&self, prev: &[Token]) -> bool {
        if matches!(prev.last().map(|t| &t.tok), Some(Tok::Dot)) {
            return false;
        }
        let s = self.src;
        let p = self.pos;
        if p + 3 > s.len() {
            return false;
        }
        if !s[p..p + 3].eq_ignore_ascii_case(b"rem") {
            return false;
        }
        // Must be followed by a delimiter, not more identifier characters.
        match s.get(p + 3) {
            None => true,
            Some(&c) => !(c.is_ascii_alphanumeric() || c == b'_'),
        }
    }

    fn next_token(&mut self, prev: &[Token]) -> LResult<Token> {
        let before = self.pos;
        let continued = self.skip_space_and_comments(prev);
        let spaced = self.pos != before && !continued;
        let line = self.line;
        let mk = |tok| Token { tok, line, text: None, spaced };

        if self.pos >= self.src.len() {
            return Ok(mk(Tok::Eof));
        }

        let c = self.peek();
        match c {
            b'\n' => {
                self.pos += 1;
                self.line += 1;
                Ok(mk(Tok::Newline))
            }
            b':' => {
                self.pos += 1;
                Ok(mk(Tok::Colon))
            }
            b'(' => { self.pos += 1; Ok(mk(Tok::LParen)) }
            b')' => { self.pos += 1; Ok(mk(Tok::RParen)) }
            b',' => { self.pos += 1; Ok(mk(Tok::Comma)) }
            b'+' => { self.pos += 1; Ok(mk(Tok::Plus)) }
            b'-' => { self.pos += 1; Ok(mk(Tok::Minus)) }
            b'*' => { self.pos += 1; Ok(mk(Tok::Star)) }
            b'/' => { self.pos += 1; Ok(mk(Tok::Slash)) }
            b'\\' => { self.pos += 1; Ok(mk(Tok::Backslash)) }
            b'^' => { self.pos += 1; Ok(mk(Tok::Caret)) }
            b'=' => {
                self.pos += 1;
                // VBScript also accepts the reversed forms `=>` and `=<`.
                match self.peek() {
                    b'>' => { self.pos += 1; Ok(mk(Tok::Ge)) }
                    b'<' => { self.pos += 1; Ok(mk(Tok::Le)) }
                    _ => Ok(mk(Tok::Eq)),
                }
            }
            b'<' => {
                self.pos += 1;
                match self.peek() {
                    b'>' => { self.pos += 1; Ok(mk(Tok::Ne)) }
                    b'=' => { self.pos += 1; Ok(mk(Tok::Le)) }
                    _ => Ok(mk(Tok::Lt)),
                }
            }
            b'>' => {
                self.pos += 1;
                match self.peek() {
                    b'=' => { self.pos += 1; Ok(mk(Tok::Ge)) }
                    // `><` is an accepted spelling of `<>`.
                    b'<' => { self.pos += 1; Ok(mk(Tok::Ne)) }
                    _ => Ok(mk(Tok::Gt)),
                }
            }
            b'"' => self.lex_string(line, spaced),
            b'#' => self.lex_date(line, spaced),
            b'&' => {
                // `&h`/`&o` introduce a numeric literal only when a digit of
                // that radix actually follows; `"x" &hi` is a concatenation.
                let starts_literal = match self.peek_at(1) {
                    b'h' | b'H' => self.peek_at(2).is_ascii_hexdigit(),
                    b'o' | b'O' => (b'0'..=b'7').contains(&self.peek_at(2)),
                    d => d.is_ascii_digit(),
                };
                if starts_literal {
                    self.lex_based(line, spaced)
                } else {
                    self.pos += 1;
                    Ok(mk(Tok::Amp))
                }
            }
            b'.' => {
                if self.peek_at(1).is_ascii_digit() {
                    self.lex_number(line, spaced)
                } else {
                    self.pos += 1;
                    Ok(mk(Tok::Dot))
                }
            }
            b'0'..=b'9' => self.lex_number(line, spaced),
            b'[' => self.lex_bracket_ident(line, spaced),
            c if c.is_ascii_alphabetic() || c == b'_' || c >= 0x80 => self.lex_ident(line, spaced),
            _ => self.err(format!("unexpected character '{}'", c as char)),
        }
    }

    fn lex_string(&mut self, line: u32, spaced: bool) -> LResult<Token> {
        self.pos += 1; // opening quote
        let mut s = String::new();
        loop {
            if self.pos >= self.src.len() {
                return self.err("unterminated string literal");
            }
            match self.bump() {
                b'"' => {
                    if self.peek() == b'"' {
                        self.pos += 1;
                        s.push('"');
                    } else {
                        break;
                    }
                }
                b'\n' => return self.err("unterminated string literal"),
                c => push_byte(&mut s, self.src, &mut self.pos, c),
            }
        }
        Ok(Token { tok: Tok::Str(s), line, text: None, spaced })
    }

    /// `[foo bar]` — an escaped identifier. VBScript accepts these for names
    /// that collide with keywords.
    fn lex_bracket_ident(&mut self, line: u32, spaced: bool) -> LResult<Token> {
        self.pos += 1;
        let start = self.pos;
        while self.pos < self.src.len() && self.peek() != b']' {
            if self.peek() == b'\n' {
                return self.err("unterminated escaped identifier");
            }
            self.pos += 1;
        }
        if self.pos >= self.src.len() {
            return self.err("unterminated escaped identifier");
        }
        let raw = String::from_utf8_lossy(&self.src[start..self.pos]).into_owned();
        self.pos += 1; // closing bracket
        Ok(Token { tok: Tok::Ident(raw.to_ascii_lowercase()), line, text: Some(raw), spaced })
    }

    fn lex_ident(&mut self, line: u32, spaced: bool) -> LResult<Token> {
        let start = self.pos;
        while self.pos < self.src.len() {
            let c = self.peek();
            if c.is_ascii_alphanumeric() || c == b'_' || c >= 0x80 {
                self.pos += 1;
            } else {
                break;
            }
        }
        let raw = String::from_utf8_lossy(&self.src[start..self.pos]).into_owned();
        let lower = raw.to_ascii_lowercase();
        let tok = match Kw::from_word(&lower) {
            Some(k) => Tok::Keyword(k),
            None => Tok::Ident(lower),
        };
        Ok(Token { tok, line, text: Some(raw), spaced })
    }

    /// `&Hffff`, `&O777`, or `&777` (octal). A trailing `&` forces VT_I4.
    fn lex_based(&mut self, line: u32, spaced: bool) -> LResult<Token> {
        self.pos += 1; // '&'
        let radix: u32 = match self.peek() {
            b'h' | b'H' => { self.pos += 1; 16 }
            b'o' | b'O' => { self.pos += 1; 8 }
            _ => 8,
        };
        let start = self.pos;
        while self.peek().is_ascii_alphanumeric() {
            let c = self.peek().to_ascii_lowercase();
            let ok = if radix == 16 {
                c.is_ascii_hexdigit()
            } else {
                (b'0'..=b'7').contains(&c)
            };
            if !ok {
                break;
            }
            self.pos += 1;
        }
        if start == self.pos {
            return self.err("expected digits after '&'");
        }
        let digits = std::str::from_utf8(&self.src[start..self.pos]).unwrap();

        // Excess leading zeros are ignored; the *significant* digit count
        // decides whether the value is 16-bit or 32-bit.
        let trimmed = digits.trim_start_matches('0');
        let sig = if trimmed.is_empty() { "0" } else { trimmed };

        let value_u64 = u64::from_str_radix(sig, radix)
            .map_err(|_| LexError {
                msg: "numeric literal overflow".into(),
                line,
                code: 1031,
            })?;

        let forced_long = self.peek() == b'&';
        if forced_long {
            self.pos += 1;
        }

        if value_u64 > 0xFFFF_FFFF {
            return self.err("numeric literal overflow");
        }
        let tok = if forced_long {
            // The trailing `&` reads all the digits as a 32-bit value, which
            // then narrows to Integer if it fits.
            let v = value_u64 as u32 as i32;
            if v >= i16::MIN as i32 && v <= i16::MAX as i32 {
                Tok::Int(v)
            } else {
                Tok::Long(v)
            }
        } else if value_u64 <= 0xFFFF {
            // 16 bits or fewer wrap to a signed Integer, so &hffff is -1.
            let v = value_u64 as u16 as i16 as i32;
            // &H8000 is the one exception native promotes to Long.
            if value_u64 == 0x8000 {
                Tok::Long(v)
            } else {
                Tok::Int(v)
            }
        } else {
            Tok::Long(value_u64 as u32 as i32)
        };
        Ok(Token { tok, line, text: None, spaced })
    }

    fn lex_number(&mut self, line: u32, spaced: bool) -> LResult<Token> {
        let start = self.pos;
        let mut is_real = false;
        while self.peek().is_ascii_digit() {
            self.pos += 1;
        }
        if self.peek() == b'.' && self.peek_at(1) != b'.' {
            // A `.` directly after digits is a decimal point unless what
            // follows makes it a member access on a numeric literal, which
            // VBScript does not allow anyway.
            is_real = true;
            self.pos += 1;
            while self.peek().is_ascii_digit() {
                self.pos += 1;
            }
        }
        if matches!(self.peek(), b'e' | b'E') {
            let save = self.pos;
            self.pos += 1;
            if matches!(self.peek(), b'+' | b'-') {
                self.pos += 1;
            }
            if self.peek().is_ascii_digit() {
                is_real = true;
                while self.peek().is_ascii_digit() {
                    self.pos += 1;
                }
            } else {
                self.pos = save;
            }
        }
        let text = std::str::from_utf8(&self.src[start..self.pos]).unwrap();

        if is_real {
            let v: f64 = text.parse().map_err(|_| LexError {
                msg: format!("bad numeric literal '{text}'"),
                line,
                code: 1002,
            })?;
            if !v.is_finite() {
                return Err(LexError {
                    msg: format!("number '{text}' is out of range"),
                    line,
                    code: 1031,
                });
            }
            return Ok(Token { tok: Tok::Real(v), line, text: None, spaced });
        }

        // Integers narrow to VT_I2 when they fit, else VT_I4, else VT_R8.
        let tok = match text.parse::<i64>() {
            Ok(v) if v >= i16::MIN as i64 && v <= i16::MAX as i64 => Tok::Int(v as i32),
            Ok(v) if v >= i32::MIN as i64 && v <= i32::MAX as i64 => Tok::Long(v as i32),
            _ => Tok::Real(text.parse::<f64>().map_err(|_| LexError {
                msg: format!("bad numeric literal '{text}'"),
                line,
                code: 1002,
            })?),
        };
        Ok(Token { tok, line, text: None, spaced })
    }

    fn lex_date(&mut self, line: u32, spaced: bool) -> LResult<Token> {
        self.pos += 1; // '#'
        let start = self.pos;
        while self.pos < self.src.len() && self.peek() != b'#' && self.peek() != b'\n' {
            self.pos += 1;
        }
        if self.peek() != b'#' {
            return self.err("unterminated date literal");
        }
        let text = String::from_utf8_lossy(&self.src[start..self.pos]).into_owned();
        self.pos += 1;
        match crate::builtins::datetime::parse_date(&text) {
            Some(d) => Ok(Token { tok: Tok::DateLit(d), line, text: None, spaced }),
            None => self.err(format!("bad date literal '#{text}#'")),
        }
    }
}

/// Decode one UTF-8 character starting at the byte already consumed.
fn push_byte(s: &mut String, src: &[u8], pos: &mut usize, first: u8) {
    if first < 0x80 {
        s.push(first as char);
        return;
    }
    let extra = if first >= 0xF0 { 3 } else if first >= 0xE0 { 2 } else { 1 };
    let start = *pos - 1;
    let end = (start + 1 + extra).min(src.len());
    match std::str::from_utf8(&src[start..end]) {
        Ok(t) => {
            s.push_str(t);
            *pos = end;
        }
        Err(_) => s.push(char::REPLACEMENT_CHARACTER),
    }
}

fn is_eol_after_underscore(src: &[u8], mut p: usize) -> bool {
    // `_` continues the line only when nothing but whitespace follows it.
    // Otherwise it is part of an identifier, which the caller handles first.
    p += 1;
    while let Some(&c) = src.get(p) {
        match c {
            b' ' | b'\t' | b'\r' => p += 1,
            b'\n' => return true,
            _ => return false,
        }
    }
    true
}
