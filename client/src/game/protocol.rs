//! What goes on the wire, independent of how it is sent.
//!
//! Keeping this separate from any HTTP client means the desktop build, the
//! browser build and the tests all speak the same protocol, and that the
//! protocol itself can be tested without a network.

use super::server::{ApiRequest, ResponseType, ServerResponse};

/// Where the game's API lives.
pub const DEFAULT_API_ROOT: &str = "https://darksignsonline.com/api/";

/// The protocol version this client speaks.
///
/// This header is not optional. Without it the server answers in a legacy
/// mode that prefixes every body with a four-character status code, which
/// nothing here expects.
pub const PROTOCOL_VERSION_HEADER: &str = "DSO-Protocol-Version";
pub const PROTOCOL_VERSION: &str = "2";

/// Identifies the client to the server, in the shape the VB6 client used.
pub fn user_agent(version: &str) -> String {
    format!("Mozilla/4.0 (compatible; Win32; VbAsyncSocket; DarkSignsOnline/{version})")
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Method {
    Get,
    Post,
}

/// Credentials for the game account, sent as HTTP basic auth.
#[derive(Debug, Clone, Default)]
pub struct Credentials {
    pub username: String,
    pub password: String,
}

impl Credentials {
    pub fn new(username: impl Into<String>, password: impl Into<String>) -> Credentials {
        Credentials { username: username.into(), password: password.into() }
    }

    pub fn is_set(&self) -> bool {
        !self.username.is_empty() && !self.password.is_empty()
    }
}

/// A request ready to be sent by whatever transport the build has.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct HttpRequest {
    pub url: String,
    pub method: Method,
    /// Form-encoded body, for a POST.
    pub body: String,
    pub headers: Vec<(String, String)>,
    /// Set when the request should carry basic auth.
    pub auth: Option<(String, String)>,
}

/// Build the HTTP request for an API call.
pub fn build_request(
    api_root: &str,
    request: &ApiRequest,
    credentials: &Credentials,
    client_version: &str,
) -> HttpRequest {
    let mut headers = vec![(
        PROTOCOL_VERSION_HEADER.to_string(),
        PROTOCOL_VERSION.to_string(),
    )];

    // Not in a browser. `User-Agent` is a forbidden header name: script is
    // not allowed to set it, and the browser sends its own regardless. The
    // two engines disagree about how to refuse, which is the whole problem --
    // Chromium drops it silently, while Firefox honours the call and then
    // lists `user-agent` in `Access-Control-Request-Headers`. No server that
    // does not name it back gets past the preflight, and it cannot sensibly
    // name back a header the client was never allowed to send.
    #[cfg(not(target_arch = "wasm32"))]
    headers.push(("User-Agent".to_string(), user_agent(client_version)));
    #[cfg(target_arch = "wasm32")]
    let _ = client_version;

    let (method, body) = match &request.body {
        Some(b) => {
            headers.push((
                "Content-Type".to_string(),
                "application/x-www-form-urlencoded".to_string(),
            ));
            (Method::Post, b.trim().to_string())
        }
        None => (Method::Get, String::new()),
    };

    HttpRequest {
        url: format!("{api_root}{}", request.path),
        method,
        body,
        headers,
        auth: credentials
            .is_set()
            .then(|| (credentials.username.clone(), credentials.password.clone())),
    }
}

/// The calls that can be made without an account.
///
/// `auth.php` is the login itself. Reading chat is the room the site has
/// always shown to anyone at `chatlog.php`, and answering it without an
/// account is what keeps a client watching it from making the server verify
/// a password once a second. Saying something is not on the list.
const ANONYMOUS: [&str; 2] = ["auth.php", "chat.php?action=read"];

/// Whether a call needs credentials. The client refuses to send one without
/// them rather than getting a 401 back.
pub fn requires_login(path: &str) -> bool {
    !ANONYMOUS.iter().any(|prefix| path.starts_with(prefix))
}

/// How long a complaint may get before it stops being worth reading.
const SUMMARY_LIMIT: usize = 200;

/// Drop the four-digit status code an endpoint puts in front of its answer.
///
/// Most of them stopped sending it at protocol 2. `dsmail.php`,
/// `file_database.php` and `textspace.php` did not — the first two ask for it
/// unconditionally and the third writes it by hand — so the code is part of
/// their replies and has to come off before anything else is read.
pub fn strip_code(body: &str) -> &str {
    let text = body.trim_start_matches(['\r', '\n']);
    match text.len() >= 4 && text[..4].bytes().all(|b| b.is_ascii_digit()) {
        true => &text[4..],
        false => text,
    }
}

