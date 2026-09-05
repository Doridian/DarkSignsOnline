//! Checks the DarkSigns `.ds` mission scripts against the interpreter.
//!
//! The scripts call ~160 host procedures the game supplies. This harness
//! answers all of them with `Empty`, so what it really tests is that the
//! parser accepts the corpus and that execution reaches the host rather than
//! tripping over the language itself.

use std::cell::RefCell;
use std::collections::BTreeSet;
use std::path::{Path, PathBuf};
use std::rc::Rc;

use vbscript::interp::{ArgVal, Host, Interp};
use vbscript::value::Value;
use vbscript::VbResult;

/// A host that accepts every call and records the names it was asked for.
#[derive(Default)]
struct StubHost {
    seen: BTreeSet<String>,
}

impl Host for StubHost {
    fn get_global(&mut self, _it: &mut Interp, name: &str) -> VbResult<Option<Value>> {
        self.seen.insert(name.to_string());
        Ok(Some(Value::Empty))
    }
    fn call(
        &mut self,
        _it: &mut Interp,
        name: &str,
        _args: &mut [ArgVal],
    ) -> VbResult<Option<Value>> {
        self.seen.insert(name.to_string());
        Ok(Some(Value::Empty))
    }
}

fn scripts() -> Vec<PathBuf> {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .expect("client has a parent directory")
        .join("client-legacy/user");
    let mut out = Vec::new();
    collect(&root, &mut out);
    out.sort();
    out
}

fn collect(dir: &Path, out: &mut Vec<PathBuf>) {
    let Ok(entries) = std::fs::read_dir(dir) else {
        return;
    };
    for e in entries.flatten() {
        let p = e.path();
        if p.is_dir() {
            collect(&p, out);
        } else if p.extension().is_some_and(|x| x == "ds") {
            out.push(p);
        }
    }
}

/// Scripts written in the older, pre-VBScript DarkSigns dialect, or with
/// syntax the real engine would also reject.
const NOT_VBSCRIPT: &[&str] = &[
    // `If <cond>` with no `Then`.
    "xnull.ds",
    "xnullb.ds",
    // Uses the legacy `@label` / `input` / `!` command language.
    "xnullrg.ds",
];

fn excluded(p: &Path) -> bool {
    let name = p.file_name().and_then(|n| n.to_str()).unwrap_or("");
    NOT_VBSCRIPT.contains(&name)
}

#[test]
fn all_scripts_parse() {
    let files = scripts();
    assert!(!files.is_empty(), "no .ds scripts found");

    let mut failures = Vec::new();
    for f in &files {
        if excluded(f) {
            continue;
        }
        let src = std::fs::read_to_string(f).expect("script is readable");
        if let Err(e) = vbscript::check(&src) {
            failures.push(format!("{}: {e}", f.display()));
        }
    }
    assert!(
        failures.is_empty(),
        "{} of {} scripts failed to parse:\n{}",
        failures.len(),
        files.len(),
        failures.join("\n")
    );
}

/// Runs every script against the stub host and reports how execution ended.
/// Errors here come from the stubbed host returning `Empty` everywhere, so
/// this is a diagnostic rather than a pass/fail check.
#[test]
#[ignore]
fn run_scripts() {
    let mut completed = 0;
    let mut errors: Vec<(String, String)> = Vec::new();
    let mut host_names: BTreeSet<String> = BTreeSet::new();
    for f in scripts() {
        if excluded(&f) {
            continue;
        }
        let src = std::fs::read_to_string(&f).expect("script is readable");
        let host = Rc::new(RefCell::new(StubHost::default()));
        let mut it = Interp::with_host(host.clone());
        // Several scripts sit in a menu loop waiting on the player, which
        // never ends when every host call answers Empty.
        it.set_step_budget(100_000);
        match it.run_source(&src) {
            Ok(()) => completed += 1,
            Err(e) => errors.push((f.display().to_string(), e)),
        }
        host_names.extend(host.borrow().seen.iter().cloned());
    }
    println!("completed: {completed}, errored: {}", errors.len());
    // Group by message so the shape of the failures is visible at a glance.
    let mut by_kind: std::collections::BTreeMap<String, Vec<&str>> = Default::default();
    for (f, e) in &errors {
        let kind = e.split(':').next().unwrap_or(e).to_string();
        by_kind.entry(kind).or_default().push(f);
    }
    for (kind, files) in &by_kind {
        println!("{}: {}", kind, files.len());
        for f in files.iter().take(3) {
            println!("    {f}");
        }
    }
    println!("\nhost names the corpus reaches for ({}):", host_names.len());
    for chunk in host_names.iter().collect::<Vec<_>>().chunks(8) {
        println!("  {}", chunk.iter().map(|s| s.as_str()).collect::<Vec<_>>().join(" "));
    }
}

/// The excluded scripts are expected to fail, so a change that starts
/// accepting them should be noticed.
#[test]
fn legacy_scripts_are_rejected() {
    for f in scripts().into_iter().filter(|f| excluded(f)) {
        let src = std::fs::read_to_string(&f).expect("script is readable");
        assert!(
            vbscript::check(&src).is_err(),
            "{} parses, but is listed as not-VBScript",
            f.display()
        );
    }
}
