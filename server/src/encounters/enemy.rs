use crate::combat::{aim_at, line_of_sight};
use crate::navigation::NavigationGoal;
use crate::protocol::{
    Action, CampaignActor, CampaignDifficulty, EnemyKind, EnemyPhase, Snapshot, WeaponType,
};
use crate::sim::{BotIntent, GameState, PLAYER_FLOOR_Y};
use std::f32::consts::{PI, TAU};
use uuid::Uuid;
mod enforcer;
mod redactor;
mod spine_patrol;
pub(crate) use enforcer::{CHARGE_DAMAGE, CHARGE_SHOVE};

/// Damage from one tick at or above this staggers an armored body. A Rail hit,
/// a close Scatter blast or several pellets landing together qualify; a single
/// pistol, rifle or fist hit does not.
pub(crate) const STAGGER_DAMAGE: i32 = 40;
/// Visual pursuit memory and the engagement bound shared by walking enemies.
const SIGHT_RANGE: f32 = 32.0;
const ENGAGE_RANGE: f32 = 24.0;
/// A walking guard further than this from its authored post walks back once
/// when its chase ends, or when its alarm search ends and it is the last of
/// its group still standing. Shorter trails stay where they end.
const POST_RADIUS: f32 = 8.0;
/// Bound on one walk home; a blocked guard idles once this lapses.
const POST_RETURN_TICKS: u64 = 400;
/// The turret reaches a little further because it cannot close the distance.
const TURRET_ENGAGE_RANGE: f32 = 28.0;
/// Idle head sweep either side of the authored facing, and its rate per tick.
const TURRET_SWEEP_ARC: f32 = 0.8;
const TURRET_SWEEP_RATE: f32 = 0.035;
/// Tracking turn rate per tick (2 rad/s). A close sideways run can outpace it.
const TURRET_TRACK_RATE: f32 = 0.1;
/// Half-angle either side of the head in which a turret notices a new target.
/// Anything behind the sweep is a flank.
const TURRET_ACQUIRE_CONE: f32 = 1.0;
/// The head must settle this close to its target before the spin-up starts.
const TURRET_LOCK: f32 = 0.06;
/// Sideways steps a Heavy Sweeper takes after each recovery before its next
/// burst. Slow gait makes this a short shuffle, not a dodge.
const HEAVY_REPOSITION_TICKS: u64 = 24;
/// Require enough of a low body to be visible for its leap tell to read.
const CRAWLER_EXPOSED_HALF_WIDTH: f32 = 0.6;
const CRAWLER_WINDUP_TICKS: u64 = 12;
const CRAWLER_RECOVERY_TICKS: u64 = 20;
/// A Ranged Sweeper reads the whole crater cut, inside the Sniper's reach.
const MARKSMAN_SIGHT_RANGE: f32 = 90.0;
const MARKSMAN_ENGAGE_RANGE: f32 = 88.0;
/// Half-angle either side of its authored facing in which a Ranged Sweeper
/// notices a new target. A platform's flank stays a flank.
const MARKSMAN_NOTICE_CONE: f32 = 1.0;

fn crawler_body_exposed(
    viewer: &crate::protocol::PlayerState,
    crawler_feet: [f32; 3],
    solids: &[crate::movement::Solid],
) -> bool {
    let origin = [
        viewer.x,
        viewer.y - PLAYER_FLOOR_Y + crate::combat::eye_height(viewer.campaign),
        viewer.z,
    ];
    let dx = crawler_feet[0] - viewer.x;
    let dz = crawler_feet[2] - viewer.z;
    let distance = dx.hypot(dz);
    let lateral = if distance > 0.001 {
        [-dz / distance, dx / distance]
    } else {
        [1.0, 0.0]
    };
    [-CRAWLER_EXPOSED_HALF_WIDTH, 0.0, CRAWLER_EXPOSED_HALF_WIDTH]
        .into_iter()
        .all(|offset| {
            line_of_sight(
                origin,
                [
                    crawler_feet[0] + lateral[0] * offset,
                    crawler_feet[1] + crate::combat::CRAWLER_HEIGHT * 0.5,
                    crawler_feet[2] + lateral[1] * offset,
                ],
                solids,
            )
        })
}

/// Spawned health and issued weapon. Difficulty never changes these.
pub(crate) fn body(kind: EnemyKind) -> (i32, WeaponType) {
    match kind {
        EnemyKind::Clerk => (60, WeaponType::Tack),
        EnemyKind::Sweeper => (80, WeaponType::Flechette),
        EnemyKind::HeavySweeper => (160, WeaponType::Flechette),
        EnemyKind::Turret => (100, WeaponType::Rail),
        EnemyKind::Crawler => (55, WeaponType::Fists),
        EnemyKind::Jammer => (90, WeaponType::Fists),
        EnemyKind::Notary => (50, WeaponType::Tack),
        EnemyKind::Auditor => (120, WeaponType::Tack),
        EnemyKind::RangedSweeper => (70, WeaponType::Sniper),
        EnemyKind::Enforcer => (140, WeaponType::Fists),
        EnemyKind::Redactor => (90, WeaponType::Shiv),
    }
}

/// Share of participant top speed. Turrets are fixed equipment.
pub(crate) fn gait(kind: EnemyKind) -> f32 {
    match kind {
        EnemyKind::Clerk | EnemyKind::Sweeper => 0.5,
        EnemyKind::HeavySweeper => 0.3,
        EnemyKind::Turret | EnemyKind::Jammer | EnemyKind::Notary | EnemyKind::RangedSweeper => 0.0,
        EnemyKind::Crawler => 0.7,
        EnemyKind::Auditor => 0.4,
        EnemyKind::Enforcer => 0.45,
        EnemyKind::Redactor => 0.6,
    }
}

/// Committed shots per attack.
fn burst(kind: EnemyKind) -> u8 {
    match kind {
        EnemyKind::Clerk
        | EnemyKind::Turret
        | EnemyKind::Crawler
        | EnemyKind::Jammer
        | EnemyKind::Auditor
        | EnemyKind::RangedSweeper
        | EnemyKind::Redactor => 1,
        EnemyKind::Enforcer => 1,
        EnemyKind::Sweeper | EnemyKind::Notary => 3,
        EnemyKind::HeavySweeper => 4,
    }
}

/// Hit stun in ticks. Armored bodies only enter it on a heavy hit.
fn stun(kind: EnemyKind) -> u64 {
    match kind {
        EnemyKind::Clerk
        | EnemyKind::Sweeper
        | EnemyKind::Crawler
        | EnemyKind::Jammer
        | EnemyKind::Notary
        | EnemyKind::Auditor
        | EnemyKind::RangedSweeper
        | EnemyKind::Redactor => 6,
        EnemyKind::HeavySweeper => 16,
        EnemyKind::Enforcer => 16,
        EnemyKind::Turret => 10,
    }
}

fn armored(kind: EnemyKind) -> bool {
    matches!(
        kind,
        EnemyKind::HeavySweeper | EnemyKind::Turret | EnemyKind::Enforcer
    )
}

