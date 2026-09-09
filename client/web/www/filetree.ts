// The file explorers.
//
// There is one filesystem, in the fs worker, so there is one place to read
// the tree from. `FileModel` is that place on this side: it is asked for the
// tree once and then applies every change the worker reports as it makes it,
// which is why nothing here polls -- an `MD` typed at console 3 goes through
// that worker and comes straight back out as a change.
//
// `Files` in the status bar opens a window onto that model, and every click
// opens another one: looking in two folders at once is common enough that
// one window was the wrong number, and sharing the model is what makes the
// second one nearly free. What a window owns is where it is looking -- the
// folder showing, the file picked out, which folders are unfolded -- and
// nothing else, so two of them never have to be kept in step. `Explorers`
// owns the set, the way `Editors` owns the editors.
//
// It is two panes, as a file manager is: the folders on the left, and the
// chosen folder's files on the right as icons. One tree holding both was
// what this used to be, and a tree is the wrong shape for the job -- a
// hundred files in `/system` push everything below them off the bottom, and
// the thing being looked for is a file in a folder rather than a position in
// an outline. Splitting them means the left pane is only ever as long as the
// folders are, and the right one is a grid that uses the width.
//
// The model mirrors what the filesystem holds rather than what looks tidy. In
// particular a directory stays after the last file in it is deleted, because
// that is what the filesystem does -- writing `/a/b.ds` makes `/a`, and
// deleting the file does not take it away again.
//
// Four things can be done with what is drawn:
//   - dragged onto a console, where it types its absolute path,
//   - opened in the editor, by double-clicking a file,
//   - downloaded, from the button on a file's icon,
//   - dropped onto, which writes what was dropped into that folder.

import type { Ask, FileChange, Tree } from "./types.js";
import { draggable, manage, unmanage } from "./window.js";

/**
 * The drag type an explorer's own drags carry.
 *
 * A private type rather than `text/plain` alone, so a console can tell a
 * path dragged from here from any other text -- and can ignore a file being
 * dragged in from the desktop, which is not something to paste.
 */
export const PATH_DRAG = "application/x-dso-path";

/**
 * The largest file that may be dropped in, in bytes.
 *
 * One cap for everything now: a dropped file goes to disk whatever it is,
 * and only a text one is also held in memory -- and a text one big enough
 * to matter is not a script. What is left to guard is the browser's own
 * storage quota, which this stays well under so that a single careless drop
 * cannot fill it.
 */
const MAX_UPLOAD = 64 * 1024 * 1024;

/** How far each window opens down and right of the one already there. */
const CASCADE = 26;

/** How many windows the cascade steps through before starting over. */
const CASCADE_STEPS = 6;

/** Where the width of the folder pane is remembered. */
const SPLIT_KEY = "darksigns.filetree.split";

/** How narrow either pane may be dragged, in pixels. */
const MIN_PANE = 90;

/**
 * What a file's name says it is.
 *
 * The glyph is the whole of the icon: the client has no artwork of its own
 * and a drawn one would be six more files to ship for something a character
 * says as well. What it is for is telling a script from a song at a glance,
 * which is the distinction the game actually makes -- `Music` plays one and
 * `Run` runs the other.
 */
const KINDS: Array<[RegExp, string, string]> = [
  [/\.ds$/, "script", "▸"],
  [/\.(txt|log|md|ini|cfg|dat)$/, "text", "≡"],
  [/\.(mp3|wav|ogg|mid|midi|m4a|flac)$/, "song", "♫"],
  [/\.(png|jpe?g|gif|bmp|webp|svg)$/, "image", "▦"],
  [/\.(zip|gz|tar|7z|rar)$/, "pack", "▣"],
];

/** What one file is drawn as. */
interface Kind {
  name: string;
  glyph: string;
}

function kindOf(name: string): Kind {
  for (const [pattern, kind, glyph] of KINDS) {
    if (pattern.test(name.toLowerCase())) {
      return { name: kind, glyph };
    }
  }
  return { name: "other", glyph: "□" };
}

/** What one entry needs to draw itself and be found again. */
interface TreeNode {
  path: string;
  name: string;
  /** Bytes, for a file. */
  size: number;
}

/**
 * The filesystem as the page sees it, and the one copy of it there is.
 *
 * Every window draws from this. It is read once and then kept up from what
 * the fs worker reports, so opening a second window costs a render and
 * nothing else -- and two windows cannot disagree about what is on disk,
 * there being only one picture of it to disagree with.
 */
