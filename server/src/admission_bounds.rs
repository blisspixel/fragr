//! Connection admission that runs before a socket can wait or take a game slot.
//! Loopback keeps room for the desktop client, playtests, and soak.

use std::collections::{HashMap, VecDeque};
use std::net::IpAddr;
use std::sync::{Arc, Mutex};
use std::time::Instant;

use uuid::Uuid;

const PRECLASS_NORMAL: usize = 4;
const PRECLASS_LOOPBACK: usize = 32;
const ACCEPTS_PER_SEC_NORMAL: f32 = 8.0;
const ACCEPT_BURST_NORMAL: f32 = 16.0;
const ACCEPTS_PER_SEC_LOOPBACK: f32 = 64.0;
const ACCEPT_BURST_LOOPBACK: f32 = 64.0;
const STATUS_NORMAL: usize = 2;
const STATUS_LOOPBACK: usize = 8;
const SPECTATOR_GLOBAL: usize = 16;
const SPECTATOR_NORMAL: usize = 4;
const SPECTATOR_LOOPBACK: usize = 8;
const PAWN_GLOBAL: usize = 96;
const PAWN_NORMAL: usize = 40;
const PAWN_LOOPBACK: usize = 64;
const JOINS_PER_WINDOW_NORMAL: usize = 4;
const JOINS_PER_WINDOW_LOOPBACK: usize = 30;
const JOIN_WINDOW: std::time::Duration = std::time::Duration::from_secs(10);
const BOARD_SESSION_PER_SEC: usize = 8 * 1024;
const BOARD_ADDRESS_PER_SEC: usize = 16 * 1024;

pub fn is_loopback(ip: IpAddr) -> bool {
    match ip {
        IpAddr::V4(address) => address.is_loopback(),
        IpAddr::V6(address) => address.is_loopback(),
    }
}

#[derive(Debug)]
struct Bucket {
    level: f32,
    updated: Instant,
}

impl Bucket {
    fn allow(&mut self, now: Instant, per_sec: f32, burst: f32) -> bool {
        let elapsed = now.saturating_duration_since(self.updated).as_secs_f32();
        self.level = (self.level + elapsed * per_sec).min(burst);
        self.updated = now;
        if self.level >= 1.0 {
            self.level -= 1.0;
            true
        } else {
            false
        }
    }
}

#[derive(Debug)]
struct PreclassInner {
    held: HashMap<IpAddr, usize>,
    status: HashMap<IpAddr, usize>,
    accepts: HashMap<IpAddr, Bucket>,
}

#[derive(Clone)]
pub struct PreclassGate {
    inner: Arc<Mutex<PreclassInner>>,
}

pub struct PreclassPermit {
    ip: IpAddr,
    gate: PreclassGate,
}

impl Drop for PreclassPermit {
    fn drop(&mut self) {
        let mut inner = self.gate.lock();
        if let Some(count) = inner.held.get_mut(&self.ip) {
            *count = count.saturating_sub(1);
            if *count == 0 {
                inner.held.remove(&self.ip);
            }
        }
    }
}

pub struct StatusPermit {
    ip: IpAddr,
    gate: PreclassGate,
}

impl Drop for StatusPermit {
    fn drop(&mut self) {
        let mut inner = self.gate.lock();
        if let Some(count) = inner.status.get_mut(&self.ip) {
            *count = count.saturating_sub(1);
            if *count == 0 {
                inner.status.remove(&self.ip);
            }
        }
    }
}

impl PreclassGate {
    pub fn new() -> Self {
        Self {
            inner: Arc::new(Mutex::new(PreclassInner {
                held: HashMap::new(),
                status: HashMap::new(),
                accepts: HashMap::new(),
            })),
        }
    }

    fn lock(&self) -> std::sync::MutexGuard<'_, PreclassInner> {
        self.inner.lock().unwrap_or_else(|error| error.into_inner())
    }

    /// Fail immediately. This does not wait for the status classification budget.
    pub fn try_acquire(&self, ip: IpAddr, now: Instant) -> Result<PreclassPermit, &'static str> {
        let mut inner = self.lock();
        let (per_sec, burst) = if is_loopback(ip) {
            (ACCEPTS_PER_SEC_LOOPBACK, ACCEPT_BURST_LOOPBACK)
        } else {
            (ACCEPTS_PER_SEC_NORMAL, ACCEPT_BURST_NORMAL)
        };
        let bucket = inner.accepts.entry(ip).or_insert(Bucket {
            level: burst,
            updated: now,
        });
        if !bucket.allow(now, per_sec, burst) {
            return Err("accept_rate");
        }
        let cap = if is_loopback(ip) {
            PRECLASS_LOOPBACK
        } else {
            PRECLASS_NORMAL
        };
        let held = inner.held.entry(ip).or_insert(0);
        if *held >= cap {
            return Err("preclass_limit");
        }
        *held += 1;
        drop(inner);
        Ok(PreclassPermit {
            ip,
            gate: self.clone(),
        })
    }

    pub fn try_status(&self, ip: IpAddr) -> Result<StatusPermit, &'static str> {
        let mut inner = self.lock();
        let cap = if is_loopback(ip) {
            STATUS_LOOPBACK
        } else {
            STATUS_NORMAL
        };
        let held = inner.status.entry(ip).or_insert(0);
        if *held >= cap {
            return Err("status_limit");
        }
        *held += 1;
        drop(inner);
        Ok(StatusPermit {
            ip,
            gate: self.clone(),
        })
    }
}

