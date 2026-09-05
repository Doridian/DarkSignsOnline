//! The tree-walking evaluator.

use std::cell::RefCell;
use std::collections::HashMap;
use std::rc::Rc;

use crate::ast::*;
use crate::error::{err, describe, hresult_to_number, ExecResult, Flow, VbError, VbResult};
use crate::objects::{ClassObj, ObjKind};
use crate::ops;
use crate::value::{slot, Slot, VbArray, Value};

/// Maximum nested procedure calls before reporting "out of stack space".
const MAX_DEPTH: usize = 512;

/// Outcome of evaluating a control expression under `On Error Resume Next`.
enum Ctrl<T> {
    Ok(T),
    /// The expression failed and the control transfer it fed was skipped.
    Skipped,
}

/// How a value reaches a parameter. `Ref` shares the caller's binding so a
/// `ByRef` parameter can assign through it.
pub enum ArgVal {
    /// A variable, passed by sharing its slot. `aliased` records that the
    /// slot really is the caller's storage rather than a copy made for a
    /// `ByVal` parameter, which is the difference between a plain array
    /// argument and a `VT_BYREF` one.
    Ref { slot: Slot, aliased: bool },
    Val(Value),
    /// An elided argument in `f(1, , 3)`.
    Missing,
}

impl ArgVal {
    pub fn value(&self) -> Value {
        match self {
            ArgVal::Ref { slot, .. } => slot.borrow().clone(),
            ArgVal::Val(v) => v.clone(),
            ArgVal::Missing => Value::ErrCode(crate::value::VT_ERROR),
        }
    }
    pub fn is_missing(&self) -> bool {
        matches!(self, ArgVal::Missing)
    }
    /// Whether this argument names storage the callee can write through.
    pub fn is_aliased(&self) -> bool {
        matches!(self, ArgVal::Ref { aliased: true, .. })
    }
}

/// Services the embedding application provides to scripts.
///
/// Methods take `&self` because a host procedure may run further script —
/// `Include`, `Run` and `Capture` all do — and that script calls straight
/// back into the same host. An implementation therefore keeps its mutable
/// state behind its own `RefCell`s and borrows them only for the length of
/// one operation, never across a nested call.
pub trait Host {
    /// Resolve an identifier the interpreter does not know.
    fn get_global(&self, _it: &mut Interp, _name: &str) -> VbResult<Option<Value>> {
        Ok(None)
    }
    /// Invoke a host-provided procedure. Returning `None` means "not mine".
    fn call(
        &self,
        _it: &mut Interp,
        _name: &str,
        _args: &mut [ArgVal],
    ) -> VbResult<Option<Value>> {
        Ok(None)
    }
    /// The object `Me` refers to outside any class, if the host has one.
    fn global_object(&self, _it: &mut Interp) -> VbResult<Option<Value>> {
        Ok(None)
    }
    /// Assign to a host-provided global. Returning `false` means the host
    /// does not own this name, so the script scope handles it.
    fn set_global(&self, _it: &mut Interp, _name: &str, _value: Value) -> VbResult<bool> {
        Ok(false)
    }
    /// Construct a `CreateObject` target.
    fn create_object(&self, _it: &mut Interp, _progid: &str) -> VbResult<Option<Value>> {
        Ok(None)
    }
    /// Destination for `MsgBox` and similar output.
    fn echo(&self, _text: &str) {}

    /// Milliseconds since the Unix epoch, for `Now`, `Date` and `Timer`.
    ///
    /// The default reads the system clock, which a browser build overrides
    /// because `wasm32-unknown-unknown` has no clock of its own.
    fn now_unix_millis(&self) -> f64 {
        #[cfg(not(target_arch = "wasm32"))]
        {
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .map(|d| d.as_secs_f64() * 1000.0)
                .unwrap_or(0.0)
        }
        #[cfg(target_arch = "wasm32")]
        {
            // Without a host-supplied clock there is nothing sensible to
            // return, so dates start at the epoch rather than panicking.
            0.0
        }
    }

    /// Fill `buffer` with cryptographically strong random bytes.
    ///
    /// Used for encryption salts. The default reads the system source; a
    /// browser build overrides it with `crypto.getRandomValues`. Returning
    /// `false` means no randomness was available, and the caller reports
    /// that rather than using a predictable salt.
    fn random_bytes(&self, buffer: &mut [u8]) -> bool {
        #[cfg(not(target_arch = "wasm32"))]
        {
            use std::io::Read;
            std::fs::File::open("/dev/urandom")
                .and_then(|mut f| f.read_exact(buffer))
                .is_ok()
        }
        #[cfg(target_arch = "wasm32")]
        {
            let _ = buffer;
            false
        }
    }
}

/// A host that provides nothing.
pub struct NullHost;
impl Host for NullHost {}

struct Frame {
    vars: HashMap<Rc<str>, Slot>,
    me: Option<ObjKind>,
    /// `On Error Resume Next` is scoped to the procedure that enables it.
    on_error: bool,
    /// Parameters bound to a copy rather than to the caller's storage.
    /// Passing one on does not make it a by-reference argument.
    copied_params: std::collections::HashSet<Rc<str>>,
}

impl Frame {
    fn new() -> Frame {
        Frame {
            vars: HashMap::new(),
            me: None,
            on_error: false,
            copied_params: std::collections::HashSet::new(),
        }
    }
}

/// The mutable state behind the `Err` object.
#[derive(Clone)]
pub struct ErrState {
    pub number: i32,
    pub source: Rc<str>,
    pub description: Rc<str>,
    pub helpfile: Rc<str>,
    pub helpcontext: i32,
}

impl ErrState {
    fn clear() -> ErrState {
        ErrState {
            number: 0,
            source: Rc::from(""),
            description: Rc::from(""),
            helpfile: Rc::from(""),
            helpcontext: 0,
        }
    }
}

pub struct Interp {
    globals: HashMap<Rc<str>, Slot>,
    frames: Vec<Frame>,
    pub funcs: HashMap<Rc<str>, Rc<FuncDef>>,
    pub props: HashMap<(Rc<str>, PropKind), Rc<PropDef>>,
    pub classes: HashMap<Rc<str>, Rc<ClassDef>>,
    pub consts: HashMap<Rc<str>, Value>,
    with_stack: Vec<Value>,
    pub err: ErrState,
    pub option_explicit: bool,
    pub host: Rc<dyn Host>,
    pub locale: i32,
    /// State for `Rnd`/`Randomize`.
    pub rng: u32,
    pub last_rnd: f32,
    /// Options the script declared that we do not interpret. A preprocessor
    /// is expected to handle these; they are recorded rather than rejected.
    pub unknown_options: Vec<Rc<str>>,
    /// Source line of the statement being executed, reported in errors.
    pub cur_line: u32,
    /// `On Error Resume Next` state for top-level code, which has no frame.
    global_on_error: bool,
    /// Nesting depth of `Execute`/`ExecuteGlobal`. Each call compiles a
    /// separate unit, and a unit that did not declare a constant itself sees
    /// the global variable of that name instead.
    execute_depth: u32,
    /// Constants declared by the unit currently being compiled, used to
    /// reject a `Dim` of the same name.
    unit_consts: std::collections::HashSet<Rc<str>>,
    /// Globals that already held an array when the current unit started, so
    /// a `Dim` of one of them is a redeclaration rather than a first one.
    unit_prior_arrays: std::collections::HashSet<Rc<str>>,
    /// Statements left before the script is stopped, when a budget is set.
    /// An embedder running player-authored scripts uses this to bound a
    /// runaway loop.
    step_budget: Option<u64>,
}

impl Default for Interp {
    fn default() -> Interp {
        Interp::new()
    }
}

impl Interp {
    pub fn new() -> Interp {
        Interp::with_host(Rc::new(NullHost))
    }

    pub fn with_host(host: Rc<dyn Host>) -> Interp {
        Interp {
            globals: HashMap::new(),
            frames: Vec::new(),
            funcs: HashMap::new(),
            props: HashMap::new(),
            classes: HashMap::new(),
            consts: HashMap::new(),
            with_stack: Vec::new(),
            err: ErrState::clear(),
            option_explicit: false,
            host,
            locale: crate::locale::DEFAULT_LCID,
            rng: 0x0005_0000,
            last_rnd: 0.0,
            unknown_options: Vec::new(),
            cur_line: 0,
            global_on_error: false,
            execute_depth: 0,
            unit_consts: std::collections::HashSet::new(),
            unit_prior_arrays: std::collections::HashSet::new(),
            step_budget: None,
        }
    }

    /// Stop the script once it has executed `steps` statements. Without a
    /// budget a script may loop forever, which suits trusted code and
    /// little else.
    pub fn set_step_budget(&mut self, steps: u64) {
        self.step_budget = Some(steps);
    }

    // ---- scopes ----------------------------------------------------------

    fn frame(&self) -> Option<&Frame> {
        self.frames.last()
    }

    fn in_proc(&self) -> bool {
        !self.frames.is_empty()
    }

    fn lookup_slot(&self, name: &str) -> Option<Slot> {
        if let Some(f) = self.frames.last() {
            if let Some(s) = f.vars.get(name) {
                return Some(s.clone());
            }
            // A method sees its instance's fields as bare names.
            if let Some(ObjKind::Class(c)) = &f.me {
                if let Some(s) = c.fields.borrow().get(name) {
                    return Some(s.clone());
                }
            }
        }
        self.globals.get(name).cloned()
    }

