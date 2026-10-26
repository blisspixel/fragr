//! Connected avenue, office and recovery saves carry outcomes forward.
use super::*;
use crate::mission::run_file::{M16Outcome, M17Outcome, M18Outcome, SavedStep};

fn completed(mut entry: RunDocument) -> RunDocument {
    let SavedStep::MissionEntry {
        mission,
        entry: resources,
    } = &entry.step
    else {
        unreachable!()
    };
    let mission = *mission;
    let resources = resources.clone();
    let next = match mission {
        MissionId::FreedomOfMovement => {
            entry.m16_outcome = Some(M16Outcome {
                ride_started: true,
                green_wave_triggered: true,
                bus_freed: false,
                forecourt_secured: true,
                doors_open: true,
            });
            "peace_without_interruption"
        }
        MissionId::PeaceWithoutInterruption => {
            entry.m17_outcome = Some(M17Outcome {
                approach_breached: true,
                kessel_secured: false,
                core_unsealed: true,
                core_defeated: true,
                voss_captured: true,
            });
            "all_systems_normal"
        }
        MissionId::AllSystemsNormal => {
            entry.m18_outcome = Some(M18Outcome {
                aid_delivered: true,
                square_defended: true,
                collector_neutralized: true,
                overlook_witnessed: true,
                concourse_secured: true,
            });
            "planned_works"
        }
        _ => unreachable!(),
    };
    entry.step = SavedStep::AwaitingMission {
        completed_mission: mission,
        next_mission: next.into(),
        exit: resources,
    };
    entry
        .validate(m09_tests::HASHES[stage_index(mission)])
        .unwrap();
    entry
}

#[test]
fn late_campaign_promotion_carries_outcomes_and_refills_only_episode_v() {
    let mut source = m15_tests::completed_stadium();
    source.remaining_continues = 1;
    for (mission, outcome) in [
        (MissionId::FreedomOfMovement, "m15_outcome"),
        (MissionId::PeaceWithoutInterruption, "m16_outcome"),
        (MissionId::AllSystemsNormal, "m17_outcome"),
    ] {
        let directory = std::env::temp_dir().join(format!("fragr-late-save-{}", Uuid::new_v4()));
        let store = RunStore::open_with_hashes(&directory, m09_tests::HASHES).unwrap();
        store.save(&source).unwrap();
        let bytes = fs::read(directory.join(RUN_NAME)).unwrap();
        let loaded = store.load().unwrap().unwrap();
        assert_eq!(loaded, source);
        let next = loaded
            .promote_next(mission, m09_tests::HASHES[stage_index(mission)])
            .unwrap();
        let SavedStep::AwaitingMission { exit, .. } = &source.step else {
            unreachable!()
        };
        let SavedStep::MissionEntry { entry, .. } = &next.step else {
            unreachable!()
        };
        let mut expected = exit.clone();
        expected.equipment.personal_claims.clear();
        assert_eq!(entry, &expected, "promotion retains finite resources");
        let continues = if mission == MissionId::AllSystemsNormal {
            3
        } else {
            1
        };
        assert_eq!(
            (
                next.remaining_continues,
                next.level_start_continues,
                next.attempt()
            ),
            (continues, continues, 1)
        );
        let mut before = serde_json::to_value(&source).unwrap();
        let mut after = serde_json::to_value(&next).unwrap();
        for key in [
            "step",
            "content_sha256",
            "remaining_continues",
            "level_start_continues",
        ] {
            before.as_object_mut().unwrap().remove(key);
            after.as_object_mut().unwrap().remove(key);
        }
        assert_eq!(before, after, "earlier choices remain unchanged");
        assert!(store
            .save_with_sync(
                &next,
                |_| Err(io::Error::other("interrupted late promotion")),
                sync_directory,
            )
            .is_err());
        assert_eq!(fs::read(directory.join(RUN_NAME)).unwrap(), bytes);
        store.save(&next).unwrap();
        assert_eq!(store.load().unwrap().unwrap(), next);

        // A carried outcome is never optional once its mission is complete.
        let mut forged = serde_json::to_value(&next).unwrap();
        forged[outcome] = serde_json::Value::Null;
        assert!(matches!(
            RunStore::inspect_bytes(&serde_json::to_vec(&forged).unwrap(), m09_tests::HASHES),
            RunProbe::Corrupt
        ));
        forged.as_object_mut().unwrap().remove(outcome);
        assert!(matches!(
            RunStore::inspect_bytes(&serde_json::to_vec(&forged).unwrap(), m09_tests::HASHES),
            RunProbe::Incompatible
        ));
        source = completed(next);
        drop(store);
        fs::remove_dir_all(directory).unwrap();
    }
    assert!(
        matches!(&source.step, SavedStep::AwaitingMission { next_mission, .. } if next_mission == "planned_works")
    );
    assert!(source.m16_outcome.as_ref().is_some_and(|o| !o.bus_freed));
    assert!(source
        .m17_outcome
        .as_ref()
        .is_some_and(|o| !o.kessel_secured));
    // Completed recovery opens only Planned Works; m19_tests owns that edge.
    for mission in CAMPAIGN_MISSIONS {
        if mission != MissionId::PlannedWorks {
            assert!(source
                .promote_next(mission, m09_tests::HASHES[stage_index(mission)])
                .is_err());
        }
    }
}

