#!/usr/bin/env node
// A development server for the browser client.
//
// It exists mainly for two headers: SharedArrayBuffer is only available to a
// cross-origin isolated page, and without it the worker cannot block waiting
// for input. Any static server will do in production as long as it sends
// these.

import { createServer } from "node:http";
import { readFile } from "node:fs/promises";
import { extname, join, normalize } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(fileURLToPath(new URL(".", import.meta.url)), "www");
const port = Number(process.env.PORT ?? 8080);

// The prefix the client is served under, matching production, where the page
// is /game/index.php and every asset it ships sits beside it. The page only
// ever addresses its own files relatively, so the prefix costs it nothing --
// but serving it here too means a path that works in development is a path
// that works deployed.
const PREFIX = "/game";

const TYPES: Record<string, string> = {
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".json": "application/json; charset=utf-8",
  ".wasm": "application/wasm",
  ".ds": "text/plain; charset=utf-8",
};

createServer(async (req, res) => {
  // Normalising first keeps a request from climbing out of the root.
  const requested = normalize(decodeURIComponent(new URL(req.url ?? "/", "http://x").pathname));

  // Anything outside the prefix goes to it, so that opening the bare host
  // lands on the game the way `/game` does on the deployed site. Bare
  // `/game` is redirected rather than served, because the page's relative
  // asset URLs resolve against the document's own address: only a trailing
  // slash makes `./main.js` mean `/game/main.js`. nginx redirects it for the
  // same reason, being a directory.
  if (!requested.startsWith(`${PREFIX}/`)) {
    res.writeHead(302, { Location: `${PREFIX}/` }).end();
    return;
  }

  const within = requested.slice(PREFIX.length);
  const path = join(root, within === "/" ? "/index.html" : within);

  if (!path.startsWith(root)) {
    res.writeHead(403).end("forbidden");
    return;
  }

  try {
    const body = await readFile(path);
    res.writeHead(200, {
      "Content-Type": TYPES[extname(path)] ?? "application/octet-stream",
      // Required for SharedArrayBuffer, and so for Atomics.wait.
      "Cross-Origin-Opener-Policy": "same-origin",
      "Cross-Origin-Embedder-Policy": "require-corp",
      "Cache-Control": "no-store",
    });
    res.end(body);
  } catch {
    res.writeHead(404).end("not found");
  }
}).listen(port, () => {
  console.log(`serving ${root} on http://localhost:${port}${PREFIX}/`);
});
