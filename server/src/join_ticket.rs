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

const NONCE_CAP: usize = 4096;

/// Process-local v2 nonces. One server owns one cache. Tests do not share it.
#[derive(Debug, Default)]
pub struct NonceCache {
    live: std::collections::HashMap<String, u64>,
}

impl NonceCache {
    fn prune(&mut self, now: u64) {
        let floor = now.saturating_sub(15);
        self.live.retain(|_, exp| *exp > floor);
    }

    /// False when this nonce was already redeemed or the cache is full of live nonces.
    pub fn redeem(&mut self, nonce: &str, exp: u64, now: u64) -> bool {
        self.prune(now);
        if self.live.contains_key(nonce) {
            return false;
        }
        if self.live.len() >= NONCE_CAP {
            return false;
        }
        self.live.insert(nonce.to_string(), exp);
        true
    }
}

/// v1 stays the local tool ticket. v2 binds a nonce and an audience.
pub fn mint_v2(
    secret: &JoinSecret,
    role: Role,
    exp: u64,
    nonce: &str,
    audience: &str,
) -> Result<String, &'static str> {
    let role_name = ticket_role(role)?;
    if hex_decode(nonce).map(|bytes| bytes.len() == 16 && hex_encode(&bytes) == nonce) != Ok(true) {
        return Err("nonce");
    }
    if !audience_well_formed(audience) {
        return Err("audience");
    }
    let mac = hmac_sha256(
        secret.0.as_bytes(),
        payload_v2(exp, role_name, nonce, audience).as_bytes(),
    );
    Ok(format!(
        "v2.{exp}.{role_name}.{nonce}.{}.{}",
        b64url_encode(audience.as_bytes()),
        hex_encode(&mac)
    ))
}

fn payload_v2(exp: u64, role: &str, nonce: &str, audience: &str) -> String {
    format!("fragr-join-v2\n{exp}\n{role}\n{nonce}\n{audience}")
}

fn ticket_role(role: Role) -> Result<&'static str, &'static str> {
    match role {
        Role::Spectator => Ok("spectator"),
        other => role_name(other),
    }
}

/// `required_audience` set rejects v1 and requires that exact v2 audience.
/// Unset still admits replayable v1, and admits v2 once for any well-formed audience.
pub fn admit_presented(
    secret: Option<&JoinSecret>,
    role: Role,
    ticket: Option<&str>,
    now: u64,
    required_audience: Option<&str>,
    spectator_tickets: bool,
    nonces: &mut NonceCache,
) -> bool {
    let Some(secret) = secret else {
        return true;
    };
    if role == Role::Spectator && !spectator_tickets {
        return true;
    }
    let Some(ticket) = ticket else {
        return false;
    };
    if ticket.starts_with("v1.") {
        if required_audience.is_some() || role == Role::Spectator {
            return false;
        }
        return admit(Some(secret), role, Some(ticket), now);
    }
    let mut parts = ticket.split('.');
    let (
        Some(version),
        Some(exp_text),
        Some(role_text),
        Some(nonce),
        Some(audience_text),
        Some(mac_text),
        None,
    ) = (
        parts.next(),
        parts.next(),
        parts.next(),
        parts.next(),
        parts.next(),
        parts.next(),
        parts.next(),
    )
    else {
        return false;
    };
    if version != "v2" {
        return false;
    }
    let Ok(expected_role) = ticket_role(role) else {
        return false;
    };
    if role_text != expected_role || role == Role::Spectator && !spectator_tickets {
        return false;
    }
    let Ok(exp) = exp_text.parse::<u64>() else {
        return false;
    };
    if exp <= now.saturating_sub(15) || exp > now.saturating_add(75) {
        return false;
    }
    if hex_decode(nonce).map(|bytes| bytes.len() == 16 && hex_encode(&bytes) == nonce) != Ok(true) {
        return false;
    }
    let Ok(audience_bytes) = b64url_decode(audience_text) else {
        return false;
    };
    let Ok(audience) = String::from_utf8(audience_bytes) else {
        return false;
    };
    if let Some(required) = required_audience {
        if audience != required {
            return false;
        }
    } else if !audience_well_formed(&audience) {
        return false;
    }
    let Ok(mac) = hex_decode(mac_text) else {
        return false;
    };
    if mac.len() != 32 {
        return false;
    }
    let expect = hmac_sha256(
        secret.0.as_bytes(),
        payload_v2(exp, role_text, nonce, &audience).as_bytes(),
    );
    if !mac_equal(&mac, &expect) {
        return false;
    }
    nonces.redeem(nonce, exp, now)
}

