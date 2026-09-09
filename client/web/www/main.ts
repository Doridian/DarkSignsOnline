// The page.
//
// It owns the display and the keyboard, and hands work to the workers. The
// only subtle part is input: a worker blocks on `Atomics.wait`, so a typed
// line is written into a SharedArrayBuffer and the worker is woken.
//
// A terminal is a window with a worker behind it, and there are as many as
// the player opens -- one to begin with, another every time `Terminal` is
// pressed. They cannot share a worker: a console blocked in `ReadLine`
// blocks its whole worker, and the others have to stay usable. What they do
// share -- the player's files -- is not shared at all any more: there is one
// filesystem, in a worker of its own, and every terminal asks it. Nothing on
// this page keeps copies of a tree in step, because there are no copies.

import { ChatPanel } from "./chat.js";
import { CommView, ConsoleView } from "./console.js";
import {
  ABORT,
  ANSWER_CAPACITY,
  CLOSED,
  CONTROL_SLOTS,
  DRAWING,
  FS_ANSWER_CAPACITY,
  LENGTH,
  READY,
  STATE,
} from "./control.js";
import { Editors } from "./editor.js";
import { Explorers, FileModel, PATH_DRAG, quotePath } from "./filetree.js";
import { LibraryWindow } from "./library.js";
import { MailWindow } from "./mail.js";
import { MusicPlayer } from "./music.js";
import { taskbar } from "./taskbar.js";
import type { Asked, ConsoleEvent, FromFs, FromWorker, FsAsk, ToWorker } from "./types.js";
import { centred, draggable, focusedWindow, manage, raise, unmanage } from "./window.js";

/** The script each console opens with, following `Start_Console`. */
const STARTUP_SCRIPT = "/system/startup.ds";
const NEW_CONSOLE_SCRIPT = "/system/newconsole.ds";

/** How far each terminal opens down and right of the one already there. */
const CASCADE = 26;

/** How many terminals the cascade steps through before starting over. */
const CASCADE_STEPS = 6;

const comm = new CommView(element("comm-log"));
const desktopHint = element("desktop-hint");
const statusDot = element("status-dot");
const statusText = element("status-text");
const account = element("account");
const accountLabel = element("account-label");
const accountUser = element("account-user");
const accountMenu = element("account-menu");
const accountToggle = element("account-toggle") as HTMLButtonElement;
const logoutButton = element("logout") as HTMLButtonElement;

// The communications log. It has no module of its own -- `CommView` only
// appends lines -- so its window is set up here.
const commWindow = element("comm");
manage(commWindow, {
  // Top right, out of the way of the prompt, which is where a console starts
  // writing.
  rect: (desk) => ({
    x: Math.max(desk.left + 12, desk.right - 12 - 30 * 16),
    y: desk.top + 12,
    w: Math.min(30 * 16, desk.right - desk.left - 24),
    h: Math.min(10 * 16, desk.bottom - desk.top - 24),
  }),
  min: { w: 240, h: 90 },
  close: () => showComm(false),
});
draggable(commWindow, commWindow.querySelector(".win-bar") as HTMLElement);

const mail = new MailWindow(dialog("mail"), (request) => ask(request));
const library = new LibraryWindow(dialog("library"), (request) => ask(request));
// The editors. There is one window per file being edited, made when the
// file is opened, so they are not in the page to begin with and are added to
// it here. An editor runs what it was editing in the console that opened it,
// which is only possible when that console is not already busy.
const editors = new Editors(document.body, (request) => ask(request), (id, path) => {
  // The terminal it was opened from, if that one is still open; otherwise
  // whichever is in front, since a script has to run somewhere visible.
  const target = consoles.find((item) => item.id === id) ?? active;
  if (!target || target.busy || target.awaitingInput) {
    return false;
  }
  setActive(target, true);
  target.view.echo(target.prompt.textContent ?? "", path, false);
  target.runFile(path);
  return true;
});

/**
 * The filesystem, which is a worker of its own.
 *
 * It owns the tree and it is the only thing that touches storage. Every
 * terminal asks it over a port of its own; this page asks it here, for the
 * explorers, the editors and whatever is about to play a song.
 */
const fsWorker = new Worker("./fsworker.js", { type: "module" });

/** Settles when the tree has been read and the first terminal can open. */
let fsReadyResolve: (report: { persistent: boolean; restored: number }) => void = () => {};
const fsStarted = new Promise<{ persistent: boolean; restored: number }>((resolve) => {
  fsReadyResolve = resolve;
});

/** Questions put to the filesystem, by the token each answer comes back with. */
const askedFs = new Map<number, { resolve: (v: any) => void; reject: (e: Error) => void }>();

/**
 * Ask the filesystem something.
 *
 * Unlike a console, it is never busy: it holds the tree in memory and
 * answers straight away, so these are not queued behind anything.
 */
function askFs(request: FsAsk, transfer: Transferable[] = []): Promise<any> {
  return new Promise((resolve, reject) => {
    const token = nextToken;
    nextToken += 1;
    askedFs.set(token, { resolve, reject });
    fsWorker.postMessage({ type: "ask", token, ...request }, transfer);
  });
}

fsWorker.onmessage = (e: MessageEvent<FromFs>) => {
  const message = e.data;
  switch (message.type) {
    case "fsReady":
      fsReadyResolve(message);
      break;

    // Whatever any terminal did to the tree. This is the only reason the
    // explorers do not have to poll: the worker that made the change says
    // so, and every open window redraws from the one model.
    case "changed":
      for (const change of message.changes) {
        files.apply(change);
      }
      break;

    case "answer": {
      const promise = askedFs.get(message.token);
      askedFs.delete(message.token);
      promise?.resolve(message.value);
      break;
    }

    case "failed": {
      const promise = askedFs.get(message.token);
      askedFs.delete(message.token);
      promise?.reject(new Error(message.message));
      break;
    }
  }
};

/** The questions the filesystem answers rather than a console. */
const FS_ASKS = new Set([
  "listTree",
  "listFiles",
  "readFile",
  "writeFile",
  "fileAt",
  "putFile",
]);

// The filesystem as the page sees it, read through `ask` like the windows
// do and kept up afterwards from what the fs worker reports as it changes.
// One copy, however many explorers are looking at it.
const files = new FileModel((request) => ask(request));

// The explorers themselves, of which `Files` opens one per press.
const explorers = new Explorers(
  document.body,
  files,
  // Double-clicking a file opens it where `EDIT` would, in the terminal in
  // front -- so running it from the editor runs it somewhere visible.
  (path) => void editors.openFile(path, active?.id ?? 0),
  (text) => comm.add(text),
);

// `Music`. It asks the filesystem for the file at a path and plays it; the
// bytes never come through here, only a handle on them.
const music = new MusicPlayer((request) => ask(request), (text) => comm.add(text));

