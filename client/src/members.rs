//! Property and method dispatch for every object kind.

use std::rc::Rc;

use crate::ast::PropKind;
use crate::error::{err, VbError, VbResult};
use crate::interp::{ArgVal, Interp};
use crate::objects::dictionary::{array_of, Dictionary, BINARY_COMPARE, TEXT_COMPARE};
use crate::objects::{ClassObj, ObjKind};
use crate::value::Value;

fn eq_ci(a: &str, b: &str) -> bool {
    a.eq_ignore_ascii_case(b)
}

fn need_args(args: &[Value], n: usize) -> VbResult<()> {
    if args.len() < n {
        Err(err::wrong_arg_count())
    } else {
        Ok(())
    }
}

/// Read a member. `empty_parens` records that the source wrote `o.p()`
/// rather than a bare `o.p`, which VBScript rejects for a plain field.
pub fn get(
    it: &mut Interp,
    o: &ObjKind,
    name: &str,
    args: &[Value],
    empty_parens: bool,
) -> VbResult<Value> {
    match o {
        ObjKind::Class(c) => class_get(it, c, name, args, empty_parens),
        ObjKind::Dictionary(d) => dict_get(it, d, name, args),
        ObjKind::RegExp(r) => regexp_get(it, r, name, args),
        ObjKind::Matches(m) => match_coll_get(m, name, args),
        ObjKind::Match(m) => match_get(m, name, args),
        ObjKind::SubMatches(s) => sub_matches_get(s, name, args),
        ObjKind::Err => err_get(it, name, args),
        ObjKind::FuncRef(_) | ObjKind::BuiltinRef(_) => Err(err::member_not_found(name)),
        ObjKind::Native(n) => {
            let n = n.clone();
            n.get(it, name, args)
        }
    }
}

pub fn set(
    it: &mut Interp,
    o: &ObjKind,
    name: &str,
    args: &[Value],
    value: Value,
    is_set: bool,
) -> VbResult<()> {
    match o {
        ObjKind::Class(c) => class_set(it, c, name, args, value, is_set),
        ObjKind::Dictionary(d) => dict_set(d, name, args, value),
        ObjKind::RegExp(r) => regexp_set(r, name, value),
        ObjKind::Err => err_set(it, name, value),
        ObjKind::Native(n) => {
            let n = n.clone();
            n.set(it, name, args, value, is_set)
        }
        _ => Err(err::member_not_found(name)),
    }
}

pub fn call_default(it: &mut Interp, o: &ObjKind, args: &[Value]) -> VbResult<Value> {
    match o {
        ObjKind::Class(c) => {
            let dm = c.def.default_member.clone();
            match dm {
                Some(name) => class_get(it, c, &name, args, false),
                None => Err(err::object_no_value()),
            }
        }
        ObjKind::Dictionary(d) => {
            // `d(key)` is `d.Item(key)`.
            need_args(args, 1)?;
            let v = d.borrow_mut().item(&args[0]);
            Ok(v)
        }
        ObjKind::Match(m) => Ok(Value::Str(m.value.clone())),
        ObjKind::Matches(m) => match_coll_get(m, "item", args),
        ObjKind::SubMatches(s) => sub_matches_get(s, "item", args),
        ObjKind::FuncRef(f) => {
            let f = f.clone();
            let a = args.iter().map(|v| ArgVal::Val(v.clone())).collect();
            it.call_func(&f, a, None)
        }
        ObjKind::BuiltinRef(n) => {
            let n = n.clone();
            let mut a: Vec<ArgVal> = args.iter().map(|v| ArgVal::Val(v.clone())).collect();
            match crate::builtins::call(it, &n, &mut a)? {
                Some(v) => Ok(v),
                None => Err(err::sub_not_defined(&n)),
            }
        }
        ObjKind::Native(n) => {
            let n = n.clone();
            n.call_default(it, args)
        }
        // `x = Err` reads Err.Number, its default member.
        ObjKind::Err => Ok(Value::I4(it.err.number)),
        ObjKind::RegExp(_) => Err(err::object_no_value()),
    }
}

