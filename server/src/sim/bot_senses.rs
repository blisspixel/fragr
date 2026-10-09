//! Bounded observations for ordinary arcade opponents. Hidden poses never aim.

use super::{fighter_chest, fighter_eye, BotBehavior, BotController, BotIntent, GameState, Player};
use crate::navigation::NavigationGoal;
use crate::protocol::{Action, EquipmentPolicy, GameMode, WeaponType};
use std::f32::consts::{FRAC_PI_3, PI, TAU};
use uuid::Uuid;

const OBSERVE_EVERY: u64 = 2;
const MEMORY_TICKS: u64 = 40;
const SIGHT_RANGE: f32 = 64.0;
const AIM_ERROR: f32 = 0.055;
const TURN_PER_TICK: f32 = 0.1;

#[derive(Debug, Clone, Copy)]
struct Observation {
    id: Uuid,
    feet: [f32; 3],
    chest: [f32; 3],
    seen_at: u64,
    ready_at: u64,
    visible: bool,
}

#[derive(Debug, Clone, Default)]
pub(super) struct BotSenses {
    target: Option<Observation>,
    observed_at: Option<u64>,
}

fn angle_difference(to: f32, from: f32) -> f32 {
    (to - from + PI).rem_euclid(TAU) - PI
}

// Stateless mixing leaves gameplay RNG alone and repeats from the seeded roster.
fn mix(mut value: u64) -> u64 {
    value ^= value >> 30;
    value = value.wrapping_mul(0xbf58_476d_1ce4_e5b9);
    value ^= value >> 27;
    value = value.wrapping_mul(0x94d0_49bb_1331_11eb);
    value ^ (value >> 31)
}

fn salt(id: Uuid) -> u64 {
    let value = id.as_u128();
    value as u64 ^ (value >> 64) as u64
}

fn aim_error(id: Uuid, tick: u64) -> [f32; 2] {
    let sample = mix(salt(id) ^ (tick / 6).wrapping_mul(0x9e37_79b9_7f4a_7c15));
    let unit = |value: u64| ((value & 0xffff) as f32 / 32767.5 - 1.0) * AIM_ERROR;
    [unit(sample), unit(sample >> 32)]
}

fn hostile(state: &GameState, bot: &Player, target: &Player) -> bool {
    target.id != bot.id
        && state.contact_eligible(target)
        && crate::protocol::hostile(bot.campaign, target.campaign)
        && !(bot.team.is_some() && bot.team == target.team)
}

fn visible(state: &GameState, bot: &Player, target: &Player) -> bool {
    let dx = target.x - bot.x;
    let dz = target.z - bot.z;
    dx.hypot(dz) <= SIGHT_RANGE
        && angle_difference(dz.atan2(dx), bot.yaw).abs() <= FRAC_PI_3
        && crate::combat::line_of_sight(
            fighter_eye(bot),
            fighter_chest(target),
            &state.current_arena().solids,
        )
        && state.vehicles.iter().all(|vehicle| {
            if vehicle.state.seat(bot.id).is_some() || vehicle.state.seat(target.id).is_some() {
                return true;
            }
            crate::combat::line_of_sight(
                fighter_eye(bot),
                fighter_chest(target),
                std::slice::from_ref(&crate::vehicles::hull(&vehicle.state)),
            )
        })
}

impl BotSenses {
    fn observe(&self, state: &GameState, bot: &Player) -> Self {
        if state.tick % OBSERVE_EVERY != salt(bot.id) % OBSERVE_EVERY
            || self.observed_at == Some(state.tick)
        {
            return self.clone();
        }
        let previous = self.target.filter(|target| {
            state.tick.saturating_sub(target.seen_at) <= MEMORY_TICKS
                && state
                    .players
                    .iter()
                    .any(|player| player.id == target.id && hostile(state, bot, player))
        });
        // Keep a visible opponent until cover breaks contact. Changing targets
        // every observation otherwise lets the nearest crossing body steal aim.
        let target = previous
            .and_then(|old| state.players.iter().find(|player| player.id == old.id))
            .filter(|target| visible(state, bot, target))
            .or_else(|| {
                state
                    .players
                    .iter()
                    .filter(|target| hostile(state, bot, target) && visible(state, bot, target))
                    .min_by(|a, b| {
                        (a.x - bot.x)
                            .hypot(a.z - bot.z)
                            .total_cmp(&(b.x - bot.x).hypot(b.z - bot.z))
                            .then(a.id.cmp(&b.id))
                    })
            });
        let target = if let Some(target) = target {
            let ready_at = previous
                .filter(|old| old.id == target.id && old.visible)
                .map(|old| old.ready_at)
                .unwrap_or_else(|| {
                    // Between 200 and 400 ms after first observation, plus the
                    // staggered observation wait. No personality gets more HP.
                    state
                        .tick
                        .saturating_add(4 + mix(salt(bot.id) ^ salt(target.id) ^ state.tick) % 5)
                });
            Some(Observation {
                id: target.id,
                feet: [target.x, target.y - super::PLAYER_FLOOR_Y, target.z],
                chest: fighter_chest(target),
                seen_at: state.tick,
                ready_at,
                visible: true,
            })
        } else {
            previous.map(|mut old| {
                old.visible = false;
                old
            })
        };
        Self {
            target,
            observed_at: Some(state.tick),
        }
    }
}

