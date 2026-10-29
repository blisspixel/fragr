use serde::{Deserialize, Serialize};
use uuid::Uuid;

mod actors;
mod barks;
pub use barks::{BarkRegister, CompanionBarkKind, EnemyBarkKind, BARK_VARIANTS};
mod blade;
mod body;
mod podium;
pub use podium::{DuelRecord, Podium};
mod conquest;
mod decoration;
pub mod delta;
pub use delta::WorldReader;
mod explosive;
mod loadout;
mod m04;
mod m05;
mod m06;
mod m07;
mod m08;
pub mod quantize;
mod water;
pub(crate) use m08::M08NeutralLayout;
mod moon_residents;
pub(crate) use moon_residents::moon_residents;
mod m09;
mod m10;
mod m11;
mod m12;
mod m13;
mod m14;
pub use m14::{
    M14ChallengeState, M14MapGeometry, M14ObjectiveState, M14_FALLEN_PARTS, M14_OBJECTIVE_IDS,
};
mod m15;
pub use m15::{
    M15ChallengeState, M15MapGeometry, M15ObjectiveState, M15_ENTRANTS, M15_OBJECTIVE_IDS,
};
mod m16;
pub use m16::*;
mod m17;
pub use m17::*;
mod m18;
pub use m18::*;
mod m19;
pub use m19::*;
mod works;
pub use works::{JetpackState, PaverStripState, MAX_PAVER_STRIPS};
mod walker;
pub use m13::{
    M13ChallengeState, M13HazardCycle, M13HazardPhase, M13LiftPhase, M13LiftState, M13MapGeometry,
    M13ObjectiveState, M13WorkerResponse, M13_LIFT_SPEED, M13_OBJECTIVE_IDS, M13_WORKER_RESPONSES,
};
pub use walker::*;
mod m20;
pub use m20::*;
mod epilogue;
pub use epilogue::*;
mod mission;
mod rules;
mod sabotage;
mod spectator;
pub use spectator::{
    ChainFact, PadClock, PlateFact, SpectatorFacts, SpreeFact, MAX_SPECTATOR_PADS,
    MAX_SPECTATOR_RUNS, SPECTATOR_FACTS_EVERY_TICKS,
};
mod statistics;
mod status;
mod vehicle;
pub use actors::{
    hostile, AuditorState, CampaignActor, CompanionKind, CompanionPhase, ControlDomain, EnemyKind,
    EnemyPhase, SurveyorMarkState, AUDITOR_REPAIRS, SURVEYOR_MARK_RADIUS,
};
pub use blade::{ArticleBladeInfo, ArticleBladePhase, ArticleBladeState};
pub use body::BodyKind;
pub use conquest::{CapturePoint, ConquestState, CONQUEST_BLEED_TICKETS};
pub use decoration::{
    validate_decorations, MapDecoration, MapDecorationKind, MapFace, MAX_MAP_DECORATIONS,
    MAX_MAP_LIGHTS,
};
mod remote_mine;
pub use explosive::{
    AssessorCanisterState, ExplosionHit, ExplosionResult, GrenadeState, MinePhase, MineState,
    RocketState, MINE_ARMING_TICKS, MINE_TRIP_TICKS,
};
pub(crate) use loadout::validate_equipment;
pub use loadout::{
    AmmoCount, AmmoPool, EquipmentPolicy, LoadoutState, MagazineCount, SupplyClaim, MINE_CARRY_CAP,
};
pub use m04::{
    M04ClinicGeometry, M04MapGeometry, M04ObjectiveState, M04PatientGeometry, M04PatientState,
    M04_OBJECTIVE_IDS,
};
pub use m05::{
    M05MapGeometry, M05ObjectiveState, M05RescueGeometry, M05TramGeometry, M05TramPhase,
    M05TramState, M05WorkerGeometry, M05WorkerState, M05_OBJECTIVE_IDS, M05_WORKER_IDS,
};
pub use m06::{M06MapGeometry, M06ObjectiveState, M06_OBJECTIVE_IDS, M06_SERVICE_ID};
pub use m07::{M07MapGeometry, M07ObjectiveState, M07_OBJECTIVE_IDS};
pub use m08::{
    M08MapGeometry, M08NodeGeometry, M08ObjectiveState, M08_BAYS_ID, M08_CABINET_ID,
    M08_MACHINE_STEP, M08_NODES, M08_NODE_HP, M08_OBJECTIVE_IDS,
};
pub use m09::{
    M08Outcome, M09CrewGeometry, M09CrewState, M09MapGeometry, M09ObjectiveState, M09_CREW_IDS,
    M09_CREW_STEP, M09_OBJECTIVE_IDS,
};
pub use m10::{
    M10MapGeometry, M10ObjectiveState, M10PassengerGeometry, M10Transit, M10_OBJECTIVE_IDS,
};
pub use m11::{
    M11ChallengeState, M11MapGeometry, M11ObjectiveState, M11_OBJECTIVE_IDS, M11_SIGNAL_TICKS,
};
pub use m12::{
    M12AidVehicle, M12ChallengeState, M12MapGeometry, M12ObjectiveState, M12PumpGeometry,
    M12_OBJECTIVE_IDS, M12_PUMP_MAX_HP,
};
pub(crate) use mission::CampaignSupply;
pub use mission::{
    CampaignDifficulty, CampaignRules, CampaignRunState, CampaignRunStatus, InteractionKind,
    InteractionPrompt, M02EvacuationPhase, M02EvacuationState, M02ObjectiveState, M03CarGeometry,
    M03CarState, M03MapGeometry, M03MastGeometry, M03ObjectiveState, MissionContinue,
    MissionGeometry, MissionId, MissionMember, MissionObjective, MissionObjectiveAction,
    MissionPhase, MissionReady, MissionState, Region3, UseTarget, CAMPAIGN_CONTINUES,
    CAMPAIGN_RULES_REVISION, M03_MAST_MAX_HP, M03_MAX_CARS, MISSION_PARTY_LIMIT, USE_DISTANCE,
};
pub use remote_mine::{
    RemoteMinePhase, RemoteMineState, REMOTE_MINE_ARMING_TICKS, REMOTE_MINE_CARRY_CAP,
    REMOTE_MINE_TRIGGER_TICKS,
};
pub use rules::{
    GameMode, HostReactionKind, MatchRules, Mutator, Team, TeamScores, HOST_REACTION_VARIANTS,
};
pub use sabotage::{
    Callout, ChargeState, ChargeStatus, ProgressKind, SabotageEventKind, SabotageFormat,
    SabotageMap, SabotagePhase, SabotageProgress, SabotageReason, SabotageResult, SabotageSite,
    SabotageState, SiteId, MAX_CALLOUTS, MAX_CALLOUT_ID,
};
pub use statistics::{
    per_minute_tenths, ratio_scaled, wilson_thousandths, CombatCounts, PlayerRecord, RecordScope,
    RecordStatus, WeaponCounts, EIGHT_COLUMN_RECORD_VERSION, LEGACY_RECORD_VERSION,
    NINE_COLUMN_RECORD_VERSION, RECORD_TICKS_PER_SECOND, RECORD_VERSION, TEN_COLUMN_RECORD_VERSION,
};
pub use status::{
    BuildInfo, ClientRate, Health, HealthReason, HealthState, NightTotals, OpsStatus, ProcessInfo,
    RewindTotals, RoleCounts, TickSummary, TickTiming, TrafficTotals, OPS_VERSION,
};
pub use vehicle::{VehicleKind, VehicleSeat, VehicleState, MAX_VEHICLES, VEHICLE_GAMEPLAY_VERSION};
pub use water::{validate_water_regions, WaterRegion};

/// The arena's identity on the warmup card and the result card. The radio
/// station is small background flavour, never the match's name.
pub const MODE_NAME: &str = "Scrap League";
/// Playlist label under the league lie: map 1's display name.
pub const PLAYLIST_NAME: &str = "Larak Lot";
/// Desktop builds and `SHA256SUMS.txt`. Join does not fetch this URL.
pub const RELEASES_URL: &str = "https://github.com/blisspixel/fragr/releases/latest";

pub fn default_mode_name() -> String {
    MODE_NAME.to_string()
}

pub fn default_playlist() -> String {
    PLAYLIST_NAME.to_string()
}

/// The Host's plain arena intro: where, then go. He never explains the
/// setting and never chants.
pub fn default_host_line() -> String {
    "HOST: LARAK LOT IS LIVE.".to_string()
}

pub fn default_mode_id() -> String {
    GameMode::Ffa.id().to_string()
}

/// Map 1, Larak Lot, reworked from the Arena Duel field on 2026-10-23 with
/// its wire id unchanged.
pub const MAP_ID_ARENA_DUEL: u32 = 1;
pub const MAP_NAME_LARAK_LOT: &str = "Larak Lot";

pub fn default_map_id() -> u32 {
    MAP_ID_ARENA_DUEL
}

pub fn default_map_name() -> String {
    MAP_NAME_LARAK_LOT.to_string()
}

/// Public match line for a directory, an overlay, or a server list.
/// Counts and the map name only. No addresses, callsigns, or seeds.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct LiveStatus {
    pub schema_version: u32,
    /// `arena` or `campaign`. A missing kind is not an arena.
    pub kind: String,
    pub map: String,
    pub round: u32,
    pub tick: u64,
    pub fighters: usize,
    pub humans: usize,
    pub agents: usize,
    pub bots: usize,
    pub connections: usize,
    /// Additive to schema 2: the rule set's mode id, `ffa` when absent.
    #[serde(default = "default_mode_id")]
    pub mode: String,
    /// Additive to schema 2: mutator ids, omitted when none.
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub mutators: Vec<String>,
    /// Additive to schema 2. Absent until the tick loop's first refresh.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub health: Option<Health>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub ops: Option<OpsStatus>,
    /// Additive to schema 2. The gameplay contract this process speaks.
    /// Absent on an older host, and a missing value does not close Watch or Join.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub gameplay_version: Option<u32>,
    /// Additive to schema 2. The geometry contract this process speaks.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub geometry_version: Option<u32>,
}

impl Default for LiveStatus {
    fn default() -> Self {
        Self {
            schema_version: 2,
            kind: "arena".into(),
            map: default_map_name(),
            round: 1,
            tick: 0,
            fighters: 0,
            humans: 0,
            agents: 0,
            bots: 0,
            connections: 0,
            mode: default_mode_id(),
            mutators: Vec::new(),
            health: None,
            ops: None,
            gameplay_version: None,
            geometry_version: None,
        }
    }
}

/// Host line while Continuance compliance pressure is live.
pub fn compliance_host_line() -> String {
    "HOST: CONTINUANCE COMPLIANCE PING. APPROVED LANES ONLY.".to_string()
}

/// Host line while the Continuance Compliance Drone (NODS flavor) is on the floor.
pub fn boss_host_line() -> String {
    "HOST: CONTINUANCE COMPLIANCE DRONE ON DECK. ARTICLE 7 ENFORCEMENT.".to_string()
}

/// Host line after the Compliance Drone is fragged.
pub fn boss_down_host_line() -> String {
    "HOST: DRONE DOWN. CONTINUANCE DENIES THE INCIDENT. SCRAP ON.".to_string()
}

/// Host line when a live drone is wiped at round end (no frag credit).
pub fn boss_round_wipe_host_line() -> String {
    "HOST: TIME. DRONE RECALLED. NOBODY GETS THAT ONE.".to_string()
}

/// Host line for round-end MVP / podium.
pub fn mvp_host_line(mvp: &str, frags: u32) -> String {
    format!("HOST: ROUND MVP. {mvp} WITH {frags} FRAGS. CONTINUANCE DENIES THE PODIUM.")
}

/// Host line when a team round ends: the winning side and the score, or a draw.
pub fn team_round_host_line(winner: Option<Team>, scores: TeamScores) -> String {
    match winner {
        Some(team) => {
            let (win, lose) = (scores.get(team), scores.get(team.other()));
            format!(
                "HOST: {} TAKE THE ROUND, {win} TO {lose}. SAME RULES NEXT TIME.",
                team.name().to_uppercase()
            )
        }
        None => format!(
            "HOST: LEVEL AT THE BELL, {} ALL. NOBODY FILES A COMPLAINT.",
            scores.union
        ),
    }
}

/// Host line when a Sabotage round is decided. `score` is round wins by the
/// uniform each side wore in the round. The client keys its own words; this
/// is the English line for logs, MCP and older readers.
pub fn sabotage_round_host_line(
    winner: Team,
    reason: SabotageReason,
    score: TeamScores,
    match_over: bool,
) -> String {
    let how = match reason {
        SabotageReason::Elimination => "NOBODY LEFT ON THE OTHER SIDE",
        SabotageReason::Detonation => "THE CHARGE WENT UP",
        SabotageReason::Defused => "CHARGE DEFUSED",
        SabotageReason::Time => "THE CLOCK RAN OUT ON THE CHARGE",
    };
    let (win, lose) = (score.get(winner), score.get(winner.other()));
    if match_over {
        format!(
            "HOST: {how}. {} TAKE THE MATCH, {win} TO {lose}.",
            winner.name().to_uppercase()
        )
    } else {
        format!(
            "HOST: {how}. {} TAKE THE ROUND, {win} TO {lose}.",
            winner.name().to_uppercase()
        )
    }
}