export class FileModel {
  /** Every directory, the root included. */
  dirs = new Set<string>(["/"]);
  /** Every file, by path, against its size in bytes. */
  files = new Map<string, FileInfo>();
  /** Set once the tree has been read, so a window can say what it is doing. */
  loaded = false;
  /** What went wrong reading it, if it did. */
  trouble: string | null = null;
  /**
   * Changes that arrived while `listTree` was in flight.
   *
   * The answer describes the filesystem as it was when the worker looked at
   * it, and a console may have written something in the meantime.
   * Holding those and replaying them over the answer costs nothing -- every
   * change is idempotent, so replaying one the answer already has is
   * harmless -- and it also serves as the flag that a load is in progress.
   */
  pending: FileChange[] | null = null;

  /** The open windows, each of which redraws when this changes. */
  readonly watchers = new Set<() => void>();

  constructor(readonly ask: Ask) {}

  /** Redraw that window from now on, until the returned function is called. */
  watch(redraw: () => void): () => void {
    this.watchers.add(redraw);
    return () => {
      this.watchers.delete(redraw);
    };
  }

  /** Ask the filesystem for the whole tree. */
  async load(): Promise<void> {
    if (this.pending) {
      return;
    }
    this.pending = [];
    let tree: Tree;
    try {
      tree = await this.ask({ type: "listTree" });
    } catch (err) {
      this.pending = null;
      this.trouble = err instanceof Error ? err.message : String(err);
      this.changed();
      return;
    }
    this.loaded = true;
    this.trouble = null;
    this.dirs = new Set(tree.dirs);
    this.dirs.add("/");
    this.files = new Map(
      tree.files.map((file) => [file.path, { size: file.size }]),
    );

    const missed = this.pending;
    this.pending = null;
    for (const change of missed) {
      this.take(change);
    }
    this.changed();
  }

  /**
   * Take up one change the filesystem reported.
   *
   * Whatever any console did went through that one worker, so this is every
   * change there is.
   */
  apply(change: FileChange): void {
    if (this.pending) {
      this.pending.push(change);
      return;
    }
    this.take(change);
    this.changed();
  }

  /** Fold one change in, without telling anyone. */
  take(change: FileChange): void {
    switch (change.op) {
      case "file":
        this.files.set(change.path, { size: change.size });
        // Writing a file makes the directories above it, so the model makes
        // them too rather than waiting to be told about them.
        this.addParents(change.path);
        break;
      case "dir":
        this.dirs.add(change.path);
        this.addParents(change.path);
        break;
      case "gone":
        // Whichever it was. The directories above a deleted file stay: the
        // filesystem keeps them, and a model that dropped them would
        // disagree with `DIR`.
        this.files.delete(change.path);
        this.dirs.delete(change.path);
        break;
    }
  }

  /** Record every directory on the way to `path`, but not `path` itself. */
  addParents(path: string): void {
    let at = parentOf(path);
    while (!this.dirs.has(at)) {
      this.dirs.add(at);
      if (at === "/") {
        return;
      }
      at = parentOf(at);
    }
  }

  /** The folders directly inside `dir`, in the order `DIR` lists them. */
  foldersIn(dir: string): TreeNode[] {
    const out: TreeNode[] = [];
    for (const path of this.dirs) {
      if (path !== "/" && parentOf(path) === dir) {
        out.push({ path, name: baseName(path), size: 0 });
      }
    }
    return out.sort((a, b) => a.name.localeCompare(b.name));
  }

  /** The files directly inside `dir`, by name. */
  filesIn(dir: string): TreeNode[] {
    const out: TreeNode[] = [];
    for (const [path, info] of this.files) {
      if (parentOf(path) === dir) {
        out.push({ path, name: baseName(path), size: info.size });
      }
    }
    return out.sort((a, b) => a.name.localeCompare(b.name));
  }

  /** Redraw every window looking at this. */
  changed(): void {
    for (const redraw of this.watchers) {
      redraw();
    }
  }
}

/** What `Explorers` hands a window when it makes one. */
interface ExplorerOptions {
  /** How far this window opens from where an explorer was last left. */
  offset: number;
  /** Told when the window has been closed and thrown away. */
  closed: () => void;
}

/**
 * Every open explorer, and the only way one is opened.
 *
 * Unlike an editor there is nothing here to open twice: a window is a place
 * to look from rather than a document, and two of them on the same folder is
 * a reasonable thing to ask for. So `Files` opens one every time, and the
 * cascade is what stops the new one landing exactly on the last.
 */
export class Explorers {
  readonly open = new Set<FileTree>();

  /**
   * How many have been opened, which is what the cascade counts.
   *
   * Not how many are open, as the editors count: an explorer is opened and
   * closed far more freely than a file is edited, and counting what is open
   * would drop a new window exactly onto one that outlived an earlier one.
   */
  made = 0;

  /**
   * `host` is what the windows are added to, `model` is the filesystem they
   * all draw from, `edit` is what a double-click does with a file, and
   * `notify` says something in the communications log.
   */
  constructor(
    readonly host: HTMLElement,
    readonly model: FileModel,
    readonly edit: (path: string) => void,
    readonly notify: (text: string) => void,
  ) {}