impl GameState {
    pub(crate) fn update_bot_senses(&mut self, controllers: &[BotController]) {
        for controller in controllers {
            let Some(index) = self
                .players
                .iter()
                .position(|p| p.id == controller.player_id)
            else {
                continue;
            };
            let bot = &self.players[index];
            if !controller.uses_senses(self, bot) {
                // A playlist can carry an armed rule bot into a mode whose
                // controller still uses the established single ammunition pool.
                self.players[index].inventory.disarm_magazines();
                self.players[index].bot_senses = BotSenses::default();
                continue;
            }
            if !self.contact_eligible(bot) {
                self.players[index].bot_senses = BotSenses::default();
                continue;
            }
            let senses = bot.bot_senses.observe(self, bot);
            let bot = &mut self.players[index];
            bot.bot_senses = senses;
            if bot.contestant() && bot.inventory.policy() == EquipmentPolicy::FullArsenal {
                bot.inventory.arm_magazines();
                if !bot.inventory.usable(bot.weapon) && !bot.inventory.reloading() {
                    bot.inventory.request_reload(bot.weapon, self.tick);
                }
            }
        }
    }
}

impl BotController {
    pub(super) fn uses_senses(&self, state: &GameState, bot: &Player) -> bool {
        (bot.contestant() || self.behavior == BotBehavior::Compliance)
            && !state.map.is_campaign()
            && !state.solo_broadcast.enabled
            && bot.inventory.policy() == EquipmentPolicy::FullArsenal
            && matches!(
                state.config.rules.mode(),
                GameMode::Ffa | GameMode::Tdm | GameMode::Conquest
            )
    }

    pub(super) fn sensed_intent(&self, state: &GameState, bot: &Player) -> BotIntent {
        if !state.contact_eligible(bot) {
            return BotIntent::default();
        }
        let observation = bot.bot_senses.target.filter(|target| {
            state.tick.saturating_sub(target.seen_at) <= MEMORY_TICKS
                && state
                    .players
                    .iter()
                    .any(|p| p.id == target.id && hostile(state, bot, p))
        });
        let swap = if !bot.inventory.usable(bot.weapon)
            && !bot.inventory.reloading()
            && !bot.inventory.can_reload(bot.weapon)
        {
            WeaponType::ARCADE
                .into_iter()
                .find(|weapon| bot.inventory.usable(*weapon) || bot.inventory.can_reload(*weapon))
        } else {
            None
        };
        let supplied = bot.inventory.usable(bot.weapon)
            || bot.inventory.reloading()
            || bot.inventory.can_reload(bot.weapon)
            || swap.is_some();

        let observed_distance = observation
            .filter(|target| target.visible)
            .map_or(f32::MAX, |target| {
                (target.feet[0] - bot.x).hypot(target.feet[2] - bot.z)
            });
        if let Some(feet) = state.golden_rail_goal(bot, observed_distance) {
            let mut action = super::face_flag_goal(bot, feet);
            action.weapon_swap = swap;
            return BotIntent {
                action,
                goal: Some(NavigationGoal {
                    feet,
                    combat: false,
                }),
            };
        }

        if let Some(observed) = observation.filter(|_| supplied) {
            if !observed.visible {
                let mut action = super::face_flag_goal(bot, observed.feet);
                action.weapon_swap = swap;
                if (observed.feet[0] - bot.x).hypot(observed.feet[2] - bot.z) < 1.5 {
                    action.forward = false;
                    action.turn_right = true;
                    return BotIntent { action, goal: None };
                }
                return BotIntent {
                    action,
                    goal: Some(NavigationGoal {
                        feet: observed.feet,
                        combat: false,
                    }),
                };
            }
            return self.observed_combat_intent(state, bot, observed, swap);
        }

        // Known supplies and spawn locations are navigation knowledge. No live
        // opponent coordinates enter this search or its route destination.
        let supply = state
            .pickups
            .iter()
            .filter(|_| !bot.is_boss)
            .filter(|pad| pad.available)
            .filter(|pad| match pad.kind {
                super::PickupKind::Weapon(weapon) => bot.inventory.weapon_pad_useful(weapon),
                super::PickupKind::Health => supplied && bot.hp < super::PLAYER_MAX_HP,
                super::PickupKind::Armor => supplied && bot.armor < super::PLAYER_MAX_ARMOR,
                _ => false,
            })
            .min_by(|a, b| {
                (a.x - bot.x)
                    .hypot(a.z - bot.z)
                    .total_cmp(&(b.x - bot.x).hypot(b.z - bot.z))
            });
        let feet = supply
            .map(|pad| [pad.x, pad.floor, pad.z])
            .unwrap_or_else(|| {
                let slot = mix(salt(bot.id) ^ (state.tick / 80)) % 16;
                let (x, z, _, floor) = state.map.spawn(slot as f32 / 16.0 * TAU);
                [x, floor, z]
            });
        let mut action = super::face_flag_goal(bot, feet);
        action.weapon_swap = swap;
        BotIntent {
            action,
            goal: Some(NavigationGoal {
                feet,
                combat: false,
            }),
        }
    }

