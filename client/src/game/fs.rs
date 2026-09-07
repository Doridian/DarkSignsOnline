//! The in-game filesystem the local half of the host API works on.
//!
//! Scripts see a `/`-rooted tree that is really the player's directory. The
//! [`FileSystem`] trait is the seam: the desktop client backs it with real
//! files, tests back it with [`MemoryFs`].
//!
//! The tree is case-insensitive, as the Windows one the VB6 client used was.
//! [`FileSystem`] folds every path on the way in, so a backend stores and
//! lists one spelling of each name whatever case it was written in.

use std::collections::BTreeMap;

use super::path::{fold_case, split_parent};

/// What went wrong with a filesystem operation. These map onto the errors
/// the VB6 client raised, so scripts see familiar numbers.
#[derive(Debug, PartialEq, Eq)]
pub enum FsError {
    NotFound(String),
    NotADirectory(String),
    IsADirectory(String),
    AlreadyExists(String),
    NotEmpty(String),
    /// A text operation on a file that holds bytes rather than text.
    NotText(String),
    Io(String),
}

impl std::fmt::Display for FsError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            FsError::NotFound(p) => write!(f, "File not found: {p}"),
            FsError::NotADirectory(p) => write!(f, "Can only list directories: {p}"),
            FsError::IsADirectory(p) => write!(f, "Path is a directory: {p}"),
            FsError::AlreadyExists(p) => write!(f, "File already exists: {p}"),
            FsError::NotEmpty(p) => write!(f, "Directory is not empty: {p}"),
            FsError::NotText(p) => write!(f, "Not a text file: {p}"),
            FsError::Io(m) => write!(f, "{m}"),
        }
    }
}

pub type FsResult<T> = Result<T, FsError>;

/// One entry from a directory listing. Directories keep the trailing slash
/// the client's `ReadDir` puts on them.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DirEntry {
    pub name: String,
    pub is_dir: bool,
}

impl DirEntry {
    /// The form scripts see, where a directory ends in `/`.
    pub fn display_name(&self) -> String {
        if self.is_dir {
            format!("{}/", self.name)
        } else {
            self.name.clone()
        }
    }
}

/// What a path holds.
///
/// Text is what scripts read and write, and is nearly every path in the tree:
/// scripts, notes, INI files. A blob is bytes the tree only ever *describes*
/// -- how many of them there are and what kind they are -- because nothing in
/// the engine wants them as a string. A player's music and pictures live
/// there, and the page plays or shows them when a script names the path.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum NodeKind {
    Text,
    Blob(BlobRef),
}

/// Where a blob's bytes are, and what they are.
///
/// `id` names the bytes rather than the path that reaches them, which is what
/// makes copying a blob cheap: a second name for one set of bytes, however
/// many megabytes those are. What an id *means* is the backend's business --
/// [`MemoryFs`] treats it as an opaque handle, [`DiskFs`] as the path the
/// bytes already sit at -- so long as `raw_read_blob` can follow it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BlobRef {
    pub id: String,
    pub size: i64,
    /// The MIME type the page needs in order to play or show this,
    /// `audio/mpeg` and the like. Empty when nothing worked it out.
    pub media_type: String,
}

/// The MIME type a name implies, or `None` when nothing about it says the
/// file is anything but text.
///
/// The tree is overwhelmingly scripts, so this lists what a player would
/// plausibly want to hear or see rather than trying to be a full table.
pub fn media_type_for(path: &str) -> Option<&'static str> {
    let name = path.rsplit('/').next().unwrap_or(path);
    let ext = name.rsplit_once('.')?.1.to_ascii_lowercase();
    Some(match ext.as_str() {
        "mp3" => "audio/mpeg",
        "ogg" | "oga" => "audio/ogg",
        "wav" => "audio/wav",
        "flac" => "audio/flac",
        "m4a" | "aac" => "audio/mp4",
        "png" => "image/png",
        "jpg" | "jpeg" => "image/jpeg",
        "gif" => "image/gif",
        "webp" => "image/webp",
        "bmp" => "image/bmp",
        "mp4" | "m4v" => "video/mp4",
        "webm" => "video/webm",
        _ => return None,
    })
}

/// The filesystem scripts see, which is case-insensitive.
///
/// The `raw_*` methods are the backing store and are what an implementation
/// writes. They are only ever handed a path already folded by
/// [`fold_case`], so the store holds one spelling of every name and finds it
/// by plain comparison; the methods below them are what callers use, and
/// they do that folding. An implementation that needs to fold a path itself
/// -- to seed the tree, say -- calls the folding method rather than the
/// `raw_*` one.
pub trait FileSystem {
    fn raw_exists(&self, path: &str) -> bool;
    fn raw_is_dir(&self, path: &str) -> bool;
    fn raw_read(&self, path: &str) -> FsResult<String>;
    fn raw_write(&mut self, path: &str, contents: &str) -> FsResult<()>;
    fn raw_append(&mut self, path: &str, contents: &str) -> FsResult<()>;
    fn raw_len(&self, path: &str) -> FsResult<i64>;
    fn raw_delete(&mut self, path: &str) -> FsResult<()>;
    fn raw_read_dir(&self, path: &str) -> FsResult<Vec<DirEntry>>;
    fn raw_make_dir(&mut self, path: &str) -> FsResult<()>;
    fn raw_remove_dir(&mut self, path: &str) -> FsResult<()>;
    /// What `path` holds: text, or bytes the tree only describes.
    fn raw_kind(&self, path: &str) -> FsResult<NodeKind>;
    /// The bytes behind `path`. Text reads back as its own UTF-8, so that
    /// handing any file to something outside the engine works the same way
    /// whichever kind it is.
    fn raw_read_blob(&self, path: &str) -> FsResult<Vec<u8>>;
    /// Point `path` at the bytes `blob` names, replacing whatever was there.
    fn raw_write_blob(&mut self, path: &str, blob: BlobRef) -> FsResult<()>;

