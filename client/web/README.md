# dso-web

The DarkSigns client in a browser: the interpreter compiled to WASM, running
in a worker, with a page that renders its console.

## Why a worker

Scripts block. `ReadLine` waits for the player and `WaitFor` waits for the
server, and the browser forbids both on the main thread. Inside a worker they
are fine — a synchronous `XMLHttpRequest` is allowed there, and `Atomics.wait`
parks the worker until the page delivers a typed line.

That is what lets [`GameServer`](../src/game/server.rs) stay synchronous and
the interpreter stay straightforward.

## Four consoles, four workers

The client has four consoles, as the desktop one does, and each gets a worker
and a `Session` of its own. They cannot share one: a console blocked in
`ReadLine` blocks its whole worker, and the point of having four is that the
other three keep working. Scripts read which one they are in as `ConsoleID`.

What they do share is the player's files. Each session holds its own copy of
the tree, so a write is reported to the page and passed on to the other three
as a seed — a change that is neither persisted twice nor echoed back. Only
the console that made it writes it to IndexedDB.

`F1`–`F4` select a console, as in the original, and so do the tabs in the
status bar. An inactive console is hidden but still laid out, so it keeps its
scroll position and its scripts keep measuring against the width they will be
shown at.

## Layout

| File | Role |
|---|---|
| [`src/lib.rs`](src/lib.rs) | `Session`, the API the worker drives |
| [`src/console.rs`](src/console.rs) | Console output as styled runs; input through blocking callbacks |
| [`src/metrics.rs`](src/metrics.rs) | Measures text with an `OffscreenCanvas`, for `TextWidth` |
| [`src/server.rs`](src/server.rs) | The game API over synchronous `XMLHttpRequest` |
| [`src/host.rs`](src/host.rs) | Supplies the clock, which wasm has no portable source for |
| [`www/worker.js`](www/worker.js) | Runs the interpreter; blocks on `Atomics.wait` for input |
| [`www/main.js`](www/main.js) | The page: the four consoles, keyboard, and waking a worker |
| [`www/console.js`](www/console.js) | Turns styled runs into elements |
| [`www/mail.js`](www/mail.js) | The DSMail reader |
| [`www/fonts.js`](www/fonts.js) | The font stacks, shared so text is measured in the face it is drawn in |

Markup is parsed in Rust, so the page receives runs with a font, size and
`#rrggbb` colour and never has to understand `{{...}}`.

## Measurements

`TextWidth`, `ConsoleWidth` and `PreSpaceWidth` are one unit in the original —
twips — because scripts subtract one from another to decide where a column
ends. Here that unit is the CSS pixel: the page reports the width of a console
and the indent a line carries, and the worker measures text with an
`OffscreenCanvas`. Measuring in the worker is what makes it affordable, since
`TextWidth` is called in loops and a round trip to the page for each call
would not be.

## Building

```sh
# A distro Rust may already carry the target; check with
# `ls $(rustc --print sysroot)/lib/rustlib` before reaching for rustup.
rustup target add wasm32-unknown-unknown
cargo install wasm-bindgen-cli --version 0.2.128

./build.sh          # release; pass `debug` for a debug build
node smoke.mjs      # drives the built module the way the worker does
node serve.js       # http://localhost:8080
```

`build.sh` also copies the shipped `.ds` scripts into `www/scripts` with a
manifest, which the page loads into the session's filesystem at startup.

## Serving it

Two headers are required, because without them `SharedArrayBuffer` is
unavailable and the worker cannot block for input:

```
Cross-Origin-Opener-Policy: same-origin
Cross-Origin-Embedder-Policy: require-corp
```

`serve.js` sends them. Any static host will do as long as it does the same;
the page says so plainly if it finds itself not cross-origin isolated.

## Remembering a sign-in

The "Remember me" box keeps the username and password in `localStorage` — not
the IndexedDB the files use, because the form is on the main thread and a
worker cannot reach `localStorage` at all. They are stored as typed. There is
nowhere on a page to hide a password from anyone holding the browser, so the
box is the honest control, and it is off unless ticked. A remembered sign-in
reaches all four workers before any startup script runs, so every console is
already authorized by the time anything asks the server.

## Starting up

`Start_Console` is followed exactly: console 1 runs `/system/startup.ds` and
the other three run `/system/newconsole.ds`, both from the player's own
filesystem, so an edited copy takes effect. A remembered sign-in is handed to
all four workers first, which is what lets the `LOGIN` and the `Include
"/system/newconsole.ds"` at the end of `startup.ds` do their job and greet the
player by name.

## Mail

`mail` at the prompt opens the reader, which is the only way in, as in the
original. The window is a page, but the connection is a worker's: credentials
never leave the workers, so the reader asks whichever console is free and that
one speaks to `dsmail.php`. A console blocked in `ReadLine` is not free, and a
question waits for one that is.

The inbox is handed out incrementally — a request asks for everything newer
than the highest id already held — so the client keeps its own copy in
`/system/mail.dat`, the original's file in the original's format, complete
with the read flag the server does not track. It is written through the
filesystem like any other file, so it persists and the other three consoles
see it. [`mail.rs`](../src/game/mail.rs) holds both formats and is where the
tests are.

Unlike the original, `MAIL` does not hold the script up while the window is
open. It cannot: the worker that raised it is the one still running the
script, and blocking it would leave nothing able to answer the window.

## What is not here yet

- **Chat.** The original opens a TLS socket to `irc.libera.chat:6697` and
  speaks IRC. A browser has no raw sockets, so this cannot be a client-side
  port at all — it needs something server-side to sit on the IRC connection
  and offer a WebSocket, and that does not exist yet.
- **The editor and the file library.** Both are console events the page
  logs and ignores. Neither needs anything new to be possible; they are the
  same shape as the mail window.
- **Stopping a running script.** `Ctrl+B` reaches a console that is waiting
  for input, which is all a blocked worker can hear; one busy in a loop runs
  until its step budget is spent.
