// The player's filesystem, which is the origin private filesystem.
//
// There is one of these, in the fs worker, and it is the whole in-game
// filesystem: a script's notes, the shipped commands, and the player's music
// are all the same tree, stored the same way. OPFS mirrors it directly --
// `/home/music/theme.mp3` is `fs/home/music/theme.mp3` on disk -- so the
// thing the game calls a filesystem and the thing the browser stores are the
// same shape, and an empty directory persists because it is a directory.
//
// A file is bytes. Nothing here looks at those bytes to decide what a file
// is, because nothing here needs to know: the tree holds a name and a size,
// which is all `Dir` and `FileLen` ask for, and the bytes come off disk when
// something actually reads them. That is why a boot does not pull an album
// into memory, and why a file cannot be one thing when it is dropped in and
// another when it is read back.
//
// The semantics here are `MemoryFs`'s, in `src/game/fs.rs`, because that is
// what every test pins and what the desktop client does.

import init, { foldPath, mediaTypeFor } from "./pkg/dso_web.js";
import type { Entry, FileChange, Tree } from "./types.js";

/** The OPFS directory the game tree lives under. */
const ROOT = "fs";

/**
 * A failure named the way `FsError` names it.
 *
 * The name travels down the channel and is turned back into the same variant
 * on the Rust side, so the error number a script sees does not depend on
 * which side of the channel noticed the problem.
 */
export class FsFail extends Error {
  constructor(
    readonly kind: string,
    readonly arg: string,
  ) {
    super(`${kind}: ${arg}`);
  }
}

const notFound = (p: string) => new FsFail("notFound", p);
const isADirectory = (p: string) => new FsFail("isADirectory", p);
const notADirectory = (p: string) => new FsFail("notADirectory", p);

/** `/home/x.txt` -> `["/home", "x.txt"]`, matching `split_parent`. */
function splitParent(path: string): [string, string] {
  const at = path.lastIndexOf("/");
  if (at < 0) return ["", path];
  if (at === 0) return ["/", path.slice(1)];
  return [path.slice(0, at), path.slice(at + 1)];
}

/** The segments of a path, with the empties collapsed. */
function parts(path: string): string[] {
  return path.split("/").filter((p) => p !== "");
}

const encoder = new TextEncoder();

function concat(a: Uint8Array, b: Uint8Array): Uint8Array {
  const out = new Uint8Array(a.length + b.length);
  out.set(a);
  out.set(b, a.length);
  return out;
}

export class GameFs {
  /** Every file, by folded path, and how many bytes it holds. */
  nodes = new Map<string, number>();
  dirs = new Set<string>(["/"]);

  /**
   * Writes still on their way to disk.
   *
   * A chain rather than a batch: OPFS has no transaction to put a burst in,
   * so the next best thing is that the operations land in the order the
   * scripts made them. A read waits for it, which is what makes a write and
   * the read after it agree; nothing else does -- the script that caused a
   * write carried on the moment the tree was updated.
   */
  private chain: Promise<unknown> = Promise.resolve();

  /** What has changed since the panel was last told, oldest first. */
  changes: FileChange[] = [];

  /**
   * The client's own files, which are not the player's to keep.
   *
   * They are refetched every load and never written out: saving four hundred
   * of them would make every boot a write burst, and a copy on disk would
   * shadow the newer one the client ships next time. So they sit here and
   * are read from here, until something writes over one -- at which point
   * the write is the player's, goes to disk like any other, and this forgets
   * the original. Delete one and it is gone until the next load brings it
   * back, because it was never the player's to delete.
   */
  private shipped = new Map<string, Uint8Array>();

  /**
   * File contents where there is nowhere to put them.
   *
   * Only used where the browser has no OPFS. The session still works and
   * still plays what the player drops into it; none of it outlives the tab,
   * which is the same bargain the rest of the tree makes there.
   */
  private loose = new Map<string, Uint8Array>();

