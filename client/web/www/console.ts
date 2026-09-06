// Rendering the console.
//
// The worker sends styled runs rather than markup, so this only has to turn
// them into elements and apply the bands `Draw` asks for.

import { background, evenBands, fixedBands } from "./draw.js";
import { fontFor } from "./fonts.js";

import type {
  DrawCustomEvent,
  DrawEvenEvent,
  DrawEvent,
  LineEvent,
  PartialLine,
} from "./types.js";

const FLASH_CLASS: Record<string, string | null> = {
  none: null,
  normal: "flash",
  fast: "flash-fast",
  slow: "flash-slow",
};

export class ConsoleView {
  /** The most recent line, so `SayLine` can replace it and `Draw` reach it. */
  lastLine: HTMLElement | null = null;

  /**
   * `root` is where lines are appended, and `anchor` an element kept last,
   * ahead of which they are inserted -- the input line lives inside the log
   * so that typing happens where the text ends.
   */
  constructor(
    readonly root: HTMLElement,
    readonly anchor: HTMLElement | null = null,
  ) {}

  /** Add a line, leaving the anchor last. */
  add(el: HTMLElement): void {
    this.root.insertBefore(el, this.anchor);
  }

  clear(): void {
    for (const child of [...this.root.children]) {
      if (child !== this.anchor) {
        child.remove();
      }
    }
    this.lastLine = null;
  }

  /** Remove the last line, which is what `LineUp` does. */
  lineUp(): void {
    if (!this.lastLine) return;
    // Read the neighbour before unlinking; the anchor is not a line.
    const previous = this.lastLine.previousElementSibling as HTMLElement | null;
    this.lastLine.remove();
    this.lastLine = previous;
  }

  /** Append a line, or replace the previous one. */
  line(event: LineEvent | PartialLine): void {
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
      // The client's sizes are points, as VB6 fonts are. CSS agrees about
      // what a point is, so the unit does the conversion: the default 10
      // lands at 13.3px rather than a too-small 10px.
      span.style.fontSize = `${run.size}pt`;
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
  draw(event: DrawEvent): void {
    this.bandBehindLast(background(event.color, event.mode, event.segments));
  }

  /**
   * Paint a band of set widths behind the most recent line.
   *
   * `DrawCustom` gives each piece a width in the same pixels `TextWidth`
   * reports, so the band is laid out in those and whatever is left of the
   * line stays as it was.
   */
  drawCustom(event: DrawCustomEvent): void {
    this.bandBehindLast(fixedBands(event.bands));
  }

  /** `DrawEven` splits the whole line equally between its colours. */
  drawEven(event: DrawEvenEvent): void {
    this.bandBehindLast(evenBands(event.colors));
  }

  /**
   * Put a background behind the last line, adding a line if there is none:
   * a band addresses a row rather than the text on it, so an empty row is
   * still a row.
   */
  bandBehindLast(background: string): void {
    if (!this.lastLine) {
      this.line({ runs: [], align: "left", preSpace: true, replace: false });
    }
    (this.lastLine as HTMLElement).style.background = background;
  }

  /**
   * Echo a submitted line: the prompt keeps its own colour, and what was
   * typed is shown plainly, the way the console draws it.
   */
  echo(promptText: string, text: string, scriptPrompt = false): void {
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
  system(text: string, kind = "system"): void {
    const el = document.createElement("div");
    el.className = `line ${kind}`;
    el.textContent = text;
    this.add(el);
    this.lastLine = el;
    this.scrollToBottom();
  }

  scrollToBottom(): void {
    this.root.scrollTop = this.root.scrollHeight;
  }
}

/** The communications log along the top of the window. */
export class CommView {
  constructor(readonly root: HTMLElement) {}

  add(text: string): void {
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
