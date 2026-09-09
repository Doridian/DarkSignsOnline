// The status bar's app buttons, and the menu that drops up from them.
//
// A button there is an app, not a switch. Pressing it with nothing open
// opens something; pressing it with something open brings that something to
// the front. What it never does is close a window. A button that opened a
// terminal on the way down and threw a running script away on the way up is
// one control doing two opposite things, and nothing about it says which it
// is about to do -- closing is what a window's own bar is for, where the
// window it closes is the one you are looking at.
//
// Apps there can be several of -- the terminals, the file explorers -- have
// more than one answer to "bring it to the front", so a press with windows
// open drops a menu up instead: every window the app has, and below them one
// more entry to open another. With nothing open there is nothing to choose
// between, so the press just opens one. Apps there is only ever one of skip
// the menu entirely: open it, or raise it.
//
// One menu element serves every button. It hangs from `document.body` and is
// `position: fixed`, placed against whichever button it belongs to: the
// status bar is a thin strip at the foot of the page, and a menu laid out
// inside it would be a menu the height of one line.

import { overlay } from "./window.js";

/** One open window of an app, as the menu lists it. */
export interface Instance {
  /** What the menu calls it. Worked out afresh every time the menu opens,
      so an explorer is named for the folder it is looking at now. */
  label: string;
  /** The window itself, so the menu can mark whichever is in front. */
  el: HTMLElement;
  /** Bring it forward and give it the keyboard. */
  show: () => void;
}

export interface App {
  /** The status bar button that stands for it. */
  button: HTMLElement;
  /**
   * What the menu's last entry says, for apps there can be several of.
   *
   * Left out by the one-of-a-kind windows -- the communications log, chat,
   * the library -- which have nothing to open a second of and so never show
   * a menu at all.
   */
  another?: string;
  /** Whatever it has open, in the order the menu should list them. */
  instances: () => Instance[];
  /** Open one more. */
  launch: () => void;
}

/** How far above the button the menu sits, in pixels. */
const GAP = 6;

/** How close to the edge of the page the menu may be pushed, in pixels. */
const EDGE = 8;

/** Every registered button, so a press on one is not "outside the menu". */
const buttons = new Set<HTMLElement>();

/** The one menu, made when the first app is registered. */
let menu: HTMLElement | null = null;

/** Whose menu is up, or null when none is. */
let showing: App | null = null;

/**
 * Put the status bar's buttons in charge of their windows.
 *
 * Called once, with every app the bar has.
 */
export function taskbar(apps: App[]): void {
  menu ??= buildMenu();
  for (const app of apps) {
    buttons.add(app.button);
    if (app.another) {
      app.button.setAttribute("aria-haspopup", "menu");
      app.button.setAttribute("aria-controls", "app-menu");
      app.button.setAttribute("aria-expanded", "false");
    }
    // `detail` is 0 when the button was pressed with the keyboard, which is
    // the case that needs the caret carried into the menu: a mouse leaves it
    // where it was and aims at the entry it wants.
    app.button.addEventListener("click", (event) => press(app, event.detail === 0));
  }
}

/**
 * A press: open, raise, or offer the choice between them.
 */
function press(app: App, byKeyboard: boolean): void {
  // Pressing the button whose menu is already up puts it away, the way any
  // menu behaves.
  if (showing === app) {
    close(true);
    return;
  }
  close(false);
  const open = app.instances();
  if (open.length === 0) {
    app.launch();
    return;
  }
  // One window and no way to have a second: there is nothing to choose, so
  // the press does the only thing it could have meant.
  if (!app.another) {
    open[0]?.show();
    return;
  }
  openMenu(app, open, byKeyboard);
}

// ---- the menu --------------------------------------------------------------

function buildMenu(): HTMLElement {
  const el = document.createElement("div");
  el.id = "app-menu";
  el.role = "menu";
  el.hidden = true;
  document.body.append(el);

  // On the document rather than on the menu, and ahead of everyone else: a
  // menu opened with the mouse leaves the keyboard on the button that opened
  // it, so Escape and the arrows have to be caught wherever they land. The
  // guard is `showing`, so nothing here is in the way while no menu is up.
  document.addEventListener("keydown", (event) => onMenuKey(event), true);

  // A press anywhere else puts the menu away, before whatever was aimed at
  // underneath happens. The app buttons are the exception: their own handler
  // decides, so that pressing the open one closes it rather than closing and
  // opening it again in the same gesture.
  document.addEventListener("pointerdown", (event) => {
    const target = event.target as Node | null;
    if (!showing || (target && (el.contains(target) || onAButton(target)))) {
      return;
    }
    close(false);
  });

  // The keyboard leaving the menu puts it away. A press elsewhere is not the
  // only way that happens: a script reaching `ReadLine` takes the caret back
  // to its own terminal, and a menu still up over a terminal being typed in
  // would swallow the arrow keys that were meant for the line.
  document.addEventListener("focusin", (event) => {
    const target = event.target as Node | null;
    if (!showing || !target || el.contains(target) || onAButton(target)) {
      return;
    }
    close(false);
  });

  // The menu is placed against a button that has just moved, and nothing
  // moves it after the fact.
  window.addEventListener("resize", () => close(false));
  return el;
}

