//! The operator view behind `GET /status`: process clock, build identity,
//! tick timing over a sixty second window and the process lifetime, traffic
//! per session and in total, and the health verdict. Recording is a few
//! integer operations per tick or frame; the view is rebuilt once a second.
//!
//! Nothing here holds an address, a callsign, a ticket or a token.

use crate::bench::Histogram;
use crate::protocol::{
    BuildInfo, ClientRate, Health, HealthReason, HealthState, LiveStatus, OpsStatus, ProcessInfo,
    Role, RoleCounts, TickSummary, TickTiming, TrafficTotals, OPS_VERSION,
};
use std::collections::{HashMap, VecDeque};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, OnceLock};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};
use uuid::Uuid;

/// One window slot. Six of them make the window.
pub const SLOT: Duration = Duration::from_secs(10);
const SLOTS: usize = 6;
/// The span health and rates describe: the last 50 to 60 seconds.
pub const WINDOW: Duration = Duration::from_secs(60);
/// Fewer window ticks than this never trip the p99 rule (a cold start).
pub const MIN_WINDOW_TICKS: u64 = 100;
/// A served snapshot older than this is `stale`.
pub const STALE_AFTER: Duration = Duration::from_secs(2);
/// How often the tick loop rebuilds the operator block.
pub const REFRESH_EVERY: Duration = Duration::from_secs(1);
/// What a tick sample covers. See `TickTiming::scope`.
pub const TICK_SCOPE: &str = "tick_handler";

struct ProcessClock {
    started: Instant,
    started_unix_s: u64,
}

fn process_clock() -> &'static ProcessClock {
    static CLOCK: OnceLock<ProcessClock> = OnceLock::new();
    CLOCK.get_or_init(|| ProcessClock {
        started: Instant::now(),
        started_unix_s: SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|since| since.as_secs())
            .unwrap_or(0),
    })
}

/// Fix the process start. The binary calls this first; later calls are no-ops.
pub fn mark_process_start() {
    let _ = process_clock();
}

pub fn process_uptime() -> Duration {
    process_clock().started.elapsed()
}

fn process_info(now: Instant) -> ProcessInfo {
    let clock = process_clock();
    ProcessInfo {
        started_unix_s: clock.started_unix_s,
        uptime_s: now.saturating_duration_since(clock.started).as_secs_f64(),
    }
}

/// Build identity. `FRAGR_BUILD_COMMIT` and `FRAGR_BUILD_VERSION` are read at
/// compile time; a local build without them reports `unknown` and no release.
pub fn build_info() -> BuildInfo {
    build_info_from(
        option_env!("FRAGR_BUILD_COMMIT"),
        option_env!("FRAGR_BUILD_VERSION"),
    )
}

fn build_info_from(commit: Option<&str>, release: Option<&str>) -> BuildInfo {
    let commit = commit
        .map(str::trim)
        .filter(|value| (7..=40).contains(&value.len()))
        .filter(|value| value.chars().all(|c| c.is_ascii_hexdigit()))
        .map(str::to_ascii_lowercase)
        .unwrap_or_else(|| "unknown".to_string());
    let release = release
        .map(str::trim)
        .filter(|value| (1..=64).contains(&value.len()))
        .filter(|value| {
            value
                .chars()
                .all(|c| c.is_ascii_alphanumeric() || matches!(c, '.' | '-' | '_' | '+'))
        })
        .map(str::to_string);
    BuildInfo {
        crate_version: env!("CARGO_PKG_VERSION").to_string(),
        release,
        commit,
    }
}

/// Payload counts at one instant.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct Counters {
    pub out_bytes: u64,
    pub out_msgs: u64,
    pub in_bytes: u64,
    pub in_msgs: u64,
}

#[derive(Debug, Clone, Copy, Default, PartialEq)]
struct Rates {
    out_bytes: f64,
    out_msgs: f64,
    in_bytes: f64,
    in_msgs: f64,
}

impl Counters {
    fn per_second_since(&self, earlier: &Counters, seconds: f64) -> Rates {
        if seconds <= 0.0 {
            return Rates::default();
        }
        let rate = |now: u64, then: u64| now.saturating_sub(then) as f64 / seconds;
        Rates {
            out_bytes: rate(self.out_bytes, earlier.out_bytes),
            out_msgs: rate(self.out_msgs, earlier.out_msgs),
            in_bytes: rate(self.in_bytes, earlier.in_bytes),
            in_msgs: rate(self.in_msgs, earlier.in_msgs),
        }
    }
}

/// Process totals for one listener. Closed sessions stay counted.
#[derive(Debug, Default)]
pub struct TrafficCounters {
    out_bytes: AtomicU64,
    out_msgs: AtomicU64,
    in_bytes: AtomicU64,
    in_msgs: AtomicU64,
}

