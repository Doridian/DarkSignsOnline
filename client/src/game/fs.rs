//! The in-game filesystem the local half of the host API works on.
//!
//! Scripts see a `/`-rooted tree that is really the player's directory. The
//! [`FileSystem`] trait is the seam: the desktop client backs it with real
//! files, tests back it with [`MemoryFs`].
//!
//! A file is bytes. Nothing here decides whether a path holds text, because
//! nothing here has to: the *operation* decides what it needs. `Cat` widens
//! bytes into characters, `Include` insists on UTF-8 and says so when it
//! does not get it, and `FileLen` never looks at the contents at all. That
//! is what a real filesystem does, and it is what VB6 did -- `Open ... For
//! Input` against `For Binary` was the caller's choice there too.
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

/// A file's bytes as the characters a script sees, one character per byte.
///
/// This is VB6's `Open ... For Binary` and its codepage: byte 0xE9 is
/// character U+00E9, so `Len` of what comes back is the file's length in
/// bytes and `Mid` indexes into it by byte. It is also what
/// `DecodeBase64Str` has always done, so it is not a new convention in this
/// engine -- only a newly uniform one.
///
/// The cost is that a UTF-8 file of non-ASCII text reads back as the
/// mojibake its bytes spell. It still round-trips exactly; it only displays
/// wrong. The engine's own files avoid this by declaring their encoding --
/// see [`FileSystem::read_text`].
pub fn bytes_to_text(bytes: &[u8]) -> String {
    bytes.iter().map(|&b| b as char).collect()
}

/// Characters as the bytes a file holds, the inverse of [`bytes_to_text`].
///
/// A character above U+00FF has no byte, which VB6 answered by substituting
/// through the codepage rather than refusing. `?` is what it substituted, so
/// it is what is substituted here.
pub fn text_to_bytes(text: &str) -> Vec<u8> {
    text.chars().map(|c| if (c as u32) <= 0xFF { c as u8 } else { b'?' }).collect()
}

/// The MIME type a name implies, or `None` when the name says nothing.
///
/// Nothing is classified by this any more: it decides only what to tell
/// `<audio>`, which needs a type in order to pick a decoder and gets an
/// empty one from OPFS. The tree is overwhelmingly scripts, so this lists
/// what a player would plausibly want to hear or see rather than trying to
/// be a full table.
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
///
/// Only three of these carry contents, and those three carry bytes. The rest
/// take paths and answer about the tree.
pub trait FileSystem {
    fn raw_exists(&self, path: &str) -> bool;
    fn raw_is_dir(&self, path: &str) -> bool;
    fn raw_read(&self, path: &str) -> FsResult<Vec<u8>>;
    fn raw_write(&mut self, path: &str, contents: &[u8]) -> FsResult<()>;
    fn raw_append(&mut self, path: &str, contents: &[u8]) -> FsResult<()>;
    fn raw_len(&self, path: &str) -> FsResult<i64>;
    fn raw_delete(&mut self, path: &str) -> FsResult<()>;
    fn raw_read_dir(&self, path: &str) -> FsResult<Vec<DirEntry>>;
    fn raw_make_dir(&mut self, path: &str) -> FsResult<()>;
    fn raw_remove_dir(&mut self, path: &str) -> FsResult<()>;

    /// The first `max` bytes of a file.
    ///
    /// `Cat` is the only caller, and it has a limit because a file may be a
    /// forty-megabyte song and a console asked to show one wants a
    /// screenful, not the album. Reading the lot and dropping most of it is
    /// the answer that always works; a backend that can stop early -- a real
    /// disk, or a worker that can seek -- says so by overriding this.
    fn raw_read_upto(&self, path: &str, max: usize) -> FsResult<Vec<u8>> {
        let mut bytes = self.raw_read(path)?;
        bytes.truncate(max);
        Ok(bytes)
    }

    fn exists(&self, path: &str) -> bool {
        self.raw_exists(&fold_case(path))
    }

    fn is_dir(&self, path: &str) -> bool {
        self.raw_is_dir(&fold_case(path))
    }

    fn read(&self, path: &str) -> FsResult<Vec<u8>> {
        self.raw_read(&fold_case(path))
    }

    fn read_upto(&self, path: &str, max: usize) -> FsResult<Vec<u8>> {
        self.raw_read_upto(&fold_case(path), max)
    }

    fn write(&mut self, path: &str, contents: &[u8]) -> FsResult<()> {
        self.raw_write(&fold_case(path), contents)
    }

    fn append(&mut self, path: &str, contents: &[u8]) -> FsResult<()> {
        self.raw_append(&fold_case(path), contents)
    }

