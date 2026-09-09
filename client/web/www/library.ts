// The file library, and the text space that shares its window.
//
// The library is where players publish scripts to one another: pick a
// category, download a row into `/downloads`, publish one of your own or
// withdraw it again. The text space is a numbered scratchpad anyone can read
// and write, and in the original it is a panel of this same form.
//
// As with mail, the window is the page's and the connection is a worker's:
// every request goes through `ask`, which hands it to whichever console is
// free. The wire format is parsed in Rust -- see `game::library` -- so what
// arrives here is already rows.

import type { Ask } from "./types.js";
import { centred, draggable, manage, raise } from "./window.js";

/** One file in the library. */
interface Entry {
  id: number;
  title: string;
  version: string;
  size: number;
  /** The size as the client formats it. */
  sizeText: string;
  author: string;
  filename: string;
  description: string;
  date: string;
  time: string;
}

/** One of the player's own uploads. */
interface Upload {
  id: number;
  label: string;
}

/** Which of the window's four panels is showing. */
type Panel = "browse" | "upload" | "mine" | "text";

/** The columns of the results table, and what each reads off a row. */
const COLUMNS: Array<[string, keyof Entry]> = [
  ["Title", "title"],
  ["Version", "version"],
  ["Size", "sizeText"],
  ["Author", "author"],
  ["Filename", "filename"],
  ["Date", "date"],
];

export class LibraryWindow {
  categories: string[] = [];
  channels = 999;
  panel: Panel = "browse";
  category = "";
  entries: Entry[] = [];
  selected: Entry | null = null;
  mine: Upload[] = [];
  /** Which of the player's own uploads is picked out for removal. */
  removing: number | null = null;
  /** Which column the table is sorted by, and which way. */
  sort: { column: keyof Entry; descending: boolean } = {
    column: "title",
    descending: false,
  };
  /** The player's files, for the upload picker. */
  files: string[] = [];
  draft = { category: "", title: "", version: "1.0", description: "", path: "" };
  textspace = { channel: 2, text: "", loaded: false };
  status = "To begin, choose a category.";
  busy = false;

  constructor(
    readonly root: HTMLDialogElement,
    readonly ask: Ask,
  ) {
    manage(root, {
      rect: (desk) => centred(desk, 72 * 16, 42 * 16),
      min: { w: 420, h: 260 },
    });
  }

  get open(): boolean {
    return this.root.open;
  }

  /** Show the window, filling in whatever it can without asking the server. */
  async show(): Promise<void> {
    if (!this.root.open) {
      this.root.show();
    }
    // A window that was already open is one the manager did not see appear,
    // so it is raised here: shown and brought forward are the same request.
    raise(this.root);
    this.render();
    if (this.categories.length === 0) {
      // The tables live in Rust beside the requests they shape, and the page
      // has no wasm of its own, so they are asked for like everything else.
      const tables = await this.send<{ categories: string[]; channels: number }>(
        { type: "libraryTables" },
        () => this.status,
      );
      if (tables) {
        this.categories = tables.categories;
        this.channels = tables.channels;
        this.draft.category ||= this.categories[0] ?? "";
      }
      this.render();
    }
    if (this.category === "") {
      await this.browse(this.categories[0] ?? "");
    }
  }

  /**
   * Run one request, keeping the window honest while it is in flight.
   *
   * `done` says what to put in the status line when it worked.
   */
  async send<T>(
    request: { type: string } & Record<string, unknown>,
    done: (value: T) => string,
  ): Promise<T | null> {
    if (this.busy) {
      return null;
    }
    this.busy = true;
    this.render();
    try {
      const value: T = await this.ask(request);
      this.status = done(value);
      return value;
    } catch (err) {
      this.status = String(err instanceof Error ? err.message : err);
      return null;
    } finally {
      this.busy = false;
      this.render();
    }
  }

  // ---- what the window can do ------------------------------------------

