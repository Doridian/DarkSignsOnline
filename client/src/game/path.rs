//! Path resolution for the in-game filesystem, ported from
//! `basCommands.ResolvePathRel`.
//!
//! Game paths are `/`-separated and rooted at the player's directory.
//! Backslashes are accepted as separators because the VB6 client ran on
//! Windows and scripts were written both ways. For the same reason paths are
//! case-insensitive, so resolving one also folds its case -- see
//! [`fold_case`].

/// Fold a path to the one spelling the filesystem stores it under.
///
/// The VB6 client ran on Windows, where `/Home/A.TXT` and `/home/a.txt` are
/// the same file, and scripts were written accordingly. Rather than search
/// case-insensitively at every lookup, every path is folded on the way in
/// and the backing store only ever holds the folded form, so a lookup stays
/// a plain string comparison and a listing shows one spelling of a name
/// instead of whichever the writer happened to type.
///
/// ASCII only, which is the folding the interpreter uses for identifiers,
/// and it keeps a path the same length however it is spelled.
pub fn fold_case(path: &str) -> String {
    path.to_ascii_lowercase()
}

/// Resolve `path` against `base`, collapsing `.` and `..` segments and
/// folding the result's case.
///
/// A path starting with `/` or `\` is absolute and ignores `base`. The
/// result keeps a leading `/` when absolute and a leading `./` when not,
/// matching what the client stores in the console's working directory.
pub fn resolve_rel(base: &str, path: &str) -> String {
    if path.is_empty() {
        return fold_case(base);
    }

    let joined = if path.starts_with('/') || path.starts_with('\\') {
        path.to_string()
    } else {
        format!("{base}/{path}")
    };

    let joined = fold_case(&joined.replace('\\', "/"));
    // A leading `/` marks the path absolute; the flag survives the split.
    let absolute = joined.starts_with('/');

    let mut parts: Vec<&str> = Vec::new();
    for segment in joined.split('/') {
        match segment {
            // Empty segments come from `//`, which collapses.
            "" | "." => {}
            ".." => {
                parts.pop();
            }
            other => parts.push(other),
        }
    }

    if parts.is_empty() {
        return "/".into();
    }
    if absolute {
        format!("/{}", parts.join("/"))
    } else {
        format!("./{}", parts.join("/"))
    }
}

/// The script-facing `ResolvePathRel`, which additionally drops a trailing
/// slash and never returns an empty string.
pub fn resolve_rel_trimmed(base: &str, path: &str) -> String {
    let mut out = resolve_rel(base, path);
    if out.len() > 1 && out.ends_with('/') {
        out.pop();
    }
    if out.is_empty() {
        out.push('/');
    }
    out
}

/// Split a path into its parent and final component.
pub fn split_parent(path: &str) -> (&str, &str) {
    match path.rfind('/') {
        Some(0) => ("/", &path[1..]),
        Some(i) => (&path[..i], &path[i + 1..]),
        None => ("", path),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn absolute_paths_ignore_the_base() {
        assert_eq!(resolve_rel("/home", "/system/x"), "/system/x");
        assert_eq!(resolve_rel("/home", "\\system\\x"), "/system/x");
    }

    #[test]
    fn relative_paths_hang_off_the_base() {
        assert_eq!(resolve_rel("/home", "x"), "/home/x");
        assert_eq!(resolve_rel("/home/sub", "a/b"), "/home/sub/a/b");
    }

    #[test]
    fn dot_segments_collapse() {
        assert_eq!(resolve_rel("/home", "./x"), "/home/x");
        assert_eq!(resolve_rel("/home/sub", "../x"), "/home/x");
        assert_eq!(resolve_rel("/home", "a/../b"), "/home/b");
        assert_eq!(resolve_rel("/home", "a/./b/../c"), "/home/a/c");
    }

    #[test]
    fn repeated_separators_collapse() {
        assert_eq!(resolve_rel("/home", "a//b"), "/home/a/b");
        assert_eq!(resolve_rel("/", "//a"), "/a");
    }

    #[test]
    fn walking_above_the_root_stops_there() {
        assert_eq!(resolve_rel("/", "../.."), "/");
        assert_eq!(resolve_rel("/home", "../../../x"), "/x");
    }

    #[test]
    fn an_empty_path_returns_the_base() {
        assert_eq!(resolve_rel("/home", ""), "/home");
    }

    #[test]
    fn a_relative_base_keeps_its_dot_prefix() {
        assert_eq!(resolve_rel("home", "x"), "./home/x");
    }

    #[test]
    fn the_trimmed_form_drops_a_trailing_slash() {
        assert_eq!(resolve_rel_trimmed("/home", "sub/"), "/home/sub");
        // The root keeps its slash.
        assert_eq!(resolve_rel_trimmed("/", "/"), "/");
        assert_eq!(resolve_rel_trimmed("/home", ".."), "/");
    }

    #[test]
    fn resolving_folds_case() {
        assert_eq!(resolve_rel("/home", "Notes.TXT"), "/home/notes.txt");
        assert_eq!(resolve_rel("/Home/Sub", "../X"), "/home/x");
        // The base is folded too, even where it is all the answer is.
        assert_eq!(resolve_rel("/Home", ""), "/home");
        assert_eq!(resolve_rel_trimmed("/Home", "Sub/"), "/home/sub");
    }

    #[test]
    fn splits_parent_from_name() {
        assert_eq!(split_parent("/a/b/c"), ("/a/b", "c"));
        assert_eq!(split_parent("/a"), ("/", "a"));
        assert_eq!(split_parent("a"), ("", "a"));
    }
}
