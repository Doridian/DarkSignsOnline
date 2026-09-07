// The player's filesystem, which is the origin private filesystem.
//
// There is one of these, in the fs worker, and it is the whole in-game
// filesystem: a script's notes, the shipped commands, and the player's music
// are all the same tree, stored the same way. OPFS mirrors it directly --
// `/home/music/theme.mp3` is `fs/home/music/theme.mp3` on disk -- so the
// thing the game calls a filesystem and the thing the browser stores are the
// same shape, and an empty directory persists because it is a directory.
//
// Text is held in memory as well as on disk, because scripts read it
// synchronously and OPFS is asynchronous however you hold it. That is one
// copy of some small script files. Media is never held: the tree keeps a
// size and a type, which is all `Dir` and `FileLen` need, and the bytes are
// fetched only when something actually plays or reads them.
//
// The semantics here are `MemoryFs`'s, in `src/game/fs.rs`, because that is
// what every test pins and what the desktop client does. Where a comment
// says a case is refused, that is the reason.

import init, { foldPath, mediaTypeFor } from "./pkg/dso_web.js";
import type { BlobRef, Entry, FileChange, Tree } from "./types.js";

/** The OPFS directory the game tree lives under. */
const ROOT = "fs";

/** What nothing else could have been: bytes that are not text. */
const UNKNOWN_MEDIA = "application/octet-stream";

/**
 * How much of an unnamed file to read before deciding it is not text.
 *
 * A file whose name says what it is never reaches this. One whose name says
 * nothing has to be looked at, and looking at it means holding it, so past
 * this size it is taken for bytes without being read -- no script is half a
 * megabyte.
 */
const SNIFF_LIMIT = 512 * 1024;

/** One node. Text carries its contents; a blob carries only its description. */
type Node =
  | { kind: "text"; text: string }
  | { kind: "blob"; size: number; mediaType: string };

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
/** What `FileLen` reports, which is bytes rather than UTF-16 units. */
const byteLength = (text: string) => encoder.encode(text).length;

/**
 * Decide what a file is.
 *
 * The only place that decides, which matters more than it looks: a file
 * dropped in and the same file read back off disk at the next load go
 * through here alike, so the two can never disagree about what it is. They
 * did once, and the answer changed across a reload.
 *
 * A file is media when its name says so, which is what the desktop client
 * decides by and what keeps `Cat` on a song refusing in both clients. When
 * the name says nothing the bytes decide, since what is not valid UTF-8
 * cannot be text whatever it is called -- but only up to a point, because
 * deciding means holding it, and nothing worth calling a script is half a
 * megabyte.
 */
async function classify(path: string, file: File): Promise<Node> {
  const named = mediaTypeFor(path);
  if (named !== "") {
    return { kind: "blob", size: file.size, mediaType: named };
  }
  if (file.size > SNIFF_LIMIT) {
    return { kind: "blob", size: file.size, mediaType: UNKNOWN_MEDIA };
  }
  try {
    const text = new TextDecoder("utf-8", { fatal: true }).decode(await file.arrayBuffer());
    return { kind: "text", text };
  } catch {
    return { kind: "blob", size: file.size, mediaType: UNKNOWN_MEDIA };
  }
}

export class GameFs {
  /** Every file, by folded path. Directories are kept separately. */
  nodes = new Map<string, Node>();
  dirs = new Set<string>(["/"]);

  /**
   * Writes still on their way to disk.
   *
   * A chain rather than a batch: OPFS has no transaction to put a burst in,
   * so the next best thing is that the operations land in the order the
   * scripts made them. Nothing waits on this -- the script that caused a
   * write carried on the moment the tree was updated.
   */
  private chain: Promise<unknown> = Promise.resolve();

  /** What has changed since the panel was last told, oldest first. */
  changes: FileChange[] = [];

  /**
   * A blob's bytes when there is nowhere to put them.
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

  /** Wait for everything queued so far, for a reset or a test. */
  async settled(): Promise<void> {
    await this.chain;
  }

