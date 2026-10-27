//! Market-only arbitration of already constrained ordinary key actions. This
//! evaluator revision sees only the current delayed-visible floor strips.
//! It neither remembers unseen hazards nor chooses a new navigation route.
use fragr_server::movement::{Arena, MoveInput, MoveState, ACTOR_REFERENCE_SPEED, CONTACT_EPSILON};
use fragr_server::protocol::{Action, PaverStripState, PlayerState, Snapshot};
use fragr_server::sim::PLAYER_FLOOR_Y;

pub(super) fn protect(
    shared: Action,
    mut proposed: Action,
    me: &PlayerState,
    observed: &Snapshot,
    arena: &Arena,
) -> Action {
    let current = || {
        observed
            .paver_strips
            .iter()
            .filter(|strip| strip.phase_ends >= observed.tick)
    };
    let from = feet(me);
    if current().any(|strip| crosses(strip, from, from)) {
        // This alternative already passed the same reload, aim and turning
        // constraints. Generic dodge/hearing/scanning cannot replace escape.
        return shared;
    }
    let floor = arena.support_height(from[0], from[2], from[1] + CONTACT_EPSILON);
    if proposed.jump || (from[1] - floor).abs() > CONTACT_EPSILON {
        // No private vertical velocity, airborne prediction or extra flight
        // ability is introduced by this grounded ingress check.
        return proposed;
    }
    let to = project(me, &proposed, arena);
    if current().any(|strip| crosses(strip, from, to)) {
        // Wait or keep shooting from the safe side. A retired/unrecognized
        // strip contributes no veto next tick. No inventory or aim mutation.
        proposed.forward = false;
        proposed.back = false;
        proposed.left = false;
        proposed.right = false;
    }
    proposed
}

fn feet(me: &PlayerState) -> [f32; 3] {
    [me.x, me.y - PLAYER_FLOOR_Y, me.z]
}

fn project(me: &PlayerState, action: &Action, arena: &Arena) -> [f32; 3] {
    let from = feet(me);
    let after = fragr_server::movement::live_step(
        MoveState {
            x: from[0],
            y: from[1],
            z: from[2],
            vx: 0.0,
            vy: 0.0,
            vz: 0.0,
            yaw: me.yaw,
        },
        &MoveInput {
            forward: action.forward,
            back: action.back,
            left: action.left,
            right: action.right,
            yaw: action.yaw.unwrap_or(me.yaw),
            ..Default::default()
        },
        ACTOR_REFERENCE_SPEED,
        super::DT,
        arena,
    );
    [after.x, after.y, after.z]
}

fn local(strip: &PaverStripState, point: [f32; 3]) -> [f32; 3] {
    let dx = point[0] - strip.origin[0];
    let dz = point[2] - strip.origin[2];
    [
        dx * strip.yaw.cos() + dz * strip.yaw.sin(),
        point[1] - strip.origin[1],
        -dx * strip.yaw.sin() + dz * strip.yaw.cos(),
    ]
}

/// Conservative centre-path crossing of the published floor rectangle, with
/// the existing 0.7m floor band. A corner crossing counts even when both ends
/// are outside. This is an avoidance model, never damage authority.
fn crosses(strip: &PaverStripState, from: [f32; 3], to: [f32; 3]) -> bool {
    let a = local(strip, from);
    let b = local(strip, to);
    let bounds = [
        (0.0, strip.length),
        (-0.7, 0.7),
        (-strip.half_width, strip.half_width),
    ];
    let mut enter = 0.0_f32;
    let mut leave = 1.0_f32;
    for (axis, (low, high)) in bounds.into_iter().enumerate() {
        let delta = b[axis] - a[axis];
        if delta.abs() < 1e-6 {
            if a[axis] < low || a[axis] > high {
                return false;
            }
        } else {
            let one = (low - a[axis]) / delta;
            let two = (high - a[axis]) / delta;
            enter = enter.max(one.min(two));
            leave = leave.min(one.max(two));
            if enter > leave {
                return false;
            }
        }
    }
    true
}

#[cfg(test)]
mod tests;
