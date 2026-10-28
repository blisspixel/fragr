use super::*;
use crate::maps::{AuthoredMap, AuthoredSource};
use crate::protocol::{Action, AmmoPool, CampaignRunStatus, MissionId, Role};

fn run() -> (GameState, Uuid) {
    let map = AuthoredMap::read(
        serde_json::to_vec(&super::super::tests::definition())
            .unwrap()
            .as_slice(),
    )
    .unwrap();
    let mut state = GameState::with_authored_map(map);
    state.enable_campaign_run().unwrap();
    let id = Uuid::new_v4();
    state.add_player(id, "Retry test".into(), Role::Human);
    let player = &mut state.players[0];
    player.inventory.grant_weapon(WeaponType::Tack);
    player.inventory.try_fire(WeaponType::Tack);
    player.inventory.record_claim("entry_claim".into());
    player.weapon = WeaponType::Tack;
    player.hp = 90;
    player.armor = 17;
    state.acknowledge_mission(
        id,
        MissionReady {
            id: MissionId::RecallNotice,
            attempt: 1,
        },
    );
    (state, id)
}

fn request(state: &GameState) -> MissionContinue {
    let mission = state.mission_state().unwrap();
    MissionContinue {
        id: mission.id,
        run_id: mission.run.unwrap().id,
        attempt: mission.attempt,
    }
}

fn die(state: &mut GameState, id: Uuid) {
    let player = state.players.iter_mut().find(|p| p.id == id).unwrap();
    player.hp = 0;
    player.respawn_timer = Some(1);
    state.tick(0.05);
    state.mission_state().unwrap().validate(state.tick).unwrap();
}

#[test]
fn statistics_survive_continue_while_attempt_counts_restart() {
    let (mut state, id) = run();
    state.set_action(
        id,
        Action {
            fire: true,
            ..Default::default()
        },
    );
    state.tick(0.05);
    let before = state.player_record(id).unwrap();
    assert_eq!(before.total.attacks(), 1);
    assert_eq!(before.total.alive_ticks, 1);
    assert_eq!(state.mission.as_ref().unwrap().started_at, Some(0));
    before.validate_for(Some(id), None).unwrap();
    die(&mut state, id);
    let death = state.player_record(id).unwrap();
    death.validate_for(Some(id), Some(&before)).unwrap();
    for _ in 0..100 {
        state.tick(0.05);
    }
    assert_eq!(
        state.player_record(id).unwrap().total,
        death.total,
        "retry choice is not active time"
    );
    let request = request(&state);
    assert!(state.continue_mission(id, request));
    assert_eq!(state.mission.as_ref().unwrap().started_at, Some(state.tick));
    let retry = state.player_record(id).unwrap();
    retry.validate_for(Some(id), Some(&death)).unwrap();
    assert_eq!(retry.total, before.total);
    assert_eq!(retry.attempt, crate::protocol::CombatCounts::default());
    state.set_action(
        id,
        Action {
            fire: true,
            ..Default::default()
        },
    );
    state.tick(0.05);
    let played = state.player_record(id).unwrap();
    assert_eq!(played.total.attacks(), 2);
    assert_eq!(played.attempt.attacks(), 1);
    assert!(!state.continue_mission(id, request));
    assert_eq!(
        state.mission.as_ref().unwrap().started_at,
        Some(state.tick - 1)
    );
    assert_eq!(played.total, state.player_record(id).unwrap().total);
}

