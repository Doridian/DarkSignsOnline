//! Runs wine's VBScript conformance suite against this interpreter.

mod harness;

use std::path::Path;

fn run_file(name: &str) -> (harness::Report, Option<String>) {
    let path = Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/vbs").join(name);
    let src = std::fs::read_to_string(&path)
        .unwrap_or_else(|e| panic!("cannot read {}: {e}", path.display()));
    harness::run_script(&src)
}

fn check(name: &str) {
    let (report, error) = run_file(name);
    let mut msg = String::new();
    if !report.failures.is_empty() {
        msg.push_str(&format!(
            "{}: {} of {} assertions failed\n",
            name,
            report.failures.len(),
            report.checks
        ));
        for f in report.failures.iter().take(40) {
            msg.push_str(&format!("  {f}\n"));
        }
        if report.failures.len() > 40 {
            msg.push_str(&format!("  ... and {} more\n", report.failures.len() - 40));
        }
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
