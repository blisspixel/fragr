//! Deterministic arcade jeep movement and the one server-owned vehicle body.
//! The pure step is mirrored by the client before local driving prediction.

use crate::movement::{Arena, Solid, CONTACT_EPSILON, GRAVITY};
use crate::protocol::{VehicleKind, VehicleSeat, VehicleState};
use serde::{Deserialize, Serialize};
use uuid::Uuid;
#[cfg(test)]
mod tests;
mod water_air;
pub use water_air::{surface_at, vehicle_step_kind, BOAT_DRAFT, FLIGHT_CEILING};

pub const HALF_LENGTH: f32 = 1.9;
pub const HALF_WIDTH: f32 = 0.95;
pub const BODY_TOP: f32 = 1.35;
/// The exposed gunner uses the ordinary standing hit body above its seat.
pub const CLEARANCE_HEIGHT: f32 = 2.75;
pub const TOP_SPEED: f32 = 16.0;
pub const REVERSE_SPEED: f32 = 6.0;
pub const ENTRY_SPEED: f32 = 2.0;
pub const BURN_TICKS: u32 = 40;
pub const SWITCH_TICKS: u64 = 10;

pub fn spawns(map_id: u32) -> Vec<(VehicleKind, [f32; 3], f32)> {
    match map_id {
        7 => vec![
            (
                VehicleKind::Jeep,
                [-110.0, 3.0, 70.0],
                -std::f32::consts::FRAC_PI_2,
            ),
            (
                VehicleKind::Jeep,
                [110.0, 3.0, 70.0],
                -std::f32::consts::FRAC_PI_2,
            ),
            (VehicleKind::Jeep, [0.0, 3.0, -116.0], 0.0),
            (
                VehicleKind::Boat,
                [-58.0, 2.2, 75.0],
                std::f32::consts::FRAC_PI_2,
            ),
            (
                VehicleKind::Boat,
                [58.0, 2.2, 75.0],
                std::f32::consts::FRAC_PI_2,
            ),
            (
                VehicleKind::LightAircraft,
                [0.0, 3.0, -105.0],
                std::f32::consts::FRAC_PI_2,
            ),
        ],
        _ => Vec::new(),
    }
}

pub(crate) fn ray_hit(
    state: &VehicleState,
    ray: crate::combat::Ray,
    range: f32,
) -> Option<crate::combat::SurfaceHit> {
    let [length, width, height] = dimensions(state.kind);
    let (sin, cos) = state.yaw.sin_cos();
    let dx = ray.origin[0] - state.position[0];
    let dz = ray.origin[2] - state.position[2];
    let local = crate::combat::Ray {
        origin: [
            dx * cos + dz * sin,
            ray.origin[1] - state.position[1],
            -dx * sin + dz * cos,
        ],
        direction: [
            ray.direction[0] * cos + ray.direction[2] * sin,
            ray.direction[1],
            -ray.direction[0] * sin + ray.direction[2] * cos,
        ],
    };
    let mut hit = local.solid(
        &Solid {
            min_x: -length,
            max_x: length,
            min_z: -width,
            max_z: width,
            bottom: 0.0,
            top: height,
        },
        range,
    )?;
    hit.normal = [
        hit.normal[0] * cos - hit.normal[2] * sin,
        hit.normal[1],
        hit.normal[0] * sin + hit.normal[2] * cos,
    ];
    Some(hit)
}

#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
pub struct VehicleMotion {
    pub position: [f32; 3],
    pub yaw: f32,
    pub speed: f32,
    pub vy: f32,
}

#[derive(Debug, Clone, Copy, Default, Serialize, Deserialize)]
pub struct VehicleInput {
    pub forward: bool,
    pub back: bool,
    pub left: bool,
    pub right: bool,
    pub brake: bool,
    #[serde(default)]
    pub descend: bool,
}

#[derive(Debug, Clone)]
pub struct Jeep {
    pub state: VehicleState,
    pub spawn: VehicleMotion,
    pub gun_ready: u64,
    pub overheated: bool,
    pub last_attacker: Option<Uuid>,
    pub abandoned_ticks: u32,
}

impl Jeep {
    pub fn new(id: u32, position: [f32; 3], yaw: f32) -> Self {
        Self::of_kind(id, VehicleKind::Jeep, position, yaw)
    }