/// Host line when a lives-limited round ends with one fighter left, or none.
pub fn last_fighter_host_line(survivor: Option<&str>) -> String {
    match survivor {
        Some(name) => format!(
            "HOST: LAST ONE STANDING. {} WALKS OUT.",
            name.to_uppercase()
        ),
        None => "HOST: NOBODY LEFT STANDING. THE BOOTH CALLS IT EVEN.".to_string(),
    }
}

/// Host line when a round ends with no scored MVP.
pub fn empty_mvp_host_line() -> String {
    "HOST: ROUND CLOSED. NO MVP. LEAGUE DENIES THE SCRAP.".to_string()
}

/// Sticky Warmup / mid-join Host line naming the rule-bot roster.
pub fn roster_host_line(names: &[String]) -> String {
    if names.is_empty() {
        return default_host_line();
    }
    let listed = format_roster_names(names);
    format!("HOST: {listed} ON THE SCRAP.")
}

fn format_roster_names(names: &[String]) -> String {
    let upper: Vec<String> = names.iter().map(|n| n.to_uppercase()).collect();
    if upper.len() <= 4 {
        upper.join(", ")
    } else {
        format!("{}, +{}", upper[..3].join(", "), upper.len() - 3)
    }
}

/// The Warmup intro: the venue, who is on it and the countdown. A plain
/// arena intro, never a station ident.
pub fn warmup_host_line(map_name: &str, names: &[String], secs_left: u32) -> String {
    let map = map_name.to_uppercase();
    let secs = secs_left.max(1);
    if names.is_empty() {
        return format!("HOST: {map}. GOES LIVE IN {secs}.");
    }
    let listed = format_roster_names(names);
    format!("HOST: {map}. {listed} ON THE SCRAP. GOES LIVE IN {secs}.")
}

/// RoundStart Host line once Warmup ends (map + roster, fight energy, no countdown).
pub fn round_open_host_line(map_name: &str, names: &[String]) -> String {
    let map = map_name.to_uppercase();
    if names.is_empty() {
        return format!("HOST: {map} IS LIVE. FIGHT!");
    }
    let listed = format_roster_names(names);
    format!("HOST: {map}. {listed} ON THE SCRAP. FIGHT!")
}

/// Beat that triggers a rule-bot speak line.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BotTauntKind {
    Frag,
    Death,
    Killstreak,
    Warmup,
}

/// Strip overflow refill suffix (`Kind Regards-2` -> `Kind Regards`).
pub fn rule_bot_callsign_base(name: &str) -> &str {
    if let Some((base, suffix)) = name.rsplit_once('-') {
        if !suffix.is_empty() && suffix.chars().all(|c| c.is_ascii_digit()) {
            return base;
        }
    }
    name
}

/// Callsign-flavored taunt for a named scrap rule bot. Roster callsigns
/// (and their `-N` overflow copies) speak their own lines from
/// [`crate::roster`]; any other name gets the league's stock lines.
pub fn rule_bot_taunt_line(name: &str, kind: BotTauntKind, salt: u64) -> String {
    let pool: &[&str] = match crate::roster::find(name) {
        Some(fighter) => fighter.taunts(kind),
        None => match kind {
            BotTauntKind::Frag => &["clean 67", "meatproxy down"],
            BotTauntKind::Death => &["back in a sec", "bricked for now"],
            BotTauntKind::Killstreak => &["host is watching", "six-seven streak"],
            BotTauntKind::Warmup => &["gearing up", "scrap warming"],
        },
    };
    let idx = (salt as usize) % pool.len();
    pool[idx].to_string()
}

/// Display name for the mid-round Continuance boss NPC (NODS-flavored Compliance Drone).
pub const BOSS_NAME: &str = "COMPLIANCE-DRONE";

/// Solo Broadcast Episode 0 id.
pub const EPISODE_ID_EP0: &str = "ep0";
/// Solo Broadcast Episode 0 title face.
pub const EPISODE_TITLE_EP0: &str = "Solo Broadcast: Calibration";
/// Larak Lot map face for Episode 0 (geometry may reuse map 1).
pub const EPISODE_MAP_LARAK_LOT: &str = "Larak Lot";
/// Continuance Auditor elite display name (Compliance Drone retitled).
pub const AUDITOR_NAME: &str = "AUDITOR";

pub fn episode0_host_line_cold_open() -> String {
    "HOST: In the morning. Calibration night. Continuance brought NODS. You're in the league."
        .to_string()
}

pub fn episode0_host_line_nods() -> String {
    "HOST: Null-Objective Drones don't trash-talk. That's how you know they're approved."
        .to_string()
}

/// Short Scrap League Host tick per credited NODS clear (rate-sane: one line per clear).
pub fn episode0_host_line_nods_tick(cleared: u32, goal: u32) -> String {
    match cleared {
        0 => episode0_host_line_cold_open(),
        1 => episode0_host_line_nods(),
        2 => format!("HOST: NODS {cleared}/{goal}. Another approved lane goes dark."),
        3 => format!("HOST: NODS {cleared}/{goal}. Continuance is sweating the spreadsheet."),
        4 => format!("HOST: NODS {cleared}/{goal}. One more and the dish wakes up."),
        n => format!("HOST: NODS {n}/{goal}. Keep the scrap going."),
    }
}

pub fn episode0_host_line_jammer() -> String {
    "HOST: Jammer's up. Step onto the pad and seize it or I go text-only. Value for value."
        .to_string()
}

pub fn episode0_host_line_auditor() -> String {
    "HOST: Auditor on the lot. Clipboard shield. Smile for the audit.".to_string()
}

pub fn episode0_host_line_win() -> String {
    "HOST: Amen, fistbump. The league stays open.".to_string()
}

pub fn episode0_host_line_fail() -> String {
    "HOST: Citizen Handle assigned. Reload.".to_string()
}

pub fn episode0_objective_chip() -> String {
    "Clear NODS. Seize jammer dish. Drop the Auditor.".to_string()
}

pub fn episode0_unlock_teaser() -> String {
    "Callsign stub unlocked. Next: Area Kitchen.".to_string()
}

pub fn default_pickup_kind() -> String {
    "weapon".to_string()
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq, Default)]
#[serde(rename_all = "snake_case")]
pub enum WeaponType {
    #[default]
    Flechette,
    Rail,
    Scatter,
    Fists,
    Tack,
    /// Pool-less melee found as an M01 secret: faster and harder than fists.
    Shiv,
    /// Level 7 find: slow, tight, long precision hitscan fed by Cells.
    Sniper,
    /// Sustained-fire discovery prototype with server-owned warmup.
    Repeater,
    /// M12 find: bounded Cells discharge that bypasses carried armor and plates.
    Arc,
    /// Discovery projectile. Direct damage plus covered splash. Not an arcade gun.
    Rocket,
    /// Borrowed arena blade with finite swings and return to plinth.
    ArticleBlade,
}

/// The scatter gun deals full damage inside this distance.
pub const SCATTER_FULL_DAMAGE_UNITS: f32 = 4.0;
/// Inside this distance a scatter pellet is a meatshot: the barrel against
/// the body, every pellet landing, one blast through a bare fighter.
pub const SCATTER_MEATSHOT_UNITS: f32 = 2.0;
/// Damage of one meatshot pellet: seven make 105.
pub const SCATTER_MEATSHOT_PELLET: i32 = 15;
/// Pellets in one scatter blast, Doom's shotgun count.
pub const SCATTER_PELLETS: usize = 7;
/// And this share of it at the edge of its reach.
pub const SCATTER_FAR_DAMAGE_SCALE: f32 = 0.35;

/// Ticks past a weapon's cadence before a participant's grown cone starts to
/// recover (see `WeaponType::bloom_per_shot`).
pub const BLOOM_GRACE_TICKS: u32 = 2;
/// Share of the full cone recovered per tick once recovery starts: a full
/// cone is exact again 0.35 s later.
pub const BLOOM_RECOVERY_PER_TICK: f32 = 1.0 / 7.0;

impl WeaponType {
    /// Damage on a clean body hit, before the scatter gun's range falloff and
    /// before a head band doubles a traced pellet. For the scatter gun this is
    /// per pellet: seven pellets make 70 in the full band, Doom's average
    /// blast, and a meatshot closer in makes 105 (`damage_at`).
    /// Four body flechette hits, two full-band scatter blasts, or two body
    /// rail hits kill an unarmoured fighter, which puts every weapon's body
    /// time to kill inside the 0.6 to 1.2 second band in `docs/plans/gunfeel.md`.
    /// Fists, the Shiv and the Article Blade do not gain the head bonus.
    pub fn damage(self) -> i32 {
        match self {
            WeaponType::Fists | WeaponType::Tack => 20,
            // Three cuts kill a bare fighter in 0.60 s; fists need five in 1.60 s.
            WeaponType::Shiv => 35,
            WeaponType::Flechette => 25,
            WeaponType::Rail => 80,
            // One aimed hit answers one 70 HP Ranged Sweeper. A Sweeper needs
            // two, where one Rail hit drops it: the Rail owns the middle.
            WeaponType::Sniper => 70,
            WeaponType::Repeater => 14,
            WeaponType::Arc => 18,
            WeaponType::Scatter => 10,
            // Direct component only. Covered splash is resolved with the projectile.
            WeaponType::Rocket => 65,
            WeaponType::ArticleBlade => 70,
        }
    }

    /// Rays in one shot. Every pellet is tested against cover and fighters on
    /// its own; one shot still spends one unit of ammunition.
    pub fn pellets(self) -> usize {
        match self {
            WeaponType::Scatter => SCATTER_PELLETS,
            _ => 1,
        }
    }

    /// Damage at a distance. Only the scatter gun changes with it: a
    /// meatshot inside `SCATTER_MEATSHOT_UNITS` (seven pellets make 105, one
    /// blast through a bare fighter), full damage to
    /// `SCATTER_FULL_DAMAGE_UNITS`, then linearly down to
    /// `SCATTER_FAR_DAMAGE_SCALE` of it at the edge of its reach, the banded
    /// shape modern shooters use because it reads at a glance.
    pub fn damage_at(self, distance: f32) -> i32 {
        let base = self.damage();
        if self != WeaponType::Scatter {
            return base;
        }
        let near = SCATTER_FULL_DAMAGE_UNITS;
        let far = self.range_units();
        if distance.is_finite() && distance <= SCATTER_MEATSHOT_UNITS {
            return SCATTER_MEATSHOT_PELLET;
        }
        if !distance.is_finite() || distance <= near {
            return base;
        }
        if distance >= far {
            return (base as f32 * SCATTER_FAR_DAMAGE_SCALE).round() as i32;
        }
        let t = (distance - near) / (far - near);
        let scale = 1.0 - t * (1.0 - SCATTER_FAR_DAMAGE_SCALE);
        (base as f32 * scale).round().max(1.0) as i32
    }

    /// Ticks between shots at the 20 Hz tick: 0.20 s, 1.00 s, 0.60 s.
    pub fn cooldown_ticks(self) -> u32 {
        match self {
            WeaponType::Fists => 8,
            WeaponType::Shiv => 6,
            WeaponType::Tack => 5,
            WeaponType::Flechette => 4,
            WeaponType::Rail => 20,
            WeaponType::Sniper => 32,
            WeaponType::Repeater => 2,
            WeaponType::Arc => 3,
            WeaponType::Scatter => 12,
            WeaponType::Rocket => 16,
            WeaponType::ArticleBlade => 9,
        }
    }

    /// Half-angle of the dispersion cone. A shot leaves the barrel somewhere
    /// inside it, which is what a player learns to manage. This is not aim
    /// assistance: a shot still has to pass within a fighter's radius to land.
    pub fn spread_radians(self) -> f32 {
        match self {
            WeaponType::Fists | WeaponType::Shiv | WeaponType::ArticleBlade => 0.0,
            WeaponType::Tack => 0.03,
            // Mid workhorse: 2.6 degrees, forgiving in its own band.
            WeaponType::Flechette => 0.045,
            // Long precision: 0.7 degrees, near enough to a laser to reward aim.
            WeaponType::Rail => 0.012,
            // Far precision: 0.23 degrees keeps every ray inside a 0.5 m body
            // radius out to the full 90 m reach.
            WeaponType::Sniper => 0.004,
            WeaponType::Repeater => 0.035,
            WeaponType::Arc => 0.02,
            // Pellet cone: 5.4 degrees. Every pellet lands inside a body at
            // four units and about half of them still do at eight.
            WeaponType::Scatter => 0.095,
            WeaponType::Rocket => 0.0,
        }
    }

