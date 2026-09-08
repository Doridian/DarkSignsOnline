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

What they do share is the player's files, and they share them by not each
having a copy. There is a fifth worker — `fsworker.ts` — which owns the tree
and is the only thing that touches storage. A console asks it over a
`MessagePort` and parks on `Atomics.wait` until the answer arrives in a shared
buffer, which is how a synchronous `Cat` works in a language whose filesystem
is asynchronous. Nothing is kept in step with anything, because there is only
one of it.

The fs worker reports every change it makes to the page, which is what the
file panel draws from — that is all the reporting is for now. Directories are
in that stream along with files: writing `/a/b.ds` makes `/a` on the way, and
`MD` on an empty directory is implied by nothing else.

`F1`–`F4` select a console, as in the original, and so do the tabs in the
status bar. An inactive console is hidden but still laid out, so it keeps its
scroll position and its scripts keep measuring against the width they will be
shown at.

## Stopping a script

`Ctrl+B` stops whatever the console on screen is running, as it does in the
original client, and it works whether the script is spinning in a loop of its
own or parked waiting on something.

It cannot be a message. A worker running a script is not draining its queue —
that is the whole reason it can block — so a `postMessage` would not be read
until the script it was meant to stop had already finished. What the page does
instead is set a flag in the block it shares with the worker
([`control.ts`](www/control.ts)), which is memory the worker can read without
being idle. A console parked on `ReadLine` is woken as well, since it would
otherwise not look at anything until someone typed a line the script is no
longer going to use.

The worker reads that flag through `Session`'s `stop_requested` callback, and
the interpreter acts on it **between statements** — never inside a host call.
A `Ctrl+B` during a write, a directory listing or a request lets that call
finish and stops at the statement after it, so nothing is left half-done. Two
things reach the interpreter, for the two shapes a script can have: it asks
the host every so many statements, which catches a tight loop, and the host
says so itself the moment a call it was blocked in returns, which catches a
script that spends its time waiting rather than running. `On Error Resume
Next` cannot swallow the stop; the script ends, `done` comes back as it would
from any other ending, and the prompt returns.

## Layout

| File | Role |
|---|---|
| [`src/lib.rs`](src/lib.rs) | `Session`, the API the worker drives |
| [`src/console.rs`](src/console.rs) | Console output as styled runs; input through blocking callbacks |
| [`src/metrics.rs`](src/metrics.rs) | Measures text with an `OffscreenCanvas`, for `TextWidth` |
| [`src/server.rs`](src/server.rs) | The game API over synchronous `XMLHttpRequest` |
| [`src/host.rs`](src/host.rs) | Supplies the clock, which wasm has no portable source for |
| [`www/worker.ts`](www/worker.ts) | Runs the interpreter; blocks on `Atomics.wait` for input |
| [`www/main.ts`](www/main.ts) | The page: the four consoles, keyboard, and waking a worker |
| [`www/console.ts`](www/console.ts) | Turns styled runs into elements |
| [`www/filetree.ts`](www/filetree.ts) | The file tree beside the consoles, and its three drags |
| [`www/mail.ts`](www/mail.ts) | The DSMail reader |
| [`www/chat.ts`](www/chat.ts) | The chat pane: the poll, the history, and `/me` |
| [`www/editor.ts`](www/editor.ts) | The editor, with the highlighter and the indenting |
| [`www/vbs.ts`](www/vbs.ts) | What a line of VBScript is made of, and how far it is indented |
| [`www/library.ts`](www/library.ts) | The file library and the text space |
| [`www/window.ts`](www/window.ts) | Dragging a sub-window by its title bar |
| [`www/types.ts`](www/types.ts) | Every message between the page, a worker and the wasm |
| [`www/control.ts`](www/control.ts) | The shared control block's three states |
| [`www/fonts.ts`](www/fonts.ts) | The font stacks, shared so text is measured in the face it is drawn in |

`www/words.ts` and `www/reference.ts` are the editor's vocabulary. The first
is generated by `build.sh` from the interpreter's own tables -- the lexer's
keywords and the two `match` arms that dispatch names -- so a name the
interpreter learns is a name the editor colours. The second is the API
reference the editor lists, taken from `clsScriptFunctions.cls` and filtered
to what the host actually implements.

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

## TypeScript

