//! The in-game filesystem the local half of the host API works on.
//!
//! Scripts see a `/`-rooted tree that is really the player's directory. The
//! [`FileSystem`] trait is the seam: the desktop client backs it with real
//! files, tests back it with [`MemoryFs`].

use std::collections::BTreeMap;

use super::path::split_parent;

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

pub trait FileSystem {
    fn exists(&self, path: &str) -> bool;
    fn is_dir(&self, path: &str) -> bool;
    fn read(&self, path: &str) -> FsResult<String>;
    fn write(&mut self, path: &str, contents: &str) -> FsResult<()>;
    fn append(&mut self, path: &str, contents: &str) -> FsResult<()>;
    fn len(&self, path: &str) -> FsResult<i64>;
    fn delete(&mut self, path: &str) -> FsResult<()>;
    fn read_dir(&self, path: &str) -> FsResult<Vec<DirEntry>>;
    fn make_dir(&mut self, path: &str) -> FsResult<()>;
    fn remove_dir(&mut self, path: &str) -> FsResult<()>;

    /// Copy a file. The default implementation reads and writes, which suits
    /// any backing store.
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
#[derive(Default)]
pub struct MemoryFs {
    files: BTreeMap<String, String>,
    dirs: std::collections::BTreeSet<String>,
}

impl MemoryFs {
    pub fn new() -> MemoryFs {
        let mut fs = MemoryFs::default();
        fs.dirs.insert("/".into());
        fs
    }

    /// Create a file and every directory leading to it, for test setup.
    pub fn with_file(mut self, path: &str, contents: &str) -> MemoryFs {
        self.create_parents(path);
        self.files.insert(path.to_string(), contents.to_string());
        self
    }

    pub fn with_dir(mut self, path: &str) -> MemoryFs {
        self.create_parents(path);
        self.dirs.insert(path.to_string());
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
        self.files.keys().map(|s| s.as_str()).collect()
    }
}

impl FileSystem for MemoryFs {
    fn exists(&self, path: &str) -> bool {
        self.files.contains_key(path) || self.dirs.contains(path)
    }

    fn is_dir(&self, path: &str) -> bool {
        self.dirs.contains(path)
    }

    fn read(&self, path: &str) -> FsResult<String> {
        if self.dirs.contains(path) {
            return Err(FsError::IsADirectory(path.into()));
        }
        self.files
            .get(path)
            .cloned()
            .ok_or_else(|| FsError::NotFound(path.into()))
    }

    fn write(&mut self, path: &str, contents: &str) -> FsResult<()> {
        if self.dirs.contains(path) {
            return Err(FsError::IsADirectory(path.into()));
        }
        self.create_parents(path);
        self.files.insert(path.into(), contents.into());
        Ok(())
    }

    fn append(&mut self, path: &str, contents: &str) -> FsResult<()> {
        if self.dirs.contains(path) {
            return Err(FsError::IsADirectory(path.into()));
        }
        self.create_parents(path);
        self.files.entry(path.into()).or_default().push_str(contents);
        Ok(())
    }

    fn len(&self, path: &str) -> FsResult<i64> {
        self.read(path).map(|c| c.len() as i64)
    }

    fn delete(&mut self, path: &str) -> FsResult<()> {
        self.files
            .remove(path)
            .map(|_| ())
            .ok_or_else(|| FsError::NotFound(path.into()))
    }

    fn read_dir(&self, path: &str) -> FsResult<Vec<DirEntry>> {
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
        for f in self.files.keys() {
            if split_parent(f).0 == path {
                out.push(DirEntry { name: split_parent(f).1.into(), is_dir: false });
            }
        }
        out.sort_by(|a, b| a.name.cmp(&b.name));
        Ok(out)
    }

    fn make_dir(&mut self, path: &str) -> FsResult<()> {
        if self.exists(path) {
            return Err(FsError::AlreadyExists(path.into()));
        }
        self.create_parents(path);
        self.dirs.insert(path.into());
        Ok(())
    }

    fn remove_dir(&mut self, path: &str) -> FsResult<()> {
        if !self.dirs.contains(path) {
            return Err(FsError::NotADirectory(path.into()));
        }
        if !self.read_dir(path)?.is_empty() {
            return Err(FsError::NotEmpty(path.into()));
        }
        self.dirs.remove(path);
        Ok(())
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
