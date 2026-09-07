// The page.
//
// It owns the display and the keyboard, and hands work to the workers. The
// only subtle part is input: a worker blocks on `Atomics.wait`, so a typed
// line is written into a SharedArrayBuffer and the worker is woken.
//
// There are four consoles, as in the original client, and each has a worker
// of its own. They cannot share one: a console blocked in `ReadLine` blocks
// its whole worker, and the other three have to stay usable. What they do
// share -- the player's files -- is kept in step by passing every change
// through this page.

import { ChatPanel } from "./chat.js";
import { CommView, ConsoleView } from "./console.js";
import { ABSENT, CLOSED, ANSWER_CAPACITY, READY } from "./control.js";
import { EditorWindow } from "./editor.js";
import { FileTree, PATH_DRAG, quotePath, TOGGLED } from "./filetree.js";
import { LibraryWindow } from "./library.js";
import { MailWindow } from "./mail.js";
import { MusicPlayer } from "./music.js";
import { BlobStore } from "./storage.js";
import type { Asked, ConsoleEvent, FromWorker, ToWorker } from "./types.js";

/** As many as the original client has, and the same F-keys select them. */
const CONSOLE_COUNT = 4;

/** The script each console opens with, following `Start_Console`. */
const STARTUP_SCRIPT = "/system/startup.ds";
const NEW_CONSOLE_SCRIPT = "/system/newconsole.ds";

const comm = new CommView(element("comm"));
const container = element("consoles");
const tabs = element("tabs");
const template = element("console-template") as HTMLTemplateElement;
const statusDot = element("status-dot");
const statusText = element("status-text");
const account = element("account");
const accountLabel = element("account-label");
const accountUser = element("account-user");
const accountMenu = element("account-menu");
const accountToggle = element("account-toggle") as HTMLButtonElement;
const logoutButton = element("logout") as HTMLButtonElement;

const mail = new MailWindow(dialog("mail"), (request) => ask(request));
const library = new LibraryWindow(dialog("library"), (request) => ask(request));
// The editor runs what it was editing in the console that opened it, which
// is only possible when that console is not already busy with something.
const editor = new EditorWindow(dialog("editor"), (request) => ask(request), (id, path) => {
  const target = consoles[id - 1] ?? consoles[0];
  if (target.busy || target.awaitingInput) {
    return false;
  }
  setActive(target);
  target.view.echo(target.prompt.textContent ?? "", path, false);
  target.runFile(path);
  return true;
});

/** The windows that cover the console, so a key can tell whether one is up. */
const windows = [mail, library, editor];

/**
 * The bytes behind the tree's media files.
 *
 * The page needs its own handle on them for two reasons: it is what plays a
 * song or shows a picture, and it is what answers a console that has parked
 * itself waiting to read one -- a worker in that state cannot read anything
 * for itself.
 */
const blobs = await BlobStore.open();

// Without this the browser may evict the origin's storage under disk
// pressure, which for a player who has added a few albums is a real loss
// rather than a re-download of some scripts. It is asked for once, quietly:
// a refusal leaves everything working exactly as it did.
void navigator.storage?.persist?.().catch(() => false);

// The file tree, which sits beside the consoles rather than over them. It
// reads the filesystem through `ask` like the windows do, and keeps up
// afterwards from the change reports the page already relays between the
// four consoles.
const fileTree = new FileTree(
  element("filetree"),
  (request) => ask(request),
  // Double-clicking a file opens it where `EDIT` would, in the console on
  // screen -- so running it from the editor runs it somewhere visible.
  (path) => void editor.openFile(path, active.id),
  (text) => comm.add(text),
  blobs,
);

// `Music`. It reads the bytes out of the same store the panel writes them
// to, and asks a console what a path holds, since the tree is the worker's.
const music = new MusicPlayer(blobs, (request) => ask(request), (text) => comm.add(text));

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
 * One console: a worker, the log it writes to, and the line being typed.
 *
 * The state that used to be page-wide -- whether a command is running,
 * whether a script is waiting for input, what is half-typed at the prompt --
 * all belongs here, since switching consoles has to leave the other three
 * exactly as they were.
 */
