//! Bounded walking routes over the authoritative heightfield.
//!
//! Graph points are feet positions. Routes are advice to a controller; only
//! normal movement actions can move a fighter or decide collision outcomes.

use crate::movement::{Arena, RADIUS, STEP_UP};
use std::cmp::Reverse;
use std::collections::BinaryHeap;
use std::sync::{Arc, Mutex, OnceLock, Weak};

mod controller;
pub use controller::{NavigationGoal, Navigator};

const CELL: f32 = 1.0;
const MAX_HALF: f32 = 256.0;
const MAX_SOLIDS: usize = 2048;
pub const SEARCH_LIMIT: usize = 16_384;
const DIRECTIONS: [(i32, i32); 8] = [
    (1, 0),
    (0, 1),
    (-1, 0),
    (0, -1),
    (2, 0),
    (0, 2),
    (-2, 0),
    (0, -2),
];

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RouteStatus {
    Complete,
    Unreachable,
    BudgetExhausted,
    InvalidPoint,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Route {
    pub status: RouteStatus,
    pub points: Vec<[f32; 3]>,
    pub expanded: usize,
}

/// Immutable topology, shared by controllers. Construction is outside the tick.
#[derive(Debug)]
pub struct Navigation {
    arena: Arena,
    span: i32,
    width: usize,
    heights: Vec<f32>,
    edges: Vec<u8>,
}

impl Navigation {
    /// Reuse identical immutable geometry across local sessions/controllers.
    /// Weak entries retain no unused maps; the index itself is capped. Serialize
    /// construction so simultaneous joins cannot multiply topology work.
    pub fn shared(arena: Arena) -> Result<Arc<Self>, &'static str> {
        static CACHE: OnceLock<Mutex<Vec<Weak<Navigation>>>> = OnceLock::new();
        let mut cache = CACHE
            .get_or_init(Mutex::default)
            .lock()
            .map_err(|_| "navigation cache unavailable")?;
        cache.retain(|entry| entry.strong_count() > 0);
        for entry in cache.iter().filter_map(Weak::upgrade) {
            if entry.arena == arena {
                return Ok(entry);
            }
        }
        let navigation = Arc::new(Self::new(arena)?);
        if cache.len() == 8 {
            cache.remove(0);
        }
        cache.push(Arc::downgrade(&navigation));
        Ok(navigation)
    }

    pub fn new(arena: Arena) -> Result<Self, &'static str> {
        if !arena.half.is_finite() || !(2.0..=MAX_HALF).contains(&arena.half) {
            return Err("navigation extent must be finite and between 2 and 256 metres");
        }
        if arena.solids.len() > MAX_SOLIDS {
            return Err("navigation solid limit exceeded");
        }
        for solid in &arena.solids {
            if [
                solid.min_x,
                solid.max_x,
                solid.min_z,
                solid.max_z,
                solid.top,
            ]
            .iter()
            .any(|v| !v.is_finite() || v.abs() > MAX_HALF * 2.0)
                || solid.min_x >= solid.max_x
                || solid.min_z >= solid.max_z
                || solid.top <= 0.0
            {
                return Err("invalid navigation solid");
            }
        }
        let span = (arena.half / CELL).floor() as i32;
        let width = (span * 2) as usize;
        let count = width * width;
        if count.saturating_mul(arena.solids.len()) > 64_000_000 {
            return Err("navigation construction work limit exceeded");
        }
        let mut navigation = Self {
            arena,
            span,
            width,
            heights: vec![f32::NAN; count],
            edges: vec![0; count],
        };
        for index in 0..count {
            let [x, _, z] = navigation.point(index);
            let floor = navigation.arena.support_height(x, z, f32::MAX);
            // Leave room for one 20 Hz movement step (0.25 m) at a waypoint.
            // Exact ledge corners are legal points but unsafe steering targets.
            let supported = [-0.3, 0.3].iter().all(|dx| {
                [-0.3, 0.3]
                    .iter()
                    .all(|dz| navigation.arena.support_height(x + dx, z + dz, f32::MAX) >= floor)
            });
            if supported && !navigation.arena.blocked_at(x, z, floor + STEP_UP) {
                navigation.heights[index] = floor;
            }
        }
        // At one-metre spacing, radius inflation makes any intervening flat
        // barrier cover at least one endpoint. Height transitions additionally
        // walk the segment to catch a taller riser before its supporting tread.
        const { assert!(CELL <= RADIUS * 2.0) };
        for index in 0..count {
            let from = navigation.point(index);
            if !from[1].is_finite() {
                continue;
            }
            for (direction, (dx, dz)) in DIRECTIONS.iter().enumerate() {
                // A descending edge may cross one cell that cannot support a
                // grounded body beside the ledge. Sweep to the landing beyond
                // it; ordinary flat ground needs no redundant long edges.
                if direction >= 4 {
                    let middle = navigation.neighbour(index, dx / 2, dz / 2);
                    if middle.is_some_and(|middle| navigation.heights[middle].is_finite()) {
                        continue;
                    }
                }
                let Some(next) = navigation.neighbour(index, *dx, *dz) else {
                    continue;
                };
                let to = navigation.point(next);
                if !to[1].is_finite() || (direction < 4 && to[1] > from[1] + STEP_UP) {
                    continue;
                }
                if (direction < 4 && from[1] == to[1]) || navigation.walkable(from, to) {
                    navigation.edges[index] |= 1 << direction;
                }
            }
        }
        Ok(navigation)
    }

    fn point(&self, index: usize) -> [f32; 3] {
        [
            (index % self.width) as f32 * CELL - self.span as f32 * CELL + CELL * 0.5,
            self.heights[index],
            (index / self.width) as f32 * CELL - self.span as f32 * CELL + CELL * 0.5,
        ]
    }

    fn neighbour(&self, index: usize, dx: i32, dz: i32) -> Option<usize> {
        let x = (index % self.width) as i32 + dx;
        let z = (index / self.width) as i32 + dz;
        (x >= 0 && z >= 0 && x < self.width as i32 && z < self.width as i32)
            .then(|| z as usize * self.width + x as usize)
    }

    fn valid_point(&self, point: [f32; 3]) -> bool {
        point.iter().all(|v| v.is_finite())
            && point[0].abs() <= self.arena.half - RADIUS
            && point[2].abs() <= self.arena.half - RADIUS
            && (0.0..=MAX_HALF * 2.0).contains(&point[1])
    }

    /// Conservative grounded walk, including the start/end connection to a grid
    /// node. Swept clearance catches corners and arbitrarily thin barriers;
    /// quarter-metre steps update the supporting tread before the next riser.
    pub fn walkable(&self, from: [f32; 3], to: [f32; 3]) -> bool {
        if !self.valid_point(from) || !self.valid_point(to) {
            return false;
        }
        let mut floor = self.arena.support_height(from[0], from[2], from[1] + 0.01);
        if (from[1] - floor).abs() > 0.1 {
            return false;
        }
        let dx = to[0] - from[0];
        let dz = to[2] - from[2];
        let steps = (dx.hypot(dz) / (RADIUS * 0.5)).ceil().max(1.0) as usize;
        let mut previous = from;
        for step in 0..=steps {
            let fraction = step as f32 / steps as f32;
            let x = from[0] + dx * fraction;
            let z = from[2] + dz * fraction;
            if self.arena.blocked_at(x, z, floor + STEP_UP) {
                return false;
            }
            let delta = [x - previous[0], 0.0, z - previous[2]];
            let length = delta[0].hypot(delta[2]);
            if length > 0.0 {
                let ray = crate::combat::Ray {
                    origin: [previous[0], floor + STEP_UP, previous[2]],
                    direction: delta.map(|v| v / length),
                };
                if self.arena.solids.iter().any(|solid| {
                    solid.top > floor + STEP_UP
                        && ray
                            .solid(
                                &crate::movement::Solid {
                                    min_x: solid.min_x - RADIUS,
                                    max_x: solid.max_x + RADIUS,
                                    min_z: solid.min_z - RADIUS,
                                    max_z: solid.max_z + RADIUS,
                                    top: solid.top,
                                },
                                length,
                            )
                            .is_some()
                }) {
                    return false;
                }
            }
            let support = self.arena.support_height(x, z, floor + STEP_UP);
            // A descending fighter keeps its height while its body clears the
            // ledge. Dropping the probe to ground immediately would collide
            // with the deck it just left and make every large drop unreachable.
            if support >= floor || to[1] >= floor || !self.arena.blocked_at(x, z, support + STEP_UP)
            {
                floor = support;
            }
            previous = [x, floor, z];
        }
        (floor - to[1]).abs() <= 0.1
    }

    pub fn floor_below(&self, point: [f32; 3]) -> Option<f32> {
        self.valid_point(point).then(|| {
            self.arena
                .support_height(point[0], point[2], point[1] + STEP_UP)
        })
    }

    fn anchor(&self, point: [f32; 3], starting: bool) -> Option<usize> {
        if !self.valid_point(point) {
            return None;
        }
        let x = (point[0] / CELL + self.span as f32 - 0.5).round() as i32;
        let z = (point[2] / CELL + self.span as f32 - 0.5).round() as i32;
        let mut candidates = Vec::with_capacity(25);
        for dz in -2..=2 {
            for dx in -2..=2 {
                let (nx, nz) = (x + dx, z + dz);
                if nx < 0 || nz < 0 || nx >= self.width as i32 || nz >= self.width as i32 {
                    continue;
                }
                let index = nz as usize * self.width + nx as usize;
                let candidate = self.point(index);
                if candidate[1].is_finite() {
                    let distance = (point[0] - candidate[0]).hypot(point[2] - candidate[2]);
                    candidates.push((distance, index));
                }
            }
        }
        candidates.sort_by(|a, b| a.0.total_cmp(&b.0).then(a.1.cmp(&b.1)));
        candidates.into_iter().find_map(|(_, index)| {
            let candidate = self.point(index);
            let connected = if starting {
                self.walkable(point, candidate)
            } else {
                self.walkable(candidate, point)
            };
            connected.then_some(index)
        })
    }

    pub fn route(&self, from: [f32; 3], to: [f32; 3], limit: usize) -> Route {
        let mut route = Route {
            status: RouteStatus::InvalidPoint,
            points: Vec::new(),
            expanded: 0,
        };
        let (Some(start), Some(goal)) = (self.anchor(from, true), self.anchor(to, false)) else {
            return route;
        };
        let heuristic = |index: usize| {
            (index % self.width).abs_diff(goal % self.width)
                + (index / self.width).abs_diff(goal / self.width)
        };
        let mut costs = vec![usize::MAX; self.heights.len()];
        let mut parents = vec![usize::MAX; self.heights.len()];
        let mut queue = BinaryHeap::new();
        costs[start] = 0;
        queue.push(Reverse((heuristic(start), Reverse(0usize), start)));
        let mut nearest = start;
        route.status = RouteStatus::Unreachable;
        while let Some(Reverse((_, Reverse(cost), index))) = queue.pop() {
            if cost != costs[index] {
                continue;
            }
            if index == goal {
                nearest = goal;
                route.status = RouteStatus::Complete;
                break;
            }
            if route.expanded >= limit.min(SEARCH_LIMIT) {
                route.status = RouteStatus::BudgetExhausted;
                break;
            }
            route.expanded += 1;
            for (direction, (dx, dz)) in DIRECTIONS.iter().enumerate() {
                if self.edges[index] & (1 << direction) == 0 {
                    continue;
                }
                let Some(next) = self.neighbour(index, *dx, *dz) else {
                    continue;
                };
                let next_cost = cost + (dx.abs() + dz.abs()) as usize;
                if next_cost < costs[next] {
                    costs[next] = next_cost;
                    parents[next] = index;
                    if (heuristic(next), next) < (heuristic(nearest), nearest) {
                        nearest = next;
                    }
                    queue.push(Reverse((
                        next_cost + heuristic(next),
                        Reverse(next_cost),
                        next,
                    )));
                }
            }
        }
        // A bounded partial route is useful, but never reported as completion.
        if route.status == RouteStatus::Unreachable || nearest == start && nearest != goal {
            return route;
        }
        let mut index = nearest;
        route.points.push(self.point(index));
        while index != start {
            index = parents[index];
            route.points.push(self.point(index));
        }
        route.points.reverse();
        if route.status == RouteStatus::Complete {
            route.points.push(to);
        }
        route
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::movement::{self, MoveInput, MoveState, Solid};

    fn arena(solids: Vec<Solid>) -> Arena {
        Arena { half: 12.0, solids }
    }

    fn stairs() -> Arena {
        let mut solids = vec![Solid::from_center_top(4.0, 0.0, 3.0, 3.0, 2.0)];
        // Approach the deck from the south, rather than through its west face.
        for i in 0..4 {
            solids.push(Solid::from_center_top(
                4.0,
                -10.0 + i as f32 * 2.0,
                2.0,
                1.0,
                (i + 1) as f32 * 0.5,
            ));
        }
        arena(solids)
    }

    #[test]
    fn shared_geometry_reuses_live_topology_without_aliasing_different_maps() {
        let geometry = arena(vec![Solid::from_center(1.25, 2.75, 0.5, 0.75)]);
        let first = Navigation::shared(geometry.clone()).unwrap();
        let second = Navigation::shared(geometry.clone()).unwrap();
        assert!(Arc::ptr_eq(&first, &second));
        let mut changed = geometry;
        changed.solids[0].top += 1.0;
        let other = Navigation::shared(changed).unwrap();
        assert!(!Arc::ptr_eq(&first, &other));
        assert_ne!(first.arena.solids, other.arena.solids);
        assert!(Navigation::shared(Arena {
            half: f32::NAN,
            solids: vec![]
        })
        .is_err());
    }

    fn assert_walks(navigation: &Navigation, from: [f32; 3], to: [f32; 3]) {
        let route = navigation.route(from, to, SEARCH_LIMIT);
        assert_eq!(
            route.status,
            RouteStatus::Complete,
            "{from:?} -> {to:?}: {route:?}"
        );
        let mut state = MoveState {
            x: from[0],
            y: from[1],
            z: from[2],
            vx: 0.0,
            vy: 0.0,
            vz: 0.0,
            yaw: 0.0,
        };
        let mut navigator = Navigator::default();
        let mut arrived = false;
        for tick in 0..4000 {
            if (state.x - to[0]).hypot(state.z - to[2]) < 0.3 && (state.y - to[1]).abs() < 0.1 {
                arrived = true;
                break;
            }
            let here = [state.x, state.y, state.z];
            let action = navigator.steer(
                navigation,
                here,
                NavigationGoal {
                    feet: to,
                    combat: false,
                },
                crate::protocol::Action {
                    forward: true,
                    ..Default::default()
                },
                tick,
                true,
            );
            state = movement::step(
                state,
                &MoveInput {
                    forward: action.forward,
                    back: action.back,
                    left: action.left,
                    right: action.right,
                    yaw: action.yaw.unwrap_or(state.yaw),
                    ..MoveInput::default()
                },
                0.05,
                &navigation.arena,
            );
        }
        assert!(arrived, "{from:?} -> {to:?}: stalled at {state:?}");
        assert!((state.x - to[0]).hypot(state.z - to[2]) < 0.3);
        assert!((state.y - to[1]).abs() < 0.1);
    }

    fn assert_server_walks(
        map: crate::sim::MapKind,
        navigation: &Navigation,
        from: [f32; 3],
        to: [f32; 3],
    ) {
        use crate::sim::{GameState, PLAYER_FLOOR_Y};
        let mut state = GameState::with_map(map, false);
        state.config.time_limit_ticks = None;
        state.config.boss_spawn_ticks = None;
        state.config.compliance_ping_ticks = None;
        let id = uuid::Uuid::from_u128(67);
        state.add_player(id, "Route Probe".into(), crate::protocol::Role::Human);
        state.start_round();
        state.players[0].x = from[0];
        state.players[0].y = from[1] + PLAYER_FLOOR_Y;
        state.players[0].z = from[2];
        let mut navigator = Navigator::default();
        for tick in 0..4000 {
            let player = &state.players[0];
            let here = [player.x, player.y - PLAYER_FLOOR_Y, player.z];
            if (here[0] - to[0]).hypot(here[2] - to[2]) < 0.3 && (here[1] - to[1]).abs() < 0.1 {
                return;
            }
            let action = navigator.steer(
                navigation,
                here,
                NavigationGoal {
                    feet: to,
                    combat: false,
                },
                crate::protocol::Action {
                    forward: true,
                    ..Default::default()
                },
                tick,
                true,
            );
            assert!(
                !action.jump,
                "ordinary walking routes do not require jumping"
            );
            state.set_action(id, action);
            state.tick(0.05);
            state.take_events();
        }
        let player = &state.players[0];
        panic!(
            "{map:?} server {from:?} -> {to:?}: stopped at ({}, {}, {})",
            player.x,
            player.y - PLAYER_FLOOR_Y,
            player.z
        );
    }

    #[test]
    fn route_finds_stairs_instead_of_walking_into_deck_face() {
        let navigation = Navigation::new(stairs()).unwrap();
        let from = [-2.0, 0.0, 0.0];
        let to = [4.0, 2.0, 0.0];
        assert!(!navigation.walkable(from, to));
        let route = navigation.route(from, to, SEARCH_LIMIT);
        assert!(route.points.iter().any(|point| point[2] < -9.0));
        assert_eq!(route, navigation.route(from, to, SEARCH_LIMIT));
        assert_walks(&navigation, from, to);
        assert_walks(&navigation, to, from);
    }

    #[test]
    fn thin_barrier_clearance_and_directed_drop_are_respected() {
        let navigation =
            Navigation::new(arena(vec![Solid::from_center(0.0, 0.0, 0.001, 3.0)])).unwrap();
        assert!(!navigation.walkable([-2.0, 0.0, 0.0], [2.0, 0.0, 0.0]));
        assert_walks(&navigation, [-2.0, 0.0, 0.0], [2.0, 0.0, 0.0]);
        let sealed =
            Navigation::new(arena(vec![Solid::from_center(0.0, 0.0, 0.001, 12.0)])).unwrap();
        assert_eq!(
            sealed
                .route([-2.0, 0.0, 0.0], [2.0, 0.0, 0.0], SEARCH_LIMIT)
                .status,
            RouteStatus::Unreachable
        );
        let deck =
            Navigation::new(arena(vec![Solid::from_center_top(0.0, 0.0, 2.0, 2.0, 2.0)])).unwrap();
        assert_eq!(
            deck.route([5.0, 0.0, 0.0], [0.0, 2.0, 0.0], SEARCH_LIMIT)
                .status,
            RouteStatus::Unreachable
        );
        assert_walks(&deck, [0.0, 2.0, 0.0], [5.0, 0.0, 0.0]);
        // Two walls leave less than the fighter's diameter between them.
        let narrow = Navigation::new(arena(vec![
            Solid::from_center(0.0, -6.0, 0.1, 5.7),
            Solid::from_center(0.0, 6.0, 0.1, 5.7),
        ]))
        .unwrap();
        assert_eq!(
            narrow
                .route([-2.0, 0.0, 0.0], [2.0, 0.0, 0.0], SEARCH_LIMIT)
                .status,
            RouteStatus::Unreachable
        );
    }

    #[test]
    fn invalid_inputs_and_budget_exhaustion_are_explicit() {
        for half in [f32::NAN, f32::INFINITY, 0.0, MAX_HALF + 1.0] {
            assert!(Navigation::new(Arena {
                half,
                solids: vec![]
            })
            .is_err());
        }
        for solid in [
            Solid::from_center(f32::NAN, 0.0, 1.0, 1.0),
            Solid::from_center(0.0, 0.0, -1.0, 1.0),
            Solid::from_center_top(0.0, 0.0, 1.0, 1.0, -1.0),
        ] {
            assert!(Navigation::new(arena(vec![solid])).is_err());
        }
        assert!(Navigation::new(arena(vec![
            Solid::from_center(0.0, 0.0, 1.0, 1.0);
            MAX_SOLIDS + 1
        ]))
        .is_err());
        assert!(Navigation::new(Arena {
            half: MAX_HALF,
            solids: vec![Solid::from_center(0.0, 0.0, 1.0, 1.0); 300],
        })
        .is_err());
        let navigation = Navigation::new(arena(vec![])).unwrap();
        for point in [
            [f32::NAN; 3],
            [12.0, 0.0, 0.0],
            [0.0, 100.0, 0.0],
            [0.0, -1.0, 0.0],
        ] {
            assert_eq!(
                navigation.route(point, [0.0; 3], SEARCH_LIMIT).status,
                RouteStatus::InvalidPoint
            );
            assert_eq!(
                navigation.route([0.0; 3], point, SEARCH_LIMIT).status,
                RouteStatus::InvalidPoint
            );
        }
        let partial = navigation.route([-10.0, 0.0, 0.0], [10.0, 0.0, 0.0], 3);
        assert_eq!(partial.status, RouteStatus::BudgetExhausted);
        assert_eq!(partial.expanded, 3);
        assert!(!partial.points.is_empty());
        assert!(partial.points.last().unwrap()[0] < 10.0);
        let empty = navigation.route([-10.0, 0.0, 0.0], [10.0, 0.0, 0.0], 0);
        assert_eq!(empty.status, RouteStatus::BudgetExhausted);
        assert!(empty.points.is_empty());
        assert_eq!(
            navigation.route([0.0; 3], [0.0; 3], 0).status,
            RouteStatus::Complete
        );
    }

    #[test]
    fn every_map_pad_has_a_route_that_normal_movement_can_follow() {
        for map in crate::sim::MapKind::ALL {
            let start = std::time::Instant::now();
            let navigation = Navigation::new(Arena {
                half: map.half_extent(),
                solids: map.solids(),
            })
            .unwrap();
            eprintln!(
                "{}: {} nodes, {} solids, built in {:?}",
                map.name(),
                navigation.heights.len(),
                navigation.arena.solids.len(),
                start.elapsed()
            );
            for pad in map.pickups() {
                assert_walks(&navigation, [0.0; 3], [pad.x, pad.floor, pad.z]);
                assert_server_walks(map, &navigation, [0.0; 3], [pad.x, pad.floor, pad.z]);
            }
            for slot in 0..16 {
                let angle = slot as f32 * std::f32::consts::TAU / 16.0;
                let from = [
                    angle.cos() * map.spawn_radius(),
                    0.0,
                    angle.sin() * map.spawn_radius(),
                ];
                if !navigation.arena.blocked_at(from[0], from[2], STEP_UP) {
                    assert_walks(&navigation, from, [0.0; 3]);
                    assert_server_walks(map, &navigation, from, [0.0; 3]);
                }
            }
        }
    }
}
