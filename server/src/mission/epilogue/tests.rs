use super::*;
use crate::maps::AuthoredMap;
use crate::navigation::{Navigation, Navigator};
use crate::protocol::{
    Action, EpiloguePose, EpilogueStage, EpilogueSurvivor, LookAt, Role, UseTarget,
};
use crate::session::GameSession;
use std::sync::{Arc, OnceLock};

const MAP: &str = include_str!("../../../maps/epilogue-still-here.json");

fn map() -> Arc<AuthoredMap> {
    static MAP_CACHE: OnceLock<Arc<AuthoredMap>> = OnceLock::new();
    MAP_CACHE
        .get_or_init(|| AuthoredMap::read(MAP.as_bytes()).unwrap())
        .clone()
}

fn session(role: Role) -> (GameSession, Uuid) {
    let mut s = GameSession::with_authored_map(map());
    s.state.use_replay_ids();
    s.state.seed(1021);
    let id = Uuid::from_u128(1021);
    s.state.add_player(id, "Still Here".into(), role);
    assert!(s.state.acknowledge_mission(
        id,
        MissionReady {
            id: MissionId::StillHere,
            attempt: 1,
        }
    ));
    (s, id)
}

/// One server tick, then the strict reader every client uses.
fn tick(s: &mut GameSession) -> MissionState {
    s.tick_messages(0.05);
    let map = &s.state.map;
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
        .replace_map_with_epilogue(
            map.epilogue_geometry().as_ref(),
            map.half_extent(),
            &map.arena().solids,
            map.presentation_ref(),
        )
        .unwrap();
    let state = s.state.mission_state().unwrap();
    reader.observe(s.state.tick, state.clone()).unwrap();
    state
}

fn place(s: &mut GameSession, id: Uuid, feet: [f32; 3]) {
    let p = s.state.players.iter_mut().find(|p| p.id == id).unwrap();
    [p.x, p.y, p.z] = [feet[0], feet[1] + PLAYER_FLOOR_Y, feet[2]];
    p.vy = 0.0;
    p.clear_input();
}

fn interact(s: &mut GameSession, id: Uuid, target: &UseTarget) -> MissionState {
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
    tick(s)
}

fn facts(state: &MissionState) -> &EpilogueObjectiveState {
    state.epilogue.as_ref().unwrap()
}

#[test]
fn the_refuge_loads_in_two_worlds_with_nothing_to_fight() {
    let world = crate::maps::RuntimeMap::Authored(map());
    assert_eq!(world.campaign_mission_id(), Some(MissionId::StillHere));
    assert_eq!(world.name(), "Still Here");
    assert!(world.encounters().is_empty());
    assert!(world.is_campaign());
    let g = world.epilogue_geometry().unwrap();
    assert!(!g.later);
    let later = world.prepared_epilogue_world(1).unwrap();
    let lg = later.epilogue_geometry().unwrap();
    assert!(lg.later);
    assert_eq!(later.name(), "Still Here, years later");
    assert_eq!(
        later.arena().solids.len(),
        world.arena().solids.len(),
        "decoration indices never move between worlds"
    );
    // Each world stows exactly the other's solids outside the square.
    for index in 0..world.arena().solids.len() {
        assert_eq!(
            crate::maps::epilogue_authored::stowed(world.arena(), index),
            g.later_only.contains(&index),
            "solid {index}"
        );
        assert_eq!(
            crate::maps::epilogue_authored::stowed(later.arena(), index),
            g.aftermath_only.contains(&index),
            "solid {index}"
        );
    }
    let back = later.prepared_epilogue_world(0).unwrap();
    assert_eq!(back.name(), "Still Here");
    assert_eq!(back.arena(), world.arena());
    // Latch is in both worlds whatever the run carried.
    for stage in [EpilogueStage::Aftermath, EpilogueStage::Later] {
        assert!(g.people.iter().any(|p| p.id == "latch"
            && p.stage == stage
            && p.requires.is_none()
            && p.unless.is_none()));
    }
    // Wire round trip of the map facts.
    let info = serde_json::to_value(world.epilogue_geometry()).unwrap();
    let parsed: crate::protocol::EpilogueMapGeometry = serde_json::from_value(info).unwrap();
    assert_eq!(parsed, g);
}

