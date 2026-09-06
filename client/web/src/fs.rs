//! A filesystem that survives a reload.
//!
//! Scripts call the filesystem synchronously and IndexedDB is asynchronous,
//! so the two are bridged by keeping the whole tree in memory and writing
//! changes out behind the script's back. The files are small text scripts,
//! so holding all of them costs little.
//!
//! Loading happens once at startup, before any script runs: the worker reads
//! IndexedDB and seeds the session, so a read never has to wait.

use wasm_bindgen::prelude::*;

use vbscript::game::fs::{DirEntry, FileSystem, FsResult, MemoryFs};

/// A [`MemoryFs`] that reports every change so the worker can persist it.
pub struct PersistentFs {
    memory: MemoryFs,
    /// Called as `(path, contents)`, with `contents` null for a deletion.
    on_change: js_sys::Function,
    /// Set while the saved tree is being loaded, so replaying it does not
    /// write every file straight back out again.
    loading: bool,
}

impl PersistentFs {
    pub fn new(on_change: js_sys::Function) -> PersistentFs {
        PersistentFs { memory: MemoryFs::new(), on_change, loading: false }
    }

    /// Seed the tree without reporting the writes back.
    ///
    /// Used for both the shipped scripts and the saved ones; whichever is
    /// applied last wins, which is how a player's edit survives an update.
    /// The path is folded on the way in like any other, so a file saved
    /// under a mixed-case name before the tree was case-insensitive comes
    /// back under its folded one.
    pub fn seed(&mut self, path: &str, contents: &str) -> FsResult<()> {
        self.loading = true;
        let result = self.memory.write(path, contents);
        self.loading = false;
        result
    }

    /// Drop a file another console deleted, without reporting it back.
    pub fn seed_delete(&mut self, path: &str) -> FsResult<()> {
        self.loading = true;
        let result = self.memory.delete(path);
        self.loading = false;
        result
    }

    fn changed(&self, path: &str, contents: Option<&str>) {
        if self.loading {
            return;
        }
        let value = match contents {
            Some(text) => JsValue::from_str(text),
            None => JsValue::NULL,
        };
        // A failed notification means the page has gone; the in-memory copy
        // is still correct for as long as this session lasts.
        let _ = self
            .on_change
            .call2(&JsValue::NULL, &JsValue::from_str(path), &value);
    }
}

/// The paths here are already folded, so what is persisted is the folded
/// name and the other consoles are told about that one.
impl FileSystem for PersistentFs {
    fn raw_exists(&self, path: &str) -> bool {
        self.memory.raw_exists(path)
    }

    fn raw_is_dir(&self, path: &str) -> bool {
        self.memory.raw_is_dir(path)
    }

    fn raw_read(&self, path: &str) -> FsResult<String> {
        self.memory.raw_read(path)
    }

    fn raw_write(&mut self, path: &str, contents: &str) -> FsResult<()> {
        self.memory.raw_write(path, contents)?;
        self.changed(path, Some(contents));
        Ok(())
    }

    fn raw_append(&mut self, path: &str, contents: &str) -> FsResult<()> {
        self.memory.raw_append(path, contents)?;
        // The whole file is persisted, since a partial append is harder to
        // replay than a rewrite.
        let full = self.memory.raw_read(path)?;
        self.changed(path, Some(&full));
        Ok(())
    }

    fn raw_len(&self, path: &str) -> FsResult<i64> {
        self.memory.raw_len(path)
    }

    fn raw_delete(&mut self, path: &str) -> FsResult<()> {
        self.memory.raw_delete(path)?;
        self.changed(path, None);
        Ok(())
    }

    fn raw_read_dir(&self, path: &str) -> FsResult<Vec<DirEntry>> {
        self.memory.raw_read_dir(path)
    }

    fn raw_make_dir(&mut self, path: &str) -> FsResult<()> {
        self.memory.raw_make_dir(path)
    }

    fn raw_remove_dir(&mut self, path: &str) -> FsResult<()> {
        self.memory.raw_remove_dir(path)
    }
}
