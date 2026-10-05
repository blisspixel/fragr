//! Fixed local formation probes. Session retains the one bounded route search.
use crate::movement::{contact::ContactBody, Arena, MoveInput, RADIUS, STEP_UP};
use crate::navigation::{Navigation, NavigationGoal};
use crate::sim::Player;

const STAND_OFF: f32 = 2.4;
const YIELD_CLEARANCE: f32 = RADIUS * 2.0 + 0.6;
const FOLLOW_TOLERANCE: f32 = 0.65;
const DIRECTIONS: [f32; 8] = [
    0.0,
    std::f32::consts::FRAC_PI_4,
    -std::f32::consts::FRAC_PI_4,
    std::f32::consts::FRAC_PI_2,
    -std::f32::consts::FRAC_PI_2,
    std::f32::consts::PI * 0.75,
    -std::f32::consts::PI * 0.75,
    std::f32::consts::PI,
];

fn occupied(point: [f32; 3], me: &ContactBody, bodies: &[ContactBody]) -> bool {
    bodies.iter().any(|body| {
        body.key != me.key
            && point[1] + me.height > body.from.y
            && body.from.y + body.height > point[1]
            && (point[0] - body.from.x).hypot(point[2] - body.from.z)
                < me.radius + body.radius + 0.1
    })
}

/// A close retreat must remain supported and traverse the actual body scene.
/// Four ordinary quarter-metre steps are the entire local forecast budget.
fn safe_yield(arena: &Arena, me: &ContactBody, bodies: &[ContactBody], yaw: f32) -> bool {
    let mut pose = me.from;
    // A one-metre retreat cannot reach a body initially more than 2.5 m away.
    // Keep local contact work independent of a distant encounter roster.
    let neighbours: Vec<_> = bodies
        .iter()
        .filter(|body| {
            body.key == me.key
                || ((body.from.x - me.from.x).hypot(body.from.z - me.from.z) <= 2.5
                    && body.from.y + body.height > me.from.y
                    && me.from.y + me.height > body.from.y)
        })
        .cloned()
        .collect();
    for _ in 0..4 {
        let proposed = crate::movement::live_step_with_height(
            pose,
            &MoveInput {
                forward: true,
                yaw,
                speed_scale: 1.0,
                ..Default::default()
            },
            crate::movement::TOP_SPEED,
            0.05,
            arena,
            me.height,
        );
        if (proposed.y - me.from.y).abs() > 0.1 || proposed.vy.abs() > 0.001 {
            return false;
        }
        let mut scene = neighbours.clone();
        let Some(index) = scene.iter().position(|body| body.key == me.key) else {
            return false;
        };
        scene[index].from = pose;
        scene[index].proposed = proposed;
        let moved = crate::movement::contact::resolve(&scene, 0.05, arena)[index];
        if (moved.y - me.from.y).abs() > 0.1
            || moved.vy.abs() > 0.001
            || (moved.x - pose.x).hypot(moved.z - pose.z) < 0.2
        {
            return false;
        }
        pose = moved;
    }
    true
}

pub(super) fn goal(
    arena: &Arena,
    companion: &Player,
    leader: [f32; 3],
    m02_slot: bool,
    bodies: &[ContactBody],
) -> Option<NavigationGoal> {
    let me = bodies
        .iter()
        .find(|body| body.key == companion.id.to_string())?;
    let feet = [me.from.x, me.from.y, me.from.z];
    let gap = (feet[0] - leader[0]).hypot(feet[2] - leader[2]);
    let close = gap < YIELD_CLEARANCE && (feet[1] - leader[1]).abs() < me.height;
    if !close && gap <= STAND_OFF + FOLLOW_TOLERANCE && (feet[1] - leader[1]).abs() < 0.1 {
        return None;
    }
    let away = (feet[2] - leader[2]).atan2(feet[0] - leader[0]);
    // Preserve the M02 ward's west-forward preference for distant following.
    // Nearby bodies yield away from the participant rather than closing that slot.
    let preferred = if m02_slot && !close {
        (1.2_f32).atan2((leader[0] - 2.4).max(-13.0) - leader[0])
    } else {
        away
    };
    for offset in DIRECTIONS {
        let yaw = preferred + offset;
        let (origin, length) = if close {
            (feet, 1.0)
        } else {
            (leader, STAND_OFF)
        };
        let x = origin[0] + yaw.cos() * length;
        let z = origin[2] + yaw.sin() * length;
        let floor = arena.support_height(x, z, origin[1] + STEP_UP);
        let point = [x, floor, z];
        if (floor - origin[1]).abs() > 0.1
            || (point[0] - leader[0]).hypot(point[2] - leader[2]) < YIELD_CLEARANCE
            || occupied(point, me, bodies)
            || !Navigation::walkable_in(arena, origin, point)
            || (close && !safe_yield(arena, me, bodies, yaw))
        {
            continue;
        }
        return Some(NavigationGoal {
            feet: point,
            combat: false,
        });
    }
    None
}
