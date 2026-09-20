//! Route memory and discrete movement intent, shared by local controllers.

use super::{Navigation, RouteStatus, SEARCH_LIMIT};
use crate::combat::{line_of_sight, FIGHTER_HEIGHT};
use crate::movement::{EYE_HEIGHT, STEP_UP};
use crate::protocol::{Action, Snapshot};
use crate::sim::PLAYER_FLOOR_Y;
use std::collections::VecDeque;
use uuid::Uuid;

#[derive(Debug, Clone, Copy)]
pub struct NavigationGoal {
    pub feet: [f32; 3],
    pub combat: bool,
}

#[derive(Debug, Clone, Default)]
pub struct Navigator {
    points: VecDeque<[f32; 3]>,
    destination: Option<[f32; 3]>,
    last_position: Option<[f32; 3]>,
    last_tick: u64,
    next_search_tick: u64,
    stalled_ticks: u32,
}

impl Navigator {
    pub fn clear(&mut self) {
        *self = Self::default();
    }

    /// Resolve a wire controller's target without a second map or aim model.
    pub fn steer_snapshot(
        &mut self,
        world: &Navigation,
        id: Uuid,
        snapshot: &Snapshot,
        action: Action,
    ) -> Action {
        self.steer_snapshot_with_budget(world, id, snapshot, action, true)
    }

    pub fn steer_snapshot_with_budget(
        &mut self,
        world: &Navigation,
        id: Uuid,
        snapshot: &Snapshot,
        action: Action,
        allow_search: bool,
    ) -> Action {
        let Some(me) = snapshot.players.iter().find(|player| player.id == id) else {
            self.clear();
            return action;
        };
        let Some(aim) = &action.look_at else {
            self.points.clear();
            return action;
        };
        let from = [me.x, me.y - PLAYER_FLOOR_Y, me.z];
        let goal = if let Some(target) = aim
            .player_id
            .and_then(|id| snapshot.players.iter().find(|player| player.id == id))
        {
            NavigationGoal {
                feet: [target.x, target.y - PLAYER_FLOOR_Y, target.z],
                combat: true,
            }
        } else if let (Some(x), Some(z)) = (aim.x, aim.z) {
            let Some(floor) = world.coordinate_floor([x, aim.y.unwrap_or(from[1] + EYE_HEIGHT), z])
            else {
                self.points.clear();
                return Action::default();
            };
            NavigationGoal {
                feet: [x, floor, z],
                combat: false,
            }
        } else {
            return action;
        };
        self.steer(world, from, goal, action, snapshot.tick, allow_search)
    }

    pub fn steer(
        &mut self,
        world: &Navigation,
        from: [f32; 3],
        goal: NavigationGoal,
        mut action: Action,
        tick: u64,
        allow_search: bool,
    ) -> Action {
        if tick < self.last_tick
            || self
                .last_position
                .is_some_and(|last| distance(last, from) > 8.0)
        {
            self.clear();
        }
        if tick > self.last_tick {
            self.stalled_ticks = if self
                .last_position
                .is_some_and(|last| distance(last, from) < 0.02)
                && !self.points.is_empty()
            {
                self.stalled_ticks.saturating_add(1)
            } else {
                0
            };
        }
        self.last_position = Some(from);
        self.last_tick = tick;
        let visible = goal.combat
            && line_of_sight(
                [from[0], from[1] + EYE_HEIGHT, from[2]],
                [
                    goal.feet[0],
                    goal.feet[1] + FIGHTER_HEIGHT * 0.5,
                    goal.feet[2],
                ],
                &world.arena.solids,
            );
        action.fire &= visible;
        if visible && !action.forward {
            self.points.clear();
            return action;
        }
        let Some(floor) = world.floor_below(goal.feet) else {
            self.points.clear();
            return action;
        };
        let destination = [goal.feet[0], floor, goal.feet[2]];
        if visible
            && !self.points.is_empty()
            && tick.is_multiple_of(4)
            && distance(from, destination) <= 32.0
            && world.walkable(from, destination)
        {
            self.points.clear();
            return action;
        }
        if self.points.is_empty() && visible {
            // Stay with the personality controller while its immediate approach
            // is walkable. Only route when cover or a ledge calls for a detour.
            let length = distance(from, destination);
            let fraction = (0.75 / length.max(0.001)).min(1.0);
            let mut probe = [
                from[0] + (destination[0] - from[0]) * fraction,
                from[1],
                from[2] + (destination[2] - from[2]) * fraction,
            ];
            probe[1] = world.floor_below(probe).unwrap_or(from[1]);
            if world.walkable(from, probe) {
                return action;
            }
        }
        let changed = self.destination.is_none_or(|old| {
            distance(old, destination) > 4.0 || (old[1] - destination[1]).abs() > STEP_UP
        });
        let needs_search = self.points.is_empty() || changed || self.stalled_ticks >= 10;
        if needs_search && allow_search && tick >= self.next_search_tick {
            self.next_search_tick = tick.saturating_add(20);
            self.destination = Some(destination);
            self.stalled_ticks = 0;
            let route = world.route(from, destination, SEARCH_LIMIT);
            self.points = if matches!(
                route.status,
                RouteStatus::Complete | RouteStatus::BudgetExhausted
            ) {
                route.points.into()
            } else {
                VecDeque::new()
            };
        }
        while let Some(&point) = self.points.front() {
            let near = distance(from, point) < 0.3 && (from[1] - point[1]).abs() < 0.1;
            let can_continue = self
                .points
                .get(1)
                .is_none_or(|next| world.walkable(from, *next));
            if !near || !can_continue {
                break;
            }
            self.points.pop_front();
        }
        if let Some(point) = self.points.front() {
            action.forward = true;
            action.back = false;
            action.left = false;
            action.right = false;
            action.turn_left = false;
            action.turn_right = false;
            action.look_at = None;
            action.yaw = Some((point[2] - from[2]).atan2(point[0] - from[0]));
            action.fire = false;
        }
        action
    }
}

