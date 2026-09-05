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
const session = new Session(
  (json) => events.push(JSON.parse(json)),
  () => (queuedInput.length ? queuedInput.shift() : null),
  () => 121, // 'y'
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
session.writeFile("/system/commands/greet.ds", 'Say "hi, " & ArgV(1)');
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

// Markup parsing is available without running a script.
const runs = JSON.parse(parseMarkup("{{red bold 20}}x"));
assert.equal(runs[0].color, "#ff0000");
assert.equal(runs[0].size, 20);

console.log(`ok — ${lines().length} lines, ${events.length} events`);
