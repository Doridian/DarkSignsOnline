// The editor, which `EDIT <file>` opens.
//
// The original is a text box with a list of commands beside it and an
// autosave on every keystroke. This keeps all three and adds what someone
// writing a script now expects: the text is coloured, and the indent carries
// from one line to the next instead of being retyped.
//
// It is a textarea with a highlighted `<pre>` behind it, drawn in the same
// metrics so the two line up exactly. The textarea keeps the caret, the
// selection, the undo history and every other thing a browser already does
// well; only the colour is ours.
//
// Unlike the mail window this one does not rebuild its DOM to redraw. A
// textarea that is replaced loses the caret, the selection and the undo
// history, so the frame is built once and the parts that change are updated
// in place.

import { API } from "./reference.js";
import type { Ask } from "./types.js";
import { INDENT, closesBlock, indentFor, indentOf, opensBlock, tokenize } from "./vbs.js";
import { centred, draggable, manage } from "./window.js";

/** How long to wait after a keystroke before saving. */
const AUTOSAVE_MS = 400;

/** What the worker answers a `readFile` with. */
interface OpenedFile {
  path: string;
  contents: string;
  exists: boolean;
}

export class EditorWindow {
  /** The file's name in the title bar. */
  title = el("strong", "ed-title", "Editor");
  /** The line numbers, the coloured layer, and the text itself. */
  numbers = el("pre", "ed-numbers");
  highlight = el("pre", "ed-highlight");
  input = el("textarea", "ed-input");
  /** The signature of whichever name was last clicked in the reference. */
  hint = el("span", "ed-hint");
  position = el("span", "ed-position", "Ln 1, Col 1");
  status = el("span", "ed-state");

  path = "";
  /** The console whose script asked for this file, so Run goes back to it. */
  consoleId = 1;
  saveTimer: ReturnType<typeof setTimeout> | undefined = undefined;
  /** Set while a save is in flight, so a second one waits for it. */
  saving = false;
  /** Set when the text has changed since the last save started. */
  dirty = false;
  /** How many lines the gutter is currently numbering. */
  lineCount = -1;
  /** Resolves the save that was asked for while one was in flight. */
  resumeSave: (() => void) | null = null;
  pending: Promise<void> | null = null;

  /**
   * `ask` asks whichever console is free; `run` runs the file in the console
   * that opened the editor and says whether it could.
   */
  constructor(
    readonly root: HTMLDialogElement,
    readonly ask: Ask,
    readonly run: (consoleId: number, path: string) => boolean,
  ) {
    manage(root, {
      rect: (desk) => centred(desk, 72 * 16, 46 * 16),
      min: { w: 420, h: 260 },
    });
    this.build();
    // Closing by any route -- the button, Escape, the browser -- saves what
    // is on screen, because the original never asks either.
    this.root.addEventListener("close", () => void this.save());
  }

  get open(): boolean {
    return this.root.open;
  }

  /**
   * Open a file, or an empty buffer where there is not one yet.
   */
  async openFile(path: string, consoleId: number): Promise<void> {
    this.path = path;
    this.consoleId = consoleId;
    this.title.textContent = path;
    this.setStatus("Opening...");
    if (!this.root.open) {
      this.root.show();
    }

    try {
      const file: OpenedFile = await this.ask({ type: "readFile", path });
      this.input.value = file.contents;
      this.setStatus(file.exists ? "Opened." : "New file.");
    } catch (err) {
      this.input.value = "";
      this.setStatus(message(err));
    }
    this.dirty = false;
    this.redraw();
    this.input.setSelectionRange(0, 0);
    this.input.focus();
    this.input.scrollTop = 0;
  }

  // ---- the frame -------------------------------------------------------

