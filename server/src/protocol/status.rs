//! Operator fields of `GET /status`. The match line in `LiveStatus` keeps
//! schema 2; these are additive and carry their own `ops.version`. Counts,
//! rates and timings only: no addresses, callsigns, tickets or tokens.
use super::Role;
use serde::{Deserialize, Serialize};

/// Bumped when an `ops` field changes meaning or is removed.
pub const OPS_VERSION: u32 = 1;

/// `ok` or `degraded`, with every reason that currently applies.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Health {
    pub status: HealthState,
    pub reasons: Vec<HealthReason>,
}

impl Health {
    pub fn from_reasons(reasons: Vec<HealthReason>) -> Self {
        Self {
            status: if reasons.is_empty() {
                HealthState::Ok
            } else {
                HealthState::Degraded
            },
            reasons,
        }
    }

    pub fn is_ok(&self) -> bool {
        self.status == HealthState::Ok
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum HealthState {
    Ok,
    Degraded,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum HealthReason {
    /// Window p99 tick handler time at or above the 50 ms budget.
    TickP99OverBudget,
    /// The loop ran under 19 ticks per second over the window: ticks skipped.
    TickRateLow,
    /// A slow reader's outbound queue overflowed inside the window.
    OutboundDrops,
    /// The served snapshot stopped being refreshed by the tick loop.
    Stale,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct OpsStatus {
    pub version: u32,
    pub build: BuildInfo,
    pub process: ProcessInfo,
    pub tick: TickTiming,
    pub connections: RoleCounts,
    pub traffic: TrafficTotals,
    /// Present only for `GET /status?clients=1`. Anonymous, one per session.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub clients: Option<Vec<ClientRate>>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct BuildInfo {
    /// The server crate version, not the release tag.
    pub crate_version: String,
    /// Release name baked in at build time (`FRAGR_BUILD_VERSION`), if any.
    pub release: Option<String>,
    /// Commit baked in at build time (`FRAGR_BUILD_COMMIT`), or `unknown`.
    pub commit: String,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ProcessInfo {
    /// Wall clock at process start, Unix seconds.
    pub started_unix_s: u64,
    /// Monotonic seconds since process start when this snapshot was taken.
    pub uptime_s: f64,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct TickTiming {
    pub budget_ms: f64,
    /// What one sample covers: `tick_handler` is expiry, simulation, run save,
    /// and broadcast plus unicast enqueue for one tick.
    pub scope: String,
    pub window_s: u64,
    /// Ticks the loop actually ran per second over the window (nominal 20).
    /// `null` until the window spans 30 s.
    pub rate_hz: Option<f64>,
    pub window: TickSummary,
    pub lifetime: TickSummary,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct TickSummary {
    pub count: u64,
    pub p50_ms: f64,
    pub p95_ms: f64,
    pub p99_ms: f64,
    pub max_ms: f64,
    /// Exact count of samples at or above the budget.
    pub over_budget: u64,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct RoleCounts {
    pub total: usize,
    pub spectators: usize,
    pub humans: usize,
    pub agents: usize,
}

impl RoleCounts {
    pub fn add(&mut self, role: Role) {
        self.total += 1;
        match role {
            Role::Spectator => self.spectators += 1,
            Role::Human => self.humans += 1,
            Role::Agent => self.agents += 1,
        }
    }
}

/// Text payload bytes and messages, excluding WebSocket framing and TCP.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct TrafficTotals {
    pub window_s: u64,
    pub out_bytes_per_s: f64,
    pub in_bytes_per_s: f64,
    pub out_msgs_per_s: f64,
    pub in_msgs_per_s: f64,
    /// Over live sessions only.
    pub per_client_out_bytes_per_s_mean: f64,
    pub per_client_out_bytes_per_s_max: f64,
    /// Since process start, including sessions that have closed.
    pub out_bytes: u64,
    pub in_bytes: u64,
    pub out_msgs: u64,
    pub in_msgs: u64,
    pub queue_overflows_window: u64,
    pub queue_overflows_total: u64,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ClientRate {
    pub role: Role,
    pub connected_s: f64,
    pub out_bytes_per_s: f64,
    pub in_bytes_per_s: f64,
    pub out_msgs_per_s: f64,
    pub in_msgs_per_s: f64,
    pub out_bytes: u64,
    pub in_bytes: u64,
    pub queue_depth: usize,
}
