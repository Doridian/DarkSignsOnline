// The file tree, beside the consoles.
//
// There is one filesystem, in the fs worker, so there is one place to read
// the tree from. The panel asks for it once and then applies every change
// the worker reports as it makes it, which is why nothing here polls: an
// `MD` typed at console 3 goes through that worker and comes straight back
// out as a change.
//
// The model mirrors what the filesystem holds rather than what looks tidy. In
// particular a directory stays after the last file in it is deleted, because
// that is what the filesystem does -- writing `/a/b.ds` makes `/a`, and
// deleting the file does not take it away again.
//
// Three things can be done with a row:
//   - dragged onto a console, where it types its absolute path,
//   - downloaded, from the button that appears on a file,
//   - dropped onto, which writes what was dropped into that folder.

import type { Ask, FileChange, Tree } from "./types.js";

/**
 * The drag type the panel's own drags carry.
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

/** Where the panel's open/closed state is remembered between visits. */
const OPEN_KEY = "darksigns.filetree";

/** Raised on the panel whenever it opens or closes; the detail is `open`. */
export const TOGGLED = "treetoggle";

/** What one node needs to draw itself and be found again. */
interface TreeNode {
  path: string;
  name: string;
  isDir: boolean;
  /** Bytes, for a file. */
  size: number;
}

export class FileTree {
  /** Every directory, the root included. */
  dirs = new Set<string>(["/"]);
  /** Every file, by path, against its size in bytes. */
  files = new Map<string, FileInfo>();
  /** Which directories are unfolded. */
  expanded = new Set<string>(["/", "/home"]);
  /** The row picked out, if any. */
  selected: string | null = null;
  /** Set once the tree has been read, so the strip can say what it is doing. */
  loaded = false;
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
  /** How many uploads are in flight, so the panel can say so. */
  uploading = 0;

  readonly body: HTMLElement;
  readonly status: HTMLElement;

  /**
   * `root` is the panel, `ask` reaches a worker, `open` is what a
   * double-click does with a file, and `notify` says something in the
   * communications log.
   */
  constructor(
    readonly root: HTMLElement,
    readonly ask: Ask,
    readonly open: (path: string) => void,
    readonly notify: (text: string) => void,
  ) {
    this.body = root.querySelector(".tree-body") as HTMLElement;
    this.status = root.querySelector(".tree-status") as HTMLElement;

    // One listener on the body rather than one per row: the rows are rebuilt
    // whenever anything changes, and listeners on them would be too.
    this.body.addEventListener("click", (e) => this.onClick(e));
    this.body.addEventListener("dblclick", (e) => this.onDoubleClick(e));
    this.body.addEventListener("dragstart", (e) => this.onDragStart(e));
    this.body.addEventListener("dragover", (e) => this.onDragOver(e));
    this.body.addEventListener("dragleave", (e) => this.onDragLeave(e));
    this.body.addEventListener("drop", (e) => void this.onDrop(e));
    this.body.addEventListener("keydown", (e) => this.onKeyDown(e));

    (root.querySelector(".tree-hide") as HTMLElement).addEventListener("click", () =>
      this.setOpen(false),
    );
  }

  // ---- showing and hiding ------------------------------------------------

  get isOpen(): boolean {
    return !this.root.classList.contains("closed");
  }

  /**
   * Put the panel in a state, without remembering it.
   *
   * The slide itself is the stylesheet's; this only sets the class it hangs
   * off and marks a closed panel inert, so what is off screen is not
   * reachable by tab either. The event is for whatever else shows the
   * state -- the switch in the status bar does.
   */
  show(open: boolean): void {
    this.root.classList.toggle("closed", !open);
    this.root.inert = !open;
    this.root.dispatchEvent(new CustomEvent(TOGGLED, { detail: open, bubbles: true }));
  }

