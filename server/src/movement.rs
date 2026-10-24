//! Shared body integration and the two input steps, mirrored in
//! `client/scripts/movement.gd`. Arena participants move with `fighter_step`:
//! persistent velocity, friction, ground and air acceleration, the dodge.
//! Campaign bodies, the participant included, and authored actors keep
//! `live_step`, which sets horizontal velocity at once (`GameState::arena_feel`
//! chooses).
//! Pure data in, pure data out, with no engine calls or randomness.
//!
//! The fighter model has two golden files, one at the live 20 Hz step and one
//! at 60 Hz. This module generates them, its tests assert the committed files
//! still match, and the headless Godot harness checks the GDScript mirror
//! within a tolerance. Change the model, regenerate the vectors, and review
//! the diff like code.

use serde::{Deserialize, Serialize};
use std::f32::consts::PI;

pub mod contact;
pub mod water;

#[cfg(test)]
mod enclosed_tests;

// Fighter feel, frozen 2026-10-23 (docs/plans/feel-pass-20261023.md).
// Nick's decision: arena speed and air control with Counter-Strike crisp
// starts and stops. The formulas are Quake 3's and Source's (friction drop of
// max(speed, STOP_SPEED) * FRICTION * dt, accelerate toward the wish speed by
// at most ACCEL * dt * wishspeed along the wish direction). The values are
// ours, chosen for a 20 Hz step: one tick reaches three quarters of top speed,
// three ticks reach all of it, a released key rests within three ticks (a
// 0.17 m slide), and a counter-strafe stops and reverses in one. The client
// mirror and both golden files record every constant in this block, and
// docs/protocol.md "Movement" lists them with their meaning.

/// Ground top speed in metres per second. Counter-Strike's knife is 6.35,
/// Quake 3 is 8.13; the arena maps were built around 5.
pub const TOP_SPEED: f32 = 6.0;
/// Ground acceleration, per second, scaled by the wish speed.
pub const GROUND_ACCEL: f32 = 15.0;
/// Ground friction, per second. Quake 3 uses 6 and CS:GO 5.2 at far higher
/// step rates; a 20 Hz step needs more to stop as crisply.
pub const FRICTION: f32 = 12.0;
/// Below this speed friction acts as if moving this fast, so the last of a
/// slide ends at once rather than creeping. Kept under the crouch walk (2.04)
/// so a crouched fighter still reaches its pace in three ticks; at 2.5 the
/// floor's grip ate nearly all of the crouch's acceleration.
pub const STOP_SPEED: f32 = 2.0;
/// Air acceleration, per second, scaled by the wish speed. Quake 3 uses 1.
/// Twice that steers a jump and lets a turning strafe gain a little speed.
pub const AIR_ACCEL: f32 = 2.0;
/// Air acceleration never pushes horizontal speed past this. Faster momentum
/// from a blast is kept, never added to.
pub const AIR_SPEED_CAP: f32 = 7.5;
/// Ground dodge: a grounded fighter with a direction held and the dodge key
/// pressed is thrown that way at this horizontal speed, half again top speed
/// (Unreal Tournament's ratio), on a low hop.
pub const DODGE_SPEED: f32 = 9.0;
/// The dodge hop's upward speed: about 0.3 s in the air and 2.9 m covered.
pub const DODGE_UP: f32 = 3.5;
/// Server ticks before another dodge is allowed. The caller owns the count
/// (it rides in the movement Ack) so the pure step stays stateless.
pub const DODGE_COOLDOWN_TICKS: u32 = 15;
/// The campaign pace. Authored actors' gaits are shares of it, and a campaign
/// participant keeps the immediate step at it, so the arena's faster run does
/// not change an encounter its route proofs were tuned against.
pub const ACTOR_REFERENCE_SPEED: f32 = 5.0;
/// Fighter collision radius in units.
pub const RADIUS: f32 = 0.5;
/// The movement step length at the 60 Hz rate the tick migration adopts.
pub const DT_60HZ: f32 = 1.0 / 60.0;
/// Current authoritative movement step length. Keep separate from the
/// proposed 60 Hz movement rate and its accelerated golden vectors.
pub const DT_LIVE: f32 = 1.0 / 20.0;
/// The base floor. Solids stand on it and a fighter with nothing under it
/// falls back to it, so it is the bottom of the heightfield rather than the
/// only ground there is.
pub const GROUND_Y: f32 = 0.0;
/// How far a fighter climbs or drops without leaving the ground. Quake's step
/// height scaled to a 1.8 metre fighter, which is what makes a staircase feel
/// like walking rather than a sequence of small jumps.
pub const STEP_UP: f32 = 0.6;
/// Contact tolerance, 0.1 mm, for feet reconstructed from a reference-height
/// snapshot. Exact comparisons can lose a fractional-height stair surface.
pub const CONTACT_EPSILON: f32 = 0.0001;
/// The top a solid gets when nobody says otherwise: higher than a jump can
/// reach, so it is a wall. Every solid written before the heightfield existed
/// means this, which is why it is also the wire default.
pub const WALL_TOP: f32 = 4.5;
/// How far above its feet a fighter's shot line sits. A solid lower than the
/// line between two fighters does not block the shot between them.
pub const EYE_HEIGHT: f32 = 1.6;
/// Full standing body height, shared by clearance and shot targets.
pub const BODY_HEIGHT: f32 = 1.8;
/// Crouch clearance. Three quarters of a standing fighter, the same hull
/// ratio Counter-Strike uses (54 of 72).
pub const DUCK_HEIGHT: f32 = 1.35;
/// The standing eye sits 0.2 m under the crown. The short body keeps that gap.
pub const DUCK_EYE_HEIGHT: f32 = 1.15;
/// Horizontal speed while the body is short, as a fraction of the chosen speed.
pub const DUCK_SPEED_SCALE: f32 = 0.34;
pub const MAX_HALF_EXTENT: f32 = 256.0;
pub const MAX_SOLIDS: usize = 2048;
/// Downward acceleration in units per second squared. With the jump below,
/// the live 20 Hz step clears 1.3 units and lands 0.7 s later (1.1 units at
/// fine steps): a Quake-ish arc rather than a floaty one.
pub const GRAVITY: f32 = 22.0;
/// Upward speed applied on a jump, in units per second.
pub const JUMP_SPEED: f32 = 7.0;

/// Where a fighter is and how it moves. Yaw is radians in `[0, 2 pi)`.
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
pub struct MoveState {
    pub x: f32,
    pub z: f32,
    /// Height above the floor. Zero is standing on it.
    #[serde(default)]
    pub y: f32,
    pub vx: f32,
    pub vz: f32,
    /// Vertical speed. Positive is upward.
    #[serde(default)]
    pub vy: f32,
    pub yaw: f32,
}

impl MoveState {
    /// Whether this fighter is standing on the base floor. Kept for the flat
    /// case; the step itself asks the arena what is under the fighter, which
    /// is a deck top as often as it is the floor.
    pub fn grounded(&self) -> bool {
        self.y <= GROUND_Y && self.vy <= 0.0
    }
}

/// One step's worth of intent. `speed_scale` is 1.0 normally and 0.5 under
/// the compliance slow; `yaw` is the client-owned facing for this step.
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
pub struct MoveInput {
    #[serde(default)]
    pub forward: bool,
    #[serde(default)]
    pub back: bool,
    #[serde(default)]
    pub left: bool,
    #[serde(default)]
    pub right: bool,
    /// Held, not edge-triggered. A fighter leaves the ground on the first step
    /// where this is set and it is standing, and holding it does not keep it
    /// climbing, so a client that drops an input does not lose a jump it has
    /// already started.
    #[serde(default)]
    pub jump: bool,
    /// Ground dodge this step. The caller has already applied the cooldown.
    #[serde(default, skip_serializing_if = "is_false")]
    pub dodge: bool,
    pub yaw: f32,
    #[serde(default = "one")]
    pub speed_scale: f32,
}

fn is_false(value: &bool) -> bool {
    !*value
}

fn one() -> f32 {
    1.0
}

impl Default for MoveInput {
    fn default() -> Self {
        MoveInput {
            forward: false,
            back: false,
            left: false,
            right: false,
            jump: false,
            dodge: false,
            yaw: 0.0,
            speed_scale: 1.0,
        }
    }
}

/// An axis-aligned solid with an XZ footprint and explicit vertical bounds.
/// An omitted bottom preserves legacy ground-filled walls and steps.
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
pub struct Solid {
    pub min_x: f32,
    pub max_x: f32,
    pub min_z: f32,
    pub max_z: f32,
    #[serde(default, skip_serializing_if = "is_ground")]
    pub bottom: f32,
    /// Height of the walkable upper surface. Defaulted rather than required so
    /// that every solid written before the heightfield existed keeps meaning a
    /// wall, on the wire and in the committed golden vectors alike.
    #[serde(default = "wall_top")]
    pub top: f32,
}

fn wall_top() -> f32 {
    WALL_TOP
}

fn is_ground(height: &f32) -> bool {
    *height == GROUND_Y
}

impl Solid {
    /// A wall: tall enough that nothing walks or jumps onto it.
    pub fn from_center(cx: f32, cz: f32, half_x: f32, half_z: f32) -> Self {
        Solid::from_center_top(cx, cz, half_x, half_z, WALL_TOP)
    }

