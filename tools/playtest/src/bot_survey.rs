//! Seeded bots-only arcade survey: whole rounds of server rule bots on the
//! authoritative session, without sockets. It measures how the rule bots that
//! fill a server actually play: frag pace, spawn deaths, pad timing and
//! contest, focus fire on one body, hits landed outside the shooter's view,
//! and which guns do the work. A survey is behaviour evidence for rule bots,
//! never a human fun verdict.
use fragr_server::net::GameCommand;
use fragr_server::protocol::{
    AmmoPool, BodyKind, GameEvent, GameMode, Role, ServerMessage, WeaponType,
};
use fragr_server::rules::RuleSet;
use fragr_server::session::{GameSession, Recipient};
use fragr_server::sim::{MapKind, MatchConfig, PickupKind};
use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, HashMap, HashSet};
use uuid::Uuid;

/// A death this soon after the fighter's spawn counts against the spawn.
const SPAWN_DEATH_TICKS: u64 = 60;
/// Shooters that hit one body inside this window count as firing together.
const VOLLEY_TICKS: u64 = 20;
/// A frag this close to a power pad, this soon after it returned, contests it.
const CONTEST_RADIUS: f32 = 8.0;
const CONTEST_TICKS: u64 = 100;
/// A claim this soon after a pad returned kept an appointment with its clock.
const APPOINTMENT_TICKS: u64 = 20;
/// Half the 120 degree view cone, with a little slack for the shooter's
/// turn on the tick the shot resolved.
const VIEW_HALF_ANGLE: f32 = std::f32::consts::FRAC_PI_3 + 0.1;
/// The roster's stall rule: a living fighter that neither moves this far in a
/// tick nor fires, for longer than five seconds, is stuck.
const STALL_EPSILON: f32 = 0.01;
const STALL_TICKS: u32 = 100;
/// Stall and wall spots kept per scenario, so a report names places to look.
const SPOTS_KEPT: usize = 24;

/// Where a fighter stood still or stood inside geometry, for a hunt.
#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq)]
pub struct Spot {
    pub seed: u64,
    pub tick: u64,
    pub fighter: String,
    /// Feet position.
    pub at: [f32; 3],
    pub seconds: f64,
    pub in_vehicle: bool,
    /// The fighter was asking to move: a wedge, not a hold.
    pub pushing: bool,
}

/// One mode and map with its roster size.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub struct Scenario {
    pub mode: GameMode,
    pub map: u32,
    pub bots: usize,
}

impl Scenario {
    pub fn label(&self) -> String {
        format!(
            "{}-{}-{}",
            self.mode.id(),
            MapKind::ALL.iter().find(|map| map.id() == self.map).map_or(
                "unknown".to_string(),
                |map| map.name().to_ascii_lowercase().replace(' ', "-")
            ),
            self.bots
        )
    }
}

/// The default spread: the duel floor, the bowl, a team room, CTF and
/// Sabotage halls and the island, at the roster sizes a filled server actually has.
pub fn default_scenarios() -> Vec<Scenario> {
    vec![
        Scenario {
            mode: GameMode::Ffa,
            map: MapKind::ArenaDuel.id(),
            bots: 6,
        },
        Scenario {
            mode: GameMode::Ffa,
            map: MapKind::Directive17.id(),
            bots: 8,
        },
        Scenario {
            mode: GameMode::Tdm,
            map: MapKind::LowWater.id(),
            bots: 8,
        },
        Scenario {
            mode: GameMode::Ctf,
            map: MapKind::Sector9.id(),
            bots: 8,
        },
        Scenario {
            mode: GameMode::Sabotage,
            map: MapKind::Sector9.id(),
            bots: 8,
        },
        Scenario {
            mode: GameMode::Conquest,
            map: MapKind::HoldfastAtoll.id(),
            bots: 8,
        },
    ]
}

#[derive(Debug, Clone)]
pub struct BotSurveyConfig {
    pub scenarios: Vec<Scenario>,
    pub seeds: Vec<u64>,
    /// Live round length per match, ticks.
    pub round_ticks: u32,
}

impl Default for BotSurveyConfig {
    fn default() -> Self {
        Self {
            scenarios: default_scenarios(),
            seeds: (1..5).collect(),
            round_ticks: 20 * 150,
        }
    }
}

