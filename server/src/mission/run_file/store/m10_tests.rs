use super::*;
use crate::mission::run_file::{M09Outcome, SavedStep};
use crate::protocol::{CampaignRunStatus, M10Transit, MissionContinue, MissionReady, Role};
use crate::sim::{GameState, PLAYER_FLOOR_Y};

#[test]
fn m10_real_promotion_completes_only_released_crew_and_retry_keeps_its_entry() {
    let map = crate::maps::AuthoredSource::Mission(MissionId::CommonCarrier)
        .load()
        .unwrap();
    for (edda, splice, known) in [
        (false, false, true),
        (true, false, true),
        (false, true, true),
        (true, true, true),
        (true, true, false),
    ] {
        let mut before = m09_receipt_tests::completed_berth(edda, splice);
        before.remaining_continues = 1;
        if !known {
            before.m09_outcome = Some(M09Outcome::HistoricalUnrecorded {});
        }
        let receipt = before.m09_outcome.clone();
        let SavedStep::AwaitingMission { exit, .. } = &before.step else {
            panic!("berth exit");
        };
        let mut entry = exit.clone();
        entry.equipment.personal_claims.clear();
        let promoted = before
            .promote_next(
                MissionId::CommonCarrier,
                crate::maps::RuntimeMap::Authored(map.clone())
                    .content_sha256()
                    .unwrap(),
            )
            .unwrap();
        assert_eq!(promoted.remaining_continues, 3);
        assert_eq!(promoted.level_start_continues, 3);
        assert_eq!(promoted.m09_outcome, receipt);
        match (&receipt, &promoted.m10_transit) {
            (
                Some(M09Outcome::Recorded {
                    released_crew,
                    aboard_at_departure,
                }),
                Some(M10Transit::Recorded { arrived_crew }),
            ) => {
                assert!(
                    aboard_at_departure.is_empty(),
                    "the true old zero-aboard fact stays empty"
                );
                assert_eq!(arrived_crew, released_crew);
            }
            (
                Some(M09Outcome::HistoricalUnrecorded {}),
                Some(M10Transit::HistoricalUnrecorded {}),
            ) => {}
            _ => panic!("unknown history or actual release was fabricated"),
        }
        assert_eq!(
            promoted.step,
            SavedStep::MissionEntry {
                mission: MissionId::CommonCarrier,
                entry: entry.clone()
            }
        );
        assert!(promoted
            .promote_next(
                MissionId::CommonCarrier,
                crate::maps::RuntimeMap::Authored(map.clone())
                    .content_sha256()
                    .unwrap()
            )
            .is_err());
        let mut state = GameState::with_authored_map(map.clone());
        state.load_campaign_run(&promoted).unwrap();
        let id = Uuid::new_v4();
        state.add_player(id, "Ship retry".into(), Role::Human);
        state.acknowledge_mission(
            id,
            MissionReady {
                id: MissionId::CommonCarrier,
                attempt: 1,
            },
        );
        let facts = state.mission_state().unwrap();
        facts.validate(state.tick).unwrap();
        let ship = facts.m10.as_ref().unwrap();
        assert_eq!(
            ship.pilot,
            crate::maps::RuntimeMap::Authored(map.clone())
                .m10_geometry()
                .unwrap()
                .pilot,
            "current Tern appears independently of history"
        );
        assert_eq!(
            ship.passengers.iter().any(|p| p.id == "edda"),
            known && edda
        );
        assert_eq!(
            ship.passengers.iter().any(|p| p.id == "splice"),
            known && splice
        );
        assert_eq!(
            ship.passengers.len(),
            if known {
                2 + usize::from(edda) + usize::from(splice)
            } else {
                0
            }
        );
        for _ in 0..40 {
            state.tick(0.05);
            state.take_events();
        }
        let player = state.players.iter().find(|p| p.id == id).unwrap();
        assert_eq!(
            (player.hp, player.armor),
            (entry.hp, entry.armor),
            "readiness cannot wake distant boarders"
        );
        assert_eq!(state.campaign_run_document().unwrap().unwrap(), promoted);
        let old_tick = state.tick;
        let player = state.players.iter_mut().find(|p| p.id == id).unwrap();
        player.hp = 0;
        player.respawn_timer = None;
        state.tick(0.05);
        let dead = state.mission_state().unwrap();
        assert_eq!(dead.run.unwrap().status, CampaignRunStatus::Continue);
        let request = MissionContinue {
            id: MissionId::CommonCarrier,
            run_id: promoted.id,
            attempt: 1,
        };
        assert!(state.continue_mission(id, request));
        assert!(!state.continue_mission(id, request));
        let retry = state.campaign_run_document().unwrap().unwrap();
        assert_eq!(retry.remaining_continues, 2);
        assert_eq!(retry.level_start_continues, 3);
        assert_eq!(retry.step, promoted.step);
        assert_eq!(retry.m09_outcome, promoted.m09_outcome);
        assert_eq!(retry.m10_transit, promoted.m10_transit);
        assert!(state.tick > old_tick);
        let player = state.players.iter().find(|p| p.id == id).unwrap();
        assert!((player.y - PLAYER_FLOOR_Y - 4.8).abs() < 0.01);
    }
}