  create(): FileTree {
    const source = document.getElementById("filetree-template");
    const root =
      source instanceof HTMLTemplateElement
        ? source.content.firstElementChild?.cloneNode(true)
        : null;
    if (!(root instanceof HTMLElement)) {
      throw new Error("the file explorer's template is missing");
    }
    this.host.append(root);
    const tree = new FileTree(root, this.model, this.edit, this.notify, {
      // Clear of the last one, and back to the top once enough have been
      // opened, so the cascade cannot walk a window off the desktop.
      offset: (this.made % CASCADE_STEPS) * CASCADE,
      closed: () => this.open.delete(tree),
    });
    this.made += 1;
    this.open.add(tree);
    // Shown only now: the template's markup is `hidden`, so the manager sees
    // the window appear and gives it a place and the front of the stack,
    // which is the same route every other window takes.
    root.hidden = false;

    // Cheap insurance: the model keeps up through the change reports, so
    // this should find nothing new. It costs one message and it means a
    // report missed while something was starting up cannot leave a stale
    // tree on screen for the rest of the session.
    void this.model.load();
    return tree;
  }
}

/**
 * One window onto the model: two panes, and where in them it is looking.
 *
 * Made by `Explorers` and thrown away when it is closed. Nothing outside of
 * the drawing below is this window's own -- the tree itself belongs to the
 * model, and every other window is drawing the same one.
 */
export class FileTree {
  /** Which directories are unfolded in the left pane. */
  expanded = new Set<string>(["/", "/home"]);
  /** The folder whose files are on the right. */
  current = "/";
  /** The file picked out on the right, if any. */
  selected: string | null = null;
  /** How many uploads are in flight, so the strip can say so. */
  uploading = 0;
  /** Stops this window redrawing once it has been thrown away. */
  readonly unwatch: () => void;

  readonly body: HTMLElement;
  readonly icons: HTMLElement;
  readonly panes: HTMLElement;
  readonly split: HTMLElement;
  readonly pathLabel: HTMLElement;
  readonly status: HTMLElement;

  /**
   * `root` is the window, `model` is the filesystem it draws, `open` is what
   * a double-click does with a file, and `notify` says something in the
   * communications log.
   */
  constructor(
    readonly root: HTMLElement,
    readonly model: FileModel,
    readonly open: (path: string) => void,
    readonly notify: (text: string) => void,
    readonly options: ExplorerOptions,
  ) {
    this.body = root.querySelector(".tree-body") as HTMLElement;
    this.icons = root.querySelector(".tree-icons") as HTMLElement;
    this.panes = root.querySelector(".tree-panes") as HTMLElement;
    this.split = root.querySelector(".tree-split") as HTMLElement;
    this.pathLabel = root.querySelector(".tree-path") as HTMLElement;
    this.status = root.querySelector(".tree-status") as HTMLElement;

    manage(root, {
      // Down the left, where the tree used to be docked, and as tall as
      // there is room for: it is the window most likely to be left out for a
      // whole session.
      rect: (desk) => ({
        x: desk.left + 12,
        y: desk.top + 12,
        w: Math.min(34 * 16, desk.right - desk.left - 24),
        h: Math.min(30 * 16, desk.bottom - desk.top - 24),
      }),
      min: { w: 320, h: 200 },
      // One geometry for all of them, as the editors have: a window sized to
      // suit the screen is the size the next one wants too, and the offset
      // is what keeps them from landing on each other.
      store: "filetree",
      offset: options.offset,
      close: () => this.destroy(),
    });
    draggable(root, root.querySelector(".win-bar") as HTMLElement);

    // One listener per pane rather than one per row: the rows are rebuilt
    // whenever anything changes, and listeners on them would be too.
    for (const pane of [this.body, this.icons]) {
      pane.addEventListener("click", (e) => this.onClick(e));
      pane.addEventListener("dblclick", (e) => this.onDoubleClick(e));
      pane.addEventListener("dragstart", (e) => this.onDragStart(e));
      pane.addEventListener("dragover", (e) => this.onDragOver(e));
      pane.addEventListener("dragleave", (e) => this.onDragLeave(e));
      pane.addEventListener("drop", (e) => void this.onDrop(e));
    }
    this.body.addEventListener("keydown", (e) => this.onTreeKey(e));
    this.icons.addEventListener("keydown", (e) => this.onIconKey(e));

    (root.querySelector(".tree-hide") as HTMLElement).addEventListener("click", () =>
      this.destroy(),
    );
    this.splitter();

    this.unwatch = this.model.watch(() => this.render());
    this.render();
  }

