//! Civic Pressure Valve connected stadium persistence, historical archives and mission-entry retry.
use super::*;
use crate::mission::run_file::{M15Outcome, SavedStep};
use crate::protocol::{AmmoPool, CampaignActor, WeaponType};

pub(crate) fn stadium_entry() -> RunDocument {
    m14_tests::completed_launch()
        .promote_next(MissionId::CivicPressureValve, m09_tests::HASHES[14])
        .unwrap()
}

pub(crate) fn completed_stadium() -> RunDocument {
    let mut document = stadium_entry();
    let SavedStep::MissionEntry { entry, .. } = &document.step else {
        unreachable!()
    };
    document.step = SavedStep::AwaitingMission {
        completed_mission: MissionId::CivicPressureValve,
        next_mission: "freedom_of_movement".into(),
        exit: entry.clone(),
    };
    document.m15_outcome = Some(M15Outcome {
        pen_armed: true,
        blade_wave_won: true,
        entrants_preserved: true,
        broadcast_taken: true,
        armed_entrants: vec![4, 12, 44, 71],
        fallen_entrants: Vec::new(),
    });
    document.validate(m09_tests::HASHES[14]).unwrap();
    document
}

#[test]
fn m15_promotion_retains_all_receipts_and_exact_stock_with_refill() {
    let source = m14_tests::completed_launch();
    let promoted = source
        .promote_next(MissionId::CivicPressureValve, m09_tests::HASHES[14])
        .unwrap();
    let SavedStep::AwaitingMission { exit, .. } = &source.step else {
        unreachable!()
    };
    let SavedStep::MissionEntry { mission, entry } = &promoted.step else {
        unreachable!()
    };
    let mut expected = exit.clone();
    expected.equipment.personal_claims.clear();
    assert_eq!(*mission, MissionId::CivicPressureValve);
    assert_eq!(entry, &expected);
    assert!(entry.equipment.weapons.contains(&WeaponType::Rocket));
    assert!(entry.equipment.weapons.contains(&WeaponType::Arc));
    // Episode IV Reckoning: refilled to 3 continues
    assert_eq!(
        (
            promoted.remaining_continues,
            promoted.level_start_continues,
            promoted.attempt()
        ),
        (3, 3, 1)
    );
    let mut before = serde_json::to_value(&source).unwrap();
    let mut after = serde_json::to_value(&promoted).unwrap();
    for field in [
        "step",
        "content_sha256",
        "remaining_continues",
        "level_start_continues",
    ] {
        before.as_object_mut().unwrap().remove(field);
        after.as_object_mut().unwrap().remove(field);
    }
    assert_eq!(
        after, before,
        "the complete launch history survives promotion"
    );
    assert!(promoted
        .promote_next(MissionId::CivicPressureValve, m09_tests::HASHES[14])
        .is_err());
    for weapon in [WeaponType::Arc, WeaponType::Rocket] {
        let mut missing = promoted.clone();
        let SavedStep::MissionEntry { entry, .. } = &mut missing.step else {
            unreachable!()
        };
        entry.equipment.weapons.retain(|w| *w != weapon);
        entry.equipment.selected = WeaponType::Repeater;
        assert!(missing.validate(m09_tests::HASHES[14]).is_err());
    }
    let mut missing = source;
    missing.m14_outcome = None;
    assert!(missing
        .promote_next(MissionId::CivicPressureValve, m09_tests::HASHES[14])
        .is_err());
}

#[test]
fn m15_v18_preview_and_promotion_archive_exact_bytes_and_keep_interrupted_source() {
    let source = m14_tests::completed_launch();
    let mut historical = serde_json::to_value(&source).unwrap();
    historical["version"] = 18.into();
    let bytes = serde_json::to_vec_pretty(&historical).unwrap();
    let directory = std::env::temp_dir().join(format!("fragr-stadium-v18-{}", Uuid::new_v4()));
    let store = RunStore::open_with_hashes(&directory, m09_tests::HASHES).unwrap();
    fs::write(directory.join(RUN_NAME), &bytes).unwrap();
    let loaded = store.load().unwrap().unwrap();
    assert_eq!(loaded, source);
    assert_eq!(fs::read(directory.join(RUN_NAME)).unwrap(), bytes);
    assert!(store.needs_upgrade().unwrap());
    let next = loaded
        .promote_next(MissionId::CivicPressureValve, m09_tests::HASHES[14])
        .unwrap();
    assert!(store
        .archive_and_save_before_replace(&loaded, &next, |_| Err(io::Error::other(
            "interrupted stadium edge"
        )))
        .is_err());
    assert_eq!(fs::read(directory.join(RUN_NAME)).unwrap(), bytes);
    let archive = store.archive_and_save(&loaded, &next).unwrap();
    assert_eq!(fs::read(archive).unwrap(), bytes);
    assert_eq!(store.load().unwrap().unwrap(), next);
    assert!(!store.needs_upgrade().unwrap());
    drop(store);
    fs::remove_dir_all(directory).unwrap();
}

