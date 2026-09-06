//! Turning a typed console line into VBScript.
//!
//! The console does not run what the player types directly. `dir /home`
//! is not valid VBScript, so `basCommands.ParseCommandLine` rewrites it as
//! `Call Run("dir", "/home")` before handing it to the engine. Anything that
//! looks like real script — an assignment, a keyword, punctuation VBScript
//! uses — is passed through untouched.
//!
//! An interactive console has the rewriting on from the start
//! (`CommandState::console`). Elsewhere it is off until a line opts in with
//! `Option DScript`, and `Option NoDScript` turns it back off.

use super::values::is_hex;

/// A word from the command line, and whether it was written in quotes.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Token {
    pub text: String,
    pub quoted: bool,
}

/// What a line was split on, so the remainder can be rejoined.
#[derive(Debug, Clone, PartialEq, Eq)]
enum Split {
    /// `:` — a statement separator.
    Colon,
    /// A newline.
    NewLine,
    /// A space, used when a comment starts mid-line.
    Space,
}

impl Split {
    fn text(&self) -> &'static str {
        match self {
            Split::Colon => ":",
            Split::NewLine => "\r\n",
            Split::Space => " ",
        }
    }
}

/// One line's worth of tokens, plus whatever followed the separator.
#[derive(Debug)]
struct Scan {
    tokens: Vec<Token>,
    /// Offset just past the separator, when the line continued.
    rest: Option<usize>,
    split: Split,
    /// Punctuation VBScript uses, which means the player wrote script.
    looks_like_script: bool,
}

/// What the parser needs to know about the surrounding session.
pub trait CommandContext {
    /// Whether `/system/commands/<name>.ds` exists.
    fn command_exists(&self, name: &str) -> bool;

    /// Whether the name is already a variable or procedure, in which case a
    /// bare word is a reference rather than a string.
    fn is_defined(&self, name: &str) -> bool;

    /// Whether `/system/commands/help/functions/<name>.ds` exists, which
    /// marks a name as documentation rather than a variable.
    fn is_help_topic(&self, name: &str) -> bool {
        let _ = name;
        false
    }
}

/// Nothing is defined and no commands exist: every bare word is a string.
pub struct NoContext;

impl CommandContext for NoContext {
    fn command_exists(&self, _name: &str) -> bool {
        false
    }
    fn is_defined(&self, _name: &str) -> bool {
        false
    }
}

/// Carried between lines, because `Option DScript` persists for the session.
#[derive(Debug, Default, Clone)]
pub struct CommandState {
    /// Whether command rewriting is switched on.
    pub dscript: bool,
}

impl CommandState {
    /// The state an interactive console starts in.
    ///
    /// Rewriting is on from the first line: `basCommands.InitConsoles` sets
    /// `scrConsoleDScript(x) = True` for each of the four consoles, so a
    /// player who types `help` gets the command, not a bare identifier. The
    /// `Default` impl is the other case — `ParseCommandLineOptional` starts
    /// from `False`, because script being parsed on a script's behalf has not
    /// opted in.
    pub fn console() -> Self {
        Self { dscript: true }
    }
}

#[derive(Debug)]
pub struct CommandError(pub String);

impl std::fmt::Display for CommandError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(&self.0)
    }
}

/// Words that start a VBScript statement, so a line beginning with one is
/// script rather than a command.
const STATEMENT_KEYWORDS: &[&str] = &[
    "next", "wend", "loop", "until", "if", "else", "elseif", "end", "public", "private",
    "property", "dim", "sub", "function", "const", "enum", "redim", "set", "goto", "type",
    "throw", "catch", "try", "finally", "on", "for", "while", "do",
];

/// Loop keywords, after which the console yields so a long loop stays
/// responsive.
const YIELDING_KEYWORDS: &[&str] = &["for", "while", "do"];

fn is_keyword(word: &str) -> bool {
    matches!(word.to_ascii_lowercase().as_str(), "true" | "false" | "null" | "nothing")
}