  /** Null where the browser has no OPFS, which leaves nothing to save to. */
  constructor(private readonly root: FileSystemDirectoryHandle | null) {}

  static async open(): Promise<GameFs> {
    try {
      const opfs = await navigator.storage.getDirectory();
      return new GameFs(await opfs.getDirectoryHandle(ROOT, { create: true }));
    } catch (err) {
      // No OPFS, or storage denied. The game still runs; this session just
      // will not outlive the tab.
      console.warn("no persistent filesystem:", err);
      return new GameFs(null);
    }
  }

  get persistent(): boolean {
    return this.root !== null;
  }

  // ---- reaching into OPFS -------------------------------------------------

  /** The directory handle for a game path, or null when it is not there. */
  private async dirHandle(
    path: string,
    create: boolean,
  ): Promise<FileSystemDirectoryHandle | null> {
    let at = this.root;
    if (!at) return null;
    for (const part of parts(path)) {
      try {
        at = await at.getDirectoryHandle(part, { create });
      } catch {
        return null;
      }
    }
    return at;
  }

  /** The file handle for a game path, making the directories above it. */
  private async fileHandle(
    path: string,
    create: boolean,
  ): Promise<FileSystemFileHandle | null> {
    const [parent, name] = splitParent(path);
    const dir = await this.dirHandle(parent, create);
    if (!dir || name === "") return null;
    try {
      return await dir.getFileHandle(name, { create });
    } catch {
      return null;
    }
  }

  /** Queue one change to disk, in order, and never let it throw upward. */
  private enqueue(work: () => Promise<unknown>): void {
    if (!this.root) return;
    this.chain = this.chain.then(work).catch((err) => {
      console.warn("could not save a change:", err);
    });
  }

  /** Wait for everything queued so far, for a read, a reset or a test. */
  async settled(): Promise<void> {
    await this.chain;
  }

  /**
   * Put bytes at a path, wherever this filesystem keeps them.
   *
   * The path stops being the client's the moment anything writes to it: a
   * shipped file that has been written over is the player's file now.
   */
  private store(path: string, bytes: Uint8Array): void {
    this.shipped.delete(path);
    if (!this.root) {
      this.loose.set(path, bytes);
      return;
    }
    this.enqueue(async () => {
      const handle = await this.fileHandle(path, true);
      if (!handle) throw new Error(`could not open ${path}`);
      const writable = await handle.createWritable();
      try {
        await writable.write(bytes as BlobPart);
      } finally {
        await writable.close();
      }
    });
  }

  private removeFile(path: string): void {
    this.loose.delete(path);
    this.shipped.delete(path);
    const [parent, name] = splitParent(path);
    this.enqueue(async () => {
      const dir = await this.dirHandle(parent, false);
      // Already gone is the state this was aiming at.
      await dir?.removeEntry(name).catch(() => {});
    });
  }

  // ---- loading ------------------------------------------------------------

  /** Take up the shipped scripts, then whatever is on disk. */
  async load(shipped: Record<string, Uint8Array>): Promise<number> {
    for (const [path, bytes] of Object.entries(shipped)) {
      const folded = foldPath(path);
      this.makeParents(folded);
      this.shipped.set(folded, bytes);
      this.nodes.set(folded, bytes.length);
    }
    if (!this.root) return 0;
    let restored = 0;
    const walk = async (dir: FileSystemDirectoryHandle, at: string): Promise<void> => {
      for await (const [name, handle] of dir.entries()) {
        const path = at === "/" ? `/${name}` : `${at}/${name}`;
        if (handle.kind === "directory") {
          this.dirs.add(path);
          await walk(handle as FileSystemDirectoryHandle, path);
          continue;
        }
        // Measured, never read: what the tree wants is a size, and a boot
        // that read every file would be a boot that read the album.
        const file = await (handle as FileSystemFileHandle).getFile();
        // The player's copy of a shipped file wins, and stops being shipped.
        this.shipped.delete(path);
        this.nodes.set(path, file.size);
        this.makeParents(path);
        restored += 1;
      }
    };
    try {
      await walk(this.root, "/");
    } catch (err) {
      console.warn("could not read the saved filesystem:", err);
    }
    return restored;
  }

