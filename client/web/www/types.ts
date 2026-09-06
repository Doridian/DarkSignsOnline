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

export interface ChatVisibleEvent {
  kind: "chatVisible";
  visible: boolean;
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
  | ChatVisibleEvent
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
  | { type: "fileChanged"; path: string; contents: string | null }
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
  | { type: "syncFile"; path: string; contents: string | null }
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
  | { type: "textspaceLoad"; channel: number }
  | { type: "textspaceSave"; channel: number; text: string }
  | { type: "listFiles" }
  | { type: "readFile"; path: string }
  | { type: "writeFile"; path: string; contents: string }
);