/// Signed shortest turn from `from` to `to`, in (-pi, pi].
fn turn(from: f32, to: f32) -> f32 {
    let delta = (to - from).rem_euclid(TAU);
    if delta > PI {
        delta - TAU
    } else {
        delta
    }
}

pub(super) struct EnemyController {
    pub id: Uuid,
    kind: EnemyKind,
    phase: EnemyPhase,
    started: u64,
    until: u64,
    target: Option<Uuid>,
    last_known: [f32; 3],
    search_until: u64,
    /// Authored post. A walking guard that lost its quarry returns here.
    home: [f32; 3],
    /// Set by a sighting; one walk home spends it.
    chased: bool,
    /// Set by an alarm; spent by a walk home as the group's last guard.
    alarmed: bool,
    /// The encounter reports whether every other member of this guard's
    /// group has fallen.
    pub(super) last_standing: bool,
    aim: (f32, f32),
    next_shot: u64,
    shots_left: u8,
    /// Authored facing; the turret sweeps around it.
    home_yaw: f32,
    /// Current turret head facing, sent as the body's yaw.
    head: f32,
    sweep: f32,
    /// Authoritative health at the previous intent, for armored stagger.
    last_hp: i32,
    /// One stagger per attack cycle: rearmed when a windup begins.
    stagger_ready: bool,
    reposition_until: u64,
    strafe_left: bool,
    seated: bool,
    /// A Crawler can connect once in each committed leap.
    contact_used: bool,
    hover: Option<crate::maps::Hover>,
    patrol_point: usize,
    hover_tick: Option<u64>,
    landed: bool,
    photograph_pending: Option<Uuid>,
    /// Auditor only: completed repairs it may still make.
    repairs_left: u8,
    /// Auditor only: the disabled body its channel reaches.
    channel_target: Option<Uuid>,
    /// A disabled body's own end of presentation, before any channel hold.
    dead_until: u64,
    /// The charge's original supported height, retained through recovery.
    charge_floor: Option<f32>,
    /// Redactor only: one held, supported lateral approach per visible pursuit.
    redactor_approach: Option<(Uuid, [f32; 3])>,
    redactor_approach_until: u64,
    redactor_approached: bool,
    /// Only the authored tender's three-Clerk file, before combat is noticed.
    spine_march: Option<spine_patrol::SpineMarch>,
}

/// (windup, recovery) ticks. Tiers change tells and openings only; health,
/// damage, burst length, locked aim and hit stun are identical.
pub(crate) fn attack_timing(kind: EnemyKind, difficulty: CampaignDifficulty) -> (u64, u64) {
    match (kind, difficulty) {
        (EnemyKind::Clerk, CampaignDifficulty::Assisted) => (20, 30),
        (EnemyKind::Clerk, CampaignDifficulty::Standard) => (12, 20),
        (EnemyKind::Clerk, CampaignDifficulty::Severe) => (10, 16),
        (EnemyKind::Sweeper, CampaignDifficulty::Assisted) => (22, 38),
        (EnemyKind::Sweeper, CampaignDifficulty::Standard) => (14, 26),
        (EnemyKind::Sweeper, CampaignDifficulty::Severe) => (12, 20),
        (EnemyKind::HeavySweeper, CampaignDifficulty::Assisted) => (32, 46),
        (EnemyKind::HeavySweeper, CampaignDifficulty::Standard) => (24, 34),
        (EnemyKind::HeavySweeper, CampaignDifficulty::Severe) => (20, 28),
        (EnemyKind::Turret, CampaignDifficulty::Assisted) => (36, 40),
        (EnemyKind::Turret, CampaignDifficulty::Standard) => (26, 30),
        (EnemyKind::Turret, CampaignDifficulty::Severe) => (20, 24),
        (EnemyKind::Crawler, _) => (CRAWLER_WINDUP_TICKS, CRAWLER_RECOVERY_TICKS),
        (EnemyKind::Jammer, _) => (24, 40),
        (EnemyKind::Notary, CampaignDifficulty::Assisted) => (24, 36),
        (EnemyKind::Notary, CampaignDifficulty::Standard) => (16, 26),
        (EnemyKind::Notary, CampaignDifficulty::Severe) => (12, 20),
        (EnemyKind::Auditor, CampaignDifficulty::Assisted) => (22, 32),
        (EnemyKind::Auditor, CampaignDifficulty::Standard) => (14, 22),
        (EnemyKind::Auditor, CampaignDifficulty::Severe) => (12, 18),
        // The glint and hold: the whole windup is the reaction window. Severe
        // still gives more than one second to drop below a sill.
        (EnemyKind::RangedSweeper, CampaignDifficulty::Assisted) => (40, 50),
        (EnemyKind::RangedSweeper, CampaignDifficulty::Standard) => (30, 40),
        (EnemyKind::RangedSweeper, CampaignDifficulty::Severe) => (24, 32),
        (EnemyKind::Enforcer, CampaignDifficulty::Assisted) => (32, 44),
        (EnemyKind::Enforcer, CampaignDifficulty::Standard) => (24, 36),
        (EnemyKind::Enforcer, CampaignDifficulty::Severe) => (20, 30),
        // New role prototype tuning; the earlier roles retain their exact tells.
        (EnemyKind::Redactor, CampaignDifficulty::Assisted) => (24, 30),
        (EnemyKind::Redactor, CampaignDifficulty::Standard) => (18, 24),
        (EnemyKind::Redactor, CampaignDifficulty::Severe) => (14, 18),
    }
}

/// Auditor repair channel length per tier: the window to snap it. Health,
/// damage, the two-repair limit and reach are identical on every tier.
pub(crate) fn channel_ticks(difficulty: CampaignDifficulty) -> u64 {
    match difficulty {
        CampaignDifficulty::Assisted => 60,
        CampaignDifficulty::Standard => 44,
        CampaignDifficulty::Severe => 36,
    }
}

/// Reach of a repair channel from the Auditor's eye to the disabled body.
pub(crate) const REPAIR_RANGE: f32 = 18.0;
/// A disabled body's phase window, hold included, never exceeds this many
/// ticks: readers bound every actor phase window to it.
pub(crate) const DISABLED_HOLD_LIMIT: u64 = 100;
/// A repaired body stands up slowly before it acts again.
pub(crate) const REPAIR_RECOVERY_TICKS: u64 = 20;
/// Recovery after a snapped channel, and after a completed one.
const CHANNEL_SNAP_TICKS: u64 = 12;
const CHANNEL_DONE_TICKS: u64 = 10;

/// Repair restores a disabled bot body, never a person.
pub(crate) fn repairable(kind: EnemyKind) -> bool {
    matches!(kind, EnemyKind::Sweeper | EnemyKind::HeavySweeper)
}

impl EnemyController {
    pub(super) fn kind(&self) -> EnemyKind {
        self.kind
    }

    pub(super) fn phase(&self) -> EnemyPhase {
        self.phase
    }

    pub(super) fn phase_started(&self) -> u64 {
        self.started
    }