  async browse(category: string): Promise<void> {
    this.category = category;
    this.selected = null;
    this.entries = [];
    const rows = await this.send<Entry[]>({ type: "libraryList", category }, (found) =>
      found.length === 0 ? "No results found." : `${found.length} results found.`,
    );
    this.entries = rows ?? [];
    this.order();
    this.render();
  }

  async download(): Promise<void> {
    const entry = this.selected;
    if (!entry) {
      this.status = "No file is selected.";
      this.render();
      return;
    }
    this.status = `Downloading ${entry.filename}...`;
    await this.send<{ path: string; bytes: number }>(
      { type: "libraryDownload", id: entry.id },
      (file) => `File downloaded ok: ${file.path}`,
    );
  }

  async upload(): Promise<void> {
    const { category, title, version, description, path } = this.draft;
    await this.send<string>(
      { type: "libraryUpload", category, title, version, description, path },
      (said) => said,
    );
    // The listing it went into is the one worth looking at afterwards.
    if (!this.status.toLowerCase().includes("error")) {
      this.panel = "browse";
      await this.browse(category);
    }
  }

  async loadMine(): Promise<void> {
    const rows = await this.send<Upload[]>({ type: "libraryRemovable" }, (found) =>
      found.length === 0
        ? "You have not uploaded anything."
        : `${found.length} of your files.`,
    );
    this.mine = rows ?? [];
    this.render();
  }

  async remove(): Promise<void> {
    if (this.removing === null) {
      this.status = "No file has been selected.";
      this.render();
      return;
    }
    await this.send<string>({ type: "libraryRemove", id: this.removing }, (said) => said);
    this.removing = null;
    await this.loadMine();
  }

  async loadChannel(): Promise<void> {
    const text = await this.send<string>(
      { type: "textspaceLoad", channel: this.textspace.channel },
      () => `Channel ${this.textspace.channel} loaded.`,
    );
    if (text !== null) {
      this.textspace.text = text;
      this.textspace.loaded = true;
    }
    this.render();
  }

  async saveChannel(): Promise<void> {
    await this.send<string>(
      {
        type: "textspaceSave",
        channel: this.textspace.channel,
        text: this.textspace.text,
      },
      (said) => said,
    );
  }

  /** The files a script could be published from, fetched once per opening. */
  async loadFiles(): Promise<void> {
    if (this.files.length > 0) {
      return;
    }
    const files = await this.send<string[]>({ type: "listFiles" }, () => this.status);
    this.files = files ?? [];
    this.render();
  }

  /** Sort the results by the chosen column. */
  order(): void {
    const { column, descending } = this.sort;
    this.entries.sort((a, b) => {
      // Size sorts by the number rather than by "1.024 KB".
      const [x, y] =
        column === "sizeText" ? [a.size, b.size] : [read(a, column), read(b, column)];
      const order = x < y ? -1 : x > y ? 1 : 0;
      return descending ? -order : order;
    });
  }

  sortBy(column: keyof Entry): void {
    this.sort =
      this.sort.column === column
        ? { column, descending: !this.sort.descending }
        : { column, descending: false };
    this.order();
    this.render();
  }

  async openPanel(panel: Panel): Promise<void> {
    this.panel = panel;
    this.render();
    if (panel === "mine" && this.mine.length === 0) {
      await this.loadMine();
    }
    if (panel === "upload") {
      await this.loadFiles();
    }
    if (panel === "text" && !this.textspace.loaded) {
      await this.loadChannel();
    }
  }

  // ---- rendering -------------------------------------------------------

  render(): void {
    const body = {
      browse: () => this.browsePanel(),
      upload: () => this.uploadPanel(),
      mine: () => this.minePanel(),
      text: () => this.textPanel(),
    }[this.panel]();
    this.root.replaceChildren(this.header(), body, this.footer());
  }

