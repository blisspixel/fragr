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
use crate::roster::{Habits, PadHabit};
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
/// The fighter a bot owes is chosen over nearer ones as if this share of
/// their distance away.
const GRUDGE_PULL: f32 = 0.5;
/// A timed power pad outranks a fight only past this distance, in metres.
const APPOINTMENT_FIGHT: f32 = 12.0;
/// Meters of walking one tick of waiting is worth when choosing a pad.
const WAIT_COST: f32 = crate::movement::TOP_SPEED / 20.0;
/// Closer than this a bot never fires the Rocket. The splash reaches four
/// metres, but in the arena a fighter takes 0.6 of its own, so a blast three
/// metres off costs the shooter a few points and the target the rocket's
/// whole weight. On Larak Lot at six bots, rockets fired inside 6.5 m hurt
/// someone four times in five, for about 50 damage each: the best shots the
/// launcher has, and the range where a holder was dying with it holstered.
const ROCKET_SAFE: f32 = 3.0;
/// The Rocket's band: from a step outside the safe distance to where a
/// strafing body has walked out of the splash before the rocket arrives. A
/// holder keeps the launcher up anywhere in it, but fires only as close as
/// `ROCKET_SURE` (or from height, `ROCKET_FROM_ABOVE`).
const ROCKET_BAND: (f32, f32) = (3.5, 32.0);
/// The furthest a bot fires the Rocket at a body on its own floor. Measured
/// on Larak Lot at six bots, a rocket fired from 20 to 32 m hurt nobody four
/// times in five; inside 16 m two in three found a body. Past this a holder
/// closes in with the launcher up instead of spending its rack.
const ROCKET_SURE: f32 = 16.0;
/// A body at least this far below the shooter's floor is splashed off the
/// ground it stands on: from height the rocket is worth a longer shot.
const ROCKET_FROM_ABOVE: f32 = 1.5;
/// How far that longer shot from height reaches.
const ROCKET_FROM_ABOVE_REACH: f32 = 24.0;
/// A dropped Rocket the bot has seen this close, while it holds none,
/// outranks a fight across the lot the way a timed power pad does.
const ROCKET_DROP_REACH: f32 = 15.0;
/// The furthest a bot leads a rocket, in metres.
const ROCKET_MAX_LEAD: f32 = 4.0;
/// Height above the feet a bot aims the Rocket at: the shins. High error
/// still strikes the body; low error strikes the floor beside it.
const ROCKET_AIM_HEIGHT: f32 = 0.4;
/// The distance a bot readies its gun for between fights: the lot's
/// typical first sighting.
const READY_DISTANCE: f32 = 15.0;
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
    /// Ground velocity in metres a second, from two sightings in a row. Zero
    /// on a first sighting: a lead is only what the bot actually watched.
    velocity: [f32; 2],
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

/// Where a bot is going for a pad.
#[derive(Debug, Clone, Copy)]
struct PadPlan {
    feet: [f32; 3],
    /// Already standing on it, early for the clock.
    waiting: bool,
    /// The power pad this callsign keeps time on, or a Rocket dropped close
    /// by while the bot holds none: worth leaving a long fight for.
    timed: bool,
    /// A gun for a bot that holds nothing better than the Pistol.
    arms: bool,
}

/// How far an objective role may stray for a pad (`objective_pad`).
#[derive(Debug, Clone, Copy, PartialEq)]
pub(super) enum Leash {
    /// Carrying the flag: only health, and only a step off the way home.
    Carrier,
    /// Beside the carrier: a step off its line.
    Escort,
    /// On the way to the enemy flag: a short detour.
    Runner,
    /// Holding its own stand: pads within reach of it.
    Defender([f32; 3]),
}

/// Metres a carrier or an escort may add to its route for a pad.
const OBJECTIVE_DETOUR_CLOSE: f32 = 6.0;
/// Metres a runner may add.
const OBJECTIVE_DETOUR_RUNNER: f32 = 14.0;
/// A defender takes pads this close to its stand.
const OBJECTIVE_DEFENDER_REACH: f32 = 24.0;
/// An objective bot wants health at or below this.
const OBJECTIVE_HEALTH_NEED: i32 = 70;
/// And armour below this.
const OBJECTIVE_ARMOR_NEED: i32 = 50;

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