/// Whether a bare word could name a variable.
///
/// The client's check is loose — it accepts parentheses so `x(1)` passes —
/// and rejects keywords and anything numeric.
pub fn is_valid_var_name(candidate: &str) -> bool {
    if candidate.is_empty() || is_keyword(candidate) || is_numeric(candidate) {
        return false;
    }
    candidate
        .chars()
        .all(|c| c.is_ascii_alphanumeric() || c == '_' || c == '(' || c == ')')
}

fn is_numeric(s: &str) -> bool {
    crate::value::parse_number(s).is_some()
}

/// Double any quote, so the text can sit inside a VBScript string literal.
fn escape(s: &str) -> String {
    s.replace('"', "\"\"")
}

/// Render an argument as a VBScript literal. A keyword or number is written
/// bare unless quotes were forced.
fn quoted_literal(s: &str, force_quotes: bool) -> String {
    if !force_quotes && (is_keyword(s) || is_numeric(s)) {
        return s.to_string();
    }
    format!("\"{}\"", escape(s))
}

/// Split one line into tokens, stopping at a statement separator.
fn scan(input: &str) -> Result<Scan, CommandError> {
    let chars: Vec<char> = input.chars().collect();
    let mut tokens: Vec<Token> = Vec::new();
    let mut current = String::new();
    let mut current_quoted = false;
    let mut in_quotes: Option<char> = None;
    let mut in_comment = false;
    let mut looks_like_script = false;
    let mut rest = None;
    let mut split = Split::NewLine;

    let mut i = 0;
    while i < chars.len() {
        let c = chars[i];

        if let Some(q) = in_quotes {
            if c != q {
                current.push(c);
                i += 1;
                continue;
            }
            // A doubled quote is an escaped one.
            if chars.get(i + 1) == Some(&q) {
                current.push(q);
                i += 2;
                continue;
            }
            // Closing quote: the token ends, even if it is empty.
            tokens.push(Token { text: std::mem::take(&mut current), quoted: true });
            current_quoted = false;
            in_quotes = None;
            i += 1;
            continue;
        }

        if in_comment && c != '\n' && c != '\r' {
            i += 1;
            continue;
        }

        match c {
            ' ' | '\t' => {
                push_token(&mut tokens, &mut current, current_quoted, &mut in_comment);
                current_quoted = false;
            }
            '"' => {
                push_token(&mut tokens, &mut current, current_quoted, &mut in_comment);
                in_quotes = Some('"');
                current_quoted = true;
            }
            '\'' => {
                // A comment only starts a line; mid-line it ends the command
                // and leaves the remainder for the next pass.
                if !current.is_empty() || !tokens.is_empty() {
                    split = Split::Space;
                    rest = Some(i);
                    break;
                }
                in_comment = true;
                current.push('\'');
            }
            ',' | ';' | '(' | ')' | '|' | '=' | '&' | '<' | '>' => {
                // Punctuation VBScript uses, so the player meant script.
                looks_like_script = true;
                current.push(c);
            }
            '_' if current.is_empty()
                && matches!(chars.get(i + 1), Some('\n') | Some('\r')) =>
            {
                // A line continuation, which only script uses.
                looks_like_script = true;
                i += 1;
                if chars.get(i) == Some(&'\r') && chars.get(i + 1) == Some(&'\n') {
                    i += 1;
                }
            }
            '\r' | '\n' => {
                let mut next = i + 1;
                if c == '\r' && chars.get(next) == Some(&'\n') {
                    next += 1;
                }
                push_token(&mut tokens, &mut current, current_quoted, &mut in_comment);
                return Ok(Scan {
                    tokens,
                    rest: (next < chars.len()).then_some(next),
                    split: Split::NewLine,
                    looks_like_script,
                });
            }
            ':' => {
                push_token(&mut tokens, &mut current, current_quoted, &mut in_comment);
                return Ok(Scan {
                    tokens,
                    rest: (i + 1 < chars.len()).then_some(i + 1),
                    split: Split::Colon,
                    looks_like_script,
                });
            }
            other => current.push(other),
        }
        i += 1;
    }

    if in_quotes.is_some() {
        return Err(CommandError("Unclosed quote in command".into()));
    }
    push_token(&mut tokens, &mut current, current_quoted, &mut in_comment);
    Ok(Scan { tokens, rest, split, looks_like_script })
}