    /// Whether the name is declared in the scope a `Dim` here would target,
    /// which is the current procedure's frame, or the globals at top level.
    fn declared_here(&self, name: &str) -> bool {
        match self.frames.last() {
            Some(f) => f.vars.contains_key(name),
            None => self.globals.contains_key(name),
        }
    }

    fn declare(&mut self, name: Rc<str>, value: Value) -> Slot {
        let s = slot(value);
        if let Some(f) = self.frames.last_mut() {
            f.vars.insert(name, s.clone());
        } else {
            self.globals.insert(name, s.clone());
        }
        s
    }

    /// Get the slot for a name, creating it when the script has not declared
    /// variables explicitly.
    fn slot_for_write(&mut self, name: &Rc<str>) -> VbResult<Slot> {
        if let Some(s) = self.lookup_slot(name) {
            return Ok(s);
        }
        if self.option_explicit {
            return Err(err::name_not_defined(name));
        }
        Ok(self.declare(name.clone(), Value::Empty))
    }

    // ---- program ---------------------------------------------------------

    pub fn run(&mut self, program: &Program) -> Result<(), VbError> {
        crate::locale::set(self.locale);
        self.option_explicit = program.option_explicit;
        self.hoist(&program.body, true);
        match self.exec_block(&program.body) {
            Ok(()) | Err(Flow::Halt) => Ok(()),
            Err(Flow::Error(e)) => Err(e),
            Err(_) => Ok(()),
        }
    }

    pub fn run_source(&mut self, src: &str) -> Result<(), String> {
        let prog = crate::parser::parse(src).map_err(|e| e.to_string())?;
        self.run(&prog).map_err(|e| e.to_string())
    }

    /// Register procedures, classes and (at procedure entry) variables before
    /// executing, since VBScript makes them visible ahead of their definition.
    fn hoist(&mut self, body: &[Stmt], top_level: bool) {
        let _ = top_level;
        for s in body {
            // A declaration nested inside a conditional or loop is still
            // hoisted, so look through the bodies of block statements.
            match &s.kind {
                StmtKind::If { branches, else_body } => {
                    for (_, b) in branches {
                        self.hoist(b, top_level);
                    }
                    if let Some(b) = else_body {
                        self.hoist(b, top_level);
                    }
                }
                StmtKind::While { body: b, .. }
                | StmtKind::Do { body: b, .. }
                | StmtKind::For { body: b, .. }
                | StmtKind::ForEach { body: b, .. }
                | StmtKind::With { body: b, .. } => self.hoist(b, top_level),
                StmtKind::Select { cases, .. } => {
                    for c in cases {
                        self.hoist(&c.body, top_level);
                    }
                }
                _ => {}
            }
            match &s.kind {
                StmtKind::Function(f) => {
                    self.funcs.insert(f.name.to_ascii_lowercase().into(), f.clone());
                }
                StmtKind::Property(p) => {
                    self.props
                        .insert((p.name.to_ascii_lowercase().into(), p.kind), p.clone());
                }
                StmtKind::Class(c) => {
                    self.classes.insert(c.name.to_ascii_lowercase().into(), c.clone());
                }
                StmtKind::Option(o) => {
                    if !o.eq_ignore_ascii_case("explicit") {
                        self.unknown_options.push(o.clone());
                    }
                }
                // Constants are visible throughout their scope, including
                // before the `Const` line and inside a branch that never runs.
                StmtKind::Const(list) => {
                    for (name, e) in list {
                        if let Ok(v) = self.eval_inner(e) {
                            let key: Rc<str> = name.to_ascii_lowercase().into();
                            if self.in_proc() {
                                self.declare(key, v);
                            } else {
                                self.unit_consts.insert(key.clone());
                                self.consts.insert(key, v);
                            }
                        }
                    }
                }
                // A `Dim` is visible throughout its scope, including before
                // the declaration itself. A sized array is only built when
                // the statement actually runs, so the name starts out Empty.
                StmtKind::Dim(vars) => {
                    for v in vars {
                        // A name already declared in this same scope keeps
                        // its value; hoisting only makes the name visible.
                        if self.declared_here(&v.name) {
                            continue;
                        }
                        let init = if v.is_array && v.dims.is_empty() {
                            let mut a = VbArray::uninitialized();
                            a.owned = true;
                            Value::Array(Rc::new(a))
                        } else {
                            Value::Empty
                        };
                        self.declare(v.name.clone(), init);
                    }
                }
                _ => {}
            }
        }
    }

    // ---- statements ------------------------------------------------------

    pub fn exec_block(&mut self, body: &[Stmt]) -> ExecResult {
        for s in body {
            match self.exec_stmt(s) {
                Ok(()) => {}
                Err(Flow::Error(e)) => {
                    // `On Error Resume Next` swallows the error and continues
                    // with the following statement.
                    if self.on_error_active() {
                        self.set_err(e);
                        continue;
                    }
                    return Err(Flow::Error(e));
                }
                Err(other) => return Err(other),
            }
        }
        Ok(())
    }

    fn on_error_active(&self) -> bool {
        match self.frames.last() {
            Some(f) => f.on_error,
            None => self.global_on_error,
        }
    }

    pub fn set_err(&mut self, e: VbError) {
        self.err = ErrState {
            number: e.number,
            source: e.source.clone(),
            description: e.description.clone(),
            helpfile: e.helpfile.clone(),
            helpcontext: e.helpcontext,
        };
    }

    fn exec_stmt(&mut self, s: &Stmt) -> ExecResult {
        if let Some(budget) = &mut self.step_budget {
            if *budget == 0 {
                return Err(Flow::Error(VbError::new(
                    28,
                    "Script exceeded its statement budget",
                )));
            }
            *budget -= 1;
        }
        self.cur_line = s.line;
        match &s.kind {
            StmtKind::Empty | StmtKind::Option(_) => Ok(()),
            StmtKind::Stop => Ok(()),

            StmtKind::Call(e) => {
                self.eval_for_effect(e)?;
                Ok(())
            }

            StmtKind::Assign { target, value } => {
                // A Sub has no return value, so using one as an expression
                // is a type mismatch.
                if self.is_statement_only_call(value) {
                    return Err(Flow::Error(err::type_mismatch()));
                }
                let v = self.eval(value)?;
                // Assigning to a variable takes an object's default value,
                // but a `Property Let` receives the object itself.
                let v = if assigns_to_property(target) {
                    v
                } else {
                    self.deref_value(v)?
                };
                self.assign_to(target, disown(v), false)?;
                Ok(())
            }

            StmtKind::SetAssign { target, value } => {
                let v = self.eval_set_rhs(value)?;
                self.assign_to(target, v, true)?;
                Ok(())
            }

            StmtKind::Dim(vars) => {
                for v in vars {
                    self.exec_dim(v)?;
                }
                Ok(())
            }

            StmtKind::ReDim { preserve, vars } => {
                for v in vars {
                    self.exec_redim(v, *preserve)?;
                }
                Ok(())
            }

            StmtKind::Const(list) => {
                for (name, e) in list {
                    let v = self.eval(e)?;
                    let v = self.deref_value(v)?;
                    let key: Rc<str> = name.to_ascii_lowercase().into();
                    if self.in_proc() {
                        self.declare(key, v);
                    } else {
                        // A variable of this name already exists, so the
                        // constant would redefine it.
                        if self.globals.contains_key(key.as_ref()) {
                            return Err(Flow::Error(VbError::code(1041)));
                        }
                        self.unit_consts.insert(key.clone());
                        self.consts.insert(key, v);
                    }
                }
                Ok(())
            }

            StmtKind::Erase(targets) => {
                for t in targets {
                    self.exec_erase(t)?;
                }
                Ok(())
            }

            StmtKind::If { branches, else_body } => {
                for (cond, body) in branches {
                    match self.eval_cond(cond)? {
                        // The test was skipped, so control falls through
                        // into this branch.
                        Ctrl::Skipped => return self.exec_block(body),
                        Ctrl::Ok(true) => return self.exec_block(body),
                        Ctrl::Ok(false) => {}
                    }
                }
                if let Some(b) = else_body {
                    return self.exec_block(b);
                }
                Ok(())
            }

            StmtKind::While { cond, body } => loop {
                match self.eval_cond(cond)? {
                    Ctrl::Ok(false) => return Ok(()),
                    Ctrl::Ok(true) | Ctrl::Skipped => {}
                }
                match self.exec_block(body) {
                    Ok(()) => {}
                    Err(Flow::ExitDo) => return Ok(()),
                    Err(e) => return Err(e),
                }
            },

            StmtKind::Do { cond, body } => self.exec_do(cond, body),
            StmtKind::For { var, from, to, step, body } => self.exec_for(var, from, to, step.as_ref(), body),
            StmtKind::ForEach { var, seq, body } => self.exec_for_each(var, seq, body),
            StmtKind::Select { subject, cases } => self.exec_select(subject, cases),

            StmtKind::With { subject, body } => {
                // A failed subject still runs the body; member access on the
                // resulting Empty then reports "object required".
                let v = match self.eval_ctrl(subject)? {
                    Ctrl::Ok(v) => {
                        // Entering `With` on a non-object raises straight
                        // away, though the body still runs.
                        if !v.is_object() {
                            let e = err::object_required();
                            if self.on_error_active() {
                                self.set_err(e);
                            } else {
                                return Err(Flow::Error(e));
                            }
                        }
                        v
                    }
                    Ctrl::Skipped => Value::Empty,
                };
                self.with_stack.push(v);
                let r = self.exec_block(body);
                self.with_stack.pop();
                r
            }

            StmtKind::Exit(k) => Err(match k {
                ExitKind::Do => Flow::ExitDo,
                ExitKind::For => Flow::ExitFor,
                ExitKind::Function => Flow::ExitFunction,
                ExitKind::Sub => Flow::ExitSub,
                ExitKind::Property => Flow::ExitProperty,
            }),

            StmtKind::OnErrorResumeNext => {
                self.err = ErrState::clear();
                match self.frames.last_mut() {
                    Some(f) => f.on_error = true,
                    None => self.global_on_error = true,
                }
                Ok(())
            }

            StmtKind::OnErrorGoto0 => {
                self.err = ErrState::clear();
                match self.frames.last_mut() {
                    Some(f) => f.on_error = false,
                    None => self.global_on_error = false,
                }
                Ok(())
            }

            // Declarations were hoisted; nothing to do at execution time.
            StmtKind::Function(_) | StmtKind::Property(_) | StmtKind::Class(_) => Ok(()),
        }
    }

