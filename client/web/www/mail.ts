// DSMail.
//
// The reader is a page, but the connection is a worker's: credentials never
// leave the workers, so everything here goes through `ask`, which hands a
// request to whichever console is free and resolves with its answer.
//
// The original is three windows -- an inbox, a reader and a composer. This is
// one, because a browser dialog inside a dialog buys nothing: selecting a
// message opens it below the list, and composing replaces the list.

import type { Ask, MailMessage, MailView } from "./types.js";
import { draggable } from "./window.js";

/** A message being written. */
interface Draft {
  to: string;
  subject: string;
  body: string;
}

/** How the server writes a date: `dd.mm.yyyy HH:MM:SS`. */
const SERVER_DATE = /^(\d{2})\.(\d{2})\.(\d{4}) (\d{2}):(\d{2}):(\d{2})$/;

export class MailWindow {
  messages: MailMessage[] = [];
  /** The message being read, or null while the list is showing. */
  reading: MailMessage | null = null;
  /** Set while a compose form is up, holding its draft. */
  draft: Draft | null = null;
  status = "";
  busy = false;

  /**
   * `ask` sends one request to a free console's worker and resolves with
   * what it answers.
   */
  constructor(
    readonly root: HTMLDialogElement,
    readonly ask: Ask,
  ) {
    this.root.addEventListener("close", () => {
      // A half-written message is kept, so closing the window by accident
      // does not throw it away.
      this.reading = null;
    });
  }

  get open(): boolean {
    return this.root.open;
  }

  /**
   * Show the window.
   *
   * The stored inbox is drawn first so there is something to look at, and
   * the server is asked straight after -- which is what the original does
   * when its inbox form loads.
   */
  async show(): Promise<void> {
    if (!this.root.open) {
      this.root.showModal();
    }
    this.render();
    await this.load("mailList");
    await this.refresh();
  }

  async refresh(): Promise<void> {
    await this.load("mailFetch", (view) => {
      this.status =
        `Current emails: ${view.messages.length} New emails: ${view.added}`;
    });
  }