fn push_token(tokens: &mut Vec<Token>, current: &mut String, quoted: bool, in_comment: &mut bool) {
    if current.is_empty() {
        return;
    }
    // `rem` as the first word comments out the rest of the line.
    if tokens.is_empty() && current.trim().eq_ignore_ascii_case("rem") {
        *in_comment = true;
    }
    tokens.push(Token { text: std::mem::take(current), quoted });
}

/// Rewrite a console line into the VBScript the engine should run.
///
/// `state` carries `Option DScript` across lines. `option_explicit` prepends
/// the declaration, which the client does when compiling a whole script
/// rather than a console line.
pub fn parse_command_line(
    input: &str,
    state: &mut CommandState,
    ctx: &dyn CommandContext,
    option_explicit: bool,
) -> Result<String, CommandError> {
    let mut out = String::new();
    let mut remaining = input;
    let mut explicit = option_explicit;

    loop {
        let scan = scan(remaining)?;
        let (piece, rest) = rewrite(remaining, scan, state, ctx, &mut explicit);
        out.push_str(&piece);
        match rest {
            Some(next) => remaining = next,
            None => break,
        }
    }

    if explicit {
        out = format!("Option Explicit : {out}");
    }
    Ok(out)
}

/// Rewrite one statement, returning it and whatever is still unparsed.
fn rewrite<'a>(
    source: &'a str,
    scan: Scan,
    state: &mut CommandState,
    ctx: &dyn CommandContext,
    explicit: &mut bool,
) -> (String, Option<&'a str>) {
    let rest_offset = scan.rest;
    let rest = rest_offset.map(|i| &source[byte_offset(source, i)..]);

    // The raw text of this statement, without the separator.
    let verbatim = match rest_offset {
        Some(i) => &source[..byte_offset(source, i.saturating_sub(scan.split.text().chars().count()))],
        None => source,
    };

    let passthrough = |explicit: &mut bool, keep_explicit: bool| {
        if !keep_explicit {
            *explicit = false;
        }
        let mut text = verbatim.to_string();
        if rest_offset.is_some() {
            text.push_str(scan.split.text());
        }
        text
    };

    let Some(first) = scan.tokens.first() else {
        // An empty statement contributes nothing but its separator.
        let mut text = String::new();
        if rest_offset.is_some() {
            text.push_str(scan.split.text());
        }
        return (text, rest);
    };

    let command = first.text.trim().to_ascii_lowercase();
    let yields = YIELDING_KEYWORDS.contains(&command.as_str());

    // A quoted first word, or script punctuation, means this is script.
    if first.quoted || scan.looks_like_script {
        return (passthrough(explicit, false), rest);
    }

    // `Option DScript` and `Option NoDScript` toggle rewriting.
    if command == "option" {
        match scan.tokens.get(1).map(|t| t.text.trim().to_ascii_lowercase()) {
            Some(word) if word == "dscript" => {
                state.dscript = true;
                let mut text = String::new();
                if rest_offset.is_some() {
                    text.push_str(scan.split.text());
                }
                return (text, rest);
            }
            Some(word) if word == "nodscript" => {
                state.dscript = false;
                let mut text = String::new();
                if rest_offset.is_some() {
                    text.push_str(scan.split.text());
                }
                return (text, rest);
            }
            _ => return (passthrough(explicit, false), rest),
        }
    }

    // A comment keeps `Option Explicit`, since it compiles fine.
    if command == "rem" || command == "'" {
        return (passthrough(explicit, true), rest);
    }

    if STATEMENT_KEYWORDS.contains(&command.as_str()) {
        let mut text = passthrough(explicit, false);
        if yields {
            // Give a long loop somewhere to breathe.
            text = format!("{text} : Yield : ");
        }
        return (text, rest);
    }

    // Without the opt-in, nothing is rewritten.
    if !state.dscript {
        return (passthrough(explicit, false), rest);
    }

    // `wait for x` is spelled as one call.
    let (command, arg_start) = if command == "wait"
        && scan.tokens.get(1).map(|t| t.text.trim().eq_ignore_ascii_case("for")) == Some(true)
    {
        ("waitfor".to_string(), 2)
    } else {
        (command, 1)
    };

    // A name with a command file behind it, or one that cannot be an
    // identifier at all, runs as a command; anything else is a call whose
    // result is printed.
    let as_command = ctx.command_exists(&command)
        || (!is_keyword(&command) && !is_valid_var_name(&command));

    let mut out = if as_command {
        format!("Call Run(\"{}\"", escape(&command))
    } else {
        format!("PrintVarSingleIfSet {command}(")
    };

    for (i, token) in scan.tokens.iter().enumerate().skip(arg_start) {
        if i > arg_start || as_command {
            out.push_str(", ");
        }
        out.push_str(&render_argument(token, ctx));
    }
    out.push(')');

    if yields {
        out.push_str(" : Yield : ");
    }
    if rest_offset.is_some() {
        out.push_str(scan.split.text());
    }
    (out, rest)
}

