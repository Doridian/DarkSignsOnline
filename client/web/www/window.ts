// The window manager.
//
// Everything the client shows that is not a console is a window: the
// communications log, the file explorer, chat, mail, the editor and the
// library. They float over the consoles, they can be moved and resized, and
// several can be open at once -- which is the whole reason they are windows
// rather than panels, and the reason none of them is modal any more.
//
// A window is any element with `position: fixed` and the `window` class; the
// three that were `<dialog>` still are, because `open`, `close()` and the
// `close` event are a serviceable window API and their owners already use
// it. `show()` rather than `showModal()` is the only difference that
// matters: a modal dialog makes the rest of the page inert, and a desktop
// where opening the editor freezes chat is not a desktop.
//
// Geometry is `left`/`top`/`width`/`height` in pixels, set here and nowhere
// else. It could have been a transform over whatever the browser chose, and
// was while the windows were modal, but resizing from the top or the left
// edge moves a window as well as sizing it, and two mechanisms for where a
// window sits is one too many. What the stylesheet still decides is the
// default size, through the rect each window is registered with.
//
// The frame is what makes resizing work without a single extra element:
// every window carries `--win-frame` of padding, so the outermost few pixels
// are the window's own box rather than anything inside it, and a pointer
// there has `event.target === el`. That test is what tells a grab at the
// edge from a grab at a scrollbar sitting against it -- and it survives the
// three windows that rebuild their whole contents on every render, which
// appended resize handles would not.

/** How much of a window must stay within the desktop, in pixels. */
const MARGIN = 24;

/** How wide the resize border is. Matches `--win-frame` in the stylesheet. */
const FRAME = 6;

/** How close to a corner still counts as the corner rather than the edge. */
const CORNER = 20;

/** Where window geometry is remembered between visits. */
const STORE = "darksigns.window.";

export interface Rect {
  x: number;
  y: number;
  w: number;
  h: number;
}

/** The room windows have: the page without its title bar and status bar. */
export interface Desktop {
  left: number;
  top: number;
  right: number;
  bottom: number;
}

/**
 * A window of that size in the middle of the desktop.
 *
 * The size is what the window would like; a viewport too small for it gets
 * what there is. Most of the windows open here, since the middle is where a
 * window nobody has moved yet belongs.
 */
export function centred(desk: Desktop, w: number, h: number): Rect {
  const width = Math.min(w, desk.right - desk.left - 24);
  const height = Math.min(h, desk.bottom - desk.top - 24);
  return {
    w: width,
    h: height,
    x: desk.left + (desk.right - desk.left - width) / 2,
    y: desk.top + (desk.bottom - desk.top - height) / 2,
  };
}

export interface Options {
  /** The size and place a window takes when it has never been moved. */
  rect: (desk: Desktop) => Rect;
  /** How small it may be dragged, in pixels. */
  min?: { w: number; h: number };
  /** Windows that hold nothing worth resizing can say so. */
  resizable?: boolean;
  /** What Escape does. Defaults to closing it the way its own bar would. */
  close?: () => void;
}

interface Managed extends Options {
  el: HTMLElement;
  min: { w: number; h: number };
  resizable: boolean;
  /** Whether it has been given a place yet. Deferred until it is first shown:
      a window sized from a viewport it was never displayed in is centred on
      the wrong thing. */
  placed: boolean;
  /** Set once the player has moved or resized it, which stops the default
      rect from being applied again. */
  moved: boolean;
}

const managed = new Map<HTMLElement, Managed>();

/** The stacking order. Windows start above the page and climb from there. */
let top = 30;

/**
 * Register a window.
 *
 * Nothing is positioned yet -- that waits until it is first shown, which is
 * noticed here rather than announced by the caller, so opening a window is
 * still `dialog.show()` or `hidden = false` wherever it happens.
 */
