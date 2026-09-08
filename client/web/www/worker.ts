// The interpreter's home.
//
// It lives in a worker because scripts block: `ReadLine` waits for the
// player and `WaitFor` waits for the server, and neither is allowed on the
// main thread. Here both are fine — a synchronous XMLHttpRequest works, and
// `Atomics.wait` lets us park until the page sends input.

import { ABORT, CLOSED, FS_MORE, LENGTH, MORE, STATE, WAITING } from "./control.js";
import { FONT_STACK } from "./fonts.js";
import init, { Session, libraryCategories, textspaceChannels } from "./pkg/dso_web.js";
import type { Asked, ToWorker } from "./types.js";

/** Shared with the page so input can be delivered to a blocked worker. */
let control: Int32Array | null = null; // [state, length, abort]
/** The encoded answer. */
let answerBytes: Uint8Array | null = null;

let session: Session | null = null;

/**
 * The channel to the filesystem.
 *
 * There is one tree and it is not here: it belongs to the fs worker, and
 * every read and write goes down this port. The answer comes back through
 * `fsBytes` because this thread is parked on `fsControl` by then, which is
 * the only way a synchronous `Cat` can work at all.
 */
let fsPort: MessagePort | null = null;
let fsControl: Int32Array | null = null;
let fsBytes: Uint8Array | null = null;
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
  if (!control || !answerBytes) {
    return null;
  }
  // The prompt travels with the request so the page can set it beside the
  // caret instead of printing it as a finished line.
  postMessage({ type: "wantInput", mode: "line", prompt: prompt ?? "" });
  Atomics.store(control, STATE, WAITING);
  Atomics.wait(control, STATE, WAITING);

  if (Atomics.load(control, STATE) === CLOSED) {
    return null;
  }
  const length = Atomics.load(control, LENGTH);
  // `slice` and not `subarray`: the buffer is shared, and TextDecoder refuses
  // a view onto shared memory outright. A subarray is such a view, so decoding
  // one threw, the error unwound through the script, and every ReadLine ended
  // the script instead of returning a line. `slice` copies into a buffer of
  // its own, which decode accepts.
  return new TextDecoder().decode(answerBytes.slice(0, length));
}

/**
 * Ask the filesystem something, and block until it has answered.
 *
 * The request goes out on the port and this thread parks. The fs worker's
 * event loop is not the one that is stopped, so it can do the asynchronous
 * work a filesystem needs and wake this up with the result -- the same trick
 * `ReadLine` plays on the page, for the same reason.
 *
 * An answer too long for one bufferful comes back in pieces: the worker
 * says `MORE`, and this asks again until it stops saying it.
 */
function fsCall(request: string): string {
  if (!fsPort || !fsControl || !fsBytes) {
    return JSON.stringify({ err: { kind: "io", arg: "no filesystem" } });
  }
  const decoder = new TextDecoder();
  let out = "";
  let ask: string | null = request;
  for (;;) {
    Atomics.store(fsControl, STATE, WAITING);
    fsPort.postMessage(ask ?? FS_MORE);
    Atomics.wait(fsControl, STATE, WAITING);
    const state = Atomics.load(fsControl, STATE);
    if (state === CLOSED) {
      return JSON.stringify({ err: { kind: "io", arg: "the filesystem went away" } });
    }
    const length = Atomics.load(fsControl, LENGTH);
    // `slice` and not `subarray`: TextDecoder refuses a view onto shared
    // memory, and a subarray is one. See the note in `readLineSync`.
    out += decoder.decode(fsBytes.slice(0, Math.max(length, 0)), { stream: true });
    if (state !== MORE) {
      break;
    }
    ask = null;
  }
  return out + decoder.decode();
}