pub fn set_default(
    it: &mut Interp,
    o: &ObjKind,
    idx: &[Value],
    value: Value,
    is_set: bool,
) -> VbResult<()> {
    match o {
        ObjKind::Dictionary(d) => {
            need_args(idx, 1)?;
            d.borrow_mut().set_item(idx[0].clone(), value);
            Ok(())
        }
        ObjKind::Class(c) => {
            let dm = c.def.default_member.clone().ok_or_else(err::object_no_value)?;
            class_set(it, c, &dm, idx, value, is_set)
        }
        ObjKind::Native(n) => {
            let n = n.clone();
            n.set(it, "", idx, value, is_set)
        }
        _ => Err(err::not_supported()),
    }
}

// ---- script classes ------------------------------------------------------

fn class_get(
    it: &mut Interp,
    c: &Rc<ClassObj>,
    name: &str,
    args: &[Value],
    empty_parens: bool,
) -> VbResult<Value> {
    // A property Get wins over a field of the same name; VBScript does not
    // allow both, so the order only matters for robustness.
    if let Some(p) = c
        .def
        .props
        .iter()
        .find(|p| p.kind == PropKind::Get && eq_ci(&p.name, name))
    {
        if p.visibility == crate::ast::Visibility::Private {
            return Err(err::member_not_found(name));
        }
        let p = p.clone();
        let a = args.iter().map(|v| ArgVal::Val(v.clone())).collect();
        return it.call_prop_get(&p, a, Some(ObjKind::Class(c.clone())));
    }
    if let Some(m) = c.def.methods.iter().find(|m| eq_ci(&m.name, name)) {
        if m.visibility == crate::ast::Visibility::Private {
            return Err(err::member_not_found(name));
        }
        let m = m.clone();
        let a = args.iter().map(|v| ArgVal::Val(v.clone())).collect();
        return it.call_func(&m, a, Some(ObjKind::Class(c.clone())));
    }
    if let Some((_, e)) = c.def.consts.iter().find(|(n, _)| eq_ci(n, name)) {
        let e = e.clone();
        return it.eval(&e).map_err(|f| match f {
            crate::error::Flow::Error(e) => e,
            _ => err::invalid_call(),
        });
    }
    let field = c.fields.borrow().get(&name.to_ascii_lowercase() as &str).cloned()
        .or_else(|| {
            let fields = c.fields.borrow();
            fields.iter().find(|(k, _)| eq_ci(k, name)).map(|(_, v)| v.clone())
        });
    if let Some(s) = field {
        // Only public fields are reachable from outside, but a method body
        // reads them through the frame's `me`, not through here.
        let vis = c
            .def
            .fields
            .iter()
            .find(|(n, _, _)| eq_ci(n, name))
            .map(|(_, v, _)| *v);
        if vis == Some(crate::ast::Visibility::Private) && !it_is_inside(it, c) {
            return Err(err::member_not_found(name));
        }
        let cur = s.borrow().clone();
        return if args.is_empty() {
            // A field is data, not a procedure, so `o.field()` is not a
            // legal call even though `o.field` reads fine.
            if empty_parens {
                Err(err::invalid_call())
            } else {
                Ok(cur)
            }
        } else {
            match &cur {
                Value::Array(_) => it.index_array(&cur, args),
                Value::Obj(Some(o)) => call_default(it, &o.clone(), args),
                // Subscripting a scalar field is not supported at all.
                _ => Err(err::member_not_found(name)),
            }
        };
    }
    Err(err::member_not_found(name))
}

/// True when the currently executing procedure belongs to this instance.
fn it_is_inside(_it: &Interp, _c: &Rc<ClassObj>) -> bool {
    // Member access from inside a method resolves through the frame's `me`
    // before reaching here, so anything arriving here is an external access.
    false
}

