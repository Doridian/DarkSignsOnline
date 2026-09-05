//! Recursive-descent parser producing the AST in `crate::ast`.

use std::rc::Rc;

use crate::ast::*;
use crate::error::SyntaxError;
use crate::lexer::{Kw, Lexer, Tok, Token};

type PResult<T> = Result<T, SyntaxError>;

pub struct Parser {
    toks: Vec<Token>,
    pos: usize,
    /// Collected `Option` statements, including ones we do not understand.
    options: Vec<Rc<str>>,
}

/// Parse a complete script.
pub fn parse(src: &str) -> PResult<Program> {
    let toks = Lexer::new(src)
        .tokenize()
        .map_err(|e| SyntaxError { msg: e.msg, line: e.line, code: e.code })?;
    let mut p = Parser { toks, pos: 0, options: Vec::new() };
    let body = p.parse_block(&[])?;
    p.expect_eof()?;
    let option_explicit = p.options.iter().any(|o| o.eq_ignore_ascii_case("explicit"));
    Ok(Program { body, option_explicit })
}

/// Terminators that end a nested block. A block stops *before* consuming them.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
enum Term {
    EndIf,
    ElseIf,
    Else,
    EndSub,
    EndFunction,
    EndProperty,
    EndClass,
    EndSelect,
    EndWith,
    Case,
    Next,
    Loop,
    Wend,
}

impl Parser {
    // ---- token helpers ---------------------------------------------------

    fn peek(&self) -> &Tok {
        &self.toks[self.pos.min(self.toks.len() - 1)].tok
    }
    fn peek_at(&self, n: usize) -> &Tok {
        &self.toks[(self.pos + n).min(self.toks.len() - 1)].tok
    }
    fn line(&self) -> u32 {
        self.toks[self.pos.min(self.toks.len() - 1)].line
    }
    /// Whether whitespace precedes the current token.
    fn spaced(&self) -> bool {
        self.toks[self.pos.min(self.toks.len() - 1)].spaced
    }
    fn bump(&mut self) -> Tok {
        let t = self.toks[self.pos.min(self.toks.len() - 1)].tok.clone();
        if self.pos < self.toks.len() {
            self.pos += 1;
        }
        t
    }
    fn err<T>(&self, msg: impl Into<String>) -> PResult<T> {
        self.err_code(msg, 1002)
    }

    fn err_code<T>(&self, msg: impl Into<String>, code: i32) -> PResult<T> {
        Err(SyntaxError { msg: msg.into(), line: self.line(), code })
    }
    fn eat(&mut self, t: &Tok) -> bool {
        if self.peek() == t {
            self.pos += 1;
            true
        } else {
            false
        }
    }
    fn eat_kw(&mut self, k: Kw) -> bool {
        self.eat(&Tok::Keyword(k))
    }
    fn is_kw(&self, k: Kw) -> bool {
        *self.peek() == Tok::Keyword(k)
    }
    fn expect(&mut self, t: Tok) -> PResult<()> {
        if self.eat(&t) {
            Ok(())
        } else {
            self.err(format!("expected `{}`, found `{}`", t, self.peek()))
        }
    }
    fn expect_kw(&mut self, k: Kw) -> PResult<()> {
        self.expect(Tok::Keyword(k))
    }
    fn expect_eof(&mut self) -> PResult<()> {
        self.skip_seps();
        if matches!(self.peek(), Tok::Eof) {
            Ok(())
        } else {
            self.err(format!("unexpected `{}`", self.peek()))
        }
    }

    fn at_sep(&self) -> bool {
        matches!(self.peek(), Tok::Newline | Tok::Colon)
    }
    fn skip_seps(&mut self) {
        while self.at_sep() {
            self.pos += 1;
        }
    }
    /// An identifier, accepting keywords that are legal as member names
    /// (`x.Count`, `obj.Class`) where the grammar is unambiguous.
    fn ident_name(&mut self) -> PResult<Rc<str>> {
        match self.peek().clone() {
            Tok::Ident(s) => {
                self.pos += 1;
                Ok(Rc::from(s.as_str()))
            }
            Tok::Keyword(k) => {
                self.pos += 1;
                Ok(Rc::from(k.as_str()))
            }
            t => self.err_code(format!("expected an identifier, found `{t}`"), 1010),
        }
    }

    /// An identifier keeping its original spelling, for names that are
    /// visible to scripts (`TypeName` reports a class's declared case).
    fn decl_ident(&mut self) -> PResult<Rc<str>> {
        let raw = self.toks[self.pos.min(self.toks.len() - 1)].text.clone();
        let lower = self.plain_ident()?;
        Ok(raw.map(|r| Rc::from(r.as_str())).unwrap_or(lower))
    }

    fn plain_ident(&mut self) -> PResult<Rc<str>> {
        match self.peek().clone() {
            Tok::Ident(s) => {
                self.pos += 1;
                Ok(Rc::from(s.as_str()))
            }
            // A few keywords double as ordinary names.
            Tok::Keyword(k @ (Kw::Property | Kw::Error | Kw::Step | Kw::Default | Kw::Explicit)) => {
                self.pos += 1;
                Ok(Rc::from(k.as_str()))
            }
            t => self.err_code(format!("expected an identifier, found `{t}`"), 1010),
        }
    }

    // ---- blocks ----------------------------------------------------------