/// Decide whether an argument is a value or a reference to a variable.
fn render_argument(token: &Token, ctx: &dyn CommandContext) -> String {
    if token.quoted {
        return quoted_literal(&token.text, true);
    }

    // `%name%` asks explicitly for the variable's value.
    if token.text.len() > 2 && token.text.starts_with('%') && token.text.ends_with('%') {
        let inner = &token.text[1..token.text.len() - 1];
        if is_valid_var_name(inner) {
            return inner.to_string();
        }
    }

    // A bare word is only a reference when it really is one; otherwise the
    // player meant it as text.
    if is_valid_var_name(&token.text)
        && !ctx.is_help_topic(&token.text)
        && ctx.is_defined(&token.text)
    {
        return escape(&token.text);
    }

    quoted_literal(&token.text, false)
}

/// Character index to byte offset, since tokens are counted in characters.
fn byte_offset(s: &str, chars: usize) -> usize {
    s.char_indices().nth(chars).map(|(i, _)| i).unwrap_or(s.len())
}

/// Exposed for the help system, which lists hex-named topics.
pub fn looks_like_hash(name: &str) -> bool {
    name.len() == 64 && is_hex(name)
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A context where the named commands and variables exist.
    struct Ctx {
        commands: Vec<&'static str>,
        defined: Vec<&'static str>,
    }

    impl CommandContext for Ctx {
        fn command_exists(&self, name: &str) -> bool {
            self.commands.contains(&name)
        }
        fn is_defined(&self, name: &str) -> bool {
            self.defined.contains(&name)
        }
    }

    fn dscript() -> CommandState {
        CommandState { dscript: true }
    }

    /// An interactive console rewrites commands from its very first line.
    /// The console is the only caller that does not set this explicitly, so
    /// a wrong default here reaches the player as `help` doing nothing at
    /// all, while every test that sets `dscript` by hand still passes.
    #[test]
    fn console_starts_with_rewriting_on() {
        assert!(CommandState::console().dscript);

        let ctx = Ctx { commands: vec!["help"], defined: vec![] };
        let mut state = CommandState::console();
        let out = parse_command_line("help", &mut state, &ctx, false).expect("parses");
        assert_eq!(out, "Call Run(\"help\")");
    }

    /// Script parsed on a script's behalf has not opted in, matching
    /// `ParseCommandLineOptional`.
    #[test]
    fn default_state_leaves_rewriting_off() {
        assert!(!CommandState::default().dscript);
    }

    fn parse(input: &str, ctx: &dyn CommandContext) -> String {
        let mut state = dscript();
        parse_command_line(input, &mut state, ctx, false).expect("parses")
    }

    #[test]
    fn a_known_command_becomes_a_run_call() {
        let ctx = Ctx { commands: vec!["dir"], defined: vec![] };
        assert_eq!(parse("dir", &ctx), r#"Call Run("dir")"#);
        assert_eq!(parse("dir /home", &ctx), r#"Call Run("dir", "/home")"#);
    }

    #[test]
    fn arguments_keep_their_quoting() {
        let ctx = Ctx { commands: vec!["say"], defined: vec![] };
        assert_eq!(
            parse(r#"say "hello world""#, &ctx),
            r#"Call Run("say", "hello world")"#
        );
    }

    #[test]
    fn a_doubled_quote_is_an_escaped_one() {
        let ctx = Ctx { commands: vec!["say"], defined: vec![] };
        assert_eq!(
            parse(r#"say "he said ""hi""""#, &ctx),
            r#"Call Run("say", "he said ""hi""")"#
        );
    }

    #[test]
    fn an_unclosed_quote_is_reported() {
        let mut state = dscript();
        let err = parse_command_line(r#"say "oops"#, &mut state, &NoContext, false);
        assert!(err.is_err());
    }

    #[test]
    fn an_unknown_name_becomes_a_printed_call() {
        let ctx = Ctx { commands: vec![], defined: vec![] };
        // A numeric argument is written bare, as the client does.
        assert_eq!(parse("myfunc 1", &ctx), "PrintVarSingleIfSet myfunc(1)");
        assert_eq!(parse("myfunc abc", &ctx), r#"PrintVarSingleIfSet myfunc("abc")"#);
    }

    #[test]
    fn a_defined_variable_is_passed_by_name() {
        let ctx = Ctx { commands: vec!["echo"], defined: vec!["myvar"] };
        assert_eq!(parse("echo myvar", &ctx), r#"Call Run("echo", myvar)"#);
    }

    #[test]
    fn an_undefined_word_is_passed_as_text() {
        let ctx = Ctx { commands: vec!["echo"], defined: vec![] };
        assert_eq!(parse("echo myvar", &ctx), r#"Call Run("echo", "myvar")"#);
    }

    #[test]
    fn percent_signs_force_a_variable_reference() {
        let ctx = Ctx { commands: vec!["echo"], defined: vec![] };
        assert_eq!(parse("echo %myvar%", &ctx), r#"Call Run("echo", myvar)"#);
    }

    #[test]
    fn numbers_and_keywords_are_written_bare() {
        let ctx = Ctx { commands: vec!["echo"], defined: vec![] };
        assert_eq!(parse("echo 42", &ctx), r#"Call Run("echo", 42)"#);
        assert_eq!(parse("echo true", &ctx), r#"Call Run("echo", true)"#);
    }

    #[test]
    fn quoting_a_number_keeps_it_a_string() {
        let ctx = Ctx { commands: vec!["echo"], defined: vec![] };
        assert_eq!(parse(r#"echo "42""#, &ctx), r#"Call Run("echo", "42")"#);
    }

    #[test]
    fn script_punctuation_passes_the_line_through() {
        let ctx = Ctx { commands: vec!["dir"], defined: vec![] };
        // An assignment is script, not a command.
        assert_eq!(parse("x = 1", &ctx), "x = 1");
        assert_eq!(parse("Say(1)", &ctx), "Say(1)");
    }

    #[test]
    fn a_statement_keyword_passes_through() {
        let ctx = Ctx { commands: vec![], defined: vec![] };
        assert_eq!(parse("Dim x", &ctx), "Dim x");
        assert_eq!(parse("End If", &ctx), "End If");
    }

    #[test]
    fn a_loop_keyword_gets_a_yield_so_it_stays_responsive() {
        let ctx = Ctx { commands: vec![], defined: vec![] };
        assert_eq!(parse("While True", &ctx), "While True : Yield : ");
    }

    #[test]
    fn a_quoted_first_word_is_script_not_a_command() {
        let ctx = Ctx { commands: vec!["dir"], defined: vec![] };
        assert_eq!(parse(r#""dir""#, &ctx), r#""dir""#);
    }

    #[test]
    fn rewriting_is_off_until_option_dscript() {
        let ctx = Ctx { commands: vec!["dir"], defined: vec![] };
        let mut state = CommandState::default();
        // Without the opt-in the line is script.
        assert_eq!(
            parse_command_line("dir /home", &mut state, &ctx, false).unwrap(),
            "dir /home"
        );
        // Turning it on changes that, and the setting sticks.
        parse_command_line("option dscript", &mut state, &ctx, false).unwrap();
        assert!(state.dscript);
        assert_eq!(
            parse_command_line("dir /home", &mut state, &ctx, false).unwrap(),
            r#"Call Run("dir", "/home")"#
        );
    }

    #[test]
    fn option_nodscript_turns_rewriting_back_off() {
        let ctx = Ctx { commands: vec!["dir"], defined: vec![] };
        let mut state = dscript();
        parse_command_line("option nodscript", &mut state, &ctx, false).unwrap();
        assert!(!state.dscript);
    }

    #[test]
    fn statements_separated_by_a_colon_are_each_rewritten() {
        let ctx = Ctx { commands: vec!["dir", "ls"], defined: vec![] };
        assert_eq!(
            parse("dir : ls", &ctx),
            r#"Call Run("dir"):Call Run("ls")"#
        );
    }

    #[test]
    fn a_comment_line_survives_untouched() {
        let ctx = Ctx { commands: vec![], defined: vec![] };
        assert_eq!(parse("' just a note", &ctx), "' just a note");
        assert_eq!(parse("rem also a note", &ctx), "rem also a note");
    }

    #[test]
    fn wait_for_collapses_into_one_call() {
        let ctx = Ctx { commands: vec![], defined: vec!["req"] };
        assert_eq!(parse("wait for req", &ctx), "PrintVarSingleIfSet waitfor(req)");
    }

    #[test]
    fn an_empty_line_produces_nothing() {
        let ctx = Ctx { commands: vec![], defined: vec![] };
        assert_eq!(parse("", &ctx), "");
        assert_eq!(parse("   ", &ctx), "");
    }

    #[test]
    fn option_explicit_is_prepended_when_asked_for() {
        let ctx = Ctx { commands: vec!["dir"], defined: vec![] };
        let mut state = dscript();
        assert_eq!(
            parse_command_line("dir", &mut state, &ctx, true).unwrap(),
            r#"Option Explicit : Call Run("dir")"#
        );
    }

    #[test]
    fn a_passed_through_statement_drops_option_explicit() {
        // Raw script may declare its own variables, so forcing the option
        // on would break it.
        let ctx = Ctx { commands: vec![], defined: vec![] };
        let mut state = dscript();
        assert_eq!(
            parse_command_line("x = 1", &mut state, &ctx, true).unwrap(),
            "x = 1"
        );
    }

    #[test]
    fn identifier_validation_matches_the_client() {
        assert!(is_valid_var_name("myVar"));
        assert!(is_valid_var_name("a_1"));
        // The client's check is loose enough to accept a subscript.
        assert!(is_valid_var_name("x(1)"));
        assert!(!is_valid_var_name(""));
        assert!(!is_valid_var_name("true"));
        assert!(!is_valid_var_name("42"));
        assert!(!is_valid_var_name("has space"));
        assert!(!is_valid_var_name("has-dash"));
    }
}
