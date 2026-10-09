//! Strict habitat carry and portable receipts. These fixtures do not claim combat.
use super::*;
use crate::mission::run_file::{M12Outcome, SavedEntry, SavedStep};
use crate::protocol::{AmmoPool, M12ChallengeState, WeaponType};

fn habitat_entry() -> RunDocument {
    arc_tests::completed_tender()
        .promote_next(MissionId::TermsOfCooperation, m09_tests::HASHES[11])
        .unwrap()
}

fn completed_habitat() -> RunDocument {
    let mut document = habitat_entry();
    let SavedStep::MissionEntry { entry, .. } = &document.step else {
        panic!("habitat entry")
    };
    let mut exit = entry.clone();
    exit.equipment.weapons.push(WeaponType::Arc);
    exit.equipment.selected = WeaponType::Arc;
    exit.equipment
        .ammo
        .iter_mut()
        .find(|a| a.pool == AmmoPool::Cells)
        .unwrap()
        .rounds = 29;
    exit.equipment
        .personal_claims
        .push("m12_actual_arc_find".into());
    exit.hp = 27;
    exit.armor = 11;
    document.step = SavedStep::AwaitingMission {
        completed_mission: MissionId::TermsOfCooperation,
        next_mission: "weight_of_permission".into(),
        exit,
    };
    document.m12_outcome = Some(M12Outcome {
        shelter_opened: true,
        workers_released: false,
        pump_health: [100, 63],
        assessor_wreck_union_kills: 3,
        pumps_intact_at_route_secure: true,
    });
    document.validate(m09_tests::HASHES[11]).unwrap();
    document
}

#[test]
fn m12_promotion_preserves_tender_receipt_finite_entry_and_episode_allowance() {
    let completed = arc_tests::completed_tender();
    let promoted = completed
        .promote_next(MissionId::TermsOfCooperation, m09_tests::HASHES[11])
        .unwrap();
    let SavedStep::AwaitingMission { exit, .. } = &completed.step else {
        panic!("tender exit")
    };
    let SavedStep::MissionEntry { mission, entry } = &promoted.step else {
        panic!("habitat entry")
    };
    let mut expected = exit.clone();
    expected.equipment.personal_claims.clear();
    assert_eq!(*mission, MissionId::TermsOfCooperation);
    assert_eq!(*entry, expected);
    assert_eq!(
        (
            promoted.remaining_continues,
            promoted.level_start_continues,
            promoted.attempt()
        ),
        (1, 1, 1)
    );
    assert_eq!(
        (promoted.id, promoted.body, promoted.rules),
        (completed.id, completed.body, completed.rules)
    );
    assert_eq!(promoted.m03_outcome, completed.m03_outcome);
    assert_eq!(promoted.m04_outcome, completed.m04_outcome);
    assert_eq!(promoted.m05_outcome, completed.m05_outcome);
    assert_eq!(promoted.m06_outcome, completed.m06_outcome);
    assert_eq!(promoted.m08_outcome, completed.m08_outcome);
    assert_eq!(promoted.m09_outcome, completed.m09_outcome);
    assert_eq!(promoted.m10_transit, completed.m10_transit);
    assert_eq!(promoted.m11_outcome, completed.m11_outcome);
    assert!(promoted.m12_outcome.is_none());
    assert!(!entry.equipment.weapons.contains(&WeaponType::Arc));
    assert_eq!(entry.equipment.remote_mines, 2);
    assert_eq!(
        entry
            .equipment
            .ammo
            .iter()
            .find(|a| a.pool == AmmoPool::Cells)
            .unwrap()
            .rounds,
        7
    );
    assert!(promoted
        .promote_next(MissionId::TermsOfCooperation, m09_tests::HASHES[11])
        .is_err());
    let mut invalid = completed.clone();
    invalid.m11_outcome = None;
    assert!(invalid
        .promote_next(MissionId::TermsOfCooperation, m09_tests::HASHES[11])
        .is_err());
    for selected in [false, true] {
        let mut invalid = promoted.clone();
        let SavedStep::MissionEntry { entry, .. } = &mut invalid.step else {
            unreachable!()
        };
        entry.equipment.weapons.push(WeaponType::Arc);
        if selected {
            entry.equipment.selected = WeaponType::Arc;
        }
        assert!(invalid.validate(m09_tests::HASHES[11]).is_err());
    }
    let mut historical = serde_json::to_value(&promoted).unwrap();
    historical["version"] = 14.into();
    historical["rules"]["revision"] = 3.into();
    assert!(matches!(
        RunStore::inspect_bytes(&serde_json::to_vec(&historical).unwrap(), m09_tests::HASHES),
        RunProbe::Incompatible
    ));
}