class GameConsole {
  /** The tab in the status bar that selects this console. */
  tab = document.createElement("button");
  readonly root: HTMLElement;
  readonly entry: HTMLElement;
  readonly prompt: HTMLElement;
  readonly input: HTMLInputElement;
  readonly view: ConsoleView;
  /** The control block and the line buffer, both shared with the worker. */
  readonly control: Int32Array<SharedArrayBuffer>;
  readonly answerBytes: Uint8Array<SharedArrayBuffer>;
  readonly worker: Worker;
  /** Set while the worker is blocked waiting for a line. */
  awaitingInput = false;
  /** Set while a command is running, so a second is not started. */
  busy = false;
  cwd = "/";

  /** `id` is which of the four this is. */
  constructor(readonly id: number) {
    const fragment = template.content.cloneNode(true) as DocumentFragment;
    this.root = fragment.querySelector(".console") as HTMLElement;
    this.entry = this.root.querySelector(".entry") as HTMLElement;
    this.prompt = this.root.querySelector(".prompt") as HTMLElement;
    this.input = this.root.querySelector(".input") as HTMLInputElement;
    this.root.setAttribute("aria-label", `Console ${id}`);
    this.input.setAttribute("aria-label", `Console ${id} input`);
    container.append(this.root);

    this.view = new ConsoleView(this.root, this.entry);

    // One control block and one buffer per console, so a line typed here
    // wakes this worker and no other.
    this.control = new Int32Array(
      new SharedArrayBuffer(2 * Int32Array.BYTES_PER_ELEMENT),
    );
    this.answerBytes = new Uint8Array(new SharedArrayBuffer(ANSWER_CAPACITY));

    this.worker = new Worker("./worker.js", { type: "module" });
    this.worker.onmessage = (e: MessageEvent<FromWorker>) => handleMessage(this, e.data);

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
    this.focus();
    this.input.setSelectionRange(caret, caret);
  }

  post(message: ToWorker): void {
    this.worker.postMessage(message);
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
    this.focus();
  }

