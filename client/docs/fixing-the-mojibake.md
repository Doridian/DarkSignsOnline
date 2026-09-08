# Fixing the mojibake

[`dropping-file-classification.md`](dropping-file-classification.md) made file
I/O byte-oriented and left one thing behind: a file of non-ASCII text reads
back as the mojibake its bytes spell. The engine's own files dodge it by
declaring their encoding — `read_text`/`write_text` in
[`fs.rs`](../src/game/fs.rs), used at 15 sites. This is what it would take to
fix the display and delete that pair.

**Done.** Option 1 below is what the client now does: one code page,
windows-1252, for every file it reads or writes. The last section says what
was built and where it went further than the plan.

## The shape of the problem

Three properties are wanted and only two can be had:

1. **One character per byte.** `Open ... For Binary` is what VB6 gave a
   DarkSigns script, so `Len` of a file's contents is its size and `Mid`
   indexes into it by byte.
2. **A lossless round trip.** Bytes read and written back are the same bytes.
3. **The full Unicode repertoire in a file.**

(1) and (2) together say the map from bytes to characters is injective on 256
inputs and its inverse is total on whatever a file can hold — so a file can
hold exactly 256 distinct characters, and (3) is gone. There is no clever
encoding that escapes this; it is counting.

So every option below is a choice of which one to drop, and the interesting
part is that **the client already drops (3)** — `text_to_bytes` substitutes
`?` above U+00FF, and has since the byte change. `read_text`/`write_text`
exist to carve out a set of files that get (3) back by giving up (1) and (2).
Two conventions in one filesystem is what produces the mojibake: the editor
writes UTF-8 and `Cat` reads Latin-1.

## Where the two conventions meet

| Written by | As | Read by | As |
|---|---|---|---|
| the editor ([`fsworker.ts:209`](../web/www/fsworker.ts)) | UTF-8 | `Cat` | Latin-1 |
| `Overwrite`, `Append` | Latin-1 | the editor ([`fsworker.ts:241`](../web/www/fsworker.ts)) | UTF-8, fatal |
| `Run`, `Include`, `DLOpen`, INI, mail store | UTF-8 | the same | UTF-8, fatal |

Type `café` in the editor and `Cat` prints `cafÃ©`. Write it from a script and
the editor shows nothing at all, because its decode is `fatal: true` and byte
0xE9 alone is not UTF-8. Both directions are wrong, and they are wrong in
opposite ways.

The failure also leaks into places that have nothing to do with encodings. A
script whose bytes are not valid UTF-8 cannot be uploaded to the library, and
the message it gets is `The file does not exist`
([`lib.rs:384`](../web/src/lib.rs)) — `read_text`'s error is discarded and
replaced with the wrong one.

## What the corpus actually holds

Of the **301** `.ds` files the client ships, **299 are pure ASCII**. The two
that are not are `darksigns/mission_scripts/q.ds` and `website.ds`, and what
they contain is not text — it is **U+FFFD**, the replacement character,
already there in the import commit (`8c6a1b0`, April 2024). In `q.ds` it sits where an opening
curly quote belongs:

```
' *say 5 Quaero is Latin and means:<FFFD>To seek, to search for, to get, to obtain".
```

That is windows-1252 byte 0x93 lost to a lossy UTF-8 decode somewhere
upstream of this repo. In `website.ds` it is worse: the replacements are
inside the obfuscated `SaySlow` strings, so the payload is unrecoverable.

Two things follow. The original data is **windows-1252**, as a 2005 VB6
client on a Western Windows would be. And the repertoire question is
theoretical for the shipped tree and practical only for what a player writes.

## Option 1 — name the code page

Keep (1) and (2). Change which 256 characters they are.

The client already has a single-byte code page; it just never named one. Four
places implement it independently and all four picked the identity map:

| | |
|---|---|
| [`fs.rs:80`](../src/game/fs.rs) | `bytes_to_text` — `b as char` |
| [`fs.rs:89`](../src/game/fs.rs) | `text_to_bytes` — `c as u8` under U+0100 |
| [`conv.rs:302`](../src/builtins/conv.rs) | `Chr` — `(b as char)` |
| [`conv.rs:282`](../src/builtins/conv.rs) | `Asc` — `c as u32` under 256 |

`conv.rs:297` even says so: *"Outside Latin-1 there is no single-byte form;
report the low byte, as the ANSI code page would after a lossy conversion."*
The ANSI code page it is standing in for is windows-1252.

