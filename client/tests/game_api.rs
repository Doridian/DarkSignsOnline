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
    // `IsDomainOnline` asks for the bool_1 shape, so the script gets a
    // Boolean rather than the server's "1".
    let out = output_of(host, r#"Say WaitFor(IsDomainOnline("example.com"))"#);
    assert_eq!(out, vec!["True"]);
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
        .answer_with(
            "get_user_stats.php",
            vbscript::game::server::ServerResponse { code: 404, body: "no".into() },
        );
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
    assert_eq!(out, vec!["True"]);
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

/// A connected script mailing the player is how the missions hand out their
/// briefings, and it went out with neither the domain it was sent from nor
/// anything waiting for it -- so nothing was ever actually sent.
#[test]
fn send_mail_to_user_names_the_domain_and_waits_for_the_send() {
    let server = ScriptedServer::new().answer("dsmail.php", "OK");
    let host = GameHost::new(RecordingConsole::new(), MemoryFs::new(), server).with_env(Env {
        // What a script running on a connected domain sees.
        server_ip: "12.34.56.78".into(),
        server_domain: "darksigns.com".into(),
        is_local: false,
        ..Default::default()
    });
    let (host, result) = run(
        host,
        r#"SendMailToUser "terminal@darksigns.com", "Training Mission", "Objective: one" & vbCrLf & "Objective: two""#,
    );
    result.expect("script ran");

    let server = host.server.borrow();
    let sent = server.requests.first().expect("the request was made");
    assert_eq!(sent.path, "dsmail.php");
    assert_eq!(
        sent.body.as_deref(),
        Some(concat!(
            "action=script_send_to_self&server=12.34.56.78",
            "&from=terminal%40darksigns.com",
            "&subject=Training+Mission",
            "&message=Objective%3A+one%0D%0AObjective%3A+two",
        )),
        "without `server` the endpoint refuses a from-address it does not own"
    );
    assert!(
        server.pending_count() == 0,
        "the send is waited on; a handle nobody waits on is never sent"
    );
    assert_eq!(
        host.console.borrow().comm_output(),
        vec!["You got a new DSMail from terminal@darksigns.com"],
    );
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
    let salt = vbscript::game::crypto::generate_salt(&vbscript::interp::NullHost).unwrap();
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

// ---- libraries ----------------------------------------------------------

#[test]
fn dlopen_loads_a_library_from_the_libs_directory() {
    let fs = MemoryFs::new().with_file(
        "/system/libs/mathlib.ds",
        "Function Cube(n)\r\n    Cube = n * n * n\r\nEnd Function\r\n",
    );
    let host = GameHost::new(RecordingConsole::new(), fs, ScriptedServer::new());
    let out = output_of(
        host,
        r#"
        DLOpen "mathlib"
        Say Cube(3)
        "#,
    );
    assert_eq!(out, vec!["27"]);
}

#[test]
fn opening_the_same_library_twice_does_not_redefine_it() {
    let fs = MemoryFs::new().with_file(
        "/system/libs/once.ds",
        "Dim Counter\r\nCounter = Counter + 1\r\n",
    );
    let host = GameHost::new(RecordingConsole::new(), fs, ScriptedServer::new());
    let out = output_of(
        host,
        r#"
        DLOpen "once"
        DLOpen "once"
        Say Counter
        "#,
    );
    assert_eq!(out, vec!["1"], "the second open is a no-op");
}

#[test]
fn dlopen_refuses_to_reach_outside_the_libs_directory() {
    let fs = MemoryFs::new().with_file("/secret.ds", "Say \"leaked\"\r\n");
    let host = GameHost::new(RecordingConsole::new(), fs, ScriptedServer::new());
    // A name with a separator is ignored rather than loaded.
    let out = output_of(host, r#"DLOpen "../secret""#);
    assert!(out.is_empty(), "nothing from outside /system/libs ran");
}

#[test]
fn opening_a_missing_library_reports_it() {
    let (_, r) = run(plain_host(), r#"DLOpen "nosuchlib""#);
    assert!(r.unwrap_err().contains("File not found"));
}

#[test]
fn a_library_may_itself_be_compiled() {
    let salt = vbscript::game::crypto::generate_salt(&vbscript::interp::NullHost).unwrap();
    let compiled = vbscript::game::crypto::compile_script(
        "Function Answer()\r\n    Answer = 42\r\nEnd Function\r\n",
        "local",
        salt,
    )
    .unwrap();
    let fs = MemoryFs::new().with_file("/system/libs/secret.ds", &compiled);
    let host = GameHost::new(RecordingConsole::new(), fs, ScriptedServer::new());
    let out = output_of(host, "DLOpen \"secret\"\r\nSay Answer()");
    assert_eq!(out, vec!["42"]);
}

#[test]
fn dlopenhash_uses_a_cached_library_when_it_hashes_correctly() {
    let source = "Function Cached()\r\n    Cached = \"from cache\"\r\nEnd Function\r\n";
    let hash = vbscript::game::crypto::sha256_hex(source.as_bytes());
    let fs = MemoryFs::new().with_file(&format!("/system/libs/hash_{hash}.ds"), source);
    let host = GameHost::new(RecordingConsole::new(), fs, ScriptedServer::new());
    let (host, r) = run(host, &format!("DLOpenHash \"{hash}\"\r\nSay Cached()"));
    r.unwrap();
    assert_eq!(host.console.borrow().output(), vec!["from cache"]);
    assert!(
        host.server.borrow().requests.is_empty(),
        "a good cache entry means no download"
    );
}

#[test]
fn dlopenhash_downloads_and_caches_when_the_copy_is_wrong() {
    let source = "Function Fetched()\r\n    Fetched = \"from server\"\r\nEnd Function\r\n";
    let hash = vbscript::game::crypto::sha256_hex(source.as_bytes());
    // The cached file has the right name but the wrong contents.
    let fs = MemoryFs::new().with_file(&format!("/system/libs/hash_{hash}.ds"), "tampered");
    let server = ScriptedServer::new().answer("libraries.php", source);
    let host = GameHost::new(RecordingConsole::new(), fs, server);

    let (host, r) = run(host, &format!("DLOpenHash \"{hash}\"\r\nSay Fetched()"));
    r.unwrap();
    assert_eq!(host.console.borrow().output(), vec!["from server"]);
    // The good copy replaces the bad one.
    assert_eq!(
        host.fs.borrow().read(&format!("/system/libs/hash_{hash}.ds")).unwrap(),
        source
    );
}

#[test]
fn dlopenhash_refuses_a_download_that_does_not_match_its_hash() {
    let hash = "a".repeat(64);
    let server = ScriptedServer::new().answer("libraries.php", "not the right content");
    let host = GameHost::new(RecordingConsole::new(), MemoryFs::new(), server);
    let (_, r) = run(host, &format!("DLOpenHash \"{hash}\""));
    assert!(r.unwrap_err().contains("Could not download hash library"));
}

#[test]
fn dlopenhash_rejects_a_name_that_is_not_a_hash() {
    let (_, r) = run(plain_host(), r#"DLOpenHash "nothex!""#);
    assert!(r.unwrap_err().contains("Invalid hash"));
}

#[test]
fn dlputhash_uploads_the_library() {
    let (host, r) = run(plain_host(), r#"DLPutHash "abcdef", "some source""#);
    r.unwrap();
    let server = host.server.borrow();
    assert_eq!(server.paths(), vec!["libraries.php"]);
    assert_eq!(
        server.requests[0].body.as_deref(),
        Some("put=abcdef&data=some+source")
    );
}

// ---- termlib ------------------------------------------------------------

#[test]
fn termlib_names_are_hidden_until_it_is_opened() {
    let (_, r) = run(plain_host(), r#"SaySlow 1, "hello", "green""#);
    assert!(
        r.unwrap_err().contains("not defined"),
        "termlib must be opened first, as in the client"
    );
}

#[test]
fn sayslow_types_the_line_out_one_character_at_a_time() {
    let (host, r) = run(
        plain_host(),
        "DLOpen \"termlib\"\r\nSaySlow 0, \"abc\", \"green\"",
    );
    r.unwrap();
    let console = host.console.borrow();
    // The first character starts the line, then it is redrawn as it grows.
    assert_eq!(
        console.output(),
        vec!["a{{green}}", "ab", "abc"],
        "each step redraws the same line"
    );
}

#[test]
fn sayslow_prints_the_whole_line_at_once_when_output_is_disabled() {
    let host = plain_host().with_env(Env { output_disabled: false, ..Default::default() });
    let (host, r) = run(
        host,
        "DLOpen \"termlib\"\r\nSaySlow 0, \"abc\", \"{green}\"",
    );
    r.unwrap();
    // The style argument has its braces normalised.
    assert_eq!(host.console.borrow().output()[0], "a{{green}}");
}

#[test]
fn qreadline_normalises_the_answer() {
    let host = GameHost::new(
        RecordingConsole::new().with_input(["  YES  "]),
        MemoryFs::new(),
        ScriptedServer::new(),
    );
    let out = output_of(host, "DLOpen \"termlib\"\r\nSay \"[\" & QReadLine(\"?\") & \"]\"");
    assert_eq!(out, vec!["?", "[yes]"]);
}

#[test]
fn mission_progress_reads_back_what_it_stored() {
    let host = plain_host().with_env(Env { script_owner: "carol".into(), ..Default::default() });
    let (host, r) = run(
        host,
        r#"
        DLOpen "termlib"
        SetMissionProgress "m1", "stage", "2"
        Say GetMissionProgress("m1", "stage")
        Say IntMissionProgress("m1", "stage")
        Say IntMissionProgress("m1", "never-set")
        "#,
    );
    r.unwrap();
    assert_eq!(host.console.borrow().output(), vec!["2", "2", "0"]);
}

#[test]
fn boolean_mission_progress_flips_between_set_and_clear() {
    let out = output_of(
        plain_host(),
        r#"
        DLOpen "termlib"
        Say BoolMissionProgress("m", "flag")
        BoolSetMissionProgress "m", "flag"
        Say BoolMissionProgress("m", "flag")
        BoolClearMissionProgress "m", "flag"
        Say BoolMissionProgress("m", "flag")
        "#,
    );
    assert_eq!(out, vec!["False", "True", "False"]);
}

#[test]
fn mission_progress_counts_up() {
    let out = output_of(
        plain_host(),
        r#"
        DLOpen "termlib"
        IncMissionProgress "m", "count"
        IncMissionProgress "m", "count"
        IncMissionProgress "m", "count"
        Say IntMissionProgress("m", "count")
        "#,
    );
    assert_eq!(out, vec!["3"]);
}

#[test]
fn getasciiwithprompt_shows_the_key_it_read() {
    let host = GameHost::new(
        // 'y'
        RecordingConsole::new().with_keys([121]),
        MemoryFs::new(),
        ScriptedServer::new(),
    );
    let (host, r) = run(
        host,
        "DLOpen \"termlib\"\r\nDim k\r\nk = GetAsciiWithCPrompt(\"Pick\")\r\nSay k",
    );
    r.unwrap();
    let out = host.console.borrow().output();
    assert_eq!(out[0], "{{noprespace}}Pick> [_]", "the prompt shows a blank");
    assert_eq!(out[1], "{{noprespace}}Pick> [y]", "then the key that was read");
    assert_eq!(out[2], "121");
}

#[test]
fn saywithbgcolor_writes_the_line_and_draws_behind_it() {
    let (host, r) = run(
        plain_host(),
        "DLOpen \"termlib\"\r\nSayWithBGColor RGB(0,0,255), \"warning\"",
    );
    r.unwrap();
    let console = host.console.borrow();
    assert_eq!(console.output(), vec!["warning"]);
    assert!(matches!(
        console.events[1],
        ConsoleEvent::Draw { rgb: 0xFF0000, .. }
    ));
}

// ---- the console command line -------------------------------------------

#[test]
fn a_typed_command_is_rewritten_and_then_runs() {
    // The console's real path: rewrite what the player typed, then run it.
    let fs = MemoryFs::new().with_file(
        "/system/commands/greet.ds",
        r#"Say "hello, " & ArgV(1)"#,
    );
    let host = Rc::new(GameHost::new(RecordingConsole::new(), fs, ScriptedServer::new()));
    let mut it = Interp::with_host(host.clone());

    let mut state = vbscript::game::cli::CommandState { dscript: true };
    let script = host
        .parse_command_line(&it, "greet world", &mut state)
        .expect("the line parses");
    assert_eq!(script, r#"Call Run("greet", "world")"#);

    run_script(&mut it, &script).expect("the rewritten line runs");
    assert_eq!(host.console.borrow().output(), vec!["hello, world"]);
}

#[test]
fn the_command_line_resolves_names_against_the_live_session() {
    let fs = MemoryFs::new().with_file("/system/commands/echo.ds", "Say ArgV(1)");
    let host = Rc::new(GameHost::new(RecordingConsole::new(), fs, ScriptedServer::new()));
    let mut it = Interp::with_host(host.clone());
    let mut state = vbscript::game::cli::CommandState { dscript: true };

    // With no such variable the word is text.
    assert_eq!(
        host.parse_command_line(&it, "echo target", &mut state).unwrap(),
        r#"Call Run("echo", "target")"#
    );

    // Once it exists, the same line passes the variable instead.
    it.run_source(r#"Dim target : target = "a value""#).unwrap();
    assert_eq!(
        host.parse_command_line(&it, "echo target", &mut state).unwrap(),
        r#"Call Run("echo", target)"#
    );
}

#[test]
fn typed_script_is_left_alone() {
    let host = Rc::new(plain_host());
    let it = Interp::with_host(host.clone());
    let mut state = vbscript::game::cli::CommandState { dscript: true };
    // An assignment, and anything with VBScript punctuation, is script.
    for line in [r#"x = 1"#, r#"Say("direct")"#, r#"If x Then Say "y""#] {
        assert_eq!(
            host.parse_command_line(&it, line, &mut state).unwrap(),
            line,
            "{line} should pass through"
        );
    }
}

#[test]
fn a_bare_host_call_is_rewritten_but_still_works() {
    // `Say "hi"` has no command file behind it, so it becomes a call whose
    // result is printed — which still reaches the host's Say.
    let host = Rc::new(plain_host());
    let mut it = Interp::with_host(host.clone());
    let mut state = vbscript::game::cli::CommandState { dscript: true };

    let script = host.parse_command_line(&it, r#"Say "hi""#, &mut state).unwrap();
    assert_eq!(script, r#"PrintVarSingleIfSet say("hi")"#);

    run_script(&mut it, &script).expect("the rewritten call runs");
    assert_eq!(host.console.borrow().output()[0], "hi");
}

// ---- corrections to the VB6 client --------------------------------------
//
// Two calls were wrong in the original. They are fixed here rather than
// reproduced, so these tests pin the corrected shapes.

#[test]
fn transfer_sends_the_body_it_builds() {
    // The VB6 client assembles this body and then sends a bare GET.
    let (host, r) = run(
        plain_host(),
        r#"Dim x : x = Transfer("  someone  ", 250, "  for services  ")"#,
    );
    r.unwrap();
    let server = host.server.borrow();
    assert_eq!(server.paths(), vec!["transfer.php"]);
    assert_eq!(
        server.requests[0].body.as_deref(),
        Some("to=someone&amount=250&description=for+services"),
        "the transfer details must reach the server"
    );
}

#[test]
fn transfer_still_refuses_a_non_positive_amount() {
    let (_, r) = run(plain_host(), r#"Dim x : x = Transfer("someone", 0, "why")"#);
    assert!(r.unwrap_err().contains("Invalid amount"));
}

#[test]
fn the_token_request_separates_its_fields() {
    // The VB6 client omits the ampersand, running the flag and the domain
    // together as `is_local_script=trued=example.com`.
    let (host, r) = run(
        plain_host(),
        r#"Dim x : x = RemoteToken("example.com", "why")"#,
    );
    r.unwrap();
    let server = host.server.borrow();
    assert_eq!(
        server.requests[0].body.as_deref(),
        Some("is_local_script=true&d=example.com&info=why")
    );
}

// ---- PrintVar -----------------------------------------------------------

/// "IfSet" means an unset value prints nothing at all.
#[test]
fn print_var_single_if_set_says_nothing_about_an_unset_value() {
    assert_eq!(
        output_of(plain_host(), "Dim v\nPrintVarSingleIfSet v"),
        Vec::<String>::new()
    );
    assert_eq!(output_of(plain_host(), r#"PrintVarSingleIfSet "here""#), vec!["here"]);
}

/// A command that does not exist reports so whether or not it was given
/// arguments. The console writes both forms as a call — `nosuchthing()` and
/// `nosuchthing("x")` — and neither is defined, so neither passes silently.
#[test]
fn an_unknown_command_is_an_error_with_or_without_arguments() {
    for source in [
        "PrintVarSingleIfSet nosuchthing()",
        r#"PrintVarSingleIfSet nosuchthing("x")"#,
    ] {
        let (_, result) = run(plain_host(), source);
        assert_eq!(
            result.unwrap_err(),
            "Error 35: Sub or function not defined: 'nosuchthing'",
            "for {source}"
        );
    }
}

/// `PrintVar` prints Empty rather than swallowing it; only the "IfSet"
/// variant is silent.
#[test]
fn print_var_prints_an_unset_value() {
    assert_eq!(output_of(plain_host(), "Dim v\nPrintVar v"), vec!["Empty"]);
}

#[test]
fn print_var_complains_when_given_nothing() {
    assert_eq!(
        output_of(plain_host(), "PrintVar"),
        vec!["No arguments to print{{orange}}"]
    );
}

/// Several values are labelled by position.
#[test]
fn print_var_labels_multiple_values_by_position() {
    assert_eq!(
        output_of(plain_host(), r#"PrintVar "a", 2"#),
        vec!["ArgV(0) a", "ArgV(1) 2"]
    );
}

/// A lone string that is really a pending request is awaited, so a script can
/// write `PrintVar Lookup(...)` and see the answer rather than the handle.
#[test]
fn print_var_waits_for_a_pending_request() {
    let server = ScriptedServer::new().answer("lookup.php", "10.0.0.1");
    let host = GameHost::new(RecordingConsole::new(), MemoryFs::new(), server);
    assert_eq!(
        output_of(host, r#"PrintVar Lookup("example.com")"#),
        vec!["10.0.0.1"]
    );
}

// ---- Connect / Fetch ----------------------------------------------------

/// Build the `:-:` record `domain_connect.php` answers with.
fn domain_record(domain: &str, port: &str, ip: &str, owner: &str, key: &str, script: &str) -> String {
    format!(
        "{domain}:-:{port}:-:{ip}:-:{owner}:-:{key}:-:{}",
        vbscript::game::crypto::encode_base64(script.as_bytes())
    )
}

fn connect_host(record: &str) -> Host {
    let server = ScriptedServer::new().answer("domain_connect.php", record);
    GameHost::new(RecordingConsole::new(), MemoryFs::new(), server)
}

/// Connecting runs the domain's script. It does not hand back the response —
/// that was the bug: the raw record was printed instead of being acted on.
#[test]
fn connect_runs_the_script_the_domain_serves() {
    let record = domain_record("darksigns.com", "80", "1.2.3.4", "root", "", r#"Say "you are in""#);
    let out = output_of(connect_host(&record), r#"Connect "darksigns.com", 80"#);
    assert_eq!(out, vec!["{{green}}Connecting to DARKSIGNS.COM:80...", "you are in"]);
}

/// Fetch takes the same journey silently and returns the output.
#[test]
fn fetch_returns_the_script_output_instead_of_printing_it() {
    let record = domain_record("darksigns.com", "80", "1.2.3.4", "root", "", r#"Say "hello""#);
    let out = output_of(
        connect_host(&record),
        r#"Say TrimWithNewline(Fetch("darksigns.com", 80))"#,
    );
    assert_eq!(out, vec!["hello"]);
}

/// The script runs as the domain, not as the local machine.
#[test]
fn a_connected_script_sees_the_domain_environment() {
    let script = r#"Say ServerDomain & "|" & ServerPort & "|" & ServerIP & "|" & IsLocal()"#;
    let record = domain_record("darksigns.com", "80", "1.2.3.4", "root", "", script);
    let out = output_of(connect_host(&record), r#"Connect "darksigns.com", 80"#);
    assert_eq!(out[1], "darksigns.com|80|1.2.3.4|False");
}

/// Argument zero is the domain's own script URL; the caller's extra
/// arguments follow it.
#[test]
fn connect_passes_its_arguments_to_the_script() {
    let record = domain_record(
        "darksigns.com", "80", "1.2.3.4", "root", "",
        r#"Say ArgV(0) & "|" & ArgV(1)"#,
    );
    let out = output_of(connect_host(&record), r#"Connect "darksigns.com", 80, "hello""#);
    assert_eq!(out[1], "dso://darksigns.com:80|hello");
}

/// A domain registered by address serves a script compiled under the address
/// key, so the hostname key is tried first and the address is the fallback.
#[test]
fn connect_falls_back_to_the_address_key() {
    let compiled = vbscript::game::crypto::compile_script(
        r#"Say "keyed to the address""#,
        "dso://1.2.3.4:80",
        [7u8; 16],
    )
    .expect("compiles");
    let record = domain_record("darksigns.com", "80", "1.2.3.4", "root", "", &compiled);
    let out = output_of(connect_host(&record), r#"Connect "darksigns.com", 80"#);
    assert_eq!(out[1], "keyed to the address");
}

/// A local script stays local afterwards, whatever the connected one did.
#[test]
fn the_local_environment_comes_back_after_connecting() {
    let record = domain_record("darksigns.com", "80", "1.2.3.4", "root", "", "Say ServerDomain");
    let out = output_of(
        connect_host(&record),
        "Connect \"darksigns.com\", 80\r\nSay \"local=\" & IsLocal() & \" domain=[\" & ServerDomain & \"]\"",
    );
    assert_eq!(out.last().unwrap(), "local=True domain=[]");
}

#[test]
fn connect_reports_a_domain_that_is_not_there() {
    let server = ScriptedServer::new()
        .answer_with("domain_connect.php", vbscript::game::server::ServerResponse {
            code: 404,
            body: String::new(),
        });
    let host = GameHost::new(RecordingConsole::new(), MemoryFs::new(), server);
    let (_, result) = run(host, r#"Connect "nowhere.com", 80"#);
    assert!(
        result.as_ref().unwrap_err().contains("Not found"),
        "got {result:?}"
    );
}

#[test]
fn connect_rejects_an_impossible_port() {
    let (_, result) = run(connect_host(""), r#"Connect "darksigns.com", 0"#);
    assert!(result.unwrap_err().contains("Invalid Port Number: 0"));
}
