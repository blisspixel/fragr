#[cfg(test)]
mod enclosed_tests;
use crate::movement::{EYE_HEIGHT, STEP_UP};
use crate::protocol::{
    boss_down_host_line, boss_host_line, boss_round_wipe_host_line, compliance_host_line,
    default_host_line, default_mode_name, default_playlist, empty_mvp_host_line,
    episode0_host_line_auditor, episode0_host_line_cold_open, episode0_host_line_fail,
    episode0_host_line_jammer, episode0_host_line_nods_tick, episode0_host_line_win,
    episode0_objective_chip, episode0_unlock_teaser, killstreak_host_line, mvp_host_line,
    roster_host_line, round_open_host_line, rule_bot_taunt_line, warmup_host_line, Action,
    BotTauntKind, GameEvent, PelletTrace, PickupState, PlayerScore, PlayerState, Role,
    ServerMessage, ShotImpact, ShotResult, ShotTrace, Snapshot, WeaponType, AUDITOR_NAME,
    BOSS_NAME, EPISODE_ID_EP0, EPISODE_MAP_LARAK_LOT, EPISODE_TITLE_EP0, MODE_NAME, PLAYLIST_NAME,
};
use std::collections::HashMap;
use std::f32::consts::PI;
use uuid::Uuid;

const MOVE_SPEED: f32 = crate::movement::TOP_SPEED;
/// The y a standing fighter reports when it is on the base floor. It is a
/// reference point rather than the floor: the client hangs the body below it
/// and the eye just above it. On a deck the fighter reports this plus the
/// deck's height, so `y - PLAYER_FLOOR_Y` is always the height of its feet.
pub const PLAYER_FLOOR_Y: f32 = 1.5;
const TURN_SPEED: f32 = 2.0;
pub const PLAYER_RADIUS: f32 = crate::movement::RADIUS;

/// One resolved ray. A scatter blast resolves several from the same origin.
struct ResolvedPellet {
    target: Option<usize>,
    distance: f32,
    end: [f32; 3],
    impact: ShotImpact,
}

struct ResolvedShot {
    weapon: WeaponType,
    origin: [f32; 3],
    pellets: Vec<ResolvedPellet>,
}
const RESPAWN_DELAY_TICKS: u32 = 60;
/// Ticks after a respawn during which a fighter cannot be hit (one second).
pub const SPAWN_SHIELD_TICKS: u32 = 20;
const HITSCAN_RANGE: f32 = 100.0;
/// The first seconds after a spawn that placement is judged over. The shield
/// covers the first; the playtest counts a death inside two as a spawn death.
const SPAWN_SAFE_SECONDS: f32 = 2.0;
/// How far a spawn point must be screened from a living opponent. No weapon
/// reaches beyond the rail (60 m), and an opponent just outside it walks
/// another ten metres inside the safe window. A longer lane cannot hurt the
/// arriving fighter; counting it would crowd out a slot that is only exposed to
/// someone too far away to shoot.
pub(crate) const SPAWN_THREAT_RANGE: f32 = 60.0 + crate::movement::TOP_SPEED * SPAWN_SAFE_SECONDS;
pub(crate) const PLAYER_MAX_HP: i32 = 100;
/// Max Unicode scalars in a speak/taunt line (after trim).
pub const SPEAK_MAX_CHARS: usize = 80;
/// Min ticks between successful speaks for one player (~3s at 20 Hz).
pub const SPEAK_COOLDOWN_TICKS: u64 = 60;
/// Chance (percent) a rule-bot killer speaks after a frag (not every scrap).
const RULE_BOT_TAUNT_FRAG_PCT: u64 = 35;
/// Chance a rule-bot victim speaks after death.
const RULE_BOT_TAUNT_DEATH_PCT: u64 = 25;
/// Chance a rule-bot speaks on killstreak tier 2/3/5.
const RULE_BOT_TAUNT_STREAK_PCT: u64 = 55;
/// Chance the Warmup cadence speaker actually talks.
const RULE_BOT_TAUNT_WARMUP_PCT: u64 = 40;
/// Warmup ticks between attempts to pick one rule bot to speak.
const RULE_BOT_WARMUP_TAUNT_EVERY: u32 = 20;
/// Continuance Compliance Drone hit points (tankier than scrap fighters).
pub const BOSS_MAX_HP: i32 = 200;
/// Touch radius for mid-map pickup pads.
pub const PICKUP_CLAIM_RADIUS: f32 = 1.75;
/// How far above or below a pad's own floor a fighter may be and still claim
/// it. Generous enough to take a pad while jumping over it, tight enough that
/// a pad on a walkway is not free to whoever stands underneath.
pub const PICKUP_CLAIM_HEIGHT: f32 = 2.0;
/// Ticks until a claimed weapon pad respawns (~12s at 20 Hz).
pub const PICKUP_RESPAWN_TICKS: u32 = 20 * 12;
/// Ticks until a claimed health/armor pad respawns (~15s at 20 Hz).
pub const HEALTH_PICKUP_RESPAWN_TICKS: u32 = 20 * 15;
/// Max scrap armor (simple absorb-before-HP).
pub const PLAYER_MAX_ARMOR: i32 = 100;
/// Health pad heal amount (capped at PLAYER_MAX_HP).
pub const HEALTH_PAD_AMOUNT: i32 = 40;
/// Armor scrap grant amount (capped at PLAYER_MAX_ARMOR).
pub const ARMOR_PAD_AMOUNT: i32 = 25;

/// Solo Broadcast Episode 0: NODS frags the meatbag must clear.
pub const EP0_NODS_GOAL: u32 = 5;
/// Soft-touch radius for the jammer dish (arena center).
/// Matches client ground ring (`RING_RADIUS` 6.2) plus player radius slack so
/// standing on the visible pad seizes; a 3.0 hub soft-locked first Calibration.
pub const EP0_JAMMER_RADIUS: f32 = 6.5;

/// The Contested Frequency map roster. Ids are stable and on the wire; the
/// layouts themselves live in `maps.rs`, which is the only place in the server
/// that knows what a map looks like.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum MapKind {
    #[default]
    ArenaDuel = 1,
    ComplianceYard = 2,
    Directive17 = 3,
    Sector9 = 4,
    ReclamationGulch = 5,
    TripointWorks = 6,
}

impl MapKind {
    /// The roster in rotation order.
    pub const ALL: [MapKind; 6] = [
        MapKind::ArenaDuel,
        MapKind::ComplianceYard,
        MapKind::Directive17,
        MapKind::Sector9,
        MapKind::ReclamationGulch,
        MapKind::TripointWorks,
    ];

    pub fn from_cli(raw: &str) -> Option<Self> {
        match raw.trim().to_ascii_lowercase().replace('_', "-").as_str() {
            "1" | "arena" | "duel" | "arena-duel" => Some(Self::ArenaDuel),
            "2" | "compliance" | "yard" | "compliance-yard" => Some(Self::ComplianceYard),
            "3" | "directive" | "substation" | "directive-17" | "directive-17-substation" => {
                Some(Self::Directive17)
            }
            "4" | "sector9" | "sector-9" | "transit" | "sector-9-transit-hall" => {
                Some(Self::Sector9)
            }
            "5" | "gulch" | "reclamation" | "reclamation-gulch" => Some(Self::ReclamationGulch),
            "6" | "tripoint" | "works" | "tripoint-works" => Some(Self::TripointWorks),
            _ => None,
        }
    }

    pub fn id(self) -> u32 {
        self as u32
    }

    /// Position in `ALL`, which is how `maps.rs` indexes its built layouts.
    pub fn index(self) -> usize {
        self as usize - 1
    }

    pub fn name(self) -> &'static str {
        match self {
            Self::ArenaDuel => "Arena Duel",
            Self::ComplianceYard => "Compliance Yard",
            Self::Directive17 => "Directive 17 Substation",
            Self::Sector9 => "Sector 9 Transit Hall",
            Self::ReclamationGulch => "Reclamation Gulch",
            Self::TripointWorks => "Tripoint Works",
        }
    }

    /// One line on what the map is for, so a picker is not six names.
    pub fn blurb(self) -> &'static str {
        match self {
            Self::ArenaDuel => "Assembly floor. A hub inside a gantry ring, rail on the walkway.",
            Self::ComplianceYard => "Records block. Nine rooms, no long shot anywhere.",
            Self::Directive17 => "Transformer bowl. Four terraces down to a pit you can see into.",
            Self::Sector9 => "Freight interchange. Two halls, one door between them.",
            Self::ReclamationGulch => "Recovery site. Two compounds, open ground, two ridges.",
            Self::TripointWorks => "Three compounds, three capture yards, a plaza nobody holds.",
        }
    }

    pub fn next(self) -> Self {
        Self::ALL[(self.index() + 1) % Self::ALL.len()]
    }

    /// Radius of the ring fighters spawn on.
    pub fn spawn_radius(self) -> f32 {
        crate::maps::def(self).spawn_radius
    }

    /// The map's solids in the shared wire shape, for the client and for
    /// agents that need to tell a clear shot from a wall.
    pub fn solids(self) -> Vec<crate::movement::Solid> {
        crate::maps::arena(self).solids.clone()
    }

    /// Half width of the playable square, centred on the origin.
    pub fn half_extent(self) -> f32 {
        crate::maps::def(self).half_extent
    }

    #[cfg(test)]
    pub(crate) fn obstacles(self) -> &'static [crate::movement::Solid] {
        &crate::maps::def(self).solids
    }

    pub(crate) fn pickups(self) -> Vec<ArenaPickup> {
        crate::maps::def(self).pickups.clone()
    }
}
/// Test-only view of the solid test, so a test can find clear ground instead
/// of hard-coding coordinates that move when a map is laid out again. Asks
/// the question a fighter standing on the base floor would ask.
#[cfg(test)]
pub fn circle_blocked_for_test(map: MapKind, x: f32, z: f32) -> bool {
    circle_blocked(map, x, z, STEP_UP)
}

/// Blocked for a fighter that can climb to `climb`. A solid whose top is at or
/// below that is walked onto rather than walked into, which is what makes a
/// staircase a staircase instead of a row of small walls.
fn circle_blocked(map: MapKind, x: f32, z: f32, climb: f32) -> bool {
    crate::maps::arena(map).blocked_at(x, z, climb)
}

/// Test-only view of the floor query, so a test can ask the map how high the
/// ground is instead of writing a number down.
#[cfg(test)]
pub fn floor_height_for_test(map: MapKind, x: f32, z: f32, ceiling: f32) -> f32 {
    floor_height(map, x, z, ceiling)
}

/// The height of the surface under `(x, z)` for a fighter that can reach
/// `ceiling`: a deck top, or the base floor when nothing qualifies.
fn floor_height(map: MapKind, x: f32, z: f32, ceiling: f32) -> f32 {
    crate::maps::support_height(map, x, z, ceiling)
}

/// A point on the spawn ring that is not inside a solid, and the height of the
/// ground there. The ring is sampled round from the requested angle; when
/// every sample is blocked the origin is the fallback, which is why the origin
/// being walkable is a rule the map validator enforces rather than a habit.
pub(crate) fn spawn_on_ring(map: MapKind, angle: f32) -> (f32, f32, f32, f32) {
    let spawn_radius = map.spawn_radius();
    let mut a = angle;
    for _ in 0..16 {
        let x = a.cos() * spawn_radius;
        let z = a.sin() * spawn_radius;
        // A fighter is put down on top of whatever is there, so the question
        // is whether anything more than a step above that crowds the point.
        // Asking whether it is blocked from the base floor would reject every
        // point on a map whose spawn rim is itself a terrace.
        let floor = floor_height(map, x, z, f32::INFINITY);
        if !circle_blocked(map, x, z, floor + STEP_UP) {
            return (x, z, a + PI, floor);
        }
        a += PI / 8.0;
    }
    (0.0, 0.0, angle + PI, 0.0)
}

/// Result of attempting an off-tick speak.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SpeakOutcome {
    Sent,
    RateLimited,
    Rejected,
}