#[test]
fn m10_locked_v12_upgrade_preserves_bytes_then_commits_distinct_transit_once() {
    for known in [false, true] {
        let mut source = m09_receipt_tests::completed_berth(true, true);
        source.remaining_continues = 1;
        if !known {
            source.m09_outcome = Some(M09Outcome::HistoricalUnrecorded {});
        }
        let mut value = serde_json::to_value(&source).unwrap();
        value["version"] = 12.into();
        let mut bytes = serde_json::to_vec_pretty(&value).unwrap();
        bytes.extend_from_slice(b"\n \n");
        let directory = std::env::temp_dir().join(format!("fragr-m10-transit-{}", Uuid::new_v4()));
        let store = RunStore::open_with_hashes(&directory, m09_tests::HASHES).unwrap();
        fs::write(directory.join(RUN_NAME), &bytes).unwrap();
        let loaded = store.load().unwrap().unwrap();
        assert_eq!(loaded, source);
        assert!(store.needs_upgrade().unwrap());
        let promoted = loaded
            .promote_next(MissionId::CommonCarrier, m09_tests::HASHES[9])
            .unwrap();
        assert!(store
            .archive_and_save_before_replace(&loaded, &promoted, |_| Err(io::Error::other(
                "interrupted transition"
            )))
            .is_err());
        assert_eq!(fs::read(directory.join(RUN_NAME)).unwrap(), bytes);
        let archive = store.archive_and_save(&loaded, &promoted).unwrap();
        assert_eq!(fs::read(archive).unwrap(), bytes);
        assert_eq!(store.load().unwrap().unwrap(), promoted);
        assert!(!store.needs_upgrade().unwrap());
        drop(store);
        let reopened = RunStore::open_with_hashes(&directory, m09_tests::HASHES).unwrap();
        assert_eq!(reopened.load().unwrap().unwrap(), promoted);
        assert!(
            reopened.archive_and_save(&loaded, &promoted).is_err(),
            "stale promotion cannot duplicate arrival/refill"
        );
        drop(reopened);
        fs::remove_dir_all(directory).unwrap();
    }
}

#[test]
fn m10_transit_refuses_forged_current_and_historical_ownership_or_arrivals() {
    let before = m09_receipt_tests::completed_berth(true, true);
    let promoted = before
        .promote_next(MissionId::CommonCarrier, m09_tests::HASHES[9])
        .unwrap();
    for transit in [
        serde_json::json!({"kind":"recorded","arrived_crew":["tern","berth_crew_a","berth_crew_b"]}),
        serde_json::json!({"kind":"historical_unrecorded"}),
        serde_json::json!({"kind":"recorded","arrived_crew":["tern","berth_crew_a","berth_crew_b","edda","edda"]}),
    ] {
        let mut value = serde_json::to_value(&promoted).unwrap();
        value["m10_transit"] = transit;
        assert!(!matches!(
            RunStore::inspect_bytes(&serde_json::to_vec(&value).unwrap(), m09_tests::HASHES),
            RunProbe::Compatible(_)
        ));
    }
    for version in [10, 11, 12] {
        let mut value = serde_json::to_value(&promoted).unwrap();
        value["version"] = version.into();
        value.as_object_mut().unwrap().remove("m10_transit");
        if version < 12 {
            value.as_object_mut().unwrap().remove("m09_outcome");
        }
        assert!(
            !matches!(
                RunStore::inspect_bytes(&serde_json::to_vec(&value).unwrap(), m09_tests::HASHES),
                RunProbe::Compatible(_)
            ),
            "historical M10 must refuse"
        );
        let mut value = serde_json::to_value(&before).unwrap();
        value["version"] = version.into();
        if version < 12 {
            value.as_object_mut().unwrap().remove("m09_outcome");
        }
        value["m10_transit"] = serde_json::Value::Null;
        assert!(matches!(
            RunStore::inspect_bytes(&serde_json::to_vec(&value).unwrap(), m09_tests::HASHES),
            RunProbe::Corrupt
        ));
    }
}
