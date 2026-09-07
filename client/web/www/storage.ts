// The player's files: the tree in IndexedDB, the bytes beside it in OPFS.
//
// Scripts read and write synchronously, so the worker holds the whole tree
// in memory and this only has to mirror it. Writes are queued and applied in
// the background; nothing waits on them.
//
// A song or a picture cannot go in that tree -- four sessions each holding
// an album is not on -- so the tree keeps only what it can answer `Dir` and
// `FileLen` from, and the bytes go in the origin private filesystem under an
// id. That split is why there are two stores here rather than one: IndexedDB
// batches many small metadata writes into a transaction, which is what a
// burst of script activity is, while OPFS hands out real files, which is
// what an `<audio>` element wants to stream.

import type { BlobRef, FileChange } from "./types.js";

const DB_NAME = "darksigns";
/**
 * Version 2 added the directory store.
 *
 * Writing a file makes the directories above it, so the files alone rebuild
 * all but the empty ones -- and those went missing over a reload, which was
 * invisible until the file panel started drawing them.
 *
 * Version 3 added the blob store: the paths whose contents are bytes in
 * OPFS rather than text in here.
 */
const DB_VERSION = 3;
const STORE = "files";
const DIRS = "dirs";
const BLOBS = "blobs";

/** The OPFS directory holding blob bytes, one file per id. */
const BLOB_DIR = "blobs";

/** Open the database, creating the stores on first use. */
function open(): Promise<IDBDatabase> {
  return new Promise((resolve, reject) => {
    const request = indexedDB.open(DB_NAME, DB_VERSION);
    request.onupgradeneeded = () => {
      const db = request.result;
      if (!db.objectStoreNames.contains(STORE)) {
        // Keyed by path, so a write replaces whatever was there.
        db.createObjectStore(STORE);
      }
      // Added in version 2. A database that predates it simply has no empty
      // directories saved, which is what it had before as well.
      if (!db.objectStoreNames.contains(DIRS)) {
        db.createObjectStore(DIRS);
      }
      // Added in version 3, and empty for a player who has added no media.
      if (!db.objectStoreNames.contains(BLOBS)) {
        db.createObjectStore(BLOBS);
      }
    };
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error);
  });
}

/** A fresh id for a set of bytes, which is all an id has to be. */
export function newBlobId(): string {
  return crypto.randomUUID();
}

/**
 * The bytes behind the tree's blobs, in the origin private filesystem.
 *
 * Kept apart from [`FileStore`] because both sides of the client need it and
 * for different reasons. A worker reads bytes here when a script asks to see
 * a file it cannot hold; the page writes them when a player adds one, and
 * reads them to hand `<audio>` something to stream. The tree itself is the
 * worker's business alone.
 */
export class BlobStore {
  /** Null where OPFS is not available, which leaves media unsupported. */
  constructor(readonly dir: FileSystemDirectoryHandle | null) {}

  static async open(): Promise<BlobStore> {
    try {
      const root = await navigator.storage.getDirectory();
      return new BlobStore(await root.getDirectoryHandle(BLOB_DIR, { create: true }));
    } catch (err) {
      // Older Safari, or storage denied. The tree still works; a player just
      // cannot keep media in it.
      console.warn("media storage unavailable:", err);
      return new BlobStore(null);
    }
  }

  /** Whether stored media can be read back at all. */
  get available(): boolean {
    return this.dir !== null;
  }

  /**
   * Whether new media can be added.
   *
   * Not the same question as `available`, and not answerable from it: Safari
   * could hand out an OPFS directory for several versions before it could
   * write to one from a page, so a browser can be perfectly able to play
   * what is already stored and unable to take any more. Reporting that as
   * "no media" would be wrong, and letting the drop fail on its own would
   * be worse.
   */
  get writable(): boolean {
    return (
      this.dir !== null &&
      typeof FileSystemFileHandle !== "undefined" &&
      "createWritable" in FileSystemFileHandle.prototype
    );
  }

