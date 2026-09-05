//! Exercises the DarkSigns host API by running VBScript against it.
//!
//! Each test builds a host from the in-memory doubles, runs a script, and
//! asserts on what the script printed or what it left behind in the
//! filesystem — the same way a `.ds` command is exercised in the game.

use std::rc::Rc;

use vbscript::game::console::{Channel, ConsoleEvent, DrawMode, RecordingConsole};
use vbscript::game::fs::{FileSystem, MemoryFs};
use vbscript::game::server::ScriptedServer;
use vbscript::game::{run_script, Env, GameHost};
use vbscript::interp::Interp;
use vbscript::value::Value;

type Host = GameHost<RecordingConsole, MemoryFs, ScriptedServer>;

/// Build a host, run `source` on it, and hand back the host for assertions.
fn run(host: Host, source: &str) -> (Rc<Host>, Result<(), String>) {
    let host = Rc::new(host);
    let mut it = Interp::with_host(host.clone());
    it.set_step_budget(200_000);
    let result = run_script(&mut it, source).map_err(|e| e.to_string());
    (host, result)
}

/// Run and require success, returning the console output.
fn output_of(host: Host, source: &str) -> Vec<String> {
    let (host, result) = run(host, source);
    result.expect("script ran");
    let out = host.console.borrow().output();
    out
}

fn plain_host() -> Host {
    GameHost::new(RecordingConsole::new(), MemoryFs::new(), ScriptedServer::new())
}

// ---- output -------------------------------------------------------------

