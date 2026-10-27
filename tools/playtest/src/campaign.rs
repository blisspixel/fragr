//! Constrained, guided campaign trials on the real simulation. The controller
//! knows public mission objectives and geometry, but sees enemies and supply
//! only inside its view. These are declared stress profiles, not human data.
use fragr_server::combat::{line_of_sight, FIGHTER_HEIGHT};
use fragr_server::inventory::control_action_with_target_filter;
use fragr_server::maps::AuthoredSource;
use fragr_server::mission::MissionClient;
use fragr_server::movement::{Arena, EYE_HEIGHT};
use fragr_server::navigation::Navigator;
use fragr_server::protocol::{
    Action, AmmoPool, CampaignActor, CampaignDifficulty, CampaignRunStatus, EnemyPhase,
    LoadoutState, LookAt, MissionContinue, MissionId, MissionPhase, MissionReady, PlayerState,
    Role, ServerMessage, Snapshot,
};
use fragr_server::session::GameSession;
use fragr_server::sim::PLAYER_FLOOR_Y;
use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, BTreeSet, VecDeque};
use std::f32::consts::{PI, TAU};
use uuid::Uuid;

const DT: f32 = 0.05;

/// The Recall Notice disclosure, shared with the carry report's M01 leg.
macro_rules! recall_notice_observation {
    () => {
        "Guided M01 route; known public objective and navigation geometry; constrained enemy/supply perception and ordinary human actions; immediate Continue acceptance with no simulated menu delay; no human-population calibration or rendered-readability claim."
    };
}

mod carry;
mod market;
mod market_guard;
mod paver;
mod search;
mod teaching;

/// One bounded campaign endpoint, using the same calibrated action policy.
#[derive(Debug, Default, Clone, Copy, PartialEq, Eq, Serialize, clap::ValueEnum)]
#[serde(rename_all = "snake_case")]
pub enum Scenario {
    #[default]
    RecallNotice,
    M19Teaching,
    M19Market,
    /// Earned M01 departure, real run-file reopen and a bounded M02 window.
    M02Carry,
    /// The same earned market prefix, continued to the next authored
    /// objective (`water_tanks`).
    M19Tanks,
}

impl Scenario {
    fn mission(self) -> MissionId {
        match self {
            Self::RecallNotice => MissionId::RecallNotice,
            Self::M02Carry => MissionId::PersonsUnknown,
            Self::M19Teaching | Self::M19Market | Self::M19Tanks => MissionId::PlannedWorks,
        }
    }

    fn is_m19(self) -> bool {
        matches!(self, Self::M19Teaching | Self::M19Market | Self::M19Tanks)
    }

    /// Runs the market objective with its evaluator revision and receipts.
    fn plays_market(self) -> bool {
        matches!(self, Self::M19Market | Self::M19Tanks)
    }

    fn segment_complete(self, state: &fragr_server::protocol::MissionState, alive: bool) -> bool {
        if !alive
            || state.run.is_some_and(|run| {
                matches!(
                    run.status,
                    CampaignRunStatus::Continue | CampaignRunStatus::Failed
                )
            })
        {
            return false;
        }
        let endpoint = match self {
            Self::RecallNotice | Self::M02Carry => return false,
            Self::M19Teaching => "tram_street",
            Self::M19Market => "market_strips",
            Self::M19Tanks => "water_tanks",
        };
        state.m19.as_ref().is_some_and(|facts| {
            facts
                .completed
                .iter()
                .any(|objective| objective == endpoint)
        })
    }

    pub fn accepts(self, trial: &Trial) -> bool {
        match self {
            Self::RecallNotice => trial.outcome == "departed",
            Self::M02Carry => carry::accepts(trial),
            Self::M19Teaching | Self::M19Market | Self::M19Tanks => {
                trial.outcome == "segment_complete"
                    && trial.teaching.as_ref().is_some_and(|evidence| {
                        evidence.flights.iter().any(|flight| {
                            flight.attempt == trial.final_attempt && flight.gallery_landing
                        })
                    })
                    && (!self.plays_market()
                        || trial.market.as_ref().is_some_and(|metrics| {
                            metrics.attempts.iter().any(|attempt| {
                                attempt.attempt == trial.final_attempt
                                    && attempt.outcome == market::Outcome::Complete
                            })
                        }))
            }
        }
    }
}

#[derive(Debug, Clone, Copy, Serialize, PartialEq)]
pub struct Profile {
    pub name: &'static str,
    pub reaction_ticks: u64,
    pub view_degrees: f32,
    pub turn_degrees_per_second: f32,
    pub aim_error_degrees: f32,
}