    fn exists(&self, path: &str) -> bool {
        self.raw_exists(&fold_case(path))
    }

    fn is_dir(&self, path: &str) -> bool {
        self.raw_is_dir(&fold_case(path))
    }

    fn read(&self, path: &str) -> FsResult<String> {
        self.raw_read(&fold_case(path))
    }

    fn write(&mut self, path: &str, contents: &str) -> FsResult<()> {
        self.raw_write(&fold_case(path), contents)
    }

    fn append(&mut self, path: &str, contents: &str) -> FsResult<()> {
        self.raw_append(&fold_case(path), contents)
    }

    fn len(&self, path: &str) -> FsResult<i64> {
        self.raw_len(&fold_case(path))
    }

    fn delete(&mut self, path: &str) -> FsResult<()> {
        self.raw_delete(&fold_case(path))
    }

    fn read_dir(&self, path: &str) -> FsResult<Vec<DirEntry>> {
        self.raw_read_dir(&fold_case(path))
    }

    fn make_dir(&mut self, path: &str) -> FsResult<()> {
        self.raw_make_dir(&fold_case(path))
    }

    fn remove_dir(&mut self, path: &str) -> FsResult<()> {
        self.raw_remove_dir(&fold_case(path))
    }

    fn kind(&self, path: &str) -> FsResult<NodeKind> {
        self.raw_kind(&fold_case(path))
    }

    fn read_blob(&self, path: &str) -> FsResult<Vec<u8>> {
        self.raw_read_blob(&fold_case(path))
    }

    fn write_blob(&mut self, path: &str, blob: BlobRef) -> FsResult<()> {
        self.raw_write_blob(&fold_case(path), blob)
    }

    /// Copy a file.
    ///
    /// Text is read and written back, which suits any backing store. A blob
    /// is copied by naming its bytes a second time, so copying a song costs
    /// what copying an empty file costs.
    fn copy(&mut self, from: &str, to: &str) -> FsResult<()> {
        match self.kind(from)? {
            NodeKind::Text => {
                let data = self.read(from)?;
                self.write(to, &data)
            }
            NodeKind::Blob(blob) => self.write_blob(to, blob),
        }
    }

    /// Move a file, which is a copy followed by a delete.
    fn rename(&mut self, from: &str, to: &str) -> FsResult<()> {
        self.copy(from, to)?;
        self.delete(from)
    }
}

/// One entry in the tree: a file's text, or a reference to bytes held apart
/// from it.
enum Node {
    Text(String),
    Blob(BlobRef),
}

/// A filesystem held entirely in memory. It is the test double, and also
/// what a sandboxed or headless client can run on.
///
/// `nodes` is the tree itself: every name, and for a blob the size and type
/// of what it points at. Blob bytes sit apart from it in `blobs`, keyed by
/// id, so that a copy is another name rather than another few megabytes --
/// and so that a backend keeping its bytes somewhere else entirely can wrap
/// this for the tree alone and leave `blobs` empty, which is what the
/// browser client does.
#[derive(Default)]
pub struct MemoryFs {
    nodes: BTreeMap<String, Node>,
    dirs: std::collections::BTreeSet<String>,
    blobs: BTreeMap<String, Vec<u8>>,
}

impl MemoryFs {
    pub fn new() -> MemoryFs {
        let mut fs = MemoryFs::default();
        fs.dirs.insert("/".into());
        fs
    }

    /// Create a file and every directory leading to it, for test setup.
    ///
    /// Panics if a directory of that name is in the way, which is a mistake
    /// in the setup rather than something to carry on from.
    pub fn with_file(mut self, path: &str, contents: &str) -> MemoryFs {
        self.write(path, contents).expect("no directory in the way");
        self
    }

    /// Create a blob and the bytes behind it, for test setup.
    pub fn with_blob(mut self, path: &str, id: &str, bytes: &[u8]) -> MemoryFs {
        self.put_blob(id, bytes.to_vec());
        let blob = BlobRef {
            id: id.into(),
            size: bytes.len() as i64,
            media_type: media_type_for(path).unwrap_or_default().into(),
        };
        self.write_blob(path, blob).expect("no directory in the way");
        self
    }

    pub fn with_dir(mut self, path: &str) -> MemoryFs {
        let path = fold_case(path);
        self.create_parents(&path);
        self.dirs.insert(path);
        self
    }

