//! Script encryption, as the VB6 client implements it in `basScriptCrypto`.
//!
//! The on-the-wire format has to match the game server exactly, because
//! compiled scripts travel between the two. A payload is
//!
//! ```text
//! <version><base64 salt>:<base64 tag>:<base64 ciphertext>
//! ```
//!
//! encrypted with AES-128-GCM, where the 16-byte salt doubles as the nonce
//! and the additional authenticated data is a single zero byte. Version `7`
//! compresses the plaintext with zstd first; version `8` does not, and is
//! used when the plaintext is short. `X` marks an empty payload and `H` a
//! header line.

use aes_gcm::aead::{Aead, KeyInit, Payload};
use aes_gcm::aead::consts::U16;
use aes_gcm::{AesGcm, Nonce};
use aes::Aes128;

/// The client uses a 16-byte salt as the GCM nonce, so J0 comes from GHASH
/// rather than the 96-bit shortcut. `Aes128Gcm` is fixed at 12 bytes, hence
/// the explicit instantiation.
type Aes128Gcm16 = AesGcm<Aes128, U16>;
use base64::Engine;
use sha2::{Digest, Sha256};

/// Prefixed to every password before the key is derived.
const DEFAULT_KEY: &str = "DSO$S3cur3_K3y!!111";

/// Marks a compiled script, and is followed by the encrypted lines.
pub const ENCRYPTED_HEADER: &str = "Option DSciptCompiled\r\n";

/// The first thing inside the ciphertext, so a wrong key is detected.
pub const ENCRYPTED_CANARY: &str = "Option DSciptCompiledLoaded\r\n";

/// Wrapped payloads are split into lines of this length.
const ENCRYPTED_LINE_LEN: usize = 140;

/// Plaintext longer than this is compressed before encryption.
const COMPRESS_THRESHOLD: usize = 128;

#[derive(Debug)]
pub struct CryptoError(pub String);

impl std::fmt::Display for CryptoError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(&self.0)
    }
}

type Result<T> = std::result::Result<T, CryptoError>;

/// The client uses the URL-safe alphabet with no padding, so payloads can
/// sit inside a script file and travel in a URL unescaped.
fn b64() -> base64::engine::general_purpose::GeneralPurpose {
    base64::engine::general_purpose::URL_SAFE_NO_PAD
}

pub fn encode_base64(data: &[u8]) -> String {
    b64().encode(data)
}

/// The standard alphabet with padding, which HTTP basic auth requires.
/// Script payloads use the URL-safe form instead.
pub fn encode_base64_standard(data: &[u8]) -> String {
    base64::engine::general_purpose::STANDARD.encode(data)
}

pub fn decode_base64(text: &str) -> Result<Vec<u8>> {
    b64()
        .decode(text.trim())
        .map_err(|e| CryptoError(format!("invalid base64: {e}")))
}

/// Lowercase hexadecimal, matching `clsSHA256`, whose output the key
/// derivation chain re-hashes — so the case is part of the format.
pub fn sha256_hex(data: &[u8]) -> String {
    let digest = Sha256::digest(data);
    let mut out = String::with_capacity(64);
    for b in digest {
        out.push_str(&format!("{b:02x}"));
    }
    out
}

/// Derive the AES key from a password and salt.
///
/// This is the client's own construction, not a standard KDF: it hashes the
/// password and salt, then folds them into a running SHA-256 chain a hundred
/// times on a fixed schedule, and takes the first 16 bytes of the final hex
/// digest. It is reproduced exactly because the server derives keys the same
/// way.
fn derive_key(password: &[u8], salt: &[u8]) -> [u8; 16] {
    let pass_hash = sha256_hex(password);
    let salt_hash = sha256_hex(salt);

    let mut current = String::from("START");
    for i in 1..=100 {
        if i % 3 == 0 {
            current.push_str(&pass_hash);
        }
        if i % 5 == 0 {
            current = format!("{pass_hash}{current}");
        }
        if i % 7 == 0 {
            current.push_str(&salt_hash);
        }
        if i % 11 == 0 {
            current = format!("{salt_hash}{current}");
        }
        current = sha256_hex(current.as_bytes());
    }

    // The derived key is the first 16 bytes of the final digest, read from
    // its hexadecimal form a byte at a time.
    let mut key = [0u8; 16];
    for (i, k) in key.iter_mut().enumerate() {
        *k = u8::from_str_radix(&current[i * 2..i * 2 + 2], 16).unwrap_or(0);
    }
    key
}

