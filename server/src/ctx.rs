//! One request's worth of state, shaped like the PHP script it replaces: an
//! output buffer that `echo` appends to, a status and headers that `header()`
//! sets, `die` as an early return, and a database connection taken on first
//! use.

use std::sync::Arc;

use mysql_async::prelude::Queryable;
use mysql_async::{Conn, Row, Value};

use crate::App;
use crate::php::Zv;
use crate::request::Request;

/// Why a script stopped before the end.
#[derive(Debug)]
pub enum Halt {
    /// `die`/`exit`: the response is whatever has been written so far.
    Exit,
    /// An uncaught exception. PHP turns it into a 500, keeping the output.
    Fatal(String),
}

impl From<mysql_async::Error> for Halt {
    fn from(e: mysql_async::Error) -> Halt {
        Halt::Fatal(format!("database: {e}"))
    }
}

pub type Res<T = ()> = Result<T, Halt>;

pub const TEXT_HTML: &str = "text/html; charset=UTF-8";
pub const TEXT_PLAIN: &str = "text/plain;charset=UTF-8";

/// A row, by column name.
pub struct Rec {
    columns: Arc<[mysql_async::Column]>,
    values: Vec<Zv>,
}

impl Rec {
    fn from_row(row: Row) -> Rec {
        let columns = row.columns();
        let values = row.unwrap().into_iter().map(zv_from_value).collect();
        Rec { columns, values }
    }

    /// `$row['name']`; NULL for a column the query did not select, as PHP
    /// gives for an undefined index.
    pub fn get(&self, name: &str) -> Zv {
        self.columns
            .iter()
            .position(|c| c.name_str() == name)
            .map_or(Zv::Null, |i| self.values[i].clone())
    }

    pub fn idx(&self, i: usize) -> Zv {
        self.values.get(i).cloned().unwrap_or(Zv::Null)
    }
}

/// mysqlnd's prepared statements hand back integer columns as integers and
/// everything else as strings.
fn zv_from_value(v: Value) -> Zv {
    match v {
        Value::NULL => Zv::Null,
        Value::Int(i) => Zv::Int(i),
        Value::UInt(u) => Zv::Int(u as i64),
        Value::Bytes(b) => Zv::Str(b),
        other => Zv::Str(other.as_sql(true).into_bytes()),
    }
}

/// A `bind_param` type `s`.
pub fn s(z: &Zv) -> Value {
    match z {
        Zv::Null => Value::NULL,
        other => Value::Bytes(other.to_bytes()),
    }
}

/// A `bind_param` type `i`. mysqlnd converts a string with `(int)`, unless
/// it would not fit, in which case the string goes to the server as is.
pub fn i(z: &Zv) -> Value {
    match z {
        Zv::Null => Value::NULL,
        Zv::Int(n) => Value::Int(*n),
        Zv::Str(b) => {
            let d = z.to_float();
            if d >= i64::MAX as f64 || d < i64::MIN as f64 {
                Value::Bytes(b.clone())
            } else {
                Value::Int(z.to_int())
            }
        }
    }
}

pub struct Ctx {
    pub app: Arc<App>,
    pub req: Request,
    pub out: Vec<u8>,
    pub status: u16,
    pub content_type: &'static str,
    pub headers: Vec<(&'static str, String)>,
    pub ver: i64,
    /// The authenticated account, once `authenticate` has found one.
    pub user: Option<Rec>,
    conn: Option<Conn>,
    in_transaction: bool,
}

impl Ctx {
    pub fn new(app: Arc<App>, req: Request) -> Ctx {
        let ver = req.protocol_version();
        Ctx {
            app,
            req,
            out: Vec::new(),
            status: 200,
            content_type: TEXT_HTML,
            headers: Vec::new(),
            ver,
            user: None,
            conn: None,
            in_transaction: false,
        }
    }

    pub fn echo(&mut self, s: impl AsRef<[u8]>) {
        self.out.extend_from_slice(s.as_ref());
    }

    /// `die($s)`.
    pub fn die<T>(&mut self, s: impl AsRef<[u8]>) -> Res<T> {
        self.echo(s);
        Err(Halt::Exit)
    }

    /// `header($name: $value)`, replacing an earlier one of the same name.
    pub fn header(&mut self, name: &'static str, value: impl Into<String>) {
        self.headers.retain(|(n, _)| !n.eq_ignore_ascii_case(name));
        self.headers.push((name, value.into()));
    }

    /// `die_error()`: the status only changes for protocol 2 and later,
    /// since a version 1 client reads the status code from the body.
    pub fn die_error<T>(&mut self, s: impl AsRef<[u8]>, code: u16) -> Res<T> {
        if self.ver > 1 {
            self.status = code;
        }
        self.die(s)
    }

    /// `print_returnwith()`: the legacy four-digit status prefix, for
    /// clients at or below `max_version` (a negative `max_version` means
    /// every client gets it).
    pub fn print_returnwith(&mut self, def: &str, max_version: i64) {
        if self.ver > max_version && max_version >= 0 {
            return;
        }
        let n = self.req.get("returnwith").to_int();
        if n == 0 {
            self.echo(def);
        } else {
            self.echo(n.to_string());
        }
    }

    pub fn user_field(&self, name: &str) -> Zv {
        self.user.as_ref().map_or(Zv::Null, |u| u.get(name))
    }

    pub fn user_id(&self) -> Zv {
        self.user_field("id")
    }

    async fn conn(&mut self) -> Res<&mut Conn> {
        if self.conn.is_none() {
            self.conn = Some(self.app.pool.get_conn().await?);
        }
        Ok(self.conn.as_mut().expect("just connected"))
    }

    /// A prepared statement's rows.
    pub async fn query(&mut self, sql: &str, params: Vec<Value>) -> Res<Vec<Rec>> {
        let rows: Vec<Row> = self.conn().await?.exec(sql, params).await?;
        Ok(rows.into_iter().map(Rec::from_row).collect())
    }

    pub async fn query_one(&mut self, sql: &str, params: Vec<Value>) -> Res<Option<Rec>> {
        Ok(self.query(sql, params).await?.into_iter().next())
    }

    /// A prepared statement run for its effect: affected rows and insert id.
    pub async fn exec(&mut self, sql: &str, params: Vec<Value>) -> Res<(u64, u64)> {
        let conn = self.conn().await?;
        conn.exec_drop(sql, params).await?;
        Ok((conn.affected_rows(), conn.last_insert_id().unwrap_or(0)))
    }

    pub async fn begin(&mut self) -> Res {
        self.conn().await?.query_drop("START TRANSACTION").await?;
        self.in_transaction = true;
        Ok(())
    }

    pub async fn commit(&mut self) -> Res {
        self.conn().await?.query_drop("COMMIT").await?;
        self.in_transaction = false;
        Ok(())
    }

    pub async fn rollback(&mut self) -> Res {
        self.conn().await?.query_drop("ROLLBACK").await?;
        self.in_transaction = false;
        Ok(())
    }

    /// Hand the connection back. A transaction still open here is one the
    /// script never committed, which PHP's closing the connection would have
    /// rolled back.
    pub async fn finish(&mut self) {
        if let Some(mut conn) = self.conn.take()
            && self.in_transaction
            && let Err(e) = conn.query_drop("ROLLBACK").await
        {
            eprintln!("rollback failed: {e}");
            let _ = conn.disconnect().await;
        }
    }
}
