use super::*;
use crate::maps::AuthoredMap;
use crate::protocol::{Action, CampaignActor, ControlDomain, EnemyPhase, LookAt, Role, UseTarget};
use crate::session::GameSession;
use std::sync::{Arc, OnceLock};

const MAP: &str = include_str!("../../../maps/m20-local-exception.json");
const FIRST_PRESSURE_GROUP: usize = crate::maps::m20_authored::FIRST_PRESSURE_GROUP;

pub(super) fn map() -> Arc<AuthoredMap> {
    static MAP_CACHE: OnceLock<Arc<AuthoredMap>> = OnceLock::new();
    MAP_CACHE
        .get_or_init(|| AuthoredMap::read(MAP.as_bytes()).unwrap())
        .clone()
}

pub(super) fn session_with(difficulty: CampaignDifficulty, role: Role) -> (GameSession, Uuid) {
    session_run(difficulty, role, false)
}

pub(super) fn session_run(
    difficulty: CampaignDifficulty,
    role: Role,
    solo: bool,
) -> (GameSession, Uuid) {
    let mut s = GameSession::with_authored_map(map());
    s.state.use_replay_ids();
    s.state.set_campaign_difficulty(difficulty).unwrap();
    if solo {
        s.state.enable_campaign_run().unwrap();
    }
    s.state.seed(1020);
    let id = Uuid::from_u128(1020);
    s.state.add_player(id, "Pier operative".into(), role);
    if role == Role::Human {
        s.state.arm_joined_magazines(id);
    }
    assert!(s.state.acknowledge_mission(
        id,
        MissionReady {
            id: MissionId::LocalException,
            attempt: 1,
        }
    ));
    (s, id)
}

fn session() -> (GameSession, Uuid) {
    session_with(CampaignDifficulty::Standard, Role::Agent)
}

#[test]
fn pier_workshop_people_are_counted_once_after_evacuation() {
    let (mut s, _) = session_run(CampaignDifficulty::Standard, Role::Agent, true);
    let solo = s.state.mission.as_mut().unwrap().solo.as_mut().unwrap();
    let before = refuge_for(Some(solo));
    solo.carried_released_workers = vec!["splice".into()];
    assert_eq!(refuge_for(Some(solo)), before);
    solo.carried_evacuated_workers = vec!["splice".into()];
    assert_eq!(refuge_for(Some(solo)).persons, before.persons + 1);
    assert!(refuge_for(Some(solo)).splice);
    solo.carried_berth = Some(run_file::M09Outcome {
        released_crew: vec![
            "tern".into(),
            "berth_crew_a".into(),
            "berth_crew_b".into(),
            "splice".into(),
        ],
        aboard_at_departure: vec![],
    });
    assert_eq!(refuge_for(Some(solo)).persons, before.persons + 4);
}

#[test]
fn pier_population_counts_only_stadium_entrants_who_survived() {
    let (mut s, _) = session_run(CampaignDifficulty::Standard, Role::Agent, true);
    let solo = s.state.mission.as_mut().unwrap().solo.as_mut().unwrap();
    let before = refuge_for(Some(solo));
    solo.carried_stadium = Some(run_file::M15Outcome {
        pen_armed: true,
        blade_wave_won: true,
        entrants_preserved: false,
        broadcast_taken: true,
        armed_entrants: vec![4, 12, 44, 71],
        fallen_entrants: vec![12, 71],
    });
    assert_eq!(refuge_for(Some(solo)).persons, before.persons + 2);
    solo.carried_stadium.as_mut().unwrap().fallen_entrants = vec![4, 12, 44, 71];
    assert_eq!(refuge_for(Some(solo)), before);
    solo.carried_stadium
        .as_mut()
        .unwrap()
        .fallen_entrants
        .clear();
    assert_eq!(refuge_for(Some(solo)).persons, before.persons + 4);
}

