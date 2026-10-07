use super::*;
use crate::inventory::Inventory;
use crate::mission::run_file::{M03Outcome, M04Outcome, M05Outcome, SavedEntry, SavedStep};
use crate::protocol::{BodyKind, CampaignDifficulty, CampaignRules, EquipmentPolicy, WeaponType};

const HASHES: ContentHashes = [
    [1; 32], [2; 32], [3; 32], [4; 32], [5; 32], [6; 32], [7; 32], [8; 32], [101; 32], [102; 32],
    [103; 32],
];

fn completed_workshop() -> RunDocument {
    let mut document = RunDocument::new(
        Uuid::new_v4(),
        CampaignRules::new(CampaignDifficulty::Severe),
        HASHES[4],
    );
    let mut inventory = Inventory::new(EquipmentPolicy::Discovery);
    inventory.grant_weapon(WeaponType::Flechette);
    inventory.grant_weapon(WeaponType::Scatter);
    inventory.grant_ammo(crate::protocol::AmmoPool::Bullets, 17);
    let mut equipment = inventory.saved_equipment(WeaponType::Flechette).unwrap();
    equipment.grenades = 2;
    equipment.personal_claims = vec!["old_workshop_grant".into()];
    document.remaining_continues = 0;
    document.level_start_continues = 2;
    document.body = Some(BodyKind::Synthetic);
    document.step = SavedStep::AwaitingMission {
        completed_mission: MissionId::NoForwardingAddress,
        next_mission: "port_of_entry".into(),
        exit: SavedEntry {
            hp: 63,
            armor: 21,
            equipment,
        },
    };
    document.m03_outcome = Some(M03Outcome {
        liberated_cars: vec!["car_b".into(), "car_a".into()],
    });
    document.m04_outcome = Some(M04Outcome {
        rescued_patients: vec!["patient_b".into()],
        photos_completed: 2,
    });
    document.m05_outcome = Some(M05Outcome {
        released_workers: vec![
            "workshop_agent_b".into(),
            "splice".into(),
            "workshop_agent_a".into(),
        ],
        evacuated_workers: vec!["workshop_agent_b".into()],
    });
    document.validate(HASHES[4]).unwrap();
    document
}

fn historical_bytes(document: &RunDocument) -> Vec<u8> {
    let mut value = serde_json::to_value(document).unwrap();
    value["version"] = 6.into();
    super::super::remove_historical_mines(&mut value);
    serde_json::to_vec_pretty(&value).unwrap()
}

fn probe(bytes: &[u8]) -> RunProbe {
    RunStore::inspect_bytes(bytes, HASHES)
}

fn open(directory: &Path) -> RunStore {
    RunStore::open_with_hashes(directory, HASHES).unwrap()
}

#[test]
fn historical_v6_preview_keeps_counts_then_atomic_promotion_refills_once() {
    let directory = std::env::temp_dir().join(format!("fragr-m06-migration-{}", Uuid::new_v4()));
    let source = completed_workshop();
    let bytes = historical_bytes(&source);
    let store = open(&directory);
    fs::write(directory.join(RUN_NAME), &bytes).unwrap();
    let loaded = store.load().unwrap().unwrap();
    assert_eq!(loaded, source);
    assert_eq!(loaded.remaining_continues, 0);
    assert_eq!(fs::read(directory.join(RUN_NAME)).unwrap(), bytes);
    assert!(store.needs_upgrade().unwrap());
    assert!(open_lock_refused(&directory));
    let promoted = loaded
        .promote_next(MissionId::PortOfEntry, HASHES[5])
        .unwrap();
    assert_eq!(promoted.remaining_continues, 3);
    assert_eq!(promoted.level_start_continues, 3);
    assert_eq!(promoted.attempt(), 1);
    assert_eq!(promoted.body, source.body);
    assert_eq!(promoted.rules, source.rules);
    assert_eq!(promoted.id, source.id);
    assert_eq!(promoted.m03_outcome, source.m03_outcome);
    assert_eq!(promoted.m04_outcome, source.m04_outcome);
    assert_eq!(promoted.m05_outcome, source.m05_outcome);
    let SavedStep::MissionEntry { entry, .. } = &promoted.step else {
        panic!("missing lunar entry")
    };
    assert_eq!(
        (entry.hp, entry.armor, entry.equipment.grenades),
        (63, 21, 2)
    );
    assert!(entry.equipment.personal_claims.is_empty());
    let SavedStep::AwaitingMission { exit, .. } = &source.step else {
        panic!("missing prior exit")
    };
    assert_eq!(entry.equipment.selected, exit.equipment.selected);
    assert_eq!(entry.equipment.weapons, exit.equipment.weapons);
    assert_eq!(entry.equipment.ammo, exit.equipment.ammo);
    let failed = store.archive_and_save_before_replace(&source, &promoted, |_| {
        Err(io::Error::other("injected replace failure"))
    });
    assert!(failed.is_err());
    assert_eq!(fs::read(directory.join(RUN_NAME)).unwrap(), bytes);
    let archive = store.archive_and_save(&source, &promoted).unwrap();
    assert_eq!(fs::read(archive).unwrap(), bytes);
    assert!(!store.needs_upgrade().unwrap());
    assert!(store.archive_and_save(&source, &promoted).is_err());
    assert!(promoted
        .promote_next(MissionId::PortOfEntry, HASHES[5])
        .is_err());
    let mut spent = promoted;
    spent.remaining_continues = 1;
    store.save(&spent).unwrap();
    drop(store);
    let reopened = open(&directory);
    assert_eq!(reopened.load().unwrap().unwrap(), spent);
    assert_eq!(spent.attempt(), 3);
    drop(reopened);
    fs::remove_dir_all(directory).unwrap();
}