function onAButton(target: Node): boolean {
  const el = target instanceof Element ? target : target.parentElement;
  for (const button of buttons) {
    if (el && (button === el || button.contains(el))) {
      return true;
    }
  }
  return false;
}

function openMenu(app: App, open: Instance[], byKeyboard: boolean): void {
  const el = menu;
  if (!el) {
    return;
  }
  el.replaceChildren();
  for (const instance of open) {
    // `front` is the window manager's mark for whichever window is on top,
    // so the menu says where a press would take you before it takes you.
    el.append(item(instance.label, instance.el.classList.contains("front"), () => {
      close(false);
      instance.show();
    }));
  }
  el.append(item(app.another ?? "New window", false, () => {
    close(false);
    app.launch();
  }, true));

  showing = app;
  app.button.setAttribute("aria-expanded", "true");
  app.button.classList.add("open");
  el.hidden = false;
  place(app.button, el);
  if (byKeyboard) {
    (el.firstElementChild as HTMLElement | null)?.focus();
  }
}

function item(label: string, front: boolean, chosen: () => void, fresh = false): HTMLElement {
  const button = document.createElement("button");
  button.type = "button";
  button.className = "app-menu-item";
  button.classList.toggle("front", front);
  button.classList.toggle("fresh", fresh);
  button.role = "menuitem";
  button.textContent = label;
  button.addEventListener("click", chosen);
  return button;
}

/** Above the button, and never off the side of the page. */
function place(button: HTMLElement, el: HTMLElement): void {
  const box = button.getBoundingClientRect();
  const width = el.getBoundingClientRect().width;
  el.style.left = `${Math.round(Math.max(EDGE, Math.min(box.left, window.innerWidth - width - EDGE)))}px`;
  el.style.bottom = `${Math.round(window.innerHeight - box.top + GAP)}px`;
  // Over the windows, whatever height their stack has climbed to by now.
  el.style.zIndex = String(overlay());
}

/**
 * Put the menu away.
 *
 * `back` hands the keyboard to the button it came from, which is what
 * Escape and a second press want; choosing an entry does not, because the
 * window that was chosen is about to take it.
 */
function close(back: boolean): void {
  const app = showing;
  if (!app || !menu) {
    return;
  }
  showing = null;
  menu.hidden = true;
  menu.replaceChildren();
  app.button.setAttribute("aria-expanded", "false");
  app.button.classList.remove("open");
  if (back) {
    app.button.focus();
  }
}

/** Walk the entries, and leave. */
function onMenuKey(event: KeyboardEvent): void {
  const el = menu;
  if (!el || !showing || event.ctrlKey || event.altKey || event.metaKey) {
    return;
  }
  if (event.key === "Escape") {
    event.preventDefault();
    close(true);
    return;
  }
  // Tab leaves the menu, and leaves from the button it dropped out of: the
  // keyboard would otherwise be on an entry that has just stopped existing,
  // and the next tab stop would be the top of the page.
  if (event.key === "Tab") {
    close(true);
    return;
  }
  const items = [...el.children] as HTMLElement[];
  // -1 while the keyboard is still on the button that opened the menu, which
  // is where a press with the mouse leaves it: the first arrow steps into
  // the menu from whichever end it was aimed at.
  const at = items.indexOf(document.activeElement as HTMLElement);
  let to = -1;
  if (event.key === "ArrowDown") {
    to = at < 0 ? 0 : (at + 1) % items.length;
  } else if (event.key === "ArrowUp") {
    to = at < 0 ? items.length - 1 : (at - 1 + items.length) % items.length;
  } else if (event.key === "Home") {
    to = 0;
  } else if (event.key === "End") {
    to = items.length - 1;
  }
  if (to !== -1) {
    event.preventDefault();
    items[to]?.focus();
  }
}