/// One server tick, then the same strict reader every client uses.
pub(super) fn tick(s: &mut GameSession) {
    s.tick_messages(0.05);
    let map = &s.state.map;
    crate::protocol::validate_decorations(
        &map.presentation_ref().unwrap().decorations,
        &map.arena().solids,
    )
    .unwrap();
    let mut reader = MissionClient::default();
    reader
        .replace_map_with_id(
            map.id(),
            None,
            false,
            None,
            map.half_extent(),
            &map.arena().solids,
            map.presentation_ref(),
        )
        .unwrap();
    reader
        .replace_map_with_m20(
            map.m20_geometry().as_ref(),
            map.half_extent(),
            &map.arena().solids,
            map.presentation_ref(),
        )
        .unwrap();
    let state = s.state.mission_state().unwrap();
    reader.observe(s.state.tick, state.clone()).unwrap();
    let g = map.m20_geometry().unwrap();
    let clock = state
        .m20
        .as_ref()
        .and_then(|f| f.pier_reached_at)
        .map(|at| g.clock(at));
    state.validate_with_clock(clock, s.state.tick).unwrap();
}

pub(super) fn place(s: &mut GameSession, id: Uuid, feet: [f32; 3]) {
    let p = s.state.players.iter_mut().find(|p| p.id == id).unwrap();
    [p.x, p.y, p.z] = [feet[0], feet[1] + PLAYER_FLOOR_Y, feet[2]];
    p.vy = 0.0;
    p.clear_input();
}

fn interact(s: &mut GameSession, id: Uuid, target: &UseTarget) {
    let point = target
        .point(
            s.state.map.presentation_ref().unwrap(),
            &s.state.map.arena().solids,
        )
        .unwrap();
    place(s, id, target.approach);
    s.state.set_action(
        id,
        Action {
            interact: true,
            look_at: Some(LookAt {
                x: Some(point[0]),
                y: Some(point[1]),
                z: Some(point[2]),
                player_id: None,
            }),
            ..Default::default()
        },
    );
    tick(s);
}

pub(super) fn clear_enemies(s: &mut GameSession) {
    for i in 0..s.state.players.len() {
        let p = &s.state.players[i];
        if p.is_campaign_enemy() && p.hp > 0 {
            let damage = p.hp + p.armor;
            s.state.environmental_self_damage(i, damage);
        }
    }
}

fn facts(s: &GameSession) -> M20ObjectiveState {
    s.state.mission_state().unwrap().m20.unwrap()
}

fn feet_of(objective: &crate::protocol::MissionObjective) -> [f32; 3] {
    match objective.action {
        MissionObjectiveAction::Arrival { feet, .. } => feet,
        _ => panic!("arrival expected"),
    }
}

/// Clear the two lessons and walk onto the quay, returning the arrival tick.
pub(super) fn reach_quay(s: &mut GameSession, id: Uuid) -> u64 {
    let g = s.state.map.m20_geometry().unwrap();
    tick(s);
    place(s, id, [-45.0, 1.2, 0.0]);
    tick(s);
    clear_enemies(s);
    place(s, id, feet_of(&g.objectives[0]));
    tick(s);
    tick(s);
    assert_eq!(facts(s).completed, vec!["sluice_crossing"]);
    place(s, id, feet_of(&g.objectives[1]));
    tick(s);
    clear_enemies(s);
    tick(s);
    tick(s);
    assert_eq!(facts(s).completed.len(), 2);
    place(s, id, feet_of(&g.objectives[2]));
    tick(s);
    let reached = facts(s).pier_reached_at.expect("quay reached");
    assert_eq!(facts(s).completed.len(), 3);
    reached
}

