//! Local Exception: the campaign's last promotion edge, terminal survival
//! recorded through the ordinary locked writer, and its refusal paths.
use super::*;
use crate::maps::AuthoredSource;
use crate::mission::run_file::{M16Outcome, M17Outcome, SavedStep};
use crate::protocol::{Action, CampaignActor, LookAt, MissionPhase, MissionReady, Role};
use crate::session::GameSession;
use crate::sim::PLAYER_FLOOR_Y;

/// Completes an Episode IV stage with every receipt, as its writer would.
fn finish(mut entry: RunDocument) -> RunDocument {
    let SavedStep::MissionEntry {
        mission,
        entry: exit,
    } = entry.step.clone()
    else {
        unreachable!()
    };
    let next = match mission {
        MissionId::FreedomOfMovement => {
            entry.m16_outcome = Some(M16Outcome {
                ride_started: true,
                green_wave_triggered: true,
                bus_freed: true,
                forecourt_secured: true,
                doors_open: true,
            });
            "peace_without_interruption"
        }
        MissionId::PeaceWithoutInterruption => {
            entry.m17_outcome = Some(M17Outcome {
                approach_breached: true,
                kessel_secured: true,
                core_unsealed: true,
                core_defeated: true,
                voss_captured: true,
            });
            "all_systems_normal"
        }
        _ => unreachable!(),
    };
    entry.step = SavedStep::AwaitingMission {
        completed_mission: mission,
        next_mission: next.into(),
        exit,
    };
    entry
}

/// A completed Planned Works awaiting Local Exception, as its departure
/// writes it.
fn awaiting_local_exception() -> RunDocument {
    m19_tests::completed_works()
}

#[test]
fn local_exception_promotes_from_planned_works_without_a_refill() {
    let source = awaiting_local_exception();
    source
        .validate(m09_tests::HASHES[stage_index(MissionId::PlannedWorks)])
        .unwrap();
    assert_eq!(stage_index(MissionId::LocalException), CAMPAIGN_STAGES - 1);
    let hash = m09_tests::HASHES[stage_index(MissionId::LocalException)];
    let entry = source
        .promote_next(MissionId::LocalException, hash)
        .unwrap();
    let SavedStep::MissionEntry { mission, .. } = &entry.step else {
        panic!("promotion enters the level");
    };
    assert_eq!(*mission, MissionId::LocalException);
    assert_eq!(
        (entry.remaining_continues, entry.level_start_continues),
        (2, 2),
        "the Episode V allowance carries; only level 18 refilled it"
    );
    for outcome in [
        entry.m03_outcome.is_some(),
        entry.m04_outcome.is_some(),
        entry.m05_outcome.is_some(),
        entry.m15_outcome.is_some(),
        entry.m16_outcome.is_some(),
        entry.m17_outcome.is_some(),
        entry.m18_outcome.is_some(),
        entry.m19_outcome.is_some(),
    ] {
        assert!(outcome, "every earlier receipt rides into the finale");
    }
    entry.validate(hash).unwrap();

    // The victory edge: completed Local Exception awaits the epilogue.
    let SavedStep::MissionEntry { entry: carried, .. } = entry.step.clone() else {
        unreachable!()
    };
    let mut victory = entry.clone();
    victory.step = SavedStep::AwaitingMission {
        completed_mission: MissionId::LocalException,
        next_mission: "still_here".into(),
        exit: carried.clone(),
    };
    victory.validate(hash).unwrap();
    for mission in MissionId::ALL {
        assert!(
            victory
                .promote_next(mission, m09_tests::HASHES[stage_index(mission)])
                .is_err(),
            "nothing promotes past the campaign's survival yet: {mission:?}"
        );
    }
    // The survival result survives a restart through the locked store.
    let directory = std::env::temp_dir().join(format!("fragr-m20-save-{}", Uuid::new_v4()));
    let store = RunStore::open_with_hashes(&directory, m09_tests::HASHES).unwrap();
    store.start_new(&victory).unwrap();
    drop(store);
    let reopened = RunStore::open_with_hashes(&directory, m09_tests::HASHES).unwrap();
    assert_eq!(reopened.load().unwrap().unwrap(), victory);
    drop(reopened);
    fs::remove_dir_all(directory).unwrap();

    // Refusals: the wrong pending name, and a victory naming another stage.
    let mut wrong = victory.clone();
    wrong.step = SavedStep::AwaitingMission {
        completed_mission: MissionId::LocalException,
        next_mission: "planned_works".into(),
        exit: carried.clone(),
    };
    assert!(wrong.validate(hash).is_err());
    let mut stray = source.clone();
    stray.step = SavedStep::AwaitingMission {
        completed_mission: MissionId::PlannedWorks,
        next_mission: "still_here".into(),
        exit: carried,
    };
    assert!(stray.validate(hash).is_err());
    // An earlier stage cannot jump to the finale.
    let early = m15_tests::completed_stadium()
        .promote_next(
            MissionId::FreedomOfMovement,
            m09_tests::HASHES[stage_index(MissionId::FreedomOfMovement)],
        )
        .unwrap();
    assert!(finish(early)
        .promote_next(MissionId::LocalException, hash)
        .is_err());
}