#[test]
fn three_explicit_continues_then_death_ends_the_run() {
    let (mut state, id) = run();
    for spent in 0..=3 {
        let retry = request(&state);
        assert!(
            !state.continue_mission(id, retry),
            "living players cannot spend"
        );
        die(&mut state, id);
        let mission = state.mission_state().unwrap();
        let run = mission.run.unwrap();
        assert_eq!(run.continues, 3 - spent);
        assert_eq!(mission.attempt, u32::from(spent) + 1);
        assert_eq!(
            run.status,
            if spent == 3 {
                CampaignRunStatus::Failed
            } else {
                CampaignRunStatus::Continue
            }
        );
        for _ in 0..100 {
            state.tick(0.05);
        }
        assert_eq!(
            state.players[0].hp, 0,
            "timers must not resurrect a waiting player"
        );
        assert!(!state.continue_mission(Uuid::new_v4(), retry));
        assert!(!state.continue_mission(
            id,
            MissionContinue {
                run_id: Uuid::new_v4(),
                ..retry
            }
        ));
        assert_eq!(state.continue_mission(id, retry), spent < 3);
        assert!(
            !state.continue_mission(id, retry),
            "duplicates cannot spend twice"
        );
        state.mission_state().unwrap().validate(state.tick).unwrap();
    }
    state.remove_player(id);
    let ended = state.mission_state().unwrap();
    assert_eq!(ended.run.unwrap().status, CampaignRunStatus::Failed);
    assert!(ended.party.is_empty());
    ended.validate(state.tick).unwrap();
}

#[test]
fn entry_inventory_and_world_restore_without_rewinding_observers() {
    let (mut state, id) = run();
    let original_map = state.map.clone();
    let entry = state.players[0]
        .inventory
        .state(id, WeaponType::Tack, state.tick)
        .unwrap();
    state.map = state.map.opened_route().unwrap();
    state.mission.as_mut().unwrap().phase = MissionPhase::ReachLift;
    let player = &mut state.players[0];
    player.inventory.grant_weapon(WeaponType::Rail);
    player.inventory.grant_ammo(AmmoPool::Shells, 20);
    player.inventory.record_claim("later_claim".into());
    assert!(player.inventory.try_fire(WeaponType::Tack));
    player.x = 3.0;
    player.vy = -9.0;
    player.armor = 0;
    player.weapon = WeaponType::Rail;
    player.last_input_seq = Some(123);
    player.pending_action = Action {
        fire: true,
        jump: true,
        interact: true,
        ..Default::default()
    };
    let revision = player.inventory.revision();
    die(&mut state, id);
    let before_epoch = match &state.input_acks()[0].1 {
        crate::protocol::ServerMessage::Ack {
            movement: Some(body),
            ..
        } => body.epoch,
        other => panic!("expected full Ack before continue: {other:?}"),
    };
    let tick = state.tick;
    assert!(state.continue_mission(id, request(&state)));
    assert_eq!(state.map, original_map);
    assert_eq!(state.tick, tick);
    let player = &state.players[0];
    assert_eq!(
        (player.x, player.z, player.vy, player.hp, player.armor),
        (0.0, -6.0, 0.0, 90, 17)
    );
    assert_eq!(player.weapon, WeaponType::Tack);
    assert_eq!(player.last_input_seq, Some(123));
    let continued = match &state.input_acks()[0].1 {
        crate::protocol::ServerMessage::Ack {
            movement: Some(body),
            ..
        } => body.clone(),
        other => panic!("expected full Ack after continue: {other:?}"),
    };
    assert!(continued.epoch > before_epoch);
    assert!(!continued.applied);
    assert_eq!(continued.y, player.y);
    assert!(
        !player.pending_action.fire && !player.pending_action.jump && !player.interaction_requested
    );
    assert!(player.inventory.claimed("entry_claim"));
    assert!(!player.inventory.claimed("later_claim"));
    assert!(!player.inventory.owns(WeaponType::Rail));
    let restored = player
        .inventory
        .state(id, player.weapon, state.tick)
        .unwrap();
    assert_eq!(restored.weapons, entry.weapons);
    assert_eq!(
        restored.ammo, entry.ammo,
        "spent and gained ammunition rewinds"
    );
    assert!(player.inventory.revision() > revision);
    let mission = state.mission_state().unwrap();
    assert_eq!(mission.phase, MissionPhase::FindTransfer);
    assert!(mission.party[0].ready);
    assert_eq!(mission.changed_at, tick);
}

