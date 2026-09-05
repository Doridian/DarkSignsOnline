//! The DarkSigns host API that `.ds` scripts call into.
//!
//! The VB6 client exposed roughly 130 procedures on `clsScriptFunctions`.
//! They split three ways: pure helpers ported outright, operations on the
//! player's files, and calls to the game server. The latter two go through
//! the [`fs::FileSystem`], [`console::Console`] and [`server::GameServer`]
//! traits so the desktop client, a headless run and the tests can each
//! supply their own.
//!
//! Note that a script's `DLOpen "termlib"` pulls in a *script* library, not
//! host functions, so names like `SaySlow` are defined in VBScript and are
//! deliberately absent here.

pub mod cli;
pub mod console;
pub mod crypto;
pub mod fs;
pub mod markup;
pub mod path;
pub mod server;
pub mod termlib;
pub mod values;

use std::cell::RefCell;
use std::rc::Rc;

use crate::error::{VbError, VbResult};
use crate::interp::{ArgVal, Host, Interp};
use crate::value::{VbArray, Value};

use console::{Channel, Console, DrawMode};
use fs::{FileSystem, FsError};
use server::{ApiRequest, GameServer};

/// Where a bare command name is looked for, in order. The working
/// directory comes last so a system command wins.
const COMMAND_PATH: &[&str] = &["/system/commands", "."];

/// `vbObjectError`, the base the client adds its own error numbers to.
const VB_OBJECT_ERROR: i32 = 0x8004_0000u32 as i32;

/// Raised by `Quit`, and by the runner when a script asks to stop. It is not
/// a failure; [`run_script`] turns it back into a normal return.
pub const QUIT_ERROR: i32 = VB_OBJECT_ERROR | 0x2000;

fn misc_error(desc: impl AsRef<str>) -> VbError {
    let mut e = VbError::new(VB_OBJECT_ERROR + 9666, desc);
    e.source = Rc::from("DarkSigns");
    e
}

fn fs_error(e: FsError) -> VbError {
    // Map onto the VBScript file errors scripts already know how to handle.
    let number = match e {
        FsError::NotFound(_) => 53,
        FsError::NotADirectory(_) | FsError::IsADirectory(_) => 54,
        FsError::AlreadyExists(_) => 58,
        FsError::NotEmpty(_) => 75,
        FsError::Io(_) => 57,
    };
    VbError::new(number, e.to_string())
}

/// Everything the host needs to know about the script it is running.
pub struct Env {
    /// Working directory for relative paths.
    pub cwd: String,
    /// Values `ArgV` reports; index 0 is the command itself.
    pub args: Vec<Value>,
    /// Account that owns the script, used to scope mission data.
    pub script_owner: String,
    /// Key a downloaded script was compiled with.
    pub file_key: String,
    /// Domain, port and address of the server the script is talking to.
    pub server_domain: String,
    pub server_port: i64,
    pub server_ip: String,
    /// Address the script appears to be connecting from.
    pub connecting_ip: String,
    /// False while running a script fetched from a remote domain, which
    /// blocks the local filesystem functions.
    pub is_local: bool,
    /// Set when the script asked to stop.
    pub quit: bool,
    /// Text captured instead of printed, when running under `Capture`.
    pub captured: Option<String>,
    /// Suppresses console output entirely, which `Run` sets for a script
    /// whose output the caller does not want.
    pub output_disabled: bool,
    /// Output is being collected rather than shown.
    pub output_redirected: bool,
    /// Libraries `DLOpen` has already brought in, so a second call is free
    /// and a library cannot be included twice.
    pub loaded_libraries: std::collections::BTreeSet<String>,
}

impl Default for Env {
    fn default() -> Env {
        Env {
            cwd: "/".into(),
            args: Vec::new(),
            script_owner: "local".into(),
            file_key: String::new(),
            server_domain: String::new(),
            server_port: 0,
            server_ip: String::new(),
            connecting_ip: String::new(),
            is_local: true,
            quit: false,
            captured: None,
            output_disabled: false,
            output_redirected: false,
            loaded_libraries: std::collections::BTreeSet::new(),
        }
    }
}

/// The host a script runs against.
///
/// Its parts sit behind `RefCell`s because `Include`, `Run` and `Capture`
/// run further script, which calls back into this same host. Each borrow
/// therefore covers one operation and is released before any nested script
/// runs.
pub struct GameHost<C, F, S> {
    pub console: RefCell<C>,
    pub fs: RefCell<F>,
    pub server: RefCell<S>,
    pub env: RefCell<Env>,
}

impl<C: Console, F: FileSystem, S: GameServer> GameHost<C, F, S> {
    pub fn new(console: C, fs: F, server: S) -> Self {
        GameHost {
            console: RefCell::new(console),
            fs: RefCell::new(fs),
            server: RefCell::new(server),
            env: RefCell::new(Env::default()),
        }
    }

    pub fn with_env(self, env: Env) -> Self {
        *self.env.borrow_mut() = env;
        self
    }

    /// Resolve a script path against the working directory.
    fn resolve(&self, p: &str) -> String {
        path::resolve_rel(&self.env.borrow().cwd, p)
    }

