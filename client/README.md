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
| [`game/`](src/game/) | The DarkSigns host API — see below. |

## Testing

Two suites, both run by `cargo test`:

- **`tests/wine.rs`** runs [wine's VBScript conformance suite](https://gitlab.winehq.org/wine/wine/-/tree/master/dlls/vbscript/tests)
  unmodified, against a host in `tests/harness/` that reimplements wine's C
  test driver (`ok`, `getVT`, `testObj`, `collectionObj`, …).
- **`tests/game_api.rs`** runs VBScript against the host API, including the
  shipped `ping`, `pingport`, `dir`, `ls` and `compile` commands unmodified.
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
| `.ds` scripts | 298 of 301 parse; 243 of 298 also run to completion |
| Host API | 51 integration tests, 68 unit tests |

Of the 55 scripts that do not run to completion, 42 sit in a `While True`
menu loop waiting on player input and stop only when the step budget runs
out, and the rest fail because the run supplies no command-line arguments and
no live server. None of them indicate an interpreter or API problem.

The corpus run also reports the names the host does not provide. Those are
down to twelve — `SaySlow`, `QReadLine`, the mission-progress helpers and so
on — and all of them are defined in VBScript by the `termlib` library a
script pulls in with `DLOpen`, not by the host.

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

## The game API

`src/game/` ports `clsScriptFunctions` from the VB6 client: the ~130
procedures `.ds` scripts call. They fall into three groups.

*Pure helpers* are ported outright and tested directly: `FormatKB`,
`BoolToString`, `Coalesce`, `IsHex`, `TrimWithNewline`, `URLEncode`,
`RGBJoin`/`RGBSplit`, `ConsoleEscape`/`ConsoleUnescape`, path resolution and
the INI reader.

*Everything with side effects* goes through one of three traits, so the
desktop client, a headless run and the tests can each supply their own:

| Trait | Covers | Test double |
|---|---|---|
| [`Console`](src/game/console.rs) | `Say`, `Draw`, `ReadLine`, `TextWidth`, … | `RecordingConsole` |
| [`FileSystem`](src/game/fs.rs) | `FileExists`, `ReadDir`, `Cat`, `WriteINI`, … | `MemoryFs` |
| [`GameServer`](src/game/server.rs) | every networked call | `ScriptedServer` |

The networked surface needs only one seam because the client funnels it all
through `DoDownloadAPI`: a call starts a request and returns a handle, and
`WaitFor` resolves it later.

### Script encryption

[`game/crypto.rs`](src/game/crypto.rs) reimplements `basScriptCrypto`, whose
format has to match the server byte for byte because compiled scripts travel
between them. It is URL-safe base64 without padding, a bespoke SHA-256
key-derivation chain, AES-128-GCM with a 16-byte nonce (so J0 comes from
GHASH, not the 96-bit shortcut), and zstd behind a four-byte little-endian
length.

`tests/fixtures/compiled.ds` is a script compiled by the real VB6 client, and
decrypting it exercises all of that at once. It is keyed
`dso://210.189.133.233:80` — the client keys a downloaded script on
`dso://<host>:<port>`, trying the domain and falling back to the IP, and this
one took the fallback.

## Embedding

A host implements [`Host`](src/interp.rs). Its methods take `&self`, because
`Include`, `Run` and `Capture` run further script which calls straight back
into the same host; an implementation keeps its state behind its own
`RefCell`s and never holds a borrow across a nested call.

The usual entry point is [`game::GameHost`](src/game/mod.rs):

```rust
use vbscript::game::{run_script, GameHost};
use vbscript::game::{console::RecordingConsole, fs::MemoryFs, server::ScriptedServer};
use vbscript::interp::Interp;

let host = std::rc::Rc::new(GameHost::new(
    RecordingConsole::new(),
    MemoryFs::new(),
    ScriptedServer::new(),
));
let mut it = Interp::with_host(host.clone());
run_script(&mut it, r#"Say "hello""#).unwrap();
```

`Interp::set_step_budget` bounds how many statements a script may execute,
which matters because players can author scripts.

## Preprocessing

`Option` statements other than `Option Explicit` are parsed, collected into
`Interp::unknown_options`, and otherwise ignored, on the assumption that a
preprocessor will handle them.
