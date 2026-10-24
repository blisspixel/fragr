//! Bounded observations for ordinary arcade opponents. Hidden poses never aim.
//!
//! Every arcade mode's rule bots see through the same gates: a 120 degree
//! view cone, a sight range, authoritative cover and vehicle hulls, a 200 to
//! 400 ms reaction to a new sighting, bounded aim error and a turn limit. A
//! hit reveals where the shot came from, never where the shooter went, and
//! kicks the victim's aim for a few ticks. Pads are seen the same way and
//! remembered with their published clocks (`pads.rs`).

use super::{fighter_chest, fighter_eye, BotBehavior, BotController, BotIntent, GameState, Player};
use crate::navigation::NavigationGoal;
use crate::protocol::{Action, EquipmentPolicy, GameMode, WeaponType};
use std::f32::consts::{FRAC_PI_3, PI, TAU};
use uuid::Uuid;

mod pads;

const OBSERVE_EVERY: u64 = 2;
const MEMORY_TICKS: u64 = 40;
const SIGHT_RANGE: f32 = 64.0;
const AIM_ERROR: f32 = 0.055;
const TURN_PER_TICK: f32 = 0.1;
/// A hit is a clue to where the shooter stood for this long.
const HURT_MEMORY: u64 = 40;
/// Taking damage spoils the victim's aim for this long.
const FLINCH_TICKS: u64 = 6;
/// Aim error multiplier while flinching.
const FLINCH_AIM: f32 = 3.0;
/// A bot leaves for a pad that is not back yet only when it would otherwise
/// arrive no more than this early.
const APPOINTMENT_SLACK: u64 = 40;
/// Below this a bot breaks off a search for health it knows about.
const HURT_HP: i32 = 50;
/// A habit pad breaks off a search only this close, in metres.
const HABIT_REACH: f32 = 20.0;
/// Meters of walking one tick of waiting is worth when choosing a pad.
const WAIT_COST: f32 = crate::movement::TOP_SPEED / 20.0;
/// Guns a bot may hold, in its fallback order when the hand runs dry.
const GUNS: [WeaponType; 8] = [
    WeaponType::Flechette,
    WeaponType::Repeater,
    WeaponType::Rail,
    WeaponType::Sniper,
    WeaponType::Scatter,
    WeaponType::Rocket,
    WeaponType::Arc,
    WeaponType::Tack,
];

#[derive(Debug, Clone, Copy)]
struct Observation {
    id: Uuid,
    feet: [f32; 3],
    chest: [f32; 3],
    seen_at: u64,
    ready_at: u64,
    visible: bool,
}

/// Where a damaging shot came from, at the moment it landed.
#[derive(Debug, Clone, Copy)]
struct Hurt {
    from: Uuid,
    feet: [f32; 3],
    at: u64,
}