fn audience_well_formed(audience: &str) -> bool {
    let Some(rest) = audience
        .strip_prefix("wss://")
        .or_else(|| audience.strip_prefix("ws://"))
    else {
        return false;
    };
    if rest
        .chars()
        .any(|ch| ch.is_ascii_uppercase() || ch.is_control())
    {
        return false;
    }
    let (host, port) = if let Some(host) = rest.strip_prefix('[') {
        let Some((host, port)) = host.split_once("]:") else {
            return false;
        };
        if !host.contains(':') {
            return false;
        }
        (host, port)
    } else {
        let Some((host, port)) = rest.split_once(':') else {
            return false;
        };
        if host.is_empty() || host.contains(':') {
            return false;
        }
        (host, port)
    };
    if host.is_empty()
        || port.is_empty()
        || port.len() > 5
        || !port.bytes().all(|byte| byte.is_ascii_digit())
    {
        return false;
    }
    let Ok(port) = port.parse::<u16>() else {
        return false;
    };
    port != 0
}

fn b64url_encode(bytes: &[u8]) -> String {
    const TABLE: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";
    let mut out = String::with_capacity(bytes.len().div_ceil(3) * 4);
    let mut index = 0;
    while index + 3 <= bytes.len() {
        let value = ((bytes[index] as u32) << 16)
            | ((bytes[index + 1] as u32) << 8)
            | bytes[index + 2] as u32;
        out.push(TABLE[((value >> 18) & 63) as usize] as char);
        out.push(TABLE[((value >> 12) & 63) as usize] as char);
        out.push(TABLE[((value >> 6) & 63) as usize] as char);
        out.push(TABLE[(value & 63) as usize] as char);
        index += 3;
    }
    match bytes.len() - index {
        1 => {
            let value = (bytes[index] as u32) << 16;
            out.push(TABLE[((value >> 18) & 63) as usize] as char);
            out.push(TABLE[((value >> 12) & 63) as usize] as char);
        }
        2 => {
            let value = ((bytes[index] as u32) << 16) | ((bytes[index + 1] as u32) << 8);
            out.push(TABLE[((value >> 18) & 63) as usize] as char);
            out.push(TABLE[((value >> 12) & 63) as usize] as char);
            out.push(TABLE[((value >> 6) & 63) as usize] as char);
        }
        _ => {}
    }
    out
}

fn b64url_decode(text: &str) -> Result<Vec<u8>, ()> {
    if text.is_empty()
        || text
            .bytes()
            .any(|byte| !matches!(byte, b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'_'))
    {
        return Err(());
    }
    fn value(byte: u8) -> u8 {
        match byte {
            b'A'..=b'Z' => byte - b'A',
            b'a'..=b'z' => byte - b'a' + 26,
            b'0'..=b'9' => byte - b'0' + 52,
            b'-' => 62,
            _ => 63,
        }
    }
    let bytes = text.as_bytes();
    let mut out = Vec::with_capacity(bytes.len() * 3 / 4);
    let mut index = 0;
    while index + 4 <= bytes.len() {
        let value = ((value(bytes[index]) as u32) << 18)
            | ((value(bytes[index + 1]) as u32) << 12)
            | ((value(bytes[index + 2]) as u32) << 6)
            | value(bytes[index + 3]) as u32;
        out.push((value >> 16) as u8);
        out.push((value >> 8) as u8);
        out.push(value as u8);
        index += 4;
    }
    match bytes.len() - index {
        0 => {}
        2 => {
            let value =
                ((value(bytes[index]) as u32) << 18) | ((value(bytes[index + 1]) as u32) << 12);
            out.push((value >> 16) as u8);
        }
        3 => {
            let value = ((value(bytes[index]) as u32) << 18)
                | ((value(bytes[index + 1]) as u32) << 12)
                | ((value(bytes[index + 2]) as u32) << 6);
            out.push((value >> 16) as u8);
            out.push((value >> 8) as u8);
        }
        _ => return Err(()),
    }
    Ok(out)
}

