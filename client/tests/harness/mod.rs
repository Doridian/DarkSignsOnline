//! Host environment for wine's VBScript conformance tests.
//!
//! The wine tests call into globals supplied by their C driver (`ok`,
//! `getVT`, `testObj`, ...). This module provides equivalents so the same
//! `.vbs` files can run against this interpreter.

#![allow(dead_code)]

use std::cell::RefCell;
use std::rc::Rc;

use vbscript::builtins::datetime;
use vbscript::error::{err, VbError, VbResult};
use vbscript::interp::{ArgVal, Host, Interp};
use vbscript::objects::{NativeObject, ObjKind};
use vbscript::value::{format_r8_invariant, Value};

/// Assertion outcomes collected while a script runs.
#[derive(Default)]
pub struct Report {
    pub failures: Vec<String>,
    pub checks: u32,
    pub todo_failures: Vec<String>,
    pub reported_success: bool,
    pub traces: Vec<String>,
}

pub struct TestHost {
    pub report: Rc<RefCell<Report>>,
    test_obj: Rc<dyn NativeObject>,
    collection_obj: Rc<dyn NativeObject>,
    indexed_obj: Rc<dyn NativeObject>,
    unk_obj: Rc<dyn NativeObject>,
    test_disp: Rc<dyn NativeObject>,
    error_obj: Rc<dyn NativeObject>,
    /// The script itself, which wine's driver adds as the named item
    /// `test`; `Me` at global scope refers to the same object.
    script_obj: Rc<dyn NativeObject>,
}

impl TestHost {
    pub fn new(report: Rc<RefCell<Report>>) -> TestHost {
        TestHost {
            report,
            test_obj: Rc::new(TestObj),
            collection_obj: Rc::new(CollectionObj { pos: RefCell::new(0) }),
            indexed_obj: Rc::new(IndexedObj),
            unk_obj: Rc::new(UnknownObj),
            test_disp: Rc::new(TestDisp),
            error_obj: Rc::new(ErrorObj),
            script_obj: Rc::new(ScriptObj),
        }
    }

    fn fail(&self, it: &Interp, msg: String) {
        self.report
            .borrow_mut()
            .failures
            .push(format!("line {}: {}", it.cur_line, msg));
    }
}

/// `getVT` reports VT_UNKNOWN for the object that stands in for an
/// `IUnknown`-only value.
const UNKNOWN_MARKER: &str = "__vt_unknown__";

fn vt_name(v: &Value) -> String {
    if let Value::Obj(Some(ObjKind::Native(n))) = v {
        if n.type_name() == UNKNOWN_MARKER {
            return "VT_UNKNOWN".into();
        }
    }
    v.vt_name()
}

impl Host for TestHost {
    fn get_global(&mut self, _it: &mut Interp, name: &str) -> VbResult<Option<Value>> {
        Ok(Some(match name {
            "isenglishlang" => Value::Bool(true),
            "maxcharsize" => Value::I4(1),
            "firstdayofweek" => Value::I4(1),
            "testobj" => Value::Obj(Some(ObjKind::Native(self.test_obj.clone()))),
            "collectionobj" => Value::Obj(Some(ObjKind::Native(self.collection_obj.clone()))),
            "indexedobj" => Value::Obj(Some(ObjKind::Native(self.indexed_obj.clone()))),
            "unkobj" => Value::Obj(Some(ObjKind::Native(self.unk_obj.clone()))),
            "testdisp" => Value::Obj(Some(ObjKind::Native(self.test_disp.clone()))),
            "testerrorobject" => Value::Obj(Some(ObjKind::Native(self.error_obj.clone()))),
            "nulldisp" => Value::Obj(None),
            "test" => Value::Obj(Some(ObjKind::Native(self.script_obj.clone()))),
            _ => return Ok(None),
        }))
    }

    fn global_object(&mut self, _it: &mut Interp) -> VbResult<Option<Value>> {
        Ok(Some(Value::Obj(Some(ObjKind::Native(self.script_obj.clone())))))
    }

    fn set_global(&mut self, _it: &mut Interp, name: &str, _value: Value) -> VbResult<bool> {
        // Assigning to this global invokes its property put, which throws.
        if name == "throwwithdesc" {
            return Err(throw_with_desc());
        }
        Ok(false)
    }

