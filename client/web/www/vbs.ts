// The language, for the editor: what a line is made of and how far it is
// indented.
//
// The vocabulary comes from `words.js`, which the build generates from the
// interpreter's own tables, so a name this colours is a name a script can
// call. Nothing here parses: the editor needs to know what a run of
// characters looks like, not what it means, and a highlighter that gives up
// gracefully on nonsense is what someone half-way through a line needs.
//
// VBScript has no multi-line string or comment, so a line can be tokenised on
// its own with no state carried from the one above it.

import { KEYWORDS, BUILTINS, API } from "./words.js";

/** One indent level. Spaces rather than tabs, as the shipped scripts use. */
export const INDENT = "    ";

const keywords = new Set(KEYWORDS.map((w) => w.toLowerCase()));
/** `vbCrLf` and friends are constants; the rest of the list is functions. */
const constants = new Set(BUILTINS.filter((w) => w.startsWith("vb")));
const builtins = new Set(BUILTINS.filter((w) => !w.startsWith("vb")));
const api = new Set(API);

/** The spelling the game uses for a name, for anything that wants to show it. */
const spelling = new Map(KEYWORDS.map((w) => [w.toLowerCase(), w]));

export function spell(word: string): string {
  return spelling.get(word.toLowerCase()) ?? word;
}

/** One run of a line, with the class to colour it. */
export interface Piece {
  text: string;
  cls: string | null;
}

/**
 * Split one line into `{ text, cls }` pieces covering all of it.
 *
 * `cls` is the highlight class, or null for anything unremarkable --
 * whitespace, punctuation and identifiers the client has never heard of.
 */
export function tokenize(line: string): Piece[] {
  const out: Piece[] = [];
  let i = 0;
  /** True when the last thing seen was a `.`, so `x.Say` is not the API's. */
  let afterDot = false;

  const push = (text: string, cls: string | null) => {
    if (text !== "") out.push({ text, cls });
  };

  while (i < line.length) {
    const c = line[i];

    // A comment runs to the end of the line, and so does a `Rem` statement.
    if (c === "'") {
      push(line.slice(i), "comment");
      break;
    }
    if (/^rem\b/i.test(line.slice(i)) && isStatementStart(line, i)) {
      push(line.slice(i), "comment");
      break;
    }

    // A string, in which `""` is an escaped quote. The game's `{{...}}`
    // markup is picked out inside it, since that is the other language a
    // script is written in and getting a tag wrong is a common mistake.
    if (c === '"') {
      let j = i + 1;
      while (j < line.length) {
        if (line[j] === '"' && line[j + 1] === '"') {
          j += 2;
          continue;
        }
        if (line[j] === '"') {
          j += 1;
          break;
        }
        j += 1;
      }
      for (const piece of splitMarkup(line.slice(i, j))) {
        push(piece.text, piece.cls);
      }
      i = j;
      afterDot = false;
      continue;
    }

    // A date literal, which is delimited rather than typed.
    if (c === "#") {
      const end = line.indexOf("#", i + 1);
      const j = end === -1 ? line.length : end + 1;
      push(line.slice(i, j), "number");
      i = j;
      afterDot = false;
      continue;
    }

    // &H1F and &O17, then ordinary numbers. A `.` only starts one when a
    // digit follows, so member access is not mistaken for a fraction.
    const radix = /^&[hHoO][0-9a-fA-F]*&?/.exec(line.slice(i));
    if (radix) {
      push(radix[0], "number");
      i += radix[0].length;
      afterDot = false;
      continue;
    }
    if (/[0-9]/.test(c) || (c === "." && /[0-9]/.test(line[i + 1] ?? ""))) {
      const number = /^[0-9]*\.?[0-9]+(?:[eE][-+]?[0-9]+)?/.exec(line.slice(i));
      const text = number ? number[0] : c;
      push(text, "number");
      i += text.length;
      afterDot = false;
      continue;
    }

    const word = /^[A-Za-z_][A-Za-z0-9_]*/.exec(line.slice(i));
    if (word) {
      push(word[0], afterDot ? "member" : classOf(word[0]));
      i += word[0].length;
      afterDot = false;
      continue;
    }

    // The line continuation is worth marking: a trailing `_` that is not one
    // is a common way to lose the rest of a statement.
    if (c === "_" && line.slice(i + 1).trim() === "") {
      push(line.slice(i), "continuation");
      break;
    }

    if (/\s/.test(c)) {
      const space = /^\s+/.exec(line.slice(i))?.[0] ?? c;
      push(space, null);
      i += space.length;
      continue;
    }

    push(c, c === "." ? null : "op");
    afterDot = c === ".";
    i += 1;
  }
  return out;
}

