//! Foundry persistence and exact historical boundaries, separate from route play.
use super::*;
use crate::mission::run_file::{M13Outcome, SavedStep};
use crate::protocol::{AmmoPool, WeaponType, M13_WORKER_RESPONSES};

fn foundry_entry() -> RunDocument {
    m12_tests::completed_habitat()
        .promote_next(MissionId::WeightOfPermission, m09_tests::HASHES[12])
        .unwrap()
}

fn completed_foundry() -> RunDocument {
    let mut document = foundry_entry();
    let SavedStep::MissionEntry { entry, .. } = &document.step else {
        unreachable!()
    };
    let mut exit = entry.clone();
    exit.equipment.weapons.push(WeaponType::Rocket);
    exit.equipment.selected = WeaponType::Rocket;
    exit.equipment
        .ammo
        .iter_mut()
        .find(|a| a.pool == AmmoPool::Rockets)
        .unwrap()
        .rounds = 2;
    document.step = SavedStep::AwaitingMission {
        completed_mission: MissionId::WeightOfPermission,
        next_mission: "launch_authority".into(),
        exit,
    };
    document.m13_outcome = Some(M13Outcome {
        workers: Some(M13_WORKER_RESPONSES),
        workers_arrived: [false, true, false],
        hazard_hurt: 11,
        supports_cleared: true,
    });
    document.validate(m09_tests::HASHES[12]).unwrap();
    document
}

#[test]
fn m13_promotion_retains_every_outcome_and_exact_entry_without_episode_refill() {
    let source = m12_tests::completed_habitat();
    let promoted = foundry_entry();
    let SavedStep::AwaitingMission { exit, .. } = &source.step else {
        unreachable!()
    };
    let SavedStep::MissionEntry { mission, entry } = &promoted.step else {
        unreachable!()
    };
    let mut expected = exit.clone();
    expected.equipment.personal_claims.clear();
    assert_eq!(*mission, MissionId::WeightOfPermission);
    assert_eq!(entry, &expected);
    assert!(entry.equipment.weapons.contains(&WeaponType::Arc));
    assert!(!entry.equipment.weapons.contains(&WeaponType::Rocket));
    assert_eq!(
        (
            promoted.remaining_continues,
            promoted.level_start_continues,
            promoted.attempt()
        ),
        (1, 1, 1)
    );
    // Each fixture gets a fresh UUID. Compare the retained shape independently.
    let actual = source
        .promote_next(MissionId::WeightOfPermission, m09_tests::HASHES[12])
        .unwrap();
    assert_eq!(
        (actual.id, actual.body, actual.rules),
        (source.id, source.body, source.rules)
    );
    let mut want = serde_json::to_value(&source).unwrap();
    let mut got = serde_json::to_value(&actual).unwrap();
    for key in ["step", "content_sha256", "level_start_continues"] {
        want.as_object_mut().unwrap().remove(key);
        got.as_object_mut().unwrap().remove(key);
    }
    assert_eq!(got, want, "no carried outcome changes at the foundry edge");
    assert!(actual
        .promote_next(MissionId::WeightOfPermission, m09_tests::HASHES[12])
        .is_err());
    let mut missing = source;
    missing.m12_outcome = None;
    assert!(missing
        .promote_next(MissionId::WeightOfPermission, m09_tests::HASHES[12])
        .is_err());
}

