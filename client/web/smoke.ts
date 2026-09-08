#!/usr/bin/env node
// A smoke test for the built wasm module.
//
// It drives the same API the worker does, so it catches a broken build
// without needing a browser. Run it after build.sh:
//
//   node web/smoke.ts

import { readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { join, dirname } from "node:path";
import assert from "node:assert/strict";

import type { ConsoleEvent, FileChange } from "./www/types.js";

const here = dirname(fileURLToPath(import.meta.url));
const pkg = join(here, "www/pkg");

const { default: init, Session, parseMarkup } = await import(join(pkg, "dso_web.js"));
const { FONT_STACK } = await import(join(here, "www/fonts.js"));
const { GameFs, handle, handleRaw } = await import(join(here, "www/opfs.js"));
const { decode: fromBytes, encode: toBytes } = await import(join(here, "www/codepage.js"));
await init({ module_or_path: await readFile(join(pkg, "dso_web_bg.wasm")) });

/** Collect console events the way the worker forwards them to the page. */
const events: ConsoleEvent[] = [];
const lines = () =>
  events
    .filter((e) => e.kind === "line")
    .map((e) => e.runs.map((run) => run.text).join(""));

const queuedInput = ["typed answer"];


/**
 * The real filesystem, with no OPFS under it.
 *
 * Not a stub: this is the same `GameFs` the fs worker runs, driven through
 * the same request dispatcher, so what the session sees here is what it sees
 * in a browser. Node has no OPFS, so nothing is written to disk -- which is
 * exactly the degraded mode a browser without it falls back to, and worth
 * exercising for its own sake.
 */
const files = await GameFs.open();
await files.load({});

const session = new Session(
  (json: string) => events.push(JSON.parse(json)),
  () => (queuedInput.length ? queuedInput.shift() : null),
  () => 121, // 'y'
  // The worker's `fsCall`: in a browser this parks on `Atomics.wait` while
  // the fs worker answers. Here the answer is simply returned.
  (request: string) => handle(files, request),
  // The worker's `fsRaw`, for the three calls that carry contents. There is
  // no OPFS under this filesystem, so there is no disk to wait for and every
  // answer is already in hand -- which is the whole reason a session can be
  // driven from here without a worker.
  (request: string, payload: Uint8Array | null) =>
    handleRaw(files, request, payload) as Uint8Array,
  2, // the console this session is, which scripts read as ConsoleID
  FONT_STACK,
);

session.setLayout(1200, 40);

// Output, with markup turned into styled runs.
session.runScript('Say "{{green}}hello"', []);
const first = events.at(-1);
assert.equal(first?.kind, "line");
assert.equal(first.runs[0].text, "hello");
assert.equal(first.runs[0].color, "#44cf3d", "green must survive the colour swap");

// Input reaches the script. Note that this cannot catch how the worker reads
// a line in a browser: it hands the callback a plain string, where the worker
// decodes out of shared memory, and only a browser refuses that. See the note
// on `slice` in worker.js.
session.runScript('Say "you said: " & ReadLine("Name?")', []);
assert.ok(lines().includes("you said: typed answer"));

// The command line is rewritten and the command runs from the filesystem.
files.write("/system/commands/greet.ds", toBytes('Say "hi, " & ArgV(1)'));
session.runCommand("option dscript");
session.runCommand("greet world");
assert.ok(lines().includes("hi, world"), "command dispatch works");

// The two hooks a browser has to supply.
session.runScript('Say "year=" & Year(Now())', []);
const year = Number(lines().at(-1)?.slice(5));
assert.ok(year >= 2024, `Date.now() should reach the script, got ${year}`);

session.runScript(
  'Dim c : c = Encrypt("secret", "pw", True) : Say "rt=" & Decrypt(c, "pw")',
  [],
);
assert.equal(lines().at(-1), "rt=secret", "Web Crypto randomness reaches the salt");

// Script errors surface rather than killing the session.
assert.throws(() => session.runScript("Dim x : x = 1/0", []), /Division by zero/);
session.runScript('Say "still alive"', []);
assert.equal(lines().at(-1), "still alive");

// A script's writes go straight into the filesystem. There is no mirror to
// keep in step and nothing queued behind them: the session and the panel are
// reading the same tree.
const text = (path: string) => fromBytes(files.read(path) as Uint8Array);

session.runScript('Overwrite "/home/notes.txt", "remember this"', []);
assert.equal(text("/home/notes.txt"), "remember this");

session.runScript('Append "/home/notes.txt", " and this"', []);
assert.equal(text("/home/notes.txt"), "remember this and this");

session.runScript('Del "/home/notes.txt"', []);
assert.equal(files.exists("/home/notes.txt"), false, "a delete reaches the filesystem");

// The startup banner the page runs, which is the busiest thing the
// renderer has to handle: alignment, fonts, sizes, and Draw bands.
const before = events.length;
session.runScript(
  [
    'Say ""',
    'Draw -1, RGB(0, 0, 0), "solid"',
    'Say "{{center impact nobold 48 lyellow}}[{{|}}{{white impact nobold 48}} D A R K S I G N S {{|}}]{{lyellow impact nobold 48}}"',
    'Draw -1, RGB(60, 120, 60), "fadecenter"',
    'Say "It is " & Time & " on the " & Date & "."',
  ].join("\r\n"),
  [],
);
const banner = events.slice(before);
assert.ok(
  banner.some((e) => e.kind === "draw" && e.mode === "fadecenter"),
  "Draw reaches the renderer with its mode",
);
const title = banner.find((e) => e.kind === "line" && e.runs.length === 3);
assert.ok(title && title.kind === "line", "the banner's title line is there");
assert.equal(title.align, "center");
assert.equal(title.runs.map((run) => run.text).join(""), "[ D A R K S I G N S ]");
assert.ok(title.runs.every((run) => run.font === "Impact" && run.size === 48 && !run.bold));

// The console knows which of the four it is, which is what `newconsole.ds`
// prints and what a script uses to address its own console.
session.runScript('Say "id=" & ConsoleID', []);
assert.equal(lines().at(-1), "id=2");

// Measurements are pixels rather than character cells, and all three agree
// on the unit, because scripts subtract one from another. Note that Node has
// no OffscreenCanvas, so this exercises the estimate rather than the real
// measurement -- what it pins down is that a bigger font is wider, which
// counting characters got wrong.
session.runScript('Say "w=" & ConsoleWidth() & " p=" & PreSpaceWidth()', []);
assert.equal(lines().at(-1), "w=1200 p=40");

session.runScript(
  'Say "small=" & TextWidth("hello") & " big=" & TextWidth("{{48}}hello")',
  [],
);
const measured = /small=(\d+) big=(\d+)/.exec(lines().at(-1) ?? "");
assert.ok(measured, "the measurements were printed");
const [small, big] = measured.slice(1).map(Number);
assert.ok(small > 0, "a measured width is not zero");
assert.ok(big > small * 3, `48pt should dwarf 10pt, got ${small} and ${big}`);

// The markup is measured, not counted: the tag itself takes no room.
session.runScript('Say "tagged=" & TextWidth("{{red}}hello")', []);
assert.equal(
  Number(lines().at(-1)?.slice(7)),
  small,
  "a colour tag is markup, not text",
);

// There is one filesystem, so a file put into it is simply there: nothing is
// seeded into a session and nothing is synced between them. This is the whole
// point of the arrangement, so it is worth asserting outright.
files.write("/home/shared.txt", toBytes("written outside the session"));
assert.equal(
  session.readFile("/home/shared.txt"),
  "written outside the session",
  "the session reads the same tree, with no seeding",
);
files.delete("/home/shared.txt");
assert.throws(() => session.readFile("/home/shared.txt"), /not found/i);

// Directories are the filesystem's too, empty ones included -- which is what
// carries them across a reload, since no file's path implies them.
session.runScript('MD "/home/empty"', []);
assert.ok(files.isDir("/home/empty"), "a new directory is in the tree");
session.runScript('RD "/home/empty"', []);
assert.equal(files.isDir("/home/empty"), false, "and a removed one is not");

// `listTree` is what the file tree draws: every directory, the root
// included, and every file with the size to label it by.
session.runScript('Overwrite "/home/tree.txt", "12345"', []);
session.runScript('MD "/home/hollow"', []);
const tree = files.tree();
assert.ok(tree.dirs.includes("/"), "the root is a directory");
assert.ok(tree.dirs.includes("/home/hollow"), "an empty directory is still in the tree");
assert.equal(
  tree.files.find((f: { path: string }) => f.path === "/home/tree.txt")?.size,
  5,
  "a file carries its size",
);
assert.equal(
  tree.dirs.filter((d: string) => d === "/home").length,
  1,
  "no directory is listed twice",
);
assert.equal(
  tree.files.some((f: { path: string }) => tree.dirs.includes(f.path)),
  false,
  "nothing is both a file and a directory",
);

// ---- files that are not text ---------------------------------------------
//
// A song is a file in the same tree as everything else, stored the same way
// and described the same way. Nothing asks what it is: the tree holds a name
// and a size, and the bytes are touched only when something reads them.
const song = new Uint8Array([0x49, 0x44, 0x33, 0x00, 0x01, 0x7f, 0xc3]);
await files.putFile("/home/music/theme.mp3", new File([song], "theme.mp3"));

assert.deepEqual(files.read("/home/music/theme.mp3"), song, "the bytes come back");

// A song is a file like any other, all the way through.
session.runScript('Say "len=" & FileLen("/home/music/theme.mp3")', []);
assert.equal(lines().at(-1), "len=7", "the size comes from the tree, not the bytes");
session.runScript('Say "there=" & FileExists("/home/music/theme.mp3")', []);
assert.equal(lines().at(-1), "there=True");

const withMedia = files.tree();
assert.equal(
  withMedia.files.find((f: { path: string }) => f.path === "/home/music/theme.mp3")?.size,
  7,
  "the panel is told how big it is, which is all it draws",
);

// Copying a song copies it, which is what a filesystem does.
session.runScript('Copy "/home/music/theme.mp3", "/home/music/copy.mp3"', []);
assert.equal(files.len("/home/music/copy.mp3"), 7, "the copy is the same size");
assert.deepEqual(files.read("/home/music/copy.mp3"), song, "with the same bytes behind it");

// A rename moves the file rather than rewriting it, and leaves nothing
// behind at the old name.
session.runScript('Move "/home/music/copy.mp3", "/home/music/moved.mp3"', []);
assert.equal(files.exists("/home/music/copy.mp3"), false);
assert.deepEqual(files.read("/home/music/moved.mp3"), song);

// `Cat` reads any file, one character per byte, and what it gives back
// `Overwrite` puts back -- byte for byte, through the wasm and the channel.
session.runScript(
  'Overwrite "/home/music/roundtrip.mp3", Cat("/home/music/theme.mp3")',
  [],
);
assert.deepEqual(
  files.read("/home/music/roundtrip.mp3"),
  song,
  "every byte survives Cat and Overwrite",
);

// And so does every byte there is, not merely the ones this song uses.
session.runScript(
  [
    "Dim s, i",
    's = ""',
    "For i = 0 To 255",
    "  s = s & Chr(i)",
    "Next",
    'Overwrite "/home/all.bin", s',
    'Say "len=" & FileLen("/home/all.bin") & "/" & Len(Cat("/home/all.bin"))',
  ].join("\r\n"),
  [],
);
assert.equal(lines().at(-1), "len=256/256", "256 bytes out, 256 characters back");
assert.deepEqual(
  files.read("/home/all.bin"),
  new Uint8Array(Array.from({ length: 256 }, (_, i) => i)),
);

// Which character each byte is, is the code page's business, and the page
// and the engine have to agree on it or the editor shows one thing and `Cat`
// another. Byte 0x93 is the left curly quote a word processor makes -- the
// character the game's own mission text was written with.
session.runScript('Say "q=" & Chr(147) & " n=" & Asc(Chr(147))', []);
assert.equal(lines().at(-1), "q=\u201c n=147", "Chr is the code page's");
assert.equal(
  fromBytes(new Uint8Array([0x93])),
  "\u201c",
  "and the page reads the byte the same way",
);
assert.deepEqual(toBytes("\u201c"), new Uint8Array([0x93]), "and writes it back");

// What the editor opens and saves is what a script sees, which is the whole
// point: the two used to disagree, and a file with an accent in it came back
// as the mojibake its UTF-8 spelled.
session.runScript(
  'Overwrite "/home/accents.txt", "caf" & Chr(233) & Chr(151) & "th" & Chr(233)',
  [],
);
assert.equal(text("/home/accents.txt"), "caf\u00e9\u2014th\u00e9", "no mojibake either way");
assert.deepEqual(
  toBytes(text("/home/accents.txt")),
  files.read("/home/accents.txt"),
  "and the editor would save exactly what it opened",
);

// `Music` resolves its path and reaches the page as a command to act on.
session.runScript('Music "play /home/music/theme.mp3"', []);
const played = events.at(-1);
assert.equal(played?.kind, "music");
assert.equal(played.command, "play /home/music/theme.mp3");

// Markup parsing is available without running a script.
const runs = JSON.parse(parseMarkup("{{red bold 20}}x"));
assert.equal(runs[0].color, "#ff0000");
assert.equal(runs[0].size, 20);

// Every change is reported once, which is what the file panel draws from.
const reported: FileChange[] = files.drain();
assert.ok(
  reported.some((c) => c.op === "file" && c.path === "/home/music/theme.mp3"),
  "the panel is told about a song",
);
assert.ok(
  reported.some((c) => c.op === "dir" && c.path === "/home/music"),
  "and about the directory the write brought into being",
);
assert.equal(files.drain().length, 0, "and told about each of them only once");

console.log(`ok — ${lines().length} lines, ${events.length} events`);