    /// Evaluate a control expression such as a loop or `If` condition.
    ///
    /// VBScript's `On Error Resume Next` resumes at the *next instruction*,
    /// not the next statement. When a control expression fails, the branch or
    /// loop test that would have consumed it is skipped, so execution falls
    /// into the body. `Ctrl::Skipped` reports exactly that.
    fn eval_ctrl(&mut self, e: &Expr) -> Result<Ctrl<Value>, Flow> {
        self.ctrl(|it| it.eval_inner(e))
    }

    /// As [`Interp::eval_ctrl`], but resolving an object to its default
    /// value, which conditions and loop bounds need.
    fn eval_ctrl_scalar(&mut self, e: &Expr) -> Result<Ctrl<Value>, Flow> {
        self.ctrl(|it| {
            let v = it.eval_inner(e)?;
            it.deref_value(v)
        })
    }

    fn ctrl<T>(
        &mut self,
        f: impl FnOnce(&mut Interp) -> VbResult<T>,
    ) -> Result<Ctrl<T>, Flow> {
        match f(self) {
            Ok(v) => Ok(Ctrl::Ok(v)),
            Err(e) => {
                if self.on_error_active() {
                    self.set_err(e);
                    Ok(Ctrl::Skipped)
                } else {
                    Err(Flow::Error(e))
                }
            }
        }
    }

    /// As [`Interp::eval_ctrl`], but also folding the conversion to a boolean.
    fn eval_cond(&mut self, e: &Expr) -> Result<Ctrl<bool>, Flow> {
        match self.eval_ctrl_scalar(e)? {
            Ctrl::Skipped => Ok(Ctrl::Skipped),
            // A Null condition is simply false.
            Ctrl::Ok(v) if v.is_null() => Ok(Ctrl::Ok(false)),
            Ctrl::Ok(v) => match v.to_bool() {
                Ok(b) => Ok(Ctrl::Ok(b)),
                Err(err) => {
                    if self.on_error_active() {
                        self.set_err(err);
                        Ok(Ctrl::Skipped)
                    } else {
                        Err(Flow::Error(err))
                    }
                }
            },
        }
    }

    fn exec_dim(&mut self, v: &DimVar) -> ExecResult {
        if !self.in_proc() {
            let key: Rc<str> = v.name.to_ascii_lowercase().into();
            // A constant and a variable of the same name cannot coexist in
            // one compile unit.
            if self.unit_consts.contains(&key) {
                return Err(Flow::Error(VbError::code(1041)));
            }
            // Re-declaring an array is an error, though a scalar may be
            // declared again by a later compile unit.
            if self.unit_prior_arrays.contains(v.name.as_ref()) {
                return Err(Flow::Error(err::type_mismatch()));
            }
        }
        // `Dim` is a declaration, not an assignment: re-declaring a name in
        // the same scope leaves whatever value it holds alone.
        if self.declared_here(&v.name) {
            let existing = self.lookup_slot(&v.name).expect("declared in scope");
            if !existing.borrow().is_empty() {
                return Ok(());
            }
        }
        let init = if v.dims.is_empty() {
            if v.is_array {
                let mut a = VbArray::uninitialized();
                a.owned = true;
                Value::Array(Rc::new(a))
            } else {
                Value::Empty
            }
        } else {
            let dims = self.eval_dims(&v.dims)?;
            let mut a = VbArray::new(dims, true);
            a.owned = true;
            Value::Array(Rc::new(a))
        };
        // Re-executing a `Dim` (a loop body, say) resets the variable.
        self.declare(v.name.clone(), init);
        Ok(())
    }

    fn eval_dims(&mut self, dims: &[Expr]) -> Result<Vec<usize>, Flow> {
        let mut out = Vec::with_capacity(dims.len());
        for d in dims {
            let v = self.eval(d)?;
            let v = self.deref_value(v)?;
            let n = v.to_f64().map_err(Flow::Error)?;
            // Bounds are inclusive upper bounds, so the count is n + 1.
            if n < -1.0 || n > i32::MAX as f64 {
                return Err(Flow::Error(err::subscript()));
            }
            out.push((n as i64 + 1).max(0) as usize);
        }
        Ok(out)
    }

    fn exec_redim(&mut self, v: &DimVar, preserve: bool) -> ExecResult {
        // `ReDim` on an unknown name declares it, even under Option Explicit.
        let s = match self.lookup_slot(&v.name) {
            Some(s) => s,
            None => self.declare(v.name.clone(), Value::Empty),
        };
        // A plain `ReDim` rejects a fixed array before even looking at the
        // new bounds; `ReDim Preserve` evaluates them first.
        let is_fixed = matches!(&*s.borrow(), Value::Array(a) if a.fixed);
        if is_fixed && !preserve {
            return Err(Flow::Error(err::array_locked()));
        }
        let dims = self.eval_dims(&v.dims)?;
        if is_fixed {
            return Err(Flow::Error(err::array_locked()));
        }
        let mut cur = s.borrow_mut();
        match &mut *cur {
            Value::Array(rc) => {
                // Preserving can only resize the rightmost dimension, so the
                // rank and every other bound have to stay the same.
                if preserve && rc.is_sized() {
                    let same_shape = rc.dims.len() == dims.len()
                        && rc.dims[..rc.dims.len() - 1] == dims[..dims.len() - 1];
                    if !same_shape {
                        return Err(Flow::Error(err::subscript()));
                    }
                }
                let arr = Rc::make_mut(rc);
                if preserve {
                    arr.redim_preserve(dims);
                } else {
                    *arr = VbArray::new(dims, false);
                }
                arr.owned = true;
            }
            // ReDim on a plain variable turns it into an array.
            other => {
                let mut a = VbArray::new(dims, false);
                a.owned = true;
                *other = Value::Array(Rc::new(a));
            }
        }
        Ok(())
    }

    fn exec_erase(&mut self, target: &Expr) -> ExecResult {
        let name = match target {
            Expr::Ident(n) => n.clone(),
            _ => return Err(Flow::Error(err::invalid_call())),
        };
        let s = match self.lookup_slot(&name) {
            Some(s) => s,
            None => {
                if self.option_explicit {
                    return Err(Flow::Error(err::name_not_defined(&name)));
                }
                // Without Option Explicit the name is created, but erasing
                // something that is not an array is still a type mismatch.
                self.declare(name, Value::Empty);
                return Err(Flow::Error(err::type_mismatch()));
            }
        };
        let mut cur = s.borrow_mut();
        match &mut *cur {
            Value::Array(rc) => {
                if rc.fixed {
                    // A fixed array keeps its shape; only the contents reset.
                    let arr = Rc::make_mut(rc);
                    for e in arr.data.iter_mut() {
                        *e = Value::Empty;
                    }
                } else {
                    *cur = Value::Array(Rc::new(VbArray::uninitialized()));
                }
            }
            _ => return Err(Flow::Error(err::type_mismatch())),
        }
        Ok(())
    }

    fn exec_do(&mut self, cond: &DoCond, body: &[Stmt]) -> ExecResult {
        loop {
            // A pre-test that fails is skipped, so the body runs.
            match cond {
                DoCond::PreWhile(e) => {
                    if let Ctrl::Ok(false) = self.eval_cond(e)? {
                        return Ok(());
                    }
                }
                DoCond::PreUntil(e) => {
                    if let Ctrl::Ok(true) = self.eval_cond(e)? {
                        return Ok(());
                    }
                }
                _ => {}
            }
            match self.exec_block(body) {
                Ok(()) => {}
                Err(Flow::ExitDo) => return Ok(()),
                Err(e) => return Err(e),
            }
            // A post-test that fails skips the jump back, ending the loop.
            match cond {
                DoCond::PostWhile(e) => match self.eval_cond(e)? {
                    Ctrl::Ok(false) | Ctrl::Skipped => return Ok(()),
                    Ctrl::Ok(true) => {}
                },
                DoCond::PostUntil(e) => match self.eval_cond(e)? {
                    Ctrl::Ok(true) | Ctrl::Skipped => return Ok(()),
                    Ctrl::Ok(false) => {}
                },
                _ => {}
            }
        }
    }