/// Whether `distance` sits in the band where `weapon` is the right gun.
fn in_band(weapon: WeaponType, distance: f32) -> bool {
    match weapon {
        WeaponType::Scatter => distance < 8.0,
        WeaponType::Rocket => (ROCKET_BAND.0..=ROCKET_BAND.1).contains(&distance),
        WeaponType::Rail => distance >= 12.0,
        WeaponType::Sniper => distance >= 30.0,
        WeaponType::Flechette => (5.0..=28.0).contains(&distance),
        WeaponType::Repeater => (5.0..=26.0).contains(&distance),
        WeaponType::Arc => (4.0..=18.0).contains(&distance),
        _ => false,
    }
}

/// The gun a personality wants for a fight at `distance`, among the guns it
/// can actually fire. The callsign's favourite comes first inside its own
/// band. New finds join each lane: the Sniper takes the longest sightlines,
/// the Repeater the middle, and the Rocket every mid-range fight it can win
/// clear of its own splash: a launcher left holstered dies with its owner.
fn preferred_weapon(
    behavior: BotBehavior,
    habits: Habits,
    bot: &Player,
    distance: f32,
) -> WeaponType {
    use WeaponType::{Flechette, Repeater, Rocket, Scatter, Sniper, Tack};
    let rail = WeaponType::Rail;
    let order: &[WeaponType] = match behavior {
        BotBehavior::Compliance => return bot.weapon,
        _ if bot.golden => &[rail],
        BotBehavior::Aggressive if distance < 10.0 => &[Scatter, Rocket, Repeater, Flechette],
        BotBehavior::Aggressive => &[Rocket, Repeater, Flechette, rail],
        BotBehavior::Defensive if distance > 30.0 => &[Sniper, rail, Flechette],
        BotBehavior::Defensive if distance > 12.0 => &[rail, Sniper, Rocket, Flechette],
        BotBehavior::Defensive => &[Rocket, Flechette, Repeater, Scatter],
        BotBehavior::Flanker if distance < 7.0 => &[Scatter, Flechette, Repeater],
        BotBehavior::Flanker => &[Rocket, Flechette, Repeater, rail],
        BotBehavior::Balanced if distance > 32.0 => &[Sniper, rail, Flechette],
        BotBehavior::Balanced if distance > 24.0 => &[rail, Sniper, Rocket, Flechette],
        BotBehavior::Balanced if distance < 6.0 => &[Scatter, Flechette],
        BotBehavior::Balanced => &[Rocket, Flechette, Repeater],
    };
    let fits = |weapon: &WeaponType| {
        bot.inventory.usable(*weapon)
            && (*weapon != Rocket || in_band(Rocket, distance))
            && *weapon != Tack
    };
    // A free-for-all life owns only the Pistol and what it took from the
    // floor: past the lane's own picks it fights with the best gun it owns,
    // the Pistol last, and never brings the Rocket inside its safe distance.
    Some(habits.favourite)
        .filter(|weapon| !bot.golden && in_band(*weapon, distance) && fits(weapon))
        .or_else(|| order.iter().copied().find(fits))
        .or_else(|| {
            GUNS.into_iter()
                .filter(|weapon| *weapon != Rocket || distance >= ROCKET_BAND.0)
                .find(|weapon| bot.inventory.usable(*weapon))
        })
        .unwrap_or(bot.weapon)
}

/// Where a bot fires the Rocket, and whether it may.
#[derive(Debug, Clone, Copy)]
struct RocketAim {
    point: [f32; 3],
    /// The blast lands clear of the shooter's own splash.
    clear: bool,
}

