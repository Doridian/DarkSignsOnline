//! Abstract syntax tree for VBScript.

use std::rc::Rc;

#[derive(Clone, Debug, PartialEq, Eq, Copy)]
pub enum BinOp {
    Add, Sub, Mul, Div, IntDiv, Mod, Pow, Concat,
    Eq, Ne, Lt, Gt, Le, Ge, Is, IsNot,
    And, Or, Xor, Eqv, Imp,
}

#[derive(Clone, Debug, PartialEq, Eq, Copy)]
pub enum UnOp {
    Neg,
    Plus,
    Not,
}

#[derive(Clone, Debug)]
pub enum Expr {
    Empty,
    Null,
    Nothing,
    Bool(bool),
    Int(i32),
    Long(i32),
    Real(f64),
    Str(Rc<str>),
    Date(f64),

    /// A bare name, or a call/index — VBScript cannot tell these apart until
    /// runtime, so `a(1)` is one node and the interpreter decides whether it
    /// indexes an array or invokes a function.
    Ident(Rc<str>),
    /// `target(args)` — call, array index, or default-property access.
    Index { target: Box<Expr>, args: Vec<Arg> },
    /// `target.name`
    Member { target: Box<Expr>, name: Rc<str> },
    /// `.name` inside a `With` block.
    WithMember { name: Rc<str> },
    /// `.name(args)` inside a `With` block.
    Me,

    New(Rc<str>),
    /// A parenthesised expression. The parentheses survive parsing because
    /// they force an argument to be passed by value.
    Paren(Box<Expr>),
    Unary(UnOp, Box<Expr>),
    Binary(BinOp, Box<Expr>, Box<Expr>),
}

/// An argument in a call. `Missing` covers the elided slots in `f(1, , 3)`.
#[derive(Clone, Debug)]
pub enum Arg {
    Val(Expr),
    Missing,
}

#[derive(Clone, Debug, Copy, PartialEq, Eq)]
pub enum Visibility {
    Public,
    Private,
}

#[derive(Clone, Debug)]
pub struct Param {
    pub name: Rc<str>,
    pub by_val: bool,
    pub optional: bool,
}

#[derive(Clone, Debug)]
pub struct FuncDef {
    pub name: Rc<str>,
    pub params: Vec<Param>,
    pub body: Rc<Vec<Stmt>>,
    pub is_function: bool,
    pub visibility: Visibility,
    pub is_default: bool,
    /// Line the definition starts on, for diagnostics.
    pub line: u32,
}

#[derive(Clone, Debug, Copy, PartialEq, Eq, Hash)]
pub enum PropKind {
    Get,
    Let,
    Set,
}

#[derive(Clone, Debug)]
pub struct PropDef {
    pub name: Rc<str>,
    pub kind: PropKind,
    pub params: Vec<Param>,
    pub body: Rc<Vec<Stmt>>,
    pub visibility: Visibility,
    pub is_default: bool,
    pub line: u32,
}

#[derive(Clone, Debug)]
pub struct ClassDef {
    pub name: Rc<str>,
    /// Declared fields, with their fixed-array bounds if any.
    pub fields: Vec<(Rc<str>, Visibility, Vec<usize>)>,
    pub methods: Vec<Rc<FuncDef>>,
    pub props: Vec<Rc<PropDef>>,
    pub consts: Vec<(Rc<str>, Expr)>,
    /// Name of the member marked `Default`, if any.
    pub default_member: Option<Rc<str>>,
}

/// One `Dim` entry: a name plus optional fixed dimensions.
#[derive(Clone, Debug)]
pub struct DimVar {
    pub name: Rc<str>,
    pub dims: Vec<Expr>,
    pub is_array: bool,
}

#[derive(Clone, Debug)]
pub enum ExitKind {
    Do,
    For,
    Function,
    Sub,
    Property,
}

#[derive(Clone, Debug)]
pub enum DoCond {
    /// `Do While c ... Loop`
    PreWhile(Expr),
    /// `Do Until c ... Loop`
    PreUntil(Expr),
    /// `Do ... Loop While c`
    PostWhile(Expr),
    /// `Do ... Loop Until c`
    PostUntil(Expr),
    /// `Do ... Loop`
    None,
}

#[derive(Clone, Debug)]
pub struct CaseClause {
    /// Empty means `Case Else`.
    pub values: Vec<Expr>,
    pub body: Vec<Stmt>,
}

#[derive(Clone, Debug)]
pub enum StmtKind {
    /// Evaluate an expression for effect — a sub call, typically.
    Call(Expr),
    Assign { target: Expr, value: Expr },
    /// `Set x = expr`; binds the object reference rather than its default value.
    SetAssign { target: Expr, value: Expr },

    Dim(Vec<DimVar>),
    ReDim { preserve: bool, vars: Vec<DimVar> },
    Const(Vec<(Rc<str>, Expr)>),
    Erase(Vec<Expr>),

    If {
        branches: Vec<(Expr, Vec<Stmt>)>,
        else_body: Option<Vec<Stmt>>,
    },
    While { cond: Expr, body: Vec<Stmt> },
    Do { cond: DoCond, body: Vec<Stmt> },
    For {
        var: Expr,
        from: Expr,
        to: Expr,
        step: Option<Expr>,
        body: Vec<Stmt>,
    },
    ForEach { var: Expr, seq: Expr, body: Vec<Stmt> },
    Select { subject: Expr, cases: Vec<CaseClause> },
    With { subject: Expr, body: Vec<Stmt> },

    Exit(ExitKind),

    /// `On Error Resume Next` / `On Error GoTo 0`
    OnErrorResumeNext,
    OnErrorGoto0,

    Function(Rc<FuncDef>),
    Property(Rc<PropDef>),
    Class(Rc<ClassDef>),

    /// `Option Explicit` and any other `Option` — unknown ones are recorded
    /// and ignored, since a preprocessor handles them.
    Option(Rc<str>),

    Stop,
    /// A no-op placeholder, e.g. a bare `Randomize` handled elsewhere.
    Empty,
}

/// A statement together with the source line it began on, which the
/// interpreter reports in runtime errors.
#[derive(Clone, Debug)]
pub struct Stmt {
    pub line: u32,
    pub kind: StmtKind,
}

impl Stmt {
    pub fn new(line: u32, kind: StmtKind) -> Stmt {
        Stmt { line, kind }
    }
}

#[derive(Clone, Debug)]
pub struct Program {
    pub body: Vec<Stmt>,
    pub option_explicit: bool,
}
