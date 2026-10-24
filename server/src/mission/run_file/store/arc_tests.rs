//! Arc ownership boundaries in the saved run, separate from played combat.
use super::*;
use crate::mission::run_file::{M11Outcome, SavedStep};
use crate::protocol::{AmmoPool, CampaignRules, WeaponType};

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
fn arc_completed_tender_round_trips_through_disk_unchanged() {
    let source = completed_tender();
    let directory = std::env::temp_dir().join(format!("fragr-arc-{}", Uuid::new_v4()));
    let store = RunStore::open_with_hashes(&directory, m09_tests::HASHES).unwrap();
    store.save(&source).unwrap();
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
fn arc_completed_m11_and_earlier_entries_never_acquire_future_ownership() {
    let base = serde_json::to_value(completed_tender()).unwrap();
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
            matches!(
                RunStore::inspect_bytes(&serde_json::to_vec(&forged).unwrap(), m09_tests::HASHES),
                RunProbe::Incompatible
            ),
            "completed M11 still precedes the Arc (selected={selected})"
        );
    }
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