    /// Does the current position start one of `terms`? Returns which.
    fn at_term(&self, terms: &[Term]) -> Option<Term> {
        let found = match self.peek() {
            Tok::Eof => return None,
            Tok::Keyword(Kw::ElseIf) => Term::ElseIf,
            Tok::Keyword(Kw::Else) => Term::Else,
            Tok::Keyword(Kw::Case) => Term::Case,
            Tok::Keyword(Kw::Next) => Term::Next,
            Tok::Keyword(Kw::Loop) => Term::Loop,
            Tok::Keyword(Kw::Wend) => Term::Wend,
            Tok::Keyword(Kw::End) => match self.peek_at(1) {
                Tok::Keyword(Kw::If) => Term::EndIf,
                Tok::Keyword(Kw::Sub) => Term::EndSub,
                Tok::Keyword(Kw::Function) => Term::EndFunction,
                Tok::Keyword(Kw::Property) => Term::EndProperty,
                Tok::Keyword(Kw::Class) => Term::EndClass,
                Tok::Keyword(Kw::Select) => Term::EndSelect,
                Tok::Keyword(Kw::With) => Term::EndWith,
                // A bare `End` terminates the script.
                _ => return None,
            },
            _ => return None,
        };
        if terms.contains(&found) {
            Some(found)
        } else {
            None
        }
    }

    fn parse_block(&mut self, terms: &[Term]) -> PResult<Vec<Stmt>> {
        let mut out = Vec::new();
        loop {
            self.skip_seps();
            if matches!(self.peek(), Tok::Eof) || self.at_term(terms).is_some() {
                return Ok(out);
            }
            // A bare `End` with nothing after it stops execution.
            if self.is_kw(Kw::End) && !matches!(self.peek_at(1), Tok::Keyword(_)) {
                if terms.is_empty() {
                    let line = self.line();
                    self.pos += 1;
                    out.push(Stmt::new(line, StmtKind::Exit(ExitKind::Sub)));
                    continue;
                }
                return Ok(out);
            }
            let before = self.pos;
            let line = self.line();
            let s = self.parse_statement()?;
            out.push(Stmt::new(line, s));
            if self.pos == before {
                return self.err(format!("unexpected `{}`", self.peek()));
            }
            // A statement must be followed by a separator (or a terminator).
            if !self.at_sep()
                && !matches!(self.peek(), Tok::Eof)
                && self.at_term(terms).is_none()
                && !self.is_kw(Kw::End)
            {
                return self
                    .err_code(format!("expected end of statement, found `{}`", self.peek()), 1025);
            }
        }
    }

    /// As [`Parser::end_of`], but naming the line the block opened on, which
    /// is far more useful than pointing at end-of-file.
    fn end_of_from(&mut self, k: Kw, opened: u32) -> PResult<()> {
        if self.is_kw(Kw::End) && *self.peek_at(1) == Tok::Keyword(k) {
            self.pos += 2;
            return Ok(());
        }
        self.err(format!(
            "expected `End {}` for the block opened on line {opened}, found `{}`",
            k.as_str(),
            self.peek()
        ))
    }

    // ---- statements ------------------------------------------------------

    fn parse_statement(&mut self) -> PResult<StmtKind> {
        match self.peek().clone() {
            Tok::Keyword(Kw::Option) => self.parse_option(),
            Tok::Keyword(Kw::Dim) => {
                self.pos += 1;
                Ok(StmtKind::Dim(self.parse_dim_list()?))
            }
            Tok::Keyword(Kw::ReDim) => self.parse_redim(),
            Tok::Keyword(Kw::Const) => {
                self.pos += 1;
                Ok(StmtKind::Const(self.parse_const_list()?))
            }
            Tok::Keyword(Kw::Erase) => {
                self.pos += 1;
                let mut v = vec![self.parse_expr()?];
                while self.eat(&Tok::Comma) {
                    v.push(self.parse_expr()?);
                }
                Ok(StmtKind::Erase(v))
            }
            Tok::Keyword(Kw::If) => self.parse_if(),
            Tok::Keyword(Kw::While) => self.parse_while(),
            Tok::Keyword(Kw::Do) => self.parse_do(),
            Tok::Keyword(Kw::For) => self.parse_for(),
            Tok::Keyword(Kw::Select) => self.parse_select(),
            Tok::Keyword(Kw::With) => self.parse_with(),
            Tok::Keyword(Kw::Exit) => self.parse_exit(),
            Tok::Keyword(Kw::On) => self.parse_on_error(),
            Tok::Keyword(Kw::Set) => {
                self.pos += 1;
                let target = self.parse_postfix_target()?;
                self.expect(Tok::Eq)?;
                let value = self.parse_expr()?;
                Ok(StmtKind::SetAssign { target, value })
            }
            Tok::Keyword(Kw::Let) => {
                self.pos += 1;
                let target = self.parse_postfix_target()?;
                self.expect(Tok::Eq)?;
                let value = self.parse_expr()?;
                Ok(StmtKind::Assign { target, value })
            }
            Tok::Keyword(Kw::Call) => {
                self.pos += 1;
                let e = self.parse_postfix_target()?;
                Ok(StmtKind::Call(e))
            }
            Tok::Keyword(Kw::Stop) => {
                self.pos += 1;
                Ok(StmtKind::Stop)
            }
            Tok::Keyword(Kw::Class) => self.parse_class(),
            Tok::Keyword(Kw::Sub) | Tok::Keyword(Kw::Function) => {
                let d = self.parse_func(Visibility::Public, false)?;
                Ok(StmtKind::Function(Rc::new(d)))
            }
            // `Property` only introduces a definition when `Get`, `Let` or
            // `Set` follows; otherwise it is being used as a variable name.
            Tok::Keyword(Kw::Property)
                if matches!(
                    self.peek_at(1),
                    Tok::Keyword(Kw::Get) | Tok::Keyword(Kw::Let) | Tok::Keyword(Kw::Set)
                ) =>
            {
                let d = self.parse_property(Visibility::Public, false)?;
                Ok(StmtKind::Property(Rc::new(d)))
            }
            Tok::Keyword(Kw::Public) | Tok::Keyword(Kw::Private) => self.parse_visible_decl(),
            _ => self.parse_call_or_assign(),
        }
    }