// Chat. It polls and sends through `ask`, the same way mail does, because
// that is where the credentials are. Both callbacks end at the comm log:
// `ChatView` mirrors the room into it, and the panel's own complaints are
// client messages, which is what that log is for.
const chat = new ChatPanel(
  element("chat"),
  (request) => ask(request),
  (text) => comm.add(text),
  (text) => comm.add(text),
);

if (!crossOriginIsolated) {
  comm.add(
    "This page is not cross-origin isolated, so scripts cannot read input. " +
      "It needs Cross-Origin-Opener-Policy: same-origin and " +
      "Cross-Origin-Embedder-Policy: require-corp.",
  );
}

/** One of the page's own elements, which are all in `index.html`. */
function element(id: string): HTMLElement {
  const found = document.getElementById(id);
  if (!found) {
    throw new Error(`the page is missing #${id}`);
  }
  return found;
}

function dialog(id: string): HTMLDialogElement {
  return element(id) as HTMLDialogElement;
}

function field(id: string): HTMLInputElement {
  return element(id) as HTMLInputElement;
}

/** Reflect the connection in the title bar. */
function setStatus(text: string, state: "offline" | "connecting" | "online"): void {
  statusText.textContent = text;
  statusDot.className = state;
}

/**
 * One terminal: a window, a worker, the log it writes to, and the line being
 * typed.
 *
 * The state that used to be page-wide -- whether a command is running,
 * whether a script is waiting for input, what is half-typed at the prompt --
 * all belongs here, since every other terminal has to be left exactly as it
 * was whatever this one is doing.
 */
class GameConsole {
  /** The window, which is what is dragged, resized and closed. */
  readonly window: HTMLElement;
  /** The log inside it, which is what scrolls and what scripts measure. */
  readonly root: HTMLElement;
  readonly entry: HTMLElement;
  readonly prompt: HTMLElement;
  readonly input: HTMLInputElement;
  readonly view: ConsoleView;
  /** The control block and the line buffer, both shared with the worker. */
  readonly control: Int32Array<SharedArrayBuffer>;
  readonly answerBytes: Uint8Array<SharedArrayBuffer>;
  /**
   * The same again for the filesystem, which is a different worker.
   *
   * Two channels rather than one because two different workers answer on
   * them, and a console waiting for a typed line must not be woken by a
   * directory listing.
   */
  readonly fsControl: Int32Array<SharedArrayBuffer>;
  readonly fsAnswer: Uint8Array<SharedArrayBuffer>;
  readonly fsChannel = new MessageChannel();
  readonly worker: Worker;
  /**
   * Set once the worker has its wasm up and will answer a message.
   *
   * A terminal is a window before it is a session: it can be opened, and
   * signed in behind, in the time its worker takes to fetch and start the
   * interpreter. Anything sent before then is refused by the worker, so
   * nothing is -- the credentials and the opening script both wait for the
   * `ready` this sets.
   */
  ready = false;
  /** Set while the worker is blocked waiting for a line. */
  awaitingInput = false;
  /** Set while a command is running, so a second is not started. */
  busy = false;
  /**
   * Set between Ctrl+B and the `done` that answers it.
   *
   * A script can outrun the page by a long way -- a loop that writes a line
   * a turn posts them far faster than they can be drawn -- so by the time the
   * stop reaches the worker there may be a great deal of already-sent output
   * still queued. Rendering it all would show the script carrying on for
   * seconds after it had actually stopped, which is what it looks like from
   * the outside: the same counter, still counting. So output for a console
   * that has been stopped is dropped rather than drawn.
   */
  stopping = false;
  /**
   * The frame that will let the worker say more, once one is arranged.
   *
   * A script outruns the page by a wide margin, so one of them has to wait
   * for the other. The one that waits is the script: the worker holds its
   * output until this console has drawn what it was last given and shown it,
   * and that is what a frame does here. Nothing is queued on this side at
   * all, which is what makes a frame the terminal as it stands rather than a
   * position in a backlog seconds deep.
   */
  private frame = 0;
  private releasing = false;
  /**
   * What paces this console while the page is in the background.
   *
   * Frames stop there and scripts do not, so the worker would hold output
   * for a frame that is not coming and park for good. A message to itself is
   * what the page has that still runs: unlike a timer it is not throttled to
   * one a second, so a console out of sight keeps drawing at the speed it is
   * written to, and comes back with nothing to catch up on.
   */
  private readonly ticker = new MessageChannel();
  cwd = "/";

  /**
   * `id` is what scripts read as `ConsoleID`, and `offset` is how far this
   * window opens from where a terminal was last left.
   */
  constructor(readonly id: number, offset: number) {
    const source = document.getElementById("terminal-template");
    const root =
      source instanceof HTMLTemplateElement
        ? source.content.firstElementChild?.cloneNode(true)
        : null;
    if (!(root instanceof HTMLElement)) {
      throw new Error("the terminal's template is missing");
    }
    this.window = root;
    this.root = root.querySelector(".console") as HTMLElement;
    this.entry = this.root.querySelector(".entry") as HTMLElement;
    this.prompt = this.root.querySelector(".prompt") as HTMLElement;
    this.input = this.root.querySelector(".input") as HTMLInputElement;
    (root.querySelector(".win-title") as HTMLElement).textContent = `Terminal ${id}`;
    root.setAttribute("aria-label", `Terminal ${id}`);
    this.input.setAttribute("aria-label", `Terminal ${id} input`);
    document.body.append(root);

    // Shown before it is managed, rather than after as the explorers are:
    // the manager places a window that is already visible there and then,
    // and the width it is placed at is what this worker is booted with. Left
    // to the observer that notices a window appearing, the placement would
    // land a microtask after the boot message had gone with the width of an
    // unplaced window.
    root.hidden = false;
    manage(root, {
      rect: (desk) => centred(desk, 60 * 16, 34 * 16),
      min: { w: 360, h: 180 },
      // One geometry for all of them, as the editors and the explorers
      // have: a terminal sized to suit the screen is the size the next one
      // wants too, and the offset is what keeps them off each other.
      store: "terminal",
      offset,
      // Escape belongs to whatever is running: a terminal holds a session
      // rather than a view of one, and closing it throws the session away.
      dismissable: false,
    });
    draggable(root, root.querySelector(".win-bar") as HTMLElement);
    (root.querySelector(".win-close") as HTMLElement).addEventListener("click", () =>
      this.destroy(),
    );
    // Whatever the pointer or the keyboard went on to do, this is now the
    // terminal the client's own keys act on. Neither takes the caret: the
    // click may be the start of a selection in the log, and a `focusin` is
    // something already having taken it.
    root.addEventListener("pointerdown", () => setActive(this), true);
    root.addEventListener("focusin", () => setActive(this));

    this.view = new ConsoleView(this.root, this.entry);

    // One control block and one buffer per console, so a line typed here
    // wakes this worker and no other.
    this.control = new Int32Array(
      new SharedArrayBuffer(CONTROL_SLOTS * Int32Array.BYTES_PER_ELEMENT),
    );
    this.answerBytes = new Uint8Array(new SharedArrayBuffer(ANSWER_CAPACITY));
    this.fsControl = new Int32Array(
      new SharedArrayBuffer(2 * Int32Array.BYTES_PER_ELEMENT),
    );
    this.fsAnswer = new Uint8Array(new SharedArrayBuffer(FS_ANSWER_CAPACITY));
    // The filesystem answers into this console's buffer, so it needs both
    // ends: the port to be asked on and the memory to reply through.
    fsWorker.postMessage(
      {
        type: "attach",
        consoleId: id,
        port: this.fsChannel.port2,
        control: this.fsControl.buffer,
        answer: this.fsAnswer.buffer,
      },
      [this.fsChannel.port2],
    );

    this.worker = new Worker("./worker.js", { type: "module" });
    this.worker.onmessage = (e: MessageEvent<FromWorker>) => handleMessage(this, e.data);
    this.ticker.port1.onmessage = () => this.releaseWorker();

    // A resized window changes what fits on a line, which is what scripts
    // lay their columns out against.
    layoutWatch.observe(this.root);

    // The filesystem is up before any terminal is made, so this can start
    // now rather than waiting to be told to.
    this.post(
      {
        type: "boot",
        consoleId: id,
        control: this.control.buffer,
        answer: this.answerBytes.buffer,
        fsPort: this.fsChannel.port1,
        fsControl: this.fsControl.buffer,
        fsAnswer: this.fsAnswer.buffer,
        ...measure(this),
      },
      [this.fsChannel.port1],
    );

    this.input.addEventListener("keydown", (e) => this.onKeyDown(e));
    this.root.addEventListener("click", (e) => this.onClick(e));

    // A name dragged out of the file tree types its path here. The whole
    // console takes the drop, not just the input: the input is one line at
    // the end of a tall log, and aiming at it is not what the gesture means.
    this.root.addEventListener("dragover", (e) => this.onDragOver(e));
    this.root.addEventListener("dragleave", () => this.root.classList.remove("drop-target"));
    this.root.addEventListener("drop", (e) => this.onDrop(e));
  }

