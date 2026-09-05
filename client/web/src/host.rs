//! The browser's host.
//!
//! [`GameHost`] already implements everything scripts need; what a browser
//! must add is a clock, because `wasm32-unknown-unknown` has none of its
//! own. Randomness needs no help — `getrandom`'s `wasm_js` backend reaches
//! the Web Crypto API.

use vbscript::game::console::Console;
use vbscript::game::fs::FileSystem;
use vbscript::game::server::GameServer;
use vbscript::game::GameHost;
use vbscript::interp::{ArgVal, Host, Interp};
use vbscript::value::Value;
use vbscript::VbResult;

/// Wraps the shared host and supplies the pieces only the page can answer.
pub struct BrowserHost<C, F, S> {
    pub inner: GameHost<C, F, S>,
}

impl<C: Console, F: FileSystem, S: GameServer> BrowserHost<C, F, S> {
    pub fn new(inner: GameHost<C, F, S>) -> Self {
        BrowserHost { inner }
    }
}

impl<C: Console, F: FileSystem, S: GameServer> Host for BrowserHost<C, F, S> {
    /// The one hook with no portable implementation.
    fn now_unix_millis(&self) -> f64 {
        js_sys::Date::now()
    }

    // The rest is the shared host's behaviour, forwarded unchanged.
    fn get_global(&self, it: &mut Interp, name: &str) -> VbResult<Option<Value>> {
        self.inner.get_global(it, name)
    }

    fn call(&self, it: &mut Interp, name: &str, args: &mut [ArgVal]) -> VbResult<Option<Value>> {
        self.inner.call(it, name, args)
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