    /// Hold the bytes an id names. A backend that keeps them elsewhere never
    /// calls this, and answers `raw_read_blob` its own way instead.
    pub fn put_blob(&mut self, id: &str, bytes: Vec<u8>) {
        self.blobs.insert(id.into(), bytes);
    }

    fn create_parents(&mut self, path: &str) {
        let (parent, _) = split_parent(path);
        let mut current = String::new();
        self.dirs.insert("/".into());
        for part in parent.split('/').filter(|p| !p.is_empty()) {
            current.push('/');
            current.push_str(part);
            self.dirs.insert(current.clone());
        }
    }

    /// Remove whatever `path` held, forgetting orphaned bytes with it.
    ///
    /// A blob's bytes outlive the name that was just dropped whenever some
    /// other name still reaches them, which is what a copy leaves behind.
    /// The scan is over the tree, which is names and sizes however large the
    /// bytes it guards are.
    fn clear_node(&mut self, path: &str) {
        let Some(Node::Blob(blob)) = self.nodes.remove(path) else {
            return;
        };
        let still_named =
            self.nodes.values().any(|n| matches!(n, Node::Blob(b) if b.id == blob.id));
        if !still_named {
            self.blobs.remove(&blob.id);
        }
    }

    /// Every path this filesystem holds, for assertions.
    pub fn paths(&self) -> Vec<&str> {
        self.nodes.keys().map(|s| s.as_str()).collect()
    }
}

impl FileSystem for MemoryFs {
    fn raw_exists(&self, path: &str) -> bool {
        self.nodes.contains_key(path) || self.dirs.contains(path)
    }

    fn raw_is_dir(&self, path: &str) -> bool {
        self.dirs.contains(path)
    }

    fn raw_read(&self, path: &str) -> FsResult<String> {
        if self.dirs.contains(path) {
            return Err(FsError::IsADirectory(path.into()));
        }
        match self.nodes.get(path) {
            Some(Node::Text(text)) => Ok(text.clone()),
            Some(Node::Blob(_)) => Err(FsError::NotText(path.into())),
            None => Err(FsError::NotFound(path.into())),
        }
    }

    fn raw_write(&mut self, path: &str, contents: &str) -> FsResult<()> {
        if self.dirs.contains(path) {
            return Err(FsError::IsADirectory(path.into()));
        }
        self.create_parents(path);
        // Writing text over a blob is allowed and drops the bytes: the file
        // is simply a different kind of file afterwards.
        self.clear_node(path);
        self.nodes.insert(path.into(), Node::Text(contents.into()));
        Ok(())
    }

    fn raw_append(&mut self, path: &str, contents: &str) -> FsResult<()> {
        if self.dirs.contains(path) {
            return Err(FsError::IsADirectory(path.into()));
        }
        self.create_parents(path);
        match self.nodes.entry(path.into()).or_insert_with(|| Node::Text(String::new())) {
            Node::Text(text) => {
                text.push_str(contents);
                Ok(())
            }
            // Unlike a write, this would leave a file that is half text and
            // half whatever it was, so it is refused rather than obeyed.
            Node::Blob(_) => Err(FsError::NotText(path.into())),
        }
    }

    fn raw_len(&self, path: &str) -> FsResult<i64> {
        if self.dirs.contains(path) {
            return Err(FsError::IsADirectory(path.into()));
        }
        match self.nodes.get(path) {
            Some(Node::Text(text)) => Ok(text.len() as i64),
            // From the tree, without the bytes ever being fetched.
            Some(Node::Blob(blob)) => Ok(blob.size),
            None => Err(FsError::NotFound(path.into())),
        }
    }

    fn raw_delete(&mut self, path: &str) -> FsResult<()> {
        if !self.nodes.contains_key(path) {
            return Err(FsError::NotFound(path.into()));
        }
        self.clear_node(path);
        Ok(())
    }

    fn raw_read_dir(&self, path: &str) -> FsResult<Vec<DirEntry>> {
        if !self.dirs.contains(path) {
            return Err(FsError::NotADirectory(path.into()));
        }
        // Only direct children: anything whose parent is this directory.
        let mut out: Vec<DirEntry> = Vec::new();
        for d in &self.dirs {
            if d != path && split_parent(d).0 == path {
                out.push(DirEntry { name: split_parent(d).1.into(), is_dir: true });
            }
        }
        for f in self.nodes.keys() {
            if split_parent(f).0 == path {
                out.push(DirEntry { name: split_parent(f).1.into(), is_dir: false });
            }
        }
        out.sort_by(|a, b| a.name.cmp(&b.name));
        Ok(out)
    }

    fn raw_make_dir(&mut self, path: &str) -> FsResult<()> {
        if self.raw_exists(path) {
            return Err(FsError::AlreadyExists(path.into()));
        }
        self.create_parents(path);
        self.dirs.insert(path.into());
        Ok(())
    }

    fn raw_remove_dir(&mut self, path: &str) -> FsResult<()> {
        if !self.dirs.contains(path) {
            return Err(FsError::NotADirectory(path.into()));
        }
        if !self.raw_read_dir(path)?.is_empty() {
            return Err(FsError::NotEmpty(path.into()));
        }
        self.dirs.remove(path);
        Ok(())
    }

