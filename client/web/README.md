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

## Layout

| File | Role |
|---|---|
| [`src/lib.rs`](src/lib.rs) | `Session`, the API the worker drives |
| [`src/console.rs`](src/console.rs) | Console output as styled runs; input through blocking callbacks |
| [`src/server.rs`](src/server.rs) | The game API over synchronous `XMLHttpRequest` |
| [`src/host.rs`](src/host.rs) | Supplies the clock, which wasm has no portable source for |
| [`www/worker.js`](www/worker.js) | Runs the interpreter; blocks on `Atomics.wait` for input |
| [`www/main.js`](www/main.js) | The page: keyboard, prompt, and waking the worker |
| [`www/console.js`](www/console.js) | Turns styled runs into elements |

Markup is parsed in Rust, so the page receives runs with a font, size and
`#rrggbb` colour and never has to understand `{{...}}`.

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
is sent to the worker before the startup script runs, so the session is
already authorized by the time anything asks the server.

## What is not here yet

- **The real `/system/startup.ds`.** The page runs an inlined copy of its
  banner instead, so the `LOGIN` and `Include "/system/newconsole.ds"` at its
  end never run and no "New Console #1" appears. That was the right call when
  nothing could be signed in before the script ran; now that a remembered
  sign-in happens first, the inlined copy could give way to the file.
- **Text metrics.** `TextWidth` counts characters rather than measuring the
  font, so scripts that lay out columns will be off. Measuring properly means
  a round trip to the page for a call scripts make in loops, so it needs a
  cache or an `OffscreenCanvas` in the worker.
- **The rest of the UI.** Chat, mail, the editor and the file library are
  console events the page currently logs and ignores.