  /** Report a file as it now stands. */
  private note(path: string): void {
    const size = this.nodes.get(path);
    if (size === undefined) return;
    this.changes.push({ op: "file", path, size });
  }

  /** Everything the panel has not been told yet. */
  drain(): FileChange[] {
    const out = this.changes;
    this.changes = [];
    return out;
  }

  /** Record the directories above a path, as `create_parents` does. */
  private makeParents(path: string): void {
    const [parent] = splitParent(path);
    let current = "";
    this.dirs.add("/");
    for (const part of parts(parent)) {
      current += `/${part}`;
      // Reported as well as recorded: a directory a write brought into
      // being is one the panel has to draw, and nothing else would say so.
      if (!this.dirs.has(current)) {
        this.dirs.add(current);
        this.changes.push({ op: "dir", path: current });
      }
    }
  }

  // ---- what a console asks (all on folded paths) --------------------------
  //
  // Everything about the tree is answered at once, because the tree is in
  // memory. Only the contents have to be waited for, and only where there is
  // a disk to wait for.

  exists(path: string): boolean {
    return this.nodes.has(path) || this.dirs.has(path);
  }

  isDir(path: string): boolean {
    return this.dirs.has(path);
  }

  /**
   * A file's bytes.
   *
   * Queued writes are waited for first, so a script that writes a file and
   * reads it back reads what it wrote rather than what was on disk before.
   */
  read(path: string, max = Infinity): Uint8Array | Promise<Uint8Array> {
    if (this.dirs.has(path)) throw isADirectory(path);
    if (!this.nodes.has(path)) throw notFound(path);
    const held = this.loose.get(path) ?? this.shipped.get(path);
    if (held) return held.slice(0, max);
    // The tree knows the file is there; whoever holds the bytes has lost
    // them, which is worth saying differently.
    if (!this.root) throw new FsFail("io", `Missing contents for ${path}`);
    return (async () => {
      await this.settled();
      const handle = await this.fileHandle(path, false);
      if (!handle) throw new FsFail("io", `Missing contents for ${path}`);
      const file = await handle.getFile();
      const wanted = Math.min(max, file.size);
      return new Uint8Array(await file.slice(0, wanted).arrayBuffer());
    })();
  }

  write(path: string, contents: Uint8Array): void {
    if (this.dirs.has(path)) throw isADirectory(path);
    this.makeParents(path);
    this.makeParentDirs(path);
    this.nodes.set(path, contents.length);
    this.store(path, contents);
    this.note(path);
  }

  /**
   * Add to the end of a file, without reading the rest of it.
   *
   * The tree already knows how long the file is, so on disk this is a write
   * at that offset -- appending to a forty-megabyte log costs what the line
   * costs. A file still held in memory is joined there instead.
   */
  append(path: string, contents: Uint8Array): void {
    if (this.dirs.has(path)) throw isADirectory(path);
    const held = this.loose.get(path) ?? this.shipped.get(path);
    if (held || !this.root) {
      this.write(path, concat(held ?? new Uint8Array(0), contents));
      return;
    }
    const at = this.nodes.get(path) ?? 0;
    this.makeParents(path);
    this.makeParentDirs(path);
    this.nodes.set(path, at + contents.length);
    this.note(path);
    this.enqueue(async () => {
      const handle = await this.fileHandle(path, true);
      if (!handle) throw new Error(`could not open ${path}`);
      const writable = await handle.createWritable({ keepExistingData: true });
      try {
        await writable.write({ type: "write", position: at, data: contents as BlobPart });
      } finally {
        await writable.close();
      }
    });
  }

