//! Parity with the PHP server this one replaced.
//!
//! Every case in `cases.rs` is a request sent through a real nginx, in
//! order, against a database seeded from `seed.sql`, with the clock frozen.
//! What comes back -- status, headers, body -- and what it did -- the rows
//! it changed, the mail it sent -- is compared with `golden.jsonl`, which
//! was recorded by running the same cases against the PHP.
//!
//! It needs MariaDB, nginx and libfaketime, which `nix develop .#server`
//! provides, so it is ignored by default:
//!
//! ```sh
//! nix develop .#server --command cargo test --manifest-path server/Cargo.toml -- --ignored
//! ```
//!
//! A deliberate change of behaviour is an edit to the goldens by hand, so
//! the diff says what clients will see change. For a new case, setting
//! `DSO_PARITY_RECORD` writes this server's answers as the goldens instead
//! of comparing; check the diff before believing it. The PHP that recorded
//! the rest was last in the tree at `91612d0`.

mod cases;
mod harness;

use std::path::PathBuf;

use harness::{Db, Masker, Site, SmtpSink, http};
use serde_json::{Value, json};

/// The home page's news, which is content rather than behaviour: the goldens
/// hold a marker where it goes, so a new post does not need them edited.
const NEWS: &str = include_str!("../../src/site/templates/index.0.html");

/// Headers that say how the bytes travelled rather than what they were, and
/// the one that named the old server's language.
const IGNORED_HEADERS: &[&str] = &[
    "date",
    "content-length",
    "transfer-encoding",
    "connection",
    "x-powered-by",
];

fn decode_qp(s: &str) -> String {
    let mut out = Vec::new();
    let b = s.as_bytes();
    let mut i = 0;
    while i < b.len() {
        if b[i] == b'=' && b.get(i + 1) == Some(&b'\r') && b.get(i + 2) == Some(&b'\n') {
            i += 3;
        } else if b[i] == b'=' && i + 2 < b.len() {
            out.push(u8::from_str_radix(std::str::from_utf8(&b[i + 1..i + 3]).unwrap(), 16).unwrap());
            i += 3;
        } else {
            out.push(b[i]);
            i += 1;
        }
    }
    String::from_utf8_lossy(&out).into_owned()
}

/// What a message said, rather than how either mailer happened to spell it.
fn normalize_mail(mail: &harness::Mail) -> Value {
    let (head, body) = mail.data.split_once("\r\n\r\n").unwrap_or((&mail.data, ""));
    let unfolded = head.replace("\r\n ", " ").replace("\r\n\t", " ");
    let header = |name: &str| {
        unfolded
            .split("\r\n")
            .find_map(|l| {
                l.split_once(':')
                    .filter(|(k, _)| k.eq_ignore_ascii_case(name))
                    .map(|(_, v)| v.trim().replace('"', ""))
            })
            .unwrap_or_default()
    };
    let body = if header("Content-Transfer-Encoding").eq_ignore_ascii_case("quoted-printable") {
        decode_qp(body)
    } else {
        body.to_string()
    };
    let envelope: Vec<String> = mail
        .envelope
        .iter()
        .map(|l| {
            let upper = l.to_ascii_uppercase();
            let verb = if upper.starts_with("MAIL") {
                "MAIL FROM"
            } else {
                "RCPT TO"
            };
            let addr = l
                .split_once('<')
                .and_then(|(_, r)| r.split_once('>'))
                .map_or("", |(a, _)| a);
            format!("{verb}:<{addr}>")
        })
        .collect();
    json!({
        "envelope": envelope,
        "from": header("From"),
        "to": header("To"),
        "subject": header("Subject"),
        "body": body.replace("\r\n", "\n").trim_end().to_string(),
    })
}

