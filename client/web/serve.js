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

const TYPES = {
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".json": "application/json; charset=utf-8",
  ".wasm": "application/wasm",
  ".ds": "text/plain; charset=utf-8",
};

createServer(async (req, res) => {
  // Normalising first keeps a request from climbing out of the root.
  const requested = normalize(decodeURIComponent(new URL(req.url, "http://x").pathname));
  const path = join(root, requested === "/" ? "/index.html" : requested);

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
  console.log(`serving ${root} on http://localhost:${port}`);
});
