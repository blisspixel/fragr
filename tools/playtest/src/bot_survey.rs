//! Seeded bots-only arcade survey: whole rounds of server rule bots on the
//! authoritative session, without sockets. It measures how the rule bots that
//! fill a server actually play: frag pace, spawn deaths, pad timing and
//! contest, focus fire on one body, hits landed outside the shooter's view,
//! and which guns do the work. A survey is behaviour evidence for rule bots,
//! never a human fun verdict.
use localexception_server::fun_metrics::{MatchTally, Observer};
use localexception_server::net::GameCommand;
use localexception_server::protocol::{
    AmmoPool, BodyKind, GameEvent, GameMode, Role, ServerMessage, WeaponType,
};
use localexception_server::rules::RuleSet;
use localexception_server::session::{GameSession, Recipient};
use localexception_server::sim::{BotSkill, MapKind, MatchConfig};
use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, HashMap, HashSet};
use uuid::Uuid;

// The columns a host's fun metrics and the survey share live with the
// recorder, so both readers fold one way (`fun_metrics::summary`).
pub use localexception_server::fun_metrics::summary::{
    check_map_targets, shared_row, ScenarioReport, Spot, MAP_CONTACT_SECONDS, MAP_DITHER_SHARE,
    MAP_DUEL_FRAGS_PER_MINUTE, MAP_FRAGS_PER_MINUTE, MAP_LEAD_CHANGES, MAP_TOP_GUN_SHARE,
};

/// Shooters that hit one body inside this window count as firing together.
const VOLLEY_TICKS: u64 = 20;
/// Half the 120 degree view cone, with a little slack for the shooter's
/// turn on the tick the shot resolved.
const VIEW_HALF_ANGLE: f32 = std::f32::consts::FRAC_PI_3 + 0.1;
/// The roster's stall rule: a living fighter that neither moves this far in a
/// tick nor fires, for longer than five seconds, is stuck.
const STALL_EPSILON: f32 = 0.01;
const STALL_TICKS: u32 = 100;
/// Stall and wall spots kept per scenario, so a report names places to look.
const SPOTS_KEPT: usize = 24;

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
    /// The rung every surveyed bot plays at.
    pub skill: BotSkill,
}

impl Default for BotSurveyConfig {
    fn default() -> Self {
        Self {
            scenarios: default_scenarios(),
            seeds: (1..5).collect(),
            round_ticks: 20 * 150,
            skill: BotSkill::Regular,
        }
    }
}

