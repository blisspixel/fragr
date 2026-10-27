//! What a rule bot believes about the map's pads. A bot sees a pad the way it
//! sees a fighter: inside its view cone, within sight range and past cover,
//! or underfoot. It learns a pad's state only from that view and keeps the
//! published return clocks a regular learns, so it can be at the Railgun
//! when it comes back without ever reading a live timer.
//!
//! A gun dropped on death (`sim::drops`) is known the same way: only once
//! seen, believed there until the bot sees the spot empty or a regular's
//! sense of how long a dropped gun lies has passed since it first saw it.
use super::super::{fighter_eye, ArenaPickup, GameState, Player};
use crate::protocol::{SupplyClaim, WeaponType};
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

/// A dropped gun the bot has seen and believes is still lying there.
#[derive(Debug, Clone, Copy, PartialEq)]
pub(in crate::sim) struct DropBelief {
    pub(in crate::sim) serial: u32,
    pub(in crate::sim) weapon: WeaponType,
    pub(in crate::sim) feet: [f32; 3],
    /// Drawn height, for the sight line.
    y: f32,
    /// Past this the bot assumes it is gone.
    gone_at: u64,
}

#[derive(Debug, Clone, Default)]
pub(in crate::sim) struct PadMemory {
    round: Option<u32>,
    beliefs: Vec<Belief>,
    drops: Vec<DropBelief>,
}

/// Whether `bot` can see `pad` right now.
pub(super) fn sees(state: &GameState, bot: &Player, pad: &ArenaPickup) -> bool {
    sees_spot(state, bot, [pad.x, pad.floor, pad.z], pad.y)
}

/// Whether `bot` can see something lying at `feet`, drawn at height `y`.
fn sees_spot(state: &GameState, bot: &Player, feet: [f32; 3], y: f32) -> bool {
    let dx = feet[0] - bot.x;
    let dz = feet[2] - bot.z;
    let distance = dx.hypot(dz);
    if distance > PAD_SIGHT {
        return false;
    }
    let underfoot =
        distance <= UNDERFOOT && (bot.y - super::super::PLAYER_FLOOR_Y - feet[1]).abs() <= 2.0;
    if !underfoot && super::angle_difference(dz.atan2(dx), bot.yaw).abs() > FRAC_PI_3 {
        return false;
    }
    underfoot
        || crate::combat::line_of_sight(
            fighter_eye(bot),
            [feet[0], y + 0.2, feet[2]],
            &state.current_arena().solids,
        )
}

impl PadMemory {
    /// A round start puts every pad back; a regular knows that much.
    fn sync(&mut self, state: &GameState) {
        if self.round != Some(state.round_number) || self.beliefs.len() != state.pickups.len() {
            if self.round != Some(state.round_number) {
                self.drops.clear();
            }
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
        for (belief, pad) in self.beliefs.iter_mut().zip(&state.pickups) {
            if sees(state, bot, pad) {
                if pad.available {
                    *belief = Belief {
                        up: true,
                        back_at: None,
                    };
                } else {
                    let clock = u64::from(pad.clock(&state.config.rules));
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
        self.look_at_drops(state, bot);
    }

    /// Learn the dropped guns in view, and forget those whose spot is in
    /// view and empty, or that have surely lain too long.
    fn look_at_drops(&mut self, state: &GameState, bot: &Player) {
        let tick = state.tick;
        self.drops.retain(|belief| {
            tick < belief.gone_at
                && (state
                    .dropped_guns
                    .iter()
                    .any(|gun| gun.serial == belief.serial)
                    || !sees_spot(state, bot, belief.feet, belief.y))
        });
        for gun in &state.dropped_guns {
            if self.drops.iter().any(|belief| belief.serial == gun.serial)
                || !sees_spot(state, bot, [gun.x, gun.floor, gun.z], gun.y)
            {
                continue;
            }
            self.drops.push(DropBelief {
                serial: gun.serial,
                weapon: gun.weapon,
                feet: [gun.x, gun.floor, gun.z],
                y: gun.y,
                // Found lying there: the bot cannot know how long it has.
                gone_at: tick + u64::from(crate::sim::drops::DROPPED_GUN_TICKS),
            });
        }
    }

    /// The dropped guns this bot believes are lying where it saw them.
    pub(in crate::sim) fn drops(&self) -> &[DropBelief] {
        &self.drops
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
