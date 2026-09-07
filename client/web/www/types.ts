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

// ---- the filesystem the four consoles share ------------------------------

/**
 * What became of one path.
 *
 * Every change any console makes is reported as one of these, which is what
 * keeps the other three sessions, the saved tree and the file panel in step
 * with it. Directories are in here as well as files: an empty one is implied
 * by nothing else, and `MKDIR` at one console has to reach the rest.
 */
export type FileChange =
  | { op: "write"; path: string; contents: string }
  | { op: "delete"; path: string }
  | { op: "mkdir"; path: string }
  | { op: "rmdir"; path: string };

/**
 * The whole tree, as `listTree` reports it.
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
  | { type: "wasReset" }
  | { type: "console"; event: ConsoleEvent }
  | { type: "fileChanged"; change: FileChange }
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
      input: SharedArrayBuffer;
      width: number;
      preSpace: number;
      files: Record<string, string>;
      apiRoot?: string;
    }
  | { type: "credentials"; username: string; password: string }
  | { type: "command"; line: string }
  | { type: "script"; source: string; args?: string[] }
  | { type: "runFile"; path: string }
  | { type: "syncFile"; change: FileChange }
  | { type: "layout"; width: number; preSpace: number }
  | { type: "reset" }
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
  | { type: "listFiles" }
  | { type: "listTree" }
  | { type: "readFile"; path: string }
  | { type: "writeFile"; path: string; contents: string }
);