    /// Objective routing keeps its destination while combat uses the same
    /// delayed, bounded observations as ordinary arcade opponents.
    pub(super) fn sensed_objective_aim(&self, state: &GameState, bot: &Player) -> Option<Action> {
        if !self.uses_senses(state, bot) || !state.contact_eligible(bot) {
            return None;
        }
        let observed = bot.bot_senses.target.filter(|target| {
            target.visible
                && state.tick.saturating_sub(target.seen_at) < OBSERVE_EVERY
                && state
                    .players
                    .iter()
                    .any(|player| player.id == target.id && hostile(state, bot, player))
        })?;
        let swap = if !bot.inventory.usable(bot.weapon)
            && !bot.inventory.reloading()
            && !bot.inventory.can_reload(bot.weapon)
        {
            WeaponType::ARCADE
                .into_iter()
                .find(|weapon| bot.inventory.usable(*weapon) || bot.inventory.can_reload(*weapon))
        } else {
            None
        };
        Some(
            self.observed_combat_intent(state, bot, observed, swap)
                .action,
        )
    }

    fn observed_combat_intent(
        &self,
        state: &GameState,
        bot: &Player,
        observed: Observation,
        mut swap: Option<WeaponType>,
    ) -> BotIntent {
        let Some((yaw, pitch)) = crate::combat::aim_at(fighter_eye(bot), observed.chest) else {
            return BotIntent::default();
        };
        if !bot.inventory.reloading() && swap.is_none() {
            let distance = (observed.feet[0] - bot.x).hypot(observed.feet[2] - bot.z);
            let preferred = match self.behavior {
                BotBehavior::Compliance => bot.weapon,
                _ if bot.golden => WeaponType::Rail,
                BotBehavior::Aggressive if distance < 10.0 => WeaponType::Scatter,
                BotBehavior::Defensive if distance > 12.0 => WeaponType::Rail,
                BotBehavior::Flanker if distance < 7.0 => WeaponType::Scatter,
                BotBehavior::Balanced if distance > 24.0 => WeaponType::Rail,
                BotBehavior::Balanced if distance < 6.0 => WeaponType::Scatter,
                _ => WeaponType::Flechette,
            };
            if preferred != bot.weapon && bot.inventory.usable(preferred) {
                swap = Some(preferred);
            }
        }
        let [yaw_error, pitch_error] = aim_error(bot.id, state.tick);
        // The arcade enforcer keeps its precise long-lane role. Its eyes,
        // reaction and turn speed are still subject to the same gates.
        let precision = if self.behavior == BotBehavior::Compliance {
            0.25
        } else {
            1.0
        };
        let wanted_yaw = yaw + yaw_error * precision;
        let difference = angle_difference(wanted_yaw, bot.yaw);
        let mut intent = self.engage_at(
            state,
            bot,
            observed.feet,
            (observed.feet[0] - bot.x).hypot(observed.feet[2] - bot.z),
            difference,
            Action {
                yaw: Some(bot.yaw + difference.clamp(-TURN_PER_TICK, TURN_PER_TICK)),
                pitch: crate::combat::clamp_pitch(pitch + pitch_error * precision),
                weapon_swap: swap,
                ..Action::default()
            },
        );
        intent.action.turn_left = false;
        intent.action.turn_right = false;
        intent.action.fire &= state.tick >= observed.ready_at
            && difference.abs() <= TURN_PER_TICK + 0.03
            && bot.inventory.usable(bot.weapon)
            && swap.is_none();
        intent
    }

    /// Routing may remove combat intent but cannot restore a blind or early shot.
    /// This veto reads live visibility only, never feeds live coordinates to aim.
    pub(crate) fn guard_sensed_action(&self, state: &GameState, mut action: Action) -> Action {
        let Some(bot) = state.players.iter().find(|p| p.id == self.player_id) else {
            return Action::default();
        };
        if !self.uses_senses(state, bot) || !action.fire {
            return action;
        }
        action.fire = bot.bot_senses.target.is_some_and(|observed| {
            observed.visible
                && state.tick >= observed.ready_at
                && state.tick.saturating_sub(observed.seen_at) < OBSERVE_EVERY
                && state.players.iter().any(|target| {
                    target.id == observed.id
                        && hostile(state, bot, target)
                        && visible(state, bot, target)
                })
        });
        action
    }
}

#[cfg(test)]
mod tests;