    /// The local filesystem is only reachable from a local script.
    fn assert_local(&self) -> VbResult<()> {
        if self.env.borrow().is_local {
            Ok(())
        } else {
            Err(misc_error("This function can only be called from a local script"))
        }
    }

    /// Send an API request and return the handle scripts pass to `WaitFor`.
    fn api(&self, request: ApiRequest) -> Value {
        let id = self.server.borrow_mut().send(request);
        Value::str(server::encode_handle(id))
    }

    /// Write a line, honouring an active `Capture`.
    pub(crate) fn emit(&self, channel: Channel, text: &str) {
        // Capture is checked and appended under one borrow, which is
        // released before anything else runs.
        if self.env.borrow().output_disabled {
            return;
        }
        let capturing = {
            let mut env = self.env.borrow_mut();
            match &mut env.captured {
                Some(buf) => {
                    buf.push_str(text);
                    buf.push_str("\r\n");
                    true
                }
                None => false,
            }
        };
        if !capturing {
            self.console.borrow_mut().say(channel, text);
        }
    }
}

/// Coerce one argument to a string, treating a missing one as empty.
pub(crate) fn arg_str(args: &[ArgVal], i: usize) -> VbResult<String> {
    match args.get(i) {
        None => Ok(String::new()),
        Some(a) if a.is_missing() => Ok(String::new()),
        Some(a) => Ok(a.value().to_vb_string()?.to_string()),
    }
}

/// Coerce one argument to a whole number, with a default when absent.
pub(crate) fn arg_int(args: &[ArgVal], i: usize, default: i64) -> VbResult<i64> {
    match args.get(i) {
        None => Ok(default),
        Some(a) if a.is_missing() => Ok(default),
        Some(a) => Ok(a.value().to_f64()? as i64),
    }
}

fn arg_bool(args: &[ArgVal], i: usize, default: bool) -> VbResult<bool> {
    match args.get(i) {
        None => Ok(default),
        Some(a) if a.is_missing() => Ok(default),
        Some(a) => a.value().to_bool(),
    }
}

fn arg_value(args: &[ArgVal], i: usize) -> Value {
    args.get(i).map(|a| a.value()).unwrap_or(Value::Empty)
}

/// The elements of an array argument, for the functions that take one.
fn arg_array(args: &[ArgVal], i: usize) -> VbResult<Vec<Value>> {
    match arg_value(args, i) {
        Value::Array(a) => Ok(a.data.clone()),
        // A single value stands in for a one-element array.
        other => Ok(vec![other]),
    }
}

fn string_array(items: Vec<String>) -> Value {
    Value::Array(Rc::new(VbArray::from_values(
        items.into_iter().map(Value::str).collect(),
    )))
}

fn value_array(items: Vec<Value>) -> Value {
    Value::Array(Rc::new(VbArray::from_values(items)))
}

impl<C: Console, F: FileSystem, S: GameServer> Host for GameHost<C, F, S> {
    fn get_global(&self, _it: &mut Interp, name: &str) -> VbResult<Option<Value>> {
        // Only the handful of names that read as values rather than calls.
        Ok(match name {
            "consoleinvisiblechar" => Some(Value::str(values::INVISIBLE_CHAR.to_string())),
            _ => None,
        })
    }

