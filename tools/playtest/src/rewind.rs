//! Deterministic lag-compensation matrix (#434 stage 5).
//!
//! It models the thin client's own timeline in process, with no sockets and no
//! wall clock, so a run is the same on every host. A human shooter stands still
//! and a fighter strafes across the lane on a seeded schedule. For each trial
//! the shooter's client sees the strafer where `RemotePresentation` would draw
//! it: the newest snapshot arrival less half the round trip, less the two-tick
//! interpolation buffer. It aims exactly at the chest it drew, with a first
//! shot that has no bloom. The Action reaches the server half a round trip
//! later and fires on the next tick. The server then resolves the ray, with or
//! without the client's reported view time.
//!
//! "On target on the client" is true by construction for every trial whose
//! client-side line is open; a server miss is a shot the player saw land.
//! Snapshot and Action delivery are modelled as fixed one-way delays of half
//! the round trip. Jitter, loss and TCP retransmission are not modelled.

use fragr_server::protocol::{Action, EquipmentPolicy, Role, WeaponType};
use fragr_server::sim::{GameState, PLAYER_FLOOR_Y};
use serde::Serialize;
use uuid::Uuid;

/// Server ticks per second and the client's interpolation buffer, as in
/// `client/scripts/remote_presentation.gd`.
const TICK_MS: f64 = 50.0;
const BUFFER_TICKS: f64 = 2.0;
/// The simulated lane: the shooter at the south end, the strafer north.
const SHOOTER: [f32; 3] = [0.0, 0.0, -8.0];
const STRAFER: [f32; 3] = [0.0, 0.0, 8.0];
/// Ticks of strafing before the first eligible shot.
const WARMUP_TICKS: u64 = 24;

/// Whether the shooter's Action carries the view time it drew.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum RewindMode {
    /// No `view_tick`: the server tests the present volumes.
    Off,
    /// The client reports its render time; the server rewinds within bounds.
    On,
}

#[derive(Debug, Clone, Serialize)]
pub struct RewindRow {
    pub rtt_ms: u32,
    pub mode: RewindMode,
    /// Trials whose client-side line was open: shots the client saw land.
    pub client_on_target: u32,
    /// Of those, the shots the server also scored on the strafer.
    pub server_hits: u32,
    pub miss_rate: f64,
    /// Fire tick minus the drawn view time, in milliseconds.
    pub mean_view_lag_ms: f64,
    pub max_view_lag_ms: f64,
    /// Horizontal distance between the drawn strafer and the present one.
    pub mean_offset_m: f64,
    pub p95_offset_m: f64,
}

#[derive(Debug, Clone, Serialize)]
pub struct RewindReport {
    pub schema: u32,
    pub seed: u64,
    pub trials: u32,
    pub rows: Vec<RewindRow>,
}

/// The round trips the matrix covers.
pub const RTTS_MS: [u32; 4] = [0, 50, 100, 150];

/// Small, owned stream so the strafe schedule never shares the sim's draws.
struct Stream(u64);

impl Stream {
    fn next(&mut self) -> u64 {
        let mut x = self.0;
        x ^= x >> 12;
        x ^= x << 25;
        x ^= x >> 27;
        self.0 = x;
        x.wrapping_mul(0x2545_F491_4F6C_DD1D)
    }
    fn unit(&mut self) -> f64 {
        (self.next() >> 11) as f64 / (1u64 << 53) as f64
    }
    fn below(&mut self, n: u64) -> u64 {
        self.next() % n
    }
}

struct Trial {
    on_target: bool,
    hit: bool,
    view_lag_ticks: f64,
    offset_m: f64,
}

fn strafe_action(direction: i8) -> Action {
    Action {
        left: direction < 0,
        right: direction > 0,
        // Facing the shooter, so left and right run across the lane.
        yaw: Some(-std::f32::consts::FRAC_PI_2),
        ..Default::default()
    }
}

fn place(state: &mut GameState, id: Uuid, feet: [f32; 3]) {
    let p = state.players.iter_mut().find(|p| p.id == id).unwrap();
    [p.x, p.y, p.z] = [feet[0], feet[1] + PLAYER_FLOOR_Y, feet[2]];
    p.vy = 0.0;
}