export function manage(el: HTMLElement, options: Options): void {
  const win: Managed = {
    ...options,
    el,
    min: options.min ?? { w: 220, h: 120 },
    resizable: options.resizable ?? true,
    placed: false,
    moved: false,
  };
  managed.set(el, win);
  el.classList.add("window");

  // Raising is on pointerdown in the capture phase: whatever the pointer
  // went on to do, the window it was in is now the front one.
  el.addEventListener("pointerdown", () => raise(el), true);
  el.addEventListener("focusin", () => raise(el));

  if (win.resizable) {
    el.addEventListener("pointerdown", (event) => beginResize(win, event));
    el.addEventListener("pointermove", (event) => showEdge(win, event));
    el.addEventListener("pointerleave", () => {
      el.style.cursor = "";
    });
  }

  // `open` for the dialogs, `hidden` for the panels: either way the window
  // has just appeared and wants a place and the front of the stack.
  new MutationObserver(() => {
    if (visible(el)) {
      place(win);
      raise(el);
    }
  }).observe(el, { attributes: true, attributeFilter: ["open", "hidden"] });

  if (visible(el)) {
    place(win);
  }
}

/**
 * Let a window be dragged by a handle.
 *
 * Safe to call again with a replacement bar, which mail, the library and the
 * editor all do: they rebuild their title bar on every render, and the
 * window keeps where it was put because the geometry is the window's.
 */
export function draggable(el: HTMLElement, handle: HTMLElement): void {
  const win = managed.get(el);
  if (!win) {
    throw new Error("draggable: that window is not managed");
  }

  /** Where in the window the pointer took hold, and which pointer it was. */
  let holding: { dx: number; dy: number; pointer: number } | null = null;

  handle.addEventListener("pointerdown", (event) => {
    // A button in the title bar is a button first.
    if (event.button !== 0 || (event.target as Element).closest("button")) {
      return;
    }
    place(win);
    const box = el.getBoundingClientRect();
    holding = {
      dx: event.clientX - box.left,
      dy: event.clientY - box.top,
      pointer: event.pointerId,
    };
    handle.setPointerCapture(event.pointerId);
    handle.classList.add("dragging");
    event.preventDefault();
  });

  handle.addEventListener("pointermove", (event) => {
    if (!holding || event.pointerId !== holding.pointer) {
      return;
    }
    const box = el.getBoundingClientRect();
    const desk = desktop();
    // Clamped so a window cannot be pushed somewhere it can never be
    // grabbed back from: a strip of it stays inside the desktop.
    const x = clamp(event.clientX - holding.dx, desk.left - box.width + MARGIN, desk.right - MARGIN);
    const y = clamp(event.clientY - holding.dy, desk.top, desk.bottom - MARGIN);
    move(win, { x, y, w: box.width, h: box.height });
  });

  const release = (event: PointerEvent) => {
    if (!holding || event.pointerId !== holding.pointer) {
      return;
    }
    holding = null;
    handle.classList.remove("dragging");
    remember(win);
  };
  handle.addEventListener("pointerup", release);
  handle.addEventListener("pointercancel", release);

  // A window that has wandered off is put back with a double-click on its
  // bar, which is quicker than dragging it home.
  handle.addEventListener("dblclick", (event) => {
    if ((event.target as Element).closest("button")) {
      return;
    }
    reset(el);
  });
}

/** Bring a window to the front, if it is not there already. */
export function raise(el: HTMLElement): void {
  if (!managed.has(el) || el.style.zIndex === String(top)) {
    return;
  }
  top += 1;
  el.style.zIndex = String(top);
  for (const [other] of managed) {
    other.classList.toggle("front", other === el);
  }
}

/** Put a window back at the size and place it opens with. */
export function reset(el: HTMLElement): void {
  const win = managed.get(el);
  if (!win) {
    return;
  }
  win.moved = false;
  win.placed = false;
  forget(win);
  place(win);
}

/** The window holding the keyboard, if the keyboard is in one. */
export function focusedWindow(): HTMLElement | null {
  const focus = document.activeElement;
  if (!focus) {
    return null;
  }
  for (const [el] of managed) {
    if (el.contains(focus) && visible(el)) {
      return el;
    }
  }
  return null;
}

/** Whether the keyboard is inside some window rather than on the page. */
export function typingInWindow(): boolean {
  return focusedWindow() !== null;
}