  /** Whether a drag is carrying a path from the file tree. */
  static carriesPath(transfer: DataTransfer | null): boolean {
    return transfer !== null && Array.from(transfer.types).includes(PATH_DRAG);
  }

  onDragOver(event: DragEvent): void {
    // Only the tree's own drags, and only while there is a prompt to type
    // at: a running script is not listening, and a file dragged in from the
    // desktop belongs on a folder in the tree rather than here.
    if (!GameConsole.carriesPath(event.dataTransfer) || this.input.disabled) {
      return;
    }
    event.preventDefault();
    if (event.dataTransfer) {
      event.dataTransfer.dropEffect = "copy";
    }
    this.root.classList.add("drop-target");
  }

  onDrop(event: DragEvent): void {
    this.root.classList.remove("drop-target");
    if (!GameConsole.carriesPath(event.dataTransfer) || this.input.disabled) {
      return;
    }
    // Without this the browser drops the text into the input itself as
    // well, and the path is typed twice.
    event.preventDefault();
    const path = event.dataTransfer?.getData(PATH_DRAG) ?? "";
    if (path !== "") {
      this.pastePath(path);
    }
  }

  /**
   * Type a path at the prompt, where the caret is.
   *
   * A space goes in front of it when the line does not already end in one,
   * since the gesture is nearly always dropping an argument after a command
   * that has just been typed.
   */
  pastePath(path: string): void {
    const text = quotePath(path);
    const start = this.input.selectionStart ?? this.input.value.length;
    const end = this.input.selectionEnd ?? start;
    const before = this.input.value.slice(0, start);
    const after = this.input.value.slice(end);
    const lead = before === "" || /\s$/.test(before) ? "" : " ";
    this.input.value = before + lead + text + after;
    const caret = (before + lead + text).length;
    // A path dropped here is aimed at this console, so it takes the caret
    // even out of the window it was dragged from.
    this.focus(true);
    this.input.setSelectionRange(caret, caret);
  }

  post(message: ToWorker, transfer: Transferable[] = []): void {
    this.worker.postMessage(message, transfer);
  }

  /**
   * Set the text beside the caret.
   *
   * The console draws `prompt & " "`, so the space belongs to the client
   * rather than to whatever asked -- a script that prompts with "Name>" still
   * gets one.
   */
  setPromptText(text: string): void {
    this.prompt.textContent = text === "" ? "" : `${text} `;
  }

  setPrompt(cwd?: string): void {
    this.cwd = cwd ?? this.cwd;
    this.prompt.classList.remove("script");
    this.setPromptText(`${this.cwd}>`);
  }

  /**
   * Show or hide the input line.
   *
   * A terminal shows no caret while it is not listening, and the line has to
   * stay at the end of the log so that typing continues where the text does.
   */
  showEntry(visible: boolean): void {
    this.entry.classList.toggle("idle", !visible);
    if (visible) {
      this.root.append(this.entry);
      this.input.disabled = false;
      this.focus();
      this.view.scrollToBottom();
    } else {
      this.input.disabled = true;
    }
  }

  /**
   * A click anywhere in the log puts the caret back at the prompt, the way a
   * terminal does -- except when the click just selected something, since
   * taking the caret would collapse a selection about to be copied.
   */
  onClick(event: MouseEvent): void {
    const target = event.target as Element | null;
    // Whatever the console draws that handles its own clicks keeps them.
    if (target?.closest("a, button, input, textarea, select")) {
      return;
    }
    // A click collapses any selection there was, so one still standing here
    // is the one this click made: a drag across the log, or a double-click.
    const selection = window.getSelection();
    if (selection && !selection.isCollapsed) {
      return;
    }
    this.focus(true);
  }

  /**
   * Take the caret, but only when this is the terminal being used.
   *
   * A script asking for a line is what usually calls this, and it can happen
   * at any moment in a terminal nobody is looking at -- so it takes the
   * keyboard neither out of another terminal nor out of a window someone is
   * typing in. While the windows were modal the browser refused that; now
   * that they are not, refusing it is this. `force` is for the cases that
   * are the player's own doing -- clicking the log, dropping a path on it,
   * bringing the window to the front -- where taking the keyboard back is
   * the whole point.
   */
  focus(force = false): void {
    if (!force && (active !== this || typingInPanel())) {
      return;
    }
    if (!this.input.disabled) {
      // Without `preventScroll` the browser drags the prompt into view,
      // which throws away wherever the log was left when a terminal is
      // clicked back into. Whether to scroll is `showEntry`'s decision.
      this.input.focus({ preventScroll: true });
    }
  }

