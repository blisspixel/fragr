use super::*;
use crate::mission::run_file::{M08Outcome, SavedStep};

const HASHES: ContentHashes = [
    [1; 32], [2; 32], [3; 32], [4; 32], [5; 32], [6; 32], [7; 32], [8; 32],
];

fn completed_archive() -> RunDocument {
    let mut document = super::m07_tests::completed_port()
        .promote_next(MissionId::DeclaredGoods, HASHES[6])
        .unwrap();
    document.step = SavedStep::AwaitingMission {
        completed_mission: MissionId::DeclaredGoods,
        next_mission: "custodian_of_record".into(),
        exit: super::m07_tests::exit(true),
    };
    document = document
        .promote_next(MissionId::CustodianOfRecord, HASHES[7])
        .unwrap();
    let mut exit = super::m07_tests::exit(true);
    exit.hp = 39;
    exit.armor = 17;
    exit.equipment.grenades = 2;
    exit.equipment.proximity_mines = 3;
    document.step = SavedStep::AwaitingMission {
        completed_mission: MissionId::CustodianOfRecord,
        next_mission: "passenger_manifest".into(),
        exit,
    };
    document.m08_outcome = Some(M08Outcome::Recorded {
        custody_released: true,
        recovered_mind_secured: true,
        captives_evacuated: true,
    });
    document.validate(HASHES[7]).unwrap();
    document
}

fn v9_bytes(document: &RunDocument) -> Vec<u8> {
    let mut value = serde_json::to_value(document).unwrap();
    value["version"] = 9.into();
    value.as_object_mut().unwrap().remove("m08_outcome");
    let mut bytes = serde_json::to_vec_pretty(&value).unwrap();
    bytes.extend_from_slice(b"\n \n");
    bytes
}

#[test]
fn strict_v9_archive_completion_retains_unknown_choices_and_exact_source_bytes() {
    let directory = std::env::temp_dir().join(format!("fragr-v9-custody-{}", Uuid::new_v4()));
    let store = RunStore::open_with_hashes(&directory, HASHES).unwrap();
    let source = completed_archive();
    let bytes = v9_bytes(&source);
    fs::write(directory.join(RUN_NAME), &bytes).unwrap();
    let preview = RunStore::preview_with_hashes(&directory, HASHES)
        .unwrap()
        .unwrap();
    let mut expected = source.clone();
    expected.m08_outcome = Some(M08Outcome::HistoricalUnrecorded {});
    assert_eq!(preview, expected);
    assert_eq!(fs::read(directory.join(RUN_NAME)).unwrap(), bytes);
    assert!(store.needs_upgrade().unwrap());
    assert!(store
        .archive_and_save_before_replace(&preview, &preview, |_| {
            Err(io::Error::other("injected v9 replacement failure"))
        })
        .is_err());
    assert_eq!(fs::read(directory.join(RUN_NAME)).unwrap(), bytes);
    let archive = store.archive_and_save(&preview, &preview).unwrap();
    assert_eq!(fs::read(archive).unwrap(), bytes);
    assert_eq!(store.load().unwrap().unwrap(), expected);
    assert!(!store.needs_upgrade().unwrap());
    assert_eq!(expected.m03_outcome, source.m03_outcome);
    assert_eq!(expected.m04_outcome, source.m04_outcome);
    assert_eq!(expected.m05_outcome, source.m05_outcome);
    assert_eq!(expected.m06_outcome, source.m06_outcome);
    assert_eq!(
        expected.step, source.step,
        "actual finite counts never default"
    );
    drop(store);
    let reopened = RunStore::open_with_hashes(&directory, HASHES).unwrap();
    assert_eq!(reopened.load().unwrap().unwrap(), expected);
    drop(reopened);
    fs::remove_dir_all(directory).unwrap();
}

#[test]
fn historical_v9_refuses_outcome_fields_even_null_and_does_not_guess_entry_choices() {
    let source = completed_archive();
    let value: serde_json::Value = serde_json::from_slice(&v9_bytes(&source)).unwrap();
    for outcome in [
        serde_json::Value::Null,
        serde_json::json!({"kind":"historical_unrecorded"}),
        serde_json::json!({"kind":"recorded","custody_released":false,
            "recovered_mind_secured":false,"captives_evacuated":false}),
    ] {
        let mut forged = value.clone();
        forged["m08_outcome"] = outcome;
        assert!(matches!(
            RunStore::inspect_bytes(&serde_json::to_vec(&forged).unwrap(), HASHES),
            RunProbe::Corrupt
        ));
    }
    let mut entry = super::m07_tests::completed_port()
        .promote_next(MissionId::DeclaredGoods, HASHES[6])
        .unwrap();
    entry.step = SavedStep::AwaitingMission {
        completed_mission: MissionId::DeclaredGoods,
        next_mission: "custodian_of_record".into(),
        exit: super::m07_tests::exit(true),
    };
    let entry = entry
        .promote_next(MissionId::CustodianOfRecord, HASHES[7])
        .unwrap();
    let RunProbe::Compatible(upgraded) = RunStore::inspect_bytes(&v9_bytes(&entry), HASHES) else {
        panic!("valid v9 M08 entry refused")
    };
    assert_eq!(*upgraded, entry);
    assert!(
        upgraded.m08_outcome.is_none(),
        "an unfinished M08 has no outcome"
    );
}

#[test]
fn current_custody_outcomes_require_release_and_refuse_extra_or_missing_facts() {
    let document = completed_archive();
    for custody_released in [false, true] {
        for recovered_mind_secured in [false, true] {
            for captives_evacuated in [false, true] {
                let mut candidate = document.clone();
                candidate.m08_outcome = Some(M08Outcome::Recorded {
                    custody_released,
                    recovered_mind_secured,
                    captives_evacuated,
                });
                assert_eq!(
                    candidate.validate(HASHES[7]).is_ok(),
                    custody_released || !captives_evacuated
                );
            }
        }
    }
    for malformed in [
        serde_json::json!({"kind":"historical_unrecorded","custody_released":false}),
        serde_json::json!({"kind":"historical_unrecorded","historical_version":9}),
        serde_json::json!({"kind":"recorded","custody_released":true,"recovered_mind_secured":true}),
        serde_json::json!({"kind":"recorded","custody_released":true,"recovered_mind_secured":true,
            "captives_evacuated":true,"mind_restored":true}),
    ] {
        let mut value = serde_json::to_value(&document).unwrap();
        value["m08_outcome"] = malformed;
        assert!(matches!(
            RunStore::inspect_bytes(&serde_json::to_vec(&value).unwrap(), HASHES),
            RunProbe::Corrupt
        ));
    }
    let mut missing = document.clone();
    missing.m08_outcome = None;
    assert!(missing.validate(HASHES[7]).is_err());
    let mut premature = RunDocument::new(document.id, document.rules, HASHES[0]);
    premature.m08_outcome = Some(M08Outcome::HistoricalUnrecorded {});
    assert!(premature.validate(HASHES[0]).is_err());
}