  /**
   * Close this window and throw it away.
   *
   * Everything it holds goes with the element; what would outlive it is the
   * entry in the model's watchers and the one in the window manager, and
   * both of those are visited by every sweep the other windows make.
   */
  destroy(): void {
    this.unwatch();
    unmanage(this.root);
    this.root.remove();
    this.options.closed();
  }

  // ---- the split between the panes ---------------------------------------

  /**
   * Drag the divider between the folders and the files.
   *
   * The width is a property on the panes rather than an inline width on the
   * left one, so the grid keeps deciding what the right pane gets -- which
   * is what makes the whole window resizable without the split moving.
   */
  splitter(): void {
    let saved: string | null = null;
    try {
      saved = localStorage.getItem(SPLIT_KEY);
    } catch {
      // Storage denied; the stylesheet's default width stands.
    }
    if (saved !== null && Number.isFinite(Number(saved))) {
      this.panes.style.setProperty("--tree-pane", `${Number(saved)}px`);
    }

    let pointer: number | null = null;
    this.split.addEventListener("pointerdown", (event) => {
      pointer = event.pointerId;
      this.split.setPointerCapture(event.pointerId);
      this.split.classList.add("dragging");
      event.preventDefault();
      // A grab on the divider is not a grab on the window's frame.
      event.stopPropagation();
    });
    this.split.addEventListener("pointermove", (event) => {
      if (pointer !== event.pointerId) {
        return;
      }
      const box = this.panes.getBoundingClientRect();
      const width = Math.round(
        Math.min(Math.max(event.clientX - box.left, MIN_PANE), box.width - MIN_PANE),
      );
      this.panes.style.setProperty("--tree-pane", `${width}px`);
    });
    const stop = (event: PointerEvent) => {
      if (pointer !== event.pointerId) {
        return;
      }
      pointer = null;
      this.split.classList.remove("dragging");
      try {
        localStorage.setItem(
          SPLIT_KEY,
          String(parseInt(this.panes.style.getPropertyValue("--tree-pane"), 10)),
        );
      } catch {
        // As above.
      }
    };
    this.split.addEventListener("pointerup", stop);
    this.split.addEventListener("pointercancel", stop);
  }

  // ---- drawing -----------------------------------------------------------

  render(): void {
    // A folder the last of whose files was deleted stays; one that is gone
    // altogether cannot be what is showing.
    if (!this.model.dirs.has(this.current)) {
      this.current = "/";
    }
    this.drawTree();
    this.drawIcons();
    this.pathLabel.textContent = this.current;
    this.say(this.summary());
  }

  /** The left pane: the folders, and nothing else. */
  drawTree(): void {
    // Rebuilt whole. There are a few dozen folders, and the alternative --
    // patching it -- would have to get every case right for no gain anyone
    // could measure. The scroll position is the one thing worth carrying
    // over, since a write in a background console must not move the view.
    const scroll = this.body.scrollTop;
    // A write in a console nobody is looking at redraws this, and it must
    // not take the keyboard away from someone using the tree.
    const focused =
      this.body.contains(document.activeElement) &&
      (document.activeElement as HTMLElement).dataset.path;
    this.body.replaceChildren(this.drawList("/", 0));
    this.body.scrollTop = scroll;
    if (focused) {
      this.rowFor(focused)?.focus();
    }
  }

  /** The `<ul>` for one folder's subfolders. */
  drawList(dir: string, depth: number): HTMLElement {
    const list = document.createElement("ul");
    list.className = "tree-list";
    // The list and the item it holds are scaffolding: the row is the tree
    // item, so the markup between it and the tree is made transparent
    // rather than being announced as a list within a list.
    list.role = depth === 0 ? "none" : "group";
    if (depth === 0) {
      // The root is a row of its own, so that files can be dropped at the
      // top of the tree and so the whole thing can be folded away.
      list.append(this.drawFolder({ path: "/", name: "/", size: 0 }, 0));
      return list;
    }
    for (const node of this.model.foldersIn(dir)) {
      list.append(this.drawFolder(node, depth));
    }
    return list;
  }