#[test]
fn late_campaign_retry_restores_entry_without_rewinding_or_fabricating_outcomes() {
    use crate::{
        maps::{AuthoredSource, RuntimeMap},
        protocol::{MissionContinue, MissionReady, Role},
        sim::GameState,
    };
    let mut source = m15_tests::completed_stadium();
    for mission in [
        MissionId::FreedomOfMovement,
        MissionId::PeaceWithoutInterruption,
        MissionId::AllSystemsNormal,
    ] {
        let map = AuthoredSource::Mission(mission).load().unwrap();
        let hash = RuntimeMap::Authored(map.clone()).content_sha256().unwrap();
        let entry = source.promote_next(mission, hash).unwrap();
        let mut state = GameState::with_authored_map(map.clone());
        state.load_campaign_run(&entry).unwrap();
        let id = Uuid::new_v4();
        state.add_player(id, "Late campaign retry".into(), Role::Human);
        assert!(state.acknowledge_mission(
            id,
            MissionReady {
                id: mission,
                attempt: 1
            }
        ));
        assert_eq!(state.campaign_run_document().unwrap().unwrap(), entry);
        let original = state.players.iter().find(|p| p.id == id).unwrap();
        let resources = (
            original.hp,
            original.armor,
            original
                .inventory
                .state(id, original.weapon, state.tick)
                .unwrap(),
        );
        state.players.iter_mut().find(|p| p.id == id).unwrap().hp = 0;
        state.tick(0.05);
        let before = state.tick;
        let pending = state.campaign_run_document().unwrap().unwrap();
        assert!(
            matches!(pending.step, SavedStep::PendingContinue { mission: m, .. } if m == mission)
        );
        let mut reopened = GameState::with_authored_map(map);
        reopened.load_campaign_run(&pending).unwrap();
        reopened.add_player(id, "Reopened retry".into(), Role::Human);
        let request = MissionContinue {
            id: mission,
            run_id: entry.id,
            attempt: 1,
        };
        for live in [&mut state, &mut reopened] {
            assert!(live.continue_mission(id, request));
            assert!(!live.continue_mission(id, request));
            let player = live.players.iter().find(|p| p.id == id).unwrap();
            let equipment = player
                .inventory
                .state(id, player.weapon, live.tick)
                .unwrap();
            assert_eq!((player.hp, player.armor), (resources.0, resources.1));
            assert_eq!(equipment.weapons, resources.2.weapons);
            assert_eq!(equipment.ammo, resources.2.ammo);
            assert_eq!(equipment.remote_mines, resources.2.remote_mines);
            let retry = live.campaign_run_document().unwrap().unwrap();
            assert_eq!(
                (
                    retry.m15_outcome,
                    retry.m16_outcome,
                    retry.m17_outcome,
                    retry.m18_outcome
                ),
                (
                    entry.m15_outcome.clone(),
                    entry.m16_outcome.clone(),
                    entry.m17_outcome.clone(),
                    entry.m18_outcome.clone()
                )
            );
        }
        assert!(state.tick >= before);
        // The portable fixture uses the registered test hashes on its next edge.
        let next = source
            .promote_next(mission, m09_tests::HASHES[stage_index(mission)])
            .unwrap();
        source = completed(next);
    }
}

