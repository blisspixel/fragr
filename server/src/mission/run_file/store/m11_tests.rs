//! Locked carry and finite retry fixtures, not a full combat playthrough.
use super::*;
use crate::mission::run_file::{M09Outcome, M11Outcome, SavedStep};
use crate::protocol::{
    Action, CampaignRunStatus, LookAt, MissionContinue, MissionReady, Role, WeaponType,
};
use crate::sim::{GameState, PLAYER_FLOOR_Y};

fn completed_ship(known: bool) -> RunDocument {
    let mut berth = m09_receipt_tests::completed_berth(true, true);
    if !known {
        berth.m09_outcome = Some(M09Outcome::HistoricalUnrecorded {});
    }
    let mut ship = berth
        .promote_next(MissionId::CommonCarrier, m09_tests::HASHES[9])
        .unwrap();
    let SavedStep::MissionEntry { entry, .. } = &ship.step else {
        panic!("ship entry")
    };
    let mut exit = entry.clone();
    exit.hp = 43;
    exit.armor = 22;
    exit.equipment.weapons.push(WeaponType::Repeater);
    exit.equipment.selected = WeaponType::Repeater;
    exit.equipment.personal_claims = vec!["m10_actual_find".into()];
    ship.remaining_continues = 1;
    ship.step = SavedStep::AwaitingMission {
        completed_mission: MissionId::CommonCarrier,
        next_mission: "right_of_search".into(),
        exit,
    };
    ship.validate(m09_tests::HASHES[9]).unwrap();
    ship
}

fn map() -> std::sync::Arc<crate::maps::AuthoredMap> {
    static MAP: std::sync::OnceLock<std::sync::Arc<crate::maps::AuthoredMap>> =
        std::sync::OnceLock::new();
    MAP.get_or_init(|| {
        crate::maps::AuthoredSource::Mission(MissionId::RightOfSearch)
            .load()
            .unwrap()
    })
    .clone()
}

fn loaded(known: bool) -> (GameState, Uuid, RunDocument) {
    let map = map();
    let hash = crate::maps::RuntimeMap::Authored(map.clone())
        .content_sha256()
        .unwrap();
    let entry = completed_ship(known)
        .promote_next(MissionId::RightOfSearch, hash)
        .unwrap();
    let mut state = GameState::with_authored_map(map);
    state.seed(42);
    state.load_campaign_run(&entry).unwrap();
    let id = Uuid::new_v4();
    state.add_player(id, "Tender carry".into(), Role::Human);
    assert!(state.acknowledge_mission(
        id,
        MissionReady {
            id: MissionId::RightOfSearch,
            attempt: 1
        }
    ));
    (state, id, entry)
}

fn place(state: &mut GameState, id: Uuid, feet: [f32; 3]) {
    let p = state.players.iter_mut().find(|p| p.id == id).unwrap();
    [p.x, p.y, p.z] = [feet[0], feet[1] + PLAYER_FLOOR_Y, feet[2]];
    p.vy = 0.0;
    p.clear_input();
}

fn tick(state: &mut GameState) {
    state.tick(0.05);
    state.take_events();
    state.mission_state().unwrap().validate(state.tick).unwrap();
}

fn remote_stock(state: &GameState) -> [f32; 3] {
    let stock = state
        .map
        .pickups()
        .into_iter()
        .find(|s| matches!(s.kind, crate::sim::PickupKind::RemoteMine { count: 4 }))
        .expect("actual four-charge armory supply");
    [stock.x, stock.floor, stock.z]
}

fn claim_armory(state: &mut GameState, id: Uuid) {
    let stock = remote_stock(state);
    place(state, id, stock);
    // Adjacent shells and charges retain the real one-pad-per-player-per-tick
    // rule. Waiting ordinary ticks never bypasses or grants that supply.
    for _ in 0..8 {
        tick(state);
        if state
            .players
            .iter()
            .find(|p| p.id == id)
            .unwrap()
            .inventory
            .remote_mines()
            == 4
        {
            return;
        }
    }
    panic!("actual armory supply was not claimed within eight ordinary ticks");
}

fn clear(state: &mut GameState, group: usize) {
    // Terminal guard fixtures isolate persistence without claiming finite combat.
    for placement in state.map.encounters()[group].enemies.clone() {
        let p = state
            .players
            .iter_mut()
            .find(|p| p.name == placement.id)
            .unwrap();
        p.hp = 0;
        state
            .encounters
            .hit(p.id, [p.x, p.y - PLAYER_FLOOR_Y, p.z], state.tick, true);
    }
    tick(state);
    assert!(state.encounters.is_complete(group));
}

