// The sub-windows: mail, the editor, the file library.
//
// Each is a `<dialog>`, which the browser centres and keeps modal. What it
// does not do is let anyone move one, and these cover the console while they
// are open -- so a window is dragged by its title bar, the way the desktop
// client's are.
//
// The drag is a transform rather than a position, so the browser keeps
// deciding where the window sits by default and this only offsets it from
// there. A resized viewport therefore still finds it, and clearing the
// offset puts it back where it began.
//
// Two of these windows rebuild their title bar whenever they redraw, so the
// offset belongs to the dialog rather than to the bar: `draggable` may be
// called again with a new handle and the window stays where it was put.

/** How much of the window must stay on screen, in pixels. */
const MARGIN = 24;

interface Placement {
  x: number;
  y: number;
  /** Whether the dialog's own listeners are attached. */
  bound: boolean;
}

const placements = new WeakMap<HTMLDialogElement, Placement>();

/**
 * Let a dialog be dragged by its title bar.
 *
 * Safe to call again with a replacement bar: the window keeps its place.
 * `handle` is the bar to drag it by.
 */
export function draggable(dialog: HTMLDialogElement, handle: HTMLElement): void {
  const place = placements.get(dialog) ?? { x: 0, y: 0, bound: false };
  placements.set(dialog, place);
  apply(dialog, place);

  /** Where the pointer took hold, and which pointer it was. */
  let holding: { x: number; y: number; pointer: number } | null = null;

  handle.addEventListener("pointerdown", (event) => {
    // A button in the title bar is a button first.
    if (event.button !== 0 || event.target instanceof HTMLButtonElement) {
      return;
    }
    holding = {
      x: event.clientX - place.x,
      y: event.clientY - place.y,
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
    // Clamped so a window cannot be pushed somewhere it can never be
    // grabbed back from.
    const box = dialog.getBoundingClientRect();
    place.x = clamp(event.clientX - holding.x, place.x, box.left, box.right, window.innerWidth);
    place.y = clamp(event.clientY - holding.y, place.y, box.top, box.bottom, window.innerHeight);
    apply(dialog, place);
  });

  const release = (event: PointerEvent) => {
    if (!holding || event.pointerId !== holding.pointer) {
      return;
    }
    holding = null;
    handle.classList.remove("dragging");
  };
  handle.addEventListener("pointerup", release);
  handle.addEventListener("pointercancel", release);

  // A window that has wandered off is put back with a double-click on its
  // bar, which is quicker than dragging it home.
  handle.addEventListener("dblclick", (event) => {
    if (event.target instanceof HTMLButtonElement) {
      return;
    }
    reset(dialog);
  });

  if (!place.bound) {
    place.bound = true;
    // The browser re-centres a dialog every time it is shown, so the offset
    // is dropped with it rather than applied to a new position.
    dialog.addEventListener("close", () => reset(dialog));
  }
}

/** Put a window back where the browser would have placed it. */
export function reset(dialog: HTMLDialogElement): void {
  const place = placements.get(dialog);
  if (!place) {
    return;
  }
  place.x = 0;
  place.y = 0;
  apply(dialog, place);
}

function apply(dialog: HTMLDialogElement, place: Placement): void {
  dialog.style.transform =
    place.x === 0 && place.y === 0 ? "" : `translate(${place.x}px, ${place.y}px)`;
}

/**
 * Keep an edge of the window on screen.
 *
 * `wanted` is the offset being asked for; `current` is the offset the box is
 * drawn with, `near` and `far` its two edges, and `viewport` how much room
 * there is -- so the limit can be worked out from where that leaves it.
 */
function clamp(
  wanted: number,
  current: number,
  near: number,
  far: number,
  viewport: number,
): number {
  // Where the edges would be with no offset at all.
  const start = near - current;
  const end = far - current;
  return Math.min(Math.max(wanted, MARGIN - end), viewport - MARGIN - start);
}