/// The whole level on a durable solo run: the departure writes the
/// campaign's terminal survival result, and nothing else does.
#[test]
fn surviving_the_reprieve_records_the_campaign_victory() {
    let map = AuthoredSource::Mission(MissionId::LocalException)
        .load()
        .unwrap();
    let mut s = GameSession::with_authored_map(map);
    let hash = s.state.map.content_sha256().unwrap();
    let source = awaiting_local_exception();
    let entry = source
        .promote_next(MissionId::LocalException, hash)
        .unwrap();
    s.state.use_replay_ids();
    s.state.seed(2020);
    s.state.load_campaign_run(&entry).unwrap();
    let id = Uuid::from_u128(2020);
    s.state.add_player(id, "Pier operative".into(), Role::Human);
    assert!(s.state.acknowledge_mission(
        id,
        MissionReady {
            id: MissionId::LocalException,
            attempt: entry.attempt(),
        }
    ));
    let refuge = s.state.mission_state().unwrap().m20.unwrap().refuge;
    assert!(refuge.persons > 400, "the run's rescues stand on the pier");
    let g = s.state.map.m20_geometry().unwrap();
    let place = |s: &mut GameSession, feet: [f32; 3]| {
        let p = s.state.players.iter_mut().find(|p| p.id == id).unwrap();
        [p.x, p.y, p.z] = [feet[0], feet[1] + PLAYER_FLOOR_Y, feet[2]];
        p.vy = 0.0;
        p.hp = 100;
    };
    let clear = |s: &mut GameSession| {
        for i in 0..s.state.players.len() {
            let p = &s.state.players[i];
            if matches!(p.campaign, Some(CampaignActor::Hostile { .. })) && p.hp > 0 {
                let damage = p.hp + p.armor;
                s.state.environmental_self_damage(i, damage);
            }
        }
    };
    let feet = |index: usize| match &g.objectives[index].action {
        crate::protocol::MissionObjectiveAction::Arrival { feet, .. } => *feet,
        _ => unreachable!(),
    };
    for _ in 0..2 {
        s.tick_messages(0.05);
    }
    place(&mut s, [-45.0, 1.2, 0.0]);
    s.tick_messages(0.05);
    for index in 0..3 {
        clear(&mut s);
        place(&mut s, feet(index));
        for _ in 0..3 {
            s.tick_messages(0.05);
        }
    }
    let reached = s
        .state
        .mission_state()
        .unwrap()
        .m20
        .unwrap()
        .pier_reached_at;
    let (_, _, reprieve) = g.clock(reached.expect("quay reached"));
    let mut written = None;
    while s.state.tick < reprieve + crate::mission::m20::GATE_TIMEOUT + 4 {
        if s.state.tick.is_multiple_of(20) {
            clear(&mut s);
        }
        place(&mut s, feet(4));
        s.tick_messages(0.05);
        let document = s.state.campaign_run_document().unwrap().unwrap();
        assert!(
            matches!(document.step, SavedStep::MissionEntry { .. }),
            "no survival result before departure"
        );
        written = Some(document);
    }
    assert!(written.is_some());
    let point = g
        .departure
        .point(
            s.state.map.presentation_ref().unwrap(),
            &s.state.map.arena().solids,
        )
        .unwrap();
    place(&mut s, g.departure.approach);
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
    s.tick_messages(0.05);
    assert_eq!(
        s.state.mission.as_ref().unwrap().phase,
        MissionPhase::Departed
    );
    let victory = s.state.campaign_run_document().unwrap().unwrap();
    let SavedStep::AwaitingMission {
        completed_mission,
        next_mission,
        ..
    } = &victory.step
    else {
        panic!("departure records the survival result");
    };
    assert_eq!(*completed_mission, MissionId::LocalException);
    assert_eq!(next_mission, "still_here");
    victory.validate(hash).unwrap();
}