fn class_set(
    it: &mut Interp,
    c: &Rc<ClassObj>,
    name: &str,
    args: &[Value],
    value: Value,
    is_set: bool,
) -> VbResult<()> {
    let want = if is_set { PropKind::Set } else { PropKind::Let };
    if let Some(p) = c.def.props.iter().find(|p| p.kind == want && eq_ci(&p.name, name)) {
        if p.visibility == crate::ast::Visibility::Private {
            return Err(err::member_not_found(name));
        }
        let p = p.clone();
        let mut a: Vec<ArgVal> = args.iter().map(|v| ArgVal::Val(v.clone())).collect();
        a.push(ArgVal::Val(value));
        return it
            .call_prop_set_public(&p, a, Some(ObjKind::Class(c.clone())));
    }
    let field = {
        let fields = c.fields.borrow();
        fields.iter().find(|(k, _)| eq_ci(k, name)).map(|(_, v)| v.clone())
    };
    if let Some(s) = field {
        // Only public fields are reachable through a qualified name.
        if c.def
            .fields
            .iter()
            .find(|(n, _, _)| eq_ci(n, name))
            .map(|(_, v, _)| *v)
            == Some(crate::ast::Visibility::Private)
        {
            return Err(err::member_not_found(name));
        }
        if args.is_empty() {
            *s.borrow_mut() = value;
        } else {
            // Only an array field accepts subscripts at all.
            if !s.borrow().is_array() {
                return Err(err::member_not_found(name));
            }
            let subs: VbResult<Vec<usize>> = args
                .iter()
                .map(|v| {
                    let n = v.to_f64()?;
                    if n < 0.0 {
                        return Err(err::subscript());
                    }
                    Ok(n as usize)
                })
                .collect();
            let subs = subs?;
            let mut cur = s.borrow_mut();
            if let Value::Array(rc) = &mut *cur {
                let arr = Rc::make_mut(rc);
                let off = arr.offset(&subs).ok_or_else(err::subscript)?;
                arr.data[off] = value;
            } else {
                // Subscripting a scalar field is not supported at all.
                return Err(err::member_not_found(name));
            }
        }
        return Ok(());
    }
    // A property that exists but has no setter of the required kind, or a
    // method, cannot be assigned to.
    if c.def.props.iter().any(|p| eq_ci(&p.name, name))
        || c.def.methods.iter().any(|m| eq_ci(&m.name, name))
    {
        return Err(err::member_not_found(name));
    }
    Err(err::member_not_found(name))
}

// ---- Dictionary ----------------------------------------------------------

fn dict_get(
    it: &mut Interp,
    d: &Rc<std::cell::RefCell<Dictionary>>,
    name: &str,
    args: &[Value],
) -> VbResult<Value> {
    let lname = name.to_ascii_lowercase();
    match lname.as_str() {
        "count" => Ok(Value::I4(d.borrow().count())),
        "item" => {
            need_args(args, 1)?;
            let v = d.borrow_mut().item(&args[0]);
            Ok(v)
        }
        "add" => {
            need_args(args, 2)?;
            d.borrow_mut().add(args[0].clone(), args[1].clone())?;
            Ok(Value::Empty)
        }
        "exists" => {
            need_args(args, 1)?;
            let e = d.borrow().exists(&args[0]);
            Ok(Value::Bool(e))
        }
        "remove" => {
            need_args(args, 1)?;
            d.borrow_mut().remove(&args[0])?;
            Ok(Value::Empty)
        }
        "removeall" => {
            d.borrow_mut().remove_all();
            Ok(Value::Empty)
        }
        "keys" | "items" => {
            let vals = if lname == "keys" { d.borrow().keys() } else { d.borrow().items() };
            if args.is_empty() {
                Ok(array_of(vals))
            } else {
                let i = args[0].to_f64()? as i64;
                if i < 0 || i as usize >= vals.len() {
                    return Err(err::subscript());
                }
                Ok(vals[i as usize].clone())
            }
        }
        "comparemode" => Ok(Value::I4(d.borrow().compare_mode)),
        "key" => {
            // Reading `.Key(k)` is not meaningful; only assignment is.
            need_args(args, 1)?;
            let _ = it;
            Err(err::member_not_found(name))
        }
        _ => Err(err::member_not_found(name)),
    }
}