pub const PROFILES: [Profile; 3] = [
    Profile {
        name: "reference",
        reaction_ticks: 0,
        view_degrees: 100.0,
        turn_degrees_per_second: 360.0,
        aim_error_degrees: 0.0,
    },
    Profile {
        name: "deliberate",
        reaction_ticks: 5,
        view_degrees: 100.0,
        turn_degrees_per_second: 180.0,
        aim_error_degrees: 1.0,
    },
    Profile {
        name: "hesitant",
        reaction_ticks: 9,
        view_degrees: 90.0,
        turn_degrees_per_second: 120.0,
        aim_error_degrees: 2.5,
    },
];

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct Trial {
    pub seed: u64,
    pub profile: String,
    pub difficulty: CampaignDifficulty,
    pub outcome: String,
    pub deaths: u32,
    pub continues_spent: u8,
    pub seconds: f64,
    pub first_contact_seconds: Option<f64>,
    pub first_contact_distance: Option<f32>,
    pub shots: u32,
    pub hits: u32,
    pub kills: u32,
    pub damage_received: i32,
    /// Nominal resolved shot damage, including overkill; not HP loss.
    pub resolved_damage_outside_view: i32,
    pub hits_received: Vec<Hit>,
    pub hits_omitted: u32,
    pub reloads: u32,
    pub longest_no_progress_seconds: f64,
    pub last_phase: MissionPhase,
    pub last_feet: [f32; 3],
    pub hp: i32,
    pub bullets: u16,
    pub weapons: Vec<String>,
    pub final_attempt: u32,
    pub teaching: Option<teaching::Metrics>,
    pub market: Option<market::Metrics>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub carry: Option<Box<carry::Metrics>>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct Hit {
    pub tick: u64,
    pub attempt: u32,
    pub source: String,
    pub feet: [f32; 3],
    pub bearing_degrees: Option<f32>,
    pub source_visible: bool,
    pub resolved_damage: i32,
}

#[derive(Debug, Serialize)]
pub struct Report {
    pub schema: u8,
    pub build: &'static str,
    pub commit: &'static str,
    pub observation: &'static str,
    pub profiles: [Profile; 3],
    pub decision_hz: u8,
    pub continuation_delay_seconds: u8,
    pub scenario: Scenario,
    pub trials: Vec<Trial>,
    /// Last fatal-hit pre-frame of the first deliberate/Standard trial.
    /// Authoritative scene data for inspection, never controller input.
    pub review: Option<serde_json::Value>,
    /// First kill of the first reference/Assisted trial, even if it later fails.
    pub first_kill_review: Option<serde_json::Value>,
    pub teaching_reviews: Vec<serde_json::Value>,
}

#[derive(Clone, Copy, PartialEq)]
enum Recording {
    None,
    Fatal,
    FirstKill,
    Teaching,
}

fn angle(value: f32) -> f32 {
    (value + PI).rem_euclid(TAU) - PI
}

fn eye(me: &PlayerState) -> [f32; 3] {
    [me.x, me.y - PLAYER_FLOOR_Y + EYE_HEIGHT, me.z]
}

fn visible(me: &PlayerState, point: [f32; 3], arena: &Arena, profile: Profile) -> bool {
    let origin = eye(me);
    let dx = point[0] - origin[0];
    let dy = point[1] - origin[1];
    let dz = point[2] - origin[2];
    let flat = dx.hypot(dz);
    flat.hypot(dy) <= 48.0
        && angle(dz.atan2(dx) - me.yaw).abs() <= profile.view_degrees.to_radians() * 0.5
        && (dy.atan2(flat) - me.pitch).abs() <= 40_f32.to_radians()
        && line_of_sight(origin, point, &arena.solids)
}

fn chest(target: &PlayerState) -> [f32; 3] {
    [
        target.x,
        target.y - PLAYER_FLOOR_Y + FIGHTER_HEIGHT * 0.5,
        target.z,
    ]
}

fn visible_aim(
    me: &PlayerState,
    target: &PlayerState,
    arena: &Arena,
    profile: Profile,
) -> Option<[f32; 3]> {
    let head = [
        target.x,
        target.y - PLAYER_FLOOR_Y
            + fragr_server::combat::stance_eye(target.campaign, target.ducking),
        target.z,
    ];
    [chest(target), head]
        .into_iter()
        .find(|point| visible(me, *point, arena, profile))
}

#[derive(Default)]
struct Perception {
    first_seen: BTreeMap<Uuid, u64>,
    strips: paver::Perception,
}

impl Perception {
    fn observe(
        &mut self,
        snapshot: &Snapshot,
        id: Uuid,
        arena: &Arena,
        profile: Profile,
    ) -> Snapshot {
        let mut observed = snapshot.clone();
        let Some(me) = snapshot.players.iter().find(|p| p.id == id) else {
            return observed;
        };
        self.first_seen.retain(|id, _| {
            snapshot
                .players
                .iter()
                .any(|p| p.id == *id && visible_aim(me, p, arena, profile).is_some())
        });
        observed.players.retain(|p| {
            // Combat selection excludes corpses, but perception must still
            // hide an unseen opponent's death from search memory.
            if me.id == p.id
                || !fragr_server::protocol::hostile(me.campaign, p.campaign)
                || (me.team.is_some() && me.team == p.team)
            {
                return true;
            }
            if visible_aim(me, p, arena, profile).is_none() {
                return false;
            }
            let since = self.first_seen.entry(p.id).or_insert(snapshot.tick);
            snapshot.tick.saturating_sub(*since) >= profile.reaction_ticks
        });
        observed
            .pickups
            .retain(|p| visible(me, [p.x, p.y + 0.3, p.z], arena, profile));
        self.strips.filter(&mut observed, me, arena, profile);
        observed
    }
}

/// Convert all target identities to ordinary yaw/pitch input, constrain turning,
/// and introduce time-correlated aim error. Never leave a server auto-aim target.
fn constrain(
    mut action: Action,
    me: &PlayerState,
    observed: &Snapshot,
    profile: Profile,
    seed: u64,
    arena: &Arena,
) -> Action {
    let wanted_motion = fragr_server::movement::wish_dir(
        &fragr_server::movement::MoveInput {
            forward: action.forward,
            back: action.back,
            left: action.left,
            right: action.right,
            yaw: action.yaw.unwrap_or(me.yaw),
            ..Default::default()
        },
        action.yaw.unwrap_or(me.yaw),
    );
    let point = action.look_at.take().and_then(|look| {
        look.player_id
            .and_then(|id| {
                observed
                    .players
                    .iter()
                    .find(|p| p.id == id)
                    .and_then(|p| visible_aim(me, p, arena, profile))
            })
            .or_else(|| Some([look.x?, look.y?, look.z?]))
    });
    let origin = eye(me);
    let (mut yaw, mut pitch) = point.map_or(
        (
            action.yaw.unwrap_or(me.yaw),
            action.pitch.unwrap_or(me.pitch),
        ),
        |p| {
            let dx = p[0] - origin[0];
            let dz = p[2] - origin[2];
            (dz.atan2(dx), (p[1] - origin[1]).atan2(dx.hypot(dz)))
        },
    );
    if action.fire {
        let time = observed.tick as f32 * DT;
        let phase = (seed % 997) as f32 * 0.37;
        let error = profile.aim_error_degrees.to_radians();
        yaw += (time * 3.1 + phase).sin() * error;
        pitch += (time * 2.3 + phase).cos() * error * 0.6;
    }
    let turn = profile.turn_degrees_per_second.to_radians() * DT;
    let delta = angle(yaw - me.yaw);
    action.yaw = Some(me.yaw + delta.clamp(-turn, turn));
    action.pitch = Some(me.pitch + (pitch - me.pitch).clamp(-turn, turn));
    // Shared navigation can move toward a waypoint while looking at an
    // objective after movement. Human yaw applies before movement: preserve
    // that world direction with ordinary strafe keys in the constrained view.
    if wanted_motion != (0.0, 0.0) {
        let choices = [
            (true, false, false, false),
            (false, true, false, false),
            (false, false, true, false),
            (false, false, false, true),
            (true, false, true, false),
            (true, false, false, true),
            (false, true, true, false),
            (false, true, false, true),
        ];
        let score = |k: &(bool, bool, bool, bool)| {
            let motion = fragr_server::movement::wish_dir(
                &fragr_server::movement::MoveInput {
                    forward: k.0,
                    back: k.1,
                    left: k.2,
                    right: k.3,
                    ..Default::default()
                },
                action.yaw.unwrap(),
            );
            motion.0 * wanted_motion.0 + motion.1 * wanted_motion.1
        };
        let best = choices
            .into_iter()
            .max_by(|a, b| score(a).total_cmp(&score(b)))
            .unwrap();
        (action.forward, action.back, action.left, action.right) = best;
    }
    action.fire &= delta.abs() < 8_f32.to_radians();
    action
}

fn configure_map(client: &mut MissionClient, message: &ServerMessage) -> Result<(), String> {
    if let ServerMessage::MapInfo {
        map_id,
        m02_objectives,
        m02_side_ward,
        m19,
        mission,
        half_extent,
        solids,
        presentation,
        ..
    } = message
    {
        client
            .replace_map_with_id(
                *map_id,
                *m02_objectives,
                *m02_side_ward,
                mission.as_ref(),
                *half_extent,
                solids,
                presentation.as_ref(),
            )
            .map_err(str::to_owned)?;
        client
            .replace_map_with_m19(m19.as_ref(), *half_extent, solids, presentation.as_ref())
            .map_err(str::to_owned)?;
    }
    Ok(())
}

pub fn trial(
    seed: u64,
    profile: Profile,
    difficulty: CampaignDifficulty,
    max_ticks: u64,
) -> Result<Trial, String> {
    trial_recorded(seed, profile, difficulty, max_ticks, Recording::None).map(|(row, _)| row)
}

fn trial_recorded(
    seed: u64,
    profile: Profile,
    difficulty: CampaignDifficulty,
    max_ticks: u64,
    recording: Recording,
) -> Result<(Trial, Option<serde_json::Value>), String> {
    trial_with_actions(seed, profile, difficulty, max_ticks, recording, |action| {
        action
    })
}

/// The action seam lets calibration supply a deliberately ineffective policy
/// without editing the simulation, granting resources or forcing an outcome.
fn trial_with_actions(
    seed: u64,
    profile: Profile,
    difficulty: CampaignDifficulty,
    max_ticks: u64,
    recording: Recording,
    actions: impl FnMut(Action) -> Action,
) -> Result<(Trial, Option<serde_json::Value>), String> {
    scenario_trial_with_actions(
        Scenario::RecallNotice,
        seed,
        profile,
        difficulty,
        max_ticks,
        recording,
        actions,
    )
    .map(|(trial, review, _)| (trial, review))
}

fn scenario_trial_with_actions(
    scenario: Scenario,
    seed: u64,
    profile: Profile,
    difficulty: CampaignDifficulty,
    max_ticks: u64,
    recording: Recording,
    actions: impl FnMut(Action) -> Action,
) -> Result<(Trial, Option<serde_json::Value>, Vec<serde_json::Value>), String> {
    validate_trial(profile, max_ticks)?;
    let mut session = GameSession::with_authored_map(
        AuthoredSource::Mission(scenario.mission())
            .load()
            .map_err(|e| e.to_string())?,
    );
    session.state.use_replay_ids();
    session.state.seed(seed);
    session
        .state
        .set_campaign_difficulty(difficulty)
        .map_err(str::to_owned)?;
    session.state.enable_campaign_run().map_err(str::to_owned)?;
    let id = admit(&mut session, scenario.mission(), 1);
    drive(
        &mut session,
        id,
        Leg {
            scenario,
            seed,
            profile,
            difficulty,
            max_ticks,
            recording,
            stop_at_pending: false,
        },
        actions,
        |_| Ok(()),
    )
}

fn validate_trial(profile: Profile, max_ticks: u64) -> Result<(), String> {
    if !(1..=36_000).contains(&max_ticks)
        || !profile.view_degrees.is_finite()
        || !(30.0..=180.0).contains(&profile.view_degrees)
        || !profile.turn_degrees_per_second.is_finite()
        || !(30.0..=720.0).contains(&profile.turn_degrees_per_second)
        || !profile.aim_error_degrees.is_finite()
        || !(0.0..=15.0).contains(&profile.aim_error_degrees)
        || profile.reaction_ticks > 40
    {
        return Err(
            "campaign trial requires bounded finite profile values and 1..=36000 ticks".into(),
        );
    }
    Ok(())
}

/// Admit the one ordinary human participant and acknowledge `attempt`.
fn admit(session: &mut GameSession, mission: MissionId, attempt: u32) -> Uuid {
    let id = Uuid::from_u128(479);
    session.state.add_player(id, "Visitor".into(), Role::Human);
    session.state.arm_joined_magazines(id);
    session.state.acknowledge_mission(
        id,
        MissionReady {
            id: mission,
            attempt,
        },
    );
    id
}

/// One continuous stretch of play in one session.
#[derive(Clone, Copy)]
struct Leg {
    scenario: Scenario,
    seed: u64,
    profile: Profile,
    difficulty: CampaignDifficulty,
    max_ticks: u64,
    recording: Recording,
    /// End at a pending Continue instead of accepting it in this session.
    stop_at_pending: bool,
}

/// Play one admitted participant with the constrained policy. `persist`
/// observes the session after each simulation step and accepted Continue.
fn drive(
    session: &mut GameSession,
    id: Uuid,
    leg: Leg,
    mut actions: impl FnMut(Action) -> Action,
    mut persist: impl FnMut(&GameSession) -> Result<(), String>,
) -> Result<(Trial, Option<serde_json::Value>, Vec<serde_json::Value>), String> {
    let Leg {
        scenario,
        seed,
        profile,
        difficulty,
        max_ticks,
        recording,
        stop_at_pending,
    } = leg;
    persist(session)?;
    let mut client = MissionClient::default();
    let mut map_record = session.state.map_info();
    configure_map(&mut client, &map_record)?;
    let mut navigator = Navigator::default();
    let mut perception = Perception::default();
    let mut search = search::Search::default();
    let mut report = Trial {
        seed,
        profile: profile.name.into(),
        difficulty,
        outcome: "timeout".into(),
        deaths: 0,
        continues_spent: 0,
        seconds: 0.0,
        first_contact_seconds: None,
        first_contact_distance: None,
        shots: 0,
        hits: 0,
        kills: 0,
        damage_received: 0,
        resolved_damage_outside_view: 0,
        hits_received: Vec::new(),
        hits_omitted: 0,
        reloads: 0,
        longest_no_progress_seconds: 0.0,
        last_phase: MissionPhase::FindTransfer,
        last_feet: [0.0; 3],
        hp: 100,
        bullets: 0,
        weapons: Vec::new(),
        final_attempt: 1,
        teaching: None,
        market: None,
        carry: None,
    };
    let mut progress = 0;
    let mut last_supply = 0;
    let mut visited = BTreeSet::new();
    let mut reload_down = false;
    let mut heard: Option<(u64, [f32; 3])> = None;
    let mut scan_remaining = 0.0_f32;
    let mut evade: Option<(u64, [f32; 2], f32)> = None;
    let mut review = None;
    let mut frames = VecDeque::new();
    let mut teaching = scenario.is_m19().then(|| {
        let recorder =
            teaching::Recorder::new(id, seed, profile, difficulty, recording != Recording::None);
        if scenario == Scenario::M19Tanks {
            recorder.through_tanks()
        } else {
            recorder
        }
    });
    let mut market = scenario.plays_market().then(|| {
        if scenario == Scenario::M19Tanks {
            market::Recorder::through_tanks()
        } else {
            market::Recorder::default()
        }
    });
    while session.state.tick < max_ticks {
        let snapshot = session.state.snapshot();
        if recording != Recording::None {
            frames.push_back(snapshot.clone());
            if frames.len() > 80 {
                frames.pop_front();
            }
        }
        let state = session.state.mission_state().ok_or("mission vanished")?;
        report.final_attempt = state.attempt;
        if let Some(recorder) = &mut market {
            recorder.observe(snapshot.tick, &state, market_status(session, id));
        }
        if let Some(recorder) = &mut teaching {
            let player = session.state.players.iter().find(|p| p.id == id);
            if recorder.observe(
                &snapshot,
                &state,
                session.state.map.arena(),
                player.map(|p| p.vy),
                &map_record,
            ) {
                progress = snapshot.tick;
            }
        }
        if state.phase != report.last_phase {
            progress = snapshot.tick;
            report.last_phase = state.phase;
        }
        if state.phase == MissionPhase::Departed {
            report.outcome = "departed".into();
            break;
        }
        if scenario.segment_complete(
            &state,
            snapshot.players.iter().any(|p| p.id == id && p.hp > 0),
        ) {
            report.outcome = "segment_complete".into();
            break;
        }
        let attempt = state.attempt;
        client
            .observe(snapshot.tick, state.clone())
            .map_err(str::to_owned)?;
        let Some(me) = snapshot.players.iter().find(|p| p.id == id && p.hp > 0) else {
            report.hp = 0;
            report.deaths += 1;
            let run = state.run.ok_or("dead campaign has no run")?;
            if run.status == CampaignRunStatus::Failed {
                report.outcome = "exhausted".into();
                break;
            }
            if stop_at_pending && run.status == CampaignRunStatus::Continue {
                report.outcome = "pending_continue".into();
                break;
            }
            if run.status != CampaignRunStatus::Continue
                || !session.state.continue_mission(
                    id,
                    MissionContinue {
                        id: state.id,
                        run_id: run.id,
                        attempt,
                    },
                )
            {
                return Err("ordinary campaign Continue was refused".into());
            }
            persist(session)?;
            report.continues_spent += 1;
            navigator.clear();
            perception = Perception::default();
            search = search::Search::default();
            frames.clear();
            heard = None;
            evade = None;
            scan_remaining = 0.0;
            reload_down = false;
            visited.clear();
            last_supply = 0;
            progress = snapshot.tick;
            map_record = session.state.map_info();
            configure_map(&mut client, &map_record)?;
            session.state.acknowledge_mission(
                id,
                MissionReady {
                    id: state.id,
                    attempt: attempt + 1,
                },
            );
            continue;
        };
        report.last_feet = [me.x, me.y - PLAYER_FLOOR_Y, me.z];
        report.hp = me.hp;
        let player = session
            .state
            .players
            .iter()
            .find(|p| p.id == id)
            .ok_or("player vanished")?;
        let gear: LoadoutState = player
            .inventory
            .state(id, player.weapon, snapshot.tick)
            .ok_or("loadout missing")?;
        report.bullets = gear.ammo(AmmoPool::Bullets);
        report.weapons = gear.weapons.iter().map(|w| w.name().to_owned()).collect();
        if gear.personal_claims.len() != last_supply {
            progress = snapshot.tick;
            last_supply = gear.personal_claims.len();
        }
        let arena = session.state.map.arena();
        let observed = perception.observe(&snapshot, id, arena, profile);
        if scenario.is_m19() {
            search.observe(&observed, id);
        }
        if let Some(recorder) = &mut teaching {
            recorder.observe_perception(&observed);
        }
        if let Some(target) = snapshot
            .players
            .iter()
            .find(|p| me.is_hostile_to(p) && visible_aim(me, p, arena, profile).is_some())
        {
            report
                .first_contact_seconds
                .get_or_insert(snapshot.tick as f64 / 20.0);
            report
                .first_contact_distance
                .get_or_insert((target.x - me.x).hypot(target.z - me.z));
        }
        let mut wanted = control_action_with_target_filter(
            id,
            &observed,
            Some(&gear),
            Action::default(),
            true,
            |_, _| true,
        );
        // Visible equipment is a deliberate short detour, not an omniscient
        // tour of every pad. The shared inventory controller owns gun choice.
        let supply = observed
            .pickups
            .iter()
            .filter(|p| p.available && (p.x - me.x).hypot(p.z - me.z) < 10.0)
            .filter(|p| {
                (p.kind == "weapon"
                    && super::weapon_from_wire(&p.weapon).is_some_and(|w| !gear.owns(w)))
                    || (p.kind == "health" && me.hp < 65)
            })
            .min_by(|a, b| {
                (a.x - me.x)
                    .hypot(a.z - me.z)
                    .total_cmp(&(b.x - me.x).hypot(b.z - me.z))
            });
        if let Some(pad) = supply.filter(|_| !wanted.fire || me.hp < 35) {
            wanted = Action {
                forward: true,
                look_at: Some(LookAt {
                    x: Some(pad.x),
                    y: Some(pad.y),
                    z: Some(pad.z),
                    player_id: None,
                }),
                ..Default::default()
            };
        }
        for shot in &snapshot.shot_results {
            if shot.target_id == Some(id) && heard.is_none() {
                if let Some(trace) = &shot.trace {
                    heard = Some((snapshot.tick, trace.origin));
                }
            }
        }
        let mut pursuing = false;
        if scenario.is_m19()
            && wanted.look_at.is_none()
            && state
                .m19
                .as_ref()
                .and_then(|facts| facts.current.as_ref())
                .is_some_and(|objective| {
                    matches!(objective.id.as_str(), "concourse_crossing" | "tram_street")
                        || (scenario.plays_market() && objective.id == "market_strips")
                })
        {
            if let Some(point) = search.destination(me, &observed) {
                // Search only the previously seen location. The shared route
                // controller receives no invented target or hidden live pose.
                wanted = Action {
                    forward: true,
                    look_at: Some(LookAt {
                        x: Some(point[0]),
                        y: Some(point[1] + EYE_HEIGHT),
                        z: Some(point[2]),
                        player_id: None,
                    }),
                    weapon_swap: wanted.weapon_swap,
                    ..Default::default()
                };
                pursuing = true;
            }
        }
        let mut action = client.steer_with_equipment(
            &mut navigator,
            session.state.map.navigation(),
            id,
            &observed,
            wanted,
            Some(&gear),
        );
        let market_escape = (scenario.plays_market()
            && state
                .m19
                .as_ref()
                .and_then(|facts| facts.current.as_ref())
                .is_some_and(|objective| objective.id == "market_strips"))
        .then(|| action.clone());
        let telling = observed.players.iter().find(|p| me.is_hostile_to(p) && matches!(p.campaign, Some(CampaignActor::Hostile { phase: EnemyPhase::Windup | EnemyPhase::Firing, phase_started, .. }) if snapshot.tick.saturating_sub(phase_started) >= profile.reaction_ticks));
        if evade.is_some_and(|(until, _, _)| snapshot.tick > until) {
            evade = None;
        }
        if let Some(guard) = telling.filter(|_| evade.is_none()) {
            let feet = report.last_feet;
            // A published raised gun commits its firing line. Keep one way
            // off it; turning to another target must not reverse the dodge.
            let side = [-1.0, 1.0]
                .into_iter()
                .map(|side| guard.yaw + side * PI * 0.5)
                .find(|yaw| {
                    session.state.map.navigation().walkable(
                        feet,
                        [
                            feet[0] + yaw.cos() * 2.2,
                            feet[1],
                            feet[2] + yaw.sin() * 2.2,
                        ],
                    )
                });
            evade = side.map(|yaw| (snapshot.tick + 25, [me.x, me.z], yaw));
        }
        if let Some((_, from, yaw)) = evade {
            if (me.x - from[0]) * yaw.cos() + (me.z - from[1]) * yaw.sin() < 2.0 {
                action.yaw = Some(yaw);
                action.forward = true;
                action.back = false;
                action.left = false;
                action.right = false;
            }
        }
        if let Some((tick, point)) = heard {
            if snapshot.tick.saturating_sub(tick) > 60 || wanted_is_combat(&action) {
                heard = None;
            } else if snapshot.tick.saturating_sub(tick) >= profile.reaction_ticks {
                action = Action {
                    look_at: Some(LookAt {
                        x: Some(point[0]),
                        y: Some(point[1]),
                        z: Some(point[2]),
                        player_id: None,
                    }),
                    ..Default::default()
                };
                if angle((point[2] - me.z).atan2(point[0] - me.x) - me.yaw).abs() < 0.1 {
                    heard = None;
                }
            }
        }
        // A reached arrival can still have an unfinished encounter. Looking
        // only after kills strands a constrained viewer when the last guard
        // has left its view. Retry the same bounded sweep at that public goal;
        // no unseen actor position or encounter roster informs this decision.
        if scenario.is_m19()
            && scan_remaining <= 0.0
            && snapshot.tick.saturating_sub(progress) >= 60
            && state.m19.as_ref().and_then(|facts| facts.current.as_ref()).is_some_and(|objective| {
                matches!(&objective.action, fragr_server::protocol::MissionObjectiveAction::Arrival { region, .. } if region.contains(report.last_feet))
            })
        {
            scan_remaining = TAU;
        }
        // A cleared target is not proof the room is clear. Inspect the room
        // before following the next objective, using the same turn limit.
        if scan_remaining > 0.0
            && !pursuing
            && !wanted_is_combat(&action)
            && heard.is_none()
            && evade.is_none()
        {
            let step = (profile.turn_degrees_per_second.to_radians() * DT).min(scan_remaining);
            scan_remaining -= step;
            action = Action {
                yaw: Some(me.yaw + step),
                pitch: Some(0.0),
                ..Default::default()
            };
        }
        action = apply_reload(action, &gear, reload_down);
        action = constrain(action, me, &observed, profile, seed, arena);
        let mut guard = None;
        if let Some(shared) = market_escape {
            let shared = constrain(
                apply_reload(shared, &gear, reload_down),
                me,
                &observed,
                profile,
                seed,
                arena,
            );
            let (arbitrated, branch) =
                market_guard::arbitrate(shared, action, me, &observed, arena);
            action = arbitrated;
            guard = Some(branch);
        }
        action = actions(action);
        reload_down = action.reload;
        report.reloads += u32::from(action.reload);
        let feet = report.last_feet;
        if visited.insert((
            (feet[0] / 2.0).floor() as i32,
            (feet[1] / 2.0).floor() as i32,
            (feet[2] / 2.0).floor() as i32,
        )) {
            progress = snapshot.tick;
        }
        report.longest_no_progress_seconds = report
            .longest_no_progress_seconds
            .max(snapshot.tick.saturating_sub(progress) as f64 / 20.0);
        if let Some(recorder) = &mut teaching {
            recorder.observe_stall(
                snapshot.tick.saturating_sub(progress) as f64 / 20.0,
                me,
                &map_record,
            );
        }
        let visible_shooters: Vec<Uuid> = snapshot
            .players
            .iter()
            .filter(|p| visible_aim(me, p, arena, profile).is_some())
            .map(|p| p.id)
            .collect();
        // Diagnostic market step facts: captured after the decision is final.
        let market_step = market
            .as_ref()
            .filter(|recorder| recorder.in_market())
            .map(|_| {
                (
                    snapshot
                        .players
                        .iter()
                        .map(|p| (p.id, p.name.clone()))
                        .collect::<BTreeMap<_, _>>(),
                    action.forward || action.back || action.left || action.right || action.jump,
                    market_guard::airborne(me, arena),
                )
            });
        session.state.set_action(id, action);
        let messages = session.tick_messages(DT);
        if let (Some(recorder), Some((names, moving, airborne))) = (&mut market, market_step) {
            let decision = market::stage::Decision {
                tick: snapshot.tick,
                feet,
                hp: me.hp,
                armor: me.armor,
                airborne,
                moving,
                telling: telling.is_some(),
                guard,
                recognized: observed.paver_strips.iter().map(|s| s.owner_id).collect(),
                strips: &snapshot.paver_strips,
                names: &names,
            };
            let strips = session.state.snapshot().paver_strips;
            let shots = session
                .state
                .shot_results
                .iter()
                .filter(|shot| shot.target_id == Some(id) && shot.shooter_id != id)
                .map(|shot| (shot.shooter.clone(), shot.damage))
                .collect();
            recorder.step(
                &decision,
                market::stage::Outcome {
                    strips: &strips,
                    status: market_status(session, id),
                    shots,
                },
            );
        }
        persist(session)?;
        for shot in &session.state.shot_results {
            if shot.shooter_id == id {
                report.shots += 1;
                report.hits += u32::from(shot.hit);
                report.kills += u32::from(shot.killed);
                if shot.killed {
                    scan_remaining = TAU;
                    if recording == Recording::FirstKill && review.is_none() {
                        review = Some(
                            serde_json::json!({"event":"first_kill","seed":seed,"profile":profile.name,"difficulty":difficulty,"attempt":attempt,"view":me,"map_info":session.state.map_info(),"snapshot":snapshot,"frames":frames}),
                        );
                    }
                }
                if shot.damage > 0 {
                    progress = snapshot.tick;
                }
            } else if shot.target_id == Some(id) {
                if recording == Recording::Fatal && shot.killed {
                    review = Some(
                        serde_json::json!({"event":"fatal_hit","seed":seed,"profile":profile.name,"difficulty":difficulty,"attempt":attempt,"view":me,"map_info":session.state.map_info(),"snapshot":snapshot,"frames":frames}),
                    );
                }
                if !visible_shooters.contains(&shot.shooter_id) {
                    report.resolved_damage_outside_view += shot.damage;
                }
                if report.hits_received.len() < 256 {
                    let source = snapshot.players.iter().find(|p| p.id == shot.shooter_id);
                    report.hits_received.push(Hit {
                        tick: session.state.tick,
                        attempt,
                        source: shot.shooter.clone(),
                        feet,
                        bearing_degrees: source
                            .map(|p| angle((p.z - me.z).atan2(p.x - me.x) - me.yaw).to_degrees()),
                        source_visible: visible_shooters.contains(&shot.shooter_id),
                        resolved_damage: shot.damage,
                    });
                } else {
                    report.hits_omitted += 1;
                }
            }
        }
        report.seconds = session.state.tick as f64 / 20.0;
        for message in &messages {
            configure_map(&mut client, message)?;
            if matches!(message, ServerMessage::MapInfo { .. }) {
                map_record = message.clone();
            }
        }
    }
    if let Some(record) = session.state.player_record(id) {
        report.deaths = record.total.deaths.min(u32::MAX as u64) as u32;
        report.damage_received =
            (record.total.hp_lost + record.total.armor_lost).min(i32::MAX as u64) as i32;
    }
    if let Some(player) = session.state.players.iter().find(|p| p.id == id) {
        report.hp = player.hp.max(0);
        report.last_feet = [player.x, player.y - PLAYER_FLOOR_Y, player.z];
        if let Some(gear) = player
            .inventory
            .state(id, player.weapon, session.state.tick)
        {
            report.bullets = gear.ammo(AmmoPool::Bullets);
            report.weapons = gear.weapons.iter().map(|w| w.name().to_owned()).collect();
        }
    }
    if let Some(state) = session.state.mission_state() {
        // The final permitted action has already advanced the simulation.
        // Observe its result even when no next control tick is permitted.
        // Duplicate observations on normal break paths are idempotent.
        report.final_attempt = state.attempt;
        if let Some(recorder) = &mut market {
            let status = market_status(session, id);
            recorder.observe(session.state.tick, &state, status.clone());
            recorder.finish_attempt(session.state.tick, &state, status);
        }
        if let Some(recorder) = &mut teaching {
            let player = session.state.players.iter().find(|p| p.id == id);
            recorder.observe(
                &session.state.snapshot(),
                &state,
                session.state.map.arena(),
                player.map(|p| p.vy),
                &map_record,
            );
        }
        report.last_phase = state.phase;
        if state
            .run
            .is_some_and(|run| run.status == CampaignRunStatus::Failed)
        {
            report.outcome = "exhausted".into();
        } else if state.phase == MissionPhase::Departed {
            report.outcome = "departed".into();
        } else if scenario.segment_complete(&state, report.hp > 0) {
            report.outcome = "segment_complete".into();
        }
    }
    let teaching_reviews = if let Some(recorder) = teaching {
        let (metrics, windows) = recorder.finish();
        report.teaching = Some(metrics);
        windows
    } else {
        Vec::new()
    };
    report.market = market.map(market::Recorder::finish);
    Ok((report, review, teaching_reviews))
}

/// Observation only: these are the participant's own ordinary equipment and
/// status, including the terminal body omitted from a living snapshot.
fn market_status(session: &GameSession, id: Uuid) -> Option<market::Status> {
    let player = session
        .state
        .players
        .iter()
        .find(|player| player.id == id)?;
    Some(market::Status {
        feet: [player.x, player.y - PLAYER_FLOOR_Y, player.z],
        hp: player.hp.max(0),
        armor: player.armor,
        loadout: player
            .inventory
            .state(id, player.weapon, session.state.tick)?,
    })
}

fn wanted_is_combat(action: &Action) -> bool {
    action
        .look_at
        .as_ref()
        .is_some_and(|look| look.player_id.is_some())
}

fn reload_requested(gear: &LoadoutState, reload_down: bool) -> bool {
    !reload_down
        && gear
            .loaded
            .iter()
            .any(|m| m.weapon == gear.selected && m.rounds == 0 && m.ready_at.is_none())
        && reserve_rounds(gear) > 0
}

fn reserve_rounds(gear: &LoadoutState) -> u16 {
    let Some(pool) = gear.selected.ammo_pool() else {
        return 0;
    };
    let loaded: u16 = gear
        .loaded
        .iter()
        .filter(|m| m.weapon.ammo_pool() == Some(pool))
        .map(|m| m.rounds)
        .sum();
    gear.ammo(pool).saturating_sub(loaded)
}

fn apply_reload(mut action: Action, gear: &LoadoutState, reload_down: bool) -> Action {
    action.reload = reload_requested(gear, reload_down);
    // The shared selector normally runs unmagazined agents. A human's empty
    // magazine must stay selected until its ordinary reload finishes, rather
    // than switching to Fists and cancelling the reload on the next tick.
    if gear.loaded.iter().any(|m| {
        m.weapon == gear.selected
            && (m.ready_at.is_some() || (m.rounds == 0 && reserve_rounds(gear) > 0))
    }) {
        action.weapon_swap = None;
        action.fire = false;
    }
    action
}

pub fn run(seeds: std::ops::Range<u64>, max_ticks: u64) -> Result<Report, String> {
    run_scenario(Scenario::RecallNotice, seeds, max_ticks)
}

pub fn run_scenario(
    scenario: Scenario,
    seeds: std::ops::Range<u64>,
    max_ticks: u64,
) -> Result<Report, String> {
    if scenario == Scenario::M02Carry {
        return carry::run(seeds, max_ticks);
    }
    if seeds.is_empty() || seeds.end - seeds.start > 64 {
        return Err("campaign survey requires 1..=64 seeds".into());
    }
    let mut trials = Vec::new();
    let mut review = None;
    let mut first_kill_review = None;
    let mut teaching_reviews = Vec::new();
    let first_seed = seeds.start;
    for seed in seeds {
        for profile in PROFILES {
            for difficulty in [
                CampaignDifficulty::Assisted,
                CampaignDifficulty::Standard,
                CampaignDifficulty::Severe,
            ] {
                let fatal = seed == first_seed
                    && profile.name == "deliberate"
                    && difficulty == CampaignDifficulty::Standard;
                let first_kill = seed == first_seed
                    && profile.name == "reference"
                    && difficulty == CampaignDifficulty::Assisted;
                let recording = if fatal {
                    Recording::Fatal
                } else if first_kill {
                    Recording::FirstKill
                } else if scenario.is_m19() && seed == first_seed {
                    Recording::Teaching
                } else {
                    Recording::None
                };
                let (row, frame, windows) = scenario_trial_with_actions(
                    scenario,
                    seed,
                    profile,
                    difficulty,
                    max_ticks,
                    recording,
                    |action| action,
                )?;
                teaching_reviews.extend(windows);
                if fatal {
                    review = frame;
                } else if first_kill {
                    first_kill_review = frame;
                }
                eprintln!("campaign {} seed={} {:?}: {} {:.1}s, {} shots, {} hits, {} damage, {:.1}s stall", row.profile, seed, difficulty, row.outcome, row.seconds, row.shots, row.hits, row.damage_received, row.longest_no_progress_seconds);
                trials.push(row);
            }
        }
    }
    let observation = match scenario {
        Scenario::M02Carry => carry::OBSERVATION,
        Scenario::RecallNotice => recall_notice_observation!(),
        Scenario::M19Teaching => "Standalone M19 discovery entry with Fists, ordinary earned supplies and a fresh three-continue budget, not inherited M18 progress. Guided public objectives and exact wire-authored jetpack launch/landing hints; constrained enemy, supply and sampled floor-strip perception, reaction and turning; ordinary finite-magazine human actions. Crossing/street search remembers at most 64 delayed visible enemy positions for less than 30 seconds; it investigates the last observed point without firing at hidden actors and retires reached, expired or confirmed-dead memories. An unfinished arrival gets another bounded sweep after three seconds without progress. Ends after tram_street, before the market. Supported powered ascent from below the gallery and optional Paver interruption/strip damage are reported separately. Immediate Continue with no menu delay; no human-population or rendered-readability claim.",
        Scenario::M19Market => "Standalone M19 discovery entry with Fists and a fresh three-continue budget, not inherited M18 progress. Same constrained profile, ordinary finite magazines, public objectives, authored jetpack hints, sampled floor-strip perception and last-observed enemy memory as the teaching survey. Search also applies during market_strips; no equipment, health or progress grants. Market-only evaluator revision: shared escape from a currently recognized strip takes priority over generic dodge, hearing and scanning. Outside strips, a grounded ordinary-key step predicted through existing movement and solids is withheld if it crosses a currently recognized strip; aim, fire and reload remain ordinary. No unseen-hazard memory or airborne-velocity inference. This repairs evaluator arbitration, not game balance. Ends immediately after market_strips, before acting on water_tanks. Full earned equipment, HP, armor and continues are recorded at entry, public market-objective entry, completion and each terminal attempt. Market actors may already have been encountered before tram_street completes. Challenge flags are attempt-monotone; a newly observed flag after market entry establishes timing only, not a particular Paver or hit count. Prior-true or absent attributable evidence is unknown. Per-action stage facts after public market entry record authoritative strip contacts, unshot loss inside a working strip, shot loss by shooter, the guard branch and the fatal step cause; they are read after each action and never feed a decision. Immediate Continue with no menu delay; no human-population or rendered-readability claim.",
        Scenario::M19Tanks => "The M19 market survey unchanged through market_strips, continued with the same profile, finite equipment, lives and continues to the next authored objective, water_tanks, and ended immediately after it completes, before acting on roof_loop. No kit, health, save or objective is granted or invented. The market completion receipt is kept as a non-terminal boundary; continuation facts after it are recorded separately from market facts, and later challenge flags carry no market timing. A death on the continuation retries from the ordinary attempt start, so the market must be earned again. A standalone endpoint, not an inherited M19 clear or fresh-player acceptance. Immediate Continue with no menu delay; no human-population or rendered-readability claim.",
    };
    Ok(Report {
        schema: 3,
        build: env!("FRAGR_CLI_VERSION"),
        commit: env!("FRAGR_BUILD_COMMIT"),
        observation,
        profiles: PROFILES,
        decision_hz: 20,
        continuation_delay_seconds: 0,
        scenario,
        trials,
        review,
        first_kill_review,
        teaching_reviews,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use fragr_server::movement::Solid;
    use fragr_server::protocol::LookAt;

    fn scene() -> (Snapshot, Arena, Uuid, Uuid) {
        let mut session = GameSession::new();
        let id = Uuid::from_u128(1);
        let target = Uuid::from_u128(2);
        session.state.add_player(id, "Viewer".into(), Role::Human);
        session
            .state
            .add_player(target, "Target".into(), Role::Agent);
        let mut snapshot = session.state.snapshot();
        for p in &mut snapshot.players {
            p.x = if p.id == id { 0.0 } else { 10.0 };
            p.z = 0.0;
            p.y = PLAYER_FLOOR_Y;
            p.yaw = 0.0;
            p.pitch = 0.0;
        }
        (
            snapshot,
            Arena {
                half: 64.0,
                solids: Vec::new(),
            },
            id,
            target,
        )
    }

    #[test]
    fn reaction_requires_continuous_visible_observation() {
        let (mut snapshot, arena, id, target) = scene();
        let profile = PROFILES[1];
        // Isolated perception fixture, not earned campaign progress.
        let mut inventory = fragr_server::inventory::Inventory::new(
            fragr_server::protocol::EquipmentPolicy::Discovery,
        );
        inventory.grant_weapon(fragr_server::protocol::WeaponType::Tack);
        let gear = inventory
            .state(id, fragr_server::protocol::WeaponType::Tack, 0)
            .unwrap();
        let mut perception = Perception::default();
        for tick in 0..=profile.reaction_ticks {
            snapshot.tick = tick;
            let view = perception.observe(&snapshot, id, &arena, profile);
            assert_eq!(
                view.players.iter().any(|p| p.id == target),
                tick == profile.reaction_ticks
            );
            let wanted = control_action_with_target_filter(
                id,
                &view,
                Some(&gear),
                Action::default(),
                true,
                |_, _| true,
            );
            let me = snapshot.players.iter().find(|p| p.id == id).unwrap();
            let action = constrain(wanted, me, &view, profile, 42, &arena);
            assert_eq!(action.fire, tick == profile.reaction_ticks);
        }
        snapshot
            .players
            .iter_mut()
            .find(|p| p.id == target)
            .unwrap()
            .x = -10.0;
        snapshot.tick += 1;
        assert!(!perception
            .observe(&snapshot, id, &arena, profile)
            .players
            .iter()
            .any(|p| p.id == target));
        snapshot
            .players
            .iter_mut()
            .find(|p| p.id == target)
            .unwrap()
            .x = 10.0;
        snapshot.tick += 1;
        assert!(!perception
            .observe(&snapshot, id, &arena, profile)
            .players
            .iter()
            .any(|p| p.id == target));
    }

    #[test]
    fn remembered_positions_and_deaths_require_delayed_visible_observations() {
        let (mut snapshot, arena, id, target) = scene();
        let profile = PROFILES[1];
        let mut perception = Perception::default();
        let mut memory = search::Search::default();
        for tick in 0..=profile.reaction_ticks {
            snapshot.tick = tick;
            let observed = perception.observe(&snapshot, id, &arena, profile);
            memory.observe(&observed, id);
            let mut hidden = observed.clone();
            hidden.players.retain(|p| p.id != target);
            let me = hidden.players.iter().find(|p| p.id == id).unwrap();
            assert_eq!(
                memory.destination(me, &hidden).is_some(),
                tick == profile.reaction_ticks
            );
        }
        let enemy = snapshot
            .players
            .iter_mut()
            .find(|p| p.id == target)
            .unwrap();
        enemy.x = -20.0;
        enemy.hp = 0;
        snapshot.tick += 1;
        let observed = perception.observe(&snapshot, id, &arena, profile);
        assert!(!observed.players.iter().any(|p| p.id == target));
        memory.observe(&observed, id);
        let me = observed.players.iter().find(|p| p.id == id).unwrap();
        assert_eq!(memory.destination(me, &observed), Some([10.0, 0.0, 0.0]));
        snapshot
            .players
            .iter_mut()
            .find(|p| p.id == target)
            .unwrap()
            .x = 10.0;
        for elapsed in 0..=profile.reaction_ticks {
            snapshot.tick += 1;
            let observed = perception.observe(&snapshot, id, &arena, profile);
            assert_eq!(
                observed.players.iter().any(|p| p.id == target),
                elapsed == profile.reaction_ticks
            );
            memory.observe(&observed, id);
            let me = observed.players.iter().find(|p| p.id == id).unwrap();
            assert_eq!(
                memory.destination(me, &observed).is_some(),
                elapsed < profile.reaction_ticks
            );
        }
    }

    #[test]
    fn sight_refuses_walls_range_vertical_and_rear_targets() {
        let (snapshot, mut arena, id, _) = scene();
        let me = snapshot.players.iter().find(|p| p.id == id).unwrap();
        let profile = PROFILES[0];
        assert!(visible(me, [10.0, 1.0, 0.0], &arena, profile));
        for point in [[-10.0, 1.0, 0.0], [49.0, 1.0, 0.0], [1.0, 10.0, 0.0]] {
            assert!(!visible(me, point, &arena, profile));
        }
        arena.solids.push(Solid {
            min_x: 4.0,
            max_x: 5.0,
            min_z: -2.0,
            max_z: 2.0,
            bottom: 0.0,
            top: 4.0,
        });
        assert!(!visible(me, [10.0, 1.0, 0.0], &arena, profile));
    }

    #[test]
    fn constrained_actions_cannot_use_target_lock_or_snap_turns() {
        let (mut snapshot, arena, id, target) = scene();
        snapshot
            .players
            .iter_mut()
            .find(|p| p.id == target)
            .unwrap()
            .z = 10.0;
        let me = snapshot.players.iter().find(|p| p.id == id).unwrap();
        let action = Action {
            look_at: Some(LookAt {
                player_id: Some(target),
                ..Default::default()
            }),
            fire: true,
            ..Default::default()
        };
        let constrained = constrain(action, me, &snapshot, PROFILES[1], 42, &arena);
        assert!(constrained.look_at.is_none());
        assert!(!constrained.fire);
        assert!((constrained.yaw.unwrap() - 9_f32.to_radians()).abs() < 0.0001);
        assert!(constrained.pitch.unwrap().abs() <= 9_f32.to_radians());
        assert!(angle(-PI + 0.1 - (PI - 0.1)).abs() < 0.21);
    }

    #[test]
    fn timeout_is_reported_without_a_fake_completion() {
        let row = trial(42, PROFILES[0], CampaignDifficulty::Standard, 1).unwrap();
        assert_eq!(row.outcome, "timeout");
        assert_eq!(row.seconds, 0.05);
        assert_eq!(row.kills, 0);
        assert_eq!(row.last_phase, MissionPhase::FindTransfer);
    }

    #[test]
    fn ineffective_policy_fails_and_active_stall_is_not_hidden_by_motion() {
        let (row, _) = trial_with_actions(
            42,
            PROFILES[0],
            CampaignDifficulty::Assisted,
            400,
            Recording::None,
            |_| Action::default(),
        )
        .unwrap();
        assert_eq!(row.outcome, "timeout");
        assert_eq!(row.shots, 0);
        assert_eq!(row.reloads, 0);
        assert_eq!(row.continues_spent, 0);
        assert!(row.longest_no_progress_seconds >= 19.9);
        assert_eq!(row.last_phase, MissionPhase::FindTransfer);
    }

    #[test]
    fn m19_discovery_entry_does_not_give_an_ineffective_policy_equipment_or_progress() {
        let (row, _, _) = scenario_trial_with_actions(
            Scenario::M19Teaching,
            42,
            PROFILES[0],
            CampaignDifficulty::Assisted,
            400,
            Recording::None,
            |_| Action::default(),
        )
        .unwrap();
        assert_eq!(row.outcome, "timeout");
        assert_eq!(row.weapons, ["Fists"]);
        assert_eq!(row.bullets, 0);
        assert_eq!(row.shots, 0);
        assert!(row.longest_no_progress_seconds >= 19.9);
        let metrics = row.teaching.as_ref().unwrap();
        assert!(metrics.objectives.is_empty() && metrics.flights.is_empty());
        assert!(!Scenario::M19Teaching.accepts(&row));
    }

    #[test]
    fn m19_last_allowed_tick_keeps_earned_completion_and_landing_receipts() {
        let play = |ticks| {
            scenario_trial_with_actions(
                Scenario::M19Teaching,
                42,
                PROFILES[0],
                CampaignDifficulty::Assisted,
                ticks,
                Recording::None,
                |action| action,
            )
            .unwrap()
            .0
        };
        let clear = play(2_000);
        assert!(Scenario::M19Teaching.accepts(&clear));
        let (recorded, _, windows) = scenario_trial_with_actions(
            Scenario::M19Teaching,
            42,
            PROFILES[0],
            CampaignDifficulty::Assisted,
            2_000,
            Recording::Teaching,
            |action| action,
        )
        .unwrap();
        assert_eq!(
            recorded, clear,
            "recording must not influence ordinary actions or metrics"
        );
        assert!(!windows.is_empty());
        let final_tick = (clear.seconds * 20.0).round() as u64;
        let exact = play(final_tick);
        assert_eq!(exact, clear, "the last allowed action belongs to the trial");
        let before = play(final_tick - 1);
        assert_eq!(before.outcome, "timeout");
        let landing_tick = clear
            .teaching
            .as_ref()
            .unwrap()
            .flights
            .iter()
            .find(|flight| flight.gallery_landing)
            .unwrap()
            .ended_tick;
        let landed = play(landing_tick);
        assert!(landed
            .teaching
            .unwrap()
            .flights
            .iter()
            .any(|flight| flight.gallery_landing));
        assert!(!play(landing_tick - 1)
            .teaching
            .unwrap()
            .flights
            .iter()
            .any(|flight| flight.gallery_landing));
    }

    #[test]
    fn m19_crossing_search_does_not_stop_with_a_living_guard_out_of_view() {
        // Earned standalone run. Seed 43 previously stopped at the public
        // crossing arrival for over 500 seconds with 40 bullets still held.
        let (row, _, _) = scenario_trial_with_actions(
            Scenario::M19Teaching,
            43,
            PROFILES[1],
            CampaignDifficulty::Assisted,
            2_400,
            Recording::None,
            |action| action,
        )
        .unwrap();
        assert!(row.longest_no_progress_seconds < 30.0, "{row:?}");
        assert_ne!(row.outcome, "timeout");
    }

    #[test]
    fn m19_market_keeps_the_earned_teaching_prefix_and_stops_at_the_declared_tick() {
        // Seed 42 reference/Standard earns the teaching segment without a
        // death, so its market entry is in its first attempt. (Reference/
        // Assisted dies once there since Union guards began needing a
        // sighting, wave 12.)
        let mut prefix = Vec::new();
        let (teaching, _, _) = scenario_trial_with_actions(
            Scenario::M19Teaching,
            42,
            PROFILES[0],
            CampaignDifficulty::Standard,
            2_000,
            Recording::None,
            |action| {
                prefix.push(serde_json::to_value(&action).unwrap());
                action
            },
        )
        .unwrap();
        assert!(Scenario::M19Teaching.accepts(&teaching));
        let boundary = (teaching.seconds * 20.0).round() as u64;
        let mut extended = Vec::new();
        let (market, _, _) = scenario_trial_with_actions(
            Scenario::M19Market,
            42,
            PROFILES[0],
            CampaignDifficulty::Standard,
            boundary + 1,
            Recording::None,
            |action| {
                extended.push(serde_json::to_value(&action).unwrap());
                action
            },
        )
        .unwrap();
        assert_eq!(&extended[..prefix.len()], prefix);
        assert_eq!(extended.len(), prefix.len() + 1);
        assert_eq!(market.seconds, (boundary + 1) as f64 / 20.0);
        assert_eq!(
            market.outcome, "timeout",
            "tram completion is not market completion"
        );
        assert!(!Scenario::M19Market.accepts(&market));
        let attempt = &market.market.as_ref().unwrap().attempts[0];
        assert!(attempt.entered_market);
        let entry = attempt
            .receipts
            .iter()
            .find(|r| r.event == market::Event::MarketEntry)
            .unwrap();
        assert_eq!(entry.tick, boundary);
        assert_eq!(entry.current_objective.as_deref(), Some("market_strips"));
        let earned = entry.status.as_ref().unwrap();
        assert_eq!(earned.hp, teaching.hp);
        assert_eq!(earned.loadout.ammo(AmmoPool::Bullets), teaching.bullets);
        assert_eq!(
            earned
                .loadout
                .weapons
                .iter()
                .map(|w| w.name())
                .collect::<Vec<_>>(),
            teaching.weapons
        );
        assert_eq!(attempt.receipts.last().unwrap().tick, boundary + 1);
        assert_eq!(
            attempt.receipts.last().unwrap().event,
            market::Event::Timeout
        );
        let exact = scenario_trial_with_actions(
            Scenario::M19Market,
            42,
            PROFILES[0],
            CampaignDifficulty::Standard,
            boundary,
            Recording::None,
            |action| action,
        )
        .unwrap()
        .0;
        let exact_entry = exact.market.unwrap().attempts[0]
            .receipts
            .iter()
            .find(|r| r.event == market::Event::MarketEntry)
            .cloned()
            .unwrap();
        assert_eq!(
            &exact_entry, entry,
            "last allowed action retains the new stage receipt"
        );
    }

    #[test]
    fn m19_market_observation_and_recording_never_change_actions_or_grant_supplies() {
        let play = |recording| {
            let mut actions = Vec::new();
            let result = scenario_trial_with_actions(
                Scenario::M19Market,
                42,
                PROFILES[0],
                CampaignDifficulty::Assisted,
                2_000,
                recording,
                |action| {
                    actions.push(serde_json::to_value(&action).unwrap());
                    action
                },
            )
            .unwrap();
            (result, actions)
        };
        let ((plain, _, _), actions) = play(Recording::None);
        let ((recorded, _, windows), recorded_actions) = play(Recording::Teaching);
        assert_eq!(actions, recorded_actions);
        assert_eq!(plain, recorded);
        assert!(!windows.is_empty());
        let (bad, _, _) = scenario_trial_with_actions(
            Scenario::M19Market,
            42,
            PROFILES[0],
            CampaignDifficulty::Assisted,
            400,
            Recording::None,
            |_| Action::default(),
        )
        .unwrap();
        assert_eq!(bad.outcome, "timeout");
        assert_eq!(bad.shots, 0);
        assert_eq!(bad.weapons, ["Fists"]);
        assert_eq!(bad.bullets, 0);
        let attempt = &bad.market.as_ref().unwrap().attempts[0];
        assert!(!attempt.entered_market);
        assert_eq!(attempt.outcome, market::Outcome::Timeout);
        assert_eq!(attempt.receipts.len(), 2);
        let entry = attempt.receipts[0].status.as_ref().unwrap();
        let terminal = attempt.receipts[1].status.as_ref().unwrap();
        assert_eq!(entry.loadout.weapons, terminal.loadout.weapons);
        assert_eq!(entry.loadout.ammo, terminal.loadout.ammo);
        assert!(terminal.loadout.personal_claims.is_empty());
        assert!(!Scenario::M19Market.accepts(&bad));
    }

    #[test]
    fn m19_market_earned_completion_keeps_the_final_action_and_stops_before_water_tanks() {
        // Baseline 6b8061b7: ordinary seed42 hesitant/Assisted completes at
        // tick2017 with no retry. No setup kit, position or progress edits.
        let play = |ticks| {
            let mut actions = 0_u64;
            let (row, _, _) = scenario_trial_with_actions(
                Scenario::M19Market,
                42,
                PROFILES[2],
                CampaignDifficulty::Assisted,
                ticks,
                Recording::None,
                |action| {
                    actions += 1;
                    action
                },
            )
            .unwrap();
            (row, actions)
        };
        let (clear, actions) = play(2_400);
        assert!(Scenario::M19Market.accepts(&clear), "{clear:?}");
        assert_eq!(clear.final_attempt, 1);
        let final_tick = (clear.seconds * 20.0).round() as u64;
        assert_eq!(
            actions, final_tick,
            "no extra action may follow market completion"
        );
        let terminal = clear.market.as_ref().unwrap().attempts[0]
            .receipts
            .last()
            .unwrap();
        assert_eq!(terminal.event, market::Event::MarketComplete);
        assert_eq!(terminal.tick, final_tick);
        assert_eq!(terminal.current_objective.as_deref(), Some("water_tanks"));
        assert!(!clear
            .teaching
            .as_ref()
            .unwrap()
            .objectives
            .iter()
            .any(|receipt| receipt.objective == "water_tanks"));
        let (exact, exact_actions) = play(final_tick);
        assert_eq!(
            exact, clear,
            "completion on the last allowed tick belongs to this trial"
        );
        assert_eq!(exact_actions, actions);
        let (before, before_actions) = play(final_tick - 1);
        assert_eq!(before.outcome, "timeout");
        assert_eq!(before_actions, final_tick - 1);
        assert!(!Scenario::M19Market.accepts(&before));
        let before_terminal = before.market.as_ref().unwrap().attempts[0]
            .receipts
            .last()
            .unwrap();
        assert_eq!(before_terminal.event, market::Event::Timeout);
        assert_eq!(
            before_terminal.current_objective.as_deref(),
            Some("market_strips")
        );
        assert!(!before.market.as_ref().unwrap().attempts[0]
            .receipts
            .iter()
            .any(|receipt| receipt.event == market::Event::MarketComplete));
    }

    #[test]
    fn m19_tanks_continues_the_identical_market_prefix_to_the_next_objective_only() {
        // Wave 11 cohort: ordinary seed42 hesitant/Assisted completes the
        // market and then the water tanks with no retry. No kit, position,
        // save or objective edits.
        let play = |scenario, ticks, idle_after: Option<u64>| {
            let mut actions = 0_u64;
            let (row, _, _) = scenario_trial_with_actions(
                scenario,
                42,
                PROFILES[2],
                CampaignDifficulty::Assisted,
                ticks,
                Recording::None,
                |action| {
                    actions += 1;
                    if idle_after.is_some_and(|tick| actions > tick) {
                        Action::default()
                    } else {
                        action
                    }
                },
            )
            .unwrap();
            (row, actions)
        };
        let (market, _) = play(Scenario::M19Market, 2_400, None);
        let market_terminal = market.market.as_ref().unwrap().attempts[0]
            .receipts
            .last()
            .unwrap()
            .clone();
        assert_eq!(market_terminal.event, market::Event::MarketComplete);
        let (clear, actions) = play(Scenario::M19Tanks, 2_800, None);
        assert!(Scenario::M19Tanks.accepts(&clear), "{clear:?}");
        assert_eq!(clear.final_attempt, 1);
        let final_tick = (clear.seconds * 20.0).round() as u64;
        assert_eq!(actions, final_tick, "no action follows the tanks arrival");
        let attempt = &clear.market.as_ref().unwrap().attempts[0];
        assert_eq!(attempt.outcome, market::Outcome::Complete);
        assert_eq!(
            attempt.receipts.iter().map(|r| r.event).collect::<Vec<_>>(),
            [
                market::Event::Entry,
                market::Event::MarketEntry,
                market::Event::MarketComplete,
                market::Event::TanksComplete
            ]
        );
        // The earned prefix through the market boundary is byte-identical.
        assert_eq!(attempt.receipts[2], market_terminal);
        let arrival = &attempt.receipts[3];
        assert_eq!(arrival.tick, final_tick);
        assert_eq!(arrival.current_objective.as_deref(), Some("roof_loop"));
        assert_eq!(arrival.continues, market_terminal.continues);
        let status = arrival.status.as_ref().unwrap();
        assert!(status.hp > 0 && status.feet[1] > 5.0, "{status:?}");
        let continuation = attempt.continuation.as_ref().unwrap();
        assert!(continuation.decision_steps > 0);
        assert_eq!(continuation.strip_loss, 0);
        assert!(attempt.stage.as_ref().unwrap().decision_steps > 0);
        // A controller that stops after the market cannot reach the tanks:
        // the trial times out on water_tanks and is not a clear.
        let market_tick = market_terminal.tick;
        let (idle, _) = play(Scenario::M19Tanks, market_tick + 400, Some(market_tick));
        assert_eq!(idle.outcome, "timeout");
        assert!(!Scenario::M19Tanks.accepts(&idle));
        let idle_attempt = &idle.market.as_ref().unwrap().attempts[0];
        assert_eq!(idle_attempt.receipts[2], market_terminal);
        let last = idle_attempt.receipts.last().unwrap();
        assert_eq!(last.event, market::Event::Timeout);
        assert_eq!(last.current_objective.as_deref(), Some("water_tanks"));
    }

    #[test]
    fn reload_commands_preserve_finite_supply_in_an_isolated_inventory_fixture() {
        use fragr_server::protocol::{EquipmentPolicy, WeaponType};
        // Calibration of the reload seam only; no campaign result is claimed.
        let mut inventory = fragr_server::inventory::Inventory::new(EquipmentPolicy::Discovery);
        inventory.grant_weapon(WeaponType::Tack);
        inventory.arm_magazines();
        let id = Uuid::from_u128(1);
        let initial = inventory.state(id, WeaponType::Tack, 0).unwrap();
        let mut fired = 0;
        let mut reloads = 0;
        let mut held = false;
        for tick in 0..500 {
            inventory.finish_reload(tick);
            let gear = inventory.state(id, WeaponType::Tack, tick).unwrap();
            let reload = reload_requested(&gear, held);
            if reload {
                assert_eq!(gear.shots(WeaponType::Tack), Some(0));
                assert!(inventory.request_reload(WeaponType::Tack, tick));
                reloads += 1;
            }
            held = reload;
            fired += u16::from(inventory.try_fire(WeaponType::Tack));
            let remaining = inventory
                .state(id, WeaponType::Tack, tick)
                .unwrap()
                .ammo(AmmoPool::Bullets);
            assert_eq!(fired + remaining, initial.ammo(AmmoPool::Bullets));
        }
        assert_eq!(fired, initial.ammo(AmmoPool::Bullets));
        assert!(reloads > 0 && fired > initial.shots(WeaponType::Tack).unwrap());
        assert!(!inventory.try_fire(WeaponType::Tack));
    }

    #[test]
    fn weapon_selection_cannot_cancel_an_empty_magazine_reload() {
        use fragr_server::protocol::{EquipmentPolicy, WeaponType};
        let (snapshot, _, id, _) = scene();
        // Isolated owned-gun fixture, distinct from earned campaign trials.
        let mut inventory = fragr_server::inventory::Inventory::new(EquipmentPolicy::Discovery);
        inventory.grant_weapon(WeaponType::Tack);
        inventory.arm_magazines();
        for _ in 0..12 {
            assert!(inventory.try_fire(WeaponType::Tack));
        }
        let gear = inventory.state(id, WeaponType::Tack, 0).unwrap();
        let wanted = control_action_with_target_filter(
            id,
            &snapshot,
            Some(&gear),
            Action::default(),
            true,
            |_, _| true,
        );
        let action = apply_reload(wanted, &gear, false);
        assert!(action.reload);
        assert_ne!(
            action.weapon_swap,
            Some(WeaponType::Fists),
            "reload must keep the empty gun selected"
        );
        assert!(inventory.request_reload(WeaponType::Tack, 1));
        let gear = inventory.state(id, WeaponType::Tack, 2).unwrap();
        let wanted = control_action_with_target_filter(
            id,
            &snapshot,
            Some(&gear),
            Action::default(),
            true,
            |_, _| true,
        );
        let action = apply_reload(wanted, &gear, true);
        assert_eq!(action.weapon_swap, None);
        assert!(!action.reload && !action.fire);
        inventory.finish_reload(30);
        assert!(inventory.try_fire(WeaponType::Tack));
    }

    #[test]
    fn formerly_stranded_fighter_reloads_and_finishes_with_earned_ammunition() {
        let row = trial(42, PROFILES[1], CampaignDifficulty::Assisted, 12_000).unwrap();
        assert_eq!(row.outcome, "departed");
        assert!(row.reloads > 0 && row.deaths > 0);
        assert!(row.longest_no_progress_seconds < 30.0);
    }

    #[test]
    fn calibrated_policy_accepts_m02_entry_and_initial_ordinary_actions() {
        // Standalone M02 discovery kit and a twenty-second initial window.
        // This is policy/input transfer, not earned carry, a mission clear or
        // a fresh-player acceptance trial. The server owns its ordinary kit.
        let mut session = GameSession::with_authored_map(
            AuthoredSource::Mission(MissionId::PersonsUnknown)
                .load()
                .unwrap(),
        );
        session.state.use_replay_ids();
        session.state.seed(47);
        session
            .state
            .set_campaign_difficulty(CampaignDifficulty::Assisted)
            .unwrap();
        let id = Uuid::from_u128(479);
        session
            .state
            .add_player(id, "Initial transfer fixture".into(), Role::Human);
        session.state.arm_joined_magazines(id);
        let mut client = MissionClient::default();
        configure_map(&mut client, &session.state.map_info()).unwrap();
        assert!(session.state.acknowledge_mission(
            id,
            MissionReady {
                id: MissionId::PersonsUnknown,
                attempt: 1,
            }
        ));
        let initial = session.state.snapshot();
        let initial_me = initial.players.iter().find(|p| p.id == id).unwrap();
        let start = [initial_me.x, initial_me.z];
        let profile = PROFILES[1];
        let mut perception = Perception::default();
        let mut navigator = Navigator::default();
        let mut reload_down = false;
        let mut actions = 0;
        let mut shots = 0;
        let mut reloads = 0;
        let mut distance = 0.0_f32;
        for _ in 0..400 {
            let snapshot = session.state.snapshot();
            let Some(me) = snapshot.players.iter().find(|p| p.id == id && p.hp > 0) else {
                break; // A death remains a valid bounded observation.
            };
            let state = session.state.mission_state().unwrap();
            client.observe(snapshot.tick, state).unwrap();
            let player = session.state.players.iter().find(|p| p.id == id).unwrap();
            let gear = player
                .inventory
                .state(id, player.weapon, snapshot.tick)
                .unwrap();
            assert!(
                player.inventory.armed(),
                "ordinary human magazines are active"
            );
            let arena = session.state.map.arena();
            let observed = perception.observe(&snapshot, id, arena, profile);
            let wanted = control_action_with_target_filter(
                id,
                &observed,
                Some(&gear),
                Action::default(),
                true,
                |_, _| true,
            );
            // Use only the same public mission geometry and existing
            // navigation owner as M01; add no M02 waypoints or route hints.
            let wanted = client.steer_with_equipment(
                &mut navigator,
                session.state.map.navigation(),
                id,
                &observed,
                wanted,
                Some(&gear),
            );
            let action = constrain(
                apply_reload(wanted, &gear, reload_down),
                me,
                &observed,
                profile,
                47,
                arena,
            );
            assert!(action.look_at.is_none());
            let turn = profile.turn_degrees_per_second.to_radians() * DT + 0.0001;
            assert!(angle(action.yaw.unwrap() - me.yaw).abs() <= turn);
            assert!((action.pitch.unwrap() - me.pitch).abs() <= turn);
            if action.reload {
                assert_eq!(gear.shots(gear.selected), Some(0));
                assert!(reserve_rounds(&gear) > 0);
            }
            reload_down = action.reload;
            reloads += usize::from(action.reload);
            actions += 1;
            distance = distance.max((me.x - start[0]).hypot(me.z - start[1]));
            session.state.set_action(id, action);
            for message in session.tick_messages(DT) {
                configure_map(&mut client, &message).unwrap();
            }
            shots += session
                .state
                .shot_results
                .iter()
                .filter(|shot| shot.shooter_id == id)
                .count();
        }
        assert!(
            actions > 0 && distance > 1.0,
            "the policy must move the real body"
        );
        assert!(
            shots > 0 && reloads > 0,
            "the initial encounter must exercise real attacks and reload input"
        );
        eprintln!("M02 initial policy transfer: seed=47 profile={} actions={actions} shots={shots} reloads={reloads} max_distance={distance:.2}m; standalone kit, no completion claim", profile.name);
    }

    #[test]
    fn a_peeking_head_is_seen_and_aimed_at_without_firing_into_the_counter() {
        let (snapshot, mut arena, id, target) = scene();
        arena
            .solids
            .push(Solid::from_center_top(5.0, 0.0, 0.5, 2.0, 1.4));
        let me = snapshot.players.iter().find(|p| p.id == id).unwrap();
        let enemy = snapshot.players.iter().find(|p| p.id == target).unwrap();
        assert!(!visible(me, chest(enemy), &arena, PROFILES[0]));
        assert!(visible_aim(me, enemy, &arena, PROFILES[0]).is_some());
        let mut perception = Perception::default();
        assert!(perception
            .observe(&snapshot, id, &arena, PROFILES[0])
            .players
            .iter()
            .any(|p| p.id == target));
        let action = constrain(
            Action {
                look_at: Some(LookAt {
                    player_id: Some(target),
                    ..Default::default()
                }),
                fire: true,
                ..Default::default()
            },
            me,
            &snapshot,
            PROFILES[0],
            42,
            &arena,
        );
        assert!(action.fire);
        assert!(action.pitch.unwrap().abs() < 0.001);
        arena.solids[0].top = 2.0;
        assert!(visible_aim(me, enemy, &arena, PROFILES[0]).is_none());
    }

    #[test]
    fn bounded_turning_preserves_navigation_world_direction() {
        let (snapshot, arena, id, _) = scene();
        let me = snapshot.players.iter().find(|p| p.id == id).unwrap();
        let action = constrain(
            Action {
                forward: true,
                yaw: Some(PI * 0.5),
                look_at: Some(LookAt {
                    x: Some(10.0),
                    y: Some(EYE_HEIGHT),
                    z: Some(0.0),
                    player_id: None,
                }),
                ..Default::default()
            },
            me,
            &snapshot,
            PROFILES[1],
            42,
            &arena,
        );
        let motion = fragr_server::movement::wish_dir(
            &fragr_server::movement::MoveInput {
                forward: action.forward,
                back: action.back,
                left: action.left,
                right: action.right,
                ..Default::default()
            },
            action.yaw.unwrap(),
        );
        assert!(
            motion.0.abs() < 0.001 && motion.1 > 0.99,
            "waypoint motion must survive a different facing: {motion:?}"
        );
        assert!(action.look_at.is_none());
    }

    #[test]
    fn invalid_or_empty_trials_never_report_success() {
        assert!(run(4..4, 20).is_err());
        assert!(run(0..65, 20).is_err());
        for ticks in [0, 36_001] {
            assert!(trial(42, PROFILES[0], CampaignDifficulty::Standard, ticks).is_err());
        }
        for profile in [
            Profile {
                view_degrees: f32::NAN,
                ..PROFILES[0]
            },
            Profile {
                aim_error_degrees: -1.0,
                ..PROFILES[0]
            },
            Profile {
                turn_degrees_per_second: f32::INFINITY,
                ..PROFILES[0]
            },
            Profile {
                reaction_ticks: 41,
                ..PROFILES[0]
            },
        ] {
            assert!(trial(42, profile, CampaignDifficulty::Standard, 20).is_err());
        }
    }

    #[test]
    fn real_completion_and_exhaustion_are_deterministic_and_keep_failed_attempts() {
        let (clear, first_kill) = trial_recorded(
            47,
            PROFILES[0],
            CampaignDifficulty::Assisted,
            12_000,
            Recording::FirstKill,
        )
        .unwrap();
        assert_eq!(clear.outcome, "departed");
        assert_eq!(first_kill.unwrap()["event"], "first_kill");
        assert!(clear.shots > 20 && clear.reloads > 0);
        assert_eq!(
            clear,
            trial(47, PROFILES[0], CampaignDifficulty::Assisted, 12_000).unwrap()
        );
        let (failed, review) = trial_recorded(
            47,
            PROFILES[2],
            CampaignDifficulty::Severe,
            12_000,
            Recording::Fatal,
        )
        .unwrap();
        assert_eq!(failed.outcome, "exhausted");
        assert_eq!(failed.deaths, 4);
        assert_eq!(failed.continues_spent, 3);
        assert_eq!(
            failed,
            trial(47, PROFILES[2], CampaignDifficulty::Severe, 12_000).unwrap(),
            "recorded authoritative facts must not affect controller decisions"
        );
        assert!(failed.hits_received.iter().any(|hit| hit.attempt == 4));
        assert!(failed.damage_received >= 400);
        assert_eq!(failed.hits_omitted, 0);
        let review = review.unwrap();
        assert_eq!(review["attempt"], 4);
        assert_eq!(review["seed"], 47);
        let frames: Vec<Snapshot> = serde_json::from_value(review["frames"].clone()).unwrap();
        assert_eq!(frames.len(), 80);
        assert!(frames
            .windows(2)
            .all(|pair| pair[0].tick + 1 == pair[1].tick));
        let before: Snapshot = serde_json::from_value(review["snapshot"].clone()).unwrap();
        let viewer: PlayerState = serde_json::from_value(review["view"].clone()).unwrap();
        assert!(viewer.hp > 0, "review must precede the fatal shot");
        let in_snapshot = before.players.iter().find(|p| p.id == viewer.id).unwrap();
        assert_eq!(
            serde_json::to_value(in_snapshot).unwrap(),
            serde_json::to_value(viewer).unwrap()
        );
        assert_eq!(before.tick + 1, failed.hits_received.last().unwrap().tick);
        assert_eq!(
            failed,
            serde_json::from_str(&serde_json::to_string(&failed).unwrap()).unwrap()
        );
    }
}
