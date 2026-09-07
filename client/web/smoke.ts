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

import type { ConsoleEvent } from "./www/types.js";

const here = dirname(fileURLToPath(import.meta.url));
const pkg = join(here, "www/pkg");

const { default: init, Session, parseMarkup } = await import(join(pkg, "dso_web.js"));
const { FONT_STACK } = await import(join(here, "www/fonts.js"));
await init({ module_or_path: await readFile(join(pkg, "dso_web_bg.wasm")) });

/** Collect console events the way the worker forwards them to the page. */
const events: ConsoleEvent[] = [];
const lines = () =>
  events
    .filter((e) => e.kind === "line")
    .map((e) => e.runs.map((run) => run.text).join(""));

const queuedInput = ["typed answer"];
/** Files the worker would hand to IndexedDB, and the directories beside them. */
const saved = new Map();
const savedDirs = new Set();
const session = new Session(
  (json: string) => events.push(JSON.parse(json)),
  () => (queuedInput.length ? queuedInput.shift() : null),
  () => 121, // 'y'
  // The worker's `fileChanged`: every change to the tree, files and
  // directories alike, so it can persist it and pass it to the other three.
  (kind: string, path: string, contents: string | null) => {
    switch (kind) {
      case "write":
        saved.set(path, contents);
        break;
      case "delete":
        saved.delete(path);
        break;
      case "mkdir":
        savedDirs.add(path);
        break;
      case "rmdir":
        savedDirs.delete(path);
        break;
      default:
        throw new Error(`unknown change ${kind}`);
    }
  },
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
session.seedFile("/system/commands/greet.ds", 'Say "hi, " & ArgV(1)');
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

// A script's writes are reported for saving; a seeded file is not, since
// it came from storage in the first place.
assert.equal(saved.size, 0, "seeding must not queue a save");
session.runScript('Overwrite "/home/notes.txt", "remember this"', []);
assert.equal(saved.get("/home/notes.txt"), "remember this");

session.runScript('Append "/home/notes.txt", " and this"', []);
assert.equal(
  saved.get("/home/notes.txt"),
  "remember this and this",
  "an append saves the whole file, which is simpler to replay",
);

session.runScript('Del "/home/notes.txt"', []);
assert.equal(saved.has("/home/notes.txt"), false, "a delete is persisted too");

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

// A file another console deleted is dropped without being persisted again.
session.seedFile("/home/shared.txt", "from another console");
assert.equal(session.readFile("/home/shared.txt"), "from another console");
session.forgetFile("/home/shared.txt");
assert.throws(() => session.readFile("/home/shared.txt"));
assert.equal(saved.has("/home/shared.txt"), false, "a synced change is not re-saved");

// Directories are reported as well as files, which is what carries an empty
// one to the other three consoles, to storage, and to the file tree. Nothing
// else would: a directory with no files in it is in no file's path.
assert.equal(savedDirs.size, 0, "nothing has made a directory yet");
session.runScript('MD "/home/empty"', []);
assert.ok(savedDirs.has("/home/empty"), "a new directory is reported");
session.runScript('RD "/home/empty"', []);
assert.equal(savedDirs.has("/home/empty"), false, "and so is a removed one");

// A directory another console made, taken up without being reported back.
session.seedDir("/home/elsewhere");
assert.equal(savedDirs.size, 0, "a synced directory is not re-saved");
session.forgetDir("/home/elsewhere");
assert.equal(savedDirs.size, 0);

// `listTree` is what the file tree draws: every directory, the root
// included, and every file with the size to label it by.
session.runScript('Overwrite "/home/tree.txt", "12345"', []);
session.runScript('MD "/home/hollow"', []);
const tree = JSON.parse(session.listTree());
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

// Markup parsing is available without running a script.
const runs = JSON.parse(parseMarkup("{{red bold 20}}x"));
assert.equal(runs[0].color, "#ff0000");
assert.equal(runs[0].size, 20);

console.log(`ok — ${lines().length} lines, ${events.length} events`);