/// Folded facts for one scenario across its seeds.
#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq)]
pub struct ScenarioReport {
    pub scenario: String,
    pub matches: u32,
    pub live_seconds: f64,
    pub frags: u64,
    pub frags_per_minute: f64,
    pub spawns: u64,
    pub spawn_deaths: u64,
    /// Deaths inside three seconds of the victim's own spawn, per spawn.
    pub spawn_deaths_per_spawn: f64,
    pub hits: u64,
    /// Hits on a body while two or more other shooters also hit it inside one
    /// second: three guns on one target at once.
    pub volley_hits: u64,
    pub volley_hit_share: f64,
    /// Frags whose victim took hits from three or more shooters in its last second.
    pub focus_frags: u64,
    /// Hits landed on a target outside the shooter's 120 degree view.
    pub hits_outside_view: u64,
    pub hits_outside_view_share: f64,
    /// Frags whose killer opened the fight from outside the victim's view:
    /// flanks and ambushes that worked.
    pub blindside_frags: u64,
    pub blindside_share: f64,
    pub pickups: u64,
    pub pickups_per_minute: f64,
    /// Returns of a weapon or armour pad during live play.
    pub power_returns: u64,
    /// Power claims inside one second of the pad's return.
    pub appointments: u64,
    pub appointment_share: f64,
    /// Mean seconds a returned power pad sat untouched before a claim.
    pub mean_power_wait_s: f64,
    /// Frags within 8 m of a power pad inside 5 s of its return, per frag.
    pub pad_contest_index: f64,
    /// Resolved shots by weapon, as a share of all shots.
    pub shot_share: BTreeMap<String, f64>,
    /// Frags by the weapon that landed them.
    pub frag_weapons: BTreeMap<String, u64>,
    /// Captures in CTF; Conquest sites changing hands.
    pub objective_events: u64,
    /// Claims of the power armour (the Custody Plate), per three live minutes.
    pub plate_claims: u64,
    pub plate_claims_per_3min: f64,
    /// Claims of a Rocket pad.
    pub rocket_claims: u64,
    /// Frags landed by the Rocket, as a share of all frags.
    pub rocket_frag_share: f64,
    /// Fighters killed by their own blast.
    pub self_deaths: u64,
    /// Rockets fired, and those that hurt somebody.
    pub rocket_launches: u64,
    pub rocket_damaging: u64,
    /// Guns dropped on death, and how many were taken before they went.
    pub guns_dropped: u64,
    pub drop_claims: u64,
    /// Dropped Rockets taken.
    pub rocket_drop_claims: u64,
    /// Rocket lives: from the moment a fighter holds a launcher with rounds
    /// until it dies or fires the last one.
    pub rocket_lives: u64,
    /// Mean seconds a Rocket life lasts.
    pub rocket_life_seconds: f64,
    /// Share of Rocket lives that ended in the holder's death, not a dry rack.
    pub rocket_lives_died: f64,
    /// Share of a Rocket life the launcher was the gun in hand.
    pub rocket_in_hand_share: f64,
    /// Rule bots' objective callouts said to a side, per live minute.
    pub side_calls_per_minute: f64,
    /// Times the sole leader changed hands (fighter in free-for-all and Duel,
    /// side in team deathmatch and CTF), per match. The first lead is not a change.
    pub lead_changes: u64,
    pub lead_changes_per_match: f64,
    /// Over-five-second stalls by the roster's rule, and the longest one.
    pub stalls: u64,
    /// Stalls where the fighter kept asking to move: wedged on geometry.
    pub pushing_stalls: u64,
    pub longest_stall_seconds: f64,
    pub stall_spots: Vec<Spot>,
    /// Living fighter ticks with the body inside a map solid, or outside the
    /// playable square; either is a collision bug, never play.
    pub in_solid_ticks: u64,
    pub in_solid_spots: Vec<Spot>,
    pub out_of_bounds_ticks: u64,
    /// The lowest feet height a living fighter reached.
    pub lowest_feet: f32,
    /// Authored pads nobody claimed in any surveyed match: a route failure or
    /// a pad nobody wants.
    pub unclaimed_pads: Vec<String>,
    /// Fighter seconds spent in a vehicle seat (Holdfast's jeeps, boats and
    /// aircraft).
    pub vehicle_seconds: f64,
}

/// The wave 19 fun targets for every map in rotation.
pub const MAP_FRAGS_PER_MINUTE: f64 = 10.0;
pub const MAP_LEAD_CHANGES: f64 = 3.0;
pub const MAP_TOP_GUN_SHARE: f64 = 0.45;

impl ScenarioReport {
    /// The gun that fired the most shots and its share.
    pub fn top_gun(&self) -> (String, f64) {
        self.shot_share
            .iter()
            .fold((String::new(), 0.0), |best, (gun, share)| {
                if *share > best.1 {
                    (gun.clone(), *share)
                } else {
                    best
                }
            })
    }
}

/// The lane targets for rule bots on Larak Lot's free-for-all at six bots:
/// the Rocket does a real share of the work, the Plate is fought over, the
/// Flechette is not the only gun anybody fires, and fights keep coming.
pub const LOT_ROCKET_FRAG_SHARE: (f64, f64) = (0.15, 0.25);
pub const LOT_PLATE_CLAIMS_PER_3MIN: f64 = 2.0;
pub const LOT_FLECHETTE_SHOT_SHARE: f64 = 0.45;
pub const LOT_FRAGS_PER_MINUTE: f64 = 18.0;

/// The Larak Lot free-for-all at six rule bots, the row the targets read.
pub fn lot_scenario() -> Scenario {
    Scenario {
        mode: GameMode::Ffa,
        map: MapKind::ArenaDuel.id(),
        bots: 6,
    }
}

/// Larak Lot at the sizes it hosts: the target row, a smaller free-for-all
/// and Duel.
pub fn lot_scenarios() -> Vec<Scenario> {
    let lot = lot_scenario();
    vec![
        lot,
        Scenario { bots: 4, ..lot },
        Scenario {
            mode: GameMode::Duel,
            bots: 2,
            ..lot
        },
    ]
}

/// Problems against the Larak Lot targets, for the lot's six-bot row.
pub fn check_lot_targets(row: &ScenarioReport) -> Vec<String> {
    let mut problems = Vec::new();
    let (low, high) = LOT_ROCKET_FRAG_SHARE;
    if !(low..=high).contains(&row.rocket_frag_share) {
        problems.push(format!(
            "{}: Rocket frag share {:.1} percent, want {:.0} to {:.0}",
            row.scenario,
            row.rocket_frag_share * 100.0,
            low * 100.0,
            high * 100.0
        ));
    }
    if row.plate_claims_per_3min < LOT_PLATE_CLAIMS_PER_3MIN {
        problems.push(format!(
            "{}: {:.1} Plate claims per 3 min, want {LOT_PLATE_CLAIMS_PER_3MIN} or more",
            row.scenario, row.plate_claims_per_3min
        ));
    }
    let flechette = row.shot_share.get("Flechette").copied().unwrap_or(0.0);
    if flechette >= LOT_FLECHETTE_SHOT_SHARE {
        problems.push(format!(
            "{}: Flechette fires {:.1} percent of shots, want under {:.0}",
            row.scenario,
            flechette * 100.0,
            LOT_FLECHETTE_SHOT_SHARE * 100.0
        ));
    }
    if row.frags_per_minute < LOT_FRAGS_PER_MINUTE {
        problems.push(format!(
            "{}: {:.1} frags/min, want {LOT_FRAGS_PER_MINUTE} or more",
            row.scenario, row.frags_per_minute
        ));
    }
    problems
}

#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq)]
pub struct BotSurveyReport {
    pub seeds: Vec<u64>,
    pub round_seconds: f64,
    pub scenarios: Vec<ScenarioReport>,
}

