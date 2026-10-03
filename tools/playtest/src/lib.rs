//! Agent playtest harness: boots the authoritative server in-process on a free
//! loopback port, connects scripted agents over the real wire, watches the match
//! as a spectator, and turns what it saw into a metrics report. Humans still
//! judge fun; this catches stuck agents, dead time, spawn deaths, and regressions
//! in the numbers that make a round feel alive.

use fragr_server::movement::{Solid, EYE_HEIGHT};
use fragr_server::protocol::{
    Action, ClientMessage, FlagEventKind, FlagState, FlagStatus, GameEvent, LookAt, Role,
    ServerMessage, Snapshot, Team, WeaponType,
};
use fragr_server::run::{run_server, ServerOptions, TICK};
use fragr_server::sim::{MapKind, MatchConfig};
use futures_util::{SinkExt, StreamExt};
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;
use std::fmt;
use std::time::Duration;
use tokio_tungstenite::{connect_async, tungstenite::Message};
use uuid::Uuid;

pub mod fanout;
pub mod sabotage;
pub mod soak;

/// Ticks per second of the authoritative loop.
pub const TICKS_PER_SECOND: f64 = 20.0;
/// A death this soon after a spawn counts as a spawn death.
pub const SPAWN_DEATH_WINDOW_TICKS: u64 = 40;
/// Bound additional CTF diagnostic storage independently of match duration.
const MAX_CARRY_EPISODES: usize = 256;
/// The authoritative flag touch radius is 2.5 world units.
const CTF_HOME_TOUCH_RADIUS: f32 = 2.5;
/// Reflex agents fire inside this range and walk toward targets beyond three units.
const FIRE_RANGE: f32 = 20.0;
const CLOSE_RANGE: f32 = 3.0;
/// Hold the shotgun inside this distance, the railgun beyond the next one,
/// and the needle gun between. The first combat report showed the reflex
/// agents never swapping, which left two of the three weapons unmeasured and
/// the weapon triangle an assertion rather than a finding.
/// Tuned to where fights actually happen, not to the weapons' maximum reach:
/// the first combat runs found three quarters of kills inside ten units of a
/// fifty unit arena, so a triangle drawn at thirty units would never be used.
const SCATTER_RANGE: f32 = 6.0;
const RAIL_RANGE: f32 = 18.0;

/// Bare time-to-kill band the weapon table must stay inside (#124 / gunfeel).
/// Sticky means CI fails if the table drifts out of band, not if a short
/// playtest sample wobbles.
pub const STICKY_TTK_MIN_S: f64 = 0.5;
pub const STICKY_TTK_MAX_S: f64 = 1.2;
/// Unarmoured fighter HP the sticky table assumes (matches sim spawn HP).
pub const STICKY_FIGHTER_HP: i32 = 100;

/// One weapon's clean-hit time to kill, derived from the live table.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct StickyWeaponTtk {
    pub weapon: WeaponType,
    pub hits_to_kill: u32,
    pub seconds: f64,
}

/// Flechette, rail, and scatter clean-hit TTK from `WeaponType` damage and
/// cooldown. Point-blank for the scatter gun, every pellet landing, so falloff
/// does not hide a table regression. This is the #124 claim made
/// CI-assertable from the harness.
pub fn sticky_weapon_ttk_table() -> [StickyWeaponTtk; 3] {
    [WeaponType::Flechette, WeaponType::Rail, WeaponType::Scatter].map(|weapon| {
        let damage = (weapon.damage_at(0.0) * weapon.pellets() as i32).max(1);
        let hits = ((STICKY_FIGHTER_HP + damage - 1) / damage) as u32;
        let seconds =
            (hits.saturating_sub(1) as f64) * (weapon.cooldown_ticks() as f64) / TICKS_PER_SECOND;
        StickyWeaponTtk {
            weapon,
            hits_to_kill: hits,
            seconds,
        }
    })
}

/// Problems when any sticky weapon leaves the target band or the expected
/// hit count. Empty means the table still kills in about a second, three ways.
pub fn check_sticky_ttk_table() -> Vec<String> {
    let expected = [
        (WeaponType::Flechette, 4u32, 0.6),
        (WeaponType::Rail, 2, 1.0),
        (WeaponType::Scatter, 2, 0.6),
    ];
    let mut problems = Vec::new();
    for (row, (weapon, hits, seconds)) in sticky_weapon_ttk_table().into_iter().zip(expected) {
        if row.weapon != weapon {
            problems.push(format!(
                "sticky TTK row order drifted: got {:?}, expected {:?}",
                row.weapon, weapon
            ));
            continue;
        }
        if row.hits_to_kill != hits {
            problems.push(format!(
                "{} sticky hits-to-kill {} (want {hits})",
                weapon.name(),
                row.hits_to_kill
            ));
        }
        if (row.seconds - seconds).abs() > 0.001 {
            problems.push(format!(
                "{} sticky TTK {:.3} s (want {seconds:.1} s)",
                weapon.name(),
                row.seconds
            ));
        }
        if !(STICKY_TTK_MIN_S..=STICKY_TTK_MAX_S).contains(&row.seconds) {
            problems.push(format!(
                "{} sticky TTK {:.3} s outside {STICKY_TTK_MIN_S}..{STICKY_TTK_MAX_S} s band",
                weapon.name(),
                row.seconds
            ));
        }
    }
    problems
}

/// The weapon a fighter should be holding at this distance.
pub fn weapon_for_distance(dist: f32) -> WeaponType {
    if dist < SCATTER_RANGE {
        WeaponType::Scatter
    } else if dist > RAIL_RANGE {
        WeaponType::Rail
    } else {
        WeaponType::Flechette
    }
}

/// Parse a wire weapon name; unknown names keep whatever is held.
fn weapon_from_wire(name: &str) -> Option<WeaponType> {
    match name.to_ascii_lowercase().as_str() {
        "flechette" => Some(WeaponType::Flechette),
        "rail" => Some(WeaponType::Rail),
        "scatter" => Some(WeaponType::Scatter),
        "tack" => Some(WeaponType::Tack),
        "fists" => Some(WeaponType::Fists),
        "shiv" => Some(WeaponType::Shiv),
        _ => None,
    }
}
/// Movement smaller than this between snapshots counts as idle.
const IDLE_EPSILON: f32 = 0.01;
/// Share of frags that may be spawn deaths before a run is called broken,
/// judged against the low end of the interval rather than the raw ratio.
const SPAWN_DEATH_RATE_CEILING: f64 = 0.10;
/// Opening spawn deaths allowed per completed round. The opening is placed
/// from the whole roster before anyone moves, so a death there is a map or
/// selector defect rather than a sampling accident. One is tolerated for a
/// fighter who walks out of cover into a lane inside the window; the rosters
/// that exposed this gap lost two to four fighters in every opening.
const OPENING_SPAWN_DEATHS_PER_ROUND: u64 = 1;
/// Radians the patrol sweep turns per tick: a full circle in about five
/// seconds, slow enough to actually cross ground rather than spin on the spot.
const PATROL_TURN_PER_TICK: f32 = 0.06;

#[derive(Debug, Clone)]
pub struct Config {
    pub agents: usize,
    pub rounds: u32,
    pub map: MapKind,
    pub frag_limit: u32,
    pub capture_limit: u32,
    pub time_limit_ticks: u32,
    /// Hard stop for the whole run, in ticks of the observed clock.
    pub max_ticks: u64,
    /// Simulation seed. The same seed gives the same match, which is what lets
    /// two harness runs be compared rather than merely averaged.
    pub seed: u64,
    /// Policies dealt round robin to the agents.
    pub tiers: Vec<Policy>,
    /// The host's rule set: mode and mutators. Plain free-for-all by default.
    pub rules: fragr_server::rules::RuleSet,
    /// Sabotage format and clocks, read only in Sabotage. The live clock comes
    /// from `time_limit_ticks`.
    pub sabotage: fragr_server::rules::SabotageConfig,
}

impl Default for Config {
    fn default() -> Self {
        Config {
            agents: 4,
            rounds: 1,
            map: MapKind::ArenaDuel,
            frag_limit: 5,
            capture_limit: 3,
            time_limit_ticks: 20 * 60,
            max_ticks: 20 * 120,
            seed: 1,
            tiers: vec![Policy::Reflex],
            rules: fragr_server::rules::RuleSet::default(),
            sabotage: fragr_server::rules::SabotageConfig::default(),
        }
    }
}

#[derive(Debug)]
pub enum Error {
    Server(String),
    Transport(String),
    Timeout(&'static str),
    Io(std::io::Error),
}

impl fmt::Display for Error {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Error::Server(msg) => write!(f, "server error: {msg}"),
            Error::Transport(msg) => write!(f, "transport error: {msg}"),
            Error::Timeout(what) => write!(f, "timed out waiting for {what}"),
            Error::Io(err) => write!(f, "io error: {err}"),
        }
    }
}

impl std::error::Error for Error {}

impl From<std::io::Error> for Error {
    fn from(err: std::io::Error) -> Self {
        Error::Io(err)
    }
}

/// One event with the observer's clock (the last snapshot tick seen before it).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TimedEvent {
    pub tick: u64,
    pub event: GameEvent,
}

/// Width of an engagement-distance bucket, in world units. Five units is
/// about a third of the scatter gun's reach and a twelfth of the rail's, so
/// the three weapons land in visibly different buckets.
pub const DISTANCE_BUCKET: f32 = 5.0;
/// Buckets kept; the last one is everything beyond fifty units, which is a
/// corner-to-corner shot in a fifty unit arena.
pub const DISTANCE_BUCKETS: usize = 11;

/// A distribution reported the honest way: the shape, not just the middle,
/// and always with the sample size that earned it.
#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq)]
pub struct Quantiles {
    pub count: u64,
    pub min: f64,
    pub p50: f64,
    pub p90: f64,
    pub max: f64,
    pub mean: f64,
}

impl Quantiles {
    /// From values in any order. Empty gives zeros and a count of zero, which
    /// is how a reader knows there is nothing to read.
    pub fn from_values(values: &[f64]) -> Self {
        let mut sorted: Vec<f64> = values.iter().copied().filter(|v| v.is_finite()).collect();
        if sorted.is_empty() {
            return Quantiles::default();
        }
        sorted.sort_by(|a, b| a.total_cmp(b));
        let pick = |q: f64| -> f64 {
            let idx = ((sorted.len() as f64 - 1.0) * q).round() as usize;
            sorted[idx.min(sorted.len() - 1)]
        };
        Quantiles {
            count: sorted.len() as u64,
            min: sorted[0],
            p50: pick(0.5),
            p90: pick(0.9),
            max: sorted[sorted.len() - 1],
            mean: sorted.iter().sum::<f64>() / sorted.len() as f64,
        }
    }
}

/// Wilson score interval for a proportion at about ninety five percent
/// confidence. A hit rate from nine shots and one from nine hundred are not
/// the same claim, and this is what says so. Zero trials gives the full range.
pub fn wilson_interval(hits: u64, trials: u64) -> (f64, f64) {
    if trials == 0 {
        return (0.0, 1.0);
    }
    let z = 1.96f64;
    let n = trials as f64;
    let p = hits as f64 / n;
    let denom = 1.0 + z * z / n;
    let centre = p + z * z / (2.0 * n);
    let margin = z * ((p * (1.0 - p) / n) + (z * z / (4.0 * n * n))).sqrt();
    (
        ((centre - margin) / denom).clamp(0.0, 1.0),
        ((centre + margin) / denom).clamp(0.0, 1.0),
    )
}

/// What one weapon did: how often it fired, how often that landed, how far
/// away, and how much damage it dealt.
#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq)]
pub struct WeaponReport {
    pub shots: u64,
    pub hits: u64,
    pub accuracy: f64,
    /// The interval on that accuracy, so a small sample admits it.
    pub accuracy_lo: f64,
    pub accuracy_hi: f64,
    pub damage: i64,
    pub kills: u64,
    /// Seconds from first damage to death for kills this weapon finished.
    pub time_to_kill_s: Quantiles,
    /// Distance at which its shots landed.
    pub hit_distance: Quantiles,
    /// Distance at which it killed. The weapon triangle works when these peak
    /// in different places.
    pub kill_distance: Quantiles,
}

/// The combat picture: how long a kill takes, how often shots land, and at
/// what range each weapon does its work.
#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq)]
pub struct CombatReport {
    /// Seconds from the first damage on a victim to their death.
    pub time_to_kill_s: Quantiles,
    pub shots: u64,
    pub hits: u64,
    pub accuracy: f64,
    pub accuracy_lo: f64,
    pub accuracy_hi: f64,
    pub shots_per_kill: f64,
    /// Kills per five unit bucket, the last holding everything beyond.
    pub kill_distance_buckets: Vec<u64>,
    pub by_weapon: BTreeMap<String, WeaponReport>,
}

/// Running tallies for one weapon while a run is in flight.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct WeaponTally {
    pub shots: u64,
    pub hits: u64,
    pub damage: i64,
    pub kills: u64,
    pub time_to_kill_s: Vec<f64>,
    pub hit_distances: Vec<f64>,
    pub kill_distances: Vec<f64>,
}

/// Per-fighter movement and fire bookkeeping from snapshots.
#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq)]
pub struct AgentTrack {
    pub ticks_present: u64,
    /// Ticks without movement while a round is active.
    pub idle_ticks: u64,
    /// Longest run of active-round ticks where a *living* fighter neither
    /// moved nor fired. Death is excluded deliberately: the server freezes a
    /// corpse in place for the respawn delay, so counting it made a short
    /// wedge next to a death read as one long stall, and the number could not
    /// tell a wedged agent from a dead one. Dead time is `dead_max_ticks`.
    pub stuck_max_ticks: u64,
    stuck_run: u64,
    /// Longest unbroken run of ticks spent off the field. The protocol has no
    /// corpse: the server drops a fighter from the snapshot until it respawns,
    /// so absence is how death looks from the outside. Three seconds is the
    /// respawn delay; far more than that is a fighter that never came back.
    pub dead_max_ticks: u64,
    dead_run: u64,
    /// Where and when the longest stall began, so a failure names a place on
    /// the map instead of only a duration.
    pub stuck_from_tick: u64,
    pub stuck_at: (f32, f32),
    stuck_run_from: u64,
    /// Set while a fighter is away, so the stall run breaks across a death
    /// instead of splicing the seconds before it to the seconds after.
    off_field: bool,
    last_pos: Option<(f32, f32)>,
    /// Where the fighter stood on its first snapshot after arriving, so a
    /// spawn death names the spawn point rather than only the tick.
    #[serde(default)]
    spawned_at: Option<(f32, f32)>,
    pub fire_ticks: u64,
    pub weapon_fire_ticks: BTreeMap<String, u64>,
    /// Weapon held on the newest snapshot, for attributing a frag.
    pub last_weapon: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct KillEvidence {
    killer: String,
    weapon: String,
    distance: f64,
}

/// Positions last seen for the two fighters in one frag.
#[derive(Debug, Clone, Copy, Default, Serialize, Deserialize, PartialEq)]
struct FragPlace {
    victim_spawn: Option<(f32, f32)>,
    victim: Option<(f32, f32)>,
    killer: Option<(f32, f32)>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum CarryEnd {
    Dropped,
    Captured,
    RoundEnded,
    ObservationEnded,
    Incomplete,
}

/// One bounded summary of a server-owned flag carry. Distances are horizontal
/// world units to the carrier's own stand, sampled only while the snapshot
/// still identifies this fighter as the carrier.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct CarryEpisode {
    pub flag: Team,
    pub carrier: Option<String>,
    pub started_tick: u64,
    pub ended_tick: u64,
    pub end: CarryEnd,
    pub first_distance_to_home: Option<f32>,
    pub closest_distance_to_home: Option<f32>,
    pub last_distance_to_home: Option<f32>,
    pub observed_carrier_ticks: u64,
    pub own_flag_away_ticks: u64,
    pub home_blocked_ticks: u64,
    /// A same-tick frag named this carrier when the flag was dropped.
    pub combat_drop: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct ActiveCarry {
    episode: CarryEpisode,
    carrier_id: Option<Uuid>,
    last_sample_tick: Option<u64>,
}

impl ActiveCarry {
    fn sample(
        &mut self,
        tick: u64,
        carrier: Uuid,
        name: &str,
        position: [f32; 3],
        own: &FlagState,
    ) {
        if self.last_sample_tick == Some(tick) || self.carrier_id.is_some_and(|id| id != carrier) {
            return;
        }
        self.carrier_id = Some(carrier);
        self.episode.carrier.get_or_insert_with(|| name.to_string());
        self.last_sample_tick = Some(tick);
        let distance = (position[0] - own.stand[0]).hypot(position[2] - own.stand[2]);
        let episode = &mut self.episode;
        episode.first_distance_to_home.get_or_insert(distance);
        episode.closest_distance_to_home = Some(
            episode
                .closest_distance_to_home
                .map_or(distance, |closest| closest.min(distance)),
        );
        episode.last_distance_to_home = Some(distance);
        episode.observed_carrier_ticks += 1;
        if own.status != FlagStatus::Home {
            episode.own_flag_away_ticks += 1;
            if distance <= CTF_HOME_TOUCH_RADIUS
                && (position[1] - own.stand[1]).abs() <= CTF_HOME_TOUCH_RADIUS
            {
                episode.home_blocked_ticks += 1;
            }
        }
    }
}

/// Everything the observer keeps. Snapshots are folded in as they arrive so a
/// long run does not hold every frame in memory.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct Observation {
    pub snapshots_seen: u64,
    pub first_tick: Option<u64>,
    pub last_tick: u64,
    pub snapshot_bytes: u64,
    /// Sum of carrier ticks across both flags, measured from received snapshots.
    #[serde(default)]
    pub carrier_ticks: u64,
    #[serde(default)]
    carry_episodes: Vec<CarryEpisode>,
    #[serde(default)]
    active_carries: [Option<ActiveCarry>; 2],
    /// The immediately preceding authoritative snapshot, not a frame log.
    #[serde(default)]
    latest_flags: Option<[FlagState; 2]>,
    #[serde(default)]
    carry_episodes_omitted: u64,
    #[serde(default)]
    unmatched_flag_ends: u64,
    pub events: Vec<TimedEvent>,
    pub tracks: BTreeMap<String, AgentTrack>,
    /// Per weapon, what it fired and what landed.
    pub weapons: BTreeMap<String, WeaponTally>,
    /// Victim name to the tick their engagement started, so a death can be
    /// timed from the first damage that led to it.
    pub engagement_start: BTreeMap<String, u64>,
    /// Seconds from first damage to death, one per kill that had an opening hit.
    pub time_to_kill_s: Vec<f64>,
    /// Distance of every kill, for the histogram.
    pub kill_distances: Vec<f64>,
    /// Snapshot evidence awaiting its following frag event, never a prior tick.
    #[serde(default)]
    pending_kills: BTreeMap<String, KillEvidence>,
    #[serde(default, skip_serializing_if = "BTreeMap::is_empty")]
    pending_grenade_kills: BTreeMap<Uuid, Uuid>,
    #[serde(default, skip_serializing_if = "BTreeMap::is_empty")]
    pending_grenade_names: BTreeMap<String, String>,
    /// Victim spawn point, victim position and killer position for each frag,
    /// in event order, so spawn-death evidence can say where it happened.
    #[serde(default)]
    frag_places: Vec<FragPlace>,
    /// The rule set the server advertised in map_info.
    #[serde(default)]
    pub rules: Option<fragr_server::protocol::MatchRules>,
    /// The last side each fighter was seen on; None while it had none.
    #[serde(default)]
    pub sides: BTreeMap<String, Option<fragr_server::protocol::Team>>,
}

impl Observation {
    fn finish_carry(&mut self, flag: Team, end: CarryEnd) {
        let Some(mut active) = self.active_carries[flag.index()].take() else {
            return;
        };
        active.episode.ended_tick = self.last_tick;
        active.episode.end = end;
        if end == CarryEnd::Dropped {
            active.episode.combat_drop = self
                .events
                .iter()
                .rev()
                .take_while(|timed| timed.tick == self.last_tick)
                .any(|timed| {
                    matches!(&timed.event, GameEvent::Frag { victim, .. }
                    if active.episode.carrier.as_ref() == Some(victim))
                });
        }
        if self.carry_episodes.len() < MAX_CARRY_EPISODES {
            self.carry_episodes.push(active.episode);
        } else {
            self.carry_episodes_omitted += 1;
        }
    }

    fn finish_carry_from_event(
        &mut self,
        flag: Team,
        player: Option<&str>,
        player_id: Option<Uuid>,
        end: CarryEnd,
    ) {
        let matches = self.active_carries[flag.index()]
            .as_ref()
            .is_some_and(|active| {
                if let (Some(active_id), Some(event_id)) = (active.carrier_id, player_id) {
                    active_id == event_id
                } else if let (Some(active_name), Some(event_name)) =
                    (active.episode.carrier.as_deref(), player)
                {
                    active_name == event_name
                } else {
                    false
                }
            });
        if matches {
            self.finish_carry(flag, end);
        } else {
            // An end without its matching take cannot establish this carry's
            // outcome. Preserve the partial episode and count the unmatched
            // event instead of mislabeling another fighter's route.
            self.finish_carry(flag, CarryEnd::Incomplete);
            self.unmatched_flag_ends += 1;
        }
    }