  len(path: string): number {
    if (this.dirs.has(path)) throw isADirectory(path);
    const size = this.nodes.get(path);
    if (size === undefined) throw notFound(path);
    return size;
  }

  delete(path: string): void {
    if (!this.nodes.has(path)) throw notFound(path);
    this.nodes.delete(path);
    this.removeFile(path);
    this.changes.push({ op: "gone", path });
  }

  readDir(path: string): Entry[] {
    if (!this.dirs.has(path)) throw notADirectory(path);
    const out: Entry[] = [];
    for (const d of this.dirs) {
      if (d !== path && splitParent(d)[0] === path) {
        out.push({ name: splitParent(d)[1], isDir: true });
      }
    }
    for (const f of this.nodes.keys()) {
      if (splitParent(f)[0] === path) {
        out.push({ name: splitParent(f)[1], isDir: false });
      }
    }
    out.sort((a, b) => (a.name < b.name ? -1 : a.name > b.name ? 1 : 0));
    return out;
  }

  makeDir(path: string): void {
    if (this.exists(path)) throw new FsFail("alreadyExists", path);
    this.makeParents(path);
    this.dirs.add(path);
    this.makeParentDirs(path);
    this.changes.push({ op: "dir", path });
    this.enqueue(async () => {
      await this.dirHandle(path, true);
    });
  }

  removeDir(path: string): void {
    if (!this.dirs.has(path)) throw notADirectory(path);
    if (this.readDir(path).length > 0) throw new FsFail("notEmpty", path);
    this.dirs.delete(path);
    this.changes.push({ op: "gone", path });
    const [parent, name] = splitParent(path);
    this.enqueue(async () => {
      const dir = await this.dirHandle(parent, false);
      await dir?.removeEntry(name).catch(() => {});
    });
  }

  /** Make the directories above a path on disk, so a write has somewhere to go. */
  private makeParentDirs(path: string): void {
    const [parent] = splitParent(path);
    if (parent === "/" || parent === "") return;
    this.enqueue(async () => {
      await this.dirHandle(parent, true);
    });
  }

  /**
   * Copy a file, on disk, without its bytes passing through the engine.
   *
   * The bytes here are songs: doing this the way the trait would -- read it
   * out, hand it over, hand it back, write it -- would move forty megabytes
   * through a console to give a file a second name.
   */
  copy(from: string, to: string): void {
    if (!this.nodes.has(from)) throw notFound(from);
    if (this.dirs.has(to)) throw isADirectory(to);
    this.makeParents(to);
    this.nodes.set(to, this.nodes.get(from) ?? 0);
    this.note(to);
    const held = this.loose.get(from) ?? this.shipped.get(from);
    if (held) {
      this.store(to, held);
      return;
    }
    this.makeParentDirs(to);
    this.enqueue(async () => {
      const source = await this.fileHandle(from, false);
      if (!source) throw new Error(`no bytes at ${from}`);
      const handle = await this.fileHandle(to, true);
      if (!handle) throw new Error(`could not open ${to}`);
      const writable = await handle.createWritable();
      try {
        await writable.write(await source.getFile());
      } finally {
        await writable.close();
      }
    });
  }