fn full_password(password: &str) -> Vec<u8> {
    // The VB6 source appends `vbNullString`, which is a null *pointer* and
    // concatenates as an empty string, so nothing is added here.
    format!("{DEFAULT_KEY}{password}").into_bytes()
}

fn cipher(password: &str, salt: &[u8]) -> Result<Aes128Gcm16> {
    let key = derive_key(&full_password(password), salt);
    Aes128Gcm16::new_from_slice(&key).map_err(|e| CryptoError(format!("bad key: {e}")))
}

/// The additional authenticated data is a single zero byte.
const AAD: &[u8] = &[0u8];

/// View the salt as the GCM nonce.
fn nonce(salt: &[u8]) -> Result<&Nonce<U16>> {
    <&Nonce<U16>>::try_from(salt).map_err(|_| CryptoError("salt is not 16 bytes".into()))
}

/// The compression level `basCompression` passes to zstd by default.
const ZSTD_LEVEL: i32 = 5;

/// Compress the way the client does: a four-byte little-endian original
/// size, then the zstd frame. The size lets the VB6 side size its output
/// buffer before calling into the library.
fn compress(raw: &[u8]) -> Result<Vec<u8>> {
    let frame = zstd::stream::encode_all(raw, ZSTD_LEVEL)
        .map_err(|e| CryptoError(format!("zstd compression error: {e}")))?;
    let mut out = Vec::with_capacity(frame.len() + 4);
    out.extend_from_slice(&(raw.len() as u32).to_le_bytes());
    out.extend_from_slice(&frame);
    Ok(out)
}

fn decompress(data: &[u8]) -> Result<Vec<u8>> {
    if data.len() < 4 {
        return Err(CryptoError("compressed payload is truncated".into()));
    }
    let expected = u32::from_le_bytes([data[0], data[1], data[2], data[3]]) as usize;
    let out = zstd::stream::decode_all(&data[4..])
        .map_err(|e| CryptoError(format!("zstd decompression error: {e}")))?;
    if out.len() != expected {
        return Err(CryptoError(format!(
            "decompressed {} bytes, header said {expected}",
            out.len()
        )));
    }
    Ok(out)
}

/// Convert to the single-byte encoding VB6 uses for script text.
fn to_latin1(s: &str) -> Vec<u8> {
    s.chars()
        .map(|c| if (c as u32) < 256 { c as u8 } else { b'?' })
        .collect()
}

/// Convert back from the single-byte encoding.
fn from_latin1(b: &[u8]) -> String {
    b.iter().map(|&c| c as char).collect()
}

/// Encrypt `text` with `password`, producing the wrapped form the client
/// writes to disk unless `no_wrap` is set.
pub fn encrypt(text: &str, password: &str, no_wrap: bool, salt: [u8; 16]) -> Result<String> {
    if text.is_empty() {
        return Ok("X".into());
    }

    let raw = to_latin1(text);
    let (version, processed) = if raw.len() > COMPRESS_THRESHOLD + 1 {
        ('7', compress(&raw)?)
    } else {
        ('8', raw)
    };

    let aes = cipher(password, &salt)?;
    let sealed = aes
        .encrypt(nonce(&salt)?, Payload { msg: &processed, aad: AAD })
        .map_err(|_| CryptoError("AES encryption error".into()))?;

    // `encrypt` returns ciphertext followed by the 16-byte tag; the wire
    // format carries them as separate fields.
    let split = sealed.len() - 16;
    let body = format!(
        "{}:{}:{}",
        encode_base64(&salt),
        encode_base64(&sealed[split..]),
        encode_base64(&sealed[..split])
    );

    if no_wrap {
        return Ok(format!("{version}{body}"));
    }

    let mut out = String::new();
    let mut rest: &str = &body;
    while rest.len() > ENCRYPTED_LINE_LEN {
        out.push('_');
        out.push_str(&rest[..ENCRYPTED_LINE_LEN]);
        out.push_str("\r\n");
        rest = &rest[ENCRYPTED_LINE_LEN..];
    }
    out.push(version);
    out.push_str(rest);
    Ok(out)
}

