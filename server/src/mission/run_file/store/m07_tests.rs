use super::*;
use crate::inventory::Inventory;
use crate::mission::run_file::{
    M03Outcome, M04Outcome, M05Outcome, M06Outcome, SavedEntry, SavedStep,
};
use crate::protocol::{BodyKind, CampaignDifficulty, CampaignRules, EquipmentPolicy, WeaponType};

const HASHES: ContentHashes = [
    [1; 32], [2; 32], [3; 32], [4; 32], [5; 32], [6; 32], [7; 32], [8; 32], [101; 32], [102; 32],
    [103; 32], [104; 32], [105; 32], [106; 32], [107; 32], [108; 32], [109; 32], [110; 32],
    [111; 32],
];

pub(super) fn exit(sniper: bool) -> SavedEntry {
    let mut inventory = Inventory::new(EquipmentPolicy::Discovery);
    inventory.grant_weapon(WeaponType::Flechette);
    inventory.grant_weapon(WeaponType::Scatter);
    inventory.grant_weapon(WeaponType::Rail);
    if sniper {
        inventory.grant_weapon(WeaponType::Sniper);
    }
    let selected = if sniper {
        WeaponType::Sniper
    } else {
        WeaponType::Rail
    };
    let mut equipment = inventory.saved_equipment(selected).unwrap();
    equipment.grenades = 1;
    equipment.personal_claims = vec!["old_lunar_grant".into()];
    SavedEntry {
        hp: 58,
        armor: 30,
        equipment,
    }
}

/// A completed M06 run waiting at the level 7 edge, with every earlier outcome.
pub(super) fn completed_port() -> RunDocument {
    let mut document = RunDocument::new(
        Uuid::new_v4(),
        CampaignRules::new(CampaignDifficulty::Standard),
        HASHES[5],
    );
    document.remaining_continues = 1;
    document.level_start_continues = 3;
    document.body = Some(BodyKind::Human);
    document.step = SavedStep::AwaitingMission {
        completed_mission: MissionId::PortOfEntry,
        next_mission: "declared_goods".into(),
        exit: exit(false),
    };
    document.m03_outcome = Some(M03Outcome {
        liberated_cars: vec!["car_a".into()],
    });
    document.m04_outcome = Some(M04Outcome {
        rescued_patients: vec!["patient_a".into()],
        photos_completed: 1,
    });
    document.m05_outcome = Some(M05Outcome {
        released_workers: vec![
            "splice".into(),
            "workshop_agent_a".into(),
            "workshop_agent_b".into(),
        ],
        evacuated_workers: vec!["splice".into()],
    });
    document.m06_outcome = Some(M06Outcome {
        prisoner_route_marked: true,
    });
    document.validate(HASHES[5]).unwrap();
    document
}

fn open(directory: &Path) -> RunStore {
    RunStore::open_with_hashes(directory, HASHES).unwrap()
}

#[test]
fn completed_port_promotes_into_m07_without_a_refill() {
    let directory = std::env::temp_dir().join(format!("fragr-m07-promotion-{}", Uuid::new_v4()));
    let source = completed_port();
    let store = open(&directory);
    store.save(&source).unwrap();
    let bytes = fs::read(directory.join(RUN_NAME)).unwrap();
    let loaded = store.load().unwrap().unwrap();
    assert_eq!(loaded, source);
    let promoted = loaded
        .promote_next(MissionId::DeclaredGoods, HASHES[6])
        .unwrap();
    // Episode II was already refilled entering M06; M07 keeps what M06 left.
    assert_eq!(promoted.remaining_continues, 1);
    assert_eq!(promoted.level_start_continues, 1);
    assert_eq!(promoted.attempt(), 1);
    assert_eq!(
        (promoted.id, promoted.body, promoted.rules),
        (source.id, source.body, source.rules)
    );
    assert_eq!(promoted.m03_outcome, source.m03_outcome);
    assert_eq!(promoted.m04_outcome, source.m04_outcome);
    assert_eq!(promoted.m05_outcome, source.m05_outcome);
    assert_eq!(
        promoted.m06_outcome, source.m06_outcome,
        "M06 route retained"
    );
    let SavedStep::MissionEntry { mission, entry } = &promoted.step else {
        panic!("missing town entry")
    };
    assert_eq!(*mission, MissionId::DeclaredGoods);
    assert_eq!(
        (entry.hp, entry.armor, entry.equipment.grenades),
        (58, 30, 1)
    );
    assert!(entry.equipment.personal_claims.is_empty());
    assert!(!entry.equipment.weapons.contains(&WeaponType::Sniper));
    let failed = store.save_with_sync(
        &promoted,
        |_| Err(io::Error::other("injected replace failure")),
        sync_directory,
    );
    assert!(failed.is_err());
    assert_eq!(fs::read(directory.join(RUN_NAME)).unwrap(), bytes);
    store.save(&promoted).unwrap();
    assert!(promoted
        .promote_next(MissionId::DeclaredGoods, HASHES[6])
        .is_err());
    drop(store);
    let reopened = open(&directory);
    assert_eq!(reopened.load().unwrap().unwrap(), promoted);
    drop(reopened);
    fs::remove_dir_all(directory).unwrap();
}

#[test]
fn completed_m06_and_m07_entry_refuse_a_sniper() {
    let source = completed_port();
    let mut sniper = serde_json::to_value(&source).unwrap();
    sniper["step"]["exit"] = serde_json::to_value(exit(true)).unwrap();
    let bytes = serde_json::to_vec(&sniper).unwrap();
    assert!(matches!(
        RunStore::inspect_bytes(&bytes, HASHES),
        RunProbe::Incompatible
    ));
    let mut entry = source
        .promote_next(MissionId::DeclaredGoods, HASHES[6])
        .unwrap();
    entry.step = SavedStep::MissionEntry {
        mission: MissionId::DeclaredGoods,
        entry: exit(true),
    };
    assert!(
        entry.validate(HASHES[6]).is_err(),
        "M07 entry never carries a Sniper"
    );
    let mut missing_route = source
        .promote_next(MissionId::DeclaredGoods, HASHES[6])
        .unwrap();
    missing_route.m06_outcome = None;
    assert!(missing_route.validate(HASHES[6]).is_err());
}

#[test]
fn completed_m07_carries_its_sniper_and_every_outcome_to_the_level_eight_edge() {
    let mut town = completed_port()
        .promote_next(MissionId::DeclaredGoods, HASHES[6])
        .unwrap();
    town.step = SavedStep::AwaitingMission {
        completed_mission: MissionId::DeclaredGoods,
        next_mission: "custodian_of_record".into(),
        exit: exit(true),
    };
    town.validate(HASHES[6]).unwrap();
    let bytes = serde_json::to_vec(&town).unwrap();
    let RunProbe::Compatible(read) = RunStore::inspect_bytes(&bytes, HASHES) else {
        panic!("pending level 8 edge is a compatible run")
    };
    assert_eq!(*read, town);
    assert_eq!(
        read.m06_outcome,
        Some(M06Outcome {
            prisoner_route_marked: true
        })
    );
    let mut wrong = town.clone();
    if let SavedStep::AwaitingMission { next_mission, .. } = &mut wrong.step {
        *next_mission = "declared_goods".into();
    }
    assert!(wrong.validate(HASHES[6]).is_err());
    let mut lost = town.clone();
    lost.m05_outcome = None;
    assert!(lost.validate(HASHES[6]).is_err());
    assert!(
        town.promote_next(MissionId::DeclaredGoods, HASHES[6])
            .is_err(),
        "completed town cannot promote to town again"
    );
}