    fn start_carry(&mut self, flag: Team, player: Option<String>, player_id: Option<Uuid>) {
        // A missing end event must not merge two distinct carriers into one.
        self.finish_carry(flag, CarryEnd::Incomplete);
        self.active_carries[flag.index()] = Some(ActiveCarry {
            episode: CarryEpisode {
                flag,
                carrier: player.clone(),
                started_tick: self.last_tick,
                ended_tick: self.last_tick,
                end: CarryEnd::ObservationEnded,
                first_distance_to_home: None,
                closest_distance_to_home: None,
                last_distance_to_home: None,
                observed_carrier_ticks: 0,
                own_flag_away_ticks: 0,
                home_blocked_ticks: 0,
                combat_drop: false,
            },
            carrier_id: player_id,
            last_sample_tick: None,
        });
        // Session broadcasts Snapshot before its same-tick events. Reuse that
        // compact frame so a one-tick carry is still measured.
        if let (Some(flags), Some(name), Some(id)) =
            (&self.latest_flags, player.as_ref(), player_id)
        {
            if flags[flag.index()].carrier == Some(id) {
                if let Some((x, z)) = self.tracks.get(name).and_then(|track| track.last_pos) {
                    self.active_carries[flag.index()]
                        .as_mut()
                        .expect("created above")
                        .sample(
                            self.last_tick,
                            id,
                            name,
                            [x, flags[flag.index()].position[1], z],
                            &flags[flag.other().index()],
                        );
                }
            }
        }
    }

    pub fn ingest_snapshot(&mut self, snapshot: &Snapshot, bytes: usize) {
        self.pending_kills.clear();
        self.pending_grenade_kills.clear();
        self.pending_grenade_names.clear();
        self.snapshots_seen += 1;
        self.snapshot_bytes += bytes as u64;
        if let Some(flags) = snapshot.flags.as_ref() {
            self.carrier_ticks += flags.iter().filter(|flag| flag.carrier.is_some()).count() as u64;
            for flag in flags {
                let Some(active) = self.active_carries[flag.team.index()].as_mut() else {
                    continue;
                };
                let Some(carrier_id) = flag.carrier else {
                    continue;
                };
                let Some(carrier) = snapshot.players.iter().find(|p| p.id == carrier_id) else {
                    continue;
                };
                let own = &flags[flag.team.other().index()];
                active.sample(
                    snapshot.tick,
                    carrier_id,
                    &carrier.name,
                    [carrier.x, flag.position[1], carrier.z],
                    own,
                );
            }
        }
        self.latest_flags = snapshot.flags.clone();
        if self.first_tick.is_none() {
            self.first_tick = Some(snapshot.tick);
        }
        self.last_tick = self.last_tick.max(snapshot.tick);
        let active = snapshot.round_state.as_deref() == Some("Active");
        // The protocol has no corpse. A fighter waiting to respawn is simply
        // absent from the snapshot, so absence is the only way to see death
        // from out here, and a fighter that is not on the field is not one
        // standing still on it.
        let present: std::collections::BTreeSet<&str> =
            snapshot.players.iter().map(|p| p.name.as_str()).collect();
        for (name, track) in self.tracks.iter_mut() {
            if present.contains(name.as_str()) {
                continue;
            }
            track.stuck_run = 0;
            // The last known position stays: a frag names the victim on the
            // snapshot after it leaves the field, and the kill distance is
            // measured from where the two of them were standing.
            track.off_field = true;
            if active {
                track.dead_run += 1;
                track.dead_max_ticks = track.dead_max_ticks.max(track.dead_run);
            }
        }
        for player in &snapshot.players {
            self.sides.insert(player.name.clone(), player.team);
            let track = self.tracks.entry(player.name.clone()).or_default();
            track.ticks_present += 1;
            let pos = (player.x, player.z);
            track.dead_run = 0;
            if let Some((lx, lz)) = track.last_pos {
                let moved = ((pos.0 - lx).powi(2) + (pos.1 - lz).powi(2)).sqrt();
                if !active || moved >= IDLE_EPSILON || player.just_fired || track.off_field {
                    // Moving, fighting, freshly respawned, or between rounds.
                    track.stuck_run = 0;
                } else {
                    if track.stuck_run == 0 {
                        track.stuck_run_from = snapshot.tick;
                    }
                    track.stuck_run += 1;
                    if track.stuck_run > track.stuck_max_ticks {
                        track.stuck_max_ticks = track.stuck_run;
                        track.stuck_from_tick = track.stuck_run_from;
                        track.stuck_at = pos;
                    }
                }
                if active && moved < IDLE_EPSILON {
                    track.idle_ticks += 1;
                }
            }
            if track.off_field || track.last_pos.is_none() {
                track.spawned_at = Some(pos);
            }
            track.off_field = false;
            track.last_pos = Some(pos);
            track.last_weapon = Some(player.weapon.clone());
            if player.just_fired {
                track.fire_ticks += 1;
                *track
                    .weapon_fire_ticks
                    .entry(player.weapon.clone())
                    .or_default() += 1;
            }
        }
        self.ingest_shots(snapshot);
        self.ingest_explosions(snapshot);
    }

    fn ingest_explosions(&mut self, snapshot: &Snapshot) {
        for explosion in &snapshot.explosions {
            let tally = self.weapons.entry("Grenade".into()).or_default();
            // Explosive tallies count resolved detonations, including misses.
            // Participant records separately count authoritative launches.
            tally.shots += 1;
            let mut landed = false;
            for hit in &explosion.hits {
                if hit.target_id == explosion.owner_id {
                    continue;
                }
                let effective = u64::from(hit.hp_damage) + u64::from(hit.armor_damage);
                if effective == 0 {
                    continue;
                }
                landed = true;
                tally.damage += effective as i64;
                if hit.killed {
                    self.pending_grenade_kills
                        .insert(hit.target_id, explosion.owner_id);
                    let owner = snapshot.players.iter().find(|p| p.id == explosion.owner_id);
                    let victim = snapshot.players.iter().find(|p| p.id == hit.target_id);
                    if let (Some(owner), Some(victim)) = (owner, victim) {
                        let position = [
                            victim.x,
                            victim.y - fragr_server::sim::PLAYER_FLOOR_Y,
                            victim.z,
                        ];
                        let distance = position
                            .iter()
                            .zip(explosion.position)
                            .map(|(a, b)| (f64::from(*a) - f64::from(b)).powi(2))
                            .sum::<f64>()
                            .sqrt();
                        self.pending_kills.insert(
                            victim.name.clone(),
                            KillEvidence {
                                killer: owner.name.clone(),
                                weapon: "Grenade".into(),
                                distance,
                            },
                        );
                    }
                }
            }
            tally.hits += u64::from(landed);
        }
    }

    /// Every shot resolved on this tick, with the distance it travelled. The
    /// server publishes hits and misses, so accuracy is exact rather than
    /// inferred from fire ticks. A scatter blast can publish one result per
    /// struck fighter plus one for its missed pellets; a fighter fires at most
    /// once a tick, so all of a shooter's results in one tick are one shot,
    /// and that shot is a hit if any of its pellets landed.
    fn ingest_shots(&mut self, snapshot: &Snapshot) {
        if snapshot.shot_results.is_empty() {
            return;
        }
        let mut counted: BTreeMap<Uuid, bool> = BTreeMap::new();
        let by_id: BTreeMap<Uuid, (String, f32, f32)> = snapshot
            .players
            .iter()
            .map(|p| (p.id, (p.weapon.clone(), p.x, p.z)))
            .collect();
        for shot in &snapshot.shot_results {
            let shooter = by_id.get(&shot.shooter_id);
            let weapon = shot
                .trace
                .as_ref()
                .map(|trace| trace.weapon.name().to_string())
                .or_else(|| shooter.map(|(weapon, _, _)| weapon.clone()))
                .unwrap_or_else(|| "Unknown".to_string());
            let distance = shot
                .trace
                .as_ref()
                .map(|trace| {
                    trace
                        .origin
                        .iter()
                        .zip(trace.end)
                        .map(|(a, b)| (f64::from(*a) - f64::from(b)).powi(2))
                        .sum::<f64>()
                        .sqrt()
                })
                .or_else(|| {
                    let (_, sx, sz) = shooter?;
                    let (_, tx, tz) = by_id.get(&shot.target_id?)?;
                    Some(f64::from((tx - sx).hypot(tz - sz)))
                });
            if shot.killed {
                if let (Some(victim), Some(distance)) = (&shot.target, distance) {
                    self.pending_kills.insert(
                        victim.clone(),
                        KillEvidence {
                            killer: shot.shooter.clone(),
                            weapon: weapon.clone(),
                            distance,
                        },
                    );
                }
            }
            let tally = self.weapons.entry(weapon).or_default();
            let hit_counted = counted.entry(shot.shooter_id).or_insert_with(|| {
                tally.shots += 1;
                false
            });
            if !shot.hit {
                continue;
            }
            if !*hit_counted {
                tally.hits += 1;
                *hit_counted = true;
            }
            tally.damage += shot.damage as i64;
            if let Some(distance) = distance {
                tally.hit_distances.push(distance);
            }
        }
    }

    pub fn ingest_event(&mut self, event: GameEvent) {
        match &event {
            // The clock on a death starts at the first damage that led to it.
            GameEvent::Hit {
                shooter,
                shooter_id,
                target,
                target_id,
                ..
            } => {
                if self.pending_grenade_kills.get(target_id) == Some(shooter_id) {
                    self.pending_grenade_names
                        .insert(target.clone(), shooter.clone());
                }
                self.engagement_start
                    .entry(target.clone())
                    .or_insert(self.last_tick);
            }
            GameEvent::Frag { killer, victim, .. } => {
                for episode in self.carry_episodes.iter_mut().rev() {
                    if episode.ended_tick != self.last_tick {
                        break;
                    }
                    if episode.end == CarryEnd::Dropped && episode.carrier.as_ref() == Some(victim)
                    {
                        episode.combat_drop = true;
                    }
                }
                let ttk_s = self.engagement_start.remove(victim).map(|start| {
                    let ticks = self.last_tick.saturating_sub(start);
                    ticks as f64 / TICKS_PER_SECOND
                });
                if let Some(seconds) = ttk_s {
                    self.time_to_kill_s.push(seconds);
                }
                let killer_track = self.tracks.get(killer);
                let killer_pos = killer_track.and_then(|t| t.last_pos);
                let evidence = self
                    .pending_kills
                    .remove(victim)
                    .filter(|e| e.killer == *killer);
                let killer_weapon = evidence
                    .as_ref()
                    .map(|e| e.weapon.clone())
                    .or_else(|| {
                        (self.pending_grenade_names.remove(victim).as_ref() == Some(killer))
                            .then(|| "Grenade".into())
                    })
                    .or_else(|| killer_track.and_then(|t| t.last_weapon.clone()));
                let victim_pos = self.tracks.get(victim).and_then(|t| t.last_pos);
                self.frag_places.push(FragPlace {
                    victim_spawn: self.tracks.get(victim).and_then(|t| t.spawned_at),
                    victim: victim_pos,
                    killer: killer_pos,
                });
                let distance = evidence.map(|e| e.distance).or_else(|| {
                    let (kx, kz) = killer_pos?;
                    let (vx, vz) = victim_pos?;
                    Some(f64::from((vx - kx).hypot(vz - kz)))
                });
                if let Some(distance) = distance {
                    self.kill_distances.push(distance);
                    if let Some(weapon) = killer_weapon {
                        let tally = self.weapons.entry(weapon).or_default();
                        tally.kills += 1;
                        tally.kill_distances.push(distance);
                        if let Some(seconds) = ttk_s {
                            tally.time_to_kill_s.push(seconds);
                        }
                    }
                } else if let (Some(weapon), Some(seconds)) = (killer_weapon, ttk_s) {
                    // Timed kill without positions still counts toward per-weapon TTK.
                    let tally = self.weapons.entry(weapon).or_default();
                    tally.kills += 1;
                    tally.time_to_kill_s.push(seconds);
                }
            }
            // A fighter who respawned is not still in their last engagement.
            GameEvent::Respawn { player } => {
                self.engagement_start.remove(player);
            }
            GameEvent::Flag {
                kind,
                flag,
                player,
                player_id,
                ..
            } => match kind {
                FlagEventKind::Taken => self.start_carry(*flag, player.clone(), *player_id),
                FlagEventKind::Dropped => self.finish_carry_from_event(
                    *flag,
                    player.as_deref(),
                    *player_id,
                    CarryEnd::Dropped,
                ),
                FlagEventKind::Captured => self.finish_carry_from_event(
                    *flag,
                    player.as_deref(),
                    *player_id,
                    CarryEnd::Captured,
                ),
                FlagEventKind::Returned => {}
            },
            GameEvent::RoundEnd { .. } => {
                for flag in Team::ALL {
                    self.finish_carry(flag, CarryEnd::RoundEnded);
                }
            }
            _ => {}
        }
        self.events.push(TimedEvent {
            tick: self.last_tick,
            event,
        });
    }

    /// Fold the running tallies into the combat picture.
    pub fn combat_report(&self) -> CombatReport {
        let mut shots = 0u64;
        let mut hits = 0u64;
        let mut kills = 0u64;
        let mut by_weapon = BTreeMap::new();
        for (weapon, tally) in &self.weapons {
            shots += tally.shots;
            hits += tally.hits;
            kills += tally.kills;
            let accuracy = if tally.shots == 0 {
                0.0
            } else {
                tally.hits as f64 / tally.shots as f64
            };
            let (lo, hi) = wilson_interval(tally.hits, tally.shots);
            by_weapon.insert(
                weapon.clone(),
                WeaponReport {
                    shots: tally.shots,
                    hits: tally.hits,
                    accuracy,
                    accuracy_lo: lo,
                    accuracy_hi: hi,
                    damage: tally.damage,
                    kills: tally.kills,
                    time_to_kill_s: Quantiles::from_values(&tally.time_to_kill_s),
                    hit_distance: Quantiles::from_values(&tally.hit_distances),
                    kill_distance: Quantiles::from_values(&tally.kill_distances),
                },
            );
        }
        let mut buckets = vec![0u64; DISTANCE_BUCKETS];
        for distance in &self.kill_distances {
            let index = ((distance / DISTANCE_BUCKET as f64) as usize).min(DISTANCE_BUCKETS - 1);
            buckets[index] += 1;
        }
        let (lo, hi) = wilson_interval(hits, shots);
        CombatReport {
            time_to_kill_s: Quantiles::from_values(&self.time_to_kill_s),
            shots,
            hits,
            accuracy: if shots == 0 {
                0.0
            } else {
                hits as f64 / shots as f64
            },
            accuracy_lo: lo,
            accuracy_hi: hi,
            shots_per_kill: if kills == 0 {
                0.0
            } else {
                shots as f64 / kills as f64
            },
            kill_distance_buckets: buckets,
            by_weapon,
        }
    }

    pub fn rounds_completed(&self) -> u32 {
        self.events
            .iter()
            .filter(|e| matches!(e.event, GameEvent::RoundEnd { .. }))
            .count() as u32
    }
}

#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq)]
pub struct AgentReport {
    pub frags: u64,
    pub deaths: u64,
    pub spawn_deaths: u64,
    pub frags_per_minute: f64,
    pub deaths_per_minute: f64,
    pub idle_ratio: f64,
    pub stuck_max_s: f64,
    /// Longest unbroken stretch spent off the field, which is how the
    /// protocol shows death. The respawn delay is three seconds, so anything
    /// far above that is a fighter that did not come back.
    pub dead_max_s: f64,
    /// The tick the longest stall began on and the spot it happened at, so a
    /// failure in CI names a place to look rather than only a duration.
    pub stuck_from_tick: u64,
    pub stuck_at_x: f32,
    pub stuck_at_z: f32,
    pub fire_ticks: u64,
    pub weapon_fire_ticks: BTreeMap<String, u64>,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq)]
pub struct Report {
    pub agents: usize,
    pub rounds_completed: u32,
    pub ticks: u64,
    pub seconds: f64,
    pub frags: u64,
    #[serde(default)]
    pub flag_takes: u64,
    #[serde(default)]
    pub flag_drops: u64,
    #[serde(default)]
    pub flag_returns: u64,
    #[serde(default)]
    pub captures: u64,
    #[serde(default)]
    pub carrier_seconds: f64,
    /// At most 256 carry summaries in total, including any still in progress
    /// when the observer stopped. No per-tick position log is retained.
    #[serde(default)]
    pub carry_episodes: Vec<CarryEpisode>,
    #[serde(default)]
    pub carry_episodes_omitted: u64,
    /// End events without a matching flag and carrier take.
    #[serde(default)]
    pub unmatched_flag_ends: u64,
    /// The most recent completed round, if the observer received its end event.
    #[serde(default)]
    pub last_round_reason: Option<String>,
    #[serde(default)]
    pub last_round_capture_scores: Option<fragr_server::protocol::TeamScores>,
    pub frags_per_minute: f64,
    pub time_to_first_frag_s: Option<f64>,
    pub longest_gap_without_frag_s: f64,
    pub host_beats_per_minute: f64,
    pub pickups: u64,
    pub spawn_deaths: u64,
    /// Spawn deaths whose spawn was the round opening rather than a respawn.
    /// Opening placement is decided from the whole roster before anyone moves,
    /// so these point at map geometry or the selector, not at the fight.
    #[serde(default)]
    pub opening_spawn_deaths: u64,
    pub snapshot_bytes_per_tick: f64,
    /// How the fighting actually went: time to kill, accuracy with intervals,
    /// and where each weapon does its work.
    pub combat: CombatReport,
    pub per_agent: BTreeMap<String, AgentReport>,
    /// The rule set the server advertised, as every reader sees it.
    #[serde(default)]
    pub rules: Option<fragr_server::protocol::MatchRules>,
    /// Fighters seen on each side; `none` counts fighters without one.
    #[serde(default)]
    pub sides: BTreeMap<String, u64>,
    /// Host reactions called during the run.
    #[serde(default)]
    pub host_reactions: u64,
    /// Frags where killer and victim shared a side.
    #[serde(default)]
    pub team_kills: u64,
    /// Sabotage facts by event kind, such as `planted` or `defused`.
    #[serde(default, skip_serializing_if = "BTreeMap::is_empty")]
    pub sabotage_events: BTreeMap<String, u64>,
    /// Every decided Sabotage round: its winner and result.
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub sabotage_rounds: Vec<(Option<Team>, fragr_server::protocol::SabotageResult)>,
}

fn seconds(ticks: u64) -> f64 {
    ticks as f64 / TICKS_PER_SECOND
}

fn per_minute(count: u64, ticks: u64) -> f64 {
    if ticks == 0 {
        return 0.0;
    }
    count as f64 / (seconds(ticks) / 60.0)
}

/// Fold an observation deterministically; logs preserve early-death tick evidence.
pub fn compute_report(obs: &Observation, agents: usize) -> Report {
    let first = obs.first_tick.unwrap_or(0);
    let ticks = obs.last_tick.saturating_sub(first).max(1);
    let mut per_agent: BTreeMap<String, AgentReport> = BTreeMap::new();
    for (name, track) in &obs.tracks {
        per_agent.insert(
            name.clone(),
            AgentReport {
                idle_ratio: if track.ticks_present == 0 {
                    0.0
                } else {
                    track.idle_ticks as f64 / track.ticks_present as f64
                },
                stuck_max_s: seconds(track.stuck_max_ticks),
                dead_max_s: seconds(track.dead_max_ticks),
                stuck_from_tick: track.stuck_from_tick,
                stuck_at_x: track.stuck_at.0,
                stuck_at_z: track.stuck_at.1,
                fire_ticks: track.fire_ticks,
                weapon_fire_ticks: track.weapon_fire_ticks.clone(),
                ..AgentReport::default()
            },
        );
    }

    // Spawn tick, and whether that spawn was the round opening.
    let mut last_spawn: BTreeMap<String, (u64, bool)> = BTreeMap::new();
    let mut frag_ticks: Vec<u64> = Vec::new();
    let mut host_beats = 0u64;
    let mut pickups = 0u64;
    let mut host_reactions = 0u64;
    let mut team_kills = 0u64;
    let mut flag_takes = 0u64;
    let mut flag_drops = 0u64;
    let mut flag_returns = 0u64;
    let mut captures = 0u64;
    let mut last_round_reason = None;
    let mut last_round_capture_scores = None;
    let mut sabotage_events: BTreeMap<String, u64> = BTreeMap::new();
    let mut sabotage_rounds = Vec::new();
    let mut spawn_deaths = 0u64;
    let mut opening_spawn_deaths = 0u64;
    for timed in &obs.events {
        match &timed.event {
            GameEvent::RoundStart { players, .. } => {
                host_beats += 1;
                for player in players {
                    last_spawn.insert(player.clone(), (timed.tick, true));
                }
            }
            GameEvent::Respawn { player } => {
                last_spawn.insert(player.clone(), (timed.tick, false));
            }
            GameEvent::Frag {
                killer,
                victim,
                killer_team,
                victim_team,
                ..
            } => {
                team_kills += u64::from(killer_team.is_some() && killer_team == victim_team);
                let place = obs
                    .frag_places
                    .get(frag_ticks.len())
                    .copied()
                    .unwrap_or_default();
                frag_ticks.push(timed.tick);
                per_agent.entry(killer.clone()).or_default().frags += 1;
                let victim_report = per_agent.entry(victim.clone()).or_default();
                victim_report.deaths += 1;
                if let Some(&(spawned, opening)) = last_spawn.get(victim) {
                    if timed.tick.saturating_sub(spawned) <= SPAWN_DEATH_WINDOW_TICKS {
                        tracing::warn!(
                            spawn_tick = spawned,
                            death_tick = timed.tick,
                            killer,
                            victim,
                            victim_spawn = ?place.victim_spawn,
                            victim_at = ?place.victim,
                            killer_at = ?place.killer,
                            opening,
                            "spawn death evidence"
                        );
                        victim_report.spawn_deaths += 1;
                        spawn_deaths += 1;
                        opening_spawn_deaths += u64::from(opening);
                    }
                }
            }
            GameEvent::HostReaction { .. } => {
                host_beats += 1;
                host_reactions += 1;
            }
            GameEvent::RoundEnd {
                reason,
                capture_scores,
                winning_team,
                sabotage,
                ..
            } => {
                host_beats += 1;
                last_round_reason = Some(reason.clone());
                last_round_capture_scores = *capture_scores;
                if let Some(result) = sabotage {
                    sabotage_rounds.push((*winning_team, result.clone()));
                }
            }
            GameEvent::Sabotage { kind, .. } => {
                let key = serde_json::to_value(kind)
                    .ok()
                    .and_then(|v| v.as_str().map(str::to_string))
                    .unwrap_or_default();
                *sabotage_events.entry(key).or_default() += 1;
            }
            GameEvent::Killstreak { .. }
            | GameEvent::CompliancePing { .. }
            | GameEvent::BossSpawn { .. }
            | GameEvent::BossDown { .. } => host_beats += 1,
            GameEvent::Pickup { .. } => pickups += 1,
            GameEvent::Flag { kind, .. } => match kind {
                fragr_server::protocol::FlagEventKind::Taken => flag_takes += 1,
                fragr_server::protocol::FlagEventKind::Dropped => flag_drops += 1,
                fragr_server::protocol::FlagEventKind::Returned => flag_returns += 1,
                fragr_server::protocol::FlagEventKind::Captured => captures += 1,
            },
            GameEvent::Hit { .. }
            | GameEvent::CrawlerScrabble { .. }
            | GameEvent::PlayerJoined { .. }
            | GameEvent::PlayerLeft { .. }
            | GameEvent::Speak { .. } => {}
            GameEvent::EpisodeStart { .. }
            | GameEvent::EpisodeComplete { .. }
            | GameEvent::EpisodeFail { .. } => {}
        }
    }
    for report in per_agent.values_mut() {
        report.frags_per_minute = per_minute(report.frags, ticks);
        report.deaths_per_minute = per_minute(report.deaths, ticks);
    }

    let frags = frag_ticks.len() as u64;
    let time_to_first_frag_s = frag_ticks.first().map(|t| seconds(t.saturating_sub(first)));
    let mut longest_gap = 0u64;
    let mut previous = first;
    for t in &frag_ticks {
        longest_gap = longest_gap.max(t.saturating_sub(previous));
        previous = *t;
    }
    longest_gap = longest_gap.max(obs.last_tick.saturating_sub(previous));

    let mut carry_episodes = obs.carry_episodes.clone();
    let mut carry_episodes_omitted = obs.carry_episodes_omitted;
    for active in obs.active_carries.iter().flatten() {
        if carry_episodes.len() == MAX_CARRY_EPISODES {
            carry_episodes_omitted += 1;
        } else {
            let mut episode = active.episode.clone();
            episode.ended_tick = obs.last_tick;
            episode.end = CarryEnd::ObservationEnded;
            carry_episodes.push(episode);
        }
    }

    Report {
        agents,
        rounds_completed: obs.rounds_completed(),
        ticks,
        seconds: seconds(ticks),
        frags,
        flag_takes,
        flag_drops,
        flag_returns,
        captures,
        carrier_seconds: seconds(obs.carrier_ticks),
        carry_episodes,
        carry_episodes_omitted,
        unmatched_flag_ends: obs.unmatched_flag_ends,
        last_round_reason,
        last_round_capture_scores,
        frags_per_minute: per_minute(frags, ticks),
        time_to_first_frag_s,
        longest_gap_without_frag_s: seconds(longest_gap),
        host_beats_per_minute: per_minute(host_beats, ticks),
        pickups,
        spawn_deaths,
        opening_spawn_deaths,
        snapshot_bytes_per_tick: if obs.snapshots_seen == 0 {
            0.0
        } else {
            obs.snapshot_bytes as f64 / obs.snapshots_seen as f64
        },
        combat: obs.combat_report(),
        per_agent,
        sabotage_events,
        sabotage_rounds,
        rules: obs.rules.clone(),
        sides: obs.sides.values().fold(BTreeMap::new(), |mut sides, side| {
            let key = side.map_or("none", |team| team.id()).to_string();
            *sides.entry(key).or_insert(0) += 1;
            sides
        }),
        host_reactions,
        team_kills,
    }
}