/// The survey's name for a struck zone, as the shared tables spell it.
fn zone_name(zone: localexception_server::protocol::HitZone) -> &'static str {
    use localexception_server::protocol::HitZone;
    match zone {
        HitZone::Head => "head",
        HitZone::Torso => "torso",
        HitZone::Legs => "legs",
        HitZone::Plate => "plate",
        HitZone::Weak => "weak",
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

/// One map in the modes it hosts: free-for-all at six and eight, team
/// deathmatch at eight, and Sabotage at ten where the map has sites.
pub fn map_scenarios(map: MapKind) -> Vec<Scenario> {
    let mut rows = vec![
        Scenario {
            mode: GameMode::Ffa,
            map: map.id(),
            bots: 6,
        },
        Scenario {
            mode: GameMode::Ffa,
            map: map.id(),
            bots: 8,
        },
        Scenario {
            mode: GameMode::Tdm,
            map: map.id(),
            bots: 8,
        },
    ];
    if map.sabotage_map().is_some() {
        rows.push(Scenario {
            mode: GameMode::Sabotage,
            map: map.id(),
            bots: 10,
        });
    }
    rows
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
    /// The rung every bot played at.
    #[serde(default)]
    pub skill: String,
    pub round_seconds: f64,
    pub scenarios: Vec<ScenarioReport>,
}

/// The survey's own counts beside the shared match tally. Everything a
/// host's fun metrics also measure lives in `shared`, folded by the
/// server's observer (`localexception_server::fun_metrics`); what is left here is
/// bot behaviour only a bots-only survey can read: volleys, view, stalls,
/// walls, what a body carries and the Rocket's lives.
#[derive(Default)]
struct Tally {
    matches: u32,
    /// Killing traced shots by weapon and zone.
    weapon_kill_zones: BTreeMap<String, BTreeMap<String, u64>>,
    shared: MatchTally,
    volley_hits: u64,
    focus_frags: u64,
    hits_outside_view: u64,
    blindside_frags: u64,
    living_ticks: u64,
    hand_ticks: BTreeMap<String, u64>,
    owned_ticks: BTreeMap<String, u64>,
    rocket_launches: u64,
    rocket_damaging: u64,
    guns_dropped: u64,
    rocket_drop_claims: u64,
    rocket_lives: u64,
    rocket_life_ticks: u64,
    rocket_lives_died: u64,
    rocket_in_hand_ticks: u64,
    side_calls: u64,
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
    moving_windows: u64,
    dither_windows: u64,
}

fn angle_difference(to: f32, from: f32) -> f32 {
    use std::f32::consts::{PI, TAU};
    (to - from + PI).rem_euclid(TAU) - PI
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
    use localexception_server::movement::{BODY_HEIGHT, CONTACT_EPSILON};
    use localexception_server::protocol::VehicleSeat;
    use localexception_server::sim::PLAYER_FLOOR_Y;
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
        skill: config.skill.id().to_string(),
        scenarios: Vec::new(),
    };
    // Scenarios share nothing, so each folds on its own thread; the report
    // keeps the configured order and every row is the one a serial run gives.
    let workers = std::thread::available_parallelism().map_or(1, usize::from);
    let mut rows: Vec<Option<ScenarioReport>> = vec![None; config.scenarios.len()];
    for (chunk, slots) in config
        .scenarios
        .chunks(workers)
        .zip(rows.chunks_mut(workers))
    {
        std::thread::scope(|scope| {
            for (scenario, slot) in chunk.iter().zip(slots.iter_mut()) {
                scope.spawn(move || {
                    let mut tally = Tally::default();
                    for &seed in &config.seeds {
                        survey_match(
                            *scenario,
                            seed,
                            config.round_ticks,
                            config.skill,
                            &mut tally,
                        );
                    }
                    *slot = Some(fold(scenario, &tally));
                });
            }
        });
    }
    report.scenarios = rows.into_iter().flatten().collect();
    report
}