impl TrafficCounters {
    pub fn snapshot(&self) -> Counters {
        Counters {
            out_bytes: self.out_bytes.load(Ordering::Relaxed),
            out_msgs: self.out_msgs.load(Ordering::Relaxed),
            in_bytes: self.in_bytes.load(Ordering::Relaxed),
            in_msgs: self.in_msgs.load(Ordering::Relaxed),
        }
    }
}

/// One session's counters, updated by its reader and writer tasks.
#[derive(Debug)]
pub struct ClientTraffic {
    role: Role,
    connected: Instant,
    own: TrafficCounters,
    totals: Arc<TrafficCounters>,
}

impl ClientTraffic {
    pub fn new(role: Role, totals: Arc<TrafficCounters>) -> Arc<Self> {
        Arc::new(Self {
            role,
            connected: Instant::now(),
            own: TrafficCounters::default(),
            totals,
        })
    }

    /// A text frame the session writer delivered.
    pub fn sent(&self, bytes: usize) {
        for counters in [&self.own, &*self.totals] {
            counters
                .out_bytes
                .fetch_add(bytes as u64, Ordering::Relaxed);
            counters.out_msgs.fetch_add(1, Ordering::Relaxed);
        }
    }

    /// A data frame (text or binary) the reader took off the socket.
    pub fn received(&self, bytes: usize) {
        for counters in [&self.own, &*self.totals] {
            counters.in_bytes.fetch_add(bytes as u64, Ordering::Relaxed);
            counters.in_msgs.fetch_add(1, Ordering::Relaxed);
        }
    }

    pub fn role(&self) -> Role {
        self.role
    }

    pub fn snapshot(&self) -> Counters {
        self.own.snapshot()
    }
}

/// What the refresh reads from one live session.
pub struct ClientSample<'a> {
    pub id: Uuid,
    pub traffic: &'a ClientTraffic,
    pub queue_depth: usize,
}

/// Six ten second histograms plus the lifetime. Memory is fixed.
#[derive(Debug)]
struct TickWindow {
    slots: Vec<Histogram>,
    over: [u64; SLOTS],
    overflows: [u64; SLOTS],
    current: usize,
    slot_started: Instant,
    lifetime: Histogram,
    lifetime_over: u64,
    overflows_total: u64,
}

impl TickWindow {
    fn new(now: Instant) -> Self {
        Self {
            slots: (0..SLOTS).map(|_| Histogram::new()).collect(),
            over: [0; SLOTS],
            overflows: [0; SLOTS],
            current: 0,
            slot_started: now,
            lifetime: Histogram::new(),
            lifetime_over: 0,
            overflows_total: 0,
        }
    }

    fn advance(&mut self, now: Instant) {
        let behind = now.saturating_duration_since(self.slot_started);
        if behind >= WINDOW {
            for slot in &mut self.slots {
                slot.clear();
            }
            self.over = [0; SLOTS];
            self.overflows = [0; SLOTS];
            self.slot_started = now;
            return;
        }
        while now.saturating_duration_since(self.slot_started) >= SLOT {
            self.current = (self.current + 1) % SLOTS;
            self.slots[self.current].clear();
            self.over[self.current] = 0;
            self.overflows[self.current] = 0;
            self.slot_started += SLOT;
        }
    }

    fn record_tick(&mut self, now: Instant, elapsed: Duration, budget: Duration) {
        self.advance(now);
        let ns = elapsed.as_nanos().min(u64::MAX as u128) as u64;
        let over = u64::from(elapsed >= budget);
        self.slots[self.current].record(ns);
        self.over[self.current] += over;
        self.lifetime.record(ns);
        self.lifetime_over += over;
    }

    fn record_overflows(&mut self, now: Instant, count: u64) {
        if count == 0 {
            return;
        }
        self.advance(now);
        self.overflows[self.current] += count;
        self.overflows_total += count;
    }

    fn window(&mut self, now: Instant) -> (Histogram, u64, u64) {
        self.advance(now);
        let mut merged = Histogram::new();
        for slot in &self.slots {
            merged.merge(slot);
        }
        (merged, self.over.iter().sum(), self.overflows.iter().sum())
    }
}

fn summarize(histogram: &Histogram, over_budget: u64) -> TickSummary {
    let ms = |ns: u64| ns as f64 * 1e-6;
    TickSummary {
        count: histogram.count(),
        p50_ms: ms(histogram.quantile(0.50)),
        p95_ms: ms(histogram.quantile(0.95)),
        p99_ms: ms(histogram.quantile(0.99)),
        max_ms: ms(histogram.max()),
        over_budget,
    }
}

