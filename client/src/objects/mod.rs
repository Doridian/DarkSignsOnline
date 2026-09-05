//! Object values: script classes, the built-in COM-alikes, and an escape
//! hatch for host-supplied objects.

pub mod dictionary;
pub mod regexp;

use std::cell::RefCell;
use std::collections::HashMap;
use std::rc::Rc;

use crate::ast::{ClassDef, FuncDef};
use crate::error::VbResult;
use crate::interp::Interp;
use crate::value::{Slot, Value};

use dictionary::Dictionary;
use regexp::{MatchObj, RegExpObj};

/// An instance of a script-defined `Class`.
pub struct ClassObj {
    pub def: Rc<ClassDef>,
    pub fields: RefCell<HashMap<Rc<str>, Slot>>,
    /// Set once `Class_Terminate` has run, so it cannot run twice.
    pub terminated: RefCell<bool>,
}

/// A host object. Implementors decide how member access behaves.
pub trait NativeObject {
    fn type_name(&self) -> &str;

    /// Read a property or call a method.
    fn get(&self, it: &mut Interp, name: &str, args: &[Value]) -> VbResult<Value>;

    /// Assign to a property. `is_set` distinguishes `Set o.p = x`.
    fn set(&self, _it: &mut Interp, name: &str, _args: &[Value], _v: Value, _is_set: bool)
        -> VbResult<()> {
        Err(crate::error::err::member_not_found(name))
    }

    /// Invoke the default member, i.e. `o(args)` or a bare `o`.
    fn call_default(&self, _it: &mut Interp, _args: &[Value]) -> VbResult<Value> {
        Err(crate::error::err::object_no_value())
    }

    /// Items yielded by `For Each`.
    fn enumerate(&self, _it: &mut Interp) -> VbResult<Option<Vec<Value>>> {
        Ok(None)
    }
}

#[derive(Clone)]
pub enum ObjKind {
    Class(Rc<ClassObj>),
    Dictionary(Rc<RefCell<Dictionary>>),
    RegExp(Rc<RefCell<RegExpObj>>),
    /// The result of `RegExp.Execute`.
    Matches(Rc<Vec<Rc<MatchObj>>>),
    Match(Rc<MatchObj>),
    SubMatches(Rc<Vec<Value>>),
    /// The global `Err` object. It has no per-instance state.
    Err,
    /// A procedure reference from `GetRef`.
    FuncRef(Rc<FuncDef>),
    /// A reference to a built-in function by name, also from `GetRef`.
    BuiltinRef(Rc<str>),
    Native(Rc<dyn NativeObject>),
}

impl ObjKind {
    pub fn type_name(&self) -> String {
        match self {
            ObjKind::Class(c) => c.def.name.to_string(),
            ObjKind::Dictionary(_) => "Dictionary".into(),
            ObjKind::RegExp(_) => "RegExp".into(),
            ObjKind::Matches(_) => "IMatchCollection2".into(),
            ObjKind::Match(_) => "IMatch2".into(),
            ObjKind::SubMatches(_) => "ISubMatches".into(),
            ObjKind::Err => "ErrObject".into(),
            ObjKind::FuncRef(_) | ObjKind::BuiltinRef(_) => "VBScriptTypeInfo".into(),
            ObjKind::Native(n) => n.type_name().to_string(),
        }
    }

    /// Reference identity, as tested by `Is`.
    pub fn same(&self, other: &ObjKind) -> bool {
        match (self, other) {
            (ObjKind::Class(a), ObjKind::Class(b)) => Rc::ptr_eq(a, b),
            (ObjKind::Dictionary(a), ObjKind::Dictionary(b)) => Rc::ptr_eq(a, b),
            (ObjKind::RegExp(a), ObjKind::RegExp(b)) => Rc::ptr_eq(a, b),
            (ObjKind::Matches(a), ObjKind::Matches(b)) => Rc::ptr_eq(a, b),
            (ObjKind::Match(a), ObjKind::Match(b)) => Rc::ptr_eq(a, b),
            (ObjKind::SubMatches(a), ObjKind::SubMatches(b)) => Rc::ptr_eq(a, b),
            (ObjKind::Err, ObjKind::Err) => true,
            (ObjKind::FuncRef(a), ObjKind::FuncRef(b)) => Rc::ptr_eq(a, b),
            (ObjKind::BuiltinRef(a), ObjKind::BuiltinRef(b)) => a == b,
            (ObjKind::Native(a), ObjKind::Native(b)) => Rc::ptr_eq(a, b),
            _ => false,
        }
    }
}

impl ClassObj {
    pub fn new(def: Rc<ClassDef>) -> Rc<ClassObj> {
        let mut fields = HashMap::new();
        for (name, _vis, bounds) in &def.fields {
            let init = if bounds.is_empty() {
                Value::Empty
            } else {
                // A field declared with bounds belongs to the instance, so
                // passing it hands over the array itself.
                let mut a = crate::value::VbArray::new(bounds.clone(), true);
                a.owned = true;
                Value::Array(Rc::new(a))
            };
            fields.insert(name.clone(), crate::value::slot(init));
        }
        Rc::new(ClassObj {
            def,
            fields: RefCell::new(fields),
            terminated: RefCell::new(false),
        })
    }
}