  /** Take the caret, but only when this console is the one on screen. */
  focus(): void {
    if (this.root.classList.contains("active") && !this.input.disabled) {
      // Without `preventScroll` the browser drags the prompt into view,
      // which throws away the place a console was left at when it is
      // switched back to. Whether to scroll is `showEntry`'s decision.
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
    Atomics.store(this.control, 1, length);
    Atomics.store(this.control, 0, READY);
    Atomics.notify(this.control, 0);
    this.awaitingInput = false;
  }

  /**
   * Hand a file's bytes to the worker that is blocked waiting for them.
   *
   * `null` says the bytes are gone, which is not the same as a file of no
   * bytes and has to be tellable from it -- the tree still lists the file,
   * so the console says so rather than printing nothing.
   */
  deliverBlob(bytes: Uint8Array | null): void {
    if (bytes === null) {
      Atomics.store(this.control, 1, ABSENT);
    } else {
      const length = Math.min(bytes.length, ANSWER_CAPACITY);
      this.answerBytes.set(bytes.subarray(0, length));
      Atomics.store(this.control, 1, length);
    }
    Atomics.store(this.control, 0, READY);
    Atomics.notify(this.control, 0);
  }

  /** Tell a blocked worker that no more input is coming. */
  closeInput(): void {
    Atomics.store(this.control, 0, CLOSED);
    Atomics.notify(this.control, 0);
    this.awaitingInput = false;
  }

  onKeyDown(e: KeyboardEvent): void {
    // Ctrl+B stops a script in the original client. It only reaches one that
    // is waiting for input: a script busy in a loop cannot be interrupted,
    // since the worker running it is not listening for anything.
    if (e.ctrlKey && e.key.toLowerCase() === "b") {
      e.preventDefault();
      if (this.awaitingInput) {
        this.view.system("Script Stopped by User (CTRL + B)", "stopped");
        this.input.value = "";
        this.showEntry(false);
        this.closeInput();
      }
      return;
    }
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
    this.post({ type: "command", line });
  }

  /**
   * Run a script from the player's filesystem, the way a command does.
   */
  runFile(path: string): void {
    this.busy = true;
    this.showEntry(false);
    this.post({ type: "runFile", path });
  }
}

const consoles: GameConsole[] = [];
for (let id = 1; id <= CONSOLE_COUNT; id += 1) {
  consoles.push(new GameConsole(id));
}

/** The console on screen; the other three keep running out of sight. */
let active: GameConsole = consoles[0] as GameConsole;

function setActive(target: GameConsole): void {
  active = target;
  for (const other of consoles) {
    const isActive = other === target;
    other.root.classList.toggle("active", isActive);
    other.tab.classList.toggle("active", isActive);
    other.tab.setAttribute("aria-selected", String(isActive));
  }
  // An inactive console is hidden but still laid out, so it keeps its scroll
  // position and its width -- which is what its scripts measure against.
  target.focus();
}

// The tabs, and the F1-F4 that select the same four consoles in the original.
for (const item of consoles) {
  const tab = item.tab;
  tab.className = "tab";
  tab.type = "button";
  tab.textContent = String(item.id);
  tab.setAttribute("role", "tab");
  tab.title = `Console ${item.id} (F${item.id})`;
  tab.addEventListener("click", () => setActive(item));
  tabs.append(tab);
}

window.addEventListener("keydown", (e) => {
  // Escape closes the account menu, as it does any menu, and gives the
  // keyboard back to the button that opened it.
  if (e.key === "Escape" && accountMenuOpen()) {
    e.preventDefault();
    showAccountMenu(false);
    accountToggle.focus();
    return;
  }
  const match = /^F([1-5])$/.exec(e.key);
  if (
    !match ||
    e.ctrlKey ||
    e.altKey ||
    e.metaKey ||
    // A console switch would take the caret out of the sign-in fields.
    accountMenuOpen() ||
    windows.some((w) => w.open)
  ) {
    return;
  }
  // F1 and F3 are the browser's otherwise; in a console they are the client's.
  e.preventDefault();
  // F5 raises chat, as `ShowChat` does. F1-F4 put it away again on their way
  // to a console, which is what the original's handlers do before switching.
  if (match[1] === "5") {
    chat.toggle();
    return;
  }
  chat.hide();
  const chosen = consoles[Number(match[1]) - 1];
  if (chosen) {
    setActive(chosen);
  }
});

setActive(consoles[0]);

// The file library, which the original opens from a label on the console
// rather than from a command. The status bar is where that label is here.
element("open-library").addEventListener("click", () => void library.show());

// The original raises chat with F5 alone. The button is here for the same
// reason the console tabs are: a phone has no function keys.
element("open-chat").addEventListener("click", () => chat.toggle());

// The file tree, which is the client's own rather than anything the original
// had. The switch says whether the panel is out, since the panel can also be
// put away from its own bar.
const filesButton = element("open-files");
filesButton.addEventListener("click", () => fileTree.toggle());
element("filetree").addEventListener(TOGGLED, (e) => {
  filesButton.setAttribute("aria-expanded", String((e as CustomEvent<boolean>).detail));
});
// Last, so the state it restores is reflected in the switch as well. This is
// before the page has been painted, so a panel left closed starts closed
// instead of sliding shut in front of whoever opened the client.
fileTree.restore();

// A file dragged in from the desktop and dropped anywhere but a folder in
// the tree would otherwise be opened by the browser, which navigates away
// from the client and throws four consoles' worth of session away with it.
// Refusing the drop outright is what says so, with the cursor, before it
// happens.
for (const kind of ["dragover", "drop"] as const) {
  window.addEventListener(kind, (event: DragEvent) => {
    const transfer = event.dataTransfer;
    const inTree = (event.target as Element | null)?.closest?.("#filetree");
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

/** In-flight questions, by the token that identifies each answer. */
const asked = new Map<
  number,
  { resolve: (value: unknown) => void; reject: (err: Error) => void }
>();
/** Questions with no free console yet, in the order they were asked. */
const waiting: Asked[] = [];
let nextToken = 1;

/** Ask whichever console is free, and resolve with its answer. */
function ask(request: { type: string } & Record<string, unknown>): Promise<any> {
  return new Promise((resolve, reject) => {
    const token = nextToken;
    nextToken += 1;
    asked.set(token, { resolve, reject });
    // The shape is the window's; only the token is added here, and only the
    // worker reads the rest of it.
    waiting.push({ ...request, token } as Asked);
    dispatchAsked();
  });
}

/** Hand out as many waiting questions as there are free consoles to take them. */
function dispatchAsked(): void {
  while (waiting.length > 0) {
    const free = consoles.find((c) => !c.busy && !c.awaitingInput);
    const question = waiting[0];
    if (!free || !question) {
      return;
    }
    waiting.shift();
    free.post(question);
  }
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
      target.setPrompt(message.cwd);
      // All four load the same saved tree, so one of them reports on it.
      if (target.id === 1) {
        storageReport = message;
      }
      readyCount += 1;
      if (readyCount === consoles.length) {
        allReady();
      }
      break;

    case "credentialsSet":
      // All four are told; only one need say so -- and only when there is
      // someone to greet, since signing out clears the credentials by
      // handing over an empty pair the same way.
      if (target.id === 1 && pendingUser !== "") {
        setStatus("Online.", "online");
        showAccount(pendingUser);
        comm.add(`You have been authorized as ${pendingUser}.`);
        comm.add("Welcome to the Dark Signs Network!");
        // The room can be read without an account; this is what opens the
        // box, as the original's connect-on-login did.
        chat.setSignedIn(true);
      }
      break;

    case "wasReset":
      if (target.id === 1) {
        comm.add("Saved files cleared. Reload to start fresh.");
      }
      break;

    case "console":
      renderEvent(target, message.event);
      break;

    case "fileChanged":
      // The other three hold their own copy of the tree; keep it in step.
      for (const other of consoles) {
        if (other !== target) {
          other.post({ type: "syncFile", change: message.change });
        }
      }
      // And so does the panel, which is why it never has to poll: whatever
      // any console does to the filesystem comes past here first.
      fileTree.apply(message.change);
      break;

    case "missingFile":
      comm.add(`${message.path} is missing; the client bundle may be incomplete.`);
      break;

    case "wantBlob":
      // The worker is parked and cannot read OPFS itself, so this side does
      // it and wakes it up. Nothing is awaited by the player: the console
      // that asked is the only thing waiting, and it asked to wait.
      void blobs
        .bytes(message.id, message.max)
        .catch(() => null)
        .then((bytes) => target.deliverBlob(bytes));
      break;

    case "wantInput":
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
      target.setPrompt(message.cwd);
      target.showEntry(true);
      dispatchAsked();
      break;

    case "error":
      target.view.system(message.message, "error");
      target.busy = false;
      target.awaitingInput = false;
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
      void editor.openFile(event.path, target.id);
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
 * The room a line has for text, in CSS pixels.
 *
 * Scripts subtract `PreSpaceWidth` from `ConsoleWidth` to decide where a
 * column ends, so both have to be the page's real measurements rather than
 * a guess. They are read from the stylesheet so that only one place decides
 * them.
 */
function measureLayout(): { width: number; preSpace: number } {
  const [first] = consoles;
  const style = getComputedStyle(first.entry);
  const gutter = parseFloat(style.paddingLeft) || 0;
  const trailing = parseFloat(style.paddingRight) || 0;
  const preSpace =
    parseFloat(
      getComputedStyle(document.documentElement).getPropertyValue("--prespace"),
    ) || 0;
  // All four panes are the same size, so one measurement serves them all.
  return {
    width: Math.max(0, first.root.clientWidth - gutter - trailing),
    preSpace,
  };
}

function reportLayout(): void {
  const layout = measureLayout();
  for (const item of consoles) {
    item.post({ type: "layout", ...layout });
  }
}

/**
 * Report the layout once things have stopped moving.
 *
 * A dragged window edge and the file tree's slide both change the console's
 * width every frame, and each frame would otherwise be four messages
 * carrying a measurement nothing will lay anything out against. What a
 * script wants is the width it ends at, so only that one is sent.
 */
let layoutTimer = 0;
function reportLayoutSoon(): void {
  clearTimeout(layoutTimer);
  layoutTimer = setTimeout(reportLayout, 120);
}

// A resized window changes what fits on a line, which is what scripts lay
// their columns out against.
new ResizeObserver(reportLayoutSoon).observe(container);

let readyCount = 0;
/**
 * What the first console said about the saved files, kept until all four are
 * up and there is somewhere to report it.
 */
let storageReport: { persistent: boolean; restored: number } | null = null;

/**
 * Everything is up: sign in if we can, then open the four consoles.
 *
 * The credentials go first so that a restored session is already authorized
 * by the time `startup.ds` runs -- it calls `LOGIN` and prints the player's
 * name, neither of which works before then.
 */
function allReady(): void {
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

  // `Start_Console`: the first console runs the startup script, which ends
  // by including the new-console banner; the rest run that banner directly.
  for (const item of consoles) {
    item.runFile(item.id === 1 ? STARTUP_SCRIPT : NEW_CONSOLE_SCRIPT);
  }

  // The panel's first picture of the tree. Asked for after the startup
  // scripts are away, so it waits for a free console rather than making
  // four of them wait for it; anything they write in the meantime is
  // reported and folded in.
  void fileTree.load();
}

// Start the workers with the shared buffers and the commands the shell needs.
async function boot(): Promise<void> {
  const files = await loadStartupFiles();
  const layout = measureLayout();
  for (const item of consoles) {
    item.post({
      type: "boot",
      consoleId: item.id,
      control: item.control.buffer,
      answer: item.answerBytes.buffer,
      ...layout,
      files,
    });
  }
}

/**
 * Fetch the scripts that ship with the client.
 *
 * Fetched once and handed to all four workers, since they seed the same tree
 * into four sessions.
 */
async function loadStartupFiles(): Promise<Record<string, string>> {
  const files: Record<string, string> = {};
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
          files[path] = await response.text();
        }
      }),
    );
  } catch {
    // Running without the script bundle is fine; the shell still works.
  }
  return files;
}

