// The player's files, kept in IndexedDB.
//
// Scripts read and write synchronously, so the worker holds the whole tree
// in memory and this only has to mirror it. Writes are queued and applied in
// the background; nothing waits on them.

const DB_NAME = "darksigns";
const DB_VERSION = 1;
const STORE = "files";

/** Open the database, creating the store on first use. */
function open() {
  return new Promise((resolve, reject) => {
    const request = indexedDB.open(DB_NAME, DB_VERSION);
    request.onupgradeneeded = () => {
      const db = request.result;
      if (!db.objectStoreNames.contains(STORE)) {
        // Keyed by path, so a write replaces whatever was there.
        db.createObjectStore(STORE);
      }
    };
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error);
  });
}

export class FileStore {
  constructor(db) {
    this.db = db;
    /** Pending changes, keyed by path so a rewrite supersedes an earlier one. */
    this.queue = new Map();
    this.flushing = false;
  }

  static async open() {
    try {
      return new FileStore(await open());
    } catch (err) {
      // A private window, or storage denied. The session still works; it
      // just will not survive a reload.
      console.warn("persistent storage unavailable:", err);
      return new FileStore(null);
    }
  }

  get available() {
    return this.db !== null;
  }

  /** Every saved file, as a path→contents object. */
  async loadAll() {
    if (!this.db) {
      return {};
    }
    return new Promise((resolve) => {
      const files = {};
      const tx = this.db.transaction(STORE, "readonly");
      const cursor = tx.objectStore(STORE).openCursor();
      cursor.onsuccess = () => {
        const at = cursor.result;
        if (!at) {
          resolve(files);
          return;
        }
        files[at.key] = at.value;
        at.continue();
      };
      cursor.onerror = () => resolve(files);
    });
  }

  /**
   * Record a change. `contents` is null for a deletion.
   *
   * Returns immediately: the script that caused it is not waiting.
   */
  record(path, contents) {
    if (!this.db) {
      return;
    }
    this.queue.set(path, contents);
    this.scheduleFlush();
  }

  scheduleFlush() {
    if (this.flushing) {
      return;
    }
    this.flushing = true;
    // Batch whatever a script does in one burst into a single transaction.
    queueMicrotask(() => this.flush());
  }

  flush() {
    const pending = this.queue;
    this.queue = new Map();
    this.flushing = false;
    if (pending.size === 0 || !this.db) {
      return;
    }

    try {
      const tx = this.db.transaction(STORE, "readwrite");
      const store = tx.objectStore(STORE);
      for (const [path, contents] of pending) {
        if (contents === null) {
          store.delete(path);
        } else {
          store.put(contents, path);
        }
      }
      tx.onerror = () => console.warn("could not save files:", tx.error);
    } catch (err) {
      console.warn("could not save files:", err);
    }
  }

  /** Forget everything, for a reset. */
  async clear() {
    if (!this.db) {
      return;
    }
    await new Promise((resolve) => {
      const tx = this.db.transaction(STORE, "readwrite");
      tx.objectStore(STORE).clear();
      tx.oncomplete = resolve;
      tx.onerror = resolve;
    });
  }
}