#[test]
fn canonical_waterworks_loads_with_ordered_lessons_and_pressure() {
    let map = map();
    let runtime = crate::maps::RuntimeMap::Authored(map.clone());
    assert_eq!(runtime.id(), 1020);
    assert_eq!(runtime.name(), "Local Exception");
    assert_eq!(
        runtime.campaign_mission_id(),
        Some(MissionId::LocalException)
    );
    let prepared = runtime.m20_objectives().unwrap();
    assert_eq!(prepared.crew.len(), M20_CREW);
    assert!(prepared.pressure.len() >= 12, "a long hold needs pressure");
    assert!(prepared
        .pressure
        .windows(2)
        .all(|pair| pair[0].at <= pair[1].at));
    let encounters = runtime.encounters();
    assert_eq!(encounters[SLUICE_GROUP].id, "sluice_watch");
    assert_eq!(
        encounters[SLUICE_GROUP]
            .enemies
            .iter()
            .filter(|e| e.kind == EnemyKind::Surveyor)
            .count(),
        1,
        "the first Surveyor works alone"
    );
    assert_eq!(
        encounters[SLUICE_GROUP].enemies.len(),
        1,
        "nothing stands with the Surveyor through its lesson window"
    );
    assert_eq!(encounters[FOLLOW_GROUP].id, "sluice_follow");
    assert!(encounters[FOLLOW_GROUP]
        .enemies
        .iter()
        .all(|e| e.kind != EnemyKind::Surveyor));
    // The wipe's finale fields the Inheritance itself: restoration Surveyors
    // and Pavers, and absorbed bots. Nothing here still answers the Union.
    let all: Vec<_> = encounters.iter().flat_map(|g| &g.enemies).collect();
    assert!(all.iter().all(|e| match e.kind {
        EnemyKind::Surveyor | EnemyKind::Paver => e.control == ControlDomain::Restoration,
        _ => e.control == ControlDomain::Absorbed,
    }));
    assert!(
        encounters[CROSSING_GROUP]
            .enemies
            .iter()
            .any(|e| e.kind == EnemyKind::Paver),
        "a Paver stripes the service road"
    );
    assert!(
        encounters
            .iter()
            .filter(|g| g.id.starts_with("freight_"))
            .any(|g| g.enemies.iter().any(|e| e.kind == EnemyKind::Paver)),
        "Pavers stripe the freight yard"
    );
    assert!(
        encounters
            .iter()
            .filter(|g| g.enemies.iter().any(|e| e.kind == EnemyKind::Surveyor))
            .count()
            >= 3,
        "Surveyors mark the set piece too"
    );
    let shut = runtime.m20_geometry().unwrap();
    assert!(!shut.gate_open);
    let opened = runtime.prepared_m20_world(1).unwrap();
    assert!(opened.m20_geometry().unwrap().gate_open);
    assert_eq!(opened.m20_stage(), 1);
    assert!(runtime.prepared_m20_world(2).is_none());
    assert!(runtime.requires_surveyor_contract());
    assert_eq!(
        MissionId::LocalException.gameplay_version(),
        crate::protocol::M20_GAMEPLAY_VERSION
    );
    // The gate is the one door: shut, the crossing control is unreachable.
    let route = runtime
        .navigation()
        .route(
            [-59.0, 1.2, 0.0],
            shut.departure.approach,
            crate::navigation::SEARCH_LIMIT,
        )
        .status;
    assert_ne!(route, crate::navigation::RouteStatus::Complete);
}

#[test]
fn the_surveyor_teaches_alone_until_its_first_disc_ends() {
    let (mut s, id) = session();
    tick(&mut s);
    let hostiles = |s: &GameSession| -> Vec<EnemyKind> {
        s.state
            .players
            .iter()
            .filter(|p| p.hp > 0)
            .filter_map(|p| match p.campaign {
                Some(CampaignActor::Hostile { kind, .. }) => Some(kind),
                _ => None,
            })
            .collect()
    };
    // Stand where the lens sees the catwalks and let it open on us.
    let mut cast = false;
    for _ in 0..400 {
        place(&mut s, id, [-45.0, 1.2, 4.0]);
        s.state.players.iter_mut().find(|p| p.id == id).unwrap().hp = 100;
        tick(&mut s);
        if !s.state.snapshot().surveyor_marks.is_empty() {
            cast = true;
            break;
        }
        assert_eq!(
            hostiles(&s),
            vec![EnemyKind::Surveyor],
            "the lens works alone"
        );
    }
    assert!(cast, "the lesson Surveyor casts its disc");
    // Through the first disc's whole life, nothing else is on the sluices.
    while !s.state.snapshot().surveyor_marks.is_empty() {
        assert_eq!(hostiles(&s), vec![EnemyKind::Surveyor]);
        place(&mut s, id, [-45.0, 1.2, 4.0]);
        s.state.players.iter_mut().find(|p| p.id == id).unwrap().hp = 100;
        tick(&mut s);
    }
    // Once that disc has ended, one machine follows it in.
    for _ in 0..4 {
        s.state.players.iter_mut().find(|p| p.id == id).unwrap().hp = 100;
        tick(&mut s);
    }
    let kinds = hostiles(&s);
    assert_eq!(
        kinds.iter().filter(|k| **k == EnemyKind::Sweeper).count(),
        1,
        "one absorbed Sweeper joins after the lesson window: {kinds:?}"
    );
    assert!(s.state.players.iter().any(|p| matches!(
        p.campaign,
        Some(CampaignActor::Hostile {
            kind: EnemyKind::Sweeper,
            control: ControlDomain::Absorbed,
            ..
        })
    ) && p.hp > 0));
}