    fn parse_option(&mut self) -> PResult<StmtKind> {
        self.pos += 1;
        // Consume the rest of the line verbatim; unknown options are recorded
        // and left for a later preprocessing pass.
        let mut parts: Vec<String> = Vec::new();
        while !self.at_sep() && !matches!(self.peek(), Tok::Eof) {
            parts.push(self.bump().to_string());
        }
        let text: Rc<str> = Rc::from(parts.join(" ").as_str());
        self.options.push(text.clone());
        Ok(StmtKind::Option(text))
    }

    fn parse_visible_decl(&mut self) -> PResult<StmtKind> {
        let vis = if self.eat_kw(Kw::Public) {
            Visibility::Public
        } else {
            self.expect_kw(Kw::Private)?;
            Visibility::Private
        };
        let is_default = self.eat_kw(Kw::Default);
        match self.peek() {
            Tok::Keyword(Kw::Sub) | Tok::Keyword(Kw::Function) => {
                let d = self.parse_func(vis, is_default)?;
                Ok(StmtKind::Function(Rc::new(d)))
            }
            Tok::Keyword(Kw::Property) => {
                let d = self.parse_property(vis, is_default)?;
                Ok(StmtKind::Property(Rc::new(d)))
            }
            Tok::Keyword(Kw::Const) => {
                self.pos += 1;
                Ok(StmtKind::Const(self.parse_const_list()?))
            }
            // `Public x, y` declares variables, like `Dim`.
            _ => Ok(StmtKind::Dim(self.parse_dim_list()?)),
        }
    }

    fn parse_dim_list(&mut self) -> PResult<Vec<DimVar>> {
        let mut out = Vec::new();
        loop {
            let name = self.plain_ident()?;
            let mut dims = Vec::new();
            let mut is_array = false;
            if self.eat(&Tok::LParen) {
                is_array = true;
                if !self.eat(&Tok::RParen) {
                    loop {
                        dims.push(self.parse_expr()?);
                        if !self.eat(&Tok::Comma) {
                            break;
                        }
                    }
                    self.expect(Tok::RParen)?;
                }
            }
            out.push(DimVar { name, dims, is_array });
            if !self.eat(&Tok::Comma) {
                break;
            }
        }
        Ok(out)
    }

    fn parse_redim(&mut self) -> PResult<StmtKind> {
        self.expect_kw(Kw::ReDim)?;
        let preserve = self.eat_kw(Kw::Preserve);
        let vars = self.parse_dim_list()?;
        Ok(StmtKind::ReDim { preserve, vars })
    }

    fn parse_const_list(&mut self) -> PResult<Vec<(Rc<str>, Expr)>> {
        let mut out = Vec::new();
        loop {
            let name = self.plain_ident()?;
            self.expect(Tok::Eq)?;
            let v = self.parse_expr()?;
            out.push((name, v));
            if !self.eat(&Tok::Comma) {
                break;
            }
        }
        Ok(out)
    }

    fn parse_if(&mut self) -> PResult<StmtKind> {
        let opened = self.line();
        self.expect_kw(Kw::If)?;
        let cond = self.parse_expr()?;
        self.expect_kw(Kw::Then)?;

        // A statement on the same line as `Then` makes this the single-line
        // form, which ends at the newline rather than at `End If`.
        if !matches!(self.peek(), Tok::Newline | Tok::Eof) {
            return self.parse_inline_if(cond);
        }

        let mut branches = Vec::new();
        let terms = [Term::EndIf, Term::ElseIf, Term::Else];
        let body = self.parse_block(&terms)?;
        branches.push((cond, body));
        let mut else_body = None;
        loop {
            match self.at_term(&terms) {
                Some(Term::ElseIf) => {
                    self.pos += 1;
                    let c = self.parse_expr()?;
                    self.expect_kw(Kw::Then)?;
                    let b = self.parse_block(&terms)?;
                    branches.push((c, b));
                }
                Some(Term::Else) => {
                    self.pos += 1;
                    let b = self.parse_block(&[Term::EndIf])?;
                    else_body = Some(b);
                    break;
                }
                _ => break,
            }
        }
        self.end_of_from(Kw::If, opened)?;
        Ok(StmtKind::If { branches, else_body })
    }