    fn raw_kind(&self, path: &str) -> FsResult<NodeKind> {
        if self.dirs.contains(path) {
            return Err(FsError::IsADirectory(path.into()));
        }
        match self.nodes.get(path) {
            Some(Node::Text(_)) => Ok(NodeKind::Text),
            Some(Node::Blob(blob)) => Ok(NodeKind::Blob(blob.clone())),
            None => Err(FsError::NotFound(path.into())),
        }
    }

    fn raw_read_blob(&self, path: &str) -> FsResult<Vec<u8>> {
        match self.raw_kind(path)? {
            NodeKind::Text => self.raw_read(path).map(String::into_bytes),
            NodeKind::Blob(blob) => self
                .blobs
                .get(&blob.id)
                .cloned()
                // The tree knows the file is there; whoever holds the bytes
                // has lost them, which is worth saying differently.
                .ok_or_else(|| FsError::Io(format!("Missing blob {} for {path}", blob.id))),
        }
    }

    fn raw_write_blob(&mut self, path: &str, blob: BlobRef) -> FsResult<()> {
        if self.dirs.contains(path) {
            return Err(FsError::IsADirectory(path.into()));
        }
        self.create_parents(path);
        self.clear_node(path);
        self.nodes.insert(path.into(), Node::Blob(blob));
        Ok(())
    }
}

/// A filesystem backed by a real directory.
///
/// Native only: a browser build uses [`MemoryFs`] over whatever storage it
/// has.
///
/// Every game path is resolved and stripped of `..` before it is joined to
/// the root, so a script cannot reach outside the player's directory even if
/// it constructs the path itself.
///
/// The root holds folded names, since that is all this ever writes; a file
/// put there by hand under a mixed-case name is invisible on a
/// case-sensitive host filesystem.
#[cfg(not(target_arch = "wasm32"))]
pub struct DiskFs {
    root: std::path::PathBuf,
}

#[cfg(not(target_arch = "wasm32"))]
impl DiskFs {
    pub fn new(root: impl Into<std::path::PathBuf>) -> DiskFs {
        DiskFs { root: root.into() }
    }

    /// Map a game path onto a real one, refusing anything that would escape
    /// the root.
    fn real(&self, path: &str) -> std::path::PathBuf {
        let normalized = super::path::resolve_rel("/", path);
        let mut out = self.root.clone();
        for part in normalized.split('/') {
            // `resolve_rel` has already collapsed these, but a second check
            // costs nothing and this is the sandbox boundary.
            if part.is_empty() || part == "." || part == ".." {
                continue;
            }
            out.push(part);
        }
        out
    }

    fn io(e: std::io::Error, path: &str) -> FsError {
        match e.kind() {
            std::io::ErrorKind::NotFound => FsError::NotFound(path.into()),
            std::io::ErrorKind::AlreadyExists => FsError::AlreadyExists(path.into()),
            _ => FsError::Io(e.to_string()),
        }
    }
}

#[cfg(not(target_arch = "wasm32"))]
impl FileSystem for DiskFs {
    fn raw_exists(&self, path: &str) -> bool {
        self.real(path).exists()
    }

    fn raw_is_dir(&self, path: &str) -> bool {
        self.real(path).is_dir()
    }

    fn raw_read(&self, path: &str) -> FsResult<String> {
        let real = self.real(path);
        if real.is_dir() {
            return Err(FsError::IsADirectory(path.into()));
        }
        // Refused by name rather than by content, so that a script gets the
        // same answer here as it does in the browser, where the tree was
        // told what the file was when it arrived.
        if real.is_file() && media_type_for(path).is_some() {
            return Err(FsError::NotText(path.into()));
        }
        std::fs::read_to_string(&real).map_err(|e| DiskFs::io(e, path))
    }

    fn raw_write(&mut self, path: &str, contents: &str) -> FsResult<()> {
        let real = self.real(path);
        if let Some(parent) = real.parent() {
            std::fs::create_dir_all(parent).map_err(|e| DiskFs::io(e, path))?;
        }
        std::fs::write(&real, contents).map_err(|e| DiskFs::io(e, path))
    }

    fn raw_append(&mut self, path: &str, contents: &str) -> FsResult<()> {
        use std::io::Write;
        let real = self.real(path);
        if let Some(parent) = real.parent() {
            std::fs::create_dir_all(parent).map_err(|e| DiskFs::io(e, path))?;
        }
        let mut f = std::fs::OpenOptions::new()
            .create(true)
            .append(true)
            .open(&real)
            .map_err(|e| DiskFs::io(e, path))?;
        f.write_all(contents.as_bytes()).map_err(|e| DiskFs::io(e, path))
    }

    fn raw_len(&self, path: &str) -> FsResult<i64> {
        let meta = std::fs::metadata(self.real(path)).map_err(|e| DiskFs::io(e, path))?;
        Ok(meta.len() as i64)
    }

    fn raw_delete(&mut self, path: &str) -> FsResult<()> {
        std::fs::remove_file(self.real(path)).map_err(|e| DiskFs::io(e, path))
    }

