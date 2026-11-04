use crate::protocol::{Action, GameEvent, Role, WeaponHandlingKind, WeaponType};
use crate::sim::{GameState, PLAYER_FLOOR_Y};
use uuid::Uuid;

fn arena(role: Role) -> (GameState, Uuid) {
    let mut state = GameState::new();
    state.config.boss_spawn_ticks = None;
    state.config.compliance_ping_ticks = None;
    state.start_round();
    let id = Uuid::from_u128(558);
    state.add_player(id, "Handler".into(), role);
    state.players[0].x = 0.0;
    state.players[0].z = 0.0;
    state.players[0].y = PLAYER_FLOOR_Y;
    state.take_events();
    (state, id)
}

fn cues(state: &mut GameState, kind: WeaponHandlingKind) -> Vec<GameEvent> {
    state
        .take_events()
        .into_iter()
        .filter(|event| {
            matches!(event,
        GameEvent::WeaponHandling { kind: found, .. } if *found == kind)
        })
        .collect()
}

#[test]
fn accepted_reload_emits_once_and_a_later_snapshot_has_no_handling_cue() {
    let (mut state, id) = arena(Role::Human);
    state.arm_joined_magazines(id);
    assert!(state.players[0].inventory.try_fire(WeaponType::Tack));
    state.set_action(
        id,
        Action {
            reload: true,
            ..Action::default()
        },
    );
    state.tick(0.05);
    let events = cues(&mut state, WeaponHandlingKind::ReloadStart);
    assert_eq!(events.len(), 1);
    assert!(
        matches!(events[0], GameEvent::WeaponHandling { player_id, tick, position, .. }
        if player_id == id && tick == state.tick && position == [0.0;3])
    );
    for _ in 0..20 {
        state.tick(0.05);
        assert!(cues(&mut state, WeaponHandlingKind::ReloadStart).is_empty());
    }
    state.set_action(id, Action::default());
    state.tick(0.05);
    state.set_action(
        id,
        Action {
            reload: true,
            ..Action::default()
        },
    );
    state.tick(0.05);
    assert!(
        cues(&mut state, WeaponHandlingKind::ReloadStart).is_empty(),
        "a full magazine refuses the press"
    );
    assert!(!serde_json::to_string(&state.snapshot())
        .unwrap()
        .contains("weapon_handling"));
}

#[test]
fn dry_trigger_is_one_public_cue_per_press_for_hitscan_and_rocket() {
    for weapon in [WeaponType::Tack, WeaponType::Rocket] {
        let (mut state, id) = arena(Role::Agent);
        state.players[0].inventory.grant_weapon(weapon);
        state.players[0].weapon = weapon;
        while state.players[0].inventory.try_fire(weapon) {}
        state.players[0].inventory.release_trigger();
        state.set_action(
            id,
            Action {
                fire: true,
                ..Action::default()
            },
        );
        state.tick(0.05);
        assert_eq!(
            cues(&mut state, WeaponHandlingKind::DryFire).len(),
            1,
            "{weapon:?}"
        );
        for _ in 0..20 {
            state.tick(0.05);
            assert!(cues(&mut state, WeaponHandlingKind::DryFire).is_empty());
        }
        state.set_action(id, Action::default());
        state.tick(0.05);
        state.set_action(
            id,
            Action {
                fire: true,
                ..Action::default()
            },
        );
        state.tick(0.05);
        assert_eq!(cues(&mut state, WeaponHandlingKind::DryFire).len(), 1);
        assert!(state.shot_results.is_empty() && state.snapshot().rockets.is_empty());
    }
}

#[tokio::test]
async fn second_client_receives_each_handling_event_once_through_real_dispatch() {
    use crate::net::{Broadcast, ClientSession, Outbound};
    use crate::protocol::{ServerMessage, GAMEPLAY_VERSION};
    use crate::session::{broadcast_views_to_clients, send_unicasts, GameSession, Recipient};
    use std::collections::{HashMap, HashSet};
    use std::sync::Arc;
    use tokio::sync::Mutex;

    let (state, actor) = arena(Role::Human);
    let mut session = GameSession::new();
    session.state = state;
    session.state.arm_joined_magazines(actor);
    let observer = Uuid::from_u128(559);
    session
        .state
        .add_player(observer, "Listener".into(), Role::Human);
    session.state.players[1].x = 2.0;
    session.state.players[1].z = 0.0;
    session.state.players[1].y = PLAYER_FLOOR_Y;
    session.client_to_player.insert(actor, actor);
    session.client_to_player.insert(observer, observer);
    let (source_tx, mut source_rx) = crate::net::outbound_channel(128);
    let (observer_tx, mut observer_rx) = crate::net::outbound_channel(128);
    let clients = Arc::new(Mutex::new(vec![
        ClientSession::new(actor, source_tx, GAMEPLAY_VERSION),
        ClientSession::new(observer, observer_tx, GAMEPLAY_VERSION),
    ]));
    let map = session.state.map_info();
    send_unicasts(
        &clients,
        &HashMap::new(),
        &[
            (Recipient::Client(actor), map.clone()),
            (Recipient::Client(observer), map),
        ],
    )
    .await;
    assert!(matches!(
        source_rx.try_recv().unwrap(),
        ServerMessage::MapInfo { .. }
    ));
    assert!(matches!(
        observer_rx.try_recv().unwrap(),
        ServerMessage::MapInfo { .. }
    ));
    assert!(session.state.players[0]
        .inventory
        .try_fire(WeaponType::Tack));
    let mut heard = Vec::new();
    for step in 0..42 {
        if step == 0 {
            session.state.set_action(
                actor,
                Action {
                    reload: true,
                    ..Action::default()
                },
            );
        }
        if step == 21 {
            let inventory = &mut session.state.players[0].inventory;
            while inventory.try_fire(WeaponType::Tack) {}
            inventory.release_trigger();
            session.state.set_action(
                actor,
                Action {
                    fire: true,
                    ..Action::default()
                },
            );
        }
        let broadcasts = Broadcast::encode_all(session.tick_messages(0.05)).unwrap();
        let views = session.interest_views(&broadcasts).unwrap();
        broadcast_views_to_clients(&clients, &broadcasts, &HashSet::new(), &views).await;
        while source_rx.try_recv().is_ok() {}
        while let Ok(delivery) = observer_rx.try_take() {
            let Outbound::Shared(frame) = delivery.frame else {
                panic!("public handling uses the broadcast path");
            };
            let value: serde_json::Value = serde_json::from_str(frame.text()).unwrap();
            if value["event"] == "weapon_handling" {
                assert_eq!(value["player_id"], actor.to_string());
                assert!(value["position"].is_array());
                heard.push(value["kind"].as_str().unwrap().to_owned());
            }
        }
    }
    assert_eq!(
        heard,
        ["reload_start", "dry_fire"],
        "later snapshots and held inputs replay neither cue"
    );
}
