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

/**
 * How many lines a console keeps.
 *
 * A log that keeps everything gets slower the longer it is -- it is all held,
 * styled and laid out, and the height the page reads at the end of a batch is
 * the height of all of it -- and it never gets faster again. Since a script is
 * paced by the page now (see `GameConsole.drawBatch`), that is not a display
 * falling behind but the script itself slowing down as it prints. Dropping
 * the oldest lines is what bounds that, and the memory with it.
 *
 * What is kept is very nearly what a printing script costs, so this is not a
 * number to raise idly: in Chromium, 300,000 lines take 1.8s at 500 and 37.3s
 * at 32,000. Keeping everything is not the cheap end of that -- appending
 * beats dropping until the log is large enough to be its own problem, and
 * then it falls off a cliff: 1,000,000 lines take 83.2s kept in full against
 * 13.5s at 2000. The README has the table.
 *
 * 2000 is well past a screenful and past anything the game's own scripts
 * print in one go, and it is the scrollback a terminal usually keeps.
 */
export const SCROLLBACK = 2000;

/** The same for the communications log, which a whole session writes to. */
const COMM_SCROLLBACK = 500;

/**
 * Drop the oldest lines until no more than `limit` are left.
 *
 * `anchor`, when there is one, is kept last and is not a line, so it is
 * counted out rather than removed. Nothing is measured here, so nothing is
 * laid out here either; what it costs is that the next layout has to move
 * what is left up, which is why the limit is what a printing script costs.
 */
function trim(root: HTMLElement, limit: number, anchor: Element | null): void {
  while (root.children.length > limit + (anchor ? 1 : 0)) {
    const oldest = root.firstElementChild;
    // The anchor is last, so it is only at the front when it is all there
    // is; either way there is nothing left to drop.
    if (!oldest || oldest === anchor) {
      return;
    }
    oldest.remove();
  }
}

export class ConsoleView {
  /** The most recent line, so `SayLine` can replace it and `Draw` reach it. */
  lastLine: HTMLElement | null = null;
  /**
   * Set while a batch of lines is being added, to scroll once at the end.
   *
   * Reading `scrollHeight` forces the browser to lay the log out, so doing
   * it per line makes adding a hundred a hundred times the work of adding
   * them together. The page draws a frame's worth at a time; see
   * `GameConsole.drawBatch`.
   */
  holdScroll = false;

  /**
   * `root` is where lines are appended, and `anchor` an element kept last,
   * ahead of which they are inserted -- the input line lives inside the log
   * so that typing happens where the text ends.
   */
  constructor(
    readonly root: HTMLElement,
    readonly anchor: HTMLElement | null = null,
    readonly limit: number = SCROLLBACK,
  ) {}

  /** Add a line, leaving the anchor last and the log within its limit. */
  add(el: HTMLElement): void {
    this.root.insertBefore(el, this.anchor);
    // Scrolled up, this shifts what is being read up with it -- but a log
    // that keeps everything cannot be read for long either, and correcting
    // the position means measuring what was dropped, which is the layout
    // this is here to avoid.
    trim(this.root, this.limit, this.anchor);
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
    if (this.holdScroll) {
      return;
    }
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
    trim(this.root, COMM_SCROLLBACK, null);
    this.root.scrollTop = this.root.scrollHeight;
  }
}