#[test]
fn abandonment_never_reopens_the_owner_seat() {
    for dead in [false, true] {
        let (mut state, id) = run();
        if dead {
            die(&mut state, id);
        }
        state.remove_player(id);
        let mission = state.mission_state().unwrap();
        mission.validate(state.tick).unwrap();
        assert_eq!(mission.run.unwrap().status, CampaignRunStatus::Abandoned);
        state.add_player(Uuid::new_v4(), "Replacement".into(), Role::Agent);
        assert!(state.players.is_empty());
        assert!(!state.continue_mission(id, request(&state)));
    }
}

#[test]
fn m01_retry_restores_all_authored_guards_stock_and_closed_lift() {
    let mut state = GameState::with_authored_map(
        AuthoredSource::Mission(MissionId::RecallNotice)
            .load()
            .unwrap(),
    );
    state.enable_campaign_run().unwrap();
    let id = Uuid::new_v4();
    state.add_player(id, "M01 retry".into(), Role::Agent);
    state.acknowledge_mission(
        id,
        MissionReady {
            id: MissionId::RecallNotice,
            attempt: 1,
        },
    );
    state.tick(0.05);
    let mut original: Vec<_> = state
        .players
        .iter()
        .filter(|p| p.is_campaign_enemy())
        .map(|p| (p.name.clone(), p.hp))
        .collect();
    original.sort();
    assert_eq!(original.len(), 20);
    for player in state.players.iter_mut().filter(|p| p.is_campaign_enemy()) {
        player.hp = 0;
    }
    for pickup in &mut state.pickups {
        pickup.available = false;
    }
    state.map = state.map.opened_route().unwrap();
    state.mission.as_mut().unwrap().phase = MissionPhase::ReachLift;
    die(&mut state, id);
    assert!(state.continue_mission(id, request(&state)));
    assert!(state.pickups.iter().all(|p| p.available));
    state.tick(0.05);
    let mut restored: Vec<_> = state
        .players
        .iter()
        .filter(|p| p.is_campaign_enemy())
        .map(|p| (p.name.clone(), p.hp))
        .collect();
    restored.sort();
    assert_eq!(restored, original);
    assert_eq!(
        state.mission_state().unwrap().phase,
        MissionPhase::FindTransfer
    );
    assert_eq!(
        state.players.iter().find(|p| p.id == id).unwrap().weapon,
        WeaponType::Fists
    );
}

#[test]
fn run_configuration_and_wire_reject_invalid_states() {
    assert!(GameState::new().enable_campaign_run().is_err());
    let (mut state, id) = run();
    assert!(state.enable_campaign_run().is_err());
    die(&mut state, id);
    let valid = serde_json::to_value(state.mission_state().unwrap()).unwrap();
    for patch in [
        serde_json::json!({"continues":4}),
        serde_json::json!({"continues":0}),
        serde_json::json!({"status":"complete"}),
        serde_json::json!({"status":"failed"}),
        serde_json::json!({"id":Uuid::nil()}),
    ] {
        let mut value = valid.clone();
        for (key, field) in patch.as_object().unwrap() {
            value["run"][key] = field.clone();
        }
        let mission: MissionState = serde_json::from_value(value).unwrap();
        assert!(mission.validate(state.tick).is_err());
    }
    let mut value = valid;
    value["run"]["extra"] = true.into();
    assert!(serde_json::from_value::<MissionState>(value).is_err());
}

#[test]
fn retry_seed_is_a_pure_function_of_process_seed_run_and_attempt() {
    let run = Uuid::from_u128(0xfeed);
    let seed = retry_seed(1, run, 2);
    assert_eq!(seed, retry_seed(1, run, 2), "the same inputs replay");
    for other in [
        retry_seed(2, run, 2),
        retry_seed(1, Uuid::from_u128(0xfeee), 2),
        retry_seed(1, Uuid::from_u128(0xfeed | 1 << 64), 2),
        retry_seed(1, run, 3),
    ] {
        assert_ne!(seed, other, "every input moves the stream");
    }
    assert_ne!(retry_seed(1, run, 1), 1, "never the process seed itself");
}

