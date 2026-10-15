//! Launch-work persistence, historical archives and mission-entry retry.
use super::*;
use crate::mission::run_file::{M14Outcome, SavedStep};
use crate::protocol::{AmmoPool, WeaponType};

fn launch_entry() -> RunDocument {
    m13_tests::completed_foundry()
        .promote_next(MissionId::LaunchAuthority, m09_tests::HASHES[13])
        .unwrap()
}

fn completed_launch() -> RunDocument {
    let mut document = launch_entry();
    let SavedStep::MissionEntry { entry, .. } = &document.step else {
        unreachable!()
    };
    document.step = SavedStep::AwaitingMission {
        completed_mission: MissionId::LaunchAuthority,
        next_mission: "civic_pressure_valve".into(),
        exit: entry.clone(),
    };
    document.m14_outcome = Some(M14Outcome {
        depot_secured: true,
        walker_disabled: true,
        jeep_preserved: false,
        on_foot: true,
    });
    document.validate(m09_tests::HASHES[13]).unwrap();
    document
}

#[test]
fn m14_promotion_retains_all_receipts_and_exact_stock_without_refill() {
    let source = m13_tests::completed_foundry();
    let promoted = source
        .promote_next(MissionId::LaunchAuthority, m09_tests::HASHES[13])
        .unwrap();
    let SavedStep::AwaitingMission { exit, .. } = &source.step else {
        unreachable!()
    };
    let SavedStep::MissionEntry { mission, entry } = &promoted.step else {
        unreachable!()
    };
    let mut expected = exit.clone();
    expected.equipment.personal_claims.clear();
    assert_eq!(*mission, MissionId::LaunchAuthority);
    assert_eq!(entry, &expected);
    assert!(entry.equipment.weapons.contains(&WeaponType::Rocket));
    assert_eq!(
        (
            promoted.remaining_continues,
            promoted.level_start_continues,
            promoted.attempt()
        ),
        (1, 1, 1)
    );
    let mut before = serde_json::to_value(&source).unwrap();
    let mut after = serde_json::to_value(&promoted).unwrap();
    for field in ["step", "content_sha256", "level_start_continues"] {
        before.as_object_mut().unwrap().remove(field);
        after.as_object_mut().unwrap().remove(field);
    }
    assert_eq!(
        after, before,
        "the complete foundry history survives promotion"
    );
    assert!(promoted
        .promote_next(MissionId::LaunchAuthority, m09_tests::HASHES[13])
        .is_err());
    for weapon in [WeaponType::Arc, WeaponType::Rocket] {
        let mut missing = promoted.clone();
        let SavedStep::MissionEntry { entry, .. } = &mut missing.step else {
            unreachable!()
        };
        entry.equipment.weapons.retain(|w| *w != weapon);
        entry.equipment.selected = WeaponType::Repeater;
        assert!(missing.validate(m09_tests::HASHES[13]).is_err());
    }
    let mut missing = source;
    missing.m13_outcome = None;
    assert!(missing
        .promote_next(MissionId::LaunchAuthority, m09_tests::HASHES[13])
        .is_err());
}