/// Solo Broadcast Episode 0 phase (Calibration on Larak Lot).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum EpisodePhase {
    Nods,
    Jammer,
    Auditor,
    Won,
    Failed,
}

impl EpisodePhase {
    pub fn wire(self) -> &'static str {
        match self {
            Self::Nods => "nods",
            Self::Jammer => "jammer",
            Self::Auditor => "auditor",
            Self::Won => "won",
            Self::Failed => "failed",
        }
    }
}

/// Contested Frequency Solo Broadcast Episode 0 runtime (off = MP unchanged).
#[derive(Debug, Clone)]
pub struct SoloBroadcastEp0 {
    pub enabled: bool,
    pub started: bool,
    pub nods_cleared: u32,
    pub nods_goal: u32,
    pub jammer_seized: bool,
    pub phase: EpisodePhase,
    /// Sticky Host line override while Solo Broadcast is live.
    pub host_line: Option<String>,
}

impl Default for SoloBroadcastEp0 {
    fn default() -> Self {
        Self {
            enabled: false,
            started: false,
            nods_cleared: 0,
            nods_goal: EP0_NODS_GOAL,
            jammer_seized: false,
            phase: EpisodePhase::Nods,
            host_line: None,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RoundState {
    Warmup,
    Active,
    Ended,
}

#[derive(Debug, Clone)]
pub struct MatchConfig {
    pub frag_limit: Option<u32>,
    pub time_limit_ticks: Option<u32>,
    pub warmup_ticks: u32,
    pub end_delay_ticks: u32,
    /// Tick into Active when Continuance compliance ping fires once (None = off).
    pub compliance_ping_ticks: Option<u32>,
    /// How long approved-lanes slow lasts after the ping.
    pub compliance_duration_ticks: u32,
    /// Tick into Active when Compliance Drone spawns once (None = off).
    pub boss_spawn_ticks: Option<u32>,
}

impl Default for MatchConfig {
    fn default() -> Self {
        Self {
            frag_limit: Some(10),
            time_limit_ticks: Some(20 * 60 * 3),
            warmup_ticks: 20 * 2,
            end_delay_ticks: 20 * 8,
            // ~15s into Active so one round of play feels the pressure beat.
            compliance_ping_ticks: Some(20 * 15),
            compliance_duration_ticks: 20 * 6,
            // ~20s into Active: Continuance escalates with a killable drone.
            boss_spawn_ticks: Some(20 * 20),
        }
    }
}

/// What a mid-map pad grants on claim.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PickupKind {
    Ammo {
        pool: crate::protocol::AmmoPool,
        rounds: u16,
    },
    Weapon(WeaponType),
    Health,
    Armor,
}

impl PickupKind {
    pub fn wire_name(self) -> &'static str {
        match self {
            PickupKind::Ammo { .. } => "ammo",
            PickupKind::Weapon(_) => "weapon",
            PickupKind::Health => "health",
            PickupKind::Armor => "armor",
        }
    }

    pub fn weapon(self) -> Option<WeaponType> {
        match self {
            PickupKind::Weapon(w) => Some(w),
            _ => None,
        }
    }
}

/// Authoritative mid-map pad (weapon / health / armor; Quake chase energy).
#[derive(Debug, Clone)]
pub struct ArenaPickup {
    pub claim: crate::protocol::SupplyClaim,
    pub id: String,
    pub kind: PickupKind,
    pub amount: i32,
    pub x: f32,
    /// Where the pad is drawn: a little above the surface it lies on.
    pub y: f32,
    pub z: f32,
    /// The surface the pad lies on. A rail on a walkway cannot be claimed
    /// from the ground underneath it, which is what makes "the best thing in
    /// the worst place" a position worth taking rather than a coordinate.
    pub floor: f32,
    pub available: bool,
    pub respawn_timer: Option<u32>,
    /// An authored secret: optional, found by exploring, never required.
    pub secret: bool,
}

impl ArenaPickup {
    fn to_state(&self) -> PickupState {
        let weapon = self
            .kind
            .weapon()
            .map(|w| w.name().to_string())
            .unwrap_or_default();
        let amount = match self.kind {
            PickupKind::Weapon(_) => None,
            PickupKind::Health | PickupKind::Armor => Some(self.amount),
            PickupKind::Ammo { rounds, .. } => Some(i32::from(rounds)),
        };
        PickupState {
            claim: self.claim,
            pool: match self.kind {
                PickupKind::Ammo { pool, .. } => Some(pool),
                _ => None,
            },
            id: self.id.clone(),
            kind: self.kind.wire_name().to_string(),
            weapon,
            amount,
            x: self.x,
            y: self.y,
            z: self.z,
            available: self.available,
            respawn_in: if self.available {
                None
            } else {
                self.respawn_timer
            },
        }
    }

    fn respawn_ticks(&self) -> u32 {
        match self.kind {
            PickupKind::Ammo { .. } => 200,
            PickupKind::Weapon(_) => PICKUP_RESPAWN_TICKS,
            PickupKind::Health | PickupKind::Armor => HEALTH_PICKUP_RESPAWN_TICKS,
        }
    }
}

pub struct GameState {
    pub(crate) statistics_session: Uuid,
    pub(crate) statistics_round_started: u64,
    pub(crate) encounters: crate::encounters::Encounters,
    pub(crate) mission: Option<crate::mission::MissionRun>,
    /// Offline recordings opt into stable entity identities. Live sessions keep
    /// UUIDv4; identity allocation must not consume the gameplay random stream.
    replay_id_counter: Option<u128>,
    /// Deterministic random state. Seeded from `seed()`; every draw in the sim
    /// goes through it, so a run can be reproduced and two runs compared.
    /// The generator lives here rather than in a crate so the value stream
    /// cannot change under a dependency upgrade.
    pub rng_state: u64,
    pub tick: u64,
    pub players: Vec<Player>,
    pub events: Vec<GameEvent>,
    pub bots: Vec<BotController>,
    pub scores: HashMap<Uuid, u32>,
    pub round_state: RoundState,
    pub round_ticks: u32,
    pub round_number: u32,
    pub config: MatchConfig,
    /// Cleared each tick; filled when weapons fire this tick.
    pub shot_results: Vec<ShotResult>,
    /// Remaining ticks of Continuance compliance slow (0 = none).
    pub compliance_ticks_left: u32,
    /// Whether this Active round already fired its compliance ping.
    pub compliance_fired: bool,
    /// Living Compliance Drone player id (None if not spawned or already down).
    pub boss_id: Option<Uuid>,
    /// Whether this Active round already spawned its drone.
    pub boss_spawned: bool,
    /// Mid-map pads: weapons, health, armor (Solo Scrap + MP).
    pub pickups: Vec<ArenaPickup>,
    /// Sticky Host line while RoundState::Ended (MVP podium bumper for mid-join).
    pub ended_host_line: Option<String>,
    /// Sticky MVP name while Ended (structured mid-join rehydrate).
    pub ended_mvp: Option<String>,
    /// Sticky MVP frag count while Ended.
    pub ended_mvp_frags: Option<u32>,
    /// Sticky Warmup / mid-join Host line naming dialed-in rule bots (None = default league line).
    pub roster_host_line: Option<String>,
    /// Dialed-in rule-bot callsigns for Warmup / RoundStart Host drama.
    pub roster_names: Vec<String>,
    /// Active Contested Frequency scrap layout.
    pub map: crate::maps::RuntimeMap,
    /// When true, alternate map each start_round.
    pub map_rotate: bool,
    /// Fighters that just respawned and their remaining shield ticks.
    pub spawn_shields: HashMap<Uuid, u32>,
    /// Solo Broadcast Episode 0 (Calibration / Larak Lot). Off for MP.
    pub solo_broadcast: SoloBroadcastEp0,
}

pub struct Player {
    pub(crate) statistics: crate::statistics::CombatLedger,
    pub campaign: Option<crate::protocol::CampaignActor>,
    pub id: Uuid,
    pub name: String,
    pub x: f32,
    pub y: f32,
    pub z: f32,
    pub yaw: f32,
    pub pitch: f32,
    /// Vertical speed. Positive is upward, zero while standing.
    pub vy: f32,
    pub hp: i32,
    /// Scrap armor; absorbs damage before HP (0 on spawn/respawn).
    pub armor: i32,
    pub pending_action: Action,
    /// A press survives newer released input until one simulation tick observes it.
    jump_requested: bool,
    pub(crate) interaction_requested: bool,
    pub fire_cooldown: u32,
    pub respawn_timer: Option<u32>,
    pub just_fired: bool,
    pub role: Role,
    pub weapon: WeaponType,
    pub inventory: crate::inventory::Inventory,
    /// Tick of last successful speak (rate limit).
    pub last_speak_tick: Option<u64>,
    /// Continuance Compliance Drone (no respawn, distinct silhouette).
    pub is_boss: bool,
    /// Within-round killstreak (resets on death and round boundaries).
    pub killstreak: u32,
    /// Agent-set observe chip (never used for combat). Rule bots use BotController.
    pub display_behavior: Option<String>,
    /// Newest input sequence applied to this fighter, echoed in the Ack.
    pub last_input_seq: Option<u32>,
}

impl Player {
    pub(crate) fn clear_input(&mut self) {
        self.pending_action = Action::default();
        self.jump_requested = false;
        self.interaction_requested = false;
    }

    pub fn is_campaign_enemy(&self) -> bool {
        self.campaign
            .is_some_and(crate::protocol::CampaignActor::is_enemy)
    }

    fn at_spawn(
        id: Uuid,
        name: String,
        role: Role,
        (x, z, yaw, floor): (f32, f32, f32, f32),
        policy: crate::protocol::EquipmentPolicy,
    ) -> Self {
        Self {
            campaign: None,
            statistics: Default::default(),
            id,
            name,
            role,
            x,
            z,
            yaw,
            y: PLAYER_FLOOR_Y + floor,
            pitch: 0.0,
            vy: 0.0,
            hp: PLAYER_MAX_HP,
            armor: 0,
            pending_action: Action::default(),
            jump_requested: false,
            interaction_requested: false,
            fire_cooldown: 0,
            respawn_timer: None,
            just_fired: false,
            weapon: if policy == crate::protocol::EquipmentPolicy::Discovery {
                WeaponType::Fists
            } else {
                WeaponType::default()
            },
            inventory: crate::inventory::Inventory::new(policy),
            last_speak_tick: None,
            is_boss: false,
            killstreak: 0,
            display_behavior: None,
            last_input_seq: None,
        }
    }
}

impl GameState {
    pub(crate) fn use_replay_ids(&mut self) {
        assert!(
            self.players.is_empty(),
            "set replay identity policy before spawning"
        );
        self.replay_id_counter = Some(0);
        self.statistics_session = Uuid::nil();
    }

    pub(crate) fn new_entity_id(&mut self) -> Uuid {
        match self.replay_id_counter.as_mut() {
            Some(counter) => {
                *counter += 1;
                Uuid::from_u128(*counter)
            }
            None => Uuid::new_v4(),
        }
    }

    pub fn new() -> Self {
        Self::default()
    }

    /// Fix the random stream. Two states with the same seed that are given the
    /// same inputs produce the same match.
    pub fn seed(&mut self, seed: u64) {
        // Any non-zero state works; mixing keeps small seeds from starting cold.
        self.rng_state = seed ^ 0x9E37_79B9_7F4A_7C15;
        if self.rng_state == 0 {
            self.rng_state = 0x2545_F491_4F6C_DD1D;
        }
    }

    /// xorshift64star: one multiply and three shifts, a long period, and a
    /// value stream that belongs to this repository rather than to a crate.
    pub fn next_u64(&mut self) -> u64 {
        let mut x = self.rng_state;
        x ^= x >> 12;
        x ^= x << 25;
        x ^= x >> 27;
        self.rng_state = x;
        x.wrapping_mul(0x2545_F491_4F6C_DD1D)
    }

    /// A random number in `[0, 1)`, from the top 24 bits so it is uniform.
    pub fn next_f32(&mut self) -> f32 {
        ((self.next_u64() >> 40) as f32) / (1u32 << 24) as f32
    }

