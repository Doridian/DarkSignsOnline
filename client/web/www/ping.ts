// The round trip to the game server, in the title bar.
//
// The dot beside it says whether the player is signed in, which is a thing
// the client knows without asking anybody. Whether the server is still there
// is not: a session can sit at a prompt for an hour, and nothing about the
// page changes when the connection behind it has gone. So something has to
// ask, regularly, and this is it.
//
// ## Why not the chat poll
//
// Chat already asks the server about once a second, so it looks like the
// measurement is there for free. It is not, for two reasons.
//
// It is not regular. The poll runs only while somebody is reading the
// answer -- the pane up, or `ChatView` mirroring into the comm log -- and
// never in a background tab, so a player who has never opened chat would
// have an indicator that never moved.
//
// And it would be measuring the wrong thing. A window's question goes to
// whichever console is free, and a console blocked in `ReadLine` is not
// free: the question waits in a queue on the page until one is. A reading
// taken around that is a reading of how busy the terminals are. So the ping
// is the one request the page makes itself, with `fetch`, which nothing can
// be in front of.
//
// ## Why time.php
//
// It is the cheapest thing the server can be asked -- no account, no
// database, no bcrypt, one line -- which is what makes it affordable to ask
// every few seconds for as long as anyone is looking. The endpoint's own
// comment says so. A GET with no headers of its own is a simple request, so
// there is no preflight in front of it either, which would otherwise be half
// of what was being measured.

/** How often the round trip is measured, while the tab is in front. */
const INTERVAL = 5000;

/** Past this a request has not been answered; it has been lost. */
const TIMEOUT = 8000;

/** Above this many milliseconds a reading is fair rather than good. */
const FAIR = 150;

/** And above this it is poor. */
const POOR = 400;

/** What the bar says before the first answer, and in place of a number. */
const UNKNOWN = "--";

export class PingMeter {
  /** Where to ask, once a session has said. Nothing is asked before that. */
  private root: string | null = null;
  private timer: number | undefined;
  /** Set while a request is out, so a slow one does not stack up behind it. */
  private asking = false;

  constructor(readonly el: HTMLElement) {
    // A background tab is nobody looking at the title bar, and a reading
    // taken while the browser is throttling timers would be a reading of the
    // throttling. Coming back asks at once rather than waiting a tick.
    document.addEventListener("visibilitychange", () => this.restart());
    this.draw("unknown", UNKNOWN, "Waiting for the first reading.");
  }

  /**
   * Say where the API is.
   *
   * The page has no address of its own: the root is the interpreter's
   * constant, reported by a worker as it comes ready, so there is one copy
   * of it rather than one here and one in Rust. The first session to say so
   * is what starts the meter.
   */
  setApiRoot(root: string): void {
    const url = `${root.replace(/\/+$/, "")}/time.php`;
    if (url === this.root) {
      return;
    }
    this.root = url;
    this.restart();
  }

  /** Ask now, and keep asking, or stop if there is nobody to ask for. */
  private restart(): void {
    clearTimeout(this.timer);
    this.timer = undefined;
    if (this.root !== null && !document.hidden) {
      void this.measure();
    }
  }

  private async measure(): Promise<void> {
    const url = this.root;
    if (this.asking || url === null || document.hidden) {
      return;
    }
    this.asking = true;
    const stop = AbortSignal.timeout(TIMEOUT);
    const started = performance.now();
    try {
      // Measured to the end of the body rather than to the headers: it is
      // ten bytes in the same packet, and the whole answer arriving is what
      // a request costs.
      const response = await fetch(url, { cache: "no-store", signal: stop });
      const body = await response.text();
      const elapsed = Math.round(performance.now() - started);
      if (!response.ok) {
        this.lost(`The server answered ${response.status}.`);
      } else if (!Number.isFinite(Number(body.trim()))) {
        // Something answered, but not the API: a captive portal or a proxy
        // page is reachable in a way that the game is not.
        this.lost("Something other than the server answered.");
      } else {
        const band = elapsed < FAIR ? "good" : elapsed < POOR ? "fair" : "poor";
        this.draw(band, `${elapsed} ms`, `Round trip to the server: ${elapsed} ms.`);
      }
    } catch {
      // A dropped connection, a refused one, or one that never came back.
      // Which of the three it was is not worth a different word here.
      this.lost("The server did not answer.");
    } finally {
      this.asking = false;
    }
    if (this.root !== null && !document.hidden) {
      this.timer = setTimeout(() => void this.measure(), INTERVAL);
    }
  }

  /**
   * A reading that did not happen, which is worse news than a slow one.
   *
   * It says why in the tooltip rather than in the bar: the bar has room for
   * a number and the reason is a sentence, and the one thing a glance needs
   * is that there was no answer at all.
   */
  private lost(why: string): void {
    this.draw("lost", UNKNOWN, why);
  }

  private draw(state: "unknown" | "good" | "fair" | "poor" | "lost", text: string, why: string): void {
    this.el.textContent = text;
    this.el.className = state;
    this.el.title = why;
  }
}
