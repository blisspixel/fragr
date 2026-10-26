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
    pub trials: Vec<Trial>,
    /// Last fatal-hit pre-frame of the first deliberate/Standard trial.
    /// Authoritative scene data for inspection, never controller input.
    pub review: Option<serde_json::Value>,
    /// First kill of the first reference/Assisted trial, even if it later fails.
    pub first_kill_review: Option<serde_json::Value>,
}

#[derive(Clone, Copy, PartialEq)]
enum Recording {
    None,
    Fatal,
    FirstKill,
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
                .any(|p| p.id == *id && p.hp > 0 && visible_aim(me, p, arena, profile).is_some())
        });
        observed.players.retain(|p| {
            if !me.is_hostile_to(p) {
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
                None,
                false,
                mission.as_ref(),
                *half_extent,
                solids,
                presentation.as_ref(),
            )
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
    mut actions: impl FnMut(Action) -> Action,
) -> Result<(Trial, Option<serde_json::Value>), String> {
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
    let mut session = GameSession::with_authored_map(
        AuthoredSource::Mission(MissionId::RecallNotice)
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
    let id = Uuid::from_u128(479);
    session.state.add_player(id, "Visitor".into(), Role::Human);
    session.state.arm_joined_magazines(id);
    session.state.acknowledge_mission(
        id,
        MissionReady {
            id: MissionId::RecallNotice,
            attempt: 1,
        },
    );
    let mut client = MissionClient::default();
    configure_map(&mut client, &session.state.map_info())?;
    let mut navigator = Navigator::default();
    let mut perception = Perception::default();
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
    while session.state.tick < max_ticks {
        let snapshot = session.state.snapshot();
        if recording != Recording::None {
            frames.push_back(snapshot.clone());
            if frames.len() > 80 {
                frames.pop_front();
            }
        }
        let state = session.state.mission_state().ok_or("mission vanished")?;
        if state.phase != report.last_phase {
            progress = snapshot.tick;
            report.last_phase = state.phase;
        }
        if state.phase == MissionPhase::Departed {
            report.outcome = "departed".into();
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
            report.continues_spent += 1;
            navigator.clear();
            perception = Perception::default();
            frames.clear();
            heard = None;
            evade = None;
            scan_remaining = 0.0;
            reload_down = false;
            visited.clear();
            last_supply = 0;
            progress = snapshot.tick;
            configure_map(&mut client, &session.state.map_info())?;
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
        let mut action = client.steer_with_equipment(
            &mut navigator,
            session.state.map.navigation(),
            id,
            &observed,
            wanted,
            Some(&gear),
        );
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
        // A cleared target is not proof the room is clear. Inspect the room
        // before following the next objective, using the same turn limit.
        if scan_remaining > 0.0 && !wanted_is_combat(&action) && heard.is_none() && evade.is_none()
        {
            let step = (profile.turn_degrees_per_second.to_radians() * DT).min(scan_remaining);
            scan_remaining -= step;
            action = Action {
                yaw: Some(me.yaw + step),
                pitch: Some(0.0),
                ..Default::default()
            };
        }
        action.reload = reload_requested(&gear, reload_down);
        action = actions(constrain(action, me, &observed, profile, seed, arena));
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
        let visible_shooters: Vec<Uuid> = snapshot
            .players
            .iter()
            .filter(|p| visible_aim(me, p, arena, profile).is_some())
            .map(|p| p.id)
            .collect();
        session.state.set_action(id, action);
        let messages = session.tick_messages(DT);
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
        report.last_phase = state.phase;
        if state.phase == MissionPhase::Departed {
            report.outcome = "departed".into();
        } else if state
            .run
            .is_some_and(|run| run.status == CampaignRunStatus::Failed)
        {
            report.outcome = "exhausted".into();
        }
    }
    Ok((report, review))
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
        && gear.ammo(AmmoPool::Bullets) > 0
}

pub fn run(seeds: std::ops::Range<u64>, max_ticks: u64) -> Result<Report, String> {
    if seeds.is_empty() || seeds.end - seeds.start > 64 {
        return Err("campaign survey requires 1..=64 seeds".into());
    }
    let mut trials = Vec::new();
    let mut review = None;
    let mut first_kill_review = None;
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
                } else {
                    Recording::None
                };
                let (row, frame) = trial_recorded(seed, profile, difficulty, max_ticks, recording)?;
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
    Ok(Report { schema: 1, build: env!("FRAGR_CLI_VERSION"), commit: env!("FRAGR_BUILD_COMMIT"), observation: "Guided M01 route; known public objective and navigation geometry; constrained enemy/supply perception and ordinary human actions; immediate Continue acceptance with no simulated menu delay; no human-population calibration or rendered-readability claim.", profiles: PROFILES, decision_hz: 20, continuation_delay_seconds: 0, trials, review, first_kill_review })
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