/// Frustration signals and sticky weapon-table TTK that block a merge.
/// Empty means the run is acceptable and the #124 table still holds.
pub fn check_thresholds(report: &Report) -> Vec<String> {
    let mut problems = check_shared_thresholds(report);
    if report
        .rules
        .as_ref()
        .is_some_and(|rules| rules.mode == fragr_server::protocol::GameMode::Ctf)
    {
        if report.flag_takes == 0 {
            problems.push("no flag pickups".to_string());
        }
        if report.captures == 0 {
            problems.push("no flag captures".to_string());
        }
    } else if report.agents >= 4 && report.frags_per_minute < 1.0 {
        problems.push(format!(
            "only {:.2} frags per minute with {} agents",
            report.frags_per_minute, report.agents
        ));
    }
    problems
}

fn check_shared_thresholds(report: &Report) -> Vec<String> {
    let mut problems = check_sticky_ttk_table();
    let lives = report.rules.as_ref().and_then(|rules| rules.lives);
    if report.rounds_completed == 0 {
        problems.push("no round completed".to_string());
    }
    for (name, agent) in &report.per_agent {
        if agent.stuck_max_s > 5.0 {
            problems.push(format!(
                "{name} stuck for {:.1} s from tick {} at ({:.1}, {:.1})",
                agent.stuck_max_s, agent.stuck_from_tick, agent.stuck_at_x, agent.stuck_at_z
            ));
        }
        // Three seconds is the respawn delay. Twice that is a fighter the
        // server forgot, which no amount of agent cleverness can fix. Under
        // limited lives an eliminated fighter is meant to stay off the field.
        if agent.dead_max_s > 6.0 && lives.is_none() {
            problems.push(format!(
                "{name} dead for {:.1} s without respawning",
                agent.dead_max_s
            ));
        }
    }
    // Spawn deaths are a rate, and a rate from ten frags is mostly noise: at
    // ten, two spawn deaths reads as twenty percent when the truth could be
    // five. Judge the lower bound of the interval instead, the same Wilson
    // bound the accuracy figures already carry, so a run fails when the
    // evidence supports a real problem rather than when a small sample landed
    // badly. A genuinely bad rate still fails; it just has to prove itself.
    if report.frags > 0 {
        let (low, _) = wilson_interval(report.spawn_deaths, report.frags);
        if low > SPAWN_DEATH_RATE_CEILING {
            problems.push(format!(
                "spawn deaths {} of {} frags ({:.0}% at worst, ceiling {:.0}%)",
                report.spawn_deaths,
                report.frags,
                low * 100.0,
                SPAWN_DEATH_RATE_CEILING * 100.0
            ));
        }
    }
    let opening_limit = OPENING_SPAWN_DEATHS_PER_ROUND * u64::from(report.rounds_completed.max(1));
    if report.opening_spawn_deaths > opening_limit {
        problems.push(format!(
            "opening spawn deaths {} (limit {opening_limit})",
            report.opening_spawn_deaths
        ));
    }
    problems.extend(check_rules(report));
    problems
}

/// A contested sample must prove combat and valid CTF replication. Capture is
/// covered by the separate controlled route gate, not by match luck.
pub fn check_contested_ctf(report: &Report, observation: &Observation) -> Vec<String> {
    let mut problems = check_shared_thresholds(report);
    if report.rules.as_ref().map(|rules| rules.mode) != Some(fragr_server::protocol::GameMode::Ctf)
    {
        problems.push("not a CTF round".to_string());
    }
    if report.frags == 0 {
        problems.push("no contested combat".to_string());
    }
    if observation.latest_flags.is_none() {
        problems.push("no authoritative flag snapshot".to_string());
    }
    if report.last_round_capture_scores.is_none() {
        problems.push("no final capture score".to_string());
    }
    problems
}

/// The controlled route must make the one joined fighter take and score over
/// the normal socket, with corroborating server events, carried state and end.
pub fn check_ctf_route_smoke(report: &Report, observation: &Observation) -> Vec<String> {
    let mut problems = Vec::new();
    if report.rules.as_ref().map(|rules| rules.mode) != Some(fragr_server::protocol::GameMode::Ctf)
    {
        problems.push("not a CTF round".to_string());
    }
    if report.agents != 1 || report.rounds_completed != 1 {
        problems.push("route probe did not finish one single-fighter round".to_string());
    }
    if report.flag_takes == 0 || report.captures != 1 {
        problems.push("route probe did not take and capture one flag".to_string());
    }
    let capture = observation
        .events
        .iter()
        .enumerate()
        .find_map(|(index, timed)| {
            if let GameEvent::Flag {
                kind: FlagEventKind::Captured,
                flag,
                player: Some(player),
                player_id: Some(id),
                capture_scores,
            } = &timed.event
            {
                (player == "route-probe-1").then_some((index, *flag, *id, *capture_scores))
            } else {
                None
            }
        });
    if let Some((index, flag, id, event_scores)) = capture {
        let same_take = observation.events[..index].iter().any(|timed| {
            matches!(&timed.event, GameEvent::Flag {
                kind: FlagEventKind::Taken,
                flag: taken_flag,
                player_id: Some(taker),
                ..
            } if *taken_flag == flag && *taker == id)
        });
        if !same_take {
            problems.push("capture had no preceding take by the same fighter".to_string());
        }
        if !report.carry_episodes.iter().any(|episode| {
            episode.flag == flag
                && episode.carrier.as_deref() == Some("route-probe-1")
                && episode.end == CarryEnd::Captured
                && episode.observed_carrier_ticks > 0
        }) {
            problems.push("no carried snapshot and capture for the joined route probe".to_string());
        }
        let scored_side = flag.other();
        if event_scores.get(scored_side) != 1 || event_scores.get(flag) != 0 {
            problems.push("capture event did not credit the carrier's side".to_string());
        }
        if !report
            .last_round_capture_scores
            .is_some_and(|scores| scores.get(scored_side) == 1 && scores.get(flag) == 0)
        {
            problems.push("capture score did not credit the carrier's side".to_string());
        }
        let matching_end = observation.events[index + 1..].iter().any(|timed| {
            matches!(&timed.event, GameEvent::RoundEnd {
                winning_team: Some(winner),
                capture_scores: Some(scores),
                reason,
                ..
            } if *winner == scored_side
                && Some(*scores) == report.last_round_capture_scores
                && reason == "Capture limit reached")
        });
        if !matching_end {
            problems.push("no matching server round end after capture".to_string());
        }
    } else {
        problems.push("no server capture event naming the route probe".to_string());
    }
    if report.last_round_reason.as_deref() != Some("Capture limit reached") {
        problems.push("round did not end at the capture limit".to_string());
    }
    if report.carry_episodes_omitted > 0 || report.unmatched_flag_ends > 0 {
        problems.push("route evidence was omitted or unmatched".to_string());
    }
    problems
}

/// The unopposed Sabotage probe: one attacker carries the charge to A and
/// plants it, one defender walks onto it and defuses, over the real socket.
pub fn check_sabotage_route_smoke(report: &Report) -> Vec<String> {
    let mut problems = Vec::new();
    if report.rules.as_ref().map(|rules| rules.mode)
        != Some(fragr_server::protocol::GameMode::Sabotage)
    {
        problems.push("not a Sabotage round".to_string());
    }
    if report.agents != 2 {
        problems.push("the probe needs one attacker and one defender".to_string());
    }
    let count = |kind: &str| report.sabotage_events.get(kind).copied().unwrap_or(0);
    for kind in [
        "live",
        "plant_started",
        "planted",
        "defuse_started",
        "defused",
    ] {
        if count(kind) == 0 {
            problems.push(format!("no {kind} event"));
        }
    }
    match report.sabotage_rounds.first() {
        Some((winner, result)) => {
            if *winner != Some(Team::Union)
                || result.reason != fragr_server::protocol::SabotageReason::Defused
            {
                problems.push(format!(
                    "the first round ended {:?} for {winner:?}, not a Union defuse",
                    result.reason
                ));
            }
            if result.score.union != 1 || result.score.coalition != 0 {
                problems.push("the defuse did not score one round to the Union".to_string());
            }
        }
        None => problems.push("no decided Sabotage round".to_string()),
    }
    problems
}

/// A contested Sabotage socket round: every decided round carries a result,
/// fighters fought, the charge moved and the rule set held.
pub fn check_contested_sabotage(report: &Report) -> Vec<String> {
    let mut problems = check_rules(report);
    if report.sabotage_rounds.is_empty() {
        problems.push("no decided Sabotage round".to_string());
    }
    if report.rounds_completed as usize != report.sabotage_rounds.len() {
        problems.push("a round ended without a Sabotage result".to_string());
    }
    if report.frags == 0 {
        problems.push("no frags in a contested round".to_string());
    }
    if report.sabotage_events.get("live").copied().unwrap_or(0) == 0 {
        problems.push("muster never ended".to_string());
    }
    if report.pickups == 0 {
        problems.push("nobody picked up a weapon, though every life starts empty".to_string());
    }
    problems
}

/// The advertised rule set held: a team round put every fighter on one of
/// two sides with no team kills unless friendly fire is on, and a weapon-only
/// round fired nothing else.
pub fn check_rules(report: &Report) -> Vec<String> {
    let mut problems = Vec::new();
    let Some(rules) = report.rules.as_ref() else {
        return problems;
    };
    if rules.mode.teams() {
        if report.sides.get("none").copied().unwrap_or(0) > 0 {
            problems.push(format!("{} fighters without a side", report.sides["none"]));
        }
        for team in fragr_server::protocol::Team::ALL {
            if report.sides.get(team.id()).copied().unwrap_or(0) == 0 {
                problems.push(format!("no fighter on the {} side", team.id()));
            }
        }
        if !rules.friendly_fire && report.team_kills > 0 {
            problems.push(format!(
                "{} team kills with friendly fire off",
                report.team_kills
            ));
        }
    }
    if let Some(only) = rules.mutators.iter().find_map(|m| m.only_weapon()) {
        for weapon in report.combat.by_weapon.keys() {
            if weapon != only.name() {
                problems.push(format!("{weapon} fired under {}", rules.name));
            }
        }
    }
    problems
}

/// Reflex tier: face the nearest fighter, close in, fire in range. Same policy as
/// the adapter's scripted bot, driven straight from the server's wire types.
/// Nobody in sight. A fighter that has the map to itself goes looking rather
/// than standing where it last saw someone, which is both what a player does
/// and what keeps an empty stretch of a round from reading as a stuck agent.
/// The sweep is offset per fighter so two of them do not walk the same circle
/// in step and meet nobody.
pub fn patrol_action(me: &fragr_server::protocol::PlayerState, tick: u64, arena: &Arena) -> Action {
    let radius = arena.half_extent * 0.6;
    let offset = (me.id.as_u128() % 628) as f32 / 100.0;
    let angle = offset + tick as f32 * PATROL_TURN_PER_TICK;
    Action {
        look_at: Some(LookAt {
            y: None,
            player_id: None,
            x: Some(angle.cos() * radius),
            z: Some(angle.sin() * radius),
        }),
        forward: true,
        ..Action::default()
    }
}

pub fn reflex_action(bot_id: Uuid, snapshot: &Snapshot, arena: &Arena) -> Action {
    let Some(me) = snapshot.players.iter().find(|p| p.id == bot_id) else {
        return Action::default();
    };
    let mut nearest: Option<(f32, &fragr_server::protocol::PlayerState)> = None;
    for other in &snapshot.players {
        if !me.is_hostile_to(other) {
            continue;
        }
        let dist = ((other.x - me.x).powi(2) + (other.z - me.z).powi(2)).sqrt();
        if nearest.is_none_or(|(d, _)| dist < d) {
            nearest = Some((dist, other));
        }
    }
    let Some((dist, target)) = nearest else {
        return patrol_action(me, snapshot.tick, arena);
    };
    // Swap only when the right weapon is not already in hand, so the report
    // does not fill with pointless swaps.
    let wanted = weapon_for_distance(dist);
    let weapon_swap = (weapon_from_wire(&me.weapon) != Some(wanted)).then_some(wanted);
    // Do not shoot the wall in front of the enemy. Behind cover, keep closing
    // rather than standing there: an agent that cannot see its target should
    // move to clear the corner, which is also what stops it looking stuck.
    let clear = arena.fighter_visible(me, target);
    // A fist or a blade has to be inside its reach, which is also how a
    // Fists Only round gets played: the swap is refused, so walk in.
    let held = weapon_from_wire(&me.weapon);
    if let Some(melee) = held.filter(|w| w.ammo_pool().is_none()) {
        let reach = melee.range_units() - 0.3;
        return Action {
            look_at: Some(LookAt {
                y: None,
                player_id: Some(target.id),
                x: None,
                z: None,
            }),
            forward: dist > reach * 0.6 || !clear,
            left: !clear && snapshot.tick % 40 < 20,
            right: !clear && snapshot.tick % 40 >= 20,
            fire: clear && dist < reach,
            weapon_swap,
            ..Action::default()
        };
    }
    Action {
        look_at: Some(LookAt {
            y: None,
            player_id: Some(target.id),
            x: None,
            z: None,
        }),
        forward: dist > CLOSE_RANGE || !clear,
        // Walking straight into a pillar is how an agent gets pinned. While it
        // cannot see its target it also slides, alternating every second, so a
        // corner is something it goes around rather than into.
        left: !clear && snapshot.tick % 40 < 20,
        right: !clear && snapshot.tick % 40 >= 20,
        fire: clear && dist < FIRE_RANGE,
        weapon_swap,
        ..Action::default()
    }
}

/// How an agent decides what to do. Both play through the same wire; the
/// difference is only what they ask for.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Policy {
    /// Chase the nearest fighter and hold the fire button. The baseline, and
    /// the reason the first combat reports found every kill at knife range.
    Reflex,
    /// Keep the distance its weapon wants, break off for health when hurt,
    /// and collect a weapon it does not have.
    Planner,
    /// Controlled, unopposed objective probe for CTF and Sabotage. Never
    /// fights. Not offered as a normal tier.
    RouteProbe,
}

impl Policy {
    pub fn parse(text: &str) -> Option<Policy> {
        match text.trim().to_ascii_lowercase().as_str() {
            "reflex" => Some(Policy::Reflex),
            "planner" => Some(Policy::Planner),
            _ => None,
        }
    }

    pub fn name(self) -> &'static str {
        match self {
            Policy::Reflex => "reflex",
            Policy::Planner => "planner",
            Policy::RouteProbe => "route-probe",
        }
    }

    /// Parse a comma separated list, which the harness deals round robin to
    /// the agents. An empty or unparseable list is an error rather than a
    /// silent fall back to one policy.
    pub fn parse_list(text: &str) -> Result<Vec<Policy>, String> {
        let mut out = Vec::new();
        for part in text.split(',') {
            let part = part.trim();
            if part.is_empty() {
                continue;
            }
            out.push(Policy::parse(part).ok_or_else(|| format!("unknown tier {part:?}"))?);
        }
        if out.is_empty() {
            return Err("no tiers given".to_string());
        }
        Ok(out)
    }
}

/// Below this health the planner breaks off for a health pad.
pub const PLANNER_LOW_HEALTH: i32 = 45;
/// It will detour for a pickup no further away than this.
pub const PLANNER_PICKUP_REACH: f32 = 18.0;

/// The distance band a weapon wants to fight at: (comfortable, ideal).
fn preferred_band(weapon: WeaponType) -> (f32, f32) {
    match weapon {
        WeaponType::Fists => (0.0, 1.5),
        WeaponType::Shiv => (0.0, 1.9),
        WeaponType::Tack => (5.0, 12.0),
        WeaponType::Scatter => (1.5, 4.0),
        WeaponType::Flechette => (7.0, 12.0),
        WeaponType::Rail => (18.0, 28.0),
    }
}

/// The planner: hold the range your weapon wants, heal when hurt, and pick up
/// a weapon you do not have when one is close. Everything it knows comes from
/// the same snapshot a reflex agent sees.
pub fn planner_action(bot_id: Uuid, snapshot: &Snapshot, arena: &Arena) -> Action {
    let Some(me) = snapshot.players.iter().find(|p| p.id == bot_id) else {
        return Action::default();
    };
    let held = weapon_from_wire(&me.weapon).unwrap_or_default();
    let distance_to = |x: f32, z: f32| ((x - me.x).powi(2) + (z - me.z).powi(2)).sqrt();

    let mut nearest: Option<(f32, &fragr_server::protocol::PlayerState)> = None;
    for other in &snapshot.players {
        if !me.is_hostile_to(other) {
            continue;
        }
        let dist = distance_to(other.x, other.z);
        if nearest.is_none_or(|(d, _)| dist < d) {
            nearest = Some((dist, other));
        }
    }

    // Hurt and a pad within reach: go and heal, and do not stop to shoot.
    if me.hp < PLANNER_LOW_HEALTH {
        if let Some(pad) = nearest_pickup(snapshot, me, |p| p.kind == "health") {
            return walk_to(pad, me, nearest.map(|(_, e)| e));
        }
    }

    let Some((dist, enemy)) = nearest else {
        // Nobody about: collect something useful.
        if let Some(pad) = nearest_pickup(snapshot, me, |p| p.kind != "health") {
            return walk_to(pad, me, None);
        }
        return patrol_action(me, snapshot.tick, arena);
    };

    // A weapon this fighter is not carrying, close by, and no enemy breathing
    // down its neck: worth the detour.
    if dist > preferred_band(held).1 * 1.5 {
        if let Some(pad) = nearest_pickup(snapshot, me, |p| {
            p.kind == "weapon" && weapon_from_wire(&p.weapon) != Some(held)
        }) {
            return walk_to(pad, me, Some(enemy));
        }
    }

    let wanted = weapon_for_distance(dist);
    let weapon_swap = (held != wanted).then_some(wanted);
    // Three zones: too far, in the band, too close. In the band it strafes
    // rather than standing still, which is the whole difference from a reflex
    // agent that only ever charges.
    let (comfortable, ideal) = preferred_band(wanted);
    let clear = arena.fighter_visible(me, enemy);
    // With cover in the way the band does not matter: step out and look.
    let holding = clear && dist >= comfortable && dist <= ideal;
    Action {
        look_at: Some(LookAt {
            y: None,
            player_id: Some(enemy.id),
            x: None,
            z: None,
        }),
        forward: dist > ideal || !clear,
        back: clear && dist < comfortable,
        // Always strafing while it cannot see is what clears a corner.
        left: (holding || !clear) && snapshot.tick % 40 < 20,
        right: (holding || !clear) && snapshot.tick % 40 >= 20,
        fire: clear && dist < wanted.range_units(),
        weapon_swap,
        ..Action::default()
    }
}

