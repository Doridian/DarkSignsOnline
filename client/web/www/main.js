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

const view = new ConsoleView(document.getElementById("output"));
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
    case "ready":
      setPrompt(message.cwd);
      comm.add("Welcome to Dark Signs Delta.");
      if (!message.persistent) {
        comm.add("Storage is unavailable; this session will not be saved.");
      } else if (message.restored > 0) {
        comm.add(`Restored ${message.restored} saved file(s).`);
      }
      runStartup();
      break;

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
      // being treated as a new command.
      awaitingInput = true;
      input.disabled = false;
      input.focus();
      break;

    case "done":
      busy = false;
      awaitingInput = false;
      setPrompt(message.cwd);
      input.disabled = false;
      input.focus();
      break;

    case "error":
      view.system(message.message, "error");
      busy = false;
      awaitingInput = false;
      if (message.cwd) setPrompt(message.cwd);
      input.disabled = false;
      input.focus();
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

function setPrompt(cwd) {
  prompt.textContent = `${cwd ?? "/"}>`;
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
    // Echo it, since the script asked for it rather than the shell.
    view.system(line, "echo");
    deliverInput(line);
    return;
  }
  if (busy) {
    return;
  }

  view.system(`${prompt.textContent} ${line}`, "echo");
  if (line.trim() === "") {
    return;
  }
  busy = true;
  input.disabled = true;
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

document.getElementById("login").addEventListener("submit", (e) => {
  e.preventDefault();
  pendingUser = document.getElementById("username").value.trim();
  const password = document.getElementById("password").value;
  if (!pendingUser || !password) {
    return;
  }
  worker.postMessage({ type: "credentials", username: pendingUser, password });
  // The password is handed to the worker and forgotten here.
  document.getElementById("password").value = "";
  setStatus(`Signing in as ${pendingUser}...`, "connecting");
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
  input.disabled = true;
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