    pub(super) fn phase_ends(&self) -> u64 {
        self.until
    }

    pub(super) fn repairs_left(&self) -> u8 {
        self.repairs_left
    }

    pub(super) fn channel_target(&self) -> Option<Uuid> {
        self.channel_target
            .filter(|_| self.phase == EnemyPhase::Channeling)
    }

    /// Free to begin a channel: not mid-attack, stunned or recovering.
    pub(super) fn can_channel(&self, tick: u64) -> bool {
        self.kind == EnemyKind::Auditor
            && self.repairs_left > 0
            && match self.phase {
                EnemyPhase::Idle | EnemyPhase::Moving => true,
                EnemyPhase::Recovery | EnemyPhase::Hit => tick >= self.until,
                _ => false,
            }
    }

    pub(super) fn start_channel(&mut self, body: Uuid, tick: u64, duration: u64) {
        self.shots_left = 0;
        self.target = None;
        self.channel_target = Some(body);
        self.enter(EnemyPhase::Channeling, tick, duration);
    }

    /// Broken sight, a missing body or an occupied spot ends the channel
    /// without spending a repair.
    pub(super) fn snap_channel(&mut self, tick: u64) {
        self.channel_target = None;
        self.enter(EnemyPhase::Recovery, tick, CHANNEL_SNAP_TICKS);
    }

    pub(super) fn complete_channel(&mut self, tick: u64) {
        self.channel_target = None;
        self.repairs_left = self.repairs_left.saturating_sub(1);
        self.enter(EnemyPhase::Recovery, tick, CHANNEL_DONE_TICKS);
    }

    /// Keep a disabled body while a channel reaches it; otherwise its own
    /// presentation window applies.
    pub(super) fn hold_disabled(&mut self, until: Option<u64>) {
        if self.phase == EnemyPhase::Dead {
            self.until = until.map_or(self.dead_until, |held| held.max(self.dead_until));
        }
    }

    /// A repaired bot stands up at the given health, ready after a recovery.
    pub(super) fn repaired(&mut self, tick: u64, hp: i32) {
        self.last_hp = hp;
        self.target = None;
        self.shots_left = 0;
        self.stagger_ready = true;
        self.contact_used = false;
        self.photograph_pending = None;
        self.enter(EnemyPhase::Recovery, tick, REPAIR_RECOVERY_TICKS);
    }

    pub fn new(
        id: Uuid,
        kind: EnemyKind,
        alarm_position: [f32; 3],
        yaw: f32,
        tick: u64,
        seated: bool,
    ) -> Self {
        Self {
            id,
            kind,
            phase: EnemyPhase::Idle,
            started: tick,
            until: tick,
            target: None,
            last_known: alarm_position,
            home: alarm_position,
            chased: false,
            alarmed: false,
            last_standing: false,
            // Dispatch can require a full stair route to another floor. This
            // is a fixed alarm location, never the unseen participant's live
            // position. Visual pursuit below keeps its shorter memory.
            search_until: tick.saturating_add(600),
            aim: (0.0, 0.0),
            next_shot: 0,
            shots_left: 0,
            home_yaw: yaw,
            head: yaw,
            sweep: 1.0,
            last_hp: body(kind).0,
            stagger_ready: true,
            reposition_until: 0,
            strafe_left: false,
            seated,
            contact_used: false,
            hover: None,
            patrol_point: 0,
            hover_tick: None,
            landed: false,
            photograph_pending: None,
            repairs_left: if kind == EnemyKind::Auditor {
                crate::protocol::AUDITOR_REPAIRS
            } else {
                0
            },
            channel_target: None,
            dead_until: tick,
            charge_floor: None,
            redactor_approach: None,
            redactor_approach_until: 0,
            redactor_approached: false,
            spine_march: None,
        }
    }

    pub fn identity(&self) -> CampaignActor {
        CampaignActor::Union {
            kind: self.kind,
            phase: self.phase,
            phase_started: self.started,
            phase_ends: self.until,
            seated: self.seated,
        }
    }

    pub(super) fn with_spine_march(
        mut self,
        patrol: Option<crate::maps::SpinePatrol>,
        member: usize,
    ) -> Self {
        if self.kind == EnemyKind::Clerk && member < 3 {
            self.spine_march =
                patrol.map(|parameters| spine_patrol::SpineMarch::new(parameters, member));
        }
        self
    }

    pub(super) fn end_spine_march(&mut self) {
        self.spine_march = None;
    }

    pub fn alarm(&mut self, position: [f32; 3], tick: u64) {
        if let Some(march) = &mut self.spine_march {
            march.start(tick);
        }
        self.seated = false;
        self.alarmed = true;
        self.last_known = position;
        self.search_until = tick.saturating_add(600);
    }

    fn enter(&mut self, phase: EnemyPhase, tick: u64, duration: u64) {
        self.phase = phase;
        self.started = tick;
        self.until = tick.saturating_add(duration);
    }

    pub fn hit(&mut self, tick: u64, died: bool) {
        self.end_spine_march();
        self.redactor_approach = None;
        self.redactor_approached = false;
        self.photograph_pending = None;
        self.seated = false;
        if self.kind != EnemyKind::Enforcer || died {
            self.contact_used = true;
        }
        if self.phase == EnemyPhase::Dead {
            return;
        }
        // Any damaging hit snaps a repair channel.
        self.channel_target = None;
        if died {
            self.shots_left = 0;
            self.enter(EnemyPhase::Dead, tick, 40);
            self.dead_until = self.until;
        } else if !armored(self.kind) {
            self.shots_left = 0;
            self.enter(EnemyPhase::Hit, tick, stun(self.kind));
        }
        // Armor shrugs off ordinary hits. The next intent reads the tick's
        // total damage from the body and staggers on a heavy one.
    }

    /// Fixed equipment turns its head, never its feet.
    fn face(&mut self, action: &mut Action, toward: f32, rate: f32) -> f32 {
        let delta = turn(self.head, toward);
        self.head = crate::movement::normalize_yaw(self.head + delta.clamp(-rate, rate));
        action.yaw = Some(self.head);
        action.pitch = Some(0.0);
        delta
    }

