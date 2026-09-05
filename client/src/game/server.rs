//! The game server, and the asynchronous request handles scripts pass around.
//!
//! Every networked host function funnels through the client's
//! `DoDownloadAPI`: it starts an HTTP request and immediately returns a
//! handle, which the script later resolves with `WaitFor`. That gives the
//! whole networked surface a single seam, [`GameServer`].

use super::values::INVISIBLE_CHAR;

/// Identifies an in-flight request.
pub type RequestId = i64;

/// A request to the game's HTTP API.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ApiRequest {
    /// Path and query below the API root, e.g. `ping.php?domain=x&port=0`.
    pub path: String,
    /// Body to POST, or `None` for a GET.
    pub body: Option<String>,
    /// The client's `ResponseType` hint, which selects how the server
    /// formats its answer (`bool_1` and so on).
    pub response_type: String,
}

impl ApiRequest {
    pub fn get(path: impl Into<String>) -> ApiRequest {
        ApiRequest { path: path.into(), body: None, response_type: String::new() }
    }
    pub fn with_response_type(mut self, t: &str) -> ApiRequest {
        self.response_type = t.into();
        self
    }
    pub fn post(path: impl Into<String>, body: impl Into<String>) -> ApiRequest {
        ApiRequest {
            path: path.into(),
            body: Some(body.into()),
            response_type: String::new(),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ServerResponse {
    pub code: i64,
    pub body: String,
}

impl ServerResponse {
    pub fn ok(body: impl Into<String>) -> ServerResponse {
        ServerResponse { code: 200, body: body.into() }
    }
}

pub trait GameServer {
    /// Start a request and return its handle.
    fn send(&mut self, request: ApiRequest) -> RequestId;

    /// Wait for a request to finish.
    fn wait(&mut self, id: RequestId) -> ServerResponse;

    /// Whether the player is logged in, which gates the account functions.
    fn is_logged_in(&self) -> bool {
        false
    }

    /// The signed-in account name.
    fn username(&self) -> String {
        String::new()
    }
}

/// Wrap a request id in the string form scripts pass around.
pub fn encode_handle(id: RequestId) -> String {
    format!("HTTPRequest{INVISIBLE_CHAR}({id})")
}

/// Read a request id back out of a handle, or `None` if the text is just an
/// ordinary string. `WaitFor` returns such strings unchanged.
pub fn decode_handle(text: &str) -> Option<RequestId> {
    let prefix = format!("HTTPRequest{INVISIBLE_CHAR}(");
    let inner = text.strip_prefix(&prefix)?.strip_suffix(')')?;
    inner.parse().ok()
}

/// A server that answers from a canned table and records what it was asked.
///
/// Responses are matched by substring against the request path, so a test
/// can key on `ping.php` without spelling out the whole query.
#[derive(Default)]
pub struct ScriptedServer {
    rules: Vec<(String, ServerResponse)>,
    /// Every request made, in order.
    pub requests: Vec<ApiRequest>,
    pending: std::collections::BTreeMap<RequestId, ApiRequest>,
    next_id: RequestId,
    pub logged_in: bool,
    pub user: String,
    /// Returned when no rule matches.
    pub default_response: Option<ServerResponse>,
}

impl ScriptedServer {
    pub fn new() -> ScriptedServer {
        ScriptedServer { next_id: 1, ..Default::default() }
    }

    /// Answer any request whose path contains `needle` with `body`.
    pub fn answer(mut self, needle: &str, body: &str) -> ScriptedServer {
        self.rules.push((needle.into(), ServerResponse::ok(body)));
        self
    }

    pub fn answer_with(mut self, needle: &str, response: ServerResponse) -> ScriptedServer {
        self.rules.push((needle.into(), response));
        self
    }

    pub fn logged_in_as(mut self, user: &str) -> ScriptedServer {
        self.logged_in = true;
        self.user = user.into();
        self
    }

    /// Paths of the requests made so far.
    pub fn paths(&self) -> Vec<&str> {
        self.requests.iter().map(|r| r.path.as_str()).collect()
    }
}

impl GameServer for ScriptedServer {
    fn send(&mut self, request: ApiRequest) -> RequestId {
        let id = self.next_id;
        self.next_id += 1;
        self.requests.push(request.clone());
        self.pending.insert(id, request);
        id
    }

    fn wait(&mut self, id: RequestId) -> ServerResponse {
        let Some(request) = self.pending.remove(&id) else {
            return ServerResponse { code: 404, body: String::new() };
        };
        for (needle, response) in &self.rules {
            if request.path.contains(needle.as_str()) {
                return response.clone();
            }
        }
        self.default_response
            .clone()
            .unwrap_or_else(|| ServerResponse::ok(""))
    }

    fn is_logged_in(&self) -> bool {
        self.logged_in
    }

    fn username(&self) -> String {
        self.user.clone()
    }
}

/// A server that is not reachable. Every request fails, which is what an
/// offline or single-player client should present.
pub struct OfflineServer;

impl GameServer for OfflineServer {
    fn send(&mut self, _request: ApiRequest) -> RequestId {
        0
    }
    fn wait(&mut self, _id: RequestId) -> ServerResponse {
        ServerResponse { code: 0, body: String::new() }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn handles_round_trip() {
        let h = encode_handle(42);
        assert_eq!(decode_handle(&h), Some(42));
    }

    #[test]
    fn ordinary_strings_are_not_handles() {
        assert_eq!(decode_handle("hello"), None);
        assert_eq!(decode_handle("HTTPRequest(1)"), None, "the marker is required");
        assert_eq!(decode_handle(""), None);
    }

    #[test]
    fn scripted_answers_match_on_the_path() {
        let mut s = ScriptedServer::new()
            .answer("ping.php", "1")
            .answer("lookup.php", "1.2.3.4");

        let a = s.send(ApiRequest::get("ping.php?domain=x&port=0"));
        let b = s.send(ApiRequest::get("lookup.php?d=x"));
        assert_eq!(s.wait(a).body, "1");
        assert_eq!(s.wait(b).body, "1.2.3.4");
    }

    #[test]
    fn requests_are_recorded_in_order() {
        let mut s = ScriptedServer::new();
        s.send(ApiRequest::get("first"));
        s.send(ApiRequest::post("second", "body"));
        assert_eq!(s.paths(), vec!["first", "second"]);
        assert_eq!(s.requests[1].body.as_deref(), Some("body"));
    }

    #[test]
    fn an_unmatched_request_answers_empty() {
        let mut s = ScriptedServer::new().answer("ping.php", "1");
        let id = s.send(ApiRequest::get("other.php"));
        assert_eq!(s.wait(id), ServerResponse::ok(""));
    }

    #[test]
    fn waiting_twice_on_one_handle_reports_it_is_gone() {
        let mut s = ScriptedServer::new().answer("x", "y");
        let id = s.send(ApiRequest::get("x"));
        assert_eq!(s.wait(id).body, "y");
        assert_eq!(s.wait(id).code, 404);
    }

    #[test]
    fn the_offline_server_never_answers() {
        let mut s = OfflineServer;
        let id = s.send(ApiRequest::get("anything"));
        assert_eq!(s.wait(id).code, 0);
        assert!(!s.is_logged_in());
    }
}
