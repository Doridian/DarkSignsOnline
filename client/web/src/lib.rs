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
mod server;

use std::cell::RefCell;
use std::rc::Rc;

use wasm_bindgen::prelude::*;

use vbscript::game::cli::CommandState;
use vbscript::game::fs::FileSystem;
use vbscript::game::protocol::{Credentials, DEFAULT_API_ROOT};
use vbscript::game::{run_script, Env, GameHost};
use vbscript::interp::Interp;
use vbscript::value::Value;

use console::WorkerConsole;
use fs::PersistentFs;
use host::BrowserHost;
use server::XhrServer;

/// How many statements a script may run before it is stopped.
///
/// Player-authored scripts loop, and a worker that never returns cannot be
/// asked to stop from the page.
const STEP_BUDGET: u64 = 50_000_000;


/// One player's session: a filesystem, a connection, and the console it
/// talks to. The page holds one of these for as long as it is open.
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
    #[wasm_bindgen(constructor)]
    pub fn new(
        emit: js_sys::Function,
        read_line: js_sys::Function,
        read_key: js_sys::Function,
        on_file_change: js_sys::Function,
        width: i32,
    ) -> Session {
        let console = WorkerConsole::new(emit, read_line, read_key, width as i64);
        let inner = GameHost::new(console, PersistentFs::new(on_file_change), XhrServer::new(
            DEFAULT_API_ROOT.to_string(),
            Credentials::default(),
        ))
        .with_env(Env { cwd: "/".into(), ..Default::default() });

        Session {
            host: Rc::new(BrowserHost::new(inner)),
            command_state: CommandState::default(),
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
