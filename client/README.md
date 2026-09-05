# dso-client

A VBScript interpreter in Rust, written to run the DarkSigns Online game
scripts (`.ds` files, which are VBScript with a game-specific host API).

## Layout

| Module | Role |
|---|---|
| [`lexer.rs`](src/lexer.rs) | Tokens. Case-insensitivity, line continuations, `&H`/`&O` literals, the `=>`/`><` operator spellings, and the whitespace bit that separates `obj.member` from `Sub .member`. |
| [`parser.rs`](src/parser.rs) | Recursive descent over the full statement and expression grammar. |
| [`ast.rs`](src/ast.rs) | Syntax tree. Statements carry their source line for runtime errors. |
| [`value.rs`](src/value.rs) | The `Variant`: every VARTYPE, `%.15G` real formatting, SAFEARRAY storage, and the comparison rules. |
| [`ops.rs`](src/ops.rs) | Arithmetic, logical and bitwise operators with VBScript's type-promotion lattice and three-valued `Null` logic. |
| [`interp.rs`](src/interp.rs) | Tree-walking evaluator: scopes, `ByRef` binding, error handling, the `Host` trait. |
| [`members.rs`](src/members.rs) | Property and method dispatch for classes, `Err`, `Dictionary` and `RegExp`. |
| [`objects/`](src/objects/) | Script class instances, `Scripting.Dictionary`, `VBScript.RegExp`. |
| [`builtins/`](src/builtins/) | ~110 built-in functions: conversion, strings, math, date/time, formatting. |
| [`locale.rs`](src/locale.rs) | Number separators and date field order per LCID. |

## Testing

Two suites, both run by `cargo test`:

- **`tests/wine.rs`** runs [wine's VBScript conformance suite](https://gitlab.winehq.org/wine/wine/-/tree/master/dlls/vbscript/tests)
  unmodified, against a host in `tests/harness/` that reimplements wine's C
  test driver (`ok`, `getVT`, `testObj`, `collectionObj`, …).
- **`tests/game_scripts.rs`** parses the `.ds` corpus in `../client-legacy/user`.
  Its ignored `run_scripts` test also *executes* the corpus against a host
  that answers every call with `Empty`, and prints the host names the scripts
  reach for — a worklist for implementing the real game host:

  ```
  cargo test --test game_scripts run_scripts -- --ignored --nocapture
  ```

### Status

| Suite | Result |
|---|---|
| `lang.vbs` | 1466 assertions, all pass |
| `error.vbs` | 165 assertions, all pass |
| `regexp.vbs` | 108 assertions, all pass |
| `noexplicit.vbs` | 5 assertions, all pass |
| `api.vbs` | 2161 assertions, 3 known failures (see below) |
| `.ds` scripts | 298 of 301 parse; 235 of 298 also run to completion |

Of the 63 scripts that do not run to completion under the stub host, 57 sit
in a `While True` menu loop waiting on player input and stop only when the
step budget runs out, 3 raise their own usage errors because `ArgV` is empty,
and 3 index an array the stub host never returned. None of them indicate an
interpreter problem.

The three `.ds` scripts that do not parse are not VBScript: `xnull.ds` and
`xnullb.ds` have an `If` with no `Then`, and `xnullrg.ds` is written in the
older `@label` / `input` / `!` DarkSigns command language. They are listed in
`NOT_VBSCRIPT` in the test, which asserts they stay rejected.

`cargo test` is green: the three `api.vbs` assertions are listed in
`KNOWN_FAILURES` in `tests/wine.rs`, which also fails the test if one of them
starts passing, so a fix cannot go unnoticed.

### Known limitation

The `*B` string functions (`LenB`, `LeftB`, `RightB`, `MidB`, `ChrB`) treat a
string as its little-endian UTF-16 byte image, and that image can have an odd
length: `LeftB("ABC", 3)` is three bytes, one and a half UTF-16 units, and
`LenB` of it is 3. A `Value::Str` holds a Rust `str`, which cannot represent
half a unit, so the result rounds up and `LenB` reports 4.

Fixing this means holding strings as bytes rather than as `str`, which
touches every string operation, comparison and conversion in the interpreter
— a lot of churn for a legacy DBCS feature no DarkSigns script uses. The
three `api.vbs` assertions it costs are the ones in `KNOWN_FAILURES`.

## Embedding

A host implements [`Host`](src/interp.rs) to supply the game's ~160
procedures:

```rust
use vbscript::{ArgVal, Host, Interp, Value, VbResult};

struct GameHost;

impl Host for GameHost {
    fn call(&mut self, _it: &mut Interp, name: &str, args: &mut [ArgVal])
        -> VbResult<Option<Value>>
    {
        match name {
            "say" => { /* ... */ Ok(Some(Value::Empty)) }
            // Returning None means "not mine", and the interpreter reports
            // an undefined procedure.
            _ => Ok(None),
        }
    }
}
```

`Interp::set_step_budget` bounds how many statements a script may execute,
which matters because players can author scripts.

## Preprocessing

`Option` statements other than `Option Explicit` are parsed, collected into
`Interp::unknown_options`, and otherwise ignored, on the assumption that a
preprocessor will handle them.
