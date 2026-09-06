#!/usr/bin/env node
// Copy the built page into dist/, naming every asset for what is in it.
//
// The deployed client is served out of the nix store, where every file's
// mtime is the epoch. nginx builds `Last-Modified` and `ETag` out of that
// mtime, so neither says which build a file came from, and a browser given
// no `Cache-Control` guesses a freshness lifetime of a tenth of the age it
// reads off `Last-Modified` -- a tenth of fifty-six years. It stops asking.
// A cached `pkg/dso_web_bg.wasm` was still being handed to the next build's
// `pkg/dso_web.js`, which showed up as a missing export rather than as
// anything to do with caching.
//
// So each file is copied out under a name carrying the hash of its contents
// and every reference to it is rewritten to that name. A URL then names one
// file of one build: it can be cached forever, and a name from a build that
// is gone is a 404 rather than something quietly wrong.
//
// `index.html` keeps its name, being the one URL a player types, and is the
// only response that has to be revalidated. Everything it can reach is
// copied; a file nothing points at is not served, so a module that nothing
// imports -- `types.ts` compiles to an empty one -- simply does not ship.
//
// The order falls out of the references themselves: rewriting one changes a
// file's contents and so its hash, which means a file is named only once
// everything it points at has been. That requires the graph to be acyclic,
// and a cycle is reported rather than worked around.

import { createHash } from "node:crypto";
import { mkdirSync, readdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { dirname, extname, join, posix } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
/** What `build.sh` has just produced: sources, output and all. */
const src = join(here, "www");
/** What is served, and nothing else. */
const out = join(here, "dist");

/** How much of the digest a name carries. 48 bits never collide here. */
const HASH_LENGTH = 12;

/** The page, which keeps its name so that `/game/` stays one address. */
const ENTRY = "index.html";

/** The shipped game files, and the manifest this writes to name them. */
const SCRIPTS = "scripts";
const MANIFEST = `${SCRIPTS}/manifest.json`;

/** The kinds of file whose references are rewritten; the rest are bytes. */
const REWRITTEN = new Set([".css", ".html", ".js", ".json"]);

/**
 * One file's reference to another: a quoted path, which is the shape an
 * `import`, a `new Worker`, a `new URL` beside `import.meta.url`, a `fetch`
 * and a `<link href>` all have in common.
 *
 * A fresh one per call because the replacement recurses, and a global
 * regular expression carries its position between uses.
 *
 * The extensions are listed rather than matched loosely so that a game path
 * in a string -- `/system/commands/greet.ds` -- is left alone. The shipped
 * `.ds` files are reached through the manifest, which is written here.
 */
function references(): RegExp {
  return /(["'])((?:\.{0,2}\/)?[\w./-]+\.(?:css|js|json|wasm))\1/g;
}

/** Every file that may be served, by its path under `www/`. */
const shippable = new Set<string>();
/** Contents for the files this writes rather than finds. */
const generated = new Map<string, string>();
/** The name each has been given, once it has one. */
const stamped = new Map<string, string>();
/** Those part-way through, which is how a cycle is caught. */
const naming = new Set<string>();

function walk(dir: string): string[] {
  const found: string[] = [];
  for (const entry of readdirSync(join(src, dir), { withFileTypes: true })) {
    const rel = dir ? posix.join(dir, entry.name) : entry.name;
    if (entry.isDirectory()) {
      found.push(...walk(rel));
    } else {
      found.push(rel);
    }
  }
  return found;
}

function digest(content: string | Buffer): string {
  return createHash("sha256").update(content).digest("hex").slice(0, HASH_LENGTH);
}

/** `pkg/dso_web.js` and a digest become `pkg/dso_web.<digest>.js`. */
function withDigest(rel: string, hash: string): string {
  const dot = rel.lastIndexOf(".");
  return dot > rel.lastIndexOf("/")
    ? `${rel.slice(0, dot)}.${hash}${rel.slice(dot)}`
    : `${rel}.${hash}`;
}

/** How `from` has to spell `to`, keeping the leading `./` a specifier wants. */
function specifier(from: string, to: string): string {
  const rel = posix.relative(posix.dirname(from), to);
  return rel.startsWith(".") ? rel : `./${rel}`;
}

function write(rel: string, content: string | Buffer): void {
  const path = join(out, rel);
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, content);
}

/** Copy one file out under its stamped name, and return that name. */
function stamp(rel: string): string {
  const already = stamped.get(rel);
  if (already !== undefined) {
    return already;
  }
  if (naming.has(rel)) {
    throw new Error(
      `${rel} is in a reference cycle: a file cannot be named for contents that depend on its own name`,
    );
  }
  naming.add(rel);

  const source = generated.get(rel) ?? readFileSync(join(src, rel));
  let content: string | Buffer = source;
  if (REWRITTEN.has(extname(rel))) {
    content = source.toString().replace(references(), (whole, quote: string, path: string) => {
      const target = posix.normalize(posix.join(posix.dirname(rel), path));
      return shippable.has(target) ? quote + specifier(rel, stamp(target)) + quote : whole;
    });
  }

  const name = rel === ENTRY ? rel : withDigest(rel, digest(content));
  write(name, content);
  naming.delete(rel);
  stamped.set(rel, name);
  return name;
}

rmSync(out, { recursive: true, force: true });

for (const rel of walk("")) {
  // The TypeScript beside the JavaScript it compiled to, the types
  // wasm-bindgen emits with the module, and the .gitignore that hides all of
  // it from git: the page loads none of them.
  if (rel.endsWith(".ts") || rel.endsWith(".map") || rel.endsWith(".gitignore")) {
    continue;
  }
  shippable.add(rel);
}

// The manifest maps each shipped file's place in the game's filesystem --
// which is the name it is seeded under, and cannot carry a hash -- to the URL
// it is served at, which must. Written here because only this knows the URLs.
const manifest: Record<string, string> = {};
for (const rel of [...shippable].filter((r) => r.startsWith(`${SCRIPTS}/`)).sort()) {
  manifest[rel.slice(SCRIPTS.length)] = `./${stamp(rel)}`;
}
generated.set(MANIFEST, JSON.stringify(manifest));
shippable.add(MANIFEST);

stamp(ENTRY);

const unreached = [...shippable].filter((rel) => !stamped.has(rel));
console.log(
  `stamped ${stamped.size} files into ${out}` +
    (unreached.length ? `, leaving out ${unreached.join(", ")}, which nothing loads` : ""),
);
