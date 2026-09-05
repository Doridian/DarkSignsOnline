//! `Scripting.Dictionary`.

use std::cmp::Ordering;
use std::rc::Rc;

use crate::error::{err, VbError, VbResult};
use crate::value::{compare_str, Value};

/// Key comparison mode, matching the `CompareMode` property.
pub const BINARY_COMPARE: i32 = 0;
pub const TEXT_COMPARE: i32 = 1;

pub struct Dictionary {
    /// Insertion-ordered, since `Keys`/`Items` and `For Each` observe order.
    pub entries: Vec<(Value, Value)>,
    pub compare_mode: i32,
}

impl Default for Dictionary {
    fn default() -> Dictionary {
        Dictionary::new()
    }
}

impl Dictionary {
    pub fn new() -> Dictionary {
        Dictionary { entries: Vec::new(), compare_mode: BINARY_COMPARE }
    }

    fn key_eq(&self, a: &Value, b: &Value) -> bool {
        match (a, b) {
            (Value::Str(x), Value::Str(y)) => {
                compare_str(x, y, self.compare_mode == TEXT_COMPARE) == Ordering::Equal
            }
            (Value::Obj(Some(x)), Value::Obj(Some(y))) => x.same(y),
            (Value::Obj(None), Value::Obj(None)) => true,
            (Value::Empty, Value::Empty) => true,
            (Value::Null, Value::Null) => true,
            _ => {
                if a.is_object() || b.is_object() || a.is_array() || b.is_array() {
                    return false;
                }
                match (a.to_f64(), b.to_f64()) {
                    (Ok(x), Ok(y)) => x == y,
                    _ => false,
                }
            }
        }
    }

    pub fn find(&self, key: &Value) -> Option<usize> {
        self.entries.iter().position(|(k, _)| self.key_eq(k, key))
    }

    pub fn count(&self) -> i32 {
        self.entries.len() as i32
    }

    pub fn add(&mut self, key: Value, item: Value) -> VbResult<()> {
        if self.find(&key).is_some() {
            return Err(VbError::new(
                457,
                "This key is already associated with an element of this collection",
            ));
        }
        self.entries.push((key, item));
        Ok(())
    }

    /// Reading a missing key inserts it with an `Empty` value, as the real
    /// Dictionary does.
    pub fn item(&mut self, key: &Value) -> Value {
        match self.find(key) {
            Some(i) => self.entries[i].1.clone(),
            None => {
                self.entries.push((key.clone(), Value::Empty));
                Value::Empty
            }
        }
    }

    pub fn set_item(&mut self, key: Value, item: Value) {
        match self.find(&key) {
            Some(i) => self.entries[i].1 = item,
            None => self.entries.push((key, item)),
        }
    }

    pub fn set_key(&mut self, old: &Value, new: Value) -> VbResult<()> {
        match self.find(old) {
            Some(i) => {
                self.entries[i].0 = new;
                Ok(())
            }
            None => Err(err::invalid_call()),
        }
    }

    pub fn exists(&self, key: &Value) -> bool {
        self.find(key).is_some()
    }

    pub fn remove(&mut self, key: &Value) -> VbResult<()> {
        match self.find(key) {
            Some(i) => {
                self.entries.remove(i);
                Ok(())
            }
            None => Err(err::invalid_call()),
        }
    }

    pub fn remove_all(&mut self) {
        self.entries.clear();
    }

    pub fn keys(&self) -> Vec<Value> {
        self.entries.iter().map(|(k, _)| k.clone()).collect()
    }

    pub fn items(&self) -> Vec<Value> {
        self.entries.iter().map(|(_, v)| v.clone()).collect()
    }
}

pub fn array_of(values: Vec<Value>) -> Value {
    Value::Array(Rc::new(crate::value::VbArray::from_values(values)))
}