#[test]
fn m13_v15_and_v16_preview_and_atomic_promotion_archive_exact_original_bytes() {
    for version in [15, 16] {
        let source = m12_tests::completed_habitat();
        let mut historical = serde_json::to_value(&source).unwrap();
        historical["version"] = version.into();
        if version == 15 {
            super::super::omit_historical_rockets(&mut historical);
        }
        let bytes = serde_json::to_vec_pretty(&historical).unwrap();
        let directory =
            std::env::temp_dir().join(format!("fragr-foundry-v{version}-{}", Uuid::new_v4()));
        let store = RunStore::open_with_hashes(&directory, m09_tests::HASHES).unwrap();
        fs::write(directory.join(RUN_NAME), &bytes).unwrap();
        let loaded = store.load().unwrap().unwrap();
        assert_eq!(loaded, source);
        assert_eq!(
            fs::read(directory.join(RUN_NAME)).unwrap(),
            bytes,
            "preview never rewrites history"
        );
        assert!(store.needs_upgrade().unwrap());
        let next = loaded
            .promote_next(MissionId::WeightOfPermission, m09_tests::HASHES[12])
            .unwrap();
        assert!(store
            .archive_and_save_before_replace(&loaded, &next, |_| Err(io::Error::other(
                "interrupted foundry edge"
            )))
            .is_err());
        assert_eq!(fs::read(directory.join(RUN_NAME)).unwrap(), bytes);
        let archive = store.archive_and_save(&loaded, &next).unwrap();
        assert_eq!(fs::read(archive).unwrap(), bytes);
        assert_eq!(store.load().unwrap().unwrap(), next);
        assert!(!store.needs_upgrade().unwrap());
        assert_eq!(next.remaining_continues, 1);
        drop(store);
        fs::remove_dir_all(directory).unwrap();
    }
}

#[test]
fn m13_historical_shapes_refuse_future_facts_and_actual_launcher_ownership() {
    for version in [15, 16] {
        let mut base = serde_json::to_value(m12_tests::completed_habitat()).unwrap();
        base["version"] = version.into();
        if version == 15 {
            super::super::omit_historical_rockets(&mut base);
        }
        assert!(matches!(
            RunStore::inspect_bytes(&serde_json::to_vec(&base).unwrap(), m09_tests::HASHES),
            RunProbe::Compatible(_)
        ));
        if version == 16 {
            for missing in [true, false] {
                let mut malformed = base.clone();
                let counts = malformed["step"]["exit"]["equipment"]["ammo"]
                    .as_array_mut()
                    .unwrap();
                if missing {
                    counts.retain(|count| count["pool"] != "rockets");
                } else {
                    counts
                        .iter_mut()
                        .find(|count| count["pool"] == "rockets")
                        .unwrap()["rounds"] = 1.into();
                }
                assert!(matches!(
                    RunStore::inspect_bytes(
                        &serde_json::to_vec(&malformed).unwrap(),
                        m09_tests::HASHES
                    ),
                    RunProbe::Incompatible
                ));
            }
        }
        for outcome in [
            serde_json::Value::Null,
            serde_json::to_value(completed_foundry().m13_outcome.unwrap()).unwrap(),
        ] {
            let mut forged = base.clone();
            forged["m13_outcome"] = outcome;
            assert!(matches!(
                RunStore::inspect_bytes(&serde_json::to_vec(&forged).unwrap(), m09_tests::HASHES),
                RunProbe::Corrupt
            ));
        }
        for selected in [true, false] {
            let mut forged = base.clone();
            if selected {
                forged["step"]["exit"]["equipment"]["selected"] = "rocket".into();
            } else {
                forged["step"]["exit"]["equipment"]["weapons"]
                    .as_array_mut()
                    .unwrap()
                    .push("rocket".into());
            }
            assert!(!matches!(
                RunStore::inspect_bytes(&serde_json::to_vec(&forged).unwrap(), m09_tests::HASHES),
                RunProbe::Compatible(_)
            ));
        }
        let mut future = serde_json::to_value(foundry_entry()).unwrap();
        future["version"] = version.into();
        if version == 15 {
            super::super::omit_historical_rockets(&mut future);
        }
        assert!(matches!(
            RunStore::inspect_bytes(&serde_json::to_vec(&future).unwrap(), m09_tests::HASHES),
            RunProbe::Incompatible
        ));
    }
}

