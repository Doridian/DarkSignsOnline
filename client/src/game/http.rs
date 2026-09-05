//! A [`GameServer`] backed by a real HTTP client.
//!
//! This is the desktop transport. It is synchronous, which suits the
//! interpreter's `WaitFor`, and is compiled only when the `native-http`
//! feature is on — a browser build talks to the server through `fetch`
//! instead.

use std::collections::BTreeMap;

use super::protocol::{self, Credentials, Method};
use super::server::{ApiRequest, GameServer, RequestId, ResponseType, ServerResponse};

/// Sends API calls over HTTP.
///
/// Requests are issued when the script waits on them rather than when they
/// are started, because the transport is blocking. Scripts cannot tell the
/// difference: the client's own requests are asynchronous, but a script only
/// ever observes the result through `WaitFor`.
pub struct HttpServer {
    api_root: String,
    credentials: Credentials,
    client_version: String,
    pending: BTreeMap<RequestId, ApiRequest>,
    next_id: RequestId,
    logged_in: bool,
}

impl HttpServer {
    pub fn new(credentials: Credentials) -> HttpServer {
        HttpServer {
            api_root: protocol::DEFAULT_API_ROOT.to_string(),
            credentials,
            client_version: env!("CARGO_PKG_VERSION").to_string(),
            pending: BTreeMap::new(),
            next_id: 1,
            logged_in: false,
        }
    }

    /// Point the client at a different server, for a test instance.
    pub fn with_api_root(mut self, root: impl Into<String>) -> HttpServer {
        self.api_root = root.into();
        self
    }

    fn perform(&self, request: &ApiRequest) -> ServerResponse {
        if protocol::requires_login(&request.path) && !self.credentials.is_set() {
            return ServerResponse { code: 401, body: "User not logged in".into() };
        }

        let http =
            protocol::build_request(&self.api_root, request, &self.credentials, &self.client_version);

        // The builder's type differs between a request with and without a
        // body, so each branch applies the headers itself.
        let mut headers: Vec<(&str, String)> =
            http.headers.iter().map(|(k, v)| (k.as_str(), v.clone())).collect();
        if let Some((user, password)) = &http.auth {
            headers.push(("Authorization", basic_auth(user, password)));
        }

        let sent = match http.method {
            Method::Get => {
                let mut b = ureq::get(&http.url);
                for (name, value) in &headers {
                    b = b.header(*name, value);
                }
                b.call()
            }
            Method::Post => {
                let mut b = ureq::post(&http.url);
                for (name, value) in &headers {
                    b = b.header(*name, value);
                }
                b.send(&http.body)
            }
        };

        match sent {
            Ok(mut response) => {
                let code = response.status().as_u16() as i64;
                let body = response.body_mut().read_to_string().unwrap_or_default();
                ServerResponse { code, body }
            }
            // A transport failure is reported as a status the script can see
            // rather than as a panic.
            Err(ureq::Error::StatusCode(code)) => {
                ServerResponse { code: code as i64, body: String::new() }
            }
            Err(e) => ServerResponse { code: 0, body: e.to_string() },
        }
    }
}

/// `Basic base64(user:password)`.
fn basic_auth(user: &str, password: &str) -> String {
    let encoded = super::crypto::encode_base64_standard(format!("{user}:{password}").as_bytes());
    format!("Basic {encoded}")
}

impl GameServer for HttpServer {
    fn send(&mut self, request: ApiRequest) -> RequestId {
        let id = self.next_id;
        self.next_id += 1;
        self.pending.insert(id, request);
        id
    }

    fn wait(&mut self, id: RequestId) -> ServerResponse {
        let Some(request) = self.pending.remove(&id) else {
            return ServerResponse { code: 404, body: String::new() };
        };
        let response = self.perform(&request);
        if request.path.starts_with("auth.php") && response.is_success() {
            self.logged_in = true;
        }
        response
    }

    fn response_type(&self, id: RequestId) -> ResponseType {
        self.pending.get(&id).map(|r| r.response_type).unwrap_or_default()
    }

    fn is_logged_in(&self) -> bool {
        self.logged_in
    }

    fn username(&self) -> String {
        self.credentials.username.clone()
    }
}
