//! Issued powered armor commits momentum, never a target-following ray.
use super::*;

pub(crate) const CHARGE_TICKS: u64 = 14;
pub(crate) const CHARGE_DAMAGE: i32 = 30;
pub(crate) const CHARGE_SHOVE: f32 = 1.5;
pub(crate) const CHARGE_FALL: f32 = 2.5;

impl EnemyController {
    pub(super) fn enforcer(
        &mut self,
        target: Option<&crate::protocol::PlayerState>,
        feet: [f32; 3],
        grounded: bool,
        timing: (u64, u64),
        tick: u64,
    ) -> BotIntent {
        let mut action = Action::default();
        if grounded && matches!(self.phase, EnemyPhase::Hit | EnemyPhase::Recovery) {
            self.charge_floor = None;
        }
        if matches!(self.phase, EnemyPhase::Hit | EnemyPhase::Recovery) && tick < self.until {
            return BotIntent::default();
        }
        if self.phase == EnemyPhase::Windup {
            action.yaw = Some(self.aim.0);
            if tick >= self.until {
                // A falling body cannot begin a ground charge. Only a charge
                // launched from actual support can own the descent counter.
                if !grounded {
                    self.charge_floor = None;
                    self.enter(EnemyPhase::Recovery, tick, timing.1);
                    return BotIntent::default();
                }
                self.enter(EnemyPhase::Charging, tick, CHARGE_TICKS);
                self.charge_floor = Some(feet[1]);
                action.forward = true;
            }
            return BotIntent { action, goal: None };
        }
        if self.phase == EnemyPhase::Charging {
            if tick >= self.until {
                self.enter(EnemyPhase::Recovery, tick, timing.1);
                if grounded {
                    self.charge_floor = None;
                }
                return BotIntent::default();
            }
            action.yaw = Some(self.aim.0);
            action.forward = true;
            return BotIntent { action, goal: None };
        }
        let destination = target.map_or(self.last_known, |p| [p.x, p.y - PLAYER_FLOOR_Y, p.z]);
        let distance = (destination[0] - feet[0]).hypot(destination[2] - feet[2]);
        if grounded
            && target.is_some()
            && distance <= 8.0
            && (destination[1] - feet[1]).abs() <= 0.5
        {
            self.aim = (
                (destination[2] - feet[2])
                    .atan2(destination[0] - feet[0])
                    .rem_euclid(TAU),
                0.0,
            );
            self.contact_used = false;
            self.stagger_ready = true;
            self.enter(EnemyPhase::Windup, tick, timing.0);
            action.yaw = Some(self.aim.0);
            return BotIntent { action, goal: None };
        }
        if distance > 0.6 && (target.is_some() || tick <= self.search_until) {
            if self.phase != EnemyPhase::Moving {
                self.enter(EnemyPhase::Moving, tick, 0);
            }
            action.forward = true;
            action.yaw = Some((destination[2] - feet[2]).atan2(destination[0] - feet[0]));
            return BotIntent {
                action,
                goal: Some(NavigationGoal {
                    feet: destination,
                    combat: target.is_some(),
                }),
            };
        }
        if self.phase != EnemyPhase::Idle {
            self.enter(EnemyPhase::Idle, tick, 0);
        }
        BotIntent::default()
    }

    pub(in crate::encounters) fn claim_enforcer_contact(&mut self) -> bool {
        if self.kind != EnemyKind::Enforcer
            || self.phase != EnemyPhase::Charging
            || self.contact_used
        {
            return false;
        }
        self.contact_used = true;
        true
    }

    pub(in crate::encounters) fn enforcer_fell(&self, feet: [f32; 3]) -> bool {
        self.kind == EnemyKind::Enforcer
            && self.phase != EnemyPhase::Dead
            && self
                .charge_floor
                .is_some_and(|start| start - feet[1] > CHARGE_FALL)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_preexisting_fall_cannot_start_or_claim_a_charge_descent() {
        let mut enemy = EnemyController::new(
            Uuid::nil(),
            EnemyKind::Enforcer,
            [0.0, 4.0, 0.0],
            0.0,
            0,
            false,
        );
        let timing = attack_timing(EnemyKind::Enforcer, CampaignDifficulty::Severe);
        enemy.enter(EnemyPhase::Windup, 1, timing.0);
        let intent = enemy.enforcer(None, [0.0, 3.0, 0.0], false, timing, 1 + timing.0);
        assert_eq!(enemy.phase, EnemyPhase::Recovery);
        assert!(!intent.action.forward && intent.goal.is_none());
        assert!(!enemy.claim_enforcer_contact());
        assert!(!enemy.enforcer_fell([0.0, 0.0, 0.0]));
    }

    #[test]
    fn charge_commits_aim_after_tell_and_never_follows_a_dodge() {
        let mut enemy = EnemyController::new(
            Uuid::nil(),
            EnemyKind::Enforcer,
            [0.0, 4.0, 0.0],
            0.0,
            0,
            false,
        );
        let mut game = GameState::new();
        game.add_player(
            Uuid::from_u128(1),
            "walker".into(),
            crate::protocol::Role::Human,
        );
        game.players[0].x = 6.0;
        game.players[0].z = 0.0;
        game.players[0].y = PLAYER_FLOOR_Y + 4.0;
        let first = game.snapshot();
        let timing = attack_timing(EnemyKind::Enforcer, CampaignDifficulty::Standard);
        let windup = enemy.enforcer(Some(&first.players[0]), [0.0, 4.0, 0.0], true, timing, 1);
        assert_eq!((enemy.phase, enemy.until), (EnemyPhase::Windup, 25));
        assert!(!windup.action.forward && windup.goal.is_none());
        game.players[0].z = 6.0;
        let dodged = game.snapshot();
        for tick in 2..25 {
            let intent = enemy.enforcer(
                Some(&dodged.players[0]),
                [0.0, 4.0, 0.0],
                true,
                timing,
                tick,
            );
            assert!(!intent.action.forward && !intent.action.fire && intent.goal.is_none());
            assert_eq!(intent.action.yaw, Some(0.0));
        }
        let launch = enemy.enforcer(Some(&dodged.players[0]), [0.0, 4.0, 0.0], true, timing, 25);
        assert!(launch.action.forward && !launch.action.jump && !launch.action.fire);
        assert_eq!((enemy.phase, enemy.until), (EnemyPhase::Charging, 39));
        assert!(enemy.claim_enforcer_contact());
        assert!(!enemy.claim_enforcer_contact());
        let lost = enemy.enforcer(None, [2.0, 4.0, 0.0], true, timing, 27);
        assert!(lost.action.forward && lost.goal.is_none());
        assert_eq!(lost.action.yaw, Some(0.0));
        assert!(!enemy.enforcer_fell([4.0, 1.5, 0.0]));
        assert!(enemy.enforcer_fell([4.0, 1.49, 0.0]));
        let recover = enemy.enforcer(None, [6.0, 4.0, 0.0], true, timing, 39);
        assert!(!recover.action.forward);
        assert_eq!((enemy.phase, enemy.until), (EnemyPhase::Recovery, 75));
        assert!(
            !enemy
                .enforcer(None, [6.0, 4.0, 0.0], true, timing, 74)
                .action
                .forward
        );
        enemy.hit(76, true);
        assert!(!enemy.enforcer_fell([4.0, 0.0, 0.0]));
    }
}
