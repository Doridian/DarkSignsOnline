//! The browser's host.
//!
//! [`GameHost`] already implements everything scripts need; what a browser
//! must add is a clock, because `wasm32-unknown-unknown` has none of its
//! own, and an answer to whether the player has asked for the running script
//! to stop. Randomness needs no help — `getrandom`'s `wasm_js` backend
//! reaches the Web Crypto API.

use vbscript::game::console::Console;
use vbscript::game::fs::FileSystem;
use vbscript::game::server::GameServer;
use vbscript::game::GameHost;
use vbscript::interp::{ArgVal, Host, Interp};
use vbscript::value::Value;
use vbscript::VbResult;
use wasm_bindgen::JsValue;

/// Wraps the shared host and supplies the pieces only the page can answer.
pub struct BrowserHost<C, F, S> {
    pub inner: GameHost<C, F, S>,
    /// Whether the page has asked for the running script to stop.
    ///
    /// It reads a flag out of the block this worker shares with the page,
    /// which is the only channel that reaches a thread busy running a
    /// script: a `postMessage` would sit in a queue nothing is draining.
    ///
    /// Being the one call out of a running script, it is also where the
    /// worker hands the page whatever the script has said since the page
    /// last drew. Asking is therefore not free of consequence, which is why
    /// it is asked at the points that suit both: often enough that held
    /// output is never held long, rarely enough to cost nothing.
    stop_requested: js_sys::Function,
}

impl<C: Console, F: FileSystem, S: GameServer> BrowserHost<C, F, S> {
    pub fn new(inner: GameHost<C, F, S>, stop_requested: js_sys::Function) -> Self {
        BrowserHost { inner, stop_requested }
    }
}

impl<C: Console, F: FileSystem, S: GameServer> Host for BrowserHost<C, F, S> {
    /// The one hook with no portable implementation.
    fn now_unix_millis(&self) -> f64 {
        js_sys::Date::now()
    }

    fn poll_abort(&self) -> bool {
        self.stop_requested
            .call0(&JsValue::NULL)
            .ok()
            .and_then(|v| v.as_bool())
            .unwrap_or(false)
    }

    // The rest is the shared host's behaviour, forwarded unchanged.
    fn get_global(&self, it: &mut Interp, name: &str) -> VbResult<Option<Value>> {
        self.inner.get_global(it, name)
    }

    fn call(&self, it: &mut Interp, name: &str, args: &mut [ArgVal]) -> VbResult<Option<Value>> {
        // Asked on both sides of the call, for two different reasons.
        //
        // Before it, because asking is the one thing a running script does
        // that reaches the page at all, and the page uses it to collect the
        // output it is owed. A call is about to park this worker for as long
        // as a request takes, and a line said just before one should wait for
        // a frame rather than for the answer.
        //
        // After it, because the call may have parked for as long as the
        // player was willing to wait -- on a typed line, on a request -- and
        // the stop would otherwise be left to the interpreter's own poll,
        // which counts statements and so is reached slowly by a script that
        // spends its time waiting. The call still returns whatever it was
        // going to; the stop lands at the next statement either way.
        if self.poll_abort() {
            it.request_abort();
        }
        let result = self.inner.call(it, name, args);
        if self.poll_abort() {
            it.request_abort();
        }
        result
    }

    fn global_object(&self, it: &mut Interp) -> VbResult<Option<Value>> {
        self.inner.global_object(it)
    }

    fn set_global(&self, it: &mut Interp, name: &str, value: Value) -> VbResult<bool> {
        self.inner.set_global(it, name, value)
    }

    fn create_object(&self, it: &mut Interp, progid: &str) -> VbResult<Option<Value>> {
        self.inner.create_object(it, progid)
    }

    fn echo(&self, text: &str) {
        self.inner.echo(text)
    }
}