  /**
   * Hand a typed line to the worker that is blocked waiting for one.
   */
  deliverInput(text: string): void {
    const encoded = new TextEncoder().encode(text);
    const length = Math.min(encoded.length, ANSWER_CAPACITY);
    this.answerBytes.set(encoded.subarray(0, length));
    Atomics.store(this.control, LENGTH, length);
    Atomics.store(this.control, STATE, READY);
    Atomics.notify(this.control, STATE);
    this.awaitingInput = false;
  }

  /** Tell a blocked worker that no more input is coming. */
  closeInput(): void {
    Atomics.store(this.control, STATE, CLOSED);
    Atomics.notify(this.control, STATE);
    this.awaitingInput = false;
  }

  /**
   * Stop whatever is running here, which is what Ctrl+B does.
   *
   * The flag is what reaches the worker: it is running the script, so it is
   * not reading messages, and shared memory is the only thing it can be told
   * anything through. The interpreter picks the flag up between two
   * statements -- never inside a host call, so a write or a request that is
   * already under way finishes rather than being torn in half -- and ends
   * the script from there. `done` comes back as it would from any other
   * ending, and puts the prompt back.
   *
   * A console parked on `ReadLine` is waiting rather than running, so it is
   * also woken: without that, the flag would not be looked at until someone
   * typed the line the script is no longer going to use.
   */
  stop(): void {
    // Already asked and not yet answered: saying so twice would put the
    // notice on the console twice.
    if ((!this.busy && !this.awaitingInput) || this.stopping) {
      return;
    }
    this.stopping = true;
    Atomics.store(this.control, ABORT, 1);
    // A worker parked waiting for this console to draw is woken as well: it
    // would otherwise not look at the stop until the wait timed out. What it
    // was holding is dropped rather than sent, there and here both, since
    // drawing it would show the script running on after it ended.
    this.releaseWorker();
    this.input.value = "";
    this.showEntry(false);
    // Unconditionally, not only when this console is known to be waiting:
    // the worker may have parked on a `ReadLine` whose `wantInput` is still
    // in the queue, in which case nothing here knows it is waiting yet and
    // it would park until someone typed a line the script no longer wants.
    // Waking a worker that was not parked costs nothing -- the next read
    // stores over the state before it waits on it.
    this.closeInput();
    this.view.system("Script Stopped by User (CTRL + B)", "stopped");
  }

  /**
   * Draw a batch of console output, all of it, now.
   *
   * There is nothing to schedule: the worker sends one batch and waits, so
   * what arrives here is everything said since the last frame and drawing it
   * is what makes the next frame current. A batch is drawn as one -- the
   * scroll is held to the end of it, since reading `scrollHeight` lays the
   * whole log out and doing that once a line is what a hundred lines cost a
   * hundred times over.
   */
  drawBatch(events: ConsoleEvent[]): void {
    // Not for a console that has been stopped: this was said before the stop
    // reached the worker, and drawing it now would show a script that has
    // already ended still running. See `GameConsole.stopping`.
    if (!this.stopping) {
      this.view.holdScroll = true;
      try {
        for (const event of events) {
          renderEvent(this, event);
        }
      } finally {
        this.view.holdScroll = false;
      }
      this.view.scrollToBottom();
    }
    // Drawn or dropped, the worker is waiting on this console either way.
    this.scheduleRelease();
  }

  /**
   * Let the worker say more on the next frame.
   *
   * On the frame rather than here, because a frame is the whole of the
   * pacing: what the next batch holds is what was said between this frame
   * and that one, so the frame after it draws the terminal as it then
   * stands. Released any sooner and the worker would be free to run ahead of
   * the display again, which is the backlog this is here to prevent.
   */
  private scheduleRelease(): void {
    if (this.releasing) {
      return;
    }
    this.releasing = true;
    if (document.hidden) {
      this.ticker.port2.postMessage(0);
    } else {
      this.frame = requestAnimationFrame(() => {
        this.frame = 0;
        this.releaseWorker();
      });
    }
  }

  /**
   * A frame that is not coming: hand the release to the ticker instead.
   *
   * Called when the tab goes away with one arranged. Without it the worker
   * would hold its output for a frame the browser has stopped producing,
   * and a script writing to a hidden console would stop where it stood.
   */
  releaseOnTicker(): void {
    if (!this.releasing || this.frame === 0) {
      return;
    }
    cancelAnimationFrame(this.frame);
    this.frame = 0;
    this.ticker.port2.postMessage(0);
  }

  /** Say that what the worker sent has been drawn, waking it if it parked. */
  releaseWorker(): void {
    if (this.frame !== 0) {
      cancelAnimationFrame(this.frame);
      this.frame = 0;
    }
    this.releasing = false;
    Atomics.store(this.control, DRAWING, 0);
    Atomics.notify(this.control, DRAWING);
  }

  /** Ready this console to run something, forgetting the last stop. */
  clearStop(): void {
    this.stopping = false;
    Atomics.store(this.control, ABORT, 0);
    // Nothing of the last run is left to draw -- whatever it said has been
    // drawn or dropped -- so the next one starts free to speak rather than
    // waiting on a frame for output nobody is holding.
    this.releaseWorker();
  }

  onKeyDown(e: KeyboardEvent): void {
    // Ctrl+B is handled for the whole window: the input is disabled while a
    // script runs, and a disabled field is sent no keys at all.
    if (e.key !== "Enter") {
      return;
    }
    e.preventDefault();
    const line = this.input.value;
    this.input.value = "";

    if (this.awaitingInput) {
      // The script asked, so the echo keeps its prompt and the answer
      // together.
      this.view.echo(this.prompt.textContent ?? "", line, true);
      this.showEntry(false);
      this.deliverInput(line);
      return;
    }
    if (this.busy) {
      return;
    }

    this.view.echo(this.prompt.textContent ?? "", line, false);
    if (line.trim() === "") {
      return;
    }
    this.busy = true;
    this.showEntry(false);
    // Cleared here rather than in the worker: a Ctrl+B pressed after this
    // point is meant for the command about to run, and the worker would not
    // reach the message that carries it until the run was over.
    this.clearStop();
    this.post({ type: "command", line });
  }

  /**
   * Run a script from the player's filesystem, the way a command does.
   */
  runFile(path: string): void {
    this.busy = true;
    this.showEntry(false);
    this.clearStop();
    this.post({ type: "runFile", path });
  }

  /**
   * Close this terminal and throw it away.
   *
   * Whatever it was running goes with it. The worker is terminated rather
   * than asked to stop: a stop is a courtesy to a console that is going to
   * carry on afterwards, and there is nothing here left to print to. The
   * filesystem is told as well, since the port and the buffers this console
   * shared with it are reachable from nowhere else.
   */
  destroy(): void {
    this.worker.terminate();
    fsWorker.postMessage({ type: "detach", consoleId: this.id });
    if (this.frame !== 0) {
      cancelAnimationFrame(this.frame);
    }
    this.ticker.port1.close();
    this.ticker.port2.close();
    layoutWatch.unobserve(this.root);
    unmanage(this.window);
    this.window.remove();
    forget(this);
  }
}