#[test]
fn m12_portable_challenge_receipts_preserve_same_tick_damage_and_later_damage_distinction() {
    for first_damage in [None, Some(19), Some(20), Some(21)] {
        let live = M12ChallengeState {
            shelter_opened: false,
            workers_released: true,
            pump_health: if first_damage.is_some() {
                [99, 100]
            } else {
                [100, 100]
            },
            assessor_wreck_union_kills: 2,
            first_pump_damage_at: first_damage,
            shelter_route_secured_at: Some(20),
        };
        let outcome = M12Outcome::capture(&live, 25).unwrap();
        assert_eq!(
            outcome.pumps_intact_at_route_secure,
            first_damage.is_none_or(|tick| tick > 20)
        );
        assert_eq!(outcome.pump_health, live.pump_health);
        assert_eq!(outcome.assessor_wreck_union_kills, 2);
        assert!(!outcome.shelter_opened && outcome.workers_released);
        let encoded = serde_json::to_value(&outcome).unwrap();
        assert!(encoded.get("first_pump_damage_at").is_none());
        assert!(encoded.get("shelter_route_secured_at").is_none());
        assert_eq!(
            serde_json::from_value::<M12Outcome>(encoded).unwrap(),
            outcome
        );
    }
    let mut live = M12ChallengeState::default();
    assert!(M12Outcome::capture(&live, 25).is_err());
    live.shelter_route_secured_at = Some(26);
    assert!(M12Outcome::capture(&live, 25).is_err());
    let mut impossible = completed_habitat().m12_outcome.unwrap();
    impossible.pump_health = [100, 100];
    impossible.pumps_intact_at_route_secure = false;
    assert!(impossible.validate().is_err());
}

