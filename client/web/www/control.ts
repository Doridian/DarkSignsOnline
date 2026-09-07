// The control block a console and its worker share.
//
// One `SharedArrayBuffer` of two integers: the state, which the worker parks
// on with `Atomics.wait`, and the length of whatever is waiting in the other
// buffer. Both sides need the same numbers, so they are named once here
// rather than twice.

/** The worker is parked, waiting for an answer. */
export const WAITING = 0;
/** An answer is in the buffer, and its length is in the second slot. */
export const READY = 1;
/** No more input is coming; the running script ends. */
export const CLOSED = 2;

/**
 * The answer the page owes a blocked worker was never there to give.
 *
 * A typed line always exists once the player has pressed return, but a file
 * can have gone since the tree last heard about it, and "nothing" has to be
 * tellable from "no bytes".
 */
export const ABSENT = -1;

/**
 * Room for one answer, in bytes.
 *
 * It holds a typed line, or as much of a file as a script may look at in one
 * go -- `Cat` on a song, which is the only thing that asks. The larger of
 * the two sets the size, and the interpreter caps its own read to match, so
 * an answer never has to be sent in pieces.
 */
export const ANSWER_CAPACITY = 65536;

/**
 * A filesystem answer is full and more of it is waiting.
 *
 * The console asks again rather than the buffer being made big enough for
 * the worst case: a `Dir` of a large tree or a read of a long script has no
 * fixed size, and sizing the buffer for one would waste the space four times
 * over for the sake of a case that hardly happens.
 */
export const MORE = 3;

/**
 * Room for one filesystem answer, in bytes.
 *
 * Bigger than an input line because it holds a file: most scripts fit in one
 * go, and anything that does not is sent in pieces.
 */
export const FS_ANSWER_CAPACITY = 1 << 20;