/// The closest available pickup this fighter cares about, within reach.
fn nearest_pickup<'a>(
    snapshot: &'a Snapshot,
    me: &fragr_server::protocol::PlayerState,
    wanted: impl Fn(&fragr_server::protocol::PickupState) -> bool,
) -> Option<&'a fragr_server::protocol::PickupState> {
    snapshot
        .pickups
        .iter()
        .filter(|p| p.available && wanted(p))
        .map(|p| (((p.x - me.x).powi(2) + (p.z - me.z).powi(2)).sqrt(), p))
        .filter(|(d, _)| *d <= PLANNER_PICKUP_REACH)
        .min_by(|a, b| a.0.total_cmp(&b.0))
        .map(|(_, p)| p)
}

/// Walk to a point, still shooting at anything already in front.
fn walk_to(
    pad: &fragr_server::protocol::PickupState,
    me: &fragr_server::protocol::PlayerState,
    enemy: Option<&fragr_server::protocol::PlayerState>,
) -> Action {
    let dist = ((pad.x - me.x).powi(2) + (pad.z - me.z).powi(2)).sqrt();
    let fire = enemy.is_some_and(|e| {
        let to_enemy = ((e.x - me.x).powi(2) + (e.z - me.z).powi(2)).sqrt();
        to_enemy < 6.0
    });
    Action {
        look_at: Some(LookAt {
            y: None,
            x: Some(pad.x),
            z: Some(pad.z),
            player_id: None,
        }),
        forward: dist > 1.0,
        fire,
        ..Action::default()
    }
}

/// A Sabotage agent: fight what is close and in sight, otherwise play the
/// shared objective controller, otherwise its ordinary policy.
pub fn sabotage_policy_action(
    policy: Policy,
    bot_id: Uuid,
    snapshot: &Snapshot,
    arena: &Arena,
    map: &fragr_server::protocol::SabotageMap,
) -> Action {
    let objective =
        fragr_server::sim::sabotage::controller::objective_action(bot_id, snapshot, map);
    if policy == Policy::RouteProbe {
        return objective.unwrap_or_default();
    }
    let Some(me) = snapshot.players.iter().find(|p| p.id == bot_id) else {
        return Action::default();
    };
    let threatened = snapshot.players.iter().any(|other| {
        me.is_hostile_to(other)
            && other.hp > 0
            && (other.x - me.x).hypot(other.z - me.z) < 20.0
            && arena.fighter_visible(me, other)
    });
    if threatened {
        return policy_action(policy, bot_id, snapshot, arena);
    }
    objective.unwrap_or_else(|| policy_action(policy, bot_id, snapshot, arena))
}

/// The action for one agent under its policy.
pub fn policy_action(policy: Policy, bot_id: Uuid, snapshot: &Snapshot, arena: &Arena) -> Action {
    if let Some(flags) = snapshot.flags.as_ref() {
        let Some(me) = snapshot.players.iter().find(|p| p.id == bot_id) else {
            return Action::default();
        };
        let Some(team) = me.team else {
            return Action::default();
        };
        let own = &flags[team.index()];
        let enemy = &flags[team.other().index()];
        let carrying = enemy.carrier == Some(bot_id);
        // The harness gives each agent a unique callsign. Pick by that stable
        // identity rather than process-local player IDs or snapshot order.
        let defending = policy != Policy::RouteProbe
            && snapshot
                .players
                .iter()
                .filter(|player| {
                    player.team == Some(team) && player.hp > 0 && enemy.carrier != Some(player.id)
                })
                .min_by(|a, b| a.name.cmp(&b.name))
                .is_some_and(|player| player.id == bot_id);
        if policy != Policy::RouteProbe
            && !carrying
            && snapshot.players.iter().any(|other| {
                me.is_hostile_to(other)
                    && other.hp > 0
                    && (other.x - me.x).hypot(other.z - me.z) < 12.0
                    && arena.fighter_visible(me, other)
            })
        {
            return reflex_action(bot_id, snapshot, arena);
        }
        let goal = if carrying {
            if own.status == fragr_server::protocol::FlagStatus::Dropped {
                own.position
            } else {
                own.stand
            }
        } else if own.status == fragr_server::protocol::FlagStatus::Dropped {
            own.position
        } else if defending {
            own.carrier
                .and_then(|carrier| snapshot.players.iter().find(|p| p.id == carrier))
                .map(|p| [p.x, p.y - fragr_server::sim::PLAYER_FLOOR_Y, p.z])
                .unwrap_or(own.stand)
        } else {
            enemy.position
        };
        return Action {
            look_at: Some(LookAt {
                x: Some(goal[0]),
                y: Some(goal[1]),
                z: Some(goal[2]),
                player_id: None,
            }),
            forward: (goal[0] - me.x).hypot(goal[2] - me.z) > 1.5,
            ..Action::default()
        };
    }
    match policy {
        Policy::Reflex => reflex_action(bot_id, snapshot, arena),
        Policy::Planner => planner_action(bot_id, snapshot, arena),
        Policy::RouteProbe => Action::default(),
    }
}

#[derive(Default)]
struct ObservationDeadline {
    drain_tick_events: bool,
}

impl ObservationDeadline {
    fn before_message(&self, message: &ServerMessage) -> bool {
        self.drain_tick_events && matches!(message, ServerMessage::Snapshot(_))
    }

    fn after_message(&mut self, observation: &Observation, max_ticks: u64, rounds: u32) -> bool {
        if observation.rounds_completed() >= rounds {
            return true;
        }
        let elapsed = observation
            .last_tick
            .saturating_sub(observation.first_tick.unwrap_or(0));
        if elapsed >= max_ticks {
            self.drain_tick_events = true;
        }
        false
    }
}

/// The arena's solids, learned from the MapInfo the server sends on join.
/// Without them an agent has no way to tell a clear shot from a wall, which
/// is why the first combat reports showed accuracy near fifteen percent
/// whatever the policy: the agents were firing through cover.
#[derive(Debug, Clone)]
pub struct Arena {
    pub solids: Vec<Solid>,
    /// Half the width of the square, centred on the origin.
    pub half_extent: f32,
}

impl Default for Arena {
    fn default() -> Self {
        Self {
            solids: Vec::new(),
            half_extent: 25.0,
        }
    }
}

impl Arena {
    /// Ground-level eye visibility, retained for callers with horizontal points.
    pub fn line_of_sight(&self, from: (f32, f32), to: (f32, f32)) -> bool {
        fragr_server::combat::line_of_sight(
            [from.0, EYE_HEIGHT, from.1],
            [to.0, EYE_HEIGHT, to.1],
            &self.solids,
        )
    }

    fn fighter_visible(
        &self,
        from: &fragr_server::protocol::PlayerState,
        to: &fragr_server::protocol::PlayerState,
    ) -> bool {
        use fragr_server::sim::PLAYER_FLOOR_Y;
        fragr_server::combat::line_of_sight(
            [from.x, from.y - PLAYER_FLOOR_Y + EYE_HEIGHT, from.z],
            [
                to.x,
                to.y - PLAYER_FLOOR_Y + fragr_server::combat::target_height(to.campaign) * 0.5,
                to.z,
            ],
            &self.solids,
        )
    }
}

fn transport<E: fmt::Display>(err: E) -> Error {
    Error::Transport(err.to_string())
}

async fn agent_task(
    url: String,
    name: String,
    policy: Policy,
    mut stop: tokio::sync::watch::Receiver<bool>,
    mut ready: Option<tokio::sync::oneshot::Sender<()>>,
) -> Result<(), Error> {
    let (ws, _) = connect_async(&url).await.map_err(transport)?;
    let (mut sink, mut stream) = ws.split();
    let hello = ClientMessage::Hello {
        body: None,
        gameplay_version: fragr_server::protocol::GAMEPLAY_VERSION,
        geometry_version: fragr_server::protocol::GEOMETRY_VERSION,
        role: Role::Agent,
        name,
        ticket: fragr_server::join_ticket::ticket_for(Role::Agent),
        resume: None,
    };
    sink.send(Message::Text(
        serde_json::to_string(&hello).map_err(transport)?,
    ))
    .await
    .map_err(transport)?;
    let mut player_id: Option<Uuid> = None;
    let mut loadout: Option<fragr_server::protocol::LoadoutState> = None;
    let mut arena = Arena::default();
    let mut navigation = None;
    let mut navigator = fragr_server::navigation::Navigator::default();
    let mut mission_client = fragr_server::mission::MissionClient::default();
    let mut sabotage_map: Option<fragr_server::protocol::SabotageMap> = None;
    loop {
        if *stop.borrow() {
            break;
        }
        let msg = tokio::select! {
            _ = stop.changed() => break,
            message = stream.next() => match message {
                Some(message) => message,
                None => break,
            },
        };
        let Ok(Message::Text(text)) = msg else {
            continue;
        };
        match serde_json::from_str::<ServerMessage>(&text) {
            Ok(ServerMessage::Mission { tick, state }) => {
                mission_client
                    .observe(tick, state)
                    .map_err(|error| Error::Server(error.into()))?;
                if let Some(ready) = mission_client.readiness(player_id) {
                    sink.send(Message::Text(
                        serde_json::to_string(&ClientMessage::MissionReady(ready))
                            .map_err(transport)?,
                    ))
                    .await
                    .map_err(transport)?;
                }
                if let Some(request) = mission_client.continuation(player_id) {
                    sink.send(Message::Text(
                        serde_json::to_string(&ClientMessage::MissionContinue(request))
                            .map_err(transport)?,
                    ))
                    .await
                    .map_err(transport)?;
                }
            }
            Ok(ServerMessage::Loadout(next)) => {
                next.validate_for(player_id, loadout.as_ref())
                    .map_err(|error| Error::Server(error.into()))?;
                loadout = Some(next);
            }
            Ok(ServerMessage::Welcome { player_id: pid, .. }) => player_id = pid,
            Ok(ServerMessage::MapInfo {
                map_id,
                m02_objectives,
                m02_side_ward,
                m03,
                m04,
                m05,
                m06,
                solids,
                half_extent,
                geometry_version,
                presentation,
                mission,
                sabotage,
                ..
            }) => {
                if let Some(layout) = sabotage.as_ref() {
                    layout
                        .validate()
                        .map_err(|error| Error::Server(format!("invalid sabotage map: {error}")))?;
                }
                sabotage_map = sabotage;
                fragr_server::protocol::validate_map_presentation(presentation.as_ref(), &solids)
                    .map_err(|error| Error::Server(format!("invalid map presentation: {error}")))?;
                mission_client
                    .replace_map_with_id(
                        map_id,
                        m02_objectives,
                        m02_side_ward,
                        mission.as_ref(),
                        half_extent,
                        &solids,
                        presentation.as_ref(),
                    )
                    .map_err(|error| Error::Server(format!("invalid mission map: {error}")))?;
                mission_client
                    .replace_map_with_m03(m03.as_ref(), half_extent, &solids, presentation.as_ref())
                    .map_err(|error| Error::Server(format!("invalid M03 mission map: {error}")))?;
                mission_client
                    .replace_map_with_m04(m04.as_ref(), half_extent, &solids, presentation.as_ref())
                    .map_err(|error| Error::Server(format!("invalid M04 mission map: {error}")))?;
                mission_client
                    .replace_map_with_m05(m05.as_ref(), half_extent, &solids, presentation.as_ref())
                    .map_err(|error| Error::Server(format!("invalid M05 mission map: {error}")))?;
                mission_client
                    .replace_map_with_m06(m06.as_ref(), half_extent, &solids, presentation.as_ref())
                    .map_err(|error| Error::Server(format!("invalid M06 mission map: {error}")))?;
                fragr_server::protocol::validate_map_geometry(
                    half_extent,
                    &solids,
                    geometry_version,
                )
                .map_err(|error| Error::Server(format!("invalid navigation map: {error}")))?;
                let geometry = fragr_server::movement::Arena {
                    half: half_extent,
                    solids: solids.clone(),
                };
                navigation = Some(
                    tokio::task::spawn_blocking(move || {
                        fragr_server::navigation::Navigation::shared(geometry)
                    })
                    .await
                    .map_err(|error| Error::Server(format!("navigation worker failed: {error}")))?
                    .map_err(|error| Error::Server(error.to_string()))?,
                );
                navigator.clear();
                arena = Arena {
                    solids,
                    half_extent,
                };
                if player_id.is_some() {
                    if let Some(sender) = ready.take() {
                        let _ = sender.send(());
                    }
                }
            }
            Ok(ServerMessage::Snapshot(snapshot)) => {
                let Some(id) = player_id else {
                    continue;
                };
                let live_arena = mission_client.live_visibility_solids().map(|solids| Arena {
                    solids,
                    half_extent: arena.half_extent,
                });
                let physical = live_arena.as_ref().unwrap_or(&arena);
                // A plant or defuse is a held Use standing still: nothing else
                // may steer or aim this fighter while it lasts.
                if let Some(map) = sabotage_map
                    .as_ref()
                    .filter(|_| snapshot.sabotage.is_some())
                {
                    use fragr_server::sim::sabotage::controller::{objective, Objective};
                    if matches!(
                        objective(id, &snapshot, map),
                        Objective::Plant | Objective::Defuse
                    ) {
                        let hold = ClientMessage::Action(Action {
                            interact: true,
                            ..Action::default()
                        });
                        if sink
                            .send(Message::Text(
                                serde_json::to_string(&hold).map_err(transport)?,
                            ))
                            .await
                            .is_err()
                        {
                            break;
                        }
                        continue;
                    }
                }
                let wanted = match sabotage_map
                    .as_ref()
                    .filter(|_| snapshot.sabotage.is_some())
                {
                    Some(map) => sabotage_policy_action(policy, id, &snapshot, physical, map),
                    None => policy_action(policy, id, &snapshot, physical),
                };
                let wanted = fragr_server::inventory::control_action_with_target_filter(
                    id,
                    &snapshot,
                    loadout.as_ref(),
                    wanted,
                    mission_client.state.is_some(),
                    |mine, other| {
                        live_arena
                            .as_ref()
                            .is_none_or(|world| world.fighter_visible(mine, other))
                    },
                );
                let driven = navigation.as_ref().map_or_else(Action::default, |world| {
                    mission_client.steer(&mut navigator, world, id, &snapshot, wanted)
                });
                let action = ClientMessage::Action(driven);
                if sink
                    .send(Message::Text(
                        serde_json::to_string(&action).map_err(transport)?,
                    ))
                    .await
                    .is_err()
                {
                    break;
                }
            }
            Ok(ServerMessage::Error { code, message })
                if code == "unsupported_geometry"
                    || code == "unsupported_gameplay"
                    || code == "party_full" =>
            {
                return Err(Error::Server(message));
            }
            Err(error) => {
                return Err(Error::Server(format!("invalid server message: {error}")));
            }
            _ => {}
        }
    }
    let _ = sink.close().await;
    Ok(())
}

/// Run one playtest: server plus agents plus observer, then the report.
pub async fn run(config: Config) -> Result<(Report, Observation), Error> {
    let (shutdown_tx, shutdown_rx) = tokio::sync::oneshot::channel::<()>();
    let (ready_tx, ready_rx) = tokio::sync::oneshot::channel();
    // Controlled rounds: no mid-round boss or compliance beat, so the numbers
    // describe the fighters and nothing else.
    let sabotage = config.rules.mode() == fragr_server::protocol::GameMode::Sabotage;
    let match_config = MatchConfig {
        frag_limit: (!config.rules.mode().objective()).then_some(config.frag_limit),
        capture_limit: (config.rules.mode() == fragr_server::protocol::GameMode::Ctf)
            .then_some(config.capture_limit),
        // Sabotage runs its own muster, live and charge clocks.
        time_limit_ticks: (!sabotage).then_some(config.time_limit_ticks),
        boss_spawn_ticks: None,
        compliance_ping_ticks: None,
        rules: config.rules.clone(),
        sabotage: fragr_server::rules::SabotageConfig {
            live_ticks: config.time_limit_ticks,
            ..config.sabotage.clone()
        },
        ..MatchConfig::default()
    };
    let options = ServerOptions {
        campaign_run: false,
        authored: None,
        difficulty: None,
        bind: "127.0.0.1:0".to_string(),
        bots: 0,
        map: config.map,
        map_rotate: false,
        match_config: Some(match_config),
        // A harness run is reproducible and quiet: the report is the output.
        seed: config.seed,
        status_every_s: 0,
        solo_broadcast: false,
        join_secret: None,
        access: Default::default(),
    };
    let server = tokio::spawn(async move {
        run_server(
            options,
            async move {
                let _ = shutdown_rx.await;
            },
            Some(ready_tx),
        )
        .await
        .map_err(|e| e.to_string())
    });
    let addr = tokio::time::timeout(Duration::from_secs(5), ready_rx)
        .await
        .map_err(|_| Error::Timeout("server bind"))?
        .map_err(|_| Error::Server("server exited before binding".to_string()))?;
    let url = format!("ws://{addr}");

    let (stop, stopped) = tokio::sync::watch::channel(false);
    let mut agents = Vec::with_capacity(config.agents);
    let tiers = if config.tiers.is_empty() {
        vec![Policy::Reflex]
    } else {
        config.tiers.clone()
    };
    for i in 0..config.agents {
        let policy = tiers[i % tiers.len()];
        agents.push(tokio::spawn(agent_task(
            url.clone(),
            // The name carries the policy, so the per-agent report says which
            // agents were which without a second lookup.
            format!("{}-{}", policy.name(), i + 1),
            policy,
            stopped.clone(),
            None,
        )));
    }

    let (ws, _) = connect_async(&url).await.map_err(transport)?;
    let (mut sink, mut stream) = ws.split();
    let hello = ClientMessage::Hello {
        body: None,
        gameplay_version: fragr_server::protocol::GAMEPLAY_VERSION,
        geometry_version: fragr_server::protocol::GEOMETRY_VERSION,
        role: Role::Spectator,
        name: "Observer".to_string(),
        ticket: None,
        resume: None,
    };
    sink.send(Message::Text(
        serde_json::to_string(&hello).map_err(transport)?,
    ))
    .await
    .map_err(transport)?;

    let mut observation = Observation::default();
    let mut observation_deadline = ObservationDeadline::default();
    let deadline = Duration::from_secs_f64(config.max_ticks as f64 / TICKS_PER_SECOND + 15.0);
    let watch = async {
        loop {
            // The server sends Snapshot before that tick's Event messages.
            // At the max tick, drain those events through the next snapshot,
            // with a bounded wait if the connection stalls.
            let next = if observation_deadline.drain_tick_events {
                tokio::time::timeout(Duration::from_secs(1), stream.next())
                    .await
                    .ok()
                    .flatten()
            } else {
                stream.next().await
            };
            let Some(msg) = next else { break };
            let Ok(Message::Text(text)) = msg else {
                continue;
            };
            let parsed = serde_json::from_str::<ServerMessage>(&text);
            if parsed
                .as_ref()
                .is_ok_and(|message| observation_deadline.before_message(message))
            {
                break;
            }
            match parsed {
                Ok(ServerMessage::Snapshot(snapshot)) => {
                    observation.ingest_snapshot(&snapshot, text.len());
                }
                Ok(ServerMessage::Event(event)) => observation.ingest_event(event),
                Ok(ServerMessage::MapInfo { rules, .. }) => observation.rules = rules,
                _ => {}
            }
            if observation_deadline.after_message(&observation, config.max_ticks, config.rounds) {
                break;
            }
        }
    };
    let _ = tokio::time::timeout(deadline, watch).await;

    let _ = stop.send(true);
    let _ = sink.close().await;
    let _ = shutdown_tx.send(());
    let _ = tokio::time::timeout(Duration::from_secs(5), server).await;
    let mut agent_error = None;
    for agent in agents {
        let error = match tokio::time::timeout(Duration::from_secs(2), agent).await {
            Ok(Ok(Ok(()))) => None,
            Ok(Ok(Err(error))) => Some(error),
            Ok(Err(error)) => Some(Error::Server(format!("agent task failed: {error}"))),
            Err(_) => Some(Error::Timeout("agent shutdown")),
        };
        agent_error = agent_error.or(error);
    }
    if let Some(error) = agent_error {
        return Err(error);
    }
    let _ = TICK;
    let report = compute_report(&observation, config.agents);
    Ok((report, observation))
}

#[cfg(test)]
mod tests {
    use super::*;
    use fragr_server::protocol::PlayerState;

    #[tokio::test]
    async fn stopping_a_quiet_agent_does_not_wait_for_another_snapshot() {
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let url = format!("ws://{}", listener.local_addr().unwrap());
        let (joined, ready) = tokio::sync::oneshot::channel();
        let server = tokio::spawn(async move {
            let (socket, _) = listener.accept().await.unwrap();
            let mut ws = tokio_tungstenite::accept_async(socket).await.unwrap();
            ws.next().await.unwrap().unwrap();
            joined.send(()).unwrap();
            assert!(matches!(ws.next().await, Some(Ok(Message::Close(_)))));
        });
        let (stop, stopped) = tokio::sync::watch::channel(false);
        let agent = tokio::spawn(agent_task(
            url,
            "Probe".into(),
            Policy::Reflex,
            stopped,
            None,
        ));
        ready.await.unwrap();
        stop.send(true).unwrap();
        tokio::time::timeout(Duration::from_secs(1), agent)
            .await
            .unwrap()
            .unwrap()
            .unwrap();
        server.await.unwrap();
    }