fn fold(scenario: &Scenario, tally: &Tally) -> ScenarioReport {
    use localexception_server::fun_metrics::{per_minute, share};
    let live = tally.shared.live_ticks;
    let base = shared_row(scenario.label(), tally.matches, &tally.shared);
    let (single_head, single_all) = tally
        .weapon_kill_zones
        .iter()
        .filter(|(weapon, _)| weapon.as_str() != WeaponType::Scatter.name())
        .fold((0, 0), |(head, all), (_, zones)| {
            (
                head + zones.get("head").copied().unwrap_or(0),
                all + zones.values().sum::<u64>(),
            )
        });
    ScenarioReport {
        weapon_kill_zones: tally.weapon_kill_zones.clone(),
        single_ray_head_kill_share: share(single_head, single_all),
        volley_hits: tally.volley_hits,
        volley_hit_share: share(tally.volley_hits, base.hits),
        focus_frags: tally.focus_frags,
        hits_outside_view: tally.hits_outside_view,
        hits_outside_view_share: share(tally.hits_outside_view, base.hits),
        blindside_frags: tally.blindside_frags,
        blindside_share: share(tally.blindside_frags, base.frags),
        hand_share: tally
            .hand_ticks
            .iter()
            .map(|(weapon, count)| (weapon.clone(), share(*count, tally.living_ticks)))
            .collect(),
        owned_share: tally
            .owned_ticks
            .iter()
            .map(|(weapon, count)| (weapon.clone(), share(*count, tally.living_ticks)))
            .collect(),
        rocket_launches: tally.rocket_launches,
        rocket_damaging: tally.rocket_damaging,
        guns_dropped: tally.guns_dropped,
        rocket_drop_claims: tally.rocket_drop_claims,
        rocket_lives: tally.rocket_lives,
        rocket_life_seconds: if tally.rocket_lives == 0 {
            0.0
        } else {
            tally.rocket_life_ticks as f64 / tally.rocket_lives as f64 / 20.0
        },
        rocket_lives_died: share(tally.rocket_lives_died, tally.rocket_lives),
        rocket_in_hand_share: share(tally.rocket_in_hand_ticks, tally.rocket_life_ticks),
        side_calls_per_minute: per_minute(tally.side_calls, live),
        stalls: tally.stalls,
        pushing_stalls: tally.pushing_stalls,
        longest_stall_seconds: f64::from(tally.longest_stall_ticks) / 20.0,
        stall_spots: tally.stall_spots.clone(),
        in_solid_ticks: tally.in_solid_ticks,
        in_solid_spots: tally.in_solid_spots.clone(),
        out_of_bounds_ticks: tally.out_of_bounds_ticks,
        lowest_feet: tally.lowest_feet.unwrap_or(0.0),
        vehicle_seconds: tally.vehicle_ticks as f64 / 20.0,
        moving_windows: tally.moving_windows,
        dither_share: share(tally.dither_windows, tally.moving_windows),
        unclaimed_pads: tally
            .pad_claims
            .iter()
            .filter(|(_, claims)| **claims == 0)
            .map(|(id, _)| id.clone())
            .collect(),
        ..base
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

fn survey_match(
    scenario: Scenario,
    seed: u64,
    round_ticks: u32,
    skill: BotSkill,
    tally: &mut Tally,
) {
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
    session.set_bot_skill(skill);
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

    // The shared measurements: the same observer a host's fun metrics run.
    let mut observer = Observer::new(&session);
    let mut last_hit: HashMap<Uuid, HashMap<Uuid, u64>> = HashMap::new();
    // Per (shooter, target): whether the shooter opened from outside the target's view.
    let mut openings: HashMap<(Uuid, Uuid), bool> = HashMap::new();
    let mut rocket_lives: HashSet<Uuid> = HashSet::new();
    // Per fighter: last feet position and the current still run.
    let mut still: HashMap<Uuid, ([f32; 3], u32)> = HashMap::new();
    let solids = map.solids();
    let mut dither = crate::sight::DitherTracker::default();
    let rounds = scenario.mode == GameMode::Sabotage;
    let half = map.half_extent();
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
        let live = observer.live();
        if live {
            track_bodies(&session, seed, tick, half, &mut still, tally);
        } else {
            still.clear();
        }
        observer.begin_tick(&session);
        if live {
            dither.observe(&session, &solids);
            for player in &session.state.players {
                let alive = player.hp > 0 && player.respawn_timer.is_none();
                if alive {
                    tally.living_ticks += 1;
                    *tally
                        .hand_ticks
                        .entry(player.weapon.name().to_string())
                        .or_default() += 1;
                    for gun in WeaponType::ALL {
                        if gun != WeaponType::Fists && player.inventory.usable(gun) {
                            *tally.owned_ticks.entry(gun.name().to_string()).or_default() += 1;
                        }
                    }
                }
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
        for message in &messages {
            observer.message(&session, message);
            let live = observer.live();
            if let ServerMessage::Snapshot(snapshot) = message {
                for shot in snapshot
                    .shot_results
                    .iter()
                    .filter(|shot| live && shot.killed)
                {
                    if let (Some(trace), Some(zone)) = (&shot.trace, shot.zone) {
                        *tally
                            .weapon_kill_zones
                            .entry(trace.weapon.name().to_string())
                            .or_default()
                            .entry(zone_name(zone).to_string())
                            .or_default() += 1;
                    }
                }
            }
            let ServerMessage::Event(event) = message else {
                continue;
            };
            match event {
                GameEvent::Hit {
                    shooter_id,
                    target_id,
                    ..
                } if live && shooter_id != target_id => {
                    let (shooter_id, target_id) = (*shooter_id, *target_id);
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
                    victim_id: Some(victim_id),
                    killer_id,
                    ..
                } if live => {
                    let victim_id = *victim_id;
                    if let Some(killer) = killer_id {
                        if openings.remove(&(*killer, victim_id)) == Some(true) {
                            tally.blindside_frags += 1;
                        }
                    }
                    openings.retain(|(_, target), _| *target != victim_id);
                    if let Some(shooters) = last_hit.remove(&victim_id) {
                        let recent = shooters
                            .values()
                            .filter(|at| tick.saturating_sub(**at) <= VOLLEY_TICKS)
                            .count();
                        if recent >= 3 {
                            tally.focus_frags += 1;
                        }
                    }
                }
                GameEvent::Pickup {
                    pickup_id, weapon, ..
                } if live => {
                    if let Some(claims) = tally.pad_claims.get_mut(pickup_id.as_str()) {
                        *claims += 1;
                    }
                    if pickup_id.starts_with(localexception_server::sim::drops::DROPPED_GUN_PREFIX)
                        && weapon == WeaponType::Rocket.name()
                    {
                        tally.rocket_drop_claims += 1;
                    }
                }
                GameEvent::Speak { team: Some(_), .. } if live => {
                    tally.side_calls += 1;
                }
                _ => {}
            }
        }
        // Sabotage plays on through its rounds to the clock; every other
        // mode is one round, over when it ends.
        if !rounds && observer.finished() {
            ended = true;
        }
    }
    tally.moving_windows += dither.moving;
    tally.dither_windows += dither.dithers;
    tally.guns_dropped += u64::from(session.state.guns_dropped());
    let ids: Vec<Uuid> = session.state.players.iter().map(|p| p.id).collect();
    for id in ids {
        if let Some(record) = session.state.player_record(id) {
            let rocket = record.total.weapon(WeaponType::Rocket);
            tally.rocket_launches += rocket.attacks;
            tally.rocket_damaging += rocket.damaging_attacks;
        }
    }
    tally.shared.add(&observer.into_record(None).tally);
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
            ..BotSurveyConfig::default()
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
            ..BotSurveyConfig::default()
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
    fn a_map_survey_covers_the_modes_the_map_hosts() {
        let labels = |map: MapKind| -> Vec<String> {
            map_scenarios(map).iter().map(Scenario::label).collect()
        };
        assert_eq!(
            labels(MapKind::ComplianceYard),
            [
                "ffa-compliance-yard-6",
                "ffa-compliance-yard-8",
                "tdm-compliance-yard-8"
            ]
        );
        assert_eq!(
            labels(MapKind::LowWater),
            [
                "ffa-low-water-6",
                "ffa-low-water-8",
                "tdm-low-water-8",
                "sabotage-low-water-10"
            ]
        );
    }

    #[test]
    fn a_seeded_survey_repeats_exactly() {
        let config = BotSurveyConfig {
            scenarios: vec![lot_scenario()],
            seeds: vec![5],
            round_ticks: 20 * 30,
            ..BotSurveyConfig::default()
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
        player.y = localexception_server::sim::PLAYER_FLOOR_Y;
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
            ..BotSurveyConfig::default()
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
        let quiet_duel = ScenarioReport {
            frags_per_minute: 0.5,
            ..row.clone()
        };
        assert_eq!(check_map_targets(&quiet_duel, GameMode::Duel).len(), 2);
        let good = ScenarioReport {
            frags_per_minute: 12.0,
            lead_changes_per_match: 3.0,
            shot_share: [("Tack".to_string(), 0.4)].into_iter().collect(),
            ..row
        };
        assert!(check_map_targets(&good, GameMode::Ffa).is_empty());
        let slow = ScenarioReport {
            respawn_to_hit_s: crate::sight::Spread {
                count: 40,
                median: 22.0,
                p25: 15.0,
                p75: 30.0,
            },
            dither_share: 0.08,
            ..good.clone()
        };
        let misses = check_map_targets(&slow, GameMode::Ffa);
        assert_eq!(misses.len(), 2, "{misses:?}");
        assert!(misses[0].contains("first landed shot") && misses[1].contains("dithers"));
        // Contact pace is a deathmatch target; dithering is read everywhere.
        assert_eq!(check_map_targets(&slow, GameMode::Ctf).len(), 1);
        let quick = ScenarioReport {
            respawn_to_hit_s: crate::sight::Spread {
                count: 40,
                median: 3.0,
                ..crate::sight::Spread::default()
            },
            ..good
        };
        assert_eq!(check_map_targets(&quick, GameMode::Tdm).len(), 1);
    }
}
