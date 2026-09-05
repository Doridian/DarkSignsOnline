//! The game server, reached with a synchronous `XMLHttpRequest`.
//!
//! Blocking is deliberate. A script's `WaitFor` expects an answer before it
//! continues, and inside a worker a synchronous request is allowed — it is
//! only the main thread where the browser forbids it.

use wasm_bindgen::JsValue;
use web_sys::XmlHttpRequest;

use vbscript::game::protocol::{self, Credentials, Method};
use vbscript::game::server::{ApiRequest, GameServer, RequestId, ResponseType, ServerResponse};

pub struct XhrServer {
    api_root: String,
    credentials: Credentials,
    client_version: String,
    pending: std::collections::BTreeMap<RequestId, ApiRequest>,
    next_id: RequestId,
    logged_in: bool,
}

impl XhrServer {
    pub fn new(api_root: String, credentials: Credentials) -> XhrServer {
        XhrServer {
            api_root,
            credentials,
            client_version: env!("CARGO_PKG_VERSION").to_string(),
            pending: Default::default(),
            next_id: 1,
            logged_in: false,
        }
    }

    fn perform(&self, request: &ApiRequest) -> ServerResponse {
        if protocol::requires_login(&request.path) && !self.credentials.is_set() {
            return ServerResponse { code: 401, body: "User not logged in".into() };
        }
        let http = protocol::build_request(
            &self.api_root,
            request,
            &self.credentials,
            &self.client_version,
        );

        match send_sync(&http) {
            Ok(response) => response,
            // A transport failure becomes a status the script can inspect,
            // rather than an exception crossing the wasm boundary.
            Err(e) => ServerResponse {
                code: 0,
                body: e.as_string().unwrap_or_else(|| "network error".into()),
            },
        }
    }
}

fn send_sync(http: &protocol::HttpRequest) -> Result<ServerResponse, JsValue> {
    let xhr = XmlHttpRequest::new()?;
    let method = match http.method {
        Method::Get => "GET",
        Method::Post => "POST",
    };
    // `false` is what makes this synchronous.
    xhr.open_with_async(method, &http.url, false)?;

    for (name, value) in &http.headers {
        xhr.set_request_header(name, value)?;
    }
    if let Some((user, password)) = &http.auth {
        let encoded =
            vbscript::game::crypto::encode_base64_standard(format!("{user}:{password}").as_bytes());
        xhr.set_request_header("Authorization", &format!("Basic {encoded}"))?;
    }

    match http.method {
        Method::Get => xhr.send()?,
        Method::Post => xhr.send_with_opt_str(Some(&http.body))?,
    }

    Ok(ServerResponse {
        code: xhr.status()? as i64,
        body: xhr.response_text()?.unwrap_or_default(),
    })
}

impl GameServer for XhrServer {
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