    /// `If c Then a : b Else d : e` — everything up to the end of the line.
    fn parse_inline_if(&mut self, cond: Expr) -> PResult<StmtKind> {
        let then_body = self.parse_inline_body()?;
        let mut branches = vec![(cond, then_body)];
        let mut else_body = None;

        loop {
            if self.eat_kw(Kw::ElseIf) {
                let c = self.parse_expr()?;
                self.expect_kw(Kw::Then)?;
                branches.push((c, self.parse_inline_body()?));
                continue;
            }
            if self.eat_kw(Kw::Else) {
                // A single-line `If` always ends at the newline, so a
                // trailing `Else` simply has an empty body.
                else_body = Some(self.parse_inline_body()?);
            }
            break;
        }
        // `End If` is optional on the single-line form.
        if self.is_kw(Kw::End) && matches!(self.peek_at(1), Tok::Keyword(Kw::If)) {
            self.pos += 2;
        }
        Ok(StmtKind::If { branches, else_body })
    }

    /// Statements separated by `:` up to the end of the physical line.
    fn parse_inline_body(&mut self) -> PResult<Vec<Stmt>> {
        let mut out = Vec::new();
        loop {
            while self.eat(&Tok::Colon) {}
            if matches!(self.peek(), Tok::Newline | Tok::Eof)
                || self.is_kw(Kw::Else)
                || self.is_kw(Kw::ElseIf)
                || (self.is_kw(Kw::End) && matches!(self.peek_at(1), Tok::Keyword(Kw::If)))
            {
                return Ok(out);
            }
            let line = self.line();
            let st = self.parse_statement()?;
            out.push(Stmt::new(line, st));
            if !matches!(self.peek(), Tok::Colon) {
                return Ok(out);
            }
        }
    }

    fn parse_while(&mut self) -> PResult<StmtKind> {
        self.expect_kw(Kw::While)?;
        let cond = self.parse_expr()?;
        let body = self.parse_block(&[Term::Wend])?;
        self.expect_kw(Kw::Wend)?;
        Ok(StmtKind::While { cond, body })
    }

    fn parse_do(&mut self) -> PResult<StmtKind> {
        self.expect_kw(Kw::Do)?;
        let pre = if self.eat_kw(Kw::While) {
            Some(DoCond::PreWhile(self.parse_expr()?))
        } else if self.eat_kw(Kw::Until) {
            Some(DoCond::PreUntil(self.parse_expr()?))
        } else {
            None
        };
        let body = self.parse_block(&[Term::Loop])?;
        self.expect_kw(Kw::Loop)?;
        let cond = match pre {
            Some(c) => c,
            None => {
                if self.eat_kw(Kw::While) {
                    DoCond::PostWhile(self.parse_expr()?)
                } else if self.eat_kw(Kw::Until) {
                    DoCond::PostUntil(self.parse_expr()?)
                } else {
                    DoCond::None
                }
            }
        };
        Ok(StmtKind::Do { cond, body })
    }

    fn parse_for(&mut self) -> PResult<StmtKind> {
        self.expect_kw(Kw::For)?;
        if self.eat_kw(Kw::Each) {
            let var = self.parse_loop_var()?;
            self.expect_kw(Kw::In)?;
            let seq = self.parse_expr()?;
            let body = self.parse_block(&[Term::Next])?;
            self.expect_kw(Kw::Next)?;
            // `Next x` names the loop variable again; it is redundant.
            if matches!(self.peek(), Tok::Ident(_)) {
                self.pos += 1;
            }
            return Ok(StmtKind::ForEach { var, seq, body });
        }
        let var = self.parse_loop_var()?;
        self.expect(Tok::Eq)?;
        let from = self.parse_expr()?;
        self.expect_kw(Kw::To)?;
        let to = self.parse_expr()?;
        let step = if self.eat_kw(Kw::Step) {
            Some(self.parse_expr()?)
        } else {
            None
        };
        let body = self.parse_block(&[Term::Next])?;
        self.expect_kw(Kw::Next)?;
        while matches!(self.peek(), Tok::Ident(_)) {
            self.pos += 1;
            if !self.eat(&Tok::Comma) {
                break;
            }
        }
        Ok(StmtKind::For { var, from, to, step, body })
    }

    /// The counter of a `For` loop, which must name something assignable.
    fn parse_loop_var(&mut self) -> PResult<Expr> {
        let e = self.parse_postfix_target()?;
        match e {
            Expr::Ident(_) | Expr::Member { .. } | Expr::Index { .. } | Expr::WithMember { .. } => {
                Ok(e)
            }
            _ => self.err_code("expected an identifier as the loop variable", 1010),
        }
    }

    fn parse_select(&mut self) -> PResult<StmtKind> {
        let opened = self.line();
        self.expect_kw(Kw::Select)?;
        self.eat_kw(Kw::Case);
        let subject = self.parse_expr()?;
        let mut cases: Vec<CaseClause> = Vec::new();
        // Anything between `Select Case x` and the first `Case` is skipped.
        loop {
            self.skip_seps();
            if self.at_term(&[Term::EndSelect]).is_some() || matches!(self.peek(), Tok::Eof) {
                break;
            }
            if !self.eat_kw(Kw::Case) {
                return self.err(format!("expected `Case`, found `{}`", self.peek()));
            }
            let values = if self.eat_kw(Kw::Else) {
                Vec::new()
            } else {
                let mut v = vec![self.parse_expr()?];
                while self.eat(&Tok::Comma) {
                    v.push(self.parse_expr()?);
                }
                v
            };
            let body = self.parse_block(&[Term::Case, Term::EndSelect])?;
            cases.push(CaseClause { values, body });
        }
        self.end_of_from(Kw::Select, opened)?;
        Ok(StmtKind::Select { subject, cases })
    }