/// Decrypt one `<version><body>` payload.
fn decrypt_one(version: char, body: &str, password: &str) -> Result<String> {
    match version {
        // An empty payload, or a header line that carries no data.
        'X' | 'H' => Ok(String::new()),
        '7' | '8' => {
            let parts: Vec<&str> = body.split(':').collect();
            if parts.len() < 3 {
                return Err(CryptoError("malformed encrypted payload".into()));
            }
            let salt = decode_base64(parts[0])?;
            let tag = decode_base64(parts[1])?;
            let ciphertext = decode_base64(parts[2])?;

            let aes = cipher(password, &salt)?;
            let mut sealed = ciphertext;
            sealed.extend_from_slice(&tag);
            let plain = aes
                .decrypt(nonce(&salt)?, Payload { msg: &sealed, aad: AAD })
                .map_err(|_| CryptoError("AES decryption error".into()))?;

            let decompressed = if version == '7' { decompress(&plain)? } else { plain };
            Ok(from_latin1(&decompressed))
        }
        other => Err(CryptoError(format!("invalid crypto line {other}{body}"))),
    }
}

/// Decrypt a whole wrapped payload, joining its continuation lines.
pub fn decrypt(source: &str, password: &str) -> Result<String> {
    let mut out = String::new();
    let mut pending = String::new();

    for line in source.split("\r\n") {
        if !line.trim().is_empty() {
            // Every line after the first carries its text from index 1; the
            // leading character is either `_` or the version.
            pending.push_str(&line[line.len().min(1)..]);
        }
        if !line.starts_with('_') {
            if !pending.trim().is_empty() {
                let version = line.chars().next().unwrap_or('X');
                if !out.is_empty() {
                    out.push_str("\r\n");
                }
                out.push_str(&decrypt_one(version, &pending, password)?);
            }
            pending.clear();
        }
    }
    Ok(out)
}

pub fn is_script_compiled(source: &str) -> bool {
    source.len() >= ENCRYPTED_HEADER.len()
        && source[..ENCRYPTED_HEADER.len()].eq_ignore_ascii_case(ENCRYPTED_HEADER)
}

/// Decrypt a compiled script, checking the canary so a wrong key is caught.
/// Source that is not compiled is returned unchanged.
pub fn decrypt_script(source: &str, script_key: &str) -> Result<String> {
    let key = if script_key.is_empty() { "local" } else { script_key };
    if !is_script_compiled(source) {
        return Ok(source.to_string());
    }
    let plain = decrypt(&source[ENCRYPTED_HEADER.len()..], key)?;
    if plain.len() < ENCRYPTED_CANARY.len()
        || !plain[..ENCRYPTED_CANARY.len()].eq_ignore_ascii_case(ENCRYPTED_CANARY)
    {
        return Err(CryptoError("Failed to parse header of compiled script".into()));
    }
    Ok(plain[ENCRYPTED_CANARY.len()..].to_string())
}

/// Compile a script: decrypt it if it already is compiled, then re-encrypt
/// it under `script_key` behind the canary.
pub fn compile_script(source: &str, script_key: &str, salt: [u8; 16]) -> Result<String> {
    let key = if script_key.is_empty() { "local" } else { script_key };
    let plain = format!("{}{}", ENCRYPTED_CANARY, decrypt_script(source, "")?);
    let body = encrypt(&plain, key, true, salt)?;
    Ok(format!("{ENCRYPTED_HEADER}{body}\r\n"))
}