fn lerp(a: [f32; 3], b: [f32; 3], t: f64) -> [f32; 3] {
    std::array::from_fn(|i| a[i] + (b[i] - a[i]) * t as f32)
}

fn run_trial(seed: u64, trial: u32, rtt_ms: u32, mode: RewindMode) -> Trial {
    let mut stream = Stream(
        (seed ^ 0x9E37_79B9_7F4A_7C15).wrapping_add(u64::from(trial).wrapping_mul(0xA24B_AED4)),
    );
    if stream.0 == 0 {
        stream.0 = 1;
    }
    let mut state = GameState::new();
    state.seed(seed.wrapping_add(u64::from(trial)));
    state.start_round();
    state.pickups.clear();
    let (shooter, strafer) = (Uuid::from_u128(0x5100), Uuid::from_u128(0x5200));
    state.add_player(shooter, "shooter".into(), Role::Human);
    state.add_player(strafer, "strafer".into(), Role::Agent);
    place(&mut state, shooter, SHOOTER);
    place(&mut state, strafer, STRAFER);
    state.spawn_shields.clear();
    {
        let p = state.players.iter_mut().find(|p| p.id == shooter).unwrap();
        p.inventory = fragr_server::inventory::Inventory::new(EquipmentPolicy::Discovery);
        p.inventory.grant_weapon(WeaponType::Rail);
        p.weapon = WeaponType::Rail;
        p.fire_cooldown = 0;
    }

    // The fire tick. The Action arrives at a seeded phase inside the interval
    // before it, so its view time spans a whole tick of render phase.
    let lag_ticks = f64::from(rtt_ms) / TICK_MS;
    let fire_tick = state.tick + WARMUP_TICKS + 8 + stream.below(16);
    let phase = stream.unit();
    let arrival = (fire_tick - 1) as f64 + phase;
    // Snapshot travel plus Action travel is the whole round trip.
    let view = arrival - lag_ticks - BUFFER_TICKS;

    let mut feet: std::collections::BTreeMap<u64, ([f32; 3], bool)> = Default::default();
    let mut direction: i8 = if stream.below(2) == 0 { -1 } else { 1 };
    let mut hold = 3 + stream.below(10);
    let mut trial = Trial {
        on_target: false,
        hit: false,
        view_lag_ticks: fire_tick as f64 - view,
        offset_m: 0.0,
    };
    while state.tick < fire_tick {
        if hold == 0 {
            // Reverse, stop or keep going, like a fighter juking a rail.
            let resume: i8 = if stream.below(2) == 0 { -1 } else { 1 };
            direction = match (stream.below(5), direction) {
                (0, _) => 0,
                (_, 0) => resume,
                (1 | 2, moving) => -moving,
                (_, moving) => moving,
            };
            hold = 3 + stream.below(10);
        }
        hold -= 1;
        state.set_action(strafer, strafe_action(direction));
        if state.tick + 1 == fire_tick {
            let base = view.floor() as u64;
            let (a, ducked) = feet[&base];
            let (b, _) = feet.get(&(base + 1)).copied().unwrap_or((a, ducked));
            let drawn = lerp(a, b, view - base as f64);
            let eye = {
                let p = state.players.iter().find(|p| p.id == shooter).unwrap();
                [
                    p.x,
                    p.y - PLAYER_FLOOR_Y + fragr_server::combat::stance_eye(None, false),
                    p.z,
                ]
            };
            let chest = fragr_server::combat::aim_point_for(drawn, None, ducked);
            trial.on_target =
                fragr_server::combat::line_of_sight(eye, chest, &state.current_arena().solids);
            let (yaw, pitch) = fragr_server::combat::aim_at(eye, chest).unwrap();
            let action = Action {
                fire: true,
                yaw: Some(yaw),
                pitch: Some(pitch),
                view_tick: (mode == RewindMode::On).then_some(view),
                ..Default::default()
            };
            state.set_action(shooter, action);
        }
        state.tick(TICK_MS as f32 / 1000.0);
        let p = state.players.iter().find(|p| p.id == strafer).unwrap();
        feet.insert(state.tick, ([p.x, p.y - PLAYER_FLOOR_Y, p.z], p.ducking));
    }
    let present = feet[&fire_tick].0;
    let base = view.floor() as u64;
    let drawn = lerp(
        feet[&base].0,
        feet.get(&(base + 1)).map(|f| f.0).unwrap_or(feet[&base].0),
        view - base as f64,
    );
    trial.offset_m = f64::from((present[0] - drawn[0]).hypot(present[2] - drawn[2]));
    trial.hit = state
        .shot_results
        .iter()
        .any(|shot| shot.shooter_id == shooter && shot.target_id == Some(strafer));
    trial
}