fn arrive(state: &mut GameState, id: Uuid, index: usize) {
    let crate::protocol::MissionObjectiveAction::Arrival { feet, .. } =
        state.map.m11_geometry().unwrap().objectives[index].action
    else {
        panic!("arrival")
    };
    place(state, id, feet);
    tick(state);
}

fn use_target(state: &mut GameState, id: Uuid, target: crate::protocol::UseTarget) {
    place(state, id, target.approach);
    let point = target
        .point(
            state.map.presentation_ref().unwrap(),
            &state.map.arena().solids,
        )
        .unwrap();
    state.set_action(
        id,
        Action {
            interact: true,
            look_at: Some(LookAt {
                x: Some(point[0]),
                y: Some(point[1]),
                z: Some(point[2]),
                player_id: None,
            }),
            ..Default::default()
        },
    );
    tick(state);
    state.set_action(id, Action::default());
    tick(state);
}

#[test]
fn m11_locked_m10_edge_keeps_stock_history_and_does_not_refill() {
    for known in [false, true] {
        let ship = completed_ship(known);
        let next = ship
            .promote_next(MissionId::RightOfSearch, m09_tests::HASHES[10])
            .unwrap();
        assert_eq!(
            (
                next.remaining_continues,
                next.level_start_continues,
                next.attempt()
            ),
            (1, 1, 1)
        );
        assert_eq!(
            (next.id, next.body, next.rules),
            (ship.id, ship.body, ship.rules)
        );
        assert_eq!(
            (
                &next.m03_outcome,
                &next.m04_outcome,
                &next.m05_outcome,
                &next.m06_outcome,
                &next.m08_outcome,
                &next.m09_outcome,
                &next.m10_transit
            ),
            (
                &ship.m03_outcome,
                &ship.m04_outcome,
                &ship.m05_outcome,
                &ship.m06_outcome,
                &ship.m08_outcome,
                &ship.m09_outcome,
                &ship.m10_transit
            )
        );
        let SavedStep::AwaitingMission { exit, .. } = &ship.step else {
            panic!("ship exit")
        };
        let SavedStep::MissionEntry { entry, .. } = &next.step else {
            panic!("tender entry")
        };
        let mut expected = exit.clone();
        expected.equipment.personal_claims.clear();
        assert_eq!(*entry, expected);
        assert_eq!(entry.equipment.remote_mines, 0);
        assert!(entry.equipment.weapons.contains(&WeaponType::Repeater));
        assert!(next.m11_outcome.is_none());
        assert!(next
            .promote_next(MissionId::RightOfSearch, m09_tests::HASHES[10])
            .is_err());
        let directory = std::env::temp_dir().join(format!("fragr-m11-edge-{}", Uuid::new_v4()));
        let store = RunStore::open_with_hashes(&directory, m09_tests::HASHES).unwrap();
        assert!(
            RunStore::open_with_hashes(&directory, m09_tests::HASHES).is_err(),
            "one actual writer owns the edge"
        );
        let mut value = serde_json::to_value(&ship).unwrap();
        value["version"] = 13.into();
        let mut bytes = serde_json::to_vec_pretty(&value).unwrap();
        bytes.extend_from_slice(b"\n \n");
        fs::write(directory.join(RUN_NAME), &bytes).unwrap();
        let loaded = store.load().unwrap().unwrap();
        assert_eq!(loaded, ship);
        assert!(store.needs_upgrade().unwrap());
        assert!(store
            .archive_and_save_before_replace(&loaded, &next, |_| Err(io::Error::other(
                "interrupted M11 edge"
            )))
            .is_err());
        assert_eq!(fs::read(directory.join(RUN_NAME)).unwrap(), bytes);
        let archive = store.archive_and_save(&loaded, &next).unwrap();
        assert_eq!(fs::read(archive).unwrap(), bytes);
        assert_eq!(store.load().unwrap().unwrap(), next);
        assert!(!store.needs_upgrade().unwrap());
        assert!(store.archive_and_save(&loaded, &next).is_err());
        drop(store);
        let reopened = RunStore::open_with_hashes(&directory, m09_tests::HASHES).unwrap();
        assert_eq!(reopened.load().unwrap().unwrap(), next);
        drop(reopened);
        fs::remove_dir_all(directory).unwrap();
    }
}