/// Aim the Rocket at `observed`: at the shins of the body where the bot
/// expects it to be when the rocket arrives, led by the ground velocity it
/// watched. Aimed low, the splash off the floor at its feet catches a strafe
/// a body shot would miss, and a high error still strikes the body. A body
/// standing above the shooter's floor, or shins out of sight behind a kerb,
/// takes the led chest instead. Hold fire unless the impact and the first
/// metres of the flight are clear of the shooter's own splash.
fn rocket_aim(state: &GameState, bot: &Player, observed: &Observation, distance: f32) -> RocketAim {
    let flight = distance / super::rocket::SPEED;
    let mut lead = [observed.velocity[0] * flight, observed.velocity[1] * flight];
    let length = lead[0].hypot(lead[1]);
    if length > ROCKET_MAX_LEAD {
        lead = [
            lead[0] / length * ROCKET_MAX_LEAD,
            lead[1] / length * ROCKET_MAX_LEAD,
        ];
    }
    let eye = fighter_eye(bot);
    let solids = &state.current_arena().solids;
    let feet = [
        observed.feet[0] + lead[0],
        observed.feet[1] + ROCKET_AIM_HEIGHT,
        observed.feet[2] + lead[1],
    ];
    let floor = bot.y - super::PLAYER_FLOOR_Y;
    let splash =
        observed.feet[1] <= floor + 0.75 && crate::combat::line_of_sight(eye, feet, solids);
    let point = if splash {
        feet
    } else {
        [
            observed.chest[0] + lead[0],
            observed.chest[1],
            observed.chest[2] + lead[1],
        ]
    };
    let ray = [point[0] - eye[0], point[1] - eye[1], point[2] - eye[2]];
    let reach = (ray[0] * ray[0] + ray[1] * ray[1] + ray[2] * ray[2]).sqrt();
    let clear = distance >= ROCKET_SAFE
        && reach >= ROCKET_SAFE
        && crate::combat::line_of_sight(
            eye,
            [
                eye[0] + ray[0] / reach * ROCKET_SAFE,
                eye[1] + ray[1] / reach * ROCKET_SAFE,
                eye[2] + ray[2] / reach * ROCKET_SAFE,
            ],
            solids,
        );
    RocketAim { point, clear }
}