    fn exec_for(
        &mut self,
        var: &Expr,
        from: &Expr,
        to: &Expr,
        step: Option<&Expr>,
        body: &[Stmt],
    ) -> ExecResult {
        // If any control value fails, the loop set-up is skipped: the body
        // runs once and `Next` then reports an uninitialised loop.
        let start = match self.eval_ctrl_scalar(from)? {
            Ctrl::Ok(v) => v,
            Ctrl::Skipped => return self.for_uninitialized(body, 92),
        };
        let limit = match self.eval_ctrl_scalar(to)? {
            Ctrl::Ok(v) => v,
            Ctrl::Skipped => return self.for_uninitialized(body, 92),
        };
        let stepv = match step {
            Some(e) => match self.eval_ctrl_scalar(e)? {
                Ctrl::Ok(v) => v,
                Ctrl::Skipped => return self.for_uninitialized(body, 92),
            },
            None => Value::I2(1),
        };

        // All three control values must be numeric before the loop begins.
        let nums = (|| -> VbResult<(f64, f64, f64)> {
            Ok((start.to_f64()?, limit.to_f64()?, stepv.to_f64()?))
        })();
        let (start_n, limit_n, step_n) = match nums {
            Ok(t) => t,
            Err(e) => {
                if self.on_error_active() {
                    self.set_err(e);
                    return self.for_uninitialized(body, 92);
                }
                return Err(Flow::Error(e));
            }
        };

        // The counter keeps the type produced by adding the step to the
        // start, so `For i = 1 To 3` counts in Integers.
        let mut cur = ops::arith(BinOp::Add, &start, &Value::I2(0)).map_err(Flow::Error)?;
        if matches!(cur, Value::Empty) {
            cur = Value::I2(0);
        }

        loop {
            // The counter is written before the test, so it keeps the first
            // value past the limit once the loop finishes.
            self.assign_to(var, cur.clone(), false)?;
            let n = cur.to_f64().map_err(Flow::Error)?;
            let done = if step_n >= 0.0 { n > limit_n } else { n < limit_n };
            if done {
                return Ok(());
            }
            match self.exec_block(body) {
                Ok(()) => {}
                Err(Flow::ExitFor) => return Ok(()),
                Err(e) => return Err(e),
            }
            // The body may reassign the counter; continue from its value.
            // A value that is no longer numeric fails here, at `Next`.
            let observed = self.read_lvalue(var)?;
            cur = ops::arith(BinOp::Add, &observed, &stepv).map_err(Flow::Error)?;
            let _ = start_n;
        }
    }

    fn exec_for_each(&mut self, var: &Expr, seq: &Expr, body: &[Stmt]) -> ExecResult {
        let subject = match self.eval_ctrl(seq)? {
            Ctrl::Ok(v) => v,
            // Evaluating the sequence failed, so the enumerator was never
            // built: the body runs once and `Next` reports error 451.
            Ctrl::Skipped => return self.for_uninitialized(body, 451),
        };
        let items = match self.enumerate(&subject) {
            Ok(i) => i,
            Err(e) => {
                if self.on_error_active() {
                    self.set_err(e);
                    return self.for_uninitialized(body, 451);
                }
                return Err(Flow::Error(e));
            }
        };
        for item in items {
            let is_obj = item.is_object();
            self.assign_to(var, item, is_obj)?;
            match self.exec_block(body) {
                Ok(()) => {}
                Err(Flow::ExitFor) => return Ok(()),
                Err(e) => return Err(e),
            }
        }
        // Running the enumeration to completion clears the loop variable.
        self.assign_to(var, Value::Empty, false)?;
        Ok(())
    }

    /// A loop whose set-up was skipped: the body runs once, then the `Next`
    /// instruction fails because the loop state was never established.
    fn for_uninitialized(&mut self, body: &[Stmt], code: i32) -> ExecResult {
        match self.exec_block(body) {
            Ok(()) => {}
            Err(Flow::ExitFor) => return Ok(()),
            Err(e) => return Err(e),
        }
        let e = VbError::code(code);
        if self.on_error_active() {
            self.set_err(e);
            Ok(())
        } else {
            Err(Flow::Error(e))
        }
    }

    /// Items a `For Each` walks over.
    pub fn enumerate(&mut self, v: &Value) -> VbResult<Vec<Value>> {
        match v {
            Value::Array(a) => {
                if !a.is_sized() {
                    // An unsized dynamic array yields nothing.
                    return Ok(Vec::new());
                }
                Ok(a.data.clone())
            }
            Value::Obj(Some(o)) => match o {
                ObjKind::Dictionary(d) => Ok(d.borrow().keys()),
                ObjKind::Matches(m) => {
                    Ok(m.iter().map(|x| Value::Obj(Some(ObjKind::Match(x.clone())))).collect())
                }
                ObjKind::SubMatches(s) => Ok(s.as_ref().clone()),
                ObjKind::Native(n) => {
                    let n = n.clone();
                    match n.enumerate(self)? {
                        Some(items) => Ok(items),
                        None => Err(err::not_a_collection()),
                    }
                }
                ObjKind::Class(_) => Err(err::not_a_collection()),
                _ => Err(err::not_a_collection()),
            },
            Value::Obj(None) => Err(err::not_a_collection()),
            _ => Err(err::not_a_collection()),
        }
    }

    fn exec_select(&mut self, subject: &Expr, cases: &[CaseClause]) -> ExecResult {
        let subject_failed;
        let s = match self.eval_ctrl_scalar(subject)? {
            Ctrl::Ok(v) => {
                subject_failed = false;
                v
            }
            // With no subject on the stack there is nothing to compare, and
            // no branch runs at all.
            Ctrl::Skipped => {
                subject_failed = true;
                Value::Empty
            }
        };
        if subject_failed {
            return Ok(());
        }
        let mut else_body: Option<&Vec<Stmt>> = None;
        for c in cases {
            if c.values.is_empty() {
                else_body = Some(&c.body);
                continue;
            }
            for ve in &c.values {
                let v = match self.eval_ctrl_scalar(ve)? {
                    Ctrl::Ok(v) => v,
                    // The comparison was skipped, so control falls into
                    // this case body.
                    Ctrl::Skipped => return self.exec_block(&c.body),
                };
                match ops::compare_op(BinOp::Eq, &s, &v, false, false, is_literal(ve)) {
                    Ok(Value::Bool(true)) => return self.exec_block(&c.body),
                    Ok(_) => {}
                    Err(e) => {
                        if self.on_error_active() {
                            self.set_err(e);
                            return self.exec_block(&c.body);
                        }
                        return Err(Flow::Error(e));
                    }
                }
            }
        }
        match else_body {
            Some(b) => self.exec_block(b),
            None => Ok(()),
        }
    }

    // ---- assignment ------------------------------------------------------

    /// Read an lvalue's current value, used by `For` to observe the counter.
    fn read_lvalue(&mut self, target: &Expr) -> Result<Value, Flow> {
        let v = self.eval(target)?;
        Ok(v)
    }

    fn assign_to(&mut self, target: &Expr, value: Value, is_set: bool) -> ExecResult {
        // `Set x = <non-object>` is only legal for Nothing/Empty/Null.
        if is_set && !matches!(value, Value::Obj(_) | Value::Empty | Value::Null) {
            return Err(Flow::Error(err::object_required()));
        }
        match target {
            Expr::Ident(name) => {
                // Assigning to the enclosing function's own name sets the
                // return value; the frame already holds a slot for it.
                if self.lookup_slot(name).is_none() {
                    // Constants and procedure names are not assignable.
                    if self.consts.contains_key(name.as_ref())
                        || self.funcs.contains_key(name.as_ref())
                        || self.props.contains_key(&(name.clone(), PropKind::Get))
                    {
                        return Err(Flow::Error(err::illegal_assignment()));
                    }
                    let host = self.host.clone();
                    let handled =
                        host.set_global(self, name, value.clone())
                            .map_err(Flow::Error)?;
                    if handled {
                        return Ok(());
                    }
                }
                let s = self.slot_for_write(name).map_err(Flow::Error)?;
                let old = std::mem::replace(&mut *s.borrow_mut(), value);
                self.release(old).map_err(Flow::Error)?;
                Ok(())
            }
            Expr::Member { target: obj, name } => {
                let o = self.eval(obj)?;
                self.set_member(&o, name, &[], value, is_set).map_err(Flow::Error)
            }
            Expr::WithMember { name } => {
                let o = self
                    .with_stack
                    .last()
                    .cloned()
                    .ok_or_else(|| Flow::Error(err::invalid_reference()))?;
                self.set_member(&o, name, &[], value, is_set).map_err(Flow::Error)
            }
            Expr::Index { target: inner, args } => self.assign_index(inner, args, value, is_set),
            _ => Err(Flow::Error(err::illegal_assignment())),
        }
    }

    /// Run `Class_Terminate` if `old` held the last reference to an instance.
    fn release(&mut self, old: Value) -> VbResult<()> {
        let obj = match old {
            Value::Obj(Some(ObjKind::Class(c))) => c,
            _ => return Ok(()),
        };
        // `obj` is the only remaining handle, so the instance is going away.
        if Rc::strong_count(&obj) != 1 {
            return Ok(());
        }
        let term = obj
            .def
            .methods
            .iter()
            .find(|m| m.name.eq_ignore_ascii_case("class_terminate"))
            .cloned();
        if let Some(f) = term {
            self.call_func(&f, Vec::new(), Some(ObjKind::Class(obj)))?;
        }
        Ok(())
    }