/** Every open terminal, oldest first. */
const consoles: GameConsole[] = [];

/**
 * How many have been opened, which is what the cascade counts.
 *
 * Not how many are open, as the editors count: counting the open ones would
 * drop a new terminal exactly onto one that outlived an earlier one.
 */
let opened = 0;

/**
 * The terminal the client's own keys act on: `Ctrl+B`, and where a file
 * opened from an explorer is run. It is the last one touched rather than the
 * front window, since the front window is as often an editor.
 */
let active: GameConsole | null = null;

/** Open one, which is what `Terminal` does and what the client does once. */
function openTerminal(): GameConsole {
  // Clear of the last one, and back to the top once enough have been opened,
  // so the cascade cannot walk a window off the desktop.
  const item = new GameConsole(freeConsoleId(), (opened % CASCADE_STEPS) * CASCADE);
  opened += 1;
  consoles.push(item);
  desktopHint.hidden = true;
  setActive(item, true);
  return item;
}

/**
 * The lowest number no open terminal is using.
 *
 * Reused rather than counted up, because scripts print it: `ConsoleID` is
 * what the opening banner says, and a player with three terminals open
 * expects them to be 1, 2 and 3 however many have been closed on the way.
 */
function freeConsoleId(): number {
  let id = 1;
  while (consoles.some((item) => item.id === id)) {
    id += 1;
  }
  return id;
}

/** Drop a terminal that has been closed, and hand on what it was holding. */
function forget(item: GameConsole): void {
  const at = consoles.indexOf(item);
  if (at !== -1) {
    consoles.splice(at, 1);
  }
  // Its worker is gone, so anything it was asked is never coming back. The
  // questions go to the back of nothing and the front of the queue: they
  // were asked before whatever is still waiting.
  requeue(item);
  desktopHint.hidden = consoles.length > 0;
  if (active === item) {
    active = null;
    const next = consoles[consoles.length - 1];
    if (next) {
      setActive(next, true);
    }
  }
}

/**
 * Make a terminal the one in front, and the one the client's keys act on.
 *
 * `takeFocus` is for the cases that are the player's own doing -- opening
 * one, or picking it with a function key. A click inside one does not take
 * the caret here: it may be the start of a selection in the log, and the
 * log's own click handler is what decides.
 */
function setActive(target: GameConsole, takeFocus = false): void {
  active = target;
  for (const other of consoles) {
    other.window.classList.toggle("active", other === target);
  }
  raise(target.window);
  if (takeFocus) {
    target.focus(true);
  }
}

/** Whether the keyboard is in a window that is not a terminal. */
function typingInPanel(): boolean {
  const el = focusedWindow();
  return el !== null && !el.classList.contains("terminal");
}

// Frames stop while the page is in the background, which is where the
// workers are waiting for one. Each console hands its pending release to a
// task instead, so a script writing to a terminal nobody is looking at keeps
// running rather than stopping where it stood.
document.addEventListener("visibilitychange", () => {
  if (!document.hidden) {
    return;
  }
  for (const item of consoles) {
    item.releaseOnTicker();
  }
});

window.addEventListener("keydown", (e) => {
  // Escape closes the account menu, as it does any menu, and gives the
  // keyboard back to the button that opened it.
  if (e.key === "Escape" && accountMenuOpen()) {
    e.preventDefault();
    showAccountMenu(false);
    accountToggle.focus();
    return;
  }
  // Ctrl+B stops the running script, as it does in the original client.
  // Listened for on the window rather than on the console's input, because
  // that input is disabled for as long as a script is running and a disabled
  // field is sent no keys -- which is exactly the case this is for. Not while
  // the keyboard is in a window: several can be open at once now, so what
  // matters is not whether one is up but whether one is being typed in.
  if (e.ctrlKey && !e.altKey && !e.metaKey && e.key.toLowerCase() === "b") {
    if (accountMenuOpen() || typingInPanel()) {
      return;
    }
    e.preventDefault();
    active?.stop();
    return;
  }
  const match = /^F([1-5])$/.exec(e.key);
  if (
    !match ||
    e.ctrlKey ||
    e.altKey ||
    e.metaKey ||
    // Raising a terminal would take the caret out of the sign-in fields, or
    // out of whichever window is being typed in.
    accountMenuOpen() ||
    typingInPanel()
  ) {
    return;
  }
  // F1 and F3 are the browser's otherwise; in a terminal they are the
  // client's.
  e.preventDefault();
  // F5 raises chat, as `ShowChat` does. It no longer puts it away on the way
  // to a terminal: chat is a window now and sits beside them rather than
  // over them, so raising one is no reason to close the room.
  if (match[1] === "5") {
    chat.toggle();
    return;
  }
  // F1-F4 pick a terminal by the number in its title, as they picked one of
  // the four in the original. That is the number scripts print as
  // `ConsoleID`, so it is the one to aim with; a terminal that is not open
  // is not opened by pressing it.
  const chosen = consoles.find((item) => item.id === Number(match[1]));
  if (chosen) {
    setActive(chosen, true);
  }
});

// The communications log. It is the one window that opens by default -- it
// is where the server's notices land, and a notice nobody was shown is a
// notice that did not happen -- so what is remembered is having closed it,
// which is done from its own bar rather than from the status bar.
const COMM_KEY = "darksigns.comm";

function showComm(open: boolean): void {
  commWindow.hidden = !open;
  try {
    localStorage.setItem(COMM_KEY, open ? "open" : "closed");
  } catch {
    // A private window refuses storage; the log just opens by default next
    // time, which is the state it ships in anyway.
  }
}

(commWindow.querySelector(".win-close") as HTMLButtonElement).addEventListener(
  "click",
  () => showComm(false),
);
try {
  commWindow.hidden = localStorage.getItem(COMM_KEY) === "closed";
} catch {
  // As above.
}

