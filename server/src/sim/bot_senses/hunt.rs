//! Hunting a quiet round. A rule bot that has seen nobody for a while goes
//! looking, and it looks only with what a player has: its ears and the map.
//!
//! It hears gunfire and blasts across a hall (less through walls) and running
//! footsteps close by, and it remembers which way a fighter it lost sight of
//! was going. A sound gives a rough place, never a body to aim at: the
//! estimate is off by a share of the distance, and the shared sight gates
//! still decide every shot. With nothing to go on it patrols the places
//! fights happen (the pads and the spawns), the stalest first, so two bots
//! on a big floor cross paths instead of each walking its own pad circuit.
//! The Duel survey on Sector 9 had no shot in twenty minutes before this.

use super::{feet_of, hostile, mix, salt, GameState, Player};
use std::f32::consts::TAU;

/// Gunfire carries this far with a clear line, in metres.
const GUNFIRE_OPEN: f32 = 60.0;
/// And this far through walls.
pub(crate) const GUNFIRE_WALLED: f32 = 36.0;
/// A blast carries further than a shot.
const BLAST_REACH: f32 = 72.0;
/// A pad being taken is heard this close: the pickup chime.
const PICKUP_REACH: f32 = 24.0;
/// Running feet are heard this close.
pub(crate) const FOOTSTEP_REACH: f32 = 18.0;
/// The ground speed that makes footsteps, metres a second: a run, not a
/// crouched walk.
pub(crate) const FOOTSTEP_SPEED: f32 = 3.5;
/// A sound's place is off by up to this share of its distance.
pub(crate) const EAR_ERROR: f32 = 0.15;
/// A clue is worth following for this long.
const CLUE_TICKS: u64 = 20 * 8;
/// A lost sighting is followed this far along the way it was going, in
/// seconds of its watched velocity.
const LOST_LEAD_SECONDS: f32 = 1.0;
/// Without a sighting or a hit for this long the round is quiet: top-ups
/// wait and the bot hunts.
pub(super) const QUIET_TICKS: u64 = 20 * 4;
/// A pad top-up this close is still taken in a quiet round.
pub(super) const QUIET_PAD_REACH: f32 = 10.0;
/// A clue or patrol spot this close is reached.
const ARRIVED: f32 = 3.0;
/// Passing this close to a patrol spot counts as checking it.
const CHECKED: f32 = 5.0;
/// A patrol spot nearer than this is not worth choosing.
const PATROL_MIN: f32 = 8.0;
/// Staleness counts up to this many seconds.
const STALE_CAP: f32 = 60.0;
/// Seconds of staleness one metre of walking costs.
const PATROL_DISTANCE_COST: f32 = 0.25;
/// A patrol leg that has not arrived by now is given up.
const PATROL_GIVE_UP: u64 = 20 * 30;
/// Ticks a bot looks around on arriving.
const SWEEP_TICKS: u64 = 16;
/// A power pad the bot believes is due back about when it could get there
/// is where an opponent will be: worth this many seconds of staleness.
const CONTEST_PULL: f32 = 30.0;
/// "About when": arriving no more than this many ticks early or late.
const CONTEST_WINDOW: u64 = 20 * 10;
/// Seconds of staleness a power pad is worth as a patrol spot.
const POWER_PULL: f32 = 20.0;
/// Seconds of staleness the map's edge costs against its middle.
const EDGE_COST: f32 = 40.0;
/// Spawns sampled around the ring as patrol spots.
const SPAWN_SPOTS: usize = 8;

#[derive(Debug, Clone, Copy, PartialEq, serde::Serialize, serde::Deserialize)]
#[serde(deny_unknown_fields)]
struct Clue {
    feet: [f32; 3],
    at: u64,
}

#[derive(Debug, Clone, Copy, PartialEq, serde::Serialize, serde::Deserialize)]
#[serde(deny_unknown_fields)]
struct Leg {
    spot: usize,
    feet: [f32; 3],
    since: u64,
}

