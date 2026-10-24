//! What a rule bot believes about the map's pads. A bot sees a pad the way it
//! sees a fighter: inside its view cone, within sight range and past cover,
//! or underfoot. It learns a pad's state only from that view and keeps the
//! published return clocks a regular learns, so it can be at the Railgun
//! when it comes back without ever reading a live timer.
use super::super::{fighter_eye, ArenaPickup, GameState, Player};
use crate::protocol::SupplyClaim;
use std::f32::consts::FRAC_PI_3;

/// Pads further than this are only remembered, not seen.
const PAD_SIGHT: f32 = 40.0;
/// A pad this close is seen whichever way the bot faces.
const UNDERFOOT: f32 = 2.5;
/// Pads are glanced at on this cadence, staggered with the bot's observations.
pub(super) const LOOK_EVERY: u64 = 4;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct Belief {
    /// Believed up for the taking.
    up: bool,
    /// When the bot expects it back, from the clock of the moment it saw the
    /// pad empty. Seeing it taken makes this exact; finding it empty makes it
    /// a conservative bound.
    back_at: Option<u64>,
}

#[derive(Debug, Clone, Default)]
pub(in crate::sim) struct PadMemory {
    round: Option<u32>,
    beliefs: Vec<Belief>,
}

/// Whether `bot` can see `pad` right now.
pub(super) fn sees(state: &GameState, bot: &Player, pad: &ArenaPickup) -> bool {
    let dx = pad.x - bot.x;
    let dz = pad.z - bot.z;
    let distance = dx.hypot(dz);
    if distance > PAD_SIGHT {
        return false;
    }
    let underfoot =
        distance <= UNDERFOOT && (bot.y - super::super::PLAYER_FLOOR_Y - pad.floor).abs() <= 2.0;
    if !underfoot && super::angle_difference(dz.atan2(dx), bot.yaw).abs() > FRAC_PI_3 {
        return false;
    }
    underfoot
        || crate::combat::line_of_sight(
            fighter_eye(bot),
            [pad.x, pad.y + 0.2, pad.z],
            &state.current_arena().solids,
        )
}

impl PadMemory {
    /// A round start puts every pad back; a regular knows that much.
    fn sync(&mut self, state: &GameState) {
        if self.round != Some(state.round_number) || self.beliefs.len() != state.pickups.len() {
            self.round = Some(state.round_number);
            self.beliefs = vec![
                Belief {
                    up: true,
                    back_at: None,
                };
                state.pickups.len()
            ];
        }
    }

    /// Update from what the bot can see this tick. Unseen pads whose clock
    /// has run out are assumed back.
    pub(super) fn look(&mut self, state: &GameState, bot: &Player) {
        self.sync(state);
        let team_clock = state.config.rules.teams();
        for (belief, pad) in self.beliefs.iter_mut().zip(&state.pickups) {
            if sees(state, bot, pad) {
                if pad.available {
                    *belief = Belief {
                        up: true,
                        back_at: None,
                    };
                } else {
                    let clock = u64::from(pad.clock(team_clock));
                    // Seen going, or first found gone: count from now either
                    // way. An earlier estimate stays; it was never later.
                    let back_at = match belief.back_at {
                        Some(at) if !belief.up => at,
                        _ => state.tick.saturating_add(clock),
                    };
                    *belief = Belief {
                        up: false,
                        back_at: Some(back_at),
                    };
                }
            } else if belief.back_at.is_some_and(|at| state.tick >= at) {
                *belief = Belief {
                    up: true,
                    back_at: None,
                };
            }
        }
    }

    /// Ticks until the bot expects `index` to be claimable: zero when it
    /// believes the pad is up now, `None` when it has no estimate. A personal
    /// stash is the bot's own business and needs no looking.
    pub(in crate::sim) fn eta(
        &self,
        state: &GameState,
        bot: &Player,
        index: usize,
        tick: u64,
    ) -> Option<u64> {
        let pad = state.pickups.get(index)?;
        if pad.claim == SupplyClaim::Personal {
            return (pad.available && !bot.inventory.claimed(&pad.id)).then_some(0);
        }
        let Some(belief) = self.beliefs.get(index).filter(|_| {
            self.round == Some(state.round_number) && self.beliefs.len() == state.pickups.len()
        }) else {
            // Nothing seen this round yet: every pad starts the round up.
            return Some(0);
        };
        if belief.up {
            return Some(0);
        }
        belief.back_at.map(|at| at.saturating_sub(tick))
    }
}