#[derive(Default)]
struct Tally {
    matches: u32,
    live_ticks: u64,
    frags: u64,
    spawns: u64,
    spawn_deaths: u64,
    hits: u64,
    volley_hits: u64,
    focus_frags: u64,
    hits_outside_view: u64,
    blindside_frags: u64,
    pickups: u64,
    power_returns: u64,
    appointments: u64,
    power_wait_ticks: u64,
    power_claims: u64,
    contested_frags: u64,
    shots: BTreeMap<String, u64>,
    frag_weapons: BTreeMap<String, u64>,
    objective_events: u64,
    plate_claims: u64,
    rocket_claims: u64,
    self_deaths: u64,
    rocket_launches: u64,
    rocket_damaging: u64,
    guns_dropped: u64,
    drop_claims: u64,
    rocket_drop_claims: u64,
    rocket_lives: u64,
    rocket_life_ticks: u64,
    rocket_lives_died: u64,
    rocket_in_hand_ticks: u64,
    side_calls: u64,
    lead_changes: u64,
    stalls: u64,
    pushing_stalls: u64,
    longest_stall_ticks: u32,
    stall_spots: Vec<Spot>,
    in_solid_ticks: u64,
    in_solid_spots: Vec<Spot>,
    out_of_bounds_ticks: u64,
    lowest_feet: Option<f32>,
    /// Claims by pad id, with every authored pad entered at zero.
    pad_claims: BTreeMap<String, u64>,
    vehicle_ticks: u64,
}

fn power(kind: PickupKind) -> bool {
    match kind {
        PickupKind::Weapon(weapon) => weapon != WeaponType::Flechette,
        PickupKind::Armor | PickupKind::Plate => true,
        _ => false,
    }
}

fn angle_difference(to: f32, from: f32) -> f32 {
    use std::f32::consts::{PI, TAU};
    (to - from + PI).rem_euclid(TAU) - PI
}

/// The sole front of the round by the survey's own reading of the scores:
/// a fighter id in free-for-all and Duel, a side in team modes. None when level.
fn sole_leader(session: &GameSession, mode: GameMode) -> Option<String> {
    let side = |scores: fragr_server::protocol::TeamScores| {
        scores.leader().map(|team| team.id().to_string())
    };
    match mode {
        GameMode::Tdm => side(session.state.team_scores),
        GameMode::Ctf => side(session.state.capture_scores),
        GameMode::Ffa | GameMode::Duel => {
            let mut best: Option<(Uuid, u32)> = None;
            let mut level = false;
            for player in session.state.players.iter().filter(|p| !p.is_boss) {
                let score = session.state.scores.get(&player.id).copied().unwrap_or(0);
                match best {
                    Some((_, top)) if score < top => {}
                    Some((_, top)) if score == top => level = true,
                    _ => {
                        best = Some((player.id, score));
                        level = false;
                    }
                }
            }
            best.filter(|(_, top)| !level && *top > 0)
                .map(|(id, _)| id.to_string())
        }
        GameMode::Sabotage | GameMode::Conquest => None,
    }
}

fn keep(spots: &mut Vec<Spot>, spot: Spot) {
    // One spot per two metre cell, so one wedge does not fill the list.
    let cell = |at: [f32; 3]| {
        (
            (at[0] / 2.0).floor() as i32,
            (at[1] / 2.0).floor() as i32,
            (at[2] / 2.0).floor() as i32,
        )
    };
    if spots.len() < SPOTS_KEPT && !spots.iter().any(|s| cell(s.at) == cell(spot.at)) {
        spots.push(spot);
    }
}

/// Collision and stall facts for every living fighter on one live tick.
fn track_bodies(
    session: &GameSession,
    seed: u64,
    tick: u64,
    half: f32,
    still: &mut HashMap<Uuid, ([f32; 3], u32)>,
    tally: &mut Tally,
) {
    use fragr_server::movement::{BODY_HEIGHT, CONTACT_EPSILON};
    use fragr_server::protocol::VehicleSeat;
    use fragr_server::sim::PLAYER_FLOOR_Y;
    let arena = session.state.current_arena();
    for player in &session.state.players {
        let alive = player.hp > 0 && player.respawn_timer.is_none();
        if !alive {
            still.remove(&player.id);
            continue;
        }
        let in_vehicle = session.state.vehicles.iter().any(|jeep| {
            jeep.occupant(VehicleSeat::Driver) == Some(player.id)
                || jeep.occupant(VehicleSeat::Gunner) == Some(player.id)
        });
        if in_vehicle {
            tally.vehicle_ticks += 1;
        }
        let feet = [player.x, player.y - PLAYER_FLOOR_Y, player.z];
        tally.lowest_feet = Some(tally.lowest_feet.map_or(feet[1], |low| low.min(feet[1])));
        let spot = |seconds: f64| Spot {
            seed,
            tick,
            fighter: player.name.clone(),
            at: feet,
            seconds,
            in_vehicle,
            pushing: false,
        };
        if player.x.abs() > half || player.z.abs() > half {
            tally.out_of_bounds_ticks += 1;
        }
        if !in_vehicle
            && arena.solids.iter().any(|solid| {
                solid.covers(player.x, player.z)
                    && solid.top > feet[1] + CONTACT_EPSILON
                    && solid.bottom < feet[1] + BODY_HEIGHT - CONTACT_EPSILON
            })
        {
            tally.in_solid_ticks += 1;
            keep(&mut tally.in_solid_spots, spot(0.0));
        }
        let entry = still.entry(player.id).or_insert((feet, 0));
        let moved = (feet[0] - entry.0[0]).hypot(feet[2] - entry.0[2]);
        entry.0 = feet;
        if moved >= STALL_EPSILON || player.just_fired {
            entry.1 = 0;
            continue;
        }
        entry.1 += 1;
        tally.longest_stall_ticks = tally.longest_stall_ticks.max(entry.1);
        if entry.1 == STALL_TICKS + 1 {
            let intent = &player.pending_action;
            let pushing = intent.forward || intent.back || intent.left || intent.right;
            tally.stalls += 1;
            if pushing {
                tally.pushing_stalls += 1;
            }
            keep(
                &mut tally.stall_spots,
                Spot {
                    pushing,
                    ..spot(f64::from(STALL_TICKS) / 20.0)
                },
            );
        }
    }
}