  header(): HTMLElement {
    const bar = el("header", "win-bar mail-bar win-drag");
    bar.append(el("strong", null, "File Library"), el("span", "mail-spacer"));
    const tabs: Array<[string, Panel]> = [
      ["Browse", "browse"],
      ["Upload", "upload"],
      ["My Files", "mine"],
      ["Text Space", "text"],
    ];
    for (const [label, panel] of tabs) {
      const tab = button(label, () => void this.openPanel(panel), this.busy);
      tab.classList.toggle("current", this.panel === panel);
      bar.append(tab);
    }
    bar.append(button("Close", () => this.root.close()));
    // The bar is rebuilt on every render, so the drag is attached each time.
    draggable(this.root, bar);
    return bar;
  }

  browsePanel(): HTMLElement {
    const body = el("div", "lib-body");

    const list = el("div", "lib-categories");
    for (const name of this.categories) {
      const row = button(name, () => void this.browse(name), this.busy);
      row.classList.add("lib-category");
      row.classList.toggle("current", name === this.category);
      list.append(row);
    }

    const table = el("div", "lib-table");
    const head = el("div", "lib-row lib-head");
    for (const [label, key] of COLUMNS) {
      const cell = button(label, () => this.sortBy(key));
      cell.classList.add("lib-cell", "lib-sort");
      if (this.sort.column === key) {
        cell.classList.add("sorted");
        cell.append(el("span", "lib-arrow", this.sort.descending ? " ▼" : " ▲"));
      }
      head.append(cell);
    }
    table.append(head);

    const rows = el("div", "lib-rows");
    if (this.entries.length === 0) {
      rows.append(el("p", "mail-empty", this.busy ? "Updating..." : "Nothing here."));
    }
    for (const entry of this.entries) {
      const row = el("button", "lib-row");
      row.type = "button";
      row.classList.toggle("current", this.selected?.id === entry.id);
      for (const [, key] of COLUMNS) {
        row.append(el("span", "lib-cell", String(read(entry, key))));
      }
      row.addEventListener("click", () => {
        this.selected = entry;
        this.render();
      });
      row.addEventListener("dblclick", () => void this.download());
      rows.append(row);
    }
    table.append(rows);

    if (this.selected) {
      const detail = el("div", "lib-detail");
      detail.append(
        el("div", "lib-detail-title", `${this.selected.title} ${this.selected.version}`),
        el(
          "div",
          "lib-detail-meta",
          `#${this.selected.id} · ${this.selected.author} · ${this.selected.sizeText} · ` +
            `${this.selected.date} ${this.selected.time}`,
        ),
        el("p", "lib-detail-body", this.selected.description || "(no description)"),
        button(`Download ${this.selected.filename}`, () => void this.download(), this.busy),
      );
      table.append(detail);
    }

    body.append(list, table);
    return body;
  }

  uploadPanel(): HTMLElement {
    const form = el("form", "lib-form");
    form.append(el("h2", "lib-heading", "Publish a file"));

    select(form, "Category", this.categories, this.draft.category, (v) => {
      this.draft.category = v;
    });
    field(form, "Title", this.draft.title, (v) => (this.draft.title = v));
    field(form, "Version", this.draft.version, (v) => (this.draft.version = v));
    field(form, "Description", this.draft.description, (v) => (this.draft.description = v));

    // A datalist rather than a file picker: the files are the player's own,
    // inside the client, and not the machine's.
    const picker = field(form, "File", this.draft.path, (v) => (this.draft.path = v));
    const options = el("datalist");
    options.id = "lib-files";
    for (const path of this.files) {
      const option = document.createElement("option");
      option.value = path;
      options.append(option);
    }
    picker.setAttribute("list", "lib-files");
    picker.placeholder = "/home/tool.ds";
    form.append(options);

    const actions = el("div", "mail-actions");
    actions.append(button("Upload", () => void this.upload(), this.busy));
    form.append(actions);
    form.addEventListener("submit", (e) => {
      e.preventDefault();
      void this.upload();
    });
    return form;
  }

