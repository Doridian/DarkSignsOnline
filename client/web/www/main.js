// The page.
//
// It owns the display and the keyboard, and hands work to the worker. The
// only subtle part is input: the worker blocks on `Atomics.wait`, so a typed
// line is written into a SharedArrayBuffer and the worker is woken.

import { ConsoleView, CommView } from "./console.js";

const WAITING = 0;
const READY = 1;
const CLOSED = 2;

/** Room for one line of input. */
const INPUT_CAPACITY = 8192;

const entry = document.getElementById("entry");
const view = new ConsoleView(document.getElementById("output"), entry);
const comm = new CommView(document.getElementById("comm"));
const input = document.getElementById("input");
const prompt = document.getElementById("prompt");
const statusDot = document.getElementById("status-dot");
const statusText = document.getElementById("status-text");

/** Set while the worker is blocked waiting for a line. */
let awaitingInput = false;
/** Set while a command is running, so a second is not started. */
let busy = false;

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

const control = new Int32Array(new SharedArrayBuffer(2 * Int32Array.BYTES_PER_ELEMENT));
const inputBuffer = new SharedArrayBuffer(INPUT_CAPACITY);
const inputBytes = new Uint8Array(inputBuffer);

const worker = new Worker("./worker.js", { type: "module" });

worker.onmessage = (e) => {
  const message = e.data;
  switch (message.type) {
    case "ready": {
      setPrompt(message.cwd);
      comm.add("Welcome to Dark Signs Delta.");
      if (!message.persistent) {
        comm.add("Storage is unavailable; this session will not be saved.");
      } else if (message.restored > 0) {
        comm.add(`Restored ${message.restored} saved file(s).`);
      }
      // Before the startup script, so a restored session is already
      // authorized by the time anything it runs asks the server.
      const saved = loadSavedCredentials();
      if (saved) {
        document.getElementById("username").value = saved.username;
        document.getElementById("remember").checked = true;
        signIn(saved.username, saved.password);
      }
      runStartup();
      break;
    }

    case "credentialsSet":
      setStatus(`You are online as ${pendingUser}.`, "online");
      comm.add(`You have been authorized as ${pendingUser}.`);
      comm.add("Welcome to the Dark Signs Network!");
      break;

    case "wasReset":
      comm.add("Saved files cleared. Reload to start fresh.");
      break;

    case "console":
      renderEvent(message.event);
      break;

    case "wantInput":
      // The worker is parked; the next line typed goes to it rather than
      // being treated as a new command. Its prompt, if it asked with one,
      // belongs on the input line rather than on a line of its own.
      awaitingInput = true;
      prompt.classList.add("script");
      setPromptText(message.prompt ?? "");
      showEntry(true);
      break;

    case "done":
      busy = false;
      awaitingInput = false;
      setPrompt(message.cwd);
      showEntry(true);
      break;

    case "error":
      view.system(message.message, "error");
      busy = false;
      awaitingInput = false;
      setPrompt(message.cwd);
      showEntry(true);
      break;
  }
};

function renderEvent(event) {
  switch (event.kind) {
    case "line":
      // The communications channel has its own panel.
      if (event.channel === "comm") {
        comm.add(event.runs.map((r) => r.text).join(""));
      } else {
        view.line(event);
      }
      break;
    case "clear":
      view.clear();
      break;
    case "lineUp":
      view.lineUp();
      break;
    case "draw":
      view.draw(event);
      break;
    // The remaining events belong to parts of the client that do not exist
    // yet; showing them beats swallowing them.
    default:
      console.debug("unhandled console event", event);
  }
}

/**
 * Set the text beside the caret.
 *
 * The console draws `prompt & " "`, so the space belongs to the client rather
 * than to whatever asked -- a script that prompts with "Name>" still gets one.
 */
function setPromptText(text) {
  prompt.textContent = text === "" ? "" : `${text} `;
}

function setPrompt(cwd) {
  prompt.classList.remove("script");
  setPromptText(`${cwd ?? "/"}>`);
}

/**
 * Show or hide the input line.
 *
 * A terminal shows no caret while it is not listening, and the line has to
 * stay at the end of the log so that typing continues where the text does.
 */
function showEntry(visible) {
  entry.classList.toggle("idle", !visible);
  if (visible) {
    entry.parentElement.appendChild(entry);
    input.disabled = false;
    input.focus();
    view.scrollToBottom();
  } else {
    input.disabled = true;
  }
}