  /**
   * Move a file.
   *
   * One operation rather than a copy and a delete, so that renaming a song
   * does not rewrite it: `move` is used where the browser has it.
   */
  rename(from: string, to: string): void {
    const size = this.nodes.get(from);
    if (size === undefined) throw notFound(from);
    if (this.dirs.has(to)) throw isADirectory(to);
    this.makeParents(to);
    this.nodes.set(to, size);
    this.nodes.delete(from);
    this.note(to);
    this.changes.push({ op: "gone", path: from });

    const held = this.loose.get(from) ?? this.shipped.get(from);
    if (held) {
      this.store(to, held);
      this.loose.delete(from);
      this.shipped.delete(from);
      return;
    }
    this.makeParentDirs(to);
    const [toParent, toName] = splitParent(to);
    this.enqueue(async () => {
      const source = await this.fileHandle(from, false);
      if (!source) return;
      const parent = await this.dirHandle(toParent, true);
      if (parent && typeof (source as { move?: unknown }).move === "function") {
        await (source as unknown as { move: (d: unknown, n: string) => Promise<void> })
          .move(parent, toName);
        return;
      }
      // No `move`: the bytes have to be rewritten, which is what it costs
      // on a browser that has not shipped it.
      const handle = await this.fileHandle(to, true);
      if (!handle) throw new Error(`could not open ${to}`);
      const writable = await handle.createWritable();
      try {
        await writable.write(await source.getFile());
      } finally {
        await writable.close();
      }
      const dir = await this.dirHandle(splitParent(from)[0], false);
      await dir?.removeEntry(splitParent(from)[1]).catch(() => {});
    });
  }

  // ---- what the page asks (asynchronous, because it can wait) -------------

  /** The whole tree, for the file panel to draw. */
  tree(): Tree {
    const files = [...this.nodes.entries()].map(([path, size]) => ({ path, size }));
    files.sort((a, b) => (a.path < b.path ? -1 : a.path > b.path ? 1 : 0));
    return { dirs: [...this.dirs].sort(), files };
  }

  /** Every file path, for a picker to offer. */
  listFiles(): string[] {
    return [...this.nodes.keys()].sort();
  }

  /**
   * The bytes at a path as a `File`.
   *
   * A `File` is what `<audio>` and a download want: an object URL over one
   * streams off disk rather than pulling a whole song into memory. The type
   * is the one the name implies, because OPFS hands these out with an empty
   * one and `<audio>` will not play a file it cannot pick a decoder for.
   */
  async fileAt(path: string): Promise<File | null> {
    if (!this.nodes.has(path)) return null;
    const name = splitParent(path)[1];
    const type = mediaTypeFor(path);
    const held = this.loose.get(path) ?? this.shipped.get(path);
    if (held) {
      return new File([held as BlobPart], name, { type });
    }
    if (!this.root) return null;
    await this.settled();
    const handle = await this.fileHandle(path, false);
    if (!handle) return null;
    return new File([await handle.getFile()], name, { type });
  }

  /**
   * Put a file the player dropped into the tree.
   *
   * The bytes go to disk first and the name into the tree after, so a
   * failure leaves a file nothing points at rather than a name pointing at
   * nothing -- and on the next load the walk finds those bytes and gives
   * them their name back.
   */
  async putFile(path: string, file: File): Promise<void> {
    if (this.dirs.has(path)) throw isADirectory(path);
    this.makeParents(path);
    this.shipped.delete(path);
    if (!this.root) {
      this.loose.set(path, new Uint8Array(await file.arrayBuffer()));
    } else {
      await this.dirHandle(splitParent(path)[0], true);
      const handle = await this.fileHandle(path, true);
      if (!handle) throw new FsFail("io", `could not open ${path}`);
      const writable = await handle.createWritable();
      try {
        await writable.write(file);
      } finally {
        await writable.close();
      }
    }
    this.nodes.set(path, file.size);
    this.note(path);
  }

  /** Forget everything, for a reset. */
  async clear(): Promise<void> {
    this.nodes.clear();
    this.dirs = new Set(["/"]);
    this.loose.clear();
    this.shipped.clear();
    await this.settled();
    if (!this.root) return;
    try {
      for await (const name of this.root.keys()) {
        await this.root.removeEntry(name, { recursive: true });
      }
    } catch (err) {
      console.warn("could not clear the filesystem:", err);
    }
  }
}