    fn raw_read_dir(&self, path: &str) -> FsResult<Vec<DirEntry>> {
        let real = self.real(path);
        if !real.is_dir() {
            return Err(FsError::NotADirectory(path.into()));
        }
        let mut out = Vec::new();
        for entry in std::fs::read_dir(&real).map_err(|e| DiskFs::io(e, path))? {
            let entry = entry.map_err(|e| DiskFs::io(e, path))?;
            out.push(DirEntry {
                name: entry.file_name().to_string_lossy().into_owned(),
                is_dir: entry.path().is_dir(),
            });
        }
        out.sort_by(|a, b| a.name.cmp(&b.name));
        Ok(out)
    }

    fn raw_make_dir(&mut self, path: &str) -> FsResult<()> {
        let real = self.real(path);
        if real.exists() {
            return Err(FsError::AlreadyExists(path.into()));
        }
        std::fs::create_dir_all(&real).map_err(|e| DiskFs::io(e, path))
    }

    fn raw_remove_dir(&mut self, path: &str) -> FsResult<()> {
        let real = self.real(path);
        if !real.is_dir() {
            return Err(FsError::NotADirectory(path.into()));
        }
        std::fs::remove_dir(&real).map_err(|e| match e.kind() {
            // The platforms disagree on the code, so check emptiness.
            _ if std::fs::read_dir(&real).map(|mut d| d.next().is_some()).unwrap_or(false) => {
                FsError::NotEmpty(path.into())
            }
            _ => DiskFs::io(e, path),
        })
    }

    /// On a real disk every file is bytes, so the name is the only thing
    /// saying which of them a script would rather not be handed as a string.
    fn raw_kind(&self, path: &str) -> FsResult<NodeKind> {
        let real = self.real(path);
        if real.is_dir() {
            return Err(FsError::IsADirectory(path.into()));
        }
        let meta = std::fs::metadata(&real).map_err(|e| DiskFs::io(e, path))?;
        match media_type_for(path) {
            Some(media_type) => Ok(NodeKind::Blob(BlobRef {
                id: path.into(),
                size: meta.len() as i64,
                media_type: media_type.into(),
            })),
            None => Ok(NodeKind::Text),
        }
    }

    fn raw_read_blob(&self, path: &str) -> FsResult<Vec<u8>> {
        let real = self.real(path);
        if real.is_dir() {
            return Err(FsError::IsADirectory(path.into()));
        }
        std::fs::read(&real).map_err(|e| DiskFs::io(e, path))
    }

    /// Here an id is the path the bytes already sit at, so pointing a second
    /// name at them means copying the file: a directory has no way to hold
    /// one file under two names that a later write would not confuse.
    fn raw_write_blob(&mut self, path: &str, blob: BlobRef) -> FsResult<()> {
        let (from, to) = (self.real(&blob.id), self.real(path));
        if from == to {
            return Ok(());
        }
        if let Some(parent) = to.parent() {
            std::fs::create_dir_all(parent).map_err(|e| DiskFs::io(e, path))?;
        }
        std::fs::copy(&from, &to).map(|_| ()).map_err(|e| DiskFs::io(e, path))
    }
}

/// Read a value from INI text, as `GetPrivateProfileString` does: sections
/// in `[brackets]`, `key=value` lines, and a missing key yielding "".
pub fn ini_get(text: &str, section: &str, key: &str) -> String {
    let mut in_section = false;
    for line in text.lines() {
        let line = line.trim();
        if let Some(name) = line.strip_prefix('[').and_then(|l| l.strip_suffix(']')) {
            in_section = name.eq_ignore_ascii_case(section);
            continue;
        }
        if !in_section {
            continue;
        }
        if let Some((k, v)) = line.split_once('=') {
            if k.trim().eq_ignore_ascii_case(key) {
                return v.trim().to_string();
            }
        }
    }
    String::new()
}

/// Set a value in INI text, adding the section or key if needed.
pub fn ini_set(text: &str, section: &str, key: &str, value: &str) -> String {
    let mut out: Vec<String> = Vec::new();
    let mut in_section = false;
    let mut written = false;
    let mut seen_section = false;

    for line in text.lines() {
        let trimmed = line.trim();
        if let Some(name) = trimmed.strip_prefix('[').and_then(|l| l.strip_suffix(']')) {
            // Leaving the target section without having written the key
            // means it has to go in just before the next section starts.
            if in_section && !written {
                out.push(format!("{key}={value}"));
                written = true;
            }
            in_section = name.eq_ignore_ascii_case(section);
            seen_section |= in_section;
            out.push(line.to_string());
            continue;
        }
        if in_section && !written {
            if let Some((k, _)) = trimmed.split_once('=') {
                if k.trim().eq_ignore_ascii_case(key) {
                    out.push(format!("{key}={value}"));
                    written = true;
                    continue;
                }
            }
        }
        out.push(line.to_string());
    }

    if !seen_section {
        out.push(format!("[{section}]"));
    }
    if !written {
        out.push(format!("{key}={value}"));
    }
    let mut joined = out.join("\r\n");
    joined.push_str("\r\n");
    joined
}

#[cfg(test)]
mod tests {
    use super::*;