#[test]
fn m11_live_find_and_continue_restore_zero_entry_remote_and_clear_devices() {
    for known in [false, true] {
        let (mut state, id, entry) = loaded(known);
        assert_eq!(state.campaign_run_document().unwrap().unwrap(), entry);
        claim_armory(&mut state, id);
        let p = state.players.iter().find(|p| p.id == id).unwrap();
        assert_eq!(p.inventory.remote_mines(), 4);
        state.set_action(
            id,
            Action {
                place_remote_mine: true,
                ..Default::default()
            },
        );
        tick(&mut state);
        assert_eq!(state.snapshot().remote_mines.len(), 1);
        assert_eq!(
            state
                .players
                .iter()
                .find(|p| p.id == id)
                .unwrap()
                .inventory
                .remote_mines(),
            3
        );
        assert_eq!(
            state.campaign_run_document().unwrap().unwrap(),
            entry,
            "mission-start document does not rewrite finite entry after discovery"
        );
        let tick_before = state.tick;
        state.players.iter_mut().find(|p| p.id == id).unwrap().hp = 0;
        tick(&mut state);
        assert!(state.snapshot().remote_mines.is_empty());
        let pending = state.campaign_run_document().unwrap().unwrap();
        let SavedStep::PendingContinue { mission, .. } = &pending.step else {
            panic!("actual pending continue")
        };
        assert_eq!(*mission, MissionId::RightOfSearch);
        let mut reopened = GameState::with_authored_map(map());
        reopened.load_campaign_run(&pending).unwrap();
        let reopened_id = Uuid::new_v4();
        reopened.add_player(reopened_id, "Tender reopened continue".into(), Role::Human);
        reopened
            .mission_state()
            .unwrap()
            .validate(reopened.tick)
            .unwrap();
        assert_eq!(reopened.campaign_run_document().unwrap().unwrap(), pending);
        assert!(reopened.continue_mission(
            reopened_id,
            MissionContinue {
                id: MissionId::RightOfSearch,
                run_id: entry.id,
                attempt: 1
            }
        ));
        assert_eq!(
            reopened
                .players
                .iter()
                .find(|p| p.id == reopened_id)
                .unwrap()
                .inventory
                .remote_mines(),
            0
        );
        let retry = MissionContinue {
            id: MissionId::RightOfSearch,
            run_id: entry.id,
            attempt: 1,
        };
        assert!(state.continue_mission(id, retry));
        assert!(!state.continue_mission(id, retry));
        assert!(state.tick > tick_before);
        let saved = state.campaign_run_document().unwrap().unwrap();
        assert_eq!(
            (
                saved.remaining_continues,
                saved.level_start_continues,
                saved.attempt()
            ),
            (0, 1, 2)
        );
        assert_eq!(
            (&saved.step, &saved.m09_outcome, &saved.m10_transit),
            (&entry.step, &entry.m09_outcome, &entry.m10_transit)
        );
        assert!(saved.m11_outcome.is_none());
        let p = state.players.iter().find(|p| p.id == id).unwrap();
        assert_eq!(p.inventory.remote_mines(), 0);
        assert_eq!((p.hp, p.armor), (43, 22));
        assert_eq!(
            state.mission_state().unwrap().m11.unwrap().challenges,
            Default::default()
        );
        state.players.iter_mut().find(|p| p.id == id).unwrap().hp = 0;
        tick(&mut state);
        assert_eq!(
            state.mission_state().unwrap().run.unwrap().status,
            CampaignRunStatus::Failed
        );
        assert!(!state.continue_mission(
            id,
            MissionContinue {
                id: MissionId::RightOfSearch,
                run_id: entry.id,
                attempt: 2
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
}

#[test]
fn m11_actual_exit_saves_choices_elapsed_clock_and_finite_charge_count() {
    let (mut state, id, _) = loaded(true);
    claim_armory(&mut state, id);
    arrive(&mut state, id, 0);
    clear(&mut state, 0);
    arrive(&mut state, id, 1);
    arrive(&mut state, id, 2);
    clear(&mut state, 1);
    tick(&mut state);
    let g = state.map.m11_geometry().unwrap();
    use_target(&mut state, id, g.transfer_release.clone());
    arrive(&mut state, id, 3);
    clear(&mut state, 2);
    tick(&mut state);
    use_target(&mut state, id, g.records_document.clone());
    clear(&mut state, 3);
    arrive(&mut state, id, 4);
    arrive(&mut state, id, 5);
    let challenges = state.mission_state().unwrap().m11.unwrap().challenges;
    use_target(&mut state, id, g.departure);
    assert_eq!(
        state.mission_state().unwrap().run.unwrap().status,
        CampaignRunStatus::Complete
    );
    let completed = state.campaign_run_document().unwrap().unwrap();
    let SavedStep::AwaitingMission {
        completed_mission,
        next_mission,
        exit,
    } = &completed.step
    else {
        panic!("tender exit")
    };
    assert_eq!(
        (*completed_mission, next_mission.as_str()),
        (MissionId::RightOfSearch, "terms_of_cooperation")
    );
    assert_eq!(exit.equipment.remote_mines, 4);
    assert_eq!(
        completed.m11_outcome,
        Some(M11Outcome {
            transfer_released: true,
            records_read: true,
            counter_boarder_blast_kills: 0,
            bridge_response_ticks: challenges.bridge_taken_at.unwrap()
                - challenges.counter_boarding_started.unwrap()
        })
    );
    let mut hashes = m09_tests::HASHES;
    hashes[10] = completed.content_sha256;
    let bytes = serde_json::to_vec(&completed).unwrap();
    let RunProbe::Compatible(read) = RunStore::inspect_bytes(&bytes, hashes) else {
        panic!("actual complete receipt")
    };
    assert_eq!(*read, completed);
    for bad in [
        serde_json::Value::Null,
        serde_json::json!({}),
        serde_json::json!({"transfer_released":true,"records_read":true,"counter_boarder_blast_kills":7,"bridge_response_ticks":0}),
        serde_json::json!({"transfer_released":true,"records_read":true,"counter_boarder_blast_kills":0,"bridge_response_ticks":0,"invented_rescue":true}),
    ] {
        let mut forged = serde_json::to_value(&completed).unwrap();
        forged["m11_outcome"] = bad;
        assert!(!matches!(
            RunStore::inspect_bytes(&serde_json::to_vec(&forged).unwrap(), hashes),
            RunProbe::Compatible(_)
        ));
    }
    let mut missing = serde_json::to_value(&completed).unwrap();
    missing.as_object_mut().unwrap().remove("m11_outcome");
    assert!(matches!(
        RunStore::inspect_bytes(&serde_json::to_vec(&missing).unwrap(), hashes),
        RunProbe::Incompatible
    ));
    let mut historical = serde_json::to_value(&completed).unwrap();
    historical["version"] = 13.into();
    assert!(matches!(
        RunStore::inspect_bytes(&serde_json::to_vec(&historical).unwrap(), hashes),
        RunProbe::Corrupt
    ));
    assert!(GameState::with_authored_map(map())
        .load_campaign_run(&completed)
        .is_err());
    assert!(serde_json::from_str::<MissionId>("\"terms_of_cooperation\"").is_err());
    assert_eq!(
        crate::protocol::GAMEPLAY_VERSION,
        crate::protocol::M11_GAMEPLAY_VERSION
    );
}

#[test]
fn m11_saved_boundary_refuses_null_forged_outcome_pre_find_and_historical_entry() {
    let ship = completed_ship(true);
    let next = ship
        .promote_next(MissionId::RightOfSearch, m09_tests::HASHES[10])
        .unwrap();
    for bad in [
        serde_json::Value::Null,
        serde_json::json!({}),
        serde_json::json!({"transfer_released":false,"records_read":false,"counter_boarder_blast_kills":0,"bridge_response_ticks":0}),
    ] {
        for source in [&ship, &next] {
            let mut forged = serde_json::to_value(source).unwrap();
            forged["m11_outcome"] = bad.clone();
            assert!(!matches!(
                RunStore::inspect_bytes(&serde_json::to_vec(&forged).unwrap(), m09_tests::HASHES),
                RunProbe::Compatible(_)
            ));
        }
    }
    for count in [1, 6, 7] {
        let mut forged = serde_json::to_value(&next).unwrap();
        forged["step"]["entry"]["equipment"]["remote_mines"] = count.into();
        assert!(!matches!(
            RunStore::inspect_bytes(&serde_json::to_vec(&forged).unwrap(), m09_tests::HASHES),
            RunProbe::Compatible(_)
        ));
    }
    for version in 2..=13 {
        let mut forged = serde_json::to_value(&next).unwrap();
        forged["version"] = version.into();
        assert!(!matches!(
            RunStore::inspect_bytes(&serde_json::to_vec(&forged).unwrap(), m09_tests::HASHES),
            RunProbe::Compatible(_)
        ));
    }
    let outcome = M11Outcome {
        transfer_released: false,
        records_read: false,
        counter_boarder_blast_kills: 7,
        bridge_response_ticks: 0,
    };
    assert!(outcome.validate().is_err());
    assert!(M11Outcome {
        counter_boarder_blast_kills: 0,
        bridge_response_ticks: 1_u64 << 53,
        ..outcome
    }
    .validate()
    .is_err());
}
