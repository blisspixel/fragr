//! Two anonymous side-ward captives walk the prepared released world.
//! They are mission observations, never combat actors or objective gates.
use crate::movement::{integrate, Arena, MoveState};
use crate::navigation::Navigation;
use crate::protocol::{M02EvacuationPhase as Phase, M02EvacuationState as State};

const RELEASE: [[f32; 3]; 2] = [[22.6, 0.0, 7.5], [24.5, 0.0, 7.5]];
const WAIT: [[f32; 3]; 2] = State::WAIT_FEET;
const DOCK: [[f32; 3]; 2] = [[-1.0, 0.0, 21.5], [1.0, 0.0, 21.5]];
const ROUTE_A: [[f32; 3]; 9] = [
    [19.0, 0.0, 7.5],
    [19.0, 0.0, 9.0],
    [16.0, 0.0, 9.0],
    [13.0, 0.0, 9.0],
    [13.0, 0.0, 11.0],
    [7.0, 0.0, 11.0],
    [2.0, 0.0, 10.8],
    [-2.0, 0.0, 11.0],
    WAIT[0],
];
const ROUTE_B: [[f32; 3]; 11] = [
    [22.6, 0.0, 7.5],
    [19.0, 0.0, 7.5],
    [19.0, 0.0, 9.0],
    [16.0, 0.0, 9.0],
    [13.0, 0.0, 9.0],
    [13.0, 0.0, 11.0],
    [7.0, 0.0, 11.0],
    [2.0, 0.0, 10.8],
    [-2.0, 0.0, 11.0],
    [-3.0, 0.0, 11.0],
    WAIT[1],
];
const FINAL_A: [[f32; 3]; 5] = [
    [-5.2, 0.0, 13.0],
    [-2.0, 0.0, 13.0],
    [0.0, 0.0, 15.5],
    [0.0, 0.0, 19.0],
    DOCK[0],
];
const FINAL_B: [[f32; 3]; 4] = [
    [-1.5, 0.0, 12.0],
    [1.0, 0.0, 15.5],
    [1.0, 0.0, 19.0],
    DOCK[1],
];

/// Called at authored-map load, before any participant can mark mission ready.
/// The gate world already contains the raised shutter. Every segment uses the
/// same body-sized grounded sweep as the shared navigator.
pub(crate) fn validate_route(world: &Navigation) -> Result<(), &'static str> {
    for (from, to) in State::HELD_FEET.into_iter().zip(RELEASE) {
        if !world.walkable(from, to) {
            return Err("M02 captive release route is blocked");
        }
    }
    for (from, points) in [
        (RELEASE[0], ROUTE_A.as_slice()),
        (RELEASE[1], ROUTE_B.as_slice()),
    ] {
        let mut previous = from;
        for &point in points {
            if !world.walkable(previous, point) {
                return Err("M02 captive northern return is blocked");
            }
            previous = point;
        }
    }
    for (from, points) in [(WAIT[0], FINAL_A.as_slice()), (WAIT[1], FINAL_B.as_slice())] {
        let mut previous = from;
        for &point in points {
            if !world.walkable(previous, point) {
                return Err("M02 captive dock route is blocked");
            }
            previous = point;
        }
    }
    Ok(())
}

pub(super) struct Controller {
    contacts: Vec<crate::movement::contact::ContactBody>,
    pub(super) published: State,
    bodies: [MoveState; 2],
    points: [usize; 2],
    final_leg: bool,
    stalled: [u8; 2],
}

impl Default for State {
    fn default() -> Self {
        Self::held()
    }
}

impl Default for Controller {
    fn default() -> Self {
        Self {
            contacts: Vec::new(),
            published: State::held(),
            bodies: State::HELD_FEET.map(|feet| MoveState {
                x: feet[0],
                y: feet[1],
                z: feet[2],
                vx: 0.0,
                vz: 0.0,
                vy: 0.0,
                yaw: 0.0,
            }),
            points: [0; 2],
            final_leg: false,
            stalled: [0; 2],
        }
    }
}

impl Controller {
    pub(crate) fn set_contacts(&mut self, contacts: Vec<crate::movement::contact::ContactBody>) {
        self.contacts = contacts;
    }
    pub(crate) fn contact_feet(&self) -> [[f32; 3]; 2] {
        self.bodies.map(|b| [b.x, b.y, b.z])
    }
    fn ensure_bodies(&mut self) {
        if self.published.phase == Phase::Held {
            for (body, feet) in self.bodies.iter_mut().zip(State::HELD_FEET) {
                [body.x, body.y, body.z] = feet;
            }
        }
    }

    pub(super) fn tick(
        &mut self,
        _tick: u64,
        dt: f32,
        arena: &Arena,
        side_clear: bool,
        floor_clear: bool,
        dock_clear: bool,
    ) {
        match self.published.phase {
            Phase::Held if side_clear => {
                self.ensure_bodies();
                self.published.phase = Phase::Freeing;
            }
            Phase::Freeing => {
                if self.follow(arena, dt, &[RELEASE[0]], &[RELEASE[1]], 0.625) {
                    self.published.phase = Phase::Ready;
                    self.points = [0; 2];
                }
            }
            Phase::Ready if floor_clear => {
                self.published.phase = Phase::Moving;
            }
            Phase::Moving if !self.final_leg => {
                if self.follow(arena, dt, &ROUTE_A, &ROUTE_B, 2.0) {
                    self.published.phase = Phase::Waiting;
                    self.points = [0; 2];
                }
            }
            Phase::Waiting if dock_clear => {
                self.final_leg = true;
                self.published.phase = Phase::Moving;
            }
            Phase::Moving => {
                // Separate lanes through the dock opening keep the two
                // captives clear without making the second wait for arrival.
                let first = self.follow_one(0, arena, dt, &FINAL_A, 2.0);
                let second = self.follow_one(1, arena, dt, &FINAL_B, 2.0);
                if first && second {
                    self.published.phase = Phase::Evacuated;
                    self.published.evacuated = true;
                }
            }
            Phase::Held | Phase::Ready | Phase::Waiting | Phase::Evacuated => {}
        }
        // Contact prediction consumes these same feet, so publish each active
        // frame rather than leaving a moving visible blocker four ticks behind.
        self.published.captives = self.bodies.map(|body| [body.x, body.y, body.z]);
    }