    fn parse_with(&mut self) -> PResult<StmtKind> {
        let opened = self.line();
        self.expect_kw(Kw::With)?;
        let subject = self.parse_expr()?;
        let body = self.parse_block(&[Term::EndWith])?;
        self.end_of_from(Kw::With, opened)?;
        Ok(StmtKind::With { subject, body })
    }

    fn parse_exit(&mut self) -> PResult<StmtKind> {
        self.expect_kw(Kw::Exit)?;
        let k = match self.bump() {
            Tok::Keyword(Kw::Do) => ExitKind::Do,
            Tok::Keyword(Kw::For) => ExitKind::For,
            Tok::Keyword(Kw::Function) => ExitKind::Function,
            Tok::Keyword(Kw::Sub) => ExitKind::Sub,
            Tok::Keyword(Kw::Property) => ExitKind::Property,
            t => return self.err(format!("`Exit` cannot be followed by `{t}`")),
        };
        Ok(StmtKind::Exit(k))
    }

    fn parse_on_error(&mut self) -> PResult<StmtKind> {
        self.expect_kw(Kw::On)?;
        self.expect_kw(Kw::Error)?;
        if self.eat_kw(Kw::Resume) {
            self.expect_kw(Kw::Next)?;
            return Ok(StmtKind::OnErrorResumeNext);
        }
        self.expect_kw(Kw::GoTo)?;
        match self.peek() {
            Tok::Int(0) | Tok::Long(0) => {
                self.pos += 1;
                Ok(StmtKind::OnErrorGoto0)
            }
            t => self.err(format!("`On Error GoTo` supports only 0, found `{t}`")),
        }
    }

    fn parse_params(&mut self) -> PResult<Vec<Param>> {
        let mut out = Vec::new();
        if !self.eat(&Tok::LParen) {
            return Ok(out);
        }
        if self.eat(&Tok::RParen) {
            return Ok(out);
        }
        loop {
            let optional = self.eat_kw(Kw::Optional);
            // Parameters are ByRef unless marked otherwise.
            let by_val = if self.eat_kw(Kw::ByVal) {
                true
            } else {
                self.eat_kw(Kw::ByRef);
                false
            };
            let name = self.plain_ident()?;
            // An array parameter may be written `a()`.
            if self.eat(&Tok::LParen) {
                self.expect(Tok::RParen)?;
            }
            out.push(Param { name, by_val, optional });
            if !self.eat(&Tok::Comma) {
                break;
            }
        }
        self.expect(Tok::RParen)?;
        Ok(out)
    }

    fn parse_func(&mut self, visibility: Visibility, is_default: bool) -> PResult<FuncDef> {
        let line = self.line();
        let is_function = match self.bump() {
            Tok::Keyword(Kw::Function) => true,
            Tok::Keyword(Kw::Sub) => false,
            t => return self.err(format!("expected `Sub` or `Function`, found `{t}`")),
        };
        let name = self.plain_ident()?;
        let params = self.parse_params()?;
        let term = if is_function { Term::EndFunction } else { Term::EndSub };
        let body = self.parse_block(&[term])?;
        self.end_of_from(if is_function { Kw::Function } else { Kw::Sub }, line)?;
        Ok(FuncDef {
            name,
            params,
            body: Rc::new(body),
            is_function,
            visibility,
            is_default,
            line,
        })
    }

    fn parse_property(&mut self, visibility: Visibility, is_default: bool) -> PResult<PropDef> {
        let line = self.line();
        self.expect_kw(Kw::Property)?;
        let kind = match self.bump() {
            Tok::Keyword(Kw::Get) => PropKind::Get,
            Tok::Keyword(Kw::Let) => PropKind::Let,
            Tok::Keyword(Kw::Set) => PropKind::Set,
            t => return self.err(format!("expected `Get`, `Let` or `Set`, found `{t}`")),
        };
        let name = self.plain_ident()?;
        let params = self.parse_params()?;
        let body = self.parse_block(&[Term::EndProperty])?;
        self.end_of_from(Kw::Property, line)?;
        Ok(PropDef {
            name,
            kind,
            params,
            body: Rc::new(body),
            visibility,
            is_default,
            line,
        })
    }