/// Run every scenario and seed and fold the facts.
pub fn run_bot_survey(config: &BotSurveyConfig) -> BotSurveyReport {
    let mut report = BotSurveyReport {
        seeds: config.seeds.clone(),
        round_seconds: f64::from(config.round_ticks) / 20.0,
        scenarios: Vec::new(),
    };
    for scenario in &config.scenarios {
        let mut tally = Tally::default();
        for &seed in &config.seeds {
            survey_match(*scenario, seed, config.round_ticks, &mut tally);
        }
        report.scenarios.push(fold(scenario, &tally));
    }
    report
}

fn fold(scenario: &Scenario, tally: &Tally) -> ScenarioReport {
    let minutes = tally.live_ticks as f64 / 20.0 / 60.0;
    let per_minute = |count: u64| {
        if minutes > 0.0 {
            count as f64 / minutes
        } else {
            0.0
        }
    };
    let share = |part: u64, whole: u64| {
        if whole == 0 {
            0.0
        } else {
            part as f64 / whole as f64
        }
    };
    let shots: u64 = tally.shots.values().sum();
    ScenarioReport {
        scenario: scenario.label(),
        matches: tally.matches,
        live_seconds: tally.live_ticks as f64 / 20.0,
        frags: tally.frags,
        frags_per_minute: per_minute(tally.frags),
        spawns: tally.spawns,
        spawn_deaths: tally.spawn_deaths,
        spawn_deaths_per_spawn: share(tally.spawn_deaths, tally.spawns),
        hits: tally.hits,
        volley_hits: tally.volley_hits,
        volley_hit_share: share(tally.volley_hits, tally.hits),
        focus_frags: tally.focus_frags,
        hits_outside_view: tally.hits_outside_view,
        hits_outside_view_share: share(tally.hits_outside_view, tally.hits),
        blindside_frags: tally.blindside_frags,
        blindside_share: share(tally.blindside_frags, tally.frags),
        pickups: tally.pickups,
        pickups_per_minute: per_minute(tally.pickups),
        power_returns: tally.power_returns,
        appointments: tally.appointments,
        appointment_share: share(tally.appointments, tally.power_returns),
        mean_power_wait_s: if tally.power_claims == 0 {
            0.0
        } else {
            tally.power_wait_ticks as f64 / tally.power_claims as f64 / 20.0
        },
        pad_contest_index: share(tally.contested_frags, tally.frags),
        shot_share: tally
            .shots
            .iter()
            .map(|(weapon, count)| (weapon.clone(), share(*count, shots)))
            .collect(),
        frag_weapons: tally.frag_weapons.clone(),
        objective_events: tally.objective_events,
        plate_claims: tally.plate_claims,
        plate_claims_per_3min: per_minute(tally.plate_claims) * 3.0,
        rocket_claims: tally.rocket_claims,
        rocket_frag_share: share(
            tally.frag_weapons.get("Rocket").copied().unwrap_or(0),
            tally.frags,
        ),
        self_deaths: tally.self_deaths,
        rocket_launches: tally.rocket_launches,
        rocket_damaging: tally.rocket_damaging,
        guns_dropped: tally.guns_dropped,
        drop_claims: tally.drop_claims,
        rocket_drop_claims: tally.rocket_drop_claims,
        rocket_lives: tally.rocket_lives,
        rocket_life_seconds: if tally.rocket_lives == 0 {
            0.0
        } else {
            tally.rocket_life_ticks as f64 / tally.rocket_lives as f64 / 20.0
        },
        rocket_lives_died: share(tally.rocket_lives_died, tally.rocket_lives),
        rocket_in_hand_share: share(tally.rocket_in_hand_ticks, tally.rocket_life_ticks),
        side_calls_per_minute: per_minute(tally.side_calls),
        lead_changes: tally.lead_changes,
        lead_changes_per_match: if tally.matches == 0 {
            0.0
        } else {
            tally.lead_changes as f64 / f64::from(tally.matches)
        },
        stalls: tally.stalls,
        pushing_stalls: tally.pushing_stalls,
        longest_stall_seconds: f64::from(tally.longest_stall_ticks) / 20.0,
        stall_spots: tally.stall_spots.clone(),
        in_solid_ticks: tally.in_solid_ticks,
        in_solid_spots: tally.in_solid_spots.clone(),
        out_of_bounds_ticks: tally.out_of_bounds_ticks,
        lowest_feet: tally.lowest_feet.unwrap_or(0.0),
        vehicle_seconds: tally.vehicle_ticks as f64 / 20.0,
        unclaimed_pads: tally
            .pad_claims
            .iter()
            .filter(|(_, claims)| **claims == 0)
            .map(|(id, _)| id.clone())
            .collect(),
    }
}

/// Every map in every mode it hosts, at the roster size the map is built
/// for: the hunt's matrix. Duel is two seats on every map.
pub fn every_map_scenarios() -> Vec<Scenario> {
    let mut scenarios = Vec::new();
    for map in MapKind::ALL {
        let bots = match map {
            MapKind::ArenaDuel => 6,
            MapKind::ComplianceYard => 6,
            MapKind::Directive17 | MapKind::Sector9 => 8,
            MapKind::LowWater => 10,
            MapKind::ReclamationGulch | MapKind::TripointWorks => 12,
            MapKind::HoldfastAtoll => 16,
        };
        let mut modes = vec![GameMode::Ffa, GameMode::Tdm, GameMode::Duel];
        if map.ctf_stands().is_some() {
            modes.push(GameMode::Ctf);
        }
        if map.sabotage_map().is_some() {
            modes.push(GameMode::Sabotage);
        }
        if map == MapKind::HoldfastAtoll {
            modes.push(GameMode::Conquest);
        }
        for mode in modes {
            scenarios.push(Scenario {
                mode,
                map: map.id(),
                bots: if mode == GameMode::Duel { 2 } else { bots },
            });
        }
    }
    scenarios
}

