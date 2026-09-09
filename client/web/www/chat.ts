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
import { draggable, manage } from "./window.js";

// How often to ask for new lines, which depends on who is looking.
//
// The read is answered before `chat.php` includes `function.php`, so it
// costs a query and not a password check -- which is the difference between
// a second's latency being affordable and not. `function.php` authenticates
// at include time with bcrypt, around 130ms of CPU at the cost factor in
// use, and `pm.max_children` is 5 for the whole site; a poll paying that
// could not be run at this rate by more than a handful of players.
//
// Cheap is not free, so it still only asks when somebody is reading the
// answer: the pane is up, or `ChatView` is mirroring the room into the comm
// log. A tab in the background is nobody.

/** The pane is up and the tab is in front. */
const POLL_WATCHING = 1000;

/** The pane is away but `ChatView` is mirroring into the comm log. */
const POLL_MIRRORING = 5000;

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

  private timer: number | undefined;
  /** Set while a fetch is out, so a slow one does not stack up behind it. */
  private fetching = false;
  /**
   * Set once the opening backlog is in.
   *
   * Until then nothing is mirrored: the backlog is a hundred lines, and
   * `ChatView` turned on before the first fetch would otherwise empty all of
   * them into the comm log at once. The original had no backlog to mirror --
   * it saw the room only from the moment it joined.
   */
  private caughtUp = false;

  /**
   * Whether incoming chat is mirrored to the communications log.
   *
   * This is `ChatView`, and it is not the pane's visibility: the original
   * keeps it in `chatToStatus` and F5 shows the pane regardless of it.
   */
  view = false;

  readonly log: HTMLElement;
  readonly input: HTMLInputElement;
  readonly submit: HTMLButtonElement;

  constructor(
    readonly root: HTMLElement,
    readonly ask: Ask,
    /** Called for each new line while `view` is on. */
    readonly mirror: (text: string) => void,
    /** Called with the client's own complaints, which go to the comm log. */
    readonly complain: (text: string) => void,
  ) {
    manage(root, {
      // Off to one side rather than over the middle of the console: the room
      // is watched while something else is being done, which is the whole
      // reason it is a window now.
      rect: (desk) => ({
        x: Math.max(desk.left + 12, desk.right - 12 - 30 * 16),
        y: Math.max(desk.top + 12, desk.bottom - 12 - 26 * 16),
        w: Math.min(30 * 16, desk.right - desk.left - 24),
        h: Math.min(26 * 16, desk.bottom - desk.top - 24),
      }),
      min: { w: 260, h: 180 },
      close: () => this.hide(),
    });
    draggable(root, root.querySelector(".win-bar") as HTMLElement);

    this.log = root.querySelector(".chat-log") as HTMLElement;
    this.input = root.querySelector(".chat-input") as HTMLInputElement;
    this.submit = root.querySelector(".chat-send") as HTMLButtonElement;

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

    // A backgrounded tab is not being read, so it stops asking. Coming back
    // asks at once, and the fetch is incremental, so the wait costs nothing
    // but the lines arriving together.
    document.addEventListener("visibilitychange", () => this.restart());

    // Signed out until told otherwise, which is what the page starts as.
    this.setSignedIn(false);
  }

  get visible(): boolean {
    return !this.root.hidden;
  }

  /**
   * How long until the next ask, or `null` when there is nobody to ask for.
   *
   * A hidden tab is nobody: the fetch is incremental, so whatever is said
   * meanwhile arrives in one piece when the player comes back.
   */
  private interval(): number | null {
    if (document.hidden) {
      return null;
    }
    if (this.visible) {
      return POLL_WATCHING;
    }
    return this.view ? POLL_MIRRORING : null;
  }

  /**
   * Reconsider the cadence, and ask straight away if it just became worth
   * asking.
   *
   * Called whenever the answer to `interval` can have changed -- the pane
   * opening or closing, `ChatView`, the tab coming forward -- so opening the
   * pane shows what was said while it was away rather than waiting a beat
   * for the next tick.
   */
  private restart(): void {
    clearTimeout(this.timer);
    this.timer = undefined;
    if (this.interval() !== null) {
      void this.poll();
    }
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
    this.restart();
  }

  hide(): void {
    this.root.hidden = true;
    this.restart();
  }

  /**
   * Say whether there is an account.
   *
   * Reading does not need one -- `chat.php?action=read` is public, as
   * `chatlog.php` has always been -- so this gates the box and nothing
   * else. Signing out neither empties the room nor stops the reading:
   * there is nothing here that `chatlog.php` would not show to anyone.
   */
  setSignedIn(signedIn: boolean): void {
    this.input.disabled = !signedIn;
    this.submit.disabled = !signedIn;
    this.input.placeholder = signedIn
      ? "Say something, or /me does something"
      : "Sign in to join the conversation";
    this.restart();
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
    // Turning it on is a reason to poll with the pane away, and turning it
    // off may be the last reason to poll at all.
    this.restart();
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
    if (this.fetching || this.interval() === null) {
      return;
    }
    this.fetching = true;
    let failed = false;
    try {
      const fetched = (await this.ask({
        type: "chatFetch",
        last: this.fetchedTo,
      })) as ChatLine[];
      this.add(fetched);
      for (const line of fetched) {
        this.fetchedTo = Math.max(this.fetchedTo, line.id);
      }
      this.caughtUp = true;
    } catch {
      // Signed out, or the server is unreachable. Either way, saying so
      // every second would be worse than the silence.
      failed = true;
    } finally {
      this.fetching = false;
    }
    // Asked again from the top: the pane may have been put away, or the tab
    // sent to the back, while the fetch was out.
    const next = this.interval();
    if (next !== null) {
      this.timer = setTimeout(
        () => void this.poll(),
        failed ? POLL_MS_AFTER_FAILURE : next,
      );
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
      // The opening backlog is not news, so it is not mirrored; what the
      // player just said is, however early it happens.
      if (this.view && (this.caughtUp || own)) {
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