    fn follow(
        &mut self,
        arena: &Arena,
        dt: f32,
        first: &[[f32; 3]],
        second: &[[f32; 3]],
        speed: f32,
    ) -> bool {
        let a = self.follow_one(0, arena, dt, first, speed);
        let b = self.follow_one(1, arena, dt, second, speed);
        a && b
    }

    fn follow_one(
        &mut self,
        index: usize,
        arena: &Arena,
        dt: f32,
        route: &[[f32; 3]],
        speed: f32,
    ) -> bool {
        let Some(&goal) = route.get(self.points[index]) else {
            return true;
        };
        let body = &mut self.bodies[index];
        let dx = goal[0] - body.x;
        let dz = goal[2] - body.z;
        let distance = dx.hypot(dz);
        if distance <= 0.08 {
            self.points[index] += 1;
            return self.points[index] >= route.len();
        }
        let dt = dt.clamp(0.0, 0.05);
        if dt == 0.0 {
            return false;
        }
        let speed = speed.min(distance / dt);
        body.vx = dx / distance * speed;
        body.vz = dz / distance * speed;
        let proposed = integrate(*body, false, dt, arena);
        let next = crate::sim::contact::move_body(
            &format!("m02/captive/{index}"),
            *body,
            proposed,
            crate::movement::BODY_HEIGHT,
            dt,
            arena,
            &self.contacts,
        );
        if let Some(contact) = self
            .contacts
            .iter_mut()
            .find(|b| b.key == format!("m02/captive/{index}"))
        {
            contact.from = next;
            contact.proposed = next;
        }
        let moved = (next.x - body.x).hypot(next.z - body.z);
        if moved < 0.001 {
            self.stalled[index] = self.stalled[index].saturating_add(1);
            if self.stalled[index] == 40 {
                tracing::error!(
                    captive = index,
                    waypoint = self.points[index],
                    "M02 captive route stalled"
                );
            }
        } else {
            self.stalled[index] = 0;
        }
        *body = next;
        false
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::maps::{AuthoredSource, RuntimeMap};
    use crate::protocol::MissionId;

    #[test]
    fn held_bays_remain_stable_across_publish_intervals() {
        let arena = Arena {
            half: 40.0,
            solids: Vec::new(),
        };
        let mut controller = Controller::default();
        for tick in 1..=12 {
            controller.tick(tick, 0.05, &arena, false, false, false);
            assert_eq!(controller.published, State::held());
        }
    }

    #[test]
    fn both_captives_walk_clearance_checked_route_and_arrive_after_dock_clear() {
        let map = RuntimeMap::Authored(
            AuthoredSource::Mission(MissionId::PersonsUnknown)
                .load()
                .unwrap(),
        );
        let released = map.prepared_gate_world(1).unwrap();
        let mut controller = Controller::default();
        let mut saw_freeing = false;
        let mut saw_ready = false;
        let mut saw_waiting = false;
        let mut saw_final_move = false;
        let mut minimum_separation = f32::MAX;
        let mut first_wait_tick = None;
        for tick in 1..2000 {
            controller.tick(
                tick,
                0.05,
                released.arena(),
                true,
                tick >= 200,
                tick >= 1000,
            );
            let phase = controller.published.phase;
            saw_freeing |= phase == Phase::Freeing;
            saw_ready |= phase == Phase::Ready;
            saw_waiting |= phase == Phase::Waiting;
            if phase == Phase::Waiting && first_wait_tick.is_none() {
                first_wait_tick = Some(tick);
            }
            saw_final_move |= phase == Phase::Moving && tick >= 1000;
            let [a, b] = controller.bodies;
            let separation = (a.x - b.x).hypot(a.z - b.z);
            minimum_separation = minimum_separation.min(separation);
            assert!(
                separation >= 1.0,
                "captives overlap at tick {tick}: {a:?}, {b:?}"
            );
            assert!(!released.arena().blocked_at(a.x, a.z, a.y + 0.6));
            assert!(!released.arena().blocked_at(b.x, b.z, b.y + 0.6));
            if tick < 1000 {
                assert_ne!(phase, Phase::Evacuated);
            }
            if phase == Phase::Evacuated {
                assert!(controller.published.evacuated);
                assert!((a.x - DOCK[0][0]).abs() < 0.1);
                assert!((a.z - DOCK[0][2]).abs() < 0.1);
                assert!((b.x - DOCK[1][0]).abs() < 0.1);
                assert!((b.z - DOCK[1][2]).abs() < 0.1);
                assert!(saw_freeing && saw_ready && saw_waiting && saw_final_move);
                assert!(minimum_separation >= 1.0);
                println!(
                    "release tick 1, floor clear tick 200, wait tick {:?}, dock clear tick 1000, evacuated tick {tick}, minimum separation {minimum_separation:.3}",
                    first_wait_tick
                );
                return;
            }
        }
        panic!("captives never completed the physical dock route");
    }
}