    pub fn with_map(map: MapKind, map_rotate: bool) -> Self {
        Self {
            map: crate::maps::RuntimeMap::BuiltIn(map),
            map_rotate,
            pickups: map.pickups(),
            ..Self::default()
        }
    }

    /// Authored missions and traversal have no arcade clock or escalation.
    pub fn with_authored_map(map: std::sync::Arc<crate::maps::AuthoredMap>) -> Self {
        let map = crate::maps::RuntimeMap::Authored(map);
        Self {
            mission: crate::mission::MissionRun::new(&map),
            pickups: map.pickups(),
            map,
            round_state: RoundState::Active,
            round_number: 1,
            config: MatchConfig {
                frag_limit: None,
                time_limit_ticks: None,
                boss_spawn_ticks: None,
                compliance_ping_ticks: None,
                ..Default::default()
            },
            ..Default::default()
        }
    }

    pub fn start_round(&mut self) {
        let previous_winner = if self.round_number > 0 {
            self.ranked_scores().first().map(|p| p.name.clone())
        } else {
            None
        };

        self.round_number += 1;
        self.statistics_round_started = self.tick;
        self.round_state = RoundState::Active;
        self.round_ticks = 0;
        self.scores.clear();
        self.compliance_fired = false;
        self.compliance_ticks_left = 0;
        self.clear_boss();
        if self.solo_broadcast.enabled {
            self.solo_broadcast.nods_cleared = 0;
            self.solo_broadcast.jammer_seized = false;
            self.solo_broadcast.phase = EpisodePhase::Nods;
            self.solo_broadcast.started = false;
            self.solo_broadcast.host_line = Some(episode0_host_line_cold_open());
            self.relabel_rule_bots_as_nods();
        }
        if self.map_rotate && self.round_number > 1 {
            if let crate::maps::RuntimeMap::BuiltIn(kind) = &self.map {
                self.map = crate::maps::RuntimeMap::BuiltIn(kind.next());
            }
            tracing::info!("Map rotate -> {} ({})", self.map.name(), self.map.id());
        }
        self.reset_pickups();
        self.ended_host_line = None;
        self.ended_mvp = None;
        self.ended_mvp_frags = None;

        for player in &mut self.players {
            self.scores.insert(player.id, 0);
            player.killstreak = 0;
            player.statistics.begin(self.tick);
        }

        let players: Vec<String> = self.players.iter().map(|p| p.name.clone()).collect();

        self.events.push(GameEvent::RoundStart {
            round_number: self.round_number,
            frag_limit: self.config.frag_limit,
            time_limit: self.config.time_limit_ticks.map(|t| t / 20),
            players,
            previous_winner,
            mode_name: default_mode_name(),
            playlist: default_playlist(),
            host_line: if self.solo_broadcast.enabled {
                episode0_host_line_cold_open()
            } else {
                round_open_host_line(self.map.name(), &self.roster_names)
            },
        });

        tracing::info!(
            "Round {} started (frag_limit: {:?}, time_limit: {:?}s)",
            self.round_number,
            self.config.frag_limit,
            self.config.time_limit_ticks.map(|t| t / 20)
        );
    }

    fn ranked_scores(&self) -> Vec<PlayerScore> {
        let mut final_scores: Vec<PlayerScore> = self
            .scores
            .iter()
            .filter_map(|(id, &score)| {
                self.players
                    .iter()
                    .find(|p| p.id == *id)
                    .map(|p| PlayerScore {
                        name: p.name.clone(),
                        score,
                    })
            })
            .collect();

        // HashMap iteration must not pick the podium or order tied scores.
        // Alphabetical callsign order is the stable presentation tiebreak.
        final_scores.sort_by(|a, b| b.score.cmp(&a.score).then_with(|| a.name.cmp(&b.name)));
        final_scores
    }

    pub fn end_round(&mut self, reason: String) {
        // Dismiss a live drone before podium so Ended mid-join is not soft-prisoned
        // with compliance_drone pressure and MCP gets boss_down (killer null).
        self.wipe_boss_for_round_end();
        let final_scores = self.ranked_scores();
        let (winner, winner_score) = final_scores
            .first()
            .map(|score| (score.name.clone(), score.score))
            .unzip();

        // MVP is top score / frags (same selection as winner).
        let mvp = winner.clone();
        let mvp_frags = winner_score;
        let host_line = match (&mvp, mvp_frags) {
            (Some(name), Some(frags)) => mvp_host_line(name, frags),
            _ => empty_mvp_host_line(),
        };
        self.ended_host_line = Some(host_line.clone());
        self.ended_mvp = mvp.clone();
        self.ended_mvp_frags = mvp_frags;

        self.round_state = RoundState::Ended;
        self.round_ticks = 0;
        for player in &mut self.players {
            player.killstreak = 0;
        }

        self.events.push(GameEvent::RoundEnd {
            winner: winner.clone(),
            reason: reason.clone(),
            final_scores,
            winner_score,
            mvp: mvp.clone(),
            mvp_frags,
            host_line: host_line.clone(),
        });

        tracing::info!(
            "Round {} ended: {} (mvp: {:?}, frags: {:?})",
            self.round_number,
            reason,
            mvp,
            mvp_frags
        );
    }

    pub fn add_player(&mut self, id: Uuid, name: String, role: Role) {
        if !self.admit_campaign_owner(id) {
            return;
        }
        let mut angle = (self.players.len() as f32) * (2.0 * PI / 8.0);
        // Warmup is placement for the opening fight. It needs the same cover
        // and clearance policy as a live join, even before weapons activate.
        if self
            .players
            .iter()
            .any(|other| other.respawn_timer.is_none())
        {
            angle = self.select_spawn_angle(id);
        }
        let mut player = Player::at_spawn(
            id,
            name,
            role,
            self.map.spawn(angle),
            self.map.equipment_policy(),
        );
        if self.map.is_campaign() {
            player.campaign = Some(crate::protocol::CampaignActor::Participant {});
        }
        self.restore_campaign_owner(&mut player)
            .expect("validated campaign owner equipment must restore");
        player.statistics.begin(self.tick);
        self.players.push(player);

        self.scores.entry(id).or_insert(0);
    }

    pub(crate) fn spawn_campaign_enemy(&mut self, placement: &crate::maps::EnemyPlacement) -> Uuid {
        use crate::protocol::{CampaignActor, EnemyPhase, EquipmentPolicy};
        let id = self.new_entity_id();
        let [x, floor, z] = placement.feet;
        let mut player = Player::at_spawn(
            id,
            placement.id.clone(),
            Role::Agent,
            (x, z, placement.yaw, floor),
            EquipmentPolicy::Discovery,
        );
        let (hp, weapon) = crate::encounters::enemy_body(placement.kind);
        player.hp = hp;
        player.weapon = weapon;
        player.inventory.grant_weapon(weapon);
        player.campaign = Some(CampaignActor::Union {
            kind: placement.kind,
            phase: EnemyPhase::Idle,
            phase_started: self.tick,
            phase_ends: self.tick,
        });
        self.players.push(player);
        id
    }

    pub fn remove_player(&mut self, id: Uuid) {
        if let Some(player) = self.players.iter().find(|p| p.id == id) {
            if player.role == Role::Human {
                tracing::info!("Human player left, bots keep fighting");
            }
        }
        self.players.retain(|p| p.id != id);
        self.scores.remove(&id);
        self.refresh_mission_readiness();
        self.update_encounters();
    }

    pub fn set_action(&mut self, id: Uuid, mut action: Action) {
        if let Some(player) = self.players.iter_mut().find(|p| p.id == id) {
            if !crate::mission::actor_active(self.mission.as_ref(), player.id, player.campaign) {
                return;
            }
            // Continuous input takes the newest value. A discrete weapon choice
            // must survive later frames until the simulation consumes it.
            action.weapon_swap = action.weapon_swap.or(player.pending_action.weapon_swap);
            player.jump_requested |= action.jump;
            player.interaction_requested |= action.interact && !player.pending_action.interact;
            player.pending_action = action;
        }
    }

    /// Max Unicode scalars for an Agent display-behavior chip.
    pub const DISPLAY_BEHAVIOR_MAX_CHARS: usize = 32;

    /// Set observe-only behavior label for an Agent. Ignores humans, spectators,
    /// rule bots (players with a BotController), empty/overlong/control text.
    /// Never influences combat.
    pub fn set_display_behavior(&mut self, id: Uuid, raw: &str) -> bool {
        if self.bots.iter().any(|b| b.player_id == id) {
            return false;
        }
        let trimmed: String = raw
            .trim()
            .chars()
            .take(Self::DISPLAY_BEHAVIOR_MAX_CHARS + 1)
            .collect();
        if trimmed.is_empty() || trimmed.chars().count() > Self::DISPLAY_BEHAVIOR_MAX_CHARS {
            return false;
        }
        if trimmed.chars().any(|c| c.is_control()) {
            return false;
        }
        let Some(player) = self.players.iter_mut().find(|p| p.id == id) else {
            return false;
        };
        if player.role != Role::Agent {
            return false;
        }
        player.display_behavior = Some(trimmed);
        true
    }

    /// The arena's shape as a message.
    pub fn map_info(&self) -> ServerMessage {
        ServerMessage::MapInfo {
            geometry_version: crate::protocol::geometry_version(&self.map.arena().solids),
            presentation: self.map.presentation(),
            mission: self.map.mission().cloned(),
            m02_objectives: self
                .map
                .m02_objectives()
                .and_then(|objectives| u8::try_from(objectives.len()).ok()),
            map_id: self.map.id(),
            map_name: self.map.name().to_string(),
            half_extent: self.map.half_extent(),
            solids: self.map.solids(),
        }
    }

    /// One Ack per fighter whose client numbers its inputs. Built after a
    /// tick so the state it carries is the state that input produced.
    pub fn input_acks(&self) -> Vec<(Uuid, ServerMessage)> {
        self.players
            .iter()
            .filter(|p| p.role == Role::Human)
            .filter_map(|p| {
                p.last_input_seq.map(|seq| {
                    (
                        p.id,
                        ServerMessage::Ack {
                            seq,
                            tick: self.tick,
                            x: p.x,
                            z: p.z,
                            yaw: p.yaw,
                            pitch: p.pitch,
                        },
                    )
                })
            })
            .collect()
    }

    pub fn tick(&mut self, dt: f32) {
        self.tick += 1;
        self.shot_results.clear();
        self.spawn_shields.retain(|_, ticks| {
            *ticks = ticks.saturating_sub(1);
            *ticks > 0
        });
        // Do not clear events here. Join/leave are pushed from the net loop between
        // ticks; clearing would drop them before main broadcasts take_events().
        // take_events() in the game loop is the drain.

        match self.round_state {
            RoundState::Warmup => {
                self.round_ticks += 1;
                self.maybe_warmup_rule_bot_taunts();
                self.tick_solo_broadcast();
                if self.round_ticks >= self.config.warmup_ticks {
                    self.start_round();
                }
                return;
            }
            RoundState::Active => {
                self.round_ticks += 1;
                self.tick_solo_broadcast();

                if self.compliance_ticks_left > 0 {
                    self.compliance_ticks_left -= 1;
                }
                if !self.compliance_fired {
                    if let Some(at) = self.config.compliance_ping_ticks {
                        if self.round_ticks >= at {
                            self.fire_compliance_ping();
                        }
                    }
                }
                if !self.boss_spawned && !self.solo_broadcast.enabled {
                    if let Some(at) = self.config.boss_spawn_ticks {
                        if self.round_ticks >= at {
                            self.spawn_compliance_drone();
                        }
                    }
                }

                if let Some(time_limit) = self.config.time_limit_ticks {
                    if self.round_ticks >= time_limit {
                        if self.solo_broadcast.enabled {
                            self.fail_episode("Calibration timed out".to_string());
                        } else {
                            self.end_round("Time limit reached".to_string());
                        }
                        return;
                    }
                }

                if let Some(frag_limit) = self.config.frag_limit {
                    if let Some(&max_score) = self.scores.values().max() {
                        if max_score >= frag_limit {
                            self.end_round("Frag limit reached".to_string());
                            return;
                        }
                    }
                }
            }
            RoundState::Ended => {
                self.round_ticks += 1;
                if self.round_ticks >= self.config.end_delay_ticks {
                    self.start_round();
                }
                return;
            }
        }

        self.update_encounters();
        if self.mission_departed() || self.campaign_run_frozen() {
            for player in &mut self.players {
                player.just_fired = false;
            }
            return;
        }
        let map = self.map.clone();
        self.tick_active(dt, map.arena());
    }