#[test]
fn m13_current_exit_requires_actual_find_and_waits_for_unbuilt_launch_authority() {
    let mut lost_arc = foundry_entry();
    let SavedStep::MissionEntry { entry, .. } = &mut lost_arc.step else {
        unreachable!()
    };
    entry
        .equipment
        .weapons
        .retain(|weapon| *weapon != WeaponType::Arc);
    entry.equipment.selected = WeaponType::Repeater;
    assert!(lost_arc.validate(m09_tests::HASHES[12]).is_err());
    let completed = completed_foundry();
    let bytes = serde_json::to_vec(&completed).unwrap();
    let RunProbe::Compatible(decoded) = RunStore::inspect_bytes(&bytes, m09_tests::HASHES) else {
        panic!("foundry exit")
    };
    assert_eq!(*decoded, completed);
    assert!(serde_json::from_str::<MissionId>("\"launch_authority\"").is_err());
    for mission in CAMPAIGN_MISSIONS {
        assert!(completed
            .promote_next(mission, m09_tests::HASHES[stage_index(mission)])
            .is_err());
    }
    let mut missing = completed.clone();
    missing.m13_outcome = None;
    assert!(missing.validate(m09_tests::HASHES[12]).is_err());
    let mut missing = completed;
    let SavedStep::AwaitingMission { exit, .. } = &mut missing.step else {
        unreachable!()
    };
    exit.equipment.weapons.retain(|w| *w != WeaponType::Rocket);
    exit.equipment.selected = WeaponType::Arc;
    assert!(missing.validate(m09_tests::HASHES[12]).is_err());
    for selected in [true, false] {
        let mut forged = foundry_entry();
        let SavedStep::MissionEntry { entry, .. } = &mut forged.step else {
            unreachable!()
        };
        if selected {
            entry.equipment.selected = WeaponType::Rocket;
            entry.equipment.weapons.push(WeaponType::Rocket);
        } else {
            entry
                .equipment
                .ammo
                .iter_mut()
                .find(|a| a.pool == AmmoPool::Rockets)
                .unwrap()
                .rounds = 1;
        }
        assert!(forged.validate(m09_tests::HASHES[12]).is_err());
    }
}

#[test]
fn m13_worker_responses_never_invent_arrivals_and_receipts_decode_strictly() {
    let actual = completed_foundry().m13_outcome.unwrap();
    assert_eq!(actual.workers_arrived, [false, true, false]);
    let bytes = serde_json::to_vec(&actual).unwrap();
    assert_eq!(
        serde_json::from_slice::<M13Outcome>(&bytes).unwrap(),
        actual
    );
    for index in 0..4 {
        let mut forged = actual.clone();
        if index == 0 {
            forged.workers = None;
        }
        if index == 1 {
            forged.workers_arrived[2] = true;
        }
        if index == 2 {
            forged.workers.as_mut().unwrap().swap(0, 1);
        }
        if index == 3 {
            forged.supports_cleared = false;
        }
        assert!(forged.validate().is_err());
    }
    let mut no_release = actual.clone();
    no_release.workers = None;
    no_release.workers_arrived = [false; 3];
    no_release.validate().unwrap();
    let mut forged = serde_json::to_value(&actual).unwrap();
    forged["workers"] = serde_json::Value::Null;
    assert!(serde_json::from_value::<M13Outcome>(forged).is_err());
    let mut forged = serde_json::to_value(&actual).unwrap();
    forged["future_receipt"] = true.into();
    assert!(serde_json::from_value::<M13Outcome>(forged).is_err());
}