/**
 * Answer one console's request about the tree, as JSON.
 *
 * These are the ten calls that take a path and say nothing about contents,
 * and every one of them is answered without awaiting anything, because the
 * tree is in memory. The three that carry contents go through `handleRaw`
 * instead: JSON has no way to carry bytes that is not base64.
 *
 * Shared with the smoke test, which runs a `GameFs` with no OPFS under it
 * and drives a session through this exactly as the worker does.
 */
export function handle(fs: GameFs, request: string): string {
  const ok = (value: unknown) => JSON.stringify({ ok: value ?? null });
  let message: { op: string; [key: string]: unknown };
  try {
    message = JSON.parse(request);
  } catch {
    return JSON.stringify({ err: { kind: "io", arg: "unreadable request" } });
  }
  const path = String(message.path ?? "");
  try {
    switch (message.op) {
      case "exists":
        return ok(fs.exists(path));
      case "isDir":
        return ok(fs.isDir(path));
      case "len":
        return ok(fs.len(path));
      case "delete":
        fs.delete(path);
        return ok(null);
      case "readDir":
        return ok(fs.readDir(path));
      case "makeDir":
        fs.makeDir(path);
        return ok(null);
      case "removeDir":
        fs.removeDir(path);
        return ok(null);
      case "copy":
        fs.copy(path, String(message.to ?? ""));
        return ok(null);
      case "rename":
        fs.rename(path, String(message.to ?? ""));
        return ok(null);
      default:
        return JSON.stringify({
          err: { kind: "io", arg: `unknown filesystem request ${message.op}` },
        });
    }
  } catch (err) {
    if (err instanceof FsFail) {
      return JSON.stringify({ err: { kind: err.kind, arg: err.arg } });
    }
    return JSON.stringify({ err: { kind: "io", arg: String(err) } });
  }
}

/** An answer whose first byte says the rest is the contents. */
const RAW_OK = 0;
/** ...and one whose first byte says the rest is the complaint, as JSON. */
const RAW_ERR = 1;

function framed(tag: number, body: Uint8Array): Uint8Array {
  const out = new Uint8Array(body.length + 1);
  out[0] = tag;
  out.set(body, 1);
  return out;
}

function failure(err: unknown): Uint8Array {
  const wire =
    err instanceof FsFail
      ? { kind: err.kind, arg: err.arg }
      : { kind: "io", arg: String(err) };
  return framed(RAW_ERR, encoder.encode(JSON.stringify(wire)));
}

/**
 * Answer one console's request that carries contents.
 *
 * A read waits for the disk; a write and an append do not, because both are
 * done with the tree the moment it is updated and the disk catches up behind
 * them. So this answers at once where it can, and the caller awaits either
 * way -- which is also what lets the smoke test, where there is no disk to
 * wait for, drive it without a worker.
 */
export function handleRaw(
  fs: GameFs,
  request: string,
  payload: Uint8Array | null,
): Uint8Array | Promise<Uint8Array> {
  let message: { op: string; [key: string]: unknown };
  try {
    message = JSON.parse(request);
  } catch {
    return failure("unreadable request");
  }
  const path = String(message.path ?? "");
  const bytes = payload ?? new Uint8Array(0);
  try {
    switch (message.op) {
      case "read": {
        const max = message.max === null || message.max === undefined
          ? Infinity
          : Number(message.max);
        const answer = fs.read(path, max);
        return answer instanceof Promise
          ? answer.then((b) => framed(RAW_OK, b), failure)
          : framed(RAW_OK, answer);
      }
      case "write":
        fs.write(path, bytes);
        return framed(RAW_OK, new Uint8Array(0));
      case "append":
        fs.append(path, bytes);
        return framed(RAW_OK, new Uint8Array(0));
      default:
        return failure(`unknown filesystem request ${message.op}`);
    }
  } catch (err) {
    return failure(err);
  }
}

/** Start the wasm, which is here for `foldPath` and `mediaTypeFor`. */
export async function ready(): Promise<void> {
  await init();
}

export { foldPath };