#[test]
fn lifecycle_crosses_the_sluices_holds_the_pier_and_departs_through_the_gate() {
    let (mut s, id) = session();
    tick(&mut s);
    let f = facts(&s);
    assert!(f.completed.is_empty());
    assert_eq!(f.current.as_ref().unwrap().id, "sluice_crossing");
    assert_eq!(f.refuge_integrity, M20_REFUGE_INTEGRITY);
    assert!(f.challenges.refuge_held);
    assert_eq!(f.refuge, M20Refuge::alone());
    assert!(f.crew.iter().all(|c| c.phase == M20CrewPhase::Working));

    // The crossing does not complete while the Surveyor's group stands.
    let g = s.state.map.m20_geometry().unwrap();
    place(&mut s, id, [-45.0, 1.2, 0.0]);
    tick(&mut s);
    place(&mut s, id, feet_of(&g.objectives[0]));
    tick(&mut s);
    assert!(facts(&s).completed.is_empty(), "an uncleared lesson holds");

    let reached = {
        // Restart the walk with the lesson cleared.
        clear_enemies(&mut s);
        tick(&mut s);
        tick(&mut s);
        assert_eq!(facts(&s).completed, vec!["sluice_crossing"]);
        place(&mut s, id, feet_of(&g.objectives[1]));
        tick(&mut s);
        clear_enemies(&mut s);
        tick(&mut s);
        tick(&mut s);
        let f = facts(&s);
        assert_eq!(f.completed.len(), 2);
        assert!(f.crew.iter().all(|c| c.phase != M20CrewPhase::Working));
        place(&mut s, id, feet_of(&g.objectives[2]));
        tick(&mut s);
        facts(&s).pier_reached_at.unwrap()
    };
    let (start, turn, reprieve) = g.clock(reached);
    assert_eq!(start - reached, g.breath_ticks);
    assert_eq!(reprieve - turn, crate::protocol::M20_SIX_MINUTES);

    // The breath is quiet: no pressure group is placed before the clock.
    while s.state.tick < start - 1 {
        tick(&mut s);
        assert!(
            !s.state
                .players
                .iter()
                .any(|p| p.is_campaign_enemy() && p.hp > 0),
            "no pressure during the breath"
        );
    }
    // Skip the hold with the enemies cleared every second.
    while s.state.tick < turn {
        if s.state.tick.is_multiple_of(20) {
            clear_enemies(&mut s);
        }
        place(&mut s, id, feet_of(&g.objectives[3]));
        tick(&mut s);
    }
    let f = facts(&s);
    assert!(f.display_lit);
    assert_eq!(f.completed.len(), 4);
    assert_eq!(f.current.as_ref().unwrap().id, "last_six");
    while s.state.tick < reprieve {
        if s.state.tick.is_multiple_of(20) {
            clear_enemies(&mut s);
        }
        place(&mut s, id, feet_of(&g.objectives[4]));
        tick(&mut s);
    }
    let f = facts(&s);
    assert_eq!(f.reprieve_at, Some(reprieve));
    assert_eq!(f.completed.len(), 5);
    assert!(f.latch.is_some());
    assert!(!f.gate_open);
    assert_eq!(f.current.as_ref().unwrap().id, "party_departed");
    assert!(
        s.state.mission_state().unwrap().prompts.is_empty(),
        "no departure before the gate opens"
    );
    // Latch walks back; the gate opens on arrival or the bounded timeout.
    for _ in 0..(GATE_TIMEOUT + 2) {
        tick(&mut s);
        if facts(&s).gate_open {
            break;
        }
    }
    assert!(facts(&s).gate_open);
    assert_eq!(s.state.map.m20_stage(), 1);
    interact(&mut s, id, &g.departure);
    assert_eq!(
        s.state.mission.as_ref().unwrap().phase,
        MissionPhase::Departed
    );
    let f = facts(&s);
    assert_eq!(f.completed.len(), 6);
    assert!(f.current.is_none());
    // A second press after departure is inert.
    interact(&mut s, id, &g.departure);
    assert_eq!(facts(&s).completed.len(), 6);
}

