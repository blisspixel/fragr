//! Fixed local formation probes. Session retains the one bounded route search.
use crate::movement::{contact::ContactBody, Arena, MoveInput, Solid, EYE_HEIGHT, RADIUS, STEP_UP};
use crate::navigation::{Navigation, NavigationGoal};
use crate::protocol::Action;
use crate::sim::Player;

/// The participant Latch keeps company with.
pub(super) struct Leader {
    pub(super) feet: [f32; 3],
    pub(super) yaw: f32,
    /// Horizontal velocity, metres per second.
    pub(super) velocity: [f32; 2],
}

/// The enemy the participant is facing, and the world that blocks sight.
pub(super) struct Threat<'a> {
    pub(super) feet: [f32; 3],
    pub(super) solids: &'a [Solid],
}

/// A participant moving at least this fast is going somewhere.
const WALKING: f32 = 1.0;
/// The lane ahead of a moving participant that Latch keeps clear: this far
/// ahead and this wide either side of their line of travel.
const PATH_AHEAD: f32 = 4.0;
const PATH_HALF_WIDTH: f32 = 1.0;
/// Sidestep distance out of that lane.
const PATH_STEP: f32 = 1.6;
/// A covering position keeps this much angle off the participant's line of
/// fire, at a companionable distance from them.
const FIRE_CONE: f32 = 0.4;
const COVER_NEAR: f32 = 2.2;
const COVER_FAR: f32 = 4.6;
/// Furthest round from the threat bearing a covering position may sit:
/// abreast or a little back, never behind the participant's shoulders.
const COVER_WIDE: f32 = 2.1;
/// The participant's line of fire Latch keeps clear: this far down their
/// crosshair and toward the threat, this wide either side.
const FIRE_REACH: f32 = 12.0;
const FIRE_HALF_WIDTH: f32 = 0.9;

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
fn safe_yield(
    arena: &Arena,
    me: &ContactBody,
    bodies: &[ContactBody],
    yaw: f32,
    steps: u8,
) -> bool {
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
    for _ in 0..steps {
        let proposed = crate::movement::live_step_with_height(
            pose,
            &MoveInput {
                forward: true,
                yaw,
                speed_scale: 1.0,
                ..Default::default()
            },
            crate::movement::ACTOR_REFERENCE_SPEED,
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

fn angle_between(a: f32, b: f32) -> f32 {
    let delta = (a - b).rem_euclid(std::f32::consts::TAU);
    delta.min(std::f32::consts::TAU - delta)
}

/// Supported floor at `point`'s ground position level with `origin`.
fn level_point(arena: &Arena, origin: [f32; 3], x: f32, z: f32) -> Option<[f32; 3]> {
    let floor = arena.support_height(x, z, origin[1] + STEP_UP);
    ((floor - origin[1]).abs() <= 0.1).then_some([x, floor, z])
}

/// A strip of floor in front of the participant that Latch keeps clear: the
/// way they are walking, or the line they are shooting down.
#[derive(Clone, Copy)]
struct Lane {
    origin: [f32; 3],
    along: [f32; 2],
    reach: f32,
    half_width: f32,
    /// Whether leading ahead along it gets Latch out of it. Through a
    /// doorway it does; down a line of fire it never does.
    lead: bool,
}

impl Lane {
    fn toward(origin: [f32; 3], yaw: f32, reach: f32, half_width: f32, lead: bool) -> Self {
        Self {
            origin,
            along: [yaw.cos(), yaw.sin()],
            reach,
            half_width,
            lead,
        }
    }

    /// Signed sideways offset of `point` from the lane's line, and how far
    /// along it the point lies.
    fn frame(&self, point: [f32; 3]) -> (f32, f32) {
        let offset = [point[0] - self.origin[0], point[2] - self.origin[2]];
        (
            offset[0] * self.along[1] - offset[1] * self.along[0],
            offset[0] * self.along[0] + offset[1] * self.along[1],
        )
    }

    fn holds(&self, point: [f32; 3], height: f32) -> bool {
        let (lateral, ahead) = self.frame(point);
        (point[1] - self.origin[1]).abs() < height
            && ahead > 0.0
            && ahead < self.reach
            && lateral.abs() < self.half_width
    }
}

/// The lanes around the participant Latch must not stand in: where a moving
/// participant is about to walk and, in a fight, their crosshair and their
/// line to the threat.
fn lanes(leader: &Leader, threat: Option<&Threat<'_>>) -> Vec<Lane> {
    let mut lanes = Vec::new();
    if let Some(threat) = threat {
        let bearing = (threat.feet[2] - leader.feet[2]).atan2(threat.feet[0] - leader.feet[0]);
        let distance = (threat.feet[0] - leader.feet[0]).hypot(threat.feet[2] - leader.feet[2]);
        lanes.push(Lane::toward(
            leader.feet,
            bearing,
            distance,
            FIRE_HALF_WIDTH,
            false,
        ));
        lanes.push(Lane::toward(
            leader.feet,
            leader.yaw,
            FIRE_REACH,
            FIRE_HALF_WIDTH,
            false,
        ));
    }
    let speed = leader.velocity[0].hypot(leader.velocity[1]);
    if speed >= WALKING {
        let heading = leader.velocity[1].atan2(leader.velocity[0]);
        lanes.push(Lane::toward(
            leader.feet,
            heading,
            PATH_AHEAD,
            PATH_HALF_WIDTH,
            threat.is_none(),
        ));
    }
    lanes
}

/// Out of every lane around the participant: a step aside on Latch's own side
/// of the lane, the other side, a lead through the doorway ahead when the
/// walls leave no side and nobody is shooting, or a place behind the
/// participant's shoulder.
fn clear_lanes(
    arena: &Arena,
    me: &ContactBody,
    leader: &Leader,
    bodies: &[ContactBody],
    threat: Option<&Threat<'_>>,
) -> Option<NavigationGoal> {
    let feet = [me.from.x, me.from.y, me.from.z];
    let lanes = lanes(leader, threat);
    let lane = *lanes.iter().find(|lane| lane.holds(feet, me.height))?;
    let side = if lane.frame(feet).0 >= 0.0 { 1.0 } else { -1.0 };
    // The perpendicular on Latch's side of the lane.
    let across = [lane.along[1] * side, -lane.along[0] * side];
    let mut steps: Vec<[f32; 3]> = [
        (across, PATH_STEP),
        ([-across[0], -across[1]], PATH_STEP),
        (across, PATH_STEP * 0.6),
    ]
    .into_iter()
    .filter_map(|(direction, length)| {
        level_point(
            arena,
            feet,
            feet[0] + direction[0] * length,
            feet[2] + direction[1] * length,
        )
    })
    .filter(|point| Navigation::walkable_in(arena, feet, *point))
    .collect();
    if lane.lead {
        steps.extend(
            level_point(
                arena,
                feet,
                feet[0] + lane.along[0] * PATH_AHEAD,
                feet[2] + lane.along[1] * PATH_AHEAD,
            )
            .filter(|point| Navigation::walkable_in(arena, feet, *point)),
        );
    }
    // Behind the participant's shoulder, reached around them by the route
    // search rather than through them.
    for shoulder in [side, -side, 0.0] {
        steps.extend(
            level_point(
                arena,
                leader.feet,
                leader.feet[0] - lane.along[0] * STAND_OFF + lane.along[1] * shoulder * 1.0,
                leader.feet[2] - lane.along[1] * STAND_OFF - lane.along[0] * shoulder * 1.0,
            )
            .filter(|point| Navigation::walkable_in(arena, leader.feet, *point)),
        );
    }
    steps
        .into_iter()
        .find(|point| {
            !occupied(*point, me, bodies)
                && (point[0] - leader.feet[0]).hypot(point[2] - leader.feet[2]) >= YIELD_CLEARANCE
                && !lanes.iter().any(|lane| lane.holds(*point, me.height))
        })
        .map(|point| NavigationGoal {
            feet: point,
            combat: false,
        })
}

/// In a fight Latch stands beside the participant with a line on the threat,
/// out of the participant's line of fire and out of their crosshair. Returns
/// `Some(None)` to hold a position that already does that, `Some(goal)` to
/// move to the nearest one, and `None` when the ground offers none.
fn covering(
    arena: &Arena,
    me: &ContactBody,
    leader: &Leader,
    bodies: &[ContactBody],
    threat: &Threat<'_>,
) -> Option<Option<NavigationGoal>> {
    let feet = [me.from.x, me.from.y, me.from.z];
    let bearing = (threat.feet[2] - leader.feet[2]).atan2(threat.feet[0] - leader.feet[0]);
    let threat_eye = [
        threat.feet[0],
        threat.feet[1] + EYE_HEIGHT * 0.8,
        threat.feet[2],
    ];
    let covers = |point: [f32; 3]| {
        let offset = [point[0] - leader.feet[0], point[2] - leader.feet[2]];
        let reach = offset[0].hypot(offset[1]);
        let round = offset[1].atan2(offset[0]);
        (COVER_NEAR..=COVER_FAR).contains(&reach)
            && (point[1] - leader.feet[1]).abs() < me.height
            && angle_between(round, bearing) >= FIRE_CONE
            && angle_between(round, bearing) <= COVER_WIDE
            && angle_between(round, leader.yaw) >= FIRE_CONE
            && !lanes(leader, Some(threat))
                .iter()
                .any(|lane| lane.holds(point, me.height))
            && crate::combat::line_of_sight(
                [point[0], point[1] + EYE_HEIGHT, point[2]],
                threat_eye,
                threat.solids,
            )
    };
    if covers(feet) {
        return Some(None);
    }
    let mut best: Option<([f32; 3], f32)> = None;
    for reach in [2.6_f32, 3.4] {
        for turn in [0.9_f32, -0.9, 1.3, -1.3, 0.6, -0.6, 1.7, -1.7] {
            let yaw = bearing + turn;
            let Some(point) = level_point(
                arena,
                leader.feet,
                leader.feet[0] + yaw.cos() * reach,
                leader.feet[2] + yaw.sin() * reach,
            ) else {
                continue;
            };
            let walk = (point[0] - feet[0]).hypot(point[2] - feet[2]);
            if best.is_some_and(|(_, shortest)| shortest <= walk)
                || !covers(point)
                || occupied(point, me, bodies)
                || !Navigation::walkable_in(arena, leader.feet, point)
            {
                continue;
            }
            best = Some((point, walk));
        }
    }
    best.map(|(point, walk)| {
        (walk > FOLLOW_TOLERANCE).then_some(NavigationGoal {
            feet: point,
            combat: false,
        })
    })
}

pub(super) fn goal(
    arena: &Arena,
    companion: &Player,
    leader_state: &Leader,
    m02_slot: bool,
    bodies: &[ContactBody],
    threat: Option<Threat<'_>>,
) -> Option<NavigationGoal> {
    let leader = leader_state.feet;
    let me = bodies
        .iter()
        .find(|body| body.key == companion.id.to_string())?;
    let feet = [me.from.x, me.from.y, me.from.z];
    let gap = (feet[0] - leader[0]).hypot(feet[2] - leader[2]);
    let close = gap < YIELD_CLEARANCE && (feet[1] - leader[1]).abs() < me.height;
    if !close {
        if let Some(clear) = clear_lanes(arena, me, leader_state, bodies, threat.as_ref()) {
            return Some(clear);
        }
        if let Some(cover) = threat
            .as_ref()
            .and_then(|threat| covering(arena, me, leader_state, bodies, threat))
        {
            return cover;
        }
    }
    if m02_slot && !close {
        // M02 already has an authored lateral slot. Keep its exact return-route
        // placement and tolerance instead of changing ordinary support timing.
        let point = [(leader[0] - 2.4).max(-13.0), leader[1], leader[2] + 1.2];
        let support = arena.support_height(point[0], point[2], point[1] + STEP_UP);
        if (support - point[1]).abs() <= 0.1
            && !arena.blocked_at(point[0], point[2], point[1] + STEP_UP)
            && (point[0] - leader[0]).hypot(point[2] - leader[2]) >= RADIUS * 2.0 + 0.1
            && !occupied(point, me, bodies)
            && !lanes(leader_state, threat.as_ref())
                .iter()
                .any(|lane| lane.holds(point, me.height))
        {
            return ((feet[0] - point[0]).hypot(feet[2] - point[2]) > FOLLOW_TOLERANCE
                || (feet[1] - point[1]).abs() > 0.1)
                .then_some(NavigationGoal {
                    feet: point,
                    combat: false,
                });
        }
    }
    if !m02_slot
        && !close
        && gap <= STAND_OFF + FOLLOW_TOLERANCE
        && (feet[1] - leader[1]).abs() < 0.1
    {
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
            || lanes(leader_state, threat.as_ref())
                .iter()
                .any(|lane| lane.holds(point, me.height))
            || (close && !safe_yield(arena, me, bodies, yaw, 4))
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

/// A narrow supported ledge may have room for a short ordinary step but not
/// the full formation circle. This fallback uses the same action channel and
/// forecasts at most two quarter-metre steps, without a grid/search request.
pub(super) fn short_yield(
    arena: &Arena,
    companion: &Player,
    leader: [f32; 3],
    bodies: &[ContactBody],
) -> Option<Action> {
    let me = bodies
        .iter()
        .find(|body| body.key == companion.id.to_string())?;
    let feet = [me.from.x, me.from.y, me.from.z];
    let gap = (feet[0] - leader[0]).hypot(feet[2] - leader[2]);
    if gap >= YIELD_CLEARANCE || (feet[1] - leader[1]).abs() >= me.height {
        return None;
    }
    let away = (feet[2] - leader[2]).atan2(feet[0] - leader[0]);
    for steps in [2_u8, 1] {
        let length = f32::from(steps) * 0.25;
        for offset in DIRECTIONS {
            let yaw = away + offset;
            let point = [
                feet[0] + yaw.cos() * length,
                feet[1],
                feet[2] + yaw.sin() * length,
            ];
            let floor = arena.support_height(point[0], point[2], feet[1] + STEP_UP);
            if (floor - feet[1]).abs() > 0.1
                || (point[0] - leader[0]).hypot(point[2] - leader[2]) <= gap + 0.05
                || occupied(point, me, bodies)
                || !safe_yield(arena, me, bodies, yaw, steps)
            {
                continue;
            }
            return Some(Action {
                forward: true,
                yaw: Some(yaw),
                ..Default::default()
            });
        }
    }
    None
}
