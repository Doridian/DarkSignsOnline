//! The website's static files and the browser client, out of the directory
//! `DSO_WWW` names: what nginx used to serve, under the same rules.
//!
//! The client lives under `/game/`, whose `index.html` is the page, and two
//! things about how it is served are not optional.
//!
//! **Everything under `/game/` is cross-origin isolated.** Without
//! `Cross-Origin-Opener-Policy` and `Cross-Origin-Embedder-Policy` the
//! browser withholds `SharedArrayBuffer`, and the client's workers use
//! `Atomics.wait` to block while a script waits for input, so nothing runs.
//! They go on every file, not just the page: a dedicated worker inherits the
//! document's embedder policy and the browser refuses a worker script whose
//! own response does not repeat it -- and WebKit applies that to the whole
//! module graph, so every script `worker.js` statically imports needs the
//! headers too. Chromium and Firefox enforce it on the top-level worker
//! script alone, so a host that gets this wrong works everywhere but iOS.
//!
//! **The page is `no-cache` and its assets are `immutable`.** Every asset is
//! named for the hash of what is in it (`client/web/stamp.ts`), so its URL
//! can never come to mean anything else. The page is the one name that stays
//! put, so it is the one a browser has to ask about again -- and it has to
//! be asked about with nothing that could answer "no change". These files
//! come out of the nix store, where every mtime is the epoch, and
//! `index.html` does not change size when a deploy changes what it points
//! at. A validator made of those (nginx's `ETag` and `Last-Modified` were)
//! gets a `304` for a genuinely new build, and the browser keeps naming the
//! previous build's assets for as long as it caches them, which is a year.
//! So no response here carries a validator at all.

use std::path::{Path, PathBuf};

use bytes::Bytes;
use http_body_util::Full;
use hyper::header::HeaderValue;
use hyper::{Method, Response, StatusCode};

const GAME: &str = "/game/";
const GAME_PAGE: &str = "/game/index.html";

/// The media type for a file, by its extension. What nginx's `mime.types`
/// said for every kind of file the site ships.
fn content_type(path: &str) -> &'static str {
    let name = path.rsplit('/').next().unwrap_or("");
    let ext = match name.rsplit_once('.') {
        Some((_, ext)) => ext.to_ascii_lowercase(),
        None if name == "LICENSE" => return "text/plain; charset=utf-8",
        None => return "application/octet-stream",
    };
    match ext.as_str() {
        "html" | "htm" => "text/html; charset=utf-8",
        "css" => "text/css; charset=utf-8",
        "js" | "mjs" => "text/javascript; charset=utf-8",
        "json" => "application/json; charset=utf-8",
        "wasm" => "application/wasm",
        "txt" | "ds" | "py" => "text/plain; charset=utf-8",
        "png" => "image/png",
        "jpg" | "jpeg" => "image/jpeg",
        "gif" => "image/gif",
        "svg" => "image/svg+xml",
        "ico" => "image/x-icon",
        "zip" => "application/zip",
        "woff2" => "font/woff2",
        "woff" => "font/woff",
        "ttf" => "font/ttf",
        _ => "application/octet-stream",
    }
}

/// The headers a file gets for where it is: see the module comment.
fn policy_headers(path: &str) -> &'static [(&'static str, &'static str)] {
    const ISOLATED_PAGE: &[(&str, &str)] = &[
        ("cross-origin-opener-policy", "same-origin"),
        ("cross-origin-embedder-policy", "require-corp"),
        ("cache-control", "no-cache"),
    ];
    const ISOLATED_ASSET: &[(&str, &str)] = &[
        ("cross-origin-opener-policy", "same-origin"),
        ("cross-origin-embedder-policy", "require-corp"),
        ("cache-control", "public, max-age=31536000, immutable"),
    ];
    if path == GAME_PAGE {
        ISOLATED_PAGE
    } else if path.starts_with(GAME) {
        ISOLATED_ASSET
    } else {
        &[]
    }
}

fn unhex(c: u8) -> Option<u8> {
    match c {
        b'0'..=b'9' => Some(c - b'0'),
        b'a'..=b'f' => Some(c - b'a' + 10),
        b'A'..=b'F' => Some(c - b'A' + 10),
        _ => None,
    }
}

/// A request path as the segments of a file under the root: percent-decoded,
/// with `.` and empty segments dropped and `..` taking one back, never past
/// the root. `None` for a path that names no file anyone could have put
/// there.
fn segments(path: &str) -> Option<Vec<String>> {
    let raw = path.as_bytes();
    let mut decoded = Vec::with_capacity(raw.len());
    let mut i = 0;
    while i < raw.len() {
        if raw[i] == b'%' {
            let hi = unhex(*raw.get(i + 1)?)?;
            let lo = unhex(*raw.get(i + 2)?)?;
            decoded.push(hi << 4 | lo);
            i += 3;
        } else {
            decoded.push(raw[i]);
            i += 1;
        }
    }
    let decoded = String::from_utf8(decoded).ok()?;
    let mut out: Vec<String> = Vec::new();
    for seg in decoded.split('/') {
        match seg {
            "" | "." => {}
            ".." => {
                out.pop();
            }
            _ if seg.contains('\0') => return None,
            _ => out.push(seg.to_string()),
        }
    }
    Some(out)
}