#[test]
fn presence_reads_only_carried_rescues_and_stand_ins_fill_the_gaps() {
    let g = crate::maps::RuntimeMap::Authored(map())
        .epilogue_geometry()
        .unwrap();
    let alone = EpilogueRefuge::default();
    let everyone = EpilogueRefuge::EVERYONE;
    let ids = |refuge: &EpilogueRefuge, stage: EpilogueStage| -> Vec<String> {
        g.people
            .iter()
            .filter(|p| p.present(stage, refuge))
            .map(|p| p.id.clone())
            .collect()
    };
    let first_alone = ids(&alone, EpilogueStage::Aftermath);
    let first_all = ids(&everyone, EpilogueStage::Aftermath);
    for name in ["edda", "splice", "orrin", "sorrel"] {
        assert!(!first_alone.contains(&name.to_owned()), "{name}");
        assert!(first_all.contains(&name.to_owned()), "{name}");
    }
    // Somebody else lit the lamp; somebody else is at the motor.
    assert!(first_alone.contains(&"lamp_keeper".to_owned()));
    assert!(!first_all.contains(&"lamp_keeper".to_owned()));
    assert!(first_alone.contains(&"mechanic".to_owned()));
    // The canon pair disagrees in the first light whatever the run.
    for name in ["ascender", "kneeler", "latch", "tern", "mara"] {
        assert!(first_alone.contains(&name.to_owned()), "{name}");
    }
    let later_all = ids(&everyone, EpilogueStage::Later);
    assert!(later_all.contains(&"sorrel".to_owned()), "the tram cab");
    assert!(!ids(&alone, EpilogueStage::Later).contains(&"sorrel".to_owned()));
    // People on furniture never block a walker; everyone else does.
    let blocking = g.blocking(&everyone);
    assert!(blocking.iter().all(|p| g
        .people
        .iter()
        .any(|q| q.id == p.id && q.stage == EpilogueStage::Aftermath && q.pose.blocks())));
    assert!(g
        .people
        .iter()
        .any(|p| p.pose == EpiloguePose::Perch || p.pose == EpiloguePose::Lie));
    // Every carried rescue is a face in the first light and years later.
    for who in [
        EpilogueSurvivor::Cars,
        EpilogueSurvivor::Edda,
        EpilogueSurvivor::Splice,
        EpilogueSurvivor::Orrin,
        EpilogueSurvivor::Sorrel,
        EpilogueSurvivor::Entrants,
        EpilogueSurvivor::Bus,
    ] {
        for stage in [EpilogueStage::Aftermath, EpilogueStage::Later] {
            assert!(
                g.people
                    .iter()
                    .any(|p| p.requires == Some(who) && p.stage == stage),
                "{who:?} {stage:?}"
            );
        }
    }
    // A rescue the run did not carry never leaves a hole where a person
    // stood: the people from the recall cars are simply not on the court.
    assert!(!first_alone.iter().any(|id| id.starts_with("car_family")));
    assert!(first_all.iter().any(|id| id.starts_with("car_family")));
}

