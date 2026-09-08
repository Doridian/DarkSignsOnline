# Dropping file classification

The browser filesystem used to decide, for every file, whether it held text
or bytes. This is what that decision cost, three ways to stop making it, and
why the cheapest one turned out not to touch the interpreter at all.

**Done.** Option 3 below is what the client now does: file I/O is
byte-oriented, nothing stores a kind, and `Value` was not touched. The last
two sections say what was built and where it differs from the plan.

Companion to [`string-representation-performance.md`](string-representation-performance.md),
which priced the string representation change this was expected to need.

## What classified, and where

The tree stored a kind per path. In Rust that was `NodeKind::{Text, Blob}`
and `BlobRef` in [`fs.rs`](../src/game/fs.rs); in the browser it was the
`Node` union and `classify()` in [`opfs.ts`](../web/www/opfs.ts). Off it
hung:

- `FsError::NotText` → VB error 54, raised by `read` and `append` on a blob
- `raw_kind`, `raw_read_blob`, `raw_write_blob` and their folding wrappers
- `MemoryFs`'s separate `blobs` map and the `clear_node` refcount scan
- `CAT_BLOB_LIMIT` and `bytes_as_noise` in [`mod.rs`](../src/game/mod.rs)
- `SNIFF_LIMIT` and `UNKNOWN_MEDIA` in the browser, and the media type the
  file panel labels a row with

It is derived state — computed from the bytes, then stored — and it has
already drifted once. `putFile` refused to sniff anything over half a
megabyte while the boot walk had no such limit, so a large extension-less
file that happened to be valid UTF-8 was bytes when dropped in and text when
read back at the next load. Fixed by routing both callers through one
`classify`, but the shape that allowed it is inherent to storing a decision
rather than making it.

## Why it exists

Because the engine's filesystem API is typed. `FileSystem::read` returns
`FsResult<String>` — a Rust `String`, which must be valid UTF-8 — and
`read_blob` returns `Vec<u8>`. Two operations, and something has to pick
between them.

VB6 had the same split: `Open ... For Input` against `For Binary`. The
difference is that there the *caller* declared the mode, and a DarkSigns
script never does — it calls `Cat` and expects text. So the tree infers what
the script would have declared. That is why `NotText` maps to error 54, "Bad
file mode": it is VB's own error for using the wrong mode on a file, and it
is the same mistake.

Two lesser reasons ride along. The kind decides what is held in memory —
text is, media is not, because the tree only needs a name, a size and a type
to answer `Dir` and `FileLen`. And `<audio>` needs a MIME type, since OPFS
hands files back with an empty one.

Neither of those is load-bearing any more. Since the filesystem moved into a
worker of its own, every read is already a round trip to something that can
`await`, so contents could come off disk on demand and nothing be held. And
the MIME type is a pure function of the name, wanted only at playback.

Only the typed API is irreducible.

## Three ways out

### 1. Convert `Value::Str` to `Rc<[u8]>`

Priced in the companion doc: a ~19:1 net regression concentrated in `Say`,
which is the corpus's most common operation, and a doubled string heap that
bites worst on the WASM target. 46 `Value::Str` sites, all visited.

Both of those costs come from the representation being the little-endian
**UTF-16 image**, which is what `*B` accuracy requires. A file byte widens
into it at two bytes per byte, so `Cat` of a 50 MB song is a 100 MB string.

### 2. Add a `StrB(Rc<[u8]>)` arm beside `Str(Rc<str>)`

Also priced there: **+1.1% on the corpus** for having two arms at all, with
`Say` unmoved because text stays `Rc<str>` and `to_vb_string()` stays a
refcount bump. Produce `StrB` only when a read's bytes are not valid text.

The price is correctness surface. Of the 46 `Value::Str` sites, 5 are
exhaustive matches the compiler catches; ~16 are construction sites needing
no change; the remaining ~22 are `matches!(v, Value::Str(_))` tests and
`match` arms ending in `_ =>`, where a missed case is a silent wrong answer.
The dangerous ones are the five type tests: a `StrB` not recognised as
stringy makes `+` add instead of concatenate and makes comparison numeric
instead of textual.

`to_vb_string()` is the real chokepoint either way — 51 call sites across the
crate, 26 of them in `strings.rs`. Almost every builtin funnels through it
rather than matching on the variant.

### 3. Make file I/O byte-oriented

No change to `Value` at all. This is the recommendation, for the reason
below.