    /// One pre-step observation for every controller. Attack aim commits at the
    /// start of the tell, so a strafe during windup can evade the actual ray.
    pub fn intent(&mut self, state: &GameState, snapshot: &Snapshot) -> BotIntent {
        let Some(me) = snapshot
            .players
            .iter()
            .find(|p| p.id == self.id && p.hp > 0)
        else {
            return BotIntent::default();
        };
        let tick = state.tick.saturating_add(1);
        let (windup, recovery) = attack_timing(self.kind, state.campaign_rules().difficulty);
        let turret = self.kind == EnemyKind::Turret;
        let marksman = self.kind == EnemyKind::RangedSweeper;
        let sight_range = if marksman {
            MARKSMAN_SIGHT_RANGE
        } else {
            SIGHT_RANGE
        };
        let feet = [me.x, me.y - PLAYER_FLOOR_Y, me.z];
        let eye = [me.x, feet[1] + crate::combat::eye_height(me.campaign), me.z];
        let centre = |p: &crate::protocol::PlayerState| {
            [
                p.x,
                p.y - PLAYER_FLOOR_Y + crate::combat::target_height(p.campaign) * 0.5,
                p.z,
            ]
        };
        let head_point = |p: &crate::protocol::PlayerState| {
            [
                p.x,
                p.y - PLAYER_FLOOR_Y + crate::combat::eye_height(p.campaign),
                p.z,
            ]
        };
        let visible = |p: &&crate::protocol::PlayerState| {
            let solids = &state.current_arena().solids;
            p.campaign == Some(CampaignActor::Participant {})
                && me.is_hostile_to(p)
                && crate::mission::actor_active(state.mission.as_ref(), p.id, p.campaign)
                && (p.x - me.x).hypot(p.z - me.z) <= sight_range
                && if marksman {
                    // A marksman sees a peeking head as well as an open body:
                    // the participant must drop fully behind cover.
                    line_of_sight(eye, centre(p), solids)
                        || line_of_sight(eye, head_point(p), solids)
                } else {
                    line_of_sight(eye, centre(p), solids)
                        && (self.kind != EnemyKind::Notary
                            || line_of_sight(eye, head_point(p), solids))
                }
        };
        let head = self.head;
        let home = self.home_yaw;
        let noticed = |p: &&crate::protocol::PlayerState| {
            let bearing = (p.z - me.z).atan2(p.x - me.x);
            if turret {
                turn(head, bearing).abs() <= TURRET_ACQUIRE_CONE
            } else if marksman {
                turn(home, bearing).abs() <= MARKSMAN_NOTICE_CONE
            } else {
                true
            }
        };
        let target = self
            .target
            .and_then(|id| snapshot.players.iter().find(|p| p.id == id).filter(visible))
            .or_else(|| {
                // A committed attack never snaps to a replacement target.
                (!matches!(
                    self.phase,
                    EnemyPhase::Windup
                        | EnemyPhase::Firing
                        | EnemyPhase::Leaping
                        | EnemyPhase::Charging
                ))
                .then(|| {
                    snapshot
                        .players
                        .iter()
                        .filter(visible)
                        .filter(noticed)
                        .min_by(|a, b| {
                            (a.x - me.x)
                                .hypot(a.z - me.z)
                                .total_cmp(&(b.x - me.x).hypot(b.z - me.z))
                        })
                })
                .flatten()
            });
        if let Some(target) = target {
            self.end_spine_march();
            self.target = Some(target.id);
            self.last_known = [target.x, target.y - PLAYER_FLOOR_Y, target.z];
            self.search_until = tick.saturating_add(100);
            self.chased = true;
        }

        // Armor reads the whole tick's damage from the authoritative body, so
        // several pellets or trading shooters add up to one heavy hit.
        let damage = self.last_hp.saturating_sub(me.hp);
        self.last_hp = me.hp;
        if armored(self.kind)
            && damage >= STAGGER_DAMAGE
            && self.stagger_ready
            && self.phase != EnemyPhase::Hit
        {
            self.stagger_ready = false;
            self.shots_left = 0;
            self.enter(EnemyPhase::Hit, tick, stun(self.kind));
            return BotIntent::default();
        }

        let mut action = Action::default();
        if self.kind == EnemyKind::Enforcer {
            let grounded = state
                .players
                .iter()
                .find(|p| p.id == self.id)
                .is_some_and(|p| {
                    p.vy <= 0.0
                        && (feet[1]
                            - state.current_arena().support_height(
                                feet[0],
                                feet[2],
                                feet[1] + 0.01,
                            ))
                        .abs()
                            <= 0.02
                });
            return self.enforcer(target, feet, grounded, (windup, recovery), tick);
        }
        if matches!(self.phase, EnemyPhase::Hit | EnemyPhase::Recovery) && tick < self.until {
            return BotIntent::default();
        }
        if let Some(destination) = self
            .spine_march
            .as_ref()
            .and_then(|march| march.destination(tick))
        {
            if self.phase != EnemyPhase::Moving {
                self.enter(EnemyPhase::Moving, tick, 0);
            }
            // The loader proves the entire straight file corridor. A moving
            // sub-grid march target must not be repeatedly snapped to routing
            // cells. Use ordinary walking; Session still forecasts body
            // avoidance and integration still owns walls, support and contact.
            let dx = destination[0] - feet[0];
            let dz = destination[2] - feet[2];
            let half_step =
                crate::movement::TOP_SPEED * gait(self.kind) * crate::movement::DT_LIVE * 0.5;
            if dx.hypot(dz) > half_step {
                action.forward = true;
                action.yaw = Some(dz.atan2(dx));
            }
            return BotIntent { action, goal: None };
        }
        if self.phase == EnemyPhase::Channeling {
            // The Auditor holds still and faces the body, plate away from a flank.
            if let Some(body) = self
                .channel_target
                .and_then(|id| state.players.iter().find(|p| p.id == id))
            {
                if let Some(aim) = aim_at(eye, [body.x, body.y - PLAYER_FLOOR_Y + 0.4, body.z]) {
                    action.yaw = Some(aim.0);
                    action.pitch = Some(aim.1);
                    self.head = aim.0;
                }
            }
            return BotIntent { action, goal: None };
        }
        if self.kind == EnemyKind::HeavySweeper
            && self.phase == EnemyPhase::Recovery
            && target.is_some()
        {
            // A slow sideways shuffle before the next burst: a flank opening,
            // and the heavy gait on screen.
            self.reposition_until = tick.saturating_add(HEAVY_REPOSITION_TICKS);
            self.strafe_left = !self.strafe_left;
        }
        let Some(body) = state.players.iter().find(|p| p.id == self.id) else {
            return BotIntent::default();
        };
        if self.kind == EnemyKind::Crawler {
            let support = state
                .current_arena()
                .support_height(feet[0], feet[2], feet[1] + 0.01);
            let grounded = body.vy <= 0.0 && (feet[1] - support).abs() <= 0.02;
            let exposed = target.is_some_and(|target| {
                crawler_body_exposed(target, feet, &state.current_arena().solids)
            });
            return self.crawler(target, grounded, exposed, feet, tick);
        }
        if self.kind == EnemyKind::Jammer {
            return self.jammer(target, eye, (windup, recovery), tick, state);
        }
        // Guards spend the same finite ammunition counts as participants.
        // An empty guard can still defend themselves at melee distance.
        if let Some(loadout) = body.inventory.state(body.id, body.weapon, state.tick) {
            if loadout.shots(body.weapon) == Some(0) {
                if turret || marksman || self.kind == EnemyKind::Notary {
                    // A dry turret or marksman has no melee. It stays still and
                    // harmless.
                    if self.phase != EnemyPhase::Idle {
                        self.enter(EnemyPhase::Idle, tick, 0);
                    }
                    return BotIntent::default();
                }
                action.weapon_swap = Some(WeaponType::Fists);
                self.enter(EnemyPhase::Recovery, tick, 6);
                return BotIntent { action, goal: None };
            }
        }
        if matches!(self.phase, EnemyPhase::Windup | EnemyPhase::Firing) {
            if target.is_none() {
                // Broken sight cancels the committed attack, including the
                // turret's charged shot.
                self.target = None;
                self.shots_left = 0;
                self.enter(EnemyPhase::Recovery, tick, 12);
                return BotIntent::default();
            }
            action.yaw = Some(self.aim.0);
            action.pitch = Some(self.aim.1);
            if self.phase == EnemyPhase::Windup && tick >= self.until {
                self.shots_left = if body.weapon == WeaponType::Fists {
                    1
                } else {
                    burst(self.kind)
                };
                self.next_shot = tick;
                if self.kind == EnemyKind::Notary {
                    self.photograph_pending = self.target;
                }
                self.enter(
                    EnemyPhase::Firing,
                    tick,
                    u64::from(body.weapon.cooldown_ticks()) * u64::from(self.shots_left - 1) + 1,
                );
            }
            if self.phase == EnemyPhase::Firing && tick >= self.next_shot && self.shots_left > 0 {
                action.fire = true;
                self.shots_left -= 1;
                self.next_shot = tick.saturating_add(u64::from(body.weapon.cooldown_ticks()));
            } else if self.phase == EnemyPhase::Firing && self.shots_left == 0 {
                self.enter(EnemyPhase::Recovery, tick, recovery);
            }
            return BotIntent { action, goal: None };
        }
        if turret {
            return self.turret(target, eye, windup, tick, &centre);
        }
        if marksman {
            let solids = &state.current_arena().solids;
            let aim_point = target.and_then(|target| {
                [centre(target), head_point(target)]
                    .into_iter()
                    .find(|point| line_of_sight(eye, *point, solids))
            });
            return self.marksman(target, aim_point, eye, windup, tick);
        }
        if self.kind == EnemyKind::Notary {
            if let Some(target) = target {
                let horizontal = (target.x - me.x).hypot(target.z - me.z);
                let rise = eye[1] - centre(target)[1];
                if horizontal >= rise.max(0.0) && horizontal <= 24.0 {
                    if let Some(aim) = aim_at(eye, centre(target)) {
                        self.begin_windup(aim, tick, windup, &mut action);
                        return BotIntent { action, goal: None };
                    }
                }
            }
            if self.phase != EnemyPhase::Moving {
                self.enter(EnemyPhase::Moving, tick, 0);
            }
            return BotIntent::default();
        }
        if let Some(target) = target {
            let distance = (target.x - me.x).hypot(target.z - me.z);
            if self.kind == EnemyKind::HeavySweeper && tick < self.reposition_until {
                if self.phase != EnemyPhase::Moving {
                    self.enter(EnemyPhase::Moving, tick, 0);
                }
                action.yaw = Some((target.z - me.z).atan2(target.x - me.x));
                action.left = self.strafe_left;
                action.right = !self.strafe_left;
                return BotIntent { action, goal: None };
            }
            if distance <= body.weapon.range_units().min(ENGAGE_RANGE) {
                if let Some(aim) = aim_at(eye, centre(target)) {
                    self.begin_windup(aim, tick, windup, &mut action);
                    return BotIntent { action, goal: None };
                }
            }
        }
        if self.kind == EnemyKind::Redactor {
            if let Some(intent) = self.redactor_approach(state, target, feet, tick) {
                return intent;
            }
        }
        if tick <= self.search_until
            && (feet[0] - self.last_known[0]).hypot(feet[2] - self.last_known[2]) > 0.6
        {
            if self.phase != EnemyPhase::Moving {
                self.enter(EnemyPhase::Moving, tick, 0);
            }
            action.forward = true;
            action.yaw = Some((self.last_known[2] - feet[2]).atan2(self.last_known[0] - feet[0]));
            return BotIntent {
                action,
                goal: Some(NavigationGoal {
                    feet: self.last_known,
                    combat: target.is_some(),
                }),
            };
        }
        self.target = None;
        // A guard whose chase ended far from its post, or the last guard of a
        // group whose alarm search ended far away, walks back instead of
        // idling wherever the trail ran out. The last guard of a required
        // group then waits where the fight was staged, in view of the
        // objective, not alone at a far threshold nobody revisits. The post is
        // authored, never the unseen participant's live position. Other
        // alarmed guards keep their authored dispatch.
        let trail = self.chased || (self.alarmed && self.last_standing);
        if trail && (feet[0] - self.home[0]).hypot(feet[2] - self.home[2]) > POST_RADIUS {
            self.chased = false;
            self.alarmed = false;
            self.last_known = self.home;
            self.search_until = tick.saturating_add(POST_RETURN_TICKS);
            if self.phase != EnemyPhase::Moving {
                self.enter(EnemyPhase::Moving, tick, 0);
            }
            action.forward = true;
            action.yaw = Some((self.home[2] - feet[2]).atan2(self.home[0] - feet[0]));
            return BotIntent {
                action,
                goal: Some(NavigationGoal {
                    feet: self.home,
                    combat: false,
                }),
            };
        }
        if self.phase != EnemyPhase::Idle {
            self.enter(EnemyPhase::Idle, tick, 0);
        }
        BotIntent::default()
    }

