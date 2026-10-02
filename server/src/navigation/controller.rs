//! Route memory and discrete movement intent, shared by local controllers.

use super::{Navigation, RouteStatus, SEARCH_LIMIT};
use crate::combat::{line_of_sight, FIGHTER_HEIGHT};
use crate::movement::{Solid, EYE_HEIGHT, STEP_UP};
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
    avoidance_side: i8,
    avoidance_until: u64,
}

impl Navigation {
    pub(crate) fn planning_arena(&self) -> &crate::movement::Arena {
        &self.arena
    }
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
        self.steer_snapshot_with_visibility(
            world,
            id,
            snapshot,
            action,
            allow_search,
            &world.arena.solids,
        )
    }

    /// Keep immutable route topology while checking combat against live cover.
    // The same steering pass needs its existing search budget and physical LOS
    // inputs together; a second controller would duplicate route memory.
    #[allow(clippy::too_many_arguments)]
    pub fn steer_snapshot_with_visibility(
        &mut self,
        world: &Navigation,
        id: Uuid,
        snapshot: &Snapshot,
        action: Action,
        allow_search: bool,
        visibility: &[Solid],
    ) -> Action {
        let steered = self.route_snapshot_with_visibility(
            world,
            id,
            snapshot,
            action,
            allow_search,
            visibility,
        );
        let bodies = Self::snapshot_bodies(snapshot);
        let arena = crate::movement::Arena {
            half: world.arena.half,
            solids: visibility.to_vec(),
        };
        self.avoid_bodies(&arena, id, &bodies, steered, snapshot.tick)
    }

    pub(crate) fn snapshot_bodies(
        snapshot: &Snapshot,
    ) -> Vec<crate::movement::contact::ContactBody> {
        snapshot
            .players
            .iter()
            .filter(|p| p.collidable && p.hp > 0)
            .map(|p| {
                let from = crate::movement::MoveState {
                    x: p.x,
                    y: p.y - PLAYER_FLOOR_Y,
                    z: p.z,
                    vx: 0.0,
                    vz: 0.0,
                    vy: 0.0,
                    yaw: p.yaw,
                };
                crate::movement::contact::ContactBody {
                    key: p.id.to_string(),
                    from,
                    proposed: from,
                    height: crate::combat::target_height(p.campaign),
                    radius: crate::movement::RADIUS,
                    jump: false,
                }
            })
            .collect()
    }

    /// Session supplies its one authoritative body scene after resolving routes;
    /// external readers use the snapshot wrapper for the same local avoidance.
    #[allow(clippy::too_many_arguments)]
    pub fn route_snapshot_with_visibility(
        &mut self,
        world: &Navigation,
        id: Uuid,
        snapshot: &Snapshot,
        action: Action,
        allow_search: bool,
        visibility: &[Solid],
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
        let goal = if let Some(target) = aim.player_id.and_then(|id| {
            snapshot
                .players
                .iter()
                .find(|player| player.id == id && me.is_hostile_to(player))
        }) {
            if crate::combat::is_notary(target.campaign) && !action.forward {
                let origin = [from[0], from[1] + EYE_HEIGHT, from[2]];
                let centre = [
                    target.x,
                    target.y - PLAYER_FLOOR_Y + crate::combat::target_height(target.campaign) * 0.5,
                    target.z,
                ];
                if line_of_sight(origin, centre, visibility) {
                    self.clear();
                    return action;
                }
            }
            NavigationGoal {
                feet: [
                    target.x,
                    target.y - PLAYER_FLOOR_Y
                        + if crate::combat::is_notary(target.campaign) {
                            (crate::combat::target_height(target.campaign) - FIGHTER_HEIGHT) * 0.5
                        } else {
                            0.0
                        },
                    target.z,
                ],
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
        self.steer_with_visibility(
            world,
            from,
            goal,
            action,
            snapshot.tick,
            allow_search,
            visibility,
        )
    }

    /// Local ordinary input around occupied routes. Topology/search memory stays
    /// unchanged; every candidate uses map integration and the shared contact
    /// solver with immutable current bodies, including stationary civilians.
    pub fn avoid_bodies(
        &mut self,
        arena: &crate::movement::Arena,
        id: Uuid,
        bodies: &[crate::movement::contact::ContactBody],
        mut action: Action,
        tick: u64,
    ) -> Action {
        let key = id.to_string();
        let Some(me) = bodies.iter().find(|b| b.key == key) else {
            return action;
        };
        // Cached grid waypoints can lie inside an occupied body. Keep the final
        // goal, but advance intermediate occupied points within this local
        // neighbourhood so a successful pass does not turn back into its peer.
        let mut advanced = false;
        while self.points.len() > 1 {
            let point = *self.points.front().unwrap();
            let occupied = bodies.iter().any(|b| {
                b.key != key
                    && point[1] + me.height > b.from.y
                    && b.from.y + b.height > point[1]
                    && (point[0] - b.from.x).hypot(point[2] - b.from.z) < me.radius + b.radius + 0.2
            });
            if !occupied || (point[0] - me.from.x).hypot(point[2] - me.from.z) > 2.0 {
                break;
            }
            self.points.pop_front();
            advanced = true;
        }
        if advanced && action.look_at.is_none() {
            if let Some(point) = self.points.front() {
                action.yaw = Some((point[2] - me.from.z).atan2(point[0] - me.from.x));
            }
        }
        if !(action.forward || action.back || action.left || action.right) || action.jump {
            return action;
        }
        let yaw = action.yaw.unwrap_or(me.from.yaw);
        let wanted = crate::movement::live_step_with_height(
            me.from,
            &crate::movement::MoveInput {
                forward: action.forward,
                back: action.back,
                left: action.left,
                right: action.right,
                jump: false,
                yaw,
                speed_scale: 1.0,
            },
            crate::movement::TOP_SPEED,
            0.05,
            arena,
            me.height,
        );
        let dx = wanted.x - me.from.x;
        let dz = wanted.z - me.from.z;
        let length = dx.hypot(dz);
        if length < 0.01 {
            return action;
        }
        let neighbours: Vec<_> = bodies
            .iter()
            .filter(|b| {
                b.key != key
                    && (b.from.x - me.from.x).hypot(b.from.z - me.from.z) < 2.5
                    && b.from.y + b.height > me.from.y
                    && me.from.y + me.height > b.from.y
            })
            .cloned()
            .collect();
        if neighbours.is_empty() {
            return action;
        }
        let grounded = me.from.vy.abs() < 0.001
            && (me.from.y - arena.support_height(me.from.x, me.from.z, me.from.y)).abs() < 0.001;
        let forecast = |candidate: &Action| -> Option<[f32; 2]> {
            let mut pose = me.from;
            for _ in 0..6 {
                let proposed = crate::movement::live_step_with_height(
                    pose,
                    &crate::movement::MoveInput {
                        forward: candidate.forward,
                        back: candidate.back,
                        left: candidate.left,
                        right: candidate.right,
                        jump: false,
                        yaw,
                        speed_scale: 1.0,
                    },
                    crate::movement::TOP_SPEED,
                    0.05,
                    arena,
                    me.height,
                );
                if (proposed.y - pose.y).abs() > STEP_UP + 0.001 {
                    return None;
                }
                let mut scene = neighbours.clone();
                scene.push(crate::movement::contact::ContactBody {
                    key: key.clone(),
                    from: pose,
                    proposed,
                    height: me.height,
                    radius: me.radius,
                    jump: false,
                });
                let moved = crate::movement::contact::resolve(&scene, 0.05, arena)
                    .pop()
                    .unwrap_or(pose);
                if (moved.y - pose.y).abs() > STEP_UP + 0.001 || (grounded && moved.vy < -0.001) {
                    return None;
                }
                pose = moved;
            }
            Some([pose.x - me.from.x, pose.z - me.from.z])
        };
        let Some(original) = forecast(&action) else {
            // Preserve a deliberate route drop; alternative crowd passing never
            // introduces a new unsupported step on a grounded actor's behalf.
            return action;
        };
        let progress = (original[0] * dx + original[1] * dz) / length;
        if progress >= length * 5.0 {
            self.avoidance_until = 0;
            return action;
        }
        // Preserve a chosen side across successive contact ticks. Both facing
        // actors initially prefer their own right, giving a consistent pass.
        let side = if tick < self.avoidance_until {
            self.avoidance_side
        } else {
            1
        };
        let mut best = action.clone();
        let mut best_score = progress;
        for (forward, back, left, right) in [
            (true, false, false, true),
            (false, false, false, true),
            (true, false, true, false),
            (false, false, true, false),
            (false, true, false, true),
            (false, true, true, false),
            (false, true, false, false),
        ] {
            let mut candidate = action.clone();
            candidate.forward = forward;
            candidate.back = back;
            candidate.left = left;
            candidate.right = right;
            let Some(accepted) = forecast(&candidate) else {
                continue;
            };
            let along = (accepted[0] * dx + accepted[1] * dz) / length;
            let lateral = (accepted[0] * -dz + accepted[1] * dx) / length;
            let preferred = if (right && side > 0) || (left && side < 0) {
                0.025
            } else {
                0.0
            };
            let score = along + lateral.abs() * 0.35 + preferred;
            if score > best_score + 0.01 && accepted[0].hypot(accepted[1]) > 0.08 {
                best_score = score;
                best = candidate;
            }
        }
        if best.left != action.left
            || best.right != action.right
            || best.forward != action.forward
            || best.back != action.back
        {
            self.avoidance_side = if best.right { 1 } else { -1 };
            self.avoidance_until = tick.saturating_add(12);
        }
        best
    }

    pub fn steer(
        &mut self,
        world: &Navigation,
        from: [f32; 3],
        goal: NavigationGoal,
        action: Action,
        tick: u64,
        allow_search: bool,
    ) -> Action {
        self.steer_with_visibility(
            world,
            from,
            goal,
            action,
            tick,
            allow_search,
            &world.arena.solids,
        )
    }

    // Preserve the existing steering inputs while separating physical cover
    // from cached topology; this is the sole shared movement controller.
    #[allow(clippy::too_many_arguments)]
    pub fn steer_with_visibility(
        &mut self,
        world: &Navigation,
        from: [f32; 3],
        goal: NavigationGoal,
        mut action: Action,
        tick: u64,
        allow_search: bool,
        visibility: &[Solid],
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
                visibility,
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

    #[test]
    fn occupied_route_uses_ordinary_sidestep_without_crossing_body_or_wall() {
        for reversed in [false, true] {
            let document = serde_json::json!({"version":1,"map_id":1911,"name":"Crowd route test","half_extent":12,
            "ground":"concrete","solids":[{"id":"lane_wall","min":[-10,0,-2],"max":[10,4,-1.6],"surface":"service_steel"}],
            "spawns":[{"id":"west","feet":[-3,0,0],"yaw":0},{"id":"centre","feet":[0,0,0],"yaw":0}],
            "landmarks":[{"id":"east","feet":[5,0,0]}]});
            let map =
                crate::maps::AuthoredMap::read(serde_json::to_vec(&document).unwrap().as_slice())
                    .unwrap();
            let mut session = crate::session::GameSession::with_authored_map(map);
            let mover = Uuid::from_u128(if reversed { 2 } else { 1 });
            let blocker = Uuid::from_u128(if reversed { 1 } else { 2 });
            session
                .state
                .add_player(mover, "route mover".into(), Role::Agent);
            session
                .state
                .add_player(blocker, "stationary blocker".into(), Role::Human);
            for p in &mut session.state.players {
                p.x = if p.id == mover { -3.0 } else { 0.0 };
                p.z = 0.0;
                p.y = PLAYER_FLOOR_Y;
            }
            let mut navigator = Navigator::default();
            let mut lateral = 0.0_f32;
            let mut reached = false;
            for _ in 0..180 {
                let snapshot = session.state.snapshot();
                let world = session.state.map.navigation();
                let action = navigator.steer_snapshot(
                    world,
                    mover,
                    &snapshot,
                    Action {
                        forward: true,
                        look_at: Some(LookAt {
                            player_id: None,
                            x: Some(5.0),
                            y: Some(EYE_HEIGHT),
                            z: Some(0.0),
                        }),
                        ..Default::default()
                    },
                );
                session.state.set_action(mover, action);
                session.tick_messages(0.05);
                let me = session
                    .state
                    .players
                    .iter()
                    .find(|p| p.id == mover)
                    .unwrap();
                let peer = session
                    .state
                    .players
                    .iter()
                    .find(|p| p.id == blocker)
                    .unwrap();
                assert!((me.x - peer.x).hypot(me.z - peer.z) >= 0.9999);
                assert!(!session.state.current_arena().blocked_body_at(
                    me.x,
                    me.z,
                    me.y - PLAYER_FLOOR_Y,
                    me.y - PLAYER_FLOOR_Y
                ));
                lateral = lateral.max(me.z.abs());
                if (me.x - 5.0).hypot(me.z) < 0.5 {
                    assert!(lateral > 0.8, "passing requires genuine lateral progress");
                    assert_eq!([peer.x, peer.z], [0.0, 0.0]);
                    reached = true;
                    break;
                }
            }
            assert!(
                reached,
                "ordinary controller failed to pass occupied route: {:?}",
                session.state.snapshot().players
            );
        }
    }

    fn crowd_body(
        id: u128,
        x: f32,
        y: f32,
        z: f32,
        yaw: f32,
    ) -> crate::movement::contact::ContactBody {
        let from = crate::movement::MoveState {
            x,
            y,
            z,
            yaw,
            vx: 0.0,
            vy: 0.0,
            vz: 0.0,
        };
        crate::movement::contact::ContactBody {
            key: Uuid::from_u128(id).to_string(),
            from,
            proposed: from,
            height: FIGHTER_HEIGHT,
            radius: crate::movement::RADIUS,
            jump: false,
        }
    }

    #[test]
    fn crowd_pass_preserves_support_and_intent_on_a_raised_lane() {
        let arena = Arena {
            half: 12.0,
            solids: vec![Solid {
                min_x: -3.0,
                max_x: 3.0,
                min_z: -0.6,
                max_z: 2.0,
                bottom: 0.0,
                top: 3.0,
            }],
        };
        let mut mover = crowd_body(1, -1.2, 3.0, 0.0, 0.0);
        let peer = crowd_body(2, 0.0, 3.0, 0.0, 0.0);
        let mut nav = Navigator::default();
        let intent = Action {
            forward: true,
            fire: true,
            pitch: Some(0.2),
            look_at: Some(LookAt {
                player_id: Some(Uuid::from_u128(2)),
                x: None,
                y: None,
                z: None,
            }),
            ..Default::default()
        };
        let untouched = nav.avoid_bodies(
            &arena,
            Uuid::from_u128(1),
            &[mover.clone()],
            intent.clone(),
            0,
        );
        assert_eq!(
            serde_json::to_value(untouched).unwrap(),
            serde_json::to_value(&intent).unwrap(),
            "unoccupied intent is unchanged"
        );
        let mut lateral = 0.0_f32;
        for tick in 0..12 {
            let action = nav.avoid_bodies(
                &arena,
                Uuid::from_u128(1),
                &[mover.clone(), peer.clone()],
                intent.clone(),
                tick,
            );
            assert_eq!(action.fire, intent.fire);
            assert_eq!(action.pitch, intent.pitch);
            assert_eq!(action.look_at, intent.look_at);
            mover.proposed = crate::movement::live_step_with_height(
                mover.from,
                &crate::movement::MoveInput {
                    forward: action.forward,
                    back: action.back,
                    left: action.left,
                    right: action.right,
                    yaw: 0.0,
                    jump: false,
                    speed_scale: 1.0,
                },
                crate::movement::TOP_SPEED,
                0.05,
                &arena,
                mover.height,
            );
            let accepted =
                crate::movement::contact::resolve(&[mover.clone(), peer.clone()], 0.05, &arena)[0];
            assert_eq!(accepted.y, 3.0, "passing must retain real deck support");
            assert_eq!(accepted.vy, 0.0);
            assert!((accepted.x - peer.from.x).hypot(accepted.z - peer.from.z) >= 0.9999);
            mover.from = accepted;
            mover.proposed = accepted;
            lateral = lateral.max(accepted.z);
        }
        assert!(
            lateral > 0.8,
            "safe supported side must make ordinary progress"
        );
    }

    #[test]
    fn facing_crowd_passes_with_either_stable_body_order() {
        let arena = Arena {
            half: 12.0,
            solids: vec![],
        };
        for reverse in [false, true] {
            let mut bodies = vec![
                crowd_body(if reverse { 2 } else { 1 }, -2.0, 0.0, 0.0, 0.0),
                crowd_body(
                    if reverse { 1 } else { 2 },
                    2.0,
                    0.0,
                    0.0,
                    std::f32::consts::PI,
                ),
            ];
            let mut drivers = [Navigator::default(), Navigator::default()];
            for tick in 0..48 {
                let scene = bodies.clone();
                for (i, body) in bodies.iter_mut().enumerate() {
                    let id = Uuid::parse_str(&body.key).unwrap();
                    let action = drivers[i].avoid_bodies(
                        &arena,
                        id,
                        &scene,
                        Action {
                            forward: true,
                            yaw: Some(body.from.yaw),
                            ..Default::default()
                        },
                        tick,
                    );
                    body.proposed = crate::movement::live_step_with_height(
                        body.from,
                        &crate::movement::MoveInput {
                            forward: action.forward,
                            back: action.back,
                            left: action.left,
                            right: action.right,
                            jump: false,
                            yaw: body.from.yaw,
                            speed_scale: 1.0,
                        },
                        crate::movement::TOP_SPEED,
                        0.05,
                        &arena,
                        body.height,
                    );
                }
                let moved = crate::movement::contact::resolve(&bodies, 0.05, &arena);
                assert!((moved[0].x - moved[1].x).hypot(moved[0].z - moved[1].z) >= 0.9999);
                for (body, pose) in bodies.iter_mut().zip(moved) {
                    body.from = pose;
                    body.proposed = pose;
                }
            }
            assert!(
                bodies[0].from.x > 2.0 && bodies[1].from.x < -2.0,
                "both ordinary actors must pass instead of queueing: {bodies:?}"
            );
        }
    }

    #[test]
    fn nearby_bodies_do_not_replace_a_supported_stair_route() {
        let arena = Arena {
            half: 12.0,
            solids: vec![
                Solid {
                    min_x: -2.0,
                    max_x: 0.5,
                    min_z: -2.0,
                    max_z: 2.0,
                    bottom: 0.0,
                    top: 0.5,
                },
                Solid {
                    min_x: 0.5,
                    max_x: 1.5,
                    min_z: -2.0,
                    max_z: 2.0,
                    bottom: 0.0,
                    top: 1.0,
                },
                Solid {
                    min_x: 1.5,
                    max_x: 3.5,
                    min_z: -2.0,
                    max_z: 2.0,
                    bottom: 0.0,
                    top: 1.5,
                },
            ],
        };
        let mut me = crowd_body(1, 0.0, 0.5, 0.0, 0.0);
        let peer = crowd_body(2, -1.5, 0.5, 0.0, 0.0);
        let intent = Action {
            forward: true,
            yaw: Some(0.0),
            ..Default::default()
        };
        let mut nav = Navigator::default();
        for tick in 0..10 {
            let action = nav.avoid_bodies(
                &arena,
                Uuid::from_u128(1),
                &[me.clone(), peer.clone()],
                intent.clone(),
                tick,
            );
            assert!(action.forward && !action.back && !action.left && !action.right);
            me.from = crate::movement::live_step_with_height(
                me.from,
                &crate::movement::MoveInput {
                    forward: true,
                    yaw: 0.0,
                    speed_scale: 1.0,
                    ..Default::default()
                },
                crate::movement::TOP_SPEED,
                0.05,
                &arena,
                me.height,
            );
            me.proposed = me.from;
            assert_eq!(me.from.vy, 0.0);
        }
        assert!(
            me.from.x >= 2.0 && me.from.y == 1.5,
            "ordinary stairs remain usable: {me:?}"
        );
    }
}