#[test]
fn exhausted_m18_and_m19_entries_stay_failed_and_refuse_still_here() {
    use crate::{
        maps::AuthoredSource,
        protocol::{CampaignDifficulty, CampaignRunStatus, MissionContinue, MissionReady, Role},
        session::GameSession,
    };
    // Explicit entry/death fixtures, not inherited campaign clears or a
    // measure of encounter difficulty. Earlier receipts use this owner's
    // existing setup; no route, objective or survival result is played here.
    let hashes = CAMPAIGN_MISSIONS.map(AuthoredSource::bundled_content_sha256);
    let mut source = m15_tests::completed_stadium();
    for mission in [
        MissionId::FreedomOfMovement,
        MissionId::PeaceWithoutInterruption,
        MissionId::AllSystemsNormal,
        MissionId::PlannedWorks,
    ] {
        let hash = hashes[stage_index(mission)];
        let entry = source.promote_next(mission, hash).unwrap();
        if matches!(
            mission,
            MissionId::AllSystemsNormal | MissionId::PlannedWorks
        ) {
            for difficulty in [
                CampaignDifficulty::Assisted,
                CampaignDifficulty::Standard,
                CampaignDifficulty::Severe,
            ] {
                let mut boundary = entry.clone();
                boundary.rules.difficulty = difficulty;
                boundary.remaining_continues = 0;
                let SavedStep::MissionEntry {
                    entry: resources, ..
                } = &mut boundary.step
                else {
                    unreachable!()
                };
                resources.hp = 1;
                resources.armor = 0;
                boundary.validate(hash).unwrap();
                let attempt = boundary.attempt();
                let map = AuthoredSource::Mission(mission).load().unwrap();
                let mut session = GameSession::with_authored_map(map.clone());
                session.state.load_campaign_run(&boundary).unwrap();
                let id = Uuid::from_u128(1819);
                session
                    .state
                    .add_player(id, "Exhaustion fixture".into(), Role::Human);
                assert!(session.state.acknowledge_mission(
                    id,
                    MissionReady {
                        id: mission,
                        attempt,
                    }
                ));
                let before = session.state.campaign_run_document().unwrap().unwrap();
                assert_eq!(before, boundary, "admission preserves the declared entry");
                let player = session
                    .state
                    .players
                    .iter()
                    .position(|p| p.id == id)
                    .unwrap();
                assert_eq!(
                    (
                        session.state.players[player].hp,
                        session.state.players[player].armor
                    ),
                    (1, 0)
                );
                // Apply the labelled lethal fixture through damage accounting;
                // the ordinary tick owns the failed run and refusal thereafter.
                session.state.environmental_self_damage(player, 1);
                session.tick_messages(0.05);
                let state = session.state.mission_state().unwrap();
                state.validate(session.state.tick).unwrap();
                assert_eq!(state.run.unwrap().status, CampaignRunStatus::Failed);
                let failed = session.state.campaign_run_document().unwrap().unwrap();
                let SavedStep::MissionEntry {
                    entry: resources, ..
                } = before.step.clone()
                else {
                    unreachable!()
                };
                let mut expected = before;
                expected.step = SavedStep::Failed {
                    mission,
                    entry: resources,
                };
                assert_eq!(
                    failed, expected,
                    "death preserves every receipt and entry resource"
                );
                assert_eq!(failed.remaining_continues, 0);
                assert!(!failed.survived_the_wipe());
                let retry = MissionContinue {
                    id: mission,
                    run_id: failed.id,
                    attempt,
                };
                for _ in 0..2 {
                    assert!(!session.state.continue_mission(id, retry));
                    session.tick_messages(0.05);
                    assert_eq!(
                        session.state.campaign_run_document().unwrap().unwrap(),
                        failed
                    );
                }
                assert_eq!(session.state.player_record(id).unwrap().total.deaths, 1);
                let directory =
                    std::env::temp_dir().join(format!("fragr-exhausted-wipe-{}", Uuid::new_v4()));
                let store = RunStore::open_with_hashes(&directory, hashes).unwrap();
                store.save(&failed).unwrap();
                drop(store);
                let store = RunStore::open_with_hashes(&directory, hashes).unwrap();
                let reopened = store.load().unwrap().unwrap();
                assert_eq!(reopened, failed);
                reopened.validate(hash).unwrap();
                assert!(GameSession::with_authored_map(map)
                    .state
                    .load_campaign_run(&reopened)
                    .is_err());
                let epilogue = AuthoredSource::Mission(MissionId::StillHere)
                    .load()
                    .unwrap();
                assert_eq!(
                    GameSession::with_authored_map(epilogue)
                        .state
                        .load_epilogue_entitlement(&reopened, hash),
                    Err("only a recorded survival of Local Exception opens Still Here")
                );
                drop(store);
                fs::remove_dir_all(directory).unwrap();
            }
        }
        if mission != MissionId::PlannedWorks {
            // Advance only the setup receipts, never the tested failed run.
            let setup = source
                .promote_next(mission, m09_tests::HASHES[stage_index(mission)])
                .unwrap();
            source = completed(setup);
        }
    }
}
