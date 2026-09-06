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

import { ConsoleView, CommView } from "./console.js";
import { MailWindow } from "./mail.js";

const READY = 1;
const CLOSED = 2;

/** Room for one line of input. */
const INPUT_CAPACITY = 8192;

/** As many as the original client has, and the same F-keys select them. */
const CONSOLE_COUNT = 4;

/** The script each console opens with, following `Start_Console`. */
const STARTUP_SCRIPT = "/system/startup.ds";
const NEW_CONSOLE_SCRIPT = "/system/newconsole.ds";

const comm = new CommView(document.getElementById("comm"));
const mail = new MailWindow(document.getElementById("mail"), (request) => ask(request));
const container = document.getElementById("consoles");
const tabs = document.getElementById("tabs");
const template = document.getElementById("console-template");
const statusDot = document.getElementById("status-dot");
const statusText = document.getElementById("status-text");

if (!crossOriginIsolated) {
  comm.add(
    "This page is not cross-origin isolated, so scripts cannot read input. " +
      "It needs Cross-Origin-Opener-Policy: same-origin and " +
      "Cross-Origin-Embedder-Policy: require-corp.",
  );
}

/** Reflect the connection in the title bar. */
function setStatus(text, state) {
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
  constructor(id) {
    this.id = id;

    const fragment = template.content.cloneNode(true);
    this.root = fragment.querySelector(".console");
    this.entry = this.root.querySelector(".entry");
    this.prompt = this.root.querySelector(".prompt");
    this.input = this.root.querySelector(".input");
    this.root.setAttribute("aria-label", `Console ${id}`);
    this.input.setAttribute("aria-label", `Console ${id} input`);
    container.append(this.root);

    this.view = new ConsoleView(this.root, this.entry);

    // One control block and one buffer per console, so a line typed here
    // wakes this worker and no other.
    this.control = new Int32Array(
      new SharedArrayBuffer(2 * Int32Array.BYTES_PER_ELEMENT),
    );
    this.inputBytes = new Uint8Array(new SharedArrayBuffer(INPUT_CAPACITY));

    /** Set while the worker is blocked waiting for a line. */
    this.awaitingInput = false;
    /** Set while a command is running, so a second is not started. */
    this.busy = false;
    this.cwd = "/";

    this.worker = new Worker("./worker.js", { type: "module" });
    this.worker.onmessage = (e) => handleMessage(this, e.data);

    this.input.addEventListener("keydown", (e) => this.onKeyDown(e));
  }

  post(message) {
    this.worker.postMessage(message);
  }

  /**
   * Set the text beside the caret.
   *
   * The console draws `prompt & " "`, so the space belongs to the client
   * rather than to whatever asked -- a script that prompts with "Name>" still
   * gets one.
   */
  setPromptText(text) {
    this.prompt.textContent = text === "" ? "" : `${text} `;
  }

  setPrompt(cwd) {
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
  showEntry(visible) {
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

  /** Take the caret, but only when this console is the one on screen. */
  focus() {
    if (this.root.classList.contains("active") && !this.input.disabled) {
      // Without `preventScroll` the browser drags the prompt into view,
      // which throws away the place a console was left at when it is
      // switched back to. Whether to scroll is `showEntry`'s decision.
      this.input.focus({ preventScroll: true });
    }
  }

  /** Hand a typed line to the worker that is blocked waiting for one. */
  deliverInput(text) {
    const encoded = new TextEncoder().encode(text);
    const length = Math.min(encoded.length, INPUT_CAPACITY);
    this.inputBytes.set(encoded.subarray(0, length));
    Atomics.store(this.control, 1, length);
    Atomics.store(this.control, 0, READY);
    Atomics.notify(this.control, 0);
    this.awaitingInput = false;
  }

  /** Tell a blocked worker that no more input is coming. */
  closeInput() {
    Atomics.store(this.control, 0, CLOSED);
    Atomics.notify(this.control, 0);
    this.awaitingInput = false;
  }

  onKeyDown(e) {
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
      this.view.echo(this.prompt.textContent, line, true);
      this.showEntry(false);
      this.deliverInput(line);
      return;
    }
    if (this.busy) {
      return;
    }

    this.view.echo(this.prompt.textContent, line, false);
    if (line.trim() === "") {
      return;
    }
    this.busy = true;
    this.showEntry(false);
    this.post({ type: "command", line });
  }

  /** Run a script from the player's filesystem, the way a command does. */
  runFile(path) {
    this.busy = true;
    this.showEntry(false);
    this.post({ type: "runFile", path });
  }
}

const consoles = [];
for (let id = 1; id <= CONSOLE_COUNT; id += 1) {
  consoles.push(new GameConsole(id));
}

/** The console on screen; the other three keep running out of sight. */
let active = null;

function setActive(target) {
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
  const tab = document.createElement("button");
  tab.className = "tab";
  tab.type = "button";
  tab.textContent = String(item.id);
  tab.setAttribute("role", "tab");
  tab.title = `Console ${item.id} (F${item.id})`;
  tab.addEventListener("click", () => setActive(item));
  item.tab = tab;
  tabs.append(tab);
}

window.addEventListener("keydown", (e) => {
  const match = /^F([1-4])$/.exec(e.key);
  if (!match || e.ctrlKey || e.altKey || e.metaKey || mail.open) {
    return;
  }
  // F1 and F3 are the browser's otherwise; in a console they are the client's.
  e.preventDefault();
  setActive(consoles[Number(match[1]) - 1]);
});

setActive(consoles[0]);

// ---- asking a worker ----------------------------------------------------
//
// The page has questions of its own now -- the mail window's, and whatever
// comes after it. They have to be answered by a worker, because that is where
// the credentials and the connection are, so they go to whichever console is
// free. A console blocked on `ReadLine` is not free: its worker is parked in
// `Atomics.wait` and would not read the message until someone typed.

/** In-flight questions, by the token that identifies each answer. */
const asked = new Map();
/** Questions with no free console yet, in the order they were asked. */
const waiting = [];
let nextToken = 1;

function ask(request) {
  return new Promise((resolve, reject) => {
    const token = nextToken;
    nextToken += 1;
    asked.set(token, { resolve, reject });
    waiting.push({ ...request, token });
    dispatchAsked();
  });
}

/** Hand out as many waiting questions as there are free consoles to take them. */
function dispatchAsked() {
  while (waiting.length > 0) {
    const free = consoles.find((c) => !c.busy && !c.awaitingInput);
    if (!free) {
      return;
    }
    free.post(waiting.shift());
  }
}

function settleAsked(token, value, error) {
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

/** Messages from one console's worker. */
function handleMessage(target, message) {
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
      // All four are told; only one need say so.
      if (target.id === 1) {
        setStatus(`You are online as ${pendingUser}.`, "online");
        comm.add(`You have been authorized as ${pendingUser}.`);
        comm.add("Welcome to the Dark Signs Network!");
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
          other.post({
            type: "syncFile",
            path: message.path,
            contents: message.contents,
          });
        }
      }
      break;

    case "missingFile":
      comm.add(`${message.path} is missing; the client bundle may be incomplete.`);
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

    case "mail":
      settleAsked(message.token, message.view);
      break;

    case "mailSent":
      settleAsked(message.token);
      break;

    case "mailFailed":
      settleAsked(message.token, null, message.message);
      break;
  }
}