    pub fn of_kind(id: u32, kind: VehicleKind, position: [f32; 3], yaw: f32) -> Self {
        let yaw = crate::movement::normalize_yaw(yaw);
        Self {
            state: VehicleState {
                id,
                kind,
                position,
                yaw,
                speed: 0.0,
                vy: 0.0,
                hp: 400,
                driver: None,
                gunner: None,
                gun_heat: 0.0,
                burning_ticks: 0,
                control_ready_tick: 0,
            },
            spawn: VehicleMotion {
                position,
                yaw,
                speed: 0.0,
                vy: 0.0,
            },
            gun_ready: 0,
            overheated: false,
            last_attacker: None,
            abandoned_ticks: 0,
        }
    }

    pub fn motion(&self) -> VehicleMotion {
        VehicleMotion {
            position: self.state.position,
            yaw: self.state.yaw,
            speed: self.state.speed,
            vy: self.state.vy,
        }
    }

    pub fn apply_motion(&mut self, motion: VehicleMotion) {
        self.state.position = motion.position;
        self.state.yaw = motion.yaw;
        self.state.speed = motion.speed;
        self.state.vy = motion.vy;
    }

    pub fn occupant(&self, seat: VehicleSeat) -> Option<Uuid> {
        match seat {
            VehicleSeat::Driver => self.state.driver,
            VehicleSeat::Gunner => self.state.gunner,
        }
    }

    pub fn assign(&mut self, seat: VehicleSeat, occupant: Option<Uuid>) {
        match seat {
            VehicleSeat::Driver => self.state.driver = occupant,
            VehicleSeat::Gunner => self.state.gunner = occupant,
        }
    }

    pub fn release(&mut self, id: Uuid) {
        if self.state.driver == Some(id) {
            self.state.driver = None;
        }
        if self.state.gunner == Some(id) {
            self.state.gunner = None;
        }
    }

    pub fn cool(&mut self) {
        self.state.gun_heat = (self.state.gun_heat - 0.0125).max(0.0);
        if self.state.gun_heat <= 0.25 {
            self.overheated = false;
        }
    }

    pub fn fire(&mut self, tick: u64) -> bool {
        if self.state.hp <= 0
            || self.overheated
            || tick < self.gun_ready
            || tick < self.state.control_ready_tick
        {
            return false;
        }
        self.gun_ready = tick + 4;
        self.state.gun_heat = (self.state.gun_heat + 0.15).min(1.0);
        self.overheated = self.state.gun_heat >= 1.0;
        true
    }

    pub fn damage(&mut self, amount: i32, attacker: Option<Uuid>) {
        if amount <= 0 || self.state.hp <= 0 {
            return;
        }
        self.last_attacker = attacker.or(self.last_attacker);
        self.state.hp = self.state.hp.saturating_sub(amount).max(0);
        if self.state.hp == 0 {
            self.state.burning_ticks = BURN_TICKS;
            self.state.speed = 0.0;
        }
    }
}

pub fn seat_feet(state: &VehicleState, seat: VehicleSeat) -> [f32; 3] {
    let local = match (state.kind, seat) {
        (VehicleKind::Jeep, VehicleSeat::Driver) => [0.20, 0.65, -0.40],
        (VehicleKind::Jeep, VehicleSeat::Gunner) => [-0.65, 0.95, 0.0],
        (VehicleKind::Boat, VehicleSeat::Driver) => [-0.2, 0.65, -0.4],
        (VehicleKind::Boat, VehicleSeat::Gunner) => [-1.0, 0.95, 0.0],
        (VehicleKind::LightAircraft, _) => [1.45, 0.80, 0.0],
    };
    local_point(state.position, state.yaw, local)
}

pub fn local_point(position: [f32; 3], yaw: f32, local: [f32; 3]) -> [f32; 3] {
    let (sin, cos) = yaw.sin_cos();
    [
        position[0] + local[0] * cos - local[2] * sin,
        position[1] + local[1],
        position[2] + local[0] * sin + local[2] * cos,
    ]
}

pub fn hull(state: &VehicleState) -> Solid {
    let [length, span, height] = dimensions(state.kind);
    let width = state.yaw.cos().abs() * length + state.yaw.sin().abs() * span;
    let depth = state.yaw.sin().abs() * length + state.yaw.cos().abs() * span;
    Solid {
        min_x: state.position[0] - width,
        max_x: state.position[0] + width,
        min_z: state.position[2] - depth,
        max_z: state.position[2] + depth,
        bottom: state.position[1],
        top: state.position[1] + height,
    }
}

/// Half length, half width, shot-box height, in metres.
pub fn dimensions(kind: VehicleKind) -> [f32; 3] {
    match kind {
        VehicleKind::Jeep => [HALF_LENGTH, HALF_WIDTH, BODY_TOP],
        VehicleKind::Boat => [2.4, 1.1, 1.6],
        VehicleKind::LightAircraft => [4.0, 4.6, 1.8],
    }
}