    #[tokio::test]
    async fn invalid_map_is_an_agent_failure_not_a_partial_world() {
        let valid = serde_json::to_value(fragr_server::sim::GameState::new().map_info()).unwrap();
        let mut extent = valid.clone();
        extent["half_extent"] = serde_json::json!(f32::MAX);
        let mut version = valid.clone();
        version["geometry_version"] = serde_json::json!(2.5);
        let mut solid = valid.clone();
        solid["solids"][0]["bottom"] = serde_json::json!("ceiling");
        let mut surfaces = valid.clone();
        surfaces["presentation"] = serde_json::json!({"ground":"concrete","solids":[]});
        let mut details = valid.clone();
        details["presentation"] = serde_json::json!({"ground":"concrete",
            "solids":vec!["enamel"; valid["solids"].as_array().unwrap().len()],
            "decorations":[{"solid":9999,"face":"north","center":[0,0],
                "size":[1,1],"kind":"terminal"}]});
        let rejected = serde_json::json!({"type": "error", "code": "unsupported_geometry", "message": "geometry version rejected"});
        for (bad, expected) in [
            (extent.to_string(), "geometry extent"),
            (version.to_string(), "invalid server message"),
            (solid.to_string(), "invalid server message"),
            (surfaces.to_string(), "invalid map presentation"),
            (details.to_string(), "invalid map presentation"),
            ("{broken".to_string(), "invalid server message"),
            (rejected.to_string(), "geometry version rejected"),
        ] {
            assert_bad_map_fails(valid.to_string(), bad, expected).await;
        }
    }

    async fn assert_bad_map_fails(valid: String, bad: String, expected: &str) {
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let url = format!("ws://{}", listener.local_addr().unwrap());
        let server = tokio::spawn(async move {
            let (socket, _) = listener.accept().await.unwrap();
            let mut ws = tokio_tungstenite::accept_async(socket).await.unwrap();
            ws.next().await.unwrap().unwrap();
            ws.send(Message::Text(valid)).await.unwrap();
            ws.send(Message::Text(bad)).await.unwrap();
            let _ = ws.next().await;
        });
        let (_stop, stopped) = tokio::sync::watch::channel(false);
        let result = tokio::time::timeout(
            Duration::from_secs(5),
            agent_task(url, "Probe".into(), Policy::Reflex, stopped, None),
        )
        .await
        .expect("invalid map must stop the controller");
        assert!(matches!(result, Err(Error::Server(message)) if message.contains(expected)));
        server.await.unwrap();
    }

    fn player(name: &str, id: Uuid, x: f32, z: f32, fired: bool) -> PlayerState {
        PlayerState {
            collidable: true,
            body: None,
            golden: false,
            lives: None,
            team: None,
            campaign: None,
            pitch: 0.0,
            id,
            name: name.to_string(),
            x,
            y: fragr_server::sim::PLAYER_FLOOR_Y,
            z,
            yaw: 0.0,
            hp: 100,
            armor: 0,
            just_fired: fired,
            behavior: None,
            score: 0,
            weapon: "Flechette".to_string(),
        }
    }

    fn snapshot(tick: u64, players: Vec<PlayerState>) -> Snapshot {
        Snapshot {
            team_scores: None,
            flags: None,
            capture_scores: None,
            capture_limit: None,
            tick,
            players,
            round_state: Some("Active".to_string()),
            round_time_left: None,
            frag_limit: Some(5),
            shot_results: Vec::new(),
            projectiles: Vec::new(),
            grenades: Vec::new(),
            explosions: Vec::new(),
            mode_name: "Contested Frequency".to_string(),
            playlist: "Arena Duel".to_string(),
            pressure: None,
            host_line: String::new(),
            mvp: None,
            mvp_frags: None,
            pickups: Vec::new(),
            map_id: 1,
            map_name: "Arena Duel".to_string(),
            episode_id: None,
            episode_title: None,
            episode_objective: None,
            episode_progress: None,
            episode_phase: None,
            jammer_dish: None,
            sabotage: None,
        }
    }

    fn round_start(players: &[&str]) -> GameEvent {
        GameEvent::RoundStart {
            rules: None,
            round_number: 1,
            frag_limit: Some(5),
            time_limit: None,
            players: players.iter().map(|p| p.to_string()).collect(),
            previous_winner: None,
            mode_name: String::new(),
            playlist: String::new(),
            host_line: String::new(),
        }
    }

    fn frag(killer: &str, victim: &str) -> GameEvent {
        GameEvent::Frag {
            killer_team: None,
            victim_team: None,
            killer: killer.to_string(),
            victim: victim.to_string(),
            killer_score: 1,
        }
    }

    #[test]
    fn reflex_action_targets_the_nearest_fighter() {
        let me = Uuid::new_v4();
        let near = Uuid::new_v4();
        let far = Uuid::new_v4();
        let snap = snapshot(
            1,
            vec![
                player("me", me, 0.0, 0.0, false),
                player("far", far, 30.0, 0.0, false),
                player("near", near, 5.0, 0.0, false),
            ],
        );
        let action = reflex_action(me, &snap, &Arena::default());
        assert_eq!(action.look_at.unwrap().player_id, Some(near));
        assert!(action.forward);
        assert!(action.fire);
        // Alone on the map it patrols rather than standing there. Standing
        // there is what made an empty stretch of a round read as a stuck agent.
        let alone = snapshot(1, vec![player("me", me, 0.0, 0.0, false)]);
        let patrolling = reflex_action(me, &alone, &Arena::default());
        assert!(patrolling.forward, "it goes looking");
        assert!(!patrolling.fire, "at nothing in particular");
        let aim = patrolling.look_at.expect("it aims where it is going");
        assert!(aim.player_id.is_none() && aim.x.is_some() && aim.z.is_some());
        assert!(reflex_action(Uuid::new_v4(), &snap, &Arena::default())
            .look_at
            .is_none());
        let close = snapshot(
            1,
            vec![
                player("me", me, 0.0, 0.0, false),
                player("near", near, 1.0, 0.0, false),
            ],
        );
        let action = reflex_action(me, &close, &Arena::default());
        assert!(!action.forward);
        assert!(action.fire);
    }

    /// Fists Only refuses every swap, so a reflex agent walks into reach.
    #[test]
    fn reflex_action_closes_to_melee_reach_with_fists() {
        let me = Uuid::new_v4();
        let rival = Uuid::new_v4();
        let mut fists = player("me", me, 0.0, 0.0, false);
        fists.weapon = "Fists".into();
        let far = snapshot(
            1,
            vec![fists.clone(), player("rival", rival, 5.0, 0.0, false)],
        );
        let action = reflex_action(me, &far, &Arena::default());
        assert!(action.forward && !action.fire);
        let near = snapshot(1, vec![fists, player("rival", rival, 1.2, 0.0, false)]);
        let action = reflex_action(me, &near, &Arena::default());
        assert!(action.fire);
        assert_eq!(weapon_from_wire("Fists"), Some(WeaponType::Fists));
    }

    #[test]
    fn observation_tracks_idle_stuck_and_fire() {
        let a = Uuid::new_v4();
        let mut obs = Observation::default();
        obs.ingest_snapshot(&snapshot(10, vec![player("a", a, 0.0, 0.0, true)]), 100);
        obs.ingest_snapshot(&snapshot(11, vec![player("a", a, 0.0, 0.0, false)]), 100);
        obs.ingest_snapshot(&snapshot(12, vec![player("a", a, 0.0, 0.0, true)]), 100);
        obs.ingest_snapshot(&snapshot(13, vec![player("a", a, 1.0, 0.0, false)]), 100);
        obs.ingest_snapshot(&snapshot(14, vec![player("a", a, 1.0, 0.0, false)]), 100);
        let track = &obs.tracks["a"];
        assert_eq!(track.ticks_present, 5);
        assert_eq!(track.idle_ticks, 3);
        assert_eq!(track.stuck_max_ticks, 1, "firing or moving resets the run");
        assert_eq!(track.fire_ticks, 2);
        assert_eq!(track.weapon_fire_ticks["Flechette"], 2);
        assert_eq!(obs.first_tick, Some(10));
        assert_eq!(obs.last_tick, 14);
        assert_eq!(obs.snapshot_bytes, 500);
        // Standing still between rounds is not stuck and not idle.
        for tick in 15..30 {
            let mut ended = snapshot(tick, vec![player("a", a, 1.0, 0.0, false)]);
            ended.round_state = Some("Ended".to_string());
            obs.ingest_snapshot(&ended, 100);
        }
        let track = &obs.tracks["a"];
        assert_eq!(track.stuck_max_ticks, 1);
        assert_eq!(track.idle_ticks, 3);
        assert_eq!(track.ticks_present, 20);
    }

    /// A corpse is frozen by the server for the respawn delay. That is the
    /// rules working, not an agent that has stopped playing, and the harness
    /// used to report it as the latter.
    #[test]
    fn a_dead_fighter_is_counted_as_dead_not_stuck() {
        let a = Uuid::new_v4();
        let b = Uuid::new_v4();
        let mut obs = Observation::default();
        // Both on the field, then "a" dies and drops out of the snapshot.
        obs.ingest_snapshot(
            &snapshot(
                1,
                vec![
                    player("a", a, 3.0, 4.0, false),
                    player("b", b, 9.0, 9.0, false),
                ],
            ),
            100,
        );
        for tick in 2..=61 {
            obs.ingest_snapshot(&snapshot(tick, vec![player("b", b, 9.0, 9.0, false)]), 100);
        }
        let track = &obs.tracks["a"];
        assert_eq!(track.stuck_max_ticks, 0, "a corpse is not a stuck agent");
        assert_eq!(track.dead_max_ticks, 60, "three seconds of respawn delay");
    }

    /// The bug this splits apart: a brief wedge that happened to end in a
    /// death used to be reported as one long stall, so the number blamed the
    /// agent for the seconds it spent dead.
    #[test]
    fn a_wedge_and_a_death_are_not_one_long_stall() {
        let a = Uuid::new_v4();
        let mut obs = Observation::default();
        let b = Uuid::new_v4();
        let both = |tick: u64| {
            snapshot(
                tick,
                vec![
                    player("a", a, 3.0, 4.0, false),
                    player("b", b, 9.0, 9.0, false),
                ],
            )
        };
        // Alive and not moving for forty ticks: a genuine two second wedge.
        for tick in 1..=41 {
            obs.ingest_snapshot(&both(tick), 100);
        }
        // Then it dies and waits out the respawn, off the snapshot entirely.
        for tick in 42..=101 {
            obs.ingest_snapshot(&snapshot(tick, vec![player("b", b, 9.0, 9.0, false)]), 100);
        }
        // And comes back to the very spot it died on, which used to splice the
        // two stalls into one because the tracker never noticed it had left.
        for tick in 102..=111 {
            obs.ingest_snapshot(&both(tick), 100);
        }
        let track = &obs.tracks["a"];
        assert_eq!(
            track.stuck_max_ticks, 40,
            "the wedge is reported at its real length, not the length plus the funeral"
        );
        assert_eq!(track.dead_max_ticks, 60);
        assert_eq!(
            track.stuck_from_tick, 2,
            "and it says where the stall began"
        );
        assert_eq!(track.stuck_at, (3.0, 4.0));
    }

    /// The victim of a frag is already off the snapshot when the event
    /// arrives, because the server drops it the moment it dies. The kill
    /// distance is measured from the last place the two of them stood, so the
    /// tracker has to keep that position after a fighter leaves the field.
    #[test]
    fn a_kill_is_still_measured_after_the_victim_leaves_the_field() {
        let a = Uuid::new_v4();
        let b = Uuid::new_v4();
        let mut obs = Observation::default();
        obs.ingest_snapshot(
            &snapshot(
                1,
                vec![
                    player("killer", a, 0.0, 0.0, false),
                    player("victim", b, 8.0, 0.0, false),
                ],
            ),
            100,
        );
        // The victim dies: gone from the snapshot, then the frag lands.
        obs.ingest_snapshot(
            &snapshot(2, vec![player("killer", a, 0.0, 0.0, false)]),
            100,
        );
        obs.ingest_event(GameEvent::Frag {
            killer_team: None,
            victim_team: None,
            killer: "killer".to_string(),
            victim: "victim".to_string(),
            killer_score: 1,
        });
        let report = obs.combat_report();
        let kills: u64 = report.by_weapon.values().map(|w| w.kills).sum();
        assert_eq!(kills, 1, "the kill is attributed to the weapon in hand");
        assert_eq!(
            report.kill_distance_buckets.iter().sum::<u64>(),
            1,
            "and lands in a distance bucket"
        );
        assert_eq!(report.by_weapon["Flechette"].kill_distance.max, 8.0);
    }

    #[test]
    fn a_fighter_that_never_respawns_is_flagged() {
        let mut report = Report {
            rounds_completed: 1,
            agents: 1,
            ..Report::default()
        };
        report.per_agent.insert(
            "Probe-1".to_string(),
            AgentReport {
                dead_max_s: 9.0,
                ..AgentReport::default()
            },
        );
        let problems = check_thresholds(&report);
        assert!(
            problems
                .iter()
                .any(|p| p.contains("Probe-1 dead for 9.0 s without respawning")),
            "got {problems:?}"
        );
        // Waiting out the normal three second delay is not a problem.
        report.per_agent.get_mut("Probe-1").unwrap().dead_max_s = 3.0;
        assert!(
            !check_thresholds(&report)
                .iter()
                .any(|p| p.contains("dead for")),
            "the respawn delay itself is not a failure"
        );
    }

    #[test]
    fn report_counts_frags_spawn_deaths_and_gaps() {
        let a = Uuid::new_v4();
        let b = Uuid::new_v4();
        let mut obs = Observation::default();
        obs.ingest_snapshot(
            &snapshot(
                0,
                vec![
                    player("a", a, 0.0, 0.0, false),
                    player("b", b, 5.0, 0.0, false),
                ],
            ),
            200,
        );
        obs.ingest_event(round_start(&["a", "b"]));
        obs.ingest_snapshot(&snapshot(20, vec![player("a", a, 1.0, 0.0, false)]), 200);
        obs.ingest_event(frag("a", "b"));
        obs.ingest_snapshot(&snapshot(80, vec![player("a", a, 2.0, 0.0, false)]), 200);
        obs.ingest_event(GameEvent::Respawn {
            player: "b".to_string(),
        });
        obs.ingest_snapshot(&snapshot(200, vec![player("a", a, 3.0, 0.0, false)]), 200);
        obs.ingest_event(frag("b", "a"));
        obs.ingest_event(GameEvent::Pickup {
            player: "b".to_string(),
            player_id: b,
            kind: "weapon".to_string(),
            weapon: "Rail".to_string(),
            amount: None,
            pickup_id: "p1".to_string(),
            secret: false,
        });
        obs.ingest_snapshot(&snapshot(1200, vec![player("a", a, 4.0, 0.0, false)]), 200);
        obs.ingest_event(GameEvent::RoundEnd {
            team_scores: None,
            capture_scores: None,
            winning_team: None,
            winner: Some("a".to_string()),
            reason: "frag_limit".to_string(),
            final_scores: Vec::new(),
            winner_score: Some(1),
            mvp: None,
            mvp_frags: None,
            host_line: String::new(),
            sabotage: None,
        });
        let report = compute_report(&obs, 2);
        assert_eq!(report.rounds_completed, 1);
        assert_eq!(report.ticks, 1200);
        assert_eq!(report.frags, 2);
        assert_eq!(report.spawn_deaths, 1);
        assert_eq!(
            report.opening_spawn_deaths, 1,
            "b died inside the opening window"
        );
        assert_eq!(
            obs.frag_places[0],
            FragPlace {
                victim_spawn: Some((5.0, 0.0)),
                victim: Some((5.0, 0.0)),
                killer: Some((1.0, 0.0)),
            }
        );
        assert_eq!(report.pickups, 1);
        assert_eq!(report.time_to_first_frag_s, Some(1.0));
        assert!((report.longest_gap_without_frag_s - 50.0).abs() < 1e-9);
        assert!((report.frags_per_minute - 2.0).abs() < 1e-9);
        assert!((report.host_beats_per_minute - 2.0).abs() < 1e-9);
        assert!((report.snapshot_bytes_per_tick - 200.0).abs() < 1e-9);
        assert_eq!(report.per_agent["a"].frags, 1);
        assert_eq!(report.per_agent["a"].deaths, 1);
        assert_eq!(report.per_agent["b"].spawn_deaths, 1);
        assert_eq!(report.per_agent["b"].deaths, 1);
        let empty = compute_report(&Observation::default(), 0);
        assert_eq!(empty.frags, 0);
        assert_eq!(empty.time_to_first_frag_s, None);
        assert_eq!(empty.snapshot_bytes_per_tick, 0.0);
    }

    #[test]
    fn a_respawn_death_is_not_an_opening_death() {
        let a = Uuid::from_u128(1);
        let b = Uuid::from_u128(2);
        let mut obs = Observation::default();
        obs.ingest_snapshot(
            &snapshot(
                0,
                vec![
                    player("a", a, 0.0, 0.0, false),
                    player("b", b, 50.0, 0.0, false),
                ],
            ),
            100,
        );
        obs.ingest_event(round_start(&["a", "b"]));
        obs.ingest_snapshot(&snapshot(100, vec![player("a", a, 0.0, 0.0, false)]), 100);
        obs.ingest_event(frag("a", "b"));
        obs.ingest_snapshot(&snapshot(160, vec![player("a", a, 0.0, 0.0, false)]), 100);
        obs.ingest_event(GameEvent::Respawn {
            player: "b".to_string(),
        });
        for (tick, x) in [(161, 30.0), (180, 31.0)] {
            obs.ingest_snapshot(
                &snapshot(
                    tick,
                    vec![
                        player("a", a, 0.0, 0.0, false),
                        player("b", b, x, 0.0, false),
                    ],
                ),
                100,
            );
        }
        obs.ingest_event(frag("a", "b"));
        let report = compute_report(&obs, 2);
        assert_eq!(report.spawn_deaths, 1, "only the respawn death is early");
        assert_eq!(report.opening_spawn_deaths, 0);
        assert_eq!(obs.frag_places[0].victim_spawn, Some((50.0, 0.0)));
        assert_eq!(obs.frag_places[1].victim_spawn, Some((30.0, 0.0)));
        assert_eq!(obs.frag_places[1].victim, Some((31.0, 0.0)));
    }

    #[test]
    fn thresholds_flag_the_frustrations() {
        let mut report = Report {
            agents: 4,
            rounds_completed: 1,
            frags: 20,
            frags_per_minute: 4.0,
            spawn_deaths: 1,
            ..Report::default()
        };
        assert!(check_thresholds(&report).is_empty());
        report.rounds_completed = 0;
        report.frags_per_minute = 0.5;
        report.spawn_deaths = 5;
        report.per_agent.insert(
            "Probe-1".to_string(),
            AgentReport {
                stuck_max_s: 6.0,
                ..AgentReport::default()
            },
        );
        let problems = check_thresholds(&report);
        assert_eq!(problems.len(), 4, "{problems:?}");
        assert!(problems.iter().any(|p| p.contains("no round completed")));
        assert!(problems
            .iter()
            .any(|p| p.contains("Probe-1 stuck for 6.0 s")));
        assert!(problems.iter().any(|p| p.contains("spawn deaths 5 of 20")));
        assert!(problems.iter().any(|p| p.contains("0.50 frags per minute")));
    }

    #[test]
    fn ctf_report_accounts_for_each_flag_transition_and_final_score() {
        use fragr_server::protocol::{FlagEventKind, Team, TeamScores};

        let mut obs = Observation::default();
        obs.ingest_snapshot(&snapshot(1, Vec::new()), 100);
        let empty = TeamScores::default();
        for kind in [
            FlagEventKind::Taken,
            FlagEventKind::Dropped,
            FlagEventKind::Returned,
            FlagEventKind::Taken,
        ] {
            obs.ingest_event(GameEvent::Flag {
                kind,
                flag: Team::Union,
                player: None,
                player_id: None,
                capture_scores: empty,
            });
        }
        let score = TeamScores {
            union: 0,
            coalition: 1,
        };
        obs.ingest_event(GameEvent::Flag {
            kind: FlagEventKind::Captured,
            flag: Team::Union,
            player: None,
            player_id: None,
            capture_scores: score,
        });
        obs.ingest_event(GameEvent::RoundEnd {
            winner: None,
            reason: "Time limit reached".to_string(),
            final_scores: Vec::new(),
            winner_score: None,
            mvp: None,
            mvp_frags: None,
            host_line: String::new(),
            winning_team: Some(Team::Coalition),
            team_scores: None,
            capture_scores: Some(score),
            sabotage: None,
        });
        let report = compute_report(&obs, 12);
        assert_eq!(report.flag_takes, 2);
        assert_eq!(report.flag_drops, 1);
        assert_eq!(report.flag_returns, 1);
        assert_eq!(report.captures, 1);
        assert_eq!(report.rounds_completed, 1);
        assert_eq!(
            report.last_round_reason.as_deref(),
            Some("Time limit reached")
        );
        assert_eq!(report.last_round_capture_scores, Some(score));

        let mut older = serde_json::to_value(report).unwrap();
        for field in [
            "flag_drops",
            "flag_returns",
            "last_round_reason",
            "last_round_capture_scores",
        ] {
            older.as_object_mut().unwrap().remove(field);
        }
        let older: Report = serde_json::from_value(older).unwrap();
        assert_eq!(older.flag_drops, 0);
        assert_eq!(older.flag_returns, 0);
        assert_eq!(older.last_round_reason, None);
        assert_eq!(older.last_round_capture_scores, None);

        let next_score = TeamScores {
            union: 3,
            coalition: 1,
        };
        obs.ingest_event(GameEvent::RoundEnd {
            winner: None,
            reason: "Capture limit reached".to_string(),
            final_scores: Vec::new(),
            winner_score: None,
            mvp: None,
            mvp_frags: None,
            host_line: String::new(),
            winning_team: Some(Team::Union),
            team_scores: None,
            capture_scores: Some(next_score),
            sabotage: None,
        });
        let latest = compute_report(&obs, 12);
        assert_eq!(latest.rounds_completed, 2);
        assert_eq!(
            latest.last_round_reason.as_deref(),
            Some("Capture limit reached")
        );
        assert_eq!(latest.last_round_capture_scores, Some(next_score));
    }

