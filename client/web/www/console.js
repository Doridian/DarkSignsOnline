// Rendering the console.
//
// The worker sends styled runs rather than markup, so this only has to turn
// them into elements and apply the bands `Draw` asks for.

import { background } from "./draw.js";

const FLASH_CLASS = {
  none: null,
  normal: "flash",
  fast: "flash-fast",
  slow: "flash-slow",
};

/** Fonts a script can name, with fallbacks for machines that lack them. */
const FONT_STACK = {
  Impact: '"Impact", "Haettenschweiler", "Arial Narrow Bold", sans-serif',
  "Courier New": '"Courier New", "Liberation Mono", monospace',
  "Lucida Console": '"Lucida Console", "DejaVu Sans Mono", monospace',
  Verdana: '"Verdana", "DejaVu Sans", sans-serif',
  Wingdings: '"Wingdings", sans-serif',
  Webdings: '"Webdings", sans-serif',
};

function fontFor(name) {
  return FONT_STACK[name] ?? `"${name}", "DejaVu Sans", sans-serif`;
}

export class ConsoleView {
  /**
   * @param {HTMLElement} root where lines are appended
   * @param {HTMLElement|null} anchor an element kept last, ahead of which
   *   lines are inserted -- the input line lives inside the log so that
   *   typing happens where the text ends.
   */
  constructor(root, anchor = null) {
    this.root = root;
    this.anchor = anchor;
    /** The most recent line, so `SayLine` can replace it and `Draw` reach it. */
    this.lastLine = null;
  }

  /** Add a line, leaving the anchor last. */
  add(el) {
    this.root.insertBefore(el, this.anchor);
  }

  clear() {
    for (const child of [...this.root.children]) {
      if (child !== this.anchor) {
        child.remove();
      }
    }
    this.lastLine = null;
  }

  /** Remove the last line, which is what `LineUp` does. */
  lineUp() {
    if (!this.lastLine) return;
    // Read the neighbour before unlinking; the anchor is not a line.
    const previous = this.lastLine.previousElementSibling;
    this.lastLine.remove();
    this.lastLine = previous;
  }

  /** Append a line, or replace the previous one. */
  line(event) {
    const el = document.createElement("div");
    el.className = `line align-${event.align}`;
    if (!event.preSpace) {
      el.classList.add("no-prespace");
    }

    for (const run of event.runs) {
      if (run.text === "") continue;

      const span = document.createElement("span");
      span.textContent = run.text;
      span.style.color = run.color;
      span.style.fontFamily = fontFor(run.font);
      span.style.fontSize = `${run.size}px`;
      span.style.fontWeight = run.bold ? "700" : "400";
      if (run.italic) span.style.fontStyle = "italic";

      const decoration = [];
      if (run.underline) decoration.push("underline");
      if (run.strikethrough) decoration.push("line-through");
      if (decoration.length) span.style.textDecoration = decoration.join(" ");

      const flash = FLASH_CLASS[run.flash];
      if (flash) span.classList.add(flash);

      el.append(span);
    }

    // An empty line still occupies a row, and scripts use them for spacing.
    if (!el.hasChildNodes()) {
      el.append(document.createElement("br"));
    }

    if (event.replace && this.lastLine) {
      // Keep any band already drawn behind this row.
      el.style.background = this.lastLine.style.background;
      this.lastLine.replaceWith(el);
    } else {
      this.add(el);
    }
    this.lastLine = el;
    this.scrollToBottom();
  }

  /**
   * Paint a band behind the most recent line.
   *
   * `Draw` addresses a row rather than the text on it, which is how the
   * startup script builds its banner: a line, then a band behind it.
   */
  draw(event) {
    if (!this.lastLine) {
      // A band with no line yet still takes up a row.
      this.line({ runs: [], align: "left", preSpace: true, replace: false });
    }
    this.lastLine.style.background = background(event.color, event.mode, event.segments);
  }

  /**
   * Echo a submitted line: the prompt keeps its own colour, and what was
   * typed is shown plainly, the way the console draws it.
   */
  echo(promptText, text, scriptPrompt = false) {
    const el = document.createElement("div");
    el.className = "line no-prespace echo";
    const label = document.createElement("span");
    label.className = scriptPrompt ? "prompt-echo script" : "prompt-echo";
    label.textContent = promptText;
    el.append(label, document.createTextNode(text));
    this.add(el);
    this.lastLine = el;
    this.scrollToBottom();
  }

  /** A message that did not come from a script. */
  system(text, kind = "system") {
    const el = document.createElement("div");
    el.className = `line ${kind}`;
    el.textContent = text;
    this.add(el);
    this.lastLine = el;
    this.scrollToBottom();
  }

  scrollToBottom() {
    this.root.scrollTop = this.root.scrollHeight;
  }
}

/** The communications log along the top of the window. */
export class CommView {
  constructor(root) {
    this.root = root;
  }

  add(text) {
    const line = document.createElement("div");
    line.className = "comm-line";

    const time = document.createElement("span");
    time.className = "comm-time";
    time.textContent = new Date().toLocaleTimeString([], {
      hour: "numeric",
      minute: "2-digit",
      hour12: true,
    });

    const body = document.createElement("span");
    body.className = "comm-text";
    body.textContent = text;

    line.append(time, body);
    this.root.append(line);
    this.root.scrollTop = this.root.scrollHeight;
  }
}