  private putBytes(path: string, data: BlobPart): void {
    if (!this.root) {
      // Text is already in the tree; only bytes would be lost, and nothing
      // calls this with bytes.
      return;
    }
    this.enqueue(async () => {
      const handle = await this.fileHandle(path, true);
      if (!handle) throw new Error(`could not open ${path}`);
      const writable = await handle.createWritable();
      try {
        await writable.write(data);
      } finally {
        await writable.close();
      }
    });
  }

  private removeFile(path: string): void {
    this.loose.delete(path);
    const [parent, name] = splitParent(path);
    this.enqueue(async () => {
      const dir = await this.dirHandle(parent, false);
      // Already gone is the state this was aiming at.
      await dir?.removeEntry(name).catch(() => {});
    });
  }

  // ---- loading ------------------------------------------------------------

  /**
   * Take up the shipped scripts, then whatever is on disk.
   *
   * The shipped ones are not written out: they are the client's, they are
   * refetched every load, and saving four hundred of them would make every
   * boot a write burst. What that means for a player is what it meant
   * before -- edit one and the edit is saved over it; delete one and it
   * comes back with the next load, because it was never the player's to
   * delete.
   */
  async load(shipped: Record<string, string>): Promise<number> {
    for (const [path, contents] of Object.entries(shipped)) {
      const folded = foldPath(path);
      this.makeParents(folded);
      this.nodes.set(folded, { kind: "text", text: contents });
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
        // Media is measured, not read: the point of keeping it out of the
        // tree is that a boot does not pull an album into memory.
        const file = await (handle as FileSystemFileHandle).getFile();
        this.nodes.set(path, await classify(path, file));
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
    const node = this.nodes.get(path);
    if (!node) return;
    this.changes.push({
      op: "file",
      path,
      size: node.kind === "text" ? byteLength(node.text) : node.size,
      mediaType: node.kind === "text" ? "" : node.mediaType,
    });
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

  // ---- what a console asks (all synchronous, all on folded paths) ---------

  exists(path: string): boolean {
    return this.nodes.has(path) || this.dirs.has(path);
  }

  isDir(path: string): boolean {
    return this.dirs.has(path);
  }

  read(path: string): string {
    if (this.dirs.has(path)) throw isADirectory(path);
    const node = this.nodes.get(path);
    if (!node) throw notFound(path);
    if (node.kind === "blob") throw new FsFail("notText", path);
    return node.text;
  }

  write(path: string, contents: string): void {
    if (this.dirs.has(path)) throw isADirectory(path);
    this.makeParents(path);
    this.makeParentDirs(path);
    // Text over a song is allowed: the file simply becomes another kind of
    // file, and the bytes it held are overwritten by the text.
    this.nodes.set(path, { kind: "text", text: contents });
    this.putBytes(path, contents);
    this.note(path);
  }

  append(path: string, contents: string): void {
    if (this.dirs.has(path)) throw isADirectory(path);
    const node = this.nodes.get(path);
    if (node && node.kind === "blob") {
      // Unlike a write this would leave a file half text and half song, so
      // it is refused rather than obeyed.
      throw new FsFail("notText", path);
    }
    this.write(path, (node?.text ?? "") + contents);
  }

  len(path: string): number {
    if (this.dirs.has(path)) throw isADirectory(path);
    const node = this.nodes.get(path);
    if (!node) throw notFound(path);
    return node.kind === "text" ? byteLength(node.text) : node.size;
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

  kind(path: string): { blob: BlobRef | null } {
    if (this.dirs.has(path)) throw isADirectory(path);
    const node = this.nodes.get(path);
    if (!node) throw notFound(path);
    if (node.kind === "text") return { blob: null };
    return { blob: { id: path, size: node.size, mediaType: node.mediaType } };
  }

  /**
   * Point a path at bytes that are already somewhere in the tree.
   *
   * This is what a `Copy` of a song comes down to. The bytes have no name of
   * their own here, so `blob.id` is the path they are at now and copying
   * means copying: the old store could alias one set of bytes under two
   * names, which was cheaper but was also not what a filesystem does.
   */
  writeBlob(path: string, blob: BlobRef): void {
    if (this.dirs.has(path)) throw isADirectory(path);
    this.makeParents(path);
    this.nodes.set(path, { kind: "blob", size: blob.size, mediaType: blob.mediaType });
    this.note(path);
    if (blob.id === path) return;
    const from = blob.id;
    if (!this.root) {
      const bytes = this.loose.get(from);
      if (bytes) this.loose.set(path, bytes);
      return;
    }
    this.makeParentDirs(path);
    this.enqueue(async () => {
      const source = await this.fileHandle(from, false);
      if (!source) throw new Error(`no bytes at ${from}`);
      const handle = await this.fileHandle(path, true);
      if (!handle) throw new Error(`could not open ${path}`);
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
   * does not rewrite it. Text is held here anyway, so only a blob has to
   * reach disk, and `move` is used where the browser has it.
   */
  rename(from: string, to: string): void {
    const node = this.nodes.get(from);
    if (!node) throw notFound(from);
    if (this.dirs.has(to)) throw isADirectory(to);
    this.makeParents(to);
    this.nodes.set(to, node);
    this.nodes.delete(from);
    this.note(to);
    this.changes.push({ op: "gone", path: from });
    if (node.kind === "text") {
      this.putBytes(to, node.text);
      this.removeFile(from);
      return;
    }
    if (!this.root) {
      const bytes = this.loose.get(from);
      this.loose.delete(from);
      if (bytes) this.loose.set(to, bytes);
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
    const files = [...this.nodes.entries()].map(([path, node]) => ({
      path,
      size: node.kind === "text" ? byteLength(node.text) : node.size,
      mediaType: node.kind === "text" ? "" : node.mediaType,
    }));
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
   * is reapplied from the tree because OPFS hands these out with an empty
   * one, which leaves `<audio>` refusing to play a file it could play.
   */
  async fileAt(path: string): Promise<File | null> {
    const node = this.nodes.get(path);
    if (!node) return null;
    if (node.kind === "text") {
      return new File([node.text], splitParent(path)[1], { type: "text/plain" });
    }
    const name = splitParent(path)[1];
    const loose = this.loose.get(path);
    if (loose) {
      return new File([loose as BlobPart], name, { type: node.mediaType });
    }
    const handle = await this.fileHandle(path, false);
    if (!handle) return null;
    const file = await handle.getFile();
    return new File([file], name, { type: node.mediaType });
  }

  /**
   * A blob's bytes where they are held here rather than on disk.
   *
   * Only ever answers where there is no OPFS. It exists because that is the
   * one case where bytes can be had without awaiting anything, which is what
   * lets the smoke test drive a session without a worker under it.
   */
  looseBytesAt(path: string): Uint8Array | null {
    return this.loose.get(path) ?? null;
  }

  /** The first `max` bytes at a path, for a console that asked to read it. */
  async bytesAt(path: string, max: number): Promise<Uint8Array | null> {
    const node = this.nodes.get(path);
    if (!node) return null;
    if (node.kind === "text") {
      return encoder.encode(node.text).slice(0, max);
    }
    const loose = this.loose.get(path);
    if (loose) {
      return loose.slice(0, max);
    }
    const handle = await this.fileHandle(path, false);
    if (!handle) return null;
    const file = await handle.getFile();
    return new Uint8Array(await file.slice(0, max).arrayBuffer());
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
    const node = await classify(path, file);
    this.makeParents(path);
    if (node.kind === "text") {
      // A script, which lives in the tree like any other text.
      this.write(path, node.text);
      return;
    }
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
    this.nodes.set(path, node);
    this.note(path);
  }

  /** Forget everything, for a reset. */
  async clear(): Promise<void> {
    this.nodes.clear();
    this.dirs = new Set(["/"]);
    this.loose.clear();
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
 * Answer one console's request, as JSON.
 *
 * Every operation but a blob read is in here, and every one of them is
 * synchronous, because the tree is in memory. Reading a blob is not, and is
 * handled by the caller: only that one has to reach the disk.
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
      case "read":
        return ok(fs.read(path));
      case "write":
        fs.write(path, String(message.contents ?? ""));
        return ok(null);
      case "append":
        fs.append(path, String(message.contents ?? ""));
        return ok(null);
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
      case "kind":
        return ok(fs.kind(path));
      case "writeBlob":
        fs.writeBlob(path, message.blob as BlobRef);
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

/** Start the wasm, which is here for `foldPath` and `mediaTypeFor`. */
export async function ready(): Promise<void> {
  await init();
}

export { foldPath };