    fn carry_snapshot(tick: u64, x: f32, own_status: FlagStatus) -> Snapshot {
        use fragr_server::protocol::FlagState;
        let carrier_id = Uuid::from_u128(1);
        let carrier = player("Carrier", carrier_id, x, 0.0, false);
        let mut snapshot = snapshot(tick, vec![carrier]);
        snapshot.flags = Some([
            FlagState {
                team: Team::Union,
                stand: [-70.0, 0.0, 0.0],
                position: [x, 0.0, 0.0],
                status: FlagStatus::Carried,
                carrier: Some(carrier_id),
                return_ticks: None,
            },
            FlagState {
                team: Team::Coalition,
                stand: [70.0, 0.0, 0.0],
                position: [70.0, 0.0, 0.0],
                status: own_status,
                carrier: (own_status == FlagStatus::Carried).then_some(Uuid::from_u128(2)),
                return_ticks: None,
            },
        ]);
        snapshot
    }

    fn carry_event(kind: FlagEventKind) -> GameEvent {
        GameEvent::Flag {
            kind,
            flag: Team::Union,
            player: Some("Carrier".to_string()),
            player_id: Some(Uuid::from_u128(1)),
            capture_scores: fragr_server::protocol::TeamScores::default(),
        }
    }

    #[test]
    fn ctf_carry_tracks_progress_and_home_flag_denial_without_snapshots_in_report() {
        let mut obs = Observation::default();
        obs.ingest_event(carry_event(FlagEventKind::Taken));
        for (tick, x, status) in [
            (1, -70.0, FlagStatus::Carried),
            (2, 0.0, FlagStatus::Carried),
            (3, 69.0, FlagStatus::Carried),
            (4, 70.0, FlagStatus::Home),
        ] {
            obs.ingest_snapshot(&carry_snapshot(tick, x, status), 100);
        }
        // Duplicate delivery at the same tick must not inflate blocked time.
        obs.ingest_snapshot(&carry_snapshot(4, 70.0, FlagStatus::Home), 100);
        obs.ingest_event(carry_event(FlagEventKind::Captured));
        let report = compute_report(&obs, 12);
        assert_eq!(report.carry_episodes.len(), 1);
        let episode = &report.carry_episodes[0];
        assert_eq!(episode.end, CarryEnd::Captured);
        assert_eq!(episode.observed_carrier_ticks, 4);
        assert_eq!(episode.first_distance_to_home, Some(140.0));
        assert_eq!(episode.closest_distance_to_home, Some(0.0));
        assert_eq!(episode.last_distance_to_home, Some(0.0));
        assert_eq!(episode.own_flag_away_ticks, 3);
        assert_eq!(episode.home_blocked_ticks, 1);
        assert!(!episode.combat_drop);
        assert_eq!(report.carry_episodes_omitted, 0);
    }

    #[test]
    fn ctf_carry_samples_snapshot_before_same_tick_take_event() {
        let mut obs = Observation::default();
        // Session sends the tick's Snapshot before its Flag events.
        obs.ingest_snapshot(&carry_snapshot(7, -68.0, FlagStatus::Home), 100);
        obs.ingest_event(carry_event(FlagEventKind::Taken));
        obs.ingest_event(carry_event(FlagEventKind::Dropped));
        let episode = &compute_report(&obs, 12).carry_episodes[0];
        assert_eq!(episode.started_tick, 7);
        assert_eq!(episode.ended_tick, 7);
        assert_eq!(episode.observed_carrier_ticks, 1);
        assert_eq!(episode.first_distance_to_home, Some(138.0));
        assert_eq!(episode.end, CarryEnd::Dropped);
    }

    #[test]
    fn observer_max_tick_drains_same_tick_flag_events_before_next_snapshot() {
        let mut obs = Observation::default();
        let mut deadline = ObservationDeadline::default();
        let messages = [
            ServerMessage::Snapshot(snapshot(1, Vec::new())),
            ServerMessage::Snapshot(carry_snapshot(3, -68.0, FlagStatus::Home)),
            ServerMessage::Event(carry_event(FlagEventKind::Taken)),
            ServerMessage::Event(carry_event(FlagEventKind::Dropped)),
            ServerMessage::Snapshot(snapshot(4, Vec::new())),
        ];
        for message in messages {
            if deadline.before_message(&message) {
                break;
            }
            match message {
                ServerMessage::Snapshot(frame) => obs.ingest_snapshot(&frame, 100),
                ServerMessage::Event(event) => obs.ingest_event(event),
                _ => unreachable!(),
            }
            if deadline.after_message(&obs, 2, 1) {
                break;
            }
        }
        let report = compute_report(&obs, 12);
        assert_eq!(obs.last_tick, 3);
        assert_eq!(report.flag_takes, 1);
        assert_eq!(report.flag_drops, 1);
        assert_eq!(report.carry_episodes[0].end, CarryEnd::Dropped);
        assert_eq!(report.carry_episodes[0].observed_carrier_ticks, 1);
    }

    #[test]
    fn ctf_carry_distinguishes_death_drop_leave_drop_and_unfinished_round() {
        let mut obs = Observation::default();
        obs.ingest_event(carry_event(FlagEventKind::Taken));
        obs.ingest_snapshot(&carry_snapshot(1, -20.0, FlagStatus::Home), 100);
        obs.ingest_event(carry_event(FlagEventKind::Dropped));
        // The authoritative combat path emits the drop before the frag.
        obs.ingest_event(frag("Defender", "Carrier"));
        obs.ingest_snapshot(&snapshot(2, Vec::new()), 100);
        obs.ingest_event(carry_event(FlagEventKind::Taken));
        obs.ingest_event(carry_event(FlagEventKind::Dropped));
        obs.ingest_snapshot(&snapshot(3, Vec::new()), 100);
        obs.ingest_event(carry_event(FlagEventKind::Taken));
        obs.ingest_event(GameEvent::RoundEnd {
            winner: None,
            reason: "Time limit reached".to_string(),
            final_scores: Vec::new(),
            winner_score: None,
            mvp: None,
            mvp_frags: None,
            host_line: String::new(),
            winning_team: None,
            team_scores: None,
            capture_scores: None,
            sabotage: None,
        });
        let report = compute_report(&obs, 12);
        assert_eq!(report.carry_episodes.len(), 3);
        assert_eq!(report.carry_episodes[0].end, CarryEnd::Dropped);
        assert!(report.carry_episodes[0].combat_drop);
        assert_eq!(report.carry_episodes[1].end, CarryEnd::Dropped);
        assert!(!report.carry_episodes[1].combat_drop);
        assert_eq!(report.carry_episodes[2].end, CarryEnd::RoundEnded);
        assert_eq!(report.carry_episodes[2].first_distance_to_home, None);
        assert_eq!(report.carry_episodes[2].closest_distance_to_home, None);
        assert_eq!(report.carry_episodes[2].last_distance_to_home, None);
        assert_eq!(report.unmatched_flag_ends, 0);
    }

    #[test]
    fn ctf_carry_rejects_an_end_for_a_different_carrier() {
        let mut obs = Observation::default();
        obs.ingest_event(carry_event(FlagEventKind::Taken));
        let wrong_end = GameEvent::Flag {
            kind: FlagEventKind::Captured,
            flag: Team::Union,
            player: Some("Other".to_string()),
            player_id: Some(Uuid::from_u128(2)),
            capture_scores: fragr_server::protocol::TeamScores::default(),
        };
        obs.ingest_event(wrong_end.clone());
        // A missing take for the next carrier cannot be fabricated from its
        // score event; count it without assigning an episode to the first.
        obs.ingest_event(wrong_end);
        let report = compute_report(&obs, 12);
        assert_eq!(report.carry_episodes.len(), 1);
        assert_eq!(report.carry_episodes[0].carrier.as_deref(), Some("Carrier"));
        assert_eq!(report.carry_episodes[0].end, CarryEnd::Incomplete);
        assert_eq!(report.unmatched_flag_ends, 2);
        assert!(report.carry_episodes[0].first_distance_to_home.is_none());
    }

    #[test]
    fn ctf_carry_report_is_bounded_and_old_json_defaults() {
        let mut obs = Observation::default();
        for _ in 0..=MAX_CARRY_EPISODES {
            obs.ingest_event(carry_event(FlagEventKind::Taken));
            obs.ingest_event(carry_event(FlagEventKind::Dropped));
        }
        let report = compute_report(&obs, 12);
        assert_eq!(report.carry_episodes.len(), MAX_CARRY_EPISODES);
        assert_eq!(report.carry_episodes_omitted, 1);
        obs.ingest_event(carry_event(FlagEventKind::Taken));
        let active_report = compute_report(&obs, 12);
        assert_eq!(active_report.carry_episodes.len(), MAX_CARRY_EPISODES);
        assert_eq!(active_report.carry_episodes_omitted, 2);
        let mut old = serde_json::to_value(report).unwrap();
        old.as_object_mut().unwrap().remove("carry_episodes");
        old.as_object_mut()
            .unwrap()
            .remove("carry_episodes_omitted");
        old.as_object_mut().unwrap().remove("unmatched_flag_ends");
        let old: Report = serde_json::from_value(old).unwrap();
        assert!(old.carry_episodes.is_empty());
        assert_eq!(old.carry_episodes_omitted, 0);
        assert_eq!(old.unmatched_flag_ends, 0);
    }

    #[test]
    fn controlled_ctf_gate_requires_one_fighters_causal_take_carry_and_score() {
        let id = Uuid::from_u128(1);
        let score = fragr_server::protocol::TeamScores {
            union: 0,
            coalition: 1,
        };
        let flag = |kind| GameEvent::Flag {
            kind,
            flag: Team::Union,
            player: Some("route-probe-1".to_string()),
            player_id: Some(id),
            capture_scores: score,
        };
        let mut obs = Observation {
            rules: Some(
                fragr_server::rules::RuleSet::new(
                    fragr_server::protocol::GameMode::Ctf,
                    &[],
                    false,
                )
                .unwrap()
                .wire(),
            ),
            ..Observation::default()
        };
        obs.ingest_snapshot(&carry_snapshot(1, -68.0, FlagStatus::Home), 100);
        obs.ingest_event(flag(FlagEventKind::Taken));
        obs.ingest_snapshot(&carry_snapshot(2, 68.0, FlagStatus::Home), 100);
        obs.ingest_event(flag(FlagEventKind::Captured));
        obs.ingest_event(GameEvent::RoundEnd {
            winner: None,
            reason: "Capture limit reached".to_string(),
            final_scores: Vec::new(),
            winner_score: None,
            mvp: None,
            mvp_frags: None,
            host_line: String::new(),
            winning_team: Some(Team::Coalition),
            team_scores: None,
            capture_scores: Some(score),
            sabotage: None,
        });
        let report = compute_report(&obs, 1);
        assert!(check_ctf_route_smoke(&report, &obs).is_empty());

        let mut wrong_id = obs.clone();
        if let GameEvent::Flag { player_id, .. } = &mut wrong_id.events[1].event {
            *player_id = Some(Uuid::from_u128(2));
        }
        assert!(check_ctf_route_smoke(&report, &wrong_id)
            .iter()
            .any(|problem| problem.contains("preceding take")));

        let mut wrong_event_score = obs.clone();
        if let GameEvent::Flag { capture_scores, .. } = &mut wrong_event_score.events[1].event {
            *capture_scores = Default::default();
        }
        assert!(check_ctf_route_smoke(&report, &wrong_event_score)
            .iter()
            .any(|problem| problem.contains("capture event")));

        let mut no_carried_frame = report.clone();
        no_carried_frame.carry_episodes[0].observed_carrier_ticks = 0;
        assert!(check_ctf_route_smoke(&no_carried_frame, &obs)
            .iter()
            .any(|problem| problem.contains("carried snapshot")));

        let mut wrong_score = report.clone();
        wrong_score.last_round_capture_scores = Some(Default::default());
        assert!(check_ctf_route_smoke(&wrong_score, &obs)
            .iter()
            .any(|problem| problem.contains("capture score")));
    }

    #[test]
    fn contested_ctf_gate_requires_combat_flag_state_and_both_sides() {
        let mut report = Report {
            agents: 4,
            rounds_completed: 1,
            frags: 12,
            rules: Some(
                fragr_server::rules::RuleSet::new(
                    fragr_server::protocol::GameMode::Ctf,
                    &[],
                    false,
                )
                .unwrap()
                .wire(),
            ),
            sides: [("union".to_string(), 2), ("coalition".to_string(), 2)]
                .into_iter()
                .collect(),
            last_round_capture_scores: Some(Default::default()),
            ..Report::default()
        };
        let mut obs = Observation::default();
        obs.ingest_snapshot(&carry_snapshot(1, -68.0, FlagStatus::Home), 100);
        assert!(check_contested_ctf(&report, &obs).is_empty());
        // A scoreless but active fight like the failed CI run is valid
        // contested evidence when the independent capture gate passes.
        assert_eq!(report.flag_takes, 0);
        assert_eq!(report.captures, 0);
        report.frags = 0;
        assert!(check_contested_ctf(&report, &obs)
            .iter()
            .any(|problem| problem.contains("contested combat")));
        report.frags = 12;
        obs.latest_flags = None;
        assert!(check_contested_ctf(&report, &obs)
            .iter()
            .any(|problem| problem.contains("flag snapshot")));
        report.sides.remove("union");
        assert!(check_contested_ctf(&report, &obs)
            .iter()
            .any(|problem| problem.contains("union side")));
    }

    #[tokio::test]
    async fn reflex_agents_finish_a_round_in_process() {
        let config = Config {
            agents: 4,
            rounds: 1,
            frag_limit: 2,
            time_limit_ticks: 20 * 40,
            max_ticks: 20 * 90,
            ..Config::default()
        };
        let (report, observation) = run(config).await.expect("playtest run");
        assert!(observation.snapshots_seen > 0);
        assert_eq!(report.agents, 4);
        // The round ends by frag limit or time limit; how many frags land before that
        // depends on the machine (coverage builds run slower), so the thresholds are
        // enforced by the CI smoke step, not here.
        assert!(report.rounds_completed >= 1, "{report:?}");
        assert!(
            !report.per_agent.is_empty(),
            "{:?}",
            report.per_agent.keys()
        );
        assert!(
            report.per_agent.len() <= 4,
            "only the four probes should appear: {:?}",
            report.per_agent.keys()
        );
        assert!(report.snapshot_bytes_per_tick > 0.0);
    }
}

#[cfg(test)]
mod combat_tests {
    use super::*;
    use fragr_server::protocol::{PlayerState, ShotResult};

    fn player(name: &str, id: Uuid, x: f32, z: f32, weapon: &str) -> PlayerState {
        PlayerState {
            collidable: true,
            body: None,
            golden: false,
            lives: None,
            team: None,
            campaign: None,
            pitch: 0.0,
            id,
            name: name.to_string(),
            x,
            y: fragr_server::sim::PLAYER_FLOOR_Y,
            z,
            yaw: 0.0,
            hp: 100,
            armor: 0,
            just_fired: false,
            behavior: None,
            score: 0,
            weapon: weapon.to_string(),
        }
    }

    fn frame(tick: u64, players: Vec<PlayerState>, shots: Vec<ShotResult>) -> Snapshot {
        Snapshot {
            team_scores: None,
            flags: None,
            capture_scores: None,
            capture_limit: None,
            tick,
            players,
            round_state: Some("Active".to_string()),
            round_time_left: Some(60),
            frag_limit: Some(10),
            shot_results: shots,
            projectiles: Vec::new(),
            grenades: Vec::new(),
            explosions: Vec::new(),
            mode_name: "Contested Frequency".to_string(),
            playlist: "Arena Duel".to_string(),
            pressure: None,
            host_line: String::new(),
            mvp: None,
            mvp_frags: None,
            pickups: Vec::new(),
            map_id: 1,
            map_name: "Arena Duel".to_string(),
            episode_id: None,
            episode_title: None,
            episode_objective: None,
            episode_progress: None,
            episode_phase: None,
            jammer_dish: None,
            sabotage: None,
        }
    }

    fn shot(shooter: Uuid, hit: bool, target: Option<Uuid>, damage: i32) -> ShotResult {
        ShotResult {
            trace: None,
            killed: false,
            shooter_id: shooter,
            shooter: "S".to_string(),
            hit,
            target_id: target,
            target: target.map(|_| "T".to_string()),
            damage,
            target_hp_after: hit.then_some(75),
        }
    }

    #[test]
    fn resolved_grenade_evidence_never_infers_a_dead_owners_current_gun() {
        use fragr_server::protocol::{ExplosionHit, ExplosionResult};
        let owner = Uuid::from_u128(51);
        let target = Uuid::from_u128(52);
        let mut observation = Observation::default();
        observation.ingest_snapshot(
            &frame(
                1,
                vec![
                    player("Thrower", owner, 0.0, 0.0, "Rail"),
                    player("Victim", target, 2.0, 0.0, "Scatter"),
                ],
                vec![],
            ),
            10,
        );
        let mut snapshot = frame(2, vec![], vec![]);
        snapshot.explosions.push(ExplosionResult {
            id: 7,
            owner_id: owner,
            position: [0.0, 0.5, 0.0],
            radius: 4.0,
            hits: vec![
                ExplosionHit {
                    target_id: owner,
                    hp_damage: 100,
                    armor_damage: 0,
                    target_hp_after: 0,
                    killed: true,
                },
                ExplosionHit {
                    target_id: target,
                    hp_damage: 10,
                    armor_damage: 17,
                    target_hp_after: -30,
                    killed: true,
                },
            ],
        });
        observation.ingest_snapshot(&snapshot, 50);
        observation.ingest_event(GameEvent::Hit {
            shooter: "Thrower".into(),
            shooter_id: owner,
            target: "Victim".into(),
            target_id: target,
            damage: 50,
            target_hp_after: -30,
        });
        observation.ingest_event(GameEvent::Frag {
            killer: "Thrower".into(),
            victim: "Victim".into(),
            killer_score: 1,
            killer_team: None,
            victim_team: None,
        });
        let tally = &observation.weapons["Grenade"];
        assert_eq!(
            (tally.shots, tally.hits, tally.damage, tally.kills),
            (1, 1, 27, 1)
        );
        assert!(!observation.weapons.contains_key("Rail"));
        assert!(!observation.weapons.contains_key("Scatter"));
        snapshot.tick = 3;
        snapshot.explosions.clear();
        observation.ingest_snapshot(&snapshot, 5);
        assert!(observation.pending_grenade_kills.is_empty());
        assert!(observation.pending_grenade_names.is_empty());
    }

    #[test]
    fn quantiles_describe_a_distribution_and_survive_nothing() {
        let empty = Quantiles::from_values(&[]);
        assert_eq!(empty.count, 0);
        assert_eq!(empty.p50, 0.0);
        let all_bad = Quantiles::from_values(&[f64::NAN, f64::INFINITY]);
        assert_eq!(all_bad.count, 0, "nonsense values never become a statistic");
        let q = Quantiles::from_values(&[5.0, 1.0, 3.0, 2.0, 4.0]);
        assert_eq!(q.count, 5);
        assert_eq!((q.min, q.p50, q.max), (1.0, 3.0, 5.0));
        assert!((q.mean - 3.0).abs() < 1e-9);
        assert!(q.p90 >= q.p50 && q.p90 <= q.max);
        let one = Quantiles::from_values(&[7.5]);
        assert_eq!((one.count, one.min, one.p50, one.max), (1, 7.5, 7.5, 7.5));
    }

    #[test]
    fn wilson_says_how_little_a_small_sample_means() {
        assert_eq!(wilson_interval(0, 0), (0.0, 1.0), "no trials, no claim");
        let (lo, hi) = wilson_interval(1, 1);
        assert!(
            lo > 0.0 && hi == 1.0,
            "one hit from one shot is not certainty: {lo} {hi}"
        );
        assert!(lo < 0.3, "and it is a weak claim: {lo}");
        let (lo_small, hi_small) = wilson_interval(5, 10);
        let (lo_big, hi_big) = wilson_interval(500, 1000);
        assert!(
            (hi_small - lo_small) > (hi_big - lo_big) * 5.0,
            "ten shots say far less than a thousand: {lo_small}..{hi_small} vs {lo_big}..{hi_big}"
        );
        for (lo, hi) in [wilson_interval(0, 20), wilson_interval(20, 20)] {
            assert!((0.0..=1.0).contains(&lo) && (0.0..=1.0).contains(&hi));
        }
    }

    #[test]
    fn shots_are_counted_by_weapon_with_the_distance_they_travelled() {
        let mut obs = Observation::default();
        let a = Uuid::new_v4();
        let b = Uuid::new_v4();
        obs.ingest_snapshot(
            &frame(
                1,
                vec![
                    player("A", a, 0.0, 0.0, "rail"),
                    player("B", b, 12.0, 0.0, "scatter"),
                ],
                vec![shot(a, true, Some(b), 75)],
            ),
            100,
        );
        // A fighter fires at most once a tick, so the miss is the next tick.
        obs.ingest_snapshot(
            &frame(
                2,
                vec![
                    player("A", a, 0.0, 0.0, "rail"),
                    player("B", b, 12.0, 0.0, "scatter"),
                ],
                vec![shot(a, false, None, 0)],
            ),
            100,
        );
        let report = obs.combat_report();
        assert_eq!(report.shots, 2);
        assert_eq!(report.hits, 1);
        assert!((report.accuracy - 0.5).abs() < 1e-9);
        assert!(
            report.accuracy_lo < 0.5 && report.accuracy_hi > 0.5,
            "{report:?}"
        );
        let rail = &report.by_weapon["rail"];
        assert_eq!((rail.shots, rail.hits, rail.damage), (2, 1, 75));
        assert!(
            (rail.hit_distance.p50 - 12.0).abs() < 1e-4,
            "{:?}",
            rail.hit_distance
        );
        assert!(!report.by_weapon.contains_key("scatter"), "B never fired");
        obs.ingest_snapshot(
            &frame(
                3,
                vec![player("A", a, 0.0, 0.0, "rail")],
                vec![shot(Uuid::new_v4(), true, None, 10)],
            ),
            100,
        );
        assert_eq!(
            obs.combat_report().shots,
            3,
            "legacy shots still count when the shooter is absent"
        );
        assert_eq!(obs.combat_report().by_weapon["Unknown"].shots, 1);
        assert_eq!(obs.combat_report().by_weapon["rail"].shots, 2);
    }