  /** One folder row, and the sub-list under it when it is unfolded. */
  drawFolder(node: TreeNode, depth: number): HTMLElement {
    const item = document.createElement("li");
    item.role = "none";
    const row = document.createElement("div");
    row.className = "node dir";
    row.dataset.path = node.path;
    row.draggable = true;
    row.role = "treeitem";
    row.setAttribute("aria-level", String(depth + 1));
    // One tab stop for the whole tree, as a tree has: tab reaches the folder
    // that is showing and the arrows move from there.
    row.tabIndex = node.path === this.current ? 0 : -1;
    row.style.setProperty("--depth", String(depth));
    row.classList.toggle("selected", this.current === node.path);
    row.setAttribute("aria-selected", String(this.current === node.path));
    row.title = `${node.path} -- drop files here to add them`;

    const open = this.expanded.has(node.path);
    const empty = this.model.foldersIn(node.path).length === 0;
    const twist = document.createElement("span");
    twist.className = "twist";
    twist.textContent = empty ? "" : open ? "▾" : "▸";
    twist.classList.toggle("empty", empty);
    twist.setAttribute("aria-hidden", "true");

    const icon = document.createElement("span");
    icon.className = "folder-icon";
    icon.textContent = "■";
    icon.setAttribute("aria-hidden", "true");

    const name = document.createElement("span");
    name.className = "name";
    name.textContent = node.name;

    row.append(twist, icon, name);
    row.setAttribute("aria-expanded", String(open));

    item.append(row);
    if (open && !empty) {
      item.append(this.drawList(node.path, depth + 1));
    }
    return item;
  }

  /** The right pane: what is in the folder that is showing. */
  drawIcons(): void {
    const scroll = this.icons.scrollTop;
    const tiles = this.model.filesIn(this.current).map((node) => this.drawTile(node));
    if (tiles.length === 0) {
      const empty = document.createElement("p");
      empty.className = "tree-empty";
      empty.textContent = this.model.loaded
        ? "This folder holds no files. Drop some in to add them."
        : "Reading the filesystem...";
      this.icons.replaceChildren(empty);
      return;
    }
    this.icons.replaceChildren(...tiles);
    this.icons.scrollTop = scroll;
  }

  /** One file, as an icon with its name under it. */
  drawTile(node: TreeNode): HTMLElement {
    const kind = kindOf(node.name);
    const tile = document.createElement("div");
    tile.className = `tile ${kind.name}`;
    tile.dataset.path = node.path;
    tile.draggable = true;
    tile.role = "option";
    tile.title = `${node.path} (${formatSize(node.size)})`;
    const chosen = this.selected === node.path;
    tile.classList.toggle("selected", chosen);
    tile.setAttribute("aria-selected", String(chosen));

    const glyph = document.createElement("span");
    glyph.className = "tile-icon";
    glyph.textContent = kind.glyph;
    glyph.setAttribute("aria-hidden", "true");

    const name = document.createElement("span");
    name.className = "tile-name";
    name.textContent = node.name;

    const size = document.createElement("span");
    size.className = "tile-size";
    size.textContent = formatSize(node.size);

    // A button rather than a link: the contents live in a worker, so there
    // is nothing to point an `href` at until it has been asked for.
    const get = document.createElement("button");
    get.type = "button";
    get.className = "get";
    get.title = `Download ${node.name}`;
    get.setAttribute("aria-label", `Download ${node.name}`);
    get.textContent = "⤓";

    tile.append(glyph, name, size, get);
    return tile;
  }

  /** The row drawn for a folder, if it is one that is on screen. */
  rowFor(path: string): HTMLElement | null {
    return this.body.querySelector(`.node[data-path="${cssEscape(path)}"]`);
  }

  /** Every folder row now drawn, top to bottom -- which is how arrows move. */
  visibleRows(): HTMLElement[] {
    return Array.from(this.body.querySelectorAll<HTMLElement>(".node"));
  }

  /** Every file tile now drawn, in reading order. */
  visibleTiles(): HTMLElement[] {
    return Array.from(this.icons.querySelectorAll<HTMLElement>(".tile"));
  }

  /** What the strip along the bottom says when nothing else is happening. */
  summary(): string {
    if (this.uploading > 0) {
      return `Adding ${this.uploading} file(s)...`;
    }
    if (this.model.trouble !== null) {
      return this.model.trouble;
    }
    if (!this.model.loaded) {
      return "Reading the filesystem...";
    }
    const here = this.model.filesIn(this.current).length;
    const all = this.model.files.size;
    return `${here} file${here === 1 ? "" : "s"} here, ${all} in all. ` +
      "Drag one onto a console to type its path.";
  }

  say(text: string): void {
    this.status.textContent = text;
  }

  // ---- what the rows do --------------------------------------------------

  /** The folder row or file tile an event landed in, if it landed in one. */
  rowOf(event: Event): HTMLElement | null {
    const target = event.target as Element | null;
    return (target?.closest(".node, .tile") as HTMLElement | null) ?? null;
  }

  onClick(event: MouseEvent): void {
    const row = this.rowOf(event);
    if (!row || !row.dataset.path) {
      return;
    }
    const path = row.dataset.path;
    if ((event.target as Element).closest(".get")) {
      void this.download(path);
      return;
    }
    if (row.classList.contains("dir")) {
      // The twist folds; the row itself is what opens the folder, which is
      // the gesture a file manager answers to.
      if ((event.target as Element).closest(".twist")) {
        this.fold(path, !this.expanded.has(path));
        return;
      }
      this.enter(path);
      return;
    }
    // `select` and not `render`: a redraw here replaces the very tile that
    // was clicked, and a browser will not raise `dblclick` when the second
    // click lands on an element that was not there for the first. Opening a
    // file by double-clicking it depends on this tile surviving the single
    // click that precedes it.
    this.select(path);
  }