/** Hand a typed line to the worker that is blocked waiting for one. */
function deliverInput(text) {
  const encoded = new TextEncoder().encode(text);
  const length = Math.min(encoded.length, INPUT_CAPACITY);
  inputBytes.set(encoded.subarray(0, length));
  Atomics.store(control, 1, length);
  Atomics.store(control, 0, READY);
  Atomics.notify(control, 0);
  awaitingInput = false;
}

/** Tell a blocked worker that no more input is coming. */
export function closeInput() {
  Atomics.store(control, 0, CLOSED);
  Atomics.notify(control, 0);
  awaitingInput = false;
}

input.addEventListener("keydown", (e) => {
  if (e.key !== "Enter") {
    return;
  }
  e.preventDefault();
  const line = input.value;
  input.value = "";

  if (awaitingInput) {
    // The script asked, so the echo keeps its prompt and the answer together.
    view.echo(prompt.textContent, line, true);
    showEntry(false);
    deliverInput(line);
    return;
  }
  if (busy) {
    return;
  }

  view.echo(prompt.textContent, line, false);
  if (line.trim() === "") {
    return;
  }
  busy = true;
  showEntry(false);
  worker.postMessage({ type: "command", line });
});

// Start the worker with the shared buffers and the commands the shell needs.
async function boot() {
  const files = await loadStartupFiles();
  worker.postMessage({
    type: "boot",
    control: control.buffer,
    input: inputBuffer,
    width: 80,
    files,
  });
}

/**
 * Fetch the scripts that ship with the client.
 *
 * The real client keeps these in the player's directory; until that is
 * persisted, they are loaded fresh each time.
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

/** Hand the worker a set of credentials and reflect it in the titlebar. */
function signIn(username, password) {
  pendingUser = username;
  worker.postMessage({ type: "credentials", username, password });
  setStatus(`Signing in as ${username}...`, "connecting");
}

document.getElementById("login").addEventListener("submit", (e) => {
  e.preventDefault();
  pendingUser = document.getElementById("username").value.trim();
  const password = document.getElementById("password").value;
  if (!pendingUser || !password) {
    return;
  }
  if (document.getElementById("remember").checked) {
    saveCredentials(pendingUser, password);
  } else {
    forgetCredentials();
  }
  signIn(pendingUser, password);
  // The password is handed to the worker and forgotten here.
  document.getElementById("password").value = "";
  input.focus();
});

/**
 * Run the startup script, which paints the banner.
 *
 * It is a normal script, so anything it prints goes through the same path
 * as everything else.
 */
function runStartup() {
  busy = true;
  showEntry(false);
  worker.postMessage({ type: "script", source: STARTUP, args: [] });
}

// The shipped startup.ds logs in and opens a new console, neither of which
// makes sense before the player has signed in. This is the banner from it.
const STARTUP = String.raw`
Say ""
Draw -1, RGB(0, 0, 0), "solid"
Say "{{center courier_new 32}}"
Draw -1, RGB(60, 120, 60), "fadeinverse"
Say "{{center impact nobold 48 lyellow}}[{{|}}{{white impact nobold 48}} D A R K S I G N S {{|}}]{{lyellow impact nobold 48}}"
Draw -1, RGB(60, 120, 60), "fadecenter"
Say "ONLINE{{center impact nobold 84}}"
Draw -1, RGB(60, 120, 60), "fadecenter"
Say "{{center courier_new 8}}"
Draw -1, RGB(60, 120, 60), "fadeinverse"
Say "Type HELP for a list of commands.{{center courier_new 16}}"
Draw -1, RGB(60, 120, 60), "fadeinverse"
Say "{{center courier_new 8}}"
Draw -1, RGB(60, 120, 60), "fadeinverse"
Say ""
Draw -1, RGB(0, 0, 0), "solid"
Say ""
Say "It is " & Time & " on the " & Date & ".{{grey}}"
Say "You can EDIT this startup script file by typing: EDIT system\startup.ds{{lgrey}}"
Say ""
`;

// Tabs are drawn but not wired up: the session is single-console for now.
for (const tab of document.querySelectorAll(".tab")) {
  tab.addEventListener("click", () => {
    for (const other of document.querySelectorAll(".tab")) {
      other.classList.toggle("active", other === tab);
    }
    input.focus();
  });
}

boot();