fn distance(a: [f32; 3], b: [f32; 3]) -> f32 {
    (a[0] - b[0]).hypot(a[2] - b[2])
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::movement::{Arena, Solid};
    use crate::protocol::{LookAt, Role};
    use crate::sim::GameState;

    fn world() -> Navigation {
        Navigation::new(Arena {
            half: 10.0,
            solids: vec![Solid::from_center(0.0, 0.0, 0.1, 2.0)],
        })
        .unwrap()
    }

    #[test]
    fn search_permission_cadence_and_session_reset_are_enforced() {
        let world = world();
        let mut driver = Navigator::default();
        let from = [-4.0, 0.0, 0.0];
        let goal = NavigationGoal {
            feet: [4.0, 0.0, 0.0],
            combat: true,
        };
        let action = Action {
            forward: true,
            fire: true,
            ..Default::default()
        };
        let waiting = driver.steer(&world, from, goal, action.clone(), 1, false);
        assert!(
            !waiting.fire,
            "never fire into known cover while awaiting a route"
        );
        assert!(driver.points.is_empty());
        assert_eq!(driver.next_search_tick, 0);
        let walking = driver.steer(&world, from, goal, action.clone(), 2, true);
        assert!(!walking.fire && walking.forward && walking.yaw.is_some());
        assert!(!driver.points.is_empty());
        assert_eq!(driver.next_search_tick, 22);
        for tick in 3..22 {
            driver.steer(&world, from, goal, action.clone(), tick, true);
            assert_eq!(
                driver.next_search_tick, 22,
                "no repeated searches inside the cooldown"
            );
        }
        driver.steer(&world, from, goal, action.clone(), 22, true);
        assert_eq!(driver.next_search_tick, 42);
        driver.steer(&world, from, goal, action, 1, false);
        assert!(
            driver.points.is_empty(),
            "restarted ticks discard previous-session routes"
        );
        assert_eq!(driver.next_search_tick, 0);
        driver.clear();
        assert!(driver.destination.is_none() && driver.last_position.is_none());
    }

    #[test]
    fn snapshot_target_cover_death_and_pickup_paths_use_the_same_controller() {
        let world = world();
        let mut state = GameState::new();
        let me = Uuid::new_v4();
        let enemy = Uuid::new_v4();
        state.add_player(me, "Meat Proxy".into(), Role::Agent);
        state.add_player(enemy, "Target".into(), Role::Agent);
        state.players[0].x = -4.0;
        state.players[0].z = 0.0;
        state.players[1].x = 4.0;
        state.players[1].z = 0.0;
        let mut snapshot = state.snapshot();
        snapshot.tick = 1;
        let mut driver = Navigator::default();
        let action = Action {
            look_at: Some(LookAt {
                player_id: Some(enemy),
                x: None,
                y: None,
                z: None,
            }),
            fire: true,
            forward: true,
            ..Default::default()
        };
        let routed = driver.steer_snapshot(&world, me, &snapshot, action.clone());
        assert!(!routed.fire && routed.look_at.is_none() && routed.yaw.is_some());
        assert!(!driver.points.is_empty());
        let open = Navigation::new(Arena {
            half: 10.0,
            solids: vec![],
        })
        .unwrap();
        driver.clear();
        let clear = driver.steer_snapshot(&open, me, &snapshot, action);
        assert!(clear.fire && clear.look_at.as_ref().unwrap().player_id == Some(enemy));
        snapshot.tick = 30;
        let pickup = Action {
            look_at: Some(LookAt {
                player_id: None,
                x: Some(4.0),
                y: None,
                z: Some(0.0),
            }),
            forward: true,
            ..Default::default()
        };
        driver.steer_snapshot(&world, me, &snapshot, pickup);
        assert!(!driver.points.is_empty());
        snapshot.players.retain(|player| player.id != me);
        driver.steer_snapshot(&world, me, &snapshot, Action::default());
        assert!(driver.points.is_empty() && driver.destination.is_none());
    }
}
