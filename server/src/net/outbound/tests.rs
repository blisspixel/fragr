use super::*;
use crate::protocol::{ExplosionResult, GameEvent, Role, ShotResult};
use crate::sim::GameState;
use uuid::Uuid;

fn world(tick: u64) -> Snapshot {
    let mut state = GameState::new();
    state.add_player(Uuid::from_u128(1), "Moving fighter".into(), Role::Human);
    state.start_round();
    let mut snapshot = state.snapshot();
    snapshot.tick = tick;
    snapshot.players[0].x = tick as f32;
    snapshot
}

fn tick(message: ServerMessage) -> u64 {
    match message {
        ServerMessage::Snapshot(snapshot) => snapshot.tick,
        _ => panic!("expected world"),
    }
}

fn event() -> ServerMessage {
    ServerMessage::Event(GameEvent::Respawn {
        player: "Moving fighter".into(),
    })
}

#[test]
fn moving_active_world_replaces_at_capacity_without_moving_reliable_events() {
    let (tx, mut rx) = channel(2);
    let initial = world(1);
    tx.try_send(ServerMessage::Snapshot(initial.clone()))
        .unwrap();
    tx.try_send(event()).unwrap();
    for next in 2..=100 {
        let mut snapshot = initial.clone();
        snapshot.tick = next;
        snapshot.players[0].x += next as f32 * 0.1;
        snapshot.players[0].yaw += next as f32 * 0.01;
        snapshot.round_time_left = Some(60 - next as u32 / 20);
        assert_eq!(
            tx.try_send(ServerMessage::Snapshot(snapshot)).unwrap(),
            Queued::ReplacedWorld
        );
        assert_eq!(tx.depth(), 2);
    }
    assert!(matches!(rx.try_recv().unwrap(), ServerMessage::Event(_)));
    let ServerMessage::Snapshot(latest) = rx.try_recv().unwrap() else {
        panic!("world")
    };
    assert_eq!(latest.tick, 100);
    assert_eq!(latest.players[0].x, initial.players[0].x + 10.0);
    assert_eq!(latest.players[0].score, initial.players[0].score);
    assert!(rx.try_recv().is_err());
}

#[test]
fn actual_active_movement_ticks_coalesce_without_losing_the_final_body() {
    let mut state = GameState::new();
    let id = Uuid::from_u128(8);
    state.config.boss_spawn_ticks = None;
    state.config.compliance_ping_ticks = None;
    state.add_player(id, "Walker".into(), Role::Human);
    state.start_round();
    state.set_action(
        id,
        crate::protocol::Action {
            forward: true,
            ..Default::default()
        },
    );
    let first = state.snapshot().players[0].clone();
    let (tx, mut rx) = channel(16);
    let mut replaced = 0;
    for _ in 0..60 {
        state.tick(0.05);
        replaced += u64::from(
            tx.try_send(ServerMessage::Snapshot(state.snapshot()))
                .unwrap()
                == Queued::ReplacedWorld,
        );
    }
    let expected = state.snapshot();
    assert!(replaced >= 50, "only {replaced} moving worlds coalesced");
    assert!(
        (expected.players[0].x - first.x).abs() + (expected.players[0].z - first.z).abs() > 0.1
    );
    let mut last = None;
    while let Ok(message) = rx.try_recv() {
        last = Some(message);
    }
    assert_eq!(
        serde_json::to_value(last.unwrap()).unwrap(),
        serde_json::to_value(ServerMessage::Snapshot(expected)).unwrap()
    );
}

#[test]
fn sabotage_clock_and_carrier_motion_coalesce_but_charge_and_round_changes_do_not() {
    use crate::protocol::{
        ChargeState, ChargeStatus, SabotageFormat, SabotagePhase, SabotageState, TeamScores,
    };
    let mut snapshot = world(1);
    snapshot.sabotage = Some(SabotageState {
        format: SabotageFormat::Short,
        phase: SabotagePhase::Live,
        round: 1,
        period: 0,
        half: 1,
        half_rounds: 4,
        rounds_to_win: 5,
        score: TeamScores::default(),
        alive: TeamScores {
            union: 5,
            coalition: 5,
        },
        clock_ticks: 2100,
        charge: Some(ChargeState {
            status: ChargeStatus::Carried,
            position: [1.0, 0.0, 2.0],
            carrier: Some(Uuid::from_u128(1)),
            site: None,
        }),
        progress: None,
        swap_after: false,
    });
    let (tx, mut rx) = channel(3);
    tx.try_send(ServerMessage::Snapshot(snapshot.clone()))
        .unwrap();
    for next in 2..=40 {
        snapshot.tick = next;
        let sabotage = snapshot.sabotage.as_mut().unwrap();
        sabotage.clock_ticks -= 1;
        sabotage.charge.as_mut().unwrap().position[0] += 0.2;
        assert_eq!(
            tx.try_send(ServerMessage::Snapshot(snapshot.clone()))
                .unwrap(),
            Queued::ReplacedWorld
        );
    }
    snapshot.tick += 1;
    snapshot
        .sabotage
        .as_mut()
        .unwrap()
        .charge
        .as_mut()
        .unwrap()
        .status = ChargeStatus::Dropped;
    assert_eq!(
        tx.try_send(ServerMessage::Snapshot(snapshot.clone()))
            .unwrap(),
        Queued::Added
    );
    snapshot.tick += 1;
    snapshot.sabotage.as_mut().unwrap().round += 1;
    assert_eq!(
        tx.try_send(ServerMessage::Snapshot(snapshot)).unwrap(),
        Queued::Added
    );
    assert_eq!(tick(rx.try_recv().unwrap()), 40);
    assert_eq!(tick(rx.try_recv().unwrap()), 41);
    assert_eq!(tick(rx.try_recv().unwrap()), 42);
}