#[test]
fn m12_current_save_requires_exact_completed_outcome_and_retains_real_arc_counts() {
    let completed = completed_habitat();
    let bytes = serde_json::to_vec(&completed).unwrap();
    let RunProbe::Compatible(read) = RunStore::inspect_bytes(&bytes, m09_tests::HASHES) else {
        panic!("completed habitat")
    };
    assert_eq!(*read, completed);
    assert!(serde_json::from_str::<MissionId>("\"weight_of_permission\"").is_err());
    for malformed in [
        serde_json::Value::Null,
        serde_json::json!({}),
        serde_json::json!({"shelter_opened":true,"workers_released":false,"pump_health":[101,63],"assessor_wreck_union_kills":3,"pumps_intact_at_route_secure":true}),
        serde_json::json!({"shelter_opened":true,"workers_released":false,"pump_health":[100,63],"assessor_wreck_union_kills":4,"pumps_intact_at_route_secure":true}),
        serde_json::json!({"shelter_opened":true,"workers_released":false,"pump_health":[100,63],"assessor_wreck_union_kills":3,"pumps_intact_at_route_secure":true,"shelter_route_secured_at":20}),
    ] {
        let mut value = serde_json::to_value(&completed).unwrap();
        value["m12_outcome"] = malformed;
        assert!(!matches!(
            RunStore::inspect_bytes(&serde_json::to_vec(&value).unwrap(), m09_tests::HASHES),
            RunProbe::Compatible(_)
        ));
    }
    let mut missing = completed.clone();
    missing.m12_outcome = None;
    assert!(missing.validate(m09_tests::HASHES[11]).is_err());
    let mut early = habitat_entry();
    early.m12_outcome = completed.m12_outcome.clone();
    assert!(early.validate(m09_tests::HASHES[11]).is_err());
    let mut absent_find = completed.clone();
    let SavedStep::AwaitingMission { exit, .. } = &mut absent_find.step else {
        unreachable!()
    };
    exit.equipment
        .weapons
        .retain(|weapon| *weapon != WeaponType::Arc);
    exit.equipment.selected = WeaponType::Repeater;
    assert!(absent_find.validate(m09_tests::HASHES[11]).is_err());

    let directory = std::env::temp_dir().join(format!("fragr-m12-receipt-{}", Uuid::new_v4()));
    let store = RunStore::open_with_hashes(&directory, m09_tests::HASHES).unwrap();
    store.save(&completed).unwrap();
    assert_eq!(store.load().unwrap().unwrap(), completed);
    drop(store);
    let reopened = RunStore::open_with_hashes(&directory, m09_tests::HASHES).unwrap();
    let read = reopened.load().unwrap().unwrap();
    let SavedStep::AwaitingMission {
        exit: SavedEntry {
            equipment,
            hp,
            armor,
        },
        ..
    } = &read.step
    else {
        unreachable!()
    };
    assert_eq!(
        (*hp, *armor, equipment.selected, equipment.remote_mines),
        (27, 11, WeaponType::Arc, 2)
    );
    assert_eq!(
        equipment
            .ammo
            .iter()
            .find(|a| a.pool == AmmoPool::Cells)
            .unwrap()
            .rounds,
        29
    );
    assert_eq!(read.m11_outcome, completed.m11_outcome);
    assert_eq!(read.m12_outcome, completed.m12_outcome);
    assert_eq!(read.remaining_continues, 1);
    drop(reopened);
    fs::remove_dir_all(directory).unwrap();
}

#[test]
fn m12_v14_to_live_promotion_archives_original_bytes_and_recovers_interrupted_replace() {
    let source = arc_tests::completed_tender();
    let promoted = source
        .promote_next(MissionId::TermsOfCooperation, m09_tests::HASHES[11])
        .unwrap();
    let mut legacy = serde_json::to_value(&source).unwrap();
    legacy["version"] = 14.into();
    legacy["rules"]["revision"] = 3.into();
    let mut bytes = serde_json::to_vec_pretty(&legacy).unwrap();
    bytes.extend_from_slice(b"\n\t \n");
    let directory = std::env::temp_dir().join(format!("fragr-m12-promotion-{}", Uuid::new_v4()));
    let store = RunStore::open_with_hashes(&directory, m09_tests::HASHES).unwrap();
    assert!(RunStore::open_with_hashes(&directory, m09_tests::HASHES).is_err());
    fs::write(directory.join(RUN_NAME), &bytes).unwrap();
    let loaded = store.load().unwrap().unwrap();
    assert_eq!(loaded, source);
    assert!(store
        .archive_and_save_before_replace(&loaded, &promoted, |_| Err(io::Error::other(
            "interrupted M12 edge"
        )))
        .is_err());
    assert_eq!(fs::read(directory.join(RUN_NAME)).unwrap(), bytes);
    let archived = store.archive_and_save(&loaded, &promoted).unwrap();
    assert_eq!(fs::read(archived).unwrap(), bytes);
    assert_eq!(store.load().unwrap().unwrap(), promoted);
    assert!(!store.needs_upgrade().unwrap());
    assert!(store.archive_and_save(&loaded, &promoted).is_err());
    drop(store);
    let reopened = RunStore::open_with_hashes(&directory, m09_tests::HASHES).unwrap();
    assert_eq!(reopened.load().unwrap().unwrap(), promoted);
    assert_eq!(
        fs::read_dir(&directory)
            .unwrap()
            .filter_map(Result::ok)
            .filter(|p| p.file_name().to_string_lossy().starts_with("run.prior-"))
            .count(),
        1
    );
    drop(reopened);
    fs::remove_dir_all(directory).unwrap();
}