  /** Open or close the panel, and remember which. */
  setOpen(open: boolean): void {
    this.show(open);
    try {
      localStorage.setItem(OPEN_KEY, open ? "open" : "closed");
    } catch {
      // A private window refuses storage. The panel still works; it just
      // opens in its default state next time.
    }
    if (open) {
      // Cheap insurance: the panel keeps up through the change reports, so
      // this should find nothing new. It costs one message and it means a
      // report missed while something was starting up cannot leave a stale
      // tree on screen for the rest of the session.
      void this.load();
    }
  }

  toggle(): void {
    this.setOpen(!this.isOpen);
  }

  /**
   * Open in whatever state the last visit left it in.
   *
   * Called before the page has been drawn, so a panel that was left closed
   * starts closed rather than sliding shut in front of the player.
   */
  restore(): void {
    // On a phone the panel covers the console rather than sitting beside it,
    // so opening by default would put it in front of the thing the client is
    // for. On anything wider there is room for both.
    let open = !window.matchMedia("(max-width: 34rem)").matches;
    try {
      const saved = localStorage.getItem(OPEN_KEY);
      if (saved !== null) {
        open = saved !== "closed";
      }
    } catch {
      // Storage denied; the default stands.
    }
    this.show(open);
  }

  // ---- the model ---------------------------------------------------------