## The finding

**A `Value::Str` already carries arbitrary bytes losslessly.** Verified:

```vbscript
Dim s, i
s = ""
For i = 0 To 255
    s = s & Chr(i)
Next
MsgBox "Len = " & Len(s)          ' 256
For i = 0 To 255
    ' Asc(Mid(s, i + 1, 1)) = i for every i
Next
```

256 distinct bytes in, `Len` of 256, every byte back through `Asc`. Bytes
0x80–0xFF become characters U+0080–U+00FF, one character per byte, so `Len`
equals the byte count and indexing is byte indexing.

The engine already relies on this. `DecodeBase64Str` in `mod.rs` is
`bytes.iter().map(|&b| b as char).collect()` — the same widening, shipped and
in use.

So the representation change was never needed for this. It is needed to fix
`*B` odd-lengths, and `*B` has **no users**: zero uses of `LenB`, `LeftB`,
`RightB`, `MidB`, `ChrB` or `AscB` across 306 shipped files.

### And it is not a deviation from VBScript

VBScript has no opinion about `Cat` and `Overwrite`; those are DarkSigns host
API. VB6's own file I/O was byte-oriented — one character, one byte, through
the codepage. The current UTF-8 file I/O is the deviation, and going
byte-oriented moves toward the original client rather than away from it.

Nothing in the conformance suite changes. Not one of the 1033 `api.vbs`
assertions, and not the three `KNOWN_FAILURES`, which stay exactly as they
are.

## Comparison

| | `Value` change | Sites that fail silently | String heap | `Cat` of a 50 MB song | Conformance |
|---|---|---|---|---|---|
| 1. Full `Rc<[u8]>` | yes | 46 | 2× | 100 MB | 3 failures close |
| 2. `StrB` arm | yes | ~22 | 1× text, 2× bytes | 100 MB | 3 failures close |
| **3. Byte file I/O** | **none** | **0** | **1×** | **50 MB** | **untouched** |

## What option 3 changes

**The trait.** Only 3 of the 13 methods carry content; the other ten take
paths and stay `&str`.

- `raw_read → FsResult<Vec<u8>>`, `raw_write` and `raw_append` take `&[u8]`
- delete `raw_kind`, `raw_read_blob`, `raw_write_blob` and their three
  wrappers, `NodeKind`, `BlobRef`, `FsError::NotText`
- `MemoryFs`: `Node` collapses to `Vec<u8>`; the `blobs` map, `clear_node`,
  `with_blob` and `put_blob` all go
- `DiskFs` loses its `media_type_for` read refusal
- `copy` loses its branch

**The engine.** Six places consume file contents:

| Site | Becomes |
|---|---|
| `mod.rs` `Cat`/`Display` | widen bytes to characters; delete `bytes_as_noise`, keep one uniform size limit |
| `mod.rs` `Include`/`Run` | decode as UTF-8, error if it fails — correctly, since including binary is meaningless |
| `mod.rs` `Overwrite`/`Append` | narrow characters to bytes |
| `lib.rs` editor `readFile` | widen |
| `lib.rs` library upload | bytes |
| `lib.rs` mail store | explicit UTF-8, see below |

Classification does not vanish so much as relocate, from the file to the
operation. `Include` on an mp3 fails because including binary is meaningless,
not because the file carries a flag. That is where the decision belongs and
it is what a real filesystem does.

**The browser.** `read` and `readBlob` collapse into one raw-bytes op, since
a JSON reply cannot carry bytes and the raw channel already exists. `Node`
becomes a size. `classify`, `SNIFF_LIMIT` and `UNKNOWN_MEDIA` go, and
`GameFs` reduces to directories, path→size, and OPFS. `mediaTypeFor` survives
page-side only, for `<audio>` and the panel label. `music.ts` loses its
`blobAt` probe.

**Tests.** 11 blob tests in `fs.rs` and 5 in `game_api.rs` become byte
round-trips. New coverage wanted: byte-exact `Cat` → `Overwrite`, and a
0–255 round-trip through a real file.

## What it costs

**Non-ASCII text files become mojibake.** A player's UTF-8 file containing
`café` reads back as `cafÃ©`. It still round-trips byte-exactly; it displays
wrong. Exposure is small — of 306 shipped files, 2 contain non-ASCII, one
being decorative "corrupted data" noise in `website.ds` and the other a
single dash in a display string in `q.ds`. Neither is ever sliced. The real
exposure is player-written files and uploads.