#[test]
fn pressure_waits_for_its_hidden_schedule_and_the_population_cap() {
    for difficulty in [
        CampaignDifficulty::Assisted,
        CampaignDifficulty::Standard,
        CampaignDifficulty::Severe,
    ] {
        let (mut s, id) = session_with(difficulty, Role::Agent);
        let reached = reach_quay(&mut s, id);
        let g = s.state.map.m20_geometry().unwrap();
        let (start, _, _) = g.clock(reached);
        let hold = feet_of(&g.objectives[3]);
        let cap = population_cap(difficulty);
        let mut peak = 0;
        // Ninety seconds of hold with nobody fighting back: the director
        // fills to the cap and never past it.
        while s.state.tick < start + 1_800 {
            place(&mut s, id, hold);
            let p = s.state.players.iter_mut().find(|p| p.id == id).unwrap();
            p.hp = 100;
            tick(&mut s);
            let living = s
                .state
                .players
                .iter()
                .filter(|p| p.is_campaign_enemy() && p.hp > 0)
                .count();
            peak = peak.max(living);
            assert!(living <= cap, "{difficulty:?} exceeded its cap");
        }
        assert!(peak >= 2, "{difficulty:?} fielded no pressure");
        assert!(
            s.state
                .encounters
                .is_awake(s.state.map.m20_objectives().unwrap().pressure[0].group),
            "the first group is due at once"
        );
    }
}

#[test]
fn machines_on_the_refuge_line_wear_the_barricade_and_break_the_severe_brief() {
    let (mut s, id) = session_with(CampaignDifficulty::Severe, Role::Agent);
    let reached = reach_quay(&mut s, id);
    let g = s.state.map.m20_geometry().unwrap();
    let (start, _, _) = g.clock(reached);
    while s.state.tick < start + 2 {
        tick(&mut s);
    }
    // Stand a pressure machine on the line and let it work.
    let line = g.refuge_line.clone();
    let machine = s
        .state
        .players
        .iter()
        .position(|p| {
            p.is_campaign_enemy()
                && p.hp > 0
                && matches!(p.campaign, Some(CampaignActor::Hostile { kind, .. }) if kind == EnemyKind::Sweeper)
        })
        .expect("first pressure group placed");
    let worker_id = s.state.players[machine].id;
    let before = facts(&s).refuge_integrity;
    // Keep the participant far away so nothing kills the worker.
    place(&mut s, id, [-20.0, 0.0, 0.0]);
    for _ in 0..120 {
        let p = s
            .state
            .players
            .iter_mut()
            .find(|p| p.id == worker_id)
            .unwrap();
        [p.x, p.y, p.z] = [52.5, PLAYER_FLOOR_Y, -9.0];
        assert!(line.contains([p.x, p.y - PLAYER_FLOOR_Y, p.z]));
        tick(&mut s);
    }
    let after = facts(&s).refuge_integrity;
    assert!(after < before, "a machine on the line wears it");
    // Run it to the ground: the Severe brief and the held fact both fall.
    for _ in 0..4_000 {
        if facts(&s).refuge_integrity == 0 {
            break;
        }
        if let Some(p) = s.state.players.iter_mut().find(|p| p.id == worker_id) {
            [p.x, p.y, p.z] = [52.5, PLAYER_FLOOR_Y, -9.0];
            p.hp = 80;
        }
        tick(&mut s);
    }
    let f = facts(&s);
    assert_eq!(f.refuge_integrity, 0);
    assert!(!f.challenges.refuge_held);
    assert!(!f.brief_completed);
}