// ---- geometry --------------------------------------------------------------

function visible(el: HTMLElement): boolean {
  return el instanceof HTMLDialogElement ? el.open : !el.hidden;
}

/**
 * Give a window a place, once.
 *
 * Where it was left last visit wins; failing that, the rect it was
 * registered with, worked out against the room there actually is.
 */
function place(win: Managed): void {
  if (win.placed) {
    return;
  }
  win.placed = true;
  const desk = desktop();
  const saved = recall(win);
  if (saved) {
    win.moved = true;
    move(win, fit(win, saved, desk));
    return;
  }
  move(win, fit(win, win.rect(desk), desk));
}

/** Set the geometry, in the one place that does. */
function move(win: Managed, rect: Rect): void {
  const style = win.el.style;
  style.left = `${Math.round(rect.x)}px`;
  style.top = `${Math.round(rect.y)}px`;
  style.width = `${Math.round(rect.w)}px`;
  style.height = `${Math.round(rect.h)}px`;
}

/** Trim a rect to the desktop, keeping it at least its minimum size. */
function fit(win: Managed, rect: Rect, desk: Desktop): Rect {
  const w = clamp(rect.w, win.min.w, Math.max(win.min.w, desk.right - desk.left));
  const h = clamp(rect.h, win.min.h, Math.max(win.min.h, desk.bottom - desk.top));
  return {
    w,
    h,
    x: clamp(rect.x, desk.left - w + MARGIN, desk.right - MARGIN),
    y: clamp(rect.y, desk.top, Math.max(desk.top, desk.bottom - MARGIN)),
  };
}

/**
 * The room a window has.
 *
 * The title bar and the status bar are the page's own furniture and are
 * never covered, so the desktop is what is left between them.
 */
function desktop(): Desktop {
  const head = document.getElementById("titlebar");
  const foot = document.getElementById("statusbar");
  return {
    left: 0,
    top: head ? head.getBoundingClientRect().bottom : 0,
    right: window.innerWidth,
    bottom: foot ? foot.getBoundingClientRect().top : window.innerHeight,
  };
}

function clamp(value: number, low: number, high: number): number {
  return Math.min(Math.max(value, low), Math.max(low, high));
}

// ---- resizing --------------------------------------------------------------

/**
 * Which edge the pointer is over, as a compass direction, or null.
 *
 * `event.target === el` is what keeps this out of the way of the contents:
 * every window is padded by the width of its frame, so only the frame is the
 * window's own box. A scrollbar hard against the right edge is a child, and
 * a grab on it is a scroll.
 */
function edgeAt(el: HTMLElement, event: PointerEvent): string | null {
  if (event.target !== el) {
    return null;
  }
  const box = el.getBoundingClientRect();
  const x = event.clientX - box.left;
  const y = event.clientY - box.top;
  const west = x <= FRAME;
  const east = x >= box.width - FRAME;
  const north = y <= FRAME;
  const south = y >= box.height - FRAME;
  // A corner is a bigger target than the edges that meet there, which is
  // what makes the two-way handles usable without aiming.
  const nearTop = y <= CORNER;
  const nearBottom = y >= box.height - CORNER;
  const nearLeft = x <= CORNER;
  const nearRight = x >= box.width - CORNER;

  let dir = "";
  if (north || ((west || east) && nearTop)) {
    dir += "n";
  } else if (south || ((west || east) && nearBottom)) {
    dir += "s";
  }
  if (west || ((north || south) && nearLeft)) {
    dir += "w";
  } else if (east || ((north || south) && nearRight)) {
    dir += "e";
  }
  return dir === "" ? null : dir;
}

const CURSORS: Record<string, string> = {
  n: "ns-resize",
  s: "ns-resize",
  e: "ew-resize",
  w: "ew-resize",
  ne: "nesw-resize",
  sw: "nesw-resize",
  nw: "nwse-resize",
  se: "nwse-resize",
};

/** Say what a grab here would do, before it is made. */
function showEdge(win: Managed, event: PointerEvent): void {
  const dir = edgeAt(win.el, event);
  win.el.style.cursor = dir ? (CURSORS[dir] ?? "") : "";
}