    /// How much of the dispersion cone one participant shot adds, as a share
    /// of `spread_radians`. A participant's first shot flies along the exact
    /// aim ray; sustained fire grows the cone by this much a shot up to the
    /// full table value (about a second of holding the trigger), and a pause
    /// longer than the cadence lets it recover. Zero means always exact. The
    /// Scatter keeps its whole pellet cone, and authored enemies always fire
    /// the table cone.
    pub fn bloom_per_shot(self) -> f32 {
        match self {
            WeaponType::Tack => 0.25,
            WeaponType::Flechette => 0.2,
            WeaponType::Repeater => 0.1,
            WeaponType::Arc => 0.15,
            WeaponType::Fists
            | WeaponType::Shiv
            | WeaponType::ArticleBlade
            | WeaponType::Rail
            | WeaponType::Sniper
            | WeaponType::Scatter
            | WeaponType::Rocket => 0.0,
        }
    }

    /// Max hitscan reach in world units. Caps roles so Scatter is close-only
    /// and Rail owns long lanes (arena is ~50 across).
    pub fn range_units(self) -> f32 {
        match self {
            WeaponType::Fists => 1.8,
            WeaponType::Shiv => 2.2,
            WeaponType::ArticleBlade => 2.0,
            WeaponType::Tack => 30.0,
            WeaponType::Flechette => 40.0,
            WeaponType::Rail => 60.0,
            WeaponType::Sniper => 90.0,
            WeaponType::Repeater => 35.0,
            WeaponType::Arc => 24.0,
            WeaponType::Scatter => 12.0,
            WeaponType::Rocket => 72.0,
        }
    }

    /// Preferred bot engagement band (min, max) for role play.
    pub fn preferred_range(self) -> (f32, f32) {
        match self {
            WeaponType::Fists => (0.0, 1.5),
            WeaponType::Shiv => (0.0, 1.9),
            WeaponType::ArticleBlade => (0.0, 1.8),
            WeaponType::Tack => (5.0, 18.0),
            WeaponType::Flechette => (8.0, 28.0),
            WeaponType::Rail => (18.0, 45.0),
            WeaponType::Sniper => (40.0, 88.0),
            WeaponType::Repeater => (7.0, 26.0),
            WeaponType::Arc => (6.0, 18.0),
            WeaponType::Scatter => (2.0, 10.0),
            WeaponType::Rocket => (8.0, 40.0),
        }
    }

    pub fn name(self) -> &'static str {
        match self {
            WeaponType::Fists => "Fists",
            WeaponType::Shiv => "Shiv",
            WeaponType::Tack => "Tack",
            WeaponType::Flechette => "Flechette",
            WeaponType::Rail => "Rail",
            WeaponType::Sniper => "Sniper",
            WeaponType::Repeater => "Repeater",
            WeaponType::Arc => "Arc",
            WeaponType::Scatter => "Scatter",
            WeaponType::Rocket => "Rocket",
            WeaponType::ArticleBlade => "Article Blade",
        }
    }

    /// Energy discharge leaves armor intact while ordinary protection and
    /// world collision still apply. Plate owners use the same property.
    pub const fn ignores_armor(self) -> bool {
        matches!(self, Self::Arc)
    }
}

/// Highest solid format this build understands, including earlier formats.
pub const GEOMETRY_VERSION: u32 = 2;

pub const DISCOVERY_GAMEPLAY_VERSION: u32 = 2;
pub const CAMPAIGN_GAMEPLAY_VERSION: u32 = 3;
pub const MISSION_GAMEPLAY_VERSION: u32 = 4;
pub const READINESS_GAMEPLAY_VERSION: u32 = 5;
pub const DIFFICULTY_GAMEPLAY_VERSION: u32 = 6;
pub const CONTINUES_GAMEPLAY_VERSION: u32 = 7;
pub const RECORD_GAMEPLAY_VERSION: u32 = 8;
pub const M02_GAMEPLAY_VERSION: u32 = 9;
/// One ammunition count per type with no magazines or reload, and scatter
/// pellet traces. Every discovery map requires it for the loadout shape.
pub const AMMO_GAMEPLAY_VERSION: u32 = 10;
/// The pool-less Shiv in loadouts, shot traces and six-slot records, plus the
/// secret flag on pickup events and the optional record secret count. Every
/// discovery map requires it because any authored map may place the Shiv.
pub const SHIV_GAMEPLAY_VERSION: u32 = 11;
/// Match rule sets (sides, lives, the golden Railgun, keyed Host reactions)
/// and the 100 Cells cap. Every discovery map requires it for the larger
/// loadout. A shared room requires `GAMEPLAY_VERSION`, not this floor.
pub const RULES_GAMEPLAY_VERSION: u32 = 12;
/// The chosen participant body: an optional `body` on Hello, the accepted
/// body on Welcome and on every participant in a snapshot. Additive: no map
/// requires it, and an older reader ignores the field.
pub const BODY_GAMEPLAY_VERSION: u32 = 13;
/// Capture the flag state and events. The objective arrived at this
/// capability. A shared room requires `GAMEPLAY_VERSION`, not this floor.
pub const CTF_GAMEPLAY_VERSION: u32 = 14;
/// Optional seated opening posture on authored Union Clerks. M02 requires
/// this so an older presenter cannot mistake its first fight for standing guards.
pub const SEATED_GUARD_GAMEPLAY_VERSION: u32 = 15;
/// A low Crawler body, a timed leap and an audible encounter cue.
pub const CRAWLER_GAMEPLAY_VERSION: u32 = 16;
/// M02 projects ward victory before Latch's later release action.
pub const LATCH_RELEASE_GAMEPLAY_VERSION: u32 = 17;
pub const RUN_CARRY_GAMEPLAY_VERSION: u32 = 18;
pub const COMPANION_GAMEPLAY_VERSION: u32 = 19;
pub const SIDE_WARD_GAMEPLAY_VERSION: u32 = 20;
/// Server-owned, visible M02 captive evacuation after the optional side ward.
pub const EVACUATION_GAMEPLAY_VERSION: u32 = 21;
/// M02's ballistic inspection glass, which older strict surface readers cannot render.
pub const INSPECTION_GLASS_GAMEPLAY_VERSION: u32 = 22;
/// Highest understood gameplay contract; content requirements use their own minimum.
/// Authored Jammer actors and their visible traveling interference attacks.
pub const JAMMER_GAMEPLAY_VERSION: u32 = 23;
pub const M03_GAMEPLAY_VERSION: u32 = 24;
/// M04 clinic, flying Notary, photograph outcomes and roof departure.
pub const M04_GAMEPLAY_VERSION: u32 = 25;
pub const M05_GAMEPLAY_VERSION: u32 = 26;
pub const M06_GAMEPLAY_VERSION: u32 = 27;
/// Sabotage sites, charge, round state and results. The objective arrived at
/// this capability. A shared room requires `GAMEPLAY_VERSION`, not this floor.
pub const SABOTAGE_GAMEPLAY_VERSION: u32 = 28;
/// The found Proximity Mine (`place_mine`, `proximity_mines`, snapshot `mines`,
/// record `mines`) and the repairing `auditor` with its `channeling` phase.
/// Required only where a map grants mines or places an Auditor.
pub const CUSTODY_GAMEPLAY_VERSION: u32 = 29;
/// The found Sniper Rifle (`sniper` in loadouts, traces, pickups and seven-slot
/// records) and the stationary `ranged_sweeper` marksman. Required only where a
/// map grants the Sniper or places a Ranged Sweeper.
pub const SNIPER_GAMEPLAY_VERSION: u32 = 30;
/// Custodian of Record's strict `m08` geometry and mission facts and the
/// `custodian_of_record` mission id. Required only on M08.
pub const M08_GAMEPLAY_VERSION: u32 = 31;

/// Declared Goods: strict M07 geometry and facts, the depot freight departure
/// and retained earlier outcomes. Required only on M07.
pub const M07_GAMEPLAY_VERSION: u32 = 32;
/// Optional frozen mission elapsed time on completed private records.
pub const MISSION_RESULTS_GAMEPLAY_VERSION: u32 = 33;
/// Passenger Manifest and its committed human Enforcer charge.
pub const M09_GAMEPLAY_VERSION: u32 = 34;
/// Repeater identity, server warmup and strict eight-column record revision 2.
pub const REPEATER_GAMEPLAY_VERSION: u32 = 35;
pub const M10_GAMEPLAY_VERSION: u32 = 36;
/// Human magazines. The carried count stays the total, including rounds in
/// each gun. Agents, rule bots and campaign enemies keep the single count.
/// A shared arcade room requires the highest supported contract.
pub const RELOAD_GAMEPLAY_VERSION: u32 = 37;
/// Right of Search includes deliberate charges and the Redactor.
pub const M11_GAMEPLAY_VERSION: u32 = 38;
/// Capture sites and tickets on the original island venue.
pub const CONQUEST_GAMEPLAY_VERSION: u32 = 40;
/// Registered water, swimming, boat hulls and flyable light aircraft.
pub const WATER_GAMEPLAY_VERSION: u32 = 41;
/// Arc Cells discharge, armor bypass and strict nine-column record revision 3.
pub const ARC_GAMEPLAY_VERSION: u32 = 42;
pub const ASSESSOR_GAMEPLAY_VERSION: u32 = 43;
pub const M12_GAMEPLAY_VERSION: u32 = 44;
pub const LOW_WATER_SABOTAGE_GAMEPLAY_VERSION: u32 = 45;
/// Rocket Launcher flight, the `rockets` pool, ten-column records and save 16.
/// Required wherever a rocket can exist, for every role. Arcade rooms use the
/// highest contract. The foundry places the first campaign launcher.
pub const ROCKET_GAMEPLAY_VERSION: u32 = 46;
pub const M13_GAMEPLAY_VERSION: u32 = 47;
pub const M14_GAMEPLAY_VERSION: u32 = 49;
pub const WALKER_GAMEPLAY_VERSION: u32 = 48;
/// Article Blade melee, plinth lifecycle, eleven-column records and range contract.
pub const BLADE_GAMEPLAY_VERSION: u32 = 50;
/// Civic Pressure Valve connected stadium bout, two door systems, armed entrants and takeover.
pub const M15_GAMEPLAY_VERSION: u32 = 51;
/// Freedom of Movement connected ceremonial avenue, motorcycle traversal, green wave and chamber doors.
pub const M16_GAMEPLAY_VERSION: u32 = 52;
/// Peace Without Interruption connected Forever Office, three door states, Kessel custody and Voss capture.
pub const M17_GAMEPLAY_VERSION: u32 = 53;
/// All Systems Normal connected transit evacuation, clinic roadblock, overlook recon and concourse defense.
pub const M18_GAMEPLAY_VERSION: u32 = 54;
/// Single-schema campaign receipts: the carried M08 outcome loses its `kind`
/// tag and M10 practice transit is `unlinked`. Required for M09 and M10.
pub const RECEIPT_GAMEPLAY_VERSION: u32 = 55;
/// Free-for-all Pistol and Fists start, owned guns from the map, the
/// `full-arsenal` mutator and `rules.start_kit`.
pub const SIDEARM_GAMEPLAY_VERSION: u32 = RECEIPT_GAMEPLAY_VERSION;
/// Planned Works connected Low Water escape: the issued jetpack (snapshot
/// `jetpacks`, Ack `jet_fuel`), the Paver and its `paver_strips`, and the
/// waterworks departure. None of contract 55's parts shipped alone, so the
/// receipts, the Pistol start and Planned Works share it.
pub const M19_GAMEPLAY_VERSION: u32 = RECEIPT_GAMEPLAY_VERSION;
/// Local Exception: the Surveyor, its tracking mark and convergence, the
/// pier hold clock, refuge barricade, reprieve stand-down and campaign victory.
pub const M20_GAMEPLAY_VERSION: u32 = 56;
/// Still Here: the survival-gated epilogue, its two worlds, the people the
/// run carried and the read-only survival entitlement.
pub const STILL_HERE_GAMEPLAY_VERSION: u32 = 57;
/// The booth: `spectator_facts` for spectator connections only, each
/// fighter's measured `ping`, and pads that publish no live return clock.
pub const BOOTH_GAMEPLAY_VERSION: u32 = 58;
/// Highest gameplay contract this binary speaks. Shared arcade rooms require
/// this value. Campaign missions keep their own floor; higher hellos refuse.
/// Guns dropped on death, the Duel line and seat calls, the Conquest bleed
/// call and the hand-over call.
pub const ARENA_RULES_GAMEPLAY_VERSION: u32 = 59;
/// Side-addressed speak lines: a rule bot's objective callouts carry the
/// `team` they are said to, and a reader that ignored it would show one
/// side's calls to the other.
pub const SIDE_CALLS_GAMEPLAY_VERSION: u32 = 60;
/// Bounded hitscan lag compensation: a human Action may carry `view_tick`,
/// the server tick its client was drawing others at. An older strict Action
/// reader refuses the field, so a shared room moves to this contract.
pub const LAG_COMP_GAMEPLAY_VERSION: u32 = 62;
/// Snapshot deltas (`snapshot_delta`, see `protocol::delta`) in their current
/// shape: a reader at this contract may receive a world as the change from
/// the one it holds, with carried fighters keyed by base roster position
/// rather than id. Gameplay 61 introduced deltas keyed by id; that shape is
/// no longer sent, so a reader at 61 or 62 receives every world whole.
pub const DELTA_GAMEPLAY_VERSION: u32 = 63;
pub const GAMEPLAY_VERSION: u32 = DELTA_GAMEPLAY_VERSION;
pub fn legacy_gameplay_version() -> u32 {
    1
}
fn is_legacy_gameplay(version: &u32) -> bool {
    *version == 1
}
fn is_false(value: &bool) -> bool {
    !value
}

