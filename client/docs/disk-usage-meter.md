# A disk usage meter

A little bar in the status bar saying how full the player's disk is. This is
what the filesystem the client actually uses can tell us, three ways to draw
a meter from it, and what each of them costs.

**Not built.** Nothing below has been implemented; this is the choice written
down before making it.

## What the filesystem API offers

The player's filesystem is OPFS -- [`opfs.ts`](../web/www/opfs.ts) mirrors the
game tree straight onto it, so `/home/music/theme.mp3` is `fs/home/music/theme.mp3`
on disk. OPFS has no `statvfs`. There is no call on a directory handle, or on
a file handle, that says how much room is left; the API is names, bytes and
handles, and nothing else.

The one number the browser will give is `navigator.storage.estimate()`, which
resolves to `{usage, quota}`. Four things about it shape any meter built on
it:

- It is **origin-wide**, not per-directory. `usage` counts the wasm bundle in
  the HTTP cache, the service worker's store, `localStorage` and OPFS all
  together, so it is always larger than the game tree and moves for reasons
  that have nothing to do with the player's files.
- It is **asynchronous**, and on some engines slow enough that it is not
  something to call on every write.
- It is **deliberately imprecise**. Browsers round and pad the figure so that
  a page cannot use it to measure what it stored on another origin's behalf.
- `quota` varies enormously by engine. Chromium hands out a large fraction of
  free disk, which on a normal machine is hundreds of gigabytes; WebKit is far
  tighter, and a private window tighter again. So the same bar is a flat line
  on one browser and a real gauge on another.

The other number is ours already, and it is exact. `GameFs.nodes` in
[`opfs.ts`](../web/www/opfs.ts) is every file against its size in bytes, and
the panel mirrors it -- `FileTree.files` in
[`filetree.ts`](../web/www/filetree.ts) is kept in step by the `FileChange`
stream the fs worker emits, which is why the panel never polls. Summing it is
free and needs no new plumbing.

Two wrinkles in that number:

- `nodes` includes the **shipped** files. Those are the client's own scripts,
  held in `GameFs.shipped` and refetched every load; there are around three
  hundred of them, about 1.5 MB, and *none of it is on disk*. A meter counting
  them shows 1.5 MB used on a filesystem that is empty. The player's real
  bytes are `nodes` minus `shipped` -- a distinction that exists only in the
  worker, since neither `Tree` nor `FileChange` in
  [`types.ts`](../web/www/types.ts) carries it.
- Where there is no OPFS at all, everything lives in `GameFs.loose` and dies
  with the tab. There is no disk to be full of.

Worth noting alongside: running out of quota is not the only way a player
loses files. Without `navigator.storage.persist()` the whole origin is
evictable under pressure. A meter says nothing about that, and it is the more
likely way the tree disappears.

## Three ways to draw it

### 1. The real quota

Numerator `estimate().usage`, denominator `estimate().quota`.

Honest: it fills exactly as the browser fills, and goes red precisely when the
next write is about to be refused. It is also the only version that would have
warned about the thing [`filetree.ts`](../web/www/filetree.ts)'s `MAX_UPLOAD`
comment worries about.

Against it: on Chromium it reads a fraction of a percent forever and never
moves, which is not a gauge, it is a decoration. And the number it shows is
not the player's files -- it is the wasm bundle plus the player's files, so
`14 MB used` on an empty tree needs explaining.

### 2. A fictional drive

Pick a capacity in the game's fiction -- 64 MB, say -- and fill it with the
player's own bytes, shipped scripts excluded.

This is the cute one. It always moves, the numbers are small enough to read at
a glance, and the fiction is already there: the BBS in
[`npbbs.ds`](../user/darksigns/mission_scripts/npbbs.ds) has a whole thread
about disk space being tight.

Against it: it is cosmetic. A bar that reads FULL while writes keep succeeding
is a lie, and making writes fail at 100% is a gameplay rule rather than a
widget -- it would need an `FsError`, a VB error number scripts can trap, and
a decision about what happens to a player already over the line. `MAX_UPLOAD`
(64 MB, in [`filetree.ts`](../web/www/filetree.ts)) would also have to drop
below the capacity, or one drop could fill the drive.

### 3. Real bytes, real cap, clamped scale

Numerator the player's own bytes; denominator the real quota, but the *bar's*
scale clamped to something visible -- 1 GB, say -- with the true quota in the
tooltip. Colour the bar off the real ratio, not the drawn one, so it still
turns red only when the browser is genuinely nearly full.

Every number shown is true, and the bar still moves on a machine with a
terabyte free. The cost is that the bar's scale is an arbitrary choice with no
meaning behind it, which needs a sentence of explanation in the tooltip to
avoid being quietly misleading.

### Side by side

| | reads | moves on Chromium | true | warns before a write fails |
|---|---|---|---|---|
| 1. real quota | origin usage / quota | no | yes | yes |
| 2. fictional drive | player bytes / 64 MB | yes | no | no |
| 3. clamped scale | player bytes, quota in tooltip | yes | yes | yes |

The recommendation is 3 if the meter is meant to be information, and 2 if it
is meant to be furniture. They are not really the same feature.

## What building it takes, either way

- **Counting.** Don't re-sum on every change: fold a delta into a running
  total in `FileTree.take` in [`filetree.ts`](../web/www/filetree.ts), which
  already sees every `file` and `gone` and holds the old size to subtract.
- **Excluding the shipped files.** Only the worker knows which are shipped, so
  either `Tree`/`FileChange` in [`types.ts`](../web/www/types.ts) grow a flag,
  or -- smaller -- the worker reports a `used` byte count alongside the
  changes it already drains in [`fsworker.ts`](../web/www/fsworker.ts), and
  the page never does the arithmetic at all. The second keeps the definition
  of "on disk" in the one place that knows it.
- **Calling `estimate()`.** Main thread, debounced: once at boot and then at
  most every few seconds after a write burst. Never per write.
- **The widget.** `#statusbar` in [`index.html`](../web/www/index.html), beside
  `#hint`. A `<progress>` or a `div` with `role="progressbar"`,
  `aria-valuenow` and an `aria-valuetext` that spells the bytes out, since the
  bar alone says nothing to a screen reader. It should collapse on a narrow
  screen the way `#hint` already does in
  [`style.css`](../web/www/style.css) -- or shrink to the number without the
  bar.
- **The no-OPFS session.** With no disk, the meter should say that rather than
  draw a fill: nothing being stored is a different state from nothing being
  stored *yet*.

## Open questions

- Option 2 only: what happens at 100%? Refusing writes is a gameplay change
  and needs an error number scripts can see.
- Should the meter also show whether storage is persisted, given eviction is
  the likelier way files vanish?
- Status bar, or the panel's own `.tree-status` line, which is already where
  the filesystem talks about itself?