    fn begin_windup(&mut self, aim: (f32, f32), tick: u64, windup: u64, action: &mut Action) {
        self.redactor_approach = None;
        self.photograph_pending = None;
        self.aim = aim;
        self.head = aim.0;
        self.stagger_ready = true;
        self.enter(EnemyPhase::Windup, tick, windup);
        action.yaw = Some(aim.0);
        action.pitch = Some(aim.1);
    }

    pub(super) fn with_hover(mut self, hover: Option<crate::maps::Hover>) -> Self {
        self.hover = hover;
        self
    }
    pub(super) fn claim_notary_photo_target(&mut self) -> Option<Uuid> {
        self.photograph_pending.take()
    }
    pub(super) fn advance_hover(&mut self, state: &mut GameState) {
        let Some(hover) = self.hover.as_ref() else {
            return;
        };
        if self.hover_tick == Some(state.tick) {
            return;
        }
        self.hover_tick = Some(state.tick);
        let target = self
            .target
            .and_then(|id| state.players.iter().find(|p| p.id == id && p.hp > 0))
            .map(|p| [p.x, p.y - PLAYER_FLOOR_Y, p.z]);
        let arena = state.current_arena().into_owned();
        let contacts = state.contact_bodies();
        let Some(player) = state.players.iter_mut().find(|p| p.id == self.id) else {
            return;
        };
        let floor = player.y - PLAYER_FLOOR_Y;
        if player.hp <= 0 {
            let support = arena.support_height(player.x, player.z, floor + 0.001);
            if self.landed && (floor - support).abs() <= 0.02 {
                return;
            }
            self.landed = false;
            player.vy -= crate::movement::GRAVITY * 0.05;
            let next = floor + player.vy * 0.05;
            player.y = PLAYER_FLOOR_Y + next.max(support);
            player.yaw = crate::movement::normalize_yaw(player.yaw + 0.12);
            if next <= support {
                self.landed = true;
                player.vy = 0.0;
                self.until = state.tick.saturating_add(20);
            }
            player.campaign = Some(self.identity());
            return;
        }
        player.vy = 0.0;
        if matches!(self.phase, EnemyPhase::Windup | EnemyPhase::Firing) {
            return;
        }
        let mut point = hover.patrol[self.patrol_point];
        if let Some(target) = target {
            if (player.x - target[0]).hypot(player.z - target[2]) < (floor - target[1]).max(0.0) {
                if let Some(candidate) = hover.patrol.iter().max_by(|a, b| {
                    (a[0] - target[0])
                        .hypot(a[2] - target[2])
                        .total_cmp(&(b[0] - target[0]).hypot(b[2] - target[2]))
                }) {
                    point = *candidate;
                }
            }
        }
        let delta = [point[0] - player.x, point[1] - floor, point[2] - player.z];
        let length = delta.iter().map(|v| v * v).sum::<f32>().sqrt();
        if length <= 0.02 {
            self.patrol_point = (self.patrol_point + 1) % hover.patrol.len();
            return;
        }
        let step = 0.8_f32 * 0.05 / length;
        let scale = step.min(1.0);
        let from = crate::movement::MoveState {
            x: player.x,
            y: floor,
            z: player.z,
            vx: 0.0,
            vz: 0.0,
            vy: 0.0,
            yaw: player.yaw,
        };
        let mut body = crate::movement::contact::ContactBody {
            key: player.id.to_string(),
            from,
            proposed: crate::movement::MoveState {
                x: (player.x + delta[0] * scale).clamp(hover.volume.min[0], hover.volume.max[0]),
                z: (player.z + delta[2] * scale).clamp(hover.volume.min[2], hover.volume.max[2]),
                y: (floor + delta[1] * scale).clamp(hover.band[0], hover.band[1]),
                ..from
            },
            height: crate::combat::target_height(player.campaign),
            radius: crate::movement::RADIUS,
            jump: false,
        };
        let fraction = contacts
            .iter()
            .filter(|b| b.key != body.key)
            .filter_map(|b| crate::movement::contact::sweep_time(&body, b))
            .fold(1.0_f32, f32::min);
        body.proposed.x = from.x + (body.proposed.x - from.x) * fraction;
        body.proposed.y = from.y + (body.proposed.y - from.y) * fraction;
        body.proposed.z = from.z + (body.proposed.z - from.z) * fraction;
        player.x = body.proposed.x;
        player.z = body.proposed.z;
        player.y = PLAYER_FLOOR_Y + body.proposed.y;
    }