fn is_zero_u32(value: &u32) -> bool {
    *value == 0
}

pub fn legacy_geometry_version() -> u32 {
    1
}

fn is_legacy_geometry(version: &u32) -> bool {
    *version == legacy_geometry_version()
}

pub fn geometry_version(solids: &[crate::movement::Solid]) -> u32 {
    if solids.iter().any(|solid| solid.bottom != 0.0) {
        GEOMETRY_VERSION
    } else {
        legacy_geometry_version()
    }
}

pub fn validate_map_geometry(
    half: f32,
    solids: &[crate::movement::Solid],
    version: u32,
) -> Result<(), &'static str> {
    if !(1..=GEOMETRY_VERSION).contains(&version) || version < geometry_version(solids) {
        return Err("unsupported or inconsistent geometry version");
    }
    crate::movement::validate_geometry(half, solids)
}

/// Registered offline surface kits. Content cannot supply shader or asset paths.
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum MapSurface {
    Concrete,
    Enamel,
    ServiceSteel,
    RecordsTile,
    LiftPanel,
    InspectionGlass,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct MapPresentation {
    pub ground: MapSurface,
    /// One registered kit for each collision solid, in exactly the same order.
    pub solids: Vec<MapSurface>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub decorations: Vec<MapDecoration>,
}

pub fn validate_map_presentation(
    presentation: Option<&MapPresentation>,
    solids: &[crate::movement::Solid],
) -> Result<(), &'static str> {
    if let Some(presentation) = presentation {
        if presentation.solids.len() != solids.len() {
            return Err("map surfaces do not match the geometry");
        }
        validate_decorations(&presentation.decorations, solids)?;
    }
    Ok(())
}

#[cfg(test)]
mod geometry_tests {
    use super::*;
    use crate::movement::Solid;

    #[test]
    fn legacy_wire_defaults_and_raised_volume_requirements_are_explicit() {
        let hello: ClientMessage =
            serde_json::from_str(r#"{"type":"hello","role":"human","name":"Probe"}"#).unwrap();
        assert!(matches!(
            hello,
            ClientMessage::Hello {
                geometry_version: 1,
                ticket: None,
                resume: None,
                ..
            }
        ));
        let legacy =
            crate::sim::GameState::with_map(crate::sim::MapKind::ComplianceYard, false).map_info();
        let value = serde_json::to_value(&legacy).unwrap();
        assert!(value.get("geometry_version").is_none());
        assert!(value["solids"]
            .as_array()
            .unwrap()
            .iter()
            .all(|solid| solid.get("bottom").is_none()));
        let ground = [Solid::from_center(0.0, 0.0, 2.0, 2.0)];
        let raised = [Solid::from_center_volume(0.0, 0.0, 2.0, 2.0, 2.4, 3.0)];
        assert_eq!(geometry_version(&ground), 1);
        assert_eq!(geometry_version(&raised), 2);
        assert!(validate_map_geometry(12.0, &ground, 1).is_ok());
        assert!(validate_map_geometry(12.0, &raised, 2).is_ok());
        for version in [0, 1, 3] {
            assert!(validate_map_geometry(12.0, &raised, version).is_err());
        }
        assert!(validate_map_geometry(f32::NAN, &raised, 2).is_err());
        let message = ServerMessage::MapInfo {
            water_regions: Vec::new(),
            rules: None,
            presentation: None,
            mission: None,
            m02_objectives: None,
            m02_side_ward: false,
            m03: None,
            m04: None,
            m05: None,
            m06: None,
            m08: None,
            m07: None,
            m09: None,
            m10: None,
            m11: None,
            m12: None,
            m13: None,
            m14: None,
            m15: None,
            m16: None,
            m17: None,
            m18: None,
            m19: None,
            walker: None,
            m20: None,
            epilogue: None,
            article_blade: None,
            map_id: 67,
            map_name: "Enclosed fixture".into(),
            half_extent: 12.0,
            solids: raised.to_vec(),
            geometry_version: 2,
            sabotage: None,
        };
        let json = serde_json::to_string(&message).unwrap();
        assert!(!json.contains("m02_side_ward"));
        assert!(!json.contains("m07"));
        assert!(!json.contains("m08"));
        assert!(
            matches!(serde_json::from_str::<ServerMessage>(&json).unwrap(),
            ServerMessage::MapInfo { geometry_version: 2, solids, .. } if solids == raised)
        );
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum ClientMessage {
    Hello {
        role: Role,
        name: String,
        #[serde(
            default = "legacy_gameplay_version",
            skip_serializing_if = "is_legacy_gameplay"
        )]
        gameplay_version: u32,
        /// Maximum supported geometry format. Omission means ground-filled boxes.
        #[serde(
            default = "legacy_geometry_version",
            skip_serializing_if = "is_legacy_geometry"
        )]
        geometry_version: u32,
        /// Present only when the server was started with a join secret.
        #[serde(default, skip_serializing_if = "Option::is_none")]
        ticket: Option<String>,
        /// Empty asks for a resume token. A token rebinds a parked pawn.
        /// Absent means a drop removes the pawn, which is what older clients do.
        #[serde(default, skip_serializing_if = "Option::is_none")]
        resume: Option<String>,
        /// Requested participant body. Omitted means human. Ignored for a
        /// spectator, and a resumed pawn keeps the body it already has.
        #[serde(default, skip_serializing_if = "Option::is_none")]
        body: Option<BodyKind>,
        /// A Duel seat's one-time token from `SeatCall` (capability 59).
        /// While a seat is held for somebody, only the fighter Hello carrying
        /// its token is admitted. Never logged.
        #[serde(default, skip_serializing_if = "Option::is_none")]
        seat: Option<String>,
    },
    /// Explicit leave. A later socket close removes the pawn now.
    Leave,
    Action(Action),
    MissionReady(MissionReady),
    MissionContinue(MissionContinue),
    Speak(Speak),
    /// Process-local wire. Older servers ignore the type. It is not a combat fact.
    Board(BoardRequest),
    /// Agent-only display label echoed into Snapshot PlayerState.behavior.
    /// Never trusted for combat. Rule-bot behaviors still come from BotController.
    SetDisplayBehavior(SetDisplayBehavior),
    /// A Duel watcher joins the line for the next seat, or leaves it
    /// (capability 59). Ignored from a fighter and outside Duel.
    Queue(QueueRequest),
}

/// `{"type":"queue","wait":true}`: wait for a Duel seat; false steps out.
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(deny_unknown_fields)]
pub struct QueueRequest {
    pub wait: bool,
}

#[allow(clippy::large_enum_variant)] // Snapshot carries round chrome; boxing churns every tick.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum ServerMessage {
    Welcome {
        player_id: Option<Uuid>,
        role: Role,
        #[serde(default = "default_mode_name")]
        mode_name: String,
        #[serde(default = "default_playlist")]
        playlist: String,
        /// Set for a human or agent that asked to keep the pawn across a drop.
        #[serde(default, skip_serializing_if = "Option::is_none")]
        resume: Option<String>,
        /// The accepted body of a human or agent pawn. Omitted for a
        /// spectator and by servers before capability 13.
        #[serde(default, skip_serializing_if = "Option::is_none")]
        body: Option<BodyKind>,
        /// Present and true only when this server accepts a held `Action.duck`.
        /// Older servers omit it. Absence means the client must not send the key.
        #[serde(default, skip_serializing_if = "is_false")]
        duck: bool,
    },
    /// The arena's shape: the bounds and the solids that block movement and
    /// shots. Sent once to every role on join and again to everyone when
    /// the map changes, never per tick, because it does not change per tick.
    /// Agents need it to tell a clear shot from a wall; the Godot client has
    /// the same geometry in its scene.
    MapInfo {
        map_id: u32,
        map_name: String,
        /// Half width of the square arena, centred on the origin.
        half_extent: f32,
        solids: Vec<crate::movement::Solid>,
        #[serde(
            default = "legacy_geometry_version",
            skip_serializing_if = "is_legacy_geometry"
        )]
        geometry_version: u32,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        presentation: Option<MapPresentation>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        mission: Option<MissionGeometry>,
        /// Present only for M02 maps. The count binds mission state to this map.
        #[serde(default, skip_serializing_if = "Option::is_none")]
        m02_objectives: Option<u8>,
        /// True only when this M02 map authors the optional side-ward encounter.
        #[serde(default, skip_serializing_if = "is_false")]
        m02_side_ward: bool,
        /// Static Scheduled Service contract, refreshed with the prepared mast world.
        #[serde(default, skip_serializing_if = "Option::is_none")]
        m03: Option<M03MapGeometry>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        m04: Option<M04MapGeometry>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        m05: Option<M05MapGeometry>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        m06: Option<M06MapGeometry>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        m08: Option<M08MapGeometry>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        m07: Option<M07MapGeometry>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        m09: Option<M09MapGeometry>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        m10: Option<M10MapGeometry>,
        #[serde(
            default,
            deserialize_with = "m11::present",
            skip_serializing_if = "Option::is_none"
        )]
        m11: Option<M11MapGeometry>,
        #[serde(
            default,
            deserialize_with = "m11::present",
            skip_serializing_if = "Option::is_none"
        )]
        m12: Option<M12MapGeometry>,
        #[serde(
            default,
            deserialize_with = "m11::present",
            skip_serializing_if = "Option::is_none"
        )]
        m13: Option<M13MapGeometry>,
        #[serde(
            default,
            deserialize_with = "m11::present",
            skip_serializing_if = "Option::is_none"
        )]
        m14: Option<M14MapGeometry>,
        #[serde(
            default,
            deserialize_with = "m11::present",
            skip_serializing_if = "Option::is_none"
        )]
        m15: Option<M15MapGeometry>,
        #[serde(
            default,
            deserialize_with = "m11::present",
            skip_serializing_if = "Option::is_none"
        )]
        m16: Option<M16MapGeometry>,
        #[serde(
            default,
            deserialize_with = "m11::present",
            skip_serializing_if = "Option::is_none"
        )]
        m17: Option<M17MapGeometry>,
        #[serde(
            default,
            deserialize_with = "m11::present",
            skip_serializing_if = "Option::is_none"
        )]
        m18: Option<M18MapGeometry>,
        #[serde(
            default,
            deserialize_with = "m11::present",
            skip_serializing_if = "Option::is_none"
        )]
        m19: Option<M19MapGeometry>,
        #[serde(
            default,
            deserialize_with = "m11::present",
            skip_serializing_if = "Option::is_none"
        )]
        walker: Option<WalkerGeometry>,
        #[serde(
            default,
            deserialize_with = "m11::present",
            skip_serializing_if = "Option::is_none"
        )]
        m20: Option<M20MapGeometry>,
        #[serde(
            default,
            deserialize_with = "m11::present",
            skip_serializing_if = "Option::is_none"
        )]
        epilogue: Option<EpilogueMapGeometry>,
        /// The arena's rule set. Omitted on authored campaign maps.
        #[serde(default, skip_serializing_if = "Option::is_none")]
        rules: Option<MatchRules>,
        /// Sabotage sites and callouts. Present only on a Sabotage server.
        #[serde(default, skip_serializing_if = "Option::is_none")]
        sabotage: Option<SabotageMap>,
        /// Bounded water volumes used by swimming, hulls and presentation.
        #[serde(default, skip_serializing_if = "Vec::is_empty")]
        water_regions: Vec<WaterRegion>,
        /// Registered Article Blade plinth facts.
        #[serde(default, skip_serializing_if = "Option::is_none")]
        article_blade: Option<ArticleBladeInfo>,
    },
    Mission {
        tick: u64,
        state: MissionState,
    },
    Snapshot(Snapshot),
    Loadout(LoadoutState),
    Record(PlayerRecord),
    Event(GameEvent),
    /// Unicast acknowledgement of the newest input applied to this client's
    /// fighter, with the authoritative state it produced. Sent every tick to a
    /// client that numbers its inputs; the basis for client-side prediction.
    Ack {
        seq: u32,
        tick: u64,
        x: f32,
        z: f32,
        yaw: f32,
        #[serde(default)]
        pitch: f32,
        /// Optional post-tick body state for replay-aware human clients.
        #[serde(default, skip_serializing_if = "Option::is_none")]
        movement: Option<MovementAck>,
        /// Ticks until this fighter's server respawn attempt, present only
        /// while it is down and awaiting an arcade respawn. The respawn runs
        /// on tick `tick + respawn_ticks`. Presentation only: a client cannot
        /// request or advance it.
        #[serde(default, skip_serializing_if = "Option::is_none")]
        respawn_ticks: Option<u32>,
    },
    /// Unicast control-plane rejection (e.g. speak rate limit). Not broadcast.
    Error {
        code: String,
        message: String,
    },
    /// Unicast answer for the connection that asked. Not broadcast.
    Board(BoardPage),
    /// The booth: live pad clocks, the Custody Plate, sprees and open
    /// multikill chains. Broadcast only to spectator connections, never to
    /// a connection that holds a fighter, and never on a campaign map.
    SpectatorFacts(SpectatorFacts),
    /// Unicast to the watcher at the head of the Duel line when a seat is
    /// theirs (capability 59): reconnect as a fighter with `seat` in the
    /// Hello within ten seconds. Nobody else is admitted to a held seat.
    SeatCall {
        seat: String,
    },
    /// Unicast to a Duel watcher whenever its place in line changes
    /// (capability 59): `place` from 1, or 0 when it is not in line; `of`
    /// the line's length. The shared `duel_queue` names can repeat, so this
    /// is how a watcher knows which entry is its own.
    QueuePlace {
        place: u32,
        of: u32,
    },
}

