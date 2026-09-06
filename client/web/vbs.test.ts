#!/usr/bin/env node
// The editor's language rules.
//
// Highlighting and indenting are the two things it does that a plain
// textarea does not, and both are decided line by line in `www/vbs.js`. Run
// them here rather than in a browser:
//
//   node --test web/vbs.test.ts
//
// The vocabulary comes from `www/words.js`, which `build.sh` generates, so
// these also fail if that file has gone missing.

import test from "node:test";
import assert from "node:assert/strict";

import {
  INDENT,
  closesBlock,
  indentFor,
  indentOf,
  opensBlock,
  tokenize,
} from "./www/vbs.js";

/** The classes a line's pieces are given, joined for a compact assertion. */
const classes = (line: string) =>
  tokenize(line)
    .filter((piece) => piece.text.trim() !== "")
    .map((piece) => `${piece.cls ?? "-"}:${piece.text}`)
    .join(" ");

test("a word is coloured by what the interpreter would do with it", () => {
  assert.equal(
    classes("Dim x : x = Len(name)"),
    "keyword:Dim -:x op:: -:x op:= builtin:Len op:( -:name op:)",
  );
  // `Say` is the game's, `Len` is VBScript's, and `nosuchthing` is neither.
  assert.equal(classes("Say nosuchthing"), "api:Say -:nosuchthing");
  // The dot is punctuation, and what follows it is a member, not the API.
  assert.equal(classes("x.Say"), "-:x -:. member:Say");
});

test("a comment swallows the rest of the line, and a string does not", () => {
  assert.equal(classes("x = 1 ' Say hello"), "-:x op:= number:1 comment:' Say hello");
  assert.equal(classes("Rem Say hello"), "comment:Rem Say hello");
  // An apostrophe inside a string is text, not the start of a comment.
  assert.deepEqual(
    tokenize(`Say "it's here" ' but this is a comment`).filter((p) => p.cls === "comment"),
    [{ text: "' but this is a comment", cls: "comment" }],
  );
});

test("the game's own markup is picked out inside a string", () => {
  assert.equal(
    classes('Say "{{green}}ok"'),
    'api:Say string:" markup:{{green}} string:ok"',
  );
});

test("numbers keep their VBScript spellings", () => {
  assert.equal(classes("x = &HFF"), "-:x op:= number:&HFF");
  assert.equal(classes("x = 1.5e3"), "-:x op:= number:1.5e3");
  // A dot between names is member access, not the start of a fraction.
  assert.equal(classes("a.b"), "-:a -:. member:b");
});

test("a block opener indents what follows it", () => {
  for (const line of [
    "If x = 1 Then",
    "  For each item In list",
    "Do While x < 3",
    "Do",
    "While x",
    "Sub Main()",
    "Public Function F(a)",
    "Class Thing",
    "With obj",
    "Select Case x",
    "  Case 1",
    "Else",
    "ElseIf y Then",
  ]) {
    assert.ok(opensBlock(line), `${line} should open a block`);
  }
});

test("a one-line If opens nothing", () => {
  assert.ok(!opensBlock("If x = 1 Then Say \"hi\""));
  assert.ok(!opensBlock("Say \"End If\""), "a keyword inside a string is text");
  assert.ok(!opensBlock("x = 1"));
  assert.ok(!opensBlock("' If x Then"), "a comment opens nothing");
});

test("a block closer pulls its own line back", () => {
  for (const line of [
    "End If",
    "End Sub",
    "  End Function",
    "End Class",
    "End With",
    "End Select",
    "Next",
    "Loop",
    "Wend",
    "Else",
    "ElseIf z Then",
    "Case Else",
  ]) {
    assert.ok(closesBlock(line), `${line} should close a block`);
  }
  assert.ok(!closesBlock("Endless = 1"), "a word that merely starts the same does not");
});

test("the indent carries from one line to the next", () => {
  // What the editor does on Enter: the line above decides the one below.
  assert.equal(indentFor("Sub Main()", ""), INDENT);
  assert.equal(indentFor(`${INDENT}If x Then`, ""), INDENT + INDENT);
  assert.equal(indentFor(`${INDENT}Say "hi"`, ""), INDENT);
  // A line that closes a block comes back out a level.
  assert.equal(indentFor(`${INDENT}Say "hi"`, "End Sub"), "");
  // And one that both closes and opens stays where the block is.
  assert.equal(indentFor(`${INDENT}${INDENT}Say "hi"`, `${INDENT}Else`), INDENT);
  assert.equal(indentFor(null, "anything"), "", "nothing above means no indent");
});

test("a whole procedure indents the way it was typed", () => {
  const source = [
    "Sub Main()",
    "If ArgC() > 0 Then",
    "For n = 1 To ArgC()",
    'Say ArgV(n)',
    "Next",
    "Else",
    'Say "nothing to do"',
    "End If",
    "End Sub",
  ];
  const wanted = [
    "",
    INDENT,
    INDENT + INDENT,
    INDENT + INDENT + INDENT,
    INDENT + INDENT,
    INDENT,
    INDENT + INDENT,
    INDENT,
    "",
  ];

  const laid: string[] = [];
  for (const [n, line] of source.entries()) {
    laid.push(indentFor(n === 0 ? null : laid[n - 1] + source[n - 1], line));
  }
  assert.deepEqual(laid, wanted);
});

test("indentOf reads the whitespace a line starts with", () => {
  assert.equal(indentOf("    x"), "    ");
  assert.equal(indentOf("x"), "");
  assert.equal(indentOf(""), "");
});