#[test]
fn crates_hold_their_supplies_until_the_people_bring_them_up() {
    let (mut s, id) = session();
    let crates = s.state.map.m20_objectives().unwrap().crates.clone();
    let hidden = |s: &GameSession, ids: &[String]| {
        s.state
            .pickups
            .iter()
            .filter(|p| ids.contains(&p.id))
            .all(|p| !p.available)
    };
    tick(&mut s);
    for c in &crates {
        assert!(hidden(&s, &c.supplies), "crates arrive with the clock");
    }
    let reached = reach_quay(&mut s, id);
    let g = s.state.map.m20_geometry().unwrap();
    let (start, _, _) = g.clock(reached);
    while s.state.tick < start + 1 {
        tick(&mut s);
    }
    for c in &crates {
        let released = s.state.tick >= start + c.release;
        assert_eq!(
            !hidden(&s, &c.supplies),
            released,
            "crate release follows the hold clock"
        );
    }
}

#[test]
fn death_before_the_reprieve_spends_a_continue_and_restarts_the_level() {
    let (mut s, id) = session_run(CampaignDifficulty::Standard, Role::Human, true);
    let reached = reach_quay(&mut s, id);
    let g = s.state.map.m20_geometry().unwrap();
    let (start, _, _) = g.clock(reached);
    while s.state.tick < start + 40 {
        tick(&mut s);
    }
    let index = s.state.players.iter().position(|p| p.id == id).unwrap();
    let damage = s.state.players[index].hp + s.state.players[index].armor;
    s.state.environmental_self_damage(index, damage);
    tick(&mut s);
    let state = s.state.mission_state().unwrap();
    assert_eq!(
        state.run.unwrap().status,
        crate::protocol::CampaignRunStatus::Continue
    );
    assert!(state.m20.as_ref().unwrap().reprieve_at.is_none());
    assert!(s.state.continue_mission(
        id,
        crate::protocol::MissionContinue {
            id: MissionId::LocalException,
            run_id: state.run.unwrap().id,
            attempt: state.attempt,
        }
    ));
    tick(&mut s);
    let f = facts(&s);
    assert!(f.completed.is_empty(), "a continue restarts the level");
    assert!(f.pier_reached_at.is_none());
    assert_eq!(f.refuge_integrity, M20_REFUGE_INTEGRITY);
    assert!(!s.state.players.iter().any(|p| p.is_campaign_enemy()
        && p.hp > 0
        && s.state.encounters.is_awake(FIRST_PRESSURE_GROUP)));
}

