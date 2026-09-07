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

import type { BlobStore } from "./storage.js";
import type { Ask, BlobRef } from "./types.js";

export class MusicPlayer {
  readonly audio = new Audio();
  /** The object URL currently loaded, so it can be released on the next one. */
  url: string | null = null;

  constructor(
    readonly blobs: BlobStore,
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
    // The tree is the worker's, so the path is resolved to a set of bytes by
    // asking it. Text answers null here, which is the honest reply: a script
    // is not something to play.
    let found: BlobRef | null;
    try {
      found = await this.ask({ type: "blobAt", path });
    } catch (err) {
      this.notify(`Music: ${err instanceof Error ? err.message : err}`);
      return;
    }
    if (!found) {
      this.notify(`Music: ${path} is not a sound file.`);
      return;
    }
    const file = await this.blobs.file(found.id);
    if (!file) {
      this.notify(`Music: the contents of ${path} are missing.`);
      return;
    }

    this.stop();
    // OPFS does not remember what a file was, so `getFile` hands back a type
    // of "". `slice` puts the tree's answer back on without copying a byte,
    // which is what lets the element pick a decoder rather than sniff for
    // one -- and the tree is where the type belongs anyway, since that is
    // what `Dir` and the file panel read.
    this.url = URL.createObjectURL(file.slice(0, file.size, found.mediaType));
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