    /// Resolve the active frame against one immutable world. Movement and shots
    /// must consume the same volumes, including their lower vertical bounds.
    fn tick_active(&mut self, dt: f32, arena: &crate::movement::Arena) {
        let mut respawn_ids = Vec::new();
        let move_speed = if self.compliance_ticks_left > 0 {
            MOVE_SPEED * 0.5
        } else {
            MOVE_SPEED
        };
        for player in &mut self.players {
            player.just_fired = false;
            if !crate::mission::actor_active(self.mission.as_ref(), player.id, player.campaign) {
                continue;
            }
            let jump_requested = std::mem::take(&mut player.jump_requested);

            if player.fire_cooldown > 0 {
                player.fire_cooldown -= 1;
            }

            if let Some(timer) = player.respawn_timer.as_mut() {
                *timer = timer.saturating_sub(1);
                if *timer == 0 {
                    respawn_ids.push(player.id);
                }
                continue;
            }

            if player.hp <= 0 {
                continue;
            }

            player.statistics.alive_tick();
            player.inventory.tick(player.pending_action.fire);

            if let Some(new_weapon) = player.pending_action.weapon_swap.take() {
                if player.inventory.select(player.weapon, new_weapon) {
                    player.weapon = new_weapon;
                }
            }

            let action = &player.pending_action;

            if let Some(seq) = action.seq {
                player.last_input_seq = Some(seq);
            }

            // Client-owned yaw wins and is applied before the move, so the
            // fighter travels in the direction the client predicted for this
            // same input. Without it, the turn bits still turn at a fixed rate
            // after the move, which is how agents and older clients aim.
            let client_yaw = action.yaw.filter(|y| y.is_finite());
            if let Some(yaw) = client_yaw {
                player.yaw = crate::movement::normalize_yaw(yaw);
            }
            if let Some(pitch) = action.pitch.and_then(crate::combat::clamp_pitch) {
                player.pitch = pitch;
            }

            let mut dx = 0.0;
            let mut dz = 0.0;
            if action.forward {
                dx += player.yaw.cos();
                dz += player.yaw.sin();
            }
            if action.back {
                dx -= player.yaw.cos();
                dz -= player.yaw.sin();
            }
            if action.left {
                dx += (player.yaw - PI / 2.0).cos();
                dz += (player.yaw - PI / 2.0).sin();
            }
            if action.right {
                dx += (player.yaw + PI / 2.0).cos();
                dz += (player.yaw + PI / 2.0).sin();
            }

            let len = (dx * dx + dz * dz).sqrt();
            if len > 0.0 {
                dx /= len;
                dz /= len;
            }

            let move_speed = move_speed * crate::encounters::gait(player.campaign);
            let moved = crate::movement::integrate(
                crate::movement::MoveState {
                    x: player.x,
                    z: player.z,
                    y: player.y - PLAYER_FLOOR_Y,
                    vx: dx * move_speed,
                    vz: dz * move_speed,
                    vy: player.vy,
                    yaw: player.yaw,
                },
                action.jump || jump_requested,
                dt,
                arena,
            );
            player.x = moved.x;
            player.z = moved.z;
            player.y = PLAYER_FLOOR_Y + moved.y;
            player.vy = moved.vy;

            if client_yaw.is_none() {
                if action.turn_left {
                    player.yaw -= TURN_SPEED * dt;
                }
                if action.turn_right {
                    player.yaw += TURN_SPEED * dt;
                }
            }

            while player.yaw < 0.0 {
                player.yaw += 2.0 * PI;
            }
            while player.yaw >= 2.0 * PI {
                player.yaw -= 2.0 * PI;
            }
        }

        // Target intent takes precedence after movement, for every controller role.
        // Applied after movement/turn so agents can still strafe while locking aim.
        let look_intents: Vec<(Uuid, crate::protocol::LookAt)> = self
            .players
            .iter()
            .filter(|p| p.respawn_timer.is_none())
            .filter(|p| crate::mission::actor_active(self.mission.as_ref(), p.id, p.campaign))
            .filter_map(|p| p.pending_action.look_at.clone().map(|look| (p.id, look)))
            .collect();
        for (aimer_id, look) in look_intents {
            let target_point: Option<[f32; 3]> = if let Some(pid) = look.player_id {
                self.players
                    .iter()
                    .find(|p| {
                        p.id == pid
                            && p.respawn_timer.is_none()
                            && crate::mission::actor_active(self.mission.as_ref(), p.id, p.campaign)
                    })
                    .map(|p| {
                        [
                            p.x,
                            p.y - PLAYER_FLOOR_Y + crate::combat::FIGHTER_HEIGHT * 0.5,
                            p.z,
                        ]
                    })
            } else if let (Some(x), Some(z)) = (look.x, look.z) {
                self.players
                    .iter()
                    .find(|p| p.id == aimer_id)
                    .map(|p| [x, look.y.unwrap_or(p.y - PLAYER_FLOOR_Y + EYE_HEIGHT), z])
            } else {
                None
            };
            if let Some(target) = target_point {
                if let Some(aimer) = self.players.iter_mut().find(|p| p.id == aimer_id) {
                    let eye = [aimer.x, aimer.y - PLAYER_FLOOR_Y + EYE_HEIGHT, aimer.z];
                    if let Some((yaw, pitch)) = crate::combat::aim_at(eye, target) {
                        aimer.yaw = yaw;
                        aimer.pitch = pitch;
                    }
                }
            }
        }

        self.tick_pickups();

        let mut hits = Vec::new();
        for i in 0..self.players.len() {
            let player = &mut self.players[i];

            if player.respawn_timer.is_some()
                || player.hp <= 0
                || !crate::mission::actor_active(self.mission.as_ref(), player.id, player.campaign)
            {
                continue;
            }

            if player.pending_action.fire && player.fire_cooldown == 0 {
                let dry_before = player.inventory.dry_fire_count();
                if player.inventory.try_fire(player.weapon) {
                    player.statistics.attack(player.weapon);
                    hits.push((i, self.check_hitscan(i, arena)));
                } else if player.inventory.dry_fire_count() > dry_before {
                    player.statistics.dry_trigger();
                }
            }
        }

        for (shooter_idx, shot) in hits {
            let weapon = shot.weapon;
            {
                let shooter = &mut self.players[shooter_idx];
                shooter.fire_cooldown = weapon.cooldown_ticks();
                shooter.just_fired = true;
            }
            // Pellets group by struck fighter in firing order; pellets that hit
            // cover or run out of range share one miss result after them.
            let mut groups: Vec<(Option<usize>, Vec<ResolvedPellet>)> = Vec::new();
            for pellet in shot.pellets {
                match groups
                    .iter_mut()
                    .find(|(target, _)| *target == pellet.target)
                {
                    Some((_, members)) => members.push(pellet),
                    None => groups.push((pellet.target, vec![pellet])),
                }
            }
            groups.sort_by_key(|(target, _)| target.is_none());
            let (mut hp_total, mut armor_total, mut kills) = (0, 0, 0);
            for (target, members) in groups {
                // Falloff follows each pellet's own 3D distance to the surface.
                let damage = members
                    .iter()
                    .map(|pellet| weapon.damage_at(pellet.distance))
                    .sum::<i32>();
                let trace = ShotTrace {
                    weapon,
                    origin: shot.origin,
                    end: members[0].end,
                    impact: members[0].impact.clone(),
                    pellets: if weapon.pellets() > 1 {
                        members
                            .iter()
                            .map(|pellet| PelletTrace {
                                end: pellet.end,
                                impact: pellet.impact.clone(),
                            })
                            .collect()
                    } else {
                        Vec::new()
                    },
                };
                match target {
                    Some(victim_idx) => {
                        let (hp, armor, died) =
                            self.resolve_fighter_hit(shooter_idx, victim_idx, damage, trace);
                        hp_total += hp;
                        armor_total += armor;
                        kills += u64::from(died);
                    }
                    None => {
                        let shooter = &self.players[shooter_idx];
                        self.shot_results.push(ShotResult {
                            shooter_id: shooter.id,
                            shooter: shooter.name.clone(),
                            hit: false,
                            target_id: None,
                            target: None,
                            damage: 0,
                            target_hp_after: None,
                            trace: Some(trace),
                            killed: false,
                        });
                    }
                }
            }
            // One attack is one damaging attack however many fighters it struck.
            self.players[shooter_idx]
                .statistics
                .hit(weapon, hp_total, armor_total, kills);
        }

        self.update_campaign_run();
        self.advance_mission();
        for id in respawn_ids {
            self.do_respawn(id);
        }

        self.reap_dead_boss();
    }

    /// Commit one fighter's share of a shot: every pellet that struck them,
    /// summed, so armour absorbs once and one death awards one frag.
    fn resolve_fighter_hit(
        &mut self,
        shooter_idx: usize,
        victim_idx: usize,
        damage: i32,
        trace: ShotTrace,
    ) -> (u64, u64, bool) {
        let shooter_name = self.players[shooter_idx].name.clone();
        let shooter_id = self.players[shooter_idx].id;
        let hostile = crate::protocol::hostile(
            self.players[shooter_idx].campaign,
            self.players[victim_idx].campaign,
        );
        let (
            target_id,
            target_name,
            target_hp_after,
            died,
            victim_was_boss,
            boss_id,
            damage,
            hp_damage,
            armor_damage,
        ) = {
            let victim = &mut self.players[victim_idx];
            let target_id = victim.id;
            let target_name = victim.name.clone();
            // Rays commit together, including trades. A body already
            // killed by an earlier ray this tick cannot award another frag.
            let was_alive = victim.hp > 0;
            let damage = if was_alive && hostile { damage } else { 0 };
            let absorbed = damage.min(victim.armor);
            let hp_damage = (damage - absorbed).min(victim.hp.max(0)) as u64;
            victim.armor -= absorbed;
            victim.hp -= damage - absorbed;
            let target_hp_after = victim.hp;
            let died = was_alive && victim.hp <= 0;
            victim.statistics.hurt(hp_damage, absorbed as u64, died);
            let victim_was_boss = victim.is_boss;
            if died {
                victim.inventory.release_trigger();
                // Victim streak dies with them; boss does not respawn.
                victim.killstreak = 0;
                if victim_was_boss || victim.is_campaign_enemy() {
                    victim.respawn_timer = None;
                } else {
                    victim.respawn_timer = Some(RESPAWN_DELAY_TICKS);
                }
            }
            (
                target_id,
                target_name,
                target_hp_after,
                died,
                victim_was_boss,
                target_id,
                damage,
                hp_damage,
                absorbed as u64,
            )
        };

        if damage > 0 {
            let victim = &self.players[victim_idx];
            let feet = [victim.x, victim.y - PLAYER_FLOOR_Y, victim.z];
            if let Some(identity) = self.encounters.hit(target_id, feet, self.tick, died) {
                self.players[victim_idx].campaign = Some(identity);
            }
        }

        self.shot_results.push(ShotResult {
            shooter_id,
            shooter: shooter_name.clone(),
            hit: true,
            target_id: Some(target_id),
            target: Some(target_name.clone()),
            damage,
            target_hp_after: Some(target_hp_after),
            trace: Some(trace),
            killed: died,
        });
        if damage > 0 {
            self.events.push(GameEvent::Hit {
                shooter: shooter_name.clone(),
                shooter_id,
                target: target_name.clone(),
                target_id,
                damage,
                target_hp_after,
            });
        }

        if died {
            // Campaign casualties have no arcade streaks, taunts or
            // participant scores. ShotResult remains the kill evidence.
            if self.players[shooter_idx].campaign.is_some() {
                tracing::info!(shooter = %shooter_name, target = %target_name, "Campaign combatant down");
                return (hp_damage, armor_damage, died);
            }
            *self.scores.entry(shooter_id).or_insert(0) += 1;
            let killer_score = self.scores[&shooter_id];

            self.events.push(GameEvent::Frag {
                killer: shooter_name.clone(),
                victim: target_name.clone(),
                killer_score,
            });

            // Killer streak (victim already reset). Host callouts at 2/3/5.
            let killer_streak = {
                let killer = &mut self.players[shooter_idx];
                killer.killstreak = killer.killstreak.saturating_add(1);
                killer.killstreak
            };
            if let Some((tier, message)) = killstreak_host_line(killer_streak, &shooter_name) {
                self.events.push(GameEvent::Killstreak {
                    player: shooter_name.clone(),
                    player_id: shooter_id,
                    streak: killer_streak,
                    tier,
                    message,
                });
            }

            // Named rule bots: occasional Contested Frequency speak (off-tick).
            if matches!(killer_streak, 2 | 3 | 5) {
                self.maybe_rule_bot_taunt(
                    shooter_id,
                    BotTauntKind::Killstreak,
                    RULE_BOT_TAUNT_STREAK_PCT,
                );
            } else {
                self.maybe_rule_bot_taunt(shooter_id, BotTauntKind::Frag, RULE_BOT_TAUNT_FRAG_PCT);
            }
            self.maybe_rule_bot_taunt(target_id, BotTauntKind::Death, RULE_BOT_TAUNT_DEATH_PCT);

            if victim_was_boss {
                let boss_msg = if self.solo_broadcast.enabled {
                    episode0_host_line_win()
                } else {
                    boss_down_host_line()
                };
                self.events.push(GameEvent::BossDown {
                    name: target_name.clone(),
                    boss_id,
                    killer: Some(shooter_name.clone()),
                    message: boss_msg,
                });
                tracing::info!(
                    "BOSS DOWN: {} fragged {} (score: {})",
                    shooter_name,
                    target_name,
                    killer_score
                );
                if self.solo_broadcast.enabled && self.solo_broadcast.phase == EpisodePhase::Auditor
                {
                    self.complete_episode("Auditor down. Frequency stays unmetered.".to_string());
                }
            } else {
                self.note_nods_frag(shooter_id, target_id);
                tracing::info!(
                    "FRAG: {} -> {} (score: {})",
                    shooter_name,
                    target_name,
                    killer_score
                );
            }
        }
        (hp_damage, armor_damage, died)
    }

