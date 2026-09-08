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
 * Room for one answer from the page, in bytes.
 *
 * It holds a typed line, which is the only thing the page is ever asked for.
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
 * Bigger than an input line because it holds a file: most files fit in one
 * go, and anything that does not -- a long `Dir`, or a song -- is sent in
 * pieces.
 */
export const FS_ANSWER_CAPACITY = 1 << 20;

/**
 * The request that asks for the rest of an answer that did not fit.
 *
 * Not a question about the filesystem at all -- the worker recognises it
 * before it looks at what was asked -- so both sides name it here rather
 * than spelling the same JSON twice.
 */
export const FS_MORE = '{"op":"more"}';
