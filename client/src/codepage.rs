//! The client's single-byte code page.
//!
//! VBScript on a Western Windows is a windows-1252 machine: `Chr(147)` is a
//! left curly quote, `Asc` gives back 147, and a file opened `For Binary`
//! hands over one character per byte through the same table. This module is
//! that table, in one place, because the client used to spell it out four
//! separate times -- `Chr`, `Asc`, and the two file boundaries -- and each
//! spelling had quietly settled on Latin-1 instead.
//!
//! The difference is thirty-two bytes wide. Latin-1 spends 0x80..0x9F on the
//! C1 control characters, which nothing prints and no script types;
//! windows-1252 spends them on the punctuation a word processor produces --
//! the curly quotes, the dashes, the ellipsis. That is where the game's own
//! mission text came from, so those are the bytes it actually contains.
//!
//! [`decode`] is total and injective over all 256 bytes: the five positions
//! windows-1252 leaves undefined map to the C1 control of the same value,
//! which is what the WHATWG encoding standard specifies and what makes the
//! round trip through a file exact.

/// Bytes 0x80..0x9F, the only ones that differ from Latin-1.
const HIGH: [char; 32] = [
    '\u{20AC}', // €
    '\u{0081}', // undefined in the code page
    '\u{201A}', // ‚
    '\u{0192}', // ƒ
    '\u{201E}', // „
    '\u{2026}', // …
    '\u{2020}', // †
    '\u{2021}', // ‡
    '\u{02C6}', // ˆ
    '\u{2030}', // ‰
    '\u{0160}', // Š
    '\u{2039}', // ‹
    '\u{0152}', // Œ
    '\u{008D}', // undefined in the code page
    '\u{017D}', // Ž
    '\u{008F}', // undefined in the code page
    '\u{0090}', // undefined in the code page
    '\u{2018}', // ‘
    '\u{2019}', // ’
    '\u{201C}', // “
    '\u{201D}', // ”
    '\u{2022}', // •
    '\u{2013}', // –
    '\u{2014}', // —
    '\u{02DC}', // ˜
    '\u{2122}', // ™
    '\u{0161}', // š
    '\u{203A}', // ›
    '\u{0153}', // œ
    '\u{009D}', // undefined in the code page
    '\u{017E}', // ž
    '\u{0178}', // Ÿ
];

/// What VB6 put in place of a character the code page cannot hold.
pub const SUBSTITUTE: u8 = b'?';

/// The character one byte spells.
pub fn decode(byte: u8) -> char {
    match byte {
        0x80..=0x9F => HIGH[(byte - 0x80) as usize],
        other => other as char,
    }
}

/// The byte one character is spelled with, or `None` when it has none.
///
/// Callers substitute rather than refuse, because that is what a VB6 write
/// through the code page did. The character stays representable in memory;
/// it is only the byte form that cannot hold it.
pub fn encode(c: char) -> Option<u8> {
    match c as u32 {
        // Below the C1 block and above it, byte and code point agree.
        0x00..=0x7F | 0xA0..=0xFF => Some(c as u8),
        _ => HIGH.iter().position(|&h| h == c).map(|i| 0x80 + i as u8),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn every_byte_is_a_different_character() {
        let mut seen: Vec<char> = (0..=255u8).map(decode).collect();
        seen.sort_unstable();
        seen.dedup();
        assert_eq!(seen.len(), 256, "the code page is not injective");
    }

    #[test]
    fn every_byte_survives_the_round_trip() {
        for b in 0..=255u8 {
            assert_eq!(encode(decode(b)), Some(b), "byte {b:#04x}");
        }
    }

    #[test]
    fn the_punctuation_latin_1_wastes_is_spelled() {
        assert_eq!(decode(0x93), '\u{201C}');
        assert_eq!(decode(0x97), '—');
        assert_eq!(decode(0x80), '€');
        assert_eq!(encode('\u{201C}'), Some(0x93));
    }

    #[test]
    fn a_character_outside_the_code_page_has_no_byte() {
        assert_eq!(encode('\u{4E2D}'), None);
        // A C1 control the code page spends on punctuation is not itself
        // storable: the byte it would take spells the punctuation instead.
        assert_eq!(encode('\u{0093}'), None);
    }
}
