// The one filesystem.
//
// Four consoles share a filesystem, so somebody has to own it, and this is
// that somebody: it holds the tree, it is the only thing that touches OPFS,
// and the consoles ask it. That is why there is no syncing here. Nothing has
// to be kept in step with anything, because there is only one of it.
//
// A console asks over a `MessagePort` and then parks on `Atomics.wait`,
// which is what makes a synchronous `Cat` possible in a language that has no
// synchronous filesystem. The answer goes back through the shared buffer the
// console handed over when it attached. This worker never blocks: its event
// loop is the one doing the work.

import { CLOSED, FS_MORE, MORE, READY } from "./control.js";
import { GameFs, foldPath, handle, handleRaw, ready } from "./opfs.js";
import type { FromFs, ToFs } from "./types.js";

let fs: GameFs | null = null;

/** One console's channel: where to put an answer and how to wake it. */
interface Channel {
  control: Int32Array;
  bytes: Uint8Array;
  /** The tail of an answer too long for one bufferful. */
  pending: Uint8Array | null;
}

const channels = new Map<number, Channel>();
const encoder = new TextEncoder();

/**
 * What comes down a console's port.
 *
 * A bare string is one of the ten questions about the tree. The object form
 * is one of the three that carry contents: the same JSON, with the bytes
 * beside it rather than encoded into it.
 */
type FsRequest = string | { json: string; payload: Uint8Array | null };

/**
 * Hand one answer to a parked console.
 *
 * What does not fit is kept for the console to ask for, which it does as
 * soon as it sees `MORE`. The buffer is the console's own, so two consoles
 * asking at once never contend.
 */
function deliver(channel: Channel, payload: Uint8Array): void {
  const fits = Math.min(payload.length, channel.bytes.length);
  channel.bytes.set(payload.subarray(0, fits));
  channel.pending = fits < payload.length ? payload.subarray(fits) : null;
  Atomics.store(channel.control, 1, fits);
  Atomics.store(channel.control, 0, channel.pending ? MORE : READY);
  Atomics.notify(channel.control, 0);
}

/** Wake a console that asked for something impossible to answer. */
function refuse(channel: Channel): void {
  Atomics.store(channel.control, 1, 0);
  Atomics.store(channel.control, 0, CLOSED);
  Atomics.notify(channel.control, 0);
}

/**
 * Answer one console's question about the tree, as JSON.
 *
 * None of these awaits anything: the tree is in memory, so the answer is
 * already there and the console is unparked at once.
 */
function serve(channel: Channel, request: string): void {
  if (!fs) {
    refuse(channel);
    return;
  }

  // The tail of a previous answer, which is not a question at all.
  if (request === FS_MORE) {
    const rest = channel.pending;
    deliver(channel, rest ?? new Uint8Array(0));
    return;
  }

  deliver(channel, encoder.encode(handle(fs, request)));
  announce();
}

/**
 * Answer one console's question that carries contents.
 *
 * Contents are bytes, so these go back as bytes rather than through JSON --
 * a song does not want base64 wrapped round it on the way to a `Cat`. The
 * first byte says whether the rest is the contents or the complaint, which
 * is how a read that failed is told from a file with nothing in it.
 *
 * Only a read has to reach the disk. The console is parked either way, so it
 * waits a little longer for that one.
 */
async function serveRaw(
  channel: Channel,
  request: string,
  payload: Uint8Array | null,
): Promise<void> {
  if (!fs) {
    refuse(channel);
    return;
  }
  deliver(channel, await handleRaw(fs, request, payload));
  announce();
}

/** Tell the page what changed, so the panel can redraw without asking. */
function announce(): void {
  const changes = fs?.drain() ?? [];
  if (changes.length > 0) {
    post({ type: "changed", changes });
  }
}

function post(message: FromFs, transfer: Transferable[] = []): void {
  (postMessage as (m: unknown, t: Transferable[]) => void)(message, transfer);
}

/** Take on one console: its port to ask down, and its buffer to answer into. */
function attach(id: number, port: MessagePort, control: SharedArrayBuffer, answer: SharedArrayBuffer): void {
  const channel: Channel = {
    control: new Int32Array(control),
    bytes: new Uint8Array(answer),
    pending: null,
  };
  channels.set(id, channel);
  port.onmessage = (e: MessageEvent<FsRequest>) => {
    const message = e.data;
    if (typeof message === "string") {
      serve(channel, message);
      return;
    }
    void serveRaw(channel, message.json, message.payload);
  };
}

onmessage = async (e: MessageEvent<ToFs>) => {
  const message = e.data;
  try {
    switch (message.type) {
      case "start": {
        await ready();
        fs = await GameFs.open();
        const restored = await fs.load(message.files);
        // Ask to keep it: without this the browser may evict the whole tree
        // when it wants the space, which for this game is the save file.
        void navigator.storage?.persist?.().catch(() => false);
        fs.drain();
        post({ type: "fsReady", persistent: fs.persistent, restored });
        break;
      }

      case "attach":
        attach(message.consoleId, message.port, message.control, message.answer);
        break;

      case "ask": {
        if (!fs) {
          post({ type: "failed", token: message.token, message: "the filesystem is not up" });
          break;
        }
        const value = await answerPage(fs, message);
        post({ type: "answer", token: message.token, value: value.value }, value.transfer);
        announce();
        break;
      }
    }
  } catch (err) {
    const token = (message as { token?: number }).token;
    if (token !== undefined) {
      post({ type: "failed", token, message: String(err) });
    } else {
      console.warn("filesystem worker:", err);
    }
  }
};

/**
 * What the page asks, which is the panel, the editor and whatever is about
 * to play a song.
 *
 * These are ordinary asynchronous questions -- the page is not parked and
 * has no reason to be -- so they go by `postMessage` rather than through a
 * shared buffer.
 */
async function answerPage(
  fs: GameFs,
  message: Extract<ToFs, { type: "ask" }>,
): Promise<{ value: unknown; transfer: Transferable[] }> {
  const plain = (value: unknown) => ({ value, transfer: [] as Transferable[] });
  switch (message.ask) {
    case "listTree":
      return plain(fs.tree());
    case "listFiles":
      return plain(fs.listFiles());
    case "readFile": {
      const path = foldPath(message.path);
      return plain({
        path,
        exists: fs.exists(path),
        contents:
          fs.exists(path) && !fs.isDir(path) ? await editorText(fs, path) : "",
      });
    }
    case "writeFile":
      fs.write(foldPath(message.path), encoder.encode(message.contents));
      return plain(null);
    case "fileAt": {
      // The `File` itself, which the page turns into an object URL to play
      // or to save. It is a handle onto the bytes, not the bytes.
      const file = await fs.fileAt(foldPath(message.path));
      return plain(file);
    }
    case "putFile":
      await fs.putFile(foldPath(message.path), message.file);
      return plain(null);
    case "reset":
      await fs.clear();
      return plain(null);
  }
}

/**
 * A file as the editor can show it, or nothing.
 *
 * This is where a file is decided to be text, and it is decided here because
 * this is the operation that needs it to be: an editor shows text. A song
 * opened in one is not text and never was, and showing nothing beats showing
 * an error where a file's contents should be -- or, worse, forty megabytes
 * of mojibake, which is why anything past a size no script reaches is left
 * alone unread.
 */
const EDITOR_LIMIT = 4 * 1024 * 1024;

async function editorText(fs: GameFs, path: string): Promise<string> {
  try {
    if (fs.len(path) > EDITOR_LIMIT) return "";
    return new TextDecoder("utf-8", { fatal: true }).decode(await fs.read(path));
  } catch {
    return "";
  }
}