    /// A file the engine wrote itself, read back as the UTF-8 it wrote.
    ///
    /// The mail store, the INI files and the library cache carry
    /// server-sourced text, and a script's source is text by definition.
    /// Those declare their encoding here rather than inheriting the byte
    /// convention scripts see, so a name or a subject with an accent in it
    /// survives. Anything that is not UTF-8 is not one of these files, and
    /// saying so is more use than handing back nonsense.
    fn read_text(&self, path: &str) -> FsResult<String> {
        let bytes = self.read(path)?;
        String::from_utf8(bytes).map_err(|_| FsError::Io(format!("Not text: {path}")))
    }

    /// Write one of those files, as UTF-8.
    fn write_text(&mut self, path: &str, contents: &str) -> FsResult<()> {
        self.write(path, contents.as_bytes())
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

    /// Copy a file, by reading it and writing it back.
    ///
    /// A backend where that means moving several megabytes through the
    /// engine for the sake of a name overrides this, the way [`DiskFs`]
    /// does.
    fn copy(&mut self, from: &str, to: &str) -> FsResult<()> {
        let data = self.read(from)?;
        self.write(to, &data)
    }

    /// Move a file, which is a copy followed by a delete.
    fn rename(&mut self, from: &str, to: &str) -> FsResult<()> {
        self.copy(from, to)?;
        self.delete(from)
    }
}

/// A filesystem held entirely in memory. It is the test double, and also
/// what a sandboxed or headless client can run on.
///
/// `nodes` is the tree: every name, and the bytes under it. There is nothing
/// beside it, because there is nothing about a file to keep beside it.
#[derive(Default)]
pub struct MemoryFs {
    nodes: BTreeMap<String, Vec<u8>>,
    dirs: std::collections::BTreeSet<String>,
}

impl MemoryFs {
    pub fn new() -> MemoryFs {
        let mut fs = MemoryFs::default();
        fs.dirs.insert("/".into());
        fs
    }

    /// Create a text file and every directory leading to it, for test setup.
    ///
    /// Panics if a directory of that name is in the way, which is a mistake
    /// in the setup rather than something to carry on from.
    pub fn with_file(mut self, path: &str, contents: &str) -> MemoryFs {
        self.write_text(path, contents).expect("no directory in the way");
        self
    }

    /// The same for a file whose contents are not text.
    pub fn with_bytes(mut self, path: &str, contents: &[u8]) -> MemoryFs {
        self.write(path, contents).expect("no directory in the way");
        self
    }