    fn parse_class(&mut self) -> PResult<StmtKind> {
        let opened = self.line();
        self.expect_kw(Kw::Class)?;
        let name = self.decl_ident()?;
        let mut def = ClassDef {
            name,
            fields: Vec::new(),
            methods: Vec::new(),
            props: Vec::new(),
            consts: Vec::new(),
            default_member: None,
        };
        loop {
            self.skip_seps();
            if self.at_term(&[Term::EndClass]).is_some() || matches!(self.peek(), Tok::Eof) {
                break;
            }
            let vis = if self.eat_kw(Kw::Public) {
                Visibility::Public
            } else if self.eat_kw(Kw::Private) {
                Visibility::Private
            } else {
                Visibility::Public
            };
            let is_default = self.eat_kw(Kw::Default);
            match self.peek() {
                Tok::Keyword(Kw::Sub) | Tok::Keyword(Kw::Function) => {
                    let f = self.parse_func(vis, is_default)?;
                    if is_default {
                        def.default_member = Some(f.name.clone());
                    }
                    def.methods.push(Rc::new(f));
                }
                Tok::Keyword(Kw::Property) => {
                    let p = self.parse_property(vis, is_default)?;
                    if is_default {
                        def.default_member = Some(p.name.clone());
                    }
                    def.props.push(Rc::new(p));
                }
                Tok::Keyword(Kw::Const) => {
                    self.pos += 1;
                    def.consts.extend(self.parse_const_list()?);
                }
                Tok::Keyword(Kw::Dim) => {
                    self.pos += 1;
                    for v in self.parse_dim_list()? {
                        let bounds = v.dims.iter().map(|e| const_usize(e).unwrap_or(0)).collect();
                        def.fields.push((v.name, vis, bounds));
                    }
                }
                _ => {
                    // A field list: `Public x, y(3)`.
                    for v in self.parse_dim_list()? {
                        let bounds = v
                            .dims
                            .iter()
                            .map(|e| const_usize(e).unwrap_or(0))
                            .collect();
                        def.fields.push((v.name, vis, bounds));
                    }
                }
            }
        }
        self.end_of_from(Kw::Class, opened)?;
        Ok(StmtKind::Class(Rc::new(def)))
    }

    /// A bare statement: either `target = value` or a sub call.
    ///
    /// `Foo(1) * 8, 7` is a call to `Foo` whose first argument is `(1) * 8`,
    /// while `Foo(1) = 2` assigns to element 1 of `Foo`. The two are only
    /// distinguishable by what follows the parentheses, so the chain is
    /// parsed in full and then trimmed back if an operator turns up.
    fn parse_call_or_assign(&mut self) -> PResult<StmtKind> {
        let start = self.pos;
        let mut groups = Vec::new();
        let primary = self.parse_primary()?;
        let full = self.parse_call_chain(primary, &mut groups, usize::MAX)?;
        // `Foo (x)` — a space before the parentheses — passes one expression
        // by value rather than opening an argument list.
        let spaced_group = groups
            .last()
            .map(|&i| self.toks[i].spaced)
            .unwrap_or(false);

        let complete = matches!(self.peek(), Tok::Eq)
            || self.at_sep()
            || matches!(self.peek(), Tok::Eof)
            || self.at_term(ALL_TERMS).is_some();

        let target = if complete || groups.is_empty() {
            full
        } else {
            // Give the last parenthesised group back to the argument list.
            let cut = *groups.last().unwrap();
            self.pos = start;
            let primary = self.parse_primary()?;
            let mut ignored = Vec::new();
            self.parse_call_chain(primary, &mut ignored, cut)?
        };

        if self.eat(&Tok::Eq) {
            let value = self.parse_expr()?;
            return Ok(StmtKind::Assign { target, value });
        }

        // A sub called as a statement passes a single parenthesised
        // argument by value, whether or not a space precedes the parens.
        let _ = spaced_group;
        if complete && !groups.is_empty() {
            if let Expr::Index { target: callee, args } = target {
                if args.len() == 1 {
                    if let [Arg::Val(one)] = &args[..] {
                        return Ok(StmtKind::Call(Expr::Index {
                            target: callee,
                            args: vec![Arg::Val(Expr::Paren(Box::new(one.clone())))],
                        }));
                    }
                }
                return Ok(StmtKind::Call(Expr::Index { target: callee, args }));
            }
            return Ok(StmtKind::Call(target));
        }

        // Not an assignment, so it is a call. Any tokens still on this line
        // are a parenthesis-free argument list.
        if !self.at_sep() && !matches!(self.peek(), Tok::Eof) && self.at_term(ALL_TERMS).is_none()
        {
            let mut args = Vec::new();
            loop {
                if matches!(self.peek(), Tok::Comma) {
                    args.push(Arg::Missing);
                } else {
                    args.push(Arg::Val(self.parse_expr()?));
                }
                if !self.eat(&Tok::Comma) {
                    break;
                }
            }
            if !self.at_sep()
                && !matches!(self.peek(), Tok::Eof)
                && self.at_term(ALL_TERMS).is_none()
            {
                return self.err_code(
                    format!("expected end of statement, found `{}`", self.peek()),
                    1025,
                );
            }
            return Ok(StmtKind::Call(Expr::Index {
                target: Box::new(target),
                args,
            }));
        }

        if self.pos == start {
            return self.err(format!("unexpected `{}`", self.peek()));
        }
        Ok(StmtKind::Call(target))
    }

    /// Postfix chain for a statement's callee, stopping before token index
    /// `limit` and recording where each `(` group began.
    ///
    /// A `.` preceded by whitespace is left alone: `obj.member` continues the
    /// chain, but `Sub .member` starts an argument, and only the space tells
    /// them apart.
    fn parse_call_chain(
        &mut self,
        mut e: Expr,
        groups: &mut Vec<usize>,
        limit: usize,
    ) -> PResult<Expr> {
        loop {
            if self.pos >= limit {
                return Ok(e);
            }
            match self.peek() {
                Tok::Dot if !self.spaced() => {
                    self.pos += 1;
                    let name = self.ident_name()?;
                    e = Expr::Member { target: Box::new(e), name };
                }
                Tok::LParen => {
                    groups.push(self.pos);
                    self.pos += 1;
                    let args = self.parse_arg_list()?;
                    e = Expr::Index { target: Box::new(e), args };
                }
                _ => return Ok(e),
            }
        }
    }