    #[test]
    fn lethal_evidence_survives_trades_and_overrides_stale_weapons_and_positions() {
        use fragr_server::protocol::{ShotImpact, ShotTrace};
        let a = Uuid::new_v4();
        let b = Uuid::new_v4();
        for surviving in [false, true] {
            let mut obs = Observation::default();
            let roster = vec![
                player("A", a, 100.0, 0.0, "Scatter"),
                player("B", b, 200.0, 0.0, "Scatter"),
            ];
            obs.ingest_snapshot(&frame(1, roster.clone(), vec![]), 100);
            let shots = [(a, b, "A", "B"), (b, a, "B", "A")].map(|(from, to, name, target)| {
                let mut result = shot(from, true, Some(to), 80);
                result.shooter = name.into();
                result.target = Some(target.into());
                result.target_hp_after = Some(0);
                result.killed = true;
                result.trace = Some(ShotTrace {
                    weapon: WeaponType::Rail,
                    origin: [0.0, 1.0, 0.0],
                    end: [3.0, 5.0, 0.0],
                    impact: ShotImpact::Fighter {
                        normal: [-1.0, 0.0, 0.0],
                    },
                    pellets: vec![],
                });
                result
            });
            obs.ingest_snapshot(
                &frame(
                    2,
                    if surviving { roster } else { vec![] },
                    shots.clone().into(),
                ),
                100,
            );
            for result in shots {
                obs.ingest_event(GameEvent::Hit {
                    shooter: result.shooter.clone(),
                    shooter_id: result.shooter_id,
                    target: result.target.clone().unwrap(),
                    target_id: result.target_id.unwrap(),
                    damage: 80,
                    target_hp_after: 0,
                });
                obs.ingest_event(GameEvent::Frag {
                    killer_team: None,
                    victim_team: None,
                    killer: result.shooter,
                    victim: result.target.unwrap(),
                    killer_score: 1,
                });
            }
            let report = obs.combat_report();
            assert_eq!((report.shots, report.hits), (2, 2));
            let rail = &report.by_weapon["Rail"];
            assert_eq!((rail.shots, rail.kills), (2, 2));
            assert_eq!((rail.hit_distance.p50, rail.kill_distance.p50), (5.0, 5.0));
            assert_eq!(rail.time_to_kill_s.count, 2);
            assert!(!report.by_weapon.contains_key("Scatter"));
        }
    }

    #[test]
    fn time_to_kill_runs_from_the_first_damage_to_the_death() {
        let mut obs = Observation::default();
        let a = Uuid::new_v4();
        let b = Uuid::new_v4();
        let scene = |tick: u64| {
            frame(
                tick,
                vec![
                    player("A", a, 0.0, 0.0, "flechette"),
                    player("B", b, 6.0, 0.0, "scatter"),
                ],
                vec![],
            )
        };
        let hit = || GameEvent::Hit {
            shooter: "A".into(),
            shooter_id: a,
            target: "B".into(),
            target_id: b,
            damage: 25,
            target_hp_after: 75,
        };
        obs.ingest_snapshot(&scene(100), 50);
        obs.ingest_event(hit());
        obs.ingest_snapshot(&scene(110), 50);
        obs.ingest_event(hit());
        obs.ingest_snapshot(&scene(120), 50);
        obs.ingest_event(GameEvent::Frag {
            killer_team: None,
            victim_team: None,
            killer: "A".into(),
            victim: "B".into(),
            killer_score: 1,
        });
        let report = obs.combat_report();
        assert_eq!(report.time_to_kill_s.count, 1);
        assert!(
            (report.time_to_kill_s.p50 - 1.0).abs() < 1e-6,
            "twenty ticks at twenty a second is one second, and the second hit did not restart it: {:?}",
            report.time_to_kill_s
        );
        let flechette = &report.by_weapon["flechette"];
        assert_eq!(flechette.kills, 1);
        assert!((flechette.kill_distance.p50 - 6.0).abs() < 1e-4);
        assert_eq!(flechette.time_to_kill_s.count, 1);
        assert!(
            (flechette.time_to_kill_s.p50 - 1.0).abs() < 1e-6,
            "per-weapon sticky TTK must match the global kill timer: {:?}",
            flechette.time_to_kill_s
        );
        assert_eq!(
            report.kill_distance_buckets[1], 1,
            "six units falls in the second bucket"
        );
        assert_eq!(report.kill_distance_buckets.iter().sum::<u64>(), 1);

        obs.ingest_event(GameEvent::Respawn { player: "B".into() });
        obs.ingest_snapshot(&scene(200), 50);
        obs.ingest_event(GameEvent::Frag {
            killer_team: None,
            victim_team: None,
            killer: "A".into(),
            victim: "B".into(),
            killer_score: 2,
        });
        let report = obs.combat_report();
        assert_eq!(
            report.time_to_kill_s.count, 1,
            "a death with no opening hit is left untimed rather than timed wrongly"
        );
        assert_eq!(report.by_weapon["flechette"].kills, 2);
    }

    #[test]
    fn distance_buckets_hold_the_far_tail() {
        let obs = Observation {
            kill_distances: vec![0.0, 4.9, 5.0, 49.9, 50.0, 500.0],
            ..Observation::default()
        };
        let report = obs.combat_report();
        assert_eq!(report.kill_distance_buckets.len(), DISTANCE_BUCKETS);
        assert_eq!(report.kill_distance_buckets[0], 2, "under five units");
        assert_eq!(report.kill_distance_buckets[1], 1);
        assert_eq!(report.kill_distance_buckets[9], 1, "forty five to fifty");
        assert_eq!(
            report.kill_distance_buckets[DISTANCE_BUCKETS - 1],
            2,
            "fifty and beyond share the last bucket"
        );
    }

    #[test]
    fn an_empty_run_reports_nothing_rather_than_nonsense() {
        let report = Observation::default().combat_report();
        assert_eq!((report.shots, report.hits), (0, 0));
        assert_eq!(report.accuracy, 0.0);
        assert_eq!((report.accuracy_lo, report.accuracy_hi), (0.0, 1.0));
        assert_eq!(report.shots_per_kill, 0.0);
        assert_eq!(report.time_to_kill_s.count, 0);
        assert!(report.by_weapon.is_empty());
        assert_eq!(report.kill_distance_buckets.len(), DISTANCE_BUCKETS);
    }
    #[test]
    fn one_scatter_blast_is_one_shot_however_many_results_it_publishes() {
        use fragr_server::protocol::{PelletTrace, ShotImpact, ShotTrace, WeaponType};
        let (a, b, c) = (Uuid::from_u128(1), Uuid::from_u128(2), Uuid::from_u128(3));
        let trace = |impact: ShotImpact, count: usize| ShotTrace {
            weapon: WeaponType::Scatter,
            origin: [0.0, 1.6, 0.0],
            end: [3.0, 1.6, 0.0],
            impact: impact.clone(),
            pellets: vec![
                PelletTrace {
                    end: [3.0, 1.6, 0.0],
                    impact,
                };
                count
            ],
        };
        let fighter = ShotImpact::Fighter {
            normal: [-1.0, 0.0, 0.0],
        };
        let mut left = shot(a, true, Some(b), 40);
        left.trace = Some(trace(fighter.clone(), 4));
        let mut right = shot(a, true, Some(c), 20);
        right.trace = Some(trace(fighter, 2));
        let mut missed = shot(a, false, None, 0);
        missed.trace = Some(trace(ShotImpact::Range, 1));
        let roster = vec![
            player("A", a, 0.0, 0.0, "Scatter"),
            player("B", b, 3.0, 0.5, "Flechette"),
            player("C", c, 3.0, -0.5, "Flechette"),
        ];
        let mut obs = Observation::default();
        obs.ingest_snapshot(&frame(1, roster.clone(), vec![left, right, missed]), 100);
        let tally = &obs.weapons["Scatter"];
        assert_eq!((tally.shots, tally.hits, tally.damage), (1, 1, 60));
        assert_eq!(tally.hit_distances.len(), 2);
        let mut miss_only = shot(a, false, None, 0);
        miss_only.trace = Some(trace(ShotImpact::Range, 7));
        obs.ingest_snapshot(&frame(2, roster, vec![miss_only]), 100);
        let tally = &obs.weapons["Scatter"];
        assert_eq!((tally.shots, tally.hits), (2, 1));
    }
}

#[cfg(test)]
mod sticky_ttk_tests {
    use super::*;

    #[test]
    fn sticky_table_ttk_flechette_rail_scatter() {
        let rows = sticky_weapon_ttk_table();
        assert_eq!(rows[0].weapon, WeaponType::Flechette);
        assert_eq!(rows[0].hits_to_kill, 4);
        assert!((rows[0].seconds - 0.6).abs() < 0.001);
        assert_eq!(rows[1].weapon, WeaponType::Rail);
        assert_eq!(rows[1].hits_to_kill, 2);
        assert!((rows[1].seconds - 1.0).abs() < 0.001);
        assert_eq!(rows[2].weapon, WeaponType::Scatter);
        assert_eq!(rows[2].hits_to_kill, 2, "two full seven-pellet blasts");
        assert!((rows[2].seconds - 0.6).abs() < 0.001);
        for row in rows {
            assert!(
                (STICKY_TTK_MIN_S..=STICKY_TTK_MAX_S).contains(&row.seconds),
                "{:?} {:.3} s left the sticky band",
                row.weapon,
                row.seconds
            );
        }
        assert!(
            check_sticky_ttk_table().is_empty(),
            "{:?}",
            check_sticky_ttk_table()
        );
    }

    #[test]
    fn assert_path_includes_sticky_ttk_with_frustration_checks() {
        let report = Report {
            agents: 4,
            rounds_completed: 1,
            frags: 20,
            frags_per_minute: 4.0,
            spawn_deaths: 1,
            ..Report::default()
        };
        assert!(
            check_thresholds(&report).is_empty(),
            "sticky table plus a clean run must pass --assert: {:?}",
            check_thresholds(&report)
        );
    }
}

#[cfg(test)]
mod weapon_choice_tests {

    use super::*;

    #[test]
    fn the_weapon_follows_the_range() {
        assert_eq!(weapon_for_distance(0.0), WeaponType::Scatter);
        assert_eq!(weapon_for_distance(5.9), WeaponType::Scatter);
        assert_eq!(weapon_for_distance(6.0), WeaponType::Flechette);
        assert_eq!(weapon_for_distance(18.0), WeaponType::Flechette);
        assert_eq!(weapon_for_distance(18.1), WeaponType::Rail);
        assert_eq!(weapon_from_wire("Rail"), Some(WeaponType::Rail));
        assert_eq!(weapon_from_wire("scatter"), Some(WeaponType::Scatter));
        assert_eq!(weapon_from_wire("bfg"), None);
    }
}

#[cfg(test)]
mod planner_tests {
    use super::*;
    use fragr_server::protocol::{PickupState, PlayerState};

    #[test]
    fn both_playtest_policies_target_union_actors_instead_of_nearby_allies() {
        use fragr_server::protocol::{CampaignActor, EnemyKind, EnemyPhase};
        let me = Uuid::from_u128(1);
        let ally = Uuid::from_u128(2);
        let foe = Uuid::from_u128(3);
        let mut mine = player("me", me, 0.0, 0.0, 100, "Tack");
        mine.campaign = Some(CampaignActor::Participant {});
        let mut partner = player("partner", ally, 1.0, 0.0, 100, "Tack");
        partner.campaign = mine.campaign;
        let mut guard = player("clerk", foe, 8.0, 0.0, 60, "Tack");
        guard.campaign = Some(CampaignActor::Union {
            kind: EnemyKind::Clerk,
            phase: EnemyPhase::Idle,
            phase_started: 0,
            phase_ends: 0,
            seated: false,
        });
        let mut snapshot = scene(1, vec![mine, partner, guard], vec![]);
        let arena = Arena::default();
        for policy in [reflex_action, planner_action] {
            assert_eq!(
                policy(me, &snapshot, &arena).look_at.unwrap().player_id,
                Some(foe)
            );
        }
        snapshot.players[2].hp = 0;
        for policy in [reflex_action, planner_action] {
            let action = policy(me, &snapshot, &arena);
            assert!(!action.fire && action.look_at.is_none_or(|aim| aim.player_id.is_none()));
        }
    }

    fn player(name: &str, id: Uuid, x: f32, z: f32, hp: i32, weapon: &str) -> PlayerState {
        PlayerState {
            collidable: true,
            body: None,
            golden: false,
            lives: None,
            team: None,
            campaign: None,
            pitch: 0.0,
            id,
            name: name.to_string(),
            x,
            y: fragr_server::sim::PLAYER_FLOOR_Y,
            z,
            yaw: 0.0,
            hp,
            armor: 0,
            just_fired: false,
            behavior: None,
            score: 0,
            weapon: weapon.to_string(),
        }
    }

    fn pad(kind: &str, weapon: &str, x: f32, z: f32, available: bool) -> PickupState {
        PickupState {
            claim: fragr_server::protocol::SupplyClaim::Contested,
            pool: None,
            id: format!("{kind}-{weapon}-{x}-{z}"),
            kind: kind.to_string(),
            weapon: weapon.to_string(),
            amount: None,
            x,
            y: 0.0,
            z,
            available,
            respawn_in: None,
        }
    }

    fn scene(tick: u64, players: Vec<PlayerState>, pickups: Vec<PickupState>) -> Snapshot {
        Snapshot {
            team_scores: None,
            flags: None,
            capture_scores: None,
            capture_limit: None,
            tick,
            players,
            round_state: Some("Active".to_string()),
            round_time_left: Some(60),
            frag_limit: Some(10),
            shot_results: Vec::new(),
            projectiles: Vec::new(),
            grenades: Vec::new(),
            explosions: Vec::new(),
            mode_name: "Contested Frequency".to_string(),
            playlist: "Arena Duel".to_string(),
            pressure: None,
            host_line: String::new(),
            mvp: None,
            mvp_frags: None,
            pickups,
            map_id: 1,
            map_name: "Arena Duel".to_string(),
            episode_id: None,
            episode_title: None,
            episode_objective: None,
            episode_progress: None,
            episode_phase: None,
            jammer_dish: None,
            sabotage: None,
        }
    }

    #[test]
    fn tiers_parse_or_say_why_not() {
        assert_eq!(Policy::parse("reflex"), Some(Policy::Reflex));
        assert_eq!(Policy::parse(" Planner "), Some(Policy::Planner));
        assert_eq!(Policy::parse("brain"), None);
        assert_eq!(
            Policy::parse_list("reflex,planner").unwrap(),
            vec![Policy::Reflex, Policy::Planner]
        );
        assert_eq!(
            Policy::parse_list(" planner , planner ").unwrap(),
            vec![Policy::Planner, Policy::Planner]
        );
        assert!(
            Policy::parse_list("").is_err(),
            "an empty list is an error, not a default"
        );
        assert!(Policy::parse_list(",,").is_err());
        let err = Policy::parse_list("reflex,brain").unwrap_err();
        assert!(err.contains("brain"), "the error names the offender: {err}");
        for p in [Policy::Reflex, Policy::Planner] {
            assert_eq!(Policy::parse(p.name()), Some(p));
        }
    }

    #[test]
    fn the_planner_holds_the_range_its_weapon_wants() {
        let me = Uuid::new_v4();
        let foe = Uuid::new_v4();
        // Flechette wants roughly seven to twelve units; the rail wants
        // eighteen to twenty eight, and the planner picks the weapon first.
        let far = scene(
            0,
            vec![
                player("me", me, 0.0, 0.0, 100, "flechette"),
                player("foe", foe, 40.0, 0.0, 100, "flechette"),
            ],
            vec![],
        );
        let action = planner_action(me, &far, &Arena::default());
        assert!(action.forward, "beyond every band: close in");
        assert!(!action.back);
        assert_eq!(
            action.weapon_swap,
            Some(WeaponType::Rail),
            "and bring the rail"
        );
        assert_eq!(action.look_at.as_ref().unwrap().player_id, Some(foe));

        // At twenty five units the rail is already in its band, so it holds.
        let mut rail_band = far.clone();
        rail_band.players[1].x = 25.0;
        let action = planner_action(me, &rail_band, &Arena::default());
        assert!(!action.forward, "the rail is happy here: {action:?}");
        assert!(action.left || action.right);

        let mut holding = far.clone();
        holding.players[1].x = 10.0;
        let action = planner_action(me, &holding, &Arena::default());
        assert!(!action.forward, "in the band: stop closing");
        assert!(!action.back);
        assert!(
            action.left || action.right,
            "and keep moving while holding it"
        );
        assert!(action.fire);

        let mut hugged = far.clone();
        hugged.players[1].x = 1.0;
        let action = planner_action(me, &hugged, &Arena::default());
        assert!(action.back, "far too close: back off");
        assert!(!action.forward);

        // A reflex agent in the same spot just keeps charging, which is the
        // behaviour that put every kill at knife range.
        let reflex = reflex_action(me, &holding, &Arena::default());
        assert!(reflex.forward, "reflex closes whenever it can");
    }

    #[test]
    fn the_planner_breaks_off_for_health_when_hurt() {
        let me = Uuid::new_v4();
        let foe = Uuid::new_v4();
        let hurt = scene(
            0,
            vec![
                player("me", me, 0.0, 0.0, 20, "flechette"),
                player("foe", foe, 10.0, 0.0, 100, "flechette"),
            ],
            vec![pad("health", "", 0.0, 8.0, true)],
        );
        let action = planner_action(me, &hurt, &Arena::default());
        let look = action.look_at.as_ref().unwrap();
        assert_eq!(look.player_id, None, "it walks to the pad, not the enemy");
        assert_eq!(look.z, Some(8.0));
        assert!(action.forward);

        // With the pad taken, it goes back to fighting.
        let mut taken = hurt.clone();
        taken.pickups[0].available = false;
        let action = planner_action(me, &taken, &Arena::default());
        assert_eq!(action.look_at.as_ref().unwrap().player_id, Some(foe));

        // Healthy, it ignores the pad entirely.
        let mut healthy = hurt.clone();
        healthy.players[0].hp = 100;
        let action = planner_action(me, &healthy, &Arena::default());
        assert_eq!(action.look_at.as_ref().unwrap().player_id, Some(foe));

        // A pad on the far side of the map is not worth the walk.
        let mut distant = hurt.clone();
        distant.pickups[0].z = 40.0;
        let action = planner_action(me, &distant, &Arena::default());
        assert_eq!(action.look_at.as_ref().unwrap().player_id, Some(foe));
    }

    #[test]
    fn the_planner_collects_a_weapon_it_lacks_when_nobody_is_close() {
        let me = Uuid::new_v4();
        let foe = Uuid::new_v4();
        let quiet = scene(
            0,
            vec![
                player("me", me, 0.0, 0.0, 100, "flechette"),
                player("foe", foe, 35.0, 0.0, 100, "flechette"),
            ],
            vec![pad("weapon", "Rail", 5.0, 0.0, true)],
        );
        let action = planner_action(me, &quiet, &Arena::default());
        assert_eq!(
            action.look_at.as_ref().unwrap().x,
            Some(5.0),
            "detour for the rail"
        );

        // It does not detour for the weapon it is already holding.
        let mut same = quiet.clone();
        same.pickups[0].weapon = "Flechette".to_string();
        let action = planner_action(me, &same, &Arena::default());
        assert_eq!(action.look_at.as_ref().unwrap().player_id, Some(foe));

        // Nor with an enemy in its face.
        let mut pressed = quiet.clone();
        pressed.players[1].x = 6.0;
        let action = planner_action(me, &pressed, &Arena::default());
        assert_eq!(action.look_at.as_ref().unwrap().player_id, Some(foe));
    }

    #[test]
    fn a_planner_alone_tidies_up_and_a_missing_fighter_does_nothing() {
        let me = Uuid::new_v4();
        let alone = scene(
            0,
            vec![player("me", me, 0.0, 0.0, 100, "flechette")],
            vec![pad("armor", "", 3.0, 0.0, true)],
        );
        let action = planner_action(me, &alone, &Arena::default());
        assert_eq!(action.look_at.as_ref().unwrap().x, Some(3.0));
        assert!(!action.fire, "nothing to shoot at");

        let empty = scene(0, vec![player("me", me, 0.0, 0.0, 100, "rail")], vec![]);
        let action = planner_action(me, &empty, &Arena::default());
        assert!(action.forward && !action.fire, "nothing to fetch: patrol");
        assert!(action.look_at.as_ref().unwrap().player_id.is_none());

        let absent = planner_action(Uuid::new_v4(), &alone, &Arena::default());
        assert!(
            absent.look_at.is_none(),
            "a fighter not in the snapshot does nothing"
        );

        // Dead fighters are not targets.
        let corpses = scene(
            0,
            vec![
                player("me", me, 0.0, 0.0, 100, "flechette"),
                player("dead", Uuid::new_v4(), 5.0, 0.0, 0, "flechette"),
            ],
            vec![],
        );
        // A fighter with zero health is not a target. Nothing left to fight,
        // so it patrols instead of aiming at a body.
        let action = planner_action(me, &corpses, &Arena::default());
        assert!(action.look_at.as_ref().unwrap().player_id.is_none());
        assert!(action.forward && !action.fire);
    }

    #[test]
    fn policy_action_dispatches() {
        let me = Uuid::new_v4();
        let foe = Uuid::new_v4();
        let close = scene(
            0,
            vec![
                player("me", me, 0.0, 0.0, 100, "flechette"),
                player("foe", foe, 10.0, 0.0, 100, "flechette"),
            ],
            vec![],
        );
        assert!(
            policy_action(Policy::Reflex, me, &close, &Arena::default()).forward,
            "reflex closes"
        );
        assert!(
            !policy_action(Policy::Planner, me, &close, &Arena::default()).forward,
            "the planner is already where it wants to be"
        );
        let parked = Arena {
            solids: vec![Solid::from_center(5.0, 0.0, 0.5, 3.0)],
            half_extent: 25.0,
        };
        let moved = Arena {
            solids: vec![Solid::from_center(5.0, 8.0, 0.5, 3.0)],
            half_extent: 25.0,
        };
        for tier in [Policy::Reflex, Policy::Planner] {
            assert!(!policy_action(tier, me, &close, &parked).fire);
            assert!(
                policy_action(tier, me, &close, &moved).fire,
                "physical cover motion exposes the shot without rebuilding routes"
            );
        }
    }