#[test]
fn m13_actual_launcher_find_retries_original_stock_and_habitat_receipt_once() {
    use crate::maps::{AuthoredSource, RuntimeMap};
    use crate::protocol::{Action, CampaignRunStatus, MissionContinue, MissionReady, Role};
    use crate::sim::{GameState, PickupKind, PLAYER_FLOOR_Y};
    let map = AuthoredSource::Mission(MissionId::WeightOfPermission)
        .load()
        .unwrap();
    let hash = RuntimeMap::Authored(map.clone()).content_sha256().unwrap();
    let entry = m12_tests::completed_habitat()
        .promote_next(MissionId::WeightOfPermission, hash)
        .unwrap();
    let mut state = GameState::with_authored_map(map.clone());
    state.load_campaign_run(&entry).unwrap();
    let id = Uuid::new_v4();
    state.add_player(id, "Foundry finite retry".into(), Role::Human);
    assert!(state.acknowledge_mission(
        id,
        MissionReady {
            id: MissionId::WeightOfPermission,
            attempt: 1
        }
    ));
    assert_eq!(state.campaign_run_document().unwrap().unwrap(), entry);
    let stock = state
        .map
        .pickups()
        .into_iter()
        .find(|p| matches!(p.kind, PickupKind::Weapon(WeaponType::Rocket)))
        .unwrap();
    // Arranged placement isolates persistence; the ordinary pickup resolver
    // owns the find. Full-route walking and combat have separate tests.
    let player = state.players.iter_mut().find(|p| p.id == id).unwrap();
    [player.x, player.y, player.z] = [stock.x, stock.floor + PLAYER_FLOOR_Y, stock.z];
    player.vy = 0.0;
    player.clear_input();
    state.tick(0.05);
    state.set_action(
        id,
        Action {
            weapon_swap: Some(WeaponType::Rocket),
            ..Default::default()
        },
    );
    state.tick(0.05);
    let player = state.players.iter().find(|p| p.id == id).unwrap();
    let found = player
        .inventory
        .state(id, player.weapon, state.tick)
        .unwrap();
    let found_revision = player.inventory.revision();
    assert!(found.owns(WeaponType::Rocket));
    assert!(found.ammo(AmmoPool::Rockets) > 0);
    assert_eq!(player.weapon, WeaponType::Rocket);
    assert_eq!(
        state.campaign_run_document().unwrap().unwrap(),
        entry,
        "finding the launcher cannot rewrite entry stock"
    );
    // Arrange independent machinery facts to prove the shared retry restores
    // them along with the real inventory discovery, without rewinding ticks.
    let progress = state.foundry.as_mut().unwrap();
    progress.relay_disabled = true;
    progress.hazard_hurt = 11;
    progress.lift_top += 0.5;
    let before_death = state.tick;
    state.players.iter_mut().find(|p| p.id == id).unwrap().hp = 0;
    state.tick(0.05);
    let pending = state.campaign_run_document().unwrap().unwrap();
    assert!(matches!(
        pending.step,
        SavedStep::PendingContinue {
            mission: MissionId::WeightOfPermission,
            ..
        }
    ));
    assert_eq!(pending.m12_outcome, entry.m12_outcome);
    assert!(pending.m13_outcome.is_none());
    let retry = MissionContinue {
        id: MissionId::WeightOfPermission,
        run_id: entry.id,
        attempt: 1,
    };
    let mut reopened = GameState::with_authored_map(map);
    reopened.load_campaign_run(&pending).unwrap();
    let reopened_id = Uuid::new_v4();
    reopened.add_player(reopened_id, "Reopened foundry retry".into(), Role::Human);
    assert_eq!(reopened.campaign_run_document().unwrap().unwrap(), pending);
    assert!(reopened.continue_mission(reopened_id, retry));
    assert!(state.continue_mission(id, retry));
    assert!(!state.continue_mission(id, retry));
    assert!(state.tick > before_death);
    for (live, owner) in [(&state, id), (&reopened, reopened_id)] {
        let player = live.players.iter().find(|p| p.id == owner).unwrap();
        let restored = player
            .inventory
            .state(owner, player.weapon, live.tick)
            .unwrap();
        assert!(!restored.owns(WeaponType::Rocket));
        assert!(restored.owns(WeaponType::Arc));
        assert_eq!(
            (
                restored.ammo(AmmoPool::Rockets),
                restored.ammo(AmmoPool::Cells),
                restored.remote_mines,
                player.hp,
                player.armor,
                player.weapon
            ),
            (0, 29, 2, 27, 11, WeaponType::Arc)
        );
        let gates = live.map.m13_gates().unwrap();
        let progress = live.foundry.as_ref().unwrap();
        assert!(!progress.relay_disabled);
        assert_eq!(progress.hazard_hurt, 0);
        assert!((progress.lift_top - gates.deck.top).abs() < 0.001);
        assert!(progress.workers.is_none());
        let saved = live.campaign_run_document().unwrap().unwrap();
        assert_eq!(
            (
                saved.remaining_continues,
                saved.level_start_continues,
                saved.attempt()
            ),
            (0, 1, 2)
        );
        assert_eq!(
            (&saved.step, &saved.m12_outcome),
            (&entry.step, &entry.m12_outcome)
        );
    }
    assert!(
        state
            .players
            .iter()
            .find(|p| p.id == id)
            .unwrap()
            .inventory
            .revision()
            > found_revision
    );
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
