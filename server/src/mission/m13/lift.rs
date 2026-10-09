//! Vertical freight deck. A supported rider rises with it. Any obstruction
//! refuses the whole step, deck included.
use crate::movement::{MoveState, Solid, RADIUS};

pub const MAX_STEP: f32 = 0.075;
pub const SPEED: f32 = 1.5;
const SUPPORT_EPSILON: f32 = 0.05;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Phase {
    Parked,
    Moving,
    Blocked,
    Arrived,
}

#[derive(Debug, Clone, Copy)]
pub struct Body {
    pub x: f32,
    pub y: f32,
    pub z: f32,
    pub height: f32,
    pub supported: bool,
}

pub fn delta_y(current: f32, target: f32, dt: f32) -> Option<f32> {
    if !current.is_finite() || !target.is_finite() || !dt.is_finite() || dt <= 0.0 {
        return None;
    }
    let remaining = target - current;
    if remaining <= 0.001 {
        return Some(0.0);
    }
    Some(remaining.min(SPEED * dt.min(0.05)).min(MAX_STEP))
}

pub fn deck_at(start: Solid, top: f32) -> Option<Solid> {
    let thickness = start.top - start.bottom;
    if !top.is_finite() || !(0.05..=2.0).contains(&thickness) || top < start.top - 0.001 {
        return None;
    }
    Some(Solid {
        bottom: top - thickness,
        top,
        ..start
    })
}

pub fn supported(
    body: MoveState,
    deck: Solid,
    inset_min: [f32; 2],
    inset_max: [f32; 2],
    jumping: bool,
) -> bool {
    !jumping
        && body.vy.abs() <= 0.001
        && (body.y - deck.top).abs() <= SUPPORT_EPSILON
        && body.x >= inset_min[0]
        && body.x <= inset_max[0]
        && body.z >= inset_min[1]
        && body.z <= inset_max[1]
        && deck.covers(body.x, body.z)
}

pub fn step_blocked(
    old_deck: Solid,
    new_deck: Solid,
    bodies: &[Body],
    world: &[Solid],
    deck_index: usize,
) -> bool {
    if !deck_clear(old_deck, new_deck, world, deck_index) {
        return true;
    }
    let delta = new_deck.top - old_deck.top;
    for body in bodies {
        if !body.x.is_finite() || !body.y.is_finite() || !body.z.is_finite() || body.height <= 0.0 {
            return true;
        }
        let next_y = if body.supported {
            body.y + delta
        } else {
            body.y
        };
        if body.supported
            && hits_world(
                body.x,
                body.z,
                body.y,
                next_y,
                body.height,
                world,
                deck_index,
            )
        {
            return true;
        }
        if !body.supported && hits_volume(body, body.y, swept(old_deck, new_deck)) {
            return true;
        }
    }
    bodies.iter().enumerate().any(|(index, body)| {
        let ay = if body.supported {
            body.y + delta
        } else {
            body.y
        };
        bodies.iter().skip(index + 1).any(|other| {
            let by = if other.supported {
                other.y + delta
            } else {
                other.y
            };
            cylinders_overlap(body, ay, other, by)
        })
    })
}

fn deck_clear(old_deck: Solid, new_deck: Solid, world: &[Solid], deck_index: usize) -> bool {
    let moving = swept(old_deck, new_deck);
    world
        .iter()
        .enumerate()
        .all(|(index, solid)| index == deck_index || !volumes_overlap(moving, *solid))
}

fn swept(old_deck: Solid, new_deck: Solid) -> Solid {
    Solid {
        bottom: old_deck.bottom.min(new_deck.bottom),
        top: old_deck.top.max(new_deck.top),
        ..old_deck
    }
}

fn volumes_overlap(a: Solid, b: Solid) -> bool {
    a.min_x < b.max_x
        && a.max_x > b.min_x
        && a.min_z < b.max_z
        && a.max_z > b.min_z
        && a.bottom < b.top
        && a.top > b.bottom
}

fn hits_world(
    x: f32,
    z: f32,
    y0: f32,
    y1: f32,
    height: f32,
    world: &[Solid],
    deck_index: usize,
) -> bool {
    world
        .iter()
        .enumerate()
        .any(|(index, solid)| index != deck_index && column_hits(x, z, y0, y1, height, *solid))
}

fn column_hits(x: f32, z: f32, y0: f32, y1: f32, height: f32, solid: Solid) -> bool {
    let low = y0.min(y1);
    let high = y0.max(y1) + height;
    solid.blocks(x, z, RADIUS) && high > solid.bottom && low < solid.top
}

fn hits_volume(body: &Body, y: f32, solid: Solid) -> bool {
    column_hits(body.x, body.z, y, y, body.height, solid)
}

fn cylinders_overlap(a: &Body, ay: f32, b: &Body, by: f32) -> bool {
    let dx = a.x - b.x;
    let dz = a.z - b.z;
    let reach = RADIUS * 2.0;
    if dx * dx + dz * dz >= reach * reach {
        return false;
    }
    let a_high = ay + a.height;
    let b_high = by + b.height;
    a_high > by && ay < b_high
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::movement::BODY_HEIGHT;

    fn deck() -> Solid {
        Solid {
            min_x: -2.0,
            max_x: 2.0,
            min_z: -2.0,
            max_z: 2.0,
            bottom: 0.0,
            top: 0.3,
        }
    }

    fn rider(y: f32) -> Body {
        Body {
            x: 0.0,
            y,
            z: 0.0,
            height: BODY_HEIGHT,
            supported: true,
        }
    }

    #[test]
    fn a_clear_step_rises_and_a_body_in_the_way_refuses_it() {
        let start = deck();
        let next = deck_at(start, 0.375).unwrap();
        assert!(!step_blocked(start, next, &[rider(0.3)], &[start], 0));
        let ceiling = Solid {
            min_x: -1.0,
            max_x: 1.0,
            min_z: -1.0,
            max_z: 1.0,
            bottom: 2.05,
            top: 2.4,
        };
        assert!(step_blocked(
            start,
            next,
            &[rider(0.3)],
            &[start, ceiling],
            0
        ));
        let blocker = Body {
            x: 0.0,
            y: 1.6,
            z: 0.0,
            height: BODY_HEIGHT,
            supported: false,
        };
        assert!(step_blocked(
            start,
            next,
            &[rider(0.3), blocker],
            &[start],
            0
        ));
        assert_eq!(delta_y(0.3, 4.0, 0.05), Some(MAX_STEP));
        assert_eq!(delta_y(4.0, 4.0, 0.05), Some(0.0));
        assert!(delta_y(0.3, 4.0, f32::NAN).is_none());
    }

    #[test]
    fn support_requires_the_inset_and_a_quiet_foot() {
        let deck = deck();
        let inset = ([-1.2, -1.2], [1.2, 1.2]);
        let body = MoveState {
            x: 0.0,
            y: 0.3,
            z: 0.0,
            vx: 0.0,
            vz: 0.0,
            vy: 0.0,
            yaw: 0.0,
        };
        assert!(supported(body, deck, inset.0, inset.1, false));
        assert!(!supported(body, deck, inset.0, inset.1, true));
        assert!(!supported(
            MoveState { x: 1.8, ..body },
            deck,
            inset.0,
            inset.1,
            false
        ));
        assert!(!supported(
            MoveState { vy: 1.0, ..body },
            deck,
            inset.0,
            inset.1,
            false
        ));
    }
}