#[derive(Debug, Clone, Default)]
pub(super) struct BotSenses {
    target: Option<Observation>,
    observed_at: Option<u64>,
    hurt: Option<Hurt>,
    flinch_until: u64,
    pads: pads::PadMemory,
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

/// Between 200 and 400 ms after the observation, plus the staggered
/// observation wait. No personality reacts faster.
fn reaction(bot: Uuid, target: Uuid, tick: u64) -> u64 {
    tick.saturating_add(4 + mix(salt(bot) ^ salt(target) ^ tick) % 5)
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

fn feet_of(player: &Player) -> [f32; 3] {
    [player.x, player.y - super::PLAYER_FLOOR_Y, player.z]
}

/// The gun a personality wants for a fight at `distance`, among the guns it
/// can actually fire. New finds join each lane: the Sniper takes the longest
/// sightlines, the Repeater the middle, the Rocket a mid-range push that
/// stays clear of its own splash.
fn preferred_weapon(behavior: BotBehavior, bot: &Player, distance: f32) -> WeaponType {
    use WeaponType::{Flechette, Repeater, Rocket, Scatter, Sniper, Tack};
    let rail = WeaponType::Rail;
    let order: &[WeaponType] = match behavior {
        BotBehavior::Compliance => return bot.weapon,
        _ if bot.golden => &[rail],
        BotBehavior::Aggressive if distance < 10.0 => &[Scatter, Repeater, Flechette, Tack],
        BotBehavior::Aggressive if distance < 24.0 => &[Rocket, Repeater, Flechette, Tack],
        BotBehavior::Defensive if distance > 30.0 => &[Sniper, rail, Flechette, Tack],
        BotBehavior::Defensive if distance > 12.0 => &[rail, Sniper, Flechette, Tack],
        BotBehavior::Flanker if distance < 7.0 => &[Scatter, Flechette, Repeater, Tack],
        BotBehavior::Balanced if distance > 32.0 => &[Sniper, rail, Flechette, Tack],
        BotBehavior::Balanced if distance > 24.0 => &[rail, Sniper, Flechette, Tack],
        BotBehavior::Balanced if distance < 6.0 => &[Scatter, Flechette, Tack],
        BotBehavior::Balanced if distance > 9.0 => &[Rocket, Flechette, Repeater, Tack],
        _ => &[Flechette, Repeater, Tack],
    };
    order
        .iter()
        .copied()
        .find(|weapon| bot.inventory.usable(*weapon))
        .unwrap_or(bot.weapon)
}

/// The next gun when the one in hand is dry and cannot reload.
fn dry_swap(bot: &Player) -> Option<WeaponType> {
    if bot.inventory.usable(bot.weapon)
        || bot.inventory.reloading()
        || bot.inventory.can_reload(bot.weapon)
    {
        return None;
    }
    GUNS.into_iter()
        .find(|weapon| bot.inventory.usable(*weapon) || bot.inventory.can_reload(*weapon))
}

/// The pad each personality times. Nightfall's Night Watch line keeps the
/// rail; the Static Kids push the scatter; Aunt Linda farms health; the
/// rushers want plate before they go in.
fn habit(behavior: BotBehavior, kind: super::PickupKind) -> bool {
    use super::PickupKind;
    matches!(
        (behavior, kind),
        (
            BotBehavior::Defensive,
            PickupKind::Weapon(WeaponType::Rail | WeaponType::Sniper)
        ) | (
            BotBehavior::Flanker,
            PickupKind::Weapon(WeaponType::Scatter)
        ) | (BotBehavior::Balanced, PickupKind::Health)
            | (BotBehavior::Aggressive, PickupKind::Armor)
    )
}

impl BotSenses {
    /// A new body: no target, no hurt, no flinch. Pad memory survives.
    pub(super) fn forget_fighters(&mut self) {
        let pads = std::mem::take(&mut self.pads);
        *self = Self {
            pads,
            ..Self::default()
        };
    }

    /// Ticks until this bot expects pad `index` to be claimable; zero when
    /// it believes the pad is up. Read from its own view, never a live timer.
    pub(super) fn pad_eta(&self, state: &GameState, bot: &Player, index: usize) -> Option<u64> {
        self.pads.eta(state, bot, index, state.tick)
    }

    /// A damaging hit from `from`, who stood at `feet` when it landed.
    pub(super) fn hurt_by(&mut self, from: Uuid, feet: [f32; 3], tick: u64) {
        self.hurt = Some(Hurt {
            from,
            feet,
            at: tick,
        });
        self.flinch_until = tick.saturating_add(FLINCH_TICKS);
    }

    fn observe(&self, state: &GameState, bot: &Player) -> Self {
        if state.tick % OBSERVE_EVERY != salt(bot.id) % OBSERVE_EVERY
            || self.observed_at == Some(state.tick)
        {
            return self.clone();
        }
        let mut pads = self.pads.clone();
        if (state.tick / OBSERVE_EVERY) % (pads::LOOK_EVERY / OBSERVE_EVERY)
            == (salt(bot.id) >> 8) % (pads::LOOK_EVERY / OBSERVE_EVERY)
        {
            pads.look(state, bot);
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
        let hurt = self.hurt.filter(|hurt| {
            state.tick.saturating_sub(hurt.at) <= HURT_MEMORY
                && state
                    .players
                    .iter()
                    .any(|player| player.id == hurt.from && hostile(state, bot, player))
        });
        let target = if let Some(target) = target {
            let ready_at = previous
                .filter(|old| old.id == target.id && old.visible)
                .map(|old| old.ready_at)
                .unwrap_or_else(|| reaction(bot.id, target.id, state.tick));
            Some(Observation {
                id: target.id,
                feet: feet_of(target),
                chest: fighter_chest(target),
                seen_at: state.tick,
                ready_at,
                visible: true,
            })
        } else if let Some(hurt) =
            hurt.filter(|hurt| previous.is_none_or(|old| old.seen_at < hurt.at))
        {
            // Shot by someone out of view: turn toward where the shot came
            // from. Reacquiring them still takes a fresh reaction.
            Some(Observation {
                id: hurt.from,
                feet: hurt.feet,
                chest: [hurt.feet[0], hurt.feet[1] + 1.2, hurt.feet[2]],
                seen_at: hurt.at,
                ready_at: reaction(bot.id, hurt.from, state.tick),
                visible: false,
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
            hurt,
            flinch_until: self.flinch_until,
            pads,
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
                self.players[index].bot_senses.forget_fighters();
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
            && matches!(
                state.config.rules.mode(),
                GameMode::Ffa
                    | GameMode::Tdm
                    | GameMode::Conquest
                    | GameMode::Ctf
                    | GameMode::Sabotage
            )
    }

    /// The opponent this bot is looking at right now, with its observed
    /// distance, if it is inside `reach`. Objective controllers fight what
    /// this returns; they never pick a body nobody could see.
    pub(super) fn sensed_enemy<'a>(
        &self,
        state: &'a GameState,
        bot: &Player,
        reach: f32,
    ) -> Option<(&'a Player, f32)> {
        if !self.uses_senses(state, bot) {
            return None;
        }
        let observed = bot.bot_senses.target.filter(|target| {
            target.visible && state.tick.saturating_sub(target.seen_at) < OBSERVE_EVERY
        })?;
        let distance = (observed.feet[0] - bot.x).hypot(observed.feet[2] - bot.z);
        if distance > reach {
            return None;
        }
        state
            .players
            .iter()
            .find(|player| player.id == observed.id && hostile(state, bot, player))
            .map(|player| (player, distance))
    }

    /// Where an opponent was last seen or last fired from, while that clue
    /// is fresh and nobody is in view.
    pub(super) fn sensed_threat(&self, state: &GameState, bot: &Player) -> Option<[f32; 3]> {
        if !self.uses_senses(state, bot) {
            return None;
        }
        bot.bot_senses
            .target
            .filter(|target| {
                !target.visible && state.tick.saturating_sub(target.seen_at) <= HURT_MEMORY
            })
            .map(|target| target.feet)
    }

    /// Fight the current observation with `swap` as the hand's next gun. With
    /// `prefer`, the personality may choose a better gun for the distance.
    pub(super) fn sensed_fight(
        &self,
        state: &GameState,
        bot: &Player,
        swap: Option<WeaponType>,
        prefer: bool,
    ) -> Option<BotIntent> {
        let observed = bot.bot_senses.target.filter(|target| {
            target.visible && state.tick.saturating_sub(target.seen_at) < OBSERVE_EVERY
        })?;
        Some(self.observed_combat_intent(state, bot, observed, swap, prefer))
    }

    /// Pad believed claimable soonest for its cost, with whether the bot is
    /// already standing at it waiting for the clock.
    /// With `urgent`, only what is worth leaving a search for (see `gain`).
    fn pad_plan(
        &self,
        state: &GameState,
        bot: &Player,
        supplied: bool,
        urgent: bool,
    ) -> Option<([f32; 3], bool)> {
        if bot.is_boss {
            return None;
        }
        let mut best: Option<(f32, [f32; 3], bool)> = None;
        for (index, pad) in state.pickups.iter().enumerate() {
            let useful = match pad.kind {
                super::PickupKind::Weapon(weapon) => bot.inventory.weapon_pad_useful(weapon),
                super::PickupKind::Health => supplied && bot.hp < super::PLAYER_MAX_HP,
                super::PickupKind::Armor => supplied && bot.armor < super::PLAYER_MAX_ARMOR,
                _ => false,
            };
            // Worth dropping a search for: a gun the bot cannot fire yet,
            // plate or health when hurt, or its own habit pad close by.
            // A top-up of a gun already in hand never breaks a chase.
            let gain = match pad.kind {
                super::PickupKind::Weapon(weapon) => {
                    !bot.inventory.usable(weapon) && !bot.inventory.can_reload(weapon)
                }
                // Plate when the body has actually been worn down.
                super::PickupKind::Armor => bot.hp + bot.armor < super::PLAYER_MAX_HP,
                super::PickupKind::Health => bot.hp < HURT_HP,
                _ => false,
            };
            let near = (pad.x - bot.x).hypot(pad.z - bot.z) <= HABIT_REACH;
            let wanted = !urgent || gain || (habit(self.behavior, pad.kind) && near);
            if !useful || !wanted {
                continue;
            }
            let Some(eta) = bot.bot_senses.pad_eta(state, bot, index) else {
                continue;
            };
            let distance = (pad.x - bot.x).hypot(pad.z - bot.z);
            let travel = (distance / WAIT_COST) as u64;
            if eta > travel.saturating_add(APPOINTMENT_SLACK) {
                continue;
            }
            let wait = eta.saturating_sub(travel);
            let weight = if habit(self.behavior, pad.kind) {
                0.5
            } else if pad.kind.is_power() {
                0.8
            } else {
                1.0
            };
            let cost = distance * weight + wait as f32 * WAIT_COST;
            if best.is_none_or(|(old, _, _)| cost < old) {
                best = Some((cost, [pad.x, pad.floor, pad.z], eta > 0 && distance < 1.5));
            }
        }
        best.map(|(_, feet, waiting)| (feet, waiting))
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
        let swap = dry_swap(bot);
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

        let visible = observation.is_some_and(|observed| observed.visible);
        // A search can wait for the clock: a bot whose pad is due, or who is
        // hurt and near health, goes there first.
        let appointment = (!visible)
            .then(|| self.pad_plan(state, bot, supplied, true))
            .flatten();
        if let Some(observed) = observation.filter(|_| supplied && appointment.is_none()) {
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
            return self.observed_combat_intent(state, bot, observed, swap, true);
        }

        // Known supplies and spawn locations are navigation knowledge. No live
        // opponent coordinates or live pad timers enter this search.
        if let Some((feet, waiting)) =
            appointment.or_else(|| self.pad_plan(state, bot, supplied, false))
        {
            if waiting {
                // Early for the appointment: hold the pad and sweep the
                // approaches rather than standing blind on it.
                let sweep_left = (state.tick / 30).is_multiple_of(2);
                let action = Action {
                    turn_left: sweep_left,
                    turn_right: !sweep_left,
                    weapon_swap: swap,
                    ..Action::default()
                };
                return BotIntent { action, goal: None };
            }
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
        let slot = mix(salt(bot.id) ^ (state.tick / 80)) % 16;
        let (x, z, _, floor) = state.map.spawn(slot as f32 / 16.0 * TAU);
        let feet = [x, floor, z];
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
        Some(
            self.observed_combat_intent(state, bot, observed, dry_swap(bot), true)
                .action,
        )
    }

    fn observed_combat_intent(
        &self,
        state: &GameState,
        bot: &Player,
        observed: Observation,
        mut swap: Option<WeaponType>,
        prefer: bool,
    ) -> BotIntent {
        let Some((yaw, pitch)) = crate::combat::aim_at(fighter_eye(bot), observed.chest) else {
            return BotIntent::default();
        };
        let distance = (observed.feet[0] - bot.x).hypot(observed.feet[2] - bot.z);
        if prefer && !bot.inventory.reloading() && swap.is_none() {
            let preferred = preferred_weapon(self.behavior, bot, distance);
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
        // A fresh hit spoils the aim for a few ticks: shots go wide.
        let precision = if state.tick < bot.bot_senses.flinch_until {
            precision * FLINCH_AIM
        } else {
            precision
        };
        let wanted_yaw = yaw + yaw_error * precision;
        let difference = angle_difference(wanted_yaw, bot.yaw);
        let mut intent = self.engage_at(
            state,
            bot,
            observed.feet,
            distance,
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
            && swap.is_none()
            // The Rocket's own splash: never fire it into a body at arm's length.
            && !(bot.weapon == WeaponType::Rocket && distance < 4.0);
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
