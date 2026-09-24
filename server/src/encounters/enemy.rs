use crate::combat::{aim_at, line_of_sight, FIGHTER_HEIGHT};
use crate::movement::EYE_HEIGHT;
use crate::navigation::NavigationGoal;
use crate::protocol::{
    Action, CampaignActor, CampaignDifficulty, EnemyKind, EnemyPhase, Snapshot, WeaponType,
};
use crate::sim::{BotIntent, GameState, PLAYER_FLOOR_Y};
use uuid::Uuid;

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
}

impl EnemyController {
    fn attack_timing(&self, difficulty: CampaignDifficulty) -> (u64, u64) {
        match (self.kind, difficulty) {
            (EnemyKind::Clerk, CampaignDifficulty::Assisted) => (20, 30),
            (EnemyKind::Clerk, CampaignDifficulty::Standard) => (12, 20),
            (EnemyKind::Clerk, CampaignDifficulty::Severe) => (10, 16),
            (EnemyKind::Sweeper, CampaignDifficulty::Assisted) => (22, 38),
            (EnemyKind::Sweeper, CampaignDifficulty::Standard) => (14, 26),
            (EnemyKind::Sweeper, CampaignDifficulty::Severe) => (12, 20),
        }
    }

    pub fn new(id: Uuid, kind: EnemyKind, alarm_position: [f32; 3], tick: u64) -> Self {
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
        self.shots_left = 0;
        self.enter(
            if died {
                EnemyPhase::Dead
            } else {
                EnemyPhase::Hit
            },
            tick,
            if died { 40 } else { 6 },
        );
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
        let (windup, recovery) = self.attack_timing(state.campaign_rules().difficulty);
        let feet = [me.x, me.y - PLAYER_FLOOR_Y, me.z];
        let eye = [me.x, feet[1] + EYE_HEIGHT, me.z];
        let centre = |p: &crate::protocol::PlayerState| {
            [p.x, p.y - PLAYER_FLOOR_Y + FIGHTER_HEIGHT * 0.5, p.z]
        };
        let visible = |p: &&crate::protocol::PlayerState| {
            me.is_hostile_to(p)
                && crate::mission::actor_active(state.mission.as_ref(), p.id, p.campaign)
                && (p.x - me.x).hypot(p.z - me.z) <= 32.0
                && line_of_sight(eye, centre(p), &state.map.arena().solids)
        };
        let target = self
            .target
            .and_then(|id| snapshot.players.iter().find(|p| p.id == id).filter(visible))
            .or_else(|| {
                // A committed attack never snaps to a replacement target.
                (!matches!(self.phase, EnemyPhase::Windup | EnemyPhase::Firing))
                    .then(|| {
                        snapshot.players.iter().filter(visible).min_by(|a, b| {
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

        let mut action = Action::default();
        if matches!(self.phase, EnemyPhase::Hit | EnemyPhase::Recovery) && tick < self.until {
            return BotIntent::default();
        }
        let Some(body) = state.players.iter().find(|p| p.id == self.id) else {
            return BotIntent::default();
        };
        // Guards spend the same finite ammunition counts as participants.
        // An empty guard can still defend themselves at melee distance.
        if let Some(loadout) = body.inventory.state(body.id, body.weapon, state.tick) {
            if loadout.shots(body.weapon) == Some(0) {
                action.weapon_swap = Some(WeaponType::Fists);
                self.enter(EnemyPhase::Recovery, tick, 6);
                return BotIntent { action, goal: None };
            }
        }
        if matches!(self.phase, EnemyPhase::Windup | EnemyPhase::Firing) {
            if target.is_none() {
                self.target = None;
                self.enter(EnemyPhase::Recovery, tick, 12);
                return BotIntent::default();
            }
            action.yaw = Some(self.aim.0);
            action.pitch = Some(self.aim.1);
            if self.phase == EnemyPhase::Windup && tick >= self.until {
                self.shots_left =
                    if self.kind == EnemyKind::Sweeper && body.weapon != WeaponType::Fists {
                        3
                    } else {
                        1
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
        if let Some(target) = target {
            let distance = (target.x - me.x).hypot(target.z - me.z);
            if distance <= body.weapon.range_units().min(24.0) {
                if let Some(aim) = aim_at(eye, centre(target)) {
                    self.aim = aim;
                    self.enter(EnemyPhase::Windup, tick, windup);
                    action.yaw = Some(aim.0);
                    action.pitch = Some(aim.1);
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
}