**Characters above U+00FF cannot be written.** VB6 substituted lossily
through the codepage; match that.

**Three internal formats must declare their own encoding.** The mail store,
textspace and INI files are the engine's own files carrying server-sourced
UTF-8. They should encode and decode explicitly at their own boundary rather
than inheriting the byte convention. This is the fiddly part of the change,
and the one most likely to be got wrong.

## Verdict

Take option 3. It gets the whole payoff — no stored kind, no error 54, no
derived state that can drift — with no `Value` change, no audit, no
conformance risk, and it removes more code than it adds.

Leave the string representation alone. `StrB` is a solution to `*B`, and `*B`
has no users. If `*B` ever has to be fixed, the companion doc's second-arm
recommendation still stands and is independent of this.

Worth doing separately either way, and needing no deviation or representation
change: `Len` collects `encode_utf16()` into a `Vec` for a count, and
`Left`/`Mid` allocate where they could slice — 82–191 ns of waste apiece.

## What was built

The trait is 11 methods where it was 13: `raw_kind`, `raw_read_blob` and
`raw_write_blob` are gone, `raw_read`/`raw_write`/`raw_append` carry bytes,
and `raw_read_upto` is new. `NodeKind`, `BlobRef` and `FsError::NotText` are
gone with them, and so are `MemoryFs`'s `blobs` map and its refcount scan.
`bytes_to_text` and `text_to_bytes` are the whole of the convention: one
character per byte, `?` for a character that has no byte.

Where the decision went, per operation:

| Operation | Decides |
|---|---|
| `Cat`/`Display`, `Overwrite`, `Append` | nothing -- bytes, widened and narrowed |
| `Include`, `Run`, `Capture`, `DLOpen` | UTF-8, and says so when it does not get it |
| the mail store, INI files, the hash-library cache | UTF-8, through `read_text`/`write_text` |
| the editor | UTF-8 *and* a size -- a song opened in one still shows nothing |
| `<audio>` | the name, through `mediaTypeFor`, at the moment of playing |

### Four departures from the plan above

**`raw_read_upto` was added.** The plan had three content methods and no cap,
which makes `Cat` on a forty-megabyte song allocate forty megabytes in a
32-bit heap to show a screenful. `Cat` is the only caller; the default
implementation reads the lot and truncates, and the two backends that can
stop early -- `DiskFs` and the fs worker -- override it. `CAT_LIMIT` is 4 MB,
far above the 20 KB largest file the client ships, because `Cat` is how a
script reads a file and not merely how it shows one.

**`Cat` of a whole file is now byte-exact.** `select_lines` normalised line
endings and added a trailing `\r\n`, which for text nobody noticed and for
bytes would mean a file that does not survive `Cat` then `Overwrite`. Asked
for the whole file it now returns what was read, untouched; asked for a
window of lines it does what it always did. Every shipped file already ends
in `\r\n`, so nothing displays differently.

**The browser grew a shipped layer instead of losing its `Node`.** The tree
is `path` to size as planned, and contents come off disk on demand -- but the
client's own four hundred scripts are still never written out, for the two
reasons they never were: the write burst, and a disk copy that would shadow
the newer one the next build ships. So `GameFs` holds them in a `shipped` map
and reads through to it, and the first write to one of those paths hands it
over to the player and forgets the original. This is provenance, not a kind:
it says where the bytes are, never what they mean.

**`mediaTypeFor` stayed in the wasm and stayed in the worker.** The plan put
it page-side. It is only wanted to stamp a type on the `File` handed to
`<audio>`, and that `File` is made in the fs worker, so moving it would have
meant the page re-wrapping the handle for nothing. The file panel turned out
not to use the media type at all, so `Tree` and `FileChange` lost it.

Textspace was on the plan's list of internal formats; it never touched the
filesystem, so there was nothing to do.

### What it was checked against

The Rust suite, `api.vbs` and its three `KNOWN_FAILURES` unchanged, the wasm
smoke test, and the real client in Chromium over real OPFS: all 256 byte
values written from a script, read back through `Cat` as 256 characters with
0 first and 255 last, appended to, and -- across a reload, where the tree is
rebuilt from what is on disk -- still 257 bytes with `0x80` intact at
position 129. The shipped layer was checked the same way: a shipped file
reads, an append to one materialises it and outlives a reload, a delete
removes it, and the next load brings the client's copy back.