// The status bar. Every button there opens its app or brings it forward, and
// none of them closes anything: a window is closed from its own bar, where
// what is about to go is on screen to be looked at first. The two there can
// be several of drop a menu up when they have windows out -- which one, or
// another -- and open one straight away when they have none.
taskbar([
  {
    button: element("open-terminal"),
    another: "New terminal",
    // Oldest first, as `consoles` holds them, so a terminal keeps its place
    // in the menu for as long as it is open.
    instances: () =>
      consoles.map((item) => ({
        label: `Terminal ${item.id}`,
        el: item.window,
        // Not just raised: this is also the terminal the client's own keys
        // act on from here, which is what picking one out of a list means.
        show: () => setActive(item, true),
      })),
    launch: () => {
      openTerminal();
    },
  },
  {
    // The file explorer, which is the client's own rather than anything the
    // original had. Any number can be out at once -- two folders are often
    // wanted together -- so each is named in the menu by where it is
    // looking, which is the only thing that tells them apart.
    button: element("open-files"),
    another: "New file explorer",
    instances: () =>
      [...explorers.open].map((tree) => ({
        label: `Files: ${tree.current}`,
        el: tree.root,
        show: () => {
          raise(tree.root);
          tree.icons.focus();
        },
      })),
    launch: () => {
      explorers.create();
    },
  },
  {
    button: element("open-comm"),
    instances: () =>
      commWindow.hidden
        ? []
        : [{ label: "Communications", el: commWindow, show: () => raise(commWindow) }],
    launch: () => showComm(true),
  },
  {
    // The original raises chat with F5 alone. The button is here because a
    // function key is not the only way anyone should have to reach it; F5
    // still puts the room away again, as `ShowChat` does.
    button: element("open-chat"),
    instances: () =>
      chat.visible ? [{ label: "Chat", el: chat.root, show: () => chat.show() }] : [],
    launch: () => chat.show(),
  },
  {
    // The file library, which the original opens from a label on the console
    // rather than from a command. The status bar is where that label is here.
    button: element("open-library"),
    instances: () =>
      library.open
        ? [{ label: "File Library", el: library.root, show: () => void library.show() }]
        : [],
    launch: () => void library.show(),
  },
]);

// A file dragged in from the desktop and dropped anywhere but a folder in
// the tree would otherwise be opened by the browser, which navigates away
// from the client and throws every terminal's worth of session away with it.
// Refusing the drop outright is what says so, with the cursor, before it
// happens.
for (const kind of ["dragover", "drop"] as const) {
  window.addEventListener(kind, (event: DragEvent) => {
    const transfer = event.dataTransfer;
    const inTree = (event.target as Element | null)?.closest?.(".filetree");
    if (!inTree && transfer && Array.from(transfer.types).includes("Files")) {
      event.preventDefault();
      if (event.type === "dragover") {
        transfer.dropEffect = "none";
      }
    }
  });
}

// ---- asking a worker ----------------------------------------------------
//
// The page has questions of its own now -- the mail window's, and whatever
// comes after it. They have to be answered by a worker, because that is where
// the credentials and the connection are, so they go to whichever console is
// free. A console blocked on `ReadLine` is not free: its worker is parked in
// `Atomics.wait` and would not read the message until someone typed.
//
// Which console answered used to be nobody's business, since the four of
// them outlived every question. Now a terminal can be closed with one still
// out, so each question remembers where it went: a worker that is terminated
// answers nothing, and the question goes back in the queue rather than
// leaving whoever asked it waiting for ever. With no terminal open at all
// there is nothing to ask, and the queue is what holds the question until
// one is opened.

/** One question, from `ask` until it is answered or handed on. */
interface Question {
  /** What to send, which is the window's own shape plus the token. */
  request: Asked;
  /** The console it was handed to, if it has been handed to one yet. */
  at: GameConsole | null;
  resolve: (value: unknown) => void;
  reject: (err: Error) => void;
}

/** In-flight questions, by the token that identifies each answer. */
const asked = new Map<number, Question>();
/** Tokens with no free console yet, in the order they were asked. */
const waiting: number[] = [];
let nextToken = 1;

/** Ask whichever console is free, and resolve with its answer. */
function ask(request: { type: string } & Record<string, unknown>): Promise<any> {
  if (FS_ASKS.has(request.type)) {
    // A file, so it goes where the files are. The windows do not have to
    // know which worker holds what; this is the one place that does.
    // A `File` in here is not transferred: it is a handle on bytes already
    // on disk, and structured clone copies the handle rather than the song.
    const { type, ...rest } = request;
    return askFs({ ask: type, ...rest } as FsAsk);
  }
  return new Promise((resolve, reject) => {
    const token = nextToken;
    nextToken += 1;
    // The shape is the window's; only the token is added here, and only the
    // worker reads the rest of it.
    asked.set(token, { request: { ...request, token } as Asked, at: null, resolve, reject });
    waiting.push(token);
    dispatchAsked();
  });
}

/** Hand out as many waiting questions as there are free consoles to take them. */
function dispatchAsked(): void {
  while (waiting.length > 0) {
    const free = consoles.find((c) => c.ready && !c.busy && !c.awaitingInput);
    const token = waiting[0];
    if (!free || token === undefined) {
      return;
    }
    waiting.shift();
    const question = asked.get(token);
    if (!question) {
      continue;
    }
    question.at = free;
    free.post(question.request);
  }
}

/** Put whatever a closed terminal was asked back at the front of the queue. */
function requeue(from: GameConsole): void {
  const orphaned: number[] = [];
  for (const [token, question] of asked) {
    if (question.at === from) {
      question.at = null;
      orphaned.push(token);
    }
  }
  if (orphaned.length === 0) {
    return;
  }
  // Ahead of anything still waiting, and in the order they were asked, which
  // is the order the tokens are in.
  waiting.unshift(...orphaned.sort((a, b) => a - b));
  dispatchAsked();
}

function settleAsked(token: number, value?: unknown, error?: string): void {
  const promise = asked.get(token);
  if (!promise) {
    return;
  }
  asked.delete(token);
  if (error) {
    promise.reject(new Error(error));
  } else {
    promise.resolve(value);
  }
}

/** Messages from one console's worker. `target` is the console it came from. */
function handleMessage(target: GameConsole, message: FromWorker): void {
  switch (message.type) {
    case "ready":
      target.ready = true;
      target.setPrompt(message.cwd);
      // The first terminal of the session is the one that carries the
      // client's own startup: the saved sign-in, what storage had to say,
      // and the script that says all of it. Every one after it opens with
      // the banner alone.
      if (started) {
        // Whatever the player is signed in as. `newconsole.ds` prints
        // `Username`, so this has to be in before the script is.
        if (credentials.username !== "") {
          target.post({ type: "credentials", ...credentials });
        }
        target.runFile(NEW_CONSOLE_SCRIPT);
      } else {
        started = true;
        firstTerminal(target);
      }
      // A question asked while nothing was open to answer it -- chat polls
      // whether or not there is a terminal -- has been waiting for this.
      dispatchAsked();
      break;

    case "credentialsSet":
      // Every terminal is told, and so is every one opened afterwards; only
      // the first of them need say so -- and only when there is someone to
      // greet, since signing out clears the credentials by handing over an
      // empty pair the same way.
      if (!greeted && credentials.username !== "") {
        greeted = true;
        setStatus("Online.", "online");
        showAccount(credentials.username);
        comm.add(`You have been authorized as ${credentials.username}.`);
        comm.add("Welcome to the Dark Signs Network!");
        // The room can be read without an account; this is what opens the
        // box, as the original's connect-on-login did.
        chat.setSignedIn(true);
      }
      break;

    case "console":
      target.drawBatch(message.events);
      break;

    case "missingFile":
      comm.add(`${message.path} is missing; the client bundle may be incomplete.`);
      break;

    case "wantInput":
      // A request from before the stop, whose worker has already been told
      // no more input is coming. Showing the prompt would ask for a line
      // the script is not going to read.
      if (target.stopping) {
        break;
      }
      // The worker is parked; the next line typed goes to it rather than
      // being treated as a new command. Its prompt, if it asked with one,
      // belongs on the input line rather than on a line of its own.
      target.awaitingInput = true;
      target.prompt.classList.add("script");
      target.setPromptText(message.prompt ?? "");
      target.showEntry(true);
      break;

    case "done":
      target.busy = false;
      target.awaitingInput = false;
      target.stopping = false;
      target.setPrompt(message.cwd);
      target.showEntry(true);
      dispatchAsked();
      break;

    case "error":
      // A script that was stopped reports nothing: the notice is already on
      // the console, and what the worker is complaining about is whatever
      // the stop interrupted.
      if (!target.stopping) {
        target.view.system(message.message, "error");
      }
      target.busy = false;
      target.awaitingInput = false;
      target.stopping = false;
      target.setPrompt(message.cwd);
      target.showEntry(true);
      dispatchAsked();
      break;

    // The answer to something a window asked. Every request carries a token
    // and every answer brings it back, so which window gets it is not this
    // function's business.
    case "answer":
      settleAsked(message.token, message.value);
      break;

    case "failed":
      settleAsked(message.token, null, message.message);
      break;
  }
}