  /** Show a folder's files, unfolding the path down to it. */
  enter(dir: string): void {
    this.current = dir;
    this.selected = null;
    // What was clicked is where the player is looking, so it opens.
    this.expanded.add(dir);
    for (let at = parentOf(dir); at !== "/"; at = parentOf(at)) {
      this.expanded.add(at);
    }
    this.render();
  }

  /**
   * Pick out one tile, patching the tiles in place.
   *
   * Which tile is chosen decides three things -- the highlight, what a
   * screen reader calls selected, and what Enter would open -- and all three
   * are attributes on tiles that already exist.
   */
  select(path: string): void {
    this.selected = path;
    for (const tile of this.visibleTiles()) {
      const chosen = tile.dataset.path === path;
      tile.classList.toggle("selected", chosen);
      tile.setAttribute("aria-selected", String(chosen));
    }
  }

  /** A file opens in the editor, the way `EDIT` does; a folder unfolds. */
  onDoubleClick(event: MouseEvent): void {
    const row = this.rowOf(event);
    if (row?.classList.contains("tile") && row.dataset.path) {
      this.open(row.dataset.path);
      return;
    }
    if (row?.classList.contains("dir") && row.dataset.path) {
      this.fold(row.dataset.path, !this.expanded.has(row.dataset.path));
    }
  }

  onTreeKey(event: KeyboardEvent): void {
    const row = this.rowOf(event);
    const path = row?.dataset.path;
    if (!row || !path) {
      return;
    }
    if (event.key === "Enter" || event.key === " ") {
      event.preventDefault();
      this.enter(path);
      this.rowFor(path)?.focus();
      return;
    }
    // Down and up walk the rows as they are drawn, which is the order they
    // are read in.
    if (event.key === "ArrowDown" || event.key === "ArrowUp") {
      event.preventDefault();
      const rows = this.visibleRows();
      const next = rows[rows.indexOf(row) + (event.key === "ArrowDown" ? 1 : -1)];
      if (next?.dataset.path) {
        this.moveTo(next.dataset.path);
      }
      return;
    }
    // Right unfolds a folded folder; left folds an unfolded one and
    // otherwise steps out to the one holding it, as a tree does elsewhere.
    if (event.key === "ArrowRight" && !this.expanded.has(path)) {
      event.preventDefault();
      this.fold(path, true);
      return;
    }
    if (event.key === "ArrowLeft") {
      event.preventDefault();
      if (this.expanded.has(path)) {
        this.fold(path, false);
      } else if (path !== "/") {
        this.moveTo(parentOf(path));
      }
    }
  }

  /**
   * The arrows in the icon pane.
   *
   * Left and right step through the files in order; up and down move by a
   * row, and how many that is depends on how wide the window has been
   * dragged -- so it is counted off the tiles as they are laid out rather
   * than assumed.
   */
  onIconKey(event: KeyboardEvent): void {
    const tiles = this.visibleTiles();
    if (tiles.length === 0) {
      return;
    }
    if (event.key === "Enter" && this.selected) {
      event.preventDefault();
      this.open(this.selected);
      return;
    }
    const step = {
      ArrowRight: 1,
      ArrowLeft: -1,
      ArrowDown: columns(tiles),
      ArrowUp: -columns(tiles),
    }[event.key];
    if (step === undefined) {
      return;
    }
    event.preventDefault();
    const at = tiles.findIndex((tile) => tile.dataset.path === this.selected);
    const next = tiles[Math.min(Math.max((at < 0 ? 0 : at) + step, 0), tiles.length - 1)];
    if (next?.dataset.path) {
      this.select(next.dataset.path);
      next.scrollIntoView({ block: "nearest" });
    }
  }

  /** Pick out a folder row and put the keyboard on it. */
  moveTo(path: string): void {
    this.enter(path);
    const row = this.rowFor(path);
    row?.focus();
    row?.scrollIntoView({ block: "nearest" });
  }

  fold(path: string, open: boolean): void {
    if (open) {
      this.expanded.add(path);
    } else {
      this.expanded.delete(path);
    }
    this.render();
  }

  // ---- dragging a path out -----------------------------------------------

  onDragStart(event: DragEvent): void {
    const path = this.rowOf(event)?.dataset.path;
    if (!path || !event.dataTransfer) {
      return;
    }
    // The private type is what a console looks for; `text/plain` is there so
    // the same drag means something in an editor or a chat box.
    event.dataTransfer.setData(PATH_DRAG, path);
    event.dataTransfer.setData("text/plain", path);
    event.dataTransfer.effectAllowed = "copy";
  }