let pendingUser = "";

// Saved sign-in, when the player asked for it.
//
// This is localStorage rather than the IndexedDB the files use, because the
// form lives on this thread and a worker cannot reach localStorage at all.
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
 * Hand every console the credentials and reflect them in the titlebar.
 *
 * All four, because each has its own connection: they are separate sessions
 * that happen to belong to one player.
 */
function signIn(username: string, password: string): void {
  pendingUser = username;
  for (const item of consoles) {
    item.post({ type: "credentials", username, password });
  }
  // Not `as ${username}`: the bar is narrow on a phone, and the name is
  // about to appear on the other side of it anyway.
  setStatus("Signing in...", "connecting");
}

/**
 * Drop the credentials, here and in all four workers.
 *
 * A sign-out is an empty pair sent the way a sign-in is: `Credentials` counts
 * as set only with both halves, so the sessions stop authorizing anything
 * they send. The player's files stay where they are -- signing out is not
 * the same as clearing them, which `reset` is.
 */
function signOut(): void {
  pendingUser = "";
  forgetCredentials();
  for (const item of consoles) {
    item.post({ type: "credentials", username: "", password: "" });
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
  active.focus();
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
  // The password is handed to the workers and forgotten here.
  field("password").value = "";
  showAccountMenu(false);
  active.focus();
});

boot();
