//! `termlib`, the library a script pulls in with `DLOpen "termlib"`.
//!
//! In the VB6 client this is `clsScriptTermlib`, a native class registered as
//! a global object so its members become bare procedure names. It is built
//! entirely on top of the rest of the host API — typewriter output, prompted
//! input, and mission progress stored under a fixed INI section.
//!
//! The names are only visible once `DLOpen "termlib"` has run, matching the
//! client, so a script that forgets it fails the same way it would in game.

use crate::error::VbResult;
use crate::value::Value;

use super::console::{Channel, Console, DrawMode};
use super::fs::FileSystem;
use super::server::GameServer;
use super::values::INVISIBLE_CHAR;
use super::{arg_int, arg_str, GameHost};

/// The INI section mission progress lives in.
const PROGRESS_SECTION: &str = "progress";

/// Whether `name` is one of termlib's members.
pub fn provides(name: &str) -> bool {
    matches!(
        name,
        "saywithbgcolor"
            | "sayslowwithbgcolor"
            | "sayslow"
            | "getasciiwithcpromptbg"
            | "getasciiwithcprompt"
            | "getasciiwithprompt"
            | "setmissionprogress"
            | "getmissionprogress"
            | "intmissionprogress"
            | "incmissionprogress"
            | "boolmissionprogress"
            | "boolsetmissionprogress"
            | "boolclearmissionprogress"
            | "qreadline"
            | "qreadlinebg"
            | "twipsperpixelx"
            | "twipsperpixely"
    )
}

pub fn call<C: Console, F: FileSystem, S: GameServer>(
    host: &GameHost<C, F, S>,
    name: &str,
    args: &[crate::interp::ArgVal],
) -> VbResult<Option<Value>> {
    let v = match name {
        "saywithbgcolor" => {
            let rgb = arg_int(args, 0, -1)?;
            let text = arg_str(args, 1)?;
            host.emit(Channel::Say, &text);
            host.console.borrow_mut().draw(-1, rgb, DrawMode::Solid, 0);
            Value::Empty
        }
        "sayslowwithbgcolor" => {
            say_slow(host, arg_int(args, 0, -1)?, arg_int(args, 1, 0)?, &arg_str(args, 2)?, &arg_str(args, 3)?);
            Value::Empty
        }
        "sayslow" => {
            // `SaySlow` is the same call with no background colour.
            say_slow(host, -1, arg_int(args, 0, 0)?, &arg_str(args, 1)?, &arg_str(args, 2)?);
            Value::Empty
        }
        "getasciiwithcpromptbg" => {
            Value::I4(get_ascii_prompt(host, arg_int(args, 0, -1)?, &arg_str(args, 1)?))
        }
        "getasciiwithcprompt" => Value::I4(get_ascii_prompt(host, -1, &arg_str(args, 0)?)),
        "getasciiwithprompt" => Value::I4(get_ascii_prompt(host, -1, "")),

        "setmissionprogress" => {
            let file = host.mission_file(&arg_str(args, 0)?);
            host.write_ini(&file, PROGRESS_SECTION, &arg_str(args, 1)?, &arg_str(args, 2)?)?;
            Value::Empty
        }
        "getmissionprogress" => Value::str(progress(host, args)?),
        "intmissionprogress" => {
            // A missing or unparsable value counts as zero.
            let text = progress(host, args)?;
            Value::I4(text.trim().parse::<i32>().unwrap_or(0))
        }
        "incmissionprogress" => {
            let current = progress(host, args)?.trim().parse::<i64>().unwrap_or(0);
            let file = host.mission_file(&arg_str(args, 0)?);
            host.write_ini(
                &file,
                PROGRESS_SECTION,
                &arg_str(args, 1)?,
                &(current + 1).to_string(),
            )?;
            Value::Empty
        }
        "boolmissionprogress" => Value::Bool(progress(host, args)? == "1"),
        "boolsetmissionprogress" | "boolclearmissionprogress" => {
            let file = host.mission_file(&arg_str(args, 0)?);
            let value = if name == "boolsetmissionprogress" { "1" } else { "0" };
            host.write_ini(&file, PROGRESS_SECTION, &arg_str(args, 1)?, value)?;
            Value::Empty
        }

        // The quick readers normalise their answer, which is what makes
        // menu comparisons in the mission scripts work.
        "qreadline" => Value::str(quick_read(host, &arg_str(args, 0)?, -1)),
        "qreadlinebg" => {
            Value::str(quick_read(host, &arg_str(args, 1)?, arg_int(args, 0, -1)?))
        }

        // Screen metrics the client reads off the display.
        "twipsperpixelx" | "twipsperpixely" => Value::I4(15),

        _ => return Ok(None),
    };
    Ok(Some(v))
}