    pub fn with_dir(mut self, path: &str) -> MemoryFs {
        let path = fold_case(path);
        self.create_parents(&path);
        self.dirs.insert(path);
        self
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

    fn raw_read(&self, path: &str) -> FsResult<Vec<u8>> {
        if self.dirs.contains(path) {
            return Err(FsError::IsADirectory(path.into()));
        }
        match self.nodes.get(path) {
            Some(bytes) => Ok(bytes.clone()),
            None => Err(FsError::NotFound(path.into())),
        }
    }

    fn raw_write(&mut self, path: &str, contents: &[u8]) -> FsResult<()> {
        if self.dirs.contains(path) {
            return Err(FsError::IsADirectory(path.into()));
        }
        self.create_parents(path);
        self.nodes.insert(path.into(), contents.to_vec());
        Ok(())
    }

    fn raw_append(&mut self, path: &str, contents: &[u8]) -> FsResult<()> {
        if self.dirs.contains(path) {
            return Err(FsError::IsADirectory(path.into()));
        }
        self.create_parents(path);
        self.nodes.entry(path.into()).or_default().extend_from_slice(contents);
        Ok(())
    }

    fn raw_len(&self, path: &str) -> FsResult<i64> {
        if self.dirs.contains(path) {
            return Err(FsError::IsADirectory(path.into()));
        }
        match self.nodes.get(path) {
            Some(bytes) => Ok(bytes.len() as i64),
            None => Err(FsError::NotFound(path.into())),
        }
    }

    fn raw_delete(&mut self, path: &str) -> FsResult<()> {
        match self.nodes.remove(path) {
            Some(_) => Ok(()),
            None => Err(FsError::NotFound(path.into())),
        }
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

    fn raw_read(&self, path: &str) -> FsResult<Vec<u8>> {
        let real = self.real(path);
        if real.is_dir() {
            return Err(FsError::IsADirectory(path.into()));
        }
        std::fs::read(&real).map_err(|e| DiskFs::io(e, path))
    }

    /// Only the head comes off the disk, so `Cat` on a song costs a
    /// screenful rather than an album.
    fn raw_read_upto(&self, path: &str, max: usize) -> FsResult<Vec<u8>> {
        use std::io::Read;
        let real = self.real(path);
        if real.is_dir() {
            return Err(FsError::IsADirectory(path.into()));
        }
        let file = std::fs::File::open(&real).map_err(|e| DiskFs::io(e, path))?;
        let mut out = Vec::new();
        file.take(max as u64).read_to_end(&mut out).map_err(|e| DiskFs::io(e, path))?;
        Ok(out)
    }

    fn raw_write(&mut self, path: &str, contents: &[u8]) -> FsResult<()> {
        let real = self.real(path);
        if let Some(parent) = real.parent() {
            std::fs::create_dir_all(parent).map_err(|e| DiskFs::io(e, path))?;
        }
        std::fs::write(&real, contents).map_err(|e| DiskFs::io(e, path))
    }

    fn raw_append(&mut self, path: &str, contents: &[u8]) -> FsResult<()> {
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
        f.write_all(contents).map_err(|e| DiskFs::io(e, path))
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

    /// The disk copies for itself, so a song does not travel through the
    /// engine to be given a second name.
    fn copy(&mut self, from: &str, to: &str) -> FsResult<()> {
        let (from, to) = (fold_case(from), fold_case(to));
        let (src, dest) = (self.real(&from), self.real(&to));
        if let Some(parent) = dest.parent() {
            std::fs::create_dir_all(parent).map_err(|e| DiskFs::io(e, &to))?;
        }
        std::fs::copy(&src, &dest).map(|_| ()).map_err(|e| DiskFs::io(e, &from))
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
        assert_eq!(f.read_text("/home/a.txt").unwrap(), "alpha");
        f.write_text("/home/a.txt", "changed").unwrap();
        assert_eq!(f.read_text("/home/a.txt").unwrap(), "changed");
    }

    #[test]
    fn writing_creates_parent_directories() {
        let mut f = MemoryFs::new();
        f.write("/deep/nested/file.txt", b"x").unwrap();
        assert!(f.is_dir("/deep"));
        assert!(f.is_dir("/deep/nested"));
        assert!(f.exists("/deep/nested/file.txt"));
    }

    #[test]
    fn appending_to_a_missing_file_creates_it() {
        let mut f = MemoryFs::new();
        f.append("/log.txt", b"one").unwrap();
        f.append("/log.txt", b"two").unwrap();
        assert_eq!(f.read_text("/log.txt").unwrap(), "onetwo");
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
        assert_eq!(f.read_text("/HOME/A.TXT").unwrap(), "alpha");
        assert!(f.exists("/Home/Sub"));
        assert!(f.is_dir("/Home/Sub"));

        // Writing under another spelling rewrites the same file rather than
        // adding a second one.
        f.write_text("/Home/A.Txt", "changed").unwrap();
        assert_eq!(f.read_text("/home/a.txt").unwrap(), "changed");
        assert_eq!(f.paths(), vec!["/home/a.txt", "/home/b.txt", "/home/sub/c.txt"]);
    }

    #[test]
    fn a_new_file_is_stored_under_its_folded_name() {
        let mut f = MemoryFs::new();
        f.write_text("/Home/Notes/TODO.TXT", "x").unwrap();
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
        assert_eq!(f.read_text("/home/copy.txt").unwrap(), "alpha");
        assert!(f.exists("/home/a.txt"), "copy leaves the source");

        f.rename("/home/copy.txt", "/home/moved.txt").unwrap();
        assert_eq!(f.read_text("/home/moved.txt").unwrap(), "alpha");
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

        fs.write_text("/a/b.txt", "inside").unwrap();
        assert_eq!(fs.read_text("/a/b.txt").unwrap(), "inside");
        assert!(root.join("a/b.txt").exists());

        // A path that tries to climb out lands back at the root.
        fs.write_text("/../escaped.txt", "still inside").unwrap();
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

        fs.write_text("/Dir/One.TXT", "1").unwrap();
        assert!(root.join("dir/one.txt").exists(), "stored folded");
        assert_eq!(fs.read_text("/DIR/ONE.txt").unwrap(), "1");

        let _ = std::fs::remove_dir_all(&root);
    }

    #[test]
    #[cfg(not(target_arch = "wasm32"))]
    fn the_disk_filesystem_lists_and_removes() {
        let root = std::env::temp_dir().join(format!("dso-fs2-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&root);
        std::fs::create_dir_all(&root).unwrap();
        let mut fs = DiskFs::new(&root);

        fs.write_text("/dir/one.txt", "1").unwrap();
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

    // ---- bytes -----------------------------------------------------------
    //
    // A song is a file like any other, and the only thing that used to make
    // it different -- a kind stored beside it -- is gone. What is left is
    // that its bytes are not text, which every one of these calls either
    // does not care about or says plainly at the point of caring.

    const SONG: &[u8] = b"ID3\x04\x00\xffnonsense";

    fn with_song() -> MemoryFs {
        fs().with_bytes("/home/theme.mp3", SONG)
    }

    #[test]
    fn a_song_is_a_file_in_the_same_tree() {
        let f = with_song();
        assert!(f.exists("/home/theme.mp3"));
        assert!(!f.is_dir("/home/theme.mp3"));
        let names: Vec<String> =
            f.read_dir("/home").unwrap().iter().map(|e| e.display_name()).collect();
        assert_eq!(names, vec!["a.txt", "b.txt", "sub/", "theme.mp3"]);
    }

    #[test]
    fn a_song_reports_its_size_in_bytes() {
        assert_eq!(with_song().len("/home/theme.mp3").unwrap(), 14);
    }

    #[test]
    fn reading_a_song_gives_its_bytes() {
        assert_eq!(with_song().read("/home/theme.mp3").unwrap(), SONG);
    }

    #[test]
    fn appending_to_a_song_appends_bytes() {
        let mut f = with_song();
        f.append("/home/theme.mp3", b"\xff\xfe").unwrap();
        assert_eq!(f.read("/home/theme.mp3").unwrap(), b"ID3\x04\x00\xffnonsense\xff\xfe");
    }

    #[test]
    fn copying_and_renaming_a_song_keeps_its_bytes() {
        let mut f = with_song();
        f.copy("/home/theme.mp3", "/home/sub/copy.mp3").unwrap();
        assert_eq!(f.read("/home/sub/copy.mp3").unwrap(), SONG);
        assert_eq!(f.read("/home/theme.mp3").unwrap(), SONG, "copy leaves the source");

        f.rename("/home/sub/copy.mp3", "/home/moved.mp3").unwrap();
        assert!(!f.exists("/home/sub/copy.mp3"));
        assert_eq!(f.read("/home/moved.mp3").unwrap(), SONG);
    }

    #[test]
    fn a_song_read_as_the_engines_own_text_says_it_is_not() {
        assert!(matches!(
            with_song().read_text("/home/theme.mp3"),
            Err(FsError::Io(_))
        ));
    }

    #[test]
    fn cat_reads_only_the_head_of_a_long_file() {
        let f = MemoryFs::new().with_bytes("/big", &vec![b'x'; 4096]);
        assert_eq!(f.read_upto("/big", 10).unwrap(), b"xxxxxxxxxx");
        assert_eq!(f.read_upto("/big", 99_999).unwrap().len(), 4096, "a short file is all of it");
    }

    #[test]
    fn every_byte_survives_a_round_trip_through_a_file() {
        let all: Vec<u8> = (0..=255u8).collect();
        let mut f = MemoryFs::new();
        f.write("/bytes.bin", &all).unwrap();

        // What a script sees: one character per byte, so `Len` is the file's
        // length and indexing into it is indexing into the file.
        let text = bytes_to_text(&f.read("/bytes.bin").unwrap());
        assert_eq!(text.chars().count(), 256);
        assert!(text.chars().enumerate().all(|(i, c)| c as u32 == i as u32));

        // And writing those characters back puts the same bytes on disk.
        f.write("/again.bin", &text_to_bytes(&text)).unwrap();
        assert_eq!(f.read("/again.bin").unwrap(), all);
    }

    #[test]
    fn a_character_with_no_byte_is_substituted_as_vb_did() {
        assert_eq!(text_to_bytes("caf\u{e9} \u{4e2d}"), b"caf\xe9 ?");
    }

    #[test]
    fn names_of_files_holding_bytes_are_folded_like_any_other() {
        let f = fs().with_bytes("/Home/Theme.MP3", b"bytes");
        assert_eq!(
            f.paths(),
            vec!["/home/a.txt", "/home/b.txt", "/home/sub/c.txt", "/home/theme.mp3"]
        );
        assert_eq!(f.read("/HOME/THEME.MP3").unwrap(), b"bytes");
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
    fn the_disk_filesystem_reads_and_copies_bytes() {
        let root = std::env::temp_dir().join(format!("dso-fs4-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&root);
        std::fs::create_dir_all(&root).unwrap();
        let mut fs = DiskFs::new(&root);

        std::fs::create_dir_all(root.join("media")).unwrap();
        std::fs::write(root.join("media/theme.mp3"), b"\x00\x01\xffbytes").unwrap();

        assert_eq!(fs.len("/media/theme.mp3").unwrap(), 8);
        assert_eq!(fs.read("/media/theme.mp3").unwrap(), b"\x00\x01\xffbytes");
        assert_eq!(fs.read_upto("/media/theme.mp3", 3).unwrap(), b"\x00\x01\xff");
        assert!(matches!(fs.read_text("/media/theme.mp3"), Err(FsError::Io(_))));
        assert_eq!(fs.read("/media").unwrap_err(), FsError::IsADirectory("/media".into()));

        fs.copy("/media/theme.mp3", "/media/copy.mp3").unwrap();
        assert_eq!(fs.read("/media/copy.mp3").unwrap(), b"\x00\x01\xffbytes");
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