  // ---- dropping files in --------------------------------------------------

  /** Whether a drag is carrying files from outside the browser. */
  static carriesFiles(transfer: DataTransfer | null): boolean {
    return transfer !== null && Array.from(transfer.types).includes("Files");
  }

  /**
   * The folder a drop would land in.
   *
   * In the icon pane that is always the folder being shown, whatever the
   * drop landed on -- the tiles are its contents, not places of their own.
   * In the tree it is the folder under the pointer.
   */
  targetOf(event: DragEvent): { row: HTMLElement | null; dir: string } | null {
    const row = this.rowOf(event);
    if (this.icons.contains(event.target as Node)) {
      return { row: null, dir: this.current };
    }
    const path = row?.dataset.path;
    if (!row || !path) {
      return null;
    }
    return { row, dir: path };
  }

  onDragOver(event: DragEvent): void {
    if (!FileTree.carriesFiles(event.dataTransfer)) {
      return;
    }
    const target = this.targetOf(event);
    // Always, even over the blank space below the last row: without
    // `preventDefault` the browser takes the drop itself and navigates away
    // from the client to display the file. What that blank space is not is a
    // place to drop something, and the cursor is where that is said -- a
    // drop there has no folder to land in and does nothing.
    event.preventDefault();
    if (event.dataTransfer) {
      event.dataTransfer.dropEffect = target ? "copy" : "none";
    }
    this.markTarget(target ? (target.row ?? this.icons) : null);
  }

  onDragLeave(event: DragEvent): void {
    // `dragleave` fires on the way into a child as well, so a leave that is
    // still inside the window is not one.
    if (!this.panes.contains(event.relatedTarget as Node | null)) {
      this.markTarget(null);
    }
  }

  /** Show which folder a drop would land in, and only that one. */
  markTarget(target: HTMLElement | null): void {
    for (const marked of this.panes.querySelectorAll(".drop-target")) {
      marked.classList.remove("drop-target");
    }
    target?.classList.add("drop-target");
  }

  async onDrop(event: DragEvent): Promise<void> {
    if (!FileTree.carriesFiles(event.dataTransfer)) {
      return;
    }
    event.preventDefault();
    const target = this.targetOf(event);
    this.markTarget(null);
    if (!target || !event.dataTransfer) {
      return;
    }
    // The entries have to be taken now: a `DataTransfer` is emptied as soon
    // as the drop handler returns, and everything below here is asynchronous.
    const dropped = collect(event.dataTransfer);
    // So the files land somewhere visible rather than inside a folded row.
    this.expanded.add(target.dir);

    this.uploading += 1;
    this.say(this.summary());
    try {
      const files = await flatten(dropped);
      await this.upload(target.dir, files);
    } finally {
      this.uploading -= 1;
      this.render();
    }
  }

  /**
   * Write what was dropped, one file at a time, and report what did not fit.
   *
   * The window does not decide what kind of file anything is. It hands the
   * filesystem a name and a file, and the filesystem decides -- by the name
   * where the name says something, by the bytes where it does not. That is
   * the same decision it makes when it reads the tree back off disk at
   * startup, which is why a dropped file and a reloaded one are always
   * classed the same way.
   */
  async upload(dir: string, files: Array<{ path: string; file: File }>): Promise<void> {
    let written = 0;
    for (const { path, file } of files) {
      const target = join(dir, path);
      if (file.size > MAX_UPLOAD) {
        this.notify(`${file.name} is too big for the game filesystem; it was not added.`);
        continue;
      }
      try {
        await this.model.ask({ type: "putFile", path: target, file });
        written += 1;
      } catch (err) {
        this.notify(`Could not write ${target}: ${err instanceof Error ? err.message : err}`);
      }
      // The write reports itself back as a change, which is what puts the
      // row in the tree -- nothing is added here.
    }
    if (written > 0) {
      this.notify(`Added ${written} file(s) to ${dir}.`);
    }
  }

  // ---- taking a file out --------------------------------------------------

  /** Hand a file to the browser to save. */
  async download(path: string): Promise<void> {
    // One question whatever the file is: the filesystem hands back a `File`
    // for a song and for a script alike, and for a song that is a handle on
    // the bytes rather than the bytes, so saving an album does not pull one
    // through the page.
    let file: File | null;
    try {
      file = await this.model.ask({ type: "fileAt", path });
    } catch (err) {
      this.notify(`Could not read ${path}: ${err instanceof Error ? err.message : err}`);
      return;
    }
    if (!file) {
      this.notify(`${path} is no longer there.`);
      return;
    }
    this.save(file, baseName(path));
  }