  /** Ask the filesystem for the whole tree and draw it. */
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
      this.say(err instanceof Error ? err.message : String(err));
      return;
    }
    this.loaded = true;
    this.dirs = new Set(tree.dirs);
    this.dirs.add("/");
    this.files = new Map(
      tree.files.map((file) => [file.path, { size: file.size, mediaType: file.mediaType }]),
    );

    const missed = this.pending;
    this.pending = null;
    for (const change of missed) {
      this.take(change);
    }
    this.render();
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
    // Redrawn even while closed, since it costs almost nothing and means an
    // opening panel is right immediately rather than after its request.
    this.render();
  }

  /** Fold one change into the model, without redrawing. */
  take(change: FileChange): void {
    switch (change.op) {
      case "file":
        this.files.set(change.path, { size: change.size, mediaType: change.mediaType });
        // Writing a file makes the directories above it, so the panel makes
        // them too rather than waiting to be told about them.
        this.addParents(change.path);
        break;
      case "dir":
        this.dirs.add(change.path);
        this.addParents(change.path);
        break;
      case "gone":
        // Whichever it was. The directories above a deleted file stay: the
        // filesystem keeps them, and a panel that dropped them would
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

  // ---- drawing -----------------------------------------------------------

  render(): void {
    // Rebuilt whole. The tree is a few dozen rows, and the alternative --
    // patching it -- would have to get every case right for no gain anyone
    // could measure. The scroll position is the one thing worth carrying
    // over, since a write in a background console must not move the view.
    const scroll = this.body.scrollTop;
    // A write in a console nobody is looking at redraws this, and it must
    // not take the keyboard away from someone using the tree.
    const focused =
      this.body.contains(document.activeElement) &&
      (document.activeElement as HTMLElement).dataset.path;
    const children = this.index();
    this.body.replaceChildren(this.drawList("/", children, 0));
    this.body.scrollTop = scroll;
    if (focused) {
      this.rowFor(focused)?.focus();
    }
    this.say(this.summary());
  }

  /** The row drawn for a path, if it is one that is on screen. */
  rowFor(path: string): HTMLElement | null {
    return this.body.querySelector(`.node[data-path="${cssEscape(path)}"]`);
  }

  /** Every row now drawn, top to bottom -- which is how the arrows move. */
  visibleRows(): HTMLElement[] {
    return Array.from(this.body.querySelectorAll<HTMLElement>(".node"));
  }

  /** Every directory's children, worked out in one pass. */
  index(): Map<string, TreeNode[]> {
    const children = new Map<string, TreeNode[]>();
    const put = (node: TreeNode) => {
      const parent = parentOf(node.path);
      const list = children.get(parent);
      if (list) {
        list.push(node);
      } else {
        children.set(parent, [node]);
      }
    };
    for (const path of this.dirs) {
      if (path !== "/") {
        put({ path, name: baseName(path), isDir: true, size: 0 });
      }
    }
    for (const [path, info] of this.files) {
      put({ path, name: baseName(path), isDir: false, size: info.size });
    }
    // Directories first and then by name, which is how `DIR` orders a
    // listing and how a file tree is expected to read.
    for (const list of children.values()) {
      list.sort((a, b) =>
        a.isDir === b.isDir ? a.name.localeCompare(b.name) : a.isDir ? -1 : 1,
      );
    }
    return children;
  }

  /** The `<ul>` for one directory's contents. */
  drawList(dir: string, children: Map<string, TreeNode[]>, depth: number): HTMLElement {
    const list = document.createElement("ul");
    list.className = "tree-list";
    // The list and the item it holds are scaffolding: the row is the tree
    // item, so the markup between it and the tree is made transparent
    // rather than being announced as a list within a list.
    list.role = depth === 0 ? "none" : "group";
    if (depth === 0) {
      // The root is a row of its own, so that files can be dropped at the
      // top of the tree and so the whole thing can be folded away.
      list.append(this.drawNode({ path: "/", name: "/", isDir: true, size: 0 }, children, 0));
      return list;
    }
    for (const node of children.get(dir) ?? []) {
      list.append(this.drawNode(node, children, depth));
    }
    return list;
  }

  /** One row, and the sub-list under it when it is an unfolded directory. */
  drawNode(node: TreeNode, children: Map<string, TreeNode[]>, depth: number): HTMLElement {
    const item = document.createElement("li");
    item.role = "none";
    const row = document.createElement("div");
    row.className = node.isDir ? "node dir" : "node file";
    row.dataset.path = node.path;
    row.draggable = true;
    row.role = "treeitem";
    row.setAttribute("aria-level", String(depth + 1));
    // One tab stop for the whole tree, as a tree has: tab reaches the row
    // last used and the arrows move from there. Three hundred shipped files
    // are three hundred stops otherwise.
    const chosen = this.selected ?? "/";
    row.tabIndex = node.path === chosen ? 0 : -1;
    row.style.setProperty("--depth", String(depth));
    row.classList.toggle("selected", this.selected === node.path);
    row.setAttribute("aria-selected", String(this.selected === node.path));

    const open = this.expanded.has(node.path);
    const twist = document.createElement("span");
    twist.className = "twist";
    if (node.isDir) {
      const empty = (children.get(node.path) ?? []).length === 0;
      twist.textContent = empty ? "" : open ? "▾" : "▸";
      twist.classList.toggle("empty", empty);
    }
    twist.setAttribute("aria-hidden", "true");

    const name = document.createElement("span");
    name.className = "name";
    name.textContent = node.name;

    row.append(twist, name);
    if (node.isDir) {
      row.setAttribute("aria-expanded", String(open));
      row.title = `${node.path} -- drop files here to add them`;
    } else {
      const size = document.createElement("span");
      size.className = "size";
      size.textContent = formatSize(node.size);
      // A button rather than a link: the contents live in a worker, so there
      // is nothing to point an `href` at until it has been asked for.
      const get = document.createElement("button");
      get.type = "button";
      get.className = "get";
      get.title = `Download ${node.name}`;
      get.setAttribute("aria-label", `Download ${node.name}`);
      get.textContent = "⤓";
      row.append(size, get);
      row.title = node.path;
    }

    item.append(row);
    if (node.isDir && open) {
      item.append(this.drawList(node.path, children, depth + 1));
    }
    return item;
  }

  /** What the strip under the tree says when nothing else is happening. */
  summary(): string {
    if (this.uploading > 0) {
      return `Adding ${this.uploading} file(s)...`;
    }
    if (!this.loaded) {
      return "Reading the filesystem...";
    }
    const files = this.files.size;
    return `${files} file${files === 1 ? "" : "s"}. Drag a name onto a console.`;
  }

  say(text: string): void {
    this.status.textContent = text;
  }

  // ---- what the rows do --------------------------------------------------

  /** The row an event landed in, if it landed in one. */
  rowOf(event: Event): HTMLElement | null {
    const target = event.target as Element | null;
    return (target?.closest(".node") as HTMLElement | null) ?? null;
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
      this.selected = path;
      this.fold(path, !this.expanded.has(path));
      return;
    }
    // `select` and not `render`: a redraw here replaces the very row that
    // was clicked, and a browser will not raise `dblclick` when the second
    // click lands on an element that was not there for the first. Opening a
    // file by double-clicking it depended on this row surviving the single
    // click that precedes it.
    this.select(path);
  }

  /**
   * Pick out one row, patching the rows in place.
   *
   * Which row is chosen decides three things -- the highlight, what a screen
   * reader calls selected, and where the tree's single tab stop sits -- and
   * all three are attributes on rows that already exist.
   */
  select(path: string): void {
    this.selected = path;
    for (const row of this.visibleRows()) {
      const chosen = row.dataset.path === path;
      row.classList.toggle("selected", chosen);
      row.setAttribute("aria-selected", String(chosen));
      row.tabIndex = chosen ? 0 : -1;
    }
  }

  /** A file opens in the editor, the way `EDIT` does; a folder unfolds. */
  onDoubleClick(event: MouseEvent): void {
    const row = this.rowOf(event);
    if (row?.classList.contains("file") && row.dataset.path) {
      this.open(row.dataset.path);
    }
  }

  onKeyDown(event: KeyboardEvent): void {
    const row = this.rowOf(event);
    const path = row?.dataset.path;
    if (!row || !path) {
      return;
    }
    const dir = row.classList.contains("dir");
    if (event.key === "Enter" || event.key === " ") {
      event.preventDefault();
      this.selected = path;
      if (dir) {
        this.fold(path, !this.expanded.has(path));
      } else {
        this.select(path);
        this.open(path);
      }
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
    // Right unfolds a folded directory; left folds an unfolded one and
    // otherwise steps out to the one holding this, as a tree does elsewhere.
    if (event.key === "ArrowRight" && dir && !this.expanded.has(path)) {
      event.preventDefault();
      this.fold(path, true);
      return;
    }
    if (event.key === "ArrowLeft") {
      event.preventDefault();
      if (dir && this.expanded.has(path)) {
        this.fold(path, false);
      } else if (path !== "/") {
        this.moveTo(parentOf(path));
      }
    }
  }

  /** Pick out a row and put the keyboard on it. */
  moveTo(path: string): void {
    this.select(path);
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

  /** The folder a drop would land in: the row under it, or its parent. */
  targetOf(event: DragEvent): { row: HTMLElement; dir: string } | null {
    const row = this.rowOf(event);
    const path = row?.dataset.path;
    if (!row || !path) {
      return null;
    }
    // Dropping onto a file means the folder holding it, which is what every
    // other file manager does and saves aiming at a one-line target.
    return { row, dir: row.classList.contains("dir") ? path : parentOf(path) };
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
    this.markTarget(target?.row ?? null);
  }

  onDragLeave(event: DragEvent): void {
    // `dragleave` fires on the way into a child as well, so a leave that is
    // still inside the panel is not one.
    if (!this.body.contains(event.relatedTarget as Node | null)) {
      this.markTarget(null);
    }
  }

  /** Show which folder a drop would land in, and only that one. */
  markTarget(row: HTMLElement | null): void {
    for (const marked of this.body.querySelectorAll(".node.drop-target")) {
      marked.classList.remove("drop-target");
    }
    if (!row) {
      return;
    }
    // The highlight belongs on the folder that would take the files, which
    // for a file row is the row above it in the tree.
    const dir = row.classList.contains("dir")
      ? row
      : this.rowFor(parentOf(row.dataset.path ?? "/"));
    dir?.classList.add("drop-target");
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
   * The panel does not decide what kind of file anything is. It hands the
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
        await this.ask({ type: "putFile", path: target, file });
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
      file = await this.ask({ type: "fileAt", path });
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

/** What the panel remembers about one file. */
interface FileInfo {
  size: number;
  /** Empty for text; names the kind for a file whose contents are bytes. */
  mediaType: string;
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