    fn jammer(
        &mut self,
        target: Option<&crate::protocol::PlayerState>,
        eye: [f32; 3],
        timing: (u64, u64),
        tick: u64,
        state: &GameState,
    ) -> BotIntent {
        let (windup, recovery) = timing;
        let mut action = Action::default();
        if self.phase == EnemyPhase::Firing {
            self.enter(EnemyPhase::Recovery, tick, recovery);
            return BotIntent::default();
        }
        if self.phase == EnemyPhase::Windup {
            if target.is_none() {
                self.target = None;
                self.enter(EnemyPhase::Recovery, tick, recovery);
                return BotIntent::default();
            }
            action.yaw = Some(self.aim.0);
            action.pitch = Some(self.aim.1);
            if tick >= self.until {
                action.fire = true;
                self.enter(EnemyPhase::Firing, tick, 1);
            }
            return BotIntent { action, goal: None };
        }
        if !state.has_traveling_shot(self.id) {
            if let Some(target) =
                target.filter(|target| (target.x - eye[0]).hypot(target.z - eye[2]) <= ENGAGE_RANGE)
            {
                let centre = [
                    target.x,
                    target.y - PLAYER_FLOOR_Y + crate::combat::target_height(target.campaign) * 0.5,
                    target.z,
                ];
                if let Some(aim) = aim_at(eye, centre) {
                    self.begin_windup(aim, tick, windup, &mut action);
                    return BotIntent { action, goal: None };
                }
            }
        }
        if self.phase != EnemyPhase::Idle {
            self.enter(EnemyPhase::Idle, tick, 0);
        }
        BotIntent::default()
    }

    fn crawler(
        &mut self,
        target: Option<&crate::protocol::PlayerState>,
        grounded: bool,
        exposed: bool,
        feet: [f32; 3],
        tick: u64,
    ) -> BotIntent {
        const LEAP_TICKS: u64 = 16;
        let mut action = Action::default();
        if self.phase == EnemyPhase::Windup {
            action.yaw = Some(self.aim.0);
            if tick >= self.until {
                self.enter(EnemyPhase::Leaping, tick, LEAP_TICKS);
                action.jump = true;
                action.forward = true;
            }
            return BotIntent { action, goal: None };
        }
        if self.phase == EnemyPhase::Leaping {
            if tick >= self.until || (tick > self.started + 1 && grounded) {
                self.enter(EnemyPhase::Recovery, tick, CRAWLER_RECOVERY_TICKS);
                return BotIntent::default();
            }
            action.yaw = Some(self.aim.0);
            action.forward = true;
            return BotIntent { action, goal: None };
        }
        let Some(target) = target else {
            if tick <= self.search_until
                && (feet[0] - self.last_known[0]).hypot(feet[2] - self.last_known[2]) > 0.6
            {
                if self.phase != EnemyPhase::Moving {
                    self.enter(EnemyPhase::Moving, tick, 0);
                }
                action.forward = true;
                action.yaw =
                    Some((self.last_known[2] - feet[2]).atan2(self.last_known[0] - feet[0]));
                return BotIntent {
                    action,
                    goal: Some(NavigationGoal {
                        feet: self.last_known,
                        combat: false,
                    }),
                };
            }
            if self.phase != EnemyPhase::Idle {
                self.enter(EnemyPhase::Idle, tick, 0);
            }
            return BotIntent::default();
        };
        let distance = (target.x - feet[0]).hypot(target.z - feet[2]);
        if grounded
            && exposed
            && distance <= 4.0
            && (target.y - PLAYER_FLOOR_Y - feet[1]).abs() <= 1.2
        {
            self.aim = (
                (target.z - feet[2])
                    .atan2(target.x - feet[0])
                    .rem_euclid(TAU),
                0.0,
            );
            self.last_known = [target.x, target.y - PLAYER_FLOOR_Y, target.z];
            self.contact_used = false;
            self.enter(EnemyPhase::Windup, tick, CRAWLER_WINDUP_TICKS);
            action.yaw = Some(self.aim.0);
            return BotIntent { action, goal: None };
        }
        if self.phase != EnemyPhase::Moving {
            self.enter(EnemyPhase::Moving, tick, 0);
        }
        action.forward = true;
        action.yaw = Some((target.z - feet[2]).atan2(target.x - feet[0]));
        BotIntent {
            action,
            goal: Some(NavigationGoal {
                feet: [target.x, target.y - PLAYER_FLOOR_Y, target.z],
                combat: true,
            }),
        }
    }

