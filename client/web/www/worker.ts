// The interpreter's home.
//
// It lives in a worker because scripts block: `ReadLine` waits for the
// player and `WaitFor` waits for the server, and neither is allowed on the
// main thread. Here both are fine — a synchronous XMLHttpRequest works, and
// `Atomics.wait` lets us park until the page sends input.

import { CLOSED, WAITING } from "./control.js";
import { FONT_STACK } from "./fonts.js";
import init, { Session, libraryCategories, textspaceChannels } from "./pkg/dso_web.js";
import { FileStore } from "./storage.js";
import type { Asked, ToWorker } from "./types.js";

/** Shared with the page so input can be delivered to a blocked worker. */
let control: Int32Array | null = null; // [state, length]
/** The encoded answer. */
let inputBytes: Uint8Array | null = null;

let session: Session | null = null;
let store: FileStore | null = null;
/**
 * The console's measurements, in CSS pixels.
 *
 * Held here because the page reports them as soon as it has laid the console
 * out, which is well before this worker has finished loading its wasm. The
 * latest report wins whenever the session is ready for it.
 */
let layout = { width: 960, preSpace: 40 };

/** Send one console event to the page. */
function emit(json: string): void {
  postMessage({ type: "console", event: JSON.parse(json) });
}

/** Answer a window's question, with the token it asked under. */
function answer(asked: Asked, value: unknown): void {
  postMessage({ type: "answer", token: asked.token, value });
}

/**
 * Block until the page supplies a line.
 *
 * Returns null when input has been closed, which ends the running script
 * the way closing the console does in the original client.
 */
