//! Stopping a running script from outside it.
//!
//! The embedder asks -- a browser console does it with Ctrl+B -- and the
//! interpreter ends the script at its next statement. What these check is
//! where the stop lands: after the host call it was asked during, out of
//! whatever procedure the script was inside, and past an `On Error Resume
//! Next` that would otherwise carry on.

use std::cell::{Cell, RefCell};
use std::rc::Rc;

use vbscript::error::ABORT_ERROR;
use vbscript::interp::{ArgVal, Host, Interp};
use vbscript::value::Value;
use vbscript::VbResult;

/// A host that can be told to stop the script, and remembers what ran.
///
/// `Tick` counts down to a stop the interpreter has to notice by asking;
/// `StopNow` asks for one from inside a call, the way a host woken out of a
/// blocking read does. `Remember` records a value, so a test can see whether
/// the statement the stop was asked during finished.
#[derive(Default)]
struct StopHost {
    /// `Tick`s left before the stop is wanted; `None` means never.
    countdown: Cell<Option<i32>>,
    stop: Cell<bool>,
    /// Every host call made, in order.
    calls: RefCell<Vec<String>>,
}

impl StopHost {
    fn stopping_after(ticks: i32) -> Rc<StopHost> {
        let h = StopHost::default();
        h.countdown.set(Some(ticks));
        Rc::new(h)
    }

    fn calls(&self) -> Vec<String> {
        self.calls.borrow().clone()
    }

    fn count(&self, name: &str) -> usize {
        self.calls.borrow().iter().filter(|c| *c == name).count()
    }
}

impl Host for StopHost {
    fn poll_abort(&self) -> bool {
        self.stop.get()
    }

    fn call(&self, it: &mut Interp, name: &str, args: &mut [ArgVal]) -> VbResult<Option<Value>> {
        match name.to_ascii_lowercase().as_str() {
            "tick" => {
                self.calls.borrow_mut().push("tick".into());
                if let Some(left) = self.countdown.get() {
                    self.countdown.set(Some(left - 1));
                    if left <= 1 {
                        self.stop.set(true);
                    }
                }
                Ok(Some(Value::Empty))
            }
            // A stop the host knows about before it returns, which it says
            // rather than waiting to be asked.
            "stopnow" => {
                self.calls.borrow_mut().push("stopnow".into());
                it.request_abort();
                Ok(Some(Value::str("stopped")))
            }
            "remember" => {
                let text = args.first().map(|a| a.value()).unwrap_or(Value::Empty);
                self.calls
                    .borrow_mut()
                    .push(format!("remember:{}", text.to_vb_string()?));
                Ok(Some(Value::Empty))
            }
            // A call that fails at the same moment as it asks for the
            // stop: a request the host gave up on when it was woken.
            "stopfailing" => {
                self.calls.borrow_mut().push("stopfailing".into());
                it.request_abort();
                Err(vbscript::VbError::new(462, "the server went away"))
            }
            "note" => {
                self.calls.borrow_mut().push("note".into());
                Ok(Some(Value::Empty))
            }
            _ => Ok(None),
        }
    }
}

/// Run `source` against `host` and hand back what it ended with.
fn run(host: &Rc<StopHost>, source: &str) -> (Interp, Result<(), vbscript::VbError>) {
    let program = vbscript::parser::parse(source).expect("script parses");
    let mut it = Interp::with_host(host.clone());
    // Low enough that a loop nothing stopped ends the test rather than
    // hanging it, and far above what any of these should reach.
    it.set_step_budget(100_000);
    let result = it.run(&program);
    (it, result)
}

/// The case the whole thing exists for: a loop with no way out of its own.
#[test]
fn a_runaway_loop_is_stopped() {
    let host = StopHost::stopping_after(3);
    let (it, result) = run(&host, "Do\n  Tick\nLoop\n");

    assert!(it.aborted(), "the interpreter reports the script was stopped");
    let err = result.expect_err("the script did not run to its end");
    assert_eq!(err.number, ABORT_ERROR);
    // The stop is noticed by asking, which happens every so many statements
    // rather than at every one, so a few more ticks after the third are
    // expected. Thousands would mean it was not noticed at all.
    assert!(host.count("tick") < 200, "stopped promptly, ran {} ticks", host.count("tick"));
}

/// `On Error Resume Next` is how a script handles its own failures. It is
/// not a veto over the player ending it, which is what swallowing this would
/// amount to -- the loop would carry on with nothing left to stop it.
#[test]
fn on_error_resume_next_does_not_swallow_it() {
    let host = StopHost::stopping_after(3);
    let (it, result) = run(&host, "On Error Resume Next\nDo\n  Tick\nLoop\n");

    assert!(it.aborted());
    assert_eq!(result.expect_err("stopped").number, ABORT_ERROR);
    assert!(host.count("tick") < 200, "ran {} ticks", host.count("tick"));
}

/// A stop ends the script, not the procedure it happened to be in.
#[test]
fn it_unwinds_out_of_a_procedure() {
    let host = StopHost::stopping_after(3);
    let (_, result) = run(
        &host,
        "Sub Spin\n  On Error Resume Next\n  Do\n    Tick\n  Loop\nEnd Sub\nSpin\nNote\n",
    );

    assert_eq!(result.expect_err("stopped").number, ABORT_ERROR);
    assert_eq!(host.count("note"), 0, "nothing runs after the call that was stopped");
}

/// A host that learns of the stop while it is being called says so, and is
/// taken at its word at the very next statement -- without being asked, which
/// a script that spends its time waiting would be slow to reach.
#[test]
fn a_host_can_ask_for_the_stop_itself() {
    let host = Rc::new(StopHost::default());
    let (it, result) = run(&host, "StopNow\nNote\n");

    assert!(it.aborted());
    assert_eq!(result.expect_err("stopped").number, ABORT_ERROR);
    assert_eq!(host.calls(), vec!["stopnow"]);
}

/// The stop lands between two statements and never inside one. A host call
/// is left to finish -- it may be halfway through a write or a request -- and
/// so is the statement it was made from.
#[test]
fn the_statement_the_stop_was_asked_during_finishes() {
    let host = Rc::new(StopHost::default());
    let (_, result) = run(&host, "Remember StopNow() & \"-tail\"\nNote\n");

    assert_eq!(result.expect_err("stopped").number, ABORT_ERROR);
    assert_eq!(
        host.calls(),
        vec!["stopnow", "remember:stopped-tail"],
        "the rest of the statement ran, and the next one did not"
    );
}

/// A call that fails as it asks for the stop reports the stop. Its own
/// complaint is about a request the host abandoned because it was stopped,
/// which is not what the player wants to read about.
#[test]
fn the_stop_is_reported_rather_than_what_failed_alongside_it() {
    let host = Rc::new(StopHost::default());
    let (_, result) = run(&host, "On Error Resume Next\nStopFailing\nNote\n");

    let err = result.expect_err("stopped");
    assert_eq!(err.number, ABORT_ERROR, "reported \"{err}\"");
    assert_eq!(host.count("note"), 0);
}

/// Nothing is stopped unless it is asked for.
#[test]
fn a_script_nobody_stops_runs_to_its_end() {
    let host = Rc::new(StopHost::default());
    let (it, result) = run(&host, "For i = 1 To 3\n  Tick\nNext\nNote\n");

    result.expect("ran to its end");
    assert!(!it.aborted());
    assert_eq!(host.count("tick"), 3);
    assert_eq!(host.count("note"), 1);
}