    fn assign_index(
        &mut self,
        inner: &Expr,
        args: &[Arg],
        value: Value,
        is_set: bool,
    ) -> ExecResult {
        let idx = self.eval_args(args)?;
        let idx_vals: Vec<Value> = idx.iter().map(|a| a.value()).collect();

        // `a(i) = v` on a variable holding an array writes the element.
        if let Expr::Ident(name) = inner {
            if let Some(s) = self.lookup_slot(name) {
                let is_arr = matches!(&*s.borrow(), Value::Array(_));
                if is_arr {
                    let subs = self.to_subscripts(&idx_vals).map_err(Flow::Error)?;
                    let mut cur = s.borrow_mut();
                    if let Value::Array(rc) = &mut *cur {
                        let arr = Rc::make_mut(rc);
                        let off = arr.offset(&subs).ok_or(Flow::Error(err::subscript()))?;
                        arr.data[off] = value;
                        return Ok(());
                    }
                    unreachable!()
                }
            }
        }

        // A chain like `x(0)(1) = v` writes into a nested array, which means
        // descending from the variable rather than through a copy of it.
        if let Expr::Index { .. } = inner {
            if let Some((root, groups)) = index_chain(inner) {
                if let Some(slot) = self.lookup_slot(root) {
                    let is_arr = slot.borrow().is_array();
                    if is_arr {
                        let mut path = Vec::with_capacity(groups.len() + 1);
                        for g in &groups {
                            let vals = self.eval_args_v(g)?;
                            path.push(self.to_subscripts(&vals).map_err(Flow::Error)?);
                        }
                        path.push(self.to_subscripts(&idx_vals).map_err(Flow::Error)?);
                        let mut cur = slot.borrow_mut();
                        return set_nested(&mut cur, &path, value).map_err(Flow::Error);
                    }
                }
            }
        }

        // A qualified name is a property assignment, with any subscripts
        // passed through as the property's arguments.
        match inner {
            Expr::Member { target: t2, name } => {
                let o = self.eval(t2)?;
                return self
                    .set_member(&o, name, &idx_vals, value, is_set)
                    .map_err(Flow::Error);
            }
            Expr::WithMember { name } => {
                let o = self
                    .with_stack
                    .last()
                    .cloned()
                    .ok_or_else(|| Flow::Error(err::invalid_reference()))?;
                return self
                    .set_member(&o, name, &idx_vals, value, is_set)
                    .map_err(Flow::Error);
            }
            _ => {}
        }

        // Otherwise the target must itself be an object with a default
        // indexed property.
        let obj = self.eval(inner)?;
        if !matches!(obj, Value::Obj(_) | Value::Array(_)) {
            return Err(Flow::Error(err::type_mismatch()));
        }
        self.set_default_indexed(&obj, &idx_vals, value, is_set)
            .map_err(Flow::Error)
    }

    fn to_subscripts(&self, idx: &[Value]) -> VbResult<Vec<usize>> {
        idx.iter()
            .map(|v| {
                let n = v.to_f64()?;
                if n < 0.0 || n > i32::MAX as f64 {
                    return Err(err::subscript());
                }
                Ok(crate::value::round_half_even(n) as usize)
            })
            .collect()
    }

    // ---- expressions -----------------------------------------------------

    pub fn eval(&mut self, e: &Expr) -> Result<Value, Flow> {
        self.eval_inner(e).map_err(Flow::Error)
    }

    /// Evaluate a statement-level expression, discarding the result.
    fn eval_for_effect(&mut self, e: &Expr) -> ExecResult {
        // A variable used as a whole statement calls its default member;
        // a scalar has none, which is a type mismatch.
        if let Expr::Ident(name) = e {
            if let Some(slot) = self.lookup_slot(name) {
                let cur = slot.borrow().clone();
                return match cur {
                    Value::Obj(Some(o)) => {
                        self.call_default(&o, &[]).map(|_| ()).map_err(Flow::Error)
                    }
                    _ => Err(Flow::Error(err::type_mismatch())),
                };
            }
        }
        let discards_result = self.is_bare_conversion_call(e);
        let v = self.eval_inner(e).map_err(Flow::Error)?;
        // A conversion invoked as a bare statement is called without a result
        // slot, and reports that its value has nowhere to go. Null is the one
        // result that needs no storage.
        if discards_result && !matches!(v, Value::Empty | Value::Null) {
            return Err(Flow::Error(VbError::code(458)));
        }
        Ok(())
    }

    /// Whether this expression is a bare call to one of the conversion
    /// built-ins, which need a result slot the statement form does not give
    /// them.
    fn is_bare_conversion_call(&self, e: &Expr) -> bool {
        const CONVERSIONS: &[&str] = &[
            "cbool", "cbyte", "ccur", "cdate", "cdbl", "cint", "clng", "csng", "cstr",
        ];
        let name = match e {
            Expr::Index { target, .. } => match &**target {
                Expr::Ident(n) => n,
                _ => return false,
            },
            _ => return false,
        };
        CONVERSIONS.contains(&name.as_ref())
            && self.lookup_slot(name).is_none()
            && !self.funcs.contains_key(name.as_ref())
    }

    /// Whether this expression calls a built-in that behaves as a Sub, and
    /// so cannot appear where a value is expected.
    fn is_statement_only_call(&self, e: &Expr) -> bool {
        const SUBS: &[&str] = &["randomize", "execute", "executeglobal"];
        let name = match e {
            Expr::Index { target, .. } => match &**target {
                Expr::Ident(n) => n,
                _ => return false,
            },
            _ => return false,
        };
        SUBS.contains(&name.as_ref())
            && self.lookup_slot(name).is_none()
            && !self.funcs.contains_key(name.as_ref())
    }

    /// The right-hand side of `Set`: an object reference, not its value.
    fn eval_set_rhs(&mut self, e: &Expr) -> Result<Value, Flow> {
        self.eval(e)
    }

    fn eval_inner(&mut self, e: &Expr) -> VbResult<Value> {
        match e {
            Expr::Empty => Ok(Value::Empty),
            Expr::Null => Ok(Value::Null),
            Expr::Nothing => Ok(Value::Obj(None)),
            Expr::Bool(b) => Ok(Value::Bool(*b)),
            Expr::Int(v) => Ok(Value::I2(*v as i16)),
            Expr::Long(v) => Ok(Value::I4(*v)),
            Expr::Real(v) => Ok(Value::R8(*v)),
            Expr::Date(v) => Ok(Value::Date(*v)),
            Expr::Str(s) => Ok(Value::Str(s.clone())),

            Expr::Me => {
                if let Some(o) = self.frame().and_then(|f| f.me.clone()) {
                    return Ok(Value::Obj(Some(o)));
                }
                // At global scope `Me` is the host's script object.
                let host = self.host.clone();
                let g = host.global_object(self)?;
                g.ok_or_else(err::invalid_reference)
            }

            Expr::New(name) => self.construct(name),

            // Parentheses only affect how an argument is passed.
            Expr::Paren(inner) => self.eval_inner(inner),

            Expr::Ident(name) => self.eval_ident(name),

            Expr::WithMember { name } => {
                let o = self.with_stack.last().cloned().ok_or_else(err::invalid_reference)?;
                self.get_member(&o, name, &[])
            }

            Expr::Member { target, name } => {
                let o = self.eval_inner(target)?;
                self.get_member(&o, name, &[])
            }

            Expr::Index { target, args } => self.eval_index(target, args),

            Expr::Unary(op, a) => {
                let v = self.eval_inner(a)?;
                // Unary plus is an identity: it neither converts its operand
                // nor resolves an object to its default value.
                if matches!(op, UnOp::Plus) {
                    return Ok(v);
                }
                let v = self.deref_value(v)?;
                match op {
                    UnOp::Neg => ops::negate(&v),
                    UnOp::Not => ops::not(&v),
                    UnOp::Plus => unreachable!(),
                }
            }

            Expr::Binary(op, a, b) => self.eval_binary(*op, a, b),
        }
    }

    fn eval_binary(&mut self, op: BinOp, a: &Expr, b: &Expr) -> VbResult<Value> {
        // `Is` compares references, so neither side is dereferenced.
        if matches!(op, BinOp::Is | BinOp::IsNot) {
            let x = self.eval_inner(a)?;
            let y = self.eval_inner(b)?;
            let same = match (&x, &y) {
                (Value::Obj(None), Value::Obj(None)) => true,
                (Value::Obj(Some(p)), Value::Obj(Some(q))) => p.same(q),
                (Value::Obj(Some(_)), Value::Obj(None))
                | (Value::Obj(None), Value::Obj(Some(_))) => false,
                // `Is` is only defined between object references.
                _ => return Err(err::object_required()),
            };
            return Ok(Value::Bool(if op == BinOp::Is { same } else { !same }));
        }

        let x = self.eval_inner(a)?;
        let x = self.deref_value(x)?;
        let y = self.eval_inner(b)?;
        let y = self.deref_value(y)?;

        match op {
            BinOp::Add => ops::add(&x, &y),
            BinOp::Sub | BinOp::Mul => ops::arith(op, &x, &y),
            BinOp::Div => ops::divide(&x, &y),
            BinOp::IntDiv => ops::int_divide(&x, &y),
            BinOp::Mod => ops::modulo(&x, &y),
            BinOp::Pow => ops::power(&x, &y),
            BinOp::Concat => ops::concat(&x, &y),
            BinOp::Eq | BinOp::Ne | BinOp::Lt | BinOp::Gt | BinOp::Le | BinOp::Ge => {
                ops::compare_op(op, &x, &y, false, is_literal(a), is_literal(b))
            }
            BinOp::And | BinOp::Or | BinOp::Xor | BinOp::Eqv | BinOp::Imp => {
                ops::logical(op, &x, &y)
            }
            BinOp::Is | BinOp::IsNot => unreachable!(),
        }
    }