    /// A solid whose upper surface is at `top`. Below `STEP_UP` it is a step,
    /// below a jump's reach it is a ledge, above that it is a wall.
    pub fn from_center_top(cx: f32, cz: f32, half_x: f32, half_z: f32, top: f32) -> Self {
        Self::from_center_volume(cx, cz, half_x, half_z, GROUND_Y, top)
    }

    pub fn from_center_volume(
        cx: f32,
        cz: f32,
        half_x: f32,
        half_z: f32,
        bottom: f32,
        top: f32,
    ) -> Self {
        Solid {
            min_x: cx - half_x,
            max_x: cx + half_x,
            min_z: cz - half_z,
            max_z: cz + half_z,
            bottom,
            top,
        }
    }

    /// True when a circle of `radius` at `(x, z)` overlaps this solid.
    pub fn blocks(&self, x: f32, z: f32, radius: f32) -> bool {
        x >= self.min_x - radius
            && x <= self.max_x + radius
            && z >= self.min_z - radius
            && z <= self.max_z + radius
    }

    /// A fall may lower the feet while the body still overlaps a ledge's
    /// inflated footprint. Permit escape through its nearest face, never deeper
    /// penetration, so leaving a deck cannot trap the fighter against its side.
    pub fn blocks_motion(&self, from: (f32, f32), to: (f32, f32), radius: f32) -> bool {
        if !self.blocks(to.0, to.1, radius) {
            return false;
        }
        if !self.blocks(from.0, from.1, radius) {
            return true;
        }
        let depths = [
            from.0 - (self.min_x - radius),
            self.max_x + radius - from.0,
            from.1 - (self.min_z - radius),
            self.max_z + radius - from.1,
        ];
        let nearest = depths.into_iter().fold(f32::INFINITY, f32::min);
        !((depths[0] == nearest && to.0 < from.0)
            || (depths[1] == nearest && to.0 > from.0)
            || (depths[2] == nearest && to.1 < from.1)
            || (depths[3] == nearest && to.1 > from.1))
    }

    /// True when the point itself is over this solid. Standing on a deck uses
    /// the point rather than the inflated box, so a fighter is held up by what
    /// is under its feet rather than by what is beside it.
    pub fn covers(&self, x: f32, z: f32) -> bool {
        x >= self.min_x && x <= self.max_x && z >= self.min_z && z <= self.max_z
    }
}

/// The playable square of half-width `half` (centre at the origin) and its solids.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Arena {
    pub half: f32,
    pub solids: Vec<Solid>,
}

/// Shared bounds for wire geometry and topology, checked before allocation of
/// derived meshes or routes. Navigation applies additional construction limits.
pub fn validate_geometry(half: f32, solids: &[Solid]) -> Result<(), &'static str> {
    if !half.is_finite() || !(2.0..=MAX_HALF_EXTENT).contains(&half) {
        return Err("geometry extent must be finite and between 2 and 256 metres");
    }
    if solids.len() > MAX_SOLIDS {
        return Err("geometry solid limit exceeded");
    }
    for solid in solids {
        if [
            solid.min_x,
            solid.max_x,
            solid.min_z,
            solid.max_z,
            solid.bottom,
            solid.top,
        ]
        .iter()
        .any(|value| !value.is_finite() || value.abs() > MAX_HALF_EXTENT * 2.0)
            || solid.min_x >= solid.max_x
            || solid.min_z >= solid.max_z
            || solid.bottom < 0.0
            || solid.top <= solid.bottom
        {
            return Err("invalid solid bounds");
        }
    }
    Ok(())
}

impl Arena {
    /// Blocked for a fighter standing on the base floor. The flat-arena
    /// question, kept because plenty of callers only ever ask it.
    pub fn blocked(&self, x: f32, z: f32) -> bool {
        self.blocked_at(x, z, GROUND_Y + STEP_UP)
    }

    /// Grounded clearance, with feet one step below `climb`. Airborne callers
    /// supply their actual foot height through `blocked_body_at`.
    pub fn blocked_at(&self, x: f32, z: f32, climb: f32) -> bool {
        self.blocked_body_at(x, z, climb - STEP_UP, climb)
    }

    pub fn blocked_body_at(&self, x: f32, z: f32, feet: f32, climb: f32) -> bool {
        self.blocked_body_at_height(x, z, feet, climb, BODY_HEIGHT)
    }

    pub fn blocked_body_at_height(
        &self,
        x: f32,
        z: f32,
        feet: f32,
        climb: f32,
        height: f32,
    ) -> bool {
        self.solids.iter().any(|s| {
            s.top > climb && s.bottom < feet + height - CONTACT_EPSILON && s.blocks(x, z, RADIUS)
        })
    }

    /// Grounded route probe; live movement supplies its actual foot height.
    pub fn blocked_motion(&self, from: (f32, f32), to: (f32, f32), climb: f32) -> bool {
        self.blocked_body_motion(from, to, climb - STEP_UP, climb, true)
    }

    /// Check headroom at the height the body would reach after an automatic
    /// step. A step beneath a low ceiling must fail before changing position.
    pub fn blocked_body_motion(
        &self,
        from: (f32, f32),
        to: (f32, f32),
        feet: f32,
        climb: f32,
        was_grounded: bool,
    ) -> bool {
        self.blocked_body_motion_height(from, to, feet, climb, was_grounded, BODY_HEIGHT)
    }

    pub fn blocked_body_motion_height(
        &self,
        from: (f32, f32),
        to: (f32, f32),
        feet: f32,
        climb: f32,
        was_grounded: bool,
        height: f32,
    ) -> bool {
        let support = self.support_height(to.0, to.1, climb);
        let next_feet = if was_grounded && feet - support <= STEP_UP {
            support
        } else {
            feet
        };
        self.solids.iter().any(|solid| {
            solid.top > climb
                && solid.bottom < next_feet + height - CONTACT_EPSILON
                && if solid.bottom >= feet + height - CONTACT_EPSILON {
                    // The old body was below this slab. Horizontal overlap is
                    // not permission to step upward through its underside.
                    solid.blocks(to.0, to.1, RADIUS)
                } else {
                    solid.blocks_motion(from, to, RADIUS)
                }
        })
    }

    /// Lowest underside above the current head, including radius overlap at an
    /// edge. Swept upward motion stops here even if one tick crosses the slab.
    pub fn ceiling_height(&self, x: f32, z: f32, feet: f32) -> f32 {
        self.ceiling_height_for_body(x, z, feet, BODY_HEIGHT)
    }

    /// True when a body of `height` at `feet` does not intersect a solid.
    pub fn fits_height(&self, x: f32, z: f32, feet: f32, height: f32) -> bool {
        !self.blocked_body_at_height(x, z, feet, feet, height)
    }

    pub fn ceiling_height_for_body(&self, x: f32, z: f32, feet: f32, height: f32) -> f32 {
        self.solids
            .iter()
            .filter(|solid| {
                solid.bottom >= feet + height - CONTACT_EPSILON && solid.blocks(x, z, RADIUS)
            })
            .map(|solid| solid.bottom)
            .fold(f32::INFINITY, f32::min)
    }

    /// The highest surface at `(x, z)` that is no higher than `ceiling`, or the
    /// base floor when nothing qualifies. This is the floor the fighter is
    /// standing on.
    pub fn support_height(&self, x: f32, z: f32, ceiling: f32) -> f32 {
        let mut best = GROUND_Y;
        for s in &self.solids {
            if s.top <= ceiling + CONTACT_EPSILON && s.top > best && s.covers(x, z) {
                best = s.top;
            }
        }
        best
    }

    pub fn clamp(&self, x: f32, z: f32) -> (f32, f32) {
        let limit = self.half - RADIUS;
        (x.clamp(-limit, limit), z.clamp(-limit, limit))
    }
}

/// How high a fighter at `feet` with floor `floor` under it can climb this
/// step. Standing, it is a step above the floor; airborne, it is wherever the
/// feet are, so a jump clears exactly what it rises over and no more.
pub fn climb_height(feet: f32, floor: f32, vy: f32) -> f32 {
    if grounded(feet, floor, vy) {
        floor + STEP_UP
    } else {
        feet
    }
}

pub fn grounded(feet: f32, floor: f32, vy: f32) -> bool {
    feet <= floor + CONTACT_EPSILON && vy <= 0.0
}

/// Held key, or already short under a ceiling that will not take the standing body.
pub fn ducked_stance(want: bool, was: bool, fits_standing: bool) -> bool {
    want || (was && !fits_standing)
}

/// Wrap any finite yaw into `[0, 2 pi)`. Non-finite yaw becomes 0.
pub fn normalize_yaw(yaw: f32) -> f32 {
    if !yaw.is_finite() {
        return 0.0;
    }
    let two_pi = 2.0 * PI;
    let mut y = yaw % two_pi;
    if y < 0.0 {
        y += two_pi;
    }
    if y >= two_pi {
        y -= two_pi;
    }
    y
}