#[test]
fn m14_v17_preview_and_promotion_archive_exact_bytes_and_keep_interrupted_source() {
    let source = m13_tests::completed_foundry();
    let mut historical = serde_json::to_value(&source).unwrap();
    historical["version"] = 17.into();
    let bytes = serde_json::to_vec_pretty(&historical).unwrap();
    let directory = std::env::temp_dir().join(format!("fragr-launch-v17-{}", Uuid::new_v4()));
    let store = RunStore::open_with_hashes(&directory, m09_tests::HASHES).unwrap();
    fs::write(directory.join(RUN_NAME), &bytes).unwrap();
    let loaded = store.load().unwrap().unwrap();
    assert_eq!(loaded, source);
    assert_eq!(fs::read(directory.join(RUN_NAME)).unwrap(), bytes);
    assert!(store.needs_upgrade().unwrap());
    let next = loaded
        .promote_next(MissionId::LaunchAuthority, m09_tests::HASHES[13])
        .unwrap();
    assert!(store
        .archive_and_save_before_replace(&loaded, &next, |_| Err(io::Error::other(
            "interrupted launch edge"
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
fn m14_historical_decoder_refuses_future_mission_and_even_null_outcomes() {
    let mut historical = serde_json::to_value(m13_tests::completed_foundry()).unwrap();
    historical["version"] = 17.into();
    for receipt in [
        serde_json::Value::Null,
        serde_json::to_value(completed_launch().m14_outcome.unwrap()).unwrap(),
    ] {
        let mut forged = historical.clone();
        forged["m14_outcome"] = receipt;
        assert!(matches!(
            RunStore::inspect_bytes(&serde_json::to_vec(&forged).unwrap(), m09_tests::HASHES),
            RunProbe::Corrupt
        ));
    }
    let mut future = serde_json::to_value(launch_entry()).unwrap();
    future["version"] = 17.into();
    assert!(matches!(
        RunStore::inspect_bytes(&serde_json::to_vec(&future).unwrap(), m09_tests::HASHES),
        RunProbe::Incompatible
    ));
    let mut current = serde_json::to_value(launch_entry()).unwrap();
    current["m14_outcome"] = serde_json::Value::Null;
    assert!(matches!(
        RunStore::inspect_bytes(&serde_json::to_vec(&current).unwrap(), m09_tests::HASHES),
        RunProbe::Corrupt
    ));
    current["m14_outcome"] = serde_json::to_value(completed_launch().m14_outcome.unwrap()).unwrap();
    assert!(matches!(
        RunStore::inspect_bytes(&serde_json::to_vec(&current).unwrap(), m09_tests::HASHES),
        RunProbe::Incompatible
    ));
}

#[test]
fn m14_completed_run_retains_optional_losses_and_refuses_unbuilt_m15() {
    let completed = completed_launch();
    let bytes = serde_json::to_vec(&completed).unwrap();
    let RunProbe::Compatible(decoded) = RunStore::inspect_bytes(&bytes, m09_tests::HASHES) else {
        panic!("launch exit")
    };
    assert_eq!(*decoded, completed);
    assert!(!decoded.m14_outcome.as_ref().unwrap().jeep_preserved);
    assert!(serde_json::from_str::<MissionId>("\"civic_pressure_valve\"").is_err());
    for mission in CAMPAIGN_MISSIONS {
        assert!(completed
            .promote_next(mission, m09_tests::HASHES[stage_index(mission)])
            .is_err());
    }
    let mut missing = completed.clone();
    missing.m14_outcome = None;
    assert!(missing.validate(m09_tests::HASHES[13]).is_err());
    for required in ["depot_secured", "walker_disabled"] {
        let mut forged = serde_json::to_value(&completed).unwrap();
        forged["m14_outcome"][required] = false.into();
        assert!(matches!(
            RunStore::inspect_bytes(&serde_json::to_vec(&forged).unwrap(), m09_tests::HASHES),
            RunProbe::Incompatible
        ));
    }
}

#[test]
fn m14_retry_restores_finite_entry_jeep_and_walker_without_rewinding_or_refill() {
    use crate::maps::{AuthoredSource, RuntimeMap};
    use crate::protocol::{CampaignRunStatus, MissionContinue, MissionReady, Role};
    use crate::sim::GameState;
    let map = AuthoredSource::Mission(MissionId::LaunchAuthority)
        .load()
        .unwrap();
    let hash = RuntimeMap::Authored(map.clone()).content_sha256().unwrap();
    let entry = m13_tests::completed_foundry()
        .promote_next(MissionId::LaunchAuthority, hash)
        .unwrap();
    let mut state = GameState::with_authored_map(map.clone());
    state.load_campaign_run(&entry).unwrap();
    let id = Uuid::new_v4();
    state.add_player(id, "Launch finite retry".into(), Role::Human);
    assert!(state.acknowledge_mission(
        id,
        MissionReady {
            id: MissionId::LaunchAuthority,
            attempt: 1
        }
    ));
    assert_eq!(state.campaign_run_document().unwrap().unwrap(), entry);
    let original_jeep = state.vehicles[0].state.clone();
    let original_walker = state.walker.as_ref().unwrap().state.clone();
    // Arrange damaged machinery separately from combat. The shared death,
    // save/reopen and continue lifecycle must reset the complete world.
    state.vehicles[0].state.hp = 0;
    state.walker.as_mut().unwrap().state.hp = 1;
    state.players.iter_mut().find(|p| p.id == id).unwrap().hp = 0;
    state.tick(0.05);
    let before_retry = state.tick;
    let pending = state.campaign_run_document().unwrap().unwrap();
    assert!(matches!(
        pending.step,
        SavedStep::PendingContinue {
            mission: MissionId::LaunchAuthority,
            ..
        }
    ));
    assert_eq!(pending.m13_outcome, entry.m13_outcome);
    assert!(pending.m14_outcome.is_none());
    let retry = MissionContinue {
        id: MissionId::LaunchAuthority,
        run_id: entry.id,
        attempt: 1,
    };
    let mut reopened = GameState::with_authored_map(map);
    reopened.load_campaign_run(&pending).unwrap();
    let reopened_id = Uuid::new_v4();
    reopened.add_player(reopened_id, "Reopened launch retry".into(), Role::Human);
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
        assert_eq!(live.vehicles[0].state.hp, original_jeep.hp);
        assert_eq!(live.vehicles[0].state.position, original_jeep.position);
        assert_eq!(live.walker.as_ref().unwrap().state.hp, original_walker.hp);
        assert_eq!(
            live.walker.as_ref().unwrap().state.feet,
            original_walker.feet
        );
        let facts = live.mission_state().unwrap().m14.unwrap();
        assert!(facts.completed.is_empty() && !facts.machine_fallen && facts.support_stage == 0);
        let saved = live.campaign_run_document().unwrap().unwrap();
        assert_eq!(
            (
                saved.remaining_continues,
                saved.level_start_continues,
                saved.attempt()
            ),
            (0, 1, 2)
        );
        assert_eq!(saved.step, entry.step);
        assert_eq!(saved.m13_outcome, entry.m13_outcome);
    }
    state.players.iter_mut().find(|p| p.id == id).unwrap().hp = 0;
    state.tick(0.05);
    assert_eq!(
        state.mission_state().unwrap().run.unwrap().status,
        CampaignRunStatus::Failed
    );
    assert!(!state.continue_mission(
        id,
        MissionContinue {
            attempt: 2,
            ..retry
        }
    ));
}

#[test]
fn m14_actual_supported_departure_captures_finite_exit_and_resolved_outcome() {
    use crate::maps::{AuthoredSource, RuntimeMap};
    use crate::protocol::{Action, LookAt, M14ChallengeState, MissionReady, Role};
    use crate::sim::{GameState, PLAYER_FLOOR_Y};
    let map = AuthoredSource::Mission(MissionId::LaunchAuthority)
        .load()
        .unwrap();
    let hash = RuntimeMap::Authored(map.clone()).content_sha256().unwrap();
    let entry = m13_tests::completed_foundry()
        .promote_next(MissionId::LaunchAuthority, hash)
        .unwrap();
    let mut state = GameState::with_authored_map(map);
    state.load_campaign_run(&entry).unwrap();
    let id = Uuid::new_v4();
    state.add_player(id, "Launch departure receipt".into(), Role::Human);
    assert!(state.acknowledge_mission(
        id,
        MissionReady {
            id: MissionId::LaunchAuthority,
            attempt: 1
        }
    ));
    // Isolate save capture from route combat: arrange the resolved final world,
    // then use the actual control with finite entry stock and the ready owner.
    state.map = state.map.prepared_m14_world([8.0, 0.0, 26.0]).unwrap();
    state.walker = None;
    let progress = state.mission.as_mut().unwrap().m14.as_mut().unwrap();
    progress.index = 6;
    progress.support_stage = 2;
    progress.first_cycle_complete = true;
    progress.machine_fallen = true;
    progress.challenges = M14ChallengeState {
        depot_secured: true,
        walker_disabled: true,
        jeep_preserved: false,
        on_foot: true,
    };
    let geometry = state.map.m14_geometry().unwrap();
    let point = geometry
        .departure
        .point(
            state.map.presentation_ref().unwrap(),
            &state.current_arena().solids,
        )
        .unwrap();
    let owner = state.players.iter_mut().find(|p| p.id == id).unwrap();
    [owner.x, owner.y, owner.z] = [
        geometry.departure.approach[0],
        geometry.departure.approach[1] + PLAYER_FLOOR_Y,
        geometry.departure.approach[2],
    ];
    owner.vy = 0.0;
    owner.clear_input();
    let exit_before = super::super::SavedEntry::from_player(owner).unwrap();
    state.set_action(
        id,
        Action {
            interact: true,
            look_at: Some(LookAt {
                player_id: None,
                x: Some(point[0]),
                y: Some(point[1]),
                z: Some(point[2]),
            }),
            ..Default::default()
        },
    );
    state.tick(0.05);
    let completed = state.campaign_run_document().unwrap().unwrap();
    let SavedStep::AwaitingMission {
        completed_mission,
        next_mission,
        exit,
    } = &completed.step
    else {
        panic!("fresh supported Use must complete the saved mission")
    };
    assert_eq!(*completed_mission, MissionId::LaunchAuthority);
    assert_eq!(next_mission, "civic_pressure_valve");
    assert_eq!(exit.equipment, exit_before.equipment);
    assert_eq!(completed.remaining_continues, entry.remaining_continues);
    assert_eq!(completed.m13_outcome, entry.m13_outcome);
    assert_eq!(
        completed.m14_outcome,
        Some(M14Outcome {
            depot_secured: true,
            walker_disabled: true,
            jeep_preserved: false,
            on_foot: true
        })
    );
    state
        .mission
        .as_mut()
        .unwrap()
        .m14
        .as_mut()
        .unwrap()
        .machine_fallen = false;
    assert!(
        state.campaign_run_document().is_err(),
        "completion cannot invent the actual fallen-world receipt"
    );
}
