// The control block a console and its worker share.
//
// One `SharedArrayBuffer` of two integers: the state, which the worker parks
// on with `Atomics.wait`, and the length of the line waiting in the other
// buffer. Both sides need the same three numbers, so they are named once
// here rather than twice.

/** The worker is parked, waiting for a line. */
export const WAITING = 0;
/** A line is in the buffer, and its length is in the second slot. */
export const READY = 1;
/** No more input is coming; the running script ends. */
export const CLOSED = 2;

/** Room for one line of input, in bytes. */
export const INPUT_CAPACITY = 8192;