/// Unit direction of the movement keys in the yaw frame, or zero.
pub fn wish_dir(input: &MoveInput, yaw: f32) -> (f32, f32) {
    let mut dx = 0.0f32;
    let mut dz = 0.0f32;
    if input.forward {
        dx += yaw.cos();
        dz += yaw.sin();
    }
    if input.back {
        dx -= yaw.cos();
        dz -= yaw.sin();
    }
    if input.left {
        dx += (yaw - PI / 2.0).cos();
        dz += (yaw - PI / 2.0).sin();
    }
    if input.right {
        dx += (yaw + PI / 2.0).cos();
        dz += (yaw + PI / 2.0).sin();
    }
    let len = (dx * dx + dz * dz).sqrt();
    if len > 0.0 {
        (dx / len, dz / len)
    } else {
        (0.0, 0.0)
    }
}

/// The authored-actor step. `speed` is the effective units-per-second speed
/// already chosen by the simulation, including its gait modifiers.
/// Horizontal velocity changes at once; no acceleration is applied. The
/// caller supplies the yaw selected for this server tick and owns jump-edge
/// latching and the world-y/feet conversion. Participants use `fighter_step`.
pub fn live_step(
    state: MoveState,
    input: &MoveInput,
    speed: f32,
    dt: f32,
    arena: &Arena,
) -> MoveState {
    live_step_with_height(state, input, speed, dt, arena, BODY_HEIGHT)
}

/// The live movement step with an authored actor's collision height. Ordinary
/// fighters use `live_step` and the same default-height collision path.
pub fn live_step_with_height(
    state: MoveState,
    input: &MoveInput,
    speed: f32,
    dt: f32,
    arena: &Arena,
    height: f32,
) -> MoveState {
    let yaw = normalize_yaw(input.yaw);
    let (wx, wz) = wish_dir(input, yaw);
    integrate_with_height(
        MoveState {
            vx: wx * speed,
            vz: wz * speed,
            yaw,
            ..state
        },
        input.jump,
        dt,
        arena,
        height,
    )
}

/// One participant step of `dt` seconds at wish speed `speed` (already scaled
/// for compliance and crouch by the caller; `input.speed_scale` scales it
/// again for the 60 Hz vectors). The order is the contract the GDScript
/// mirror keeps: yaw and wish; grounded test on the old position; ground
/// friction unless jumping; ground acceleration when grounded and not
/// jumping, otherwise capped air acceleration; then `integrate`, which owns
/// collision, the blocked-axis velocity, step, jump, gravity and landing.
///
/// A jump on the landing step skips friction and accelerates as in the air,
/// as Quake's `PM_WalkMove` hands a jump to `PM_AirMove`. That keeps a held
/// jump's speed without letting the ground's large acceleration add to it.
pub fn fighter_step(
    state: MoveState,
    input: &MoveInput,
    speed: f32,
    dt: f32,
    arena: &Arena,
) -> MoveState {
    fighter_step_with_height(state, input, speed, dt, arena, BODY_HEIGHT)
}

pub fn fighter_step_with_height(
    state: MoveState,
    input: &MoveInput,
    speed: f32,
    dt: f32,
    arena: &Arena,
    height: f32,
) -> MoveState {
    let yaw = normalize_yaw(input.yaw);
    let wish = wish_dir(input, yaw);
    let scale = if input.speed_scale.is_finite() {
        input.speed_scale.clamp(0.0, 1.0)
    } else {
        1.0
    };
    let wish_speed = if speed.is_finite() {
        speed.max(0.0) * scale
    } else {
        0.0
    };
    let dt = if dt.is_finite() { dt.max(0.0) } else { 0.0 };
    let mut velocity = if state.vx.is_finite() && state.vz.is_finite() {
        (state.vx, state.vz)
    } else {
        (0.0, 0.0)
    };
    let floor = arena.support_height(state.x, state.z, state.y);
    let on_floor = grounded(state.y, floor, state.vy);
    let mut launch = input.jump.then_some(JUMP_SPEED);
    if on_floor && input.dodge && wish != (0.0, 0.0) {
        velocity = (wish.0 * DODGE_SPEED, wish.1 * DODGE_SPEED);
        launch = Some(DODGE_UP);
    } else if on_floor && !input.jump {
        velocity = friction(velocity, dt);
        velocity = accelerate(velocity, wish, wish_speed, GROUND_ACCEL, dt);
    } else {
        let before = velocity.0.hypot(velocity.1);
        velocity = accelerate(velocity, wish, wish_speed, AIR_ACCEL, dt);
        let limit = before.max(AIR_SPEED_CAP);
        let after = velocity.0.hypot(velocity.1);
        if after > limit {
            velocity = (velocity.0 * limit / after, velocity.1 * limit / after);
        }
    }
    launch_with_height(
        MoveState {
            vx: velocity.0,
            vz: velocity.1,
            yaw,
            ..state
        },
        launch,
        dt,
        arena,
        height,
    )
}

/// Whether `fighter_step` would dodge on this input from this state: standing,
/// a direction held, and the (cooldown-checked) dodge bit set. Callers use it
/// to start their cooldown.
pub fn dodge_applies(state: &MoveState, input: &MoveInput, arena: &Arena) -> bool {
    input.dodge
        && wish_dir(input, normalize_yaw(input.yaw)) != (0.0, 0.0)
        && grounded(
            state.y,
            arena.support_height(state.x, state.z, state.y),
            state.vy,
        )
}

/// Quake and Source ground friction: lose `max(speed, STOP_SPEED) *
/// FRICTION * dt`, never below rest.
pub fn friction(velocity: (f32, f32), dt: f32) -> (f32, f32) {
    let speed = velocity.0.hypot(velocity.1);
    if speed < 0.01 {
        return (0.0, 0.0);
    }
    let drop = speed.max(STOP_SPEED) * FRICTION * dt;
    let kept = (speed - drop).max(0.0) / speed;
    (velocity.0 * kept, velocity.1 * kept)
}

/// Quake and Source acceleration: add up to `accel * dt * wish_speed` along
/// the wish direction, but never past `wish_speed` measured along it.
pub fn accelerate(
    velocity: (f32, f32),
    wish: (f32, f32),
    wish_speed: f32,
    accel: f32,
    dt: f32,
) -> (f32, f32) {
    if wish == (0.0, 0.0) || wish_speed <= 0.0 {
        return velocity;
    }
    let current = velocity.0 * wish.0 + velocity.1 * wish.1;
    let room = wish_speed - current;
    if room <= 0.0 {
        return velocity;
    }
    let add = (accel * dt * wish_speed).min(room);
    (velocity.0 + wish.0 * add, velocity.1 + wish.1 * add)
}

/// Resolve an already chosen velocity against the map, then apply jumping and
/// gravity. The live server supplies immediate horizontal velocity; `step`
/// supplies accelerated velocity. Both use this collision and grounding path.
pub fn integrate(state: MoveState, jump: bool, dt: f32, arena: &Arena) -> MoveState {
    integrate_with_height(state, jump, dt, arena, BODY_HEIGHT)
}

/// Server-only body profile for low authored enemies. Participant movement
/// continues through `integrate` and its unchanged client mirror.
pub fn integrate_with_height(
    state: MoveState,
    jump: bool,
    dt: f32,
    arena: &Arena,
    height: f32,
) -> MoveState {
    launch_with_height(state, jump.then_some(JUMP_SPEED), dt, arena, height)
}

/// `integrate_with_height` with the upward speed a grounded body leaves the
/// floor at, if any: a jump's or a dodge's.
pub fn launch_with_height(
    state: MoveState,
    launch: Option<f32>,
    dt: f32,
    arena: &Arena,
    height: f32,
) -> MoveState {
    let mut vx = state.vx;
    let mut vz = state.vz;

    let old_x = state.x;
    let old_z = state.z;
    let (nx, nz) = arena.clamp(old_x + vx * dt, old_z + vz * dt);

    // What is under the fighter now, and therefore how high it can climb into
    // the next square. A deck one step up is walked onto; anything higher is a
    // wall until a jump puts the feet above it.
    let floor = arena.support_height(old_x, old_z, state.y);
    let was_grounded = grounded(state.y, floor, state.vy);
    let climb = climb_height(state.y, floor, state.vy);

    let blocked = |x, z| {
        arena.blocked_body_motion_height(
            (old_x, old_z),
            (x, z),
            state.y,
            climb,
            was_grounded,
            height,
        )
    };
    let (x, z) = if !blocked(nx, nz) {
        (nx, nz)
    } else if !blocked(nx, old_z) {
        vz = 0.0;
        (nx, old_z)
    } else if !blocked(old_x, nz) {
        vx = 0.0;
        (old_x, nz)
    } else {
        vx = 0.0;
        vz = 0.0;
        arena.clamp(old_x, old_z)
    };

    // Vertical, against the floor under where the fighter ended up. Stepping
    // up to a surface within `climb` snaps to it; stepping down by up to a
    // step snaps too, so a staircase is walked rather than fallen down; a
    // bigger drop is a fall on the ordinary gravity curve.
    let support = arena.support_height(x, z, climb);
    let mut vy = state.vy;
    let mut y = state.y;
    let on_ground = grounded(y, support, state.vy) || (was_grounded && y - support <= STEP_UP);
    if on_ground {
        y = support;
        vy = 0.0;
        if let Some(up) = launch {
            vy = up;
        }
    } else {
        vy -= GRAVITY * dt;
    }
    let ceiling = arena.ceiling_height_for_body(x, z, y, height);
    y += vy * dt;
    if vy > 0.0 && y + height > ceiling {
        y = ceiling - height;
        vy = 0.0;
    }
    // Swept landing: anything the fall passed through on the way down counts,
    // so a fighter that comes off a deck lands on the next one rather than
    // through it.
    let landing = arena.support_height(x, z, state.y.max(y));
    if y <= landing {
        y = landing;
        if vy < 0.0 {
            vy = 0.0;
        }
    }

    MoveState {
        x,
        z,
        y,
        vx,
        vz,
        vy,
        yaw: state.yaw,
    }
}