fn open_lock_refused(directory: &Path) -> bool {
    RunStore::open_with_hashes(directory, HASHES).is_err()
}

#[test]
fn v6_rejects_future_mission_outcome_and_malformed_equipment_without_rewriting() {
    let original: serde_json::Value =
        serde_json::from_slice(&historical_bytes(&completed_workshop())).unwrap();
    let mut future = original.clone();
    future["step"]["completed_mission"] = "port_of_entry".into();
    future["step"]["next_mission"] = "declared_goods".into();
    assert!(matches!(
        probe(&serde_json::to_vec(&future).unwrap()),
        RunProbe::Incompatible
    ));
    for (path, forged) in [
        (
            "m06_outcome",
            serde_json::json!({"prisoner_route_marked": true}),
        ),
        ("unexpected", serde_json::json!(true)),
    ] {
        let mut value = original.clone();
        value[path] = forged;
        assert!(matches!(
            probe(&serde_json::to_vec(&value).unwrap()),
            RunProbe::Corrupt
        ));
    }
    let mut missing = original.clone();
    missing["step"]["exit"]["equipment"]
        .as_object_mut()
        .unwrap()
        .remove("grenades");
    assert!(matches!(
        probe(&serde_json::to_vec(&missing).unwrap()),
        RunProbe::Corrupt
    ));
    for invalid in [
        serde_json::json!(7),
        serde_json::json!(-1),
        serde_json::json!("2"),
    ] {
        let mut value = original.clone();
        value["step"]["exit"]["equipment"]["grenades"] = invalid;
        assert!(!matches!(
            probe(&serde_json::to_vec(&value).unwrap()),
            RunProbe::Compatible(_)
        ));
    }
    let mut wrong_hash = original.clone();
    wrong_hash["content_sha256"] = serde_json::to_value([9; 32]).unwrap();
    assert!(matches!(
        probe(&serde_json::to_vec(&wrong_hash).unwrap()),
        RunProbe::Incompatible
    ));
    let mut invalid_subset = original;
    invalid_subset["m05_outcome"]["evacuated_workers"] = serde_json::json!(["unknown_worker"]);
    assert!(matches!(
        probe(&serde_json::to_vec(&invalid_subset).unwrap()),
        RunProbe::Incompatible
    ));
}

#[test]
fn m06_route_outcome_is_required_only_at_completed_edge_and_failed_runs_do_not_refill() {
    let entry = completed_workshop()
        .promote_next(MissionId::PortOfEntry, HASHES[5])
        .unwrap();
    let SavedStep::MissionEntry { entry: saved, .. } = entry.step.clone() else {
        panic!("missing entry")
    };
    let mut document = entry;
    document.m06_outcome = Some(crate::mission::run_file::M06Outcome {
        prisoner_route_marked: true,
    });
    assert!(document.validate(HASHES[5]).is_err());
    document.step = SavedStep::AwaitingMission {
        completed_mission: MissionId::PortOfEntry,
        next_mission: "declared_goods".into(),
        exit: saved.clone(),
    };
    document.validate(HASHES[5]).unwrap();
    document.m06_outcome = None;
    assert!(document.validate(HASHES[5]).is_err());
    document.step = SavedStep::Failed {
        mission: MissionId::PortOfEntry,
        entry: saved.clone(),
    };
    document.remaining_continues = 0;
    document.validate(HASHES[5]).unwrap();
    assert!(document
        .promote_next(MissionId::PortOfEntry, HASHES[5])
        .is_err());
    document.step = SavedStep::Abandoned {
        mission: MissionId::PortOfEntry,
        entry: saved,
    };
    document.validate(HASHES[5]).unwrap();
    assert!(document
        .promote_next(MissionId::PortOfEntry, HASHES[5])
        .is_err());
}