fn run() -> Vec<Value> {
    let dir = PathBuf::from(env!("CARGO_TARGET_TMPDIR")).join("parity");
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();

    let db = Db::start(&dir);
    db.reset();
    let smtp = SmtpSink::start();
    let site = Site::start(&dir, &db, smtp.port);

    let mut before = db.dump();
    let mut masker = Masker::new(&before);
    let mut results = Vec::new();
    for case in cases::all() {
        let case = case.resolve(&db);
        let mails_before = smtp.mails.lock().unwrap().len();
        let resp = http(
            site.port,
            &case.method,
            &case.target,
            &case.headers,
            case.body.as_deref(),
        );
        // The mailer may still be talking to the sink as the page returns.
        std::thread::sleep(std::time::Duration::from_millis(if case.expects_mail {
            300
        } else {
            0
        }));
        let after = db.dump();
        masker.learn(&after);

        let removed: Vec<String> = before
            .iter()
            .filter(|l| !after.contains(l))
            .map(|l| format!("- {}", masker.apply(l)))
            .collect();
        let added: Vec<String> = after
            .iter()
            .filter(|l| !before.contains(l))
            .map(|l| format!("+ {}", masker.apply(l)))
            .collect();
        let db_changes: Vec<String> = removed.into_iter().chain(added).collect();
        let mails: Vec<Value> = smtp.mails.lock().unwrap()[mails_before..]
            .iter()
            .map(|m| {
                let mut v = normalize_mail(m);
                v["body"] = Value::String(masker.apply(v["body"].as_str().unwrap()));
                v["subject"] = Value::String(masker.apply(v["subject"].as_str().unwrap()));
                v
            })
            .collect();
        let headers: Vec<Value> = resp
            .headers
            .iter()
            .filter(|(k, _)| !IGNORED_HEADERS.contains(&k.to_ascii_lowercase().as_str()))
            // Names compare without regard to case, as HTTP has them.
            .map(|(k, v)| json!([k.to_ascii_lowercase(), v]))
            .collect();
        let body = match String::from_utf8(resp.body.clone()) {
            Ok(s) => json!(masker.apply(&s.replace(NEWS, "<!-- news -->"))),
            Err(_) => json!({ "hex": resp.body.iter().map(|b| format!("{b:02x}")).collect::<String>() }),
        };
        results.push(json!({
            "case": case.name,
            "request": format!("{} {}", case.method, case.target_shown),
            "status": resp.status,
            "headers": headers,
            "body": body,
            "db": db_changes,
            "mail": mails,
        }));
        before = after;
    }
    results
}

#[test]
#[ignore = "needs MariaDB, nginx and libfaketime: run in `nix develop .#server` with --ignored"]
fn parity() {
    let golden_path = harness::fixture("golden.jsonl");
    let results = run();
    if std::env::var_os("DSO_PARITY_RECORD").is_some() {
        let lines: Vec<String> = results.iter().map(|r| serde_json::to_string(r).unwrap()).collect();
        std::fs::write(&golden_path, lines.join("\n") + "\n").unwrap();
        eprintln!("recorded {} cases to {}", results.len(), golden_path.display());
        return;
    }

    let golden: Vec<Value> = std::fs::read_to_string(&golden_path)
        .expect("golden.jsonl (record it with DSO_PARITY_RECORD)")
        .lines()
        .map(|l| serde_json::from_str(l).unwrap())
        .collect();
    assert_eq!(
        golden.len(),
        results.len(),
        "the case list and the goldens have drifted apart; record again"
    );

    let mut failures = Vec::new();
    for (want, got) in golden.iter().zip(&results) {
        assert_eq!(
            want["case"], got["case"],
            "the case list and the goldens have drifted apart; record again"
        );
        if want != got {
            failures.push(format!(
                "{}\n  want: {}\n  got:  {}",
                want["case"].as_str().unwrap(),
                serde_json::to_string(want).unwrap(),
                serde_json::to_string(got).unwrap()
            ));
        }
    }
    assert!(
        failures.is_empty(),
        "{} of {} cases differ:\n\n{}",
        failures.len(),
        results.len(),
        failures.join("\n\n")
    );
}