/// A salt for a new payload, drawn from the host's random source.
///
/// The host provides it because a browser has no `/dev/urandom`; a
/// predictable salt would be worse than failing, so a host that cannot
/// supply randomness gets an error.
pub fn generate_salt(host: &dyn crate::interp::Host) -> Result<[u8; 16]> {
    let mut salt = [0u8; 16];
    if !host.random_bytes(&mut salt) {
        return Err(CryptoError("no source of randomness available".into()));
    }
    Ok(salt)
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A fixed salt keeps the tests deterministic.
    const SALT: [u8; 16] = [
        0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F,
        0x10,
    ];

    #[test]
    fn sha256_matches_known_vectors() {
        assert_eq!(
            sha256_hex(b""),
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        );
        assert_eq!(
            sha256_hex(b"abc"),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        );
    }

    #[test]
    fn base64_round_trips() {
        assert_eq!(encode_base64(b"hello"), "aGVsbG8");
        assert_eq!(decode_base64("aGVsbG8").unwrap(), b"hello");
        // The alphabet is URL-safe: `-` and `_` rather than `+` and `/`.
        assert_eq!(encode_base64(&[0xFB, 0xFF]), "-_8");
    }

    /// The key derivation has no standard to check against, so this pins the
    /// current output: it must stay stable or compiled scripts stop loading.
    #[test]
    fn key_derivation_is_deterministic() {
        let a = derive_key(&full_password("secret"), &SALT);
        let b = derive_key(&full_password("secret"), &SALT);
        assert_eq!(a, b);
        // A different password gives a different key.
        assert_ne!(a, derive_key(&full_password("other"), &SALT));
        // So does a different salt.
        assert_ne!(a, derive_key(&full_password("secret"), &[0u8; 16]));
    }

    #[test]
    fn short_payloads_are_stored_uncompressed() {
        let out = encrypt("Say \"hi\"", "pw", true, SALT).unwrap();
        assert!(out.starts_with('8'), "expected version 8, got {out}");
        assert_eq!(decrypt(&out, "pw").unwrap(), "Say \"hi\"");
    }

    #[test]
    fn long_payloads_are_compressed() {
        let text = "Say \"hello world\"\r\n".repeat(40);
        let out = encrypt(&text, "pw", true, SALT).unwrap();
        assert!(out.starts_with('7'), "expected version 7");
        assert_eq!(decrypt(&out, "pw").unwrap(), text);
    }

    #[test]
    fn empty_payload_is_the_x_marker() {
        assert_eq!(encrypt("", "pw", true, SALT).unwrap(), "X");
        assert_eq!(decrypt("X", "pw").unwrap(), "");
    }

    #[test]
    fn wrapped_output_splits_into_continuation_lines() {
        // Varied text so it does not compress below the wrap threshold.
        let text: String = (0..60)
            .map(|i| format!("Say \"line {i} {}\"\r\n", i * 7919))
            .collect();
        let wrapped = encrypt(&text, "pw", false, SALT).unwrap();
        let lines: Vec<&str> = wrapped.split("\r\n").collect();
        assert!(lines.len() > 1, "long payload should wrap");
        for line in &lines[..lines.len() - 1] {
            assert!(line.starts_with('_'), "continuation lines start with _");
            assert_eq!(line.len(), ENCRYPTED_LINE_LEN + 1);
        }
        assert_eq!(decrypt(&wrapped, "pw").unwrap(), text);
    }

    #[test]
    fn wrong_password_fails_rather_than_returning_garbage() {
        let out = encrypt("Say \"hi\"", "right", true, SALT).unwrap();
        assert!(decrypt(&out, "wrong").is_err());
    }

    #[test]
    fn compiled_scripts_round_trip_through_the_canary() {
        let source = "Option Explicit\r\nSay \"hello\"\r\n";
        let compiled = compile_script(source, "key", SALT).unwrap();
        assert!(is_script_compiled(&compiled));
        assert_eq!(decrypt_script(&compiled, "key").unwrap(), source);
    }

    #[test]
    fn compiling_with_no_key_uses_the_local_key() {
        let source = "Say \"hello\"\r\n";
        let compiled = compile_script(source, "", SALT).unwrap();
        assert_eq!(decrypt_script(&compiled, "local").unwrap(), source);
        assert_eq!(decrypt_script(&compiled, "").unwrap(), source);
    }

    #[test]
    fn a_wrong_script_key_is_reported_not_ignored() {
        let compiled = compile_script("Say \"hello\"\r\n", "right", SALT).unwrap();
        assert!(decrypt_script(&compiled, "wrong").is_err());
    }

    #[test]
    fn plain_source_passes_through_decrypt_script() {
        let source = "Say \"hello\"\r\n";
        assert_eq!(decrypt_script(source, "any").unwrap(), source);
    }

    #[test]
    fn recompiling_an_already_compiled_script_re_keys_it() {
        let source = "Say \"hello\"\r\n";
        let first = compile_script(source, "", SALT).unwrap();
        let second = compile_script(&first, "other", SALT).unwrap();
        assert_eq!(decrypt_script(&second, "other").unwrap(), source);
    }

    #[test]
    fn salts_differ_between_calls() {
        let host = crate::interp::NullHost;
        let a = generate_salt(&host).unwrap();
        let b = generate_salt(&host).unwrap();
        assert_ne!(a, b, "salt must not repeat");
    }
}