    fn eval_ident(&mut self, name: &Rc<str>) -> VbResult<Value> {
        if let Some(f) = self.frames.last() {
            if let Some(s) = f.vars.get(name.as_ref()) {
                return Ok(s.borrow().clone());
            }
            if let Some(ObjKind::Class(c)) = &f.me {
                let field = c.fields.borrow().get(name.as_ref()).cloned();
                if let Some(s) = field {
                    return Ok(s.borrow().clone());
                }
            }
        }
        // A constant is inlined into the unit that declares it, so that unit
        // keeps seeing the constant even if a later unit Dims the same name.
        if self.execute_depth == 0 {
            if let Some(v) = self.consts.get(name.as_ref()) {
                return Ok(v.clone());
            }
        }
        if let Some(s) = self.globals.get(name.as_ref()) {
            return Ok(s.borrow().clone());
        }
        if let Some(v) = self.consts.get(name.as_ref()) {
            return Ok(v.clone());
        }
        if name.as_ref() == "err" {
            return Ok(Value::Obj(Some(ObjKind::Err)));
        }
        // A class method's own instance members.
        if let Some(v) = self.class_member_value(name)? {
            return Ok(v);
        }
        if let Some(f) = self.funcs.get(name.as_ref()).cloned() {
            return self.call_func(&f, Vec::new(), None);
        }
        if let Some(p) = self.props.get(&(name.clone(), PropKind::Get)).cloned() {
            return self.call_prop_get(&p, Vec::new(), None);
        }
        if let Some(v) = crate::builtins::constant(name) {
            return Ok(v);
        }
        if let Some(r) = crate::builtins::call(self, name, &mut Vec::new())? {
            return Ok(r);
        }
        let host = self.host.clone();
        let h = host;
        if let Some(v) = h.get_global(self, name)? {
            return Ok(v);
        }
        let mut no_args: Vec<ArgVal> = Vec::new();
        if let Some(v) = h.call(self, name, &mut no_args)? {
            return Ok(v);
        }
        drop(h);
        if self.option_explicit {
            Err(err::name_not_defined(name))
        } else {
            // Reading an undeclared name defines it as Empty.
            self.declare(name.clone(), Value::Empty);
            Ok(Value::Empty)
        }
    }

    fn class_member_value(&mut self, name: &Rc<str>) -> VbResult<Option<Value>> {
        let me = match self.frame().and_then(|f| f.me.clone()) {
            Some(ObjKind::Class(c)) => c,
            _ => return Ok(None),
        };
        if let Some(m) = me.def.methods.iter().find(|m| m.name.eq_ignore_ascii_case(name)) {
            let m = m.clone();
            return Ok(Some(self.call_func(&m, Vec::new(), Some(ObjKind::Class(me)))?));
        }
        if let Some(p) = me
            .def
            .props
            .iter()
            .find(|p| p.kind == PropKind::Get && p.name.eq_ignore_ascii_case(name))
        {
            let p = p.clone();
            return Ok(Some(self.call_prop_get(&p, Vec::new(), Some(ObjKind::Class(me)))?));
        }
        if let Some((_, v)) = me.def.consts.iter().find(|(n, _)| n.eq_ignore_ascii_case(name)) {
            let v = v.clone();
            return Ok(Some(self.eval_inner(&v)?));
        }
        Ok(None)
    }

    /// `target(args)`: a call, an array index, or a default-property read.
    fn eval_index(&mut self, target: &Expr, args: &[Arg]) -> VbResult<Value> {
        // Parentheses around the callee change nothing about the call.
        let target = strip_parens(target);
        if let Expr::Ident(name) = target {
            // A variable holding an array is indexed, never called.
            if let Some(s) = self.lookup_slot(name) {
                let cur = s.borrow().clone();
                return match cur {
                    Value::Array(_) => {
                        let idx = self.eval_args_v(args)?;
                        self.index_array(&cur, &idx)
                    }
                    Value::Obj(Some(o)) => {
                        let idx = self.eval_args_v(args)?;
                        self.call_default(&o, &idx)
                    }
                    // A scalar cannot be subscripted, and empty parentheses
                    // are a call rather than a read. The name may still be a
                    // procedure: inside a function its own name doubles as
                    // the return-value slot, so `f(x)` there recurses.
                    _ => {
                        if self.funcs.contains_key(name.as_ref())
                            || self.props.contains_key(&(name.clone(), PropKind::Get))
                        {
                            self.call_named(name, args)
                        } else {
                            Err(err::type_mismatch())
                        }
                    }
                };
            }
            return self.call_named(name, args);
        }

        if let Expr::Member { target: obj, name } = target {
            let o = self.eval_inner(obj)?;
            let a = self.eval_args_v(args)?;
            return self.get_member_ex(&o, name, &a, args.is_empty());
        }

        if let Expr::WithMember { name } = target {
            let o = self.with_stack.last().cloned().ok_or_else(err::invalid_reference)?;
            let a = self.eval_args_v(args)?;
            return self.get_member_ex(&o, name, &a, args.is_empty());
        }

        // `f(1)(2)` and similar chains.
        let base = self.eval_inner(target)?;
        let idx = self.eval_args_v(args)?;
        match &base {
            Value::Array(_) => self.index_array(&base, &idx),
            Value::Obj(Some(o)) => self.call_default(&o.clone(), &idx),
            _ => Err(err::type_mismatch()),
        }
    }

    /// Call a name that is not a variable: a script procedure, a builtin, or
    /// something the host provides.
    fn call_named(&mut self, name: &Rc<str>, args: &[Arg]) -> VbResult<Value> {
        // Inside a class method the instance's own members come first, so a
        // global procedure of the same name does not shadow them.
        if let Some(ObjKind::Class(c)) = self.frame().and_then(|f| f.me.clone()) {
            if let Some(m) = c.def.methods.iter().find(|m| m.name.eq_ignore_ascii_case(name)) {
                let m = m.clone();
                let a = self.eval_args(args).map_err(flow_to_err)?;
                return self.call_func(&m, a, Some(ObjKind::Class(c)));
            }
            if let Some(p) = c
                .def
                .props
                .iter()
                .find(|p| p.kind == PropKind::Get && p.name.eq_ignore_ascii_case(name))
            {
                let p = p.clone();
                let a = self.eval_args(args).map_err(flow_to_err)?;
                return self.call_prop_get(&p, a, Some(ObjKind::Class(c)));
            }
            // An instance field that holds an array or object.
            let field = c.fields.borrow().get(name.as_ref()).cloned();
            if let Some(s) = field {
                let cur = s.borrow().clone();
                let idx = self.eval_args_v(args)?;
                return match cur {
                    Value::Array(_) => self.index_array(&cur, &idx),
                    Value::Obj(Some(o)) => self.call_default(&o, &idx),
                    other if idx.is_empty() => Ok(other),
                    _ => Err(err::type_mismatch()),
                };
            }
        }
        if let Some(f) = self.funcs.get(name.as_ref()).cloned() {
            let (a, wb) = self.eval_args_wb(args).map_err(flow_to_err)?;
            let r = self.call_func(&f, a, None);
            self.apply_writebacks(wb)?;
            return r;
        }
        if let Some(p) = self.props.get(&(name.clone(), PropKind::Get)).cloned() {
            let (a, wb) = self.eval_args_wb(args).map_err(flow_to_err)?;
            let r = self.call_prop_get(&p, a, None);
            self.apply_writebacks(wb)?;
            return r;
        }
        if crate::builtins::is_builtin(name) {
            let (mut a, wb) = self.eval_args_wb(args).map_err(flow_to_err)?;
            let r = crate::builtins::call(self, name, &mut a);
            self.apply_writebacks(wb)?;
            if let Some(v) = r? {
                return Ok(v);
            }
        }
        {
            let host = self.host.clone();
            let (mut a, wb) = self.eval_args_wb(args).map_err(flow_to_err)?;
            let r = host.call(self, name, &mut a);
            self.apply_writebacks(wb)?;
            if let Some(v) = r? {
                return Ok(v);
            }
        }
        if let Some(v) = self.consts.get(name.as_ref()).cloned() {
            let idx = self.eval_args_v(args)?;
            if idx.is_empty() {
                return Ok(v);
            }
            return match &v {
                Value::Array(_) => self.index_array(&v, &idx),
                _ => Err(err::type_mismatch()),
            };
        }
        // A host global that is an object can be indexed through its
        // default member, as in `indexedObj(0)`.
        {
            let host = self.host.clone();
            let g = host.get_global(self, name)?;
            if let Some(v) = g {
                let idx = self.eval_args_v(args)?;
                return match &v {
                    Value::Obj(Some(o)) => self.call_default(&o.clone(), &idx),
                    Value::Array(_) => self.index_array(&v, &idx),
                    other if idx.is_empty() => Ok(other.clone()),
                    _ => Err(err::type_mismatch()),
                };
            }
        }
        // Not a procedure and not a variable: creating it on demand matches
        // VBScript when Option Explicit is off.
        if !self.option_explicit && args.is_empty() {
            self.declare(name.clone(), Value::Empty);
            return Ok(Value::Empty);
        }
        Err(err::sub_not_defined(name))
    }

