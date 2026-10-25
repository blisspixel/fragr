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
    store.save(&victory).unwrap();
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

/// The campaign's survival with the bundled Local Exception identity, as a
/// desktop parent's run directory holds it after the reprieve.
fn bundled_victory() -> RunDocument {
    let hash = AuthoredSource::bundled_content_sha256(MissionId::LocalException);
    let entry = awaiting_local_exception()
        .promote_next(MissionId::LocalException, hash)
        .unwrap();
    let SavedStep::MissionEntry { entry: exit, .. } = entry.step.clone() else {
        unreachable!()
    };
    let mut victory = entry;
    victory.step = SavedStep::AwaitingMission {
        completed_mission: MissionId::LocalException,
        next_mission: "still_here".into(),
        exit,
    };
    victory.validate(hash).unwrap();
    victory
}

type Opened = (
    crate::protocol::MissionState,
    crate::protocol::CampaignDifficulty,
);

/// Start the real local loop for Still Here on `directory`, as the desktop
/// child does, and return what a human sees first.
async fn open_still_here(
    directory: &Path,
) -> Result<Opened, Box<dyn std::error::Error + Send + Sync>> {
    use crate::protocol::{ClientMessage, ServerMessage};
    use futures_util::{SinkExt, StreamExt};
    use tokio_tungstenite::{connect_async, tungstenite::Message};
    let options = crate::run::ServerOptions {
        bind: "127.0.0.1:0".into(),
        bots: 0,
        authored: Some(AuthoredSource::Mission(MissionId::StillHere)),
        difficulty: Some(crate::protocol::CampaignDifficulty::Standard),
        seed: 21,
        status_every_s: 0,
        ..Default::default()
    };
    let (ready_tx, ready_rx) = tokio::sync::oneshot::channel();
    let (stop_tx, stop_rx) = tokio::sync::oneshot::channel::<()>();
    let (difficulty_tx, difficulty_rx) = tokio::sync::oneshot::channel();
    let server = tokio::spawn(crate::run::run_local_server(
        options,
        async {
            let _ = stop_rx.await;
        },
        ready_tx,
        crate::run::LocalRunConfig {
            directory: directory.to_path_buf(),
            resume: true,
            difficulty_ready: difficulty_tx,
        },
    ));
    let Ok(address) = ready_rx.await else {
        return Err(server
            .await
            .unwrap()
            .expect_err("a refused entitlement never advertises readiness"));
    };
    let difficulty = difficulty_rx.await.unwrap();
    let (mut socket, _) = connect_async(format!("ws://{address}")).await.unwrap();
    socket
        .send(Message::Text(
            serde_json::to_string(&ClientMessage::Hello {
                body: None,
                role: Role::Human,
                name: "Still here".into(),
                geometry_version: crate::protocol::GEOMETRY_VERSION,
                gameplay_version: crate::protocol::STILL_HERE_GAMEPLAY_VERSION,
                ticket: None,
                resume: None,
            })
            .unwrap(),
        ))
        .await
        .unwrap();
    let state = tokio::time::timeout(std::time::Duration::from_secs(5), async {
        while let Some(Ok(Message::Text(text))) = socket.next().await {
            if let Ok(ServerMessage::Mission { state, .. }) = serde_json::from_str(&text) {
                if !state.party.is_empty() {
                    return state;
                }
            }
        }
        panic!("the epilogue ended before a mission state");
    })
    .await
    .unwrap();
    drop(socket);
    let _ = stop_tx.send(());
    server.await.unwrap()?;
    Ok((state, difficulty))
}

/// Surviving opens Still Here read-only: the run's rescues stand in the
/// refuge, the readiness echoes the run's own difficulty, and the saved
/// survival is byte for byte what it was. Anything short of it is refused.
#[tokio::test]
async fn the_saved_survival_opens_still_here_read_only() {
    let hashes = CAMPAIGN_MISSIONS.map(AuthoredSource::bundled_content_sha256);
    let directory = std::env::temp_dir().join(format!("fragr-still-here-{}", Uuid::new_v4()));
    let victory = bundled_victory();
    let store = RunStore::open_with_hashes(&directory, hashes).unwrap();
    store.save(&victory).unwrap();
    drop(store);
    let before = fs::read(directory.join(RUN_NAME)).unwrap();

    let (state, difficulty) = open_still_here(&directory).await.unwrap();
    assert_eq!(state.id, MissionId::StillHere);
    assert!(state.run.is_none(), "the epilogue keeps no run of its own");
    assert_eq!(difficulty, victory.rules.difficulty);
    let refuge = state.epilogue.as_ref().unwrap().refuge;
    assert_eq!(refuge, crate::mission::epilogue::refuge_from(&victory));
    assert_eq!(
        refuge,
        crate::protocol::EpilogueRefuge::EVERYONE,
        "every rescue this run made stands in the refuge"
    );
    assert_eq!(
        fs::read(directory.join(RUN_NAME)).unwrap(),
        before,
        "replay never writes the run"
    );
    // A second visit is the same visit: nothing was consumed.
    let (again, _) = open_still_here(&directory).await.unwrap();
    assert_eq!(again.epilogue.unwrap().refuge, refuge);

    // A run still inside the wipe, and no run at all, are refused.
    let pending = awaiting_local_exception()
        .promote_next(
            MissionId::LocalException,
            AuthoredSource::bundled_content_sha256(MissionId::LocalException),
        )
        .unwrap();
    let store = RunStore::open_with_hashes(&directory, hashes).unwrap();
    store.save(&pending).unwrap();
    drop(store);
    assert!(open_still_here(&directory).await.is_err());
    fs::remove_dir_all(&directory).unwrap();
    assert!(open_still_here(&directory).await.is_err());
}