fn dict_set(
    d: &Rc<std::cell::RefCell<Dictionary>>,
    name: &str,
    args: &[Value],
    value: Value,
) -> VbResult<()> {
    match name.to_ascii_lowercase().as_str() {
        "item" => {
            need_args(args, 1)?;
            d.borrow_mut().set_item(args[0].clone(), value);
            Ok(())
        }
        "key" => {
            need_args(args, 1)?;
            d.borrow_mut().set_key(&args[0], value)
        }
        "comparemode" => {
            let m = value.to_f64()? as i32;
            if m != BINARY_COMPARE && m != TEXT_COMPARE {
                return Err(err::invalid_call());
            }
            d.borrow_mut().compare_mode = m;
            Ok(())
        }
        _ => Err(err::member_not_found(name)),
    }
}

// ---- RegExp --------------------------------------------------------------

fn regexp_get(
    _it: &mut Interp,
    r: &Rc<std::cell::RefCell<crate::objects::regexp::RegExpObj>>,
    name: &str,
    args: &[Value],
) -> VbResult<Value> {
    match name.to_ascii_lowercase().as_str() {
        "pattern" => Ok(Value::Str(r.borrow().pattern.clone())),
        "global" => Ok(Value::Bool(r.borrow().global)),
        "ignorecase" => Ok(Value::Bool(r.borrow().ignore_case)),
        "multiline" => Ok(Value::Bool(r.borrow().multiline)),
        "test" => {
            need_args(args, 1)?;
            let s = args[0].to_vb_string()?;
            let b = r.borrow_mut().test(&s)?;
            Ok(Value::Bool(b))
        }
        "execute" => {
            need_args(args, 1)?;
            let s = args[0].to_vb_string()?;
            let m = r.borrow_mut().execute(&s)?;
            Ok(Value::Obj(Some(ObjKind::Matches(Rc::new(m)))))
        }
        "replace" => {
            need_args(args, 2)?;
            let s = args[0].to_vb_string()?;
            // The replacement goes through a numeric conversion first, so a
            // Boolean renders as -1/0 rather than True/False.
            let rep = match &args[1] {
                Value::Bool(b) => Rc::from(if *b { "-1" } else { "0" }),
                other => other.to_vb_string()?,
            };
            let out = r.borrow_mut().replace(&s, &rep)?;
            Ok(Value::str(out))
        }
        _ => Err(err::member_not_found(name)),
    }
}

fn regexp_set(
    r: &Rc<std::cell::RefCell<crate::objects::regexp::RegExpObj>>,
    name: &str,
    value: Value,
) -> VbResult<()> {
    match name.to_ascii_lowercase().as_str() {
        "pattern" => {
            r.borrow_mut().pattern = value.to_vb_string()?;
            Ok(())
        }
        "global" => {
            r.borrow_mut().global = value.to_bool()?;
            Ok(())
        }
        "ignorecase" => {
            r.borrow_mut().ignore_case = value.to_bool()?;
            Ok(())
        }
        "multiline" => {
            r.borrow_mut().multiline = value.to_bool()?;
            Ok(())
        }
        _ => Err(err::member_not_found(name)),
    }
}

fn match_coll_get(
    m: &Rc<Vec<Rc<crate::objects::regexp::MatchObj>>>,
    name: &str,
    args: &[Value],
) -> VbResult<Value> {
    match name.to_ascii_lowercase().as_str() {
        "count" => Ok(Value::I4(m.len() as i32)),
        "item" => {
            need_args(args, 1)?;
            let i = args[0].to_f64()? as i64;
            if i < 0 || i as usize >= m.len() {
                return Err(err::subscript());
            }
            Ok(Value::Obj(Some(ObjKind::Match(m[i as usize].clone()))))
        }
        _ => Err(err::member_not_found(name)),
    }
}

fn match_get(
    m: &Rc<crate::objects::regexp::MatchObj>,
    name: &str,
    args: &[Value],
) -> VbResult<Value> {
    match name.to_ascii_lowercase().as_str() {
        "value" => Ok(Value::Str(m.value.clone())),
        "firstindex" => Ok(Value::I4(m.first_index)),
        "length" => Ok(Value::I4(m.length)),
        "submatches" => {
            // `m.SubMatches(0)` reads through to the item in one expression.
            if args.is_empty() {
                Ok(Value::Obj(Some(ObjKind::SubMatches(m.submatches.clone()))))
            } else {
                sub_matches_get(&m.submatches, "item", args)
            }
        }
        _ => Err(err::member_not_found(name)),
    }
}