    /// Seeded 3D rays for both cover and targets, one per pellet. No height
    /// auto-aim or forgiveness cone: a ray must intersect the finite fighter volume.
    fn check_hitscan(
        &mut self,
        shooter_idx: usize,
        arena: &crate::movement::Arena,
    ) -> ResolvedShot {
        let shooter = &self.players[shooter_idx];
        let origin = [
            shooter.x,
            shooter.y - PLAYER_FLOOR_Y + EYE_HEIGHT,
            shooter.z,
        ];
        let (yaw, pitch, weapon) = (shooter.yaw, shooter.pitch, shooter.weapon);
        let pellets = (0..weapon.pellets())
            .map(|_| {
                let samples = [self.next_f32(), self.next_f32()];
                let ray = crate::combat::Ray::dispersed(
                    origin,
                    yaw,
                    pitch,
                    weapon.spread_radians(),
                    samples,
                );
                self.resolve_pellet(shooter_idx, arena, ray, weapon)
            })
            .collect();
        ResolvedShot {
            weapon,
            origin,
            pellets,
        }
    }

    fn resolve_pellet(
        &self,
        shooter_idx: usize,
        arena: &crate::movement::Arena,
        ray: crate::combat::Ray,
        weapon: WeaponType,
    ) -> ResolvedPellet {
        let mut closest_dist = weapon.range_units().min(HITSCAN_RANGE);
        let mut cover_distance = f32::INFINITY;
        let mut impact = ShotImpact::Range;
        if let Some(distance) = ray.floor(closest_dist) {
            cover_distance = distance;
            impact = ShotImpact::Solid {
                normal: [0.0, 1.0, 0.0],
            };
        }
        for solid in &arena.solids {
            if let Some(hit) = ray.solid(solid, closest_dist) {
                if hit.distance < cover_distance {
                    cover_distance = hit.distance;
                    impact = ShotImpact::Solid { normal: hit.normal };
                }
            }
        }
        let mut closest_idx = None;
        for (i, target) in self.players.iter().enumerate() {
            if i == shooter_idx
                || target.hp <= 0
                || target.respawn_timer.is_some()
                || !crate::mission::actor_active(self.mission.as_ref(), target.id, target.campaign)
                || self.spawn_shields.get(&target.id).is_some_and(|t| *t > 0)
            {
                continue;
            }
            let feet = [target.x, target.y - PLAYER_FLOOR_Y, target.z];
            if let Some(hit) = ray.fighter(feet, PLAYER_RADIUS, closest_dist) {
                if hit.distance < cover_distance
                    && (closest_idx.is_none() || hit.distance < closest_dist)
                {
                    closest_dist = hit.distance;
                    closest_idx = Some(i);
                    impact = ShotImpact::Fighter { normal: hit.normal };
                }
            }
        }
        let distance = closest_dist.min(cover_distance);
        ResolvedPellet {
            target: closest_idx,
            distance,
            end: ray.point(distance),
            impact,
        }
    }
    /// Prefer unoccupied slots, then fewer exposed firing lanes, then clearance.
    /// Cover matters even when the widest gap is inside another fighter's range.
    /// A lane only counts inside `SPAWN_THREAT_RANGE`: one longer than any
    /// weapon's reach must not push a respawn toward a closer covered corner.
    fn select_spawn_angle(&mut self, player_id: Uuid) -> f32 {
        let others: Vec<[f32; 3]> = self
            .players
            .iter()
            .filter(|p| p.id != player_id && p.respawn_timer.is_none())
            .map(|p| [p.x, p.y - PLAYER_FLOOR_Y + EYE_HEIGHT, p.z])
            .collect();
        if others.is_empty() {
            return self.next_f32() * 2.0 * PI;
        }
        let mut best_angle = 0.0;
        let mut best: Option<(bool, usize, f32)> = None;
        let solids = self.map.solids();
        let slots = self.map.spawn_slots();
        for slot in 0..slots {
            let angle = slot as f32 * (2.0 * PI / slots as f32);
            let (sx, sz, _, floor) = self.map.spawn(angle);
            let nearest = others
                .iter()
                .map(|eye| (eye[0] - sx).hypot(eye[2] - sz))
                .fold(f32::MAX, f32::min);
            let clear = nearest >= PLAYER_RADIUS * 2.0;
            let exposed = others
                .iter()
                .filter(|&&eye| {
                    // The longest weapon bounds relevant lanes even if the
                    // opponent swaps weapons immediately after this spawn.
                    (eye[0] - sx).hypot(eye[2] - sz) <= SPAWN_THREAT_RANGE
                        && [crate::combat::FIGHTER_HEIGHT * 0.5, EYE_HEIGHT]
                            .into_iter()
                            .any(|height| {
                                crate::combat::line_of_sight(eye, [sx, floor + height, sz], &solids)
                            })
                })
                .count();
            if best.is_none_or(|(was_clear, threats, gap)| {
                (clear && !was_clear)
                    || (clear == was_clear
                        && (exposed < threats || (exposed == threats && nearest > gap)))
            }) {
                best = Some((clear, exposed, nearest));
                best_angle = angle;
            }
        }
        best_angle
    }

    fn do_respawn(&mut self, player_id: Uuid) {
        let angle = self.select_spawn_angle(player_id);
        if let Some(player) = self.players.iter_mut().find(|p| p.id == player_id) {
            let (sx, sz, yaw, floor) = self.map.spawn(angle);

            player.x = sx;
            player.y = PLAYER_FLOOR_Y + floor;
            // A fighter that died mid-jump must not respawn still falling.
            player.vy = 0.0;
            player.z = sz;
            player.yaw = yaw;
            player.pitch = 0.0;
            player.hp = PLAYER_MAX_HP;
            player.armor = 0;
            player.respawn_timer = None;
            player.fire_cooldown = 0;

            if self.map.equipment_policy() == crate::protocol::EquipmentPolicy::Discovery {
                player.inventory = crate::inventory::Inventory::new(self.map.equipment_policy());
                player.weapon = WeaponType::Fists;
                player.pending_action = Action::default();
                player.jump_requested = false;
                player.just_fired = false;
            }

            self.events.push(GameEvent::Respawn {
                player: player.name.clone(),
            });
            self.spawn_shields.insert(player_id, SPAWN_SHIELD_TICKS);
        }
    }

    pub fn snapshot(&self) -> Snapshot {
        let round_time_left = if self.round_state == RoundState::Active {
            self.config
                .time_limit_ticks
                .map(|limit| (limit.saturating_sub(self.round_ticks)) / 20)
        } else if self.round_state == RoundState::Warmup {
            let remaining = self.config.warmup_ticks.saturating_sub(self.round_ticks);
            Some(remaining.div_ceil(20).max(1))
        } else {
            None
        };

        Snapshot {
            tick: self.tick,
            players: self
                .players
                .iter()
                .filter(|p| p.respawn_timer.is_none())
                .map(|p| {
                    let behavior = self
                        .bots
                        .iter()
                        .find(|b| b.player_id == p.id)
                        .map(|b| format!("{:?}", b.behavior))
                        .or_else(|| p.display_behavior.clone());

                    PlayerState {
                        campaign: p.campaign,
                        id: p.id,
                        name: p.name.clone(),
                        x: p.x,
                        y: p.y,
                        z: p.z,
                        yaw: p.yaw,
                        pitch: p.pitch,
                        hp: p.hp,
                        armor: p.armor,
                        just_fired: p.just_fired,
                        behavior,
                        score: *self.scores.get(&p.id).unwrap_or(&0),
                        weapon: p.weapon.name().to_string(),
                    }
                })
                .collect(),
            round_state: Some(format!("{:?}", self.round_state)),
            round_time_left,
            frag_limit: self.config.frag_limit,
            shot_results: self.shot_results.clone(),
            mode_name: if self.map.is_authored() {
                "Campaign development"
            } else {
                MODE_NAME
            }
            .to_string(),
            playlist: if self.map.is_authored() {
                "Campaign development"
            } else {
                PLAYLIST_NAME
            }
            .to_string(),
            pressure: if self.boss_id.is_some() {
                Some("compliance_drone".to_string())
            } else if self.compliance_ticks_left > 0 {
                Some("compliance".to_string())
            } else {
                None
            },
            host_line: if self.map.mission().is_some() {
                String::new()
            } else if self.map.is_authored() {
                if self.map.has_encounters() {
                    "Campaign development: introductory encounters; objectives and extraction remain in progress."
                } else {
                    "Campaign development: encounters and objectives are not implemented."
                }.to_string()
            } else if self.round_state == RoundState::Ended {
                self.ended_host_line
                    .clone()
                    .unwrap_or_else(default_host_line)
            } else if let Some(line) = self.solo_broadcast.host_line.as_ref() {
                line.clone()
            } else if self.boss_id.is_some() {
                boss_host_line()
            } else if self.compliance_ticks_left > 0 {
                compliance_host_line()
            } else if self.round_state == RoundState::Warmup {
                let remaining = self.config.warmup_ticks.saturating_sub(self.round_ticks);
                let secs = remaining.div_ceil(20).max(1);
                warmup_host_line(&self.display_map_name(), &self.roster_names, secs)
            } else {
                default_host_line()
            },
            mvp: if self.round_state == RoundState::Ended {
                self.ended_mvp.clone()
            } else {
                None
            },
            mvp_frags: if self.round_state == RoundState::Ended {
                self.ended_mvp_frags
            } else {
                None
            },
            pickups: self.pickups.iter().map(|p| p.to_state()).collect(),
            map_id: self.map.id(),
            map_name: self.display_map_name(),
            episode_id: if self.solo_broadcast.enabled {
                Some(EPISODE_ID_EP0.to_string())
            } else {
                None
            },
            episode_title: if self.solo_broadcast.enabled {
                Some(EPISODE_TITLE_EP0.to_string())
            } else {
                None
            },
            episode_objective: if self.solo_broadcast.enabled {
                Some(episode0_objective_chip())
            } else {
                None
            },
            episode_progress: if self.solo_broadcast.enabled {
                Some(self.episode_progress_chip())
            } else {
                None
            },
            episode_phase: if self.solo_broadcast.enabled {
                Some(self.solo_broadcast.phase.wire().to_string())
            } else {
                None
            },
            jammer_dish: self.jammer_dish_state(),
        }
    }

