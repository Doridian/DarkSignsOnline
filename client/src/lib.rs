//! A VBScript interpreter.
//!
//! The pipeline is the conventional one: [`lexer`] produces tokens,
//! [`parser`] builds the [`ast`], and [`interp`] walks it. [`value`] holds the
//! `Variant` type that every stage passes around.

pub mod ast;
pub mod builtins;
pub mod error;
pub mod interp;
pub mod lexer;
pub mod locale;
pub mod members;
pub mod objects;
pub mod ops;
pub mod parser;
pub mod value;

pub use error::{VbError, VbResult};
pub use interp::{ArgVal, Host, Interp};
pub use value::Value;

/// Parse and run a script with no host services.
pub fn run(src: &str) -> Result<(), String> {
    Interp::new().run_source(src)
}

/// Check that a script parses, without running it.
pub fn check(src: &str) -> Result<(), error::SyntaxError> {
    parser::parse(src).map(|_| ())
}

pub mod game;