Swapping Latin-1 for **WHATWG windows-1252** costs one 32-entry table.
Verified: all 256 bytes map to 256 distinct code points, because the five
slots cp1252 leaves undefined (0x81, 0x8D, 0x8F, 0x90, 0x9D) map to the C1
controls of the same value. So it is a bijection and (1) and (2) survive
intact. What it buys is the 27 characters Latin-1 wastes on invisible C1
controls:

```
€ ‚ ƒ „ … † ‡ ˆ ‰ Š ‹ Œ Ž ' ' " " • – — ˜ ™ š › œ ž Ÿ
```

Then `read_text`/`write_text` go, and every file uses the one convention.
The editor decodes with `new TextDecoder("windows-1252")` — native, no
dependency — and encodes with the inverse table. Editor and script now agree,
and the mojibake is gone in both directions.

**It is strictly better than today at the boundary it changes.** Every
character `text_to_bytes` can store today it still stores; 27 more join them;
27 that read back invisible now read back as themselves.

**What it costs** is the files that currently get the UTF-8 carve-out. A
script a player writes with `中` in a literal works today and would become
`?`. For a tree that is 99.3% ASCII and a game whose original client would
have done the same substitution, that is a defensible trade — but it is
silent and one-way, and existing OPFS content written as UTF-8 by the editor
re-reads as mojibake with no marker to detect it.

**What it fixes beyond the display.** Library upload and download become
lossless for any byte content, because `bytes_to_text` cannot fail: today
they are lossless only for files that happen to be valid UTF-8, and fail with
the wrong message when they are not.

## Option 2 — escape what will not decode

Drop (1), keep (2) and (3).

Decode as UTF-8; for each byte that is not part of a well-formed sequence,
emit a private-use character — byte `b` → U+E000 + `b`, so U+E080..U+E0FF.
Encode back by mapping that range to its byte and everything else to UTF-8.
This is Python's `surrogateescape` with a private-use plane instead of lone
surrogates, which Rust's `String` cannot hold.

The round trip is exact, `read_text` is unnecessary, text of any script
displays correctly, and binary shows as visibly-wrong boxes rather than
plausible-looking mojibake — arguably an improvement.

What breaks is one character per byte. `Len` of a file's contents stops being
its size, `Mid` stops indexing by byte, and
`reading_a_song_gives_one_character_per_byte` in
[`game_api.rs`](../tests/game_api.rs) is asserting the property this removes.
Nothing in the corpus depends on it — all 73 `Asc(` sites are `Asc("1")`-style
literals and no script indexes file bytes — but it is the property the
previous change was built to establish, and it is what `Open For Binary`
means.

The editor needs the same escape in TypeScript to stay lossless, so the
saving is smaller than it looks: the encoding logic is duplicated either way,
and only the size cap can be dropped from `editorText`.

## Option 3 — byte strings end to end

Keep (1), (2) and (3), and drop the assumption that a `Value::Str` is what
gets displayed. Strings become byte strings everywhere; UTF-8 is decoded only
at the renderer.

This works on paper and is the most faithful to VB6, and it is much larger
than it sounds, because a string's provenance stops being uniform. Text
arriving from the server is Unicode already — `xhr.response_text()`
([`server.rs:82`](../web/src/server.rs)), `read_to_string`
([`http.rs`](../src/game/http.rs)), and the three `decode_text` helpers in
[`chat.rs`](../src/game/chat.rs), [`mail.rs`](../src/game/mail.rs) and
[`library.rs`](../src/game/library.rs) — as is the player's typed input
(`deliverInput`, [`main.ts:406`](../web/www/main.ts)). All of it would have to
be re-encoded to bytes on arrival or the renderer would double-decode it. And
every display surface would have to decode: `Run.text` and `ChatSent` in
[`console.rs`](../web/src/console.rs), `TextWidth`/`TextHeight` through
[`metrics.rs`](../web/src/metrics.rs), the editor, the file panel, the mail
window.

It also breaks `Chr`. Under byte strings `Chr(233)` is one byte, 0xE9, which
is not valid UTF-8 alone and renders as U+FFFD — where today and in VB6 it is
`é`.

And it is the change [`string-representation-performance.md`](string-representation-performance.md)
priced and rejected, in a weaker form: the decode it measured at **57.8 ns**
per 42-character console line, against 3355 `Say` sites, lands on the same
boundary. Doing it without changing `Value` to `Rc<[u8]>` keeps the cost and
gives up the type checking that would find the sites.

## Recommendation

**Option 1.** It is a 32-entry table plus 15 call-site deletions; it fixes the
display in both directions; it is a strict improvement on the byte boundary
the client already has; it removes a failure mode from library upload; and it
makes explicit a code page that four separate functions are already guessing
at. Options 2 and 3 each buy the full repertoire — which the corpus does not
use — by giving up a property the client just spent a change establishing.