#[test]
fn m12_actual_arc_find_is_not_rewritten_into_entry_and_real_continue_restores_it() {
    use crate::maps::{AuthoredSource, RuntimeMap};
    use crate::protocol::{Action, CampaignRunStatus, MissionContinue, MissionReady, Role};
    use crate::sim::{GameState, PickupKind, PLAYER_FLOOR_Y};
    let map = AuthoredSource::Mission(MissionId::TermsOfCooperation)
        .load()
        .unwrap();
    let hash = RuntimeMap::Authored(map.clone()).content_sha256().unwrap();
    let entry = arc_tests::completed_tender()
        .promote_next(MissionId::TermsOfCooperation, hash)
        .unwrap();
    let mut state = GameState::with_authored_map(map.clone());
    state.load_campaign_run(&entry).unwrap();
    let id = Uuid::new_v4();
    state.add_player(id, "Habitat finite retry".into(), Role::Human);
    assert!(state.acknowledge_mission(
        id,
        MissionReady {
            id: MissionId::TermsOfCooperation,
            attempt: 1
        }
    ));
    assert_eq!(state.campaign_run_document().unwrap().unwrap(), entry);
    let stock = state
        .map
        .pickups()
        .into_iter()
        .find(|p| matches!(p.kind, PickupKind::Weapon(WeaponType::Arc)))
        .unwrap();
    // Place only to isolate persistence. Actual pickup resolution still owns
    // the grant; the separate lesson and mission tests own walking and combat.
    let player = state.players.iter_mut().find(|p| p.id == id).unwrap();
    [player.x, player.y, player.z] = [stock.x, stock.floor + PLAYER_FLOOR_Y, stock.z];
    player.vy = 0.0;
    player.clear_input();
    for _ in 0..8 {
        state.tick(0.05);
    }
    state.set_action(
        id,
        Action {
            weapon_swap: Some(WeaponType::Arc),
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
    assert!(found.owns(WeaponType::Arc));
    assert_eq!(found.ammo(AmmoPool::Cells), 47);
    assert_eq!(player.weapon, WeaponType::Arc);
    assert_eq!(
        state.campaign_run_document().unwrap().unwrap(),
        entry,
        "actual discovery does not rewrite mission-start stock"
    );
    let before_death = state.tick;
    state.players.iter_mut().find(|p| p.id == id).unwrap().hp = 0;
    state.tick(0.05);
    let pending = state.campaign_run_document().unwrap().unwrap();
    assert!(matches!(
        pending.step,
        SavedStep::PendingContinue {
            mission: MissionId::TermsOfCooperation,
            ..
        }
    ));
    assert_eq!(pending.m11_outcome, entry.m11_outcome);
    assert!(pending.m12_outcome.is_none());
    let retry = MissionContinue {
        id: MissionId::TermsOfCooperation,
        run_id: entry.id,
        attempt: 1,
    };
    let mut reopened = GameState::with_authored_map(map);
    reopened.load_campaign_run(&pending).unwrap();
    let reopened_id = Uuid::new_v4();
    reopened.add_player(reopened_id, "Reopened habitat retry".into(), Role::Human);
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
        assert!(!restored.owns(WeaponType::Arc));
        assert_eq!(
            (
                restored.ammo(AmmoPool::Cells),
                player.hp,
                player.armor,
                player.weapon
            ),
            (7, 37, 19, WeaponType::Repeater)
        );
        assert_eq!(restored.remote_mines, 2);
        assert_eq!(
            live.mission_state().unwrap().m12.unwrap().challenges,
            M12ChallengeState::default()
        );
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
            (&saved.step, &saved.m11_outcome),
            (&entry.step, &entry.m11_outcome)
        );
    }
    let player = state.players.iter().find(|p| p.id == id).unwrap();
    assert!(player.inventory.revision() > found_revision);
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
    assert_eq!(
        state
            .campaign_run_document()
            .unwrap()
            .unwrap()
            .remaining_continues,
        0
    );
}
