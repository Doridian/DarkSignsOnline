//! A filesystem that survives a reload.
//!
//! Scripts call the filesystem synchronously and IndexedDB is asynchronous,
//! so the two are bridged by keeping the whole tree in memory and writing
//! changes out behind the script's back. The files are small text scripts,
//! so holding all of them costs little.
//!
//! Loading happens once at startup, before any script runs: the worker reads
//! IndexedDB and seeds the session, so a read never has to wait.
//!
//! A player's music and pictures are the exception, and are why the tree
//! separates a file's name from its contents. Holding a few albums in memory
//! in each of the four sessions is not on, so the tree keeps only what it
//! can answer `Dir` and `FileLen` from -- a name, a size, a type -- and the
//! bytes stay in the origin private filesystem. Nothing has to become
//! asynchronous for that: OPFS hands out synchronous access handles inside a
//! worker, which is where this runs.

use wasm_bindgen::prelude::*;

use vbscript::game::fs::{BlobRef, DirEntry, FileSystem, FsError, FsResult, MemoryFs, NodeKind};

/// A [`MemoryFs`] that reports every change so the worker can persist it.
pub struct PersistentFs {
    memory: MemoryFs,
    /// Called as `(kind, path, detail)`. `kind` is one of `write`, `blob`,
    /// `delete`, `mkdir` or `rmdir`. `detail` is the file's text for a
    /// write, an `{ id, size, mediaType }` object for a blob, and null for
    /// the rest.
    ///
    /// Directories are reported as well as files because the four consoles
    /// share one tree: an `MD` typed at one of them has to reach the other
    /// three and the file tree beside them, and an empty directory is not
    /// implied by any file that would otherwise carry it.
    on_change: js_sys::Function,
    /// Called as `(id)` and answering with a `Uint8Array`, or null when the
    /// bytes are gone. This is the one place the engine reaches outside its
    /// own tree, and it is synchronous because a script asking to `Cat` a
    /// song is not in a position to wait.
    read_blob: js_sys::Function,
    /// Set while the saved tree is being loaded, so replaying it does not
    /// write every file straight back out again.
    loading: bool,
}

impl PersistentFs {
    pub fn new(on_change: js_sys::Function, read_blob: js_sys::Function) -> PersistentFs {
        PersistentFs { memory: MemoryFs::new(), on_change, read_blob, loading: false }
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

    /// Take up a blob the saved tree or another console has, without
    /// reporting it back. Only the name and the description of the bytes
    /// travel; the bytes themselves are already in OPFS, which every session
    /// shares.
    pub fn seed_blob(&mut self, path: &str, blob: BlobRef) -> FsResult<()> {
        self.loading = true;
        let result = self.memory.write_blob(path, blob);
        self.loading = false;
        result
    }

    /// Take up a directory another console made, without reporting it back.
    pub fn seed_make_dir(&mut self, path: &str) -> FsResult<()> {
        self.loading = true;
        let result = self.memory.make_dir(path);
        self.loading = false;
        result
    }

    /// Drop a directory another console removed, without reporting it back.
    pub fn seed_remove_dir(&mut self, path: &str) -> FsResult<()> {
        self.loading = true;
        let result = self.memory.remove_dir(path);
        self.loading = false;
        result
    }

    fn changed(&self, kind: &str, path: &str, detail: JsValue) {
        if self.loading {
            return;
        }
        // A failed notification means the page has gone; the in-memory copy
        // is still correct for as long as this session lasts.
        let _ = self.on_change.call3(
            &JsValue::NULL,
            &JsValue::from_str(kind),
            &JsValue::from_str(path),
            &detail,
        );
    }
}

/// A blob as the page sees it: enough to find the bytes and to know what to
/// do with them, and nothing of the bytes themselves.
fn blob_detail(blob: &BlobRef) -> JsValue {
    let out = js_sys::Object::new();
    let _ = js_sys::Reflect::set(&out, &"id".into(), &blob.id.as_str().into());
    let _ = js_sys::Reflect::set(&out, &"size".into(), &(blob.size as f64).into());
    let _ = js_sys::Reflect::set(&out, &"mediaType".into(), &blob.media_type.as_str().into());
    out.into()
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
        self.changed("write", path, JsValue::from_str(contents));
        Ok(())
    }

    fn raw_append(&mut self, path: &str, contents: &str) -> FsResult<()> {
        self.memory.raw_append(path, contents)?;
        // The whole file is persisted, since a partial append is harder to
        // replay than a rewrite.
        let full = self.memory.raw_read(path)?;
        self.changed("write", path, JsValue::from_str(&full));
        Ok(())
    }

    fn raw_len(&self, path: &str) -> FsResult<i64> {
        self.memory.raw_len(path)
    }

    fn raw_delete(&mut self, path: &str) -> FsResult<()> {
        self.memory.raw_delete(path)?;
        self.changed("delete", path, JsValue::NULL);
        Ok(())
    }

    fn raw_read_dir(&self, path: &str) -> FsResult<Vec<DirEntry>> {
        self.memory.raw_read_dir(path)
    }

    fn raw_make_dir(&mut self, path: &str) -> FsResult<()> {
        self.memory.raw_make_dir(path)?;
        self.changed("mkdir", path, JsValue::NULL);
        Ok(())
    }

    fn raw_remove_dir(&mut self, path: &str) -> FsResult<()> {
        self.memory.raw_remove_dir(path)?;
        self.changed("rmdir", path, JsValue::NULL);
        Ok(())
    }

    fn raw_kind(&self, path: &str) -> FsResult<NodeKind> {
        self.memory.raw_kind(path)
    }

    fn raw_read_blob(&self, path: &str) -> FsResult<Vec<u8>> {
        let NodeKind::Blob(blob) = self.memory.raw_kind(path)? else {
            // Text is held in the tree like it always was; only blobs have
            // their bytes somewhere this has to go and ask for them.
            return self.memory.raw_read_blob(path);
        };
        let answer = self
            .read_blob
            .call1(&JsValue::NULL, &JsValue::from_str(&blob.id))
            .map_err(|_| FsError::Io(format!("Could not read {path}")))?;
        if answer.is_null() || answer.is_undefined() {
            return Err(FsError::Io(format!("Missing blob {} for {path}", blob.id)));
        }
        Ok(js_sys::Uint8Array::new(&answer).to_vec())
    }

    fn raw_write_blob(&mut self, path: &str, blob: BlobRef) -> FsResult<()> {
        let detail = blob_detail(&blob);
        self.memory.raw_write_blob(path, blob)?;
        self.changed("blob", path, detail);
        Ok(())
    }
}