    fn fs() -> MemoryFs {
        MemoryFs::new()
            .with_file("/home/a.txt", "alpha")
            .with_file("/home/b.txt", "beta")
            .with_dir("/home/sub")
            .with_file("/home/sub/c.txt", "gamma")
    }

    #[test]
    fn reads_and_writes_files() {
        let mut f = fs();
        assert_eq!(f.read("/home/a.txt").unwrap(), "alpha");
        f.write("/home/a.txt", "changed").unwrap();
        assert_eq!(f.read("/home/a.txt").unwrap(), "changed");
    }

    #[test]
    fn writing_creates_parent_directories() {
        let mut f = MemoryFs::new();
        f.write("/deep/nested/file.txt", "x").unwrap();
        assert!(f.is_dir("/deep"));
        assert!(f.is_dir("/deep/nested"));
        assert!(f.exists("/deep/nested/file.txt"));
    }

    #[test]
    fn appending_to_a_missing_file_creates_it() {
        let mut f = MemoryFs::new();
        f.append("/log.txt", "one").unwrap();
        f.append("/log.txt", "two").unwrap();
        assert_eq!(f.read("/log.txt").unwrap(), "onetwo");
    }

    #[test]
    fn reading_a_missing_file_reports_not_found() {
        assert_eq!(
            fs().read("/nope").unwrap_err(),
            FsError::NotFound("/nope".into())
        );
    }

    #[test]
    fn reading_a_directory_is_an_error() {
        assert_eq!(
            fs().read("/home/sub").unwrap_err(),
            FsError::IsADirectory("/home/sub".into())
        );
    }

    #[test]
    fn lists_only_direct_children_with_directories_marked() {
        let names: Vec<String> = fs()
            .read_dir("/home")
            .unwrap()
            .iter()
            .map(|e| e.display_name())
            .collect();
        assert_eq!(names, vec!["a.txt", "b.txt", "sub/"]);
    }

    #[test]
    fn listing_a_file_is_an_error() {
        assert!(matches!(
            fs().read_dir("/home/a.txt"),
            Err(FsError::NotADirectory(_))
        ));
    }

    #[test]
    fn names_are_matched_and_stored_folded() {
        let mut f = fs();
        assert_eq!(f.read("/HOME/A.TXT").unwrap(), "alpha");
        assert!(f.exists("/Home/Sub"));
        assert!(f.is_dir("/Home/Sub"));

        // Writing under another spelling rewrites the same file rather than
        // adding a second one.
        f.write("/Home/A.Txt", "changed").unwrap();
        assert_eq!(f.read("/home/a.txt").unwrap(), "changed");
        assert_eq!(f.paths(), vec!["/home/a.txt", "/home/b.txt", "/home/sub/c.txt"]);
    }

    #[test]
    fn a_new_file_is_stored_under_its_folded_name() {
        let mut f = MemoryFs::new();
        f.write("/Home/Notes/TODO.TXT", "x").unwrap();
        assert_eq!(f.paths(), vec!["/home/notes/todo.txt"]);
        let names: Vec<String> =
            f.read_dir("/home/notes").unwrap().iter().map(|e| e.display_name()).collect();
        assert_eq!(names, vec!["todo.txt"]);
        assert!(f.is_dir("/home/notes"), "the parents are folded too");
    }

    #[test]
    fn copy_and_rename_move_content() {
        let mut f = fs();
        f.copy("/home/a.txt", "/home/copy.txt").unwrap();
        assert_eq!(f.read("/home/copy.txt").unwrap(), "alpha");
        assert!(f.exists("/home/a.txt"), "copy leaves the source");

        f.rename("/home/copy.txt", "/home/moved.txt").unwrap();
        assert_eq!(f.read("/home/moved.txt").unwrap(), "alpha");
        assert!(!f.exists("/home/copy.txt"), "rename removes the source");
    }

    #[test]
    fn directories_must_be_empty_to_remove() {
        let mut f = fs();
        assert!(matches!(
            f.remove_dir("/home/sub"),
            Err(FsError::NotEmpty(_))
        ));
        f.delete("/home/sub/c.txt").unwrap();
        f.remove_dir("/home/sub").unwrap();
        assert!(!f.exists("/home/sub"));
    }

    #[test]
    fn making_an_existing_directory_is_an_error() {
        let mut f = fs();
        assert!(matches!(
            f.make_dir("/home/sub"),
            Err(FsError::AlreadyExists(_))
        ));
    }