/** What kind of word this is, or null when nothing knows it. */
function classOf(word: string): string | null {
  const lower = word.toLowerCase();
  if (keywords.has(lower)) return "keyword";
  if (constants.has(lower)) return "constant";
  if (builtins.has(lower)) return "builtin";
  if (api.has(lower)) return "api";
  return null;
}

/** True when only whitespace, or a statement separator, comes before `at`. */
function isStatementStart(line: string, at: number): boolean {
  return /^[\s:]*$/.test(line.slice(0, at));
}

/** Split a string literal into its text and the `{{...}}` markup in it. */
function splitMarkup(text: string): Piece[] {
  const pieces: Piece[] = [];
  let at = 0;
  for (const match of text.matchAll(/\{\{.*?\}\}/g)) {
    pieces.push({ text: text.slice(at, match.index), cls: "string" });
    pieces.push({ text: match[0], cls: "markup" });
    at = match.index + match[0].length;
  }
  pieces.push({ text: text.slice(at), cls: "string" });
  return pieces;
}

// ---- indentation --------------------------------------------------------
//
// Two rules, which is all VBScript needs and all VS Code uses: a line that
// opens a block indents the one after it, and a line that closes one is
// pulled back level with the line that opened it.

/** `If ... Then` with nothing after it, and the other block openers. */
const OPENS =
  /^(?:(?:public|private|default)\s+)?(?:sub|function|class|property\s+(?:get|let|set))\b|^(?:for|while|with)\b|^do\b(?:\s+(?:while|until)\b.*)?$|^select\s+case\b|^(?:else|case)\b|^elseif\b.*\bthen$|^if\b.*\bthen$/;

/** The other half of each of those. */
const CLOSES = /^(?:end\s+(?:if|sub|function|property|class|with|select)|next|loop|wend|else|elseif|case)\b/;

/**
 * Whether a line opens a block, so the next one is indented further.
 *
 * The comment and any trailing continuation come off first, and a one-line
 * `If x Then y` opens nothing -- which is why `OPENS` insists that `Then` be
 * the last word on the line.
 */
export function opensBlock(line: string): boolean {
  return OPENS.test(significant(line));
}

/** Whether a line closes one, so it is pulled back a level itself. */
export function closesBlock(line: string): boolean {
  return CLOSES.test(significant(line));
}

/** A line reduced to the words that decide its indent. */
function significant(line: string): string {
  let text = line.trim();
  // A comment cannot open or close anything. Quotes are respected so that
  // an apostrophe inside a string is not read as one.
  let out = "";
  let inString = false;
  for (let i = 0; i < text.length; i += 1) {
    const c = text[i];
    if (c === '"') inString = !inString;
    if (c === "'" && !inString) break;
    // A string's contents cannot be a keyword, and blanking it keeps a
    // `Say "End If"` from pulling the line back.
    out += inString && c !== '"' ? " " : c;
  }
  return out.trim().replace(/\s+_$/, "").replace(/\s+/g, " ").toLowerCase();
}

/** The whitespace a line starts with. */
export function indentOf(line: string): string {
  return /^[ \t]*/.exec(line)?.[0] ?? "";
}

/**
 * What a line's indent should be, given the line above it.
 *
 * `previous` is the nearest line with anything on it; a blank one says
 * nothing about where the next belongs.
 */
export function indentFor(previous: string | null, line: string): string {
  if (previous === null) {
    return "";
  }
  let indent = indentOf(previous);
  if (opensBlock(previous)) {
    indent += INDENT;
  }
  if (closesBlock(line) && indent.length >= INDENT.length) {
    indent = indent.slice(0, -INDENT.length);
  }
  return indent;
}
