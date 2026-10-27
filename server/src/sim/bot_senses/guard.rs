//! Campaign guards on post see through the same gates as the arcade's rule
//! bots: the 120 degree cone, cover and the 200 to 400 ms reaction. A guard
//! on post looks level, so a body well above or below its eye line, such as
//! an ambush from a gantry overhead, is outside its cone.

use super::{angle_difference, fighter_chest, fighter_eye, reaction, GameState, Player};
use std::f32::consts::FRAC_PI_3;
use uuid::Uuid;

/// Furthest a guard on post looks above or below level, in radians.
pub(crate) const GUARD_ELEVATION: f32 = 0.6;

/// Whether `guard`, facing `facing`, sees `target`'s chest inside `range`
/// metres: within the shared cone, near level and in the clear.
pub(crate) fn guard_sees(
    state: &GameState,
    guard: &Player,
    facing: f32,
    range: f32,
    target: &Player,
) -> bool {
    let eye = fighter_eye(guard);
    let chest = fighter_chest(target);
    let dx = chest[0] - eye[0];
    let dz = chest[2] - eye[2];
    let flat = dx.hypot(dz);
    flat <= range
        && angle_difference(dz.atan2(dx), facing).abs() <= FRAC_PI_3
        && (chest[1] - eye[1]).atan2(flat).abs() <= GUARD_ELEVATION
        && crate::combat::line_of_sight(eye, chest, &state.current_arena().solids)
}

/// The tick a guard that first saw `target` at `tick` reacts: 200 to 400 ms
/// later, the arcade's reaction.
pub(crate) fn guard_reaction(guard: Uuid, target: Uuid, tick: u64) -> u64 {
    reaction(guard, target, tick)
}