function readLineSync(prompt: string, _rgb: number): string | null {
  if (!control || !inputBytes) {
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
function readKeySync(): number {
  const line = readLineSync("", -1);
  if (line === null || line.length === 0) {
    return 0;
  }
  return line.charCodeAt(0);
}

async function boot(message: Extract<ToWorker, { type: "boot" }>): Promise<void> {
  await init();

  control = new Int32Array(message.control);
  inputBytes = new Uint8Array(message.input);
  store = await FileStore.open();

  // The page listens to each worker separately, so this only has to reach
  // the session: it is what scripts read as `ConsoleID`.
  session = new Session(
    emit,
    readLineSync,
    readKeySync,
    fileChanged,
    message.consoleId ?? 0,
    FONT_STACK,
  );
  if (message.width !== undefined) {
    layout = { width: message.width, preSpace: message.preSpace };
  }
  session.setLayout(layout.width, layout.preSpace);
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

/**
 * A script wrote or deleted a file.
 *
 * The four consoles share one filesystem in the original client, but here
 * each has a session of its own with its own copy of the tree. Only the
 * console that made the change persists it; the page passes the change to
 * the other three so their copies agree.
 */
/** `contents` is null for a deletion. */
function fileChanged(path: string, contents: string | null): void {
  store?.record(path, contents);
  postMessage({ type: "fileChanged", path, contents });
}

onmessage = async (e: MessageEvent<ToWorker>) => {
  const message = e.data;
  try {
    if (message.type === "boot") {
      await boot(message);
      return;
    }

    // The console's measurements, which need no session: they are kept here
    // and handed to the wasm whenever it is ready. This is answered ahead of
    // the guard below because it is the one thing the page really does send
    // early -- its `ResizeObserver` fires as soon as the console has been
    // laid out, which is long before a worker has fetched and started its
    // wasm. Left to the guard, that first report became an error line on the
    // console at every load. The measurement was no loss there, since the
    // `boot` message carries one of its own, but a report that arrives early
    // is meant to be kept until the session turns up rather than rejected.
    if (message.type === "layout") {
      layout = { width: message.width, preSpace: message.preSpace };
      session?.setLayout(layout.width, layout.preSpace);
      return;
    }

    // Nothing else can be served before the wasm is up. The page does not
    // send anything else until every worker has reported `ready`, so this is
    // a guard rather than a case that happens.
    if (!session || !store) {
      throw new Error("this console is still starting up");
    }

    switch (message.type) {
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

      case "runFile": {
        // What `Start_Console` does: the console's opening script is run
        // from the filesystem like any other, so an edited one takes effect.
        let source;
        try {
          source = session.readFile(message.path);
        } catch {
          postMessage({ type: "missingFile", path: message.path });
          postMessage({ type: "done", cwd: session.currentDirectory() });
          break;
        }
        // ArgV(0) is the command, the way a script run from the prompt sees it.
        session.runScript(source, [message.path]);
        postMessage({ type: "done", cwd: session.currentDirectory() });
        break;
      }

      case "syncFile":
        // Another console's change, replayed so this session's copy of the
        // tree matches. Seeding rather than writing, so it is not persisted
        // a second time or echoed back.
        if (message.contents === null) {
          session.forgetFile(message.path);
        } else {
          session.seedFile(message.path, message.contents);
        }
        break;

      // ---- what the windows ask -----------------------------------------
      //
      // Mail, the editor and the file library are pages, but the connection
      // and the files live here, so each of them asks through whichever
      // console is free. `token` comes back untouched, so the page can match
      // an answer to the window that wanted it.
      case "mailList":
        answer(message, JSON.parse(session.mailList()));
        break;

      case "mailFetch":
        answer(message, JSON.parse(session.mailFetch()));
        break;

      case "mailMarkRead":
        answer(message, JSON.parse(session.mailMarkRead(message.id)));
        break;

      case "mailSend":
        session.mailSend(message.to, message.subject, message.body);
        answer(message, null);
        break;

      case "libraryTables":
        answer(message, {
          categories: JSON.parse(libraryCategories()),
          channels: textspaceChannels(),
        });
        break;

      case "libraryList":
        answer(message, JSON.parse(session.libraryList(message.category)));
        break;

      case "libraryDownload":
        answer(message, JSON.parse(session.libraryDownload(message.id)));
        break;

      case "libraryRemovable":
        answer(message, JSON.parse(session.libraryRemovable()));
        break;

      case "libraryRemove":
        answer(message, session.libraryRemove(message.id));
        break;

      case "libraryUpload":
        answer(
          message,
          session.libraryUpload(
            message.category,
            message.title,
            message.version,
            message.description,
            message.path,
          ),
        );
        break;

      case "textspaceLoad":
        answer(message, session.textspaceLoad(message.channel));
        break;

      case "textspaceSave":
        answer(message, session.textspaceSave(message.channel, message.text));
        break;

      case "listFiles":
        answer(message, JSON.parse(session.listFiles()));
        break;

      // The editor opens a file that need not exist yet, so a missing one
      // is an empty buffer rather than a failure.
      case "readFile": {
        const exists = session.fileExists(message.path);
        answer(message, {
          path: message.path,
          contents: exists ? session.readFile(message.path) : "",
          exists,
        });
        break;
      }

      case "writeFile":
        session.writeFile(message.path, message.contents);
        answer(message, null);
        break;

      case "reset":
        await store.clear();
        postMessage({ type: "wasReset" });
        break;

      default: {
        // Unreachable as far as the types go. A message from a page that
        // has been reloaded onto a newer build is not, so it says so rather
        // than being dropped.
        const unknown = message as { type: string };
        postMessage({
          type: "error",
          message: `unknown message ${unknown.type}`,
          cwd: session.currentDirectory(),
        });
      }
    }
  } catch (err) {
    const text = err instanceof Error ? err.message : String(err);
    // A window's failure belongs in that window, not in the console log:
    // nothing was running there.
    if ("token" in message) {
      postMessage({ type: "failed", token: message.token, message: text });
      return;
    }
    // A script error is normal: report it and let the page carry on.
    postMessage({
      type: "error",
      message: text,
      cwd: session ? session.currentDirectory() : "/",
    });
  }
};
