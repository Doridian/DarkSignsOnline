//! Runs wine's VBScript conformance suite against this interpreter.

mod harness;

use std::path::Path;

fn run_file(name: &str) -> (harness::Report, Option<String>) {
    let path = Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/vbs").join(name);
    let src = std::fs::read_to_string(&path)
        .unwrap_or_else(|e| panic!("cannot read {}: {e}", path.display()));
    harness::run_script(&src)
}

/// An assertion that fails for a reason we understand and have chosen not to
/// fix yet. `script` names the test file, `pattern` is matched against the
/// assertion message, and `reason` says what would have to change.
struct KnownFailure {
    script: &'static str,
    pattern: &'static str,
    reason: &'static str,
}

/// Why the `*B` assertions fail.
///
/// `LeftB`, `RightB` and `ChrB` slice a string's little-endian UTF-16 byte
/// image, and that image can have an odd length: `LeftB("ABC", 3)` is three
/// bytes, one and a half UTF-16 units, and `LenB` of it is 3. A `Value::Str`
/// holds a Rust `str`, which cannot represent half a unit, so the result
/// rounds up to a whole one and `LenB` reports 4.
///
/// Fixing this means holding strings as bytes rather than as `str`, which
/// touches every string operation, comparison and conversion in the
/// interpreter. That is a lot of churn for a legacy DBCS feature that no
/// DarkSigns script uses, so it is parked here rather than half-done.
const BYTE_STRING_REASON: &str =
    "*B functions need a byte-based string representation; Value::Str is a Rust str \
     and cannot hold an odd number of UTF-16 bytes";

const KNOWN_FAILURES: &[KnownFailure] = &[
    KnownFailure {
        script: "api.vbs",
        pattern: "LenB(LeftB(\"ABC\", 3))",
        reason: BYTE_STRING_REASON,
    },
    KnownFailure {
        script: "api.vbs",
        pattern: "LenB(RightB(\"ABC\", 3))",
        reason: BYTE_STRING_REASON,
    },
    KnownFailure {
        script: "api.vbs",
        pattern: "LenB(ChrB(65))",
        reason: BYTE_STRING_REASON,
    },
];

fn check(name: &str) {
    let (report, error) = run_file(name);

    // Split the failures into ones we expect and ones we do not, and note
    // which expected ones did not turn up.
    let expected: Vec<&KnownFailure> =
        KNOWN_FAILURES.iter().filter(|k| k.script == name).collect();
    let mut unmatched: Vec<&KnownFailure> = expected.clone();
    let mut unexpected = Vec::new();
    for f in &report.failures {
        match expected.iter().find(|k| f.contains(k.pattern)) {
            Some(hit) => unmatched.retain(|k| k.pattern != hit.pattern),
            None => unexpected.push(f),
        }
    }

    let mut msg = String::new();
    if !unexpected.is_empty() {
        msg.push_str(&format!(
            "{}: {} of {} assertions failed\n",
            name,
            unexpected.len(),
            report.checks
        ));
        for f in unexpected.iter().take(40) {
            msg.push_str(&format!("  {f}\n"));
        }
        if unexpected.len() > 40 {
            msg.push_str(&format!("  ... and {} more\n", unexpected.len() - 40));
        }
    }

    // A known failure that stopped failing is good news, but the entry has
    // to go or it will hide a later regression.
    for k in &unmatched {
        msg.push_str(&format!(
            "{}: known failure now passes, remove its KNOWN_FAILURES entry: {}\n  ({})\n",
            name, k.pattern, k.reason
        ));
    }

    if let Some(e) = error {
        msg.push_str(&format!("{name}: script aborted: {e}\n"));
    } else if !report.reported_success {
        msg.push_str(&format!("{name}: script did not reach reportSuccess\n"));
    }
    if !msg.is_empty() {
        panic!("\n{msg}");
    }
}

#[test]
fn lang() {
    check("lang.vbs");
}

#[test]
fn api() {
    check("api.vbs");
}

#[test]
fn error() {
    check("error.vbs");
}

#[test]
fn regexp() {
    check("regexp.vbs");
}

#[test]
fn noexplicit() {
    check("noexplicit.vbs");
}

/// Ad-hoc script used while narrowing down failures.
#[test]
#[ignore]
fn scratch() {
    let path = std::env::var("VBS").expect("set VBS=<path>");
    let src = std::fs::read_to_string(&path).unwrap();
    let (report, error) = harness::run_script(&src);
    for f in &report.failures {
        println!("FAIL {f}");
    }
    if let Some(e) = error {
        println!("ABORT {e}");
    }
    println!("checks={} success={}", report.checks, report.reported_success);
}