    #[test]
    fn ctf_policy_fights_a_visible_blocker_then_resumes_the_flag_route() {
        use fragr_server::protocol::{FlagState, FlagStatus, Team};
        let me = Uuid::from_u128(1);
        let foe = Uuid::from_u128(2);
        let mut mine = player("me", me, 0.0, 0.0, 100, "flechette");
        mine.team = Some(Team::Coalition);
        let mut blocker = player("foe", foe, 6.0, 0.0, 100, "flechette");
        blocker.team = Some(Team::Union);
        let mut defender = player("a-defender", Uuid::from_u128(3), 0.0, 0.0, 100, "flechette");
        defender.team = Some(Team::Coalition);
        let mut snap = scene(1, vec![mine, blocker, defender], vec![]);
        snap.flags = Some([
            FlagState {
                team: Team::Union,
                stand: [-70.0, 0.0, 0.0],
                position: [-70.0, 0.0, 0.0],
                status: FlagStatus::Home,
                carrier: None,
                return_ticks: None,
            },
            FlagState {
                team: Team::Coalition,
                stand: [70.0, 0.0, 0.0],
                position: [70.0, 0.0, 0.0],
                status: FlagStatus::Home,
                carrier: None,
                return_ticks: None,
            },
        ]);
        for policy in [Policy::Reflex, Policy::Planner] {
            let fight = policy_action(policy, me, &snap, &Arena::default());
            assert_eq!(fight.look_at.unwrap().player_id, Some(foe));
            assert!(fight.fire);
        }
        let probe = policy_action(Policy::RouteProbe, me, &snap, &Arena::default());
        assert_eq!(probe.look_at.unwrap().x, Some(-70.0));
        assert!(!probe.fire);
        snap.flags.as_mut().unwrap()[Team::Union.index()].carrier = Some(me);
        snap.flags.as_mut().unwrap()[Team::Union.index()].status = FlagStatus::Carried;
        snap.flags.as_mut().unwrap()[Team::Union.index()].position = [0.0, 0.0, 0.0];
        for policy in [Policy::Reflex, Policy::Planner] {
            let carry = policy_action(policy, me, &snap, &Arena::default());
            assert_eq!(carry.look_at.unwrap().x, Some(70.0));
            assert!(!carry.fire);
        }
        snap.flags.as_mut().unwrap()[Team::Union.index()].carrier = None;
        snap.flags.as_mut().unwrap()[Team::Union.index()].status = FlagStatus::Home;
        snap.flags.as_mut().unwrap()[Team::Union.index()].position = [-70.0, 0.0, 0.0];
        snap.players[1].x = 30.0;
        for policy in [Policy::Reflex, Policy::Planner] {
            let route = policy_action(policy, me, &snap, &Arena::default());
            assert_eq!(route.look_at.unwrap().x, Some(-70.0));
            assert!(!route.fire);
        }
    }

    fn ctf_six_a_side() -> Snapshot {
        use fragr_server::protocol::{FlagState, FlagStatus, Team};

        let mut players = Vec::new();
        for (team, first_id, prefix) in [
            (Team::Union, 1_u128, "union"),
            (Team::Coalition, 7_u128, "coalition"),
        ] {
            for seat in 0..6 {
                let mut fighter = player(
                    &format!("{prefix}-{:02}", seat + 1),
                    Uuid::from_u128(first_id + seat),
                    if team == Team::Union { -40.0 } else { 40.0 },
                    0.0,
                    100,
                    "flechette",
                );
                fighter.team = Some(team);
                players.push(fighter);
            }
        }
        let mut snapshot = scene(1, players, vec![]);
        snapshot.flags = Some([
            FlagState {
                team: Team::Union,
                stand: [-70.0, 0.0, 0.0],
                position: [-70.0, 0.0, 0.0],
                status: FlagStatus::Home,
                carrier: None,
                return_ticks: None,
            },
            FlagState {
                team: Team::Coalition,
                stand: [70.0, 0.0, 0.0],
                position: [70.0, 0.0, 0.0],
                status: FlagStatus::Home,
                carrier: None,
                return_ticks: None,
            },
        ]);
        snapshot
    }

    fn ctf_goal_x(snapshot: &Snapshot, id: Uuid) -> f32 {
        policy_action(Policy::Reflex, id, snapshot, &Arena::default())
            .look_at
            .unwrap()
            .x
            .unwrap()
    }

    #[test]
    fn ctf_six_a_side_has_one_stable_defender_per_side() {
        use fragr_server::protocol::Team;

        let mut snapshot = ctf_six_a_side();
        for team in [Team::Union, Team::Coalition] {
            let own_x = snapshot.flags.as_ref().unwrap()[team.index()].stand[0];
            let enemy_x = snapshot.flags.as_ref().unwrap()[team.other().index()].stand[0];
            let side: Vec<_> = snapshot
                .players
                .iter()
                .filter(|player| player.team == Some(team))
                .map(|player| player.id)
                .collect();
            assert_eq!(side.len(), 6);
            assert_eq!(
                side.iter()
                    .filter(|id| ctf_goal_x(&snapshot, **id) == own_x)
                    .count(),
                1
            );
            assert_eq!(
                side.iter()
                    .filter(|id| ctf_goal_x(&snapshot, **id) == enemy_x)
                    .count(),
                5
            );
        }
        let original: Vec<_> = snapshot
            .players
            .iter()
            .map(|player| (player.id, ctf_goal_x(&snapshot, player.id)))
            .collect();
        snapshot.players.reverse();
        for (id, goal_x) in original {
            assert_eq!(ctf_goal_x(&snapshot, id), goal_x);
        }
        snapshot
            .players
            .iter_mut()
            .find(|player| player.id == Uuid::from_u128(1))
            .unwrap()
            .hp = 0;
        assert_eq!(ctf_goal_x(&snapshot, Uuid::from_u128(2)), -70.0);
    }

    #[test]
    fn ctf_roles_recover_dropped_flags_and_support_carriers() {
        use fragr_server::protocol::{FlagStatus, Team};

        let mut snapshot = ctf_six_a_side();
        let union_defender = Uuid::from_u128(1);
        let union_attacker = Uuid::from_u128(2);
        let coalition_carrier = Uuid::from_u128(7);
        let coalition_next_defender = Uuid::from_u128(8);
        let coalition_attacker = Uuid::from_u128(9);

        // A stolen Union flag pulls its defender toward the thief, while
        // another Union fighter still presses the Coalition stand. The carrier
        // returns home, and another Coalition fighter assumes defense.
        snapshot.players[6].x = 15.0;
        snapshot.players[6].z = 3.0;
        let flags = snapshot.flags.as_mut().unwrap();
        flags[Team::Union.index()].status = FlagStatus::Carried;
        flags[Team::Union.index()].position = [15.0, 0.0, 3.0];
        flags[Team::Union.index()].carrier = Some(coalition_carrier);
        assert_eq!(ctf_goal_x(&snapshot, union_defender), 15.0);
        assert_eq!(ctf_goal_x(&snapshot, union_attacker), 70.0);
        assert_eq!(ctf_goal_x(&snapshot, coalition_carrier), 70.0);
        assert_eq!(ctf_goal_x(&snapshot, coalition_next_defender), 70.0);
        assert_eq!(ctf_goal_x(&snapshot, coalition_attacker), 15.0);

        // A grounded home flag takes objective priority for every noncarrier
        // and the carrier attempting to score, while no close blocker is present.
        let flags = snapshot.flags.as_mut().unwrap();
        flags[Team::Coalition.index()].status = FlagStatus::Dropped;
        flags[Team::Coalition.index()].position = [32.0, 0.0, 0.0];
        assert_eq!(ctf_goal_x(&snapshot, coalition_carrier), 32.0);
        assert_eq!(ctf_goal_x(&snapshot, coalition_next_defender), 32.0);
        assert_eq!(ctf_goal_x(&snapshot, coalition_attacker), 32.0);
    }
}

#[cfg(test)]
mod line_of_sight_tests {
    use super::*;

    fn box_at(cx: f32, cz: f32, half: f32) -> Solid {
        Solid::from_center(cx, cz, half, half)
    }

    #[test]
    fn a_wall_between_two_points_blocks_the_line() {
        let arena = Arena {
            solids: vec![box_at(5.0, 0.0, 1.0)],
            ..Arena::default()
        };
        assert!(
            !arena.line_of_sight((0.0, 0.0), (10.0, 0.0)),
            "straight through it"
        );
        assert!(
            arena.line_of_sight((0.0, 0.0), (3.0, 0.0)),
            "stopping short of it"
        );
        assert!(
            arena.line_of_sight((0.0, 5.0), (10.0, 5.0)),
            "passing above it"
        );
        assert!(
            arena.line_of_sight((0.0, 0.0), (0.0, 10.0)),
            "perpendicular to it"
        );
        // Standing in the doorway: the box starts at x=4, so a shot from 4.5
        // to 10 begins inside it and is blocked.
        assert!(!arena.line_of_sight((4.5, 0.0), (10.0, 0.0)));
    }

    #[test]
    fn an_empty_arena_never_blocks_anything() {
        let empty = Arena::default();
        assert!(empty.line_of_sight((0.0, 0.0), (40.0, 40.0)));
        assert!(
            empty.line_of_sight((0.0, 0.0), (0.0, 0.0)),
            "a point sees itself"
        );
        assert!(empty.line_of_sight((-20.0, 3.0), (20.0, -3.0)));
    }

    #[test]
    fn the_line_only_counts_solids_before_the_target() {
        let arena = Arena {
            solids: vec![box_at(20.0, 0.0, 1.0)],
            ..Arena::default()
        };
        assert!(
            arena.line_of_sight((0.0, 0.0), (10.0, 0.0)),
            "a wall behind the target does not block the shot"
        );
        assert!(!arena.line_of_sight((0.0, 0.0), (30.0, 0.0)));
    }

    #[test]
    fn agents_hold_fire_when_the_line_is_blocked() {
        let me = Uuid::new_v4();
        let foe = Uuid::new_v4();
        let mut snap = Snapshot {
            team_scores: None,
            flags: None,
            capture_scores: None,
            capture_limit: None,
            tick: 0,
            players: vec![],
            round_state: Some("Active".to_string()),
            round_time_left: Some(60),
            frag_limit: Some(10),
            shot_results: Vec::new(),
            projectiles: Vec::new(),
            grenades: Vec::new(),
            explosions: Vec::new(),
            mode_name: "Contested Frequency".to_string(),
            playlist: "Arena Duel".to_string(),
            pressure: None,
            host_line: String::new(),
            mvp: None,
            mvp_frags: None,
            pickups: Vec::new(),
            map_id: 1,
            map_name: "Arena Duel".to_string(),
            episode_id: None,
            episode_title: None,
            episode_objective: None,
            episode_progress: None,
            episode_phase: None,
            jammer_dish: None,
            sabotage: None,
        };
        let mk = |id: Uuid, x: f32| fragr_server::protocol::PlayerState {
            collidable: true,
            body: None,
            golden: false,
            lives: None,
            team: None,
            campaign: None,
            pitch: 0.0,
            id,
            name: format!("p{x}"),
            x,
            y: fragr_server::sim::PLAYER_FLOOR_Y,
            z: 0.0,
            yaw: 0.0,
            hp: 100,
            armor: 0,
            just_fired: false,
            behavior: None,
            score: 0,
            weapon: "flechette".to_string(),
        };
        snap.players = vec![mk(me, 0.0), mk(foe, 10.0)];

        let clear = Arena::default();
        let blocked = Arena {
            solids: vec![box_at(5.0, 0.0, 1.0)],
            ..Arena::default()
        };
        assert!(reflex_action(me, &snap, &clear).fire, "clear line: shoot");
        assert!(
            !reflex_action(me, &snap, &blocked).fire,
            "wall in the way: hold"
        );
        assert!(planner_action(me, &snap, &clear).fire);
        assert!(!planner_action(me, &snap, &blocked).fire);
        // Holding fire must not mean standing still. An agent that cannot see
        // its target moves to clear the corner, which is both better play and
        // the reason the harness does not flag it as stuck.
        let action = reflex_action(me, &snap, &blocked);
        assert_eq!(action.look_at.as_ref().unwrap().player_id, Some(foe));
        assert!(action.forward, "blind: close in rather than stand");
        let action = planner_action(me, &snap, &blocked);
        assert!(
            action.forward || action.left || action.right,
            "blind: move to find a line, got {action:?}"
        );
        // And once the line is clear it settles back into its band.
        let holding = planner_action(me, &snap, &clear);
        assert!(!holding.forward, "ten units is the flechette band");
        assert!(holding.left || holding.right);
        for player in &mut snap.players {
            player.y = fragr_server::sim::PLAYER_FLOOR_Y + 5.0;
        }
        assert!(
            reflex_action(me, &snap, &blocked).fire,
            "both fighters see over the wall"
        );
        assert!(planner_action(me, &snap, &blocked).fire);
        snap.players[1].y = fragr_server::sim::PLAYER_FLOOR_Y;
        assert!(
            !reflex_action(me, &snap, &blocked).fire,
            "descending aim meets the wall"
        );
        assert!(!planner_action(me, &snap, &blocked).fire);
    }
}

#[cfg(test)]
mod patrol_tests {
    use super::*;

    fn lone(id: Uuid) -> fragr_server::protocol::PlayerState {
        fragr_server::protocol::PlayerState {
            collidable: true,
            body: None,
            golden: false,
            lives: None,
            team: None,
            campaign: None,
            pitch: 0.0,
            id,
            name: "lone".to_string(),
            x: 0.0,
            y: fragr_server::sim::PLAYER_FLOOR_Y,
            z: 0.0,
            yaw: 0.0,
            hp: 100,
            armor: 0,
            just_fired: false,
            behavior: None,
            score: 0,
            weapon: "Flechette".to_string(),
        }
    }

    #[test]
    fn a_patrol_always_moves_and_aims_inside_the_arena() {
        let arena = Arena::default();
        let me = lone(Uuid::new_v4());
        for tick in (0..600).step_by(7) {
            let action = patrol_action(&me, tick, &arena);
            assert!(action.forward, "a patrol never stands still");
            let aim = action.look_at.expect("it aims somewhere");
            let (x, z) = (aim.x.unwrap(), aim.z.unwrap());
            assert!(
                x.abs() <= arena.half_extent && z.abs() <= arena.half_extent,
                "aimed off the map at tick {tick}: ({x}, {z})"
            );
        }
    }

    #[test]
    fn the_sweep_actually_sweeps() {
        let arena = Arena::default();
        let me = lone(Uuid::new_v4());
        let first = patrol_action(&me, 0, &arena).look_at.unwrap();
        let later = patrol_action(&me, 60, &arena).look_at.unwrap();
        let moved = (first.x.unwrap() - later.x.unwrap()).abs()
            + (first.z.unwrap() - later.z.unwrap()).abs();
        assert!(
            moved > 1.0,
            "three seconds should change where it is headed"
        );
    }

    #[test]
    fn two_fighters_do_not_walk_the_same_circle() {
        let arena = Arena::default();
        let a = patrol_action(&lone(Uuid::from_u128(1)), 0, &arena)
            .look_at
            .unwrap();
        let b = patrol_action(&lone(Uuid::from_u128(200)), 0, &arena)
            .look_at
            .unwrap();
        let apart = (a.x.unwrap() - b.x.unwrap()).abs() + (a.z.unwrap() - b.z.unwrap()).abs();
        assert!(
            apart > 0.5,
            "two agents alone should search different ground"
        );
    }
}

#[cfg(test)]
mod spawn_death_threshold_tests {
    use super::*;

    fn report_with(spawn_deaths: u64, frags: u64) -> Report {
        Report {
            rounds_completed: 1,
            agents: 4,
            frags,
            frags_per_minute: 20.0,
            spawn_deaths,
            ..Report::default()
        }
    }

    fn complains(spawn_deaths: u64, frags: u64) -> bool {
        check_thresholds(&report_with(spawn_deaths, frags))
            .iter()
            .any(|p| p.contains("spawn deaths"))
    }

    #[test]
    fn a_small_sample_that_landed_badly_is_not_a_failure() {
        // The run that failed CI: two of ten reads as twenty percent, but ten
        // frags cannot tell twenty percent from five.
        assert!(!complains(2, 10), "two of ten is not evidence of a problem");
        assert!(!complains(1, 10));
        assert!(!complains(0, 10));
    }

    #[test]
    fn a_rate_that_holds_up_still_fails() {
        assert!(
            complains(20, 100),
            "twenty percent over a hundred frags is real"
        );
        assert!(complains(40, 200));
    }

    #[test]
    fn spawn_camping_fails_even_on_a_short_run() {
        // Eight of ten is not a sampling accident at any sample size.
        assert!(complains(8, 10));
    }

    #[test]
    fn a_clean_run_never_complains() {
        assert!(!complains(0, 200));
        assert!(!complains(0, 0), "no frags is no rate");
    }
}

#[cfg(test)]
mod opening_spawn_death_tests {
    use super::*;

    fn report_with(opening: u64, rounds: u32) -> Report {
        Report {
            rounds_completed: rounds,
            agents: 6,
            frags: 30,
            frags_per_minute: 20.0,
            spawn_deaths: opening,
            opening_spawn_deaths: opening,
            ..Report::default()
        }
    }

    fn complains(opening: u64, rounds: u32) -> bool {
        check_thresholds(&report_with(opening, rounds))
            .iter()
            .any(|p| p.contains("opening spawn deaths"))
    }

    #[test]
    fn the_recorded_opening_gap_fails() {
        // Directive 17, Sector 9 and Reclamation Gulch lost two to four
        // fighters inside the window of the round opening before the fix, and
        // three of thirty frags still passes the rate ceiling.
        assert!(complains(2, 1));
        assert!(complains(3, 1));
        assert!(complains(3, 2));
    }

    #[test]
    fn one_walk_into_a_lane_per_round_is_tolerated() {
        assert!(!complains(0, 1));
        assert!(!complains(1, 1));
        assert!(!complains(2, 2));
        assert!(!complains(1, 0), "an unfinished round still gets one");
    }
}

#[cfg(test)]
mod rule_checks {
    use super::*;
    use fragr_server::protocol::{GameMode, MatchRules, Mutator};

    fn rules(mode: GameMode, mutators: &[Mutator], friendly_fire: bool) -> MatchRules {
        fragr_server::rules::RuleSet::new(mode, mutators, friendly_fire)
            .unwrap()
            .wire()
    }

    fn report(
        rules: MatchRules,
        sides: &[(&str, u64)],
        weapons: &[&str],
        team_kills: u64,
    ) -> Report {
        let mut report = Report {
            rules: Some(rules),
            sides: sides.iter().map(|(k, v)| (k.to_string(), *v)).collect(),
            team_kills,
            ..Report::default()
        };
        for weapon in weapons {
            report
                .combat
                .by_weapon
                .insert(weapon.to_string(), WeaponReport::default());
        }
        report
    }

    #[test]
    fn a_team_round_needs_both_sides_and_no_team_kills() {
        let tdm = rules(GameMode::Tdm, &[], false);
        assert!(check_rules(&report(
            tdm.clone(),
            &[("union", 2), ("coalition", 2)],
            &["Rail"],
            0
        ))
        .is_empty());
        let problems = check_rules(&report(
            tdm.clone(),
            &[("coalition", 3), ("none", 1)],
            &[],
            2,
        ));
        assert_eq!(problems.len(), 3, "{problems:?}");
        let ff = rules(GameMode::Tdm, &[], true);
        assert!(check_rules(&report(ff, &[("union", 1), ("coalition", 1)], &[], 2)).is_empty());
        assert!(check_rules(&Report::default()).is_empty());
    }

    #[test]
    fn a_weapon_only_round_fires_one_weapon() {
        let rail = rules(GameMode::Ffa, &[Mutator::RailOnly], false);
        assert!(check_rules(&report(rail.clone(), &[("none", 4)], &["Rail"], 0)).is_empty());
        let problems = check_rules(&report(rail, &[("none", 4)], &["Rail", "Flechette"], 0));
        assert_eq!(problems, ["Flechette fired under Free-for-all: Rail Only"]);
    }

    #[test]
    fn the_report_counts_sides_reactions_and_team_kills() {
        let mut obs = Observation {
            rules: Some(rules(GameMode::Tdm, &[], false)),
            ..Observation::default()
        };
        obs.sides
            .insert("a".into(), Some(fragr_server::protocol::Team::Union));
        obs.sides
            .insert("b".into(), Some(fragr_server::protocol::Team::Coalition));
        obs.sides.insert("c".into(), None);
        obs.events.push(TimedEvent {
            tick: 5,
            event: GameEvent::HostReaction {
                kind: fragr_server::protocol::HostReactionKind::FirstBlood,
                variant: 0,
                player: Some("a".into()),
                other: Some("b".into()),
                team: None,
            },
        });
        obs.events.push(TimedEvent {
            tick: 6,
            event: GameEvent::Frag {
                killer: "a".into(),
                victim: "d".into(),
                killer_score: 1,
                killer_team: Some(fragr_server::protocol::Team::Union),
                victim_team: Some(fragr_server::protocol::Team::Union),
            },
        });
        let report = compute_report(&obs, 3);
        assert_eq!(report.host_reactions, 1);
        assert_eq!(report.team_kills, 1);
        assert_eq!(report.sides.get("none"), Some(&1));
        assert_eq!(report.sides.get("union"), Some(&1));
        assert_eq!(report.rules.as_ref().unwrap().mode, GameMode::Tdm);
    }
}