/// Rows that miss the wave 19 fun targets. Frag pace is read on the
/// deathmatch modes in rotation (a two-seat Duel trades far fewer frags by
/// nature), lead changes on free-for-all, gun share everywhere.
pub fn check_map_targets(row: &ScenarioReport, mode: GameMode) -> Vec<String> {
    let mut misses = Vec::new();
    if matches!(mode, GameMode::Ffa | GameMode::Tdm) && row.frags_per_minute < MAP_FRAGS_PER_MINUTE
    {
        misses.push(format!(
            "{}: {:.1} frags/min, want {MAP_FRAGS_PER_MINUTE} or more",
            row.scenario, row.frags_per_minute
        ));
    }
    if mode == GameMode::Ffa && row.lead_changes_per_match < MAP_LEAD_CHANGES {
        misses.push(format!(
            "{}: {:.1} lead changes per match, want {MAP_LEAD_CHANGES} or more",
            row.scenario, row.lead_changes_per_match
        ));
    }
    let (gun, share) = row.top_gun();
    if share >= MAP_TOP_GUN_SHARE {
        misses.push(format!(
            "{}: {gun} fires {:.0} percent of shots, want under {:.0}",
            row.scenario,
            share * 100.0,
            MAP_TOP_GUN_SHARE * 100.0
        ));
    }
    misses
}