    fn jammer_dish_state(&self) -> Option<crate::protocol::JammerDishState> {
        if !self.solo_broadcast.enabled {
            return None;
        }
        let sb = &self.solo_broadcast;
        match sb.phase {
            EpisodePhase::Jammer => Some(crate::protocol::JammerDishState {
                x: 0.0,
                y: 0.35,
                z: 0.0,
                live: true,
                seized: false,
            }),
            EpisodePhase::Auditor | EpisodePhase::Won if sb.jammer_seized => {
                Some(crate::protocol::JammerDishState {
                    x: 0.0,
                    y: 0.35,
                    z: 0.0,
                    live: false,
                    seized: true,
                })
            }
            _ => None,
        }
    }

    /// Refresh sticky Warmup Host roster line from current rule-bot display names.
    /// Clears when `names` is empty so mid-join falls back to the default league line.
    pub fn set_roster_host_line_from_names(&mut self, names: &[String]) {
        self.roster_names = names.to_vec();
        if names.is_empty() {
            self.roster_host_line = None;
        } else {
            self.roster_host_line = Some(roster_host_line(names));
        }
    }

    /// Enable Contested Frequency Solo Broadcast Episode 0 (Calibration / Larak Lot).
    /// Relabels rule bots as NODS, disables timed Compliance Drone (Auditor is gated),
    /// and arms episode chrome. Safe to call once at boot.
    pub fn enable_solo_broadcast_ep0(&mut self) {
        self.solo_broadcast = SoloBroadcastEp0 {
            enabled: true,
            started: false,
            nods_cleared: 0,
            nods_goal: EP0_NODS_GOAL,
            jammer_seized: false,
            phase: EpisodePhase::Nods,
            host_line: Some(episode0_host_line_cold_open()),
        };
        // Auditor spawns after jammer seize, not on a timed mid-round drone.
        self.config.boss_spawn_ticks = None;
        // Insanely-fun: time-to-first-frag under ~30s. Short Warmup, keep guns loud.
        self.config.warmup_ticks = 20; // 1s
                                       // Slightly earlier compliance ping as Continuance probe-van flavor.
        self.config.compliance_ping_ticks = Some(20 * 8);
        self.relabel_rule_bots_as_nods();
    }

    pub(crate) fn relabel_rule_bots_as_nods(&mut self) {
        let mut n = 0u32;
        for player in &mut self.players {
            if player.is_boss || player.role == Role::Human {
                continue;
            }
            if self.bots.iter().any(|b| b.player_id == player.id) {
                n += 1;
                player.name = format!("NODS-{n:02}");
            }
        }
        let names: Vec<String> = self
            .players
            .iter()
            .filter(|p| self.bots.iter().any(|b| b.player_id == p.id) && !p.is_boss)
            .map(|p| p.name.clone())
            .collect();
        self.set_roster_host_line_from_names(&names);
    }

    /// Directory line. Bots are the server's own fighters. Agents joined.
    pub fn live_status(&self, connections: usize) -> crate::protocol::LiveStatus {
        let mut humans = 0;
        let mut agents = 0;
        let mut bots = 0;
        for player in &self.players {
            match player.role {
                Role::Human => humans += 1,
                Role::Agent if self.is_rule_bot(player.id) => bots += 1,
                Role::Agent => agents += 1,
                Role::Spectator => {}
            }
        }
        crate::protocol::LiveStatus {
            schema_version: 2,
            kind: if self.map.is_campaign() {
                "campaign"
            } else {
                "arena"
            }
            .to_string(),
            map: self.display_map_name(),
            round: self.round_number,
            tick: self.tick,
            fighters: humans + agents + bots,
            humans,
            agents,
            bots,
            connections,
            health: None,
            ops: None,
        }
    }

    fn display_map_name(&self) -> String {
        // Episode 0 face "Larak Lot" only when geometry is Arena Duel (map 1).
        // Compliance Yard (map 2) must not lie as Larak Lot.
        if self.solo_broadcast.enabled && self.map == MapKind::ArenaDuel {
            EPISODE_MAP_LARAK_LOT.to_string()
        } else {
            self.map.name().to_string()
        }
    }

    fn episode_progress_chip(&self) -> String {
        let sb = &self.solo_broadcast;
        let nods = format!(
            "NODS {}/{}",
            sb.nods_cleared.min(sb.nods_goal),
            sb.nods_goal
        );
        let jammer = if sb.jammer_seized {
            "JAMMER OK"
        } else if sb.phase == EpisodePhase::Jammer {
            "SEIZE JAMMER"
        } else {
            "JAMMER"
        };
        let auditor = match sb.phase {
            EpisodePhase::Auditor => "AUDITOR LIVE",
            EpisodePhase::Won => "AUDITOR DOWN",
            EpisodePhase::Failed => "FAILED",
            _ => "AUDITOR",
        };
        format!("{nods} | {jammer} | {auditor}")
    }

    pub(crate) fn maybe_start_episode(&mut self) {
        if !self.solo_broadcast.enabled || self.solo_broadcast.started {
            return;
        }
        self.solo_broadcast.started = true;
        self.solo_broadcast.host_line = Some(episode0_host_line_cold_open());
        self.events.push(GameEvent::EpisodeStart {
            id: EPISODE_ID_EP0.to_string(),
            title: EPISODE_TITLE_EP0.to_string(),
            objective: episode0_objective_chip(),
            host_line: episode0_host_line_cold_open(),
            map_name: self.display_map_name(),
        });
        tracing::info!(
            "Solo Broadcast Episode 0 started (Calibration / {})",
            self.display_map_name()
        );
    }

    /// True when `id` is a server rule-bot controller (not MCP/Agent meatbag).
    fn is_rule_bot(&self, id: Uuid) -> bool {
        self.bots.iter().any(|b| b.player_id == id)
    }

    /// Meatbag scrap path: Human, or Agent that is not a rule bot / Auditor.
    fn is_meatbag_id(&self, id: Uuid) -> bool {
        let Some(player) = self.players.iter().find(|p| p.id == id) else {
            return false;
        };
        match player.role {
            Role::Human => true,
            Role::Agent => !player.is_boss && !self.is_rule_bot(id),
            Role::Spectator => false,
        }
    }

    /// NODS rule-bot victim: NODS-* name or bot controller, never boss/Auditor.
    fn is_nods_victim_id(&self, id: Uuid) -> bool {
        let Some(player) = self.players.iter().find(|p| p.id == id) else {
            return false;
        };
        if player.is_boss {
            return false;
        }
        player.name.starts_with("NODS-") || self.is_rule_bot(id)
    }

    /// Credit Calibration NODS progress for a meatbag frag of a NODS victim.
    pub(crate) fn note_nods_frag(&mut self, killer_id: Uuid, victim_id: Uuid) {
        if !self.solo_broadcast.enabled {
            return;
        }
        if self.solo_broadcast.phase != EpisodePhase::Nods {
            return;
        }
        if !self.is_meatbag_id(killer_id) {
            return;
        }
        if !self.is_nods_victim_id(victim_id) {
            return;
        }
        self.solo_broadcast.nods_cleared = self.solo_broadcast.nods_cleared.saturating_add(1);
        let cleared = self.solo_broadcast.nods_cleared;
        let goal = self.solo_broadcast.nods_goal;
        // Rate-sane Host bump: one sticky line per credited clear. Goal clear
        // hands Host to jammer only (no double booth beat).
        if cleared < goal {
            self.solo_broadcast.host_line = Some(episode0_host_line_nods_tick(cleared, goal));
        }
        if cleared >= goal {
            self.solo_broadcast.phase = EpisodePhase::Jammer;
            self.solo_broadcast.host_line = Some(episode0_host_line_jammer());
            tracing::info!("Episode 0: NODS cleared, jammer dish is live");
        }
    }

    pub(crate) fn try_seize_jammer(&mut self) {
        if !self.solo_broadcast.enabled || self.solo_broadcast.phase != EpisodePhase::Jammer {
            return;
        }
        let meatbag_near = self
            .players
            .iter()
            .filter(|p| p.respawn_timer.is_none())
            .filter(|p| (p.x * p.x + p.z * p.z).sqrt() <= EP0_JAMMER_RADIUS)
            .any(|p| match p.role {
                Role::Human => true,
                Role::Agent => !p.is_boss && !self.bots.iter().any(|b| b.player_id == p.id),
                Role::Spectator => false,
            });
        if !meatbag_near {
            return;
        }
        self.solo_broadcast.jammer_seized = true;
        self.solo_broadcast.phase = EpisodePhase::Auditor;
        self.solo_broadcast.host_line = Some(episode0_host_line_auditor());
        self.spawn_auditor();
        tracing::info!("Episode 0: jammer seized, Auditor inbound");
    }

    /// Continuance Auditor elite (clipboard shield). Reuses Compliance AI path.
    pub fn spawn_auditor(&mut self) -> Option<Uuid> {
        if self.boss_spawned || self.boss_id.is_some() {
            return None;
        }
        if self.round_state != RoundState::Active {
            return None;
        }
        let id = self.new_entity_id();
        let name = AUDITOR_NAME.to_string();
        self.players.push(Player {
            statistics: Default::default(),
            campaign: None,
            id,
            name: name.clone(),
            x: 0.0,
            y: 2.2,
            z: 0.0,
            yaw: 0.0,
            pitch: 0.0,
            vy: 0.0,
            hp: BOSS_MAX_HP,
            armor: 50,
            pending_action: Action::default(),
            jump_requested: false,
            fire_cooldown: 0,
            interaction_requested: false,
            respawn_timer: None,
            just_fired: false,
            role: Role::Agent,
            weapon: WeaponType::Rail,
            inventory: crate::inventory::Inventory::new(
                crate::protocol::EquipmentPolicy::FullArsenal,
            ),
            last_speak_tick: None,
            is_boss: true,
            killstreak: 0,
            display_behavior: None,
            last_input_seq: None,
        });
        self.bots
            .push(BotController::new(id, BotBehavior::Compliance));
        self.scores.insert(id, 0);
        self.boss_id = Some(id);
        self.boss_spawned = true;
        self.events.push(GameEvent::BossSpawn {
            name: name.clone(),
            boss_id: id,
            message: episode0_host_line_auditor(),
            hp: BOSS_MAX_HP,
        });
        tracing::info!("Auditor spawned ({})", id);
        Some(id)
    }

    pub(crate) fn complete_episode(&mut self, reason: String) {
        if !self.solo_broadcast.enabled || self.solo_broadcast.phase == EpisodePhase::Won {
            return;
        }
        self.solo_broadcast.phase = EpisodePhase::Won;
        let host = episode0_host_line_win();
        self.solo_broadcast.host_line = Some(host.clone());
        self.events.push(GameEvent::EpisodeComplete {
            id: EPISODE_ID_EP0.to_string(),
            reason: reason.clone(),
            host_line: host,
            unlock_teaser: episode0_unlock_teaser(),
        });
        tracing::info!("Episode 0 complete: {reason}");
        self.end_round(reason);
    }

    pub(crate) fn fail_episode(&mut self, reason: String) {
        if !self.solo_broadcast.enabled {
            self.end_round(reason);
            return;
        }
        if self.solo_broadcast.phase == EpisodePhase::Won
            || self.solo_broadcast.phase == EpisodePhase::Failed
        {
            return;
        }
        self.solo_broadcast.phase = EpisodePhase::Failed;
        let host = episode0_host_line_fail();
        self.solo_broadcast.host_line = Some(host.clone());
        self.events.push(GameEvent::EpisodeFail {
            id: EPISODE_ID_EP0.to_string(),
            reason: reason.clone(),
            host_line: host,
        });
        tracing::info!("Episode 0 fail: {reason}");
        self.end_round("Citizen Handle assigned".to_string());
    }