pub fn run_row(seed: u64, trials: u32, rtt_ms: u32, mode: RewindMode) -> RewindRow {
    let results: Vec<Trial> = (0..trials)
        .map(|trial| run_trial(seed, trial, rtt_ms, mode))
        .collect();
    let seen: Vec<&Trial> = results.iter().filter(|t| t.on_target).collect();
    let client_on_target = seen.len() as u32;
    let server_hits = seen.iter().filter(|t| t.hit).count() as u32;
    let mut offsets: Vec<f64> = seen.iter().map(|t| t.offset_m).collect();
    offsets.sort_by(f64::total_cmp);
    let mean = |values: &mut dyn Iterator<Item = f64>| {
        let (sum, n) = values.fold((0.0, 0u32), |(s, n), v| (s + v, n + 1));
        if n == 0 {
            0.0
        } else {
            sum / f64::from(n)
        }
    };
    RewindRow {
        rtt_ms,
        mode,
        client_on_target,
        server_hits,
        miss_rate: if client_on_target == 0 {
            0.0
        } else {
            1.0 - f64::from(server_hits) / f64::from(client_on_target)
        },
        mean_view_lag_ms: mean(&mut seen.iter().map(|t| t.view_lag_ticks * TICK_MS)),
        max_view_lag_ms: seen
            .iter()
            .map(|t| t.view_lag_ticks * TICK_MS)
            .fold(0.0, f64::max),
        mean_offset_m: mean(&mut offsets.iter().copied()),
        p95_offset_m: offsets
            .get((offsets.len() * 95 / 100).min(offsets.len().saturating_sub(1)))
            .copied()
            .unwrap_or(0.0),
    }
}

pub fn run_matrix(seed: u64, trials: u32, modes: &[RewindMode]) -> RewindReport {
    let rows = modes
        .iter()
        .flat_map(|&mode| RTTS_MS.iter().map(move |&rtt| (rtt, mode)))
        .map(|(rtt, mode)| run_row(seed, trials, rtt, mode))
        .collect();
    RewindReport {
        // The seed and the trial count reproduce the report exactly.
        schema: 1,
        seed,
        trials,
        rows,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_matrix_is_deterministic_and_rewind_recovers_drawn_hits() {
        let report = run_matrix(42, 60, &[RewindMode::Off, RewindMode::On]);
        assert_eq!(report.rows.len(), 8);
        let again = run_matrix(42, 60, &[RewindMode::Off, RewindMode::On]);
        assert_eq!(
            serde_json::to_string(&report).unwrap(),
            serde_json::to_string(&again).unwrap()
        );
        let row = |rtt: u32, mode: RewindMode| {
            report
                .rows
                .iter()
                .find(|row| row.rtt_ms == rtt && row.mode == mode)
                .unwrap()
        };
        for rtt in RTTS_MS {
            let (off, on) = (row(rtt, RewindMode::Off), row(rtt, RewindMode::On));
            assert_eq!(off.client_on_target, 60, "the lane is open");
            assert_eq!(off.mean_view_lag_ms, on.mean_view_lag_ms);
            assert!(off.miss_rate > 0.3, "{off:?}");
            assert!(on.miss_rate < off.miss_rate, "{on:?} {off:?}");
            // The lag is the round trip, the buffer and up to a tick of phase.
            let floor = f64::from(rtt) + 100.0;
            assert!(off.mean_view_lag_ms > floor && off.max_view_lag_ms <= floor + 50.0);
        }
        // Inside the 200 ms bound every drawn hit lands.
        for rtt in [0, 50] {
            assert_eq!(row(rtt, RewindMode::On).miss_rate, 0.0);
        }
    }
}