  /**
   * Put bytes in the store under `id`.
   *
   * The source is streamed in rather than read into memory first, which is
   * most of the point of keeping it here: a player adding a hundred
   * megabytes of music never has a hundred megabytes in the heap.
   */
  async put(id: string, data: Blob): Promise<void> {
    if (!this.dir || !this.writable) {
      throw new Error("this browser cannot keep media files");
    }
    const handle = await this.dir.getFileHandle(id, { create: true });
    const writable = await handle.createWritable();
    try {
      await writable.write(data);
    } finally {
      await writable.close();
    }
  }

  /**
   * The bytes as a `File`.
   *
   * A `File` is what `<audio>` and `<img>` want: an object URL over one of
   * these streams off disk and can be seeked into, so playing a song never
   * pulls the whole song into memory.
   */
  async file(id: string): Promise<File | null> {
    if (!this.dir) {
      return null;
    }
    try {
      return await (await this.dir.getFileHandle(id)).getFile();
    } catch {
      return null;
    }
  }

  /** The first `max` bytes, for a console that asked to read the file. */
  async bytes(id: string, max: number): Promise<Uint8Array | null> {
    const file = await this.file(id);
    return file ? new Uint8Array(await file.slice(0, max).arrayBuffer()) : null;
  }

  async remove(id: string): Promise<void> {
    try {
      await this.dir?.removeEntry(id);
    } catch {
      // Already gone, which is the state this was aiming at.
    }
  }

  /** Drop every set of bytes, for a reset. */
  async clear(): Promise<void> {
    if (!this.dir) {
      return;
    }
    try {
      for await (const name of this.dir.keys()) {
        await this.dir.removeEntry(name);
      }
    } catch (err) {
      console.warn("could not clear media files:", err);
    }
  }
}

/** The saved tree: file contents by path, the blobs, and the directories. */
export interface Saved {
  files: Record<string, string>;
  blobs: Record<string, BlobRef>;
  dirs: string[];
}

export class FileStore {
  /**
   * Pending changes, keyed by path so a rewrite supersedes an earlier one.
   *
   * A path is a file, a blob or a directory and cannot be two of them, so
   * one queue serves all three stores: the change itself says which it
   * belongs in.
   */
  queue = new Map<string, FileChange>();
  flushing = false;

  /**
   * Every blob the tree names, by path.
   *
   * Kept so that deleting a path can tell whether its bytes are still
   * wanted: a copy is a second name for one id, and dropping one name must
   * not take the bytes the other still reaches.
   */
  inodes = new Map<string, BlobRef>();

  /** `db` is null when storage is unavailable. */
  constructor(
    readonly db: IDBDatabase | null,
    readonly blobs: BlobStore,
  ) {}

  static async open(): Promise<FileStore> {
    let db: IDBDatabase | null = null;
    try {
      db = await open();
    } catch (err) {
      // A private window, or storage denied. The session still works; it
      // just will not survive a reload.
      console.warn("persistent storage unavailable:", err);
    }
    return new FileStore(db, await BlobStore.open());
  }

  get available(): boolean {
    return this.db !== null;
  }

  /** Whether media can be kept at all, which the file panel says out loud. */
  get mediaAvailable(): boolean {
    return this.db !== null && this.blobs.available;
  }

  /** Everything saved: the files by path, the blobs, and the directories. */
  async loadAll(): Promise<Saved> {
    const db = this.db;
    if (!db) {
      return { files: {}, blobs: {}, dirs: [] };
    }
    const files: Record<string, string> = {};
    const blobs: Record<string, BlobRef> = {};
    const dirs: string[] = [];
    await Promise.all([
      this.sweep(db, STORE, (key, value) => {
        files[key] = value as string;
      }),
      this.sweep(db, BLOBS, (key, value) => {
        blobs[key] = value as BlobRef;
      }),
      this.sweep(db, DIRS, (key) => {
        dirs.push(key);
      }),
    ]);
    this.inodes = new Map(Object.entries(blobs));
    return { files, blobs, dirs };
  }