    pub(crate) fn tick_solo_broadcast(&mut self) {
        if !self.solo_broadcast.enabled {
            return;
        }
        self.maybe_start_episode();
        if self.round_state == RoundState::Active {
            self.try_seize_jammer();
        }
    }

    fn reset_pickups(&mut self) {
        self.pickups = self.map.pickups();
    }

    /// Decrement pad respawn timers and claim available pads on touch.
    fn tick_pickups(&mut self) {
        for pad in &mut self.pickups {
            if let Some(timer) = pad.respawn_timer.as_mut() {
                *timer = timer.saturating_sub(1);
                if *timer == 0 {
                    pad.respawn_timer = None;
                    pad.available = true;
                }
            }
        }

        // Collect claims (player_id, pad index) without holding dual borrows.
        let mut claims: Vec<(Uuid, usize)> = Vec::new();
        for player in &self.players {
            if player.respawn_timer.is_some()
                || player.hp <= 0
                || player.is_boss
                || player.is_campaign_enemy()
                || !crate::mission::actor_active(self.mission.as_ref(), player.id, player.campaign)
            {
                continue;
            }
            for (pi, pad) in self.pickups.iter().enumerate() {
                if !pad.available {
                    continue;
                }
                if pad.claim == crate::protocol::SupplyClaim::Personal
                    && player.inventory.claimed(&pad.id)
                {
                    continue;
                }
                let useful = match pad.kind {
                    PickupKind::Weapon(weapon) => {
                        !player.inventory.owns(weapon)
                            || player.inventory.policy()
                                == crate::protocol::EquipmentPolicy::FullArsenal
                            || weapon
                                .ammo_pool()
                                .is_some_and(|pool| player.inventory.needs_ammo(pool))
                    }
                    PickupKind::Ammo { pool, .. } => player.inventory.needs_ammo(pool),
                    PickupKind::Health => player.hp < PLAYER_MAX_HP,
                    PickupKind::Armor => player.armor < PLAYER_MAX_ARMOR,
                };
                if !useful {
                    continue;
                }
                let dx = player.x - pad.x;
                let dz = player.z - pad.z;
                // On roughly the pad's floor, not merely over its footprint.
                if (player.y - PLAYER_FLOOR_Y - pad.floor).abs() > PICKUP_CLAIM_HEIGHT {
                    continue;
                }
                if dx * dx + dz * dz <= PICKUP_CLAIM_RADIUS * PICKUP_CLAIM_RADIUS
                    && (!self.map.is_authored()
                        || crate::combat::line_of_sight(
                            [player.x, player.y - PLAYER_FLOOR_Y + EYE_HEIGHT, player.z],
                            [pad.x, pad.y, pad.z],
                            &self.map.arena().solids,
                        ))
                {
                    claims.push((player.id, pi));
                    break; // one pad per player per tick
                }
            }
        }

        for (player_id, pad_idx) in claims {
            let pad = &mut self.pickups[pad_idx];
            if !pad.available {
                continue; // raced / already taken this tick
            }
            let kind = pad.kind;
            let amount = pad.amount;
            let secret = pad.secret;
            let pickup_id = pad.id.clone();
            // Campaign stock is consumed until the authoritative party reset.
            // Arcade pads retain their timed circulation around the map.
            let respawn = (!self.map.is_campaign()).then(|| pad.respawn_ticks());
            if pad.claim == crate::protocol::SupplyClaim::Contested {
                pad.available = false;
                pad.respawn_timer = respawn;
            }

            let Some(player) = self.players.iter_mut().find(|p| p.id == player_id) else {
                continue;
            };
            if pad.claim == crate::protocol::SupplyClaim::Personal {
                player.inventory.record_claim(pickup_id.clone());
            }
            if secret {
                player.statistics.secret(&pickup_id);
            }
            let (weapon_wire, amount_wire, label) = match kind {
                PickupKind::Weapon(w) => {
                    let discovered = !player.inventory.owns(w);
                    player.inventory.grant_weapon(w);
                    if discovered
                        || player.inventory.policy()
                            == crate::protocol::EquipmentPolicy::FullArsenal
                    {
                        player.inventory.release_trigger();
                        player.weapon = w;
                    }
                    (w.name().to_string(), None, w.name().to_string())
                }
                PickupKind::Ammo { pool, rounds } => {
                    let gained = player.inventory.grant_ammo(pool, rounds);
                    (
                        String::new(),
                        Some(i32::from(gained)),
                        format!("{pool:?} ammunition"),
                    )
                }
                PickupKind::Health => {
                    let before = player.hp;
                    player.hp = (player.hp + amount).min(PLAYER_MAX_HP);
                    let gained = player.hp - before;
                    (String::new(), Some(gained), format!("+{} HP", gained))
                }
                PickupKind::Armor => {
                    let before = player.armor;
                    player.armor = (player.armor + amount).min(PLAYER_MAX_ARMOR);
                    let gained = player.armor - before;
                    (String::new(), Some(gained), format!("+{} armor", gained))
                }
            };
            let name = player.name.clone();
            self.events.push(GameEvent::Pickup {
                player: name.clone(),
                player_id,
                kind: kind.wire_name().to_string(),
                weapon: weapon_wire,
                amount: amount_wire,
                pickup_id: pickup_id.clone(),
                secret,
            });
            tracing::info!("PICKUP: {} claimed {} ({})", name, label, pickup_id);
        }
    }

    fn fire_compliance_ping(&mut self) {
        self.compliance_fired = true;
        self.compliance_ticks_left = self.config.compliance_duration_ticks;
        self.events.push(GameEvent::CompliancePing {
            message: compliance_host_line(),
            duration_ticks: self.config.compliance_duration_ticks,
        });
        tracing::info!(
            "Compliance ping fired (duration {} ticks)",
            self.config.compliance_duration_ticks
        );
    }

    /// Drop the Continuance Compliance Drone into the Active scrap (once per round).
    pub fn spawn_compliance_drone(&mut self) -> Option<Uuid> {
        if self.boss_spawned || self.boss_id.is_some() {
            return None;
        }
        if self.round_state != RoundState::Active {
            return None;
        }
        let id = self.new_entity_id();
        self.players.push(Player {
            statistics: Default::default(),
            campaign: None,
            id,
            name: BOSS_NAME.to_string(),
            x: 0.0,
            y: 2.2,
            z: 0.0,
            yaw: 0.0,
            pitch: 0.0,
            vy: 0.0,
            hp: BOSS_MAX_HP,
            armor: 0,
            pending_action: Action::default(),
            jump_requested: false,
            fire_cooldown: 0,
            interaction_requested: false,
            respawn_timer: None,
            just_fired: false,
            role: Role::Agent,
            weapon: WeaponType::Rail,
            inventory: crate::inventory::Inventory::new(
                crate::protocol::EquipmentPolicy::FullArsenal,
            ),
            last_speak_tick: None,
            is_boss: true,
            killstreak: 0,
            display_behavior: None,
            last_input_seq: None,
        });
        self.bots
            .push(BotController::new(id, BotBehavior::Compliance));
        self.scores.insert(id, 0);
        self.boss_id = Some(id);
        self.boss_spawned = true;
        self.events.push(GameEvent::BossSpawn {
            name: BOSS_NAME.to_string(),
            boss_id: id,
            message: boss_host_line(),
            hp: BOSS_MAX_HP,
        });
        tracing::info!("Compliance Drone spawned ({})", id);
        Some(id)
    }

    /// Round-end dismiss: emit boss_down (no killer) then scrub the drone.
    fn wipe_boss_for_round_end(&mut self) {
        let Some(id) = self.boss_id else {
            return;
        };
        let alive = self
            .players
            .iter()
            .any(|p| p.id == id && p.hp > 0 && p.respawn_timer.is_none());
        if !alive {
            self.clear_boss();
            return;
        }
        let name = self
            .players
            .iter()
            .find(|p| p.id == id)
            .map(|p| p.name.clone())
            .unwrap_or_else(|| BOSS_NAME.to_string());
        self.events.push(GameEvent::BossDown {
            name,
            boss_id: id,
            killer: None,
            message: boss_round_wipe_host_line(),
        });
        self.clear_boss();
        tracing::info!("Boss wiped on round end ({})", id);
    }

    fn clear_boss(&mut self) {
        if let Some(id) = self.boss_id.take() {
            self.players.retain(|p| p.id != id);
            self.bots.retain(|b| b.player_id != id);
            self.scores.remove(&id);
        }
        self.boss_spawned = false;
        // Also scrub any orphaned boss players (round recycle safety).
        let orphan_ids: Vec<Uuid> = self
            .players
            .iter()
            .filter(|p| p.is_boss)
            .map(|p| p.id)
            .collect();
        for id in orphan_ids {
            self.players.retain(|p| p.id != id);
            self.bots.retain(|b| b.player_id != id);
            self.scores.remove(&id);
        }
    }

    fn reap_dead_boss(&mut self) {
        let Some(boss_id) = self.boss_id else {
            return;
        };
        let dead = self
            .players
            .iter()
            .find(|p| p.id == boss_id)
            .map(|p| p.hp <= 0)
            .unwrap_or(true);
        if !dead {
            return;
        }
        self.players.retain(|p| p.id != boss_id);
        self.bots.retain(|b| b.player_id != boss_id);
        self.scores.remove(&boss_id);
        self.boss_id = None;
    }

    /// True when `id` is a named scrap rule bot (not Continuance Compliance).
    pub fn is_named_rule_bot(&self, id: Uuid) -> bool {
        self.bots
            .iter()
            .any(|b| b.player_id == id && b.behavior != BotBehavior::Compliance)
    }

    fn taunt_roll(tick: u64, player_id: Uuid, salt: u64) -> u64 {
        tick.wrapping_mul(2654435761)
            .wrapping_add(player_id.as_u128() as u64)
            .wrapping_add(salt)
            % 100
    }

    /// Probabilistic Contested Frequency speak for a named rule bot.
    /// Silent on miss / RateLimited / Rejected (no Error unicast spam for bots).
    pub fn maybe_rule_bot_taunt(&mut self, player_id: Uuid, kind: BotTauntKind, chance_pct: u64) {
        if !self.is_named_rule_bot(player_id) {
            return;
        }
        let salt = match kind {
            BotTauntKind::Frag => 11,
            BotTauntKind::Death => 22,
            BotTauntKind::Killstreak => 33,
            BotTauntKind::Warmup => 44,
        };
        if Self::taunt_roll(self.tick, player_id, salt) >= chance_pct {
            return;
        }
        let _ = self.try_rule_bot_taunt(player_id, kind);
    }

    /// Always attempt a callsign-flavored speak (still respects SPEAK_COOLDOWN).
    pub fn try_rule_bot_taunt(&mut self, player_id: Uuid, kind: BotTauntKind) -> SpeakOutcome {
        if !self.is_named_rule_bot(player_id) {
            return SpeakOutcome::Rejected;
        }
        let name = match self.players.iter().find(|p| p.id == player_id) {
            Some(p) => p.name.clone(),
            None => return SpeakOutcome::Rejected,
        };
        let salt = self.tick ^ (player_id.as_u128() as u64);
        let line = rule_bot_taunt_line(&name, kind, salt);
        self.try_speak(player_id, &line)
    }

    /// During Warmup, occasionally one dialed-in rule bot speaks a tuning-in line.
    fn maybe_warmup_rule_bot_taunts(&mut self) {
        if self.round_ticks == 0 || !self.round_ticks.is_multiple_of(RULE_BOT_WARMUP_TAUNT_EVERY) {
            return;
        }
        let rule_bots: Vec<Uuid> = self
            .bots
            .iter()
            .filter(|b| b.behavior != BotBehavior::Compliance)
            .map(|b| b.player_id)
            .collect();
        if rule_bots.is_empty() {
            return;
        }
        let idx = (self.tick as usize) % rule_bots.len();
        self.maybe_rule_bot_taunt(
            rule_bots[idx],
            BotTauntKind::Warmup,
            RULE_BOT_TAUNT_WARMUP_PCT,
        );
    }