    fn call(
        &self,
        it: &mut Interp,
        name: &str,
        args: &mut [ArgVal],
    ) -> VbResult<Option<Value>> {
        let v = match name {
            // ---- pure helpers -------------------------------------------
            "coalesce" => {
                let vals: Vec<Value> = args.iter().map(|a| a.value()).collect();
                values::coalesce(&vals)
            }
            "booltostring" => Value::Bool(
                values::parse_bool(&arg_str(args, 0)?).map_err(misc_error)?,
            ),
            "trimwithnewline" => Value::str(values::trim_with_newline(&arg_str(args, 0)?)),
            "ishex" => Value::Bool(values::is_hex(&arg_str(args, 0)?)),
            "formatkb" => Value::str(values::format_kb(arg_int(args, 0, 0)?)),
            "urlencode" => Value::str(values::url_encode(&arg_str(args, 0)?)),
            "consoleescape" => Value::str(values::console_escape(&arg_str(args, 0)?)),
            "consoleunescape" => Value::str(values::console_unescape(&arg_str(args, 0)?)),
            "rgbjoin" => {
                let parts = arg_array(args, 0)?;
                let get = |i: usize| -> VbResult<i64> {
                    Ok(parts.get(i).map(|v| v.to_f64()).transpose()?.unwrap_or(0.0) as i64)
                };
                Value::I4(values::rgb_join(get(0)?, get(1)?, get(2)?))
            }
            "rgbsplit" => {
                let [r, g, b] = values::rgb_split(arg_int(args, 0, 0)? as i32);
                value_array(vec![Value::I4(r), Value::I4(g), Value::I4(b)])
            }

            // ---- crypto -------------------------------------------------
            "sha256" | "sha" => Value::str(crypto::sha256_hex(arg_str(args, 0)?.as_bytes())),
            "encodebase64str" | "encodebase" => {
                Value::str(crypto::encode_base64(arg_str(args, 0)?.as_bytes()))
            }
            "decodebase64str" | "decodebase" => {
                let bytes = crypto::decode_base64(&arg_str(args, 0)?)
                    .map_err(|e| misc_error(e.to_string()))?;
                Value::str(bytes.iter().map(|&b| b as char).collect::<String>())
            }
            "encodebase64bytes" => {
                let bytes: Vec<u8> = arg_array(args, 0)?
                    .iter()
                    .map(|v| v.to_f64().map(|n| n as u8))
                    .collect::<VbResult<_>>()?;
                Value::str(crypto::encode_base64(&bytes))
            }
            "decodebase64bytes" => {
                let bytes = crypto::decode_base64(&arg_str(args, 0)?)
                    .map_err(|e| misc_error(e.to_string()))?;
                value_array(bytes.into_iter().map(Value::UI1).collect())
            }
            "encrypt" => {
                let salt = crypto::generate_salt().map_err(|e| misc_error(e.to_string()))?;
                // The script-facing password is namespaced so it cannot
                // collide with a script key.
                let password = format!("dsoscript_{}", arg_str(args, 1)?);
                Value::str(
                    crypto::encrypt(
                        &arg_str(args, 0)?,
                        &password,
                        arg_bool(args, 2, false)?,
                        salt,
                    )
                    .map_err(|e| misc_error(e.to_string()))?,
                )
            }
            "decrypt" => {
                let password = format!("dsoscript_{}", arg_str(args, 1)?);
                Value::str(
                    crypto::decrypt(&arg_str(args, 0)?, &password)
                        .map_err(|e| misc_error(e.to_string()))?,
                )
            }
            "compilestr" => {
                let salt = crypto::generate_salt().map_err(|e| misc_error(e.to_string()))?;
                Value::str(
                    crypto::compile_script(&arg_str(args, 0)?, &arg_str(args, 1)?, salt)
                        .map_err(|e| misc_error(e.to_string()))?,
                )
            }

            // ---- script environment -------------------------------------
            "argc" => Value::I4(self.env.borrow().args.len() as i32 - 1),
            "argv" => {
                let i = arg_int(args, 0, 0)?;
                let env = self.env.borrow();
                if i < 0 || i as usize >= env.args.len() {
                    Value::str("")
                } else {
                    env.args[i as usize].clone()
                }
            }
            "islocal" => Value::Bool(self.env.borrow().is_local),
            "username" => Value::str(self.server.borrow().username()),
            "connectingip" => Value::str(self.env.borrow().connecting_ip.clone()),
            "consoleid" => Value::I4(0),
            "spooflocalconnectingip" => {
                if self.env.borrow().is_local {
                    let v = arg_str(args, 0)?;
                    let mut env = self.env.borrow_mut();
                    // An empty argument restores the real address.
                    env.connecting_ip = if v.is_empty() { env.server_ip.clone() } else { v };
                }
                Value::Empty
            }
            "quit" => {
                self.env.borrow_mut().quit = true;
                return Err(VbError::new(QUIT_ERROR, "Script stopped"));
            }
            // Yielding and waiting are cooperative scheduling in the real
            // client; a synchronous host has nothing to hand control to.
            "yield" | "wait" | "unabort" | "cleanupscripttasks" | "restart" => Value::Empty,
            "scriptgetoutput" => Value::str(self.env.borrow().captured.clone().unwrap_or_default()),

            // ---- paths ---------------------------------------------------
            "resolvepath" => {
                self.assert_local()?;
                Value::str(self.resolve(&arg_str(args, 0)?))
            }
            "resolvepathrel" => Value::str(path::resolve_rel_trimmed(
                &arg_str(args, 0)?,
                &arg_str(args, 1)?,
            )),
            "resolvecommand" => {
                self.assert_local()?;
                Value::str(self.resolve_command(&arg_str(args, 0)?).unwrap_or_default())
            }
            "cd" => {
                self.assert_local()?;
                let target = self.resolve(&arg_str(args, 0)?);
                if !self.fs.borrow_mut().is_dir(&target) {
                    return Err(fs_error(FsError::NotADirectory(target)));
                }
                self.env.borrow_mut().cwd = target;
                Value::Empty
            }

            // ---- local files ---------------------------------------------
            "fileexists" => {
                self.assert_local()?;
                let p = self.resolve(&arg_str(args, 0)?);
                Value::Bool(self.fs.borrow_mut().exists(&p) && !self.fs.borrow_mut().is_dir(&p))
            }
            "direxists" => {
                self.assert_local()?;
                let p = self.resolve(&arg_str(args, 0)?);
                Value::Bool(self.fs.borrow_mut().is_dir(&p))
            }
            "filelen" => {
                self.assert_local()?;
                let p = self.resolve(&arg_str(args, 0)?);
                Value::I4(self.fs.borrow_mut().len(&p).map_err(fs_error)? as i32)
            }
            "overwrite" => {
                self.assert_local()?;
                let p = self.resolve(&arg_str(args, 0)?);
                self.fs.borrow_mut().write(&p, &arg_str(args, 1)?).map_err(fs_error)?;
                Value::Empty
            }
            "append" => {
                self.assert_local()?;
                let p = self.resolve(&arg_str(args, 0)?);
                self.fs.borrow_mut().append(&p, &arg_str(args, 1)?).map_err(fs_error)?;
                Value::Empty
            }
            "del" | "delete" => {
                self.assert_local()?;
                let p = self.resolve(&arg_str(args, 0)?);
                self.fs.borrow_mut().delete(&p).map_err(fs_error)?;
                Value::Empty
            }
            "copy" => {
                self.assert_local()?;
                let (a, b) = (self.resolve(&arg_str(args, 0)?), self.resolve(&arg_str(args, 1)?));
                self.fs.borrow_mut().copy(&a, &b).map_err(fs_error)?;
                Value::Empty
            }
            "rename" | "move" => {
                self.assert_local()?;
                let (a, b) = (self.resolve(&arg_str(args, 0)?), self.resolve(&arg_str(args, 1)?));
                self.fs.borrow_mut().rename(&a, &b).map_err(fs_error)?;
                Value::Empty
            }
            "md" => {
                self.assert_local()?;
                let p = self.resolve(&arg_str(args, 0)?);
                self.fs.borrow_mut().make_dir(&p).map_err(fs_error)?;
                Value::Empty
            }
            "rd" => {
                self.assert_local()?;
                let p = self.resolve(&arg_str(args, 0)?);
                self.fs.borrow_mut().remove_dir(&p).map_err(fs_error)?;
                Value::Empty
            }
            "readdir" => {
                self.assert_local()?;
                let p = self.resolve(&arg_str(args, 0)?);
                let entries = self.fs.borrow_mut().read_dir(&p).map_err(fs_error)?;
                string_array(entries.iter().map(|e| e.display_name()).collect())
            }
            "cat" | "display" => {
                self.assert_local()?;
                let p = self.resolve(&arg_str(args, 0)?);
                let text = self.fs.borrow_mut().read(&p).map_err(fs_error)?;
                Value::str(select_lines(
                    &text,
                    arg_int(args, 1, 0)?,
                    arg_int(args, 2, 0)?,
                ))
            }
            "writeini" => {
                self.assert_local()?;
                let p = self.resolve(&arg_str(args, 0)?);
                self.write_ini(&p, &arg_str(args, 1)?, &arg_str(args, 2)?, &arg_str(args, 3)?)?;
                Value::Empty
            }
            "readini" => {
                self.assert_local()?;
                let p = self.resolve(&arg_str(args, 0)?);
                Value::str(self.read_ini(&p, &arg_str(args, 1)?, &arg_str(args, 2)?))
            }
            "getmissionfile" => Value::str(self.mission_file(&arg_str(args, 0)?)),
            "getmissiondata" => {
                let f = self.mission_file(&arg_str(args, 0)?);
                Value::str(self.read_ini(&f, &arg_str(args, 1)?, &arg_str(args, 2)?))
            }
            "setmissiondata" => {
                let f = self.mission_file(&arg_str(args, 0)?);
                self.write_ini(&f, &arg_str(args, 1)?, &arg_str(args, 2)?, &arg_str(args, 3)?)?;
                Value::Empty
            }

            // ---- console --------------------------------------------------
            "say" => {
                let text = join_params(args)?;
                self.emit(Channel::Say, &text);
                Value::Empty
            }
            "saycomm" => {
                let text = join_params(args)?;
                self.emit(Channel::Comm, &text);
                Value::Empty
            }
            "sayline" => {
                let text = arg_str(args, 0)?;
                let y = arg_int(args, 1, -1)?;
                self.console.borrow_mut().say_at(&text, y);
                Value::Empty
            }
            "chatsend" => {
                let text = arg_str(args, 0)?;
                self.console.borrow_mut().say(Channel::Chat, &text);
                Value::Empty
            }
            "chatview" => {
                let on = arg_bool(args, 0, true)?;
                self.console.borrow_mut().set_chat_visible(on);
                Value::Empty
            }
            "cls" | "clear" => {
                self.console.borrow_mut().clear();
                Value::Empty
            }
            "lineup" => {
                self.console.borrow_mut().line_up();
                Value::Empty
            }
            "draw" => {
                let y = arg_int(args, 0, -1)?;
                let rgb = arg_int(args, 1, -1)?;
                let mode = DrawMode::parse(&arg_str(args, 2)?);
                let segments = arg_int(args, 3, 0)?;
                self.console.borrow_mut().draw(y, rgb, mode, segments);
                Value::Empty
            }
            "drawcustom" | "drawcustoma" => {
                let y = arg_int(args, 0, -1)?;
                let rest = trailing_ints(args, 1)?;
                self.console.borrow_mut().draw_custom(y, &rest);
                Value::Empty
            }
            "draweven" | "drawevena" => {
                let y = arg_int(args, 0, -1)?;
                let rest = trailing_ints(args, 1)?;
                self.console.borrow_mut().draw_even(y, &rest);
                Value::Empty
            }
            "consolewidth" => Value::I4(self.console.borrow().console_width() as i32),
            "prespacewidth" => Value::I4(self.console.borrow().pre_space_width() as i32),
            "textwidth" => Value::I4(self.console.borrow().text_width(&arg_str(args, 0)?) as i32),
            "textheight" => Value::I4(self.console.borrow().text_height(&arg_str(args, 0)?) as i32),
            "ydiv" => {
                let v = arg_int(args, 0, 0)?;
                self.console.borrow_mut().set_y_div(v);
                Value::Empty
            }
            "readline" => {
                let prompt = arg_str(args, 0)?;
                let rgb = arg_int(args, 1, -1)?;
                match self.console.borrow_mut().read_line(&prompt, rgb) {
                    Some(line) => Value::str(line),
                    // No more input ends the script, as closing the console
                    // does in the client.
                    None => return Err(VbError::new(QUIT_ERROR, "Input ended")),
                }
            }
            "getkey" => Value::I4(self.console.borrow_mut().get_key() as i32),
            "getascii" => Value::I4(self.console.borrow_mut().get_ascii() as i32),
            "pause" => {
                let prompt = arg_str(args, 0)?;
                let rgb = arg_int(args, 1, -1)?;
                self.console.borrow_mut().read_line(&prompt, rgb);
                Value::Empty
            }
            "edit" => {
                self.assert_local()?;
                let p = self.resolve(&arg_str(args, 0)?);
                self.console.borrow_mut().edit(&p);
                Value::Empty
            }
            "music" => {
                self.assert_local()?;
                let c = arg_str(args, 0)?;
                self.console.borrow_mut().music(&c);
                Value::Empty
            }
            "mail" => {
                self.assert_local()?;
                self.console.borrow_mut().mail();
                Value::Empty
            }
            "printvar" | "printvarsingleifset" => {
                for i in 0..args.len() {
                    let text = format_var(&arg_value(args, i));
                    self.emit(Channel::Say, &text);
                }
                Value::Empty
            }

            // ---- running other scripts -----------------------------------
            "include" => {
                self.assert_local()?;
                let p = self.resolve(&arg_str(args, 0)?);
                let src = self.fs.borrow_mut().read(&p).map_err(fs_error)?;
                let key = self.env.borrow().file_key.clone();
                let src = crypto::decrypt_script(&src, &key)
                    .map_err(|e| misc_error(e.to_string()))?;
                it.execute(&src, false)?;
                Value::Empty
            }
            "includecode" => {
                let src = arg_str(args, 0)?;
                it.execute(&src, false)?;
                Value::Empty
            }
            "run" | "runa" => {
                self.assert_local()?;
                let name = arg_str(args, 0)?;
                let p = self
                    .resolve_command(&name)
                    .ok_or_else(|| fs_error(FsError::NotFound(name)))?;
                let src = self.fs.borrow_mut().read(&p).map_err(fs_error)?;
                let key = self.env.borrow().file_key.clone();
                let src = crypto::decrypt_script(&src, &key)
                    .map_err(|e| misc_error(e.to_string()))?;
                self.run_nested(it, &src, args, 1, false)?
            }
            "runcode" | "runcodea" => {
                let src = arg_str(args, 0)?;
                self.run_nested(it, &src, args, 1, false)?
            }
            "capture" | "capturea" => {
                self.assert_local()?;
                let name = arg_str(args, 0)?;
                let p = self
                    .resolve_command(&name)
                    .ok_or_else(|| fs_error(FsError::NotFound(name)))?;
                let src = self.fs.borrow_mut().read(&p).map_err(fs_error)?;
                let key = self.env.borrow().file_key.clone();
                let src = crypto::decrypt_script(&src, &key)
                    .map_err(|e| misc_error(e.to_string()))?;
                self.run_nested(it, &src, args, 1, true)?
            }
            "capturecode" | "capturecodea" => {
                let src = arg_str(args, 0)?;
                self.run_nested(it, &src, args, 1, true)?
            }
            "dlopen" => {
                self.dl_open(it, &arg_str(args, 0)?)?;
                Value::Empty
            }
            "dlopenhash" => {
                self.dl_open_hash(it, &arg_str(args, 0)?)?;
                Value::Empty
            }
            "dlputhash" => {
                self.assert_local()?;
                let hash = arg_str(args, 0)?;
                if !values::is_hex(&hash) {
                    return Err(misc_error("Invalid hash"));
                }
                let data = arg_str(args, 1)?;
                let handle = self.api(ApiRequest::post(
                    "libraries.php",
                    format!(
                        "put={}&data={}",
                        values::url_encode(&hash.to_lowercase()),
                        values::url_encode(&data)
                    ),
                ));
                // The client waits for the upload before returning.
                if let Some(id) = server::decode_handle(&handle.to_vb_string()?) {
                    self.server.borrow_mut().wait(id);
                }
                Value::Empty
            }
            "isoutputdisabled" => Value::Bool(self.env.borrow().output_disabled),
            "isoutputredirected" => Value::Bool(self.env.borrow().output_redirected),

            // ---- the game server ------------------------------------------
            "lookup" => {
                let d = values::url_encode(&arg_str(args, 0)?);
                self.api(ApiRequest::get(format!("lookup.php?d={d}")))
            }
            "getdomain" => {
                let ip = values::url_encode(&arg_str(args, 0)?);
                self.api(ApiRequest::get(format!("domain_meta.php?getdomain={ip}")))
            }
            "getip" => {
                let d = values::url_encode(&arg_str(args, 0)?);
                self.api(ApiRequest::get(format!("domain_meta.php?getip={d}")))
            }
            "isportopen" | "isdomainonline" => {
                let d = values::url_encode(&arg_str(args, 0)?);
                // `IsDomainOnline` is `IsPortOpen` against port 0.
                let port = if name == "isdomainonline" { 0 } else { arg_int(args, 1, 0)? };
                self.api(
                    ApiRequest::get(format!("ping.php?domain={d}&port={port}"))
                        .with_response_type("bool_1"),
                )
            }
            "waitfor" => {
                let text = arg_str(args, 0)?;
                match server::decode_handle(&text) {
                    Some(id) => Value::str(self.server.borrow_mut().wait(id).body),
                    // Anything that is not a handle passes straight through.
                    None => Value::str(text),
                }
            }
            "waitforraw" => {
                let text = arg_str(args, 0)?;
                let r = match server::decode_handle(&text) {
                    Some(id) => self.server.borrow_mut().wait(id),
                    None => server::ServerResponse::ok(text),
                };
                value_array(vec![Value::I4(r.code as i32), Value::str(r.body)])
            }
            "httprequest" => {
                let url = arg_str(args, 0)?;
                let body = arg_str(args, 1)?;
                let req = if body.is_empty() {
                    ApiRequest::get(url)
                } else {
                    ApiRequest::post(url, body)
                };
                self.api(req)
            }
            "uploadstr" => {
                let d = values::url_encode(&arg_str(args, 0)?);
                let port = arg_int(args, 1, 0)?;
                let data = arg_str(args, 2)?;
                self.api(ApiRequest::post(
                    format!("upload.php?domain={d}&port={port}"),
                    data,
                ))
            }
            "downloadstr" => {
                let d = values::url_encode(&arg_str(args, 0)?);
                let port = arg_int(args, 1, 0)?;
                self.api(ApiRequest::get(format!("download.php?domain={d}&port={port}")))
            }
            "register" | "unregister" | "closeport" => {
                let d = values::url_encode(&arg_str(args, 0)?);
                let extra = if name == "closeport" {
                    format!("&port={}", arg_int(args, 1, 0)?)
                } else {
                    String::new()
                };
                self.api(ApiRequest::get(format!("domain.php?op={name}&d={d}{extra}")))
            }
            "registerprices" => self.api(ApiRequest::get("domain.php?op=prices")),
            "mydomains" | "mysubdomains" | "myips" => {
                self.api(ApiRequest::get(format!("domain_list.php?type={name}")))
            }
            "stats" => self.api(ApiRequest::get("stats.php")),
            "transfer" => {
                let target = values::url_encode(&arg_str(args, 0)?);
                let amount = arg_int(args, 1, 0)?;
                let desc = values::url_encode(&arg_str(args, 2)?);
                self.api(ApiRequest::get(format!(
                    "transfer.php?to={target}&amount={amount}&desc={desc}"
                )))
            }
            "sendmailtouser" => {
                let from = values::url_encode(&arg_str(args, 0)?);
                let subject = values::url_encode(&arg_str(args, 1)?);
                let body = arg_str(args, 2)?;
                self.api(ApiRequest::post(
                    format!("mail.php?from={from}&subject={subject}"),
                    body,
                ))
            }
            "login" | "logout" => {
                self.api(ApiRequest::get(format!("account.php?op={name}")))
            }
            // Remote and server-side file operations share one endpoint,
            // differing only in which domain they address.
            "remotewrite" | "remoteappend" | "remotesafeappend" | "remotedelete"
            | "remotedir" | "remoteview" | "remotetoken" => {
                let domain = values::url_encode(&arg_str(args, 0)?);
                let op = name.trim_start_matches("remote");
                let rest = values::url_encode(&arg_str(args, 1)?);
                self.api(ApiRequest::post(
                    format!("domain_fs.php?domain={domain}&op={op}&file={rest}"),
                    arg_str(args, 2)?,
                ))
            }
            "serverwrite" | "serverappend" | "serversafeappend" | "serverdelete"
            | "serverdir" | "serverview" | "servertoken" | "fileserver" => {
                let domain = values::url_encode(&self.env.borrow().server_domain.clone());
                let op = name.trim_start_matches("server");
                let rest = values::url_encode(&arg_str(args, 0)?);
                self.api(ApiRequest::post(
                    format!("domain_fs.php?domain={domain}&op={op}&file={rest}"),
                    arg_str(args, 1)?,
                ))
            }
            "fetch" | "fetcha" | "connect" | "connecta" => {
                let domain = values::url_encode(&arg_str(args, 0)?);
                let port = arg_int(args, 1, 0)?;
                self.api(ApiRequest::get(format!(
                    "connect.php?domain={domain}&port={port}"
                )))
            }
            "requestreadfile" | "requestwritefile" => Value::str(""),

            // Anything else may belong to a library the script opened.
            other => {
                if self.env.borrow().loaded_libraries.contains("termlib")
                    && termlib::provides(other)
                {
                    match termlib::call(self, other, args)? {
                        Some(v) => v,
                        None => return Ok(None),
                    }
                } else {
                    return Ok(None);
                }
            }
        };
        Ok(Some(v))
    }
}

