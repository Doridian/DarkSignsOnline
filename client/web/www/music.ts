// What `Music` does.
//
// A script names a file and this plays it. The command has already had its
// path resolved against the console's working directory -- see
// `resolve_music` in `game/mod.rs` -- so what arrives here is a verb and, for
// the two verbs that take one, a full path.
//
// The bytes never come through a console. The tree holds the name and the
// page holds the bytes, so playing a song is a matter of turning the one into
// the other and handing the browser a URL it can stream from: an `<audio>`
// element reads a file off disk as it goes and can seek within it, which is
// what makes a forty-megabyte track cost nothing to start.

import type { Ask } from "./types.js";

export class MusicPlayer {
  readonly audio = new Audio();
  /** The object URL currently loaded, so it can be released on the next one. */
  url: string | null = null;

  constructor(
    readonly ask: Ask,
    readonly notify: (text: string) => void,
  ) {}

  /** Run one `Music` command. */
  async run(command: string): Promise<void> {
    const trimmed = command.trim();
    const cut = trimmed.search(/\s/);
    const verb = (cut < 0 ? trimmed : trimmed.slice(0, cut)).toLowerCase();
    const rest = cut < 0 ? "" : trimmed.slice(cut + 1).trim();

    switch (verb) {
      case "play":
      case "loop":
        await this.play(rest, verb === "loop");
        break;
      case "stop":
        this.stop();
        break;
      case "volume": {
        // The game counts 0 to 100 and the element counts 0 to 1.
        const level = Number(rest);
        if (Number.isFinite(level)) {
          this.audio.volume = Math.min(1, Math.max(0, level / 100));
        }
        break;
      }
      default:
        this.notify(`Music: ${verb || "(nothing)"} is not something it can do.`);
    }
  }

  async play(path: string, loop: boolean): Promise<void> {
    if (!path) {
      this.notify("Music: play what?");
      return;
    }
    // The filesystem is asked what is at the path, and answers with the file
    // rather than its contents: a handle the browser can stream from.
    let file: File | null;
    try {
      file = await this.ask({ type: "fileAt", path });
    } catch (err) {
      this.notify(`Music: ${err instanceof Error ? err.message : err}`);
      return;
    }
    if (!file) {
      this.notify(`Music: the contents of ${path} are missing.`);
      return;
    }
    // Nothing in the filesystem knows a song from a script -- a file is
    // bytes -- so the name is what says whether this is worth handing to
    // `<audio>`, and the filesystem has already put that on the file as its
    // type. Saying so beats handing the element a script and letting it fail
    // its own way.
    if (!file.type.startsWith("audio/")) {
      this.notify(`Music: ${path} is not a sound file.`);
      return;
    }

    this.stop();
    // The type comes from the tree, put back on by the fs worker: OPFS does
    // not remember what a file was and hands one back with a type of "",
    // which leaves the element sniffing for a decoder instead of picking one.
    this.url = URL.createObjectURL(file);
    this.audio.src = this.url;
    this.audio.loop = loop;
    try {
      await this.audio.play();
    } catch {
      // Browsers refuse to start audio until the page has been interacted
      // with. A player who typed the command has done that, so this is the
      // rarer case of a script playing something before they ever clicked.
      this.notify(`Music: the browser would not start ${path} until you click the page.`);
    }
  }

  stop(): void {
    this.audio.pause();
    // Releasing the URL is what lets the file be closed; without it every
    // track a long session played would be held open until the tab went.
    if (this.url) {
      this.audio.removeAttribute("src");
      URL.revokeObjectURL(this.url);
      this.url = null;
    }
  }
}
