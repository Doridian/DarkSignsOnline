//! The DarkSigns client, compiled for a browser.
//!
//! The interpreter runs in a worker, not on the page. That is what makes the
//! design work: a script's `ReadLine` and `WaitFor` both block, which a
//! worker may do and the main thread may not.
//!
//! The page talks to this module through [`Session`]: it supplies callbacks
//! for output and input, then asks it to run a line or a script.

mod console;
mod fs;
mod host;
mod metrics;
mod server;

use std::cell::RefCell;
use std::rc::Rc;

use wasm_bindgen::prelude::*;

use vbscript::game::cli::CommandState;
use vbscript::game::fs::FileSystem;
use vbscript::game::mail;
use vbscript::game::protocol::{Credentials, DEFAULT_API_ROOT};
use vbscript::game::server::{ApiRequest, GameServer};
use vbscript::game::{run_script, Env, GameHost};
use vbscript::interp::Interp;
use vbscript::value::Value;

use console::WorkerConsole;
use fs::PersistentFs;
use host::BrowserHost;
use metrics::TextMetrics;
use server::XhrServer;

/// How many statements a script may run before it is stopped.
///
/// Player-authored scripts loop, and a worker that never returns cannot be
/// asked to stop from the page.
const STEP_BUDGET: u64 = 50_000_000;


/// One player's session: a filesystem, a connection, and the console it
/// talks to. The page holds one of these per console, each in a worker of
/// its own, because a console blocked in `ReadLine` must not stop the
/// other three.
#[wasm_bindgen]
pub struct Session {
    host: Rc<BrowserHost<WorkerConsole, PersistentFs, XhrServer>>,
    command_state: CommandState,
    /// Kept so either setting can change without discarding the other.
    api_root: RefCell<String>,
    credentials: RefCell<Credentials>,
}

#[wasm_bindgen]
impl Session {
    /// Build a session.
    ///
    /// `emit` is called with one JSON console event. `read_line` and
    /// `read_key` must block until the page has an answer — inside a worker
    /// that means `Atomics.wait`, which needs the page to be cross-origin
    /// isolated.
    ///
    /// `console_id` is which of the four this is, which scripts read as
    /// `ConsoleID`. `fonts` is the page's family-to-CSS-stack table, so that
    /// `TextWidth` measures the face that will actually be drawn.
    #[wasm_bindgen(constructor)]
    pub fn new(
        emit: js_sys::Function,
        read_line: js_sys::Function,
        read_key: js_sys::Function,
        on_file_change: js_sys::Function,
        console_id: i32,
        fonts: JsValue,
    ) -> Session {
        let console = WorkerConsole::new(emit, read_line, read_key, TextMetrics::new(&fonts));
        let inner = GameHost::new(console, PersistentFs::new(on_file_change), XhrServer::new(
            DEFAULT_API_ROOT.to_string(),
            Credentials::default(),
        ))
        // A console starts in /home, not at the root: `frmConsole.frm` seeds
        // `cPath` with "/home" for all four of them. `Env::default` is the
        // neutral root a non-console script gets.
        .with_env(Env {
            cwd: "/home".into(),
            console_id: console_id as i64,
            ..Default::default()
        });

        Session {
            host: Rc::new(BrowserHost::new(inner)),
            command_state: CommandState::console(),
            api_root: RefCell::new(DEFAULT_API_ROOT.to_string()),
            credentials: RefCell::new(Credentials::default()),
        }
    }

    /// Rebuild the connection from the current settings.
    fn reconnect(&self) {
        *self.host.inner.server.borrow_mut() = XhrServer::new(
            self.api_root.borrow().clone(),
            self.credentials.borrow().clone(),
        );
    }

    /// Sign in. Credentials stay in the worker; the page never has to hold
    /// them once they are handed over.
    #[wasm_bindgen(js_name = setCredentials)]
    pub fn set_credentials(&self, username: &str, password: &str) {
        *self.credentials.borrow_mut() = Credentials::new(username, password);
        self.reconnect();
    }

    /// Point the session at a different server, for a test instance.
    #[wasm_bindgen(js_name = setApiRoot)]
    pub fn set_api_root(&self, root: &str) {
        *self.api_root.borrow_mut() = root.to_string();
        self.reconnect();
    }

    /// Put a file into the session's filesystem without persisting it.
    ///
    /// This is how both the shipped scripts and the saved ones are loaded;
    /// applying the saved copies last is what lets a player's edit survive
    /// a client update.
    #[wasm_bindgen(js_name = seedFile)]
    pub fn seed_file(&self, path: &str, contents: &str) -> Result<(), JsValue> {
        self.host
            .inner
            .fs
            .borrow_mut()
            .seed(path, contents)
            .map_err(|e| JsValue::from_str(&e.to_string()))
    }

