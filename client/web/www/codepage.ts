// The client's single-byte code page, as the page spells it.
//
// The engine's copy is [`codepage.rs`](../../src/codepage.rs); this is the
// same windows-1252 for the one place the page turns bytes into text itself,
// which is the editor. Decoding is the browser's own -- `TextDecoder`
// implements exactly the mapping the engine does, five undefined positions
// and all -- so only the other direction is written out here, because
// `TextEncoder` speaks UTF-8 and nothing else.

const decoder = new TextDecoder("windows-1252");

/** Bytes 0x80..0x9F, the only ones that differ from Latin-1. */
const HIGH = [
  0x20ac, // €
  0x0081, // undefined in the code page
  0x201a, // ‚
  0x0192, // ƒ
  0x201e, // „
  0x2026, // …
  0x2020, // †
  0x2021, // ‡
  0x02c6, // ˆ
  0x2030, // ‰
  0x0160, // Š
  0x2039, // ‹
  0x0152, // Œ
  0x008d, // undefined in the code page
  0x017d, // Ž
  0x008f, // undefined in the code page
  0x0090, // undefined in the code page
  0x2018, // ‘
  0x2019, // ’
  0x201c, // “
  0x201d, // ”
  0x2022, // •
  0x2013, // –
  0x2014, // —
  0x02dc, // ˜
  0x2122, // ™
  0x0161, // š
  0x203a, // ›
  0x0153, // œ
  0x009d, // undefined in the code page
  0x017e, // ž
  0x0178, // Ÿ
];

/** Code point to byte, for the characters that are not their own byte. */
const BYTE_OF = new Map<number, number>(HIGH.map((cp, i) => [cp, 0x80 + i]));

/** What VB6 put in place of a character the code page cannot hold. */
const SUBSTITUTE = 0x3f; // "?"

/** The characters some bytes spell. */
export function decode(bytes: Uint8Array): string {
  return decoder.decode(bytes);
}

/** The bytes some characters are spelled with, substituting where none is. */
export function encode(text: string): Uint8Array {
  const out = new Uint8Array(text.length);
  let n = 0;
  for (const c of text) {
    const cp = c.codePointAt(0) as number;
    out[n++] =
      cp <= 0x7f || (cp >= 0xa0 && cp <= 0xff) ? cp : (BYTE_OF.get(cp) ?? SUBSTITUTE);
  }
  // `text.length` counts UTF-16 units, so an astral character reserved two
  // slots and filled one. Every one of those is a substitute anyway.
  return out.subarray(0, n);
}