    pub(super) fn claim_crawler_contact(&mut self) -> bool {
        if self.kind != EnemyKind::Crawler || self.phase != EnemyPhase::Leaping || self.contact_used
        {
            return false;
        }
        self.contact_used = true;
        true
    }

    /// Hold the platform, face the authored line, and glint at a visible target
    /// in reach. The aim locks on the first windup tick; the shared windup rule
    /// fires on its last tick or cancels when sight breaks first.
    fn marksman(
        &mut self,
        target: Option<&crate::protocol::PlayerState>,
        aim_point: Option<[f32; 3]>,
        eye: [f32; 3],
        windup: u64,
        tick: u64,
    ) -> BotIntent {
        let mut action = Action::default();
        let mut facing = self.home_yaw;
        if let Some(target) = target {
            facing = (target.z - eye[2]).atan2(target.x - eye[0]);
            if (target.x - eye[0]).hypot(target.z - eye[2]) <= MARKSMAN_ENGAGE_RANGE {
                if let Some(aim) = aim_point.and_then(|point| aim_at(eye, point)) {
                    self.begin_windup(aim, tick, windup, &mut action);
                    return BotIntent { action, goal: None };
                }
            }
        } else {
            self.target = None;
        }
        self.head = crate::movement::normalize_yaw(facing);
        action.yaw = Some(self.head);
        action.pitch = Some(0.0);
        if self.phase != EnemyPhase::Idle {
            self.enter(EnemyPhase::Idle, tick, 0);
        }
        BotIntent { action, goal: None }
    }