    // ---- expressions -----------------------------------------------------

    /// The left-hand side of an assignment, or the callee of a bare call.
    /// Same shape as a primary expression with postfix operators.
    fn parse_postfix_target(&mut self) -> PResult<Expr> {
        let e = self.parse_primary()?;
        self.parse_postfix(e)
    }

    fn parse_postfix(&mut self, mut e: Expr) -> PResult<Expr> {
        loop {
            match self.peek() {
                Tok::Dot => {
                    self.pos += 1;
                    let name = self.ident_name()?;
                    e = Expr::Member { target: Box::new(e), name };
                }
                Tok::LParen => {
                    self.pos += 1;
                    let args = self.parse_arg_list()?;
                    e = Expr::Index { target: Box::new(e), args };
                }
                _ => return Ok(e),
            }
        }
    }

    fn parse_arg_list(&mut self) -> PResult<Vec<Arg>> {
        let mut args = Vec::new();
        if self.eat(&Tok::RParen) {
            return Ok(args);
        }
        loop {
            if matches!(self.peek(), Tok::Comma | Tok::RParen) {
                args.push(Arg::Missing);
            } else {
                args.push(Arg::Val(self.parse_expr()?));
            }
            if !self.eat(&Tok::Comma) {
                break;
            }
        }
        self.expect(Tok::RParen)?;
        Ok(args)
    }

    pub fn parse_expr(&mut self) -> PResult<Expr> {
        self.parse_imp()
    }

    fn parse_imp(&mut self) -> PResult<Expr> {
        let mut l = self.parse_eqv()?;
        while self.eat_kw(Kw::Imp) {
            let r = self.parse_eqv()?;
            l = Expr::Binary(BinOp::Imp, Box::new(l), Box::new(r));
        }
        Ok(l)
    }

    fn parse_eqv(&mut self) -> PResult<Expr> {
        let mut l = self.parse_xor()?;
        while self.eat_kw(Kw::Eqv) {
            let r = self.parse_xor()?;
            l = Expr::Binary(BinOp::Eqv, Box::new(l), Box::new(r));
        }
        Ok(l)
    }

    fn parse_xor(&mut self) -> PResult<Expr> {
        let mut l = self.parse_or()?;
        while self.eat_kw(Kw::Xor) {
            let r = self.parse_or()?;
            l = Expr::Binary(BinOp::Xor, Box::new(l), Box::new(r));
        }
        Ok(l)
    }

    fn parse_or(&mut self) -> PResult<Expr> {
        let mut l = self.parse_and()?;
        while self.eat_kw(Kw::Or) {
            let r = self.parse_and()?;
            l = Expr::Binary(BinOp::Or, Box::new(l), Box::new(r));
        }
        Ok(l)
    }

    fn parse_and(&mut self) -> PResult<Expr> {
        let mut l = self.parse_not()?;
        while self.eat_kw(Kw::And) {
            let r = self.parse_not()?;
            l = Expr::Binary(BinOp::And, Box::new(l), Box::new(r));
        }
        Ok(l)
    }

    fn parse_not(&mut self) -> PResult<Expr> {
        if self.eat_kw(Kw::Not) {
            let e = self.parse_not()?;
            return Ok(Expr::Unary(UnOp::Not, Box::new(e)));
        }
        self.parse_compare()
    }

    fn parse_compare(&mut self) -> PResult<Expr> {
        let mut l = self.parse_concat()?;
        loop {
            let op = match self.peek() {
                Tok::Eq => BinOp::Eq,
                Tok::Ne => BinOp::Ne,
                Tok::Lt => BinOp::Lt,
                Tok::Gt => BinOp::Gt,
                Tok::Le => BinOp::Le,
                Tok::Ge => BinOp::Ge,
                Tok::Keyword(Kw::Is) => BinOp::Is,
                _ => return Ok(l),
            };
            self.pos += 1;
            // `Is Not Nothing` is idiomatic enough to deserve direct support.
            let op = if op == BinOp::Is && self.eat_kw(Kw::Not) {
                BinOp::IsNot
            } else {
                op
            };
            let r = self.parse_concat()?;
            l = Expr::Binary(op, Box::new(l), Box::new(r));
        }
    }

    fn parse_concat(&mut self) -> PResult<Expr> {
        let mut l = self.parse_additive()?;
        while self.eat(&Tok::Amp) {
            let r = self.parse_additive()?;
            l = Expr::Binary(BinOp::Concat, Box::new(l), Box::new(r));
        }
        Ok(l)
    }

    fn parse_additive(&mut self) -> PResult<Expr> {
        let mut l = self.parse_mod()?;
        loop {
            let op = match self.peek() {
                Tok::Plus => BinOp::Add,
                Tok::Minus => BinOp::Sub,
                _ => return Ok(l),
            };
            self.pos += 1;
            let r = self.parse_mod()?;
            l = Expr::Binary(op, Box::new(l), Box::new(r));
        }
    }

    fn parse_mod(&mut self) -> PResult<Expr> {
        let mut l = self.parse_intdiv()?;
        while self.eat_kw(Kw::Mod) {
            let r = self.parse_intdiv()?;
            l = Expr::Binary(BinOp::Mod, Box::new(l), Box::new(r));
        }
        Ok(l)
    }