/// What the bot is hunting toward.
#[derive(Debug, Clone, Copy, PartialEq)]
pub(super) enum Quarry {
    /// A sound or a lost sighting: go and look.
    Clue([f32; 3]),
    /// A patrol spot.
    Patrol([f32; 3]),
    /// Arrived: look around before the next leg.
    Sweep,
}

#[derive(Debug, Clone, Default, serde::Serialize, serde::Deserialize)]
#[serde(deny_unknown_fields)]
pub(super) struct Hunt {
    /// When the bot last saw an opponent or took a hit.
    contact: Option<u64>,
    clue: Option<Clue>,
    leg: Option<Leg>,
    sweep_until: u64,
    /// Last tick each patrol spot was checked, by spot index.
    checked: Vec<u64>,
}

/// The places a regular patrols: every pad that is not a secret and spawns
/// around the ring. Map knowledge, never a live position.
fn spots(state: &GameState) -> Vec<([f32; 3], Option<usize>)> {
    let mut spots: Vec<([f32; 3], Option<usize>)> = state
        .pickups
        .iter()
        .enumerate()
        .filter(|(_, pad)| !pad.secret)
        .map(|(index, pad)| ([pad.x, pad.floor, pad.z], Some(index)))
        .collect();
    for index in 0..SPAWN_SPOTS {
        let (x, z, _, floor) = state.map.spawn(index as f32 / SPAWN_SPOTS as f32 * TAU);
        spots.push(([x, floor, z], None));
    }
    spots
}

fn flat(a: [f32; 3], b: [f32; 3]) -> f32 {
    (a[0] - b[0]).hypot(a[2] - b[2])
}

/// Where a sound at `source` seems to come from: off by a bounded share of
/// its distance, the same way for the same bot and moment.
fn estimate(bot: &Player, source: [f32; 3], tick: u64) -> [f32; 3] {
    let distance = flat(feet_of(bot), source);
    let sample = mix(salt(bot.id) ^ tick.wrapping_mul(0x9e37_79b9_7f4a_7c15));
    let angle = (sample & 0xffff) as f32 / 65535.0 * TAU;
    let reach = ((sample >> 16) & 0xffff) as f32 / 65535.0 * EAR_ERROR * distance;
    [
        source[0] + angle.cos() * reach,
        source[1],
        source[2] + angle.sin() * reach,
    ]
}

impl Hunt {
    /// A new body keeps what it knows of the map, not its old errand.
    pub(super) fn respawned(&mut self) {
        self.clue = None;
        self.leg = None;
        self.sweep_until = 0;
    }

    /// Whether nothing has been seen or felt for `QUIET_TICKS`.
    pub(super) fn quiet(&self, tick: u64) -> bool {
        self.contact
            .is_none_or(|at| tick.saturating_sub(at) > QUIET_TICKS)
    }

    /// Listen and walk the patrol for one tick. `seen` is an opponent in
    /// view now; `lost` is where a fighter the bot stopped seeing was last
    /// watched, with its velocity and the tick; `hurt` is a fresh hit.
    pub(super) fn update(
        &mut self,
        state: &GameState,
        bot: &Player,
        seen: bool,
        lost: Option<([f32; 3], [f32; 2], u64)>,
        hurt: bool,
        pads: &super::pads::PadMemory,
    ) {
        let tick = state.tick;
        if seen || hurt {
            self.contact = Some(tick);
        }
        if seen {
            // A body in view is a fight, not a hunt.
            self.clue = None;
            self.leg = None;
            self.sweep_until = 0;
        }
        if let Some((feet, velocity, at)) = lost.filter(|_| !seen) {
            let ahead = [
                feet[0] + velocity[0] * LOST_LEAD_SECONDS,
                feet[1],
                feet[2] + velocity[1] * LOST_LEAD_SECONDS,
            ];
            if self.clue.is_none_or(|clue| clue.at < at) {
                self.clue = Some(Clue { feet: ahead, at });
            }
        }
        if !seen {
            if let Some(sound) = self.hear(state, bot) {
                self.clue = Some(Clue {
                    feet: estimate(bot, sound, tick),
                    at: tick,
                });
            }
        }
        let here = feet_of(bot);
        if self
            .clue
            .is_some_and(|clue| tick.saturating_sub(clue.at) > CLUE_TICKS)
        {
            self.clue = None;
        }
        if self
            .clue
            .is_some_and(|clue| flat(here, clue.feet) <= ARRIVED)
        {
            // Nobody here: look around, then carry on.
            self.clue = None;
            self.sweep_until = tick + SWEEP_TICKS;
        }
        let spots = spots(state);
        if self.checked.len() != spots.len() {
            self.checked = vec![0; spots.len()];
            self.leg = None;
        }
        for (index, (spot, _)) in spots.iter().enumerate() {
            if flat(here, *spot) <= CHECKED {
                self.checked[index] = tick.max(1);
            }
        }
        if let Some(leg) = self.leg {
            let arrived = flat(here, leg.feet) <= ARRIVED;
            if arrived {
                self.sweep_until = tick + SWEEP_TICKS;
            }
            if arrived || tick.saturating_sub(leg.since) > PATROL_GIVE_UP {
                self.checked[leg.spot] = tick.max(1);
                self.leg = None;
            }
        }
        if self.leg.is_none() && tick >= self.sweep_until {
            self.leg = self.next_leg(state, bot, &spots, pads);
        }
    }

