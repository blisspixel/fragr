//! A visible close ambush uses the shared walking controller and ordinary strike.
use super::*;
use crate::movement::{Arena, BODY_HEIGHT, RADIUS, STEP_UP};

const APPROACH_TICKS: u64 = 60;
const APPROACH_RANGE: f32 = 6.0;
const APPROACH_OFFSET: f32 = 1.3;

impl EnemyController {
    pub(super) fn redactor_approach(
        &mut self,
        state: &GameState,
        target: Option<&crate::protocol::PlayerState>,
        feet: [f32; 3],
        tick: u64,
    ) -> Option<BotIntent> {
        let Some(target) = target else {
            self.redactor_approach = None;
            self.redactor_approached = false;
            return None;
        };
        if self.phase == EnemyPhase::Recovery {
            self.redactor_approach = None;
            self.redactor_approached = false;
        }
        if self
            .redactor_approach
            .is_some_and(|(id, _)| id != target.id)
        {
            self.redactor_approach = None;
            self.redactor_approached = false;
        }
        if let Some((_, goal)) = self.redactor_approach {
            if tick >= self.redactor_approach_until
                || (goal[0] - feet[0]).hypot(goal[2] - feet[2]) <= 0.35
            {
                self.redactor_approach = None;
            }
        }
        let dx = target.x - feet[0];
        let dz = target.z - feet[2];
        let distance = dx.hypot(dz);
        // Fixed local clearance probes choose an approach; all walking and
        // bounded path searches still belong to the Session navigator.
        if !self.redactor_approached && distance <= APPROACH_RANGE {
            self.redactor_approached = true;
            let arena = state.current_arena();
            let same_floor = (target.y - PLAYER_FLOOR_Y - feet[1]).abs() <= 0.02;
            if same_floor && distance > WeaponType::Shiv.range_units() {
                let direction = [dx / distance, dz / distance];
                let contacts = state.contact_bodies();
                let own_key = self.id.to_string();
                for side in [1.0_f32, -1.0] {
                    let goal = [
                        target.x
                            - direction[0] * APPROACH_OFFSET
                            - direction[1] * APPROACH_OFFSET * side,
                        feet[1],
                        target.z - direction[1] * APPROACH_OFFSET
                            + direction[0] * APPROACH_OFFSET * side,
                    ];
                    let clear_of_bodies = contacts.iter().all(|body| {
                        body.key == own_key
                            || body.from.y + body.height <= goal[1]
                            || goal[1] + BODY_HEIGHT <= body.from.y
                            || (body.from.x - goal[0]).hypot(body.from.z - goal[2])
                                >= body.radius + RADIUS + 0.02
                    });
                    if clear_of_bodies && supported_approach(&arena, feet, goal) {
                        self.redactor_approach = Some((target.id, goal));
                        self.redactor_approach_until = tick.saturating_add(APPROACH_TICKS);
                        break;
                    }
                }
            }
        }
        let (_, goal) = self.redactor_approach?;
        // A changed world or actor occupying the held slot does not permit
        // an unsupported stance. The normal pursuit supplies the fallback.
        let arena = state.current_arena();
        let own_key = self.id.to_string();
        let occupied = state.contact_bodies().iter().any(|body| {
            body.key != own_key
                && body.from.y + body.height > goal[1]
                && goal[1] + BODY_HEIGHT > body.from.y
                && (body.from.x - goal[0]).hypot(body.from.z - goal[2])
                    < body.radius + RADIUS + 0.02
        });
        if occupied || !supported_stance(&arena, goal) {
            self.redactor_approach = None;
            return None;
        }
        if self.phase != EnemyPhase::Moving {
            self.enter(EnemyPhase::Moving, tick, 0);
        }
        Some(BotIntent {
            action: Action {
                forward: true,
                yaw: Some((goal[2] - feet[2]).atan2(goal[0] - feet[0])),
                ..Action::default()
            },
            goal: Some(NavigationGoal {
                feet: goal,
                combat: true,
            }),
        })
    }
}

fn supported_stance(arena: &Arena, feet: [f32; 3]) -> bool {
    let limit = arena.half - RADIUS;
    feet[0].abs() <= limit
        && feet[2].abs() <= limit
        && !arena.blocked_body_at(feet[0], feet[2], feet[1], feet[1] + STEP_UP)
        && [-RADIUS, RADIUS].into_iter().all(|dx| {
            [-RADIUS, RADIUS].into_iter().all(|dz| {
                (arena.support_height(feet[0] + dx, feet[2] + dz, feet[1] + 0.01) - feet[1]).abs()
                    <= 0.02
            })
        })
}