impl Default for PreclassGate {
    fn default() -> Self {
        Self::new()
    }
}

#[derive(Debug)]
struct Seat {
    ip: IpAddr,
}

#[derive(Debug, Default)]
struct PopulationInner {
    pawns: HashMap<Uuid, Seat>,
    spectators: HashMap<Uuid, Seat>,
    joins: HashMap<IpAddr, VecDeque<Instant>>,
}

#[derive(Clone, Default)]
pub struct Population {
    inner: Arc<Mutex<PopulationInner>>,
}

impl Population {
    fn lock(&self) -> std::sync::MutexGuard<'_, PopulationInner> {
        self.inner.lock().unwrap_or_else(|error| error.into_inner())
    }

    pub fn reserve_pawn(&self, player: Uuid, ip: IpAddr, now: Instant) -> Result<(), &'static str> {
        let mut inner = self.lock();
        if inner.pawns.contains_key(&player) {
            return Ok(());
        }
        if inner.pawns.len() >= PAWN_GLOBAL {
            return Err("pawn_limit");
        }
        let cap = if is_loopback(ip) {
            PAWN_LOOPBACK
        } else {
            PAWN_NORMAL
        };
        let mine = inner.pawns.values().filter(|seat| seat.ip == ip).count();
        if mine >= cap {
            return Err("pawn_address_limit");
        }
        let window = if is_loopback(ip) {
            JOINS_PER_WINDOW_LOOPBACK
        } else {
            JOINS_PER_WINDOW_NORMAL
        };
        let recent = inner.joins.entry(ip).or_default();
        while recent
            .front()
            .is_some_and(|at| now.saturating_duration_since(*at) > JOIN_WINDOW)
        {
            recent.pop_front();
        }
        if recent.len() >= window {
            return Err("join_rate");
        }
        recent.push_back(now);
        inner.pawns.insert(player, Seat { ip });
        Ok(())
    }

    pub fn reserve_spectator(&self, client: Uuid, ip: IpAddr) -> Result<(), &'static str> {
        let mut inner = self.lock();
        if inner.spectators.contains_key(&client) {
            return Ok(());
        }
        if inner.spectators.len() >= SPECTATOR_GLOBAL {
            return Err("spectator_limit");
        }
        let cap = if is_loopback(ip) {
            SPECTATOR_LOOPBACK
        } else {
            SPECTATOR_NORMAL
        };
        let mine = inner
            .spectators
            .values()
            .filter(|seat| seat.ip == ip)
            .count();
        if mine >= cap {
            return Err("spectator_address_limit");
        }
        inner.spectators.insert(client, Seat { ip });
        Ok(())
    }

    pub fn release_pawn(&self, player: Uuid) {
        self.lock().pawns.remove(&player);
    }

    pub fn release_spectator(&self, client: Uuid) {
        self.lock().spectators.remove(&client);
    }

    pub fn contains_pawn(&self, player: Uuid) -> bool {
        self.lock().pawns.contains_key(&player)
    }

    pub fn contains_spectator(&self, client: Uuid) -> bool {
        self.lock().spectators.contains_key(&client)
    }

    pub fn pawn_count(&self) -> usize {
        self.lock().pawns.len()
    }

    pub fn spectator_count(&self) -> usize {
        self.lock().spectators.len()
    }
}

/// Audience, browser origins, and the spectator-ticket switch.
/// The dedicated and local processes read this. The match loop does not.
pub struct ProcessPolicy {
    pub audience: Option<String>,
    pub origins: Vec<String>,
    pub spectator_tickets: bool,
}

