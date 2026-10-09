use super::*;

impl EnemyController {
    pub(super) fn assessor(
        &mut self,
        target: Option<&crate::protocol::PlayerState>,
        eye: [f32; 3],
        timing: (u64, u64),
        tick: u64,
    ) -> BotIntent {
        let (windup, recovery) = timing;
        let mut action = Action::default();
        if matches!(self.phase, EnemyPhase::Windup | EnemyPhase::Firing) {
            if target.is_none() || self.canisters_left == 0 {
                self.target = None;
                self.shots_left = 0;
                self.canister_target = None;
                self.enter(EnemyPhase::Recovery, tick, recovery);
                return BotIntent::default();
            }
            action.yaw = Some(self.aim.0);
            action.pitch = Some(self.aim.1);
            if self.phase == EnemyPhase::Windup && tick >= self.until {
                self.shots_left = self.canisters_left.min(3);
                self.next_shot = tick;
                self.enter(EnemyPhase::Firing, tick, 13);
            }
            if self.phase == EnemyPhase::Firing && self.shots_left > 0 && tick >= self.next_shot {
                action.fire = true;
                self.shots_left -= 1;
                self.next_shot = tick.saturating_add(6);
            } else if self.phase == EnemyPhase::Firing && self.shots_left == 0 {
                self.enter(EnemyPhase::Recovery, tick, recovery);
            }
            return BotIntent { action, goal: None };
        }
        if self.canisters_left > 0 {
            if let Some(target) = target {
                let point = crate::combat::aim_point_for(
                    [target.x, target.y - PLAYER_FLOOR_Y, target.z],
                    target.campaign,
                    target.ducking,
                );
                let horizontal = (point[0] - eye[0]).hypot(point[2] - eye[2]);
                if horizontal >= (eye[1] - point[1]).max(0.0)
                    && horizontal <= 24.0
                    && crate::sim::assessor::launch_velocity(eye, point).is_some()
                {
                    if let Some(aim) = aim_at(eye, point) {
                        self.begin_windup(aim, tick, windup, &mut action);
                        self.canister_target = Some(point);
                        return BotIntent { action, goal: None };
                    }
                }
            }
        }
        if self.phase != EnemyPhase::Moving {
            self.enter(EnemyPhase::Moving, tick, 0);
        }
        BotIntent::default()
    }

    pub(in crate::encounters) fn canister_target(&self) -> Option<[f32; 3]> {
        (self.kind == EnemyKind::Assessor
            && self.canisters_left > 0
            && self.phase == EnemyPhase::Firing)
            .then_some(self.canister_target)
            .flatten()
    }

    pub(in crate::encounters) fn spend_canister(&mut self) -> bool {
        if self.canister_target().is_none() {
            return false;
        }
        self.canisters_left -= 1;
        true
    }

    pub(in crate::encounters) fn take_wreck(&mut self) -> bool {
        std::mem::take(&mut self.wreck_pending)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn assessor_intent_keeps_tier_windows_locked_aim_and_real_burst_spacing() {
        use crate::protocol::Role;
        let mut state = GameState::new();
        let target_id = Uuid::from_u128(991);
        state.add_player(target_id, "Visitor".into(), Role::Human);
        let mut target = state.snapshot().players.remove(0);
        target.x = 10.0;
        target.z = 0.0;
        target.y = PLAYER_FLOOR_Y;
        let eye = [0.0, 4.6, 0.0];
        for (tier, windup, recovery) in [
            (CampaignDifficulty::Assisted, 32, 50),
            (CampaignDifficulty::Standard, 24, 40),
            (CampaignDifficulty::Severe, 18, 32),
        ] {
            assert_eq!(attack_timing(EnemyKind::Assessor, tier), (windup, recovery));
            let mut controller = EnemyController::new(
                Uuid::from_u128(992),
                EnemyKind::Assessor,
                [0.0, 4.0, 0.0],
                0.0,
                10,
                false,
            );
            let initial = controller.assessor(Some(&target), eye, (windup, recovery), 10);
            assert!(!initial.action.fire);
            let point = controller.canister_target.unwrap();
            let aim = controller.aim;
            let mut moved = target.clone();
            moved.z = 5.0;
            let mut fires = Vec::new();
            for tick in 11..=10 + windup + 13 {
                let intent = controller.assessor(Some(&moved), eye, (windup, recovery), tick);
                assert_eq!(
                    controller.canister_target,
                    Some(point),
                    "committed point never tracks a lateral dodge"
                );
                if intent.action.fire {
                    assert_eq!(
                        (intent.action.yaw, intent.action.pitch),
                        (Some(aim.0), Some(aim.1))
                    );
                    assert!(controller.spend_canister());
                    fires.push(tick);
                }
            }
            assert_eq!(fires, vec![10 + windup, 16 + windup, 22 + windup]);
            assert_eq!(controller.phase, EnemyPhase::Recovery);
            assert_eq!(controller.until, 23 + windup + recovery);
            assert_eq!(controller.canisters_left, 27);
        }
    }
}