#[test]
fn stay_with_latch_then_years_later_then_ask_the_score() {
    let (mut s, id) = session(Role::Human);
    let state = tick(&mut s);
    assert_eq!(state.phase, MissionPhase::InProgress);
    assert!(state.run.is_none(), "the epilogue keeps no run of its own");
    let f = facts(&state);
    assert_eq!(f.current.as_ref().unwrap().id, "stay_with_latch");
    assert!(!f.later && f.turning_at.is_none());
    let g = s.state.map.epilogue_geometry().unwrap();

    // A press that does not look at the ledger does nothing.
    place(&mut s, id, g.latch.approach);
    s.state.set_action(
        id,
        Action {
            interact: true,
            ..Default::default()
        },
    );
    let state = tick(&mut s);
    assert!(facts(&state).turning_at.is_none());
    assert!(state.prompts.is_empty());

    let state = interact(&mut s, id, &g.latch);
    let turned_at = facts(&state).turning_at.expect("the turn starts");
    assert_eq!(facts(&state).completed, vec!["stay_with_latch"]);
    assert!(
        state.prompts.is_empty(),
        "nothing to use while the world turns"
    );
    for _ in 0..EPILOGUE_TURN_TICKS {
        let state = tick(&mut s);
        if facts(&state).later {
            break;
        }
    }
    let state = tick(&mut s);
    let f = facts(&state);
    assert!(f.later, "the world turned");
    assert!(s.state.tick >= turned_at + EPILOGUE_TURN_TICKS);
    assert_eq!(s.state.map.name(), "Still Here, years later");
    assert_eq!(s.state.map.epilogue_stage(), 1);
    let player = s.state.players.iter().find(|p| p.id == id).unwrap();
    let slot = g.later_slots()[0];
    assert!((player.x - slot[0]).abs() < 0.3 && (player.z - slot[2]).abs() < 0.3);
    assert!(f.blocking.iter().all(|p| g
        .people
        .iter()
        .any(|q| q.id == p.id && q.stage == EpilogueStage::Later)));

    // The bench cannot be used before walking the court.
    let state = interact(&mut s, id, &g.departure);
    assert_ne!(state.phase, MissionPhase::Departed);
    place(&mut s, id, g.arrival_feet);
    let state = tick(&mut s);
    assert_eq!(facts(&state).completed.len(), 2);
    assert_eq!(facts(&state).current.as_ref().unwrap().id, "party_departed");
    let state = interact(&mut s, id, &g.departure);
    assert_eq!(state.phase, MissionPhase::Departed);
    assert_eq!(
        facts(&state).completed,
        vec!["stay_with_latch", "years_later", "party_departed"]
    );
    // Nothing after the ending can revoke it, and it is not a tally.
    for _ in 0..40 {
        assert_eq!(tick(&mut s).phase, MissionPhase::Departed);
    }
    assert!(s.state.player_record(id).is_none());
}

#[test]
fn people_are_bodies_and_furniture_holds_the_seated() {
    let (mut s, _id) = session(Role::Human);
    tick(&mut s);
    let mut bodies = Vec::new();
    s.state.append_civilian_contacts(&mut bodies);
    let g = s.state.map.epilogue_geometry().unwrap();
    let blocking = g.blocking(&EpilogueRefuge::default());
    assert_eq!(bodies.len(), blocking.len());
    assert!(bodies.iter().any(|b| b.key == "epilogue/latch"));
    assert!(!bodies.iter().any(|b| b.key == "epilogue/patient_a"));
}

#[test]
fn a_reset_keeps_who_the_run_brought() {
    let (mut s, id) = session(Role::Human);
    s.state
        .mission
        .as_mut()
        .unwrap()
        .epilogue
        .as_mut()
        .unwrap()
        .refuge = EpilogueRefuge {
        sorrel: true,
        ..EpilogueRefuge::default()
    };
    tick(&mut s);
    let g = s.state.map.epilogue_geometry().unwrap();
    interact(&mut s, id, &g.latch);
    s.state.reset_mission();
    let state = tick(&mut s);
    assert!(facts(&state).refuge.sorrel);
    assert!(facts(&state).turning_at.is_none());
    assert_eq!(s.state.map.epilogue_stage(), 0);
}

#[test]
fn the_entitlement_is_only_a_recorded_survival() {
    let (mut s, _) = session(Role::Human);
    let document = run_file::RunDocument::new(
        Uuid::from_u128(7),
        crate::protocol::CampaignRules::default(),
        [0; 32],
    );
    assert!(!document.survived_the_wipe());
    assert!(
        s.state
            .load_epilogue_entitlement(&document, [0; 32])
            .is_err(),
        "admission has already happened"
    );
    let mut fresh = GameSession::with_authored_map(map());
    assert!(fresh
        .state
        .load_epilogue_entitlement(&document, [0; 32])
        .is_err());
}