/// The fighter constants a golden file was generated with. Both files carry
/// them, and both test harnesses refuse vectors made with other values.
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
pub struct FeelConstants {
    pub radius: f32,
    pub top_speed: f32,
    pub ground_accel: f32,
    pub friction: f32,
    pub stop_speed: f32,
    pub air_accel: f32,
    pub air_speed_cap: f32,
    pub gravity: f32,
    pub jump_speed: f32,
    pub dodge_speed: f32,
    pub dodge_up: f32,
}

pub const FEEL: FeelConstants = FeelConstants {
    radius: RADIUS,
    top_speed: TOP_SPEED,
    ground_accel: GROUND_ACCEL,
    friction: FRICTION,
    stop_speed: STOP_SPEED,
    air_accel: AIR_ACCEL,
    air_speed_cap: AIR_SPEED_CAP,
    gravity: GRAVITY,
    jump_speed: JUMP_SPEED,
    dodge_speed: DODGE_SPEED,
    dodge_up: DODGE_UP,
};

/// One golden case: an arena, a start, a wish speed, inputs, and the state
/// expected after every `stride` steps (so a long case stays small on disk).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct GoldenCase {
    pub name: String,
    pub arena: Arena,
    pub start: MoveState,
    pub speed: f32,
    pub inputs: Vec<MoveInput>,
    pub stride: usize,
    pub expected: Vec<MoveState>,
}

/// A golden file: its step length, the constants, and the cases.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct GoldenFile {
    pub version: u32,
    pub dt: f32,
    pub constants: FeelConstants,
    pub cases: Vec<GoldenCase>,
}

pub const GOLDEN_VERSION: u32 = 3;
/// The fighter model at 60 Hz, shared with the Godot harness.
pub const GOLDEN_PATH: &str = "client/golden/move_vectors.json";
/// The fighter model at the live 20 Hz server step.
pub const LIVE_GOLDEN_PATH: &str = "client/golden/live_move_vectors.json";

fn golden_case(
    name: &str,
    arena: &Arena,
    start: MoveState,
    speed: f32,
    inputs: Vec<MoveInput>,
    stride: usize,
    dt: f32,
) -> GoldenCase {
    let mut state = start;
    let mut expected = Vec::new();
    for (i, input) in inputs.iter().enumerate() {
        state = fighter_step(state, input, speed, dt, arena);
        if (i + 1) % stride == 0 {
            expected.push(state);
        }
    }
    GoldenCase {
        name: name.to_string(),
        arena: arena.clone(),
        start,
        speed,
        inputs,
        stride,
        expected,
    }
}

/// Live 20 Hz vectors: start and stop, counter-strafe, yaw, collision,
/// height, jump, air steering, a turning strafe jump against the air cap, a
/// ground dodge, blast momentum above the cap, overhead clearance, compliance
/// and crouch speeds.
pub fn live_golden_cases() -> GoldenFile {
    let dt = DT_LIVE;
    let flat = Arena {
        half: 25.0,
        solids: Vec::new(),
    };
    let obstacle = golden_arena();
    let terrace = golden_terrace_arena();
    let ceiling = Arena {
        half: 12.0,
        solids: vec![Solid::from_center_volume(0.0, 0.0, 2.0, 2.0, 2.1, 3.0)],
    };
    let mut start_stop = hold(keys(true, false, false, false, 0.0), 6);
    start_stop.extend(hold(MoveInput::default(), 5));
    let mut counter = hold(keys(false, false, false, true, 0.0), 6);
    counter.extend(hold(keys(false, false, true, false, 0.0), 3));
    counter.extend(hold(MoveInput::default(), 4));
    let mut jump = hold(MoveInput::default(), 16);
    jump[0].jump = true;
    let mut steer = hold(keys(true, false, false, false, 0.0), 6);
    let mut takeoff = keys(true, false, false, false, 0.0);
    takeoff.jump = true;
    steer.push(takeoff);
    steer.extend(hold(keys(false, false, true, false, 0.0), 16));
    // Forward and right held with jump, the view turning right a little each
    // tick: the turning strafe that gains speed until the air cap.
    let mut strafe_jump = hold(keys(true, false, false, false, 0.0), 6);
    for tick in 0..48 {
        let mut input = keys(true, false, false, true, 0.07 * tick as f32);
        input.jump = true;
        strafe_jump.push(input);
    }
    strafe_jump.extend(hold(MoveInput::default(), 6));
    // Run forward, dodge right, land, then a dodge bit with no direction
    // held, which must do nothing but stand.
    let mut dodge = hold(keys(true, false, false, false, 0.0), 4);
    let mut side = keys(false, false, false, true, 0.0);
    side.dodge = true;
    dodge.push(side);
    dodge.extend(hold(keys(false, false, false, true, 0.0), 9));
    dodge.extend(hold(MoveInput::default(), 4));
    dodge.push(MoveInput {
        dodge: true,
        ..MoveInput::default()
    });
    dodge.extend(hold(MoveInput::default(), 2));
    let blast = MoveState {
        vx: 12.0,
        vy: 6.0,
        ..at_y(-10.0, 0.0, 0.5, 0.0)
    };
    let cases = vec![
        golden_case(
            "start_and_stop",
            &flat,
            at(0.0, 0.0, 0.0),
            TOP_SPEED,
            start_stop,
            1,
            dt,
        ),
        golden_case(
            "counter_strafe",
            &flat,
            at(0.0, 0.0, 0.0),
            TOP_SPEED,
            counter,
            1,
            dt,
        ),
        golden_case(
            "diagonal_yaw",
            &flat,
            at(0.0, 0.0, 0.0),
            TOP_SPEED,
            hold(keys(true, false, false, true, PI / 3.0), 8),
            1,
            dt,
        ),
        golden_case(
            "wall_slide",
            &obstacle,
            at(4.3, -2.0, 0.0),
            TOP_SPEED,
            hold(keys(true, false, false, true, 0.0), 16),
            1,
            dt,
        ),
        golden_case(
            "stair_climb_and_deck",
            &terrace,
            at(0.0, 0.0, 0.0),
            TOP_SPEED,
            hold(keys(true, false, false, false, 0.0), 56),
            4,
            dt,
        ),
        golden_case(
            "deck_edge_fall",
            &terrace,
            at_y(12.0, 0.0, 3.0, 0.0),
            TOP_SPEED,
            hold(keys(false, false, false, true, 0.0), 24),
            2,
            dt,
        ),
        golden_case(
            "jump_arc",
            &flat,
            at(0.0, 0.0, 0.0),
            TOP_SPEED,
            jump.clone(),
            1,
            dt,
        ),
        golden_case(
            "air_steer",
            &flat,
            at(0.0, 0.0, 0.0),
            TOP_SPEED,
            steer,
            1,
            dt,
        ),
        golden_case(
            "strafe_jump_air_cap",
            &flat,
            at(-20.0, -10.0, 0.0),
            TOP_SPEED,
            strafe_jump,
            2,
            dt,
        ),
        golden_case(
            "ground_dodge",
            &flat,
            at(0.0, 0.0, 0.0),
            TOP_SPEED,
            dodge,
            1,
            dt,
        ),
        golden_case(
            "blast_momentum",
            &flat,
            blast,
            TOP_SPEED,
            hold(keys(true, false, false, false, 0.0), 20),
            1,
            dt,
        ),
        golden_case(
            "ceiling_head_strike",
            &ceiling,
            at(0.0, 0.0, 0.0),
            TOP_SPEED,
            jump,
            1,
            dt,
        ),
        golden_case(
            "compliance_half_speed",
            &flat,
            at(0.0, 0.0, 0.0),
            TOP_SPEED * 0.5,
            hold(keys(true, false, false, false, 0.0), 8),
            1,
            dt,
        ),
        golden_case(
            "crouch_speed",
            &flat,
            at(0.0, 0.0, 0.0),
            TOP_SPEED * DUCK_SPEED_SCALE,
            hold(keys(true, false, false, false, 0.0), 8),
            1,
            dt,
        ),
    ];
    GoldenFile {
        version: GOLDEN_VERSION,
        dt,
        constants: FEEL,
        cases,
    }
}

fn at(x: f32, z: f32, yaw: f32) -> MoveState {
    at_y(x, z, GROUND_Y, yaw)
}

fn at_y(x: f32, z: f32, y: f32, yaw: f32) -> MoveState {
    MoveState {
        x,
        z,
        y,
        vx: 0.0,
        vz: 0.0,
        vy: 0.0,
        yaw,
    }
}

fn hold(input: MoveInput, n: usize) -> Vec<MoveInput> {
    vec![input; n]
}

fn keys(forward: bool, back: bool, left: bool, right: bool, yaw: f32) -> MoveInput {
    MoveInput {
        forward,
        back,
        left,
        right,
        jump: false,
        dodge: false,
        yaw,
        speed_scale: 1.0,
    }
}

