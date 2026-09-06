// DSMail.
//
// The reader is a page, but the connection is a worker's: credentials never
// leave the workers, so everything here goes through `ask`, which hands a
// request to whichever console is free and resolves with its answer.
//
// The original is three windows -- an inbox, a reader and a composer. This is
// one, because a browser dialog inside a dialog buys nothing: selecting a
// message opens it below the list, and composing replaces the list.

/** How the server writes a date: `dd.mm.yyyy HH:MM:SS`. */
const SERVER_DATE = /^(\d{2})\.(\d{2})\.(\d{4}) (\d{2}):(\d{2}):(\d{2})$/;

export class MailWindow {
  /**
   * @param {HTMLDialogElement} root the dialog
   * @param {(message: object) => Promise<object>} ask sends one request to a
   *   free console's worker and resolves with what it answers
   */
  constructor(root, ask) {
    this.root = root;
    this.ask = ask;
    this.messages = [];
    /** The message being read, or null while the list is showing. */
    this.reading = null;
    /** Set while a compose form is up, holding its draft. */
    this.draft = null;
    this.status = "";
    this.busy = false;

    this.root.addEventListener("close", () => {
      // A half-written message is kept, so closing the window by accident
      // does not throw it away.
      this.reading = null;
    });
  }

  get open() {
    return this.root.open;
  }

  /**
   * Show the window.
   *
   * The stored inbox is drawn first so there is something to look at, and
   * the server is asked straight after -- which is what the original does
   * when its inbox form loads.
   */
  async show() {
    if (!this.root.open) {
      this.root.showModal();
    }
    this.render();
    await this.load("mailList");
    await this.refresh();
  }

  async refresh() {
    await this.load("mailFetch", (view) => {
      this.status =
        `Current emails: ${view.messages.length} New emails: ${view.added}`;
    });
  }

  /** Run one request against a worker, keeping the window honest meanwhile. */
  async load(type, after, extra = {}) {
    if (this.busy) {
      return;
    }
    this.busy = true;
    this.render();
    try {
      const view = await this.ask({ type, ...extra });
      this.messages = view.messages;
      after?.(view);
    } catch (err) {
      this.status = String(err.message ?? err);
    } finally {
      this.busy = false;
      this.render();
    }
  }

  async read(id) {
    this.reading = this.messages.find((m) => m.id === id) ?? null;
    this.render();
    if (this.reading?.unread) {
      await this.load("mailMarkRead", null, { id });
      // The list was replaced, so point at the message in the new one.
      this.reading = this.messages.find((m) => m.id === id) ?? this.reading;
      this.render();
    }
  }

  compose(draft = { to: "", subject: "", body: "" }) {
    this.draft = draft;
    this.reading = null;
    this.status = "";
    this.render();
  }

  /**
   * Reply, quoting the original the way the client does: the body is prefixed
   * line by line with `#`, under a short header.
   */
  reply(message) {
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

  async send() {
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
      this.status = String(err.message ?? err);
      this.render();
    }
  }

  // ---- rendering -------------------------------------------------------

  render() {
    this.root.replaceChildren(
      this.header(),
      this.draft ? this.composer() : this.inbox(),
      this.footer(),
    );
  }

  header() {
    const bar = el("header", "mail-bar");
    const title = el("strong", null, this.draft ? "New message" : "DSO Mail");
    bar.append(title, el("span", "mail-spacer"));
    if (!this.draft) {
      bar.append(
        button("New", () => this.compose(), this.busy),
        button("Refresh", () => this.refresh(), this.busy),
      );
    }
    bar.append(button("Close", () => this.root.close()));
    return bar;
  }

  inbox() {
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

    if (this.reading) {
      const pane = el("article", "mail-read");
      const head = el("header", "mail-read-head");
      head.append(
        el("div", "mail-read-subject", this.reading.subject || "(no subject)"),
        el("div", "mail-read-meta", `${this.reading.from} · ${this.reading.date}`),
        button("Reply", () => this.reply(this.reading), this.busy),
      );
      pane.append(head, el("pre", "mail-read-body", this.reading.body));
      body.append(pane);
    }
    return body;
  }

  composer() {
    const form = el("form", "mail-compose");
    const to = field(form, "To", "text", this.draft.to, (v) => (this.draft.to = v));
    field(form, "Subject", "text", this.draft.subject, (v) => (this.draft.subject = v));

    const label = el("label", "mail-field mail-field-body");
    label.append(el("span", null, "Message"));
    const area = document.createElement("textarea");
    area.value = this.draft.body;
    area.rows = 12;
    area.addEventListener("input", () => (this.draft.body = area.value));
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
    queueMicrotask(() => (this.draft.to === "" ? to : area).focus());
    return form;
  }

  footer() {
    const bar = el("footer", "mail-status");
    bar.textContent = this.busy && this.status === "" ? "Working..." : this.status;
    return bar;
  }
}

/** `alice@users` is shown as `alice`; anything else is left whole. */
function nameOf(address) {
  return address.endsWith("@users") ? address.slice(0, -"@users".length) : address;
}

/** Drop the seconds, which no inbox column has ever needed. */
function shortDate(date) {
  const parts = SERVER_DATE.exec(date);
  return parts ? `${parts[1]}.${parts[2]}.${parts[3]} ${parts[4]}:${parts[5]}` : date;
}

function el(tag, className, text) {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (text !== undefined) node.textContent = text;
  return node;
}

function button(label, onClick, disabled = false) {
  const node = el("button", "mail-button", label);
  node.type = "button";
  node.disabled = disabled;
  node.addEventListener("click", onClick);
  return node;
}

function field(form, label, type, value, onInput) {
  const wrap = el("label", "mail-field");
  wrap.append(el("span", null, label));
  const input = document.createElement("input");
  input.type = type;
  input.value = value;
  input.addEventListener("input", () => onInput(input.value));
  wrap.append(input);
  form.append(wrap);
  return input;
}
