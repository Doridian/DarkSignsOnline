#!/usr/bin/env node
// A smoke test for the built wasm module.
//
// It drives the same API the worker does, so it catches a broken build
// without needing a browser. Run it after build.sh:
//
//   node web/smoke.mjs

import { readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { join, dirname } from "node:path";
import assert from "node:assert/strict";

const here = dirname(fileURLToPath(import.meta.url));
const pkg = join(here, "www/pkg");

const { default: init, Session, parseMarkup } = await import(join(pkg, "dso_web.js"));
await init({ module_or_path: await readFile(join(pkg, "dso_web_bg.wasm")) });

/** Collect console events the way the worker forwards them to the page. */
const events = [];
const lines = () =>
  events
    .filter((e) => e.kind === "line")
    .map((e) => e.runs.map((r) => r.text).join(""));

const queuedInput = ["typed answer"];
/** Changes the worker would hand to IndexedDB. */
const saved = new Map();
const session = new Session(
  (json) => events.push(JSON.parse(json)),
  () => (queuedInput.length ? queuedInput.shift() : null),
  () => 121, // 'y'
  (path, contents) => (contents === null ? saved.delete(path) : saved.set(path, contents)),
  80,
);

// Output, with markup turned into styled runs.
session.runScript('Say "{{green}}hello"', []);
const first = events.at(-1);
assert.equal(first.kind, "line");
assert.equal(first.runs[0].text, "hello");
assert.equal(first.runs[0].color, "#44cf3d", "green must survive the colour swap");

// Input reaches the script.
session.runScript('Say "you said: " & ReadLine("Name?")', []);
assert.ok(lines().includes("you said: typed answer"));

// The command line is rewritten and the command runs from the filesystem.
session.seedFile("/system/commands/greet.ds", 'Say "hi, " & ArgV(1)');
session.runCommand("option dscript");
session.runCommand("greet world");
assert.ok(lines().includes("hi, world"), "command dispatch works");

// The two hooks a browser has to supply.
session.runScript('Say "year=" & Year(Now())', []);
const year = Number(lines().at(-1).slice(5));
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
assert.equal(title.align, "center");
assert.equal(title.runs.map((r) => r.text).join(""), "[ D A R K S I G N S ]");
assert.ok(title.runs.every((r) => r.font === "Impact" && r.size === 48 && !r.bold));

// Markup parsing is available without running a script.
const runs = JSON.parse(parseMarkup("{{red bold 20}}x"));
assert.equal(runs[0].color, "#ff0000");
assert.equal(runs[0].size, 20);

console.log(`ok — ${lines().length} lines, ${events.length} events`);