impl<C: Console, F: FileSystem, S: GameServer> GameHost<C, F, S> {
    /// Find the script behind a command name.
    ///
    /// A name containing a separator is taken as a path. Otherwise `.ds` is
    /// appended if missing and the search path is tried in order, so a
    /// command in the working directory can shadow nothing but is still
    /// reachable. `None` means no such command.
    pub fn resolve_command(&self, command: &str) -> Option<String> {
        if command.contains('/') || command.contains('\\') {
            let path = self.resolve(command);
            return self.fs.borrow_mut().exists(&path).then_some(path);
        }

        let file = if command.to_ascii_lowercase().ends_with(".ds") {
            command.to_string()
        } else {
            format!("{command}.ds")
        };
        for dir in COMMAND_PATH {
            let path = self.resolve(&format!("{dir}/{file}"));
            if self.fs.borrow_mut().exists(&path) {
                return Some(path);
            }
        }
        None
    }

    /// Rewrite a line the player typed into the VBScript to run.
    ///
    /// This is the console's entry point: it decides whether `dir /home` is
    /// a command or script, and resolves bare words against what the session
    /// has actually defined.
    pub fn parse_command_line(
        &self,
        it: &Interp,
        input: &str,
        state: &mut cli::CommandState,
    ) -> Result<String, cli::CommandError> {
        let ctx = HostCommandContext { host: self, interp: it };
        cli::parse_command_line(input, state, &ctx, false)
    }