    fn eval_args(&mut self, args: &[Arg]) -> Result<Vec<ArgVal>, Flow> {
        self.eval_args_wb(args).map(|(a, _)| a)
    }

    /// Evaluate call arguments, returning the values plus the array elements
    /// that must be copied back once the call returns.
    ///
    /// VBScript passes variables and array elements by reference. A variable
    /// can share its slot directly; an element lives inside the array, so it
    /// gets a temporary slot and is written back afterwards.
    fn eval_args_wb<'a>(
        &mut self,
        args: &'a [Arg],
    ) -> Result<(Vec<ArgVal>, Writebacks<'a>), Flow> {
        let mut out = Vec::with_capacity(args.len());
        let mut writeback = Vec::new();
        for a in args {
            match a {
                Arg::Missing => out.push(ArgVal::Missing),
                Arg::Val(Expr::Ident(n)) => {
                    let aliased = self.is_aliased_binding(n);
                    match self.lookup_slot(n) {
                        Some(s) => out.push(ArgVal::Ref { slot: s, aliased }),
                        None => {
                            let v = self.eval(&Expr::Ident(n.clone()))?;
                            // Evaluating may have declared it; prefer the slot.
                            match self.lookup_slot(n) {
                                Some(s) => out.push(ArgVal::Ref { slot: s, aliased }),
                                None => out.push(ArgVal::Val(v)),
                            }
                        }
                    }
                }
                // Parentheses force a copy, so `f (x)` cannot write back.
                Arg::Val(Expr::Paren(inner)) => {
                    let v = self.eval(inner)?;
                    out.push(ArgVal::Val(v));
                }
                Arg::Val(e @ Expr::Index { target, .. }) if self.is_array_lvalue(target) => {
                    let v = self.eval(e)?;
                    let s = slot(v);
                    // A temporary standing in for an array element is not
                    // the caller's own storage.
                    out.push(ArgVal::Ref { slot: s.clone(), aliased: false });
                    writeback.push((e, s));
                }
                Arg::Val(e) => {
                    let v = self.eval(e)?;
                    out.push(ArgVal::Val(v));
                }
            }
        }
        Ok((out, writeback))
    }

    /// Whether this name refers to storage the caller owns, rather than a
    /// copy made when binding a parameter.
    fn is_aliased_binding(&self, name: &str) -> bool {
        match self.frames.last() {
            Some(f) => !f.copied_params.contains(name),
            None => true,
        }
    }

    /// True when `e` is a chain rooted at a variable that holds an array,
    /// so an element of it can be passed by reference.
    fn is_array_lvalue(&self, e: &Expr) -> bool {
        let root = match e {
            Expr::Ident(n) => n,
            Expr::Index { .. } => match index_chain(e) {
                Some((n, _)) => n,
                None => return false,
            },
            _ => return false,
        };
        self.lookup_slot(root)
            .map(|s| s.borrow().is_array())
            .unwrap_or(false)
    }

    fn apply_writebacks(&mut self, wb: Writebacks<'_>) -> VbResult<()> {
        for (e, s) in wb {
            let v = s.borrow().clone();
            self.assign_to(e, v, false).map_err(flow_to_err)?;
        }
        Ok(())
    }

    /// Argument values for a member or index expression. Objects stay
    /// objects here: an argument is passed as a reference, and only a
    /// context that needs a scalar (an array subscript, say) resolves it.
    fn eval_args_v(&mut self, args: &[Arg]) -> VbResult<Vec<Value>> {
        let mut out = Vec::with_capacity(args.len());
        for a in args {
            match a {
                Arg::Missing => out.push(Value::ErrCode(crate::value::VT_ERROR)),
                Arg::Val(e) => out.push(self.eval_inner(e)?),
            }
        }
        Ok(out)
    }

    pub fn index_array(&mut self, arr: &Value, idx: &[Value]) -> VbResult<Value> {
        {
            let a = match arr {
                Value::Array(a) => a,
                _ => return Err(err::type_mismatch()),
            };
            if !a.is_sized() {
                return Err(err::subscript());
            }
        }
        if idx.is_empty() {
            // `a()` supplies no subscripts at all, which is out of range for
            // any array.
            return Err(err::subscript());
        }
        // A subscript given as an object resolves through its default value.
        let mut scalars = Vec::with_capacity(idx.len());
        for v in idx {
            scalars.push(self.deref_value(v.clone())?);
        }
        let a = match arr {
            Value::Array(a) => a,
            _ => return Err(err::type_mismatch()),
        };
        let subs = self.to_subscripts(&scalars)?;
        let off = a.offset(&subs).ok_or_else(err::subscript)?;
        Ok(a.data[off].clone())
    }

    // ---- procedures ------------------------------------------------------

    fn push_frame(&mut self, f: Frame) -> VbResult<()> {
        if self.frames.len() >= MAX_DEPTH {
            return Err(err::out_of_stack());
        }
        self.frames.push(f);
        Ok(())
    }

    /// Bind arguments into a fresh frame and run a procedure body.
    fn invoke(
        &mut self,
        name: &Rc<str>,
        params: &[Param],
        body: &[Stmt],
        mut args: Vec<ArgVal>,
        me: Option<ObjKind>,
        wants_result: bool,
    ) -> VbResult<Value> {
        let required = params.iter().filter(|p| !p.optional).count();
        if args.len() > params.len() || args.len() < required {
            return Err(err::wrong_arg_count());
        }

        let mut frame = Frame::new();
        frame.me = me;
        for (i, p) in params.iter().enumerate() {
            let (s, copied) = match args.get_mut(i) {
                None | Some(ArgVal::Missing) => (slot(Value::Empty), true),
                Some(ArgVal::Ref { slot: r, aliased }) => {
                    if p.by_val {
                        (slot(r.borrow().clone()), true)
                    } else {
                        (r.clone(), !*aliased)
                    }
                }
                Some(ArgVal::Val(v)) => (slot(v.clone()), true),
            };
            if copied {
                frame.copied_params.insert(p.name.clone());
            }
            frame.vars.insert(p.name.clone(), s);
        }
        // The return value lives in a slot named after the procedure.
        if wants_result {
            frame.vars.insert(name.clone(), slot(Value::Empty));
        }

        self.push_frame(frame)?;
        self.hoist(body, false);
        let r = self.exec_block(body);
        let frame = self.frames.pop().expect("frame balance");

        match r {
            Ok(())
            | Err(Flow::ExitFunction)
            | Err(Flow::ExitSub)
            | Err(Flow::ExitProperty)
            | Err(Flow::Halt) => {}
            Err(Flow::Error(e)) => return Err(e),
            // A stray `Exit For`/`Exit Do` outside a loop simply ends the call.
            Err(_) => {}
        }

        if wants_result {
            Ok(frame.vars.get(name).map(|s| s.borrow().clone()).unwrap_or(Value::Empty))
        } else {
            Ok(Value::Empty)
        }
    }

    pub fn call_func(
        &mut self,
        f: &Rc<FuncDef>,
        args: Vec<ArgVal>,
        me: Option<ObjKind>,
    ) -> VbResult<Value> {
        self.invoke(&f.name, &f.params, &f.body, args, me, f.is_function)
    }

    pub fn call_prop_get(
        &mut self,
        p: &Rc<PropDef>,
        args: Vec<ArgVal>,
        me: Option<ObjKind>,
    ) -> VbResult<Value> {
        self.invoke(&p.name, &p.params, &p.body, args, me, true)
    }

    pub fn call_prop_set_public(
        &mut self,
        p: &Rc<PropDef>,
        args: Vec<ArgVal>,
        me: Option<ObjKind>,
    ) -> VbResult<()> {
        self.invoke(&p.name, &p.params, &p.body, args, me, false)?;
        Ok(())
    }

    fn construct(&mut self, name: &Rc<str>) -> VbResult<Value> {
        let key: Rc<str> = name.to_ascii_lowercase().into();
        // `New RegExp` is built in.
        if key.as_ref() == "regexp" {
            return Ok(Value::Obj(Some(ObjKind::RegExp(Rc::new(RefCell::new(
                crate::objects::regexp::RegExpObj::new(),
            ))))));
        }
        let def = match self.classes.get(&key).cloned() {
            Some(d) => d,
            // The name is resolved as a variable first, so an entirely
            // unknown identifier reports "variable is undefined".
            None => {
                return Err(if self.lookup_slot(&key).is_some() {
                    err::class_not_defined()
                } else {
                    err::name_not_defined(name)
                })
            }
        };
        let obj = ClassObj::new(def.clone());
        // Run the constructor if the class defines one.
        if let Some(init) = def
            .methods
            .iter()
            .find(|m| m.name.eq_ignore_ascii_case("class_initialize"))
        {
            let init = init.clone();
            self.call_func(&init, Vec::new(), Some(ObjKind::Class(obj.clone())))?;
        }
        Ok(Value::Obj(Some(ObjKind::Class(obj))))
    }

    // ---- members ---------------------------------------------------------

    pub fn get_member(&mut self, obj: &Value, name: &str, args: &[Value]) -> VbResult<Value> {
        self.get_member_ex(obj, name, args, false)
    }

    /// As [`Interp::get_member`], but recording whether the source wrote an
    /// empty argument list.
    pub fn get_member_ex(
        &mut self,
        obj: &Value,
        name: &str,
        args: &[Value],
        empty_parens: bool,
    ) -> VbResult<Value> {
        let o = match obj {
            Value::Obj(Some(o)) => o.clone(),
            Value::Obj(None) => return Err(err::object_required()),
            Value::Empty | Value::Null => return Err(err::object_required()),
            _ => return Err(err::object_required()),
        };
        crate::members::get(self, &o, name, args, empty_parens)
    }

    pub fn set_member(
        &mut self,
        obj: &Value,
        name: &str,
        args: &[Value],
        value: Value,
        is_set: bool,
    ) -> VbResult<()> {
        let o = match obj {
            Value::Obj(Some(o)) => o.clone(),
            Value::Obj(None) => return Err(err::object_required()),
            _ => return Err(err::object_required()),
        };
        crate::members::set(self, &o, name, args, value, is_set)
    }

    pub fn call_default(&mut self, o: &ObjKind, args: &[Value]) -> VbResult<Value> {
        crate::members::call_default(self, o, args)
    }

    fn set_default_indexed(
        &mut self,
        obj: &Value,
        idx: &[Value],
        value: Value,
        is_set: bool,
    ) -> VbResult<()> {
        let o = match obj {
            Value::Obj(Some(o)) => o.clone(),
            _ => return Err(err::object_required()),
        };
        crate::members::set_default(self, &o, idx, value, is_set)
    }

    pub fn object_default_value(&mut self, o: &ObjKind) -> VbResult<Value> {
        crate::members::call_default(self, o, &[])
    }

    // ---- helpers used by builtins ---------------------------------------

    /// Invoke a class method or property by name, used by `GetRef` callbacks.
    pub fn call_by_name(&mut self, name: &str, args: Vec<ArgVal>) -> VbResult<Value> {
        let key: Rc<str> = name.to_ascii_lowercase().into();
        if let Some(f) = self.funcs.get(&key).cloned() {
            return self.call_func(&f, args, None);
        }
        let mut a = args;
        if let Some(r) = crate::builtins::call(self, &key, &mut a)? {
            return Ok(r);
        }
        Err(err::sub_not_defined(name))
    }

    /// Whether a name is currently a variable, procedure or constant.
    ///
    /// The console uses this to tell `echo myvar` — which passes a value —
    /// from `echo myvar` where no such variable exists and the word is text.
    pub fn is_defined(&self, name: &str) -> bool {
        let key = name.to_ascii_lowercase();
        self.lookup_slot(&key).is_some()
            || self.consts.contains_key(key.as_str())
            || self.funcs.contains_key(key.as_str())
            || self.classes.contains_key(key.as_str())
            || self.props.contains_key(&(Rc::from(key.as_str()), PropKind::Get))
    }

    pub fn err_state(&self) -> &ErrState {
        &self.err
    }

    /// Raise an error the way `Err.Raise` does, normalising the HRESULT form.
    pub fn raise(&mut self, number: i32, source: Option<Rc<str>>, description: Option<Rc<str>>,
                 helpfile: Option<Rc<str>>, helpcontext: Option<i32>) -> VbError {
        let n = hresult_to_number(number);
        let desc = description.unwrap_or_else(|| {
            let d = describe(n);
            if d == "Unknown runtime error" && n != number {
                Rc::from("")
            } else {
                Rc::from(d)
            }
        });
        VbError {
            number: n,
            source: source.unwrap_or_else(|| Rc::from("Microsoft VBScript runtime error")),
            description: desc,
            helpfile: helpfile.unwrap_or_else(|| Rc::from("")),
            helpcontext: helpcontext.unwrap_or(0),
        }
    }

    /// Run source text in the current scope (`Execute`).
    pub fn execute(&mut self, src: &str, global: bool) -> VbResult<()> {
        let prog = crate::parser::parse(src).map_err(syntax_to_vb)?;
        let saved = if global { Some(std::mem::take(&mut self.frames)) } else { None };
        // `Option Explicit` applies to the unit that declares it and does
        // not leak into or out of the surrounding script.
        let saved_explicit = std::mem::replace(&mut self.option_explicit, prog.option_explicit);
        let saved_unit = std::mem::take(&mut self.unit_consts);
        let prior: std::collections::HashSet<Rc<str>> = self
            .globals
            .iter()
            .filter(|(_, s)| s.borrow().is_array())
            .map(|(k, _)| k.clone())
            .collect();
        let saved_prior = std::mem::replace(&mut self.unit_prior_arrays, prior);
        self.execute_depth += 1;
        self.hoist(&prog.body, !self.in_proc());
        let r = self.exec_block(&prog.body);
        self.execute_depth -= 1;
        self.unit_consts = saved_unit;
        self.unit_prior_arrays = saved_prior;
        self.option_explicit = saved_explicit;
        if let Some(f) = saved {
            self.frames = f;
        }
        match r {
            Ok(()) | Err(Flow::Halt) => Ok(()),
            Err(Flow::Error(e)) => Err(e),
            Err(_) => Ok(()),
        }
    }

    /// Evaluate an expression from source text (`Eval`).
    pub fn eval_source(&mut self, src: &str) -> VbResult<Value> {
        let e = crate::parser::parse_expression(src).map_err(syntax_to_vb)?;
        // `Eval` is its own compile unit, so it resolves names the way a
        // later unit would.
        self.execute_depth += 1;
        let v = self.eval_inner(&e).and_then(|v| self.deref_value(v));
        self.execute_depth -= 1;
        v
    }
}

