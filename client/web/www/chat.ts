// Chat.
//
// The original client opened a TLS socket to `irc.libera.chat:6697` and sat
// in `#darksignsonline`. A browser has no raw sockets, so the room is the
// game server's own now and this asks `chat.php` for whatever is newer than
// the last line it holds.
//
// Everything above the transport is the original's. The pane covers the
// console and F5 raises it, as `ShowChat` does. A line reads `<who>  text`,
// `/me` is an emote, `//` escapes a leading slash, and Up and Down walk back
// through the last fifty things typed.
//
// Like mail, the connection belongs to a worker -- credentials never leave
// them -- so both the polling and the sending go through `ask`, which hands
// the work to whichever console is free.

import type { Ask, ChatLine, Said } from "./types.js";

/** How often to ask for new lines. */
const POLL_MS = 2000;

/** After a failure, back off to this until one succeeds again. */
const POLL_MS_AFTER_FAILURE = 15000;

/** How many typed lines Up and Down walk back through, as in the original. */
const HISTORY_LIMIT = 50;

/** How many lines the pane keeps before dropping the oldest. */
const SCROLLBACK = 500;

export class ChatPanel {
  /**
   * Ids already shown.
   *
   * A line sent from here is drawn at once and comes back on the next poll,
   * and a script's `ChatSend` arrives as a console event the same way. Both
   * carry the id the server gave them, so this is what keeps either from
   * being drawn twice.
   */
  private shown = new Set<number>();
  /**
   * The highest id asked past.
   *
   * Advanced only by a fetch. An echoed line can have a higher id than
   * anything fetched, and moving this to it would skip whatever was said in
   * between.
   */
  private fetchedTo = 0;
  /** The last fifty lines typed, newest first, as `ircMsgs` holds them. */
  private history: string[] = [];
  /** Where Up and Down are in that list; -1 is the line being typed. */
  private historyAt = -1;

  /** Set once signed in, since the room needs an account to be read at all. */
  private polling = false;
  private timer: number | undefined;
  /** Set while a fetch is out, so a slow one does not stack up behind it. */
  private fetching = false;

  /**
   * Whether incoming chat is mirrored to the communications log.
   *
   * This is `ChatView`, and it is not the pane's visibility: the original
   * keeps it in `chatToStatus` and F5 shows the pane regardless of it.
   */
  view = false;

  readonly log: HTMLElement;
  readonly input: HTMLInputElement;

  constructor(
    readonly root: HTMLElement,
    readonly ask: Ask,
    /** Called for each new line while `view` is on. */
    readonly mirror: (text: string) => void,
    /** Called with the client's own complaints, which go to the comm log. */
    readonly complain: (text: string) => void,
  ) {
    this.log = root.querySelector(".chat-log") as HTMLElement;
    this.input = root.querySelector(".chat-input") as HTMLInputElement;

    const form = root.querySelector(".chat-entry") as HTMLFormElement;
    form.addEventListener("submit", (e) => {
      e.preventDefault();
      void this.say();
    });

    this.input.addEventListener("keydown", (e) => this.walkHistory(e));
    (root.querySelector(".chat-close") as HTMLButtonElement).addEventListener(
      "click",
      () => this.hide(),
    );
  }

  get visible(): boolean {
    return !this.root.hidden;
  }

  /** F5, and the status bar's button. */
  toggle(): void {
    if (this.visible) {
      this.hide();
    } else {
      this.show();
    }
  }

  show(): void {
    this.root.hidden = false;
    this.input.focus();
    // Whatever arrived while it was down is at the bottom.
    this.log.scrollTop = this.log.scrollHeight;
  }

  hide(): void {
    this.root.hidden = true;
  }

  /**
   * Start polling, or stop.
   *
   * Signing out stops it and forgets the room: the next account to sign in
   * gets its own backlog rather than the last one's.
   */
  setSignedIn(signedIn: boolean): void {
    if (signedIn === this.polling) {
      return;
    }
    this.polling = signedIn;
    clearTimeout(this.timer);
    if (!signedIn) {
      this.shown.clear();
      this.fetchedTo = 0;
      this.log.replaceChildren();
      return;
    }
    void this.poll();
  }

  /**
   * A line a script sent with `ChatSend`.
   *
   * It is already rendered and already accepted by the server, so this only
   * has to place it and remember the id.
   */
  sent(id: number, text: string): void {
    if (this.shown.has(id)) {
      return;
    }
    this.shown.add(id);
    // Always the player's own, and never an emote: `ChatSend` is the
    // original's, which only ever sent a PRIVMSG. `/me` is the chat box's.
    this.append(text, "own");
    if (this.view) {
      this.mirror(text);
    }
  }

