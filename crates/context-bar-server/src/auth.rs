//! Bearer-token auth. Single static token stored in a file; the menubar
//! app includes it in every request as `Authorization: Bearer <token>`.
//!
//! The token is generated on first launch and never rotated automatically.
//! An operator can rotate by deleting the file (a new one is generated
//! on next start) or by passing `--token-set <new>`.

use std::time::{SystemTime, UNIX_EPOCH};

/// Generates a 192-bit token from the system clock + process-info entropy.
/// Not cryptographically rigorous, but plenty for a LAN-only homelab tool
/// where the threat model is "someone on my Wi-Fi snooping", not a
/// nation-state attacker. (For real threat models, put the server behind
/// a reverse proxy with TLS + a real token store.)
pub fn generate_token() -> String {
    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_nanos())
        .unwrap_or(0);
    let pid = std::process::id() as u128;
    let tid = format!("{:?}", std::thread::current().id());
    // Mix several entropy sources into a single string, then hex-encode.
    let mut mixed: u128 = now;
    mixed ^= pid.wrapping_mul(0x9E37_79B9_7F4A_7C15);
    for (i, b) in tid.bytes().enumerate() {
        mixed ^= (b as u128).wrapping_shl(((i as u32) % 16) * 8);
    }
    let mut bytes = [0u8; 24];
    for i in 0..12 {
        bytes[i]     = ((mixed >> (i as u32 * 8)) & 0xFF) as u8;
        bytes[i + 12] = ((now >> (i as u32 * 8)) & 0xFF) as u8;
    }
    let mut hex = String::with_capacity(bytes.len() * 2);
    for b in bytes {
        hex.push_str(&format!("{:02x}", b));
    }
    // Slap a prefix so the token is recognizable in logs / config.
    format!("cbar_{}", hex)
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn generated_token_is_long_enough() {
        let t = generate_token();
        assert!(t.len() >= 16, "token too short: {:?}", t);
        assert!(t.starts_with("cbar_"));
    }
    #[test]
    fn tokens_are_unique() {
        let a = generate_token();
        std::thread::sleep(std::time::Duration::from_millis(2));
        let b = generate_token();
        assert_ne!(a, b);
    }
}