  minePanel(): HTMLElement {
    const body = el("div", "lib-panel");
    body.append(
      el("h2", "lib-heading", "Your uploads"),
      el("p", "lib-note", "You can withdraw anything you have published."),
    );

    const list = el("div", "lib-rows");
    if (this.mine.length === 0) {
      list.append(el("p", "mail-empty", this.busy ? "Updating..." : "Nothing published."));
    }
    for (const upload of this.mine) {
      const row = el("button", "lib-row lib-mine");
      row.type = "button";
      row.classList.toggle("current", this.removing === upload.id);
      row.append(el("span", "lib-cell", `#${upload.id}`), el("span", "lib-cell", upload.label));
      row.addEventListener("click", () => {
        this.removing = upload.id;
        this.render();
      });
      list.append(row);
    }

    const actions = el("div", "mail-actions");
    actions.append(
      button("Remove", () => void this.remove(), this.busy || this.removing === null),
      button("Refresh", () => void this.loadMine(), this.busy),
    );
    body.append(list, actions);
    return body;
  }

  textPanel(): HTMLElement {
    const body = el("div", "lib-panel");
    body.append(el("h2", "lib-heading", `Text space, channels 1 to ${this.channels}`));

    const bar = el("div", "lib-channel");
    const number = document.createElement("input");
    number.type = "number";
    number.min = "1";
    number.max = String(this.channels);
    number.value = String(this.textspace.channel);
    number.setAttribute("aria-label", "Channel");
    number.addEventListener("change", () => {
      this.textspace.channel = clampChannel(Number(number.value), this.channels);
      void this.loadChannel();
    });
    bar.append(
      el("span", null, "Channel"),
      number,
      button("Load", () => void this.loadChannel(), this.busy),
      button("Save Changes", () => void this.saveChannel(), this.busy),
    );

    const area = document.createElement("textarea");
    area.className = "lib-text";
    area.value = this.textspace.text;
    area.spellcheck = false;
    area.setAttribute("aria-label", "Channel text");
    area.addEventListener("input", () => (this.textspace.text = area.value));

    body.append(bar, area);
    // Channel 1 is readable and not writable, which the server enforces and
    // the window may as well say first.
    if (this.textspace.channel <= 1) {
      body.append(el("p", "lib-note", "Channel 1 cannot be written to."));
    }
    return body;
  }

  footer(): HTMLElement {
    const bar = el("footer", "mail-status");
    bar.textContent = this.busy ? "Working..." : this.status;
    return bar;
  }
}

/** One field of a row, as text. */
function read(entry: Entry, key: keyof Entry): string | number {
  return entry[key] ?? "";
}

function clampChannel(value: number, highest: number): number {
  if (!Number.isFinite(value)) {
    return 1;
  }
  return Math.min(Math.max(Math.trunc(value), 1), highest);
}

function el<K extends keyof HTMLElementTagNameMap>(
  tag: K,
  className?: string | null,
  text?: string,
): HTMLElementTagNameMap[K] {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (text !== undefined) node.textContent = text;
  return node;
}

function button(label: string, onClick: () => void, disabled = false): HTMLButtonElement {
  const node = el("button", "mail-button", label);
  node.type = "button";
  node.disabled = disabled;
  node.addEventListener("click", onClick);
  return node;
}

function field(
  form: HTMLElement,
  label: string,
  value: string,
  onInput: (value: string) => void,
): HTMLInputElement {
  const wrap = el("label", "mail-field");
  wrap.append(el("span", null, label));
  const input = el("input");
  input.type = "text";
  input.value = value;
  input.addEventListener("input", () => onInput(input.value));
  wrap.append(input);
  form.append(wrap);
  return input;
}

function select(
  form: HTMLElement,
  label: string,
  options: string[],
  value: string,
  onChange: (value: string) => void,
): HTMLSelectElement {
  const wrap = el("label", "mail-field");
  wrap.append(el("span", null, label));
  const picker = el("select");
  for (const name of options) {
    const option = document.createElement("option");
    option.value = name;
    option.textContent = name;
    option.selected = name === value;
    picker.append(option);
  }
  picker.addEventListener("change", () => onChange(picker.value));
  wrap.append(picker);
  form.append(wrap);
  return picker;
}