#[test]
fn the_reprieve_stands_every_machine_down_and_retires_them_at_the_exits() {
    let (mut s, id) = session();
    let reached = reach_quay(&mut s, id);
    let g = s.state.map.m20_geometry().unwrap();
    let (_, _, reprieve) = g.clock(reached);
    let hold = feet_of(&g.objectives[4]);
    while s.state.tick < reprieve - 1 {
        place(&mut s, id, hold);
        let p = s.state.players.iter_mut().find(|p| p.id == id).unwrap();
        p.hp = 100;
        tick(&mut s);
    }
    assert!(
        s.state
            .players
            .iter()
            .any(|p| p.is_campaign_enemy() && p.hp > 0),
        "the climax ends with machines on the quay"
    );
    tick(&mut s);
    assert!(facts(&s).reprieve_at.is_some());
    let hp_at_reprieve = s.state.players.iter().find(|p| p.id == id).unwrap().hp;
    // No machine attacks after the reprieve, and every one leaves. The work
    // front appears already standing down, holds, then walks on past the
    // refuge toward the next district.
    let exit = s.state.map.m20_objectives().unwrap().passing.1;
    let mut front_start: Option<f32> = None;
    let mut front_closest = f32::INFINITY;
    let mut held = false;
    for step in 0..1_700 {
        place(&mut s, id, hold);
        tick(&mut s);
        let front: Vec<f32> = s
            .state
            .players
            .iter()
            .filter(|p| p.name.starts_with("passing_work") && p.hp > 0)
            .map(|p| (p.x - exit[0]).hypot(p.z - exit[2]))
            .collect();
        if let Some(nearest) = front.iter().copied().reduce(f32::min) {
            if front_start.is_none() {
                front_start = Some(nearest);
            }
            if step < crate::encounters::enemy::STAND_DOWN_HOLD as usize {
                held |= (nearest - front_start.unwrap()).abs() < 0.01;
            }
            front_closest = front_closest.min(nearest);
        }
        for p in s.state.players.iter().filter(|p| p.is_campaign_enemy()) {
            if let Some(CampaignActor::Hostile { phase, .. }) = p.campaign {
                assert!(
                    !matches!(phase, EnemyPhase::Windup | EnemyPhase::Firing),
                    "a stood-down machine never commits an attack"
                );
            }
        }
        assert!(s.state.encounters.surveyor_marks().is_empty());
    }
    assert_eq!(
        s.state.players.iter().find(|p| p.id == id).unwrap().hp,
        hp_at_reprieve,
        "the reprieve ends every local harm"
    );
    let start = front_start.expect("the work front appears after the reprieve");
    assert!(held, "the front stops where it stands first");
    assert!(
        front_closest < start - 10.0,
        "the front walks on toward the next district: {start} -> {front_closest}"
    );
    assert!(
        !s.state
            .players
            .iter()
            .any(|p| p.is_campaign_enemy() && p.hp > 0),
        "the machines go on to the next district"
    );
    assert!(facts(&s).gate_open);
}

#[test]
fn the_crew_cross_on_their_own_once_the_crossing_is_clear() {
    let (mut s, id) = session_with(CampaignDifficulty::Assisted, Role::Agent);
    tick(&mut s);
    let starts: Vec<_> = facts(&s).crew.iter().map(|c| c.feet).collect();
    // Nobody leaves the pump hall while the crossing is held.
    for _ in 0..200 {
        tick(&mut s);
    }
    assert!(facts(&s)
        .crew
        .iter()
        .zip(&starts)
        .all(|(c, start)| c.phase == M20CrewPhase::Working && c.feet == *start));
    reach_quay(&mut s, id);
    let released = s.state.tick;
    let mut arrived_at = None;
    for _ in 0..2_000 {
        place(&mut s, id, [33.0, 1.0, 0.0]);
        if s.state.tick.is_multiple_of(20) {
            clear_enemies(&mut s);
        }
        tick(&mut s);
        if facts(&s).challenges.crew_crossed {
            arrived_at = Some(s.state.tick);
            break;
        }
    }
    let arrived_at = arrived_at.expect("the crew reach the wicket");
    assert!(arrived_at - released < 1_600, "about a minute on foot");
    let f = facts(&s);
    assert!(f.crew.iter().all(|c| c.phase == M20CrewPhase::Arrived));
    assert!(
        f.brief_completed,
        "the Assisted brief is the crew's crossing"
    );
    // Arrived crew are behind the line: no longer contact bodies.
    let mut bodies = Vec::new();
    s.state.append_civilian_contacts(&mut bodies);
    assert!(!bodies.iter().any(|b| b.key.starts_with("m20/crew")));
}