    /// Forget a file another console deleted, without persisting the
    /// deletion a second time.
    #[wasm_bindgen(js_name = forgetFile)]
    pub fn forget_file(&self, path: &str) {
        // A path this console never had is not an error: the four sessions
        // are told about every change, including ones that predate a file
        // they only learned of later.
        let _ = self.host.inner.fs.borrow_mut().seed_delete(path);
    }

    /// Report the console's measurements, in CSS pixels.
    ///
    /// `width` is the room a line has for text and `pre_space` the indent an
    /// ordinary one carries; scripts read them as `ConsoleWidth` and
    /// `PreSpaceWidth` and subtract one from the other.
    #[wasm_bindgen(js_name = setLayout)]
    pub fn set_layout(&self, width: f64, pre_space: f64) {
        self.host.inner.console.borrow_mut().set_layout(width, pre_space);
    }

    /// Write a file the way a script would, so the change is persisted.
    #[wasm_bindgen(js_name = writeFile)]
    pub fn write_file(&self, path: &str, contents: &str) -> Result<(), JsValue> {
        self.host
            .inner
            .fs
            .borrow_mut()
            .write(path, contents)
            .map_err(|e| JsValue::from_str(&e.to_string()))
    }

    #[wasm_bindgen(js_name = readFile)]
    pub fn read_file(&self, path: &str) -> Result<String, JsValue> {
        self.host
            .inner
            .fs
            .borrow()
            .read(path)
            .map_err(|e| JsValue::from_str(&e.to_string()))
    }

    /// The working directory, for a prompt.
    #[wasm_bindgen(js_name = currentDirectory)]
    pub fn current_directory(&self) -> String {
        self.host.inner.env.borrow().cwd.clone()
    }

    /// Run a line the player typed.
    ///
    /// The line is rewritten first — `dir /home` is not VBScript — and the
    /// result is run. An error is returned as a string for the page to show.
    #[wasm_bindgen(js_name = runCommand)]
    pub fn run_command(&mut self, line: &str) -> Result<(), JsValue> {
        let mut interp = self.interpreter();
        let script = self
            .host
            .inner
            .parse_command_line(&interp, line, &mut self.command_state)
            .map_err(|e| JsValue::from_str(&e.to_string()))?;
        run_script(&mut interp, &script).map_err(|e| JsValue::from_str(&e.to_string()))
    }

    /// Run a script directly, without the command-line rewriting.
    #[wasm_bindgen(js_name = runScript)]
    pub fn run_script(&self, source: &str, args: Vec<String>) -> Result<(), JsValue> {
        {
            let mut env = self.host.inner.env.borrow_mut();
            env.args = args.into_iter().map(Value::str).collect();
        }
        let mut interp = self.interpreter();
        run_script(&mut interp, source).map_err(|e| JsValue::from_str(&e.to_string()))
    }

    // ---- mail --------------------------------------------------------
    //
    // The reader is a page, but the connection is here: credentials never
    // leave the worker, and the API is spoken over the same synchronous
    // transport a script uses. The page asks; this answers in JSON.

    /// The inbox as it stands, without going to the server.
    #[wasm_bindgen(js_name = mailList)]
    pub fn mail_list(&self) -> Result<String, JsValue> {
        json(&MailView::new(0, &self.mail_store()))
    }

    /// Ask the server for everything newer than what is held, save it, and
    /// return the whole inbox with a count of what arrived.
    #[wasm_bindgen(js_name = mailFetch)]
    pub fn mail_fetch(&self) -> Result<String, JsValue> {
        let mut store = self.mail_store();
        let response = self.request(ApiRequest::post(
            "dsmail.php",
            mail::inbox_body(mail::highest_id(&store)),
        ));
        if !response.is_success() {
            return Err(JsValue::from_str(&server_error(&response)));
        }

        let added = mail::merge(&mut store, mail::parse_inbox(&response.body));
        // Written through the filesystem, so it is persisted and the other
        // consoles see it -- a script may read `/system/mail.dat` too.
        if added > 0 {
            self.write_store(&store)?;
        }
        json(&MailView::new(added, &store))
    }