    /// Validate and emit an off-tick speak event.
    pub fn try_speak(&mut self, player_id: Uuid, raw_text: &str) -> SpeakOutcome {
        let trimmed: String = raw_text.trim().chars().take(SPEAK_MAX_CHARS + 1).collect();
        if trimmed.is_empty() {
            return SpeakOutcome::Rejected;
        }
        if trimmed.chars().count() > SPEAK_MAX_CHARS {
            return SpeakOutcome::Rejected;
        }
        if trimmed.chars().any(|c| c.is_control()) {
            return SpeakOutcome::Rejected;
        }

        let tick = self.tick;
        let player = match self.players.iter_mut().find(|p| p.id == player_id) {
            Some(p) => p,
            None => return SpeakOutcome::Rejected,
        };

        if let Some(last) = player.last_speak_tick {
            if tick.saturating_sub(last) < SPEAK_COOLDOWN_TICKS {
                return SpeakOutcome::RateLimited;
            }
        }

        let name = player.name.clone();
        player.last_speak_tick = Some(tick);
        self.events.push(GameEvent::Speak {
            player: name,
            player_id,
            text: trimmed,
        });
        SpeakOutcome::Sent
    }

    pub fn take_events(&mut self) -> Vec<GameEvent> {
        std::mem::take(&mut self.events)
    }

    pub fn push_event(&mut self, event: GameEvent) {
        self.events.push(event);
    }
}

impl Default for GameState {
    fn default() -> Self {
        Self {
            statistics_session: Uuid::new_v4(),
            statistics_round_started: 0,
            encounters: crate::encounters::Encounters::default(),
            mission: None,
            replay_id_counter: None,
            rng_state: 0x2545_F491_4F6C_DD1D,
            tick: 0,
            players: Vec::new(),
            events: Vec::new(),
            bots: Vec::new(),
            scores: HashMap::new(),
            round_state: RoundState::Warmup,
            round_ticks: 0,
            round_number: 0,
            config: MatchConfig::default(),
            shot_results: Vec::new(),
            compliance_ticks_left: 0,
            compliance_fired: false,
            boss_id: None,
            boss_spawned: false,
            pickups: MapKind::ArenaDuel.pickups(),
            ended_host_line: None,
            ended_mvp: None,
            ended_mvp_frags: None,
            roster_host_line: None,
            roster_names: Vec::new(),
            map: crate::maps::RuntimeMap::BuiltIn(MapKind::ArenaDuel),
            map_rotate: false,
            spawn_shields: HashMap::new(),
            solo_broadcast: SoloBroadcastEp0::default(),
        }
    }
}

#[derive(Clone)]
pub struct BotController {
    pub player_id: Uuid,
    pub behavior: BotBehavior,
}

#[derive(Default)]
pub(crate) struct BotIntent {
    pub action: Action,
    pub goal: Option<crate::navigation::NavigationGoal>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BotBehavior {
    Aggressive,
    Defensive,
    Flanker,
    Balanced,
    /// Continuance Compliance Drone: mid-range Rail enforcer.
    Compliance,
}

impl BotController {
    pub fn new(player_id: Uuid, behavior: BotBehavior) -> Self {
        Self {
            player_id,
            behavior,
        }
    }

    pub fn update(&self, state: &GameState) -> Action {
        self.intent(state).action
    }

    pub(crate) fn intent(&self, state: &GameState) -> BotIntent {
        let Some(bot) = state.players.iter().find(|p| p.id == self.player_id) else {
            return BotIntent::default();
        };

        if bot.respawn_timer.is_some() {
            return BotIntent::default();
        }

        let mut nearest_dist = f32::MAX;
        let mut nearest_target: Option<&Player> = None;

        for target in &state.players {
            if target.id == self.player_id
                || target.respawn_timer.is_some()
                || target.hp <= 0
                || !crate::protocol::hostile(bot.campaign, target.campaign)
            {
                continue;
            }

            let dx = target.x - bot.x;
            let dz = target.z - bot.z;
            let dist = (dx * dx + dz * dz).sqrt();

            if dist < nearest_dist {
                nearest_dist = dist;
                nearest_target = Some(target);
            }
        }

        let Some(target) = nearest_target else {
            return BotIntent::default();
        };

        let dx = target.x - bot.x;
        let dz = target.z - bot.z;
        let target_angle = dz.atan2(dx);

        let mut angle_diff = target_angle - bot.yaw;
        while angle_diff > PI {
            angle_diff -= 2.0 * PI;
        }
        while angle_diff < -PI {
            angle_diff += 2.0 * PI;
        }

        let eye = [bot.x, bot.y - PLAYER_FLOOR_Y + EYE_HEIGHT, bot.z];
        let target_centre = [
            target.x,
            target.y - PLAYER_FLOOR_Y + crate::combat::FIGHTER_HEIGHT * 0.5,
            target.z,
        ];
        let mut action = Action {
            pitch: crate::combat::aim_at(eye, target_centre).map(|(_, pitch)| pitch),
            ..Action::default()
        };

        // Seek a role pad when Flechette and a better weapon is nearby.
        // Prefer Scatter when the fight is close; Rail when it is long.
        if bot.weapon == WeaponType::Flechette && self.behavior != BotBehavior::Compliance {
            let want_scatter = nearest_dist < 12.0;
            let mut best: Option<(f32, f32, f32, f32)> = None;
            for pad in &state.pickups {
                let Some(pad_weapon) = pad.kind.weapon() else {
                    continue;
                };
                if !pad.available || pad_weapon == WeaponType::Flechette {
                    continue;
                }
                let pdx = pad.x - bot.x;
                let pdz = pad.z - bot.z;
                let pdist = (pdx * pdx + pdz * pdz).sqrt();
                if pdist < 28.0 {
                    // Soft preference: matching role is closer in score space.
                    let role_bonus = match (want_scatter, pad_weapon) {
                        (true, WeaponType::Scatter) => 0.0,
                        (false, WeaponType::Rail) => 0.0,
                        _ => 6.0,
                    };
                    let score = pdist + role_bonus;
                    let take = match best {
                        Some((s, _, _, _)) => score < s,
                        None => true,
                    };
                    if take {
                        best = Some((score, pad.x, pad.z, pad.floor));
                    }
                }
            }
            if let Some((_, px, pz, floor)) = best {
                let pdx = px - bot.x;
                let pdz = pz - bot.z;
                let pdist = (pdx * pdx + pdz * pdz).sqrt();
                if nearest_dist > 10.0 || pdist < nearest_dist * 0.7 {
                    let pad_angle = pdz.atan2(pdx);
                    let mut pad_diff = pad_angle - bot.yaw;
                    while pad_diff > PI {
                        pad_diff -= 2.0 * PI;
                    }
                    while pad_diff < -PI {
                        pad_diff += 2.0 * PI;
                    }
                    if pad_diff.abs() > 0.2 {
                        if pad_diff > 0.0 {
                            action.turn_right = true;
                        } else {
                            action.turn_left = true;
                        }
                    }
                    action.forward = true;
                    if pad_diff.abs() < 0.5 && nearest_dist < 18.0 {
                        action.fire = true;
                    }
                    return BotIntent {
                        action,
                        goal: Some(crate::navigation::NavigationGoal {
                            feet: [px, floor, pz],
                            combat: false,
                        }),
                    };
                }
            }
        }

        // Hold the role lane for the weapon in hand.
        let (prefer_min, prefer_max) = bot.weapon.preferred_range();
        let fire_range = bot.weapon.range_units() * 0.95;
        let aim_slack = match bot.weapon {
            WeaponType::Fists | WeaponType::Shiv => 0.55,
            WeaponType::Tack => 0.40,
            WeaponType::Rail => 0.22,
            WeaponType::Scatter => 0.55,
            WeaponType::Flechette => 0.40,
        };

        match self.behavior {
            BotBehavior::Aggressive => {
                // Rush toward preferred band; Scatter push-in, Rail less so.
                if angle_diff.abs() > 0.2 {
                    if angle_diff > 0.0 {
                        action.turn_right = true;
                    } else {
                        action.turn_left = true;
                    }
                }
                if nearest_dist > prefer_min {
                    action.forward = true;
                } else if nearest_dist < prefer_min * 0.6 && bot.weapon != WeaponType::Scatter {
                    action.back = true;
                } else {
                    action.forward = true;
                }
                if angle_diff.abs() < aim_slack && nearest_dist < fire_range {
                    action.fire = true;
                }
            }

            BotBehavior::Defensive => {
                // Hold preferred band, strafe, precise shots (Rail-friendly).
                if angle_diff.abs() > 0.15 {
                    if angle_diff > 0.0 {
                        action.turn_right = true;
                    } else {
                        action.turn_left = true;
                    }
                }

                if nearest_dist < prefer_min {
                    action.back = true;
                } else if nearest_dist > prefer_max {
                    action.forward = true;
                } else if (state.tick % 40) < 20 {
                    action.left = true;
                } else {
                    action.right = true;
                }

                if angle_diff.abs() < aim_slack.min(0.3) && nearest_dist < fire_range {
                    action.fire = true;
                }
            }

            BotBehavior::Flanker => {
                if angle_diff.abs() > 0.25 {
                    if angle_diff > 0.0 {
                        action.turn_right = true;
                    } else {
                        action.turn_left = true;
                    }
                }

                if nearest_dist > prefer_max {
                    action.forward = true;
                } else {
                    action.forward = nearest_dist > prefer_min;
                    if (state.tick % 60) < 30 {
                        action.left = true;
                        action.turn_left = true;
                    } else {
                        action.right = true;
                        action.turn_right = true;
                    }
                }

                if angle_diff.abs() < aim_slack && nearest_dist < fire_range {
                    action.fire = true;
                }
            }

            BotBehavior::Balanced => {
                if angle_diff.abs() > 0.3 {
                    if angle_diff > 0.0 {
                        action.turn_right = true;
                    } else {
                        action.turn_left = true;
                    }
                }

                if nearest_dist > prefer_min {
                    action.forward = true;
                } else if nearest_dist < prefer_min * 0.7 {
                    action.back = true;
                }

                if angle_diff.abs() < aim_slack && nearest_dist < fire_range {
                    action.fire = true;
                }
            }

            BotBehavior::Compliance => {
                // Mid-range Rail enforcer: hold orbit, precise shots.
                if angle_diff.abs() > 0.12 {
                    if angle_diff > 0.0 {
                        action.turn_right = true;
                    } else {
                        action.turn_left = true;
                    }
                }
                if nearest_dist < prefer_min {
                    action.back = true;
                } else if nearest_dist > prefer_max {
                    action.forward = true;
                } else if (state.tick % 50) < 25 {
                    action.left = true;
                } else {
                    action.right = true;
                }
                if angle_diff.abs() < 0.25 && nearest_dist < fire_range {
                    action.fire = true;
                }
            }
        }

        BotIntent {
            action,
            goal: Some(crate::navigation::NavigationGoal {
                feet: [target.x, target.y - PLAYER_FLOOR_Y, target.z],
                combat: true,
            }),
        }
    }
}

#[cfg(test)]
mod live_status_tests {
    use super::GameState;
    use crate::protocol::Role;
    use uuid::Uuid;

    #[test]
    fn live_status_counts_joined_agents_apart_from_humans() {
        let mut state = GameState::new();
        state.add_player(Uuid::new_v4(), "Ada".into(), Role::Human);
        state.add_player(Uuid::new_v4(), "Probe".into(), Role::Agent);
        let live = state.live_status(3);
        assert_eq!(live.schema_version, 2);
        assert_eq!(live.kind, "arena");
        assert_eq!(live.humans, 1);
        assert_eq!(live.agents, 1);
        assert_eq!(live.bots, 0);
        assert_eq!(live.fighters, 2);
        assert_eq!(live.connections, 3);
        assert_eq!(live.map, "Arena Duel");
    }
}