    fn parse_intdiv(&mut self) -> PResult<Expr> {
        let mut l = self.parse_muldiv()?;
        while self.eat(&Tok::Backslash) {
            let r = self.parse_muldiv()?;
            l = Expr::Binary(BinOp::IntDiv, Box::new(l), Box::new(r));
        }
        Ok(l)
    }

    fn parse_muldiv(&mut self) -> PResult<Expr> {
        let mut l = self.parse_power()?;
        loop {
            let op = match self.peek() {
                Tok::Star => BinOp::Mul,
                Tok::Slash => BinOp::Div,
                _ => return Ok(l),
            };
            self.pos += 1;
            let r = self.parse_power()?;
            l = Expr::Binary(op, Box::new(l), Box::new(r));
        }
    }

    fn parse_unary(&mut self) -> PResult<Expr> {
        // VBScript accepts `Not` on the right of another operator, where it
        // takes the widest operand it can, as in `true <> Not true`.
        if self.is_kw(Kw::Not) {
            return self.parse_not();
        }
        match self.peek() {
            Tok::Minus => {
                self.pos += 1;
                let e = self.parse_unary()?;
                Ok(Expr::Unary(UnOp::Neg, Box::new(e)))
            }
            Tok::Plus => {
                self.pos += 1;
                let e = self.parse_unary()?;
                Ok(Expr::Unary(UnOp::Plus, Box::new(e)))
            }
            _ => self.parse_operand(),
        }
    }

    /// `^` associates left, and binds *looser* than unary minus, so `-3^2`
    /// is `(-3)^2` — VBScript differs from VBA here.
    fn parse_power(&mut self) -> PResult<Expr> {
        let mut l = self.parse_unary()?;
        while self.eat(&Tok::Caret) {
            let r = self.parse_unary()?;
            l = Expr::Binary(BinOp::Pow, Box::new(l), Box::new(r));
        }
        Ok(l)
    }

    fn parse_operand(&mut self) -> PResult<Expr> {
        let e = self.parse_primary()?;
        self.parse_postfix(e)
    }

    fn parse_primary(&mut self) -> PResult<Expr> {
        match self.peek().clone() {
            Tok::Int(v) => { self.pos += 1; Ok(Expr::Int(v)) }
            Tok::Long(v) => { self.pos += 1; Ok(Expr::Long(v)) }
            Tok::Real(v) => { self.pos += 1; Ok(Expr::Real(v)) }
            Tok::DateLit(v) => { self.pos += 1; Ok(Expr::Date(v)) }
            Tok::Str(s) => { self.pos += 1; Ok(Expr::Str(Rc::from(s.as_str()))) }
            Tok::Ident(s) => { self.pos += 1; Ok(Expr::Ident(Rc::from(s.as_str()))) }
            Tok::Keyword(Kw::True) => { self.pos += 1; Ok(Expr::Bool(true)) }
            Tok::Keyword(Kw::False) => { self.pos += 1; Ok(Expr::Bool(false)) }
            Tok::Keyword(Kw::Empty) => { self.pos += 1; Ok(Expr::Empty) }
            Tok::Keyword(Kw::Null) => { self.pos += 1; Ok(Expr::Null) }
            Tok::Keyword(Kw::Nothing) => { self.pos += 1; Ok(Expr::Nothing) }
            Tok::Keyword(Kw::Me) => { self.pos += 1; Ok(Expr::Me) }
            Tok::Keyword(Kw::New) => {
                self.pos += 1;
                let name = self.plain_ident()?;
                Ok(Expr::New(name))
            }
            Tok::Dot => {
                self.pos += 1;
                let name = self.ident_name()?;
                Ok(Expr::WithMember { name })
            }
            Tok::LParen => {
                self.pos += 1;
                let e = self.parse_expr()?;
                self.expect(Tok::RParen)?;
                Ok(Expr::Paren(Box::new(e)))
            }
            // `Error` is both a keyword and the name of a function in some
            // dialects; treat a bare use as an identifier.
            Tok::Keyword(
                k @ (Kw::Error | Kw::Step | Kw::Default | Kw::Get | Kw::Property | Kw::Explicit),
            ) => {
                self.pos += 1;
                Ok(Expr::Ident(Rc::from(k.as_str())))
            }
            t => self.err(format!("unexpected `{t}` in expression")),
        }
    }
}

const ALL_TERMS: &[Term] = &[
    Term::EndIf, Term::ElseIf, Term::Else, Term::EndSub, Term::EndFunction,
    Term::EndProperty, Term::EndClass, Term::EndSelect, Term::EndWith,
    Term::Case, Term::Next, Term::Loop, Term::Wend,
];

/// Evaluate a constant dimension expression at parse time, for class fields.
fn const_usize(e: &Expr) -> Option<usize> {
    match e {
        Expr::Int(v) | Expr::Long(v) if *v >= 0 => Some(*v as usize + 1),
        _ => None,
    }
}

/// Parse a single expression, for `Eval`.
pub fn parse_expression(src: &str) -> PResult<Expr> {
    let toks = Lexer::new(src)
        .tokenize()
        .map_err(|e| SyntaxError { msg: e.msg, line: e.line, code: e.code })?;
    let mut p = Parser { toks, pos: 0, options: Vec::new() };
    p.skip_seps();
    let e = p.parse_expr()?;
    p.skip_seps();
    if !matches!(p.peek(), Tok::Eof) {
        return p.err(format!("unexpected `{}` after expression", p.peek()));
    }
    Ok(e)
}