#[test]
fn combat_facts_remain_exact_and_ordered_before_their_acknowledgement() {
    let (tx, mut rx) = channel(8);
    let mut fired = world(10);
    fired.shot_results.push(ShotResult {
        shooter_id: Uuid::from_u128(1),
        shooter: "Moving fighter".into(),
        hit: true,
        target_id: Some(Uuid::from_u128(2)),
        target: Some("Target".into()),
        damage: 25,
        target_hp_after: Some(75),
        trace: None,
        killed: false,
    });
    fired.explosions.push(ExplosionResult {
        id: 7,
        owner_id: Uuid::from_u128(1),
        position: [1.0, 0.0, 2.0],
        radius: 4.0,
        hits: Vec::new(),
    });
    let expected = serde_json::to_value(&fired).unwrap();
    tx.try_send(ServerMessage::Snapshot(fired)).unwrap();
    let ack = ServerMessage::Ack {
        seq: 1,
        tick: 10,
        x: 1.0,
        z: 2.0,
        yaw: 0.0,
        pitch: 0.0,
        movement: None,
    };
    tx.try_send(ack.clone()).unwrap();
    tx.try_send(ServerMessage::Snapshot(world(11))).unwrap();
    assert_eq!(
        tx.try_send(ServerMessage::Snapshot(world(12))).unwrap(),
        Queued::ReplacedWorld
    );
    let ServerMessage::Snapshot(actual) = rx.try_recv().unwrap() else {
        panic!("combat world")
    };
    assert_eq!(serde_json::to_value(actual).unwrap(), expected);
    assert_eq!(
        serde_json::to_value(rx.try_recv().unwrap()).unwrap(),
        serde_json::to_value(ack).unwrap()
    );
    assert_eq!(tick(rx.try_recv().unwrap()), 12);
    assert!(rx.try_recv().is_err());
}

#[test]
fn exact_scores_deaths_statistics_and_round_changes_are_never_replaced() {
    let initial = world(1);
    let mut changes = Vec::new();
    let mut state = initial.clone();
    for field in ["score", "deaths", "attacks", "connects", "heads", "damage"] {
        let mut value = serde_json::to_value(&state).unwrap();
        value["players"][0][field] = serde_json::json!(1);
        state = serde_json::from_value(value).unwrap();
        state.tick += 1;
        changes.push(state.clone());
    }
    state.tick += 1;
    state.round_state = Some("ended".into());
    changes.push(state);
    let (tx, mut rx) = channel(16);
    tx.try_send(ServerMessage::Snapshot(initial)).unwrap();
    for snapshot in &changes {
        assert_eq!(
            tx.try_send(ServerMessage::Snapshot(snapshot.clone()))
                .unwrap(),
            Queued::Added
        );
    }
    assert_eq!(tick(rx.try_recv().unwrap()), 1);
    for expected in changes {
        let actual = rx.try_recv().unwrap();
        assert_eq!(
            serde_json::to_value(actual).unwrap(),
            serde_json::to_value(ServerMessage::Snapshot(expected)).unwrap()
        );
    }
}

#[test]
fn same_map_geometry_barrier_and_first_map_remain_before_their_worlds() {
    let (tx, mut rx) = channel(5);
    let map = GameState::new().map_info();
    tx.try_send(map.clone()).unwrap();
    tx.try_send(ServerMessage::Snapshot(world(1))).unwrap();
    tx.try_send(map).unwrap();
    assert_eq!(
        tx.try_send(ServerMessage::Snapshot(world(2))).unwrap(),
        Queued::Added
    );
    assert_eq!(
        tx.try_send(ServerMessage::Snapshot(world(3))).unwrap(),
        Queued::ReplacedWorld
    );
    assert!(matches!(
        rx.try_recv().unwrap(),
        ServerMessage::MapInfo { .. }
    ));
    assert_eq!(tick(rx.try_recv().unwrap()), 1);
    assert!(matches!(
        rx.try_recv().unwrap(),
        ServerMessage::MapInfo { .. }
    ));
    assert_eq!(tick(rx.try_recv().unwrap()), 3);
}

