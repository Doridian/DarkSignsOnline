// The player's files, kept in IndexedDB.
//
// Scripts read and write synchronously, so the worker holds the whole tree
// in memory and this only has to mirror it. Writes are queued and applied in
// the background; nothing waits on them.

import type { FileChange } from "./types.js";

const DB_NAME = "darksigns";
/**
 * Version 2 added the directory store.
 *
 * Writing a file makes the directories above it, so the files alone rebuild
 * all but the empty ones -- and those went missing over a reload, which was
 * invisible until the file panel started drawing them.
 */
const DB_VERSION = 2;
const STORE = "files";
const DIRS = "dirs";

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
    };
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error);
  });
}

/** The saved tree: file contents by path, and the directories beside them. */
export interface Saved {
  files: Record<string, string>;
  dirs: string[];
}

export class FileStore {
  /**
   * Pending changes, keyed by path so a rewrite supersedes an earlier one.
   *
   * A path is either a file or a directory and cannot be both, so one queue
   * serves both stores: the change itself says which it belongs in.
   */
  queue = new Map<string, FileChange>();
  flushing = false;

  /** `db` is null when storage is unavailable. */
  constructor(readonly db: IDBDatabase | null) {}

  static async open(): Promise<FileStore> {
    try {
      return new FileStore(await open());
    } catch (err) {
      // A private window, or storage denied. The session still works; it
      // just will not survive a reload.
      console.warn("persistent storage unavailable:", err);
      return new FileStore(null);
    }
  }

  get available(): boolean {
    return this.db !== null;
  }

  /** Everything saved: the files by path, and the directories. */
  async loadAll(): Promise<Saved> {
    const db = this.db;
    if (!db) {
      return { files: {}, dirs: [] };
    }
    const files: Record<string, string> = {};
    const dirs: string[] = [];
    await Promise.all([
      this.sweep(db, STORE, (key, value) => {
        files[key] = value as string;
      }),
      this.sweep(db, DIRS, (key) => {
        dirs.push(key);
      }),
    ]);
    return { files, dirs };
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
   * Record a change.
   *
   * Returns immediately: the script that caused it is not waiting.
   */
  record(change: FileChange): void {
    if (!this.db) {
      return;
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
      // One transaction over both stores, so a burst that made a directory
      // and filled it is saved whole or not at all.
      const tx = this.db.transaction([STORE, DIRS], "readwrite");
      const files = tx.objectStore(STORE);
      const dirs = tx.objectStore(DIRS);
      for (const change of pending.values()) {
        switch (change.op) {
          case "write":
            files.put(change.contents, change.path);
            break;
          case "delete":
            files.delete(change.path);
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
    await new Promise<void>((resolve) => {
      const tx = db.transaction([STORE, DIRS], "readwrite");
      tx.objectStore(STORE).clear();
      tx.objectStore(DIRS).clear();
      tx.oncomplete = () => resolve();
      tx.onerror = () => resolve();
    });
  }
}