  /** Run one request against a worker, keeping the window honest meanwhile. */
  async load(
    type: string,
    after?: ((view: MailView) => void) | null,
    extra: Record<string, unknown> = {},
  ): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    this.render();
    try {
      const view: MailView = await this.ask({ type, ...extra });
      this.messages = view.messages;
      after?.(view);
    } catch (err) {
      this.status = complaint(err);
    } finally {
      this.busy = false;
      this.render();
    }
  }

  async read(id: number): Promise<void> {
    this.reading = this.messages.find((m) => m.id === id) ?? null;
    this.render();
    if (this.reading?.unread) {
      await this.load("mailMarkRead", null, { id });
      // The list was replaced, so point at the message in the new one.
      this.reading = this.messages.find((m) => m.id === id) ?? this.reading;
      this.render();
    }
  }

  compose(draft: Draft = { to: "", subject: "", body: "" }): void {
    this.draft = draft;
    this.reading = null;
    this.status = "";
    this.render();
  }

  /**
   * Reply, quoting the original the way the client does: the body is prefixed
   * line by line with `#`, under a short header.
   */
  reply(message: MailMessage): void {
    const quoted = message.body
      .split(/\r\n|\r|\n/)
      .map((line) => `#${line}`)
      .join("\r\n");
    this.compose({
      to: nameOf(message.from),
      subject: message.subject.startsWith("Re: ")
        ? message.subject
        : `Re: ${message.subject}`,
      body: `\r\n\r\n\r\n#From ${message.from}\r\n# Subject ${message.subject}\r\n#\r\n${quoted}`,
    });
  }

  async send(): Promise<void> {
    if (!this.draft) {
      return;
    }
    const { to, subject, body } = this.draft;
    if (to.trim() === "") {
      this.status = "Say who it is going to.";
      this.render();
      return;
    }
    this.busy = true;
    this.status = "Sending...";
    this.render();
    try {
      await this.ask({ type: "mailSend", to, subject, body });
      this.draft = null;
      this.status = "Sent.";
      this.busy = false;
      // A message to yourself should appear without asking twice.
      await this.refresh();
    } catch (err) {
      this.busy = false;
      this.status = complaint(err);
      this.render();
    }
  }

  // ---- rendering -------------------------------------------------------

  render(): void {
    this.root.replaceChildren(
      this.header(),
      this.draft ? this.composer() : this.inbox(),
      this.footer(),
    );
  }

  header(): HTMLElement {
    const bar = el("header", "mail-bar win-drag");
    const title = el("strong", null, this.draft ? "New message" : "DSO Mail");
    bar.append(title, el("span", "mail-spacer"));
    if (!this.draft) {
      bar.append(
        button("New", () => this.compose(), this.busy),
        button("Refresh", () => this.refresh(), this.busy),
      );
    }
    bar.append(button("Close", () => this.root.close()));
    // The bar is rebuilt on every render, so the window is told each time
    // which element to be dragged by; it keeps wherever it was put.
    draggable(this.root, bar);
    return bar;
  }

  inbox(): HTMLElement {
    const body = el("div", "mail-body");
    const list = el("div", "mail-list");
    list.setAttribute("role", "list");

    if (this.messages.length === 0) {
      list.append(el("p", "mail-empty", this.busy ? "Checking mail..." : "No mail."));
    }
    // Newest first: the server hands them out oldest first, which is the
    // order they are stored in.
    for (const message of [...this.messages].reverse()) {
      const row = el("button", "mail-row");
      row.type = "button";
      row.setAttribute("role", "listitem");
      row.classList.toggle("unread", message.unread);
      row.classList.toggle("current", this.reading?.id === message.id);
      row.append(
        el("span", "mail-from", nameOf(message.from)),
        el("span", "mail-subject", message.subject || "(no subject)"),
        el("span", "mail-date", shortDate(message.date)),
      );
      row.addEventListener("click", () => this.read(message.id));
      list.append(row);
    }
    body.append(list);

    const reading = this.reading;
    if (reading) {
      const pane = el("article", "mail-read");
      const head = el("header", "mail-read-head");
      head.append(
        el("div", "mail-read-subject", reading.subject || "(no subject)"),
        el("div", "mail-read-meta", `${reading.from} · ${reading.date}`),
        button("Reply", () => this.reply(reading), this.busy),
      );
      pane.append(head, el("pre", "mail-read-body", reading.body));
      body.append(pane);
    }
    return body;
  }

  composer(): HTMLElement {
    const draft = this.draft as Draft;
    const form = el("form", "mail-compose");
    const to = field(form, "To", "text", draft.to, (v) => (draft.to = v));
    field(form, "Subject", "text", draft.subject, (v) => (draft.subject = v));

    const label = el("label", "mail-field mail-field-body");
    label.append(el("span", null, "Message"));
    const area = el("textarea");
    area.value = draft.body;
    area.rows = 12;
    area.addEventListener("input", () => (draft.body = area.value));
    label.append(area);
    form.append(label);

    const actions = el("div", "mail-actions");
    actions.append(
      button("Send", () => this.send(), this.busy),
      button("Cancel", () => {
        this.draft = null;
        this.status = "";
        this.render();
      }, this.busy),
    );
    form.append(actions);
    form.addEventListener("submit", (e) => {
      e.preventDefault();
      this.send();
    });
    // Focus wherever the message is unfinished, which for a reply is the body.
    queueMicrotask(() => (draft.to === "" ? to : area).focus());
    return form;
  }

  footer(): HTMLElement {
    const bar = el("footer", "mail-status");
    bar.textContent = this.busy && this.status === "" ? "Working..." : this.status;
    return bar;
  }
}

/** `alice@users` is shown as `alice`; anything else is left whole. */
function nameOf(address: string): string {
  return address.endsWith("@users") ? address.slice(0, -"@users".length) : address;
}

/** Drop the seconds, which no inbox column has ever needed. */
function shortDate(date: string): string {
  const parts = SERVER_DATE.exec(date);
  return parts ? `${parts[1]}.${parts[2]}.${parts[3]} ${parts[4]}:${parts[5]}` : date;
}

/** What went wrong, in the words it came with. */
function complaint(err: unknown): string {
  return String(err instanceof Error ? err.message : err);
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
  type: string,
  value: string,
  onInput: (value: string) => void,
): HTMLInputElement {
  const wrap = el("label", "mail-field");
  wrap.append(el("span", null, label));
  const input = el("input");
  input.type = type;
  input.value = value;
  input.addEventListener("input", () => onInput(input.value));
  wrap.append(input);
  form.append(wrap);
  return input;
}