function renderEvent(target: GameConsole, event: ConsoleEvent): void {
  switch (event.kind) {
    case "line":
      // The communications channel is one panel for the whole client, not
      // one per console.
      if (event.channel === "comm") {
        comm.add(event.runs.map((run) => run.text).join(""));
      } else {
        target.view.line(event);
      }
      break;
    case "clear":
      target.view.clear();
      break;
    case "lineUp":
      target.view.lineUp();
      break;
    case "draw":
      target.view.draw(event);
      break;
    case "drawCustom":
      target.view.drawCustom(event);
      break;
    case "drawEven":
      target.view.drawEven(event);
      break;
    case "edit":
      // `EDIT` opens the editor. Like mail it does not hold the script up:
      // the worker that raised this is the one still running it, and it is
      // also the one the editor asks to read and write the file.
      void editors.openFile(event.path, target.id);
      break;
    case "mail":
      // `MAIL` opens the reader. Unlike the original it does not hold the
      // script up while the window is open: the worker that raised this is
      // the one still running the script, and blocking it would leave
      // nothing able to answer the window's own requests.
      mail.show();
      break;
    case "music":
      // `Music` plays what the player has put in the filesystem. It does not
      // hold the script up: a track runs for minutes and the script that
      // started it has other things to be doing.
      void music.run(event.command);
      break;
    case "chatView":
      // `ChatView` decides whether the room is mirrored into the comm log.
      // It does not raise the pane; F5 does that.
      chat.setView(event.enabled);
      break;
    case "chatSent":
      // `ChatSend` from a script. The worker has already sent it, so this
      // only places the line and remembers the id it was given.
      chat.sent(event.id, event.text);
      break;
    // The remaining events belong to parts of the client that do not exist
    // yet; showing them beats swallowing them.
    default:
      console.debug("unhandled console event", event);
  }
}

/**
 * The room one terminal's lines have for text, in CSS pixels.
 *
 * Scripts subtract `PreSpaceWidth` from `ConsoleWidth` to decide where a
 * column ends, so both have to be the page's real measurements rather than
 * a guess. They are read from the stylesheet so that only one place decides
 * them.
 *
 * One measurement no longer serves them all: a terminal is a window, and two
 * of them are hardly ever the same width. What a script laid out before its
 * window was dragged narrower stays as it was drawn -- the lines are already
 * on the screen and nothing redraws them -- which is what resizing a
 * terminal has always done to what is above the prompt.
 */
function measure(item: GameConsole): { width: number; preSpace: number } {
  const style = getComputedStyle(item.entry);
  const gutter = parseFloat(style.paddingLeft) || 0;
  const trailing = parseFloat(style.paddingRight) || 0;
  const preSpace =
    parseFloat(
      getComputedStyle(document.documentElement).getPropertyValue("--prespace"),
    ) || 0;
  return {
    width: Math.max(0, item.root.clientWidth - gutter - trailing),
    preSpace,
  };
}

function reportLayout(): void {
  for (const item of consoles) {
    item.post({ type: "layout", ...measure(item) });
  }
}

/**
 * Report the layout once things have stopped moving.
 *
 * Dragging an edge changes a terminal's width every frame, and each frame
 * would otherwise be a message carrying a measurement nothing will lay
 * anything out against. What a script wants is the width the drag ends at,
 * so only that one is sent -- and every terminal is told, since one message
 * each is cheaper than working out which of them the observer meant.
 */
let layoutTimer = 0;
function reportLayoutSoon(): void {
  clearTimeout(layoutTimer);
  layoutTimer = setTimeout(reportLayout, 120);
}

/** Watches every open terminal; each adds itself as it is made. */
const layoutWatch = new ResizeObserver(reportLayoutSoon);

/** Set once the first terminal has started, which happens once a session. */
let started = false;
/**
 * What the filesystem said about what it found, kept until the consoles are
 * up and there is somewhere to report it.
 */
let storageReport: { persistent: boolean; restored: number } | null = null;

/**
 * The first terminal is up: sign in if we can, then start it.
 *
 * The credentials go first so that a restored session is already authorized
 * by the time `startup.ds` runs -- it calls `LOGIN` and prints the player's
 * name, neither of which works before then.
 */
function firstTerminal(item: GameConsole): void {
  if (storageReport && !storageReport.persistent) {
    comm.add("Storage is unavailable; this session will not be saved.");
  } else if (storageReport && storageReport.restored > 0) {
    comm.add(`Restored ${storageReport.restored} saved file(s).`);
  }

  const saved = loadSavedCredentials();
  if (saved) {
    field("username").value = saved.username;
    field("remember").checked = true;
    signIn(saved.username, saved.password);
  }

  // `Start_Console`: the first terminal runs the startup script, which ends
  // by including the new-console banner. Every one opened after it runs that
  // banner directly.
  item.runFile(STARTUP_SCRIPT);

  // The first picture of the tree. Asked for after the startup script is
  // away, so it waits for a free console rather than making that one wait
  // for it; anything written in the meantime is reported and folded in. Read
  // whether or not a window is open, so the first explorer to be opened is
  // drawn immediately rather than after a request.
  void files.load();
}

