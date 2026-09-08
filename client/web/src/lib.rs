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
use vbscript::game::fs::{bytes_to_text, text_to_bytes, FileSystem};
use vbscript::game::{chat, library, mail};
use vbscript::game::protocol::{self, Credentials, DEFAULT_API_ROOT};
use vbscript::game::server::{ApiRequest, GameServer};
use vbscript::game::{run_script, Env, GameHost};
use vbscript::interp::Interp;
use vbscript::value::Value;

use console::WorkerConsole;
use fs::RemoteFs;
use host::BrowserHost;
use metrics::TextMetrics;
use server::XhrServer;

/// How many statements a script may run before it is stopped.
///
/// A backstop rather than the way out of a runaway loop: Ctrl+B stops a
/// running script now, and this is what catches one nobody is watching.
const STEP_BUDGET: u64 = 50_000_000;


/// One player's session: a filesystem, a connection, and the console it
/// talks to. The page holds one of these per console, each in a worker of
/// its own, because a console blocked in `ReadLine` must not stop the
/// other three.
#[wasm_bindgen]
pub struct Session {
    host: Rc<BrowserHost<WorkerConsole, RemoteFs, XhrServer>>,
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
    /// isolated. `stop_requested` answers whether the player has asked for
    /// the running script to stop; it is read out of shared memory, since a
    /// worker running a script is not draining its message queue.
    ///
    /// `fs_call` is the filesystem: it takes one JSON request, blocks until
    /// the fs worker has answered, and hands back one JSON reply. There is
    /// one tree and four consoles, so no console holds it. `fs_raw` is the
    /// same channel for the three calls that carry contents, which are
    /// bytes: it takes a request and the bytes going out and answers with
    /// the bytes coming back, so that a song on its way to a `Cat` does not
    /// have to be encoded into JSON.
    ///
    /// `console_id` is which of the four this is, which scripts read as
    /// `ConsoleID`. `fonts` is the page's family-to-CSS-stack table, so that
    /// `TextWidth` measures the face that will actually be drawn.
    #[wasm_bindgen(constructor)]
    pub fn new(
        emit: js_sys::Function,
        read_line: js_sys::Function,
        read_key: js_sys::Function,
        stop_requested: js_sys::Function,
        fs_call: js_sys::Function,
        fs_raw: js_sys::Function,
        console_id: i32,
        fonts: JsValue,
    ) -> Session {
        let console = WorkerConsole::new(emit, read_line, read_key, TextMetrics::new(&fonts));
        let inner = GameHost::new(console, RemoteFs::new(fs_call, fs_raw), XhrServer::new(
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
            host: Rc::new(BrowserHost::new(inner, stop_requested)),
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
            .write(path, &text_to_bytes(contents))
            .map_err(|e| JsValue::from_str(&e.to_string()))
    }

    #[wasm_bindgen(js_name = readFile)]
    pub fn read_file(&self, path: &str) -> Result<String, JsValue> {
        self.host
            .inner
            .fs
            .borrow()
            .read(path)
            .map(|bytes| bytes_to_text(&bytes))
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

    // ---- chat ---------------------------------------------------------
    //
    // The room lives on the game server, and the client asks for whatever
    // is newer than the last line it holds. The page keeps that log rather
    // than any one worker: it polls through whichever console is free, so
    // no single session sees the whole of it.

    /// Everything said after `last`. `0` asks for the opening backlog.
    #[wasm_bindgen(js_name = chatFetch)]
    pub fn chat_fetch(&self, last: f64) -> Result<String, JsValue> {
        let response = self.request(ApiRequest::get(chat::read_path(last as i64)));
        if !response.is_success() {
            return Err(JsValue::from_str(&server_error(&response)));
        }
        json(&chat::parse_log(&response.body)
            .iter()
            .map(ChatLine::from)
            .collect::<Vec<_>>())
    }

    /// Say what the player typed at the chat box.
    ///
    /// The line is read here rather than on the page so that `/me` and the
    /// `//` escape mean one thing in one place — [`chat::parse_entry`], the
    /// original's `cmdChat_Click` rules — whether they were typed at the box
    /// or reached the room some other way.
    ///
    /// A sent line comes back with the id the server gave it, so the page
    /// can show it at once and still recognise it when the next poll brings
    /// it round again.
    #[wasm_bindgen(js_name = chatSay)]
    pub fn chat_say(&self, typed: &str) -> Result<String, JsValue> {
        let (text, emote) = match chat::parse_entry(typed) {
            chat::Entry::Say(text) => (text, false),
            chat::Entry::Emote(text) => (text, true),
            chat::Entry::Nothing => return json(&SaidView::Nothing),
            chat::Entry::Unknown(command) => return json(&SaidView::Unknown { command }),
        };
        let Some(text) = chat::clean(&text) else {
            return json(&SaidView::Nothing);
        };
        let response = self.request(ApiRequest::post("chat.php", chat::send_body(&text, emote)));
        // `send_result` reads the refusals too -- the endpoint's own words,
        // and the 401 that `function.php` answers with a bare code.
        let id = chat::send_result(&response).map_err(|e| JsValue::from_str(&e))?;
        json(&SaidView::Sent {
            line: ChatLine::from(&chat::Line {
                id,
                from: self.host.inner.server.borrow().username(),
                text,
                action: emote,
                // The server stamps the time. A line echoed before the next
                // poll has none yet, and the page shows the moment it was
                // said instead.
                date: String::new(),
            }),
        })
    }

    // ---- the file library ---------------------------------------------
    //
    // The same arrangement as mail: the window is a page and the connection
    // is here. Every call answers in JSON, and a refusal comes back as an
    // error the window shows in its status line.

    /// List one category.
    #[wasm_bindgen(js_name = libraryList)]
    pub fn library_list(&self, category: &str) -> Result<String, JsValue> {
        let body = self.get(&library::list_path(category))?;
        json(&library::parse_listing(&body).iter().map(LibraryEntry::from).collect::<Vec<_>>())
    }

    /// Download one file into `/downloads`, and say where it landed.
    ///
    /// It is written through the filesystem like any other file, so it is
    /// persisted and every console can see it -- there is one tree, so the
    /// player can run it straight away in whichever console they are in.
    #[wasm_bindgen(js_name = libraryDownload)]
    pub fn library_download(&self, id: f64) -> Result<String, JsValue> {
        let body = self.get(&library::download_path(id as i64))?;
        let (name, contents) =
            library::parse_download(&body).map_err(|e| JsValue::from_str(&e))?;
        let path = library::download_target(&name);
        let bytes = text_to_bytes(&contents);
        self.host
            .inner
            .fs
            .borrow_mut()
            .write(&path, &bytes)
            .map_err(|e| JsValue::from_str(&e.to_string()))?;
        // The file's size, which is its bytes -- not the length of the text
        // they spell, which stopped being the same number.
        json(&Download { path, bytes: bytes.len() })
    }

    /// The player's own uploads, which they may withdraw.
    #[wasm_bindgen(js_name = libraryRemovable)]
    pub fn library_removable(&self) -> Result<String, JsValue> {
        let body = self.get(&library::removable_path())?;
        json(&library::parse_removable(&body).iter().map(LibraryUpload::from).collect::<Vec<_>>())
    }

    /// Withdraw one, and return what the server said about it.
    #[wasm_bindgen(js_name = libraryRemove)]
    pub fn library_remove(&self, id: f64) -> Result<String, JsValue> {
        let body = self.get(&library::remove_path(id as i64))?;
        Ok(library::message(&body, "Removed."))
    }

    /// Publish a file from the player's own filesystem.
    ///
    /// The path is resolved and read here rather than on the page, so the
    /// window never has to hold the contents and a file that has since
    /// changed is published as it now stands.
    #[wasm_bindgen(js_name = libraryUpload)]
    pub fn library_upload(
        &self,
        category: &str,
        title: &str,
        version: &str,
        description: &str,
        path: &str,
    ) -> Result<String, JsValue> {
        let resolved = self.host.inner.resolve(path);
        let name = library::short_name(&resolved).to_string();
        library::check_upload(category, title, description, &name)
            .map_err(|e| JsValue::from_str(&e))?;
        // A read can only fail for a real filesystem reason now -- there is
        // no encoding for it to fail on -- so the reason is worth reporting.
        let contents = self
            .host
            .inner
            .fs
            .borrow()
            .read(&resolved)
            .map(|bytes| bytes_to_text(&bytes))
            .map_err(|e| JsValue::from_str(&format!("{resolved}: {e}")))?;

        let response = self.request(ApiRequest::post(
            "file_database.php",
            library::upload_body(category, title, version, description, &name, &contents),
        ));
        if !response.is_success() {
            return Err(JsValue::from_str(&server_error(&response)));
        }
        Ok(library::message(&response.body, "Upload complete!"))
    }

    /// Read one text-space channel.
    #[wasm_bindgen(js_name = textspaceLoad)]
    pub fn textspace_load(&self, channel: f64) -> Result<String, JsValue> {
        let body = self.get(&library::textspace_path(channel as i64))?;
        Ok(library::parse_textspace(&body))
    }

    /// Write one. The server refuses channel 1 and below.
    #[wasm_bindgen(js_name = textspaceSave)]
    pub fn textspace_save(&self, channel: f64, text: &str) -> Result<String, JsValue> {
        let response = self.request(ApiRequest::post(
            "textspace.php",
            library::textspace_body(channel as i64, text),
        ));
        if !response.is_success() {
            return Err(JsValue::from_str(&server_error(&response)));
        }
        Ok(library::message(&response.body, "Saved."))
    }

    // ---- files, for the editor and the upload form ----------------------

    /// Whether a file is there, so the editor can open one that is not yet.
    #[wasm_bindgen(js_name = fileExists)]
    pub fn file_exists(&self, path: &str) -> bool {
        self.host.inner.fs.borrow().exists(path)
    }

    /// Resolve a path against the console's working directory, the way a
    /// script's own file calls do.
    #[wasm_bindgen(js_name = resolvePath)]
    pub fn resolve_path(&self, path: &str) -> String {
        self.host.inner.resolve(path)
    }

    /// Send one GET and hand back its body, or the complaint that came
    /// instead.
    fn get(&self, path: &str) -> Result<String, JsValue> {
        let response = self.request(ApiRequest::get(path));
        match response.is_success() {
            true => Ok(response.body),
            false => Err(JsValue::from_str(&server_error(&response))),
        }
    }

    fn mail_store(&self) -> Vec<mail::Message> {
        // No file yet is an empty inbox, not a failure: it is written the
        // first time anything arrives.
        let bytes =
            self.host.inner.fs.borrow().read(mail::STORE_PATH).unwrap_or_default();
        mail::parse_store(&bytes_to_text(&bytes))
    }

    fn write_store(&self, store: &[mail::Message]) -> Result<(), JsValue> {
        self.host
            .inner
            .fs
            .borrow_mut()
            .write(mail::STORE_PATH, &text_to_bytes(&mail::render_store(store)))
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

/// One library row, ready for the page. `sizeText` is rendered here so the
/// window shows the same `FormatKB` string the original does.
#[derive(serde::Serialize)]
#[serde(rename_all = "camelCase")]
struct LibraryEntry {
    id: i64,
    title: String,
    version: String,
    size: i64,
    size_text: String,
    author: String,
    filename: String,
    description: String,
    date: String,
    time: String,
}

impl From<&library::Entry> for LibraryEntry {
    fn from(e: &library::Entry) -> LibraryEntry {
        LibraryEntry {
            id: e.id,
            title: e.title.clone(),
            version: e.version.clone(),
            size: e.size,
            size_text: vbscript::game::values::format_kb(e.size),
            author: e.author.clone(),
            filename: e.filename.clone(),
            description: e.description.clone(),
            date: e.date.clone(),
            time: e.time.clone(),
        }
    }
}

/// One of the player's own uploads.
#[derive(serde::Serialize)]
#[serde(rename_all = "camelCase")]
struct LibraryUpload {
    id: i64,
    label: String,
}

impl From<&library::Upload> for LibraryUpload {
    fn from(u: &library::Upload) -> LibraryUpload {
        LibraryUpload { id: u.id, label: u.label.clone() }
    }
}

/// Where a downloaded file landed.
#[derive(serde::Serialize)]
#[serde(rename_all = "camelCase")]
struct Download {
    path: String,
    bytes: usize,
}

/// One chat line, ready for the page.
#[derive(serde::Serialize)]
#[serde(rename_all = "camelCase")]
struct ChatLine {
    id: f64,
    from: String,
    text: String,
    action: bool,
    date: String,
}

impl From<&chat::Line> for ChatLine {
    fn from(l: &chat::Line) -> ChatLine {
        ChatLine {
            id: l.id as f64,
            from: l.from.clone(),
            text: l.text.clone(),
            action: l.action,
            date: l.date.clone(),
        }
    }
}

/// What became of a line typed at the chat box.
#[derive(serde::Serialize)]
#[serde(tag = "kind", rename_all = "camelCase")]
enum SaidView {
    /// It reached the room.
    Sent { line: ChatLine },
    /// Nothing was typed, so nothing was said -- which is where the
    /// original's handler exits too.
    Nothing,
    /// A `/word` that is not one of ours. The original answers "Command not
    /// found."; naming the word says more.
    #[serde(rename_all = "camelCase")]
    Unknown { command: String },
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
    let body = protocol::summary(protocol::strip_code(&response.body));
    match (response.code, body.is_empty()) {
        (401, _) => "You are not signed in.".into(),
        (0, true) => "Could not reach the server.".into(),
        (code, true) => format!("The server answered {code}."),
        (_, false) => body,
    }
}

/// The library's categories and how many text-space channels there are, so
/// the window's pickers are built from the same table the requests are.
#[wasm_bindgen(js_name = libraryCategories)]
pub fn library_categories() -> Result<String, JsValue> {
    serde_json::to_string(&library::CATEGORIES).map_err(|e| JsValue::from_str(&e.to_string()))
}

#[wasm_bindgen(js_name = textspaceChannels)]
pub fn textspace_channels() -> f64 {
    library::CHANNELS as f64
}

/// Fold a path the way the filesystem does.
///
/// The page needs it for the saved tree: a file written before the
/// filesystem was case-insensitive is still stored under whatever case it
/// was typed in, and the store has to be able to move it to the folded name.
#[wasm_bindgen(js_name = foldPath)]
pub fn fold_path(path: &str) -> String {
    vbscript::game::path::fold_case(path)
}

/// The MIME type a name implies, or an empty string when nothing about the
/// name says.
///
/// Nothing is classified by this: a file is bytes and the engine never asks
/// what kind. It exists because `<audio>` needs a type in order to pick a
/// decoder and OPFS hands a file back with an empty one, so the page puts
/// the type back on at the moment of playing. Exported rather than written
/// again in TypeScript because the table is already here.
#[wasm_bindgen(js_name = mediaTypeFor)]
pub fn media_type_for_js(path: &str) -> String {
    vbscript::game::fs::media_type_for(path).unwrap_or_default().to_string()
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