    /// The loudest hostile sound in earshot this tick: last tick's gunfire
    /// and blasts, and running feet close by. Where it was, not who.
    fn hear(&self, state: &GameState, bot: &Player) -> Option<[f32; 3]> {
        let here = feet_of(bot);
        let solids = &state.current_arena().solids;
        let mut best: Option<(f32, [f32; 3])> = None;
        let mut consider = |distance: f32, feet: [f32; 3]| {
            if best.is_none_or(|(old, _)| distance < old) {
                best = Some((distance, feet));
            }
        };
        for other in &state.players {
            if !hostile(state, bot, other) {
                continue;
            }
            let feet = feet_of(other);
            let distance = flat(here, feet);
            if other.just_fired && distance <= GUNFIRE_OPEN {
                let open = distance <= GUNFIRE_WALLED
                    || crate::combat::line_of_sight(
                        super::fighter_eye(bot),
                        super::fighter_eye(other),
                        solids,
                    );
                if open {
                    consider(distance, feet);
                }
            }
            let running = other.vx.hypot(other.vz) >= FOOTSTEP_SPEED && !other.ducking;
            if running && distance <= FOOTSTEP_REACH {
                consider(distance, feet);
            }
        }
        for pad in &state.pickups {
            // Taken on the tick just played: its clock has not moved yet.
            let taken = !pad.available && pad.respawn_timer == Some(pad.clock(&state.config.rules));
            let feet = [pad.x, pad.floor, pad.z];
            let distance = flat(here, feet);
            let by_hostile = state
                .players
                .iter()
                .any(|other| hostile(state, bot, other) && flat(feet_of(other), feet) <= 2.5);
            if taken && by_hostile && distance <= PICKUP_REACH {
                consider(distance, feet);
            }
        }
        for blast in &state.explosion_results {
            let by_hostile = state
                .players
                .iter()
                .any(|owner| owner.id == blast.owner_id && hostile(state, bot, owner));
            let distance = flat(here, blast.position);
            if by_hostile && distance <= BLAST_REACH {
                consider(distance, blast.position);
            }
        }
        best.map(|(_, feet)| feet)
    }

