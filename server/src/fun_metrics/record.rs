//! The one shape a fun metrics file holds: counts, durations, booleans and
//! closed enums about a match, never about a person.
//!
//! This file deliberately names no text, id or address type. A test reads it
//! and fails if one appears, and another walks a fully populated record and
//! fails on any field that is not listed in `docs/PRIVACY.md`. A field is
//! added here, there and in the test's list in the same change, or not at all.
use crate::protocol::{GameMode, HitZone, Mutator, WeaponType};
use crate::sim::BotSkill;
use serde::{Deserialize, Serialize};

/// The record schema. One current shape; an older file is refused, never
/// migrated.
pub const RECORD_SCHEMA: u32 = 1;

/// The most samples one list keeps in one match. A match is minutes long,
/// so this only bounds a server left on one endless round.
pub const SAMPLES_KEPT: usize = 65_536;

/// One value per gun, in `WeaponType::ALL` order. Written as a map from the
/// gun's wire id, leaving out guns with nothing to say.
#[derive(Debug, Clone, PartialEq)]
pub struct WeaponTable<T>(pub [T; WeaponType::ALL.len()]);

impl<T: Default> Default for WeaponTable<T> {
    fn default() -> Self {
        Self(std::array::from_fn(|_| T::default()))
    }
}

impl<T> WeaponTable<T> {
    pub fn get(&self, weapon: WeaponType) -> &T {
        &self.0[weapon.index()]
    }

    pub fn get_mut(&mut self, weapon: WeaponType) -> &mut T {
        &mut self.0[weapon.index()]
    }

    /// Every gun with its value.
    pub fn iter(&self) -> impl Iterator<Item = (WeaponType, &T)> {
        WeaponType::ALL.into_iter().zip(self.0.iter())
    }
}

/// An unordered bag of whole-number measurements: ticks for a time,
/// centimetres for a distance. Kept sorted on disk, so it is a distribution
/// and never a timeline.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
#[serde(transparent)]
pub struct Samples(pub Vec<u32>);

impl Samples {
    pub fn push(&mut self, value: u32) {
        if self.0.len() < SAMPLES_KEPT {
            self.0.push(value);
        }
    }

    pub fn extend(&mut self, other: &Samples) {
        for value in &other.0 {
            self.push(*value);
        }
    }

    pub fn len(&self) -> usize {
        self.0.len()
    }

    pub fn is_empty(&self) -> bool {
        self.0.is_empty()
    }

    pub fn sort(&mut self) {
        self.0.sort_unstable();
    }

    /// The values scaled to a unit: ticks to seconds, centimetres to metres.
    pub fn scaled(&self, unit: f64) -> Vec<f64> {
        self.0
            .iter()
            .map(|value| f64::from(*value) * unit)
            .collect()
    }
}

/// Sabotage rounds, read by the uniform that attacked (the free coalition
/// carries the charge; sides swap uniforms at half).
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct SabotageTally {
    pub rounds: u32,
    pub attack_wins: u32,
    pub defence_wins: u32,
    pub level_rounds: u32,
    pub by_elimination: u32,
    pub by_detonation: u32,
    pub by_defuse: u32,
    pub by_time: u32,
    pub plants: u32,
    /// Matches that reached their decided round.
    pub matches_decided: u32,
}

/// Conquest's end: who won on tickets, how often sites changed hands, and
/// what each side held at the whistle.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ConquestTally {
    pub matches_decided: u32,
    pub union_wins: u32,
    pub coalition_wins: u32,
    pub site_flips: u64,
    pub union_sites_at_end: u32,
    pub coalition_sites_at_end: u32,
    pub union_tickets_left: u32,
    pub coalition_tickets_left: u32,
}

/// Landed shots by the body zone they struck (`ShotResult.zone`): the share of
/// head hits and kills the 1.0 bar's Fights row reads.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ZoneTally {
    pub head: u64,
    pub torso: u64,
    pub legs: u64,
    pub plate: u64,
    pub weak: u64,
}