#[test]
fn full_reliable_queue_refuses_without_losing_its_existing_facts() {
    let (tx, mut rx) = channel(1);
    let mut shot = world(1);
    shot.players[0].just_fired = true;
    tx.try_send(ServerMessage::Snapshot(shot)).unwrap();
    assert!(matches!(
        tx.try_send(ServerMessage::Snapshot(world(2))),
        Err(QueueError::Full)
    ));
    assert_eq!(tx.depth(), 1);
    assert_eq!(tick(rx.try_recv().unwrap()), 1);
    assert!(matches!(rx.try_recv(), Err(TryRecvError::Empty)));
}

#[test]
fn backwards_or_duplicate_ticks_cannot_replace_a_newer_world() {
    let (tx, mut rx) = channel(3);
    tx.try_send(ServerMessage::Snapshot(world(2))).unwrap();
    assert_eq!(
        tx.try_send(ServerMessage::Snapshot(world(2))).unwrap(),
        Queued::Added
    );
    assert_eq!(
        tx.try_send(ServerMessage::Snapshot(world(1))).unwrap(),
        Queued::Added
    );
    assert_eq!(tick(rx.try_recv().unwrap()), 2);
    assert_eq!(tick(rx.try_recv().unwrap()), 2);
    assert_eq!(tick(rx.try_recv().unwrap()), 1);
}

#[test]
fn driven_vehicle_motion_coalesces_but_hp_seat_and_burn_transitions_stay_exact() {
    let (mut snapshot, mut next) = (world(1), world(2));
    snapshot
        .vehicles
        .push(crate::vehicles::Jeep::new(1, [0.0; 3], 0.0).state);
    next.vehicles = snapshot.vehicles.clone();
    next.vehicles[0].position[0] = 1.0;
    next.vehicles[0].speed = 4.0;
    next.vehicles[0].gun_heat = 0.2;
    let (tx, mut rx) = channel(4);
    tx.try_send(ServerMessage::Snapshot(snapshot)).unwrap();
    assert_eq!(
        tx.try_send(ServerMessage::Snapshot(next.clone())).unwrap(),
        Queued::ReplacedWorld
    );
    next.tick = 3;
    next.vehicles[0].hp = 375;
    assert_eq!(
        tx.try_send(ServerMessage::Snapshot(next.clone())).unwrap(),
        Queued::Added
    );
    next.tick = 4;
    next.vehicles[0].driver = Some(Uuid::from_u128(1));
    assert_eq!(
        tx.try_send(ServerMessage::Snapshot(next.clone())).unwrap(),
        Queued::Added
    );
    next.tick = 5;
    next.vehicles[0].hp = 0;
    next.vehicles[0].burning_ticks = 40;
    assert_eq!(
        tx.try_send(ServerMessage::Snapshot(next)).unwrap(),
        Queued::Added
    );
    assert_eq!(tick(rx.try_recv().unwrap()), 2);
    assert_eq!(tick(rx.try_recv().unwrap()), 3);
    assert_eq!(tick(rx.try_recv().unwrap()), 4);
    assert_eq!(tick(rx.try_recv().unwrap()), 5);
}

#[tokio::test]
async fn sender_clones_close_only_after_all_are_gone_and_receiver_drop_refuses() {
    let (tx, mut rx) = channel(1);
    let clone = tx.clone();
    drop(tx);
    assert!(matches!(rx.try_recv(), Err(TryRecvError::Empty)));
    clone.try_send(event()).unwrap();
    drop(clone);
    assert!(matches!(rx.recv().await, Some(ServerMessage::Event(_))));
    assert!(rx.recv().await.is_none());
    let (tx, rx) = channel(1);
    tx.try_send(event()).unwrap();
    drop(rx);
    assert_eq!(tx.depth(), 0);
    assert!(matches!(tx.try_send(event()), Err(QueueError::Closed)));
}

#[tokio::test]
async fn waiting_receiver_wakes_on_send_and_final_sender_drop() {
    let (tx, mut rx) = channel(1);
    let receive = tokio::spawn(async move {
        assert!(matches!(rx.recv().await, Some(ServerMessage::Event(_))));
        assert!(rx.recv().await.is_none());
    });
    tokio::task::yield_now().await;
    tx.try_send(event()).unwrap();
    drop(tx);
    tokio::time::timeout(std::time::Duration::from_secs(1), receive)
        .await
        .unwrap()
        .unwrap();
}
