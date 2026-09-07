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

pub mod chat;
pub mod cli;
pub mod console;
pub mod crypto;
pub mod fs;
#[cfg(feature = "native-http")]
pub mod http;
pub mod library;
pub mod mail;
pub mod markup;
pub mod path;
pub mod protocol;
pub mod server;
pub mod termlib;
pub mod values;

use std::cell::RefCell;
use std::rc::Rc;

use crate::error::{VbError, VbResult};
use crate::interp::{ArgVal, Host, Interp};
use crate::value::{VbArray, Value};

use console::{Channel, Console, DrawMode};
use fs::{FileSystem, FsError, NodeKind};
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
        // 54 is "Bad file mode", which is what asking for a directory or
        // for a song as though it were text both amount to.
        FsError::NotADirectory(_) | FsError::IsADirectory(_) | FsError::NotText(_) => 54,
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
    /// Which of the four consoles this script is running in, or 0 for a
    /// script that is not running in one at all.
    pub console_id: i64,
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
            console_id: 0,
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
    pub fn resolve(&self, p: &str) -> String {
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
        // Collecting comes first and disabling second, the order `Say` uses.
        // A script whose output is both collected and hidden -- which is what
        // `Fetch` asks for -- still fills the buffer it is going to return.
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
        if !capturing && !self.env.borrow().output_disabled {
            let mut console = self.console.borrow_mut();
            match channel {
                // `Say` splits on vbCrLf and calls `SayRaw` once per part,
                // because a console row renders one line: handing the whole
                // string over instead loses everything after the first
                // newline, which is what `cat` on a multi-line file is.
                Channel::Say => {
                    for row in console_rows(text) {
                        console.say(channel, row);
                    }
                }
                // `SayCOMM` has no such loop -- a comm message is one line.
                Channel::Comm | Channel::Chat => console.say(channel, text),
            }
        }
    }

    /// `PrintVar`, which has three cases rather than the one it looks like.
    ///
    /// A lone string is said as-is, except that a pending request handle is
    /// awaited first and its result printed instead — that is what lets a
    /// script write `PrintVar Stats()` and see the answer rather than the
    /// handle. Several values are labelled by position, as the client does.
    fn print_var(&self, values: &[Value]) -> VbResult<()> {
        let [only] = values else {
            if values.is_empty() {
                self.emit(Channel::Say, "No arguments to print{{orange}}");
                return Ok(());
            }
            for (i, value) in values.iter().enumerate() {
                self.emit(Channel::Say, &format!("ArgV({i}) {}", format_var(value)));
            }
            return Ok(());
        };

        let Ok(text) = only.to_vb_string() else {
            self.emit(Channel::Say, &format_var(only));
            return Ok(());
        };
        if !matches!(only, Value::Str(_)) {
            self.emit(Channel::Say, &format_var(only));
            return Ok(());
        }
        match server::decode_handle(&text) {
            Some(id) => {
                let shape = self.server.borrow().response_type(id);
                let response = self.server.borrow_mut().wait(id);
                let value = shape_response(&response, shape)?;
                self.print_var(&[value])
            }
            None => {
                self.emit(Channel::Say, &text);
                Ok(())
            }
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
                let salt = crypto::generate_salt(it.host.as_ref()).map_err(|e| misc_error(e.to_string()))?;
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
                let salt = crypto::generate_salt(it.host.as_ref()).map_err(|e| misc_error(e.to_string()))?;
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
            // What a connected script knows about the domain it is serving.
            // Local scripts see the empty values a local environment carries.
            "serverdomain" => Value::str(self.env.borrow().server_domain.clone()),
            "serverip" => Value::str(self.env.borrow().server_ip.clone()),
            "serverport" => Value::I4(self.env.borrow().server_port as i32),
            // Never the password itself, only whether there is one -- the
            // client is careful about this and a connected script is remote
            // code that has no business reading it.
            "password" => Value::str(match self.server.borrow().username().is_empty() {
                true => "",
                false => "[hidden]",
            }),
            "username" => Value::str(self.server.borrow().username()),
            "connectingip" => Value::str(self.env.borrow().connecting_ip.clone()),
            "consoleid" => Value::I4(self.env.borrow().console_id as i32),
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
                let kind = self.fs.borrow().kind(&p).map_err(fs_error)?;
                let text = match kind {
                    NodeKind::Text => self.fs.borrow().read(&p).map_err(fs_error)?,
                    // Reading a song at a terminal gets you what it has
                    // always got you, which is noise.
                    NodeKind::Blob(_) => {
                        let mut bytes = self.fs.borrow().read_blob(&p).map_err(fs_error)?;
                        bytes.truncate(CAT_BLOB_LIMIT);
                        values::console_escape(&bytes_as_noise(&bytes))
                    }
                };
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
            // Chat, which the original spoke to IRC and this client asks
            // the game server for. Both are local-only: a script fetched
            // from someone else's domain does not get to talk in the room
            // as the player.
            "chatsend" => {
                self.assert_local()?;
                let Some(text) = chat::clean(&arg_str(args, 0)?) else {
                    // The original exits its handler on an empty message
                    // rather than sending a blank line.
                    return Ok(Some(Value::Empty));
                };
                let id = self
                    .server
                    .borrow_mut()
                    .send(ApiRequest::post("chat.php", chat::send_body(&text, false)));
                let response = self.server.borrow_mut().wait(id);
                match chat::send_result(&response) {
                    Ok(id) => {
                        let line = chat::Line {
                            id,
                            from: self.server.borrow().username(),
                            text,
                            action: false,
                            date: String::new(),
                        };
                        self.console.borrow_mut().chat_sent(id, &line.render());
                    }
                    // A refusal is the server's own words -- being talked
                    // down for talking too fast, most likely -- and the
                    // communications channel is where the client's own
                    // complaints go.
                    Err(complaint) => self.emit(Channel::Comm, &complaint),
                }
                Value::Empty
            }
            "chatview" => {
                let on = arg_bool(args, 0, true)?;
                self.assert_local()?;
                self.console.borrow_mut().set_chat_view(on);
                self.emit(
                    Channel::Comm,
                    match on {
                        true => "Chatview is now enabled.",
                        false => "Chatview is now disabled.",
                    },
                );
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
                self.console.borrow_mut().music(&resolve_music(&c, |p| self.resolve(p)));
                Value::Empty
            }
            "mail" => {
                self.assert_local()?;
                self.console.borrow_mut().mail();
                Value::Empty
            }
            // The two differ in exactly one way, and merging them was what
            // made a mistyped command print "empty": the console rewrites an
            // unknown bare word to `PrintVarSingleIfSet name()`, so the value
            // it prints is an unset variant. "IfSet" is the instruction to say
            // nothing about that.
            "printvarsingleifset" => {
                let value = arg_value(args, 0);
                if !matches!(value, Value::Empty) {
                    self.print_var(&[value])?;
                }
                Value::Empty
            }
            "printvar" => {
                let values: Vec<Value> =
                    (0..args.len()).map(|i| arg_value(args, i)).collect();
                self.print_var(&values)?;
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
            //
            // Endpoint names and request bodies match the VB6 client
            // exactly; scripts read the raw response, so the shapes are part
            // of the contract with the server.
            "lookup" => self.api(ApiRequest::get(format!(
                "lookup.php?d={}",
                values::url_encode(&arg_str(args, 0)?)
            ))),
            "getdomain" => self.api(ApiRequest::get(format!(
                "domain_meta.php?getdomain={}",
                values::url_encode(&arg_str(args, 0)?)
            ))),
            "getip" => self.api(ApiRequest::get(format!(
                "domain_meta.php?getip={}",
                values::url_encode(&arg_str(args, 0)?)
            ))),
            "isportopen" | "isdomainonline" => {
                let domain = values::url_encode(&arg_str(args, 0)?);
                // `IsDomainOnline` is `IsPortOpen` against port 0.
                let port = if name == "isdomainonline" { 0 } else { arg_int(args, 1, 0)? };
                self.api(
                    ApiRequest::get(format!("ping.php?domain={domain}&port={port}"))
                        .returning(server::ResponseType::Bool1),
                )
            }
            "stats" => self.api(ApiRequest::get("get_user_stats.php")),
            "login" => self.api(ApiRequest::post_empty("auth.php")),
            "logout" => Value::Empty,

            "uploadstr" => {
                self.assert_local()?;
                let domain = arg_str(args, 0)?;
                let port = arg_int(args, 1, 0)?;
                let data = arg_str(args, 2)?;
                // An already-compiled script is re-keyed for its destination
                // before upload.
                let payload = if crypto::is_script_compiled(&data) {
                    let key = format!("dso://{}:{port}", domain.to_lowercase());
                    let salt = crypto::generate_salt(it.host.as_ref()).map_err(|e| misc_error(e.to_string()))?;
                    crypto::compile_script(&data, &key, salt)
                        .map_err(|e| misc_error(e.to_string()))?
                } else {
                    data
                };
                let encoded = crypto::encode_base64(payload.as_bytes());
                self.api(ApiRequest::post(
                    "domain_upload.php",
                    format!(
                        "port={port}&d={}&filedata={}",
                        values::url_encode(&domain),
                        values::url_encode(&encoded)
                    ),
                ))
            }
            "downloadstr" => {
                self.assert_local()?;
                self.api(ApiRequest::post(
                    "domain_download.php",
                    format!(
                        "port={}&d={}",
                        arg_int(args, 1, 0)?,
                        values::url_encode(&arg_str(args, 0)?)
                    ),
                ))
            }
            "register" | "unregister" => {
                self.assert_local()?;
                let endpoint = if name == "register" {
                    "domain_register.php"
                } else {
                    "domain_unregister.php"
                };
                self.api(ApiRequest::post(
                    endpoint,
                    format!("d={}", values::url_encode(&arg_str(args, 0)?)),
                ))
            }
            "registerprices" => self.api(
                ApiRequest::get("domain_register.php?prices=true")
                    .returning(server::ResponseType::Lines),
            ),
            "closeport" => {
                self.assert_local()?;
                self.api(ApiRequest::post(
                    "domain_close.php",
                    format!(
                        "port={}&d={}",
                        arg_int(args, 1, 0)?,
                        values::url_encode(&arg_str(args, 0)?)
                    ),
                ))
            }
            "mydomains" | "mysubdomains" | "myips" => {
                self.assert_local()?;
                let kind = match name {
                    "mydomains" => "domain",
                    "mysubdomains" => "subdomain",
                    _ => "ip",
                };
                self.api(
                    ApiRequest::get(format!("my_domains.php?type={kind}"))
                        .returning(server::ResponseType::Lines),
                )
            }
            "transfer" => {
                let target = arg_str(args, 0)?;
                let amount = arg_int(args, 1, 0)?;
                let description = arg_str(args, 2)?;
                if amount < 1 {
                    return Err(misc_error(format!("Invalid amount: ${amount}.00!")));
                }
                // The VB6 client builds this body and then sends a bare GET,
                // discarding it. Sending it is what the call was meant to do.
                self.api(ApiRequest::post(
                    "transfer.php",
                    format!(
                        "to={}&amount={amount}&description={}",
                        values::url_encode(target.trim()),
                        values::url_encode(description.trim())
                    ),
                ))
            }
            // A connected script mailing the player, which is how the
            // missions hand out their briefings.
            //
            // `server` is not optional in practice. The endpoint defaults it
            // to the player's own `<name>.usr` and then refuses to send from
            // an address whose domain has a different owner -- so a briefing
            // from `terminal@darksigns.com` is rejected outright unless the
            // domain the script is running on comes along with it.
            "sendmailtouser" => {
                let from = arg_str(args, 0)?;
                let subject = arg_str(args, 1)?;
                let body = arg_str(args, 2)?;
                let server = self.env.borrow().server_ip.clone();
                let handle = self.api(ApiRequest::post(
                    "dsmail.php",
                    format!(
                        "action=script_send_to_self&server={}&from={}&subject={}&message={}",
                        values::url_encode(&server),
                        values::url_encode(&from),
                        values::url_encode(&subject),
                        values::url_encode(&body)
                    ),
                ));
                // The client waits for the send before announcing it, and a
                // handle nobody waits on is a request that is never made --
                // which is what left the mission mail unsent.
                if let Some(id) = server::decode_handle(&handle.to_vb_string()?) {
                    self.server.borrow_mut().wait(id);
                }
                self.emit(Channel::Comm, &format!("You got a new DSMail from {from}"));
                Value::Empty
            }
            // Connecting to a domain runs the script that domain answers
            // with; it does not hand back the response. `Fetch` is the same
            // journey with the output collected and returned instead of
            // shown. The `A` variants take the script's arguments as one
            // array rather than as trailing parameters.
            "fetch" | "fetcha" | "connect" | "connecta" => {
                let domain = arg_str(args, 0)?;
                let port = arg_int(args, 1, 0)?;
                let params = match name.ends_with('a') {
                    true => match arg_value(args, 2) {
                        Value::Array(a) => a.data.to_vec(),
                        Value::Empty => Vec::new(),
                        single => vec![single],
                    },
                    false => args.iter().skip(2).map(|a| a.value()).collect(),
                };
                self.connect_raw(it, &domain, port, params, name.starts_with("connect"))?
            }

            // The remote and server filesystem calls share one endpoint,
            // differing only in which domain they name and which operation
            // they ask for.
            "remotewrite" | "remoteappend" | "remotesafeappend" | "remotedelete"
            | "remotedir" | "remoteview" => {
                self.assert_local()?;
                let domain = arg_str(args, 0)?;
                let (op, response) = self.domain_fs_op(name, args, 1)?;
                self.api(self.domain_fs_request(&domain, &op, response))
            }
            "serverwrite" | "serverappend" | "serversafeappend" | "serverdelete"
            | "serverdir" | "serverview" | "fileserver" => {
                let domain = self.env.borrow().server_domain.clone();
                let logical = if name == "fileserver" { "serverview" } else { name };
                let (op, response) = self.domain_fs_op(logical, args, 0)?;
                self.api(self.domain_fs_request(&domain, &op, response))
            }
            "waitfor" => {
                let text = arg_str(args, 0)?;
                match server::decode_handle(&text) {
                    Some(id) => {
                        let shape = self.server.borrow().response_type(id);
                        let response = self.server.borrow_mut().wait(id);
                        shape_response(&response, shape)?
                    }
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
                // The raw form reports the status rather than raising on it.
                value_array(vec![Value::I4(r.code as i32), Value::str(r.body)])
            }
            "httprequest" => {
                // An arbitrary URL, which is the one call that does not go
                // through the game API.
                let url = arg_str(args, 0)?;
                let body = arg_str(args, 1)?;
                let req = if body.is_empty() {
                    ApiRequest::get(url)
                } else {
                    ApiRequest::post(url, body)
                };
                self.api(req)
            }
            "remotetoken" | "servertoken" => {
                let (domain, info) = if name == "remotetoken" {
                    (arg_str(args, 0)?, arg_str(args, 1)?)
                } else {
                    (self.env.borrow().server_domain.clone(), arg_str(args, 0)?)
                };
                let is_local = if self.env.borrow().is_local { "true" } else { "false" };
                self.api(ApiRequest::post(
                    "domain_token.php",
                    format!(
                        // The VB6 client omits this separator, running the
                        // flag and the domain together.
                        "is_local_script={is_local}&d={}&info={}",
                        values::url_encode(&domain),
                        values::url_encode(&info)
                    ),
                ))
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
    /// The operation half of a `domain_filesystem.php` body, and how the
    /// answer should be shaped.
    fn domain_fs_op(
        &self,
        name: &str,
        args: &[ArgVal],
        first: usize,
    ) -> VbResult<(String, server::ResponseType)> {
        let file = values::url_encode(&arg_str(args, first)?);
        let contents = || -> VbResult<String> {
            Ok(values::url_encode(&arg_str(args, first + 1)?))
        };
        Ok(match name.trim_start_matches("remote").trim_start_matches("server") {
            "write" => (format!("write={file}&filedata={}", contents()?), server::ResponseType::Raw),
            "append" => (
                format!("append={file}&filedata={}", contents()?),
                server::ResponseType::Raw,
            ),
            "safeappend" => (
                format!("safeappend={file}&filedata={}", contents()?),
                server::ResponseType::Raw,
            ),
            "delete" => (format!("delete={file}"), server::ResponseType::Raw),
            // `dir` always lists the root and comes back as lines.
            "dir" => ("dir=%2F".to_string(), server::ResponseType::Lines),
            _ => (
                format!(
                    "fileserver={file}&maxlines={}&startline={}",
                    arg_int(args, first + 2, 0)?,
                    arg_int(args, first + 1, 0)?
                ),
                server::ResponseType::Raw,
            ),
        })
    }

    /// Wrap a filesystem operation in the fields every such request carries.
    fn domain_fs_request(
        &self,
        domain: &str,
        op: &str,
        response: server::ResponseType,
    ) -> ApiRequest {
        let env = self.env.borrow();
        let is_local = if env.is_local { "true" } else { "false" };
        ApiRequest::post(
            "domain_filesystem.php",
            format!(
                "is_local_script={is_local}&keycode={}&d={}&{op}",
                values::url_encode(&env.file_key),
                values::url_encode(domain)
            ),
        )
        .returning(response)
    }

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
        // Folded, like any other path: a mission id and an owner name are
        // both spelled however they were typed, and `GetMissionFile` hands
        // this back to the script as a path.
        path::fold_case(&format!(
            "/system/missions/{}_{safe}.ini",
            self.env.borrow().script_owner
        ))
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
    /// `Connect` and `Fetch`: run the script a game domain serves.
    ///
    /// The response describes the domain -- its canonical name, port, address,
    /// owner and file key -- and carries the script itself. The script then
    /// runs in an environment built from those fields rather than the local
    /// one, which is what gives `ServerDomain`, `ServerIP` and `ScriptOwner`
    /// something to say inside it, and what makes `IsLocal` false so the
    /// local filesystem stays out of reach.
    ///
    /// `Connect` is a Sub: it announces itself and lets the script's output
    /// through to the console. `Fetch` is silent and returns that output. A
    /// `Connect` made from inside a `Capture` behaves like `Fetch` and says
    /// the collected text, which is how the client nests the two.
    fn connect_raw(
        &self,
        it: &mut Interp,
        domain: &str,
        port: i64,
        params: Vec<Value>,
        connect: bool,
    ) -> VbResult<Value> {
        if !(1..=65535).contains(&port) {
            return Err(misc_error(format!("Invalid Port Number: {port}")));
        }

        let (redirect, disable) = if connect {
            let env = self.env.borrow();
            (env.output_redirected && env.output_disabled, env.output_disabled)
        } else {
            (true, true)
        };

        if connect {
            self.emit(
                Channel::Say,
                &format!("{{{{green}}}}Connecting to {}:{port}...", domain.to_uppercase()),
            );
        }

        let id = self.server.borrow_mut().send(ApiRequest::post_empty(format!(
            "domain_connect.php?d={}&port={port}",
            values::url_encode(domain)
        )));
        let response = self.server.borrow_mut().wait(id);
        match response.code {
            404 => {
                return Err(misc_error(format!(
                    "Could not connect to{}:{port} -> Not found",
                    domain.to_uppercase()
                )))
            }
            403 => {
                return Err(misc_error(format!(
                    "Could not connect to{}:{port} -> Access denied",
                    domain.to_uppercase()
                )))
            }
            _ => {
                shape_response(&response, server::ResponseType::Raw)?;
            }
        }

        // domain :-: port :-: ip :-: owner :-: file key :-: script
        let fields: Vec<&str> = response.body.split(":-:").collect();
        let [d_domain, d_port, d_ip, d_owner, d_key, d_code] = fields[..] else {
            return Err(misc_error(format!(
                "Could not connect to {}:{port} -> malformed response",
                domain.to_uppercase()
            )));
        };

        // A port the server does not state is deliberately absurd rather than
        // zero: zero would read as a local script and unlock the filesystem.
        let stated: i64 = d_port
            .trim()
            .chars()
            .take_while(char::is_ascii_digit)
            .collect::<String>()
            .parse()
            .unwrap_or(0);
        let script_port = if stated > 0 { stated } else { 99999 };
        let owner = match d_owner {
            "" => "unknown".to_string(),
            other => other.to_string(),
        };
        let code = String::from_utf8_lossy(
            &crypto::decode_base64(d_code).map_err(|e| misc_error(e.to_string()))?,
        )
        .into_owned();

        // The script is keyed to whichever name the domain answers to. Try
        // the hostname, and fall back to the address when that does not open
        // it -- a domain registered by address was compiled under one.
        let by_domain = format!("dso://{}:{script_port}", d_domain.to_lowercase());
        let by_ip = format!("dso://{}:{script_port}", d_ip.to_lowercase());
        let key = match crypto::decrypt_script(&code, &by_domain) {
            Ok(_) => by_domain.clone(),
            Err(_) => by_ip,
        };
        let source = crypto::decrypt_script(&code, &key)
            .map_err(|e| misc_error(format!("[DECODING {by_domain}] {e}")))?;

        // A whole environment, not an edit of this one: the connected script
        // gets its own arguments, owner and libraries, and the previous set
        // comes back untouched however it ends.
        let mut script_args = vec![Value::str(by_domain.clone())];
        script_args.extend(params);
        let saved = {
            let mut env = self.env.borrow_mut();
            let fresh = Env {
                cwd: env.cwd.clone(),
                args: script_args,
                script_owner: owner,
                // A connected script still writes to the console that
                // reached out, so it keeps its number.
                console_id: env.console_id,
                file_key: d_key.to_string(),
                server_domain: d_domain.to_string(),
                server_port: script_port,
                server_ip: d_ip.to_string(),
                connecting_ip: env.server_ip.clone(),
                is_local: false,
                quit: false,
                captured: redirect.then(String::new),
                output_disabled: disable,
                output_redirected: redirect,
                loaded_libraries: std::collections::BTreeSet::new(),
            };
            std::mem::replace(&mut *env, fresh)
        };

        let result = it.execute(&source, false);

        let collected = {
            let mut env = self.env.borrow_mut();
            let finished = std::mem::replace(&mut *env, saved);
            finished.captured.unwrap_or_default()
        };

        match result {
            Ok(()) => {}
            // A connected script that quits stops itself, not its caller.
            Err(e) if e.number == QUIT_ERROR => {}
            Err(e) => return Err(VbError::new(e.number, format!("[RUNNING {by_domain}] {e}"))),
        }

        if connect {
            // Only when the caller was collecting output itself.
            if redirect {
                self.emit(Channel::Say, &collected);
            }
            return Ok(Value::Empty);
        }
        Ok(Value::str(collected))
    }

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

/// Turn a response into the value the script asked for, failing when the
/// request itself did.
fn shape_response(
    response: &server::ServerResponse,
    shape: server::ResponseType,
) -> VbResult<Value> {
    if !response.is_success() {
        let first_line = response.body.lines().next().unwrap_or("");
        return Err(VbError::new(
            VB_OBJECT_ERROR + 6000 + response.code as i32,
            format!("HTTP error {}: {first_line}", response.code),
        ));
    }
    let trimmed = values::trim_with_newline(&response.body);
    Ok(match shape {
        server::ResponseType::Raw => Value::str(&response.body),
        server::ResponseType::Bool1 => Value::Bool(trimmed == "1"),
        server::ResponseType::Lines => {
            string_array(trimmed.split("\r\n").map(|l| l.to_string()).collect())
        }
    })
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

/// Split console output into the rows a console draws.
///
/// The client splits on `vbCrLf`; a lone CR or LF ends a row here too, so a
/// file written with bare newlines is not silently cut short. Empty rows are
/// kept, including the trailing one a text ending in a newline produces --
/// `Split` leaves that behind as well.
fn console_rows(text: &str) -> Vec<&str> {
    let bytes = text.as_bytes();
    let mut rows = Vec::new();
    let (mut start, mut i) = (0, 0);
    while i < bytes.len() {
        match bytes[i] {
            b'\r' => {
                rows.push(&text[start..i]);
                i += if bytes.get(i + 1) == Some(&b'\n') { 2 } else { 1 };
                start = i;
            }
            b'\n' => {
                rows.push(&text[start..i]);
                i += 1;
                start = i;
            }
            _ => i += 1,
        }
    }
    rows.push(&text[start..]);
    rows
}

/// `Display`'s line window: `start` is 1-based, and `max` of 0 means all.
/// Resolve the path inside a `Music` command, leaving the rest of it alone.
///
/// `Music "play theme.mp3"` names a file the way every other file call does,
/// so the name is resolved against the working directory here -- the console
/// that plays it has no working directory to resolve it against, and by the
/// time it hears about the command the script that knew may have moved on.
///
/// A command that names no file, `stop` being the one that matters, passes
/// through as it was written.
fn resolve_music(command: &str, resolve: impl Fn(&str) -> String) -> String {
    let trimmed = command.trim();
    let Some((verb, rest)) = trimmed.split_once(char::is_whitespace) else {
        return trimmed.to_string();
    };
    if !matches!(verb.to_ascii_lowercase().as_str(), "play" | "loop") {
        return trimmed.to_string();
    }
    format!("{verb} {}", resolve(rest.trim()))
}

/// The most of a blob `Cat` will pour into the console.
///
/// Reading a song as though it were text is a real thing to do at a real
/// terminal, and the answer there is a screenful of noise, so it is the
/// answer here too. A whole album of it would wedge the console rather than
/// amuse anyone, so the noise stops.
const CAT_BLOB_LIMIT: usize = 64 * 1024;

/// Render bytes the way a terminal shows a file that is not text: printable
/// ones as themselves, the rest as the Latin-1 characters their values name.
///
/// Control bytes become dots instead. They are what a real terminal would
/// act on rather than print -- and acting on them here would mean a file
/// deciding how the console draws, which is not a trick worth allowing.
fn bytes_as_noise(bytes: &[u8]) -> String {
    bytes
        .iter()
        .map(|b| match b {
            b'\r' | b'\n' | b'\t' => *b as char,
            0x00..=0x1f | 0x7f => '.',
            // Anything else is its own code point, which for the high bytes
            // an mp3 is mostly made of means accented letters and symbols.
            _ => *b as char,
        })
        .collect()
}

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
