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
- **`tests/game_scripts.rs`** parses the `.ds` corpus in `user/`.
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
| `.ds` scripts | 298 of 301 parse; 242 of 298 also run to completion |
| Host API | 74 integration tests, 117 unit tests |
| Live server | 4 tests, ignored by default |
| Browser build | `web/smoke.mjs`, driving the built wasm |

Of the 55 scripts that do not run to completion, 42 sit in a `While True`
menu loop waiting on player input and stop only when the step budget runs
out, and the rest fail because the run supplies no command-line arguments and
no live server. None of them indicate an interpreter or API problem.

The corpus run also reports the names the host does not provide, which is
down to three. `pingport` is a command name, reached through the command-line
parser rather than as a procedure. `SaySlow` and `QReadLine` come from
`specialstorage.ds`, which uses termlib without opening it first and so fails
the same way in the real client.

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

| Trait | Covers | Implementations |
|---|---|---|
| [`Console`](src/game/console.rs) | `Say`, `Draw`, `ReadLine`, `TextWidth`, … | `RecordingConsole` |
| [`FileSystem`](src/game/fs.rs) | `FileExists`, `ReadDir`, `Cat`, `WriteINI`, … | `MemoryFs`, `DiskFs` |
| [`GameServer`](src/game/server.rs) | every networked call | `ScriptedServer`, `OfflineServer` |

`DiskFs` is rooted at the player's directory and normalises every path
before joining it, so a script cannot reach outside even if it builds the
path itself.

### Libraries

`DLOpen "name"` loads `/system/libs/name.ds`; a name containing a path
separator is ignored, which is how the client keeps a script inside that
directory. `DLOpenHash` is content-addressed: the copy under `/system/libs`
is only trusted when it hashes to the name it is filed under, and otherwise
refetched from the server.

`DLOpen "termlib"` is special — in the client it registers a native class
rather than loading a script, so [`termlib.rs`](src/game/termlib.rs) provides
its seventeen members (`SaySlow`, `QReadLine`, the mission-progress helpers).
They stay invisible until the script opens the library, matching the client,
so a script that forgets `DLOpen` fails the same way it would in game.

The networked surface needs only one seam because the client funnels it all
through `DoDownloadAPI`: a call starts a request and returns a handle, and
`WaitFor` resolves it later.

### For the UI

Two pieces exist for the renderer and the input line rather than for
scripts:

[`markup.rs`](src/game/markup.rs) parses the `{{...}}` markup into styled
runs — font, size, colour, flash, alignment — so a renderer receives
segments it can draw rather than a string to re-parse. `RecordingConsole`
exposes `styled_output()` for exactly that.

[`cli.rs`](src/game/cli.rs) is the console's input path. The player types
`dir /home`, which is not VBScript, so it is rewritten as
`Call Run("dir", "/home")` before the engine sees it; anything that looks
like script is passed through untouched. Bare words resolve against the live
session, so `echo target` passes a variable if one exists and the text
otherwise. `GameHost::parse_command_line` wires it to the running
interpreter.

### Talking to the server

[`protocol.rs`](src/game/protocol.rs) holds the wire format with no
transport attached, so the desktop build, a browser build and the tests all
speak the same protocol and it can be tested without a network. Endpoint
names and request bodies match the VB6 client exactly, because scripts read
the raw response.

One header is not optional:

```
DSO-Protocol-Version: 2
```

Without it the server answers in a legacy mode that prefixes every body with
a four-character status code. Everything here expects the clean body, so a
missing header shows up as garbage at the front of every string.

Calls carry HTTP basic auth, and POST bodies are form-encoded.
`ResponseType` decides the shape the script receives — `bool_1` yields a
Boolean, `lines` an array, anything else the body as it arrived — and a
non-2xx status raises rather than returning.

[`http.rs`](src/game/http.rs) is the desktop transport, behind the
`native-http` feature. `tests/live_server.rs` runs against the real server;
it is ignored by default and reads credentials from `DSO_USER` and
`DSO_PASS`, so none live in the repository:

```sh
DSO_USER=... DSO_PASS=... cargo test --test live_server -- --ignored --nocapture
```

### DSMail and the file library

Two pieces of the client are windows rather than script API, and each has its
wire format here so the front end only ever sees rows:
[`mail.rs`](src/game/mail.rs) for `dsmail.php` and both of its formats, and
[`library.rs`](src/game/library.rs) for `file_database.php` and
`textspace.php` — the categories, the listing, an upload's checks, and where
a download is written.

### The browser client

[`web/`](web/) is the browser front end: this library compiled to WASM,
running in a worker, with a page that renders its console. Its page is
TypeScript. See [`web/README.md`](web/README.md) for how to build and serve
it, and for the editor and the library windows.

### Targeting the browser

The library builds for `wasm32-unknown-unknown`:

```sh
cargo build --lib --no-default-features --target wasm32-unknown-unknown
```

`--no-default-features` drops the blocking HTTP client, which a browser
build replaces. `DiskFs` is compiled out on that target too.

The interpreter is meant to run in a **worker**, not on the main thread.
That settles what would otherwise be the hard question: `WaitFor` blocks,
and blocking is fine in a worker — synchronous `XMLHttpRequest` still works
there, as does `Atomics.wait`. So [`GameServer`](src/game/server.rs) stays
synchronous, and the interpreter needs no resumability.

The same shape serves server-side execution, which is the point of putting
every platform dependency behind a trait: running a script somewhere the
player cannot tamper with it is a different set of `Console`, `FileSystem`
and `GameServer` implementations, not a different interpreter.

Two hooks on `Host` have no portable default and a browser build must
supply them:

| Hook | Browser |
|---|---|
| `now_unix_millis` | `Date.now()`. The default returns 0 on wasm, so dates start at the epoch until it is overridden. |
| `random_bytes` | Handled already — `getrandom`'s `wasm_js` feature reaches the Web Crypto API. |

### Corrections to the original

Two calls were wrong in the VB6 client and are fixed here, with tests
pinning the corrected shapes:

- `Transfer` assembled a form body and then sent a bare `GET`, discarding
  it, so the recipient, amount and description never reached the server.
- `RemoteToken`/`ServerToken` omitted an `&`, running two fields together as
  `is_local_script=trued=example.com`.

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
