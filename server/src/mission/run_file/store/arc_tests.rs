//! Actual local upgrade and archive boundaries, separate from played combat.
use super::*;
use crate::mission::run_file::{M11Outcome, SavedStep};
use crate::protocol::{AmmoPool, CampaignRules, WeaponType, CAMPAIGN_RULES_REVISION};

fn historical(mut value: serde_json::Value, version: u32) -> serde_json::Value {
    value["version"] = version.into();
    value["rules"]["revision"] = (if version <= 4 { 2 } else { 3 }).into();
    if version == 2 {
        value.as_object_mut().unwrap().remove("body");
        value
            .as_object_mut()
            .unwrap()
            .remove("level_start_continues");
    }
    let entry = if value["step"].get("entry").is_some() {
        "entry"
    } else {
        "exit"
    };
    let equipment = value["step"][entry]["equipment"].as_object_mut().unwrap();
    if version < 6 {
        equipment.remove("grenades");
    }
    if version < 9 {
        equipment.remove("proximity_mines");
    }
    if version < 14 {
        equipment.remove("remote_mines");
    }
    super::super::omit_historical_rockets(&mut value);
    value
}

#[test]
fn arc_every_exact_historical_decoder_refuses_selected_or_owned_arc_even_with_zero_cells() {
    let source = RunDocument::new(Uuid::new_v4(), CampaignRules::default(), [7; 32]);
    for version in 2..=14 {
        let base = historical(serde_json::to_value(&source).unwrap(), version);
        assert!(
            matches!(
                RunStore::inspect_bytes(
                    &serde_json::to_vec(&base).unwrap(),
                    [[7; 32]; CAMPAIGN_STAGES]
                ),
                RunProbe::Compatible(_)
            ),
            "valid original v{version} first"
        );
        for select in [false, true] {
            let mut forged = base.clone();
            if select {
                forged["step"]["entry"]["equipment"]["selected"] = "arc".into();
            } else {
                forged["step"]["entry"]["equipment"]["weapons"]
                    .as_array_mut()
                    .unwrap()
                    .push("arc".into());
            }
            assert!(
                matches!(
                    RunStore::inspect_bytes(
                        &serde_json::to_vec(&forged).unwrap(),
                        [[7; 32]; CAMPAIGN_STAGES]
                    ),
                    RunProbe::Corrupt
                ),
                "v{version} Arc selected={select} must fail its exact decoder"
            );
        }
        let mut forged = base;
        forged["rules"]["revision"] = CAMPAIGN_RULES_REVISION.into();
        assert!(
            matches!(
                RunStore::inspect_bytes(
                    &serde_json::to_vec(&forged).unwrap(),
                    [[7; 32]; CAMPAIGN_STAGES]
                ),
                RunProbe::Incompatible
            ),
            "v{version} cannot claim current timing semantics"
        );
    }
}

pub(super) fn completed_tender() -> RunDocument {
    let mut ship = m09_receipt_tests::completed_berth(true, true)
        .promote_next(MissionId::CommonCarrier, m09_tests::HASHES[9])
        .unwrap();
    let SavedStep::MissionEntry { entry, .. } = &ship.step else {
        panic!("ship entry")
    };
    let mut exit = entry.clone();
    exit.equipment.weapons.push(WeaponType::Repeater);
    exit.equipment.selected = WeaponType::Repeater;
    ship.step = SavedStep::AwaitingMission {
        completed_mission: MissionId::CommonCarrier,
        next_mission: "right_of_search".into(),
        exit,
    };
    let mut tender = ship
        .promote_next(MissionId::RightOfSearch, m09_tests::HASHES[10])
        .unwrap();
    let SavedStep::MissionEntry { entry, .. } = &tender.step else {
        panic!("tender entry")
    };
    let mut exit = entry.clone();
    exit.hp = 37;
    exit.armor = 19;
    exit.equipment.remote_mines = 2;
    exit.equipment
        .ammo
        .iter_mut()
        .find(|a| a.pool == AmmoPool::Cells)
        .unwrap()
        .rounds = 7;
    exit.equipment.personal_claims = vec!["m11_actual_find".into()];
    tender.remaining_continues = 1;
    tender.step = SavedStep::AwaitingMission {
        completed_mission: MissionId::RightOfSearch,
        next_mission: "terms_of_cooperation".into(),
        exit,
    };
    tender.m11_outcome = Some(M11Outcome {
        transfer_released: true,
        records_read: true,
        counter_boarder_blast_kills: 3,
        bridge_response_ticks: 457,
    });
    tender.validate(m09_tests::HASHES[10]).unwrap();
    tender
}

