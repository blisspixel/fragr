//! The shared movement step: the one function that both the server and the
//! predicting client run, written here in Rust and mirrored line for line in
//! `client/scripts/movement.gd`. Pure data in, pure data out, no engine calls,
//! no randomness, so the same inputs give the same states on both sides.
//!
//! Agreement is proven by golden vectors in `client/golden/move_vectors.json`:
//! this module generates them, the test below asserts this module reproduces
//! them exactly, and the headless Godot harness asserts the GDScript mirror
//! reproduces them within a tolerance. Change the model here, regenerate the
//! vectors, review the diff like code.

use serde::{Deserialize, Serialize};
use std::f32::consts::PI;

/// Fighter collision radius in units.
pub const RADIUS: f32 = 0.5;
/// Ground top speed in units per second.
pub const TOP_SPEED: f32 = 5.0;
/// Time constant for speeding up, seconds.
pub const TAU_ACCEL: f32 = 0.06;
/// Time constant for slowing down, seconds.
pub const TAU_DECEL: f32 = 0.04;
/// The movement step length at the 60 Hz rate the tick migration adopts.
pub const DT_60HZ: f32 = 1.0 / 60.0;
/// The base floor. Solids stand on it and a fighter with nothing under it
/// falls back to it, so it is the bottom of the heightfield rather than the
/// only ground there is.
pub const GROUND_Y: f32 = 0.0;
/// How far a fighter climbs or drops without leaving the ground. Quake's step
/// height scaled to a 1.8 metre fighter, which is what makes a staircase feel
/// like walking rather than a sequence of small jumps.
pub const STEP_UP: f32 = 0.6;
/// The top a solid gets when nobody says otherwise: higher than a jump can
/// reach, so it is a wall. Every solid written before the heightfield existed
/// means this, which is why it is also the wire default.
pub const WALL_TOP: f32 = 4.5;
/// How far above its feet a fighter's shot line sits. A solid lower than the
/// line between two fighters does not block the shot between them.
pub const EYE_HEIGHT: f32 = 1.5;
/// Downward acceleration in units per second squared. Chosen with the jump
/// below so a hop clears about 1.1 units and lasts a little under half a
/// second, which is the Quake-ish arc this game's speed wants rather than the
/// floatier one a slower game can afford.
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
    pub yaw: f32,
    #[serde(default = "one")]
    pub speed_scale: f32,
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
            yaw: 0.0,
            speed_scale: 1.0,
        }
    }
}

/// An axis-aligned solid in the XZ plane, not yet inflated by the radius. It
/// runs from the base floor up to `top`, so it is a box rather than a prism:
/// there is no space underneath one, and a low one is a step rather than a
/// wall.
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
pub struct Solid {
    pub min_x: f32,
    pub max_x: f32,
    pub min_z: f32,
    pub max_z: f32,
    /// Height of the walkable upper surface. Defaulted rather than required so
    /// that every solid written before the heightfield existed keeps meaning a
    /// wall, on the wire and in the committed golden vectors alike.
    #[serde(default = "wall_top")]
    pub top: f32,
}

fn wall_top() -> f32 {
    WALL_TOP
}

impl Solid {
    /// A wall: tall enough that nothing walks or jumps onto it.
    pub fn from_center(cx: f32, cz: f32, half_x: f32, half_z: f32) -> Self {
        Solid::from_center_top(cx, cz, half_x, half_z, WALL_TOP)
    }