    /// `DLOpen`: bring in a library by name.
    ///
    /// `termlib` is built in, so opening it only records that its names are
    /// now visible. Any other name is a script under `/system/libs`. A name
    /// containing a path separator is ignored rather than rejected, which is
    /// what the client does — it stops a script reaching outside that
    /// directory.
    fn dl_open(&self, it: &mut Interp, library: &str) -> VbResult<()> {
        let name = library.trim().to_ascii_lowercase();

        if name == "termlib" {
            self.env.borrow_mut().loaded_libraries.insert(name);
            return Ok(());
        }
        if name.contains('/') || name.contains('\\') {
            return Ok(());
        }
        if !self.env.borrow_mut().loaded_libraries.insert(name.clone()) {
            // Already open; including it twice would redefine its procedures.
            return Ok(());
        }

        let path = format!("/system/libs/{name}.ds");
        let source = self.fs.borrow_mut().read(&path).map_err(fs_error)?;
        let source = self.decrypt_library(&source)?;
        it.execute(&source, false)
    }

    /// `DLOpenHash`: bring in a library by content hash.
    ///
    /// The copy under `/system/libs` is a cache. It is only trusted when it
    /// hashes to the name it is filed under, so a corrupt or tampered file
    /// is refetched rather than run.
    fn dl_open_hash(&self, it: &mut Interp, hash: &str) -> VbResult<()> {
        if !values::is_hex(hash) {
            return Err(misc_error("Invalid hash"));
        }
        let hash = hash.to_lowercase();
        let path = format!("/system/libs/hash_{hash}.ds");

        let cached = self.fs.borrow_mut().read(&path).unwrap_or_default();
        let source = if crypto::sha256_hex(cached.as_bytes()) == hash {
            cached
        } else {
            // Drop the bad cache entry and ask the server for the real one.
            let _ = self.fs.borrow_mut().delete(&path);
            let handle = self.api(ApiRequest::post(
                "libraries.php",
                format!("get={}", values::url_encode(&hash)),
            ));
            let body = match server::decode_handle(&handle.to_vb_string()?) {
                Some(id) => self.server.borrow_mut().wait(id).body,
                None => String::new(),
            };
            if crypto::sha256_hex(body.as_bytes()) != hash {
                return Err(misc_error("Could not download hash library correctly :("));
            }
            self.fs.borrow_mut().write(&path, &body).map_err(fs_error)?;
            body
        };

        if !self.env.borrow_mut().loaded_libraries.insert(format!("hash_{hash}")) {
            return Ok(());
        }
        let source = self.decrypt_library(&source)?;
        it.execute(&source, false)
    }