  /**
   * A link that is clicked and thrown away.
   *
   * There is no URL to point at until now: the contents came out of a
   * filesystem the page cannot serve from directly.
   */
  save(data: Blob, name: string): void {
    const url = URL.createObjectURL(data);
    const link = document.createElement("a");
    link.href = url;
    link.download = name;
    link.click();
    // Not revoked immediately: the click has only started the save.
    setTimeout(() => URL.revokeObjectURL(url), 60_000);
  }
}

/** What the model remembers about one file. */
interface FileInfo {
  size: number;
}

// ---- paths ---------------------------------------------------------------

/** The directory holding `path`. The root holds itself. */
function parentOf(path: string): string {
  const cut = path.lastIndexOf("/");
  return cut <= 0 ? "/" : path.slice(0, cut);
}

function baseName(path: string): string {
  return path === "/" ? "/" : path.slice(path.lastIndexOf("/") + 1);
}

/** `dir` and a path below it, without doubling the separator at the root. */
function join(dir: string, rest: string): string {
  return dir === "/" ? `/${rest}` : `${dir}/${rest}`;
}

/**
 * A path as it must be typed at a console.
 *
 * The shell takes double quotes and reads a doubled one as an escape -- see
 * `game::cli` -- so a name with a space in it survives being pasted.
 */
export function quotePath(path: string): string {
  return /[\s"]/.test(path) ? `"${path.replace(/"/g, '""')}"` : path;
}

/** Escape a path for use in a CSS attribute selector. */
function cssEscape(value: string): string {
  return typeof CSS !== "undefined" && CSS.escape ? CSS.escape(value) : value;
}

// ---- sizes ---------------------------------------------------------------

function formatSize(bytes: number): string {
  if (bytes < 1024) {
    return `${bytes} B`;
  }
  if (bytes < 1024 * 1024) {
    return `${(bytes / 1024).toFixed(1)} K`;
  }
  return `${(bytes / (1024 * 1024)).toFixed(1)} M`;
}

// ---- reading what was dropped --------------------------------------------

/**
 * What a drop carried, taken before the transfer is emptied.
 *
 * `webkitGetAsEntry` is what makes a dropped folder more than its name, and
 * it has to be called inside the event handler. Where it is not available
 * the plain file list still works; it just cannot see into a folder.
 */
function collect(transfer: DataTransfer): Array<FileSystemEntry | File> {
  const entries: Array<FileSystemEntry | File> = [];
  for (const item of Array.from(transfer.items)) {
    if (item.kind !== "file") {
      continue;
    }
    const entry = item.webkitGetAsEntry?.();
    const file = entry ? null : item.getAsFile();
    if (entry) {
      entries.push(entry);
    } else if (file) {
      entries.push(file);
    }
  }
  return entries.length > 0 ? entries : Array.from(transfer.files);
}

/** Walk whatever was dropped into a flat list of files and relative paths. */
async function flatten(
  dropped: Array<FileSystemEntry | File>,
): Promise<Array<{ path: string; file: File }>> {
  const out: Array<{ path: string; file: File }> = [];
  const walk = async (entry: FileSystemEntry | File, prefix: string): Promise<void> => {
    if (entry instanceof File) {
      out.push({ path: prefix + entry.name, file: entry });
      return;
    }
    if (entry.isFile) {
      const file = await new Promise<File | null>((resolve) =>
        (entry as FileSystemFileEntry).file(resolve, () => resolve(null)),
      );
      if (file) {
        out.push({ path: prefix + entry.name, file });
      }
      return;
    }
    for (const child of await readDir(entry as FileSystemDirectoryEntry)) {
      await walk(child, `${prefix}${entry.name}/`);
    }
  };
  for (const entry of dropped) {
    await walk(entry, "");
  }
  return out;
}

/**
 * Every entry in a dropped directory.
 *
 * `readEntries` hands back a batch at a time and an empty batch means the
 * end, so it is called until it does.
 */
async function readDir(dir: FileSystemDirectoryEntry): Promise<FileSystemEntry[]> {
  const reader = dir.createReader();
  const all: FileSystemEntry[] = [];
  for (;;) {
    const batch = await new Promise<FileSystemEntry[]>((resolve) =>
      reader.readEntries(resolve, () => resolve([])),
    );
    if (batch.length === 0) {
      return all;
    }
    all.push(...batch);
  }
}


/**
 * How many tiles fit across the icon pane.
 *
 * Counted off the first row rather than worked out from the widths: the pane
 * is a grid that reflows as the window is resized, and what the arrows have
 * to agree with is what is on screen.
 */
function columns(tiles: HTMLElement[]): number {
  const first = tiles[0]?.offsetTop;
  const across = tiles.findIndex((tile) => tile.offsetTop !== first);
  return across <= 0 ? tiles.length : across;
}