    /// Send a message. The error is the server's own complaint.
    #[wasm_bindgen(js_name = mailSend)]
    pub fn mail_send(&self, to: &str, subject: &str, body: &str) -> Result<(), JsValue> {
        let response =
            self.request(ApiRequest::post("dsmail.php", mail::send_body(to, subject, body)));
        // A refusal comes back either as a status or as the complaint in the
        // body, depending on which check in the endpoint caught it.
        if !response.is_success() {
            return Err(JsValue::from_str(&server_error(&response)));
        }
        mail::send_result(&response.body).map_err(|e| JsValue::from_str(&e))
    }

    /// Mark one message read, which is the client's own flag.
    #[wasm_bindgen(js_name = mailMarkRead)]
    pub fn mail_mark_read(&self, id: f64) -> Result<String, JsValue> {
        let mut store = self.mail_store();
        let Some(message) = store.iter_mut().find(|m| m.id == id as i64) else {
            return json(&MailView::new(0, &store));
        };
        if message.unread {
            message.unread = false;
            self.write_store(&store)?;
        }
        json(&MailView::new(0, &store))
    }

    fn mail_store(&self) -> Vec<mail::Message> {
        // No file yet is an empty inbox, not a failure: it is written the
        // first time anything arrives.
        let text = self.host.inner.fs.borrow().read(mail::STORE_PATH).unwrap_or_default();
        mail::parse_store(&text)
    }

    fn write_store(&self, store: &[mail::Message]) -> Result<(), JsValue> {
        self.host
            .inner
            .fs
            .borrow_mut()
            .write(mail::STORE_PATH, &mail::render_store(store))
            .map_err(|e| JsValue::from_str(&e.to_string()))
    }

    /// Send one API call and wait for it, the way `WaitFor` does.
    fn request(&self, request: ApiRequest) -> vbscript::game::server::ServerResponse {
        let mut server = self.host.inner.server.borrow_mut();
        let id = server.send(request);
        server.wait(id)
    }

    /// A fresh interpreter over this session's host.
    ///
    /// Each command gets its own, so a script cannot leave variables behind
    /// for the next one. The host — filesystem, connection, console — is
    /// shared and outlives them all.
    fn interpreter(&self) -> Interp {
        let mut it = Interp::with_host(self.host.clone());
        it.set_step_budget(STEP_BUDGET);
        it
    }
}

/// One message, ready for the page.
///
/// A mirror of [`mail::Message`] rather than the type itself, so that serde
/// stays out of the interpreter crate -- the same arrangement as `Run` and
/// `markup::Segment`.
#[derive(serde::Serialize)]
#[serde(rename_all = "camelCase")]
struct MailMessage {
    id: i64,
    from: String,
    subject: String,
    body: String,
    date: String,
    unread: bool,
}

impl From<&mail::Message> for MailMessage {
    fn from(m: &mail::Message) -> MailMessage {
        MailMessage {
            id: m.id,
            from: m.from.clone(),
            subject: m.subject.clone(),
            body: m.body.clone(),
            date: m.date.clone(),
            unread: m.unread,
        }
    }
}

/// The inbox and how much of it just arrived.
#[derive(serde::Serialize)]
#[serde(rename_all = "camelCase")]
struct MailView {
    added: usize,
    messages: Vec<MailMessage>,
}

impl MailView {
    fn new(added: usize, store: &[mail::Message]) -> MailView {
        MailView { added, messages: store.iter().map(MailMessage::from).collect() }
    }
}

fn json<T: serde::Serialize>(value: &T) -> Result<String, JsValue> {
    serde_json::to_string(value).map_err(|e| JsValue::from_str(&e.to_string()))
}

/// What to show when the server refuses outright.
///
/// A 401 is the one worth naming: it means nobody is signed in, which is the
/// likely state the first time a player opens the reader.
fn server_error(response: &vbscript::game::server::ServerResponse) -> String {
    let body = mail::summary(mail::strip_code(&response.body));
    match (response.code, body.is_empty()) {
        (401, _) => "You are not signed in.".into(),
        (0, true) => "Could not reach the server.".into(),
        (code, true) => format!("The server answered {code}."),
        (_, false) => body,
    }
}

/// A convenience for the page: parse markup without running anything, so a
/// prompt or a status line can be styled the same way script output is.
#[wasm_bindgen(js_name = parseMarkup)]
pub fn parse_markup(text: &str) -> Result<String, JsValue> {
    let line = vbscript::game::markup::parse(text);
    serde_json::to_string(&console::runs_json(&line))
        .map_err(|e| JsValue::from_str(&e.to_string()))
}

/// Set up better panic messages in the browser console.
#[wasm_bindgen(start)]
pub fn start() {
    std::panic::set_hook(Box::new(|info| {
        let message = format!("dso-web panicked: {info}");
        web_sys::console::error_1(&JsValue::from_str(&message));
    }));
}