    /// A library may itself be compiled, in which case it is keyed the same
    /// way a downloaded script is.
    fn decrypt_library(&self, source: &str) -> VbResult<String> {
        let key = self.env.borrow().file_key.clone();
        crypto::decrypt_script(source, &key).map_err(|e| misc_error(e.to_string()))
    }

    pub(crate) fn mission_file(&self, mission_id: &str) -> String {
        let safe = mission_id.replace(['/', '\\'], "_");
        format!("/system/missions/{}_{safe}.ini", self.env.borrow().script_owner)
    }

    pub(crate) fn read_ini(&self, file: &str, section: &str, key: &str) -> String {
        match self.fs.borrow_mut().read(file) {
            Ok(text) => fs::ini_get(&text, section, key),
            // A missing file reads as a missing key.
            Err(_) => String::new(),
        }
    }

    pub(crate) fn write_ini(&self, file: &str, section: &str, key: &str, value: &str) -> VbResult<()> {
        let text = self.fs.borrow_mut().read(file).unwrap_or_default();
        let updated = fs::ini_set(&text, section, key, value);
        self.fs.borrow_mut().write(file, &updated).map_err(fs_error)
    }

    /// Run a nested script. `capture` redirects its output into a string
    /// instead of the console, which is what `Capture` is for.
    fn run_nested(
        &self,
        it: &mut Interp,
        source: &str,
        args: &[ArgVal],
        first_arg: usize,
        capture: bool,
    ) -> VbResult<Value> {
        // Swap in the nested script's environment, then release the borrow:
        // the script about to run will call back into this same host.
        let (saved_args, saved_capture) = {
            let mut env = self.env.borrow_mut();
            let mut nested: Vec<Value> =
                args.iter().skip(first_arg).map(|a| a.value()).collect();
            // Index 0 is the command name, so the caller's arguments start at 1.
            nested.insert(0, Value::str(""));
            let saved_args = std::mem::replace(&mut env.args, nested);
            let saved_capture = if capture {
                Some(env.captured.replace(String::new()))
            } else {
                None
            };
            (saved_args, saved_capture)
        };

        let result = it.execute(source, false);

        let out = {
            let mut env = self.env.borrow_mut();
            env.args = saved_args;
            match saved_capture {
                Some(previous) => std::mem::replace(&mut env.captured, previous),
                None => None,
            }
        };

        match result {
            Ok(()) => {}
            // A nested script that quits stops itself, not its caller.
            Err(e) if e.number == QUIT_ERROR => {}
            Err(e) => return Err(e),
        }
        Ok(Value::str(out.unwrap_or_default()))
    }
}