pub fn supports_seat(kind: VehicleKind, seat: VehicleSeat) -> bool {
    kind != VehicleKind::LightAircraft || seat == VehicleSeat::Driver
}

pub fn entry_radius(kind: VehicleKind) -> f32 {
    if kind == VehicleKind::LightAircraft {
        6.0
    } else {
        2.0
    }
}

pub fn clear_kind(kind: VehicleKind, position: [f32; 3], yaw: f32, arena: &Arena) -> bool {
    if kind == VehicleKind::Jeep {
        return clear_body(position, yaw, arena);
    }
    if !position.iter().all(|v| v.is_finite()) || !yaw.is_finite() {
        return false;
    }
    let [length, width, _] = dimensions(kind);
    let (sin, cos) = yaw.sin_cos();
    let extent_x = cos.abs() * length + sin.abs() * width;
    let extent_z = sin.abs() * length + cos.abs() * width;
    if position[0].abs() + extent_x > arena.half || position[2].abs() + extent_z > arena.half {
        return false;
    }
    let bottom = if kind == VehicleKind::Boat {
        position[1] - BOAT_DRAFT
    } else {
        position[1] + 0.3
    };
    !arena.solids.iter().any(|s| {
        s.top > bottom + CONTACT_EPSILON
            && s.bottom < position[1] + CLEARANCE_HEIGHT - CONTACT_EPSILON
            && s.max_x > position[0] - extent_x
            && s.min_x < position[0] + extent_x
            && s.max_z > position[2] - extent_z
            && s.min_z < position[2] + extent_z
    })
}

/// Conservative three-circle body, checked every 0.1 m and every small yaw
/// increment. A thin wall cannot be crossed by a fast single 20 Hz step.
pub fn clear_body(position: [f32; 3], yaw: f32, arena: &Arena) -> bool {
    if !position.iter().all(|v| v.is_finite()) || !yaw.is_finite() {
        return false;
    }
    [-0.95, 0.0, 0.95].into_iter().all(|offset| {
        let p = local_point(position, yaw, [offset, 0.0, 0.0]);
        p[0].abs() <= arena.half - HALF_WIDTH
            && p[2].abs() <= arena.half - HALF_WIDTH
            && !arena.solids.iter().any(|solid| {
                solid.top > p[1] + 0.3 + CONTACT_EPSILON
                    && solid.bottom < p[1] + CLEARANCE_HEIGHT - CONTACT_EPSILON
                    && solid.blocks(p[0], p[2], HALF_WIDTH)
            })
    })
}

pub fn vehicle_step(
    mut state: VehicleMotion,
    input: VehicleInput,
    dt: f32,
    arena: &Arena,
) -> VehicleMotion {
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
    let throttle = i32::from(input.forward) - i32::from(input.back);
    let target = if throttle > 0 {
        TOP_SPEED
    } else if throttle < 0 {
        -REVERSE_SPEED
    } else {
        0.0
    };
    let rate = if input.brake {
        30.0
    } else if throttle == 0 {
        5.0
    } else if state.speed * (throttle as f32) < 0.0 {
        18.0
    } else {
        8.0
    };
    let target = if input.brake { 0.0 } else { target };
    state.speed += (target - state.speed).clamp(-rate * dt, rate * dt);
    state.speed = state.speed.clamp(-REVERSE_SPEED, TOP_SPEED);
    let turn = (i32::from(input.right) - i32::from(input.left)) as f32;
    let angular =
        turn * 1.5 * (state.speed / 4.0).clamp(-1.0, 1.0) / (1.0 + state.speed.abs() * 0.07);
    let steps = ((state.speed.abs() * dt / 0.1).ceil() as usize).max(4);
    let step = dt / steps as f32;
    for _ in 0..steps {
        let yaw = crate::movement::normalize_yaw(state.yaw + angular * step);
        let mut candidate = state.position;
        candidate[0] += yaw.cos() * state.speed * step;
        candidate[2] += yaw.sin() * state.speed * step;
        let support = [-0.95, 0.0, 0.95]
            .into_iter()
            .map(|offset| {
                let p = local_point(candidate, yaw, [offset, 0.0, 0.0]);
                arena.support_height(p[0], p[2], state.position[1] + 0.3)
            })
            .fold(0.0_f32, f32::max);
        state.vy -= GRAVITY * step;
        candidate[1] += state.vy * step;
        if candidate[1] <= support {
            candidate[1] = support;
            state.vy = 0.0;
        }
        if clear_body(candidate, yaw, arena) {
            state.position = candidate;
            state.yaw = yaw;
        } else {
            state.speed = 0.0;
            break;
        }
    }
    state
}