/// A body reduced to one line, for showing a player.
///
/// The whitespace collapses and a long one is cut short, since an endpoint
/// that refuses says so in its first few words and a player is reading this
/// in a status line.
pub fn summary(body: &str) -> String {
    let mut out = String::new();
    for word in body.split_whitespace() {
        if !out.is_empty() {
            out.push(' ');
        }
        out.push_str(word);
        if out.len() >= SUMMARY_LIMIT {
            out.push('…');
            break;
        }
    }
    out
}

/// Shape a raw HTTP result the way the request asked for.
pub fn shape(code: i64, body: String, response_type: ResponseType) -> ServerResponse {
    let _ = response_type;
    ServerResponse { code, body }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn creds() -> Credentials {
        Credentials::new("user", "pass")
    }

    #[test]
    fn a_get_carries_the_version_header() {
        let req = build_request(DEFAULT_API_ROOT, &ApiRequest::get("lookup.php?d=x"), &creds(), "1.0");
        assert_eq!(req.url, "https://darksignsonline.com/api/lookup.php?d=x");
        assert_eq!(req.method, Method::Get);
        assert!(req.body.is_empty());
        assert!(
            req.headers
                .iter()
                .any(|(k, v)| k == PROTOCOL_VERSION_HEADER && v == "2"),
            "without this header the server answers in its legacy mode"
        );
    }

    #[test]
    fn a_post_is_form_encoded() {
        let req = build_request(
            DEFAULT_API_ROOT,
            &ApiRequest::post("domain_register.php", "d=example.com"),
            &creds(),
            "1.0",
        );
        assert_eq!(req.method, Method::Post);
        assert_eq!(req.body, "d=example.com");
        assert!(req
            .headers
            .iter()
            .any(|(k, v)| k == "Content-Type" && v == "application/x-www-form-urlencoded"));
    }

    #[test]
    fn credentials_are_attached_when_they_are_set() {
        let req = build_request(DEFAULT_API_ROOT, &ApiRequest::get("x"), &creds(), "1.0");
        assert_eq!(req.auth, Some(("user".into(), "pass".into())));

        let anon = build_request(DEFAULT_API_ROOT, &ApiRequest::get("x"), &Credentials::default(), "1.0");
        assert_eq!(anon.auth, None);
    }

    #[test]
    fn only_the_login_call_may_go_out_unauthenticated() {
        assert!(!requires_login("auth.php"));
        assert!(requires_login("lookup.php?d=x"));
    }

    /// Reading chat is public, so a signed-out client can still watch the
    /// room. Saying something in it is not.
    #[test]
    fn reading_chat_needs_no_account_but_saying_something_does() {
        assert!(!requires_login("chat.php?action=read&last=0"));
        assert!(requires_login("chat.php"), "a send is a POST to the bare path");
        assert!(requires_login("chat.php?action=send"));
    }

    #[test]
    fn the_user_agent_names_the_client() {
        assert_eq!(
            user_agent("1.2.3"),
            "Mozilla/4.0 (compatible; Win32; VbAsyncSocket; DarkSignsOnline/1.2.3)"
        );
    }

    /// A browser must not be handed a `User-Agent` to set. Chromium ignores
    /// the attempt, but Firefox makes it part of the preflight and then fails
    /// the request with "CORS Missing Allow Header", because no server names
    /// back a header the client had no business sending.
    #[test]
    fn user_agent_is_sent_only_where_it_is_allowed() {
        let req =
            build_request("https://example.test/api/", &ApiRequest::get("a.php"), &creds(), "1");
        let names: Vec<&str> = req.headers.iter().map(|(k, _)| k.as_str()).collect();
        assert_eq!(names.contains(&"User-Agent"), !cfg!(target_arch = "wasm32"));
        // The version header travels on every target; without it the server
        // drops into its legacy response mode.
        assert!(names.contains(&PROTOCOL_VERSION_HEADER));
    }

    #[test]
    fn the_status_code_comes_off_the_front() {
        assert_eq!(strip_code("7000X_1:--:a"), "X_1:--:a");
        assert_eq!(strip_code("success"), "success");
        // A short body is left alone rather than truncated.
        assert_eq!(strip_code("no"), "no");
    }

    #[test]
    fn a_complaint_is_reduced_to_one_line() {
        assert_eq!(summary("  Unknown name:\n  nobody  "), "Unknown name: nobody");
        let long = summary(&"word ".repeat(100));
        assert!(long.ends_with('…'), "a long one is cut short, got {long:?}");
    }

    #[test]
    fn the_api_root_is_joined_without_a_double_slash() {
        let req = build_request("https://example.test/api/", &ApiRequest::get("a.php"), &creds(), "1");
        assert_eq!(req.url, "https://example.test/api/a.php");
    }
}
