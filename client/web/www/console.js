// Rendering the console.
//
// The worker sends styled runs rather than markup, so this only has to turn
// them into elements.

const FLASH_CLASS = {
  none: null,
  normal: "flash",
  fast: "flash-fast",
  slow: "flash-slow",
};

export class ConsoleView {
  /** @param {HTMLElement} root where lines are appended */
  constructor(root) {
    this.root = root;
    /** The most recent line, so `SayLine` can replace it. */
    this.lastLine = null;
  }

  clear() {
    this.root.replaceChildren();
    this.lastLine = null;
  }

  /** Remove the last line, which is what `LineUp` does. */
  lineUp() {
    if (this.lastLine) {
      this.lastLine.remove();
      this.lastLine = this.root.lastElementChild;
    }
  }

  /** Append a line, or replace the previous one. */
  line(event) {
    const el = document.createElement("div");
    el.className = `line align-${event.align} channel-${event.channel}`;
    if (!event.preSpace) {
      el.classList.add("no-prespace");
    }

    for (const run of event.runs) {
      if (run.text === "") {
        continue;
      }
      const span = document.createElement("span");
      span.textContent = run.text;
      span.style.color = run.color;
      span.style.fontFamily = `"${run.font}", monospace`;
      span.style.fontSize = `${run.size}px`;
      span.style.fontWeight = run.bold ? "bold" : "normal";
      span.style.fontStyle = run.italic ? "italic" : "normal";

      const decoration = [];
      if (run.underline) decoration.push("underline");
      if (run.strikethrough) decoration.push("line-through");
      if (decoration.length) {
        span.style.textDecoration = decoration.join(" ");
      }

      const flash = FLASH_CLASS[run.flash];
      if (flash) {
        span.classList.add(flash);
      }
      el.append(span);
    }

    // An empty line still takes up a row.
    if (!el.hasChildNodes()) {
      el.innerHTML = "&nbsp;";
    }

    if (event.replace && this.lastLine) {
      this.lastLine.replaceWith(el);
    } else {
      this.root.append(el);
    }
    this.lastLine = el;
    this.scrollToBottom();
  }

  /** A horizontal rule behind the previous line. */
  draw(event) {
    if (this.lastLine) {
      this.lastLine.style.backgroundColor = event.color;
    }
  }

  scrollToBottom() {
    this.root.scrollTop = this.root.scrollHeight;
  }

  /** Show a message that did not come from a script. */
  system(text, kind = "system") {
    const el = document.createElement("div");
    el.className = `line ${kind}`;
    el.textContent = text;
    this.root.append(el);
    this.lastLine = el;
    this.scrollToBottom();
  }
}