impl ZoneTally {
    /// Count one shot in its zone.
    pub fn count(&mut self, zone: HitZone) {
        match zone {
            HitZone::Head => self.head += 1,
            HitZone::Torso => self.torso += 1,
            HitZone::Legs => self.legs += 1,
            HitZone::Plate => self.plate += 1,
            HitZone::Weak => self.weak += 1,
        }
    }

    /// Add another tally to this one.
    pub fn add(&mut self, other: &ZoneTally) {
        self.head += other.head;
        self.torso += other.torso;
        self.legs += other.legs;
        self.plate += other.plate;
        self.weak += other.weak;
    }

    /// All shots counted in any zone.
    pub fn total(&self) -> u64 {
        self.head + self.torso + self.legs + self.plate + self.weak
    }
}

/// How the server kept time over the match: tick work in microseconds.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct TickHealth {
    pub ticks: u64,
    pub p50_us: u32,
    pub p99_us: u32,
    pub max_us: u32,
    pub over_budget: u64,
}

/// The measured part of a match, summed the same way across matches. The
/// bot survey folds these and a host's records fold these.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct MatchTally {
    /// Rounds that started: one per match outside Sabotage.
    pub rounds: u32,
    /// Ticks of live play, outside warmups, musters and podiums.
    pub live_ticks: u64,
    pub frags: u64,
    pub spawns: u64,
    /// Deaths inside three seconds of the victim's own spawn.
    pub spawn_deaths: u64,
    /// Hits that landed on somebody else.
    pub hits: u64,
    /// Fighters killed by their own blast.
    pub self_deaths: u64,
    /// Times the sole leader changed hands: a fighter in free-for-all and
    /// Duel, a side in team deathmatch and CTF. The first lead is not a change.
    pub lead_changes: u64,
    /// Pads claimed during live play, dropped guns included.
    pub pickups: u64,
    /// Returns of a weapon or armour pad during live play.
    pub power_returns: u64,
    /// First claims of a returned power pad, and ticks it waited for them.
    pub power_claims: u64,
    pub power_wait_ticks: u64,
    /// Power claims inside one second of the return.
    pub appointments: u64,
    /// Frags within 8 m of a power pad inside 5 s of its return.
    pub contested_frags: u64,
    pub plate_claims: u64,
    pub rocket_claims: u64,
    /// Guns dropped on death that somebody took.
    pub drop_claims: u64,
    /// Flags captured in CTF.
    pub captures: u64,
    /// Resolved shots by gun; rockets launched count as Rocket shots.
    pub shots: WeaponTable<u64>,
    /// Frags by the gun that landed them.
    pub frag_weapons: WeaponTable<u64>,
    /// Landed shots by the zone they struck.
    pub zone_hits: ZoneTally,
    /// Killing shots by the zone they struck.
    pub kill_zones: ZoneTally,
    /// Centimetres between killer and victim when the frag landed, by gun.
    pub kill_distance_cm: WeaponTable<Samples>,
    /// Ticks from the first damage a victim took from somebody else in this
    /// life to the frag.
    pub time_to_kill_ticks: Samples,
    /// Ticks from a spawn to first contact: an opponent seen either way
    /// (120 degree cone, 64 m, clear sight), or a shot that lands either way.
    pub respawn_to_contact_ticks: Samples,
    /// Ticks from a spawn to the first shot that lands either way.
    pub respawn_to_hit_ticks: Samples,
    pub sabotage: SabotageTally,
    pub conquest: ConquestTally,
}

/// One match on one host, as it reaches the disk.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct FunRecord {
    pub schema: u32,
    /// The roster map's number (`--map`).
    pub map_id: u32,
    pub mode: GameMode,
    pub mutators: Vec<Mutator>,
    pub friendly_fire: bool,
    pub bot_tier: BotSkill,
    /// The match reached its end; false for a match the server stopped.
    pub finished: bool,
    /// Ticks from the first round's start to the end, podiums between
    /// Sabotage rounds included.
    pub match_ticks: u64,
    /// The most fighters, and the most of them rule bots, at once. Humans
    /// and agents are counted together, like any other fighter.
    pub fighters_peak: u32,
    pub bots_peak: u32,
    pub tally: MatchTally,
    /// Absent where nothing timed the ticks (the bot survey).
    pub tick_health: Option<TickHealth>,
}