fn survey_match(scenario: Scenario, seed: u64, round_ticks: u32, tally: &mut Tally) {
    let Some(map) = MapKind::ALL
        .iter()
        .copied()
        .find(|m| m.id() == scenario.map)
    else {
        return;
    };
    let mut session = GameSession::with_map(map, false);
    // Numbered fighters: aim error and reaction mix the fighter id, so random
    // ids would make two runs of one seed differ.
    session.state.use_replay_ids();
    session.state.seed(seed);
    let Ok(rules) = RuleSet::new(scenario.mode, &[], false) else {
        return;
    };
    session.state.apply_config(MatchConfig {
        frag_limit: None,
        capture_limit: None,
        time_limit_ticks: Some(round_ticks),
        boss_spawn_ticks: None,
        compliance_ping_ticks: None,
        rules,
        ..MatchConfig::default()
    });
    session.spawn_bots(scenario.bots);
    // Side calls go only to their side and the booth, so the survey listens
    // from one booth seat that holds no fighter.
    let booth = Uuid::from_u128(u128::MAX);
    session.apply_command(GameCommand::Connected {
        body: BodyKind::Human,
        id: booth,
        role: Role::Spectator,
        name: "Survey Booth".into(),
        player_id: None,
    });
    tally.matches += 1;
    for pad in &session.state.pickups {
        tally.pad_claims.entry(pad.id.clone()).or_default();
    }

    // Per pad: the tick it last returned during live play, and whether that
    // return still waits for its first claim.
    let mut returned: Vec<Option<u64>> = vec![None; session.state.pickups.len()];
    let mut waiting: Vec<bool> = vec![false; session.state.pickups.len()];
    let mut was_available: Vec<bool> = session.state.pickups.iter().map(|p| p.available).collect();
    let mut spawned_at: HashMap<Uuid, u64> = HashMap::new();
    let mut last_hit: HashMap<Uuid, HashMap<Uuid, u64>> = HashMap::new();
    // Per (shooter, target): whether the shooter opened from outside the target's view.
    let mut openings: HashMap<(Uuid, Uuid), bool> = HashMap::new();
    let mut rocket_lives: HashSet<Uuid> = HashSet::new();
    // Per fighter: last feet position and the current still run.
    let mut still: HashMap<Uuid, ([f32; 3], u32)> = HashMap::new();
    let mut leader: Option<String> = None;
    let rounds = scenario.mode == GameMode::Sabotage;
    let half = map.half_extent();
    let mut live = false;
    let mut ended = false;
    let limit = u64::from(round_ticks) + 20 * 30;
    while session.state.tick < limit && !ended {
        let mut messages = session.tick_messages(0.05);
        messages.extend(
            session
                .take_unicasts()
                .into_iter()
                .filter(|(recipient, _)| *recipient == Recipient::Client(booth))
                .map(|(_, message)| message),
        );
        let tick = session.state.tick;
        if live {
            track_bodies(&session, seed, tick, half, &mut still, tally);
            if let Some(now) = sole_leader(&session, scenario.mode) {
                if leader.as_ref().is_some_and(|before| *before != now) {
                    tally.lead_changes += 1;
                }
                leader = Some(now);
            }
        } else {
            still.clear();
        }
        if live {
            tally.live_ticks += 1;
            for player in &session.state.players {
                let alive = player.hp > 0 && player.respawn_timer.is_none();
                let armed = alive
                    && player.inventory.owns(WeaponType::Rocket)
                    && player.inventory.carried(AmmoPool::Rockets) > 0;
                match (armed, rocket_lives.contains(&player.id)) {
                    (true, false) => {
                        rocket_lives.insert(player.id);
                        tally.rocket_lives += 1;
                    }
                    (false, true) => {
                        rocket_lives.remove(&player.id);
                        if !alive {
                            tally.rocket_lives_died += 1;
                        }
                    }
                    _ => {}
                }
                if armed {
                    tally.rocket_life_ticks += 1;
                    if player.weapon == WeaponType::Rocket {
                        tally.rocket_in_hand_ticks += 1;
                    }
                }
            }
        }
        for (index, pad) in session.state.pickups.iter().enumerate() {
            if index >= was_available.len() {
                break;
            }
            if live && pad.available && !was_available[index] && power(pad.kind) {
                tally.power_returns += 1;
                returned[index] = Some(tick);
                waiting[index] = true;
            }
            was_available[index] = pad.available;
        }
        for message in messages {
            let event = match message {
                ServerMessage::Event(event) => event,
                ServerMessage::Snapshot(snapshot) => {
                    if live {
                        for shot in &snapshot.shot_results {
                            if let Some(trace) = &shot.trace {
                                *tally
                                    .shots
                                    .entry(trace.weapon.name().to_string())
                                    .or_default() += 1;
                            }
                        }
                    }
                    continue;
                }
                _ => continue,
            };
            match event {
                // Sabotage plays rounds: live from each round's go to its end,
                // so the muster freeze is not counted as standing still.
                GameEvent::Sabotage {
                    kind: fragr_server::protocol::SabotageEventKind::Live,
                    ..
                } if rounds => {
                    live = true;
                }
                GameEvent::RoundEnd { .. } if rounds => {
                    live = false;
                }
                GameEvent::RoundStart { .. } if rounds => {
                    for player in &session.state.players {
                        spawned_at.insert(player.id, tick);
                        tally.spawns += 1;
                    }
                }
                GameEvent::RoundStart { .. } => {
                    live = true;
                    for player in &session.state.players {
                        spawned_at.insert(player.id, tick);
                        tally.spawns += 1;
                    }
                }
                GameEvent::RoundEnd { .. } => {
                    if live {
                        ended = true;
                    }
                }
                GameEvent::Respawn { ref player } if live => {
                    if let Some(p) = session.state.players.iter().find(|p| &p.name == player) {
                        spawned_at.insert(p.id, tick);
                        tally.spawns += 1;
                    }
                }
                GameEvent::Hit {
                    shooter_id,
                    target_id,
                    target_hp_after,
                    ..
                } if live && shooter_id == target_id => {
                    // A fighter's own blast is not a hit on anybody else.
                    if target_hp_after <= 0 {
                        tally.self_deaths += 1;
                    }
                }
                GameEvent::Hit {
                    shooter_id,
                    target_id,
                    ..
                } if live => {
                    tally.hits += 1;
                    let shooters = last_hit.entry(target_id).or_default();
                    let fresh = shooters
                        .get(&shooter_id)
                        .is_none_or(|at| tick.saturating_sub(*at) > 60);
                    shooters.insert(shooter_id, tick);
                    let together = shooters
                        .values()
                        .filter(|at| tick.saturating_sub(**at) <= VOLLEY_TICKS)
                        .count();
                    if together >= 3 {
                        tally.volley_hits += 1;
                    }
                    let shooter = session.state.players.iter().find(|p| p.id == shooter_id);
                    let target = session.state.players.iter().find(|p| p.id == target_id);
                    if let (Some(shooter), Some(target)) = (shooter, target) {
                        let bearing = (target.z - shooter.z).atan2(target.x - shooter.x);
                        let close = (target.x - shooter.x).hypot(target.z - shooter.z) < 1.5;
                        if !close && angle_difference(bearing, shooter.yaw).abs() > VIEW_HALF_ANGLE
                        {
                            tally.hits_outside_view += 1;
                        }
                        if fresh {
                            let back = (shooter.z - target.z).atan2(shooter.x - target.x);
                            openings.insert(
                                (shooter_id, target_id),
                                angle_difference(back, target.yaw).abs() > VIEW_HALF_ANGLE,
                            );
                        }
                    }
                }
                GameEvent::Frag {
                    victim_id,
                    killer_id,
                    weapon,
                    ..
                } if live => {
                    tally.frags += 1;
                    if let Some(weapon) = weapon {
                        *tally
                            .frag_weapons
                            .entry(weapon.name().to_string())
                            .or_default() += 1;
                    }
                    let Some(victim_id) = victim_id else {
                        continue;
                    };
                    if let Some(killer) = killer_id {
                        if openings.remove(&(killer, victim_id)) == Some(true) {
                            tally.blindside_frags += 1;
                        }
                    }
                    openings.retain(|(_, target), _| *target != victim_id);
                    if spawned_at
                        .get(&victim_id)
                        .is_some_and(|at| tick.saturating_sub(*at) <= SPAWN_DEATH_TICKS)
                    {
                        tally.spawn_deaths += 1;
                    }
                    if let Some(shooters) = last_hit.remove(&victim_id) {
                        let recent = shooters
                            .values()
                            .filter(|at| tick.saturating_sub(**at) <= VOLLEY_TICKS)
                            .count();
                        if recent >= 3 {
                            tally.focus_frags += 1;
                        }
                    }
                    let near = |id: Option<Uuid>| {
                        id.and_then(|id| session.state.players.iter().find(|p| p.id == id))
                            .map(|p| (p.x, p.z))
                    };
                    let places = [near(Some(victim_id)), near(killer_id)];
                    let contested = session.state.pickups.iter().enumerate().any(|(i, pad)| {
                        power(pad.kind)
                            && returned
                                .get(i)
                                .copied()
                                .flatten()
                                .is_some_and(|at| tick.saturating_sub(at) <= CONTEST_TICKS)
                            && places
                                .iter()
                                .flatten()
                                .any(|(x, z)| (pad.x - x).hypot(pad.z - z) <= CONTEST_RADIUS)
                    });
                    if contested {
                        tally.contested_frags += 1;
                    }
                }
                GameEvent::Pickup {
                    ref pickup_id,
                    ref weapon,
                    ..
                } if live => {
                    tally.pickups += 1;
                    if let Some(claims) = tally.pad_claims.get_mut(pickup_id.as_str()) {
                        *claims += 1;
                    }
                    if pickup_id.starts_with(fragr_server::sim::drops::DROPPED_GUN_PREFIX) {
                        tally.drop_claims += 1;
                        if weapon == WeaponType::Rocket.name() {
                            tally.rocket_drop_claims += 1;
                        }
                    }
                    if let Some(index) = session
                        .state
                        .pickups
                        .iter()
                        .position(|p| &p.id == pickup_id)
                    {
                        match session.state.pickups[index].kind {
                            PickupKind::Plate => tally.plate_claims += 1,
                            PickupKind::Weapon(WeaponType::Rocket) => tally.rocket_claims += 1,
                            _ => {}
                        }
                        if let Some(at) = returned[index].filter(|_| waiting[index]) {
                            // The return tick stays for the contest window; the
                            // next claim needs the next return.
                            waiting[index] = false;
                            let wait = tick.saturating_sub(at);
                            tally.power_claims += 1;
                            tally.power_wait_ticks += wait;
                            if wait <= APPOINTMENT_TICKS {
                                tally.appointments += 1;
                            }
                        }
                    }
                }
                GameEvent::Flag {
                    kind: fragr_server::protocol::FlagEventKind::Captured,
                    ..
                } if live => {
                    tally.objective_events += 1;
                }
                GameEvent::Speak { team: Some(_), .. } if live => {
                    tally.side_calls += 1;
                }
                _ => {}
            }
        }
    }
    tally.guns_dropped += u64::from(session.state.guns_dropped());
    let ids: Vec<Uuid> = session.state.players.iter().map(|p| p.id).collect();
    for id in ids {
        if let Some(record) = session.state.player_record(id) {
            let rocket = record.total.weapon(WeaponType::Rocket);
            tally.rocket_launches += rocket.attacks;
            tally.rocket_damaging += rocket.damaging_attacks;
        }
    }
    if let Some(conquest) = session.state.snapshot().conquest {
        tally.objective_events += conquest
            .points
            .iter()
            .filter(|point| point.owner.is_some())
            .count() as u64;
    }
}

