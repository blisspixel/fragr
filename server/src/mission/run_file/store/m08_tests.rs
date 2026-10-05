use super::*;
use crate::maps::{AuthoredSource, RuntimeMap};
use crate::mission::run_file::{SavedEntry, SavedStep};
use crate::protocol::{Action, CampaignRunStatus, MissionContinue, MissionReady, Role};
use crate::sim::GameState;

const HASHES: ContentHashes = [
    [1; 32], [2; 32], [3; 32], [4; 32], [5; 32], [6; 32], [7; 32], [8; 32], [101; 32], [102; 32],
];

fn completed_town() -> RunDocument {
    let mut document = super::m07_tests::completed_port()
        .promote_next(MissionId::DeclaredGoods, HASHES[6])
        .unwrap();
    document.step = SavedStep::AwaitingMission {
        completed_mission: MissionId::DeclaredGoods,
        next_mission: "custodian_of_record".into(),
        exit: super::m07_tests::exit(true),
    };
    document.validate(HASHES[6]).unwrap();
    document
}

fn v8_bytes(document: &RunDocument) -> Vec<u8> {
    let mut value = serde_json::to_value(document).unwrap();
    value["version"] = 8.into();
    super::super::remove_historical_mines(&mut value);
    // Preserve noncanonical formatting to prove the archive is the source.
    let mut bytes = serde_json::to_vec_pretty(&value).unwrap();
    bytes.extend_from_slice(b"\n  \n");
    bytes
}

#[test]
fn v8_town_exit_promotes_exact_gear_and_outcomes_into_m08_without_refill() {
    let directory = std::env::temp_dir().join(format!("fragr-m08-carry-{}", Uuid::new_v4()));
    let store = RunStore::open_with_hashes(&directory, HASHES).unwrap();
    let source = completed_town();
    let bytes = v8_bytes(&source);
    fs::write(directory.join(RUN_NAME), &bytes).unwrap();
    let preview = RunStore::preview_with_hashes(&directory, HASHES)
        .unwrap()
        .unwrap();
    assert_eq!(preview, source);
    assert_eq!(fs::read(directory.join(RUN_NAME)).unwrap(), bytes);
    assert!(store.needs_upgrade().unwrap());
    let promoted = preview
        .promote_next(MissionId::CustodianOfRecord, HASHES[7])
        .unwrap();
    let SavedStep::AwaitingMission { exit, .. } = &source.step else {
        panic!("missing exit")
    };
    let SavedStep::MissionEntry { mission, entry } = &promoted.step else {
        panic!("missing entry")
    };
    assert_eq!(*mission, MissionId::CustodianOfRecord);
    let mut expected = exit.clone();
    expected.equipment.personal_claims.clear();
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
        (source.id, source.body, source.rules)
    );
    assert_eq!(promoted.m03_outcome, source.m03_outcome);
    assert_eq!(promoted.m04_outcome, source.m04_outcome);
    assert_eq!(promoted.m05_outcome, source.m05_outcome);
    assert_eq!(promoted.m06_outcome, source.m06_outcome);
    let mut spent = source.clone();
    spent.remaining_continues = 0;
    let exhausted = spent
        .promote_next(MissionId::CustodianOfRecord, HASHES[7])
        .unwrap();
    assert_eq!(
        (
            exhausted.remaining_continues,
            exhausted.level_start_continues
        ),
        (0, 0)
    );
    assert!(store
        .archive_and_save_before_replace(&preview, &promoted, |_| Err(io::Error::other(
            "injected replacement failure"
        )))
        .is_err());
    assert_eq!(fs::read(directory.join(RUN_NAME)).unwrap(), bytes);
    let archive = store.archive_and_save(&preview, &promoted).unwrap();
    assert_eq!(fs::read(&archive).unwrap(), bytes);
    assert_eq!(
        fs::read_dir(&directory)
            .unwrap()
            .filter_map(Result::ok)
            .filter(|entry| entry
                .file_name()
                .to_string_lossy()
                .starts_with("run.prior-"))
            .count(),
        1
    );
    assert!(!store.needs_upgrade().unwrap());
    assert_eq!(store.load().unwrap().unwrap(), promoted);
    assert!(promoted
        .promote_next(MissionId::CustodianOfRecord, HASHES[7])
        .is_err());
    drop(store);
    let reopened = RunStore::open_with_hashes(&directory, HASHES).unwrap();
    assert_eq!(reopened.load().unwrap().unwrap(), promoted);
    drop(reopened);
    fs::remove_dir_all(directory).unwrap();
}