    #[test]
    #[cfg(not(target_arch = "wasm32"))]
    fn the_disk_filesystem_stays_inside_its_root() {
        let root = std::env::temp_dir().join(format!("dso-fs-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&root);
        std::fs::create_dir_all(&root).unwrap();
        let mut fs = DiskFs::new(&root);

        fs.write("/a/b.txt", "inside").unwrap();
        assert_eq!(fs.read("/a/b.txt").unwrap(), "inside");
        assert!(root.join("a/b.txt").exists());

        // A path that tries to climb out lands back at the root.
        fs.write("/../escaped.txt", "still inside").unwrap();
        assert!(root.join("escaped.txt").exists(), "must not escape the root");
        assert!(!root.parent().unwrap().join("escaped.txt").exists());

        let _ = std::fs::remove_dir_all(&root);
    }

    #[test]
    #[cfg(not(target_arch = "wasm32"))]
    fn the_disk_filesystem_folds_names_too() {
        let root = std::env::temp_dir().join(format!("dso-fs3-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&root);
        std::fs::create_dir_all(&root).unwrap();
        let mut fs = DiskFs::new(&root);

        fs.write("/Dir/One.TXT", "1").unwrap();
        assert!(root.join("dir/one.txt").exists(), "stored folded");
        assert_eq!(fs.read("/DIR/ONE.txt").unwrap(), "1");

        let _ = std::fs::remove_dir_all(&root);
    }

    #[test]
    #[cfg(not(target_arch = "wasm32"))]
    fn the_disk_filesystem_lists_and_removes() {
        let root = std::env::temp_dir().join(format!("dso-fs2-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&root);
        std::fs::create_dir_all(&root).unwrap();
        let mut fs = DiskFs::new(&root);

        fs.write("/dir/one.txt", "1").unwrap();
        fs.make_dir("/dir/sub").unwrap();
        let names: Vec<String> =
            fs.read_dir("/dir").unwrap().iter().map(|e| e.display_name()).collect();
        assert_eq!(names, vec!["one.txt", "sub/"]);

        assert!(matches!(fs.remove_dir("/dir"), Err(FsError::NotEmpty(_))));
        fs.delete("/dir/one.txt").unwrap();
        fs.remove_dir("/dir/sub").unwrap();
        fs.remove_dir("/dir").unwrap();
        assert!(!fs.exists("/dir"));

        let _ = std::fs::remove_dir_all(&root);
    }

    // ---- blobs -----------------------------------------------------------

    fn with_song() -> MemoryFs {
        fs().with_blob("/home/theme.mp3", "blob1", b"ID3\x04\x00nonsense")
    }

    #[test]
    fn a_blob_is_a_file_in_the_same_tree() {
        let f = with_song();
        assert!(f.exists("/home/theme.mp3"));
        assert!(!f.is_dir("/home/theme.mp3"));
        let names: Vec<String> =
            f.read_dir("/home").unwrap().iter().map(|e| e.display_name()).collect();
        assert_eq!(names, vec!["a.txt", "b.txt", "sub/", "theme.mp3"]);
    }

    #[test]
    fn a_blob_reports_its_size_without_its_bytes() {
        assert_eq!(with_song().len("/home/theme.mp3").unwrap(), 13);
    }

    #[test]
    fn a_blob_carries_the_type_its_name_implies() {
        let NodeKind::Blob(blob) = with_song().kind("/home/theme.mp3").unwrap() else {
            panic!("expected a blob");
        };
        assert_eq!(blob.media_type, "audio/mpeg");
        assert_eq!(blob.size, 13);
    }

    #[test]
    fn reading_a_blob_as_text_is_refused() {
        assert_eq!(
            with_song().read("/home/theme.mp3").unwrap_err(),
            FsError::NotText("/home/theme.mp3".into())
        );
    }

    #[test]
    fn appending_to_a_blob_is_refused() {
        assert_eq!(
            with_song().append("/home/theme.mp3", "more").unwrap_err(),
            FsError::NotText("/home/theme.mp3".into())
        );
    }

    #[test]
    fn a_text_file_reads_back_as_its_own_bytes() {
        assert_eq!(fs().read_blob("/home/a.txt").unwrap(), b"alpha");
    }

    #[test]
    fn copying_a_blob_gives_the_bytes_a_second_name() {
        let mut f = with_song();
        f.copy("/home/theme.mp3", "/home/sub/copy.mp3").unwrap();

        let NodeKind::Blob(original) = f.kind("/home/theme.mp3").unwrap() else {
            panic!("expected a blob");
        };
        let NodeKind::Blob(copy) = f.kind("/home/sub/copy.mp3").unwrap() else {
            panic!("expected a blob");
        };
        assert_eq!(original.id, copy.id, "one set of bytes under two names");
        assert_eq!(f.read_blob("/home/sub/copy.mp3").unwrap(), b"ID3\x04\x00nonsense");
    }

    #[test]
    fn deleting_one_name_leaves_the_bytes_for_the_other() {
        let mut f = with_song();
        f.copy("/home/theme.mp3", "/home/copy.mp3").unwrap();
        f.delete("/home/theme.mp3").unwrap();
        assert_eq!(f.read_blob("/home/copy.mp3").unwrap(), b"ID3\x04\x00nonsense");
    }

    #[test]
    fn deleting_the_last_name_forgets_the_bytes() {
        let mut f = with_song();
        let NodeKind::Blob(blob) = f.kind("/home/theme.mp3").unwrap() else {
            panic!("expected a blob");
        };
        f.delete("/home/theme.mp3").unwrap();

        // Naming those bytes again finds nothing behind them, which is how
        // the tree says it dropped them rather than kept them for ever.
        f.write_blob("/home/back.mp3", blob).unwrap();
        assert!(matches!(f.read_blob("/home/back.mp3"), Err(FsError::Io(_))));
    }

    #[test]
    fn renaming_a_blob_moves_the_name_only() {
        let mut f = with_song();
        f.rename("/home/theme.mp3", "/home/other.mp3").unwrap();
        assert!(!f.exists("/home/theme.mp3"));
        assert_eq!(f.read_blob("/home/other.mp3").unwrap(), b"ID3\x04\x00nonsense");
    }

    #[test]
    fn writing_text_over_a_blob_makes_it_a_text_file() {
        let mut f = with_song();
        f.write("/home/theme.mp3", "not a song any more").unwrap();
        assert_eq!(f.kind("/home/theme.mp3").unwrap(), NodeKind::Text);
        assert_eq!(f.read("/home/theme.mp3").unwrap(), "not a song any more");
    }

    #[test]
    fn blob_names_are_folded_like_any_other() {
        let f = fs().with_blob("/Home/Theme.MP3", "blob1", b"bytes");
        assert_eq!(f.paths(), vec!["/home/a.txt", "/home/b.txt", "/home/sub/c.txt", "/home/theme.mp3"]);
        assert_eq!(f.read_blob("/HOME/THEME.MP3").unwrap(), b"bytes");
    }

    #[test]
    fn media_types_come_from_the_name() {
        assert_eq!(media_type_for("/a/song.mp3"), Some("audio/mpeg"));
        assert_eq!(media_type_for("/a/SONG.MP3"), Some("audio/mpeg"));
        assert_eq!(media_type_for("/a/shot.png"), Some("image/png"));
        assert_eq!(media_type_for("/a/clip.webm"), Some("video/webm"));
        assert_eq!(media_type_for("/a/script.vbs"), None);
        assert_eq!(media_type_for("/a/readme"), None);
        assert_eq!(media_type_for("/my.files/readme"), None, "the dot is in the directory");
    }

    #[test]
    #[cfg(not(target_arch = "wasm32"))]
    fn the_disk_filesystem_treats_media_names_as_blobs() {
        let root = std::env::temp_dir().join(format!("dso-fs4-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&root);
        std::fs::create_dir_all(&root).unwrap();
        let mut fs = DiskFs::new(&root);

        std::fs::create_dir_all(root.join("media")).unwrap();
        std::fs::write(root.join("media/theme.mp3"), b"\x00\x01\x02bytes").unwrap();

        let NodeKind::Blob(blob) = fs.kind("/media/theme.mp3").unwrap() else {
            panic!("expected a blob");
        };
        assert_eq!(blob.media_type, "audio/mpeg");
        assert_eq!(blob.size, 8);
        assert_eq!(fs.kind("/media").unwrap_err(), FsError::IsADirectory("/media".into()));

        assert!(matches!(fs.read("/media/theme.mp3"), Err(FsError::NotText(_))));
        assert_eq!(fs.read_blob("/media/theme.mp3").unwrap(), b"\x00\x01\x02bytes");

        // On a real disk a second name has to be a second file.
        fs.copy("/media/theme.mp3", "/media/copy.mp3").unwrap();
        assert_eq!(fs.read_blob("/media/copy.mp3").unwrap(), b"\x00\x01\x02bytes");
        assert!(root.join("media/theme.mp3").exists(), "copy leaves the source");

        let _ = std::fs::remove_dir_all(&root);
    }

    #[test]
    fn ini_reads_values_within_their_section() {
        let text = "[a]\r\nx=1\r\ny=2\r\n[b]\r\nx=3\r\n";
        assert_eq!(ini_get(text, "a", "x"), "1");
        assert_eq!(ini_get(text, "b", "x"), "3");
        assert_eq!(ini_get(text, "a", "z"), "", "a missing key reads empty");
        assert_eq!(ini_get(text, "c", "x"), "", "a missing section reads empty");
    }

    #[test]
    fn ini_lookup_ignores_case_and_surrounding_space() {
        let text = "[Section]\r\n Key = value \r\n";
        assert_eq!(ini_get(text, "section", "key"), "value");
    }

    #[test]
    fn ini_updates_an_existing_key_in_place() {
        let text = "[a]\r\nx=1\r\ny=2\r\n";
        let out = ini_set(text, "a", "x", "9");
        assert_eq!(ini_get(&out, "a", "x"), "9");
        assert_eq!(ini_get(&out, "a", "y"), "2", "other keys survive");
    }

    #[test]
    fn ini_adds_a_missing_key_to_an_existing_section() {
        let out = ini_set("[a]\r\nx=1\r\n[b]\r\nz=3\r\n", "a", "y", "2");
        assert_eq!(ini_get(&out, "a", "y"), "2");
        assert_eq!(ini_get(&out, "a", "x"), "1");
        assert_eq!(ini_get(&out, "b", "z"), "3", "later sections survive");
    }

    #[test]
    fn ini_adds_a_missing_section() {
        let out = ini_set("[a]\r\nx=1\r\n", "new", "k", "v");
        assert_eq!(ini_get(&out, "new", "k"), "v");
        assert_eq!(ini_get(&out, "a", "x"), "1");
    }

    #[test]
    fn ini_round_trips_through_an_empty_document() {
        let out = ini_set("", "s", "k", "v");
        assert_eq!(ini_get(&out, "s", "k"), "v");
    }
}