/// Whether a rocket at `observed`, `distance` away, is worth one of the four
/// in the rack: inside `ROCKET_SURE`, or from height at a body below, whose
/// floor catches the splash.
fn rocket_shot(bot: &Player, observed: &Observation, distance: f32) -> bool {
    let below = bot.y - super::PLAYER_FLOOR_Y - observed.feet[1];
    distance <= ROCKET_SURE || (below >= ROCKET_FROM_ABOVE && distance <= ROCKET_FROM_ABOVE_REACH)
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

/// Whether `kind` is the pad these habits time (`roster::habits`): the
/// Plate (with ordinary armour on the way), the Railgun or Sniper, the
/// Scatter, the Rocket, or health.
fn habit(habits: Habits, kind: super::PickupKind) -> bool {
    use super::PickupKind;
    matches!(
        (habits.times, kind),
        (PadHabit::Plate, PickupKind::Armor | PickupKind::Plate)
            | (
                PadHabit::Rail,
                PickupKind::Weapon(WeaponType::Rail | WeaponType::Sniper)
            )
            | (PadHabit::Scatter, PickupKind::Weapon(WeaponType::Scatter))
            | (PadHabit::Rocket, PickupKind::Weapon(WeaponType::Rocket))
            | (PadHabit::Health, PickupKind::Health)
    )
}

/// A pad worth crossing the map for: the power pad a callsign times (not
/// the ordinary armour on the way to it), and the Custody Plate for anyone
/// already holding the gun they like: armed, the next thing worth having is
/// plate.
fn timed(habits: Habits, bot: &Player, kind: super::PickupKind) -> bool {
    let own = habit(habits, kind)
        && habits.times.map_wide()
        && kind.is_power()
        && kind != super::PickupKind::Armor;
    own || (kind == super::PickupKind::Plate && bot.inventory.usable(habits.favourite))
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

    /// The opponent in view at the latest observation, with the feet the
    /// bot saw: what a callout may name. Nothing older than one look.
    pub(super) fn sees_now(&self, tick: u64) -> Option<(Uuid, [f32; 3])> {
        self.target
            .filter(|target| target.visible && tick.saturating_sub(target.seen_at) < OBSERVE_EVERY)
            .map(|target| (target.id, target.feet))
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
        // Among new sightings the nearest wins, except the fighter this bot
        // owes (`grudge.rs`), who counts as much closer than they stand.
        let target = previous
            .and_then(|old| state.players.iter().find(|player| player.id == old.id))
            .filter(|target| visible(state, bot, target))
            .or_else(|| {
                let seen: Vec<&Player> = state
                    .players
                    .iter()
                    .filter(|target| hostile(state, bot, target) && visible(state, bot, target))
                    .collect();
                // The book is read only when there is a choice to make.
                let owed = (seen.len() > 1)
                    .then(|| state.grudge_of(&bot.name))
                    .flatten();
                let reach = |target: &Player| {
                    let distance = (target.x - bot.x).hypot(target.z - bot.z);
                    if Some(target.id) == owed {
                        distance * GRUDGE_PULL
                    } else {
                        distance
                    }
                };
                seen.into_iter()
                    .min_by(|a, b| reach(a).total_cmp(&reach(b)).then(a.id.cmp(&b.id)))
            });
        let hurt = self.hurt.filter(|hurt| {
            state.tick.saturating_sub(hurt.at) <= HURT_MEMORY
                && state
                    .players
                    .iter()
                    .any(|player| player.id == hurt.from && hostile(state, bot, player))
        });
        let target = if let Some(target) = target {
            let watched = previous.filter(|old| old.id == target.id && old.visible);
            let ready_at = watched
                .map(|old| old.ready_at)
                .unwrap_or_else(|| reaction(bot.id, target.id, state.tick));
            let feet = feet_of(target);
            let velocity =
                watched
                    .filter(|old| state.tick > old.seen_at)
                    .map_or([0.0, 0.0], |old| {
                        let seconds = (state.tick - old.seen_at) as f32 / 20.0;
                        let step = |axis: usize, slot: usize| {
                            let now = (feet[axis] - old.feet[axis]) / seconds;
                            // Half the new reading: a dodge does not swing the lead.
                            (old.velocity[slot] + now) * 0.5
                        };
                        [step(0, 0), step(2, 1)]
                    });
            Some(Observation {
                id: target.id,
                feet,
                chest: fighter_chest(target),
                velocity,
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
                velocity: [0.0, 0.0],
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
                    | GameMode::Duel
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

    /// This fighter's habits, read from the callsign it wears right now.
    pub(super) fn habits(&self, bot: &Player) -> Habits {
        crate::roster::habits(&bot.name, self.behavior)
    }

    /// Pad believed claimable soonest for its cost, with whether the bot is
    /// already standing at it waiting for the clock, and whether it is the
    /// power pad this callsign times.
    /// With `urgent`, only what is worth leaving a search for (see `gain`).
    fn pad_plan(
        &self,
        state: &GameState,
        bot: &Player,
        supplied: bool,
        urgent: bool,
    ) -> Option<PadPlan> {
        if bot.is_boss {
            return None;
        }
        let habits = self.habits(bot);
        let pistol_only = !GUNS
            .into_iter()
            .any(|gun| gun != WeaponType::Tack && bot.inventory.usable(gun));
        let mut best: Option<(f32, PadPlan)> = None;
        for (index, pad) in state.pickups.iter().enumerate() {
            let useful = match pad.kind {
                super::PickupKind::Weapon(weapon) => bot.inventory.weapon_pad_useful(weapon),
                super::PickupKind::Health => supplied && bot.hp < super::PLAYER_MAX_HP,
                super::PickupKind::Armor => supplied && bot.armor < super::PLAYER_MAX_ARMOR,
                super::PickupKind::Plate => supplied && bot.armor < super::PLATE_MAX_ARMOR,
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
                super::PickupKind::Armor | super::PickupKind::Plate => {
                    bot.hp + bot.armor < super::PLAYER_MAX_HP
                }
                super::PickupKind::Health => bot.hp < HURT_HP,
                _ => false,
            };
            let near = (pad.x - bot.x).hypot(pad.z - bot.z) <= HABIT_REACH;
            // The power pad a callsign times is an appointment from anywhere
            // on the map; its other habits only when they are close.
            let timed = timed(habits, bot, pad.kind);
            let habitual = habit(habits, pad.kind);
            let wanted = !urgent || gain || timed || (habitual && near);
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
            // The favourite gun is worth a detour while the hand lacks it.
            let favourite = pad.kind.weapon() == Some(habits.favourite)
                && !bot.inventory.usable(habits.favourite);
            let weight = if timed {
                0.3
            } else if habitual {
                0.5
            } else if favourite {
                0.6
            } else if pad.kind.is_power() {
                0.8
            } else {
                1.0
            };
            let cost = distance * weight + wait as f32 * WAIT_COST;
            if best.as_ref().is_none_or(|(old, _)| cost < *old) {
                best = Some((
                    cost,
                    PadPlan {
                        feet: [pad.x, pad.floor, pad.z],
                        waiting: eta > 0 && distance < 1.5,
                        timed,
                        arms: pad.kind.weapon().is_some() && pistol_only,
                    },
                ));
            }
        }
        // A gun somebody dropped, where this bot saw it lying: there now
        // or never, so no clock, and valued by the same habits as a pad.
        for gun in bot.bot_senses.pads.drops() {
            let weapon = gun.weapon;
            if !bot.inventory.weapon_pad_useful(weapon) {
                continue;
            }
            let kind = super::PickupKind::Weapon(weapon);
            let distance = (gun.feet[0] - bot.x).hypot(gun.feet[2] - bot.z);
            let gain = !bot.inventory.usable(weapon) && !bot.inventory.can_reload(weapon);
            let habitual = habit(habits, kind);
            let favourite = weapon == habits.favourite && !bot.inventory.usable(weapon);
            if urgent && !gain && !(habitual && distance <= HABIT_REACH) {
                continue;
            }
            let weight = if habitual {
                0.5
            } else if favourite {
                0.6
            } else if kind.is_power() {
                0.8
            } else {
                1.0
            };
            let cost = distance * weight;
            if best.as_ref().is_none_or(|(old, _)| cost < *old) {
                best = Some((
                    cost,
                    PadPlan {
                        feet: gun.feet,
                        waiting: false,
                        timed: weapon == WeaponType::Rocket
                            && gain
                            && distance <= ROCKET_DROP_REACH,
                        arms: pistol_only,
                    },
                ));
            }
        }
        best.map(|(_, plan)| plan)
    }

    /// A pad worth a short detour off an objective route to `goal`, within
    /// the role's `leash`. Only what the bot needs (health when hurt, armour
    /// when thin, rounds for a gun down to half its spawn kit) and only a pad
    /// it believes is up now, from its own view of the pads; never a live
    /// timer.
    pub(super) fn objective_pad(
        &self,
        state: &GameState,
        bot: &Player,
        goal: [f32; 3],
        leash: Leash,
    ) -> Option<[f32; 3]> {
        if !self.uses_senses(state, bot) || bot.is_boss {
            return None;
        }
        let (budget, anchor) = match leash {
            Leash::Carrier | Leash::Escort => (OBJECTIVE_DETOUR_CLOSE, None),
            Leash::Runner => (OBJECTIVE_DETOUR_RUNNER, None),
            Leash::Defender(stand) => (f32::MAX, Some(stand)),
        };
        let flat = |a: [f32; 3], b: [f32; 3]| (a[0] - b[0]).hypot(a[2] - b[2]);
        let here = feet_of(bot);
        let direct = flat(here, goal);
        let mut best: Option<(f32, [f32; 3])> = None;
        for (index, pad) in state.pickups.iter().enumerate() {
            let needed = match pad.kind {
                super::PickupKind::Health => bot.hp <= OBJECTIVE_HEALTH_NEED,
                super::PickupKind::Armor | super::PickupKind::Plate => {
                    leash != Leash::Carrier && bot.armor < OBJECTIVE_ARMOR_NEED
                }
                super::PickupKind::Weapon(weapon) => {
                    leash != Leash::Carrier
                        && bot.inventory.armed()
                        && bot.inventory.owns(weapon)
                        && bot.inventory.weapon_pad_useful(weapon)
                        && weapon.ammo_pool().is_some_and(|pool| {
                            bot.inventory.carried(pool) * 2 < pool.arcade_spawn()
                        })
                }
                _ => false,
            };
            if !needed || bot.bot_senses.pad_eta(state, bot, index) != Some(0) {
                continue;
            }
            let feet = [pad.x, pad.floor, pad.z];
            let distance = flat(here, feet);
            if anchor.is_some_and(|stand| flat(stand, feet) > OBJECTIVE_DEFENDER_REACH) {
                continue;
            }
            let extra = distance + flat(feet, goal) - direct;
            if extra > budget {
                continue;
            }
            if best.is_none_or(|(old, _)| distance < old) {
                best = Some((distance, feet));
            }
        }
        best.map(|(_, feet)| feet)
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
        // Between fights a bot has the gun for the next one in hand, so a
        // Rocket it walked to is up before the first body shows.
        let swap = swap.or_else(|| {
            (observed_distance == f32::MAX && !bot.inventory.reloading())
                .then(|| preferred_weapon(self.behavior, self.habits(bot), bot, READY_DISTANCE))
                .filter(|weapon| *weapon != bot.weapon && bot.inventory.usable(*weapon))
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
        // hurt and near health, goes there first. A timed power pad, or a
        // first real gun, also outranks a fight across the lot: a regular who
        // keeps time on the Plate walks away from a long trade to be there
        // when it lands, and a fresh life arms up before it duels with the
        // Pistol; a Rocket somebody dropped close by is worth the same. It
        // still shoots what it sees on the way.
        let walk_off = !visible || (observed_distance > APPOINTMENT_FIGHT && bot.hp >= HURT_HP);
        let appointment = walk_off
            .then(|| self.pad_plan(state, bot, supplied, true))
            .flatten()
            .filter(|plan| !visible || plan.timed || plan.arms);
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
        if let Some(PadPlan { feet, waiting, .. }) =
            appointment.or_else(|| self.pad_plan(state, bot, supplied, false))
        {
            // Walking to an appointment past a fight still shoots what it
            // sees, the way an objective route does.
            let aim = observation
                .filter(|observed| observed.visible && supplied)
                .map(|observed| {
                    self.observed_combat_intent(state, bot, observed, swap, true)
                        .action
                });
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
                return BotIntent {
                    action: aim.map_or(action, |aim| Action {
                        forward: false,
                        back: false,
                        left: aim.left,
                        right: aim.right,
                        ..aim
                    }),
                    goal: None,
                };
            }
            let mut action = super::face_flag_goal(bot, feet);
            action.weapon_swap = swap;
            if let Some(aim) = aim {
                action.yaw = aim.yaw;
                action.pitch = aim.pitch;
                action.weapon_swap = aim.weapon_swap;
                action.turn_left = false;
                action.turn_right = false;
                action.fire = aim.fire;
            }
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
        let distance = (observed.feet[0] - bot.x).hypot(observed.feet[2] - bot.z);
        if prefer && !bot.inventory.reloading() && swap.is_none() {
            let preferred = preferred_weapon(self.behavior, self.habits(bot), bot, distance);
            if preferred != bot.weapon && bot.inventory.usable(preferred) {
                swap = Some(preferred);
            }
        }
        let rocket = (bot.weapon == WeaponType::Rocket && swap.is_none())
            .then(|| rocket_aim(state, bot, &observed, distance));
        let point = rocket.map_or(observed.chest, |aim| aim.point);
        let Some((yaw, pitch)) = crate::combat::aim_at(fighter_eye(bot), point) else {
            return BotIntent::default();
        };
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
            // The Rocket's own splash: never fire it where the blast reaches
            // back, at a body inside the safe distance or into a wall in front.
            && rocket.is_none_or(|aim| aim.clear);
        if rocket.is_some() && distance < ROCKET_BAND.0 {
            // Too close for the launcher: give ground while the hand changes.
            intent.action.forward = false;
            intent.action.back = true;
        }
        if rocket.is_some() && !rocket_shot(bot, &observed, distance) {
            // A long shot on the level mostly hits nobody and empties a rack
            // of four: keep the launcher up and close to where it lands.
            intent.action.fire = false;
            intent.action.forward = true;
            intent.action.back = false;
        }
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