#[test]
fn historical_equipment_refuses_forged_mines_and_preserves_exact_counts() {
    let source = RunDocument::new(
        Uuid::new_v4(),
        crate::protocol::CampaignRules::new(crate::protocol::CampaignDifficulty::Standard),
        HASHES[0],
    );
    for version in 2..=8 {
        let mut value = serde_json::to_value(&source).unwrap();
        value["version"] = version.into();
        if version <= 5 {
            super::super::remove_historical_grenades(&mut value);
        } else {
            super::super::remove_historical_mines(&mut value);
        }
        if version <= 4 {
            value["rules"]["revision"] = 2.into();
        }
        if version == 2 {
            let fields = value.as_object_mut().unwrap();
            fields.remove("body");
            fields.remove("level_start_continues");
        }
        if version >= 6 {
            value["step"]["entry"]["equipment"]["grenades"] = 3.into();
        }
        let RunProbe::Compatible(read) =
            RunStore::inspect_bytes(&serde_json::to_vec(&value).unwrap(), HASHES)
        else {
            panic!("valid historical version {version}")
        };
        let SavedStep::MissionEntry { entry, .. } = &read.step else {
            panic!("missing entry")
        };
        assert_eq!(entry.equipment.proximity_mines, 0);
        assert_eq!(entry.equipment.grenades, if version >= 6 { 3 } else { 0 });
        for field in ["proximity_mines", "mines", "future_equipment"] {
            let mut forged = value.clone();
            forged["step"]["entry"]["equipment"][field] = 0.into();
            assert!(
                matches!(
                    RunStore::inspect_bytes(&serde_json::to_vec(&forged).unwrap(), HASHES),
                    RunProbe::Corrupt
                ),
                "version {version} refuses {field} even at zero"
            );
        }
        if version >= 6 {
            value["step"]["entry"]["equipment"]
                .as_object_mut()
                .unwrap()
                .remove("grenades");
            assert!(matches!(
                RunStore::inspect_bytes(&serde_json::to_vec(&value).unwrap(), HASHES),
                RunProbe::Corrupt
            ));
        }
    }
}

#[test]
fn v8_refuses_playable_m08_and_current_counts_remain_strict() {
    let source = completed_town();
    let promoted = source
        .promote_next(MissionId::CustodianOfRecord, HASHES[7])
        .unwrap();
    assert!(matches!(
        RunStore::inspect_bytes(&v8_bytes(&promoted), HASHES),
        RunProbe::Incompatible
    ));
    let mut value = serde_json::to_value(&promoted).unwrap();
    for malformed in [
        serde_json::json!(-1),
        serde_json::json!(1.5),
        serde_json::json!(true),
        serde_json::json!("3"),
        serde_json::Value::Null,
    ] {
        value["step"]["entry"]["equipment"]["proximity_mines"] = malformed;
        assert!(matches!(
            RunStore::inspect_bytes(&serde_json::to_vec(&value).unwrap(), HASHES),
            RunProbe::Corrupt
        ));
    }
    value["step"]["entry"]["equipment"]["proximity_mines"] = 5.into();
    assert!(matches!(
        RunStore::inspect_bytes(&serde_json::to_vec(&value).unwrap(), HASHES),
        RunProbe::Incompatible
    ));
    value["step"]["entry"]["equipment"]
        .as_object_mut()
        .unwrap()
        .remove("proximity_mines");
    assert!(matches!(
        RunStore::inspect_bytes(&serde_json::to_vec(&value).unwrap(), HASHES),
        RunProbe::Corrupt
    ));
    let mut forged_town = source;
    if let SavedStep::AwaitingMission { exit, .. } = &mut forged_town.step {
        exit.equipment.proximity_mines = 1;
    }
    assert!(forged_town.validate(HASHES[6]).is_err());
}

