use super::*;

#[test]
fn remote_v13_upgrade_preserves_actual_crew_and_archives_exact_original_bytes() {
    let before = m09_receipt_tests::completed_berth(true, true);
    let source = before
        .promote_next(
            crate::protocol::MissionId::CommonCarrier,
            m09_tests::HASHES[9],
        )
        .unwrap();
    let mut old = serde_json::to_value(&source).unwrap();
    old["version"] = 13.into();
    let mut bytes = serde_json::to_vec_pretty(&old).unwrap();
    bytes.extend_from_slice(b"\n \n");
    let directory = std::env::temp_dir().join(format!("fragr-remote-v13-{}", Uuid::new_v4()));
    let store = RunStore::open_with_hashes(&directory, m09_tests::HASHES).unwrap();
    fs::write(directory.join(RUN_NAME), &bytes).unwrap();
    let loaded = store.load().unwrap().unwrap();
    assert_eq!(loaded, source);
    assert_eq!(loaded.version, super::super::RUN_FILE_VERSION);
    assert_eq!(loaded.m09_outcome, source.m09_outcome);
    assert_eq!(loaded.m10_transit, source.m10_transit);
    let super::super::SavedStep::MissionEntry { entry, .. } = &loaded.step else {
        panic!("actual ship entry");
    };
    assert_eq!(entry.equipment.remote_mines, 0);
    assert!(store.needs_upgrade().unwrap());
    assert!(store
        .archive_and_save_before_replace(&loaded, &loaded, |_| Err(io::Error::other(
            "interrupted upgrade"
        )))
        .is_err());
    assert_eq!(fs::read(directory.join(RUN_NAME)).unwrap(), bytes);
    let archive = store.archive_and_save(&loaded, &loaded).unwrap();
    assert_eq!(fs::read(archive).unwrap(), bytes);
    assert!(!store.needs_upgrade().unwrap());
    assert_eq!(store.load().unwrap(), Some(source.clone()));
    drop(store);
    let reopened = RunStore::open_with_hashes(&directory, m09_tests::HASHES).unwrap();
    assert_eq!(reopened.load().unwrap(), Some(source));
    drop(reopened);
    fs::remove_dir_all(directory).unwrap();
}

#[test]
fn remote_v13_refuses_forged_count_even_zero_and_current_pre_find_carry() {
    let before = m09_receipt_tests::completed_berth(true, true);
    let source = before
        .promote_next(
            crate::protocol::MissionId::CommonCarrier,
            m09_tests::HASHES[9],
        )
        .unwrap();
    for bad in [
        serde_json::json!(0),
        serde_json::json!(1),
        serde_json::json!(6),
        serde_json::json!(7),
        serde_json::Value::Null,
    ] {
        let mut old = serde_json::to_value(&source).unwrap();
        old["version"] = 13.into();
        old["step"]["entry"]["equipment"]["remote_mines"] = bad;
        assert!(matches!(
            RunStore::inspect_bytes(&serde_json::to_vec(&old).unwrap(), m09_tests::HASHES),
            RunProbe::Corrupt
        ));
    }
    // The new field does not grant the missing mission or retroactively put its
    // equipment into an actual earlier entry. Current M10 stays pre-find.
    let mut forged = serde_json::to_value(&source).unwrap();
    forged["step"]["entry"]["equipment"]["remote_mines"] = 1.into();
    assert!(!matches!(
        RunStore::inspect_bytes(&serde_json::to_vec(&forged).unwrap(), m09_tests::HASHES),
        RunProbe::Compatible(_)
    ));
}

#[test]
fn m11_pending_carry_refuses_current_and_historical_identity_without_indexing_unbuilt_hash() {
    let before = m09_receipt_tests::completed_berth(true, true);
    let source = before
        .promote_next(
            crate::protocol::MissionId::CommonCarrier,
            m09_tests::HASHES[9],
        )
        .unwrap();
    assert!(source
        .promote_next(crate::protocol::MissionId::RightOfSearch, [42; 32])
        .is_err());
    for version in [13, super::super::RUN_FILE_VERSION] {
        let mut forged = serde_json::to_value(&source).unwrap();
        forged["version"] = version.into();
        forged["step"]["mission"] = "right_of_search".into();
        assert!(matches!(
            RunStore::inspect_bytes(&serde_json::to_vec(&forged).unwrap(), m09_tests::HASHES),
            RunProbe::Incompatible
        ));
    }
}
