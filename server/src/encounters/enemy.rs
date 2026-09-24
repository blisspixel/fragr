use crate::combat::{aim_at, line_of_sight, FIGHTER_HEIGHT};
use crate::movement::EYE_HEIGHT;
use crate::navigation::NavigationGoal;
use crate::protocol::{
    Action, CampaignActor, CampaignDifficulty, EnemyKind, EnemyPhase, Snapshot, WeaponType,
};
use crate::sim::{BotIntent, GameState, PLAYER_FLOOR_Y};
use std::f32::consts::{PI, TAU};
use uuid::Uuid;

/// Damage from one tick at or above this staggers an armored body. A Rail hit,
/// a close Scatter blast or several pellets landing together qualify; a single
/// pistol, rifle or fist hit does not.
pub(crate) const STAGGER_DAMAGE: i32 = 40;
/// Visual pursuit memory and the engagement bound shared by walking enemies.
const SIGHT_RANGE: f32 = 32.0;
const ENGAGE_RANGE: f32 = 24.0;
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

/// Spawned health and issued weapon. Difficulty never changes these.
pub(crate) fn body(kind: EnemyKind) -> (i32, WeaponType) {
    match kind {
        EnemyKind::Clerk => (60, WeaponType::Tack),
        EnemyKind::Sweeper => (80, WeaponType::Flechette),
        EnemyKind::HeavySweeper => (160, WeaponType::Flechette),
        EnemyKind::Turret => (100, WeaponType::Rail),
    }
}

/// Share of participant top speed. Turrets are fixed equipment.
pub(crate) fn gait(kind: EnemyKind) -> f32 {
    match kind {
        EnemyKind::Clerk | EnemyKind::Sweeper => 0.5,
        EnemyKind::HeavySweeper => 0.3,
        EnemyKind::Turret => 0.0,
    }
}

/// Committed shots per attack.
fn burst(kind: EnemyKind) -> u8 {
    match kind {
        EnemyKind::Clerk | EnemyKind::Turret => 1,
        EnemyKind::Sweeper => 3,
        EnemyKind::HeavySweeper => 4,
    }
}

/// Hit stun in ticks. Armored bodies only enter it on a heavy hit.
fn stun(kind: EnemyKind) -> u64 {
    match kind {
        EnemyKind::Clerk | EnemyKind::Sweeper => 6,
        EnemyKind::HeavySweeper => 16,
        EnemyKind::Turret => 10,
    }
}

fn armored(kind: EnemyKind) -> bool {
    matches!(kind, EnemyKind::HeavySweeper | EnemyKind::Turret)
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
    }
}

impl EnemyController {
    pub fn new(id: Uuid, kind: EnemyKind, alarm_position: [f32; 3], yaw: f32, tick: u64) -> Self {
        Self {
            id,
            kind,
            phase: EnemyPhase::Idle,
            started: tick,
            until: tick,
            target: None,
            last_known: alarm_position,
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
        }
    }

    pub fn identity(&self) -> CampaignActor {
        CampaignActor::Union {
            kind: self.kind,
            phase: self.phase,
            phase_started: self.started,
            phase_ends: self.until,
        }
    }

    pub fn alarm(&mut self, position: [f32; 3], tick: u64) {
        self.last_known = position;
        self.search_until = tick.saturating_add(600);
    }

    fn enter(&mut self, phase: EnemyPhase, tick: u64, duration: u64) {
        self.phase = phase;
        self.started = tick;
        self.until = tick.saturating_add(duration);
    }

    pub fn hit(&mut self, tick: u64, died: bool) {
        if self.phase == EnemyPhase::Dead {
            return;
        }
        if died {
            self.shots_left = 0;
            self.enter(EnemyPhase::Dead, tick, 40);
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
        let feet = [me.x, me.y - PLAYER_FLOOR_Y, me.z];
        let eye = [me.x, feet[1] + EYE_HEIGHT, me.z];
        let centre = |p: &crate::protocol::PlayerState| {
            [p.x, p.y - PLAYER_FLOOR_Y + FIGHTER_HEIGHT * 0.5, p.z]
        };
        let visible = |p: &&crate::protocol::PlayerState| {
            me.is_hostile_to(p)
                && crate::mission::actor_active(state.mission.as_ref(), p.id, p.campaign)
                && (p.x - me.x).hypot(p.z - me.z) <= SIGHT_RANGE
                && line_of_sight(eye, centre(p), &state.map.arena().solids)
        };
        let head = self.head;
        let noticed = |p: &&crate::protocol::PlayerState| {
            !turret || turn(head, (p.z - me.z).atan2(p.x - me.x)).abs() <= TURRET_ACQUIRE_CONE
        };
        let target = self
            .target
            .and_then(|id| snapshot.players.iter().find(|p| p.id == id).filter(visible))
            .or_else(|| {
                // A committed attack never snaps to a replacement target.
                (!matches!(self.phase, EnemyPhase::Windup | EnemyPhase::Firing))
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
            self.target = Some(target.id);
            self.last_known = [target.x, target.y - PLAYER_FLOOR_Y, target.z];
            self.search_until = tick.saturating_add(100);
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
        if matches!(self.phase, EnemyPhase::Hit | EnemyPhase::Recovery) && tick < self.until {
            return BotIntent::default();
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
        // Guards spend the same finite ammunition counts as participants.
        // An empty guard can still defend themselves at melee distance.
        if let Some(loadout) = body.inventory.state(body.id, body.weapon, state.tick) {
            if loadout.shots(body.weapon) == Some(0) {
                if turret {
                    // A dry turret has no melee. It stays still and harmless.
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
        if self.phase != EnemyPhase::Idle {
            self.enter(EnemyPhase::Idle, tick, 0);
        }
        BotIntent::default()
    }

    fn begin_windup(&mut self, aim: (f32, f32), tick: u64, windup: u64, action: &mut Action) {
        self.aim = aim;
        self.head = aim.0;
        self.stagger_ready = true;
        self.enter(EnemyPhase::Windup, tick, windup);
        action.yaw = Some(aim.0);
        action.pitch = Some(aim.1);
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