#[test]
fn say_writes_a_line() {
    let out = output_of(plain_host(), r#"Say "hello""#);
    assert_eq!(out, vec!["hello"]);
}

#[test]
fn say_concatenates_its_parameter_list() {
    // The client's `Say` takes a ParamArray and joins it.
    let out = output_of(plain_host(), r#"Say "a", "b", 3"#);
    assert_eq!(out, vec!["ab3"]);
}

#[test]
fn saycomm_goes_to_its_own_channel() {
    let (host, r) = run(plain_host(), r#"SayCOMM "system message""#);
    r.unwrap();
    let h = &host;
    assert!(h.console.borrow().output().is_empty(), "not on the main channel");
    assert_eq!(
        h.console.borrow().events[0],
        ConsoleEvent::Say { channel: Channel::Comm, text: "system message".into() }
    );
}

#[test]
fn draw_records_its_mode_and_colour() {
    let (host, r) = run(plain_host(), r#"draw -1, RGB(0, 255, 0), "fadecenter""#);
    r.unwrap();
    assert_eq!(
        host.console.borrow().events[0],
        ConsoleEvent::Draw { y: -1, rgb: 0x00FF00, mode: DrawMode::FadeCenter, segments: 0 }
    );
}

#[test]
fn console_measurements_are_available_to_scripts() {
    let out = output_of(
        plain_host(),
        r#"Say ConsoleWidth() & ":" & TextWidth("{{red}}abc") & ":" & PreSpaceWidth()"#,
    );
    assert_eq!(out, vec!["80:3:0"]);
}

// ---- script environment -------------------------------------------------

#[test]
fn argv_and_argc_expose_the_command_line() {
    let host = plain_host().with_env(Env {
        args: vec![Value::str("ping"), Value::str("example.com"), Value::str("80")],
        ..Default::default()
    });
    let out = output_of(host, r#"Say ArgC() & " " & ArgV(1) & " " & ArgV(2)"#);
    assert_eq!(out, vec!["2 example.com 80"]);
}

#[test]
fn argv_past_the_end_is_empty_rather_than_an_error() {
    let host = plain_host().with_env(Env {
        args: vec![Value::str("cmd")],
        ..Default::default()
    });
    let out = output_of(host, r#"Say "[" & ArgV(5) & "]""#);
    assert_eq!(out, vec!["[]"]);
}

#[test]
fn quit_stops_the_script_without_failing_it() {
    let out = output_of(plain_host(), "Say \"before\"\r\nQuit\r\nSay \"after\"");
    assert_eq!(out, vec!["before"], "nothing after Quit runs");
}

// ---- pure helpers -------------------------------------------------------

#[test]
fn value_helpers_match_the_client() {
    let out = output_of(
        plain_host(),
        r#"
        Say FormatKB(2048)
        Say BoolToString("yes")
        Say Coalesce(Empty, "picked")
        Say URLEncode("a b+c")
        Say IsHex("DEAD01")
        Say TrimWithNewline("  x  ")
        "#,
    );
    assert_eq!(out, vec!["2.00 KB", "True", "picked", "a+b%2Bc", "True", "x"]);
}

#[test]
fn an_invalid_boolean_word_raises() {
    let (_, r) = run(plain_host(), r#"Say BoolToString("perhaps")"#);
    assert!(r.unwrap_err().contains("Invalid value for boolean"));
}

#[test]
fn rgb_helpers_round_trip() {
    let out = output_of(
        plain_host(),
        r#"
        Dim parts
        parts = RGBSplit(RGB(1, 2, 3))
        Say parts(0) & "," & parts(1) & "," & parts(2)
        Say RGBJoin(parts)
        "#,
    );
    assert_eq!(out, vec!["1,2,3".to_string(), (1 | (2 << 8) | (3 << 16)).to_string()]);
}

#[test]
fn console_escaping_survives_a_round_trip_through_a_script() {
    let out = output_of(
        plain_host(),
        r#"Say ConsoleUnescape(ConsoleEscape("{{red}}"))"#,
    );
    assert_eq!(out, vec!["{{red}}"]);
}

// ---- crypto -------------------------------------------------------------

#[test]
fn sha256_is_available_to_scripts() {
    let out = output_of(plain_host(), r#"Say SHA256("abc")"#);
    assert_eq!(
        out,
        vec!["ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"]
    );
}

#[test]
fn encrypt_and_decrypt_round_trip_in_script() {
    let out = output_of(
        plain_host(),
        r#"
        Dim c
        c = Encrypt("secret text", "pw", True)
        Say Decrypt(c, "pw")
        "#,
    );
    assert_eq!(out, vec!["secret text"]);
}

#[test]
fn compilestr_produces_a_loadable_script() {
    let out = output_of(
        plain_host(),
        r#"
        Dim c
        c = CompileStr("Say ""x""" & vbCrLf, "k")
        Say Left(c, 21)
        "#,
    );
    assert_eq!(out, vec!["Option DSciptCompiled"]);
}

#[test]
fn base64_round_trips_in_script() {
    let out = output_of(
        plain_host(),
        r#"Say DecodeBase64Str(EncodeBase64Str("hello"))"#,
    );
    assert_eq!(out, vec!["hello"]);
}

// ---- local files --------------------------------------------------------

fn fs_host() -> Host {
    let fs = MemoryFs::new()
        .with_file("/home/notes.txt", "line one\r\nline two\r\nline three\r\n")
        .with_dir("/home/sub");
    GameHost::new(RecordingConsole::new(), fs, ScriptedServer::new()).with_env(Env {
        cwd: "/home".into(),
        ..Default::default()
    })
}

#[test]
fn file_predicates_see_the_filesystem() {
    let out = output_of(
        fs_host(),
        r#"
        Say FileExists("notes.txt")
        Say FileExists("missing.txt")
        Say DirExists("sub")
        Say DirExists("notes.txt")
        Say FileLen("notes.txt")
        "#,
    );
    assert_eq!(out, vec!["True", "False", "True", "False", "32"]);
}

#[test]
fn overwrite_and_append_change_the_file() {
    let (host, r) = run(
        fs_host(),
        r#"
        Overwrite "out.txt", "first"
        Append "out.txt", "-second"
        "#,
    );
    r.unwrap();
    assert_eq!(host.fs.borrow().read("/home/out.txt").unwrap(), "first-second");
}

#[test]
fn paths_resolve_against_the_working_directory() {
    let (host, r) = run(
        fs_host(),
        r#"
        Say ResolvePath("x.txt")
        Say ResolvePath("../other/y.txt")
        Say ResolvePath("/absolute")
        "#,
    );
    r.unwrap();
    assert_eq!(
        host.console.borrow().output(),
        vec!["/home/x.txt", "/other/y.txt", "/absolute"]
    );
}

#[test]
fn cd_changes_where_relative_paths_land() {
    let (host, r) = run(
        fs_host(),
        r#"
        CD "sub"
        Overwrite "inner.txt", "data"
        "#,
    );
    r.unwrap();
    assert!(host.fs.borrow().exists("/home/sub/inner.txt"));
}

#[test]
fn cd_into_a_missing_directory_fails() {
    let (_, r) = run(fs_host(), r#"CD "nowhere""#);
    assert!(r.is_err());
}

#[test]
fn readdir_marks_directories_with_a_slash() {
    let out = output_of(
        fs_host(),
        r#"
        Dim entries, i
        entries = ReadDir(".")
        For i = LBound(entries) To UBound(entries)
            Say entries(i)
        Next
        "#,
    );
    assert_eq!(out, vec!["notes.txt", "sub/"]);
}

#[test]
fn cat_reads_a_window_of_lines() {
    let out = output_of(
        fs_host(),
        r#"
        Say Cat("notes.txt", 2, 1)
        "#,
    );
    assert_eq!(out, vec!["line two\r\n"]);
}

#[test]
fn cat_without_a_window_reads_everything() {
    let out = output_of(fs_host(), r#"Say Cat("notes.txt")"#);
    assert_eq!(out, vec!["line one\r\nline two\r\nline three\r\n"]);
}

#[test]
fn directories_can_be_made_and_removed() {
    let (host, r) = run(
        fs_host(),
        r#"
        MD "fresh"
        Say DirExists("fresh")
        RD "fresh"
        Say DirExists("fresh")
        "#,
    );
    r.unwrap();
    assert_eq!(host.console.borrow().output(), vec!["True", "False"]);
}

#[test]
fn copy_leaves_the_source_and_rename_does_not() {
    let (host, r) = run(
        fs_host(),
        r#"
        Copy "notes.txt", "copy.txt"
        Rename "copy.txt", "moved.txt"
        Del "notes.txt"
        "#,
    );
    r.unwrap();
    let fs = host.fs.borrow();
    assert!(fs.exists("/home/moved.txt"));
    assert!(!fs.exists("/home/copy.txt"));
    assert!(!fs.exists("/home/notes.txt"));
}

#[test]
fn deleting_a_missing_file_reports_file_not_found() {
    let (_, r) = run(fs_host(), r#"Del "nothing.txt""#);
    assert!(r.unwrap_err().contains("File not found"));
}

// ---- INI and mission data -----------------------------------------------

#[test]
fn ini_values_persist_across_reads() {
    let out = output_of(
        fs_host(),
        r#"
        WriteINI "cfg.ini", "main", "colour", "green"
        WriteINI "cfg.ini", "main", "size", "10"
        Say ReadINI("cfg.ini", "main", "colour", "")
        Say ReadINI("cfg.ini", "main", "size", "")
        Say "[" & ReadINI("cfg.ini", "main", "absent", "") & "]"
        "#,
    );
    assert_eq!(out, vec!["green", "10", "[]"]);
}

#[test]
fn mission_data_is_scoped_to_the_script_owner() {
    let host = GameHost::new(RecordingConsole::new(), MemoryFs::new(), ScriptedServer::new())
        .with_env(Env { script_owner: "alice".into(), ..Default::default() });
    let (host, r) = run(
        host,
        r#"
        SetMissionData "m1", "state", "step", "3"
        Say GetMissionData("m1", "state", "step")
        Say GetMissionFile("m1")
        "#,
    );
    r.unwrap();
    assert_eq!(
        host.console.borrow().output(),
        vec!["3", "/system/missions/alice_m1.ini"]
    );
    assert!(host.fs.borrow().exists("/system/missions/alice_m1.ini"));
}

#[test]
fn mission_ids_cannot_escape_their_directory() {
    let host = plain_host().with_env(Env { script_owner: "bob".into(), ..Default::default() });
    let out = output_of(host, r#"Say GetMissionFile("../../etc/passwd")"#);
    assert_eq!(out, vec!["/system/missions/bob_.._.._etc_passwd.ini"]);
}

// ---- input --------------------------------------------------------------

#[test]
fn readline_returns_queued_input() {
    let host = GameHost::new(
        RecordingConsole::new().with_input(["typed answer"]),
        MemoryFs::new(),
        ScriptedServer::new(),
    );
    let out = output_of(host, r#"Say "you said: " & ReadLine("Prompt?")"#);
    assert_eq!(out, vec!["Prompt?", "you said: typed answer"]);
}

#[test]
fn running_out_of_input_ends_the_script_quietly() {
    let (host, r) = run(
        plain_host(),
        "Say \"before\"\r\nDim x\r\nx = ReadLine(\"?\")\r\nSay \"after\"",
    );
    r.expect("ending input is not a failure");
    assert_eq!(host.console.borrow().output(), vec!["before", "?"]);
}

// ---- the game server ----------------------------------------------------

#[test]
fn network_calls_return_a_handle_that_waitfor_resolves() {
    let server = ScriptedServer::new().answer("ping.php", "1");
    let host = GameHost::new(RecordingConsole::new(), MemoryFs::new(), server);
    let out = output_of(host, r#"Say WaitFor(IsDomainOnline("example.com"))"#);
    assert_eq!(out, vec!["1"]);
}

#[test]
fn waitfor_passes_through_anything_that_is_not_a_handle() {
    let out = output_of(plain_host(), r#"Say WaitFor("plain string")"#);
    assert_eq!(out, vec!["plain string"]);
}

#[test]
fn the_request_carries_the_encoded_domain_and_port() {
    let server = ScriptedServer::new().answer("ping.php", "0");
    let host = GameHost::new(RecordingConsole::new(), MemoryFs::new(), server);
    let (host, r) = run(host, r#"Dim x : x = WaitFor(IsPortOpen("a b.com", 8080))"#);
    r.unwrap();
    assert_eq!(
        host.server.borrow().paths(),
        vec!["ping.php?domain=a+b.com&port=8080"]
    );
}

#[test]
fn lookup_and_getip_hit_their_own_endpoints() {
    let server = ScriptedServer::new()
        .answer("lookup.php", "found")
        .answer("domain_meta.php?getip", "1.2.3.4");
    let host = GameHost::new(RecordingConsole::new(), MemoryFs::new(), server);
    let out = output_of(
        host,
        r#"
        Say WaitFor(Lookup("example.com"))
        Say WaitFor(GetIP("example.com"))
        "#,
    );
    assert_eq!(out, vec!["found", "1.2.3.4"]);
}

#[test]
fn waitforraw_reports_the_status_code_alongside_the_body() {
    let server = ScriptedServer::new()
        .answer_with("stats.php", vbscript::game::server::ServerResponse { code: 404, body: "no".into() });
    let host = GameHost::new(RecordingConsole::new(), MemoryFs::new(), server);
    let out = output_of(
        host,
        r#"
        Dim r
        r = WaitForRaw(Stats())
        Say r(0) & ":" & r(1)
        "#,
    );
    assert_eq!(out, vec!["404:no"]);
}

// ---- running other scripts ----------------------------------------------

#[test]
fn include_brings_in_definitions_from_a_file() {
    let fs = MemoryFs::new().with_file(
        "/system/lib.ds",
        "Function Doubled(n)\r\n    Doubled = n * 2\r\n End Function\r\n",
    );
    let host = GameHost::new(RecordingConsole::new(), fs, ScriptedServer::new());
    let out = output_of(
        host,
        r#"
        Include "/system/lib.ds"
        Say Doubled(21)
        "#,
    );
    assert_eq!(out, vec!["42"]);
}

#[test]
fn includecode_runs_source_from_a_string() {
    let out = output_of(
        plain_host(),
        "IncludeCode \"Dim greeting\" & vbCrLf & \"greeting = \"\"hi\"\"\"\r\nSay greeting",
    );
    assert_eq!(out, vec!["hi"]);
}

#[test]
fn capturecode_collects_output_instead_of_printing_it() {
    let out = output_of(
        plain_host(),
        r#"
        Dim captured
        captured = CaptureCode("Say ""inner""")
        Say "got:" & TrimWithNewline(captured)
        "#,
    );
    assert_eq!(out, vec!["got:inner"], "the inner Say did not reach the console");
}

#[test]
fn a_nested_script_sees_its_own_arguments() {
    let out = output_of(
        plain_host(),
        r#"
        Dim captured
        captured = CaptureCode("Say ArgV(1)", "passed")
        Say TrimWithNewline(captured)
        "#,
    );
    assert_eq!(out, vec!["passed"]);
}

#[test]
fn quitting_a_nested_script_does_not_stop_the_caller() {
    let out = output_of(
        plain_host(),
        r#"
        RunCode "Quit"
        Say "caller kept going"
        "#,
    );
    assert_eq!(out, vec!["caller kept going"]);
}

// ---- remote scripts -----------------------------------------------------

#[test]
fn a_remote_script_cannot_touch_the_local_filesystem() {
    let host = fs_host().with_env(Env {
        cwd: "/home".into(),
        is_local: false,
        ..Default::default()
    });
    let (_, r) = run(host, r#"Say FileExists("notes.txt")"#);
    assert!(
        r.unwrap_err().contains("local script"),
        "remote scripts must be blocked from local files"
    );
}

#[test]
fn a_remote_script_may_still_talk_to_the_server() {
    let server = ScriptedServer::new().answer("ping.php", "1");
    let host = GameHost::new(RecordingConsole::new(), MemoryFs::new(), server)
        .with_env(Env { is_local: false, ..Default::default() });
    let out = output_of(host, r#"Say WaitFor(IsDomainOnline("x.com"))"#);
    assert_eq!(out, vec!["1"]);
}

// ---- real game commands -------------------------------------------------
//
// These run the shipped `.ds` commands unmodified, which is the closest
// thing to exercising the API the way the game does.

fn command_source(name: &str) -> String {
    let path = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .unwrap()
        .join("client-legacy/user/system/commands")
        .join(format!("{name}.ds"));
    std::fs::read_to_string(&path).unwrap_or_else(|e| panic!("reading {}: {e}", path.display()))
}

#[test]
fn the_ping_command_reports_a_server_as_online() {
    let server = ScriptedServer::new().answer("ping.php", "1");
    let host = GameHost::new(RecordingConsole::new(), MemoryFs::new(), server).with_env(Env {
        args: vec![Value::str("ping"), Value::str("example.com")],
        ..Default::default()
    });
    let out = output_of(host, &command_source("ping"));
    assert_eq!(out, vec!["{{green}}Server example.com is online."]);
}

#[test]
fn the_ping_command_reports_a_server_as_offline() {
    let server = ScriptedServer::new().answer("ping.php", "0");
    let host = GameHost::new(RecordingConsole::new(), MemoryFs::new(), server).with_env(Env {
        args: vec![Value::str("ping"), Value::str("example.com")],
        ..Default::default()
    });
    let out = output_of(host, &command_source("ping"));
    assert_eq!(out, vec!["{{red}}Server example.com is offline."]);
}

#[test]
fn the_pingport_command_passes_the_port_through() {
    let server = ScriptedServer::new().answer("ping.php", "1");
    let host = GameHost::new(RecordingConsole::new(), MemoryFs::new(), server).with_env(Env {
        args: vec![Value::str("pingport"), Value::str("example.com"), Value::str("8080")],
        ..Default::default()
    });
    let (host, r) = run(host, &command_source("pingport"));
    r.unwrap();
    assert_eq!(
        host.console.borrow().output(),
        vec!["{{green}}Port 8080 is open on server example.com."]
    );
    assert_eq!(
        host.server.borrow().paths(),
        vec!["ping.php?domain=example.com&port=8080"]
    );
}

#[test]
fn the_dir_command_lists_files_and_directories() {
    let fs = MemoryFs::new()
        .with_file("/home/readme.txt", "some contents here")
        .with_file("/home/notes.md", "x")
        .with_dir("/home/projects");
    let host = GameHost::new(RecordingConsole::new(), fs, ScriptedServer::new()).with_env(Env {
        cwd: "/home".into(),
        args: vec![Value::str("dir")],
        ..Default::default()
    });
    let out = output_of(host, &command_source("dir"));
    let joined = out.join("\n");

    // Directories are bracketed and upper-cased, files carry their size.
    assert!(joined.contains("[PROJECTS]"), "got: {joined}");
    assert!(joined.contains("readme.txt"), "got: {joined}");
    assert!(joined.contains("notes.md"), "got: {joined}");
    assert!(
        joined.contains("2 file(s) and 1 dir(s) found in /home"),
        "got: {joined}"
    );
}

#[test]
fn the_ls_command_includes_dir_and_behaves_the_same() {
    // `ls.ds` is just `Include "/system/commands/dir.ds"`.
    let fs = MemoryFs::new()
        .with_file("/system/commands/dir.ds", &command_source("dir"))
        .with_file("/home/a.txt", "x");
    let host = GameHost::new(RecordingConsole::new(), fs, ScriptedServer::new()).with_env(Env {
        cwd: "/home".into(),
        args: vec![Value::str("ls")],
        ..Default::default()
    });
    let out = output_of(host, &command_source("ls"));
    assert!(out.join("\n").contains("1 file(s) and 0 dir(s)"));
}

#[test]
fn the_compile_command_round_trips_a_script_through_the_filesystem() {
    let fs = MemoryFs::new().with_file("/home/src.ds", "Say \"hello\"\r\n");
    let host = GameHost::new(RecordingConsole::new(), fs, ScriptedServer::new()).with_env(Env {
        cwd: "/home".into(),
        args: vec![Value::str("compile"), Value::str("src.ds"), Value::str("out.ds")],
        ..Default::default()
    });
    let (host, r) = run(host, &command_source("compile"));
    r.unwrap();

    let compiled = host.fs.borrow().read("/home/out.ds").unwrap();
    assert!(vbscript::game::crypto::is_script_compiled(&compiled));
    // `CompileStr` with no key uses the local one.
    assert_eq!(
        vbscript::game::crypto::decrypt_script(&compiled, "local").unwrap(),
        "Say \"hello\"\r\n"
    );
}

#[test]
fn a_compiled_script_can_then_be_included_and_run() {
    let salt = vbscript::game::crypto::generate_salt().unwrap();
    let compiled = vbscript::game::crypto::compile_script(
        "Say \"from a compiled script\"\r\n",
        "local",
        salt,
    )
    .unwrap();
    let fs = MemoryFs::new().with_file("/home/lib.ds", &compiled);
    let host = GameHost::new(RecordingConsole::new(), fs, ScriptedServer::new())
        .with_env(Env { cwd: "/home".into(), ..Default::default() });
    let out = output_of(host, r#"Include "lib.ds""#);
    assert_eq!(out, vec!["from a compiled script"]);
}