  /** Walk one store, handing every row to `take`. */
  sweep(
    db: IDBDatabase,
    store: string,
    take: (key: string, value: unknown) => void,
  ): Promise<void> {
    return new Promise((resolve) => {
      const cursor = db.transaction(store, "readonly").objectStore(store).openCursor();
      cursor.onsuccess = () => {
        const at = cursor.result;
        if (!at) {
          resolve();
          return;
        }
        take(String(at.key), at.value);
        at.continue();
      };
      // A store missing because the upgrade did not run is nothing saved,
      // which is what an empty sweep says.
      cursor.onerror = () => resolve();
    });
  }

  /**
   * Forget a blob's bytes once no path names them.
   *
   * Called after the tree has already dropped the name, so a copy still
   * standing is a copy this finds.
   */
  async dropBlobIfUnused(id: string): Promise<void> {
    for (const blob of this.inodes.values()) {
      if (blob.id === id) {
        return;
      }
    }
    await this.blobs.remove(id);
  }

  // ---- recording changes ---------------------------------------------------

  /**
   * Record a change.
   *
   * Returns immediately: the script that caused it is not waiting.
   */
  record(change: FileChange): void {
    if (!this.db) {
      return;
    }
    // The blob table is kept in step here rather than at flush time, since
    // it is what decides whether a delete takes the bytes with it and the
    // flush may not have run by then.
    const previous = this.inodes.get(change.path);
    if (change.op === "blob") {
      this.inodes.set(change.path, change.blob);
    } else {
      this.inodes.delete(change.path);
    }
    if (previous && previous.id !== (change.op === "blob" ? change.blob.id : null)) {
      void this.dropBlobIfUnused(previous.id);
    }

    this.queue.set(change.path, change);
    this.scheduleFlush();
  }

  scheduleFlush(): void {
    if (this.flushing) {
      return;
    }
    this.flushing = true;
    // Batch whatever a script does in one burst into a single transaction.
    queueMicrotask(() => this.flush());
  }

  flush(): void {
    const pending = this.queue;
    this.queue = new Map();
    this.flushing = false;
    if (pending.size === 0 || !this.db) {
      return;
    }

    try {
      // One transaction over all three stores, so a burst that made a
      // directory and filled it is saved whole or not at all.
      const tx = this.db.transaction([STORE, DIRS, BLOBS], "readwrite");
      const files = tx.objectStore(STORE);
      const dirs = tx.objectStore(DIRS);
      const blobs = tx.objectStore(BLOBS);
      for (const change of pending.values()) {
        switch (change.op) {
          case "write":
            // A path is text or bytes, never both, so writing text over a
            // song has to clear the row that said it was one.
            blobs.delete(change.path);
            files.put(change.contents, change.path);
            break;
          case "blob":
            files.delete(change.path);
            blobs.put(change.blob, change.path);
            break;
          case "delete":
            files.delete(change.path);
            blobs.delete(change.path);
            break;
          case "mkdir":
            // The value is not read back; the key is the whole record.
            dirs.put(1, change.path);
            break;
          case "rmdir":
            dirs.delete(change.path);
            break;
        }
      }
      tx.onerror = () => console.warn("could not save files:", tx.error);
    } catch (err) {
      console.warn("could not save files:", err);
    }
  }

  /** Forget everything, for a reset. */
  async clear(): Promise<void> {
    const db = this.db;
    if (!db) {
      return;
    }
    this.inodes = new Map();
    await new Promise<void>((resolve) => {
      const tx = db.transaction([STORE, DIRS, BLOBS], "readwrite");
      tx.objectStore(STORE).clear();
      tx.objectStore(DIRS).clear();
      tx.objectStore(BLOBS).clear();
      tx.oncomplete = () => resolve();
      tx.onerror = () => resolve();
    });
    // The bytes go too: nothing names them any more.
    await this.blobs.clear();
  }
}