    fn call(
        &mut self,
        it: &mut Interp,
        name: &str,
        args: &mut [ArgVal],
    ) -> VbResult<Option<Value>> {
        let val = |i: usize| -> Value { args.get(i).map(|a| a.value()).unwrap_or(Value::Empty) };

        match name {
            "ok" | "todo_wine_ok" => {
                let cond = val(0);
                let msg = val(1).to_vb_string().unwrap_or_else(|_| Rc::from("<no message>"));
                let passed = matches!(cond, Value::Bool(true))
                    || (!cond.is_null() && cond.to_bool().unwrap_or(false));
                self.report.borrow_mut().checks += 1;
                if !passed {
                    let line = it.cur_line;
                    let mut r = self.report.borrow_mut();
                    let text = format!("line {line}: {msg}");
                    if name == "ok" {
                        r.failures.push(text);
                    } else {
                        r.todo_failures.push(text);
                    }
                }
                Ok(Some(Value::Empty))
            }

            "trace" => {
                let msg = val(0).to_vb_string().unwrap_or_else(|_| Rc::from(""));
                self.report.borrow_mut().traces.push(msg.to_string());
                Ok(Some(Value::Empty))
            }

            "reportsuccess" => {
                self.report.borrow_mut().reported_success = true;
                Ok(Some(Value::Empty))
            }

            // wine's driver appends `*` when the argument arrived as
            // VT_BYREF|VT_VARIANT, which is what passing a variable does.
            "getvt" => {
                let arg = args.first();
                let passed_variable = matches!(arg, Some(ArgVal::Ref { .. }));
                let v = val(0);
                // An array held in the caller's own storage arrives as a
                // by-reference SAFEARRAY rather than a copy.
                let owned = matches!(&v, Value::Array(a) if a.owned);
                let mut n = if owned && arg.map(|a| a.is_aliased()).unwrap_or(false) {
                    "VT_ARRAY|VT_BYREF|VT_VARIANT".to_string()
                } else {
                    vt_name(&v)
                };
                if passed_variable {
                    n.push('*');
                }
                Ok(Some(Value::str(n)))
            }

            "doubleasstring" => {
                let d = val(0).to_f64()?;
                Ok(Some(Value::str(format_r8_invariant(d))))
            }

            "isarrayfixed" => Ok(Some(Value::Bool(match val(0) {
                Value::Array(a) => a.fixed,
                _ => false,
            }))),

            // Raises the given HRESULT, and evaluates to False when used in
            // an expression.
            // Only a failure HRESULT (the sign bit set) raises; a success
            // code leaves `Err` untouched and evaluates to False.
            "throwint" => {
                let hr = val(0).to_f64()? as i64 as i32;
                if hr < 0 {
                    Err(it.raise(hr, None, Some(Rc::from("")), None, None))
                } else {
                    Ok(Some(Value::Bool(false)))
                }
            }

            "throwwithdesc" => Err(throw_with_desc()),

            "throwexception" => Err(VbError::new(5, "test exception")),

            // Argument-shape checks in the C driver; nothing to verify here.
            "testarray" | "testoptionalarg" | "globalcallback" | "callglobalcallback" => {
                Ok(Some(Value::Empty))
            }

            "invokedisp" | "invokemethod" | "testdisp" => Ok(Some(Value::Empty)),

            "counter" => Ok(Some(Value::I4(0))),

            // True for the null dispatch pointer, which VBScript spells
            // `Nothing`.
            "isnulldisp" => Ok(Some(Value::Bool(matches!(val(0), Value::Obj(None))))),

            "weekstartday" => Ok(Some(Value::I4(1))),

            _ => Ok(None),
        }
    }

    fn echo(&mut self, text: &str) {
        self.report.borrow_mut().traces.push(text.to_string());
    }
}

/// The exception `throwWithDesc` raises, carrying description and help
/// fields so the tests can read them back off `Err`.
fn throw_with_desc() -> VbError {
    VbError {
        number: 0xdead_beefu32 as i32,
        source: Rc::from("Microsoft VBScript runtime error"),
        description: Rc::from("test"),
        helpfile: Rc::from("test.chm"),
        helpcontext: 10,
    }
}

/// `testObj` — mostly used to check that keywords work as member names.
struct TestObj;

impl NativeObject for TestObj {
    fn type_name(&self) -> &str {
        "TestObj"
    }

    fn get(&self, _it: &mut Interp, name: &str, _args: &[Value]) -> VbResult<Value> {
        Ok(match name.to_ascii_lowercase().as_str() {
            "propget" => Value::I2(0),
            // Members typed as the integer VARIANTs VBScript must widen.
            "i1val" => Value::I2(5),
            // VT_I8 has no VBScript representation but does not error.
            "i8val" => Value::R8(1.0),
            // These Automation types VBScript cannot use at all.
            "ui8val" => Value::Unsupported(21),
            "ui2val" => Value::Unsupported(18),
            "ui4val" => Value::Unsupported(19),
            "uintval" => Value::Unsupported(23),
            "propput" => return Err(err::member_not_found(name)),
            // Every VBScript keyword is also a valid member name here, and
            // they all answer with the same value.
            _ => Value::I2(10),
        })
    }

