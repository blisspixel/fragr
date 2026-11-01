//! Who could see whom, read from outside the bots: the 120 degree cone, a
//! range and a clear line from eye to chest. Contact is measured with these
//! by the bot survey and by a host's fun metrics alike.
use crate::movement::Solid;
use crate::protocol::{GameMode, Role};
use crate::sim::Player;

/// Half the 120 degree view cone every rule bot looks through.
pub const CONE: f32 = std::f32::consts::FRAC_PI_3;
/// The default rung's eyes, metres: contact is read at what a regular sees.
pub const SIGHT: f32 = 64.0;

/// A fighter on its feet: alive, not waiting to respawn, not in the booth.
pub fn alive(player: &Player) -> bool {
    player.hp > 0 && player.respawn_timer.is_none() && player.role != Role::Spectator
}

/// Feet position.
pub fn feet(player: &Player) -> [f32; 3] {
    [player.x, player.y - crate::sim::PLAYER_FLOOR_Y, player.z]
}

/// Whether `a` and `b` fight each other in `mode`.
pub fn hostile(mode: GameMode, a: &Player, b: &Player) -> bool {
    a.id != b.id
        && !a.is_boss
        && !b.is_boss
        && match mode {
            GameMode::Ffa | GameMode::Duel => true,
            _ => a.team.is_some() && a.team != b.team,
        }
}

/// Whether `from` has `to` inside its 120 degree cone, within `range`,
/// with clear sight from its eye to the other's chest.
pub fn sees(solids: &[Solid], from: &Player, to: &Player, range: f32) -> bool {
    let dx = to.x - from.x;
    let dz = to.z - from.z;
    if dx.hypot(dz) > range {
        return false;
    }
    let bearing = dz.atan2(dx);
    let turn = (bearing - from.yaw + std::f32::consts::PI).rem_euclid(std::f32::consts::TAU)
        - std::f32::consts::PI;
    if turn.abs() > CONE {
        return false;
    }
    let mut eye = feet(from);
    eye[1] += crate::combat::stance_eye(from.campaign, from.ducking);
    let chest = crate::combat::aim_point_for(feet(to), to.campaign, to.ducking);
    crate::combat::line_of_sight(eye, chest, solids)
}

/// Whether `a` and `b` are opponents who can see each other either way.
pub fn in_contact(mode: GameMode, solids: &[Solid], a: &Player, b: &Player) -> bool {
    alive(b) && hostile(mode, a, b) && (sees(solids, a, b, SIGHT) || sees(solids, b, a, SIGHT))
}