    /// A solid whose upper surface is at `top`. Below `STEP_UP` it is a step,
    /// below a jump's reach it is a ledge, above that it is a wall.
    pub fn from_center_top(cx: f32, cz: f32, half_x: f32, half_z: f32, top: f32) -> Self {
        Solid {
            min_x: cx - half_x,
            max_x: cx + half_x,
            min_z: cz - half_z,
            max_z: cz + half_z,
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

impl Arena {
    /// Blocked for a fighter standing on the base floor. The flat-arena
    /// question, kept because plenty of callers only ever ask it.
    pub fn blocked(&self, x: f32, z: f32) -> bool {
        self.blocked_at(x, z, GROUND_Y + STEP_UP)
    }

    /// Blocked for a fighter that can reach up to `climb`. Anything at or
    /// below that height is walked onto instead of walked into.
    pub fn blocked_at(&self, x: f32, z: f32, climb: f32) -> bool {
        self.solids
            .iter()
            .any(|s| s.top > climb && s.blocks(x, z, RADIUS))
    }

    /// The highest surface at `(x, z)` that is no higher than `ceiling`, or the
    /// base floor when nothing qualifies. This is the floor the fighter is
    /// standing on.
    pub fn support_height(&self, x: f32, z: f32, ceiling: f32) -> f32 {
        let mut best = GROUND_Y;
        for s in &self.solids {
            if s.top <= ceiling && s.top > best && s.covers(x, z) {
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
    if feet <= floor && vy <= 0.0 {
        floor + STEP_UP
    } else {
        feet
    }
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

/// Advance one fighter by `dt` seconds. The order of operations is the
/// contract the GDScript mirror keeps: yaw, wish, velocity approach, the floor
/// under the old position, integrate, clamp, axis-separated slide with
/// velocity zeroed on the blocked axis, then the vertical against the floor
/// under the new position.
///
/// On flat ground with nothing low enough to stand on, every heightfield term
/// collapses: `support` is `GROUND_Y`, the step-down allowance is implied by
/// the grounded test that precedes it, and the arithmetic is the same to the
/// last bit as the version that had no heightfield in it. That is what keeps
/// the committed golden vectors valid across this change.
pub fn step(state: MoveState, input: &MoveInput, dt: f32, arena: &Arena) -> MoveState {
    let yaw = normalize_yaw(input.yaw);
    let (wx, wz) = wish_dir(input, yaw);
    let scale = if input.speed_scale.is_finite() {
        input.speed_scale.clamp(0.0, 1.0)
    } else {
        1.0
    };
    let target_x = wx * TOP_SPEED * scale;
    let target_z = wz * TOP_SPEED * scale;

    let current_speed = (state.vx * state.vx + state.vz * state.vz).sqrt();
    let target_speed = (target_x * target_x + target_z * target_z).sqrt();
    let tau = if target_speed > current_speed {
        TAU_ACCEL
    } else {
        TAU_DECEL
    };
    let blend = (dt / tau).min(1.0);
    let mut vx = state.vx + (target_x - state.vx) * blend;
    let mut vz = state.vz + (target_z - state.vz) * blend;

    let old_x = state.x;
    let old_z = state.z;
    let (nx, nz) = arena.clamp(old_x + vx * dt, old_z + vz * dt);

    // What is under the fighter now, and therefore how high it can climb into
    // the next square. A deck one step up is walked onto; anything higher is a
    // wall until a jump puts the feet above it.
    let floor = arena.support_height(old_x, old_z, state.y);
    let was_grounded = state.y <= floor && state.vy <= 0.0;
    let climb = climb_height(state.y, floor, state.vy);

    let (x, z) = if !arena.blocked_at(nx, nz, climb) {
        (nx, nz)
    } else if !arena.blocked_at(nx, old_z, climb) {
        vz = 0.0;
        (nx, old_z)
    } else if !arena.blocked_at(old_x, nz, climb) {
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
    let on_ground = (y <= support || (was_grounded && y - support <= STEP_UP)) && state.vy <= 0.0;
    if on_ground {
        y = support;
        vy = 0.0;
        if input.jump {
            vy = JUMP_SPEED;
        }
    } else {
        vy -= GRAVITY * dt;
    }
    y += vy * dt;
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
        yaw,
    }
}

/// One golden case: an arena, a start, inputs, and the state expected after
/// every `stride` steps (so a long case stays small on disk).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct GoldenCase {
    pub name: String,
    pub arena: Arena,
    pub start: MoveState,
    pub inputs: Vec<MoveInput>,
    pub stride: usize,
    pub expected: Vec<MoveState>,
}

/// The golden file: the constants the vectors were made with, and the cases.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct GoldenFile {
    pub version: u32,
    pub dt: f32,
    pub radius: f32,
    pub top_speed: f32,
    pub tau_accel: f32,
    pub tau_decel: f32,
    pub cases: Vec<GoldenCase>,
}

/// Where the vectors live, shared with the Godot harness.
pub const GOLDEN_PATH: &str = "client/golden/move_vectors.json";

fn run_case(
    arena: &Arena,
    start: MoveState,
    inputs: &[MoveInput],
    dt: f32,
    stride: usize,
) -> Vec<MoveState> {
    let mut state = start;
    let mut out = Vec::new();
    for (i, input) in inputs.iter().enumerate() {
        state = step(state, input, dt, arena);
        if (i + 1) % stride == 0 {
            out.push(state);
        }
    }
    out
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
///
/// It is a separate arena from `golden_arena` on purpose. Putting a step into
/// the flat one would move the expected states of every case that already
/// exists, and the point of the golden file is that those do not move unless
/// the model moved.
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

/// Build the golden file from the current model.
pub fn golden_cases(dt: f32) -> GoldenFile {
    let arena = golden_arena();
    let terrace = golden_terrace_arena();
    let mut cases = Vec::new();
    let push_in = |name: &str,
                   arena: &Arena,
                   start: MoveState,
                   inputs: Vec<MoveInput>,
                   stride: usize,
                   out: &mut Vec<GoldenCase>| {
        let expected = run_case(arena, start, &inputs, dt, stride);
        out.push(GoldenCase {
            name: name.to_string(),
            arena: arena.clone(),
            start,
            inputs,
            stride,
            expected,
        });
    };
    {
        let mut push = |name: &str, start: MoveState, inputs: Vec<MoveInput>, stride: usize| {
            let expected = run_case(&arena, start, &inputs, dt, stride);
            cases.push(GoldenCase {
                name: name.to_string(),
                arena: arena.clone(),
                start,
                inputs,
                stride,
                expected,
            });
        };

        push(
            "straight_run",
            at(0.0, -5.0, 0.0),
            hold(keys(true, false, false, false, 0.0), 40),
            1,
        );
        push(
            "diagonal_run_normalised",
            at(-5.0, -5.0, 0.7),
            hold(keys(true, false, false, true, 0.7), 40),
            1,
        );
        let mut start_stop = hold(keys(true, false, false, false, 1.2), 30);
        start_stop.extend(hold(keys(false, false, false, false, 1.2), 30));
        push("start_and_stop", at(-8.0, 2.0, 1.2), start_stop, 1);
        push(
            "slide_along_wall_x",
            at(-3.0, 8.0, 0.3),
            hold(keys(true, false, false, false, 0.3), 60),
            1,
        );
        push(
            "slide_along_wall_z",
            at(4.2, -4.0, PI / 2.0 + 0.2),
            hold(keys(true, false, false, false, PI / 2.0 + 0.2), 60),
            1,
        );
        push(
            "corner_stop",
            at(-14.0, -14.0, PI / 4.0),
            hold(keys(true, false, false, false, PI / 4.0), 60),
            1,
        );
        push(
            "arena_edge_clamp",
            at(20.0, 20.0, PI / 4.0),
            hold(keys(true, false, false, false, PI / 4.0), 80),
            1,
        );
        let mut wrap = hold(keys(true, false, false, false, -0.05), 10);
        wrap.extend(hold(keys(true, false, false, false, 2.0 * PI + 0.05), 10));
        wrap.extend(hold(keys(true, false, false, false, 3.0 * PI), 10));
        push("yaw_wrap", at(0.0, 0.0, 0.0), wrap, 1);
        let mut slow = hold(keys(true, false, false, false, 2.5), 20);
        for input in slow.iter_mut().skip(10) {
            input.speed_scale = 0.5;
        }
        push("compliance_slow", at(5.0, -15.0, 2.5), slow, 1);
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
        push("long_wander_1000", at(2.0, 2.0, 0.0), long, 100);
        // One tick of jump held, then nothing, so the arc is gravity's and not the
        // key's. Every checkpoint pins a height, which is what holds the GDScript
        // mirror to the same curve.
        let mut hop = Vec::with_capacity(40);
        let mut first = keys(true, false, false, false, 0.0);
        first.jump = true;
        hop.push(first);
        hop.extend(hold(keys(true, false, false, false, 0.0), 39));
        push("jump_arc", at(0.0, 0.0, 0.0), hop, 4);
    }

    // The heightfield cases. Each one pins `y` at every checkpoint, which is
    // the only thing holding the GDScript mirror to the same staircase.
    push_in(
        "stair_climb",
        &terrace,
        at(0.0, 0.0, 0.0),
        hold(keys(true, false, false, false, 0.0), 200),
        20,
        &mut cases,
    );
    push_in(
        "stair_descend",
        &terrace,
        at_y(13.2, 0.0, 3.0, PI),
        hold(keys(true, false, false, false, PI), 200),
        20,
        &mut cases,
    );
    push_in(
        "deck_edge_fall",
        &terrace,
        at_y(13.2, 0.0, 3.0, PI / 2.0),
        hold(keys(true, false, false, false, PI / 2.0), 120),
        10,
        &mut cases,
    );

    GoldenFile {
        version: 2,
        dt,
        radius: RADIUS,
        top_speed: TOP_SPEED,
        tau_accel: TAU_ACCEL,
        tau_decel: TAU_DECEL,
        cases,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::Path;

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
            s.x > 2.0 && s.x < 2.5,
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
        for _ in 0..55 {
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
    }

    #[test]
    fn climb_height_is_a_step_when_standing_and_the_feet_when_not() {
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
        assert_eq!(file.version, 2);
        assert_eq!(file.dt, DT_60HZ);
        assert_eq!(
            (file.radius, file.top_speed, file.tau_accel, file.tau_decel),
            (RADIUS, TOP_SPEED, TAU_ACCEL, TAU_DECEL),
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
