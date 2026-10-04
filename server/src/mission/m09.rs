//! Passenger Manifest uses supported walking routes, never waypoint teleportation.
use crate::movement::{integrate, Arena, MoveState, BODY_HEIGHT, CONTACT_EPSILON, DT_LIVE, RADIUS};

pub(crate) fn m09_route_segment_valid(arena: &Arena, from: [f32; 3], target: [f32; 3]) -> bool {
    if [from, target].iter().any(|p| {
        p.iter().any(|v| !v.is_finite())
            || p[0].abs() > arena.half - RADIUS
            || p[2].abs() > arena.half - RADIUS
            || p[1] < 0.0
            || arena.blocked_body_at(p[0], p[2], p[1], p[1])
            || p[1] + BODY_HEIGHT > crate::movement::MAX_HALF_EXTENT * 2.0
            || [-RADIUS, RADIUS].iter().any(|dx| {
                [-RADIUS, RADIUS].iter().any(|dz| {
                    (arena.support_height(p[0] + dx, p[2] + dz, p[1] + CONTACT_EPSILON) - p[1])
                        .abs()
                        > CONTACT_EPSILON
                })
            })
    }) {
        return false;
    }
    let mut state = MoveState {
        x: from[0],
        y: from[1],
        z: from[2],
        vx: 0.0,
        vz: 0.0,
        vy: 0.0,
        yaw: 0.0,
    };
    for _ in 0..1024 {
        let dx = target[0] - state.x;
        let dz = target[2] - state.z;
        let distance = dx.hypot(dz);
        if distance <= 0.01 && (state.y - target[1]).abs() <= 0.01 && state.vy.abs() <= 0.01 {
            return true;
        }
        let speed = (distance / DT_LIVE).min(2.0);
        state.vx = if distance > 0.0 {
            dx / distance * speed
        } else {
            0.0
        };
        state.vz = if distance > 0.0 {
            dz / distance * speed
        } else {
            0.0
        };
        state = integrate(state, false, DT_LIVE, arena);
    }
    false
}
