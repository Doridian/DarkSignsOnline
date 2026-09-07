//! The filesystem, which lives in another worker.
//!
//! There is one filesystem and four consoles, so somebody has to own it.
//! In the browser that is the fs worker: it holds the tree and it is the
//! only thing that touches OPFS. Everything here is a shim that asks it.
//!
//! Scripts call the filesystem synchronously, and a question asked across
//! workers is not synchronous, so the answer comes back the way `ReadLine`'s
//! does: post the request, park on `Atomics.wait`, and let the worker that
//! is not blocked do the work. That costs a few microseconds a call, which
//! is the price of there being one tree rather than four copies that have to
//! be kept in step.
//!
//! Nothing is cached here on purpose. A cache would be a second copy of the
//! tree, and second copies of the tree are what this replaced.

use serde::{Deserialize, Serialize};
use wasm_bindgen::prelude::*;

use vbscript::game::fs::{BlobRef, DirEntry, FileSystem, FsError, FsResult, NodeKind};
use vbscript::game::path::fold_case;

/// One question for the fs worker. The paths in it are already folded.
#[derive(Serialize)]
#[serde(tag = "op", rename_all = "camelCase")]
enum Request<'a> {
    Exists { path: &'a str },
    IsDir { path: &'a str },
    Read { path: &'a str },
    Write { path: &'a str, contents: &'a str },
    Append { path: &'a str, contents: &'a str },
    Len { path: &'a str },
    Delete { path: &'a str },
    ReadDir { path: &'a str },
    MakeDir { path: &'a str },
    RemoveDir { path: &'a str },
    Kind { path: &'a str },
    /// `blob.id` is the path the bytes are at now, so this is both "point
    /// this name at those bytes" and "copy that file to here".
    WriteBlob { path: &'a str, blob: WireBlob },
    Rename { path: &'a str, to: &'a str },
}

/// A blob on the wire. `id` is a path: in a real filesystem the bytes have
/// no name of their own, and giving them one is what the id store used to
/// be for.
#[derive(Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct WireBlob {
    id: String,
    size: f64,
    media_type: String,
}

impl From<BlobRef> for WireBlob {
    fn from(blob: BlobRef) -> WireBlob {
        WireBlob { id: blob.id, size: blob.size as f64, media_type: blob.media_type }
    }
}

impl From<WireBlob> for BlobRef {
    fn from(wire: WireBlob) -> BlobRef {
        BlobRef { id: wire.id, size: wire.size as i64, media_type: wire.media_type }
    }
}

/// What a path holds, on the wire. Null means text.
#[derive(Deserialize)]
struct WireKind {
    blob: Option<WireBlob>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct WireEntry {
    name: String,
    is_dir: bool,
}

/// The failure, named the way [`FsError`] names it so the error a script
/// sees does not depend on which side of the channel noticed.
#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct WireError {
    kind: String,
    arg: String,
}

/// An answer: whichever of the two is there.
#[derive(Deserialize)]
struct Answer<T> {
    ok: Option<T>,
    err: Option<WireError>,
}

impl From<WireError> for FsError {
    fn from(wire: WireError) -> FsError {
        let arg = wire.arg;
        match wire.kind.as_str() {
            "notFound" => FsError::NotFound(arg),
            "notADirectory" => FsError::NotADirectory(arg),
            "isADirectory" => FsError::IsADirectory(arg),
            "alreadyExists" => FsError::AlreadyExists(arg),
            "notEmpty" => FsError::NotEmpty(arg),
            "notText" => FsError::NotText(arg),
            _ => FsError::Io(arg),
        }
    }
}

/// The filesystem as a console sees it: a channel to the worker that has one.
pub struct RemoteFs {
    /// Called with one JSON request and answering with one JSON reply. It
    /// blocks; that is the whole point of it.
    call: js_sys::Function,
    /// Called with a path and answering with a `Uint8Array`, or null when
    /// the bytes have gone. Bytes get a function of their own rather than
    /// riding in the JSON, since a song does not want base64 wrapped round
    /// it on the way to a `Cat`.
    read_blob: js_sys::Function,
}

impl RemoteFs {
    pub fn new(call: js_sys::Function, read_blob: js_sys::Function) -> RemoteFs {
        RemoteFs { call, read_blob }
    }

    /// Ask, and unwrap the answer into the result the trait wants.
    fn ask<T: for<'de> Deserialize<'de>>(&self, request: &Request<'_>) -> FsResult<T> {
        let json = serde_json::to_string(request)
            .map_err(|e| FsError::Io(format!("Could not ask the filesystem: {e}")))?;
        let reply = self
            .call
            .call1(&JsValue::NULL, &JsValue::from_str(&json))
            // The fs worker has gone, which nothing this side can put right.
            .map_err(|_| FsError::Io("The filesystem is not answering".into()))?;
        let text = reply.as_string().ok_or_else(|| {
            FsError::Io("The filesystem answered with something unreadable".into())
        })?;
        let answer: Answer<T> = serde_json::from_str(&text)
            .map_err(|e| FsError::Io(format!("The filesystem answered badly: {e}")))?;
        match (answer.ok, answer.err) {
            (Some(value), _) => Ok(value),
            (None, Some(err)) => Err(err.into()),
            // `ok` may legitimately be absent for a unit answer.
            (None, None) => serde_json::from_str::<T>("null")
                .map_err(|_| FsError::Io("The filesystem answered with nothing".into())),
        }
    }

    /// Ask, where nothing useful comes back and only the failure matters.
    fn tell(&self, request: &Request<'_>) -> FsResult<()> {
        self.ask::<serde_json::Value>(request).map(|_| ())
    }

    /// Ask, where a failure is indistinguishable from a no.
    fn ask_bool(&self, request: &Request<'_>) -> bool {
        self.ask::<bool>(request).unwrap_or(false)
    }
}

/// Every path is folded before it goes down the channel, so the worker on
/// the other end stores and lists one spelling of each name.
impl FileSystem for RemoteFs {
    fn raw_exists(&self, path: &str) -> bool {
        self.ask_bool(&Request::Exists { path })
    }

    fn raw_is_dir(&self, path: &str) -> bool {
        self.ask_bool(&Request::IsDir { path })
    }

    fn raw_read(&self, path: &str) -> FsResult<String> {
        self.ask(&Request::Read { path })
    }

    fn raw_write(&mut self, path: &str, contents: &str) -> FsResult<()> {
        self.tell(&Request::Write { path, contents })
    }

    fn raw_append(&mut self, path: &str, contents: &str) -> FsResult<()> {
        self.tell(&Request::Append { path, contents })
    }

    fn raw_len(&self, path: &str) -> FsResult<i64> {
        self.ask::<f64>(&Request::Len { path }).map(|n| n as i64)
    }

    fn raw_delete(&mut self, path: &str) -> FsResult<()> {
        self.tell(&Request::Delete { path })
    }

    fn raw_read_dir(&self, path: &str) -> FsResult<Vec<DirEntry>> {
        let entries: Vec<WireEntry> = self.ask(&Request::ReadDir { path })?;
        Ok(entries
            .into_iter()
            .map(|e| DirEntry { name: e.name, is_dir: e.is_dir })
            .collect())
    }

    fn raw_make_dir(&mut self, path: &str) -> FsResult<()> {
        self.tell(&Request::MakeDir { path })
    }

    fn raw_remove_dir(&mut self, path: &str) -> FsResult<()> {
        self.tell(&Request::RemoveDir { path })
    }

    fn raw_kind(&self, path: &str) -> FsResult<NodeKind> {
        let kind: WireKind = self.ask(&Request::Kind { path })?;
        Ok(match kind.blob {
            Some(blob) => NodeKind::Blob(blob.into()),
            None => NodeKind::Text,
        })
    }

    fn raw_read_blob(&self, path: &str) -> FsResult<Vec<u8>> {
        let answer = self
            .read_blob
            .call1(&JsValue::NULL, &JsValue::from_str(path))
            .map_err(|_| FsError::Io(format!("Could not read {path}")))?;
        if answer.is_null() || answer.is_undefined() {
            return Err(FsError::NotFound(path.to_string()));
        }
        Ok(js_sys::Uint8Array::new(&answer).to_vec())
    }

    fn raw_write_blob(&mut self, path: &str, blob: BlobRef) -> FsResult<()> {
        self.tell(&Request::WriteBlob { path, blob: blob.into() })
    }

    /// One call rather than the copy-then-delete the trait would do.
    ///
    /// Worth overriding because the worker can rename in OPFS without
    /// touching the bytes, and the bytes here are songs: the default would
    /// rewrite several megabytes to change a name. The folding the trait's
    /// wrappers do has to happen here instead, since this skips them.
    fn rename(&mut self, from: &str, to: &str) -> FsResult<()> {
        self.tell(&Request::Rename { path: &fold_case(from), to: &fold_case(to) })
    }
}