/// The documented thresholds. `stale` is applied when a snapshot is served.
pub fn evaluate(window: &TickSummary, budget_ms: f64, overflows_window: u64) -> Vec<HealthReason> {
    let mut reasons = Vec::new();
    if window.count >= MIN_WINDOW_TICKS && window.p99_ms >= budget_ms {
        reasons.push(HealthReason::TickP99OverBudget);
    }
    if overflows_window > 0 {
        reasons.push(HealthReason::OutboundDrops);
    }
    reasons
}

/// Rolling per-session and total rates, sampled on each refresh.
#[derive(Debug)]
struct TrafficRates {
    clients: HashMap<Uuid, VecDeque<(Instant, Counters)>>,
    totals: VecDeque<(Instant, Counters)>,
}

fn push_sample(history: &mut VecDeque<(Instant, Counters)>, now: Instant, counters: Counters) {
    history.push_back((now, counters));
    // Keep the newest sample that is at least a window old as the baseline.
    while history.len() > 2 && now.saturating_duration_since(history[1].0) >= WINDOW {
        history.pop_front();
    }
}

fn history_rate(history: &VecDeque<(Instant, Counters)>) -> Rates {
    match (history.front(), history.back()) {
        (Some((then, earlier)), Some((now, latest))) => {
            latest.per_second_since(earlier, now.saturating_duration_since(*then).as_secs_f64())
        }
        _ => Rates::default(),
    }
}

impl TrafficRates {
    fn new(started: Instant) -> Self {
        Self {
            clients: HashMap::new(),
            totals: VecDeque::from([(started, Counters::default())]),
        }
    }

    fn sample(
        &mut self,
        now: Instant,
        totals: Counters,
        clients: &[ClientSample<'_>],
    ) -> (Rates, Vec<ClientRate>) {
        push_sample(&mut self.totals, now, totals);
        self.clients
            .retain(|id, _| clients.iter().any(|client| client.id == *id));
        let mut rates = Vec::with_capacity(clients.len());
        for client in clients {
            let history = self.clients.entry(client.id).or_insert_with(|| {
                VecDeque::from([(client.traffic.connected, Counters::default())])
            });
            let counters = client.traffic.snapshot();
            push_sample(history, now, counters);
            let rate = history_rate(history);
            rates.push(ClientRate {
                role: client.traffic.role(),
                connected_s: now
                    .saturating_duration_since(client.traffic.connected)
                    .as_secs_f64(),
                out_bytes_per_s: rate.out_bytes,
                in_bytes_per_s: rate.in_bytes,
                out_msgs_per_s: rate.out_msgs,
                in_msgs_per_s: rate.in_msgs,
                out_bytes: counters.out_bytes,
                in_bytes: counters.in_bytes,
                queue_depth: client.queue_depth,
            });
        }
        // A stable, anonymous order: role, then the longest connected first.
        rates.sort_by(|a, b| {
            role_rank(a.role)
                .cmp(&role_rank(b.role))
                .then(b.connected_s.total_cmp(&a.connected_s))
        });
        (history_rate(&self.totals), rates)
    }
}

fn role_rank(role: Role) -> u8 {
    match role {
        Role::Human => 0,
        Role::Agent => 1,
        Role::Spectator => 2,
    }
}

/// Owned by the tick loop. Records every tick and rebuilds the operator
/// block on `REFRESH_EVERY`.
#[derive(Debug)]
pub struct StatusTracker {
    budget: Duration,
    ticks: TickWindow,
    rates: TrafficRates,
    totals: Arc<TrafficCounters>,
    build: BuildInfo,
    last_refresh: Option<Instant>,
    health: Option<Health>,
    ops: Option<OpsStatus>,
}

impl StatusTracker {
    pub fn new(totals: Arc<TrafficCounters>, budget: Duration) -> Self {
        let now = Instant::now();
        Self {
            budget,
            ticks: TickWindow::new(now),
            rates: TrafficRates::new(now),
            totals,
            build: build_info(),
            last_refresh: None,
            health: None,
            ops: None,
        }
    }

    pub fn record_tick(&mut self, now: Instant, elapsed: Duration) {
        self.ticks.record_tick(now, elapsed, self.budget);
    }

    pub fn record_overflows(&mut self, now: Instant, count: u64) {
        self.ticks.record_overflows(now, count);
    }

    pub fn due(&self, now: Instant) -> bool {
        self.last_refresh
            .is_none_or(|last| now.saturating_duration_since(last) >= REFRESH_EVERY)
    }