  /** `ChatView` from a script. */
  setView(enabled: boolean): void {
    this.view = enabled;
  }

  /** Send whatever is in the box. */
  private async say(): Promise<void> {
    const typed = this.input.value;
    if (typed.trim() === "") {
      return;
    }
    this.input.value = "";
    this.remember(typed.trim());
    try {
      const said = (await this.ask({ type: "chatSay", typed })) as Said;
      if (said.kind === "sent") {
        this.add([said.line], true);
      } else if (said.kind === "unknown") {
        // "Command not found." is the original's whole answer; naming the
        // word it did not know is the one thing added.
        this.complain(`Command not found: /${said.command}`);
      }
    } catch (err) {
      this.complain(`Could not say that: ${message(err)}`);
      // Put it back, so a message is not lost to a dropped connection.
      if (this.input.value === "") {
        this.input.value = typed;
      }
    }
  }

  /** Ask for everything newer than what is held, then queue the next ask. */
  private async poll(): Promise<void> {
    if (!this.polling || this.fetching) {
      return;
    }
    this.fetching = true;
    let delay = POLL_MS;
    try {
      const fetched = (await this.ask({
        type: "chatFetch",
        last: this.fetchedTo,
      })) as ChatLine[];
      this.add(fetched);
      for (const line of fetched) {
        this.fetchedTo = Math.max(this.fetchedTo, line.id);
      }
    } catch {
      // Signed out, or the server is unreachable. Either way, saying so
      // every two seconds would be worse than the silence.
      delay = POLL_MS_AFTER_FAILURE;
    } finally {
      this.fetching = false;
    }
    if (this.polling) {
      this.timer = setTimeout(() => void this.poll(), delay);
    }
  }

  /**
   * Place lines that have not been placed already.
   *
   * `own` marks a line this client just said, which is the one thing a
   * fetched line cannot tell you: the server names the account, and two
   * browsers signed into the same one would both be right to claim it.
   */
  private add(lines: ChatLine[], own = false): void {
    for (const line of lines) {
      if (this.shown.has(line.id)) {
        continue;
      }
      this.shown.add(line.id);
      const text = render(line);
      // An emote keeps its own colour whoever sent it, as in the original.
      this.append(text, line.action ? "emote" : own ? "own" : "said");
      if (this.view) {
        this.mirror(text);
      }
    }
  }

  private append(text: string, kind: "said" | "emote" | "own"): void {
    const row = document.createElement("div");
    row.className = `chat-line ${kind}`;
    row.textContent = text;
    this.log.append(row);
    while (this.log.childElementCount > SCROLLBACK) {
      this.log.firstElementChild?.remove();
    }
    // Only follow the bottom if that is where the reader already was, so
    // scrolling back to read something is not undone by the next line.
    const atBottom =
      this.log.scrollHeight - this.log.scrollTop - this.log.clientHeight < 40;
    if (atBottom) {
      this.log.scrollTop = this.log.scrollHeight;
    }
  }

  /** Push a typed line onto the history, as `IRCTxtList` does. */
  private remember(typed: string): void {
    this.history.unshift(typed);
    this.history.length = Math.min(this.history.length, HISTORY_LIMIT);
    this.historyAt = -1;
  }

  /**
   * Up and Down through what was typed before.
   *
   * The original puts a trailing space on a recalled line, which is what
   * lets `/msg someone` be finished rather than edited. That is kept.
   */
  private walkHistory(e: KeyboardEvent): void {
    if (e.key !== "ArrowUp" && e.key !== "ArrowDown") {
      return;
    }
    e.preventDefault();
    const step = e.key === "ArrowUp" ? 1 : -1;
    const next = this.historyAt + step;
    if (next < -1 || next >= this.history.length) {
      return;
    }
    this.historyAt = next;
    const recalled = this.history[next];
    this.input.value = next === -1 || recalled === undefined ? "" : `${recalled} `;
    this.input.setSelectionRange(this.input.value.length, this.input.value.length);
  }
}

/** `<who>  text`, or `* who text` for an emote, as the original wrote them. */
function render(line: ChatLine): string {
  return line.action ? `* ${line.from} ${line.text}` : `<${line.from}>  ${line.text}`;
}

function message(err: unknown): string {
  return err instanceof Error ? err.message : String(err);
}