/**
 * Ask the filesystem something that carries contents, and block until it has
 * answered.
 *
 * The three calls that carry contents carry bytes, so this is the same trick
 * as `fsCall` with bytes on both sides of it rather than JSON: base64 round
 * a song on its way to a `Cat` is a waste of everybody's time. The answer's
 * first byte says whether the rest is the contents or the complaint, and the
 * Rust side reads that; here it is only carried through.
 *
 * A file longer than one bufferful comes back in pieces, the way a long
 * `Dir` does.
 */
const encoder = new TextEncoder();

function fsRaw(request: string, payload: Uint8Array | null): Uint8Array {
  if (!fsPort || !fsControl || !fsBytes) {
    // Framed as a failure, the way the worker frames one.
    return withTag(1, encoder.encode('{"kind":"io","arg":"no filesystem"}'));
  }
  const pieces: Uint8Array[] = [];
  let total = 0;
  let ask: { json: string; payload: Uint8Array | null } | null = { json: request, payload };
  for (;;) {
    Atomics.store(fsControl, STATE, WAITING);
    if (ask) {
      fsPort.postMessage(ask);
    } else {
      fsPort.postMessage(FS_MORE);
    }
    Atomics.wait(fsControl, STATE, WAITING);
    const state = Atomics.load(fsControl, STATE);
    if (state === CLOSED) {
      return withTag(1, encoder.encode('{"kind":"io","arg":"the filesystem went away"}'));
    }
    const length = Math.max(Atomics.load(fsControl, LENGTH), 0);
    // A copy, not a view: what the wasm is handed must not be a window onto
    // memory another thread can still write to.
    pieces.push(fsBytes.slice(0, length));
    total += length;
    if (state !== MORE) {
      break;
    }
    ask = null;
  }
  if (pieces.length === 1) {
    return pieces[0];
  }
  const out = new Uint8Array(total);
  let at = 0;
  for (const piece of pieces) {
    out.set(piece, at);
    at += piece.length;
  }
  return out;
}

/** One answer, framed the way the fs worker frames one. */
function withTag(tag: number, body: Uint8Array): Uint8Array {
  const out = new Uint8Array(body.length + 1);
  out[0] = tag;
  out.set(body, 1);
  return out;
}

/**
 * Whether the player has asked for the running script to stop.
 *
 * Read straight out of shared memory: this thread is busy running the script
 * the answer is about, so nothing it could be sent would arrive in time. The
 * interpreter asks between statements, and again after every host call, so a
 * script stuck waiting on one stops as soon as the wait is over.
 */
function stopRequested(): boolean {
  return control !== null && Atomics.load(control, ABORT) !== 0;
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
  answerBytes = new Uint8Array(message.answer);
  fsControl = new Int32Array(message.fsControl);
  fsBytes = new Uint8Array(message.fsAnswer);
  fsPort = message.fsPort;
  // Nothing is listened for on this port: every answer comes back through
  // the shared buffer, because by then this thread is parked and a message
  // could not be received anyway.
  fsPort.start();

  // The page listens to each worker separately, so this only has to reach
  // the session: it is what scripts read as `ConsoleID`.
  session = new Session(
    emit,
    readLineSync,
    readKeySync,
    stopRequested,
    fsCall,
    fsRaw,
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

  // Nothing is seeded and nothing is loaded. The tree was built once, by the
  // worker that owns it, before this console was told to start; there is no
  // copy here to fill.
  postMessage({ type: "ready", cwd: session.currentDirectory() });
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
    if (!session) {
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

      // ---- what the windows ask -----------------------------------------
      //
      // Mail and the file library are pages, but the connection lives here,
      // so each of them asks through whichever console is free. `token`
      // comes back untouched, so the page can match an answer to the window
      // that wanted it. Questions about files are not in here any more: the
      // page puts those to the fs worker, which is where the files are.
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

      case "chatFetch":
        answer(message, JSON.parse(session.chatFetch(message.last)));
        break;

      case "chatSay":
        answer(message, JSON.parse(session.chatSay(message.typed)));
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