/// Whether an expression is written as a literal in the source. VBScript's
/// string-versus-number comparison depends on it.
fn is_literal(e: &Expr) -> bool {
    matches!(
        e,
        Expr::Int(_)
            | Expr::Long(_)
            | Expr::Real(_)
            | Expr::Date(_)
            | Expr::Str(_)
            | Expr::Bool(_)
            | Expr::Empty
            | Expr::Null
    )
}

/// Turn a parse failure into the error a script sees from `Execute`.
fn syntax_to_vb(e: crate::error::SyntaxError) -> VbError {
    let mut err = VbError::new(
        e.code,
        if e.code == 1031 { "Invalid number" } else { "Syntax error" },
    );
    err.source = Rc::from("Microsoft VBScript compilation error");
    err
}

/// Whether an assignment target names a property rather than a variable or
/// an array element.
fn assigns_to_property(target: &Expr) -> bool {
    match target {
        Expr::Member { .. } | Expr::WithMember { .. } => true,
        Expr::Index { target: inner, .. } => {
            matches!(**inner, Expr::Member { .. } | Expr::WithMember { .. })
        }
        _ => false,
    }
}

/// Look through any parentheses wrapping an expression.
fn strip_parens(e: &Expr) -> &Expr {
    let mut cur = e;
    while let Expr::Paren(inner) = cur {
        cur = inner;
    }
    cur
}

/// Array elements passed by reference, each paired with the temporary slot
/// the callee wrote through, to be copied back once the call returns.
type Writebacks<'a> = Vec<(&'a Expr, Slot)>;

/// The root variable of an index chain, with one argument group per `(...)`.
type IndexChain<'a> = (&'a Rc<str>, Vec<&'a Vec<Arg>>);

/// Decompose `a(i)(j)...` into the root variable and its index groups.
fn index_chain(e: &Expr) -> Option<IndexChain<'_>> {
    let mut groups: Vec<&Vec<Arg>> = Vec::new();
    let mut cur = e;
    loop {
        match cur {
            Expr::Index { target, args } => {
                groups.push(args);
                cur = target;
            }
            Expr::Ident(name) => {
                groups.reverse();
                return Some((name, groups));
            }
            _ => return None,
        }
    }
}

/// Store `value` at `path` within nested arrays, copying on write at each
/// level so the outer array's element is updated in place.
fn set_nested(target: &mut Value, path: &[Vec<usize>], value: Value) -> VbResult<()> {
    let (first, rest) = path.split_first().expect("non-empty path");
    let rc = match target {
        Value::Array(rc) => rc,
        _ => return Err(err::type_mismatch()),
    };
    let arr = Rc::make_mut(rc);
    let off = arr.offset(first).ok_or_else(err::subscript)?;
    if rest.is_empty() {
        arr.data[off] = value;
        Ok(())
    } else {
        set_nested(&mut arr.data[off], rest, value)
    }
}

/// An array copied into a new binding is no longer the one a `Dim`
/// statement created, so it is passed by value from then on.
fn disown(v: Value) -> Value {
    match v {
        Value::Array(rc) if rc.owned => {
            let mut a = (*rc).clone();
            a.owned = false;
            Value::Array(Rc::new(a))
        }
        other => other,
    }
}

fn flow_to_err(f: Flow) -> VbError {
    match f {
        Flow::Error(e) => e,
        _ => err::invalid_call(),
    }
}
