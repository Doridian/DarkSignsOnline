//! Talks to the real game server.
//!
//! These are ignored by default: they need the network and an account. Run
//! them with credentials in the environment, which keeps the credentials out
//! of the repository:
//!
//! ```sh
//! DSO_USER=... DSO_PASS=... cargo test --test live_server -- --ignored --nocapture
//! ```
//!
//! `DSO_API_ROOT` points them at another instance -- a local `php -S` over a
//! scratch database, say -- which is how anything that writes can be tried
//! without putting it in the live room.

#![cfg(feature = "native-http")]

use std::rc::Rc;

use vbscript::game::console::RecordingConsole;
use vbscript::game::fs::MemoryFs;
use vbscript::game::http::HttpServer;
use vbscript::game::protocol::Credentials;
use vbscript::game::server::{ApiRequest, GameServer};
use vbscript::game::chat;
use vbscript::game::{run_script, Env, GameHost};
use vbscript::interp::Interp;
use vbscript::value::Value;

fn credentials() -> Credentials {
    let user = std::env::var("DSO_USER").expect("set DSO_USER");
    let pass = std::env::var("DSO_PASS").expect("set DSO_PASS");
    Credentials::new(user, pass)
}

type Host = GameHost<RecordingConsole, MemoryFs, HttpServer>;

/// The server under test: the live one unless `DSO_API_ROOT` names another.
fn server() -> HttpServer {
    let http = HttpServer::new(credentials());
    match std::env::var("DSO_API_ROOT") {
        Ok(root) => http.with_api_root(root),
        Err(_) => http,
    }
}

fn host_with(args: Vec<Value>) -> Host {
    GameHost::new(RecordingConsole::new(), MemoryFs::new(), server())
        .with_env(Env { args, ..Default::default() })
}

fn run_on(host: Host, source: &str) -> (Rc<Host>, Result<(), String>) {
    let host = Rc::new(host);
    let mut it = Interp::with_host(host.clone());
    it.set_step_budget(200_000);
    let r = run_script(&mut it, source).map_err(|e| e.to_string());
    (host, r)
}

#[test]
#[ignore = "needs the network and an account"]
fn stats_comes_back_without_the_legacy_code_prefix() {
    let (host, r) = run_on(host_with(vec![]), r#"Say WaitFor(Stats())"#);
    r.expect("the script ran");
    let out = host.console.borrow().output();
    let line = out.first().expect("something was said");
    println!("stats: {line}");

    assert!(line.contains("You have"), "unexpected body: {line}");
    // The legacy protocol prefixes every body with a four-character code.
    // Getting one here means the version header did not take effect.
    assert!(
        !line.starts_with("2000"),
        "server answered in legacy mode: {line}"
    );
}

#[test]
#[ignore = "needs the network and an account"]
fn lookup_reports_a_known_domain() {
    let (host, r) = run_on(
        host_with(vec![]),
        r#"Say WaitFor(Lookup("darksigns.com"))"#,
    );
    r.expect("the script ran");
    let out = host.console.borrow().output();
    println!("lookup: {}", out[0]);
    assert!(out[0].contains("darksigns.com"));
    assert!(!out[0].starts_with("2000"), "legacy mode");
}

#[test]
#[ignore = "needs the network and an account"]
fn the_ping_command_runs_against_the_real_server() {
    // The shipped command, unmodified, against the live API.
    let source = std::fs::read_to_string(
        std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("user/system/commands/ping.ds"),
    )
    .unwrap();

    let (host, r) = run_on(
        host_with(vec![Value::str("ping"), Value::str("darksigns.com")]),
        &source,
    );
    r.expect("the script ran");
    let out = host.console.borrow().output();
    println!("ping: {}", out[0]);
    // Either answer is fine; what matters is that bool_1 shaping worked and
    // the script took one of its two branches.
    assert!(
        out[0].contains("is online") || out[0].contains("is offline"),
        "unexpected: {}",
        out[0]
    );
}

#[test]
#[ignore = "needs the network and an account"]
fn a_bad_password_is_reported_rather_than_silently_succeeding() {
    let host = GameHost::new(
        RecordingConsole::new(),
        MemoryFs::new(),
        // The real username with a wrong password, so the server rejects
        // the credentials rather than the account.
        HttpServer::new(Credentials::new(
            std::env::var("DSO_USER").expect("set DSO_USER"),
            "definitely-not-the-password",
        )),
    );
    let (_, r) = run_on(host, r#"Say WaitFor(Stats())"#);
    let err = r.expect_err("a wrong password must fail");
    println!("rejected: {err}");
    assert!(err.contains("HTTP error"), "unexpected: {err}");
}

// ---- chat ---------------------------------------------------------------
//
// These write, so they are meant for a scratch instance: point `DSO_API_ROOT`
// at one rather than saying "hello" in the live room every time the suite
// runs.

/// The whole chain for a script that talks: the interpreter's `ChatSend`,
/// the request `chat.php` accepts, the row it writes, and the line that
/// comes back out of a read.
#[test]
#[ignore = "needs the network and an account"]
fn chatsend_reaches_the_room_and_reads_back() {
    let marker = format!("live test {}", std::process::id());

    let (host, r) = run_on(host_with(vec![]), &format!(r#"ChatSend "{marker}""#));
    r.expect("the script ran");

    // The console event carries the id the server gave the row, which is
    // what tells a front end it has already seen the line.
    let events = host.console.borrow().events.clone();
    let sent = events
        .iter()
        .find_map(|e| match e {
            vbscript::game::console::ConsoleEvent::ChatSent { id, text } => Some((*id, text.clone())),
            _ => None,
        })
        .unwrap_or_else(|| panic!("nothing was sent; events: {events:?}"));
    println!("sent as X_{}: {}", sent.0, sent.1);
    assert!(sent.0 > 0, "the row was given an id");
    assert!(sent.1.ends_with(&marker), "shown as said: {}", sent.1);

    // And it is in the room. The read goes straight to the server rather
    // than through a script, since no script function reads chat -- the
    // page's poll is what does, through `Session::chatFetch`.
    let mut http = server();
    let id = http.send(ApiRequest::get(chat::read_path(sent.0 - 1)));
    let response = http.wait(id);
    assert!(response.is_success(), "read failed: {response:?}");

    let lines = chat::parse_log(&response.body);
    println!("read back {} line(s)", lines.len());
    let found = lines
        .iter()
        .find(|l| l.id == sent.0)
        .unwrap_or_else(|| panic!("the line just said is not in the room: {:?}", response.body));
    assert_eq!(found.text, marker, "and it came back as it was said");
    assert!(!found.action, "it was not a /me");
    assert_eq!(found.render(), sent.1, "the same line the console was shown");
}

/// `ChatView` is local state and says so on the communications channel; it
/// makes no request at all, which is worth pinning against a real server.
#[test]
#[ignore = "needs the network and an account"]
fn chatview_talks_to_nobody() {
    let (host, r) = run_on(host_with(vec![]), "ChatView True");
    r.expect("the script ran");
    assert_eq!(host.console.borrow().comm_output(), vec!["Chatview is now enabled."]);
}