/// A run's survival with nobody carried still opens the walk: absent
/// rescues change the faces, never the entitlement.
#[test]
fn a_survival_that_carried_nobody_still_opens_the_walk() {
    let hash = AuthoredSource::bundled_content_sha256(MissionId::LocalException);
    let mut alone = bundled_victory();
    alone.m03_outcome.as_mut().unwrap().liberated_cars.clear();
    alone.m04_outcome.as_mut().unwrap().rescued_patients.clear();
    let workshop = alone.m05_outcome.as_mut().unwrap();
    workshop.released_workers.clear();
    workshop.evacuated_workers.clear();
    // Neither Edda nor Splice was there to board Tern's ship in level 9.
    let berth = alone.m09_outcome.as_mut().unwrap();
    for list in [&mut berth.released_crew, &mut berth.aboard_at_departure] {
        list.retain(|id| id != "edda" && id != "splice");
    }
    if let Some(crate::protocol::M10Transit::Recorded { arrived_crew }) = alone.m10_transit.as_mut()
    {
        arrived_crew.retain(|id| id != "edda" && id != "splice");
    }
    alone.m08_outcome.as_mut().unwrap().recovered_mind_secured = false;
    alone.m11_outcome.as_mut().unwrap().transfer_released = false;
    let stadium = alone.m15_outcome.as_mut().unwrap();
    stadium.fallen_entrants = stadium.armed_entrants.clone();
    alone.m16_outcome.as_mut().unwrap().bus_freed = false;
    alone.validate(hash).unwrap();
    assert!(alone.survived_the_wipe());
    assert_eq!(
        crate::mission::epilogue::refuge_from(&alone),
        crate::protocol::EpilogueRefuge::default()
    );
    let map = AuthoredSource::Mission(MissionId::StillHere)
        .load()
        .unwrap();
    let mut session = GameSession::with_authored_map(map);
    session
        .state
        .load_epilogue_entitlement(&alone, hash)
        .unwrap();
    session
        .state
        .add_player(Uuid::from_u128(21), "Still here".into(), Role::Human);
    let state = session.state.mission_state().unwrap();
    assert_eq!(
        state.epilogue.unwrap().refuge,
        crate::protocol::EpilogueRefuge::default()
    );
}

/// One run shows the same faces at Level 20's pier and in Still Here's first
/// light. Splice stands at either only after reaching the level 5 freight,
/// as Tern's crew list in level 9 does: release alone brings nobody.
#[test]
fn the_pier_and_the_refuge_agree_on_who_came() {
    let map = AuthoredSource::Mission(MissionId::LocalException)
        .load()
        .unwrap();
    let hash = AuthoredSource::bundled_content_sha256(MissionId::LocalException);
    let carried = awaiting_local_exception()
        .promote_next(MissionId::LocalException, hash)
        .unwrap();
    let mut released_only = carried.clone();
    let workshop = released_only.m05_outcome.as_mut().unwrap();
    assert!(workshop.released_workers.iter().any(|id| id == "splice"));
    workshop.evacuated_workers.clear();
    // Splice missed the freight, so never boarded Tern's ship either.
    let berth = released_only.m09_outcome.as_mut().unwrap();
    for list in [&mut berth.released_crew, &mut berth.aboard_at_departure] {
        list.retain(|id| id != "splice");
    }
    if let Some(crate::protocol::M10Transit::Recorded { arrived_crew }) =
        released_only.m10_transit.as_mut()
    {
        arrived_crew.retain(|id| id != "splice");
    }
    released_only.validate(hash).unwrap();
    for (entry, splice) in [(carried, true), (released_only, false)] {
        let mut s = GameSession::with_authored_map(map.clone());
        s.state.load_campaign_run(&entry).unwrap();
        s.state
            .add_player(Uuid::from_u128(2021), "Pier operative".into(), Role::Human);
        let pier = s.state.mission_state().unwrap().m20.unwrap().refuge;
        assert_eq!(
            pier.splice, splice,
            "Splice at the pier follows the freight"
        );
        // The same run's survival, as Still Here reads it.
        let SavedStep::MissionEntry { entry: exit, .. } = entry.step.clone() else {
            unreachable!()
        };
        let mut victory = entry;
        victory.step = SavedStep::AwaitingMission {
            completed_mission: MissionId::LocalException,
            next_mission: "still_here".into(),
            exit,
        };
        victory.validate(hash).unwrap();
        let first_light = crate::mission::epilogue::refuge_from(&victory);
        assert_eq!(
            (pier.edda, pier.splice, pier.orrin, pier.sorrel),
            (
                first_light.edda,
                first_light.splice,
                first_light.orrin,
                first_light.sorrel
            ),
            "nobody stands at the pier and goes missing by the morning"
        );
    }
}

/// Live review only: writes a real survival run with every rescue to
/// `FRAGR_QA_SURVIVAL_RUN_DIR`, so a desktop child can open the fullest
/// refuge with `--local-mission still_here --run-mode resume`. Run with
/// `cargo test -p fragr-server -- --ignored write_survival_run_for_review`.
#[test]
#[ignore = "writes a review fixture outside the repository on request"]
fn write_survival_run_for_review() {
    let Some(directory) = std::env::var_os("FRAGR_QA_SURVIVAL_RUN_DIR") else {
        return;
    };
    let hashes = CAMPAIGN_MISSIONS.map(AuthoredSource::bundled_content_sha256);
    let store = RunStore::open_with_hashes(Path::new(&directory), hashes).unwrap();
    store.save(&bundled_victory()).unwrap();
}