/// Recall Notice's local child: the default process seed and a fresh run.
fn seeded_m01(seed: u64) -> GameState {
    let mut state = GameState::with_authored_map(
        AuthoredSource::Mission(MissionId::RecallNotice)
            .load()
            .unwrap(),
    );
    // Stable entity ids, so two sessions can be compared field for field.
    state.use_replay_ids();
    state.seed(seed);
    state
}

fn admit_owner(state: &mut GameState, attempt: u32) -> Uuid {
    let id = Uuid::from_u128(479);
    state.add_player(id, "Retry seed".into(), Role::Agent);
    state.acknowledge_mission(
        id,
        MissionReady {
            id: MissionId::RecallNotice,
            attempt,
        },
    );
    id
}

/// The same retry, reached in this process or by reopening the saved
/// pending Continue, runs on one stream derived from the run and attempt;
/// it never replays the process seed the first attempt ran on (#489).
#[test]
fn a_retry_runs_on_its_run_and_attempt_stream_live_or_reopened() {
    let mut first = seeded_m01(1);
    first.enable_campaign_run().unwrap();
    assert_eq!(
        first.rng_state,
        seeded_m01(1).rng_state,
        "the first attempt runs on the process seed"
    );
    let id = admit_owner(&mut first, 1);
    for _ in 0..40 {
        first.tick(0.05);
    }
    die(&mut first, id);
    let pending = first.campaign_run_document().unwrap().unwrap();
    assert!(matches!(pending.step, SavedStep::PendingContinue { .. }));
    let retry = request(&first);
    assert_eq!(retry.attempt, 1);

    let mut expected = GameState::new();
    expected.restart_stream(retry_seed(1, pending.id, 2));
    let mut process = seeded_m01(1);
    process.restart_stream(1);
    assert_ne!(expected.rng_state, process.rng_state);

    assert!(first.continue_mission(id, retry));
    assert_eq!(first.mission_state().unwrap().attempt, 2);
    assert_eq!(first.seed_base(), 1, "a retry keeps the process seed");

    // Reopen the saved death twice, as two Continues from the menu would.
    let reopen = || {
        let mut state = seeded_m01(1);
        state.load_campaign_run(&pending).unwrap();
        let owner = admit_owner(&mut state, 1);
        let before = state.rng_state;
        assert!(state.continue_mission(owner, retry));
        (state, before)
    };
    let (mut one, opened) = reopen();
    let (mut two, _) = reopen();
    assert_eq!(
        opened, process.rng_state,
        "the reopened process starts on its seed"
    );
    assert_eq!(one.mission_state().unwrap().attempt, 2);
    // Restoring the entry draws nothing, so every path now stands at the
    // start of the retry's own stream, not at the process seed.
    for retried in [&first, &one, &two] {
        assert_eq!(retried.rng_state, expected.rng_state);
    }
    for _ in 0..200 {
        one.tick(0.05);
        two.tick(0.05);
    }
    assert_eq!(
        serde_json::to_value(one.snapshot()).unwrap(),
        serde_json::to_value(two.snapshot()).unwrap(),
        "the same run and attempt replay the same retry"
    );
}

#[test]
fn a_recorded_run_draws_a_fixed_id_and_a_live_run_a_fresh_one() {
    let mut recorded = seeded_m01(42);
    recorded.enable_campaign_run().unwrap();
    let mut again = seeded_m01(42);
    again.enable_campaign_run().unwrap();
    let id = |state: &GameState| state.mission_state().unwrap().run.unwrap().id;
    assert_eq!(id(&recorded), id(&again));
    let live_run = || {
        let mut state = GameState::with_authored_map(
            AuthoredSource::Mission(MissionId::RecallNotice)
                .load()
                .unwrap(),
        );
        state.seed(42);
        state.enable_campaign_run().unwrap();
        state
    };
    let (live, other) = (live_run(), live_run());
    assert_ne!(id(&live), id(&other));
    assert_ne!(id(&live), id(&recorded));
}