/// Additive full-body extension to the legacy Ack root fields. An absent block
/// means the server does not provide a replayable movement baseline.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(deny_unknown_fields)]
pub struct MovementAck {
    pub version: u32,
    /// A new body/input ownership baseline. Never used to rewind server ticks.
    pub epoch: u64,
    /// Whether this tick produced a replayable movement step for this pawn.
    pub applied: bool,
    /// World-reference height, matching Snapshot PlayerState.y.
    pub y: f32,
    /// Post-collision velocity in world units per second.
    pub vx: f32,
    pub vy: f32,
    pub vz: f32,
    /// Speed chosen before collision, zero on an unapplied tick.
    pub effective_speed: f32,
    /// Jump request passed to movement integration, not proof of takeoff.
    pub jump_input: bool,
    /// Server ticks left before this fighter may dodge again, after this tick.
    pub dodge_cooldown: u32,
    /// Worn jetpack fuel after this step, for replay from this body. Omitted
    /// without a pack; prediction then uses the ordinary step.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub jet_fuel: Option<u16>,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum Role {
    Spectator,
    /// Human-operated participant, affectionately a meat proxy in the setting.
    Human,
    /// Connection/control role, not a claim about consciousness or agency.
    Agent,
}

/// World-point or player-id aim target. Server applies yaw and pitch.
#[derive(Debug, Clone, Serialize, Deserialize, Default, PartialEq)]
#[serde(deny_unknown_fields)]
pub struct LookAt {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub x: Option<f32>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub y: Option<f32>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub z: Option<f32>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub player_id: Option<Uuid>,
}

/// Off-tick callout / taunt (control plane, not sticky Action).
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(deny_unknown_fields)]
pub struct Speak {
    pub text: String,
}

/// One pull on the process-local wire. `list` names the boards. `read` returns
/// one. `post` writes a notice. The floor is filled by speak, not by post.
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum BoardOp {
    List,
    Read,
    Post,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(deny_unknown_fields)]
pub struct BoardRequest {
    pub op: BoardOp,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub board: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub text: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(deny_unknown_fields)]
pub struct BoardCard {
    pub id: String,
    pub count: u32,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(deny_unknown_fields)]
pub struct BoardLine {
    pub tick: u64,
    pub name: String,
    pub text: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(deny_unknown_fields)]
pub struct BoardPage {
    pub op: BoardOp,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub board: Option<String>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub boards: Vec<BoardCard>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub lines: Vec<BoardLine>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub code: Option<String>,
}