function renderEvent(target, event) {
  switch (event.kind) {
    case "line":
      // The communications channel is one panel for the whole client, not
      // one per console.
      if (event.channel === "comm") {
        comm.add(event.runs.map((r) => r.text).join(""));
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
    case "mail":
      // `MAIL` opens the reader. Unlike the original it does not hold the
      // script up while the window is open: the worker that raised this is
      // the one still running the script, and blocking it would leave
      // nothing able to answer the window's own requests.
      mail.show();
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
function measureLayout() {
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

function reportLayout() {
  const layout = measureLayout();
  for (const item of consoles) {
    item.post({ type: "layout", ...layout });
  }
}

// A resized window changes what fits on a line, which is what scripts lay
// their columns out against.
new ResizeObserver(reportLayout).observe(container);

let readyCount = 0;
let storageReport = null;

/**
 * Everything is up: sign in if we can, then open the four consoles.
 *
 * The credentials go first so that a restored session is already authorized
 * by the time `startup.ds` runs -- it calls `LOGIN` and prints the player's
 * name, neither of which works before then.
 */
function allReady() {
  if (!storageReport.persistent) {
    comm.add("Storage is unavailable; this session will not be saved.");
  } else if (storageReport.restored > 0) {
    comm.add(`Restored ${storageReport.restored} saved file(s).`);
  }

  const saved = loadSavedCredentials();
  if (saved) {
    document.getElementById("username").value = saved.username;
    document.getElementById("remember").checked = true;
    signIn(saved.username, saved.password);
  }

  // `Start_Console`: the first console runs the startup script, which ends
  // by including the new-console banner; the rest run that banner directly.
  for (const item of consoles) {
    item.runFile(item.id === 1 ? STARTUP_SCRIPT : NEW_CONSOLE_SCRIPT);
  }
}

// Start the workers with the shared buffers and the commands the shell needs.
async function boot() {
  const files = await loadStartupFiles();
  const layout = measureLayout();
  for (const item of consoles) {
    item.post({
      type: "boot",
      consoleId: item.id,
      control: item.control.buffer,
      input: item.inputBytes.buffer,
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
async function loadStartupFiles() {
  const files = {};
  try {
    const manifest = await fetch("./scripts/manifest.json").then((r) => r.json());
    await Promise.all(
      manifest.map(async (path) => {
        const response = await fetch(`./scripts${path}`);
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

function loadSavedCredentials() {
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

function saveCredentials(username, password) {
  try {
    localStorage.setItem(CREDENTIALS_KEY, JSON.stringify({ username, password }));
  } catch {
    comm.add("Could not save your sign-in; this browser refused storage.");
  }
}

function forgetCredentials() {
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
function signIn(username, password) {
  pendingUser = username;
  for (const item of consoles) {
    item.post({ type: "credentials", username, password });
  }
  setStatus(`Signing in as ${username}...`, "connecting");
}

document.getElementById("login").addEventListener("submit", (e) => {
  e.preventDefault();
  const username = document.getElementById("username").value.trim();
  const password = document.getElementById("password").value;
  if (!username || !password) {
    return;
  }
  if (document.getElementById("remember").checked) {
    saveCredentials(username, password);
  } else {
    forgetCredentials();
  }
  signIn(username, password);
  // The password is handed to the workers and forgotten here.
  document.getElementById("password").value = "";
  active.focus();
});

boot();