/// Answers the command-line parser's questions from the live session.
struct HostCommandContext<'a, C, F, S> {
    host: &'a GameHost<C, F, S>,
    interp: &'a Interp,
}

impl<C: Console, F: FileSystem, S: GameServer> cli::CommandContext
    for HostCommandContext<'_, C, F, S>
{
    fn command_exists(&self, name: &str) -> bool {
        let path = format!("/system/commands/{}.ds", name.to_ascii_lowercase());
        self.host.fs.borrow_mut().exists(&path)
    }

    fn is_defined(&self, name: &str) -> bool {
        self.interp.is_defined(name)
    }

    fn is_help_topic(&self, name: &str) -> bool {
        let path = format!("/system/commands/help/functions/{name}.ds");
        self.host.fs.borrow_mut().exists(&path)
    }
}

/// Join a `Say`-style parameter list, which the client concatenates.
fn join_params(args: &[ArgVal]) -> VbResult<String> {
    let mut out = String::new();
    for a in args {
        if a.is_missing() {
            continue;
        }
        out.push_str(&a.value().to_vb_string()?);
    }
    Ok(out)
}

/// Flatten the trailing arguments of the `Draw*` functions, which accept
/// either a list of numbers or a single array of them.
fn trailing_ints(args: &[ArgVal], from: usize) -> VbResult<Vec<i64>> {
    let mut out = Vec::new();
    for a in args.iter().skip(from) {
        match a.value() {
            Value::Array(arr) => {
                for v in &arr.data {
                    out.push(v.to_f64()? as i64);
                }
            }
            other => out.push(other.to_f64()? as i64),
        }
    }
    Ok(out)
}

