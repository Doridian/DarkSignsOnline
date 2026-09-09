# DarkSigns Online

A VB6 game client rewritten as a Rust VBScript interpreter, compiled to WASM
and run in a browser, against the original PHP server. Both halves live here.

## Where things are

| Path | What |
|---|---|
| `client/src/` | The interpreter: lexer, parser, `Variant`, ops, tree-walking `interp.rs`, `builtins/` |
| `client/src/game/` | The host API — the ~130 procedures `.ds` scripts call, ported from `clsScriptFunctions` |
| `client/web/src/` | The wasm layer: `Session`, console, `XMLHttpRequest` server, text metrics |
| `client/web/www/` | The page, in TypeScript. Sources and their compiled `.js` together; **not** what is served |
| `client/web/dist/` | What is served. Written by `stamp.ts`, every asset named for its content hash |
| `client/user/` | The shipped player filesystem, bundled into `www/scripts` at build time |
| `client/tests/` | `wine.rs` (wine's VBScript conformance suite), `game_api.rs`, `game_scripts.rs`, `live_server.rs` |
| `server/www/api/` | The PHP endpoints, 28 of them |
| `server/rootfs/` | nginx, php-fpm, s6 — including `server.conf`, which sends COOP/COEP |

## Read these before asking the code

Both READMEs are long and current — they explain *why*, which the code does
not. Read the relevant section rather than re-deriving it.

- [`client/README.md`](client/README.md) — the interpreter, the three host
  traits (`Console`/`FileSystem`/`GameServer`), the wire protocol, the `*B`
  string limitation and why it stays.
- [`client/web/README.md`](client/web/README.md) — the worker architecture,
  `Ctrl+B`, OPFS, the editor, chat, mail, the library, and the serving rules.
- `client/docs/` — four design notes, each a decision with measurements:
  `string-representation-performance.md`, `dropping-file-classification.md`,
  `fixing-the-mojibake.md`, `disk-usage-meter.md`.

## Commands

Everything goes through the flake, which is what CI uses.

```sh
nix develop                       # rustc, clippy, wasm-bindgen, node, clang for zstd's wasm build

# Rust, from the repo root
nix develop --command cargo clippy --manifest-path client/Cargo.toml --workspace --all-targets -- -D warnings
nix develop --command cargo test  --manifest-path client/Cargo.toml --workspace

# The browser client, from client/web/
./build.sh                        # wasm + wasm-bindgen + editor vocabulary + script bundle + tsc + stamp into dist/
npm run check                     # type-checks all three tsconfig projects, emits nothing
npm test                          # the editor's highlighting and indenting rules
node smoke.ts                     # drives the built wasm the way the worker does, no browser
node serve.ts                     # http://localhost:8080/game/  (sends COOP/COEP and no-store)

nix build .#darksignsonline-client   # the page as CI builds it
nix build .#darksignsonline          # the whole site, client under game/
```

`build.sh` is the whole loop: editing `www/*.ts` alone changes nothing that is
served, because `serve.ts` serves `dist/` and `stamp.ts` is what writes it.

The live-server tests are ignored by default and read credentials from the
environment, so none are in the repo:

```sh
DSO_USER=... DSO_PASS=... cargo test --test live_server -- --ignored --nocapture
```

## Things that bite

- **`DSO-Protocol-Version: 2`** on every API request. Without it the server
  answers in a legacy mode that prefixes each body with a four-character
  status code, and it shows up as garbage at the front of every string.
  `file_database.php` and `textspace.php` still send that code regardless.
- **COOP/COEP on every file the client ships**, not just the page. WebKit
  enforces the embedder policy across the whole module graph, so a host that
  gets this wrong works everywhere except Safari — which is to say iOS.
- **The page is `no-cache`, its assets are `immutable`.** nginx also needs
  `etag off` and `if_modified_since off` on that location: nix store mtimes
  are the epoch and `index.html` never changes size, so nginx would answer
  `304` to a genuinely new build. See `client/web/README.md`.
- **wasm has no native host.** No `std::fs` on the hot path (`MemoryFs` yes,
  `DiskFs` no), no `SystemTime::now`, no `/dev/urandom`; `getrandom` needs its
  `wasm_js` feature and `zstd-sys` needs clang for the target.
- **`wasm-bindgen` CLI must match the version `client/Cargo.lock` pins**
  (0.2.128). It refuses a module another version's schema wrote. `nix develop`
  gives you the right one.
- **The filesystem is case-insensitive**, folded to lower case before it
  reaches a backend, as the Windows tree the VB6 client used was.

## Conventions

- **Commit straight to `main`** and push there. No feature branches.
- **PHP diagnostics are server bugs.** Never teach the Rust or TypeScript
  client to parse around a notice or warning — fix the endpoint in
  `server/www/api/`. The usual cause is an unguarded `$_REQUEST['x']`.
- Stage precisely; the working tree usually carries unrelated changes.

## Testing in WebKit

Safari and iOS bugs reproduce locally — WebKit is the same engine and
playwright drives it on this machine. The rig is machine-specific and
gitignored: @.claude/webkit.md