/// The shared local controller walks the whole epilogue as a free agent:
/// the ledger, the turn, the court years later and the bench.
#[test]
fn the_local_agent_walks_the_epilogue_to_the_bench() {
    let (mut session, id) = session(Role::Agent);
    let mut client = MissionClient::default();
    let mut navigator = Navigator::default();
    let mut previous = None;
    let mut navigation = None;
    for _ in 0..4_000 {
        let map = &session.state.map;
        if previous.as_ref() != Some(map) {
            client
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
            client
                .replace_map_with_epilogue(
                    map.epilogue_geometry().as_ref(),
                    map.half_extent(),
                    &map.arena().solids,
                    map.presentation_ref(),
                )
                .unwrap();
            navigation = Some(Navigation::shared(map.arena().clone()).unwrap());
            previous = Some(map.clone());
            navigator.clear();
        }
        let state = session.state.mission_state().unwrap();
        client.observe(session.state.tick, state.clone()).unwrap();
        if state.phase == MissionPhase::Departed {
            assert!(facts(&state).later);
            eprintln!("Still Here walked in {} ticks", session.state.tick);
            assert!(
                session.state.tick < 3_000,
                "a short walk, not a search: {}",
                session.state.tick
            );
            return;
        }
        let snapshot = session.state.snapshot();
        let action = client.steer(
            &mut navigator,
            navigation.as_ref().unwrap(),
            id,
            &snapshot,
            Action {
                fire: true,
                ..Action::default()
            },
        );
        assert!(!action.fire, "nothing in the refuge is a target");
        session.state.set_action(id, action);
        session.tick_messages(0.05);
    }
    let player = session.state.players.iter().find(|p| p.id == id).unwrap();
    panic!(
        "stalled at [{}, {}, {}]: {:?}",
        player.x,
        player.y,
        player.z,
        session.state.mission_state().unwrap().epilogue
    );
}

/// The strict client reader's fixture: both MapInfo worlds and the mission
/// messages through an ordinary walk with everyone the run could bring.
/// Regenerate with FRAGR_UPDATE_LATE_CAMPAIGN_WORLDS=1.
#[test]
fn client_lifecycle_fixture_matches_golden() {
    let (mut s, id) = session(Role::Human);
    s.state
        .mission
        .as_mut()
        .unwrap()
        .epilogue
        .as_mut()
        .unwrap()
        .refuge = EpilogueRefuge::EVERYONE;
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
    let g = s.state.map.epilogue_geometry().unwrap();
    interact(&mut s, id, &g.latch);
    push(&s, &mut messages);
    let mut map_info_later = None;
    for _ in 0..(EPILOGUE_TURN_TICKS + 4) {
        let state = tick(&mut s);
        if facts(&state).later {
            map_info_later = Some(serde_json::to_value(s.state.map_info()).unwrap());
            push(&s, &mut messages);
            break;
        }
    }
    let map_info_later = map_info_later.expect("the world turns");
    place(&mut s, id, g.arrival_feet);
    tick(&mut s);
    push(&s, &mut messages);
    interact(&mut s, id, &g.departure);
    push(&s, &mut messages);
    assert_eq!(
        s.state.mission.as_ref().unwrap().phase,
        MissionPhase::Departed
    );
    let fixture = serde_json::json!({
        "map_info": map_info,
        "map_info_later": map_info_later,
        "messages": messages,
    });
    let path = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../client/golden/epilogue_lifecycle.json");
    let bytes = serde_json::to_string_pretty(&fixture).unwrap() + "\n";
    if std::env::var_os("FRAGR_UPDATE_LATE_CAMPAIGN_WORLDS").is_some() {
        std::fs::write(&path, &bytes).unwrap();
    }
    assert_eq!(std::fs::read_to_string(path).unwrap(), bytes);
}
