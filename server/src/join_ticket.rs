//! Optional HMAC join tickets. No secret means hello stays open.
//! A present secret must be 16 to 256 bytes or the process refuses to bind.

use crate::protocol::Role;
use sha2::{Digest, Sha256};

#[derive(Clone)]
pub struct JoinSecret(String);

impl std::fmt::Debug for JoinSecret {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter.write_str("JoinSecret([redacted])")
    }
}

impl JoinSecret {
    pub fn from_process_env() -> Result<Option<Self>, &'static str> {
        match std::env::var("FRAGR_JOIN_SECRET") {
            Err(_) => Ok(None),
            Ok(raw) => Self::from_env_value(&raw),
        }
    }

    /// Empty input is not a secret. A set secret that is the wrong length fails closed.
    pub fn from_env_value(raw: &str) -> Result<Option<Self>, &'static str> {
        let trimmed = raw.trim();
        if trimmed.is_empty() {
            return Ok(None);
        }
        if !(16..=256).contains(&trimmed.len()) {
            return Err("FRAGR_JOIN_SECRET must be 16 to 256 bytes");
        }
        Ok(Some(Self(trimmed.to_string())))
    }
}

pub fn unix_now() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|elapsed| elapsed.as_secs())
        .unwrap_or(0)
}

/// Ticket for a tool that shares the server process environment. None when no secret is set.
pub fn ticket_for(role: Role) -> Option<String> {
    let Ok(Some(secret)) = JoinSecret::from_process_env() else {
        return None;
    };
    mint(&secret, role, unix_now().saturating_add(60)).ok()
}

pub fn mint(secret: &JoinSecret, role: Role, exp: u64) -> Result<String, &'static str> {
    let role_name = role_name(role)?;
    let mac = hmac_sha256(secret.0.as_bytes(), payload(exp, role_name).as_bytes());
    Ok(format!("v1.{exp}.{role_name}.{}", hex_encode(&mac)))
}

/// `Ok` when this hello may take a seat. Spectators never need a ticket.
/// No secret ignores any ticket. A secret rejects a bad one.
pub fn admit(secret: Option<&JoinSecret>, role: Role, ticket: Option<&str>, now: u64) -> bool {
    let Some(secret) = secret else {
        return true;
    };
    if role == Role::Spectator {
        return true;
    }
    let Some(ticket) = ticket else {
        return false;
    };
    let mut parts = ticket.split('.');
    let (Some(version), Some(exp_text), Some(role_text), Some(mac_text), None) = (
        parts.next(),
        parts.next(),
        parts.next(),
        parts.next(),
        parts.next(),
    ) else {
        return false;
    };
    if version != "v1" {
        return false;
    }
    let Ok(expected_role) = role_name(role) else {
        return false;
    };
    if role_text != expected_role {
        return false;
    }
    let Ok(exp) = exp_text.parse::<u64>() else {
        return false;
    };
    if exp <= now.saturating_sub(15) || exp > now.saturating_add(75) {
        return false;
    }
    let Ok(mac) = hex_decode(mac_text) else {
        return false;
    };
    if mac.len() != 32 {
        return false;
    }
    let expect = hmac_sha256(secret.0.as_bytes(), payload(exp, role_text).as_bytes());
    mac_equal(&mac, &expect)
}

fn payload(exp: u64, role: &str) -> String {
    format!("fragr-join-v1\n{exp}\n{role}")
}

fn role_name(role: Role) -> Result<&'static str, &'static str> {
    match role {
        Role::Human => Ok("human"),
        Role::Agent => Ok("agent"),
        Role::Spectator => Err("spectators are not ticketed"),
    }
}

fn hmac_sha256(key: &[u8], data: &[u8]) -> [u8; 32] {
    const BLOCK: usize = 64;
    let mut key_block = [0u8; BLOCK];
    if key.len() > BLOCK {
        let digest = Sha256::digest(key);
        key_block[..digest.len()].copy_from_slice(&digest);
    } else {
        key_block[..key.len()].copy_from_slice(key);
    }
    let mut inner_key = [0x36u8; BLOCK];
    let mut outer_key = [0x5cu8; BLOCK];
    for i in 0..BLOCK {
        inner_key[i] ^= key_block[i];
        outer_key[i] ^= key_block[i];
    }
    let mut inner = Sha256::new();
    inner.update(inner_key);
    inner.update(data);
    let inner = inner.finalize();
    let mut outer = Sha256::new();
    outer.update(outer_key);
    outer.update(inner);
    outer.finalize().into()
}

fn mac_equal(left: &[u8], right: &[u8]) -> bool {
    if left.len() != right.len() {
        return false;
    }
    let mut diff = 0u8;
    for (a, b) in left.iter().zip(right) {
        diff |= a ^ b;
    }
    diff == 0
}

