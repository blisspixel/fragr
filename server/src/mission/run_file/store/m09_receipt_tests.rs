use super::*;
use crate::mission::run_file::{M09Outcome, SavedStep};
use crate::protocol::MissionId;
use m09_tests::HASHES;

pub(super) fn completed_berth(edda: bool, splice: bool) -> RunDocument {
    let mut archive = m09_tests::completed_archive();
    if !edda {
        archive
            .m04_outcome
            .as_mut()
            .unwrap()
            .rescued_patients
            .clear();
    }
    if !splice {
        archive
            .m05_outcome
            .as_mut()
            .unwrap()
            .evacuated_workers
            .clear();
    }
    let mut document = archive
        .promote_next(MissionId::PassengerManifest, HASHES[8])
        .unwrap();
    let SavedStep::MissionEntry { entry, .. } = &document.step else {
        panic!("M09 entry")
    };
    document.step = SavedStep::AwaitingMission {
        completed_mission: MissionId::PassengerManifest,
        next_mission: "common_carrier".into(),
        exit: entry.clone(),
    };
    let mut released_crew = vec!["tern".into(), "berth_crew_a".into(), "berth_crew_b".into()];
    if edda {
        released_crew.push("edda".into());
    }
    if splice {
        released_crew.push("splice".into());
    }
    document.m09_outcome = Some(M09Outcome::Recorded {
        released_crew,
        aboard_at_departure: vec![],
    });
    document.validate(HASHES[8]).unwrap();
    document
}

#[test]
fn m09_receipt_v10_v11_completed_upgrade_archives_unknown_without_inventing_crew() {
    for version in [10, 11] {
        let source = completed_berth(true, true);
        let mut value = serde_json::to_value(&source).unwrap();
        value["version"] = version.into();
        value.as_object_mut().unwrap().remove("m09_outcome");
        let mut bytes = serde_json::to_vec_pretty(&value).unwrap();
        bytes.extend_from_slice(b"\n  \n");
        let directory =
            std::env::temp_dir().join(format!("fragr-m09-v{version}-{}", Uuid::new_v4()));
        let store = RunStore::open_with_hashes(&directory, HASHES).unwrap();
        fs::write(directory.join(RUN_NAME), &bytes).unwrap();
        let mut expected = source.clone();
        expected.m09_outcome = Some(M09Outcome::HistoricalUnrecorded {});
        let loaded = store.load().unwrap().unwrap();
        assert_eq!(loaded, expected);
        assert!(store.needs_upgrade().unwrap());
        assert_eq!(fs::read(directory.join(RUN_NAME)).unwrap(), bytes);
        assert!(store
            .archive_and_save_before_replace(&loaded, &loaded, |_| {
                Err(io::Error::other(
                    "injected crew-receipt replacement failure",
                ))
            })
            .is_err());
        assert_eq!(fs::read(directory.join(RUN_NAME)).unwrap(), bytes);
        let archive = store.archive_and_save(&loaded, &loaded).unwrap();
        assert_eq!(fs::read(archive).unwrap(), bytes);
        assert!(!store.needs_upgrade().unwrap());
        drop(store);
        let reopened = RunStore::open_with_hashes(&directory, HASHES).unwrap();
        assert_eq!(reopened.load().unwrap().unwrap(), expected);
        assert_eq!(expected.step, source.step, "finite exit cannot refill");
        assert_eq!(expected.m08_outcome, source.m08_outcome);
        assert!(serde_json::to_value(&expected).unwrap()["m09_outcome"]
            .get("aboard_at_departure")
            .is_none());
        drop(reopened);
        fs::remove_dir_all(directory).unwrap();
    }
}

#[test]
fn m09_receipt_current_shape_requires_completed_stage_and_exact_eligible_release() {
    for edda in [false, true] {
        for splice in [false, true] {
            let mut document = completed_berth(edda, splice);
            let Some(M09Outcome::Recorded { released_crew, .. }) = &document.m09_outcome else {
                panic!("native receipt")
            };
            let released = released_crew.clone();
            for aboard in [vec![], vec!["berth_crew_b".into()], released.clone()] {
                document.m09_outcome = Some(M09Outcome::Recorded {
                    released_crew: released.clone(),
                    aboard_at_departure: aboard,
                });
                document.validate(HASHES[8]).unwrap();
            }
            for aboard in [
                vec!["missing".into()],
                vec!["tern".into(), "tern".into()],
                vec!["berth_crew_b".into(), "tern".into()],
            ] {
                document.m09_outcome = Some(M09Outcome::Recorded {
                    released_crew: released.clone(),
                    aboard_at_departure: aboard,
                });
                assert!(document.validate(HASHES[8]).is_err());
            }
            for released_crew in [
                vec![],
                vec!["tern".into()],
                vec!["edda".into(), "splice".into()],
            ] {
                document.m09_outcome = Some(M09Outcome::Recorded {
                    released_crew,
                    aboard_at_departure: vec![],
                });
                assert!(document.validate(HASHES[8]).is_err());
            }
            document.m09_outcome = None;
            assert!(document.validate(HASHES[8]).is_err());
        }
    }
    let mut premature = RunDocument::new(Uuid::new_v4(), Default::default(), HASHES[0]);
    premature.m09_outcome = Some(M09Outcome::HistoricalUnrecorded {});
    assert!(premature.validate(HASHES[0]).is_err());
}

#[test]
fn m09_receipt_historical_fields_and_missing_transit_facts_refuse_strictly() {
    let document = completed_berth(false, false);
    for version in [10, 11] {
        for outcome in [
            serde_json::Value::Null,
            serde_json::json!({"kind":"historical_unrecorded"}),
        ] {
            let mut value = serde_json::to_value(&document).unwrap();
            value["version"] = version.into();
            value["m09_outcome"] = outcome;
            assert!(matches!(
                RunStore::inspect_bytes(&serde_json::to_vec(&value).unwrap(), HASHES),
                RunProbe::Corrupt
            ));
        }
    }
    for malformed in [
        serde_json::json!({"kind":"recorded","released_crew":["tern","berth_crew_a","berth_crew_b"]}),
        serde_json::json!({"kind":"historical_unrecorded","released_crew":[]}),
        serde_json::json!({"kind":"recorded","released_crew":["tern","berth_crew_a","berth_crew_b"],"aboard_at_departure":[],"transit_complete":true}),
    ] {
        let mut value = serde_json::to_value(&document).unwrap();
        value["m09_outcome"] = malformed;
        assert!(matches!(
            RunStore::inspect_bytes(&serde_json::to_vec(&value).unwrap(), HASHES),
            RunProbe::Corrupt
        ));
    }
    let mut m10 = serde_json::to_value(&document).unwrap();
    let exit = m10["step"]["exit"].clone();
    m10["step"] =
        serde_json::json!({"kind":"mission_entry","mission":"common_carrier","entry":exit});
    m10["content_sha256"] = serde_json::json!(HASHES[9]);
    assert!(
        matches!(
            RunStore::inspect_bytes(&serde_json::to_vec(&m10).unwrap(), HASHES),
            RunProbe::Incompatible
        ),
        "current M10 identity and matching content cannot bypass required transit"
    );
    m10["version"] = 12.into();
    assert!(
        matches!(
            RunStore::inspect_bytes(&serde_json::to_vec(&m10).unwrap(), HASHES),
            RunProbe::Corrupt
        ),
        "exact v12 reader refuses any M10 identity before migration"
    );
}
