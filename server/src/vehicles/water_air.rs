//! Bounded surface craft and upright arcade flight on registered map water.
use super::{clear_kind, dimensions, local_point, vehicle_step, VehicleInput, VehicleMotion};
use crate::movement::{Arena, GRAVITY};
use crate::protocol::{VehicleKind, WaterRegion};
#[cfg(test)]
mod tests;

pub const BOAT_DRAFT: f32 = 0.6;
pub const FLIGHT_CEILING: f32 = 60.0;

pub fn surface_at(water: &[WaterRegion], x: f32, z: f32) -> Option<(f32, f32)> {
    water
        .iter()
        .find(|r| x >= r.min[0] && x <= r.max[0] && z >= r.min[1] && z <= r.max[1])
        .map(|r| (r.level, r.depth))
}

fn boat_support(state: VehicleMotion, water: &[WaterRegion]) -> Option<f32> {
    let [length, width, _] = dimensions(VehicleKind::Boat);
    let level = surface_at(water, state.position[0], state.position[2])?.0;
    for x in [-length, 0.0, length] {
        for z in [-width, width] {
            let p = local_point(state.position, state.yaw, [x, 0.0, z]);
            let (surface, depth) = surface_at(water, p[0], p[2])?;
            if depth < BOAT_DRAFT || (surface - level).abs() > 0.01 {
                return None;
            }
        }
    }
    Some(level)
}

pub fn vehicle_step_kind(
    kind: VehicleKind,
    mut state: VehicleMotion,
    input: VehicleInput,
    dt: f32,
    arena: &Arena,
    water: &[WaterRegion],
) -> VehicleMotion {
    if kind == VehicleKind::Jeep {
        let next = vehicle_step(state, input, dt, arena);
        if surface_at(water, next.position[0], next.position[2])
            .is_some_and(|(level, _)| next.position[1] < level + 0.3)
        {
            state.speed = 0.0;
            return state;
        }
        return next;
    }
    if !dt.is_finite()
        || dt <= 0.0
        || dt > 0.05
        || !state.position.iter().all(|v| v.is_finite())
        || !state.yaw.is_finite()
        || !state.speed.is_finite()
        || !state.vy.is_finite()
    {
        return state;
    }
    if kind == VehicleKind::Boat {
        return boat_step(state, input, dt, arena, water);
    }
    plane_step(state, input, dt, arena, water)
}

fn boat_step(
    mut state: VehicleMotion,
    input: VehicleInput,
    dt: f32,
    arena: &Arena,
    water: &[WaterRegion],
) -> VehicleMotion {
    let throttle = i32::from(input.forward) - i32::from(input.back);
    let target = if input.brake {
        0.0
    } else if throttle > 0 {
        14.0
    } else if throttle < 0 {
        -4.0
    } else {
        0.0
    };
    let rate = if input.brake {
        12.0
    } else if throttle == 0 {
        1.5
    } else if state.speed * (throttle as f32) < 0.0 {
        6.0
    } else {
        4.0
    };
    state.speed += (target - state.speed).clamp(-rate * dt, rate * dt);
    state.speed = state.speed.clamp(-4.0, 14.0);
    let angular = (i32::from(input.right) - i32::from(input.left)) as f32
        * 0.8
        * (state.speed / 3.0).clamp(-1.0, 1.0)
        / (1.0 + state.speed.abs() * 0.04);
    let steps = ((state.speed.abs() * dt / 0.1).ceil() as usize).max(4);
    let step = dt / steps as f32;
    for _ in 0..steps {
        let mut next = state;
        next.yaw = crate::movement::normalize_yaw(state.yaw + angular * step);
        next.position[0] += next.yaw.cos() * state.speed * step;
        next.position[2] += next.yaw.sin() * state.speed * step;
        let Some(level) = boat_support(next, water) else {
            state.speed = 0.0;
            break;
        };
        next.position[1] = level;
        next.vy = 0.0;
        if !clear_kind(VehicleKind::Boat, next.position, next.yaw, arena) {
            state.speed = 0.0;
            break;
        }
        state = next;
    }
    state
}

fn plane_step(
    mut state: VehicleMotion,
    input: VehicleInput,
    dt: f32,
    arena: &Arena,
    water: &[WaterRegion],
) -> VehicleMotion {
    let target = if input.back {
        0.0
    } else if input.forward {
        32.0
    } else {
        0.0
    };
    let rate = if input.back {
        8.0
    } else if input.forward {
        6.0
    } else {
        1.0
    };
    state.speed += (target - state.speed).clamp(-rate * dt, rate * dt);
    state.speed = state.speed.clamp(0.0, 32.0);
    let turn = (i32::from(input.right) - i32::from(input.left)) as f32;
    let angular = turn * 0.85 * (state.speed / 5.0).clamp(0.0, 1.0) / (1.0 + state.speed * 0.02);
    let steps = (((state.speed.abs() + state.vy.abs()) * dt / 0.1).ceil() as usize).clamp(4, 32);
    let step = dt / steps as f32;
    for _ in 0..steps {
        let yaw = crate::movement::normalize_yaw(state.yaw + angular * step);
        let mut next = state.position;
        next[0] += yaw.cos() * state.speed * step;
        next[2] += yaw.sin() * state.speed * step;
        let water_level = surface_at(water, next[0], next[2]).map(|(level, _)| level);
        let ground = arena.support_height(next[0], next[2], state.position[1] + 0.3);
        if state.speed >= 12.0 {
            let target_vy = (i32::from(input.brake) - i32::from(input.descend)) as f32 * 6.0;
            state.vy += (target_vy - state.vy).clamp(-8.0 * step, 8.0 * step);
        } else {
            state.vy -= GRAVITY * step;
        }
        next[1] += state.vy * step;
        if next[1] > FLIGHT_CEILING {
            next[1] = FLIGHT_CEILING;
            state.vy = state.vy.min(0.0);
        }
        if let Some(level) = water_level {
            if next[1] <= level + 0.1 {
                // A zero-speed surface contact is an unambiguous crash marker.
                next[1] = level;
                state.position = next;
                state.speed = 0.0;
                state.vy = 0.0;
                break;
            }
        } else if next[1] <= ground {
            if state.vy < -4.0 {
                state.speed = 0.0;
            }
            next[1] = ground;
            state.vy = 0.0;
        }
        if !clear_kind(VehicleKind::LightAircraft, next, yaw, arena) {
            state.speed = 0.0;
            break;
        }
        state.position = next;
        state.yaw = yaw;
    }
    state
}