// Start the filesystem, then the terminal that will be asking it things.
//
// In that order, and waited for: a console that started first would run its
// opening script against a tree that had not been read off disk yet, and
// would find none of the player's files. It is also what lets a terminal
// boot its own worker as it is made -- by the time one can be opened, the
// filesystem it attaches to is already up.
async function boot(): Promise<void> {
  fsWorker.postMessage({ type: "start", files: await loadStartupFiles() });
  storageReport = await fsStarted;
  // The one the client opens by itself. Everything after it is `Terminal`.
  openTerminal();
}

/**
 * Fetch the scripts that ship with the client.
 *
 * Handed to the filesystem, which is the only thing that holds a tree. They
 * are not saved: they come with the client and are refetched every load, so
 * an edit is saved over one and a delete lasts until the next load.
 */
async function loadStartupFiles(): Promise<Record<string, Uint8Array>> {
  const files: Record<string, Uint8Array> = {};
  try {
    // Each file's place in the game's filesystem, which is the name it is
    // seeded under, against the URL it is served at. The two differ because a
    // served name carries the hash of its contents -- see `stamp.ts`.
    const manifest: Record<string, string> = await fetch("./scripts/manifest.json").then((r) =>
      r.json(),
    );
    await Promise.all(
      Object.entries(manifest).map(async ([path, url]) => {
        const response = await fetch(url);
        if (response.ok) {
          // Bytes, not text. A shipped script is a file like any other, and
          // decoding it here would put the page's encoding in front of the
          // code page every other read goes through.
          files[path] = new Uint8Array(await response.arrayBuffer());
        }
      }),
    );
  } catch {
    // Running without the script bundle is fine; the shell still works.
  }
  return files;
}

/**
 * The sign-in every terminal is handed, and every one opened after it.
 *
 * The password stays here rather than being forgotten at the form, which is
 * what it used to be: a terminal opened an hour into a session has a worker
 * and a connection of its own, and it has to be authorized like the rest. It
 * is in memory only -- saving it is the checkbox's business, below.
 */
let credentials = { username: "", password: "" };

/** Whether this sign-in has been announced, so the next terminal does not
    announce it again. */
let greeted = false;

// Saved sign-in, when the player asked for it.
//
// This is localStorage rather than the filesystem the game's own files live
// in, because the form lives on this thread and a worker cannot reach
// localStorage at all -- and because a password is not a file.
// The password is stored as typed: there is nowhere to hide it from anyone
// with the browser, so the checkbox is the honest control and it defaults to
// off. Every access is guarded, since a private window throws on the way in.
const CREDENTIALS_KEY = "darksigns.credentials";

function loadSavedCredentials(): { username: string; password: string } | null {
  try {
    const raw = localStorage.getItem(CREDENTIALS_KEY);
    if (!raw) {
      return null;
    }
    const saved = JSON.parse(raw);
    return saved && saved.username && saved.password ? saved : null;
  } catch {
    return null;
  }
}

function saveCredentials(username: string, password: string): void {
  try {
    localStorage.setItem(CREDENTIALS_KEY, JSON.stringify({ username, password }));
  } catch {
    comm.add("Could not save your sign-in; this browser refused storage.");
  }
}

function forgetCredentials(): void {
  try {
    localStorage.removeItem(CREDENTIALS_KEY);
  } catch {
    // Nothing was saved, or storage is denied. Either way there is nothing
    // to clean up.
  }
}

/**
 * Hand every terminal the credentials and reflect them in the titlebar.
 *
 * Every one of them, because each has its own connection: they are separate
 * sessions that happen to belong to one player. So is every terminal opened
 * afterwards, which is why they are kept.
 */
function signIn(username: string, password: string): void {
  credentials = { username, password };
  greeted = false;
  for (const item of consoles) {
    // One still starting up is handed them when it reports `ready`, which
    // is also the first moment it could take them.
    if (item.ready) {
      item.post({ type: "credentials", username, password });
    }
  }
  // Not `as ${username}`: the bar is narrow on a phone, and the name is
  // about to appear on the other side of it anyway.
  setStatus("Signing in...", "connecting");
}

/**
 * Drop the credentials, here and in every worker.
 *
 * A sign-out is an empty pair sent the way a sign-in is: `Credentials` counts
 * as set only with both halves, so the sessions stop authorizing anything
 * they send. The player's files stay where they are -- signing out is not
 * the same as clearing them, which `reset` is.
 */
function signOut(): void {
  credentials = { username: "", password: "" };
  greeted = false;
  forgetCredentials();
  for (const item of consoles) {
    if (item.ready) {
      item.post({ type: "credentials", username: "", password: "" });
    }
  }
  // The username is left in the form to sign back in with; the password is
  // not, and neither is the standing offer to remember it.
  field("password").value = "";
  field("remember").checked = false;
  setStatus("Not signed in.", "offline");
  showAccount(null);
  // The original quits IRC on logout. Here the room stays readable -- it is
  // public, and `chatlog.php` shows it to anyone -- so all this closes is
  // the box you would say something in.
  chat.setSignedIn(false);
  comm.add("You have been signed out.");
  active?.focus();
}

/**
 * Show the title bar as it stands for `username`, or for nobody.
 *
 * Signed in there is nothing to type, so the form and the button holding it
 * give way to the name and the way out.
 */
function showAccount(username: string | null): void {
  accountUser.textContent = username ?? "";
  accountLabel.hidden = username === null;
  logoutButton.hidden = username === null;
  accountToggle.hidden = username !== null;
  if (username !== null) {
    showAccountMenu(false);
  }
}

/** Whether the menu is up, which is also what closes it on the next click. */
function accountMenuOpen(): boolean {
  return !accountMenu.hidden;
}

/** Open or close the menu the sign-in form lives in. */
function showAccountMenu(open: boolean): void {
  accountMenu.hidden = !open;
  accountToggle.setAttribute("aria-expanded", String(open));
  if (open) {
    // A remembered username outlives the sign-out that forgot its password,
    // so the caret goes to whichever field is still empty.
    const username = field("username");
    (username.value ? field("password") : username).focus();
  }
}

accountToggle.addEventListener("click", () => showAccountMenu(!accountMenuOpen()));
logoutButton.addEventListener("click", signOut);

// A click anywhere else closes the menu, the way a menu behaves. `pointerdown`
// rather than `click` so it closes before whatever was aimed at underneath.
document.addEventListener("pointerdown", (e) => {
  if (accountMenuOpen() && !account.contains(e.target as Node)) {
    showAccountMenu(false);
  }
});

element("login").addEventListener("submit", (e) => {
  e.preventDefault();
  const username = field("username").value.trim();
  const password = field("password").value;
  if (!username || !password) {
    return;
  }
  if (field("remember").checked) {
    saveCredentials(username, password);
  } else {
    forgetCredentials();
  }
  signIn(username, password);
  // Out of the form, where anyone walking past can read it. It is still in
  // `credentials`, which is where the next terminal gets it from.
  field("password").value = "";
  showAccountMenu(false);
  active?.focus();
});

boot();