/// Observe-only stance / tactics chip for Agent clients (control plane).
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(deny_unknown_fields)]
pub struct SetDisplayBehavior {
    pub behavior: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
#[serde(deny_unknown_fields)]
pub struct Action {
    /// Optional vehicle seat request. It uses the ordinary action ingress.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub seat: Option<VehicleSeat>,
    #[serde(default)]
    pub forward: bool,
    #[serde(default)]
    pub back: bool,
    #[serde(default)]
    pub left: bool,
    #[serde(default)]
    pub right: bool,
    /// Held. A grounded fighter leaves the floor on the first tick it is set.
    #[serde(default)]
    pub jump: bool,
    /// Rising-edge ground dodge toward the held movement keys. A press
    /// survives newer released input until one tick observes it. Ignored in
    /// the air, with no direction held, or during the dodge cooldown.
    #[serde(default, skip_serializing_if = "is_false")]
    pub dodge: bool,
    /// Ready-up on the podium: this fighter wants the next round now. Read
    /// only while an arena round has ended; ignored everywhere else.
    #[serde(default, skip_serializing_if = "is_false")]
    pub again: bool,
    #[serde(default)]
    pub turn_left: bool,
    #[serde(default)]
    pub turn_right: bool,
    #[serde(default)]
    pub fire: bool,
    /// Rising-edge use request. Release before pressing a second time.
    #[serde(default, skip_serializing_if = "is_false")]
    pub interact: bool,
    /// Rising-edge counted grenade throw, independent of selected weapon.
    #[serde(default, skip_serializing_if = "is_false")]
    pub throw_grenade: bool,
    /// Rising-edge proximity mine placement, independent of selected weapon.
    #[serde(default, skip_serializing_if = "is_false")]
    pub place_mine: bool,
    /// Rising-edge reload of the selected gun. Omitted unless pressed, so an
    /// older server that has never heard of magazines does not see the key.
    /// A pawn without magazines ignores it.
    #[serde(default, skip_serializing_if = "is_false")]
    pub reload: bool,
    /// Held crouch. Omitted unless pressed, so an older server that rejects
    /// unknown fields does not drop the rest of the input. The server publishes
    /// the resolved stance, not this bit.
    #[serde(default, skip_serializing_if = "is_false")]
    pub duck: bool,
    /// Rising-edge placement from the independent Remote Mine stock.
    #[serde(default, skip_serializing_if = "is_false")]
    pub place_remote_mine: bool,
    /// Rising-edge trigger of every currently armed owned Remote Mine.
    #[serde(default, skip_serializing_if = "is_false")]
    pub trigger_remote_mines: bool,
    #[serde(default)]
    pub weapon_swap: Option<WeaponType>,
    /// Agent target aim. A shared-room human socket drops this field. The
    /// server does not aim that pawn. Yaw and pitch remain the human aim.
    /// A campaign socket and an in-process controller may still send it.
    /// A player target is the chest when the belt is clearly open, the hips
    /// when a counter, a lip, or a gap says so, or world x/z with optional y.
    /// Omitting y for a world point means horizontal aim.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub look_at: Option<LookAt>,
    /// Client-owned absolute facing in radians. When present the server takes
    /// it as the fighter's yaw for this input instead of turning at a fixed
    /// rate from the turn bits, so the look axis never round-trips the network.
    /// Non-finite values are ignored. Agents may send it or keep the bits.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub yaw: Option<f32>,
    /// Absolute vertical aim, positive upward, clamped to +/-85 degrees.
    /// Missing values preserve aim. Non-finite values are ignored.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub pitch: Option<f32>,
    /// Input sequence number. The server acknowledges the newest sequence it
    /// applied so a predicting client can reconcile. Absent for clients that
    /// do not predict.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub seq: Option<u32>,
    /// The fractional server tick this human client was drawing other
    /// fighters at when it sampled the input (gameplay 62). A hint, not
    /// authority: the server refuses a view that is not finite, negative or
    /// newer than the newest tick it has produced, and rewinds a hitscan
    /// shot no further than 200 ms. Absent means no rewind. Agents, rule
    /// bots and older clients send none; an agent's view is ignored.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub view_tick: Option<f64>,
}

/// One server-owned point still in flight. Absent from the snapshot when none are.
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
pub struct ProjectileState {
    pub id: u32,
    pub x: f32,
    pub y: f32,
    pub z: f32,
}

/// Per-tick fire outcome for observe (hit-confirm without vision).
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct ShotResult {
    pub shooter_id: Uuid,
    pub shooter: String,
    pub hit: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub target_id: Option<Uuid>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub target: Option<String>,
    pub damage: i32,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub target_hp_after: Option<i32>,
    /// Current servers include complete evidence even when the shooter dies.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub trace: Option<ShotTrace>,
    /// True only for the shot that first takes this target to zero HP.
    #[serde(default)]
    pub killed: bool,
    /// A pellet of this result struck the head band and doubled damage that
    /// landed. Presentation only (the shooter's headshot confirm); `damage`
    /// already counts it. Omitted when false.
    #[serde(default, skip_serializing_if = "std::ops::Not::not")]
    pub head: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct ShotTrace {
    /// Resolved mount identity, retained when its gunner leaves or dies.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub vehicle_id: Option<u32>,
    pub weapon: WeaponType,
    /// Points are rounded to the millimetre on the wire only.
    #[serde(serialize_with = "quantize::wire_point")]
    pub origin: [f32; 3],
    /// The first pellet of this result when `pellets` is present.
    #[serde(serialize_with = "quantize::wire_point")]
    pub end: [f32; 3],
    pub impact: ShotImpact,
    /// Scatter only: every pellet this result covers, in firing order, all
    /// from `origin`. At most `SCATTER_PELLETS`. Empty and omitted otherwise.
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub pellets: Vec<PelletTrace>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct PelletTrace {
    #[serde(serialize_with = "quantize::wire_point")]
    pub end: [f32; 3],
    pub impact: ShotImpact,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub enum ShotImpact {
    Fighter { normal: [f32; 3] },
    Solid { normal: [f32; 3] },
    Range,
}

/// Floor pickup pad state (weapon / health / armor; authoritative mid-map).
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct PickupState {
    #[serde(default, skip_serializing_if = "loadout::is_contested")]
    pub claim: SupplyClaim,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub pool: Option<AmmoPool>,
    pub id: String,
    #[serde(default = "default_pickup_kind")]
    pub kind: String,
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub weapon: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub amount: Option<i32>,
    pub x: f32,
    pub y: f32,
    pub z: f32,
    pub available: bool,
    /// A gun a fragged fighter dropped (`sim::drops`): it lies where they
    /// fell for a short while, carries `amount` rounds and never returns.
    /// Omitted for a pad.
    #[serde(default, skip_serializing_if = "is_false")]
    pub dropped: bool,
}

impl PickupState {
    /// The pad's published return clock in ticks. A regular learns these
    /// numbers, and a joined agent's observe uses them: the snapshot carries
    /// no live timer. Only the booth (`SpectatorFacts`) does.
    /// Free-for-all clocks depend on the gun (`crate::rules`), so the pad's
    /// `weapon` name picks the clock exactly as the server does. A clock a map
    /// authors for one pad (Larak Lot's Custody Plate, 35 s) is not on the
    /// wire, so that pad reads as its kind's sheet clock here.
    pub fn clock_ticks(&self, teams: bool) -> u32 {
        let weapon = (self.kind == "weapon").then(|| {
            WeaponType::ALL
                .into_iter()
                .find(|weapon| weapon.name() == self.weapon)
                .unwrap_or(WeaponType::Flechette)
        });
        let health_or_armor = matches!(self.kind.as_str(), "health" | "armor");
        crate::rules::pad_respawn_ticks(teams, weapon, health_or_armor).unwrap_or(
            if health_or_armor {
                crate::sim::HEALTH_PICKUP_RESPAWN_TICKS
            } else {
                crate::sim::SUPPLY_PICKUP_RESPAWN_TICKS
            },
        )
    }
}

/// Solo Broadcast jammer dish world marker (arena center soft-touch).
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct JammerDishState {
    pub x: f32,
    pub y: f32,
    pub z: f32,
    /// True while phase is jammer and the dish is seizeable.
    pub live: bool,
    /// True after soft-touch seize.
    pub seized: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Snapshot {
    #[serde(
        default,
        deserialize_with = "m11::present",
        skip_serializing_if = "Option::is_none"
    )]
    pub walker: Option<WalkerState>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub vehicles: Vec<VehicleState>,
    pub tick: u64,
    pub players: Vec<PlayerState>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub round_state: Option<String>,
    /// Seconds left on the round clock. Absent during sudden death, when the
    /// clock is stopped.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub round_time_left: Option<u32>,
    /// The clock ran out level (or a level Sabotage match reached its
    /// decider round): the next score wins. Omitted when false.
    #[serde(default, skip_serializing_if = "is_false")]
    pub sudden_death: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub frag_limit: Option<u32>,
    /// Shots resolved on this tick (empty omitted on wire).
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub shot_results: Vec<ShotResult>,
    /// Points still in flight. Omitted when nothing is traveling.
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub projectiles: Vec<ProjectileState>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub grenades: Vec<GrenadeState>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub assessor_canisters: Vec<AssessorCanisterState>,
    /// Live rockets. Omitted when none are in flight, so an older reader that
    /// never meets one still accepts the snapshot.
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub rockets: Vec<RocketState>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub mines: Vec<MineState>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub remote_mines: Vec<RemoteMineState>,
    /// Living campaign Auditors and their repair channels.
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub auditors: Vec<AuditorState>,
    /// Marked Paver strips while prepared or worked. Omitted when none.
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub paver_strips: Vec<PaverStripState>,
    /// Worn jetpacks and their fuel. Omitted when nobody wears one.
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub jetpacks: Vec<JetpackState>,
    /// Live Surveyor discs, each projected by one living Surveyor.
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub surveyor_marks: Vec<SurveyorMarkState>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub explosions: Vec<ExplosionResult>,
    /// Scrap League (the independent league that denies it exists).
    #[serde(default = "default_mode_name")]
    pub mode_name: String,
    /// Larak Lot under the league lie.
    #[serde(default = "default_playlist")]
    pub playlist: String,
    /// Live pressure beat id when Continuance is squeezing the round.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub pressure: Option<String>,
    /// Sticky Scrap League Host chrome (mid-join / observe).
    #[serde(default = "default_host_line")]
    pub host_line: String,
    /// Round MVP while Ended (mid-join / observe rehydrate). Omitted otherwise.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub mvp: Option<String>,
    /// MVP frag count while Ended.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub mvp_frags: Option<u32>,
    /// Mid-map pads: weapons, health, armor (Quake chase energy). Empty omitted on wire.
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub pickups: Vec<PickupState>,
    /// Scrap League scrap layout id (1 = Larak Lot, 2 = Compliance Yard).
    #[serde(default = "default_map_id")]
    pub map_id: u32,
    /// Human-readable scrap layout name.
    #[serde(default = "default_map_name")]
    pub map_name: String,
    /// Solo Broadcast episode id (e.g. ep0). Omitted on MP.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub episode_id: Option<String>,
    /// Episode title card face.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub episode_title: Option<String>,
    /// Short objective chip.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub episode_objective: Option<String>,
    /// Progress chip (NODS n/N | JAMMER | AUDITOR).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub episode_progress: Option<String>,
    /// Phase: nods / jammer / auditor / won / failed.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub episode_phase: Option<String>,
    /// Jammer dish world marker while Solo Broadcast episode is live on jammer/seize.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub jammer_dish: Option<JammerDishState>,
    /// Side frags this round. Present only in team modes.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub team_scores: Option<TeamScores>,
    /// Two objective flags, one for each side, only in capture the flag.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub flags: Option<[FlagState; 2]>,
    /// Captures, independent of frags.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub capture_scores: Option<TeamScores>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub capture_limit: Option<u32>,
    /// The Sabotage round: phase, clock, charge, progress and score by round.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub sabotage: Option<SabotageState>,
    /// Capture sites and retained tickets on a Conquest server.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub conquest: Option<ConquestState>,
    /// Article Blade plinth and possession facts.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub article_blade: Option<ArticleBladeState>,
    /// Between rounds: the ready-up for the next one and a Duel's series.
    /// Present only while a round has ended and somebody is waited for or a
    /// series exists.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub podium: Option<Podium>,
    /// Duel: the watchers waiting for a seat, first in line first
    /// (capability 59). Omitted while nobody waits.
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub duel_queue: Vec<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum FlagStatus {
    Home,
    Carried,
    Dropped,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct FlagState {
    pub team: Team,
    pub stand: [f32; 3],
    pub position: [f32; 3],
    pub status: FlagStatus,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub carrier: Option<Uuid>,
    /// Remaining ticks before automatic return, present only when dropped.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub return_ticks: Option<u32>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum FlagEventKind {
    Taken,
    Dropped,
    Returned,
    Captured,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PlayerState {
    /// Additive body-contact eligibility. Historical snapshots default to true.
    /// A published row is explicit. Parked, eliminated, and respawning bodies are omitted.
    #[serde(default = "collidable_by_default")]
    pub collidable: bool,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub campaign: Option<CampaignActor>,
    pub id: Uuid,
    pub name: String,
    /// Position and look are rounded on the wire only (`protocol::quantize`):
    /// the millimetre and 1e-4 rad. The sim keeps the exact values.
    #[serde(serialize_with = "quantize::wire_position")]
    pub x: f32,
    #[serde(serialize_with = "quantize::wire_position")]
    pub y: f32,
    #[serde(serialize_with = "quantize::wire_position")]
    pub z: f32,
    #[serde(serialize_with = "quantize::wire_angle")]
    pub yaw: f32,
    #[serde(default, serialize_with = "quantize::wire_angle")]
    pub pitch: f32,
    pub hp: i32,
    #[serde(default)]
    pub armor: i32,
    pub just_fired: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub behavior: Option<String>,
    pub score: u32,
    /// Deaths this round. Omitted while zero. The hold-Tab board reads this
    /// from the snapshot. The frag event does not increment it.
    #[serde(default, skip_serializing_if = "is_zero_u32")]
    pub deaths: u32,
    /// Gun and fist shots this round. Grenades and mines stay off this
    /// denominator. Omitted while zero. Saturates at `u32::MAX`.
    #[serde(default, skip_serializing_if = "is_zero_u32")]
    pub attacks: u32,
    /// Shots whose pellets found a body, including a shield or a teammate that
    /// lost nothing. Omitted while zero.
    #[serde(default, skip_serializing_if = "is_zero_u32")]
    pub connects: u32,
    /// Connects with at least one pellet in the head band. Omitted while zero.
    #[serde(default, skip_serializing_if = "is_zero_u32")]
    pub heads: u32,
    /// HP and armor removed by this fighter's guns, grenades and mines.
    /// Overkill is excluded. Omitted while zero.
    #[serde(default, skip_serializing_if = "is_zero_u32")]
    pub damage: u32,
    pub weapon: String,
    /// The fighter's side in a team mode. Omitted otherwise.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub team: Option<Team>,
    /// Lives left this round when lives are limited, this one included.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub lives: Option<u8>,
    /// Holds the golden Railgun. Omitted when false.
    #[serde(default, skip_serializing_if = "is_false")]
    pub golden: bool,
    /// Short stance. Omitted while standing. True while the key is held or a
    /// low ceiling will not allow the standing body. Shot volume, eye, and
    /// contact height follow it.
    #[serde(default, skip_serializing_if = "is_false")]
    pub ducking: bool,
    /// The participant's accepted body. Omitted for Union and companion
    /// campaign actors and the arena boss, which keep their own identity.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub body: Option<BodyKind>,
    /// Round trip to this fighter's connection in milliseconds, measured by
    /// the server's WebSocket pings. Omitted for rule bots, campaign actors,
    /// a fighter whose connection has not answered a ping yet, and a pawn
    /// held for a dropped connection.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub ping: Option<u16>,
}

fn collidable_by_default() -> bool {
    true
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PlayerScore {
    pub name: String,
    pub score: u32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "event", rename_all = "snake_case")]
pub enum GameEvent {
    /// A nearby Crawler encounter wakes before its first visible attack.
    CrawlerScrabble {
        position: [f32; 3],
    },
    /// Union squad radio from one speaking body: rare and spaced. The
    /// client owns the words for `kind`, `register` and `variant`.
    EnemyBark {
        kind: EnemyBarkKind,
        register: BarkRegister,
        /// `0..BARK_VARIANTS`, rotated per kind and register.
        variant: u8,
        speaker_id: Uuid,
        /// The speaker's feet, for the spatial voice.
        position: [f32; 3],
    },
    /// A companion's callout to the party, on the same spaced channel.
    CompanionBark {
        kind: CompanionBarkKind,
        /// The enemy kind a priority callout names. Omitted otherwise.
        #[serde(default, skip_serializing_if = "Option::is_none")]
        subject: Option<EnemyKind>,
        /// `0..BARK_VARIANTS`, rotated per kind and subject.
        variant: u8,
        speaker_id: Uuid,
        position: [f32; 3],
    },
    /// A Sabotage fact everyone hears: the charge changing hands, a plant or
    /// defuse starting, stopping or finishing, the detonation and the swap.
    Sabotage {
        kind: SabotageEventKind,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        player: Option<String>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        player_id: Option<Uuid>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        site: Option<SiteId>,
        /// Round wins by current uniform.
        score: TeamScores,
    },
    Flag {
        kind: FlagEventKind,
        flag: Team,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        player: Option<String>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        player_id: Option<Uuid>,
        capture_scores: TeamScores,
    },
    Frag {
        killer: String,
        victim: String,
        killer_score: u32,
        /// Accepted participant identities, including bodies already absent.
        #[serde(default, skip_serializing_if = "Option::is_none")]
        killer_id: Option<Uuid>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        victim_id: Option<Uuid>,
        /// Resolved source only. Untyped explosions leave this absent.
        #[serde(default, skip_serializing_if = "Option::is_none")]
        weapon: Option<WeaponType>,
        /// Sides in a team mode, for killfeed colours. Omitted otherwise.
        #[serde(default, skip_serializing_if = "Option::is_none")]
        killer_team: Option<Team>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        victim_team: Option<Team>,
    },
    /// Non-lethal or pre-frag damage. Structured hit-confirm for agents.
    Hit {
        shooter: String,
        shooter_id: Uuid,
        target: String,
        target_id: Uuid,
        damage: i32,
        target_hp_after: i32,
    },
    Respawn {
        player: String,
    },
    RoundStart {
        round_number: u32,
        frag_limit: Option<u32>,
        time_limit: Option<u32>,
        players: Vec<String>,
        previous_winner: Option<String>,
        #[serde(default = "default_mode_name")]
        mode_name: String,
        #[serde(default = "default_playlist")]
        playlist: String,
        #[serde(default = "default_host_line")]
        host_line: String,
        /// The arena's rule set, repeated each round for event readers.
        #[serde(default, skip_serializing_if = "Option::is_none")]
        rules: Option<MatchRules>,
    },
    RoundEnd {
        winner: Option<String>,
        reason: String,
        final_scores: Vec<PlayerScore>,
        winner_score: Option<u32>,
        /// Round MVP (top score / frags). Same player as winner when scores exist.
        #[serde(default, skip_serializing_if = "Option::is_none")]
        mvp: Option<String>,
        /// MVP frag count (mirrors winner_score for agents / podium chrome).
        #[serde(default, skip_serializing_if = "Option::is_none")]
        mvp_frags: Option<u32>,
        /// Scrap League Host bumper for round-end podium.
        #[serde(default = "default_host_line")]
        host_line: String,
        /// Team modes: the side that won, or omitted for a draw.
        #[serde(default, skip_serializing_if = "Option::is_none")]
        winning_team: Option<Team>,
        /// Team modes: the final side frags.
        #[serde(default, skip_serializing_if = "Option::is_none")]
        team_scores: Option<TeamScores>,
        /// Capture the flag: final capture counts, independent of frags.
        #[serde(default, skip_serializing_if = "Option::is_none")]
        capture_scores: Option<TeamScores>,
        /// Sabotage: why the round was decided, the score by round and the
        /// match result once it is decided.
        #[serde(default, skip_serializing_if = "Option::is_none")]
        sabotage: Option<SabotageResult>,
    },
    PlayerJoined {
        player: String,
        role: String,
        round_number: u32,
        player_count: usize,
    },
    PlayerLeft {
        player: String,
        score: u32,
        round_number: u32,
        player_count: usize,
    },
    /// Mid-round Continuance compliance pressure (Host bumper + move slow).
    CompliancePing {
        message: String,
        duration_ticks: u32,
    },
    /// Mid-round Continuance Compliance Drone spawn (killable boss beat).
    BossSpawn {
        name: String,
        boss_id: Uuid,
        message: String,
        hp: i32,
    },
    /// Compliance Drone fragged (no respawn).
    BossDown {
        name: String,
        boss_id: Uuid,
        #[serde(skip_serializing_if = "Option::is_none")]
        killer: Option<String>,
        message: String,
    },
    /// Mid-map pad claimed (weapon swap, heal, or armor scrap).
    Pickup {
        player: String,
        player_id: Uuid,
        #[serde(default = "default_pickup_kind")]
        kind: String,
        #[serde(default, skip_serializing_if = "String::is_empty")]
        weapon: String,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        amount: Option<i32>,
        pickup_id: String,
        /// The claim found an authored secret. Omitted when false.
        #[serde(default, skip_serializing_if = "is_false")]
        secret: bool,
    },
    /// A Host beat from an authoritative fact. The client owns the words,
    /// keyed by kind and variant; names fill its placeholders. Multikills
    /// and spree tiers are kinds here too.
    HostReaction {
        kind: HostReactionKind,
        /// `0..HOST_REACTION_VARIANTS`, rotated so a regular hears them all.
        variant: u8,
        /// The fighter the beat is about.
        #[serde(default, skip_serializing_if = "Option::is_none")]
        player: Option<String>,
        /// The other fighter involved, such as who ended a streak.
        #[serde(default, skip_serializing_if = "Option::is_none")]
        other: Option<String>,
        /// The side the beat is about.
        #[serde(default, skip_serializing_if = "Option::is_none")]
        team: Option<Team>,
        /// A big moment the Host voices (`HostReactionKind::big`). Omitted
        /// for a text-only caption.
        #[serde(default, skip_serializing_if = "is_false")]
        big: bool,
    },
    /// Off-tick agent/human callout (rate-limited, length-capped).
    Speak {
        player: String,
        player_id: Uuid,
        text: String,
        /// The one fighter a line is said to, when it is said to someone: a
        /// rule bot's frag taunt names its victim here ("deleted you"), and a
        /// client shows it only from that fighter's point of view. Absent for
        /// lines meant for the whole room.
        #[serde(default, skip_serializing_if = "Option::is_none")]
        to_id: Option<Uuid>,
        /// The side a line is said to (capability 60): a rule bot's objective
        /// callout ("i have the flag") is for its own side. The session
        /// delivers it only to that side's fighters and to spectators, never
        /// as a broadcast, so the speaker's id never reaches the other side.
        /// Absent for lines meant for the whole room.
        #[serde(default, skip_serializing_if = "Option::is_none")]
        team: Option<Team>,
    },
    /// One ordinary sentence from the person running the venue. Not a player
    /// callout and not an on-air Host line.
    VenueNotice {
        text: String,
    },
    /// Solo Broadcast episode cold open / title card.
    EpisodeStart {
        id: String,
        title: String,
        objective: String,
        host_line: String,
        map_name: String,
    },
    /// Solo Broadcast episode win.
    EpisodeComplete {
        id: String,
        reason: String,
        host_line: String,
        unlock_teaser: String,
    },
    /// Solo Broadcast episode fail (Citizen Handle assigned).
    EpisodeFail {
        id: String,
        reason: String,
        host_line: String,
    },
}

#[cfg(test)]
mod protocol_tests {
    use super::*;

    #[test]
    fn unknown_action_field_fails_deserialize() {
        let json = r#"{"type":"action","forward":true,"laser":true}"#;
        let parsed: Result<ClientMessage, _> = serde_json::from_str(json);
        assert!(
            parsed.is_err(),
            "unknown Action field must fail: {:?}",
            parsed
        );
    }

    #[test]
    fn valid_action_deserializes() {
        let json = r#"{"type":"action","forward":true,"fire":true}"#;
        let parsed: Result<ClientMessage, _> = serde_json::from_str(json);
        assert!(parsed.is_ok(), "{:?}", parsed);
        match parsed.unwrap() {
            ClientMessage::Action(a) => {
                assert!(a.forward);
                assert!(a.fire);
                assert!(!a.back);
                assert!(a.look_at.is_none());
            }
            other => panic!("expected Action, got {:?}", other),
        }
    }

    #[test]
    fn look_at_player_id_deserializes() {
        let id = Uuid::new_v4();
        let json = format!(r#"{{"type":"action","look_at":{{"player_id":"{}"}}}}"#, id);
        let parsed: ClientMessage = serde_json::from_str(&json).expect("look_at action");
        match parsed {
            ClientMessage::Action(a) => {
                let look = a.look_at.expect("look_at present");
                assert_eq!(look.player_id, Some(id));
                assert!(look.x.is_none());
                assert!(look.z.is_none());
            }
            other => panic!("expected Action, got {:?}", other),
        }
    }

    #[test]
    fn look_at_world_xz_deserializes() {
        let json = r#"{"type":"action","look_at":{"x":10.0,"z":-5.0}}"#;
        let parsed: ClientMessage = serde_json::from_str(json).expect("look_at xz");
        match parsed {
            ClientMessage::Action(a) => {
                let look = a.look_at.expect("look_at present");
                assert_eq!(look.x, Some(10.0));
                assert_eq!(look.z, Some(-5.0));
                assert!(look.player_id.is_none());
            }
            other => panic!("expected Action, got {:?}", other),
        }
    }

    #[test]
    fn unknown_look_at_field_fails_deserialize() {
        let json = r#"{"type":"action","look_at":{"x":1.0,"z":2.0,"laser":true}}"#;
        let parsed: Result<ClientMessage, _> = serde_json::from_str(json);
        assert!(
            parsed.is_err(),
            "unknown LookAt field must fail: {:?}",
            parsed
        );
    }

    #[test]
    fn shot_result_and_hit_event_round_trip() {
        let shooter_id = Uuid::new_v4();
        let target_id = Uuid::new_v4();
        let shot = ShotResult {
            trace: None,
            killed: false,
            head: false,
            shooter_id,
            shooter: "A".into(),
            hit: true,
            target_id: Some(target_id),
            target: Some("B".into()),
            damage: 25,
            target_hp_after: Some(75),
        };
        let snap = Snapshot {
            vehicles: Vec::new(),
            team_scores: None,
            flags: None,
            capture_scores: None,
            capture_limit: None,
            tick: 1,
            players: vec![],
            round_state: None,
            round_time_left: None,
            sudden_death: false,
            frag_limit: None,
            shot_results: vec![shot.clone()],
            projectiles: vec![],
            grenades: Vec::new(),
            assessor_canisters: Vec::new(),
            walker: None,
            rockets: Vec::new(),
            mines: Vec::new(),
            remote_mines: Vec::new(),
            auditors: Vec::new(),
            paver_strips: Vec::new(),
            jetpacks: Vec::new(),
            surveyor_marks: Vec::new(),
            explosions: Vec::new(),
            mode_name: default_mode_name(),
            playlist: default_playlist(),
            pressure: None,
            host_line: default_host_line(),
            mvp: None,
            mvp_frags: None,
            pickups: vec![],
            map_id: default_map_id(),
            map_name: default_map_name(),
            episode_id: None,
            episode_title: None,
            episode_objective: None,
            episode_progress: None,
            episode_phase: None,
            jammer_dish: None,
            sabotage: None,
            conquest: None,
            article_blade: None,
            podium: None,
            duel_queue: Vec::new(),
        };
        let v = serde_json::to_value(&snap).unwrap();
        assert_eq!(v["shot_results"][0]["hit"], true);
        assert_eq!(v["shot_results"][0]["damage"], 25);
        let back: Snapshot = serde_json::from_value(v).unwrap();
        assert_eq!(back.shot_results, vec![shot]);

        let hit = GameEvent::Hit {
            shooter: "A".into(),
            shooter_id,
            target: "B".into(),
            target_id,
            damage: 25,
            target_hp_after: 75,
        };
        let ev = serde_json::to_value(&hit).unwrap();
        assert_eq!(ev["event"], "hit");
        assert_eq!(ev["target_hp_after"], 75);
        let back: GameEvent = serde_json::from_value(ev).unwrap();
        match back {
            GameEvent::Hit {
                damage,
                target_hp_after,
                ..
            } => {
                assert_eq!(damage, 25);
                assert_eq!(target_hp_after, 75);
            }
            other => panic!("expected Hit, got {:?}", other),
        }
    }

    #[test]
    fn speak_deserializes_and_deny_unknown() {
        let ok: ClientMessage =
            serde_json::from_str(r#"{"type":"speak","text":"nice scrap"}"#).expect("speak");
        match ok {
            ClientMessage::Speak(s) => assert_eq!(s.text, "nice scrap"),
            other => panic!("expected Speak, got {:?}", other),
        }
        let bad: Result<ClientMessage, _> =
            serde_json::from_str(r#"{"type":"speak","text":"x","laser":true}"#);
        assert!(bad.is_err(), "unknown Speak field must fail: {:?}", bad);
    }

    #[test]
    fn board_request_denies_an_unknown_field() {
        let ok: ClientMessage = serde_json::from_str(
            r#"{"type":"board","op":"post","board":"notices","text":"still here"}"#,
        )
        .expect("board");
        match ok {
            ClientMessage::Board(request) => {
                assert_eq!(request.op, BoardOp::Post);
                assert_eq!(request.board.as_deref(), Some("notices"));
                assert_eq!(request.text.as_deref(), Some("still here"));
            }
            other => panic!("expected Board, got {:?}", other),
        }
        let bad: Result<ClientMessage, _> =
            serde_json::from_str(r#"{"type":"board","op":"list","laser":true}"#);
        assert!(bad.is_err(), "unknown board field must fail: {:?}", bad);
        let page = BoardPage {
            op: BoardOp::List,
            board: None,
            boards: vec![BoardCard {
                id: "floor".into(),
                count: 1,
            }],
            lines: Vec::new(),
            code: None,
        };
        let json = serde_json::to_value(ServerMessage::Board(page)).unwrap();
        assert_eq!(json["type"], "board");
        assert_eq!(json["boards"][0]["id"], "floor");
        assert!(json.get("lines").is_none());
        assert!(json.get("code").is_none());
    }

    #[test]
    fn set_display_behavior_deserializes_and_deny_unknown() {
        let ok: ClientMessage =
            serde_json::from_str(r#"{"type":"set_display_behavior","behavior":"push_enemy"}"#)
                .expect("set_display_behavior");
        match ok {
            ClientMessage::SetDisplayBehavior(s) => assert_eq!(s.behavior, "push_enemy"),
            other => panic!("expected SetDisplayBehavior, got {:?}", other),
        }
        let bad: Result<ClientMessage, _> =
            serde_json::from_str(r#"{"type":"set_display_behavior","behavior":"x","laser":true}"#);
        assert!(
            bad.is_err(),
            "unknown SetDisplayBehavior field must fail: {:?}",
            bad
        );
    }

    #[test]
    fn speak_event_round_trip() {
        let id = Uuid::new_v4();
        let ev = GameEvent::Speak {
            player: "ArenaFox".into(),
            player_id: id,
            text: "nice scrap".into(),
            to_id: None,
            team: None,
        };
        let v = serde_json::to_value(&ev).unwrap();
        assert_eq!(v["event"], "speak");
        assert_eq!(v["text"], "nice scrap");
        assert_eq!(v["player"], "ArenaFox");
        assert!(v.get("to_id").is_none(), "a room-wide line names nobody");
        let back: GameEvent = serde_json::from_value(v).unwrap();
        match back {
            GameEvent::Speak {
                text,
                player,
                to_id,
                ..
            } => {
                assert_eq!(text, "nice scrap");
                assert_eq!(player, "ArenaFox");
                assert_eq!(to_id, None);
            }
            other => panic!("expected Speak, got {:?}", other),
        }
        let victim = Uuid::new_v4();
        let addressed = GameEvent::Speak {
            player: "Scout Ant".into(),
            player_id: id,
            text: "scout ant deleted you".into(),
            to_id: Some(victim),
            team: None,
        };
        let v = serde_json::to_value(&addressed).unwrap();
        assert_eq!(v["to_id"], victim.to_string());
        assert!(
            v.get("team").is_none(),
            "a line to one fighter names no side"
        );
        match serde_json::from_value::<GameEvent>(v).unwrap() {
            GameEvent::Speak { to_id, .. } => assert_eq!(to_id, Some(victim)),
            other => panic!("expected Speak, got {:?}", other),
        }
        let side_call = GameEvent::Speak {
            player: "Nightfall".into(),
            player_id: id,
            text: "CARRIER MID".into(),
            to_id: None,
            team: Some(Team::Union),
        };
        let v = serde_json::to_value(&side_call).unwrap();
        assert_eq!(v["team"], "union");
        match serde_json::from_value::<GameEvent>(v).unwrap() {
            GameEvent::Speak { team, to_id, .. } => {
                assert_eq!((team, to_id), (Some(Team::Union), None));
            }
            other => panic!("expected Speak, got {:?}", other),
        }
    }

    #[test]
    fn venue_notice_is_one_sentence_on_the_wire() {
        let event = GameEvent::VenueNotice {
            text: "The venue: doors at the bell".into(),
        };
        let value = serde_json::to_value(&event).unwrap();
        assert_eq!(value["event"], "venue_notice");
        assert_eq!(value["text"], "The venue: doors at the bell");
        let back: GameEvent = serde_json::from_value(value).unwrap();
        assert!(matches!(
            back,
            GameEvent::VenueNotice { text } if text == "The venue: doors at the bell"
        ));
    }

    #[test]
    fn boss_spawn_and_down_wire_json_shape() {
        let id = Uuid::new_v4();
        let spawn = GameEvent::BossSpawn {
            name: BOSS_NAME.into(),
            boss_id: id,
            message: boss_host_line(),
            hp: 200,
        };
        let v = serde_json::to_value(&spawn).unwrap();
        assert_eq!(v["event"], "boss_spawn");
        assert_eq!(v["name"], BOSS_NAME);
        assert_eq!(v["hp"], 200);
        assert_eq!(v["message"], boss_host_line());
        let back: GameEvent = serde_json::from_value(v).unwrap();
        assert!(matches!(back, GameEvent::BossSpawn { hp: 200, .. }));

        let down = GameEvent::BossDown {
            name: BOSS_NAME.into(),
            boss_id: id,
            killer: Some("Rusher".into()),
            message: boss_down_host_line(),
        };
        let v = serde_json::to_value(&down).unwrap();
        assert_eq!(v["event"], "boss_down");
        assert_eq!(v["killer"], "Rusher");
        assert!(v.get("message").is_some());
        let back: GameEvent = serde_json::from_value(v).unwrap();
        match back {
            GameEvent::BossDown { killer, .. } => assert_eq!(killer.as_deref(), Some("Rusher")),
            other => panic!("expected BossDown, got {:?}", other),
        }

        let wipe = GameEvent::BossDown {
            name: BOSS_NAME.into(),
            boss_id: id,
            killer: None,
            message: boss_round_wipe_host_line(),
        };
        let v = serde_json::to_value(&wipe).unwrap();
        assert_eq!(v["event"], "boss_down");
        assert!(v.get("killer").is_none(), "wipe must omit killer: {}", v);
        assert_eq!(v["message"], boss_round_wipe_host_line());
        let back: GameEvent = serde_json::from_value(v).unwrap();
        match back {
            GameEvent::BossDown { killer: None, .. } => {}
            other => panic!("expected BossDown wipe, got {:?}", other),
        }
    }

    #[test]
    fn pickup_state_and_event_wire_json_shape() {
        let pad = PickupState {
            claim: SupplyClaim::Contested,
            pool: None,
            id: "pad_rail".into(),
            kind: "weapon".into(),
            weapon: "Rail".into(),
            amount: None,
            x: 12.0,
            y: 0.4,
            z: 12.0,
            available: false,
            dropped: false,
        };
        let snap = Snapshot {
            vehicles: Vec::new(),
            team_scores: None,
            flags: None,
            capture_scores: None,
            capture_limit: None,
            tick: 2,
            players: vec![],
            round_state: None,
            round_time_left: None,
            sudden_death: false,
            frag_limit: None,
            shot_results: vec![],
            projectiles: vec![],
            grenades: Vec::new(),
            assessor_canisters: Vec::new(),
            walker: None,
            rockets: Vec::new(),
            mines: Vec::new(),
            remote_mines: Vec::new(),
            auditors: Vec::new(),
            paver_strips: Vec::new(),
            jetpacks: Vec::new(),
            surveyor_marks: Vec::new(),
            explosions: Vec::new(),
            mode_name: default_mode_name(),
            playlist: default_playlist(),
            pressure: None,
            host_line: default_host_line(),
            mvp: None,
            mvp_frags: None,
            pickups: vec![pad.clone()],
            map_id: default_map_id(),
            map_name: default_map_name(),
            episode_id: None,
            episode_title: None,
            episode_objective: None,
            episode_progress: None,
            episode_phase: None,
            jammer_dish: None,
            sabotage: None,
            conquest: None,
            article_blade: None,
            podium: None,
            duel_queue: Vec::new(),
        };
        let v = serde_json::to_value(&snap).unwrap();
        assert_eq!(v["pickups"][0]["id"], "pad_rail");
        assert_eq!(v["pickups"][0]["weapon"], "Rail");
        assert_eq!(v["pickups"][0]["available"], false);
        // A live return clock belongs to the booth, never the shared world.
        assert!(v["pickups"][0].get("respawn_in").is_none());
        let back: Snapshot = serde_json::from_value(v).unwrap();
        assert_eq!(back.pickups, vec![pad]);

        let id = Uuid::new_v4();
        let ev = GameEvent::Pickup {
            player: "Rusher".into(),
            player_id: id,
            kind: "weapon".into(),
            weapon: "Rail".into(),
            amount: None,
            pickup_id: "pad_rail".into(),
            secret: false,
        };
        let v = serde_json::to_value(&ev).unwrap();
        assert_eq!(v["event"], "pickup");
        assert!(
            v.get("secret").is_none(),
            "an ordinary claim omits the flag"
        );
        assert_eq!(v["kind"], "weapon");
        assert_eq!(v["weapon"], "Rail");
        assert_eq!(v["pickup_id"], "pad_rail");
        let back: GameEvent = serde_json::from_value(v).unwrap();
        match back {
            GameEvent::Pickup {
                kind,
                weapon,
                pickup_id,
                ..
            } => {
                assert_eq!(kind, "weapon");
                assert_eq!(weapon, "Rail");
                assert_eq!(pickup_id, "pad_rail");
            }
            other => panic!("expected Pickup, got {:?}", other),
        }

        let heal = GameEvent::Pickup {
            player: "Rusher".into(),
            player_id: id,
            kind: "health".into(),
            weapon: String::new(),
            amount: Some(40),
            pickup_id: "pad_health_n".into(),
            secret: false,
        };
        let v = serde_json::to_value(&heal).unwrap();
        assert_eq!(v["kind"], "health");
        assert_eq!(v["amount"], 40);
        assert!(v.get("weapon").is_none());

        let found = GameEvent::Pickup {
            player: "Rusher".into(),
            player_id: id,
            kind: "weapon".into(),
            weapon: "Shiv".into(),
            amount: None,
            pickup_id: "alcove_shiv".into(),
            secret: true,
        };
        let v = serde_json::to_value(&found).unwrap();
        assert_eq!(v["secret"], true);
        assert_eq!(v["weapon"], "Shiv");
        assert!(matches!(
            serde_json::from_value(v).unwrap(),
            GameEvent::Pickup { secret: true, .. }
        ));
    }
    #[test]
    fn host_reaction_wire_marks_big_moments_and_omits_captions_flag() {
        let triple = GameEvent::HostReaction {
            kind: HostReactionKind::TripleFrag,
            variant: 1,
            player: Some("Rusher".into()),
            other: Some("Target".into()),
            team: None,
            big: true,
        };
        let v = serde_json::to_value(&triple).unwrap();
        assert_eq!(v["event"], "host_reaction");
        assert_eq!(v["kind"], "triple_frag");
        assert_eq!(v["big"], true);
        assert!(v.get("team").is_none());
        let back: GameEvent = serde_json::from_value(v).unwrap();
        assert!(matches!(
            back,
            GameEvent::HostReaction {
                kind: HostReactionKind::TripleFrag,
                big: true,
                ..
            }
        ));
        let caption = GameEvent::HostReaction {
            kind: HostReactionKind::DoubleFrag,
            variant: 0,
            player: Some("Rusher".into()),
            other: None,
            team: None,
            big: false,
        };
        let v = serde_json::to_value(&caption).unwrap();
        assert!(v.get("big").is_none(), "a caption omits the flag: {v}");
        assert!(matches!(
            serde_json::from_value(v).unwrap(),
            GameEvent::HostReaction { big: false, .. }
        ));
    }

    #[test]
    fn host_lines_never_use_station_vocabulary() {
        let names = vec!["Dead Air Dan".to_string()];
        let lines = [
            default_host_line(),
            roster_host_line(&names),
            warmup_host_line("Arena Duel", &names, 3),
            warmup_host_line("Arena Duel", &[], 3),
            round_open_host_line("Arena Duel", &names),
            round_open_host_line("Arena Duel", &[]),
            boss_round_wipe_host_line(),
            mvp_host_line("Rusher", 3),
            empty_mvp_host_line(),
        ];
        for line in lines {
            assert!(line.starts_with("HOST: "), "{line}");
            assert!(!line.contains("FREQUENCY"), "no station puns: {line}");
            assert!(!line.contains("TUNES IN"), "no station puns: {line}");
        }
        assert_eq!(MODE_NAME, "Scrap League");
    }

    #[test]
    fn mvp_host_line_voice() {
        let line = mvp_host_line("Rusher", 10);
        assert!(line.contains("ROUND MVP"));
        assert!(line.contains("Rusher"));
        assert!(line.contains("10 FRAGS"));
        assert!(line.contains("CONTINUANCE DENIES THE PODIUM"));
        assert!(empty_mvp_host_line().contains("NO MVP"));
    }

    #[test]
    fn scrap_bot_host_lines() {
        let names: Vec<String> = crate::roster::ROSTER[..4]
            .iter()
            .map(|f| f.name.to_string())
            .collect();
        let roster = roster_host_line(&names);
        for name in &names {
            assert!(roster.contains(&name.to_uppercase()), "{roster}");
        }
        assert!(roster.contains("ON THE SCRAP"));
        // Radio is a station feature, not the Host's arena vocabulary.
        for line in [&roster, &default_host_line()] {
            assert!(!line.contains("FREQUENCY"), "{line}");
        }
        assert_eq!(roster_host_line(&[]), default_host_line());
        let many = roster_host_line(&["A".into(), "B".into(), "C".into(), "D".into(), "E".into()]);
        assert!(many.contains("+2"));
    }

    #[test]
    fn warmup_and_round_open_host_lines() {
        let names = vec!["Grandma Rizz".into(), "Nightfall".into()];
        let warm = warmup_host_line("Arena Duel", &names, 2);
        assert_eq!(
            warm,
            "HOST: ARENA DUEL. GRANDMA RIZZ, NIGHTFALL ON THE SCRAP. GOES LIVE IN 2."
        );
        assert!(warm.contains("ARENA DUEL"));
        assert!(warm.contains("GRANDMA RIZZ"));
        assert!(warm.contains("ON THE SCRAP"));
        assert!(warm.contains("GOES LIVE IN 2"));
        let empty = warmup_host_line("Compliance Yard", &[], 3);
        assert!(empty.contains("COMPLIANCE YARD"));
        assert!(empty.contains("GOES LIVE IN 3"));
        let open = round_open_host_line("Arena Duel", &names);
        assert!(open.contains("FIGHT!"));
        assert!(open.contains("ARENA DUEL"));
        assert!(open.contains("ON THE SCRAP"));
        let open_empty = round_open_host_line("Compliance Yard", &[]);
        assert!(open_empty.contains("IS LIVE"));
        assert!(open_empty.contains("FIGHT!"));
    }

    #[test]
    fn rule_bot_taunt_lines_are_callsign_flavored() {
        for fighter in crate::roster::ROSTER {
            for kind in [
                BotTauntKind::Frag,
                BotTauntKind::Death,
                BotTauntKind::Killstreak,
                BotTauntKind::Warmup,
            ] {
                let lines = fighter.taunts(kind);
                for salt in 0..3 {
                    assert_eq!(
                        rule_bot_taunt_line(fighter.name, kind, salt),
                        lines[salt as usize]
                    );
                }
                // Overflow copies speak the same lines.
                let copy = format!("{}-2", fighter.name);
                assert_eq!(rule_bot_taunt_line(&copy, kind, 4), lines[1]);
            }
        }
        let frag = rule_bot_taunt_line("Scout Ant", BotTauntKind::Frag, 0);
        assert_eq!(frag, "scout ant deleted you");
        assert_eq!(rule_bot_callsign_base("Handle 4471-K"), "Handle 4471-K");
        assert_eq!(rule_bot_callsign_base("Lil Bro 63-3"), "Lil Bro 63");
        let death = rule_bot_taunt_line("Scrap Fox", BotTauntKind::Death, 0);
        assert_eq!(death, "back in a sec");
        let generic = rule_bot_taunt_line("Scrap Fox", BotTauntKind::Frag, 1);
        assert!(
            generic == "clean 67" || generic == "meatproxy down",
            "{generic}"
        );
    }

    #[test]
    fn round_end_mvp_wire_round_trip() {
        let event = GameEvent::RoundEnd {
            team_scores: None,
            capture_scores: None,
            winning_team: None,
            winner: Some("Rusher".to_string()),
            reason: "Frag limit reached".to_string(),
            final_scores: vec![PlayerScore {
                name: "Rusher".to_string(),
                score: 10,
            }],
            winner_score: Some(10),
            mvp: Some("Rusher".to_string()),
            mvp_frags: Some(10),
            host_line: mvp_host_line("Rusher", 10),
            sabotage: None,
        };
        let v = serde_json::to_value(&event).unwrap();
        assert_eq!(v["event"], "round_end");
        assert_eq!(v["mvp"], "Rusher");
        assert_eq!(v["mvp_frags"], 10);
        assert!(v["host_line"].as_str().unwrap().contains("ROUND MVP"));
        let back: GameEvent = serde_json::from_value(v).unwrap();
        match back {
            GameEvent::RoundEnd {
                mvp,
                mvp_frags,
                host_line,
                ..
            } => {
                assert_eq!(mvp.as_deref(), Some("Rusher"));
                assert_eq!(mvp_frags, Some(10));
                assert!(host_line.contains("ROUND MVP"));
            }
            other => panic!("expected RoundEnd, got {:?}", other),
        }
        // Legacy wire without mvp fields still deserializes.
        let legacy = serde_json::json!({
            "event": "round_end",
            "winner": "Bot1",
            "reason": "Time limit reached",
            "final_scores": [],
            "winner_score": null
        });
        let legacy_ev: GameEvent = serde_json::from_value(legacy).unwrap();
        match legacy_ev {
            GameEvent::RoundEnd { mvp, host_line, .. } => {
                assert!(mvp.is_none());
                assert_eq!(host_line, default_host_line());
            }
            other => panic!("expected RoundEnd, got {:?}", other),
        }
    }

    #[test]
    fn ctf_flag_and_event_round_trip() {
        let id = Uuid::from_u128(7);
        let flag = FlagState {
            team: Team::Union,
            stand: [-70.0, 0.0, 0.0],
            position: [3.0, 0.0, 2.0],
            status: FlagStatus::Carried,
            carrier: Some(id),
            return_ticks: None,
        };
        let value = serde_json::to_value(&flag).unwrap();
        assert_eq!(value["status"], "carried");
        assert_eq!(serde_json::from_value::<FlagState>(value).unwrap(), flag);
        let event = GameEvent::Flag {
            kind: FlagEventKind::Taken,
            flag: Team::Union,
            player: Some("Carrier".into()),
            player_id: Some(id),
            capture_scores: TeamScores::default(),
        };
        let value = serde_json::to_value(&event).unwrap();
        assert_eq!(value["event"], "flag");
        assert_eq!(value["kind"], "taken");
        assert!(matches!(
            serde_json::from_value::<GameEvent>(value).unwrap(),
            GameEvent::Flag {
                kind: FlagEventKind::Taken,
                ..
            }
        ));
    }
}