  build(): void {
    const bar = el("header", "win-bar ed-bar win-drag");
    bar.append(
      this.title,
      el("span", "ed-spacer"),
      button("Run (F5)", () => void this.runFile()),
      button("Save", () => void this.save()),
      button("Close", () => this.root.close()),
    );
    draggable(this.root, bar);

    this.numbers.setAttribute("aria-hidden", "true");
    const gutter = el("div", "ed-gutter");
    gutter.append(this.numbers);

    this.highlight.setAttribute("aria-hidden", "true");

    this.input.spellcheck = false;
    this.input.autocapitalize = "off";
    this.input.autocomplete = "off";
    this.input.wrap = "off";
    this.input.setAttribute("aria-label", "Script");

    const code = el("div", "ed-code");
    code.append(this.highlight, this.input);
    const pane = el("div", "ed-pane");
    pane.append(gutter, code);

    const main = el("div", "ed-main");
    main.append(pane, this.reference());

    const footer = el("footer", "ed-status");
    footer.append(this.hint, el("span", "ed-spacer"), this.position, this.status);

    this.root.replaceChildren(bar, main, footer);

    this.input.addEventListener("input", (event) => {
      this.dirty = true;
      // A word just typed may be one that closes a block, in which case the
      // line it is on belongs a level further out. Only on a typed letter:
      // re-indenting after a backspace would put back the space the player
      // had just taken out.
      if (
        event instanceof InputEvent &&
        event.inputType === "insertText" &&
        /[A-Za-z]/.test(event.data ?? "")
      ) {
        this.reindent();
      }
      this.redraw();
      this.scheduleSave();
    });
    this.input.addEventListener("keydown", (e) => this.onKeyDown(e));
    this.input.addEventListener("scroll", () => this.syncScroll());
    // Where the caret is now, however it got there.
    for (const event of ["keyup", "click", "select"]) {
      this.input.addEventListener(event, () => this.showPosition());
    }
  }

  /** The API list, which is the original's command list brought forward. */
  reference(): HTMLElement {
    const search = el("input", "ed-search");
    search.type = "search";
    search.placeholder = "Search the API";
    search.setAttribute("aria-label", "Search the script API");

    const list = el("div", "ed-list");
    const rows = API.map(([name, args]) => {
      const row = el("button", "ed-ref-row");
      row.type = "button";
      row.append(el("span", "ed-ref-name", name), el("span", "ed-ref-args", args));
      row.title = `${name}(${args})`;
      row.addEventListener("click", () => {
        this.hint.textContent = `${name}(${args})`;
      });
      row.addEventListener("dblclick", () => this.insert(name));
      list.append(row);
      return { row, term: `${name} ${args}`.toLowerCase() };
    });

    search.addEventListener("input", () => {
      const term = search.value.trim().toLowerCase();
      for (const row of rows) {
        row.row.hidden = term !== "" && !row.term.includes(term);
      }
    });

    const aside = el("aside", "ed-ref");
    aside.append(search, list, el("p", "ed-ref-foot", "Double-click a name to insert it."));
    return aside;
  }

  // ---- drawing ---------------------------------------------------------

  redraw(): void {
    const lines = this.input.value.split("\n");
    // A trailing newline leaves an empty last line that the textarea gives
    // room to and a `<pre>` would not, so the highlight always ends in one.
    this.highlight.innerHTML = `${lines.map(highlightLine).join("\n")}\n`;
    if (this.lineCount !== lines.length) {
      this.lineCount = lines.length;
      this.numbers.textContent = lines.map((_, n) => n + 1).join("\n");
    }
    this.syncScroll();
    this.showPosition();
  }

  /** Keep the two layers and the gutter looking at the same place. */
  syncScroll(): void {
    const x = this.input.scrollLeft;
    const y = this.input.scrollTop;
    this.highlight.style.transform = `translate(${-x}px, ${-y}px)`;
    this.numbers.style.transform = `translateY(${-y}px)`;
  }

  showPosition(): void {
    const lines = this.input.value.slice(0, this.input.selectionStart).split("\n");
    this.position.textContent = `Ln ${lines.length}, Col ${(lines.at(-1) ?? "").length + 1}`;
  }

  setStatus(text: string): void {
    this.status.textContent = text;
  }

  // ---- editing ---------------------------------------------------------