fn sub_matches_get(s: &Rc<Vec<Value>>, name: &str, args: &[Value]) -> VbResult<Value> {
    match name.to_ascii_lowercase().as_str() {
        "count" => Ok(Value::I4(s.len() as i32)),
        "item" => {
            need_args(args, 1)?;
            let i = args[0].to_f64()? as i64;
            if i < 0 || i as usize >= s.len() {
                return Err(err::subscript());
            }
            Ok(s[i as usize].clone())
        }
        _ => Err(err::member_not_found(name)),
    }
}

// ---- Err -----------------------------------------------------------------

fn err_get(it: &mut Interp, name: &str, args: &[Value]) -> VbResult<Value> {
    match name.to_ascii_lowercase().as_str() {
        "number" => Ok(Value::I4(it.err.number)),
        "description" => Ok(Value::Str(it.err.description.clone())),
        "source" => Ok(Value::Str(it.err.source.clone())),
        "helpfile" => Ok(Value::Str(it.err.helpfile.clone())),
        "helpcontext" => Ok(Value::I4(it.err.helpcontext)),
        "clear" => {
            it.err = crate::interp::ErrState {
                number: 0,
                source: Rc::from(""),
                description: Rc::from(""),
                helpfile: Rc::from(""),
                helpcontext: 0,
            };
            Ok(Value::Empty)
        }
        "raise" => {
            need_args(args, 1)?;
            let number = to_i32(&args[0])?;
            // A positive code must fit in 16 bits; negatives are HRESULTs.
            if number == 0 || number > 0xFFFF {
                return Err(err::invalid_call());
            }
            let opt_str = |i: usize| -> VbResult<Option<Rc<str>>> {
                match args.get(i) {
                    None => Ok(None),
                    Some(Value::ErrCode(_)) => Ok(None),
                    Some(v) => Ok(Some(v.to_vb_string()?)),
                }
            };
            // An omitted argument keeps whatever `Err` already holds, and
            // falls back to the standard text only once `Err` is clear.
            let keep = |given: Option<Rc<str>>, current: &Rc<str>| -> Option<Rc<str>> {
                given.or_else(|| {
                    if current.is_empty() {
                        None
                    } else {
                        Some(current.clone())
                    }
                })
            };
            let source = keep(opt_str(1)?, &it.err.source);
            let description = keep(opt_str(2)?, &it.err.description);
            let helpfile = keep(opt_str(3)?, &it.err.helpfile);
            let helpcontext = match args.get(4) {
                None | Some(Value::ErrCode(_)) => {
                    if it.err.helpcontext != 0 {
                        Some(it.err.helpcontext)
                    } else {
                        None
                    }
                }
                Some(v) => Some(to_i32(v)?),
            };
            Err(it.raise(number, source, description, helpfile, helpcontext))
        }
        _ => Err(err::member_not_found(name)),
    }
}

fn err_set(it: &mut Interp, name: &str, value: Value) -> VbResult<()> {
    match name.to_ascii_lowercase().as_str() {
        "number" => {
            it.err.number = crate::error::hresult_to_number(to_i32(&value)?);
            Ok(())
        }
        "description" => {
            it.err.description = value.to_vb_string()?;
            Ok(())
        }
        "source" => {
            it.err.source = value.to_vb_string()?;
            Ok(())
        }
        "helpfile" => {
            it.err.helpfile = value.to_vb_string()?;
            Ok(())
        }
        "helpcontext" => {
            it.err.helpcontext = to_i32(&value)?;
            Ok(())
        }
        _ => Err(err::member_not_found(name)),
    }
}

fn to_i32(v: &Value) -> VbResult<i32> {
    let f = v.to_f64()?;
    if f < i32::MIN as f64 || f > i32::MAX as f64 {
        return Err(VbError::code(6));
    }
    Ok(crate::value::round_half_even(f) as i32)
}