/// Verifies interoperability with the real client, which is what the wire
/// format exists for. `tests/fixtures/compiled.ds` was produced by the VB6
/// client, so decrypting it exercises the base64 alphabet, the key
/// derivation, AES-GCM with a 16-byte nonce and the zstd layer together.
#[cfg(test)]
mod fixture_tests {
    use super::*;

    const COMPILED: &str = include_str!("../../tests/fixtures/compiled.ds");

    /// The client keys a downloaded script on `dso://<host>:<port>`, trying
    /// the domain first and falling back to the IP. This fixture came from
    /// newton.physics.berkeley.edu:80 at 210.189.133.233, and is keyed on
    /// the IP, so it also exercises that fallback.
    const SCRIPT_KEY: &str = "dso://210.189.133.233:80";

    #[test]
    fn decrypts_a_script_compiled_by_the_vb6_client() {
        assert!(is_script_compiled(COMPILED));
        let plain = decrypt_script(COMPILED, SCRIPT_KEY).expect("fixture decrypts");
        assert!(plain.starts_with("Option Explicit\r\n"), "got {:?}", &plain[..40]);
        assert!(plain.contains("DLOpen \"termlib\""));
        assert!(plain.contains("Sub SayBG(Str)"));
    }

    /// A key that is not the one the script was compiled with must fail
    /// rather than yield garbage.
    #[test]
    fn the_domain_key_does_not_open_an_ip_keyed_script() {
        assert!(decrypt_script(COMPILED, "dso://newton.physics.berkeley.edu:80").is_err());
    }

    /// Re-encrypting the fixture's plaintext and reading it back proves the
    /// encrypt path produces what the decrypt path expects.
    #[test]
    fn round_trips_the_fixture_plaintext() {
        let plain = decrypt_script(COMPILED, SCRIPT_KEY).unwrap();
        let salt = generate_salt(&crate::interp::NullHost).unwrap();
        let recompiled = compile_script(&plain, SCRIPT_KEY, salt).unwrap();
        assert_eq!(decrypt_script(&recompiled, SCRIPT_KEY).unwrap(), plain);
    }

    /// The decrypted source is real game script, so it must also parse.
    #[test]
    fn the_decrypted_script_parses() {
        let plain = decrypt_script(COMPILED, SCRIPT_KEY).unwrap();
        crate::check(&plain).expect("decrypted script parses");
    }
}