#[test]
fn m15_historical_decoder_refuses_future_mission_and_even_null_outcomes() {
    let mut historical = serde_json::to_value(m14_tests::completed_launch()).unwrap();
    historical["version"] = 18.into();
    for receipt in [
        serde_json::Value::Null,
        serde_json::to_value(completed_stadium().m15_outcome.unwrap()).unwrap(),
    ] {
        let mut forged = historical.clone();
        forged["m15_outcome"] = receipt;
        assert!(matches!(
            RunStore::inspect_bytes(&serde_json::to_vec(&forged).unwrap(), m09_tests::HASHES),
            RunProbe::Corrupt
        ));
    }
    let mut future = serde_json::to_value(stadium_entry()).unwrap();
    future["version"] = 18.into();
    assert!(matches!(
        RunStore::inspect_bytes(&serde_json::to_vec(&future).unwrap(), m09_tests::HASHES),
        RunProbe::Incompatible
    ));
    let mut current = serde_json::to_value(stadium_entry()).unwrap();
    current["m15_outcome"] = serde_json::Value::Null;
    assert!(matches!(
        RunStore::inspect_bytes(&serde_json::to_vec(&current).unwrap(), m09_tests::HASHES),
        RunProbe::Corrupt
    ));
    current["m15_outcome"] =
        serde_json::to_value(completed_stadium().m15_outcome.unwrap()).unwrap();
    assert!(matches!(
        RunStore::inspect_bytes(&serde_json::to_vec(&current).unwrap(), m09_tests::HASHES),
        RunProbe::Incompatible
    ));
}

#[test]
fn m15_completed_run_retains_challenge_outcomes_and_opens_freedom_of_movement() {
    let completed = completed_stadium();
    let bytes = serde_json::to_vec(&completed).unwrap();
    let RunProbe::Compatible(decoded) = RunStore::inspect_bytes(&bytes, m09_tests::HASHES) else {
        panic!("stadium exit")
    };
    assert_eq!(*decoded, completed);
    assert!(decoded.m15_outcome.as_ref().unwrap().entrants_preserved);
    assert_eq!(
        serde_json::from_str::<MissionId>("\"freedom_of_movement\"").unwrap(),
        MissionId::FreedomOfMovement
    );
    for mission in CAMPAIGN_MISSIONS {
        assert_eq!(
            completed
                .promote_next(mission, m09_tests::HASHES[stage_index(mission)])
                .is_ok(),
            mission == MissionId::FreedomOfMovement
        );
    }
    let mut missing = completed.clone();
    missing.m15_outcome = None;
    assert!(missing.validate(m09_tests::HASHES[14]).is_err());
    for required in ["pen_armed", "broadcast_taken"] {
        let mut forged = serde_json::to_value(&completed).unwrap();
        forged["m15_outcome"][required] = false.into();
        assert!(matches!(
            RunStore::inspect_bytes(&serde_json::to_vec(&forged).unwrap(), m09_tests::HASHES),
            RunProbe::Incompatible
        ));
    }
}

#[test]
fn m15_retry_restores_finite_entry_and_refills_without_rewinding() {
    use crate::maps::{AuthoredSource, RuntimeMap};
    use crate::protocol::{MissionContinue, MissionReady, Role};
    use crate::sim::GameState;
    let map = AuthoredSource::Mission(MissionId::CivicPressureValve)
        .load()
        .unwrap();
    let hash = RuntimeMap::Authored(map.clone()).content_sha256().unwrap();
    let entry = m14_tests::completed_launch()
        .promote_next(MissionId::CivicPressureValve, hash)
        .unwrap();
    let mut state = GameState::with_authored_map(map.clone());
    state.load_campaign_run(&entry).unwrap();
    let id = Uuid::new_v4();
    state.add_player(id, "Stadium contestant".into(), Role::Human);
    assert!(state.acknowledge_mission(
        id,
        MissionReady {
            id: MissionId::CivicPressureValve,
            attempt: 1,
        }
    ));
    assert_eq!(state.campaign_run_document().unwrap().unwrap(), entry);
    // 4 entrants present in pen
    assert_eq!(
        state
            .players
            .iter()
            .filter(|p| p.campaign.is_some_and(CampaignActor::is_entrant))
            .count(),
        4
    );

    // Participant dies
    state.players.iter_mut().find(|p| p.id == id).unwrap().hp = 0;
    state.tick(0.05);
    let before_retry = state.tick;
    let pending = state.campaign_run_document().unwrap().unwrap();
    assert!(matches!(
        pending.step,
        SavedStep::PendingContinue {
            mission: MissionId::CivicPressureValve,
            ..
        }
    ));
    assert_eq!(pending.m14_outcome, entry.m14_outcome);
    assert!(pending.m15_outcome.is_none());

    let retry = MissionContinue {
        id: MissionId::CivicPressureValve,
        run_id: entry.id,
        attempt: 1,
    };
    let mut reopened = GameState::with_authored_map(map);
    reopened.load_campaign_run(&pending).unwrap();
    let reopened_id = Uuid::new_v4();
    reopened.add_player(reopened_id, "Reopened stadium retry".into(), Role::Human);
    assert_eq!(reopened.campaign_run_document().unwrap().unwrap(), pending);
    assert!(reopened.continue_mission(reopened_id, retry));
    assert!(state.continue_mission(id, retry));
    assert!(!state.continue_mission(id, retry));
    assert!(state.tick >= before_retry);
    for (live, owner) in [(&state, id), (&reopened, reopened_id)] {
        let player = live.players.iter().find(|p| p.id == owner).unwrap();
        let equipment = player
            .inventory
            .state(owner, player.weapon, live.tick)
            .unwrap();
        assert!(equipment.owns(WeaponType::Rocket) && equipment.owns(WeaponType::Arc));
        assert_eq!(
            (
                equipment.ammo(AmmoPool::Rockets),
                equipment.ammo(AmmoPool::Cells),
                equipment.remote_mines,
                player.hp,
                player.armor
            ),
            (2, 29, 2, 27, 11)
        );
    }
}