/// `Display`'s line window: `start` is 1-based, and `max` of 0 means all.
fn select_lines(text: &str, start: i64, max: i64) -> String {
    let start = start.max(1);
    let mut out = String::new();
    for (i, line) in text.lines().enumerate() {
        let n = i as i64 + 1;
        if n < start {
            continue;
        }
        if max > 0 && n >= start + max {
            break;
        }
        out.push_str(line);
        out.push_str("\r\n");
    }
    out
}

/// `PrintVar`'s rendering of a value, used for script debugging.
fn format_var(v: &Value) -> String {
    match v {
        Value::Array(a) => {
            let inner: Vec<String> = a.data.iter().map(format_var).collect();
            format!("Array({})", inner.join(", "))
        }
        Value::Obj(None) => "Nothing".into(),
        Value::Obj(Some(_)) => "Object".into(),
        Value::Null => "Null".into(),
        Value::Empty => "Empty".into(),
        other => other.to_vb_string().map(|s| s.to_string()).unwrap_or_default(),
    }
}

/// Run a script, treating `Quit` as a normal ending rather than a failure.
pub fn run_script(it: &mut Interp, source: &str) -> Result<(), VbError> {
    let program = crate::parser::parse(source).map_err(|e| {
        let mut err = VbError::new(1002, format!("Syntax error: {}", e.msg));
        err.source = Rc::from("Microsoft VBScript compilation error");
        err
    })?;
    match it.run(&program) {
        Ok(()) => Ok(()),
        Err(e) if e.number == QUIT_ERROR => Ok(()),
        Err(e) => Err(e),
    }
}