    /// Idle sweep, bounded tracking, then a locked spin-up. The turret never
    /// walks, never searches and forgets a target the moment sight breaks.
    fn turret(
        &mut self,
        target: Option<&crate::protocol::PlayerState>,
        eye: [f32; 3],
        windup: u64,
        tick: u64,
        centre: &dyn Fn(&crate::protocol::PlayerState) -> [f32; 3],
    ) -> BotIntent {
        let mut action = Action::default();
        let Some(target) = target else {
            self.target = None;
            if self.phase != EnemyPhase::Idle {
                self.enter(EnemyPhase::Idle, tick, 0);
            }
            let edge = self.home_yaw + self.sweep * TURRET_SWEEP_ARC;
            if self.face(&mut action, edge, TURRET_SWEEP_RATE).abs() <= TURRET_SWEEP_RATE {
                self.sweep = -self.sweep;
            }
            return BotIntent { action, goal: None };
        };
        let bearing = (target.z - eye[2]).atan2(target.x - eye[0]);
        let remaining = self.face(&mut action, bearing, TURRET_TRACK_RATE);
        let distance = (target.x - eye[0]).hypot(target.z - eye[2]);
        if remaining.abs() <= TURRET_LOCK && distance <= TURRET_ENGAGE_RANGE {
            if let Some(aim) = aim_at(eye, centre(target)) {
                self.begin_windup(aim, tick, windup, &mut action);
                return BotIntent { action, goal: None };
            }
        }
        if self.phase != EnemyPhase::Moving {
            self.enter(EnemyPhase::Moving, tick, 0);
        }
        BotIntent { action, goal: None }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn union_pursues_the_participant_even_when_latch_is_closer() {
        use crate::maps::AuthoredSource;
        use crate::protocol::{MissionId, Role};

        let mut state = GameState::with_authored_map(
            AuthoredSource::Mission(MissionId::PersonsUnknown)
                .load()
                .unwrap(),
        );
        let participant_id = Uuid::from_u128(0x02b0);
        state.add_player(participant_id, "Runner".into(), Role::Human);
        assert!(state.acknowledge_m02(participant_id, 1));
        let placement = state.map.encounters()[3]
            .enemies
            .iter()
            .find(|placement| placement.id == "ward_sweeper")
            .unwrap()
            .clone();
        let enemy_id = state.spawn_campaign_enemy(&placement);
        let companion_id = state.spawn_m02_companion().unwrap();
        let participant = state
            .players
            .iter_mut()
            .find(|p| p.id == participant_id)
            .unwrap();
        [participant.x, participant.y, participant.z] = [7.0, PLAYER_FLOOR_Y, -11.0];
        let companion = state
            .players
            .iter_mut()
            .find(|p| p.id == companion_id)
            .unwrap();
        [companion.x, companion.y, companion.z] = [5.5, PLAYER_FLOOR_Y, -11.0];
        let snapshot = state.snapshot();
        let enemy = snapshot.players.iter().find(|p| p.id == enemy_id).unwrap();
        let eye = [enemy.x, crate::movement::EYE_HEIGHT, enemy.z];
        for target_id in [companion_id, participant_id] {
            let target = snapshot.players.iter().find(|p| p.id == target_id).unwrap();
            assert!(line_of_sight(
                eye,
                [
                    target.x,
                    crate::combat::target_height(target.campaign) * 0.5,
                    target.z
                ],
                &state.current_arena().solids,
            ));
        }
        let mut controller = EnemyController::new(
            enemy_id,
            placement.kind,
            placement.feet,
            placement.yaw,
            state.tick,
            false,
        );
        controller.intent(&state, &snapshot);
        assert_eq!(controller.target, Some(participant_id));

        state
            .players
            .iter_mut()
            .find(|p| p.id == participant_id)
            .unwrap()
            .hp = 0;
        let mut controller = EnemyController::new(
            enemy_id,
            placement.kind,
            placement.feet,
            placement.yaw,
            state.tick,
            false,
        );
        controller.intent(&state, &state.snapshot());
        assert_eq!(
            controller.target, None,
            "an invulnerable ally cannot distract Union fire"
        );
    }

    #[test]
    fn crawler_waits_for_visible_body_width_before_windup() {
        use crate::maps::AuthoredSource;
        use crate::protocol::{MissionId, Role};

        let mut state = GameState::with_authored_map(
            AuthoredSource::Mission(MissionId::PersonsUnknown)
                .load()
                .unwrap(),
        );
        let player_id = Uuid::from_u128(0x02c2);
        state.add_player(player_id, "Viewer".into(), Role::Human);
        let player = state
            .players
            .iter_mut()
            .find(|p| p.id == player_id)
            .unwrap();
        player.x = -10.810527;
        player.y = PLAYER_FLOOR_Y + 1.0;
        player.z = -29.530794;
        let snapshot = state.snapshot();
        let viewer = snapshot.players.iter().find(|p| p.id == player_id).unwrap();
        let solids = &state.current_arena().solids;
        let corner_feet = [-11.192674, 0.0, -27.475136];
        let eye = [viewer.x, 1.0 + crate::movement::EYE_HEIGHT, viewer.z];
        let centre = [
            corner_feet[0],
            crate::combat::CRAWLER_HEIGHT * 0.5,
            corner_feet[2],
        ];
        assert!(
            line_of_sight(eye, centre, solids),
            "the center ray clears the pillar edge"
        );
        assert!(
            !crawler_body_exposed(viewer, corner_feet, solids),
            "a center ray with one hidden flank is not a readable tell"
        );

        let mut crawler = EnemyController::new(
            Uuid::from_u128(0x02c3),
            EnemyKind::Crawler,
            corner_feet,
            0.0,
            0,
            false,
        );
        let hidden = crawler.crawler(Some(viewer), true, false, corner_feet, 20);
        assert_eq!(crawler.phase, EnemyPhase::Moving);
        assert!(hidden.action.forward);

        let open_feet = [-10.6, 0.0, -27.475136];
        assert!(crawler_body_exposed(viewer, open_feet, solids));
        let exposed = crawler.crawler(Some(viewer), true, true, open_feet, 21);
        assert_eq!(crawler.phase, EnemyPhase::Windup);
        assert!(!exposed.action.forward);
    }

    #[test]
    fn crawler_leap_lands_on_a_higher_support_and_holds_recovery() {
        let mut crawler = EnemyController::new(
            Uuid::nil(),
            EnemyKind::Crawler,
            [0.0, 0.0, 0.0],
            0.0,
            0,
            false,
        );
        crawler.aim = (0.0, 0.0);
        crawler.enter(EnemyPhase::Windup, 1, 12);
        let launch = crawler.crawler(None, true, false, [0.0, 0.0, 0.0], 13);
        assert!(launch.action.jump && launch.action.forward);
        assert_eq!(crawler.phase, EnemyPhase::Leaping);
        crawler.crawler(None, false, false, [0.5, 1.3, 0.0], 14);
        assert_eq!(crawler.phase, EnemyPhase::Leaping);
        let landed = crawler.crawler(None, true, false, [1.0, 1.0, 0.0], 15);
        assert!(!landed.action.forward && !landed.action.jump);
        assert_eq!(crawler.phase, EnemyPhase::Recovery);
        assert_eq!(crawler.until, 35);
        crawler.search_until = 0;
        let mut state = GameState::new();
        state.add_player(Uuid::nil(), "Crawler".into(), crate::protocol::Role::Human);
        state.players[0].campaign = Some(crawler.identity());
        state.tick = 33;
        let snapshot = state.snapshot();
        crawler.intent(&state, &snapshot);
        assert_eq!(
            crawler.phase,
            EnemyPhase::Recovery,
            "recovery holds through tick 34"
        );
        state.tick = 34;
        let snapshot = state.snapshot();
        crawler.intent(&state, &snapshot);
        assert_eq!(
            crawler.phase,
            EnemyPhase::Idle,
            "the next decision may leave recovery"
        );
        assert_eq!(
            attack_timing(EnemyKind::Crawler, CampaignDifficulty::Assisted),
            (12, 20)
        );
        assert_eq!(
            attack_timing(EnemyKind::Crawler, CampaignDifficulty::Severe),
            (12, 20)
        );
    }

    #[test]
    fn lost_guard_walks_back_to_its_post_once_then_waits() {
        use crate::maps::AuthoredSource;
        use crate::protocol::MissionId;

        let mut state = GameState::with_authored_map(
            AuthoredSource::Mission(MissionId::ScheduledService)
                .load()
                .unwrap(),
        );
        // The Scheduled Service straggler: a train Clerk that chased the
        // participant south and lost sight stood idle by the siding while
        // the party waited at the locomotive for the group to clear.
        let placement = state
            .map
            .encounters()
            .iter()
            .flat_map(|group| group.enemies.iter())
            .find(|placement| placement.id == "train_clerk_a")
            .unwrap()
            .clone();
        let enemy_id = state.spawn_campaign_enemy(&placement);
        let mut guard = EnemyController::new(
            enemy_id,
            placement.kind,
            placement.feet,
            placement.yaw,
            state.tick,
            false,
        );
        let stray = [-11.0, 0.0, 16.7];
        let move_body = |state: &mut GameState, x: f32, z: f32| {
            let body = state.players.iter_mut().find(|p| p.id == enemy_id).unwrap();
            [body.x, body.y, body.z] = [x, PLAYER_FLOOR_Y, z];
        };
        move_body(&mut state, stray[0], stray[2]);
        guard.search_until = 0;
        state.tick = 700;
        let unalarmed = guard.intent(&state, &state.snapshot());
        assert!(
            unalarmed.goal.is_none() && guard.phase == EnemyPhase::Idle,
            "a guard that was never alarmed or chasing stays put"
        );

        // An alarm search that ends far away keeps the authored dispatch
        // while other guards of the group still stand.
        guard.alarm([10.1, 0.0, 24.5], 700);
        guard.search_until = 0;
        state.tick = 700;
        assert!(guard.intent(&state, &state.snapshot()).goal.is_none());

        // As the group's last guard it is given a route home.
        guard.last_standing = true;
        state.tick = 701;
        let walk = guard.intent(&state, &state.snapshot());
        let goal = walk.goal.expect("the stray guard is given a route home");
        assert_eq!(goal.feet, placement.feet, "home is the authored post");
        assert!(!goal.combat && walk.action.forward && !walk.action.fire);
        assert_eq!(guard.phase, EnemyPhase::Moving);

        // Arriving at the post settles the guard.
        move_body(&mut state, placement.feet[0] + 0.3, placement.feet[2]);
        state.tick = 702;
        let settled = guard.intent(&state, &state.snapshot());
        assert!(settled.goal.is_none() && !settled.action.forward);
        assert_eq!(guard.phase, EnemyPhase::Idle);

        // A blocked walk home gives up after its bound instead of retrying,
        // and an ordinary chase that ends far away also walks home once.
        move_body(&mut state, stray[0], stray[2]);
        guard.search_until = 0;
        state.tick = 2000;
        let stuck = guard.intent(&state, &state.snapshot());
        assert!(stuck.goal.is_none() && guard.phase == EnemyPhase::Idle);
        guard.chased = true;
        state.tick = 2001;
        assert!(guard.intent(&state, &state.snapshot()).goal.is_some());

        // A short chase that ends near the post stays where it ended.
        move_body(&mut state, placement.feet[0] + 4.0, placement.feet[2]);
        guard.chased = true;
        guard.search_until = 0;
        state.tick = 2002;
        assert!(guard.intent(&state, &state.snapshot()).goal.is_none());
    }

    #[test]
    fn seated_clerk_stands_on_alarm_or_hit() {
        let seated = || EnemyController::new(Uuid::nil(), EnemyKind::Clerk, [0.0; 3], 0.0, 0, true);
        let mut alarmed = seated();
        assert!(matches!(
            alarmed.identity(),
            CampaignActor::Union { seated: true, .. }
        ));
        alarmed.alarm([1.0, 0.0, 0.0], 1);
        assert!(matches!(
            alarmed.identity(),
            CampaignActor::Union { seated: false, .. }
        ));

        let mut struck = seated();
        struck.hit(1, false);
        assert!(matches!(
            struck.identity(),
            CampaignActor::Union { seated: false, .. }
        ));
    }
}
