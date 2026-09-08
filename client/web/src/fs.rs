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
//! There are two channels because the trait splits two ways. Ten of its
//! methods take a path and answer about the tree, and those go as JSON.
//! Three carry contents, and contents are bytes: a song does not want base64
//! wrapped round it on the way to a `Cat`, and JSON has no way to carry it
//! that is not base64. Those go down a channel that speaks bytes both ways.
//!
//! Nothing is cached here on purpose. A cache would be a second copy of the
//! tree, and second copies of the tree are what this replaced.

use serde::{Deserialize, Serialize};
use wasm_bindgen::prelude::*;

use vbscript::game::fs::{DirEntry, FileSystem, FsError, FsResult};
use vbscript::game::path::fold_case;

/// One question for the fs worker. The paths in it are already folded.
#[derive(Serialize)]
#[serde(tag = "op", rename_all = "camelCase")]
enum Request<'a> {
    Exists { path: &'a str },
    IsDir { path: &'a str },
    Len { path: &'a str },
    Delete { path: &'a str },
    ReadDir { path: &'a str },
    MakeDir { path: &'a str },
    RemoveDir { path: &'a str },
    Rename { path: &'a str, to: &'a str },
    Copy { path: &'a str, to: &'a str },
}

/// One question that carries or asks for contents. `max` caps a read, so
/// `Cat` on a song fetches a screenful rather than the album.
#[derive(Serialize)]
#[serde(tag = "op", rename_all = "camelCase")]
enum RawRequest<'a> {
    Read { path: &'a str, max: Option<f64> },
    Write { path: &'a str },
    Append { path: &'a str },
}

/// The answer to a raw request is bytes, so its status has to be bytes too:
/// the first one says which of the two follows.
const RAW_OK: u8 = 0;

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
            _ => FsError::Io(arg),
        }
    }
}

/// The filesystem as a console sees it: two channels to the worker that has
/// one.
pub struct RemoteFs {
    /// Called with one JSON request and answering with one JSON reply. It
    /// blocks; that is the whole point of it.
    call: js_sys::Function,
    /// Called with one JSON request and the bytes it carries, if any, and
    /// answering with a `Uint8Array` whose first byte says whether the rest
    /// is the contents or the complaint.
    raw: js_sys::Function,
}

impl RemoteFs {
    pub fn new(call: js_sys::Function, raw: js_sys::Function) -> RemoteFs {
        RemoteFs { call, raw }
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

    /// Send one content request, with the bytes it carries, and take the
    /// bytes that come back.
    fn ask_raw(&self, request: &RawRequest<'_>, payload: Option<&[u8]>) -> FsResult<Vec<u8>> {
        let json = serde_json::to_string(request)
            .map_err(|e| FsError::Io(format!("Could not ask the filesystem: {e}")))?;
        let bytes = match payload {
            Some(bytes) => js_sys::Uint8Array::from(bytes).into(),
            None => JsValue::NULL,
        };
        let reply = self
            .raw
            .call2(&JsValue::NULL, &JsValue::from_str(&json), &bytes)
            .map_err(|_| FsError::Io("The filesystem is not answering".into()))?;
        if reply.is_null() || reply.is_undefined() {
            return Err(FsError::Io("The filesystem answered with nothing".into()));
        }
        let mut answer = js_sys::Uint8Array::new(&reply).to_vec();
        match answer.first() {
            Some(&RAW_OK) => {
                answer.remove(0);
                Ok(answer)
            }
            // Anything but `RAW_OK` is a complaint, spelled the way the JSON
            // channel spells one so both give a script the same number.
            Some(_) => {
                let wire: WireError = serde_json::from_slice(&answer[1..]).map_err(|e| {
                    FsError::Io(format!("The filesystem answered badly: {e}"))
                })?;
                Err(wire.into())
            }
            None => Err(FsError::Io("The filesystem answered with nothing".into())),
        }
    }
}

/// Every path is folded before it goes down a channel, so the worker on
/// the other end stores and lists one spelling of each name.
impl FileSystem for RemoteFs {
    fn raw_exists(&self, path: &str) -> bool {
        self.ask_bool(&Request::Exists { path })
    }

    fn raw_is_dir(&self, path: &str) -> bool {
        self.ask_bool(&Request::IsDir { path })
    }

    fn raw_read(&self, path: &str) -> FsResult<Vec<u8>> {
        self.ask_raw(&RawRequest::Read { path, max: None }, None)
    }

    /// The cap goes down the channel rather than being applied here, so a
    /// `Cat` on a song never moves the album across it.
    fn raw_read_upto(&self, path: &str, max: usize) -> FsResult<Vec<u8>> {
        self.ask_raw(&RawRequest::Read { path, max: Some(max as f64) }, None)
    }

    fn raw_write(&mut self, path: &str, contents: &[u8]) -> FsResult<()> {
        self.ask_raw(&RawRequest::Write { path }, Some(contents)).map(|_| ())
    }

    fn raw_append(&mut self, path: &str, contents: &[u8]) -> FsResult<()> {
        self.ask_raw(&RawRequest::Append { path }, Some(contents)).map(|_| ())
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

    /// One call rather than the read-and-write the trait would do.
    ///
    /// Worth overriding for the reason the rename below is: the worker can
    /// copy a file in OPFS without the bytes ever entering the engine, and
    /// the bytes here are songs. The folding the trait's wrappers do has to
    /// happen here instead, since this skips them.
    fn copy(&mut self, from: &str, to: &str) -> FsResult<()> {
        self.tell(&Request::Copy { path: &fold_case(from), to: &fold_case(to) })
    }

    /// One call rather than the copy-then-delete the trait would do.
    ///
    /// Worth overriding because the worker can rename in OPFS without
    /// touching the bytes: the default would rewrite several megabytes to
    /// change a name.
    fn rename(&mut self, from: &str, to: &str) -> FsResult<()> {
        self.tell(&Request::Rename { path: &fold_case(from), to: &fold_case(to) })
    }
}