/// The reference arena for the vectors: a 50 by 50 square with a crate, a wall,
/// and a corner pillar, in positions that keep every case off exact boundaries.
pub fn golden_arena() -> Arena {
    Arena {
        half: 25.0,
        solids: vec![
            Solid::from_center(6.0, 0.0, 1.0, 1.0),
            Solid::from_center(0.0, 10.0, 6.0, 0.5),
            Solid::from_center(-12.0, -12.0, 1.5, 1.5),
        ],
    }
}

/// The reference arena for the heightfield cases: a flight of six steps
/// climbing east from x=2 onto a deck, and a second deck with nothing leading
/// to it, so a case can walk up, walk down, and fall off an edge.
pub fn golden_terrace_arena() -> Arena {
    let mut solids = Vec::new();
    // Six 1.2 metre treads rising half a metre each, from x=2 to x=9.2.
    for i in 0..6 {
        let top = 0.5 * (i + 1) as f32;
        let cx = 2.0 + 1.2 * (i as f32 + 0.5);
        solids.push(Solid::from_center_top(cx, 0.0, 0.6, 4.0, top));
    }
    // The deck the stairs arrive on, level with the top tread.
    solids.push(Solid::from_center_top(13.2, 0.0, 4.0, 4.0, 3.0));
    // A wall on the far side of the deck, high enough to stop a fighter that
    // is standing on it.
    solids.push(Solid::from_center_top(17.6, 0.0, 0.4, 4.0, 6.0));
    Arena { half: 25.0, solids }
}

