//! Talks to the real game server.
//!
//! These are ignored by default: they need the network and an account. Run
//! them with credentials in the environment, which keeps the credentials out
//! of the repository:
//!
//! ```sh
//! DSO_USER=... DSO_PASS=... cargo test --test live_server -- --ignored --nocapture
//! ```

#![cfg(feature = "native-http")]

use std::rc::Rc;

use vbscript::game::console::RecordingConsole;
use vbscript::game::fs::MemoryFs;
use vbscript::game::http::HttpServer;
use vbscript::game::protocol::Credentials;
use vbscript::game::{run_script, Env, GameHost};
use vbscript::interp::Interp;
use vbscript::value::Value;

fn credentials() -> Credentials {
    let user = std::env::var("DSO_USER").expect("set DSO_USER");
    let pass = std::env::var("DSO_PASS").expect("set DSO_PASS");
    Credentials::new(user, pass)
}

type Host = GameHost<RecordingConsole, MemoryFs, HttpServer>;

fn host_with(args: Vec<Value>) -> Host {
    GameHost::new(
        RecordingConsole::new(),
        MemoryFs::new(),
        HttpServer::new(credentials()),
    )
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
        std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
            .parent()
            .unwrap()
            .join("client-legacy/user/system/commands/ping.ds"),
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