  onKeyDown(e: KeyboardEvent): void {
    if (e.key === "F5") {
      e.preventDefault();
      void this.runFile();
      return;
    }
    if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === "s") {
      e.preventDefault();
      void this.save();
      return;
    }
    if (e.key === "Tab") {
      e.preventDefault();
      this.tab(e.shiftKey);
      return;
    }
    if (e.key === "Enter") {
      e.preventDefault();
      this.newline();
      return;
    }
    if (e.key === "Backspace") {
      this.unindent(e);
    }
  }

  /**
   * A new line, indented where it belongs.
   *
   * The indent of the line being left is carried over and one level is added
   * when that line opened a block -- which is the whole of what was being
   * retyped before. What follows the caret is looked at too, so that
   * splitting `Sub x()|End Sub` lands both halves where they belong.
   */
  newline(): void {
    const { value, selectionStart: from, selectionEnd: to } = this.input;
    const lineStart = value.lastIndexOf("\n", from - 1) + 1;
    const current = value.slice(lineStart, from);
    const rest = value.slice(to);
    const breakAt = rest.indexOf("\n");
    const tail = rest.slice(0, breakAt === -1 ? rest.length : breakAt);

    let indent = indentOf(current);
    if (opensBlock(current)) {
      indent += INDENT;
    }
    if (closesBlock(tail) && indent.length >= INDENT.length) {
      indent = indent.slice(0, -INDENT.length);
    }
    this.replace(from, to, `\n${indent}`);
  }

  /**
   * Tab indents and Shift+Tab takes an indent back; a selection that spans
   * lines moves all of them.
   */
  tab(back: boolean): void {
    const { value, selectionStart: from, selectionEnd: to } = this.input;
    const spansLines = value.slice(from, to).includes("\n");

    if (!spansLines && !back) {
      // To the next stop, so the column lands where the eye expects.
      const column = from - (value.lastIndexOf("\n", from - 1) + 1);
      this.replace(from, to, " ".repeat(INDENT.length - (column % INDENT.length)));
      return;
    }

    const start = value.lastIndexOf("\n", from - 1) + 1;
    const lineEnd = value.indexOf("\n", to);
    const end = lineEnd === -1 ? value.length : lineEnd;
    const moved = value
      .slice(start, end)
      .split("\n")
      .map((line) => (back ? dedent(line) : INDENT + line))
      .join("\n");

    this.input.setRangeText(moved, start, end, "select");
    this.afterEdit();
  }

  /**
   * Backspace at the front of a line eats a whole indent level.
   *
   * Only within the indent itself: anywhere else the browser's own backspace
   * is the right one, undo history and all.
   */
  unindent(e: KeyboardEvent): void {
    const { value, selectionStart: from, selectionEnd: to } = this.input;
    if (from !== to) {
      return;
    }
    const lineStart = value.lastIndexOf("\n", from - 1) + 1;
    const before = value.slice(lineStart, from);
    if (before === "" || !/^ +$/.test(before)) {
      return;
    }
    const width = before.length % INDENT.length || INDENT.length;
    e.preventDefault();
    this.replace(from - width, from, "");
  }

  /**
   * Replace a range, leaving the caret after what was put there.
   */
  replace(from: number, to: number, text: string): void {
    this.input.setRangeText(text, from, to, "end");
    this.afterEdit();
  }

  /**
   * Insert at the caret, from the reference list.
   */
  insert(text: string): void {
    this.replace(this.input.selectionStart, this.input.selectionEnd, text);
    this.input.focus();
  }

  /**
   * Pull the line the caret is on back to where its opener sits.
   *
   * This is the half of the indenting that happens as a word is typed: an
   * `End If` or an `Else` belongs one level further out than the block it
   * ends, and nobody should have to reach for backspace to put it there.
   * Working out the same indent twice changes nothing, so it is safe to run
   * on every keystroke.
   */
  reindent(): void {
    const { value, selectionStart, selectionEnd } = this.input;
    if (selectionStart !== selectionEnd) {
      return;
    }
    const start = value.lastIndexOf("\n", selectionStart - 1) + 1;
    const lineEnd = value.indexOf("\n", selectionStart);
    const line = value.slice(start, lineEnd === -1 ? value.length : lineEnd);
    if (!closesBlock(line)) {
      return;
    }

    const wanted = indentFor(lastLineWithText(value.slice(0, start)), line);
    const present = indentOf(line);
    if (wanted === present) {
      return;
    }
    this.input.setRangeText(wanted, start, start + present.length);
    // The caret was somewhere after the indent; it moves with the text.
    const caret = selectionStart + (wanted.length - present.length);
    this.input.setSelectionRange(caret, caret);
  }

  /**
   * `setRangeText` raises no `input` event, so everything it changes has to
   * be followed up by hand.
   */
  afterEdit(): void {
    this.dirty = true;
    this.redraw();
    this.scheduleSave();
  }

  // ---- saving and running ----------------------------------------------

  scheduleSave(): void {
    clearTimeout(this.saveTimer);
    this.setStatus("Editing...");
    this.saveTimer = setTimeout(() => void this.save(), AUTOSAVE_MS);
  }

  /**
   * Write the file, and wait for the worker to say it landed.
   *
   * A save asked for while one is in flight is folded into a single one
   * afterwards: the whole file goes out each time, so only the last one's
   * contents matter.
   */
  async save(): Promise<void> {
    clearTimeout(this.saveTimer);
    if (!this.dirty || this.path === "") {
      return;
    }
    if (this.saving) {
      this.pending ??= new Promise<void>((resolve) => {
        this.resumeSave = resolve;
      });
      return this.pending;
    }

    this.saving = true;
    this.dirty = false;
    this.setStatus("Saving...");
    try {
      await this.ask({ type: "writeFile", path: this.path, contents: this.input.value });
      this.setStatus(`Saved ${new Date().toLocaleTimeString()}`);
    } catch (err) {
      this.dirty = true;
      this.setStatus(message(err));
    } finally {
      this.saving = false;
      const waiting = this.resumeSave;
      this.pending = null;
      this.resumeSave = null;
      // Whoever asked while this one was running gets the next one.
      if (waiting) {
        await this.save();
        waiting();
      }
    }
  }

  /**
   * What the original's "Test Script" does: close the window, and run the
   * file in the console that opened it.
   */
  async runFile(): Promise<void> {
    await this.save();
    if (!this.run(this.consoleId, this.path)) {
      this.setStatus(`Console ${this.consoleId} is busy.`);
      return;
    }
    this.root.close();
  }
}

