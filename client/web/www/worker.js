// The interpreter's home.
//
// It lives in a worker because scripts block: `ReadLine` waits for the
// player and `WaitFor` waits for the server, and neither is allowed on the
// main thread. Here both are fine — a synchronous XMLHttpRequest works, and
// `Atomics.wait` lets us park until the page sends input.

import init, { Session } from "./pkg/dso_web.js";
import { FileStore } from "./storage.js";

/** Shared with the page so input can be delivered to a blocked worker. */
let control = null; // Int32Array: [state, length]
let inputBytes = null; // Uint8Array holding the encoded answer

/** Control-block states. */
const WAITING = 0;
const READY = 1;
const CLOSED = 2;

let session = null;
let store = null;

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
function readLineSync(prompt, _rgb) {
  if (!control) {
    return null;
  }
  // The prompt travels with the request so the page can set it beside the
  // caret instead of printing it as a finished line.
  postMessage({ type: "wantInput", mode: "line", prompt: prompt ?? "" });
  Atomics.store(control, 0, WAITING);
  Atomics.wait(control, 0, WAITING);

  if (Atomics.load(control, 0) === CLOSED) {
    return null;
  }
  const length = Atomics.load(control, 1);
  // `slice` and not `subarray`: the buffer is shared, and TextDecoder refuses
  // a view onto shared memory outright. A subarray is such a view, so decoding
  // one threw, the error unwound through the script, and every ReadLine ended
  // the script instead of returning a line. `slice` copies into a buffer of
  // its own, which decode accepts.
  return new TextDecoder().decode(inputBytes.slice(0, length));
}

/** Block until the page supplies a single key, returning its char code. */
function readKeySync() {
  const line = readLineSync("", -1);
  if (line === null || line.length === 0) {
    return 0;
  }
  return line.charCodeAt(0);
}

async function boot(message) {
  await init();

  control = new Int32Array(message.control);
  inputBytes = new Uint8Array(message.input);
  store = await FileStore.open();

  session = new Session(
    emit,
    readLineSync,
    readKeySync,
    (path, contents) => store.record(path, contents),
    message.width ?? 80,
  );
  if (message.apiRoot) {
    session.setApiRoot(message.apiRoot);
  }

  // The shipped scripts first, then whatever the player has saved, so an
  // edited command survives a client update.
  for (const [path, contents] of Object.entries(message.files ?? {})) {
    session.seedFile(path, contents);
  }
  const saved = await store.loadAll();
  for (const [path, contents] of Object.entries(saved)) {
    session.seedFile(path, contents);
  }

  postMessage({
    type: "ready",
    cwd: session.currentDirectory(),
    persistent: store.available,
    restored: Object.keys(saved).length,
  });
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

      case "reset":
        await store.clear();
        postMessage({ type: "wasReset" });
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