    /// Rebuild the operator block from the live sessions.
    pub fn refresh(&mut self, now: Instant, clients: &[ClientSample<'_>]) {
        self.last_refresh = Some(now);
        let budget_ms = self.budget.as_secs_f64() * 1000.0;
        let (window, window_over, overflows_window) = self.ticks.window(now);
        let window = summarize(&window, window_over);
        let lifetime = summarize(&self.ticks.lifetime, self.ticks.lifetime_over);
        let (total_rate, clients_rates) = self.rates.sample(now, self.totals.snapshot(), clients);
        let mut roles = RoleCounts::default();
        for client in clients {
            roles.add(client.traffic.role());
        }
        let per_client_max = clients_rates
            .iter()
            .map(|client| client.out_bytes_per_s)
            .fold(0.0, f64::max);
        let per_client_mean = if clients_rates.is_empty() {
            0.0
        } else {
            clients_rates
                .iter()
                .map(|client| client.out_bytes_per_s)
                .sum::<f64>()
                / clients_rates.len() as f64
        };
        let totals = self.totals.snapshot();
        let health = Health::from_reasons(evaluate(&window, budget_ms, overflows_window));
        self.log_transition(&health);
        self.health = Some(health);
        self.ops = Some(OpsStatus {
            version: OPS_VERSION,
            build: self.build.clone(),
            process: process_info(now),
            tick: TickTiming {
                budget_ms,
                scope: TICK_SCOPE.to_string(),
                window_s: WINDOW.as_secs(),
                window,
                lifetime,
            },
            connections: roles,
            traffic: TrafficTotals {
                window_s: WINDOW.as_secs(),
                out_bytes_per_s: total_rate.out_bytes,
                in_bytes_per_s: total_rate.in_bytes,
                out_msgs_per_s: total_rate.out_msgs,
                in_msgs_per_s: total_rate.in_msgs,
                per_client_out_bytes_per_s_mean: per_client_mean,
                per_client_out_bytes_per_s_max: per_client_max,
                out_bytes: totals.out_bytes,
                in_bytes: totals.in_bytes,
                out_msgs: totals.out_msgs,
                in_msgs: totals.in_msgs,
                queue_overflows_window: overflows_window,
                queue_overflows_total: self.ticks.overflows_total,
            },
            clients: Some(clients_rates),
        });
    }

    fn log_transition(&self, next: &Health) {
        let previous = self.health.as_ref().map(|health| health.status);
        match (previous, next.status) {
            (Some(HealthState::Degraded), HealthState::Ok) => {
                tracing::info!("health ok");
            }
            (Some(HealthState::Ok) | None, HealthState::Degraded) => {
                tracing::warn!(reasons = ?next.reasons, "health degraded");
            }
            (Some(HealthState::Degraded), HealthState::Degraded)
                if self.health.as_ref().map(|health| &health.reasons) != Some(&next.reasons) =>
            {
                tracing::warn!(reasons = ?next.reasons, "health degraded");
            }
            _ => {}
        }
    }

    /// Stamp the latest operator block onto a fresh match line.
    pub fn apply(&self, live: &mut LiveStatus, now: Instant) {
        live.health.clone_from(&self.health);
        live.ops.clone_from(&self.ops);
        if let Some(ops) = live.ops.as_mut() {
            ops.process = process_info(now);
        }
    }

    pub fn health(&self) -> Option<&Health> {
        self.health.as_ref()
    }
}

/// What `GET /status` sends: the client list only when asked, and `stale`
/// when the tick loop has not refreshed the snapshot within `STALE_AFTER`.
pub fn served_status(live: &LiveStatus, with_clients: bool, uptime_now: Duration) -> LiveStatus {
    let mut served = live.clone();
    let Some(ops) = served.ops.as_mut() else {
        return served;
    };
    if !with_clients {
        ops.clients = None;
    }
    let age = uptime_now.as_secs_f64() - ops.process.uptime_s;
    if age > STALE_AFTER.as_secs_f64() {
        let health = served
            .health
            .get_or_insert_with(|| Health::from_reasons(Vec::new()));
        if !health.reasons.contains(&HealthReason::Stale) {
            health.reasons.push(HealthReason::Stale);
        }
        health.status = HealthState::Degraded;
    }
    served
}

/// `true` when the request line asks for the per-session list:
/// `GET /status?clients=1` (or a bare `clients` key) among other parameters.
pub fn wants_clients(request: &[u8]) -> bool {
    let line = request
        .split(|byte| *byte == b'\n')
        .next()
        .unwrap_or_default();
    let line = String::from_utf8_lossy(line);
    let Some(target) = line.split_ascii_whitespace().nth(1) else {
        return false;
    };
    let Some((path, query)) = target.split_once('?') else {
        return false;
    };
    path == "/status"
        && query
            .split('&')
            .any(|pair| matches!(pair, "clients" | "clients=1" | "clients=true"))
}

#[cfg(test)]
mod tests;