#[test]
fn live_m08_retry_restores_entry_mines_and_completion_saves_actual_exit() {
    let map = AuthoredSource::Mission(MissionId::CustodianOfRecord)
        .load()
        .unwrap();
    let hash = RuntimeMap::Authored(map.clone()).content_sha256().unwrap();
    let mut saved = completed_town()
        .promote_next(MissionId::CustodianOfRecord, hash)
        .unwrap();
    let SavedStep::MissionEntry { entry, .. } = &mut saved.step else {
        panic!("missing entry")
    };
    entry.equipment.proximity_mines = 3;
    let anchor = entry.clone();
    let mut state = GameState::with_authored_map(map.clone());
    state.load_campaign_run(&saved).unwrap();
    let owner = Uuid::new_v4();
    state.add_player(owner, "Visitor".into(), Role::Human);
    assert!(state.acknowledge_mission(
        owner,
        MissionReady {
            id: MissionId::CustodianOfRecord,
            attempt: 1
        }
    ));
    state.tick(0.05);
    let start_tick = state.tick;
    let player = state
        .players
        .iter()
        .find(|player| player.id == owner)
        .unwrap();
    assert_eq!(SavedEntry::from_player(player).unwrap(), anchor);
    state.set_action(
        owner,
        Action {
            seq: Some(1),
            place_mine: true,
            ..Action::default()
        },
    );
    state.tick(0.05);
    assert_eq!(
        state.snapshot().mines.len(),
        1,
        "actual placement creates a committed device"
    );
    let player = state
        .players
        .iter_mut()
        .find(|player| player.id == owner)
        .unwrap();
    assert_eq!(
        player.inventory.mines(),
        2,
        "ordinary mine action consumes exactly one"
    );
    assert_eq!(
        player.inventory.grenades(),
        1,
        "mine placement does not consume grenades"
    );
    player.hp = 0;
    state.update_campaign_run();
    let pending = state.campaign_run_document().unwrap().unwrap();
    let SavedStep::PendingContinue { entry, .. } = &pending.step else {
        panic!("pending continue missing")
    };
    assert_eq!(
        *entry, anchor,
        "save retains entry, not post-placement inventory"
    );
    let mut reopened = GameState::with_authored_map(map.clone());
    reopened.load_campaign_run(&pending).unwrap();
    reopened.add_player(owner, "Visitor".into(), Role::Human);
    assert!(reopened.continue_mission(
        owner,
        MissionContinue {
            id: MissionId::CustodianOfRecord,
            run_id: saved.id,
            attempt: 1
        }
    ));
    assert_eq!(
        reopened
            .players
            .iter()
            .find(|player| player.id == owner)
            .unwrap()
            .inventory
            .mines(),
        3
    );
    assert!(state.continue_mission(
        owner,
        MissionContinue {
            id: MissionId::CustodianOfRecord,
            run_id: saved.id,
            attempt: 1
        }
    ));
    assert!(state.tick > start_tick);
    assert!(
        state.snapshot().mines.is_empty(),
        "continue clears devices from the previous attempt"
    );
    let player = state
        .players
        .iter_mut()
        .find(|player| player.id == owner)
        .unwrap();
    assert_eq!(SavedEntry::from_player(player).unwrap(), anchor);
    assert!(player.inventory.try_place_mine());
    assert_eq!(
        player.last_input_seq,
        Some(1),
        "continue retains acknowledged input sequence"
    );
    assert!(player.inventory.try_throw());
    let exit = SavedEntry::from_player(player).unwrap();
    assert_eq!(
        (exit.equipment.proximity_mines, exit.equipment.grenades),
        (2, 0)
    );
    let solo = state.mission.as_mut().unwrap().solo.as_mut().unwrap();
    solo.capture_exit(exit.clone());
    solo.state.status = CampaignRunStatus::Complete;
    let completed = state.campaign_run_document().unwrap().unwrap();
    assert_eq!(
        completed.m08_outcome,
        Some(crate::mission::run_file::M08Outcome::Recorded {
            custody_released: false,
            recovered_mind_secured: false,
            captives_evacuated: false,
        }),
        "native completion records actual progress, never historical defaults"
    );
    assert_eq!(completed.m03_outcome, saved.m03_outcome);
    assert_eq!(completed.m04_outcome, saved.m04_outcome);
    assert_eq!(completed.m05_outcome, saved.m05_outcome);
    assert_eq!(completed.m06_outcome, saved.m06_outcome);
    assert_eq!(
        (
            completed.remaining_continues,
            completed.level_start_continues
        ),
        (0, 1)
    );
    assert_eq!(
        completed.step,
        SavedStep::AwaitingMission {
            completed_mission: MissionId::CustodianOfRecord,
            next_mission: "passenger_manifest".into(),
            exit
        }
    );
    let bytes = serde_json::to_vec(&completed).unwrap();
    assert!(matches!(
        RunStore::inspect_bytes(&bytes, [hash; CAMPAIGN_STAGES]),
        RunProbe::Compatible(_)
    ));
    let directory = std::env::temp_dir().join(format!("fragr-m08-exit-{}", Uuid::new_v4()));
    let store = RunStore::open_with_hashes(&directory, [hash; CAMPAIGN_STAGES]).unwrap();
    store.save(&completed).unwrap();
    assert_eq!(store.load().unwrap().unwrap(), completed);
    drop(store);
    fs::remove_dir_all(directory).unwrap();
    let mut fresh_admission = GameState::with_authored_map(map);
    assert!(
        fresh_admission.load_campaign_run(&completed).is_err(),
        "completed future edge is not playable"
    );
    assert_eq!(
        serde_json::from_value::<MissionId>(serde_json::json!("common_carrier")).unwrap(),
        MissionId::CommonCarrier
    );
    assert_eq!(
        serde_json::from_value::<MissionId>(serde_json::json!("right_of_search")).unwrap(),
        MissionId::RightOfSearch
    );
    assert_eq!(
        crate::protocol::GAMEPLAY_VERSION,
        36,
        "internal M11 identity does not advertise its reserved contract"
    );
}