### Checklist

1. Add the windows-1252 table and route `bytes_to_text`/`text_to_bytes`
   through it. Assert the bijection in a test over all 256 bytes.
2. Delete `read_text`/`write_text`; move the 15 call sites to `read`/`write`
   with `bytes_to_text`/`text_to_bytes`.
3. `editorText` in [`fsworker.ts`](../web/www/fsworker.ts): decode
   `windows-1252`, drop the `fatal` gate, keep `EDITOR_LIMIT`. `writeFile`:
   encode with the inverse table rather than `TextEncoder`.
4. Fix `Download { bytes: contents.len() }` in
   [`lib.rs:344`](../web/src/lib.rs) — it reports UTF-8 length, which stops
   matching the file size.
5. Restore the real error from the library upload read, now that a read can
   only fail for a real reason.
6. Decide whether `Chr`/`Asc` move too. They need not — nothing forces it —
   but leaving them on Latin-1 keeps two code pages in one client for no
   reason, and `api.vbs` only exercises `Chr(220)` and `Chr(255)`, which are
   identical under both, so the suite does not constrain the choice. Moving
   them closes a real VB6 gap: on an English Windows `Chr(147)` is `"`.

### What it does not fix

`URLEncode` percent-encodes `s.as_bytes()` — UTF-8, where VB6 encoded one
ANSI byte ([`values.rs:87`](../src/game/values.rs)). Chat, mail and library
payloads are base64 of UTF-8 on the wire, where the original client sent
base64 of ANSI. Both are protocol-compatibility questions with the server and
the original client, not display questions, and neither is touched by any
option here.

## What was built

`src/codepage.rs` is the table, and it is the only place the mapping is
spelled out in Rust. `bytes_to_text` and `text_to_bytes` call it, and so do
`Chr` and `Asc` — checklist item 6, taken, because the alternative was two
code pages in one client and the conformance suite only pins `Chr(220)` and
`Chr(255)`, which windows-1252 and Latin-1 agree on. `api.vbs` and its three
`KNOWN_FAILURES` are unchanged.

`read_text`/`write_text` are gone. All 15 call sites — `Include`, `Run`,
`Capture`, `DLOpen`, `DLOpenHash`'s cache, the INI pair, and the six in the
wasm bridge — read and write bytes and go through the code page like
everything else.

`web/www/codepage.ts` is the page's copy, for the editor. Decoding is
`TextDecoder("windows-1252")`, which is exactly the mapping the engine has,
five undefined positions and all; only the encoder is written out, because
`TextEncoder` speaks UTF-8 and nothing else.

### Three things the plan did not mention

**The shipped scripts were loaded as text.** `loadStartupFiles` fetched every
script with `response.text()` and `GameFs.load` re-encoded it with
`TextEncoder` — a UTF-8 round trip in front of the code page, which would
have destroyed a windows-1252 byte on its way from the repo to OPFS. It is
`arrayBuffer()` now, and `start`'s `files` carries `Uint8Array`. This is the
same mechanism that damaged two scripts in the first place; it was still in
the loading path.

**The corpus tests read scripts with `read_to_string`.** So did
`legacy_scripts_are_rejected`. Both now read bytes through `bytes_to_text`,
which is the only reading of a script the client has.
`no_script_carries_the_mark_of_a_lossy_decode` guards the tree against the
next tool that assumes UTF-8.

**Running a song reports a syntax error, not a bad file mode.** With no
reading that refuses to hand the bytes over, `Include` on an MP3 fails in the
parser rather than at the read. That is where VB6's refusal came from too.

### The corpus

Two files, in both the shipped tree and the test tree, held the sixteen
replacement characters a lossy decode left behind. They are listed in the
commit; `q.ds` had one, reconstructed as the windows-1252 byte it must have
been, and `website.ds` had fifteen inside decorative literals nothing
decodes, which are unrecoverable and took the code page's own substitute.

### What it was checked against

The Rust suite (179 lib, 110 `game_api`, 3 `game_scripts`), `api.vbs` under
Wine with its three known failures unchanged, `npm run check`, `node
smoke.ts`, and the real client in Chromium over real OPFS: all 256 bytes
written from a script and read back as 256 characters, first 0 and last 255,
still 256 after a reload with byte 147 intact at its offset; `Asc(Chr(147))`
= 147 and `AscW(Chr(147))` = 8220, rendered on the console as `“`; the
repaired `q.ds` arriving from the server with its byte intact, found by
`InStr(q, Chr(147))` at 16947 of 18277; and `café—quote“` written by a
script, read back by `Cat`, and shown by the editor as itself — which is the
whole point, and did not work before.