impl MatchTally {
    /// Add another match's tally to this one.
    pub fn add(&mut self, other: &MatchTally) {
        self.rounds += other.rounds;
        self.live_ticks += other.live_ticks;
        self.frags += other.frags;
        self.spawns += other.spawns;
        self.spawn_deaths += other.spawn_deaths;
        self.hits += other.hits;
        self.self_deaths += other.self_deaths;
        self.lead_changes += other.lead_changes;
        self.pickups += other.pickups;
        self.power_returns += other.power_returns;
        self.power_claims += other.power_claims;
        self.power_wait_ticks += other.power_wait_ticks;
        self.appointments += other.appointments;
        self.contested_frags += other.contested_frags;
        self.plate_claims += other.plate_claims;
        self.rocket_claims += other.rocket_claims;
        self.drop_claims += other.drop_claims;
        self.captures += other.captures;
        for weapon in WeaponType::ALL {
            *self.shots.get_mut(weapon) += other.shots.get(weapon);
            *self.frag_weapons.get_mut(weapon) += other.frag_weapons.get(weapon);
            self.kill_distance_cm
                .get_mut(weapon)
                .extend(other.kill_distance_cm.get(weapon));
        }
        self.zone_hits.add(&other.zone_hits);
        self.kill_zones.add(&other.kill_zones);
        self.time_to_kill_ticks.extend(&other.time_to_kill_ticks);
        self.respawn_to_contact_ticks
            .extend(&other.respawn_to_contact_ticks);
        self.respawn_to_hit_ticks
            .extend(&other.respawn_to_hit_ticks);
        let (mine, theirs) = (&mut self.sabotage, &other.sabotage);
        mine.rounds += theirs.rounds;
        mine.attack_wins += theirs.attack_wins;
        mine.defence_wins += theirs.defence_wins;
        mine.level_rounds += theirs.level_rounds;
        mine.by_elimination += theirs.by_elimination;
        mine.by_detonation += theirs.by_detonation;
        mine.by_defuse += theirs.by_defuse;
        mine.by_time += theirs.by_time;
        mine.plants += theirs.plants;
        mine.matches_decided += theirs.matches_decided;
        let (mine, theirs) = (&mut self.conquest, &other.conquest);
        mine.matches_decided += theirs.matches_decided;
        mine.union_wins += theirs.union_wins;
        mine.coalition_wins += theirs.coalition_wins;
        mine.site_flips += theirs.site_flips;
        mine.union_sites_at_end += theirs.union_sites_at_end;
        mine.coalition_sites_at_end += theirs.coalition_sites_at_end;
        mine.union_tickets_left += theirs.union_tickets_left;
        mine.coalition_tickets_left += theirs.coalition_tickets_left;
    }

    /// Every sample list sorted: a distribution, not the order things happened.
    pub fn settle(&mut self) {
        for list in self.kill_distance_cm.0.iter_mut() {
            list.sort();
        }
        self.time_to_kill_ticks.sort();
        self.respawn_to_contact_ticks.sort();
        self.respawn_to_hit_ticks.sort();
    }

    /// All resolved shots.
    pub fn total_shots(&self) -> u64 {
        self.shots.0.iter().sum()
    }

    /// The gun that fired the most shots, and its share. None without shots.
    pub fn top_gun(&self) -> Option<(WeaponType, f64)> {
        let total = self.total_shots();
        self.shots
            .iter()
            .filter(|(_, count)| **count > 0)
            .max_by_key(|(_, count)| **count)
            .map(|(weapon, count)| (weapon, super::share(*count, total)))
    }
}