fn hex_encode(bytes: &[u8]) -> String {
    const HEX: &[u8; 16] = b"0123456789abcdef";
    let mut out = String::with_capacity(bytes.len() * 2);
    for byte in bytes {
        out.push(HEX[(byte >> 4) as usize] as char);
        out.push(HEX[(byte & 0x0f) as usize] as char);
    }
    out
}

fn hex_decode(text: &str) -> Result<Vec<u8>, ()> {
    if !text.len().is_multiple_of(2) {
        return Err(());
    }
    let mut out = Vec::with_capacity(text.len() / 2);
    let bytes = text.as_bytes();
    let mut i = 0;
    while i < bytes.len() {
        let hi = hex_nibble(bytes[i])?;
        let lo = hex_nibble(bytes[i + 1])?;
        out.push((hi << 4) | lo);
        i += 2;
    }
    Ok(out)
}

fn hex_nibble(byte: u8) -> Result<u8, ()> {
    match byte {
        b'0'..=b'9' => Ok(byte - b'0'),
        b'a'..=b'f' => Ok(byte - b'a' + 10),
        _ => Err(()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn hmac_matches_rfc_2104_sha256_case_1() {
        let key = [0x0bu8; 20];
        let mac = hmac_sha256(&key, b"Hi There");
        assert_eq!(
            hex_encode(&mac),
            "b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7"
        );
    }

    #[test]
    fn minted_ticket_admits_inside_the_window_only() {
        let secret = JoinSecret::from_env_value("0123456789abcdef")
            .unwrap()
            .unwrap();
        let now = 1_700_000_000;
        let ticket = mint(&secret, Role::Human, now + 60).unwrap();
        assert_eq!(
            mint(&secret, Role::Human, 1_700_000_060).unwrap(),
            "v1.1700000060.human.5b6e18c7aef8a218ef64786317c23e472eb2b432bfa681e1c76e340b48d232ba"
        );
        assert!(admit(Some(&secret), Role::Human, Some(&ticket), now));
        assert!(admit(Some(&secret), Role::Human, Some(&ticket), now));
        assert!(!admit(Some(&secret), Role::Agent, Some(&ticket), now));
        assert!(admit(
            Some(&secret),
            Role::Human,
            Some(&mint(&secret, Role::Human, now - 14).unwrap()),
            now
        ));
        assert!(!admit(
            Some(&secret),
            Role::Human,
            Some(&mint(&secret, Role::Human, now - 15).unwrap()),
            now
        ));
        assert!(admit(
            Some(&secret),
            Role::Human,
            Some(&mint(&secret, Role::Human, now + 75).unwrap()),
            now
        ));
        assert!(!admit(
            Some(&secret),
            Role::Human,
            Some(&mint(&secret, Role::Human, now + 76).unwrap()),
            now
        ));
        assert!(admit(None, Role::Human, None, now));
        assert!(admit(Some(&secret), Role::Spectator, None, now));
        assert!(admit(Some(&secret), Role::Spectator, Some("garbage"), now));
        assert!(!admit(Some(&secret), Role::Human, None, now));
        assert!(!admit(
            Some(&secret),
            Role::Human,
            Some("v1.1.human.aa"),
            now
        ));
        let mut upper = ticket.clone();
        upper.replace_range(upper.len() - 1.., "A");
        assert!(!admit(Some(&secret), Role::Human, Some(&upper), now));
        let mut flipped = ticket.clone().into_bytes();
        let last = flipped.len() - 1;
        flipped[last] = if flipped[last] == b'0' { b'1' } else { b'0' };
        let flipped = String::from_utf8(flipped).unwrap();
        assert!(!admit(Some(&secret), Role::Human, Some(&flipped), now));
        assert!(!format!("{secret:?}").contains("0123456789abcdef"));
        assert!(format!("{secret:?}").contains("redacted"));
        assert!(JoinSecret::from_env_value("   ").unwrap().is_none());
        assert!(JoinSecret::from_env_value("short").is_err());
        assert!(JoinSecret::from_env_value(&"a".repeat(16))
            .unwrap()
            .is_some());
        assert!(JoinSecret::from_env_value(&"a".repeat(256))
            .unwrap()
            .is_some());
        assert!(JoinSecret::from_env_value(&"a".repeat(257)).is_err());
        let wide = JoinSecret::from_env_value(&"0123456789abcdef".repeat(5))
            .unwrap()
            .unwrap();
        let wide_ticket = mint(&wide, Role::Agent, now + 30).unwrap();
        assert!(admit(Some(&wide), Role::Agent, Some(&wide_ticket), now));
        assert!(!admit(Some(&wide), Role::Human, Some(&wide_ticket), now));
    }
}