    /// The stalest patrol spot for the walk, ties broken per bot.
    fn next_leg(
        &self,
        state: &GameState,
        bot: &Player,
        spots: &[([f32; 3], Option<usize>)],
        pads: &super::pads::PadMemory,
    ) -> Option<Leg> {
        let tick = state.tick;
        let here = feet_of(bot);
        let mut best: Option<(f32, Leg)> = None;
        for (index, (spot, pad)) in spots.iter().enumerate() {
            let spot = *spot;
            let distance = flat(here, spot);
            if distance < PATROL_MIN {
                continue;
            }
            let stale = match self.checked.get(index).copied().unwrap_or(0) {
                0 => STALE_CAP,
                at => (tick.saturating_sub(at) as f32 / 20.0).min(STALE_CAP),
            };
            let jitter = (mix(salt(bot.id) ^ index as u64 ^ (tick / 200)) % 400) as f32 / 100.0;
            // A power pad due back about when the bot could reach it: where
            // the other side will come for it, from the bot's own belief of
            // its clock. A pad believed up now has drawn nobody yet.
            let travel = (distance / super::WAIT_COST) as u64;
            let contest = pad
                .and_then(|pad| {
                    state
                        .pickups
                        .get(pad)
                        .filter(|pickup| pickup.kind.is_power())
                        .and(pads.eta(state, bot, pad, tick))
                })
                .is_some_and(|eta| eta > 0 && eta.abs_diff(travel) <= CONTEST_WINDOW);
            let pull = if contest { CONTEST_PULL } else { 0.0 };
            // Fights gather where the routes cross: power pads, and the
            // middle of the floor more than its edges. Two hunters that
            // favour the same places meet; two that sweep everything do not.
            let power = pad
                .and_then(|pad| state.pickups.get(pad))
                .is_some_and(|pickup| pickup.kind.is_power());
            let central = spot[0].hypot(spot[2]) / state.map.half_extent().max(1.0);
            let place = if power { POWER_PULL } else { 0.0 } - central * EDGE_COST;
            let score = stale + pull + place - distance * PATROL_DISTANCE_COST + jitter;
            if best.as_ref().is_none_or(|(old, _)| score > *old) {
                best = Some((
                    score,
                    Leg {
                        spot: index,
                        feet: spot,
                        since: tick,
                    },
                ));
            }
        }
        best.map(|(_, leg)| leg)
    }

    /// Where the hunt goes now: a fresh clue first, then the patrol leg.
    pub(super) fn quarry(&self, tick: u64) -> Option<Quarry> {
        if let Some(clue) = self.clue {
            return Some(Quarry::Clue(clue.feet));
        }
        if tick < self.sweep_until {
            return Some(Quarry::Sweep);
        }
        self.leg.map(|leg| Quarry::Patrol(leg.feet))
    }
}

/// A glance cycle while walking with nothing in view, in ticks.
const GLANCE_PERIOD: u64 = 64;

/// The head turn for `tick` of a walk, in eighths of a turn: a player
/// checking the doorways either side as it passes, not a gun on a swivel.
/// Left, back to the front, right, back to the front, staggered per bot.
fn glance_steps(bot: &Player, tick: u64) -> i32 {
    let phase = (tick + salt(bot.id) % GLANCE_PERIOD) % GLANCE_PERIOD;
    match phase {
        16..=19 | 28..=31 => 1,
        20..=27 => 2,
        48..=51 | 60..=63 => -1,
        52..=59 => -2,
        _ => 0,
    }
}

/// Turn the head off a straight walk without changing where the feet go: the
/// view swings by whole eighths and the keys swing back by the same amount
/// (`movement::wish_dir`), so the route the navigator chose is kept exactly.
pub(super) fn glance(
    bot: &Player,
    tick: u64,
    mut action: crate::protocol::Action,
) -> crate::protocol::Action {
    let walking = action.forward
        && !action.back
        && !action.left
        && !action.right
        && !action.fire
        && !action.turn_left
        && !action.turn_right
        && action.look_at.is_none();
    let Some(path) = action.yaw.filter(|_| walking) else {
        return action;
    };
    let steps = glance_steps(bot, tick);
    if steps == 0 {
        return action;
    }
    // Facing `steps` eighths toward +yaw, the feet keep the path with the
    // keys turned the other way: `left` walks a quarter turn below the view.
    action.yaw = Some(path + steps as f32 * std::f32::consts::FRAC_PI_4);
    match steps {
        1 => action.left = true,
        2 => {
            action.forward = false;
            action.left = true;
        }
        -1 => action.right = true,
        _ => {
            action.forward = false;
            action.right = true;
        }
    }
    action
}
