// The interpreter's home.
//
// It lives in a worker because scripts block: `ReadLine` waits for the
// player and `WaitFor` waits for the server, and neither is allowed on the
// main thread. Here both are fine — a synchronous XMLHttpRequest works, and
// `Atomics.wait` lets us park until the page sends input.

import init, { Session } from "./pkg/dso_web.js";

/** Shared with the page so input can be delivered to a blocked worker. */
let control = null; // Int32Array: [state, length]
let inputBytes = null; // Uint8Array holding the encoded answer

/** Control-block states. */
const WAITING = 0;
const READY = 1;
const CLOSED = 2;

let session = null;

/** Send one console event to the page. */
function emit(json) {
  postMessage({ type: "console", event: JSON.parse(json) });
}

/**
 * Block until the page supplies a line.
 *
 * Returns null when input has been closed, which ends the running script
 * the way closing the console does in the original client.
 */
function readLineSync(_rgb) {
  if (!control) {
    return null;
  }
  postMessage({ type: "wantInput", mode: "line" });
  Atomics.store(control, 0, WAITING);
  Atomics.wait(control, 0, WAITING);

  if (Atomics.load(control, 0) === CLOSED) {
    return null;
  }
  const length = Atomics.load(control, 1);
  return new TextDecoder().decode(inputBytes.subarray(0, length));
}

/** Block until the page supplies a single key, returning its char code. */
function readKeySync() {
  const line = readLineSync(-1);
  if (line === null || line.length === 0) {
    return 0;
  }
  return line.charCodeAt(0);
}

async function boot(message) {
  await init();

  control = new Int32Array(message.control);
  inputBytes = new Uint8Array(message.input);

  session = new Session(emit, readLineSync, readKeySync, message.width ?? 80);
  if (message.apiRoot) {
    session.setApiRoot(message.apiRoot);
  }
  for (const [path, contents] of Object.entries(message.files ?? {})) {
    session.writeFile(path, contents);
  }
  postMessage({ type: "ready", cwd: session.currentDirectory() });
}

onmessage = async (e) => {
  const message = e.data;
  try {
    switch (message.type) {
      case "boot":
        await boot(message);
        break;

      case "credentials":
        session.setCredentials(message.username, message.password);
        postMessage({ type: "credentialsSet" });
        break;

      case "command":
        // Runs to completion, blocking here as needed. The page stays
        // responsive because this is a worker.
        session.runCommand(message.line);
        postMessage({ type: "done", cwd: session.currentDirectory() });
        break;

      case "script":
        session.runScript(message.source, message.args ?? []);
        postMessage({ type: "done", cwd: session.currentDirectory() });
        break;

      case "writeFile":
        session.writeFile(message.path, message.contents);
        break;

      default:
        postMessage({ type: "error", message: `unknown message ${message.type}` });
    }
  } catch (err) {
    // A script error is normal: report it and let the page carry on.
    postMessage({
      type: "error",
      message: typeof err === "string" ? err : (err?.message ?? String(err)),
      cwd: session ? session.currentDirectory() : "/",
    });
  }
};
