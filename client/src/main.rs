//! Command-line driver: runs a `.vbs` or `.ds` script.

use std::cell::RefCell;
use std::process::ExitCode;
use std::rc::Rc;

use vbscript::interp::{Host, Interp};

/// A host that prints `MsgBox` output to stdout.
struct ConsoleHost;

impl Host for ConsoleHost {
    fn echo(&mut self, text: &str) {
        println!("{text}");
    }
}

fn main() -> ExitCode {
    let mut args = std::env::args().skip(1);
    let mut check_only = false;
    let mut path: Option<String> = None;
    for a in args.by_ref() {
        match a.as_str() {
            "--check" => check_only = true,
            "-h" | "--help" => {
                eprintln!("usage: dso-client [--check] <script>");
                return ExitCode::SUCCESS;
            }
            other => path = Some(other.to_string()),
        }
    }
    let Some(path) = path else {
        eprintln!("usage: dso-client [--check] <script>");
        return ExitCode::FAILURE;
    };

    let src = match std::fs::read_to_string(&path) {
        Ok(s) => s,
        Err(e) => {
            eprintln!("{path}: {e}");
            return ExitCode::FAILURE;
        }
    };

    if check_only {
        return match vbscript::check(&src) {
            Ok(()) => ExitCode::SUCCESS,
            Err(e) => {
                eprintln!("{path}: {e}");
                ExitCode::FAILURE
            }
        };
    }

    let mut it = Interp::with_host(Rc::new(RefCell::new(ConsoleHost)));
    match it.run_source(&src) {
        Ok(()) => ExitCode::SUCCESS,
        Err(e) => {
            eprintln!("{path}: {e}");
            ExitCode::FAILURE
        }
    }
}
