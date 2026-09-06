# The cost of byte-accurate strings

Why the `*B` limitation in [`README.md`](../README.md) stays unfixed, measured
rather than assumed.

`Value::Str` holds an `Rc<str>` ([`value.rs`](../src/value.rs)), which cannot
represent half a UTF-16 unit, so `LenB(LeftB("ABC", 3))` reports 4 instead of
3. Fixing that means holding the little-endian byte image instead —
`Rc<[u8]>`. An `Rc<[u16]>` does *not* fix it, because an odd byte count is
still unrepresentable. So the question is what `Rc<str>` → `Rc<[u8]>` costs.

## Method

Two layers, because the raw numbers and the in-context numbers answer
different questions:

- **Microbenchmarks** of the representation ops on both layouts, to price
  concat, comparison and the boundary decode on their own.
- **In-interpreter probes** — 2M iterations, median of 5 — running real
  VBScript through `GameHost`. Each probe subtracts a matched statement
  floor, so the figures are attributable to the string work rather than to
  tree-walking: an assign floor of **97.7 ns** (`r = a`) and a one-argument
  builtin dispatch floor of **153.8 ns** (`r = Abs(x)`).

Baseline for scale: the 301-script corpus runs in **1.70 s**. Call
frequencies below are static site counts over the 603 `.ds` files.

Native x86-64, `--release`. WASM's relative costs differ — allocation is
typically pricier there, which widens the boundary gap rather than narrowing
it.

## What gets faster

`LenB` and friends allocate a whole intermediate buffer just to index into
it — `bytes_of` in [`builtins/strings.rs`](../src/builtins/strings.rs), and
`utf16()` on the non-`B` path. Under `Rc<[u8]>` they become slicing.

| Op | Today, above dispatch floor | Under `Rc<[u8]>` | Δ |
|---|---|---|---|
| `LenB` | 46.9 ns | `len()` → ~0 | −47 ns |
| `Len` | 81.9 ns | `len()/2` → ~0 | −82 ns |
| `LeftB` | 99.5 ns | slice, no alloc | −~100 ns |
| `Left` | 150.9 ns | slice, no alloc | −~150 ns |
| `MidB` | 135.1 ns | slice, no alloc | −~135 ns |
| `Mid` | 191.5 ns | slice, no alloc | −~190 ns |

Binary comparison also improves — 20.7 → 11.8 ns at 42 chars, 1041 → 720 ns
at 2.7 KB (0.57–0.69×). That matters more than it looks: `Dictionary` scans
linearly with `key_eq` ([`objects/dictionary.rs`](../src/objects/dictionary.rs)),
so every lookup pays it O(n) times.

`Value` does not grow. `Rc<str>`, `Rc<[u8]>` and `Rc<[u16]>` are all 16-byte
fat pointers, so the enum stays the same size either way.

## What gets slower

**The host boundary, which dominates everything else.** Every `&str`-taking
API — 75 methods across [`console.rs`](../src/game/console.rs) (16),
[`fs.rs`](../src/game/fs.rs) (40), [`server.rs`](../src/game/server.rs) (6)
and [`interp.rs`](../src/interp.rs) (13), plus all of `markup.rs`,
`protocol.rs`, `crypto.rs`, `cli.rs` and the `regex` crate — needs a real
`str`. Today `to_vb_string()` hands one over as a refcount bump. Under bytes
it becomes decode-and-allocate:

| String | `Rc<str>` | `Rc<[u8]>` |
|---|---|---|
| 42 chars (console line) | 0.2 ns | 57.8 ns (~300×) |
| 2.7 KB (script, response) | 0.2 ns | 1718 ns (~8900×) |

`Say` is the most common operation in the corpus — 3355 sites, plus 484
`SaySlow`. Its current string work is 96.8 ns per call, so ~58 ns of decode
makes it about **60% more expensive**.

**Unicode-aware functions regress.** `LCase`/`UCase`/`Trim`/`Replace`/`Split`
(59 sites) use Rust's `str` routines directly today; under bytes they decode,
operate, then re-encode. Text-mode comparison (`compare_str`, which already
collects `to_uppercase()` into a `Vec<char>`) measured 1.04–1.13× slower.

**Concat regresses on long strings.** 0.89× at 42 chars — a wash, marginally
faster — but **1.45× at 2.7 KB**, because it copies twice the bytes. `&` is
the corpus's dominant operator at 1373 sites, and accumulator loops build
long strings.

**Memory doubles.** +100% on all string heap for ASCII text, which DSO is
almost entirely. That lands hardest where there is least room: the
[WASM build](../web/), where unbounded console scrollback
(`events: Vec<ConsoleEvent>`) and script source both sit in a constrained
heap.

## Net, weighted by the corpus

Measured per-call deltas against static call counts:

| | |
|---|---|
| `Say` + `SaySlow` (3839 × +58 ns) | **+222.7 µs** |
| `LCase`/`Trim`/`Split`/`Replace`/`UCase` (59 × ~+115 ns) | +6.8 µs |
| `&` (1373 × ~+3 ns) | +4.1 µs |
| **Total regression** | **≈ +234 µs** |
| `Mid`/`Left`/`Right`/`Len`/`InStr`/`Asc` (~162 sites) | ≈ −12 µs |
| **Net** | **≈ 19:1 against** |

Static counts proxy for dynamic frequency, which almost certainly
*understates* the regression: `Say` is the operation most likely to sit
inside a loop.

The payoff column is empty where it counts — **zero `*B` uses in 603 `.ds`
files**. And the wins on `Len`/`Mid`/`Left` are not exclusive to the
rewrite: `Len` could count `encode_utf16()` without collecting, and
`Left`/`Mid` could slice by char index directly.

## If it ever has to be fixed

Keep `Str(Rc<str>)` as the fast path and add a second arm — `StrB(Rc<[u8]>)`
— produced only when `LeftB`/`MidB`/`RightB`/`ChrB` land on an odd byte
count. Every figure above stays where it is: the cost is one
near-perfectly-predicted branch, below the ~5 ns noise floor of these
measurements, and `Value` does not grow because both arms are 16-byte fat
pointers.

The price is correctness surface rather than speed. Every `match` on
`Value::Str` needs a companion arm, and one missed in a `_ =>` case is a
silent wrong answer rather than a compile error.

## Verdict

Performance argues against the full `Rc<[u8]>` conversion, lopsidedly: a
~19:1 net regression concentrated in the hottest operation in the codebase,
plus a 2× memory cost that bites worst on the WASM target, bought for a
feature with no uses and three test assertions. The churn argument in the
README holds up under measurement; it is simply the smaller half of the
objection.

Separately worth doing on its own: the `Len`/`Left`/`Mid` allocations are
82–191 ns of pure waste today, fixable with no representation change and no
correctness risk.