function beginResize(win: Managed, event: PointerEvent): void {
  const dir = event.button === 0 ? edgeAt(win.el, event) : null;
  if (!dir) {
    return;
  }
  place(win);
  const start = win.el.getBoundingClientRect();
  const from = { x: event.clientX, y: event.clientY };
  const pointer = event.pointerId;
  win.el.setPointerCapture(pointer);
  win.el.classList.add("resizing");
  event.preventDefault();

  const drag = (move_: PointerEvent) => {
    if (move_.pointerId !== pointer) {
      return;
    }
    const desk = desktop();
    let { left, top: y0, width, height } = start;
    let right = left + width;
    let bottom = y0 + height;
    if (dir.includes("w")) {
      left = clamp(left + (move_.clientX - from.x), desk.left, right - win.min.w);
    }
    if (dir.includes("e")) {
      right = clamp(right + (move_.clientX - from.x), left + win.min.w, desk.right);
    }
    if (dir.includes("n")) {
      y0 = clamp(y0 + (move_.clientY - from.y), desk.top, bottom - win.min.h);
    }
    if (dir.includes("s")) {
      bottom = clamp(bottom + (move_.clientY - from.y), y0 + win.min.h, desk.bottom);
    }
    move(win, { x: left, y: y0, w: right - left, h: bottom - y0 });
  };

  const stop = (up: PointerEvent) => {
    if (up.pointerId !== pointer) {
      return;
    }
    win.el.removeEventListener("pointermove", drag);
    win.el.removeEventListener("pointerup", stop);
    win.el.removeEventListener("pointercancel", stop);
    win.el.classList.remove("resizing");
    remember(win);
  };
  win.el.addEventListener("pointermove", drag);
  win.el.addEventListener("pointerup", stop);
  win.el.addEventListener("pointercancel", stop);
}

// ---- remembering where things were left ------------------------------------

function remember(win: Managed): void {
  win.moved = true;
  const box = win.el.getBoundingClientRect();
  try {
    localStorage.setItem(
      STORE + win.el.id,
      JSON.stringify({ x: box.left, y: box.top, w: box.width, h: box.height }),
    );
  } catch {
    // A private window refuses storage. The desktop still works; it just
    // opens in its default arrangement next time.
  }
}

function recall(win: Managed): Rect | null {
  let saved: string | null = null;
  try {
    saved = localStorage.getItem(STORE + win.el.id);
  } catch {
    return null;
  }
  if (saved === null) {
    return null;
  }
  try {
    const rect = JSON.parse(saved) as Rect;
    const numbers = [rect.x, rect.y, rect.w, rect.h];
    return numbers.every((n) => typeof n === "number" && Number.isFinite(n)) ? rect : null;
  } catch {
    return null;
  }
}

function forget(win: Managed): void {
  try {
    localStorage.removeItem(STORE + win.el.id);
  } catch {
    // As above: nothing to forget if nothing could be stored.
  }
}

// ---- the desktop ------------------------------------------------------------

// A viewport that has shrunk can leave a window off the edge of it, which is
// where it would stay: nothing else moves a window that is not being
// dragged. Every open window is trimmed back into the desktop instead.
window.addEventListener("resize", () => {
  const desk = desktop();
  for (const [el, win] of managed) {
    if (!win.placed || !visible(el)) {
      continue;
    }
    const box = el.getBoundingClientRect();
    move(win, fit(win, { x: box.left, y: box.top, w: box.width, h: box.height }, desk));
  }
});

// Escape closes the window holding the keyboard, which is what it did while
// these were modal dialogs and the browser did it for us.
window.addEventListener("keydown", (event) => {
  if (event.key !== "Escape" || event.defaultPrevented) {
    return;
  }
  const el = focusedWindow();
  const win = el ? managed.get(el) : null;
  if (!el || !win) {
    return;
  }
  event.preventDefault();
  if (win.close) {
    win.close();
  } else if (el instanceof HTMLDialogElement) {
    el.close();
  } else {
    el.hidden = true;
  }
});