fn role_name(role: Role) -> Result<&'static str, &'static str> {
    match role {
        Role::Human => Ok("human"),
        Role::Agent => Ok("agent"),
        Role::Spectator => Err("spectators are not ticketed"),
    }
}

pub(crate) fn hmac_sha256(key: &[u8], data: &[u8]) -> [u8; 32] {
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

pub(crate) fn mac_equal(left: &[u8], right: &[u8]) -> bool {
    if left.len() != right.len() {
        return false;
    }
    let mut diff = 0u8;
    for (a, b) in left.iter().zip(right) {
        diff |= a ^ b;
    }
    diff == 0
}

pub(crate) fn hex_encode(bytes: &[u8]) -> String {
    const HEX: &[u8; 16] = b"0123456789abcdef";
    let mut out = String::with_capacity(bytes.len() * 2);
    for byte in bytes {
        out.push(HEX[(byte >> 4) as usize] as char);
        out.push(HEX[(byte & 0x0f) as usize] as char);
    }
    out
}

pub(crate) fn hex_decode(text: &str) -> Result<Vec<u8>, ()> {
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

    #[test]
    fn v2_golden_is_one_time_and_v1_stays_replayable_without_an_audience() {
        let secret = JoinSecret::from_env_value("0123456789abcdef")
            .unwrap()
            .unwrap();
        let audience = "wss://play.example:6767";
        let nonce = "00112233445566778899aabbccddeeff";
        let ticket = mint_v2(&secret, Role::Human, 1_700_000_060, nonce, audience).unwrap();
        assert_eq!(
            ticket,
            "v2.1700000060.human.00112233445566778899aabbccddeeff.d3NzOi8vcGxheS5leGFtcGxlOjY3Njc.0ec6964cd92cc8c6b91dea2c4491f9454ebc20e7aadce35b355e4d675df4b6d8"
        );
        let now = 1_700_000_000;
        let mut cache = NonceCache::default();
        assert!(admit_presented(
            Some(&secret),
            Role::Human,
            Some(&ticket),
            now,
            None,
            false,
            &mut cache
        ));
        assert!(!admit_presented(
            Some(&secret),
            Role::Human,
            Some(&ticket),
            now,
            None,
            false,
            &mut cache
        ));
        let v1 = mint(&secret, Role::Human, 1_700_000_060).unwrap();
        assert!(admit_presented(
            Some(&secret),
            Role::Human,
            Some(&v1),
            now,
            None,
            false,
            &mut cache
        ));
        assert!(admit_presented(
            Some(&secret),
            Role::Human,
            Some(&v1),
            now,
            None,
            false,
            &mut cache
        ));
        assert!(!admit_presented(
            Some(&secret),
            Role::Human,
            Some(&v1),
            now,
            Some(audience),
            false,
            &mut cache
        ));
        let mut bound = NonceCache::default();
        let bound_ticket = mint_v2(
            &secret,
            Role::Human,
            1_700_000_060,
            "ffeeddccbbaa99887766554433221100",
            audience,
        )
        .unwrap();
        assert!(admit_presented(
            Some(&secret),
            Role::Human,
            Some(&bound_ticket),
            now,
            Some(audience),
            false,
            &mut bound
        ));
        assert!(!admit_presented(
            Some(&secret),
            Role::Human,
            Some(&bound_ticket),
            now,
            Some("wss://other.example:6767"),
            false,
            &mut NonceCache::default()
        ));
        assert!(admit(Some(&secret), Role::Human, Some(&v1), now));
        assert!(admit(Some(&secret), Role::Human, Some(&v1), now));
    }
}