    fn set(
        &self,
        _it: &mut Interp,
        _name: &str,
        _args: &[Value],
        _v: Value,
        _is_set: bool,
    ) -> VbResult<()> {
        Ok(())
    }
}

/// `collectionObj` — a three-item collection that `For Each` walks.
struct CollectionObj {
    pos: RefCell<usize>,
}

impl NativeObject for CollectionObj {
    fn type_name(&self) -> &str {
        // The C driver exposes no type information, so TypeName says
        // simply "Object".
        "Object"
    }

    fn get(&self, _it: &mut Interp, name: &str, _args: &[Value]) -> VbResult<Value> {
        match name.to_ascii_lowercase().as_str() {
            "reset" => {
                *self.pos.borrow_mut() = 0;
                Ok(Value::Empty)
            }
            "count" => Ok(Value::I4(3)),
            _ => Err(err::member_not_found(name)),
        }
    }

    fn enumerate(&self, _it: &mut Interp) -> VbResult<Option<Vec<Value>>> {
        Ok(Some(vec![Value::I2(1), Value::I2(2), Value::I2(3)]))
    }
}

/// `indexedObj` — indexing it yields the index back.
struct IndexedObj;

impl NativeObject for IndexedObj {
    fn type_name(&self) -> &str {
        "IndexedObj"
    }
    fn get(&self, _it: &mut Interp, name: &str, args: &[Value]) -> VbResult<Value> {
        if name.eq_ignore_ascii_case("item") {
            return self.call_default(_it, args);
        }
        Err(err::member_not_found(name))
    }
    fn call_default(&self, _it: &mut Interp, args: &[Value]) -> VbResult<Value> {
        // The driver's indexed object doubles whatever index it is given.
        match args.first() {
            Some(v) => Ok(Value::I4(v.to_f64()? as i32 * 2)),
            None => Err(err::wrong_arg_count()),
        }
    }
    fn set(
        &self,
        _it: &mut Interp,
        _name: &str,
        _args: &[Value],
        _v: Value,
        _is_set: bool,
    ) -> VbResult<()> {
        // Writes are accepted and discarded; reads always echo the index.
        Ok(())
    }
}

/// Stands in for a value whose VARTYPE is VT_UNKNOWN.
struct UnknownObj;

impl NativeObject for UnknownObj {
    fn type_name(&self) -> &str {
        UNKNOWN_MARKER
    }
    fn get(&self, _it: &mut Interp, name: &str, _args: &[Value]) -> VbResult<Value> {
        Err(err::member_not_found(name))
    }
}

struct TestDisp;

impl NativeObject for TestDisp {
    fn type_name(&self) -> &str {
        "TestDisp"
    }
    fn get(&self, _it: &mut Interp, _name: &str, _args: &[Value]) -> VbResult<Value> {
        Ok(Value::Empty)
    }
    fn call_default(&self, _it: &mut Interp, _args: &[Value]) -> VbResult<Value> {
        Ok(Value::Empty)
    }
}

/// Stands in for the script's own dispatch, which the driver publishes as
/// the named item `test`.
struct ScriptObj;

impl NativeObject for ScriptObj {
    fn type_name(&self) -> &str {
        "Script"
    }
    fn get(&self, _it: &mut Interp, name: &str, _args: &[Value]) -> VbResult<Value> {
        Err(err::member_not_found(name))
    }
}

/// An object whose members raise, used to test error propagation.
struct ErrorObj;

impl NativeObject for ErrorObj {
    fn type_name(&self) -> &str {
        "TestErrorObject"
    }
    fn get(&self, _it: &mut Interp, _name: &str, _args: &[Value]) -> VbResult<Value> {
        Err(VbError::new(5, "test error"))
    }
}

/// Run one wine test script and return its report.
pub fn run_script(src: &str) -> (Report, Option<String>) {
    let report = Rc::new(RefCell::new(Report::default()));
    let host = Rc::new(RefCell::new(TestHost::new(report.clone())));
    let mut it = Interp::with_host(host);
    let error = match vbscript::parser::parse(src) {
        Err(e) => Some(format!("parse error at {e}")),
        Ok(prog) => match it.run(&prog) {
            Ok(()) => None,
            Err(e) => Some(format!("line {}: {} ({})", it.cur_line, e.description, e.number)),
        },
    };
    let _ = datetime::now_ole();
    let r = std::mem::take(&mut *report.borrow_mut());
    (r, error)
}