/**
 * The last line with anything on it, which is the one an indent is measured
 * against. A blank line says nothing about where the next belongs.
 */
function lastLineWithText(text: string): string | null {
  const lines = text.split("\n");
  for (let n = lines.length - 1; n >= 0; n -= 1) {
    const line = lines[n];
    if (line !== undefined && line.trim() !== "") {
      return line;
    }
  }
  return null;
}

/** One line of coloured HTML. */
function highlightLine(line: string): string {
  if (line === "") {
    return "";
  }
  let html = "";
  for (const { text, cls } of tokenize(line)) {
    html += cls ? `<span class="tok-${cls}">${escapeHtml(text)}</span>` : escapeHtml(text);
  }
  return html;
}

function escapeHtml(text: string): string {
  return text.replace(/[&<>]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;" })[c] ?? c);
}

/** Take one indent level off the front of a line, however much of one is there. */
function dedent(line: string): string {
  const width = /^ {1,4}|^\t/.exec(line);
  return width ? line.slice(width[0].length) : line;
}

/** What went wrong, in the words it came with. */
function message(err: unknown): string {
  return String(err instanceof Error ? err.message : err);
}

function el<K extends keyof HTMLElementTagNameMap>(
  tag: K,
  className?: string | null,
  text?: string,
): HTMLElementTagNameMap[K] {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (text !== undefined) node.textContent = text;
  return node;
}

function button(label: string, onClick: () => void): HTMLButtonElement {
  const node = el("button", "mail-button", label);
  node.type = "button";
  node.addEventListener("click", onClick);
  return node;
}