/// Problems that fail an asserted survey: rule bots that never fight, never
/// pick anything up, or shoot what they cannot see.
pub fn check_bot_survey(report: &BotSurveyReport) -> Vec<String> {
    let mut problems = Vec::new();
    for row in &report.scenarios {
        if row.frags == 0 {
            problems.push(format!("{}: no frags", row.scenario));
        }
        if row.pickups == 0 {
            problems.push(format!("{}: no pickups", row.scenario));
        }
        if row.hits_outside_view_share > 0.05 {
            problems.push(format!(
                "{}: {:.1} percent of hits landed outside the shooter's view",
                row.scenario,
                row.hits_outside_view_share * 100.0
            ));
        }
        if row.in_solid_ticks > 0 || row.out_of_bounds_ticks > 0 {
            problems.push(format!(
                "{}: a living fighter stood inside a solid for {} ticks and outside the square for {}",
                row.scenario, row.in_solid_ticks, row.out_of_bounds_ticks
            ));
        }
    }
    problems
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_short_ffa_survey_reports_frags_pads_and_view() {
        let report = run_bot_survey(&BotSurveyConfig {
            scenarios: vec![Scenario {
                mode: GameMode::Ffa,
                map: MapKind::ArenaDuel.id(),
                bots: 4,
            }],
            seeds: vec![3],
            round_ticks: 20 * 60,
        });
        let row = &report.scenarios[0];
        assert_eq!(row.matches, 1);
        assert!(row.live_seconds > 50.0, "{row:?}");
        assert!(row.frags > 0, "{row:?}");
        assert!(row.spawns >= 4, "{row:?}");
        assert!(row.shot_share.values().sum::<f64>() > 0.99, "{row:?}");
        assert!(row.guns_dropped > 0, "the Pistol start drops guns: {row:?}");
        assert!(row.rocket_lives > 0, "somebody held the Rocket: {row:?}");
        assert!(row.rocket_life_seconds > 0.0, "{row:?}");
        assert_eq!(
            row.side_calls_per_minute, 0.0,
            "a free-for-all has no sides"
        );
        assert!(check_bot_survey(&report).is_empty(), "{row:?}");
    }

    #[test]
    fn a_short_ctf_survey_hears_rare_side_calls() {
        let report = run_bot_survey(&BotSurveyConfig {
            scenarios: vec![Scenario {
                mode: GameMode::Ctf,
                map: MapKind::Sector9.id(),
                bots: 8,
            }],
            seeds: vec![1, 2],
            round_ticks: 20 * 150,
        });
        let row = &report.scenarios[0];
        assert!(row.side_calls_per_minute > 0.0, "{row:?}");
        // Two sides, one call each per fifteen seconds at the very most.
        assert!(row.side_calls_per_minute <= 8.0, "{row:?}");
    }

    #[test]
    fn the_lot_targets_name_each_miss_and_pass_a_good_row() {
        let labels: Vec<String> = lot_scenarios().iter().map(Scenario::label).collect();
        assert_eq!(
            labels,
            ["ffa-larak-lot-6", "ffa-larak-lot-4", "duel-larak-lot-2"]
        );
        let good = ScenarioReport {
            scenario: lot_scenario().label(),
            frags_per_minute: 20.0,
            plate_claims_per_3min: 3.0,
            rocket_frag_share: 0.2,
            shot_share: [("Flechette".to_string(), 0.4)].into_iter().collect(),
            ..ScenarioReport::default()
        };
        assert!(check_lot_targets(&good).is_empty());
        let bad = ScenarioReport {
            frags_per_minute: 10.0,
            plate_claims_per_3min: 1.0,
            rocket_frag_share: 0.3,
            shot_share: [("Flechette".to_string(), 0.6)].into_iter().collect(),
            ..good
        };
        assert_eq!(
            check_lot_targets(&bad).len(),
            4,
            "{:?}",
            check_lot_targets(&bad)
        );
    }

    #[test]
    fn a_seeded_survey_repeats_exactly() {
        let config = BotSurveyConfig {
            scenarios: vec![lot_scenario()],
            seeds: vec![5],
            round_ticks: 20 * 30,
        };
        assert_eq!(run_bot_survey(&config), run_bot_survey(&config));
    }

    #[test]
    fn the_check_names_silent_and_blind_scenarios() {
        let report = BotSurveyReport {
            scenarios: vec![ScenarioReport {
                scenario: "ffa-x-4".into(),
                hits_outside_view_share: 0.2,
                ..ScenarioReport::default()
            }],
            ..BotSurveyReport::default()
        };
        assert_eq!(check_bot_survey(&report).len(), 3);
    }

    #[test]
    fn the_map_matrix_plays_every_map_in_every_mode_it_hosts() {
        let scenarios = every_map_scenarios();
        assert_eq!(scenarios.len(), 29);
        for map in MapKind::ALL {
            for mode in [GameMode::Ffa, GameMode::Tdm, GameMode::Duel] {
                assert!(scenarios
                    .iter()
                    .any(|s| s.map == map.id() && s.mode == mode));
            }
        }
        let hosts = |mode: GameMode| -> Vec<u32> {
            scenarios
                .iter()
                .filter(|s| s.mode == mode)
                .map(|s| s.map)
                .collect()
        };
        assert_eq!(hosts(GameMode::Ctf), [3, 4]);
        assert_eq!(hosts(GameMode::Sabotage), [4, 8]);
        assert_eq!(hosts(GameMode::Conquest), [7]);
        assert!(scenarios
            .iter()
            .all(|s| (s.mode == GameMode::Duel) == (s.bots == 2)));
    }

    #[test]
    fn a_still_fighter_is_one_stall_and_a_pushing_one_is_a_wedge() {
        let mut session = GameSession::with_map(MapKind::ArenaDuel, false);
        let id = Uuid::from_u128(7);
        session.state.add_player(id, "Still".into(), Role::Agent);
        session.state.start_round();
        let mut still = HashMap::new();
        let mut tally = Tally::default();
        let half = MapKind::ArenaDuel.half_extent();
        for tick in 0..=u64::from(STALL_TICKS) + 20 {
            track_bodies(&session, 1, tick, half, &mut still, &mut tally);
        }
        assert_eq!(tally.stalls, 1, "one run is one stall however long");
        assert_eq!(tally.pushing_stalls, 0);
        assert_eq!(tally.stall_spots.len(), 1);
        assert!(!tally.stall_spots[0].pushing);
        assert_eq!(tally.in_solid_ticks, 0, "a spawn is clear floor");
        assert_eq!(tally.out_of_bounds_ticks, 0);

        // The same fighter asking to walk while it stands still is wedged.
        session.state.players[0].pending_action.forward = true;
        still.clear();
        let mut wedged = Tally::default();
        for tick in 0..=u64::from(STALL_TICKS) + 1 {
            track_bodies(&session, 1, tick, half, &mut still, &mut wedged);
        }
        assert_eq!((wedged.stalls, wedged.pushing_stalls), (1, 1));

        // Firing breaks a run: a fighter holding an angle and shooting is not stuck.
        session.state.players[0].just_fired = true;
        still.clear();
        let mut firing = Tally::default();
        for tick in 0..=u64::from(STALL_TICKS) + 1 {
            track_bodies(&session, 1, tick, half, &mut still, &mut firing);
        }
        assert_eq!(firing.stalls, 0);
    }

    #[test]
    fn a_body_inside_a_solid_or_off_the_square_is_counted() {
        let mut session = GameSession::with_map(MapKind::ArenaDuel, false);
        let id = Uuid::from_u128(8);
        session.state.add_player(id, "Wall".into(), Role::Agent);
        session.state.start_round();
        let solid = session
            .state
            .current_arena()
            .solids
            .iter()
            .copied()
            .find(|s| s.bottom == 0.0 && s.top > 2.0)
            .unwrap();
        let player = &mut session.state.players[0];
        player.x = (solid.min_x + solid.max_x) * 0.5;
        player.z = (solid.min_z + solid.max_z) * 0.5;
        player.y = fragr_server::sim::PLAYER_FLOOR_Y;
        let mut tally = Tally::default();
        let half = MapKind::ArenaDuel.half_extent();
        track_bodies(&session, 1, 0, half, &mut HashMap::new(), &mut tally);
        assert_eq!(tally.in_solid_ticks, 1);
        assert_eq!(tally.in_solid_spots.len(), 1);
        session.state.players[0].x = half + 1.0;
        track_bodies(&session, 1, 1, half, &mut HashMap::new(), &mut tally);
        assert_eq!(tally.out_of_bounds_ticks, 1);
        let row = fold(&lot_scenario(), &tally);
        assert_eq!(
            check_bot_survey(&BotSurveyReport {
                scenarios: vec![row],
                ..BotSurveyReport::default()
            })
            .iter()
            .filter(|p| p.contains("inside a solid"))
            .count(),
            1
        );
    }

    #[test]
    fn a_free_for_all_counts_lead_changes_and_sabotage_plays_its_rounds() {
        let report = run_bot_survey(&BotSurveyConfig {
            scenarios: vec![
                Scenario {
                    mode: GameMode::Ffa,
                    map: MapKind::Directive17.id(),
                    bots: 8,
                },
                Scenario {
                    mode: GameMode::Sabotage,
                    map: MapKind::LowWater.id(),
                    bots: 10,
                },
            ],
            seeds: vec![1],
            round_ticks: 20 * 120,
        });
        let ffa = &report.scenarios[0];
        assert!(ffa.lead_changes > 0, "{ffa:?}");
        assert!(
            ffa.unclaimed_pads.len() < 4
                && ffa.unclaimed_pads.iter().all(|id| !id.starts_with("drop")),
            "pads are counted, and only authored pads: {ffa:?}"
        );
        assert_eq!(ffa.in_solid_ticks + ffa.out_of_bounds_ticks, 0);
        let sabotage = &report.scenarios[1];
        assert!(
            sabotage.frags > 0 && sabotage.live_seconds > 30.0,
            "{sabotage:?}"
        );
        assert_eq!(sabotage.lead_changes, 0, "sabotage has no frag lead");
    }

    #[test]
    fn the_map_targets_read_pace_on_deathmatch_and_gun_share_everywhere() {
        let row = ScenarioReport {
            scenario: "x".into(),
            frags_per_minute: 5.0,
            lead_changes_per_match: 1.0,
            shot_share: [("Flechette".to_string(), 0.6), ("Tack".to_string(), 0.4)]
                .into_iter()
                .collect(),
            ..ScenarioReport::default()
        };
        assert_eq!(row.top_gun(), ("Flechette".to_string(), 0.6));
        assert_eq!(check_map_targets(&row, GameMode::Ffa).len(), 3);
        assert_eq!(check_map_targets(&row, GameMode::Tdm).len(), 2);
        assert_eq!(check_map_targets(&row, GameMode::Duel).len(), 1);
        let good = ScenarioReport {
            frags_per_minute: 12.0,
            lead_changes_per_match: 3.0,
            shot_share: [("Tack".to_string(), 0.4)].into_iter().collect(),
            ..row
        };
        assert!(check_map_targets(&good, GameMode::Ffa).is_empty());
    }
}