The page is TypeScript, compiled in place: `www/*.ts` are the sources and the
`www/*.js` beside them are build output, which is why they are gitignored.
Nothing bundles them -- `tsc` emits one module per source and the browser
loads them as they are.

`www/` is therefore sources and output together, and not what gets served.
`dist/` is: [`stamp.ts`](stamp.ts) copies each file the page can reach into it
under a name carrying the hash of its contents -- `main.<hash>.js`,
`pkg/dso_web_bg.<hash>.wasm`, every shipped `.ds` -- and rewrites every
reference to match. A URL then names one file of one build, which is what lets
the deployed site mark them `immutable` and lets a name from a build that is
gone answer 404 instead of something subtly wrong. `index.html` keeps its
name, being the address a player types, and is the only response that has to
be revalidated. A file nothing points at is not copied, which is why
`types.js` -- compiled from types alone, and empty -- does not ship.

Three projects, because their globals differ: `tsconfig.json` is the page,
`tsconfig.worker.json` the worker (whose `postMessage` is not the window's),
and `tsconfig.node.json` the two scripts and the test that run under node.
All extend `tsconfig.base.json`, which is strict and sets `allowJs: false`:
nothing untyped compiles.

`www/pkg/dso_web.d.ts` is generated by `wasm-bindgen` along with the module,
so `Session` and its methods are typed from the Rust rather than by hand.

## Building

The whole build is a flake package, and that is what CI and a deployment
use:

```sh
nix build .#darksignsonline-client   # the page, ready to serve
```

By hand, in a shell that has the toolchain:

```sh
nix develop         # rustc, wasm-bindgen, node, and clang for zstd's wasm build
npm install         # typescript, for the page

./build.sh          # wasm, the script bundle, and the page; `debug` for a debug build
npm run check       # type-checks all three projects, emitting nothing
npm test            # the editor's highlighting and indenting rules
node smoke.ts       # drives the built module the way the worker does
node serve.ts       # http://localhost:8080/game/
```

Without nix you need the wasm target and a `wasm-bindgen` CLI of exactly the
version `client/Cargo.lock` pins, because it refuses a module whose schema
another version wrote:

```sh
# A distro Rust may already carry the target; check with
# `ls $(rustc --print sysroot)/lib/rustlib` before reaching for rustup.
rustup target add wasm32-unknown-unknown
cargo install wasm-bindgen-cli --version 0.2.128
```

`build.sh` also copies the shipped `.ds` scripts into `www/scripts`, which the
page loads into the session's filesystem at startup. `stamp.ts` writes the
manifest naming them, mapping each file's path in the game's filesystem to the
URL it is served under, since only it knows the second.

## Serving it

Two headers are required, because without them `SharedArrayBuffer` is
unavailable and the worker cannot block for input:

```
Cross-Origin-Opener-Policy: same-origin
Cross-Origin-Embedder-Policy: require-corp
```

**Send them for every file the client ships, not just the page.** A dedicated
worker inherits the document's embedder policy, and the browser refuses a
worker script whose own response does not repeat it. WebKit applies that to
the whole module graph: `control.js`, `fonts.js`, `storage.js` and
`pkg/dso_web.js` are each refused without the header, the worker never starts,
and all four consoles stay dead. Chromium and Firefox only enforce it on
`worker.js` itself, so a host that gets this wrong works everywhere except
Safari -- which is to say everywhere except iOS, where WebKit is the only
engine there is.

`serve.ts` sends both headers on every response, which is why development
never showed this. The page says so plainly if it finds itself not
cross-origin isolated, but a page that *is* isolated can still have a worker
refused, and that failure is silent unless the console is open.

In production the page is `/game/` on the game server's own origin. The
`darksignsonline` package puts the two web roots together, giving the client
the `game/` directory to itself, and `server.conf` sends both headers for
everything under that prefix. The client is static: the page is the
directory's `index.html`, and nginx redirects `/game` to `/game/` and serves
it from there. Same origin means the API calls need no CORS at all. Every
asset sits under the same prefix, because a document at `/game/` resolves the
page's own `./main.<hash>.js` to `/game/main.<hash>.js`.

The one thing a host must get right besides the headers is that the page is
not cached the way its assets are. Their names are content hashes, so
`server.conf` marks them `immutable` and a browser never asks about them
again; `index.html` is the name that stays put, so it is served `no-cache` and
revalidated on every load. Getting that backwards is not a stale page but a
broken one: the deployed files come out of the nix store, where every mtime is
the epoch, so `Last-Modified` is a date in 1970 and a browser left to guess
gives the response five years of freshness. That is how one deploy left a
browser calling the new `pkg/dso_web.js` into the old wasm module.

`no-cache` alone does not finish the job, though, and the way it fails is
worth knowing because content hashing is what hides it. `no-cache` means
revalidate, not refetch, and the browser revalidates with whatever validator
it was given — so those validators have to be able to say *no*. Neither of
nginx's can here. It builds an `ETag` from the file's mtime and size, every
file has mtime 1, and `index.html` does not change size when a deploy changes
what it points at: `stamp.ts` writes a digest of fixed width, so
`style.<12 hex>.css` becomes `style.<12 hex>.css` and the page stays the same
number of bytes it was. Same size, same mtime, same ETag.

So the browser asks politely, nginx answers `304 Not Modified`, and the page
it keeps naming the previous build's assets — which are `immutable`, and
answered from cache for a year. The deploy is invisible to everyone who had
ever loaded the page, and the only cure is a hard reload nobody thinks to do.
`etag off` and `if_modified_since off` on that one location are what make
`no-cache` mean what it is there for.

`serve.ts` sends `no-store` for everything and no validators at all, which is
why development never showed this either.

`serve.ts` mounts the page at `/game/` too, so a path that works in
development is a path that works deployed.

## The title bar

The connection on the left, the account on the right, and nothing in the
middle that a game does not need. Signed out, the account is one button: the
sign-in form and the site's own "create an account" and "forgot your
password" pages hang from it in a menu, rather than sitting across the bar
for the whole of a session. Signed in there is nothing left to type, so the
button gives way to the name and a way out.

The two account pages are `/create_account.php` and `/forgot_password.php`,
linked root-relative because the client is served from `/game/` on that same
site, and opened in a new tab because leaving this one throws four consoles
away.

Signing out is an empty pair of credentials sent the way a sign-in is:
`Credentials` counts as set only with both halves, so all four sessions stop
authorizing anything they send, and the saved sign-in is forgotten. The
player's files stay — signing out is not clearing them.

The page never grows wider than the window: `body` is a grid of one
`minmax(0, 1fr)` column, so a row too wide for the viewport is made to fit
rather than pushing the rest past an `overflow: hidden` edge. The title bar is
the row that would, and the account is what sat on the far side of it.

## Remembering a sign-in

The "Remember me" box keeps the username and password in `localStorage` — not
the filesystem the game's own files live in, because the form is on the main
thread, a worker cannot reach `localStorage` at all, and a password is not a
file. They are stored as typed. There is
nowhere on a page to hide a password from anyone holding the browser, so the
box is the honest control, and it is off unless ticked. A remembered sign-in
reaches all four workers before any startup script runs, so every console is
already authorized by the time anything asks the server. Signing out forgets
it: the next load comes back signed out, with the username still in the form
and the password not.

## Starting up

`Start_Console` is followed exactly: console 1 runs `/system/startup.ds` and
the other three run `/system/newconsole.ds`, both from the player's own
filesystem, so an edited copy takes effect. A remembered sign-in is handed to
all four workers first, which is what lets the `LOGIN` and the `Include
"/system/newconsole.ds"` at the end of `startup.ds` do their job and greet the
player by name.

## The file tree

The panel to the left of the consoles, which the original had no equivalent
of. `Files` in the status bar slides it in and out — a margin, so the console
grows into the room rather than the panel being squeezed into nothing — and
which state it was left in is remembered.

It never polls. `listTree` gives it one picture of the filesystem, and after
that it applies the changes the fs worker reports as it makes them, so a file
written at console 3 appears here as it is written. Its model mirrors the
filesystem rather than what looks tidy: a directory stays after the last file
in it is deleted, because that is what the filesystem does and what `DIR` will
say.

Three gestures hang off it, each a plain HTML5 drag:

*A name dragged onto a console types its path.* The whole console takes the
drop, not the one-line input at the end of a tall log, and the path lands at
the caret with a space in front of it when the line does not already end in
one — the gesture is nearly always an argument for a command just typed. A
path with a space in it is quoted the way [`game::cli`](../src/game/cli.rs)
reads one back. The drag carries a private type as well as `text/plain`, so a
console can tell it from a file being dragged in from the desktop.

*A file is downloaded* from the button on its row. The contents live in a
worker, so there is nothing to point an `href` at until it has been asked
for: the answer becomes a blob and a link that is clicked and thrown away.

*Files dropped onto a folder are written into it.* A dropped folder is walked
through `webkitGetAsEntry`, and writing a file makes the directories above it,
so the shape comes across. Two kinds are refused rather than mangled:
anything over 512 KiB, since every one of the four sessions holds the whole
tree in memory, and anything that is not valid UTF-8 or that carries a NUL —
the game's filesystem holds strings, and a binary file has no honest
representation in it. A file dropped anywhere else on the page is refused
outright, because the browser would otherwise navigate to it and throw four
consoles' worth of session away.

## The filesystem

The player's files are the origin private filesystem, and nothing else. The
game tree is mirrored into it directly — `/home/music/theme.mp3` is
`fs/home/music/theme.mp3` — so what the game calls a filesystem and what the
browser stores are the same shape. An empty directory persists because it is a
directory; a song is a file because it is a file.

There is no second store and no id table. A blob's bytes are at the path that
names them, which is what makes copying a song a copy and renaming one a
rename, and which is why nothing has to reference-count anything or sweep for
bytes no name reaches.

Text is held in memory as well as on disk, because scripts read it
synchronously; that is one copy of some small script files, in the fs worker.
Media is never held — the tree keeps a size and a type, which is all `Dir` and
`FileLen` need — and the bytes are fetched only when something plays or reads
them.

What a file *is* is decided the same way at every entry point: by its name
where `media_type_for` recognises the extension, and by its bytes where it
does not — anything that is not valid UTF-8 cannot be text whatever it is
called. The same rule runs when a file is dropped in and when the tree is read
back off disk, so a dropped file and a reloaded one are always classed alike.

That decision could be removed altogether, and probably should be: it is
derived state that has drifted once already, and the way out costs less than
it looks — see
[`docs/dropping-file-classification.md`](../docs/dropping-file-classification.md).

The shipped scripts are not written out. They come with the client and are
refetched every load, so editing one saves the edit over it and deleting one
lasts until the next load — it was never the player's file to delete.

Where a browser has no OPFS the game still runs: the tree lives in memory for
as long as the tab does, media included, and the page says so once at startup.

## The sub-windows

Mail, the editor and the library are each a `<dialog>`, which the browser
centres and keeps modal -- and which covers the console underneath. So each
is dragged by its title bar, the way the desktop client's windows are. The
drag is an offset rather than a position, so the browser keeps deciding where
a window opens and a double-click on the bar puts it back there.

## The editor

`EDIT <file>` opens it, as in the original, and it saves as you type -- the
original's `AutoSave` on every keystroke, debounced. "Run (F5)" is its "Test
Script": the file is saved, the window closes, and the console that opened
the editor runs it.

Two things the original did not have:

*The text is coloured.* A line is tokenised in [`vbs.ts`](www/vbs.ts) and
drawn into a `<pre>` behind a transparent textarea, which keeps the caret,
the selection and the undo history the browser already does well. VBScript
has no multi-line string or comment, so a line can be tokenised on its own.
The game's `{{...}}` markup is picked out inside strings, since that is the
other language a script is written in.

*The indent carries.* Enter keeps the indent of the line above and adds a
level when that line opened a block; typing a word that closes one -- `Else`,
`End If`, `Next`, `Loop` -- pulls its own line back out again. Tab and
Shift+Tab move the line, or every line of a selection. It is the same two
rules VS Code uses, and the whole of what `vbs.ts` decides.

The list beside the text is the original's, brought forward: the API rather
than the old command language, searchable, and a double-click inserts a name.

## The file library

The status bar opens it, because the original opens it from a label on the
console rather than from a command. Browse a category and download a row into
`/downloads`, publish a file of your own, withdraw one, or read and write a
text-space channel. The wire format is parsed in Rust --
[`game::library`](../src/game/library.rs) -- so what reaches the page is
already rows.

Both of its endpoints still answer with the four-character status code that
protocol 2 otherwise did away with: `file_database.php` asks for it
unconditionally and `textspace.php` writes it by hand.

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

## Chat

`F5` raises it, as `ShowChat` does in the original, and it covers the console
rather than sitting beside it — it shares the grid cell the four consoles
stack in, which is that client's `ChatBox.ZOrder 0`. `F1`–`F4` put it away on
their way to a console, as the original's handlers do.

The room is not the one the original used. That client opened a TLS socket to
`irc.libera.chat:6697` and sat in `#darksignsonline`, which a browser cannot
do at all — it has no raw sockets. Libera does run a WebSocket gateway for
its own webchat, at `wss://web.libera.chat/webirc/websocket/`, but it answers
only to a page served from `web.libera.chat` and is behind Cloudflare besides,
so it is not something another client can use. Running our own gateway would
mean every player reaching Libera from the game server's single IP, which is
what their staff ask to be told about in advance because it trips the
network's anti-abuse limits.

So the room is the game server's own: [`api/chat.php`](../../server/www/api/chat.php),
one table, and a client that asks for whatever is newer than the last line it
holds — the same incremental shape `dsmail.php` has, for the same reason.
`chatlog.php`, which has said "not yet implemented" since the site went up, is
the same rows without an account.

### Why it polls, and why that is affordable

A held connection is not available here. `pm.max_children` is 5 for the whole
site, and long-polling pins one of those five per waiting client, so a handful
of players sitting in chat would be the whole server — the game API and the
website with it. Server-sent events have the same shape and the same problem.

What makes polling cheap enough to do properly is that **reading the room
needs no account**. `function.php` authenticates at include time, and that
check is a bcrypt: ~130ms of CPU at the deployed cost factor, paid by every
request that includes it. A one-second poll paying that would be 13% of a core
per player, watching or not. So `chat.php` includes `function_public.php` —
the database, the headers and the base64, without the password — answers the
read, and returns *before* `function.php` is ever pulled in. Anything after
that include is authenticated by construction, which is what makes the split
safe to extend: a new action added below it cannot forget to require an
account. Measured locally, the read went from 132ms to 3ms.

Reading being public is not a concession, either. It is what `chatlog.php`
has always done, so the client does the same: signed out, the pane still shows
the room and only the box is closed.

Cheap is not free, so the page still asks only when somebody is reading the
answer:

| State | Interval |
|---|---|
| Pane up, tab in front | 1s |
| Pane away, `ChatView` mirroring into the comm log | 5s |
| Tab in the background, or nobody reading either way | never |

Opening the pane, turning `ChatView` on and coming back to the tab each ask
straight away, so none of those wait for a tick. A failure backs off to
fifteen seconds. The fetch is incremental, so a tab left in the background
costs nothing and catches up in one request.

Above the transport it is the original's. A line reads `<who>  text`, `/me`
is an emote, `//` escapes a leading slash so a message can start with one,
and Up and Down walk back through the last fifty things typed — with the
trailing space the original adds, which is what lets a recalled line be
finished rather than edited. `/nick` and `/msg` are gone with IRC: a name
here is the account's and cannot be changed, and there is nobody to open a
query with, so both answer "Command not found" rather than pretending.

The two script functions are the original's two, and
[`game::chat`](../src/game/chat.rs) is where the rules they share live:

| Function | What it does |
|---|---|
| `ChatSend(msg)` | Trims and truncates as the original did, posts it, and shows it |
| `ChatView(on)` | Mirrors the room into the communications log |

`ChatView` is worth spelling out because the name suggests otherwise: it is
not the pane's visibility. The original keeps it in `chatToStatus`, and all
it decides is whether `displaychat` also calls `SayCOMM` — so a player
watching a script run still sees the room. F5 shows the pane regardless.

Both are local-only, as they are in `clsScriptFunctions`: a script fetched
from someone else's domain does not get to talk in the room as the player.

A line sent from here is drawn before the next poll can bring it round, so
both paths carry the id the server gave the row — `ChatSend` reports it on
its console event — and the panel draws an id once.

The opening backlog is a hundred lines and is not mirrored to the comm log,
whatever `ChatView` says: the original had no backlog to mirror, having seen
the room only from the moment it joined, and emptying a hundred lines into the
comm log at once is not what turning it on asks for.

What the original had and this does not is the user list, which came from
IRC's `353` and has no equivalent: the server tracks no presence.

## What is not here yet

- **Music.** `Music` reaches the page and stops there. The original plays
  mp3s out of the player's own `/home/music`, and there are none in a
  browser to play.