pub fn process_policy(join_secret_set: bool) -> ProcessPolicy {
    let audience = std::env::var("FRAGR_JOIN_AUDIENCE")
        .ok()
        .map(|value| value.trim().to_string())
        .filter(|value| !value.is_empty());
    let origins = std::env::var("FRAGR_ORIGIN_ALLOW")
        .ok()
        .map(|value| origin_allow_list(&value))
        .unwrap_or_default();
    let spectator_tickets = join_secret_set
        && matches!(
            std::env::var("FRAGR_SPECTATOR_TICKET").ok().as_deref(),
            Some("1")
        );
    ProcessPolicy {
        audience,
        origins,
        spectator_tickets,
    }
}

#[derive(Debug)]
pub struct ByteWindow {
    stamp: Instant,
    used: usize,
}

impl ByteWindow {
    fn take(&mut self, now: Instant, bytes: usize, cap: usize) -> bool {
        if now.saturating_duration_since(self.stamp) >= std::time::Duration::from_secs(1) {
            self.stamp = now;
            self.used = 0;
        }
        if self.used.saturating_add(bytes) > cap {
            return false;
        }
        self.used += bytes;
        true
    }
}

#[derive(Clone, Default)]
pub struct BoardBudget {
    addresses: Arc<Mutex<HashMap<IpAddr, ByteWindow>>>,
}

impl BoardBudget {
    pub fn allow(&self, ip: IpAddr, session: &mut ByteWindow, now: Instant, bytes: usize) -> bool {
        if bytes == 0 || bytes > BOARD_SESSION_PER_SEC {
            return false;
        }
        if !session.take(now, bytes, BOARD_SESSION_PER_SEC) {
            return false;
        }
        let mut addresses = self
            .addresses
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        let window = addresses.entry(ip).or_insert(ByteWindow {
            stamp: now,
            used: 0,
        });
        if window.take(now, bytes, BOARD_ADDRESS_PER_SEC) {
            true
        } else {
            session.used = session.used.saturating_sub(bytes);
            false
        }
    }
}

pub fn fresh_board_window(now: Instant) -> ByteWindow {
    ByteWindow {
        stamp: now,
        used: 0,
    }
}

/// Exact entries from `FRAGR_ORIGIN_ALLOW`. Empty rejects every present Origin.
pub fn origin_allow_list(raw: &str) -> Vec<String> {
    raw.split(',')
        .map(str::trim)
        .filter(|entry| !entry.is_empty())
        .map(str::to_string)
        .collect()
}

pub fn origin_allowed(allow: &[String], origin: Option<&str>) -> bool {
    match origin {
        None => true,
        Some(origin) => allow.iter().any(|entry| entry == origin),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_partial_address_does_not_consume_another_address() {
        let gate = PreclassGate::new();
        let now = Instant::now();
        let held: Vec<_> = (0..PRECLASS_NORMAL)
            .map(|_| {
                gate.try_acquire("203.0.113.5".parse().unwrap(), now)
                    .unwrap()
            })
            .collect();
        assert!(gate
            .try_acquire("203.0.113.5".parse().unwrap(), now)
            .is_err());
        assert!(gate
            .try_acquire("203.0.113.9".parse().unwrap(), now)
            .is_ok());
        drop(held);
        assert!(gate
            .try_acquire("203.0.113.5".parse().unwrap(), now)
            .is_ok());
    }

    #[test]
    fn loopback_preclass_keeps_playtest_headroom() {
        let gate = PreclassGate::new();
        let now = Instant::now();
        let held: Vec<_> = (0..PRECLASS_LOOPBACK)
            .map(|_| gate.try_acquire(IpAddr::from([127, 0, 0, 1]), now).unwrap())
            .collect();
        assert_eq!(held.len(), 32);
        assert!(gate
            .try_acquire(IpAddr::from([127, 0, 0, 1]), Instant::now())
            .is_err());
    }

    #[test]
    fn spectator_cap_still_leaves_a_participant_slot() {
        let population = Population::default();
        let ip: IpAddr = "198.51.100.4".parse().unwrap();
        for index in 0..SPECTATOR_NORMAL {
            population
                .reserve_spectator(Uuid::from_u128(index as u128 + 1), ip)
                .unwrap();
        }
        assert!(population
            .reserve_spectator(Uuid::from_u128(99), ip)
            .is_err());
        assert!(population
            .reserve_pawn(Uuid::from_u128(100), ip, Instant::now())
            .is_ok());
    }

    #[test]
    fn missing_origin_is_allowed_and_an_unknown_origin_is_not() {
        let allow = origin_allow_list("https://play.example");
        assert!(origin_allowed(&allow, None));
        assert!(origin_allowed(&allow, Some("https://play.example")));
        assert!(!origin_allowed(&allow, Some("https://other.example")));
        assert!(!origin_allowed(&[], Some("https://play.example")));
    }
}
