// What passes between the page, the workers and the wasm, described once.
//
// Types only: nothing here survives compilation. It is the other half of
// `web/src/console.rs` and the view types in `web/src/lib.rs`, which
// serialise exactly these shapes, so a change on one side belongs on the
// other.

/** One styled run of text, as `markup.rs` parsed it. */
export interface Run {
  text: string;
  font: string;
  size: number;
  bold: boolean;
  italic: boolean;
  underline: boolean;
  strikethrough: boolean;
  /** `#rrggbb`, already converted from the game's packing. */
  color: string;
  flash: "none" | "normal" | "fast" | "slow";
}

export interface LineEvent {
  kind: "line";
  channel: "say" | "comm" | "chat";
  runs: Run[];
  align: "left" | "center" | "right";
  preSpace: boolean;
  replace: boolean;
}

export interface ClearEvent {
  kind: "clear";
}

export interface LineUpEvent {
  kind: "lineUp";
}

export interface DrawEvent {
  kind: "draw";
  y: number;
  color: string;
  mode: string;
  segments: number;
}

/** One piece of a `DrawCustom` band: a width in pixels and a colour. */
export interface Band {
  width: number;
  color: string;
}

export interface DrawCustomEvent {
  kind: "drawCustom";
  y: number;
  bands: Band[];
}

export interface DrawEvenEvent {
  kind: "drawEven";
  y: number;
  colors: string[];
}

export interface EditEvent {
  kind: "edit";
  path: string;
}

export interface MusicEvent {
  kind: "music";
  command: string;
}

export interface MailEvent {
  kind: "mail";
}

/**
 * `ChatView` from a script.
 *
 * Not the pane's visibility -- F5 does that, as in the original. This is
 * whether incoming chat is also written to the communications log.
 */
export interface ChatViewEvent {
  kind: "chatView";
  enabled: boolean;
}

/** A line a script sent with `ChatSend`, already accepted by the server. */
export interface ChatSentEvent {
  kind: "chatSent";
  /** The row it was given, so the poller does not show it a second time. */
  id: number;
  /** Already rendered as `<who>  text` or `* who text`. */
  text: string;
}

export interface YDivEvent {
  kind: "yDiv";
  value: number;
}

export type ConsoleEvent =
  | LineEvent
  | ClearEvent
  | LineUpEvent
  | DrawEvent
  | DrawCustomEvent
  | DrawEvenEvent
  | EditEvent
  | MusicEvent
  | MailEvent
  | ChatViewEvent
  | ChatSentEvent
  | YDivEvent;

/** Enough of a line for the renderer to draw one it made up itself. */
export type PartialLine = Omit<LineEvent, "kind" | "channel">;

// ---- what the windows are answered with ---------------------------------

export interface MailMessage {
  id: number;
  from: string;
  subject: string;
  body: string;
  date: string;
  unread: boolean;
}

export interface MailView {
  /** How many of these arrived in the fetch that produced this view. */
  added: number;
  messages: MailMessage[];
}

/** One thing somebody said, as `chat.php` recorded it. */
export interface ChatLine {
  id: number;
  /** The account that said it; identity is the game account, not a nick. */
  from: string;
  text: string;
  /** A `/me`. */
  action: boolean;
  /** `dd.mm.yyyy HH:MM:SS`, or empty for a line echoed before a poll. */
  date: string;
}

/** What became of a line typed at the chat box. */
export type Said =
  | { kind: "sent"; line: ChatLine }
  | { kind: "nothing" }
  | { kind: "unknown"; command: string };

// ---- the one filesystem --------------------------------------------------

/**
 * What became of one path.
 *
 * There is one tree, in the fs worker, so this is no longer how four copies
 * of it are kept in step. It is only how the file panel learns what a script
 * did without having to ask again.
 */
export type FileChange =
  | { op: "file"; path: string; size: number }
  | { op: "dir"; path: string }
  | { op: "gone"; path: string };

/** One entry in a directory listing. */
export interface Entry {
  name: string;
  isDir: boolean;
}

/**
 * The whole tree, as the panel draws it.
 *
 * `dirs` holds every directory including `/`; `files` holds the rest. The
 * panel applies `FileChange`s to this rather than asking for it again.
 */
export interface Tree {
  dirs: string[];
  files: Array<{ path: string; size: number }>;
}

/** One request to a worker, and the answer it resolves with. */
export type Ask = (message: { type: string } & Record<string, unknown>) => Promise<any>;

// ---- the messages between the page and a worker --------------------------

export interface WorkerAnswer {
  type: "answer";
  token: number;
  value: unknown;
}

export interface WorkerFailure {
  type: "failed";
  token: number;
  message: string;
}

/** What a worker sends the page. */
export type FromWorker =
  | { type: "ready"; cwd: string; persistent: boolean; restored: number }
  | { type: "credentialsSet" }
  | { type: "console"; event: ConsoleEvent }
  | { type: "missingFile"; path: string }
  | { type: "wantInput"; mode: string; prompt: string }
  | { type: "done"; cwd: string }
  | { type: "error"; message: string; cwd: string }
  | WorkerAnswer
  | WorkerFailure;

/** What the page sends a worker, either of its own accord or for a window. */
export type ToWorker =
  | {
      type: "boot";
      consoleId: number;
      control: SharedArrayBuffer;
      answer: SharedArrayBuffer;
      /** The channel to the fs worker, and the buffers it answers into. */
      fsPort: MessagePort;
      fsControl: SharedArrayBuffer;
      fsAnswer: SharedArrayBuffer;
      width: number;
      preSpace: number;
      apiRoot?: string;
    }
  | { type: "credentials"; username: string; password: string }
  | { type: "command"; line: string }
  | { type: "script"; source: string; args?: string[] }
  | { type: "runFile"; path: string }
  | { type: "layout"; width: number; preSpace: number }
  | Asked;

/** A window's question, which carries the token its answer comes back with. */
export type Asked = { token: number } & (
  | { type: "mailList" }
  | { type: "mailFetch" }
  | { type: "mailMarkRead"; id: number }
  | { type: "mailSend"; to: string; subject: string; body: string }
  | { type: "libraryTables" }
  | { type: "libraryList"; category: string }
  | { type: "libraryDownload"; id: number }
  | { type: "libraryRemovable" }
  | { type: "libraryRemove"; id: number }
  | {
      type: "libraryUpload";
      category: string;
      title: string;
      version: string;
      description: string;
      path: string;
    }
  | { type: "chatFetch"; last: number }
  | { type: "chatSay"; typed: string }
  | { type: "textspaceLoad"; channel: number }
  | { type: "textspaceSave"; channel: number; text: string }
);

// ---- the messages between the page and the fs worker ---------------------

/** What the page sends the filesystem. */
export type ToFs =
  | { type: "start"; files: Record<string, string> }
  | {
      type: "attach";
      consoleId: number;
      port: MessagePort;
      control: SharedArrayBuffer;
      answer: SharedArrayBuffer;
    }
  | ({ type: "ask"; token: number } & FsAsk);

/** One question the page has about the tree. */
export type FsAsk =
  | { ask: "listTree" }
  | { ask: "listFiles" }
  | { ask: "readFile"; path: string }
  | { ask: "writeFile"; path: string; contents: string }
  | { ask: "fileAt"; path: string }
  | { ask: "putFile"; path: string; file: File }
  | { ask: "reset" };

/** What the filesystem sends the page. */
export type FromFs =
  | { type: "fsReady"; persistent: boolean; restored: number }
  | { type: "changed"; changes: FileChange[] }
  | WorkerAnswer
  | WorkerFailure;
