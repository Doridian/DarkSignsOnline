//! What an endpoint can know about the request: `$_GET`, `$_POST`,
//! `$_REQUEST`, the protocol version header, Basic auth and the caller's
//! address.

use std::collections::HashMap;

use crate::php::{self, Zv};

/// PHP's `post_max_size` in the production php.ini. A larger body is not
/// parsed at all, the way PHP drops `$_POST` rather than truncating it.
pub const POST_MAX_SIZE: usize = 8 * 1024 * 1024;

#[derive(Default)]
pub struct Request {
    pub method: String,
    pub path: String,
    get: HashMap<Vec<u8>, Vec<u8>>,
    post: HashMap<Vec<u8>, Vec<u8>>,
    /// The protocol version header, duplicates joined the way nginx joins
    /// them, or `None` when it was not sent.
    pub protocol_version: Option<Vec<u8>>,
    pub authorization: Option<Vec<u8>>,
    pub remote_addr: String,
}

/// `application/x-www-form-urlencoded`: `&`-separated pairs, a pair with no
/// `=` has an empty value, and the last of a repeated name wins.
fn parse_urlencoded(s: &[u8], into: &mut HashMap<Vec<u8>, Vec<u8>>) {
    for pair in s.split(|&c| c == b'&').filter(|p| !p.is_empty()) {
        let (name, value) = match pair.iter().position(|&c| c == b'=') {
            Some(i) => (&pair[..i], &pair[i + 1..]),
            None => (pair, &b""[..]),
        };
        let name = php::url_decode(name);
        if !name.is_empty() {
            into.insert(name, php::url_decode(value));
        }
    }
}

impl Request {
    pub fn new(
        method: String,
        path: String,
        query: Option<&str>,
        content_type: Option<&[u8]>,
        body: Option<&[u8]>,
    ) -> Request {
        let mut req = Request {
            method,
            path,
            ..Default::default()
        };
        if let Some(q) = query {
            parse_urlencoded(q.as_bytes(), &mut req.get);
        }
        // PHP only reads a form out of a POST, and only one that says it is
        // a form; anything after a `;` is parameters it does not look at.
        let is_form = content_type.is_some_and(|ct| {
            let mime = ct.split(|&c| c == b';' || c == b',' || c == b' ').next().unwrap_or(b"");
            mime.eq_ignore_ascii_case(b"application/x-www-form-urlencoded")
        });
        if req.method == "POST"
            && is_form
            && let Some(body) = body
        {
            parse_urlencoded(body, &mut req.post);
        }
        req
    }

    fn lookup(map: &HashMap<Vec<u8>, Vec<u8>>, name: &str) -> Zv {
        map.get(name.as_bytes()).map_or(Zv::Null, |v| Zv::Str(v.clone()))
    }

    /// `$_GET[name]`, NULL when absent.
    pub fn get(&self, name: &str) -> Zv {
        Self::lookup(&self.get, name)
    }

    /// `$_POST[name]`.
    pub fn post(&self, name: &str) -> Zv {
        Self::lookup(&self.post, name)
    }

    /// `$_REQUEST[name]`: `request_order` is "GP", so a POST value wins.
    pub fn request(&self, name: &str) -> Zv {
        match self.post(name) {
            Zv::Null => self.get(name),
            v => v,
        }
    }

    /// `PHP_AUTH_USER` and `PHP_AUTH_PW`, as PHP takes them out of a Basic
    /// `Authorization` header: the scheme is matched without regard to case,
    /// the credentials are decoded leniently, and the user is everything up
    /// to the first colon.
    pub fn basic_auth(&self) -> Option<(Vec<u8>, Vec<u8>)> {
        let auth = self.authorization.as_deref()?;
        if auth.len() < 6 || !auth[..6].eq_ignore_ascii_case(b"Basic ") {
            return None;
        }
        let decoded = php::base64_decode(&auth[6..]);
        let colon = decoded.iter().position(|&c| c == b':')?;
        Some((decoded[..colon].to_vec(), decoded[colon + 1..].to_vec()))
    }

    /// `$ver`: the protocol version header, else `?dso_version=`, and never
    /// less than 1.
    pub fn protocol_version(&self) -> i64 {
        let header = self.protocol_version.clone().map_or(Zv::Null, Zv::Str);
        let ver = if !header.is_empty() {
            header.to_int()
        } else {
            let q = self.get("dso_version");
            if !q.is_empty() { q.to_int() } else { 0 }
        };
        ver.max(1)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn post_wins_and_forms_only() {
        let req = Request::new(
            "POST".into(),
            "/".into(),
            Some("a=1&b=2&&c&d=%41+%zz"),
            Some(b"Application/X-WWW-Form-Urlencoded; charset=UTF-8"),
            Some(b"b=3"),
        );
        assert_eq!(req.request("a"), Zv::str("1"));
        assert_eq!(req.request("b"), Zv::str("3"));
        assert_eq!(req.get("b"), Zv::str("2"));
        assert_eq!(req.request("c"), Zv::str(""));
        assert_eq!(req.request("d"), Zv::str("A %zz"));
        assert_eq!(req.request("e"), Zv::Null);

        let put = Request::new(
            "PUT".into(),
            "/".into(),
            None,
            Some(b"application/x-www-form-urlencoded"),
            Some(b"b=3"),
        );
        assert_eq!(put.request("b"), Zv::Null);
    }

    #[test]
    fn basic_auth_like_php() {
        let mut req = Request {
            authorization: Some(b"basic dXNlcjpwYTpzcw==".to_vec()),
            ..Default::default()
        };
        assert_eq!(req.basic_auth(), Some((b"user".to_vec(), b"pa:ss".to_vec())));
        req.authorization = Some(b"Bearer dXNlcjpwYXNz".to_vec());
        assert_eq!(req.basic_auth(), None);
    }

    #[test]
    fn version_defaults_to_one() {
        let mut req = Request::new("GET".into(), "/".into(), Some("dso_version=2"), None, None);
        assert_eq!(req.protocol_version(), 2);
        req.protocol_version = Some(b"0".to_vec());
        assert_eq!(req.protocol_version(), 2);
        req.protocol_version = Some(b"3".to_vec());
        assert_eq!(req.protocol_version(), 3);
        req.protocol_version = Some(b"-4".to_vec());
        assert_eq!(req.protocol_version(), 1);
    }
}