/// What a request for `path` under `root` gets, or `None` for a 404.
pub async fn serve(root: &Path, method: &Method, path: &str, query: Option<&str>) -> Option<Response<Full<Bytes>>> {
    let segs = segments(path)?;
    let mut file: PathBuf = root.to_path_buf();
    file.extend(&segs);
    let mut logical = format!("/{}", segs.join("/"));

    let mut meta = tokio::fs::metadata(&file).await.ok()?;
    if meta.is_dir() {
        // A directory is its `index.html`, and only with the slash: the
        // page's relative URLs resolve against the document's own address,
        // so `/game` has to become `/game/` before `./main.js` can mean
        // `/game/main.js`.
        if !path.ends_with('/') {
            let location = match query {
                Some(q) => format!("{path}/?{q}"),
                None => format!("{path}/"),
            };
            let mut resp = Response::new(Full::new(Bytes::new()));
            *resp.status_mut() = StatusCode::MOVED_PERMANENTLY;
            resp.headers_mut()
                .insert("location", HeaderValue::try_from(location).ok()?);
            return Some(resp);
        }
        file.push("index.html");
        if !logical.ends_with('/') {
            logical.push('/');
        }
        logical.push_str("index.html");
        meta = tokio::fs::metadata(&file).await.ok()?;
    }
    if !meta.is_file() {
        return None;
    }

    if method != Method::GET && method != Method::HEAD {
        let mut resp = Response::new(Full::new(Bytes::new()));
        *resp.status_mut() = StatusCode::METHOD_NOT_ALLOWED;
        resp.headers_mut()
            .insert("allow", HeaderValue::from_static("GET, HEAD"));
        return Some(resp);
    }

    let body = tokio::fs::read(&file).await.ok()?;
    let mut resp = Response::new(Full::new(Bytes::from(body)));
    let headers = resp.headers_mut();
    headers.insert("content-type", HeaderValue::from_static(content_type(&logical)));
    for (name, value) in policy_headers(&logical) {
        headers.insert(*name, HeaderValue::from_static(value));
    }
    Some(resp)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn paths_stay_under_the_root() {
        assert_eq!(segments("/game/main.js").unwrap(), ["game", "main.js"]);
        assert_eq!(segments("/../../etc/passwd").unwrap(), ["etc", "passwd"]);
        assert_eq!(segments("/game/%2e%2e/%2E%2E/x").unwrap(), ["x"]);
        assert_eq!(segments("//game/./a%20b").unwrap(), ["game", "a b"]);
        assert_eq!(segments("/a%00b"), None);
        assert_eq!(segments("/a%zz"), None);
        assert_eq!(segments("/a%ff"), None);
    }

    #[test]
    fn the_page_is_revalidated_and_its_assets_are_not() {
        let cache = |p| {
            policy_headers(p)
                .iter()
                .find(|(k, _)| *k == "cache-control")
                .map(|(_, v)| *v)
        };
        assert_eq!(cache("/game/index.html"), Some("no-cache"));
        assert_eq!(
            cache("/game/main.0123456789ab.js"),
            Some("public, max-age=31536000, immutable")
        );
        assert_eq!(cache("/main.css"), None);
        assert!(
            policy_headers("/game/pkg/dso_web.0123456789ab.js")
                .iter()
                .any(|(k, v)| *k == "cross-origin-embedder-policy" && *v == "require-corp")
        );
    }

    #[test]
    fn types() {
        assert_eq!(content_type("/game/pkg/dso_web_bg.0123.wasm"), "application/wasm");
        assert_eq!(content_type("/LICENSE"), "text/plain; charset=utf-8");
        assert_eq!(content_type("/dso.zip"), "application/zip");
    }

    #[tokio::test]
    async fn directories_redirect_to_their_slash() {
        let root = std::env::temp_dir().join(format!("dso-www-test-{}", std::process::id()));
        std::fs::create_dir_all(root.join("game")).unwrap();
        std::fs::write(root.join("game/index.html"), "page").unwrap();

        let resp = serve(&root, &Method::GET, "/game", Some("x=1")).await.unwrap();
        assert_eq!(resp.status(), StatusCode::MOVED_PERMANENTLY);
        assert_eq!(resp.headers()["location"], "/game/?x=1");

        let resp = serve(&root, &Method::GET, "/game/", None).await.unwrap();
        assert_eq!(resp.status(), StatusCode::OK);
        assert_eq!(resp.headers()["cache-control"], "no-cache");
        assert!(resp.headers().get("etag").is_none());
        assert!(resp.headers().get("last-modified").is_none());

        assert!(serve(&root, &Method::GET, "/game/nope.js", None).await.is_none());
        let resp = serve(&root, &Method::POST, "/game/index.html", None).await.unwrap();
        assert_eq!(resp.status(), StatusCode::METHOD_NOT_ALLOWED);
        std::fs::remove_dir_all(&root).unwrap();
    }
}