#[test]
fn arc_v14_tender_upgrade_archives_exact_bytes_and_retries_failed_replacement_without_refill() {
    let source = completed_tender();
    let old = historical(serde_json::to_value(&source).unwrap(), 14);
    let mut bytes = serde_json::to_vec_pretty(&old).unwrap();
    bytes.extend_from_slice(b"\n \t\n");
    let directory = std::env::temp_dir().join(format!("fragr-arc-v14-{}", Uuid::new_v4()));
    let store = RunStore::open_with_hashes(&directory, m09_tests::HASHES).unwrap();
    fs::write(directory.join(RUN_NAME), &bytes).unwrap();
    let loaded = store.load().unwrap().unwrap();
    assert_eq!(loaded, source);
    assert_eq!(loaded.version, super::super::RUN_FILE_VERSION);
    assert_eq!(loaded.rules.revision, 4);
    assert!(store.needs_upgrade().unwrap());
    assert!(store
        .archive_and_save_before_replace(&loaded, &loaded, |_| Err(io::Error::other(
            "interrupted Arc upgrade"
        )))
        .is_err());
    assert_eq!(fs::read(directory.join(RUN_NAME)).unwrap(), bytes);
    let archive = store.archive_and_save(&loaded, &loaded).unwrap();
    assert_eq!(fs::read(&archive).unwrap(), bytes);
    assert!(!store.needs_upgrade().unwrap());
    assert_eq!(
        fs::read_dir(&directory)
            .unwrap()
            .filter_map(Result::ok)
            .filter(|p| p.file_name().to_string_lossy().starts_with("run.prior-"))
            .count(),
        1
    );
    drop(store);
    let reopened = RunStore::open_with_hashes(&directory, m09_tests::HASHES).unwrap();
    assert_eq!(
        reopened.load().unwrap().unwrap(),
        source,
        "actual equipment, outcomes, body and allowance are unchanged"
    );
    drop(reopened);
    fs::remove_dir_all(directory).unwrap();
}

#[test]
fn arc_v14_completed_m11_and_current_pre_m12_never_acquire_future_ownership() {
    let source = completed_tender();
    for version in [14, 15] {
        let mut base = serde_json::to_value(&source).unwrap();
        if version == 14 {
            base = historical(base, version);
        }
        for selected in [false, true] {
            let mut forged = base.clone();
            forged["step"]["exit"]["equipment"]["weapons"]
                .as_array_mut()
                .unwrap()
                .push("arc".into());
            if selected {
                forged["step"]["exit"]["equipment"]["selected"] = "arc".into();
            }
            assert!(
                !matches!(
                    RunStore::inspect_bytes(
                        &serde_json::to_vec(&forged).unwrap(),
                        m09_tests::HASHES
                    ),
                    RunProbe::Compatible(_)
                ),
                "v{version} completed M11 still precedes Arc"
            );
        }
    }
    let base = historical(serde_json::to_value(&source).unwrap(), 14);
    for field in ["m12_outcome", "future_outcome"] {
        let mut forged = base.clone();
        forged[field] = serde_json::json!({});
        assert!(matches!(
            RunStore::inspect_bytes(&serde_json::to_vec(&forged).unwrap(), m09_tests::HASHES),
            RunProbe::Corrupt
        ));
    }
    let mut empty = RunDocument::new(Uuid::new_v4(), CampaignRules::default(), [7; 32]);
    let SavedStep::MissionEntry { entry, .. } = &mut empty.step else {
        panic!("initial entry")
    };
    entry.equipment.weapons.push(WeaponType::Arc);
    assert!(empty.validate([7; 32]).is_err());
}