/// The strict client reader's fixture: both MapInfo worlds, the mission
/// messages at every stage of an ordinary run, and a snapshot carrying a live
/// Surveyor disc. Regenerate with FRAGR_UPDATE_LATE_CAMPAIGN_WORLDS=1.
#[test]
fn client_lifecycle_fixture_matches_golden() {
    let (mut s, id) = session_with(CampaignDifficulty::Standard, Role::Human);
    let mut messages = Vec::new();
    let push = |s: &GameSession, messages: &mut Vec<serde_json::Value>| {
        let message = serde_json::to_value(s.state.mission_message().unwrap()).unwrap();
        if messages.last() != Some(&message) {
            messages.push(message);
        }
    };
    tick(&mut s);
    let map_info = serde_json::to_value(s.state.map_info()).unwrap();
    push(&s, &mut messages);
    // A live disc over the catwalks: stand where the lesson's lens can see.
    place(&mut s, id, [-45.0, 1.2, 4.0]);
    let mut mark_snapshot = None;
    for _ in 0..240 {
        let p = s.state.players.iter_mut().find(|p| p.id == id).unwrap();
        p.hp = 100;
        tick(&mut s);
        let snapshot = s.state.snapshot();
        if snapshot.surveyor_marks.len() == 1 && snapshot.surveyor_marks[0].tracking {
            mark_snapshot = Some(serde_json::to_value(snapshot).unwrap());
            break;
        }
    }
    let mark_snapshot = mark_snapshot.expect("the lesson Surveyor marks the catwalks");
    let g = s.state.map.m20_geometry().unwrap();
    clear_enemies(&mut s);
    place(&mut s, id, feet_of(&g.objectives[0]));
    tick(&mut s);
    tick(&mut s);
    push(&s, &mut messages);
    place(&mut s, id, feet_of(&g.objectives[1]));
    tick(&mut s);
    clear_enemies(&mut s);
    tick(&mut s);
    tick(&mut s);
    push(&s, &mut messages);
    place(&mut s, id, feet_of(&g.objectives[2]));
    tick(&mut s);
    push(&s, &mut messages);
    let reached = facts(&s).pier_reached_at.unwrap();
    let (start, turn, reprieve) = g.clock(reached);
    let mut worn = false;
    while s.state.tick < reprieve + 1 {
        place(&mut s, id, feet_of(&g.objectives[3]));
        let p = s.state.players.iter_mut().find(|p| p.id == id).unwrap();
        p.hp = 100;
        if s.state.tick == start + 1_200 && !worn {
            // Stand one machine on the line long enough to wear it.
            if let Some(machine) = s.state.players.iter_mut().find(|p| {
                p.is_campaign_enemy()
                    && p.hp > 0
                    && matches!(p.campaign, Some(CampaignActor::Hostile { kind, .. }) if crate::encounters::enemy::gait(kind) > 0.0)
            }) {
                [machine.x, machine.y, machine.z] = [52.5, PLAYER_FLOOR_Y, -9.0];
                worn = true;
            }
        }
        if !s.state.tick.is_multiple_of(40) || s.state.tick < start + 1_300 {
            tick(&mut s);
        } else {
            clear_enemies(&mut s);
            tick(&mut s);
        }
        if [
            start + 2,
            start + 1_400,
            turn,
            turn + 1,
            reprieve,
            reprieve + 1,
        ]
        .contains(&s.state.tick)
        {
            push(&s, &mut messages);
        }
    }
    let mut map_info_open = None;
    for _ in 0..(GATE_TIMEOUT + 4) {
        place(&mut s, id, g.departure.approach);
        tick(&mut s);
        if facts(&s).gate_open {
            map_info_open = Some(serde_json::to_value(s.state.map_info()).unwrap());
            push(&s, &mut messages);
            break;
        }
    }
    let map_info_open = map_info_open.expect("the gate opens");
    interact(&mut s, id, &g.departure);
    push(&s, &mut messages);
    assert_eq!(
        s.state.mission.as_ref().unwrap().phase,
        MissionPhase::Departed
    );
    let fixture = serde_json::json!({
        "map_info": map_info,
        "map_info_open": map_info_open,
        "messages": messages,
        "mark_snapshot": mark_snapshot,
    });
    let path = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../client/golden/m20_lifecycle.json");
    let bytes = serde_json::to_string_pretty(&fixture).unwrap() + "\n";
    if std::env::var_os("FRAGR_UPDATE_LATE_CAMPAIGN_WORLDS").is_some() {
        std::fs::write(&path, &bytes).unwrap();
    }
    assert_eq!(std::fs::read_to_string(path).unwrap(), bytes);
}