fn supported_approach(arena: &Arena, from: [f32; 3], to: [f32; 3]) -> bool {
    supported_stance(arena, to)
        && (0..=12).all(|index| {
            let t = index as f32 / 12.0;
            supported_stance(
                arena,
                [
                    from[0] + (to[0] - from[0]) * t,
                    from[1],
                    from[2] + (to[2] - from[2]) * t,
                ],
            )
        })
        && !arena.blocked_body_motion(
            (from[0], from[2]),
            (to[0], to[2]),
            from[1],
            from[1] + STEP_UP,
            true,
        )
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::movement::Solid;

    #[test]
    fn redactor_approach_clearance_refuses_rack_headroom_edges_and_unsupported_corner() {
        let mut arena = Arena {
            half: 8.0,
            solids: vec![],
        };
        let from = [0.0, 0.0, 0.0];
        let to = [4.0, 0.0, 0.0];
        assert!(supported_approach(&arena, from, to));
        assert!(!supported_stance(&arena, [7.51, 0.0, 0.0]));
        arena.solids.push(Solid::from_center(2.0, 0.0, 0.1, 1.0));
        assert!(
            !supported_approach(&arena, from, to),
            "clear endpoints cannot cross a rack"
        );
        arena.solids.clear();
        arena
            .solids
            .push(Solid::from_center_volume(4.0, 0.0, 1.0, 1.0, 1.7, 2.0));
        assert!(
            !supported_stance(&arena, to),
            "ordinary headroom is mandatory"
        );
        arena.solids.clear();
        arena
            .solids
            .push(Solid::from_center_top(0.0, 0.0, 3.0, 0.3, 2.0));
        assert!(
            !supported_stance(&arena, [0.0, 2.0, 0.0]),
            "a supported center cannot bridge the edge"
        );
        assert!(!supported_approach(
            &arena,
            [0.0, 2.0, 0.0],
            [4.0, 2.0, 0.0]
        ));
    }

    #[test]
    fn redactor_approach_holds_visible_goal_once_then_retires_without_new_search() {
        use crate::maps::AuthoredMap;
        use crate::protocol::Role;
        let doc = serde_json::json!({"version":1,"map_id":1113,"name":"Redactor held approach",
            "half_extent":12,"ground":"concrete","equipment":"discovery","solids":[],
            "spawns":[{"id":"entry","feet":[4,0,0],"yaw":0}],
            "landmarks":[{"id":"return","feet":[-4,0,0]}]});
        let map = AuthoredMap::read(serde_json::to_vec(&doc).unwrap().as_slice()).unwrap();
        let mut state = GameState::with_authored_map(map);
        let enemy_id = Uuid::from_u128(1113);
        let target_id = Uuid::from_u128(1114);
        state.add_player(enemy_id, "Guard".into(), Role::Human);
        state.add_player(target_id, "Walker".into(), Role::Human);
        state.players[0].x = -1.0;
        state.players[0].z = 0.0;
        state.players[1].x = 4.0;
        state.players[1].z = 0.0;
        let mut guard = EnemyController::new(
            enemy_id,
            EnemyKind::Redactor,
            [-1.0, 0.0, 0.0],
            0.0,
            0,
            false,
        );
        let target = &state.snapshot().players[1];
        let first = guard
            .redactor_approach(&state, Some(target), [-1.0, 0.0, 0.0], 1)
            .unwrap();
        let point = first.goal.unwrap().feet;
        assert!(point[2].abs() > 1.0);
        let mut moved_target = target.clone();
        moved_target.z = 0.4;
        let held = guard
            .redactor_approach(&state, Some(&moved_target), [-1.0, 0.0, 0.0], 40)
            .unwrap();
        assert_eq!(
            held.goal.unwrap().feet,
            point,
            "visible target motion must not rewrite a held goal"
        );
        assert!(guard
            .redactor_approach(&state, Some(target), [-1.0, 0.0, 0.0], 61)
            .is_none());
        assert!(guard
            .redactor_approach(&state, Some(target), [-1.0, 0.0, 0.0], 62)
            .is_none());
        assert!(guard
            .redactor_approach(&state, None, [-1.0, 0.0, 0.0], 63)
            .is_none());
        assert!(guard
            .redactor_approach(&state, Some(target), [-1.0, 0.0, 0.0], 64)
            .is_some());
        guard.hit(65, false);
        assert!(guard.redactor_approach.is_none());
        assert!(!guard.redactor_approached);
    }
}