/// The 60 Hz vectors: the same model at the step a tick migration would use,
/// over the collision and heightfield cases that pin the shared integration.
pub fn golden_cases(dt: f32) -> GoldenFile {
    let arena = golden_arena();
    let terrace = golden_terrace_arena();
    let mut cases = Vec::new();
    let mut push =
        |name: &str, arena: &Arena, start: MoveState, inputs: Vec<MoveInput>, stride: usize| {
            cases.push(golden_case(
                name, arena, start, TOP_SPEED, inputs, stride, dt,
            ));
        };

    push(
        "straight_run",
        &arena,
        at(0.0, -5.0, 0.0),
        hold(keys(true, false, false, false, 0.0), 40),
        1,
    );
    push(
        "diagonal_run_normalised",
        &arena,
        at(-5.0, -5.0, 0.7),
        hold(keys(true, false, false, true, 0.7), 40),
        1,
    );
    let mut start_stop = hold(keys(true, false, false, false, 1.2), 30);
    start_stop.extend(hold(keys(false, false, false, false, 1.2), 30));
    push("start_and_stop", &arena, at(-8.0, 2.0, 1.2), start_stop, 1);
    push(
        "slide_along_wall_x",
        &arena,
        at(-3.0, 8.0, 0.3),
        hold(keys(true, false, false, false, 0.3), 60),
        1,
    );
    push(
        "slide_along_wall_z",
        &arena,
        at(4.2, -4.0, PI / 2.0 + 0.2),
        hold(keys(true, false, false, false, PI / 2.0 + 0.2), 60),
        1,
    );
    push(
        "corner_stop",
        &arena,
        at(-14.0, -14.0, PI / 4.0),
        hold(keys(true, false, false, false, PI / 4.0), 60),
        1,
    );
    push(
        "arena_edge_clamp",
        &arena,
        at(20.0, 20.0, PI / 4.0),
        hold(keys(true, false, false, false, PI / 4.0), 80),
        1,
    );
    let mut wrap = hold(keys(true, false, false, false, -0.05), 10);
    wrap.extend(hold(keys(true, false, false, false, 2.0 * PI + 0.05), 10));
    wrap.extend(hold(keys(true, false, false, false, 3.0 * PI), 10));
    push("yaw_wrap", &arena, at(0.0, 0.0, 0.0), wrap, 1);
    let mut slow = hold(keys(true, false, false, false, 2.5), 20);
    for input in slow.iter_mut().skip(10) {
        input.speed_scale = 0.5;
    }
    push("compliance_slow", &arena, at(5.0, -15.0, 2.5), slow, 1);
    let mut long = Vec::with_capacity(1000);
    for i in 0..1000usize {
        let phase = (i / 50) % 4;
        let yaw = 0.017 * i as f32;
        long.push(match phase {
            0 => keys(true, false, false, false, yaw),
            1 => keys(true, false, true, false, yaw),
            2 => keys(false, false, false, true, yaw),
            _ => keys(false, true, false, false, yaw),
        });
    }
    push("long_wander_1000", &arena, at(2.0, 2.0, 0.0), long, 100);
    // One step of jump held, then forward only, so the arc is gravity's and
    // not the key's. Every checkpoint pins a height.
    let mut hop = Vec::with_capacity(40);
    let mut first = keys(true, false, false, false, 0.0);
    first.jump = true;
    hop.push(first);
    hop.extend(hold(keys(true, false, false, false, 0.0), 39));
    push("jump_arc", &arena, at(0.0, 0.0, 0.0), hop, 4);

    // The heightfield cases. Each one pins `y` at every checkpoint, which is
    // the only thing holding the GDScript mirror to the same staircase.
    push(
        "stair_climb",
        &terrace,
        at(0.0, 0.0, 0.0),
        hold(keys(true, false, false, false, 0.0), 200),
        20,
    );
    push(
        "stair_descend",
        &terrace,
        at_y(13.2, 0.0, 3.0, PI),
        hold(keys(true, false, false, false, PI), 200),
        20,
    );
    push(
        "deck_edge_fall",
        &terrace,
        at_y(13.2, 0.0, 3.0, PI / 2.0),
        hold(keys(true, false, false, false, PI / 2.0), 120),
        10,
    );
    let ledge = Arena {
        half: 12.0,
        solids: vec![Solid::from_center_top(0.0, 0.0, 2.0, 2.0, 2.0)],
    };
    let fractional = Arena {
        half: 12.0,
        solids: vec![
            Solid::from_center_top(2.0, 0.0, 2.0, 2.0, 2.6 / 6.0),
            Solid::from_center_top(6.0, 0.0, 2.0, 2.0, 2.6 / 3.0),
        ],
    };
    for (name, error) in [
        ("stair_fractional_above", 0.00001),
        ("stair_fractional_below", -0.00001),
    ] {
        push(
            name,
            &fractional,
            at_y(2.0, 0.0, 2.6 / 6.0 + error, 0.0),
            hold(keys(true, false, false, false, 0.0), 60),
            10,
        );
    }
    for (name, yaw) in [
        ("ledge_escape_east", 0.0),
        ("ledge_escape_south", PI / 2.0),
        ("ledge_escape_west", PI),
        ("ledge_escape_north", PI * 1.5),
    ] {
        push(
            name,
            &ledge,
            at_y(0.0, 0.0, 2.0, yaw),
            hold(keys(true, false, false, false, yaw), 90),
            10,
        );
    }

    let balcony = Arena {
        half: 12.0,
        solids: vec![Solid::from_center_volume(0.0, 0.0, 2.0, 2.0, 2.4, 3.0)],
    };
    push(
        "balcony_underpass",
        &balcony,
        at(-4.0, 0.0, 0.0),
        hold(keys(true, false, false, false, 0.0), 120),
        1,
    );
    for (name, yaw) in [
        ("balcony_exit_east", 0.0),
        ("balcony_exit_south", PI / 2.0),
        ("balcony_exit_west", PI),
        ("balcony_exit_north", PI * 1.5),
    ] {
        push(
            name,
            &balcony,
            at_y(0.0, 0.0, 3.0, yaw),
            hold(keys(true, false, false, false, yaw), 90),
            1,
        );
    }
    let ceiling = Arena {
        half: 12.0,
        solids: vec![Solid::from_center_volume(0.0, 0.0, 2.0, 2.0, 2.1, 3.0)],
    };
    for (name, x) in [("ceiling_head_strike", 0.0), ("ceiling_edge_contact", 2.4)] {
        let mut hop = hold(MoveInput::default(), 60);
        hop[0].jump = true;
        push(name, &ceiling, at(x, 0.0, 0.0), hop, 1);
    }
    for (name, bottom) in [("ceiling_step_blocked", 2.2), ("ceiling_step_clear", 2.3)] {
        let stair = Arena {
            half: 12.0,
            solids: vec![
                Solid::from_center_volume(0.0, 0.0, 2.0, 2.0, bottom, 3.0),
                Solid::from_center_top(1.0, 0.0, 1.0, 1.0, 0.5),
            ],
        };
        push(
            name,
            &stair,
            at(-0.25, 0.0, 0.0),
            hold(keys(true, false, false, false, 0.0), 40),
            1,
        );
    }

    GoldenFile {
        version: GOLDEN_VERSION,
        dt,
        constants: FEEL,
        cases,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::Path;

    /// The fighter at top speed, for the collision and heightfield tests.
    fn step(state: MoveState, input: &MoveInput, dt: f32, arena: &Arena) -> MoveState {
        fighter_step(state, input, TOP_SPEED, dt, arena)
    }

    fn flat() -> Arena {
        Arena {
            half: 25.0,
            solids: Vec::new(),
        }
    }

    /// Steps at the live rate until horizontal speed is under 1 mm/s.
    fn ticks_to_rest(mut state: MoveState, input: &MoveInput, arena: &Arena) -> (usize, f32) {
        let start = state.x;
        let mut ticks = 0;
        while state.vx.hypot(state.vz) > 0.001 && ticks < 100 {
            state = fighter_step(state, input, TOP_SPEED, DT_LIVE, arena);
            ticks += 1;
        }
        (ticks, state.x - start)
    }

    #[test]
    fn live_feel_starts_and_stops_like_the_plan_says() {
        let arena = flat();
        let go = keys(true, false, false, false, 0.0);
        let first = fighter_step(at(0.0, 0.0, 0.0), &go, TOP_SPEED, DT_LIVE, &arena);
        assert!(
            (first.vx - GROUND_ACCEL * DT_LIVE * TOP_SPEED).abs() < 1e-5,
            "one tick reaches three quarters: {first:?}"
        );
        let mut running = first;
        for _ in 0..2 {
            running = fighter_step(running, &go, TOP_SPEED, DT_LIVE, &arena);
        }
        assert!((running.vx - TOP_SPEED).abs() < 1e-4, "{running:?}");
        let (ticks, slide) = ticks_to_rest(running, &MoveInput::default(), &arena);
        assert_eq!(ticks, 3, "a released key rests within three ticks");
        assert!(slide > 0.1 && slide < 0.2, "slide {slide}");
        // Counter-strafe: the opposite key cancels the run in one tick.
        let back = keys(false, true, false, false, 0.0);
        let countered = fighter_step(running, &back, TOP_SPEED, DT_LIVE, &arena);
        assert!(countered.vx < 0.0, "{countered:?}");
    }

    #[test]
    fn a_held_jump_keeps_speed_and_air_strafing_stops_at_the_cap() {
        let arena = Arena {
            half: 200.0,
            solids: Vec::new(),
        };
        let mut s = at(-150.0, 0.0, 0.0);
        let go = keys(true, false, false, false, 0.0);
        for _ in 0..6 {
            s = fighter_step(s, &go, TOP_SPEED, DT_LIVE, &arena);
        }
        let mut peak: f32 = 0.0;
        let mut landings = 0;
        for tick in 0..400 {
            let mut input = keys(true, false, false, true, 0.07 * tick as f32);
            input.jump = true;
            let before = s;
            s = fighter_step(s, &input, TOP_SPEED, DT_LIVE, &arena);
            if before.vy == 0.0 && before.y == GROUND_Y && s.vy > 0.0 && tick > 0 {
                landings += 1;
                // The landing tick hops again without ground friction.
                assert!(
                    s.vx.hypot(s.vz) >= before.vx.hypot(before.vz) - 1e-4,
                    "{before:?} -> {s:?}"
                );
            }
            peak = peak.max(s.vx.hypot(s.vz));
        }
        assert!(landings > 5, "{landings}");
        assert!(
            peak > TOP_SPEED + 0.5,
            "a turning strafe gains speed: {peak}"
        );
        assert!(peak <= AIR_SPEED_CAP + 1e-4, "never past the cap: {peak}");
        // Faster blast momentum is carried, never added to.
        let blast = MoveState {
            vx: 12.0,
            vy: 4.0,
            ..at_y(0.0, 0.0, 2.0, 0.0)
        };
        let carried = fighter_step(blast, &go, TOP_SPEED, DT_LIVE, &arena);
        assert!((carried.vx - 12.0).abs() < 1e-5, "{carried:?}");
    }

    #[test]
    fn crouch_and_compliance_cap_the_wish_speed() {
        let arena = flat();
        let go = keys(true, false, false, false, 0.0);
        let mut s = at(0.0, 0.0, 0.0);
        for _ in 0..10 {
            s = fighter_step(s, &go, TOP_SPEED * DUCK_SPEED_SCALE, DT_LIVE, &arena);
        }
        assert!((s.vx - TOP_SPEED * DUCK_SPEED_SCALE).abs() < 1e-4);
        let nan = fighter_step(s, &go, f32::NAN, f32::NAN, &arena);
        assert!(nan.x.is_finite() && nan.vx.is_finite());
        let bad = MoveState { vx: f32::NAN, ..s };
        assert_eq!(
            fighter_step(bad, &MoveInput::default(), TOP_SPEED, DT_LIVE, &arena).vx,
            0.0
        );
    }

    #[test]
    fn low_crawler_passes_under_a_beam_that_blocks_a_standing_fighter() {
        let arena = Arena {
            half: 10.0,
            solids: vec![Solid {
                min_x: -1.0,
                max_x: 1.0,
                min_z: -1.0,
                max_z: 1.0,
                bottom: 1.0,
                top: 2.5,
            }],
        };
        let mut low = at(-2.0, 0.0, 0.0);
        let mut standing = low;
        for _ in 0..20 {
            low.vx = 5.0;
            standing.vx = 5.0;
            low = integrate_with_height(low, false, 0.05, &arena, crate::combat::CRAWLER_HEIGHT);
            standing = integrate(standing, false, 0.05, &arena);
        }
        assert!(low.x > 1.5, "low body should clear the beam: {low:?}");
        assert!(
            standing.x <= -1.5,
            "standing body must stop before the beam: {standing:?}"
        );
    }

    #[test]
    fn live_step_respects_actor_height_and_keeps_default_fighter_path() {
        let arena = Arena {
            half: 10.0,
            solids: vec![Solid {
                min_x: -1.0,
                max_x: 1.0,
                min_z: -1.0,
                max_z: 1.0,
                bottom: 1.0,
                top: 2.5,
            }],
        };
        let input = keys(true, false, false, false, 0.0);
        let mut low = at(-2.0, 0.0, 0.0);
        let mut fighter = low;
        for _ in 0..20 {
            low = live_step_with_height(
                low,
                &input,
                5.0,
                0.05,
                &arena,
                crate::combat::CRAWLER_HEIGHT,
            );
            let default_height =
                live_step_with_height(fighter, &input, 5.0, 0.05, &arena, BODY_HEIGHT);
            fighter = live_step(fighter, &input, 5.0, 0.05, &arena);
            assert_eq!(fighter, default_height);
        }
        assert!(low.x > 1.5, "low actor should clear the beam: {low:?}");
        assert!(
            fighter.x <= -1.5,
            "standing fighter must stop before the beam: {fighter:?}"
        );
    }

    fn workspace_path(rel: &str) -> std::path::PathBuf {
        Path::new(env!("CARGO_MANIFEST_DIR")).join("..").join(rel)
    }

    #[test]
    fn yaw_normalises_and_survives_nonsense() {
        assert_eq!(normalize_yaw(0.0), 0.0);
        assert!((normalize_yaw(-0.5) - (2.0 * PI - 0.5)).abs() < 1e-6);
        assert!((normalize_yaw(2.0 * PI + 0.25) - 0.25).abs() < 1e-6);
        assert!(normalize_yaw(2.0 * PI) < 1e-6);
        assert_eq!(normalize_yaw(f32::NAN), 0.0);
        assert_eq!(normalize_yaw(f32::INFINITY), 0.0);
    }

    #[test]
    fn wish_direction_is_unit_or_zero() {
        let none = keys(false, false, false, false, 0.0);
        assert_eq!(wish_dir(&none, 0.0), (0.0, 0.0));
        let opposed = keys(true, true, false, false, 0.0);
        assert_eq!(wish_dir(&opposed, 0.0), (0.0, 0.0));
        let diag = keys(true, false, false, true, 0.0);
        let (dx, dz) = wish_dir(&diag, 0.0);
        assert!(((dx * dx + dz * dz).sqrt() - 1.0).abs() < 1e-6);
        let fwd = keys(true, false, false, false, PI / 2.0);
        let (dx, dz) = wish_dir(&fwd, PI / 2.0);
        assert!(dx.abs() < 1e-6 && (dz - 1.0).abs() < 1e-6);
    }

    #[test]
    fn velocity_approaches_top_speed_and_stops() {
        let arena = Arena {
            half: 25.0,
            solids: vec![],
        };
        let mut s = at(0.0, 0.0, 0.0);
        let go = keys(true, false, false, false, 0.0);
        for _ in 0..30 {
            s = step(s, &go, DT_60HZ, &arena);
        }
        assert!((s.vx - TOP_SPEED).abs() < 1e-3, "{s:?}");
        assert!(
            s.x > 2.7 && s.x < 3.0,
            "about half a second of running: {s:?}"
        );
        let stop = keys(false, false, false, false, 0.0);
        let mut steps = 0;
        while s.vx > 0.01 {
            s = step(s, &stop, DT_60HZ, &arena);
            steps += 1;
        }
        assert!(steps <= 20, "stops inside a third of a second: {steps}");
        let slow = MoveInput {
            speed_scale: 0.5,
            ..go
        };
        for _ in 0..60 {
            s = step(s, &slow, DT_60HZ, &arena);
        }
        assert!((s.vx - TOP_SPEED * 0.5).abs() < 1e-3, "{s:?}");
        let bad = MoveInput {
            speed_scale: f32::NAN,
            ..go
        };
        let s2 = step(s, &bad, DT_60HZ, &arena);
        assert!(s2.vx.is_finite());
    }

    #[test]
    fn slides_along_walls_and_clamps_to_the_arena() {
        let arena = golden_arena();
        // Into the long wall at z=10 from below, heading mostly +z with a little +x.
        let mut s = at(-3.0, 8.0, PI / 2.0 - 0.3);
        let go = keys(true, false, false, false, PI / 2.0 - 0.3);
        for _ in 0..90 {
            s = step(s, &go, DT_60HZ, &arena);
        }
        assert!(s.z <= 9.5 + 1e-4, "never inside the wall: {s:?}");
        assert!(s.x > -3.0, "slid along it: {s:?}");
        assert_eq!(s.vz, 0.0, "blocked axis velocity is zeroed");
        // Into the arena edge.
        let mut e = at(24.0, 0.0, 0.0);
        for _ in 0..30 {
            e = step(e, &keys(true, false, false, false, 0.0), DT_60HZ, &arena);
        }
        assert!((e.x - (25.0 - RADIUS)).abs() < 1e-5, "{e:?}");
        // Fully wedged: inside a corner where both axes are blocked.
        let boxed = Arena {
            half: 25.0,
            solids: vec![
                Solid::from_center(1.0, 0.0, 0.2, 5.0),
                Solid::from_center(0.0, 1.0, 5.0, 0.2),
            ],
        };
        let mut w = at(0.0, 0.0, PI / 4.0);
        for _ in 0..30 {
            w = step(
                w,
                &keys(true, false, false, false, PI / 4.0),
                DT_60HZ,
                &boxed,
            );
        }
        assert!(w.x < 0.35 && w.z < 0.35, "{w:?}");
        assert_eq!((w.vx, w.vz), (0.0, 0.0));
    }

    #[test]
    fn solid_blocks_with_radius() {
        let s = Solid::from_center(0.0, 0.0, 1.0, 1.0);
        assert!(s.blocks(1.4, 0.0, RADIUS));
        assert!(!s.blocks(1.6, 0.0, RADIUS));
        assert!(s.blocks(0.0, -1.49, RADIUS));
        assert_eq!(s.top, WALL_TOP, "a solid is a wall unless told otherwise");
        assert!(s.covers(0.9, 0.0), "the point itself is over it");
        assert!(
            !s.covers(1.4, 0.0),
            "standing beside it is not standing on it"
        );
    }

    #[test]
    fn a_step_is_walked_onto_and_a_wall_is_not() {
        let arena = Arena {
            half: 25.0,
            solids: vec![
                Solid::from_center_top(4.0, 0.0, 1.0, 4.0, 0.5),
                Solid::from_center_top(10.0, 0.0, 1.0, 4.0, 2.2),
            ],
        };
        let go = keys(true, false, false, false, 0.0);
        let mut s = at(0.0, 0.0, 0.0);
        for _ in 0..48 {
            s = step(s, &go, DT_60HZ, &arena);
        }
        assert!(s.x > 4.0, "walked onto the step: {s:?}");
        assert!((s.y - 0.5).abs() < 1e-5, "and is standing on it: {s:?}");
        for _ in 0..120 {
            s = step(s, &go, DT_60HZ, &arena);
        }
        assert!(s.x < 9.0, "stopped by the wall it cannot climb: {s:?}");
        assert_eq!(s.vx, 0.0);
    }

    #[test]
    fn stepping_down_snaps_but_a_drop_falls() {
        // A half metre step down is inside STEP_UP, so it is walked off.
        let shallow = Arena {
            half: 25.0,
            solids: vec![Solid::from_center_top(-2.0, 0.0, 4.0, 4.0, 0.5)],
        };
        let go = keys(true, false, false, false, 0.0);
        let mut s = at_y(-2.0, 0.0, 0.5, 0.0);
        for _ in 0..80 {
            s = step(s, &go, DT_60HZ, &shallow);
        }
        assert!(s.x > 2.0, "walked off the far edge: {s:?}");
        assert_eq!(s.y, GROUND_Y, "snapped down rather than fell: {s:?}");
        assert_eq!(s.vy, 0.0);

        // Three metres is a fall, and the fall lands on the floor.
        let deck = Arena {
            half: 25.0,
            solids: vec![Solid::from_center_top(-2.0, 0.0, 4.0, 4.0, 3.0)],
        };
        let mut d = at_y(-2.0, 0.0, 3.0, 0.0);
        let mut airborne = false;
        for _ in 0..120 {
            d = step(d, &go, DT_60HZ, &deck);
            if d.y < 3.0 - 1e-4 && d.y > GROUND_Y {
                airborne = true;
            }
        }
        assert!(airborne, "it was in the air on the way down");
        assert_eq!(d.y, GROUND_Y, "and it landed: {d:?}");
        assert!(
            d.x > 6.0,
            "leaving the ledge must not pin horizontal motion: {d:?}"
        );
    }

    #[test]
    fn overlapping_body_can_only_escape_toward_a_nearest_face() {
        let solid = Solid::from_center(0.0, 0.0, 2.0, 2.0);
        for (from, outward, inward) in [
            ((2.2, 0.0), (2.4, 0.0), (2.0, 0.0)),
            ((-2.2, 0.0), (-2.4, 0.0), (-2.0, 0.0)),
            ((0.0, 2.2), (0.0, 2.4), (0.0, 2.0)),
            ((0.0, -2.2), (0.0, -2.4), (0.0, -2.0)),
        ] {
            assert!(!solid.blocks_motion(from, outward, RADIUS));
            assert!(solid.blocks_motion(from, inward, RADIUS));
            assert!(solid.blocks_motion(from, from, RADIUS));
        }
        assert!(solid.blocks_motion((2.2, 0.0), (2.2, 0.2), RADIUS));
        assert!(solid.blocks_motion((3.0, 0.0), (2.4, 0.0), RADIUS));
        assert!(!solid.blocks_motion((2.2, 0.0), (3.0, 0.0), RADIUS));
        assert!(!solid.blocks_motion((2.2, 2.2), (2.3, 2.3), RADIUS));
    }

    #[test]
    fn climb_height_is_a_step_when_standing_and_the_feet_when_not() {
        let floor = 2.6 / 6.0;
        assert_eq!(
            climb_height(floor + CONTACT_EPSILON * 0.5, floor, 0.0),
            floor + STEP_UP
        );
        assert!(!grounded(floor + CONTACT_EPSILON * 2.0, floor, 0.0));
        assert!(
            !grounded(floor, floor, 0.1),
            "ascending motion is never grounded"
        );
        assert!((climb_height(0.0, 0.0, 0.0) - STEP_UP).abs() < 1e-6);
        assert!((climb_height(2.0, 2.0, -0.1) - (2.0 + STEP_UP)).abs() < 1e-6);
        // Airborne: exactly what the jump has cleared, so a low wall a jump
        // does not clear still stops the fighter.
        assert!((climb_height(0.9, 0.0, 3.0) - 0.9).abs() < 1e-6);
        let arena = Arena {
            half: 25.0,
            solids: vec![Solid::from_center_top(0.0, 0.0, 2.0, 2.0, 1.6)],
        };
        assert!(arena.blocked_at(2.4, 0.0, 0.9), "a jump does not clear 1.6");
        assert!(!arena.blocked_at(2.4, 0.0, 1.8), "from above it, it does");
        assert_eq!(arena.support_height(0.0, 0.0, 1.8), 1.6);
        assert_eq!(arena.support_height(0.0, 0.0, 1.0), GROUND_Y);
        assert_eq!(arena.support_height(3.0, 0.0, 9.0), GROUND_Y);
    }

    #[test]
    fn a_solid_with_no_top_on_the_wire_is_a_wall() {
        let s: Solid =
            serde_json::from_str(r#"{"min_x":-1,"max_x":1,"min_z":-1,"max_z":1}"#).unwrap();
        assert_eq!(s.top, WALL_TOP);
    }

    #[test]
    fn golden_vectors_match_this_model() {
        let path = workspace_path(GOLDEN_PATH);
        let text = std::fs::read_to_string(&path).unwrap_or_else(|e| {
            panic!(
                "read {}: {e}; regenerate with the ignored test",
                path.display()
            )
        });
        let file: GoldenFile = serde_json::from_str(&text).expect("golden json");
        assert_eq!(file.version, GOLDEN_VERSION);
        assert_eq!(file.dt, DT_60HZ);
        assert_eq!(
            file.constants, FEEL,
            "constants changed; regenerate the vectors"
        );
        let fresh = golden_cases(DT_60HZ);
        assert_eq!(fresh.cases.len(), file.cases.len());
        for (want, have) in file.cases.iter().zip(fresh.cases.iter()) {
            assert_eq!(want.name, have.name);
            assert_eq!(want.expected.len(), have.expected.len(), "{}", want.name);
            for (i, (w, h)) in want.expected.iter().zip(have.expected.iter()).enumerate() {
                for (label, a, b) in [
                    ("x", w.x, h.x),
                    ("z", w.z, h.z),
                    ("y", w.y, h.y),
                    ("vx", w.vx, h.vx),
                    ("vz", w.vz, h.vz),
                    ("vy", w.vy, h.vy),
                    ("yaw", w.yaw, h.yaw),
                ] {
                    assert!(
                        (a - b).abs() <= 1e-6,
                        "{} step {} {label}: file {a} vs model {b}",
                        want.name,
                        i
                    );
                }
            }
        }
    }

    #[test]
    fn live_golden_vectors_match_this_model() {
        let path = workspace_path(LIVE_GOLDEN_PATH);
        let text = std::fs::read_to_string(&path).unwrap_or_else(|e| {
            panic!(
                "read {}: {e}; regenerate with the ignored test",
                path.display()
            )
        });
        let file: GoldenFile = serde_json::from_str(&text).expect("live golden json");
        assert_eq!((file.version, file.dt), (GOLDEN_VERSION, DT_LIVE));
        assert_eq!(
            file.constants, FEEL,
            "constants changed; regenerate the vectors"
        );
        let fresh = live_golden_cases();
        assert_eq!(fresh.cases.len(), file.cases.len());
        for (want, have) in file.cases.iter().zip(fresh.cases.iter()) {
            assert_eq!(want.name, have.name);
            assert_eq!(want.arena, have.arena);
            assert_eq!(want.start, have.start);
            assert_eq!(want.inputs, have.inputs);
            assert_eq!(want.speed, have.speed);
            assert_eq!(want.stride, have.stride);
            assert_eq!(want.expected.len(), have.expected.len(), "{}", want.name);
            for (i, (w, h)) in want.expected.iter().zip(have.expected.iter()).enumerate() {
                for (label, a, b) in [
                    ("x", w.x, h.x),
                    ("z", w.z, h.z),
                    ("y", w.y, h.y),
                    ("vx", w.vx, h.vx),
                    ("vz", w.vz, h.vz),
                    ("vy", w.vy, h.vy),
                    ("yaw", w.yaw, h.yaw),
                ] {
                    assert!(
                        (a - b).abs() <= 1e-6,
                        "{} step {} {label}: file {a} vs model {b}",
                        want.name,
                        i
                    );
                }
            }
        }
    }

    #[test]
    fn live_golden_cases_exercise_the_claimed_behaviors() {
        let file = live_golden_cases();
        let find = |name: &str| {
            file.cases
                .iter()
                .find(|case| case.name == name)
                .unwrap_or_else(|| panic!("missing live case {name}"))
        };
        let stop = find("start_and_stop");
        let first = GROUND_ACCEL * DT_LIVE * TOP_SPEED;
        assert!((stop.expected[0].vx - first).abs() < 1e-5);
        assert!((stop.expected[5].vx - TOP_SPEED).abs() < 1e-4);
        assert!(stop.expected[5].vx > stop.expected[6].vx);
        assert_eq!(stop.expected[8].vx, 0.0, "rests three ticks after release");
        assert_eq!(stop.expected[9].x, stop.expected[8].x);
        let counter = find("counter_strafe");
        assert!(counter.expected[5].vz > TOP_SPEED - 1e-4);
        assert!(
            counter.expected[6].vz < 0.0,
            "the opposite key reverses at once"
        );
        let slow = find("compliance_half_speed");
        assert!((slow.expected.last().unwrap().vx - TOP_SPEED * 0.5).abs() < 1e-4);
        let crouch = find("crouch_speed");
        assert!((crouch.expected.last().unwrap().vx - TOP_SPEED * DUCK_SPEED_SCALE).abs() < 1e-4);
        let steer = find("air_steer");
        assert!(steer
            .expected
            .iter()
            .any(|state| state.y > 0.0 && state.vz < -0.5));
        let strafe = find("strafe_jump_air_cap");
        let fastest = strafe
            .expected
            .iter()
            .fold(0.0f32, |most, state| most.max(state.vx.hypot(state.vz)));
        assert!(
            fastest > TOP_SPEED && fastest <= AIR_SPEED_CAP + 1e-4,
            "{fastest}"
        );
        let blast = find("blast_momentum");
        assert!(
            blast.expected[0].vx > AIR_SPEED_CAP,
            "blast speed is carried"
        );
        let dodge = find("ground_dodge");
        assert!(
            (dodge.expected[4].vz - DODGE_SPEED).abs() < 1e-5,
            "{:?}",
            dodge.expected[4]
        );
        assert!(dodge.expected[4].y > 0.0 && dodge.expected[4].vy > 0.0);
        let still = &dodge.expected[dodge.expected.len() - 3];
        assert_eq!(
            (still.vx, still.vz, still.y),
            (0.0, 0.0, 0.0),
            "no direction, no dodge"
        );
        let wall = find("wall_slide");
        assert!(wall
            .expected
            .iter()
            .any(|state| state.vz == 0.0 && state.vx > 0.0));
        let stairs = find("stair_climb_and_deck");
        assert_eq!(stairs.expected.last().unwrap().y, 3.0);
        let fall = find("deck_edge_fall");
        assert!(fall.expected.last().unwrap().y < fall.start.y);
        let jump = find("jump_arc");
        assert!(jump.expected.iter().any(|state| state.y > 1.0));
        assert_eq!(jump.expected.last().unwrap().y, GROUND_Y);
        let ceiling = find("ceiling_head_strike");
        assert!(ceiling.expected.iter().any(|state| state.y > 0.0));
        assert!(ceiling.expected.iter().all(|state| state.y < 0.31));
    }

    #[test]
    fn live_step_preserves_the_previous_inline_velocity_formula() {
        let arena = golden_arena();
        for (state, input, speed) in [
            (
                at(0.0, 0.0, 0.0),
                keys(true, false, false, false, 0.0),
                TOP_SPEED,
            ),
            (
                at(4.3, -2.0, 0.0),
                keys(true, false, false, true, 0.0),
                TOP_SPEED,
            ),
            (
                at(0.0, 0.0, PI / 3.0),
                keys(true, false, true, false, PI / 3.0),
                TOP_SPEED * 0.5,
            ),
            (
                at(0.0, 0.0, PI / 2.0),
                MoveInput {
                    jump: true,
                    yaw: PI / 2.0,
                    ..MoveInput::default()
                },
                TOP_SPEED,
            ),
        ] {
            // This is the original sim.rs calculation, retained in a test so
            // extraction cannot silently change the current live rule.
            let yaw = input.yaw;
            let mut dx = 0.0;
            let mut dz = 0.0;
            if input.forward {
                dx += yaw.cos();
                dz += yaw.sin();
            }
            if input.back {
                dx -= yaw.cos();
                dz -= yaw.sin();
            }
            if input.left {
                dx += (yaw - PI / 2.0).cos();
                dz += (yaw - PI / 2.0).sin();
            }
            if input.right {
                dx += (yaw + PI / 2.0).cos();
                dz += (yaw + PI / 2.0).sin();
            }
            let len = (dx * dx + dz * dz).sqrt();
            if len > 0.0 {
                dx /= len;
                dz /= len;
            }
            let legacy = integrate(
                MoveState {
                    vx: dx * speed,
                    vz: dz * speed,
                    yaw,
                    ..state
                },
                input.jump,
                DT_LIVE,
                &arena,
            );
            assert_eq!(live_step(state, &input, speed, DT_LIVE, &arena), legacy);
        }
    }

    #[test]
    #[ignore]
    fn regenerate_live_golden_vectors() {
        let path = workspace_path(LIVE_GOLDEN_PATH);
        let file = live_golden_cases();
        std::fs::write(&path, serde_json::to_string_pretty(&file).unwrap() + "\n").unwrap();
    }

    /// Rewrites the golden file from the current model. Run it on purpose:
    /// `cargo test -p fragr-server regenerate_golden_vectors -- --ignored`.
    #[test]
    #[ignore]
    fn regenerate_golden_vectors() {
        let path = workspace_path(GOLDEN_PATH);
        let file = golden_cases(DT_60HZ);
        let text = serde_json::to_string(&file).unwrap();
        std::fs::create_dir_all(path.parent().unwrap()).unwrap();
        std::fs::write(&path, text + "\n").unwrap();
    }

    #[test]
    fn golden_cases_cover_the_model() {
        let file = golden_cases(DT_60HZ);
        let names: Vec<&str> = file.cases.iter().map(|c| c.name.as_str()).collect();
        for needed in [
            "straight_run",
            "diagonal_run_normalised",
            "start_and_stop",
            "slide_along_wall_x",
            "slide_along_wall_z",
            "corner_stop",
            "arena_edge_clamp",
            "yaw_wrap",
            "compliance_slow",
            "long_wander_1000",
            "jump_arc",
            "stair_climb",
            "stair_descend",
            "deck_edge_fall",
            "balcony_underpass",
            "balcony_exit_east",
            "balcony_exit_south",
            "balcony_exit_west",
            "balcony_exit_north",
            "ceiling_head_strike",
            "ceiling_edge_contact",
            "ceiling_step_blocked",
            "ceiling_step_clear",
        ] {
            assert!(names.contains(&needed), "missing golden case {needed}");
        }
        let long = file
            .cases
            .iter()
            .find(|c| c.name == "long_wander_1000")
            .unwrap();
        assert_eq!(long.expected.len(), 10, "one checkpoint per hundred steps");
        let hop = file.cases.iter().find(|c| c.name == "jump_arc").unwrap();
        let peak = hop.expected.iter().fold(f32::MIN, |a, s| a.max(s.y));
        assert!(
            peak > 0.8,
            "the jump case has to leave the ground, peaked {peak}"
        );
        assert!(
            hop.expected.last().unwrap().y.abs() < 1e-3,
            "and it has to come back down"
        );
        let wrap = file.cases.iter().find(|c| c.name == "yaw_wrap").unwrap();
        for s in &wrap.expected {
            assert!((0.0..2.0 * PI).contains(&s.yaw));
        }
        let json = serde_json::to_string(&file).unwrap();
        let back: GoldenFile = serde_json::from_str(&json).unwrap();
        assert_eq!(back, file);
    }
}