fn progress<C: Console, F: FileSystem, S: GameServer>(
    host: &GameHost<C, F, S>,
    args: &[crate::interp::ArgVal],
) -> VbResult<String> {
    let file = host.mission_file(&arg_str(args, 0)?);
    Ok(host.read_ini(&file, PROGRESS_SECTION, &arg_str(args, 1)?))
}

fn quick_read<C: Console, F: FileSystem, S: GameServer>(
    host: &GameHost<C, F, S>,
    prompt: &str,
    rgb: i64,
) -> String {
    let answer = host.console.borrow_mut().read_line(prompt, rgb);
    answer.unwrap_or_default().trim().to_lowercase()
}

/// Print `text` one character at a time, redrawing the line as it grows.
fn say_slow<C: Console, F: FileSystem, S: GameServer>(
    host: &GameHost<C, F, S>,
    rgb: i64,
    _delay_ms: i64,
    text: &str,
    style: &str,
) {
    // With output disabled there is nothing to animate, so the whole line
    // goes out at once.
    if host.env.borrow().output_disabled {
        host.emit(Channel::Say, &format!("{text}{style}"));
        return;
    }

    // The style argument arrives without its braces.
    let style = format!("{{{{{}}}}}", style.replace(['{', '}'], ""));
    let chars: Vec<char> = text.chars().collect();
    if chars.is_empty() {
        host.emit(Channel::Say, &style);
        return;
    }

    host.emit(Channel::Say, &format!("{}{style}", chars[0]));
    if rgb >= 0 {
        host.console.borrow_mut().draw(-1, rgb, DrawMode::Solid, 0);
    }

    let mut i = 1;
    while i < chars.len() {
        // An invisible marker is part of an escape, so it and the character
        // after it appear together.
        if chars[i] == INVISIBLE_CHAR {
            i += 1;
        }
        i += 1;
        let shown: String = chars[..i.min(chars.len())].iter().collect();
        host.console.borrow_mut().say_at(&shown, -1);
        if rgb >= 0 {
            host.console.borrow_mut().draw(-1, rgb, DrawMode::Solid, 0);
        }
    }
}

/// Show a prompt, read one key, then redraw the prompt with the answer in it.
fn get_ascii_prompt<C: Console, F: FileSystem, S: GameServer>(
    host: &GameHost<C, F, S>,
    rgb: i64,
    prompt: &str,
) -> i32 {
    host.emit(Channel::Say, &format!("{{{{noprespace}}}}{prompt}> [_]"));
    if rgb >= 0 {
        host.console.borrow_mut().draw(-1, rgb, DrawMode::Solid, 0);
    }
    let choice = host.console.borrow_mut().get_ascii();
    let shown = char::from_u32(choice as u32).unwrap_or(' ');
    host.console
        .borrow_mut()
        .say_at(&format!("{{{{noprespace}}}}{prompt}> [{shown}]"), -1);
    if rgb >= 0 {
        host.console.borrow_mut().draw(-1, rgb, DrawMode::Solid, 0);
    }
    choice as i32
}
