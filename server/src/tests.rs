#[cfg(test)]
use crate::protocol::{
    boss_down_host_line, boss_host_line, boss_round_wipe_host_line, compliance_host_line,
    default_host_line, default_map_id, default_map_name, default_mode_name, default_playlist,
    mvp_host_line, round_open_host_line, warmup_host_line, Action, ClientMessage, GameEvent,
    PlayerScore, PlayerState, Role, ServerMessage, Snapshot, WeaponType, AUDITOR_NAME, BOSS_NAME,
    EPISODE_ID_EP0, EPISODE_MAP_LARAK_LOT,
};
#[cfg(test)]
use crate::session::GameSession;

mod roster;

#[tokio::test]
async fn late_connections_receive_authoritative_geometry_for_every_role() {
    use futures_util::{SinkExt, StreamExt};
    use tokio_tungstenite::{connect_async, tungstenite::Message};

    let (ready_tx, ready_rx) = tokio::sync::oneshot::channel();
    let (stop_tx, stop_rx) = tokio::sync::oneshot::channel();
    let server = tokio::spawn(crate::run::run_server(
        crate::run::ServerOptions {
            bind: "127.0.0.1:0".into(),
            bots: 0,
            map: MapKind::ReclamationGulch,
            ..Default::default()
        },
        async {
            let _ = stop_rx.await;
        },
        Some(ready_tx),
    ));
    let address = ready_rx.await.unwrap();
    // The first connection waits for a snapshot, so later joins cannot rely on
    // the one-time initial map broadcast. Spectators have no player mapping.
    let mut connections = Vec::new();
    for (index, role) in ["human", "spectator", "spectator", "agent", "human"]
        .iter()
        .enumerate()
    {
        let (mut socket, _) = connect_async(format!("ws://{address}")).await.unwrap();
        socket
            .send(Message::Text(
                serde_json::json!({
                    "type": "hello", "role": role, "name": "MapProbe"
                })
                .to_string(),
            ))
            .await
            .unwrap();
        tokio::time::timeout(std::time::Duration::from_secs(3), async {
            let mut saw_map = false;
            loop {
                let message = socket.next().await.unwrap().unwrap();
                let Message::Text(text) = message else {
                    continue;
                };
                let value: serde_json::Value = serde_json::from_str(&text).unwrap();
                if value["type"] == "map_info" {
                    assert_eq!(value["map_id"], 5);
                    assert!(value["solids"].as_array().unwrap().len() > 1);
                    assert!(value["half_extent"].as_f64().unwrap() > 50.0);
                    saw_map = true;
                }
                if saw_map && value["type"] == "snapshot" {
                    if index == 4 {
                        let names: Vec<_> = value["players"]
                            .as_array()
                            .unwrap()
                            .iter()
                            .map(|player| player["name"].as_str().unwrap())
                            .collect();
                        assert_eq!(
                            names.len(),
                            3,
                            "same-name connections must retain every fighter"
                        );
                        for name in ["MapProbe", "MapProbe #2", "MapProbe #3"] {
                            assert!(names.contains(&name), "missing assigned callsign {name}");
                        }
                    }
                    break;
                }
            }
        })
        .await
        .expect("every late role must receive geometry and a snapshot");
        connections.push(socket);
    }
    for mut socket in connections {
        socket.close(None).await.unwrap();
    }
    stop_tx.send(()).unwrap();
    server.await.unwrap().unwrap();
}
#[cfg(test)]
use crate::sim::{
    BotBehavior, BotController, EpisodePhase, GameState, MapKind, MatchConfig, RoundState,
    BOSS_MAX_HP, HEALTH_PICKUP_RESPAWN_TICKS, PICKUP_RESPAWN_TICKS,
};

#[cfg(test)]
use uuid::Uuid;

#[test]
fn test_protocol_client_message_hello_serialization() {
    let hello = ClientMessage::Hello {
        role: Role::Agent,
        name: "TestBot".to_string(),
    };
    let json = serde_json::to_string(&hello).unwrap();
    assert!(json.contains(r#""type":"hello""#));
    assert!(json.contains(r#""role":"agent""#));

    let deserialized: ClientMessage = serde_json::from_str(&json).unwrap();
    match deserialized {
        ClientMessage::Hello { role, name } => {
            assert_eq!(role, Role::Agent);
            assert_eq!(name, "TestBot");
        }
        _ => panic!("Expected Hello message"),
    }
}

#[test]
fn test_protocol_client_message_action_serialization() {
    let action_msg = ClientMessage::Action(Action {
        forward: true,
        fire: true,
        weapon_swap: Some(WeaponType::Rail),
        ..Default::default()
    });
    let json = serde_json::to_string(&action_msg).unwrap();
    assert!(json.contains(r#""type":"action""#));
    assert!(json.contains(r#""forward":true"#));
    assert!(json.contains(r#""fire":true"#));
    assert!(json.contains(r#""weapon_swap":"rail""#));
}

#[test]
fn test_protocol_server_message_welcome() {
    let welcome = ServerMessage::Welcome {
        player_id: Some(Uuid::new_v4()),
        role: Role::Human,
        mode_name: default_mode_name(),
        playlist: default_playlist(),
    };
    let json = serde_json::to_string(&welcome).unwrap();
    assert!(json.contains(r#""type":"welcome""#));
    assert!(json.contains(r#""role":"human""#));

    let welcome_spectator = ServerMessage::Welcome {
        player_id: None,
        role: Role::Spectator,
        mode_name: default_mode_name(),
        playlist: default_playlist(),
    };
    let json = serde_json::to_string(&welcome_spectator).unwrap();
    assert!(json.contains(r#""player_id":null"#));
}

#[test]
fn test_protocol_server_message_event_frag() {
    let event = GameEvent::Frag {
        killer: "Bot1".to_string(),
        victim: "Bot2".to_string(),
        killer_score: 3,
    };
    let event_msg = ServerMessage::Event(event);
    let json = serde_json::to_string(&event_msg).unwrap();
    assert!(json.contains(r#""event":"frag""#));
    assert!(json.contains("Bot1"));
    assert!(json.contains("Bot2"));

    let deserialized: ServerMessage = serde_json::from_str(&json).unwrap();
    match deserialized {
        ServerMessage::Event(GameEvent::Frag {
            killer,
            victim,
            killer_score,
        }) => {
            assert_eq!(killer, "Bot1");
            assert_eq!(victim, "Bot2");
            assert_eq!(killer_score, 3);
        }
        _ => panic!("Expected Event(Frag)"),
    }
}

#[test]
fn test_protocol_role_serialization() {
    let agent = Role::Agent;
    assert_eq!(serde_json::to_string(&agent).unwrap(), r#""agent""#);

    let human = Role::Human;
    assert_eq!(serde_json::to_string(&human).unwrap(), r#""human""#);

    let spectator = Role::Spectator;
    assert_eq!(serde_json::to_string(&spectator).unwrap(), r#""spectator""#);
}

#[test]
fn test_protocol_weapon_type_serialization() {
    assert_eq!(
        serde_json::to_string(&WeaponType::Flechette).unwrap(),
        r#""flechette""#
    );
    assert_eq!(
        serde_json::to_string(&WeaponType::Rail).unwrap(),
        r#""rail""#
    );
    assert_eq!(
        serde_json::to_string(&WeaponType::Scatter).unwrap(),
        r#""scatter""#
    );
}

#[test]
fn test_protocol_weapon_type_deserialization() {
    let weapon: WeaponType = serde_json::from_str(r#""flechette""#).unwrap();
    assert_eq!(weapon, WeaponType::Flechette);

    let weapon: WeaponType = serde_json::from_str(r#""rail""#).unwrap();
    assert_eq!(weapon, WeaponType::Rail);

    let weapon: WeaponType = serde_json::from_str(r#""scatter""#).unwrap();
    assert_eq!(weapon, WeaponType::Scatter);
}

#[test]
fn test_protocol_invalid_weapon_type() {
    let result: Result<WeaponType, _> = serde_json::from_str(r#""invalid""#);
    assert!(result.is_err());
}

#[test]
fn test_protocol_action_defaults() {
    let action = Action::default();
    assert!(!action.forward);
    assert!(!action.back);
    assert!(!action.fire);
    assert!(action.weapon_swap.is_none());
}

#[test]
fn test_protocol_action_partial_deserialization() {
    let json = r#"{"forward":true}"#;
    let action: Action = serde_json::from_str(json).unwrap();
    assert!(action.forward);
    assert!(!action.back);
}

#[test]
fn test_protocol_game_event_respawn() {
    let event = GameEvent::Respawn {
        player: "Bot1".to_string(),
    };
    let json = serde_json::to_value(&event).unwrap();
    assert_eq!(json["event"], "respawn");
    assert_eq!(json["player"], "Bot1");
}

#[test]
fn test_protocol_game_event_round_start() {
    let event = GameEvent::RoundStart {
        round_number: 2,
        frag_limit: Some(10),
        time_limit: Some(180),
        players: vec!["Bot1".to_string(), "Bot2".to_string()],
        previous_winner: Some("Bot1".to_string()),
        mode_name: default_mode_name(),
        playlist: default_playlist(),
        host_line: default_host_line(),
    };
    let json = serde_json::to_value(&event).unwrap();
    assert_eq!(json["event"], "round_start");
    assert_eq!(json["round_number"], 2);
    assert_eq!(json["frag_limit"], 10);
}

#[test]
fn test_protocol_game_event_round_end() {
    let event = GameEvent::RoundEnd {
        winner: Some("Bot1".to_string()),
        reason: "Frag limit reached".to_string(),
        final_scores: vec![PlayerScore {
            name: "Bot1".to_string(),
            score: 10,
        }],
        winner_score: Some(10),
        mvp: Some("Bot1".to_string()),
        mvp_frags: Some(10),
        host_line: mvp_host_line("Bot1", 10),
    };
    let json = serde_json::to_value(&event).unwrap();
    assert_eq!(json["event"], "round_end");
    assert_eq!(json["winner"], "Bot1");
    assert_eq!(json["mvp"], "Bot1");
    assert_eq!(json["mvp_frags"], 10);
    assert!(json["host_line"].as_str().unwrap().contains("ROUND MVP"));
}

#[test]
fn test_protocol_game_event_player_joined() {
    let event = GameEvent::PlayerJoined {
        player: "NewPlayer".to_string(),
        role: "human".to_string(),
        round_number: 3,
        player_count: 5,
    };
    let json = serde_json::to_value(&event).unwrap();
    assert_eq!(json["event"], "player_joined");
    assert_eq!(json["player_count"], 5);
}

#[test]
fn test_protocol_game_event_player_left() {
    let event = GameEvent::PlayerLeft {
        player: "OldPlayer".to_string(),
        score: 8,
        round_number: 2,
        player_count: 3,
    };
    let json = serde_json::to_value(&event).unwrap();
    assert_eq!(json["event"], "player_left");
    assert_eq!(json["score"], 8);
}

#[test]
fn test_protocol_snapshot_serialization() {
    let snapshot = Snapshot {
        tick: 123,
        players: vec![PlayerState {
            pitch: 0.0,
            id: Uuid::new_v4(),
            name: "Player1".to_string(),
            x: 10.0,
            y: 1.5,
            z: -5.0,
            yaw: 1.57,
            hp: 100,
            armor: 0,
            just_fired: false,
            behavior: None,
            score: 5,
            weapon: "Flechette".to_string(),
        }],
        round_state: Some("Active".to_string()),
        round_time_left: Some(60),
        frag_limit: Some(10),
        shot_results: vec![],
        mode_name: default_mode_name(),
        playlist: default_playlist(),
        pressure: None,
        host_line: default_host_line(),
        mvp: None,
        mvp_frags: None,
        pickups: vec![],
        map_id: default_map_id(),
        map_name: default_map_name(),
        episode_id: None,
        episode_title: None,
        episode_objective: None,
        episode_progress: None,
        episode_phase: None,
        jammer_dish: None,
    };
    let json = serde_json::to_value(&snapshot).unwrap();
    assert_eq!(json["tick"], 123);
    assert_eq!(json["players"][0]["name"], "Player1");
}

#[test]
fn test_protocol_snapshot_empty_players() {
    let snapshot = Snapshot {
        tick: 0,
        players: vec![],
        round_state: None,
        round_time_left: None,
        frag_limit: None,
        shot_results: vec![],
        mode_name: default_mode_name(),
        playlist: default_playlist(),
        pressure: None,
        host_line: default_host_line(),
        mvp: None,
        mvp_frags: None,
        pickups: vec![],
        map_id: default_map_id(),
        map_name: default_map_name(),
        episode_id: None,
        episode_title: None,
        episode_objective: None,
        episode_progress: None,
        episode_phase: None,
        jammer_dish: None,
    };
    let json = serde_json::to_string(&snapshot).unwrap();
    assert!(json.contains(r#""tick":0"#));
    assert!(json.contains(r#""players":[]"#));
}

#[test]
fn test_protocol_invalid_client_message() {
    let result: Result<ClientMessage, _> = serde_json::from_str(r#"{"type":"invalid"}"#);
    assert!(result.is_err());
}

#[test]
fn test_protocol_invalid_server_message() {
    let result: Result<ServerMessage, _> = serde_json::from_str(r#"{"type":"invalid"}"#);
    assert!(result.is_err());
}

#[test]
fn test_sim_bot_controller_aggressive() {
    let mut state = GameState::new();
    state.start_round();

    let bot_id = Uuid::new_v4();
    let target_id = Uuid::new_v4();

    state.add_player(bot_id, "AggressiveBot".to_string(), Role::Agent);
    state.add_player(target_id, "Target".to_string(), Role::Agent);

    let bot = BotController::new(bot_id, BotBehavior::Aggressive);
    let action = bot.update(&state);

    assert!(action.forward || action.turn_left || action.turn_right);
}

#[test]
fn test_sim_bot_controller_defensive() {
    let mut state = GameState::new();
    state.start_round();

    let bot_id = Uuid::new_v4();
    let target_id = Uuid::new_v4();

    state.add_player(bot_id, "DefensiveBot".to_string(), Role::Agent);
    state.add_player(target_id, "Target".to_string(), Role::Agent);

    let bot = BotController::new(bot_id, BotBehavior::Defensive);
    let action = bot.update(&state);

    assert!(
        action.forward
            || action.back
            || action.left
            || action.right
            || action.turn_left
            || action.turn_right
    );
}

#[test]
fn test_sim_bot_controller_flanker() {
    let mut state = GameState::new();
    state.start_round();

    let bot_id = Uuid::new_v4();
    let target_id = Uuid::new_v4();

    state.add_player(bot_id, "FlankerBot".to_string(), Role::Agent);
    state.add_player(target_id, "Target".to_string(), Role::Agent);

    let bot = BotController::new(bot_id, BotBehavior::Flanker);
    let action = bot.update(&state);

    assert!(action.forward || action.left || action.right || action.turn_left || action.turn_right);
}

#[test]
fn test_sim_bot_controller_balanced() {
    let mut state = GameState::new();
    state.start_round();

    let bot_id = Uuid::new_v4();
    let target_id = Uuid::new_v4();

    state.add_player(bot_id, "BalancedBot".to_string(), Role::Agent);
    state.add_player(target_id, "Target".to_string(), Role::Agent);

    let bot = BotController::new(bot_id, BotBehavior::Balanced);
    let action = bot.update(&state);

    assert!(action.forward || action.turn_left || action.turn_right);
}

#[test]
fn test_sim_bot_no_target_returns_default() {
    let state = GameState::new();
    let bot_id = Uuid::new_v4();

    let bot = BotController::new(bot_id, BotBehavior::Aggressive);
    let action = bot.update(&state);

    assert!(!action.forward);
    assert!(!action.fire);
}

#[test]
fn test_sim_round_state_transitions() {
    let mut state = GameState::new();
    assert_eq!(state.round_state, RoundState::Warmup);

    for _ in 0..state.config.warmup_ticks {
        state.tick(0.05);
    }
    assert_eq!(state.round_state, RoundState::Active);

    state.end_round("Manual end".to_string());
    assert_eq!(state.round_state, RoundState::Ended);
}

#[test]
fn test_sim_round_end_event_generation() {
    let mut state = GameState::new();
    let player_id = Uuid::new_v4();
    state.add_player(player_id, "Winner".to_string(), Role::Agent);
    state.start_round();

    *state.scores.entry(player_id).or_insert(0) = 10;

    state.end_round("Test end".to_string());

    let events = state.take_events();
    assert!(events
        .iter()
        .any(|e| matches!(e, GameEvent::RoundEnd { .. })));
}

#[test]
fn test_sim_player_spawn_positions_distributed() {
    let mut state = GameState::new();

    let id1 = Uuid::new_v4();
    let id2 = Uuid::new_v4();
    let id3 = Uuid::new_v4();

    state.add_player(id1, "Player1".to_string(), Role::Agent);
    state.add_player(id2, "Player2".to_string(), Role::Agent);
    state.add_player(id3, "Player3".to_string(), Role::Agent);

    let pos1 = (state.players[0].x, state.players[0].z);
    let pos2 = (state.players[1].x, state.players[1].z);
    let pos3 = (state.players[2].x, state.players[2].z);

    assert_ne!(pos1, pos2);
    assert_ne!(pos2, pos3);
    assert_ne!(pos1, pos3);
}

#[test]
fn test_sim_fire_cooldown_decrements() {
    let mut state = GameState::new();
    state.start_round();

    let player_id = Uuid::new_v4();
    state.add_player(player_id, "TestPlayer".to_string(), Role::Agent);

    let idx = state
        .players
        .iter()
        .position(|p| p.id == player_id)
        .unwrap();
    state.players[idx].fire_cooldown = 10;

    state.tick(0.05);

    assert_eq!(state.players[idx].fire_cooldown, 9);
}

#[test]
fn test_sim_respawn_timer_decrements() {
    let mut state = GameState::new();
    state.start_round();

    let player_id = Uuid::new_v4();
    state.add_player(player_id, "TestPlayer".to_string(), Role::Agent);

    let idx = state
        .players
        .iter()
        .position(|p| p.id == player_id)
        .unwrap();
    state.players[idx].respawn_timer = Some(10);

    state.tick(0.05);

    assert_eq!(state.players[idx].respawn_timer, Some(9));
}

#[test]
fn test_sim_dead_player_excluded_from_snapshot() {
    let mut state = GameState::new();
    state.start_round();

    let alive_id = Uuid::new_v4();
    let dead_id = Uuid::new_v4();

    state.add_player(alive_id, "Alive".to_string(), Role::Agent);
    state.add_player(dead_id, "Dead".to_string(), Role::Agent);

    let dead_idx = state.players.iter().position(|p| p.id == dead_id).unwrap();
    state.players[dead_idx].respawn_timer = Some(30);

    let snapshot = state.snapshot();

    assert_eq!(snapshot.players.len(), 1);
    assert_eq!(snapshot.players[0].id, alive_id);
}

#[test]
fn test_sim_arena_boundary_clamping() {
    let mut state = GameState::new();
    state.start_round();

    let player_id = Uuid::new_v4();
    state.add_player(player_id, "TestPlayer".to_string(), Role::Agent);

    let idx = state
        .players
        .iter()
        .position(|p| p.id == player_id)
        .unwrap();
    state.players[idx].x = 100.0;

    state.set_action(
        player_id,
        Action {
            forward: true,
            ..Default::default()
        },
    );

    state.tick(0.05);

    // The bound is the arena's own half extent, not a number copied from it,
    // so widening the map does not silently turn this assertion off.
    let half = crate::sim::MapKind::ArenaDuel.half_extent();
    assert!(
        state.players[idx].x <= half,
        "walked past the edge: {} > {half}",
        state.players[idx].x
    );
}

#[test]
fn test_sim_yaw_normalization() {
    let mut state = GameState::new();
    state.start_round();

    let player_id = Uuid::new_v4();
    state.add_player(player_id, "TestPlayer".to_string(), Role::Agent);

    let idx = state
        .players
        .iter()
        .position(|p| p.id == player_id)
        .unwrap();

    for _ in 0..100 {
        state.set_action(
            player_id,
            Action {
                turn_right: true,
                ..Default::default()
            },
        );
        state.tick(0.05);
    }

    let yaw = state.players[idx].yaw;
    assert!((0.0..2.0 * std::f32::consts::PI).contains(&yaw));
}

#[test]
fn test_sim_match_config_custom() {
    let config = MatchConfig {
        frag_limit: Some(5),
        time_limit_ticks: Some(100),
        warmup_ticks: 10,
        end_delay_ticks: 20,
        compliance_ping_ticks: None,
        compliance_duration_ticks: 20 * 6,
        boss_spawn_ticks: None,
    };

    assert_eq!(config.frag_limit, Some(5));
    assert_eq!(config.time_limit_ticks, Some(100));
}

#[test]
fn test_sim_scores_initialized_on_player_add() {
    let mut state = GameState::new();
    let player_id = Uuid::new_v4();

    state.add_player(player_id, "TestPlayer".to_string(), Role::Agent);

    assert!(state.scores.contains_key(&player_id));
    assert_eq!(*state.scores.get(&player_id).unwrap(), 0);
}

#[test]
fn test_sim_just_fired_flag_cleared() {
    let mut state = GameState::new();
    state.start_round();

    let shooter_id = Uuid::new_v4();
    let target_id = Uuid::new_v4();

    state.add_player(shooter_id, "Shooter".to_string(), Role::Agent);
    state.add_player(target_id, "Target".to_string(), Role::Agent);

    let shooter_idx = state
        .players
        .iter()
        .position(|p| p.id == shooter_id)
        .unwrap();
    let target_idx = state
        .players
        .iter()
        .position(|p| p.id == target_id)
        .unwrap();

    state.players[target_idx].x = 5.0;
    state.players[target_idx].z = 0.0;
    state.players[shooter_idx].x = 0.0;
    state.players[shooter_idx].z = 0.0;
    state.players[shooter_idx].yaw = 0.0;

    state.set_action(
        shooter_id,
        Action {
            fire: true,
            ..Default::default()
        },
    );
    state.tick(0.05);

    assert!(state.players[shooter_idx].just_fired);

    state.set_action(shooter_id, Action::default());
    state.tick(0.05);

    assert!(!state.players[shooter_idx].just_fired);
}

#[test]
fn test_sim_player_cannot_fire_during_cooldown() {
    let mut state = GameState::new();
    state.start_round();

    let shooter_id = Uuid::new_v4();
    let target_id = Uuid::new_v4();

    state.add_player(shooter_id, "Shooter".to_string(), Role::Agent);
    state.add_player(target_id, "Target".to_string(), Role::Agent);

    let shooter_idx = state
        .players
        .iter()
        .position(|p| p.id == shooter_id)
        .unwrap();
    let target_idx = state
        .players
        .iter()
        .position(|p| p.id == target_id)
        .unwrap();

    state.players[target_idx].x = 5.0;
    state.players[target_idx].z = 0.0;
    state.players[shooter_idx].x = 0.0;
    state.players[shooter_idx].z = 0.0;
    state.players[shooter_idx].yaw = 0.0;

    state.set_action(
        shooter_id,
        Action {
            fire: true,
            ..Default::default()
        },
    );
    state.tick(0.05);

    let initial_hp = state.players[target_idx].hp;

    state.set_action(
        shooter_id,
        Action {
            fire: true,
            ..Default::default()
        },
    );
    state.tick(0.05);

    assert_eq!(state.players[target_idx].hp, initial_hp);
}

#[test]
fn test_sim_respawn_event_generated() {
    let mut state = GameState::new();
    state.start_round();

    let player_id = Uuid::new_v4();
    state.add_player(player_id, "TestPlayer".to_string(), Role::Agent);

    let idx = state
        .players
        .iter()
        .position(|p| p.id == player_id)
        .unwrap();
    state.players[idx].hp = 0;
    state.players[idx].respawn_timer = Some(1);

    state.tick(0.05);

    let events = state.take_events();
    assert!(events
        .iter()
        .any(|e| matches!(e, GameEvent::Respawn { .. })));
}

#[test]
fn test_sim_snapshot_includes_round_info() {
    let mut state = GameState::new();
    state.config.time_limit_ticks = Some(200);
    state.config.frag_limit = Some(15);
    state.start_round();

    state.tick(0.05);

    let snapshot = state.snapshot();
    assert!(snapshot.round_state.is_some());
    assert!(snapshot.round_time_left.is_some());
    assert_eq!(snapshot.frag_limit, Some(15));
}

#[test]
fn test_sim_event_buffer_cleared_on_take() {
    let mut state = GameState::new();
    state.push_event(GameEvent::Respawn {
        player: "Test".to_string(),
    });

    assert_eq!(state.events.len(), 1);

    let events = state.take_events();
    assert_eq!(events.len(), 1);
    assert_eq!(state.events.len(), 0);
}

#[test]
fn test_sim_bot_does_not_update_while_dead() {
    let mut state = GameState::new();
    state.start_round();

    let bot_id = Uuid::new_v4();
    state.add_player(bot_id, "DeadBot".to_string(), Role::Agent);

    let idx = state.players.iter().position(|p| p.id == bot_id).unwrap();
    state.players[idx].respawn_timer = Some(30);

    let bot = BotController::new(bot_id, BotBehavior::Aggressive);
    let action = bot.update(&state);

    assert!(!action.forward);
    assert!(!action.fire);
}

#[test]
fn test_sim_round_start_event_includes_players() {
    let mut state = GameState::new();

    let id1 = Uuid::new_v4();
    let id2 = Uuid::new_v4();

    state.add_player(id1, "Player1".to_string(), Role::Agent);
    state.add_player(id2, "Player2".to_string(), Role::Agent);

    state.start_round();

    let events = state.take_events();
    let round_start = events
        .iter()
        .find_map(|e| match e {
            GameEvent::RoundStart { players, .. } => Some(players),
            _ => None,
        })
        .expect("RoundStart event should exist");

    assert_eq!(round_start.len(), 2);
    assert!(round_start.contains(&"Player1".to_string()));
    assert!(round_start.contains(&"Player2".to_string()));
}

#[test]
fn test_net_game_command_connected() {
    use crate::net::GameCommand;

    let id = Uuid::new_v4();
    let player_id = Some(Uuid::new_v4());

    let cmd = GameCommand::Connected {
        id,
        role: Role::Agent,
        name: "TestAgent".to_string(),
        player_id,
    };

    match cmd {
        GameCommand::Connected {
            id: _,
            role,
            name,
            player_id: pid,
        } => {
            assert_eq!(role, Role::Agent);
            assert_eq!(name, "TestAgent");
            assert_eq!(pid, player_id);
        }
        _ => panic!("Expected Connected command"),
    }
}

#[test]
fn test_net_game_command_disconnected() {
    use crate::net::GameCommand;

    let id = Uuid::new_v4();
    let cmd = GameCommand::Disconnected { id };

    match cmd {
        GameCommand::Disconnected { id: cmd_id } => {
            assert_eq!(cmd_id, id);
        }
        _ => panic!("Expected Disconnected command"),
    }
}

#[test]
fn test_net_game_command_action() {
    use crate::net::GameCommand;

    let player_id = Uuid::new_v4();
    let action = Action {
        forward: true,
        fire: true,
        ..Default::default()
    };

    let cmd = GameCommand::Action {
        player_id,
        action: action.clone(),
    };

    match cmd {
        GameCommand::Action {
            player_id: pid,
            action: a,
        } => {
            assert_eq!(pid, player_id);
            assert!(a.forward);
            assert!(a.fire);
        }
        _ => panic!("Expected Action command"),
    }
}

#[test]
fn test_net_client_session_structure() {
    use crate::net::ClientSession;
    use tokio::sync::mpsc;

    let id = Uuid::new_v4();
    let (tx, _rx) = mpsc::unbounded_channel();

    let session = ClientSession { id, tx };

    assert_eq!(session.id, id);
}

#[test]
fn test_protocol_all_weapon_types_coverage() {
    assert_eq!(WeaponType::Flechette.damage(), 25);
    assert_eq!(WeaponType::Flechette.cooldown_ticks(), 4);
    assert_eq!(WeaponType::Flechette.spread_radians(), 0.045);
    assert_eq!(WeaponType::Flechette.range_units(), 40.0);
    assert_eq!(WeaponType::Flechette.name(), "Flechette");

    assert_eq!(WeaponType::Rail.damage(), 80);
    assert_eq!(WeaponType::Rail.cooldown_ticks(), 20);
    assert_eq!(WeaponType::Rail.spread_radians(), 0.012);
    assert_eq!(WeaponType::Rail.range_units(), 60.0);
    assert_eq!(WeaponType::Rail.name(), "Rail");

    assert_eq!(WeaponType::Scatter.damage(), 40);
    assert_eq!(WeaponType::Scatter.cooldown_ticks(), 9);
    assert_eq!(WeaponType::Scatter.spread_radians(), 0.20);
    assert_eq!(WeaponType::Scatter.range_units(), 12.0);
    assert_eq!(WeaponType::Scatter.name(), "Scatter");
}

#[test]
fn test_sim_all_bot_behaviors_coverage() {
    let mut state = GameState::new();
    state.start_round();

    let bot_id = Uuid::new_v4();
    let target_id = Uuid::new_v4();

    state.add_player(bot_id, "Bot".to_string(), Role::Agent);
    state.add_player(target_id, "Target".to_string(), Role::Agent);

    for behavior in [
        BotBehavior::Aggressive,
        BotBehavior::Defensive,
        BotBehavior::Flanker,
        BotBehavior::Balanced,
        BotBehavior::Compliance,
    ] {
        let bot = BotController::new(bot_id, behavior);
        let _ = bot.update(&state);
    }
}

#[test]
fn test_sim_player_movement_all_directions() {
    let mut state = GameState::new();
    state.start_round();

    let player_id = Uuid::new_v4();
    state.add_player(player_id, "Mover".to_string(), Role::Agent);

    let idx = state
        .players
        .iter()
        .position(|p| p.id == player_id)
        .unwrap();

    state.players[idx].x = 0.0;
    state.players[idx].z = 0.0;

    state.set_action(
        player_id,
        Action {
            forward: true,
            ..Default::default()
        },
    );
    state.tick(0.05);

    state.set_action(
        player_id,
        Action {
            back: true,
            ..Default::default()
        },
    );
    state.tick(0.05);

    state.set_action(
        player_id,
        Action {
            left: true,
            ..Default::default()
        },
    );
    state.tick(0.05);

    state.set_action(
        player_id,
        Action {
            right: true,
            ..Default::default()
        },
    );
    state.tick(0.05);

    state.set_action(
        player_id,
        Action {
            turn_left: true,
            ..Default::default()
        },
    );
    state.tick(0.05);

    state.set_action(
        player_id,
        Action {
            turn_right: true,
            ..Default::default()
        },
    );
    state.tick(0.05);
}

#[test]
fn test_sim_round_ended_state_waits_for_delay() {
    let mut state = GameState::new();
    state.config.end_delay_ticks = 10;
    state.start_round();
    state.end_round("Test".to_string());

    assert_eq!(state.round_state, RoundState::Ended);
    assert_eq!(
        state.round_ticks, 0,
        "end_round must reset round_ticks for end_delay"
    );

    for _ in 0..9 {
        state.tick(0.05);
        assert_eq!(state.round_state, RoundState::Ended);
    }

    state.tick(0.05);
    assert_eq!(state.round_state, RoundState::Active);
}

#[test]
fn test_sim_warmup_state_skips_combat() {
    let mut state = GameState::new();
    assert_eq!(state.round_state, RoundState::Warmup);

    let shooter_id = Uuid::new_v4();
    let target_id = Uuid::new_v4();

    state.add_player(shooter_id, "Shooter".to_string(), Role::Agent);
    state.add_player(target_id, "Target".to_string(), Role::Agent);

    state.set_action(
        shooter_id,
        Action {
            fire: true,
            forward: true,
            ..Default::default()
        },
    );

    state.tick(0.05);
}

#[test]
fn test_sim_no_frag_limit_no_early_end() {
    let mut state = GameState::new();
    state.config.frag_limit = None;
    state.config.time_limit_ticks = Some(100);
    state.start_round();

    let player_id = Uuid::new_v4();
    state.add_player(player_id, "Player".to_string(), Role::Agent);
    *state.scores.entry(player_id).or_insert(0) = 100;

    state.tick(0.05);

    assert_eq!(state.round_state, RoundState::Active);
}

#[test]
fn test_sim_no_time_limit_no_early_end() {
    let mut state = GameState::new();
    state.config.frag_limit = Some(10);
    state.config.time_limit_ticks = None;
    state.start_round();

    for _ in 0..1000 {
        state.tick(0.05);
    }

    assert_eq!(state.round_state, RoundState::Active);
}

#[test]
fn test_player_id_consistent_after_add() {
    let mut state = GameState::new();
    let player_id = Uuid::new_v4();
    let name = "TestPlayer".to_string();

    state.add_player(player_id, name.clone(), Role::Human);

    let player = state
        .players
        .iter()
        .find(|p| p.id == player_id)
        .expect("Player should exist");
    assert_eq!(player.name, name);
    assert_eq!(player.hp, 100);
}

#[test]
fn test_player_id_action_flow() {
    let mut state = GameState::new();
    let player_id = Uuid::new_v4();

    state.add_player(player_id, "ActionTest".to_string(), Role::Human);

    let action = Action {
        forward: true,
        ..Default::default()
    };

    state.set_action(player_id, action);

    let player = state
        .players
        .iter()
        .find(|p| p.id == player_id)
        .expect("Player should exist after action");

    assert_eq!(player.id, player_id);
    assert!(player.pending_action.forward);
}

#[test]
fn test_hitscan_damage() {
    let mut state = GameState::new();
    state.start_round();

    let shooter_id = Uuid::new_v4();
    let target_id = Uuid::new_v4();

    state.add_player(shooter_id, "Shooter".to_string(), Role::Agent);
    state.add_player(target_id, "Target".to_string(), Role::Agent);

    let shooter_idx = state
        .players
        .iter()
        .position(|p| p.id == shooter_id)
        .unwrap();
    let target_idx = state
        .players
        .iter()
        .position(|p| p.id == target_id)
        .unwrap();

    state.players[target_idx].x = 5.0;
    state.players[target_idx].z = 0.0;
    state.players[shooter_idx].x = 0.0;
    state.players[shooter_idx].z = 0.0;
    state.players[shooter_idx].yaw = 0.0;

    let initial_hp = state.players[target_idx].hp;

    state.set_action(
        shooter_id,
        Action {
            fire: true,
            ..Default::default()
        },
    );
    state.tick(0.05);

    let final_hp = state.players[target_idx].hp;
    assert!(
        final_hp < initial_hp,
        "Target should take damage from hitscan"
    );
}

#[test]
fn test_frag_and_respawn() {
    let mut state = GameState::new();
    state.start_round();

    let shooter_id = Uuid::new_v4();
    let target_id = Uuid::new_v4();

    state.add_player(shooter_id, "Shooter".to_string(), Role::Agent);
    state.add_player(target_id, "Target".to_string(), Role::Agent);

    let shooter_idx = state
        .players
        .iter()
        .position(|p| p.id == shooter_id)
        .unwrap();
    let target_idx = state
        .players
        .iter()
        .position(|p| p.id == target_id)
        .unwrap();

    state.players[target_idx].x = 5.0;
    state.players[target_idx].z = 0.0;
    state.players[target_idx].hp = 20;
    state.players[shooter_idx].x = 0.0;
    state.players[shooter_idx].z = 0.0;
    state.players[shooter_idx].yaw = 0.0;

    state.set_action(
        shooter_id,
        Action {
            fire: true,
            ..Default::default()
        },
    );
    state.tick(0.05);

    let target = &state.players[target_idx];
    assert!(
        target.respawn_timer.is_some(),
        "Target should be dead with respawn timer"
    );
    assert!(target.hp <= 0, "Target HP should be zero or negative");

    for _ in 0..65 {
        state.tick(0.05);
    }

    let target = &state.players[target_idx];
    assert!(
        target.respawn_timer.is_none(),
        "Target should have respawned"
    );
    assert_eq!(target.hp, 100, "Target should respawn with full HP");
}

#[test]
fn test_movement_action() {
    let mut state = GameState::new();
    state.start_round();
    let player_id = Uuid::new_v4();

    state.add_player(player_id, "Mover".to_string(), Role::Human);

    let idx = state
        .players
        .iter()
        .position(|p| p.id == player_id)
        .unwrap();
    let initial_x = state.players[idx].x;

    let action = Action {
        forward: true,
        ..Default::default()
    };

    state.set_action(player_id, action);
    state.tick(0.05);

    let final_x = state.players[idx].x;
    assert_ne!(initial_x, final_x, "Player should have moved");
}

#[test]
fn test_player_removal() {
    let mut state = GameState::new();
    let player_id = Uuid::new_v4();

    state.add_player(player_id, "RemoveMe".to_string(), Role::Human);
    assert_eq!(state.players.len(), 1);

    state.remove_player(player_id);
    assert_eq!(state.players.len(), 0);
}

#[test]
fn test_round_warmup_to_active() {
    use crate::sim::RoundState;

    let mut state = GameState::new();
    assert_eq!(state.round_state, RoundState::Warmup);

    for _ in 0..state.config.warmup_ticks {
        state.tick(0.05);
    }

    assert_eq!(state.round_state, RoundState::Active);
    assert_eq!(state.round_number, 1);
}

#[test]
fn test_round_ends_on_frag_limit() {
    use crate::sim::RoundState;

    let mut state = GameState::new();
    state.config.frag_limit = Some(2);
    state.config.time_limit_ticks = None;

    let shooter_id = Uuid::new_v4();
    let target_id = Uuid::new_v4();

    state.add_player(shooter_id, "Shooter".to_string(), Role::Agent);
    state.add_player(target_id, "Target".to_string(), Role::Agent);
    state.start_round();

    let shooter_idx = state
        .players
        .iter()
        .position(|p| p.id == shooter_id)
        .unwrap();
    let target_idx = state
        .players
        .iter()
        .position(|p| p.id == target_id)
        .unwrap();

    state.players[shooter_idx].x = 0.0;
    state.players[shooter_idx].z = 0.0;
    state.players[shooter_idx].yaw = 0.0;

    for frag_count in 0..2 {
        state.players[target_idx].x = 5.0;
        state.players[target_idx].z = 0.0;
        state.players[target_idx].hp = 25;
        state.players[target_idx].respawn_timer = None;
        state.players[shooter_idx].fire_cooldown = 0;

        state.set_action(
            shooter_id,
            Action {
                fire: true,
                ..Default::default()
            },
        );
        state.tick(0.05);

        assert_eq!(
            *state.scores.get(&shooter_id).unwrap_or(&0),
            frag_count + 1,
            "Score should increment after frag"
        );
    }

    state.tick(0.05);

    assert_eq!(
        state.round_state,
        RoundState::Ended,
        "Round should end after reaching frag limit"
    );
}

#[test]
fn test_round_ends_on_time_limit() {
    use crate::sim::RoundState;

    let mut state = GameState::new();
    state.config.frag_limit = None;
    state.config.time_limit_ticks = Some(100);
    state.start_round();

    for _ in 0..100 {
        state.tick(0.05);
    }

    assert_eq!(state.round_state, RoundState::Ended);
}

#[test]
fn test_scores_reset_between_rounds() {
    use crate::sim::RoundState;

    let mut state = GameState::new();
    let player_id = Uuid::new_v4();

    state.add_player(player_id, "Player".to_string(), Role::Agent);
    state.start_round();

    *state.scores.entry(player_id).or_insert(0) = 5;

    state.round_state = RoundState::Ended;
    state.start_round();

    assert_eq!(*state.scores.get(&player_id).unwrap_or(&0), 0);
}

#[test]
fn test_bots_persist_when_human_leaves() {
    let mut state = GameState::new();

    let bot_id = Uuid::new_v4();
    let human_id = Uuid::new_v4();

    state.add_player(bot_id, "Bot".to_string(), Role::Agent);
    state.add_player(human_id, "Human".to_string(), Role::Human);

    assert_eq!(state.players.len(), 2);

    state.remove_player(human_id);

    assert_eq!(state.players.len(), 1);
    assert_eq!(state.players[0].id, bot_id);
}

#[test]
fn test_weapon_type_stats() {
    use crate::protocol::WeaponType;

    // Four flechette hits, three scatter hits, or two rail hits kill an
    // unarmoured fighter, which puts every weapon inside the time-to-kill band
    // in docs/plans/gunfeel.md.
    assert_eq!(WeaponType::Flechette.damage(), 25);
    assert_eq!(WeaponType::Flechette.cooldown_ticks(), 4);
    assert_eq!(WeaponType::Flechette.spread_radians(), 0.045);
    assert_eq!(WeaponType::Flechette.range_units(), 40.0);

    assert_eq!(WeaponType::Rail.damage(), 80);
    assert_eq!(WeaponType::Rail.cooldown_ticks(), 20);
    assert_eq!(WeaponType::Rail.spread_radians(), 0.012);
    assert_eq!(WeaponType::Rail.range_units(), 60.0);

    assert_eq!(WeaponType::Scatter.damage(), 40);
    assert_eq!(WeaponType::Scatter.cooldown_ticks(), 9);
    assert_eq!(WeaponType::Scatter.spread_radians(), 0.20);
    assert_eq!(WeaponType::Scatter.range_units(), 12.0);

    // Time to kill at 100 HP, in seconds at the 20 Hz tick.
    for (weapon, hits, seconds) in [
        (WeaponType::Flechette, 4, 0.6),
        (WeaponType::Rail, 2, 1.0),
        (WeaponType::Scatter, 3, 0.9),
    ] {
        let needed = (100 + weapon.damage() - 1) / weapon.damage();
        assert_eq!(needed, hits, "{weapon:?} should need {hits} clean hits");
        let ttk = (needed - 1) as f32 * weapon.cooldown_ticks() as f32 / 20.0;
        assert!(
            (ttk - seconds).abs() < 0.001,
            "{weapon:?} time to kill {ttk} should be {seconds}"
        );
        assert!(
            (0.5..=1.2).contains(&ttk),
            "{weapon:?} must sit in the target band, got {ttk}"
        );
    }
}

#[test]
fn test_weapon_default_is_flechette() {
    use crate::protocol::WeaponType;

    let mut state = GameState::new();
    let player_id = Uuid::new_v4();

    state.add_player(player_id, "TestPlayer".to_string(), Role::Human);

    let player = state.players.iter().find(|p| p.id == player_id).unwrap();
    assert_eq!(player.weapon, WeaponType::Flechette);
}

#[test]
fn test_weapon_swap_action() {
    use crate::protocol::WeaponType;

    let mut state = GameState::new();
    state.start_round();

    let player_id = Uuid::new_v4();
    state.add_player(player_id, "Swapper".to_string(), Role::Human);

    let idx = state
        .players
        .iter()
        .position(|p| p.id == player_id)
        .unwrap();

    assert_eq!(state.players[idx].weapon, WeaponType::Flechette);

    state.set_action(
        player_id,
        Action {
            weapon_swap: Some(WeaponType::Rail),
            ..Default::default()
        },
    );
    state.tick(0.05);

    assert_eq!(state.players[idx].weapon, WeaponType::Rail);

    state.set_action(
        player_id,
        Action {
            weapon_swap: Some(WeaponType::Scatter),
            ..Default::default()
        },
    );
    state.tick(0.05);

    assert_eq!(state.players[idx].weapon, WeaponType::Scatter);
}

#[test]
fn weapon_choice_survives_input_bursts_and_is_consumed_once() {
    use crate::protocol::WeaponType;
    let mut state = GameState::new();
    state.start_round();
    let id = Uuid::new_v4();
    state.add_player(id, "Meat Proxy".into(), Role::Human);
    for weapon_swap in [Some(WeaponType::Rail), Some(WeaponType::Scatter), None] {
        state.set_action(
            id,
            Action {
                weapon_swap,
                ..Default::default()
            },
        );
    }
    state.set_action(
        id,
        Action {
            yaw: Some(1.2),
            seq: Some(4),
            ..Default::default()
        },
    );
    state.tick(0.05);
    let player = state.players.iter_mut().find(|p| p.id == id).unwrap();
    assert_eq!(player.weapon, WeaponType::Scatter);
    assert_eq!(player.pending_action.weapon_swap, None);
    assert_eq!(player.last_input_seq, Some(4));
    assert!((player.yaw - 1.2).abs() < 0.00001);
    // A subsequent pickup must not be overwritten by a stale selection.
    player.weapon = WeaponType::Rail;
    state.tick(0.05);
    assert_eq!(
        state.players.iter().find(|p| p.id == id).unwrap().weapon,
        WeaponType::Rail
    );
}

#[test]
fn test_rail_higher_damage_than_flechette() {
    use crate::protocol::WeaponType;

    let mut state = GameState::new();
    state.start_round();

    let shooter_id = Uuid::new_v4();
    let target_id = Uuid::new_v4();

    state.add_player(shooter_id, "Shooter".to_string(), Role::Agent);
    state.add_player(target_id, "Target".to_string(), Role::Agent);

    let shooter_idx = state
        .players
        .iter()
        .position(|p| p.id == shooter_id)
        .unwrap();
    let target_idx = state
        .players
        .iter()
        .position(|p| p.id == target_id)
        .unwrap();

    state.players[target_idx].x = 5.0;
    state.players[target_idx].z = 0.0;
    state.players[shooter_idx].x = 0.0;
    state.players[shooter_idx].z = 0.0;
    state.players[shooter_idx].yaw = 0.0;
    state.players[shooter_idx].weapon = WeaponType::Rail;

    let initial_hp = state.players[target_idx].hp;

    state.set_action(
        shooter_id,
        Action {
            fire: true,
            ..Default::default()
        },
    );
    state.tick(0.05);

    let damage_dealt = initial_hp - state.players[target_idx].hp;
    assert_eq!(damage_dealt, 80, "Rail should deal 80 damage");
    assert!(
        damage_dealt > WeaponType::Flechette.damage(),
        "Rail damage should exceed Flechette"
    );
}

#[test]
fn test_scatter_hits_harder_than_flechette_up_close() {
    use crate::protocol::WeaponType;

    let mut state = GameState::new();
    state.start_round();

    let shooter_id = Uuid::new_v4();
    let target_id = Uuid::new_v4();

    state.add_player(shooter_id, "Shooter".to_string(), Role::Agent);
    state.add_player(target_id, "Target".to_string(), Role::Agent);

    let shooter_idx = state
        .players
        .iter()
        .position(|p| p.id == shooter_id)
        .unwrap();
    let target_idx = state
        .players
        .iter()
        .position(|p| p.id == target_id)
        .unwrap();

    state.players[target_idx].x = 5.0;
    state.players[target_idx].y = crate::sim::PLAYER_FLOOR_Y;
    state.players[target_idx].z = 0.0;
    state.players[shooter_idx].x = 0.0;
    state.players[shooter_idx].y = crate::sim::PLAYER_FLOOR_Y;
    state.players[shooter_idx].z = 0.0;
    state.players[shooter_idx].yaw = 0.0;
    state.players[shooter_idx].weapon = WeaponType::Scatter;

    let initial_hp = state.players[target_idx].hp;

    state.set_action(
        shooter_id,
        Action {
            fire: true,
            ..Default::default()
        },
    );
    state.tick(0.05);

    let damage_dealt = initial_hp - state.players[target_idx].hp;
    // The target centre is five units away, but the near cylinder surface
    // is about 4.5 units away. Falloff uses the traveled ray distance.
    assert_eq!(
        damage_dealt, 38,
        "Scatter reaches the near body surface first"
    );
    assert!(
        damage_dealt > WeaponType::Flechette.damage(),
        "up close the scatter gun should hit harder than the flechette"
    );
    assert!(
        damage_dealt < WeaponType::Scatter.damage(),
        "and less than point blank, because it falls off"
    );
}

#[test]
fn test_rail_longer_cooldown() {
    use crate::protocol::WeaponType;

    let mut state = GameState::new();
    state.start_round();

    let shooter_id = Uuid::new_v4();
    let target_id = Uuid::new_v4();

    state.add_player(shooter_id, "Shooter".to_string(), Role::Agent);
    state.add_player(target_id, "Target".to_string(), Role::Agent);

    let shooter_idx = state
        .players
        .iter()
        .position(|p| p.id == shooter_id)
        .unwrap();

    state.players[shooter_idx].weapon = WeaponType::Rail;
    state.players[shooter_idx].x = 0.0;
    state.players[shooter_idx].z = 0.0;
    state.players[shooter_idx].yaw = 0.0;

    state.set_action(
        shooter_id,
        Action {
            fire: true,
            ..Default::default()
        },
    );
    state.tick(0.05);

    assert_eq!(
        state.players[shooter_idx].fire_cooldown, 20,
        "Rail cooldown should be 20 ticks, a shot a second"
    );
}

#[test]
fn test_scatter_fires_faster_than_rail() {
    use crate::protocol::WeaponType;

    let mut state = GameState::new();
    state.start_round();

    let shooter_id = Uuid::new_v4();
    let target_id = Uuid::new_v4();

    state.add_player(shooter_id, "Shooter".to_string(), Role::Agent);
    state.add_player(target_id, "Target".to_string(), Role::Agent);

    let shooter_idx = state
        .players
        .iter()
        .position(|p| p.id == shooter_id)
        .unwrap();

    state.players[shooter_idx].weapon = WeaponType::Scatter;
    state.players[shooter_idx].x = 0.0;
    state.players[shooter_idx].z = 0.0;
    state.players[shooter_idx].yaw = 0.0;

    state.set_action(
        shooter_id,
        Action {
            fire: true,
            ..Default::default()
        },
    );
    state.tick(0.05);

    assert_eq!(
        state.players[shooter_idx].fire_cooldown, 9,
        "Scatter cooldown should be 9 ticks, slower than it was but far faster than the rail"
    );
}

#[test]
fn test_weapon_spread_affects_hit_detection() {
    use crate::protocol::WeaponType;

    let mut state = GameState::new();
    state.start_round();

    let shooter_id = Uuid::new_v4();
    let target_id = Uuid::new_v4();

    state.add_player(shooter_id, "Shooter".to_string(), Role::Agent);
    state.add_player(target_id, "Target".to_string(), Role::Agent);

    let shooter_idx = state
        .players
        .iter()
        .position(|p| p.id == shooter_id)
        .unwrap();
    let target_idx = state
        .players
        .iter()
        .position(|p| p.id == target_id)
        .unwrap();

    state.players[target_idx].x = 10.0;
    state.players[target_idx].z = 2.0;
    state.players[shooter_idx].x = 0.0;
    state.players[shooter_idx].z = 0.0;
    state.players[shooter_idx].yaw = 0.1;

    state.players[shooter_idx].weapon = WeaponType::Rail;
    state.players[shooter_idx].fire_cooldown = 0;

    state.set_action(
        shooter_id,
        Action {
            fire: true,
            ..Default::default()
        },
    );

    let target_hp_before = state.players[target_idx].hp;
    state.tick(0.05);
    let rail_hit = state.players[target_idx].hp < target_hp_before;

    state.players[target_idx].hp = 100;
    state.players[shooter_idx].weapon = WeaponType::Scatter;
    state.players[shooter_idx].fire_cooldown = 0;

    state.set_action(
        shooter_id,
        Action {
            fire: true,
            ..Default::default()
        },
    );

    let target_hp_before = state.players[target_idx].hp;
    state.tick(0.05);
    let scatter_hit = state.players[target_idx].hp < target_hp_before;

    assert!(
        scatter_hit || !rail_hit,
        "Scatter should be more forgiving with wider spread"
    );
}

#[test]
fn test_weapon_snapshot_includes_weapon_name() {
    use crate::protocol::WeaponType;

    let mut state = GameState::new();
    state.start_round();

    let player_id = Uuid::new_v4();
    state.add_player(player_id, "TestPlayer".to_string(), Role::Human);

    let snapshot = state.snapshot();
    assert_eq!(snapshot.players[0].weapon, "Flechette");

    let idx = state
        .players
        .iter()
        .position(|p| p.id == player_id)
        .unwrap();
    state.players[idx].weapon = WeaponType::Rail;

    let snapshot = state.snapshot();
    assert_eq!(snapshot.players[0].weapon, "Rail");

    state.players[idx].weapon = WeaponType::Scatter;

    let snapshot = state.snapshot();
    assert_eq!(snapshot.players[0].weapon, "Scatter");
}

#[test]
fn test_join_leave_event_serialization() {
    use crate::protocol::{GameEvent, ServerMessage};

    let join_event = GameEvent::PlayerJoined {
        player: "TestPlayer".to_string(),
        role: "human".to_string(),
        round_number: 1,
        player_count: 5,
    };
    let join_msg = ServerMessage::Event(join_event);
    let join_json = serde_json::to_string(&join_msg).unwrap();
    assert!(join_json.contains(r#""event":"player_joined"#));
    assert!(join_json.contains(r#""player":"TestPlayer"#));
    assert!(join_json.contains(r#""role":"human"#));
    assert!(join_json.contains(r#""round_number":1"#));
    assert!(join_json.contains(r#""player_count":5"#));

    let leave_event = GameEvent::PlayerLeft {
        player: "TestPlayer".to_string(),
        score: 7,
        round_number: 2,
        player_count: 4,
    };
    let leave_msg = ServerMessage::Event(leave_event);
    let leave_json = serde_json::to_string(&leave_msg).unwrap();
    assert!(leave_json.contains(r#""event":"player_left"#));
    assert!(leave_json.contains(r#""player":"TestPlayer"#));
    assert!(leave_json.contains(r#""score":7"#));
    assert!(leave_json.contains(r#""round_number":2"#));
    assert!(leave_json.contains(r#""player_count":4"#));
}

#[test]
fn join_leave_events_survive_tick() {
    use crate::protocol::GameEvent;
    let mut state = GameState::new();
    state.push_event(GameEvent::PlayerJoined {
        player: "AgentA".to_string(),
        role: "agent".to_string(),
        round_number: state.round_number,
        player_count: 1,
    });
    state.tick(0.05);
    state.push_event(GameEvent::PlayerLeft {
        player: "AgentA".to_string(),
        score: 0,
        round_number: state.round_number,
        player_count: 0,
    });
    state.tick(0.05);
    let events = state.take_events();
    assert!(
        events
            .iter()
            .any(|e| matches!(e, GameEvent::PlayerJoined { .. })),
        "PlayerJoined must survive tick() and remain until take_events: {:?}",
        events
    );
    assert!(
        events
            .iter()
            .any(|e| matches!(e, GameEvent::PlayerLeft { .. })),
        "PlayerLeft must survive tick() and remain until take_events: {:?}",
        events
    );
}

#[test]
fn test_round_cycle_events_survive_ticks() {
    use crate::protocol::GameEvent;
    use crate::sim::{GameState, MatchConfig, RoundState};

    let mut state = GameState::new();
    state.config = MatchConfig {
        frag_limit: Some(2),
        time_limit_ticks: None,
        warmup_ticks: 3,
        end_delay_ticks: 3,
        compliance_ping_ticks: None,
        compliance_duration_ticks: 20 * 6,
        boss_spawn_ticks: None,
    };

    let a = uuid::Uuid::new_v4();
    let b = uuid::Uuid::new_v4();
    state.add_player(a, "Alpha".to_string(), crate::protocol::Role::Agent);
    state.add_player(b, "Bravo".to_string(), crate::protocol::Role::Agent);

    assert_eq!(state.round_state, RoundState::Warmup);

    // Warmup → Active: RoundStart must be present after the transition tick.
    for _ in 0..(state.config.warmup_ticks.saturating_sub(1)) {
        state.tick(0.05);
        let _ = state.take_events(); // drain noise; transition not yet
    }
    state.tick(0.05);
    assert_eq!(state.round_state, RoundState::Active);
    let events = state.take_events();
    assert!(
        events.iter().any(|e| matches!(
            e,
            GameEvent::RoundStart {
                round_number: 1,
                ..
            }
        )),
        "RoundStart must survive the Warmup→Active tick: {:?}",
        events
    );

    // Drive frag limit via scores (same path end_round uses).
    *state.scores.entry(a).or_insert(0) = 2;
    state.tick(0.05);
    assert_eq!(state.round_state, RoundState::Ended);
    let events = state.take_events();
    assert!(
        events
            .iter()
            .any(|e| matches!(e, GameEvent::RoundEnd { .. })),
        "RoundEnd must survive the Active→Ended tick: {:?}",
        events
    );

    // Ended delay → Round 2 Start.
    for _ in 0..(state.config.end_delay_ticks.saturating_sub(1)) {
        state.tick(0.05);
        let _ = state.take_events();
    }
    state.tick(0.05);
    assert_eq!(state.round_state, RoundState::Active);
    assert_eq!(state.round_number, 2);
    let events = state.take_events();
    assert!(
        events.iter().any(|e| matches!(
            e,
            GameEvent::RoundStart {
                round_number: 2,
                ..
            }
        )),
        "RoundStart(2) must survive the Ended→Active tick: {:?}",
        events
    );
}

#[test]
fn test_server_round_event_wire_json_shape() {
    use crate::protocol::{GameEvent, PlayerScore, ServerMessage};

    let start = ServerMessage::Event(GameEvent::RoundStart {
        round_number: 2,
        frag_limit: Some(10),
        time_limit: Some(180),
        players: vec!["Alpha".into(), "Bravo".into()],
        previous_winner: Some("Alpha".into()),
        mode_name: default_mode_name(),
        playlist: default_playlist(),
        host_line: default_host_line(),
    });
    let start_json = serde_json::to_string(&start).unwrap();
    assert!(start_json.contains(r#""type":"event""#), "{}", start_json);
    assert!(
        start_json.contains(r#""event":"round_start""#),
        "{}",
        start_json
    );
    assert!(
        start_json.contains(r#""previous_winner":"Alpha""#),
        "{}",
        start_json
    );
    assert!(
        start_json.contains(r#""mode_name":"Contested Frequency""#),
        "{}",
        start_json
    );
    assert!(
        start_json.contains(r#""playlist":"Arena Duel""#),
        "{}",
        start_json
    );

    let end = ServerMessage::Event(GameEvent::RoundEnd {
        winner: Some("Alpha".into()),
        reason: "Frag limit reached".into(),
        final_scores: vec![
            PlayerScore {
                name: "Alpha".into(),
                score: 10,
            },
            PlayerScore {
                name: "Bravo".into(),
                score: 3,
            },
        ],
        winner_score: Some(10),
        mvp: Some("Alpha".into()),
        mvp_frags: Some(10),
        host_line: mvp_host_line("Alpha", 10),
    });
    let end_json = serde_json::to_string(&end).unwrap();
    assert!(end_json.contains(r#""event":"round_end""#), "{}", end_json);
    assert!(end_json.contains(r#""final_scores""#), "{}", end_json);
    assert!(end_json.contains(r#""mvp":"Alpha""#), "{}", end_json);
    assert!(end_json.contains("ROUND MVP"), "{}", end_json);

    // Round-trip on server protocol itself.
    let parsed: ServerMessage = serde_json::from_str(&start_json).unwrap();
    assert!(matches!(
        parsed,
        ServerMessage::Event(GameEvent::RoundStart { .. })
    ));
    let parsed: ServerMessage = serde_json::from_str(&end_json).unwrap();
    assert!(matches!(
        parsed,
        ServerMessage::Event(GameEvent::RoundEnd { .. })
    ));
}

// --- Net WebSocket join/leave/action/round wire paths ---

#[tokio::test]
async fn test_net_ws_agent_hello_welcome_and_connected_command() {
    use crate::net::{GameCommand, NetServer};
    use futures_util::{SinkExt, StreamExt};
    use tokio_tungstenite::{connect_async, tungstenite::Message};

    let (game_tx, mut game_rx) = tokio::sync::mpsc::unbounded_channel();
    let net = NetServer::bind("127.0.0.1:0", game_tx).await.expect("bind");
    let addr = net.local_addr().expect("local_addr");
    tokio::spawn(async move {
        net.accept_loop().await;
    });

    let url = format!("ws://{}", addr);
    let (ws, _) = connect_async(&url).await.expect("connect");
    let (mut sink, mut stream) = ws.split();

    let hello = serde_json::json!({
        "type": "hello",
        "role": "agent",
        "name": "WireAgent"
    });
    sink.send(Message::Text(hello.to_string()))
        .await
        .expect("send hello");

    let welcome_text = tokio::time::timeout(std::time::Duration::from_secs(2), stream.next())
        .await
        .expect("welcome timeout")
        .expect("welcome msg")
        .expect("welcome ok");
    let welcome_str = match welcome_text {
        Message::Text(t) => t,
        other => panic!("expected text welcome, got {:?}", other),
    };
    let welcome: ServerMessage = serde_json::from_str(&welcome_str).expect("parse welcome");
    match welcome {
        ServerMessage::Welcome {
            player_id: Some(_),
            role: Role::Agent,
            mode_name,
            playlist,
        } => {
            assert_eq!(mode_name, default_mode_name());
            assert_eq!(playlist, default_playlist());
        }
        other => panic!("unexpected welcome: {:?}", other),
    }

    let cmd = tokio::time::timeout(std::time::Duration::from_secs(2), game_rx.recv())
        .await
        .expect("cmd timeout")
        .expect("cmd");
    match cmd {
        GameCommand::Connected {
            role: Role::Agent,
            name,
            player_id: Some(_),
            ..
        } => assert_eq!(name, "WireAgent"),
        other => panic!("unexpected cmd: {:?}", other_debug(&other)),
    }

    // Drop connection to exercise disconnect path.
    drop(sink);
    drop(stream);
    let disc = tokio::time::timeout(std::time::Duration::from_secs(2), game_rx.recv())
        .await
        .expect("disc timeout")
        .expect("disc");
    assert!(matches!(disc, GameCommand::Disconnected { .. }));
}

fn other_debug(cmd: &crate::net::GameCommand) -> String {
    match cmd {
        crate::net::GameCommand::Connected { name, role, .. } => {
            format!("Connected({:?},{})", role, name)
        }
        crate::net::GameCommand::Disconnected { .. } => "Disconnected".into(),
        crate::net::GameCommand::Action { .. } => "Action".into(),
        crate::net::GameCommand::Speak { .. } => "Speak".into(),
        crate::net::GameCommand::SetDisplayBehavior { .. } => "SetDisplayBehavior".into(),
    }
}

#[tokio::test]
async fn test_net_ws_spectator_hello_no_player_id() {
    use crate::net::{GameCommand, NetServer};
    use futures_util::{SinkExt, StreamExt};
    use tokio_tungstenite::{connect_async, tungstenite::Message};

    let (game_tx, mut game_rx) = tokio::sync::mpsc::unbounded_channel();
    let net = NetServer::bind("127.0.0.1:0", game_tx).await.expect("bind");
    let addr = net.local_addr().expect("local_addr");
    tokio::spawn(async move {
        net.accept_loop().await;
    });

    let (ws, _) = connect_async(format!("ws://{}", addr))
        .await
        .expect("connect");
    let (mut sink, mut stream) = ws.split();
    sink.send(Message::Text(
        r#"{"type":"hello","role":"spectator","name":"Eyes"}"#.into(),
    ))
    .await
    .unwrap();

    let welcome_text = tokio::time::timeout(std::time::Duration::from_secs(2), stream.next())
        .await
        .unwrap()
        .unwrap()
        .unwrap();
    let welcome_str = match welcome_text {
        Message::Text(t) => t,
        other => panic!("{:?}", other),
    };
    let welcome: ServerMessage = serde_json::from_str(&welcome_str).unwrap();
    match welcome {
        ServerMessage::Welcome {
            player_id: None,
            role: Role::Spectator,
            mode_name,
            playlist,
        } => {
            assert_eq!(mode_name, default_mode_name());
            assert_eq!(playlist, default_playlist());
        }
        other => panic!("{:?}", other),
    }

    let cmd = tokio::time::timeout(std::time::Duration::from_secs(2), game_rx.recv())
        .await
        .unwrap()
        .unwrap();
    match cmd {
        GameCommand::Connected {
            player_id: None,
            role: Role::Spectator,
            name,
            ..
        } => assert_eq!(name, "Eyes"),
        other => panic!("{}", other_debug(&other)),
    }
}

#[tokio::test]
async fn test_net_ws_action_forwarded_for_agent() {
    use crate::net::{GameCommand, NetServer};
    use futures_util::{SinkExt, StreamExt};
    use tokio_tungstenite::{connect_async, tungstenite::Message};

    let (game_tx, mut game_rx) = tokio::sync::mpsc::unbounded_channel();
    let net = NetServer::bind("127.0.0.1:0", game_tx).await.expect("bind");
    let addr = net.local_addr().expect("local_addr");
    let clients = net.clients.clone();
    tokio::spawn(async move {
        net.accept_loop().await;
    });

    let (ws, _) = connect_async(format!("ws://{}", addr))
        .await
        .expect("connect");
    let (mut sink, mut stream) = ws.split();
    sink.send(Message::Text(
        r#"{"type":"hello","role":"human","name":"Shooter"}"#.into(),
    ))
    .await
    .unwrap();

    let _ = tokio::time::timeout(std::time::Duration::from_secs(2), stream.next())
        .await
        .unwrap()
        .unwrap()
        .unwrap();
    let connected = tokio::time::timeout(std::time::Duration::from_secs(2), game_rx.recv())
        .await
        .unwrap()
        .unwrap();
    let player_id = match connected {
        GameCommand::Connected {
            player_id: Some(pid),
            ..
        } => pid,
        other => panic!("{}", other_debug(&other)),
    };

    sink.send(Message::Text(
        r#"{"type":"action","forward":true,"fire":true}"#.into(),
    ))
    .await
    .unwrap();

    let action_cmd = tokio::time::timeout(std::time::Duration::from_secs(2), game_rx.recv())
        .await
        .unwrap()
        .unwrap();
    match action_cmd {
        GameCommand::Action {
            player_id: pid,
            action,
        } => {
            assert_eq!(pid, player_id);
            assert!(action.forward);
            assert!(action.fire);
        }
        other => panic!("{}", other_debug(&other)),
    }

    // Broadcast a snapshot through the client fan-out path used by the game loop.
    {
        use crate::session::broadcast_to_clients;
        let snap = ServerMessage::Snapshot(Snapshot {
            tick: 1,
            players: vec![],
            round_state: Some("active".into()),
            round_time_left: Some(100),
            frag_limit: Some(10),
            shot_results: vec![],
            mode_name: default_mode_name(),
            playlist: default_playlist(),
            pressure: None,
            host_line: default_host_line(),
            mvp: None,
            mvp_frags: None,
            pickups: vec![],
            map_id: default_map_id(),
            map_name: default_map_name(),
            episode_id: None,
            episode_title: None,
            episode_objective: None,
            episode_progress: None,
            episode_phase: None,
            jammer_dish: None,
        });
        broadcast_to_clients(&clients, &[snap]).await;
        let msg = tokio::time::timeout(std::time::Duration::from_secs(2), stream.next())
            .await
            .unwrap()
            .unwrap()
            .unwrap();
        match msg {
            Message::Text(t) => {
                let parsed: ServerMessage = serde_json::from_str(&t).unwrap();
                assert!(matches!(parsed, ServerMessage::Snapshot(_)));
            }
            other => panic!("{:?}", other),
        }
    }
}

#[tokio::test]
async fn test_net_ws_invalid_hello_closes_without_connected() {
    use crate::net::NetServer;
    use futures_util::{SinkExt, StreamExt};
    use tokio_tungstenite::{connect_async, tungstenite::Message};

    let (game_tx, mut game_rx) = tokio::sync::mpsc::unbounded_channel();
    let net = NetServer::bind("127.0.0.1:0", game_tx).await.expect("bind");
    let addr = net.local_addr().expect("local_addr");
    tokio::spawn(async move {
        net.accept_loop().await;
    });

    let (ws, _) = connect_async(format!("ws://{}", addr))
        .await
        .expect("connect");
    let (mut sink, mut stream) = ws.split();
    sink.send(Message::Text(r#"{"type":"action","forward":true}"#.into()))
        .await
        .unwrap();

    // Connection should end without a Connected command.
    let _ = tokio::time::timeout(std::time::Duration::from_millis(500), stream.next()).await;
    let maybe = tokio::time::timeout(std::time::Duration::from_millis(300), game_rx.recv()).await;
    assert!(
        maybe.is_err() || maybe.as_ref().ok().and_then(|o| o.as_ref()).is_none(),
        "invalid hello must not emit Connected"
    );
}

#[tokio::test]
async fn test_session_plus_net_join_leave_round_broadcast_path() {
    use crate::net::NetServer;
    use crate::session::{broadcast_to_clients, GameSession};
    use futures_util::{SinkExt, StreamExt};
    use tokio_tungstenite::{connect_async, tungstenite::Message};

    let (game_tx, mut game_rx) = tokio::sync::mpsc::unbounded_channel();
    let net = NetServer::bind("127.0.0.1:0", game_tx).await.expect("bind");
    let addr = net.local_addr().expect("local_addr");
    let clients = net.clients.clone();
    tokio::spawn(async move {
        net.accept_loop().await;
    });

    let mut session = GameSession::new();
    session.spawn_bots(2);
    session.state.start_round();

    let (ws, _) = connect_async(format!("ws://{}", addr))
        .await
        .expect("connect");
    let (mut sink, mut stream) = ws.split();
    sink.send(Message::Text(
        r#"{"type":"hello","role":"agent","name":"RoundFox"}"#.into(),
    ))
    .await
    .unwrap();
    let _ = tokio::time::timeout(std::time::Duration::from_secs(2), stream.next())
        .await
        .unwrap()
        .unwrap()
        .unwrap();

    let cmd = tokio::time::timeout(std::time::Duration::from_secs(2), game_rx.recv())
        .await
        .unwrap()
        .unwrap();
    session.apply_command(cmd);

    let joined = session.state.take_events();
    assert!(joined.iter().any(|e| matches!(
        e,
        GameEvent::PlayerJoined {
            player,
            ..
        } if player == "RoundFox"
    )));

    // Re-push join onto queue then tick so Event is broadcast on the wire.
    session.state.push_event(GameEvent::PlayerJoined {
        player: "RoundFox".into(),
        role: "agent".into(),
        round_number: session.state.round_number,
        player_count: session.state.players.len(),
    });
    let messages = session.tick_messages(0.05);
    broadcast_to_clients(&clients, &messages).await;

    let mut saw_snapshot = false;
    let mut saw_join_event = false;
    for _ in 0..8 {
        let msg = tokio::time::timeout(std::time::Duration::from_millis(500), stream.next()).await;
        let Ok(Some(Ok(Message::Text(t)))) = msg else {
            break;
        };
        if let Ok(parsed) = serde_json::from_str::<ServerMessage>(&t) {
            match parsed {
                ServerMessage::Snapshot(_) => saw_snapshot = true,
                ServerMessage::Event(GameEvent::PlayerJoined { player, .. })
                    if player == "RoundFox" =>
                {
                    saw_join_event = true;
                }
                _ => {}
            }
        }
        if saw_snapshot && saw_join_event {
            break;
        }
    }
    assert!(saw_snapshot, "client should receive Snapshot");
    assert!(saw_join_event, "client should receive PlayerJoined event");

    drop(sink);
    drop(stream);
    if let Ok(Some(disc)) =
        tokio::time::timeout(std::time::Duration::from_secs(2), game_rx.recv()).await
    {
        session.apply_command(disc);
        let left = session.state.take_events();
        assert!(left
            .iter()
            .any(|e| matches!(e, GameEvent::PlayerLeft { player, .. } if player == "RoundFox")));
    }
}

#[test]
fn test_look_at_player_id_sets_yaw() {
    use std::f32::consts::PI;
    let mut state = GameState::new();
    state.start_round();

    let aimer_id = Uuid::new_v4();
    let target_id = Uuid::new_v4();
    state.add_player(aimer_id, "Aimer".to_string(), Role::Agent);
    state.add_player(target_id, "Target".to_string(), Role::Agent);

    let aimer_idx = state.players.iter().position(|p| p.id == aimer_id).unwrap();
    let target_idx = state
        .players
        .iter()
        .position(|p| p.id == target_id)
        .unwrap();
    state.players[aimer_idx].x = 0.0;
    state.players[aimer_idx].z = 0.0;
    state.players[aimer_idx].yaw = 0.0;
    state.players[target_idx].x = 0.0;
    state.players[target_idx].z = 10.0;

    state.set_action(
        aimer_id,
        Action {
            look_at: Some(crate::protocol::LookAt {
                y: None,
                player_id: Some(target_id),
                x: None,
                z: None,
            }),
            ..Default::default()
        },
    );
    state.tick(0.05);

    let yaw = state.players[aimer_idx].yaw;
    let expected = PI / 2.0;
    let mut diff = (yaw - expected).abs();
    if diff > PI {
        diff = 2.0 * PI - diff;
    }
    assert!(
        diff < 0.05,
        "look_at player_id should face target, yaw={yaw} expected~{expected}"
    );
}

#[test]
fn test_look_at_world_xz_sets_yaw() {
    use std::f32::consts::PI;
    let mut state = GameState::new();
    state.start_round();

    let aimer_id = Uuid::new_v4();
    state.add_player(aimer_id, "Aimer".to_string(), Role::Agent);
    let aimer_idx = state.players.iter().position(|p| p.id == aimer_id).unwrap();
    state.players[aimer_idx].x = 0.0;
    state.players[aimer_idx].z = 0.0;
    state.players[aimer_idx].yaw = 0.0;

    state.set_action(
        aimer_id,
        Action {
            look_at: Some(crate::protocol::LookAt {
                y: None,
                player_id: None,
                x: Some(-10.0),
                z: Some(0.0),
            }),
            ..Default::default()
        },
    );
    state.tick(0.05);

    let yaw = state.players[aimer_idx].yaw;
    let expected = PI;
    let mut diff = (yaw - expected).abs();
    if diff > PI {
        diff = 2.0 * PI - diff;
    }
    assert!(
        diff < 0.05,
        "look_at x/z should face world point, yaw={yaw} expected~{expected}"
    );
}

#[test]
fn test_shot_results_hit_and_hit_event() {
    let mut state = GameState::new();
    state.start_round();

    let shooter_id = Uuid::new_v4();
    let target_id = Uuid::new_v4();
    state.add_player(shooter_id, "Shooter".to_string(), Role::Agent);
    state.add_player(target_id, "Victim".to_string(), Role::Agent);

    let shooter_idx = state
        .players
        .iter()
        .position(|p| p.id == shooter_id)
        .unwrap();
    let target_idx = state
        .players
        .iter()
        .position(|p| p.id == target_id)
        .unwrap();
    state.players[shooter_idx].x = 0.0;
    state.players[shooter_idx].z = 0.0;
    state.players[shooter_idx].yaw = 0.0;
    state.players[target_idx].x = 5.0;
    state.players[target_idx].z = 0.0;

    let hp_before = state.players[target_idx].hp;

    state.set_action(
        shooter_id,
        Action {
            fire: true,
            ..Default::default()
        },
    );
    state.tick(0.05);

    let snap = state.snapshot();
    assert_eq!(snap.shot_results.len(), 1, "one shot_result expected");
    let shot = &snap.shot_results[0];
    assert_eq!(shot.shooter_id, shooter_id);
    assert!(shot.hit, "aligned flechette should hit");
    assert_eq!(shot.target_id, Some(target_id));
    assert_eq!(shot.damage, WeaponType::Flechette.damage());
    assert_eq!(
        shot.target_hp_after,
        Some(hp_before - WeaponType::Flechette.damage())
    );

    let hit_events: Vec<_> = state
        .events
        .iter()
        .filter(|e| matches!(e, GameEvent::Hit { .. }))
        .collect();
    assert_eq!(hit_events.len(), 1, "Hit event on damage");
    match &hit_events[0] {
        GameEvent::Hit {
            damage,
            target_hp_after,
            target_id: tid,
            ..
        } => {
            assert_eq!(*damage, WeaponType::Flechette.damage());
            assert_eq!(*target_hp_after, hp_before - WeaponType::Flechette.damage());
            assert_eq!(*tid, target_id);
        }
        _ => unreachable!(),
    }
}

#[test]
fn test_shot_results_miss() {
    use std::f32::consts::PI;
    let mut state = GameState::new();
    state.start_round();

    let shooter_id = Uuid::new_v4();
    let target_id = Uuid::new_v4();
    state.add_player(shooter_id, "Shooter".to_string(), Role::Agent);
    state.add_player(target_id, "Victim".to_string(), Role::Agent);

    let shooter_idx = state
        .players
        .iter()
        .position(|p| p.id == shooter_id)
        .unwrap();
    let target_idx = state
        .players
        .iter()
        .position(|p| p.id == target_id)
        .unwrap();
    state.players[shooter_idx].x = 0.0;
    state.players[shooter_idx].z = 0.0;
    state.players[shooter_idx].yaw = PI / 2.0;
    state.players[target_idx].x = 5.0;
    state.players[target_idx].z = 0.0;

    state.set_action(
        shooter_id,
        Action {
            fire: true,
            ..Default::default()
        },
    );
    state.tick(0.05);

    let snap = state.snapshot();
    assert_eq!(snap.shot_results.len(), 1);
    let shot = &snap.shot_results[0];
    assert!(!shot.hit);
    assert!(shot.target_id.is_none());
    assert_eq!(shot.damage, 0);
    assert!(
        !state
            .events
            .iter()
            .any(|e| matches!(e, GameEvent::Hit { .. })),
        "no Hit event on miss"
    );
}

#[test]
fn test_snapshot_carries_contested_frequency_mode_identity() {
    let state = GameState::new();
    let snap = state.snapshot();
    assert_eq!(snap.mode_name, "Contested Frequency");
    assert_eq!(snap.playlist, "Arena Duel");
    assert!(snap.pressure.is_none());
    let expected_warm = warmup_host_line("Arena Duel", &[], 2);
    assert_eq!(snap.host_line, expected_warm);
    assert_eq!(snap.round_time_left, Some(2));
    let json = serde_json::to_value(&snap).unwrap();
    assert_eq!(json["mode_name"], "Contested Frequency");
    assert_eq!(json["playlist"], "Arena Duel");
    assert!(json.get("pressure").is_none() || json["pressure"].is_null());
    assert_eq!(json["host_line"], expected_warm);
}

#[test]
fn test_compliance_ping_fires_once_and_sets_pressure() {
    let mut state = GameState::new();
    state.config = MatchConfig {
        frag_limit: Some(99),
        time_limit_ticks: Some(20 * 60),
        warmup_ticks: 2,
        end_delay_ticks: 5,
        compliance_ping_ticks: Some(5),
        compliance_duration_ticks: 10,
        boss_spawn_ticks: None,
    };
    let id = Uuid::new_v4();
    state.add_player(id, "Scrap".to_string(), Role::Human);

    // Drain warmup into Active.
    state.tick(0.05);
    state.tick(0.05);
    let _ = state.take_events();
    assert_eq!(state.round_state, RoundState::Active);
    assert!(!state.compliance_fired);

    // Ticks 1..4: no ping yet.
    for _ in 0..4 {
        state.tick(0.05);
        let ev = state.take_events();
        assert!(
            !ev.iter()
                .any(|e| matches!(e, GameEvent::CompliancePing { .. })),
            "too early: {:?}",
            ev
        );
    }

    // Tick 5: compliance fires.
    state.tick(0.05);
    let ev = state.take_events();
    let ping = ev
        .iter()
        .find_map(|e| match e {
            GameEvent::CompliancePing {
                message,
                duration_ticks,
            } => Some((message.clone(), *duration_ticks)),
            _ => None,
        })
        .expect("compliance_ping event");
    assert!(ping.0.contains("CONTINUANCE"));
    assert_eq!(ping.1, 10);
    assert!(state.compliance_fired);
    // Fire sets ticks_left after the decrement check, so the fire tick keeps full duration.
    assert_eq!(state.compliance_ticks_left, 10);

    let snap = state.snapshot();
    assert_eq!(snap.pressure.as_deref(), Some("compliance"));
    assert_eq!(snap.host_line, compliance_host_line());

    // Second fire must not happen.
    for _ in 0..20 {
        state.tick(0.05);
        let ev = state.take_events();
        assert!(
            !ev.iter()
                .any(|e| matches!(e, GameEvent::CompliancePing { .. })),
            "duplicate ping: {:?}",
            ev
        );
    }
    assert!(state.compliance_ticks_left == 0);
    assert!(state.snapshot().pressure.is_none());
}

#[test]
fn test_compliance_pressure_slows_movement() {
    let mut state = GameState::new();
    state.config = MatchConfig {
        frag_limit: Some(99),
        time_limit_ticks: Some(20 * 60),
        warmup_ticks: 1,
        end_delay_ticks: 5,
        compliance_ping_ticks: None,
        compliance_duration_ticks: 20,
        boss_spawn_ticks: None,
    };
    let id = Uuid::new_v4();
    state.add_player(id, "Runner".to_string(), Role::Human);
    state.tick(0.05); // warmup -> active
    let _ = state.take_events();

    let start_x = state.players[0].x;
    state.set_action(
        id,
        Action {
            forward: true,
            ..Default::default()
        },
    );
    state.tick(0.05);
    let normal_dx = (state.players[0].x - start_x).abs();

    // Reset position-ish by measuring another normal step
    let x2 = state.players[0].x;
    state.tick(0.05);
    let normal_dx2 = (state.players[0].x - x2).abs();

    state.compliance_ticks_left = 20;
    let x3 = state.players[0].x;
    state.tick(0.05);
    let slow_dx = (state.players[0].x - x3).abs();

    assert!(
        slow_dx < normal_dx2 * 0.75,
        "compliance should slow move: normal={} slow={}",
        normal_dx2,
        slow_dx
    );
    assert!(normal_dx > 0.0);
}

#[test]
fn test_compliance_ping_wire_json_shape() {
    let event = GameEvent::CompliancePing {
        message: compliance_host_line(),
        duration_ticks: 120,
    };
    let msg = ServerMessage::Event(event);
    let json = serde_json::to_value(&msg).unwrap();
    assert_eq!(json["type"], "event");
    assert_eq!(json["event"], "compliance_ping");
    assert_eq!(json["duration_ticks"], 120);
    assert!(json["message"].as_str().unwrap().contains("CONTINUANCE"));
}

#[test]
fn test_welcome_includes_mode_identity() {
    let welcome = ServerMessage::Welcome {
        player_id: None,
        role: Role::Spectator,
        mode_name: default_mode_name(),
        playlist: default_playlist(),
    };
    let json = serde_json::to_value(&welcome).unwrap();
    assert_eq!(json["mode_name"], "Contested Frequency");
    assert_eq!(json["playlist"], "Arena Duel");
}

#[test]
fn test_snapshot_host_line_sticky_for_mid_join() {
    // Mid-join / observe must see Host chrome without waiting for RoundStart.
    let mut state = GameState::new();
    state.config = MatchConfig {
        frag_limit: Some(99),
        time_limit_ticks: Some(20 * 60),
        warmup_ticks: 2,
        end_delay_ticks: 5,
        compliance_ping_ticks: Some(5),
        compliance_duration_ticks: 8,
        boss_spawn_ticks: None,
    };
    state.add_player(Uuid::new_v4(), "Late".to_string(), Role::Human);

    // Warmup: Contested Frequency countdown Host drama sticky on Snapshot.
    let warm = state.snapshot();
    assert!(warm.pressure.is_none());
    let expected_warm = warmup_host_line("Arena Duel", &[], 1); // warmup_ticks=2 -> 1s ceil
    assert_eq!(warm.host_line, expected_warm);
    assert_eq!(warm.round_time_left, Some(1));
    let warm_json = serde_json::to_value(&warm).unwrap();
    assert_eq!(warm_json["host_line"], expected_warm);

    // Enter Active and fire compliance.
    state.tick(0.05);
    state.tick(0.05);
    let _ = state.take_events();
    for _ in 0..5 {
        state.tick(0.05);
    }
    let _ = state.take_events();
    assert!(state.compliance_ticks_left > 0);

    let during = state.snapshot();
    assert_eq!(during.pressure.as_deref(), Some("compliance"));
    assert_eq!(during.host_line, compliance_host_line());
    let during_json = serde_json::to_value(&during).unwrap();
    assert_eq!(during_json["host_line"], compliance_host_line());

    // After pressure ends, Snapshot returns to league Host line.
    while state.compliance_ticks_left > 0 {
        state.tick(0.05);
    }
    let after = state.snapshot();
    assert!(after.pressure.is_none());
    assert_eq!(after.host_line, default_host_line());
}

#[test]
fn test_snapshot_host_line_defaults_when_absent_on_wire() {
    // Old Snapshot without host_line still deserializes (mid-join clients / adapters).
    let raw = r#"{
        "tick": 1,
        "players": [],
        "mode_name": "Contested Frequency",
        "playlist": "Arena Duel"
    }"#;
    let snap: Snapshot = serde_json::from_str(raw).expect("legacy snapshot");
    assert_eq!(snap.host_line, default_host_line());
}

#[test]
fn test_compliance_drone_spawns_once_with_pressure_and_host() {
    let mut state = GameState::new();
    let a = Uuid::new_v4();
    state.add_player(a, "Rusher".into(), Role::Agent);
    state.config = MatchConfig {
        frag_limit: Some(99),
        time_limit_ticks: Some(20 * 60),
        warmup_ticks: 1,
        end_delay_ticks: 20,
        compliance_ping_ticks: None,
        compliance_duration_ticks: 10,
        boss_spawn_ticks: Some(3),
    };
    // Warmup -> Active
    state.tick(0.05);
    assert_eq!(state.round_state, RoundState::Active);
    assert!(!state.boss_spawned);

    state.tick(0.05); // round_ticks 1
    state.tick(0.05); // 2
    let _ = state.take_events();
    state.tick(0.05); // 3: spawn
    let events = state.take_events();
    assert!(
        events.iter().any(|e| matches!(
            e,
            GameEvent::BossSpawn { name, hp, .. }
            if name == BOSS_NAME && *hp == BOSS_MAX_HP
        )),
        "expected BossSpawn, got {:?}",
        events
    );
    assert!(state.boss_id.is_some());
    assert!(state.boss_spawned);
    let snap = state.snapshot();
    assert_eq!(snap.pressure.as_deref(), Some("compliance_drone"));
    assert_eq!(snap.host_line, boss_host_line());
    assert!(snap.players.iter().any(|p| p.name == BOSS_NAME
        && p.behavior.as_deref() == Some("Compliance")
        && p.hp == BOSS_MAX_HP));

    // Second spawn attempt is a no-op.
    let before = state.players.len();
    assert!(state.spawn_compliance_drone().is_none());
    assert_eq!(state.players.len(), before);
}

#[test]
fn test_boss_wiped_on_round_end_emits_boss_down_no_killer() {
    let mut state = GameState::new();
    let a = Uuid::new_v4();
    state.add_player(a, "Rusher".into(), Role::Agent);
    state.config = MatchConfig {
        frag_limit: Some(99),
        time_limit_ticks: Some(5),
        warmup_ticks: 1,
        end_delay_ticks: 20,
        compliance_ping_ticks: None,
        compliance_duration_ticks: 10,
        boss_spawn_ticks: Some(1),
    };
    state.tick(0.05); // Warmup -> Active
    let _ = state.take_events();
    state.tick(0.05); // spawn boss
    let _ = state.take_events();
    assert!(
        state.boss_id.is_some(),
        "boss should be alive before round end"
    );
    let boss_id = state.boss_id.unwrap();

    // Drain Active time limit into Ended.
    for _ in 0..10 {
        state.tick(0.05);
        if state.round_state == RoundState::Ended {
            break;
        }
    }
    assert_eq!(state.round_state, RoundState::Ended);
    let events = state.take_events();
    let wipe = events.iter().find(|e| {
        matches!(
            e,
            GameEvent::BossDown {
                killer: None,
                message,
                ..
            } if message == &boss_round_wipe_host_line()
        )
    });
    assert!(
        wipe.is_some(),
        "expected BossDown wipe (killer null) on round end, got {:?}",
        events
    );
    assert!(
        events
            .iter()
            .any(|e| matches!(e, GameEvent::RoundEnd { .. })),
        "expected RoundEnd after wipe, got {:?}",
        events
    );
    assert!(state.boss_id.is_none());
    let snap = state.snapshot();
    assert!(
        snap.pressure.is_none(),
        "Ended must not keep compliance_drone pressure"
    );
    assert!(
        !snap.players.iter().any(|p| p.name == BOSS_NAME),
        "drone must be absent from Ended snapshot"
    );
    let _ = boss_id;
}

#[test]
fn test_compliance_drone_killable_emits_boss_down_no_respawn() {
    let mut state = GameState::new();
    let shooter = Uuid::new_v4();
    state.add_player(shooter, "Rusher".into(), Role::Agent);
    state.config = MatchConfig {
        frag_limit: Some(99),
        time_limit_ticks: Some(20 * 60),
        warmup_ticks: 1,
        end_delay_ticks: 20,
        compliance_ping_ticks: None,
        compliance_duration_ticks: 10,
        boss_spawn_ticks: Some(1),
    };
    state.tick(0.05); // warmup -> Active
    let _ = state.take_events();
    state.tick(0.05); // spawn at tick 1
    let _ = state.take_events();
    let boss_id = state.boss_id.expect("boss alive");

    // Point Rusher at boss and dump damage with Rail-level hits.
    {
        let boss = state.players.iter().find(|p| p.id == boss_id).unwrap();
        let bx = boss.x;
        let bz = boss.z;
        let rusher = state.players.iter_mut().find(|p| p.id == shooter).unwrap();
        rusher.x = bx - 5.0;
        rusher.z = bz;
        rusher.yaw = 0.0; // facing +x toward boss
        rusher.weapon = WeaponType::Rail;
        rusher.pending_action = Action {
            fire: true,
            ..Default::default()
        };
    }
    // Keep firing until boss is down (Rail 75 dmg; 200 HP => 3 hits).
    let mut saw_down = false;
    for _ in 0..20 {
        if let Some(r) = state.players.iter_mut().find(|p| p.id == shooter) {
            r.fire_cooldown = 0;
            r.pending_action.fire = true;
        }
        state.tick(0.05);
        let events = state.take_events();
        if events
            .iter()
            .any(|e| matches!(e, GameEvent::BossDown { .. }))
        {
            saw_down = true;
            assert!(
                events.iter().any(|e| matches!(
                    e,
                    GameEvent::BossDown {
                        name,
                        killer: Some(k),
                        message,
                        ..
                    } if name == BOSS_NAME && k == "Rusher" && message == &boss_down_host_line()
                )),
                "boss_down shape bad: {:?}",
                events
            );
            break;
        }
    }
    assert!(saw_down, "expected BossDown after Rail volleys");
    assert!(state.boss_id.is_none());
    assert!(!state.players.iter().any(|p| p.name == BOSS_NAME));
    assert_eq!(state.snapshot().pressure, None);
    // Advance past normal respawn window: drone must not return.
    for _ in 0..80 {
        state.tick(0.05);
        let _ = state.take_events();
    }
    assert!(!state
        .players
        .iter()
        .any(|p| p.name == BOSS_NAME || p.is_boss));
}

#[test]
fn test_boss_down_wire_json_and_compliance_ai_acts() {
    let mut state = GameState::new();
    let target = Uuid::new_v4();
    state.add_player(target, "Sniper".into(), Role::Agent);
    state.start_round();
    state.spawn_compliance_drone().expect("spawn");
    let boss_id = state.boss_id.unwrap();
    let bot = state
        .bots
        .iter()
        .find(|b| b.player_id == boss_id)
        .cloned()
        .expect("compliance controller");
    let action = bot.update(&state);
    // Should turn and/or fire toward the only scrap fighter.
    assert!(
        action.fire
            || action.turn_left
            || action.turn_right
            || action.forward
            || action.back
            || action.left
            || action.right,
        "Compliance AI should produce intent, got {:?}",
        action
    );

    let down = GameEvent::BossDown {
        name: BOSS_NAME.into(),
        boss_id,
        killer: None,
        message: boss_down_host_line(),
    };
    let v = serde_json::to_value(&down).unwrap();
    assert_eq!(v["event"], "boss_down");
    assert!(v.get("killer").is_none());
}

#[test]
fn test_sim_pickups_present_in_snapshot() {
    let state = GameState::new();
    let snap = state.snapshot();
    assert_eq!(snap.pickups.len(), 6);
    let ids: Vec<_> = snap.pickups.iter().map(|p| p.id.as_str()).collect();
    assert!(ids.contains(&"pad_rail"));
    assert!(ids.contains(&"pad_scatter"));
    assert!(ids.contains(&"pad_flechette"));
    assert!(ids.contains(&"pad_health_n"));
    assert!(ids.contains(&"pad_health_s"));
    assert!(ids.contains(&"pad_armor"));
    assert!(snap.pickups.iter().all(|p| p.available));
    let health = snap
        .pickups
        .iter()
        .find(|p| p.id == "pad_health_n")
        .unwrap();
    assert_eq!(health.kind, "health");
    assert_eq!(health.amount, Some(40));
    let armor = snap.pickups.iter().find(|p| p.id == "pad_armor").unwrap();
    assert_eq!(armor.kind, "armor");
    assert_eq!(armor.amount, Some(25));
}

/// Stand a fighter on the pad with this id, wherever the map has put it and
/// whatever it is standing on. Tests that hard-coded pad coordinates broke
/// every time a map was laid out again; asking the map is free.
fn stand_on_pad(state: &mut GameState, player: Uuid, pad_id: &str) {
    let (x, z, floor) = state
        .pickups
        .iter()
        .find(|p| p.id == pad_id)
        .map(|p| (p.x, p.z, p.floor))
        .unwrap_or_else(|| panic!("no pad {pad_id} on {}", state.map.name()));
    if let Some(p) = state.players.iter_mut().find(|p| p.id == player) {
        p.x = x;
        p.z = z;
        p.y = crate::sim::PLAYER_FLOOR_Y + floor;
    }
}

/// Put a fighter somewhere no pad can reach it, so a respawn timer can run
/// without the pad being claimed again the moment it comes back.
fn park_away_from_pads(state: &mut GameState, player: Uuid) {
    if let Some(p) = state.players.iter_mut().find(|p| p.id == player) {
        p.x = 0.0;
        p.z = 0.0;
        p.y = crate::sim::PLAYER_FLOOR_Y;
    }
    let clash = state
        .pickups
        .iter()
        .any(|p| (p.x * p.x + p.z * p.z).sqrt() < crate::sim::PICKUP_CLAIM_RADIUS * 2.0);
    assert!(!clash, "the origin has to stay free of pads for this test");
}

#[test]
fn test_sim_pickup_claim_changes_weapon_and_emits_event() {
    let mut state = GameState::new();
    state.start_round();
    let id = Uuid::new_v4();
    state.add_player(id, "Rusher".into(), Role::Human);
    stand_on_pad(&mut state, id, "pad_rail");
    if let Some(p) = state.players.iter_mut().find(|p| p.id == id) {
        p.weapon = WeaponType::Flechette;
    }
    state.tick(0.05);
    let player = state.players.iter().find(|p| p.id == id).unwrap();
    assert_eq!(player.weapon, WeaponType::Rail);
    let events = state.take_events();
    assert!(
        events.iter().any(|e| matches!(
            e,
            GameEvent::Pickup {
                kind,
                weapon,
                pickup_id,
                ..
            } if kind == "weapon" && weapon == "Rail" && pickup_id == "pad_rail"
        )),
        "expected pickup event, got {:?}",
        events
    );
    let rail = state.pickups.iter().find(|p| p.id == "pad_rail").unwrap();
    assert!(!rail.available);
    assert_eq!(rail.respawn_timer, Some(PICKUP_RESPAWN_TICKS));
}

#[test]
fn test_sim_pickup_respawns_after_timer() {
    let mut state = GameState::new();
    state.start_round();
    let id = Uuid::new_v4();
    state.add_player(id, "Rusher".into(), Role::Human);
    stand_on_pad(&mut state, id, "pad_rail");
    state.tick(0.05);
    assert!(
        !state
            .pickups
            .iter()
            .find(|p| p.id == "pad_rail")
            .unwrap()
            .available
    );
    // Move off pad so we do not re-claim instantly.
    park_away_from_pads(&mut state, id);
    for _ in 0..PICKUP_RESPAWN_TICKS {
        state.tick(0.05);
    }
    let rail = state.pickups.iter().find(|p| p.id == "pad_rail").unwrap();
    assert!(rail.available, "rail pad should respawn");
    assert!(rail.respawn_timer.is_none());
}

#[test]
fn test_sim_pickup_reset_on_round_start() {
    let mut state = GameState::new();
    state.start_round();
    let id = Uuid::new_v4();
    state.add_player(id, "Rusher".into(), Role::Human);
    stand_on_pad(&mut state, id, "pad_rail");
    state.tick(0.05);
    assert!(
        !state
            .pickups
            .iter()
            .find(|p| p.id == "pad_rail")
            .unwrap()
            .available
    );
    state.end_round("test".into());
    state.start_round();
    assert!(state.pickups.iter().all(|p| p.available));
}

#[test]
fn test_sim_health_pad_heals_and_emits_kind() {
    let mut state = GameState::new();
    state.start_round();
    let id = Uuid::new_v4();
    state.add_player(id, "Rusher".into(), Role::Human);
    stand_on_pad(&mut state, id, "pad_health_n");
    if let Some(p) = state.players.iter_mut().find(|p| p.id == id) {
        p.hp = 40;
    }
    state.tick(0.05);
    let player = state.players.iter().find(|p| p.id == id).unwrap();
    assert_eq!(player.hp, 80);
    let events = state.take_events();
    assert!(
        events.iter().any(|e| matches!(
            e,
            GameEvent::Pickup {
                kind,
                amount: Some(40),
                pickup_id,
                ..
            } if kind == "health" && pickup_id == "pad_health_n"
        )),
        "expected health pickup event, got {:?}",
        events
    );
    let pad = state
        .pickups
        .iter()
        .find(|p| p.id == "pad_health_n")
        .unwrap();
    assert!(!pad.available);
    assert_eq!(pad.respawn_timer, Some(HEALTH_PICKUP_RESPAWN_TICKS));
}

#[test]
fn test_sim_health_pad_skipped_at_full_hp() {
    let mut state = GameState::new();
    state.start_round();
    let id = Uuid::new_v4();
    state.add_player(id, "Rusher".into(), Role::Human);
    stand_on_pad(&mut state, id, "pad_health_n");
    if let Some(p) = state.players.iter_mut().find(|p| p.id == id) {
        p.hp = 100;
    }
    state.tick(0.05);
    let pad = state
        .pickups
        .iter()
        .find(|p| p.id == "pad_health_n")
        .unwrap();
    assert!(pad.available, "full HP should not claim health pad");
}

#[test]
fn test_sim_armor_pad_grants_armor_and_absorbs_damage() {
    let mut state = GameState::new();
    state.start_round();
    let id = Uuid::new_v4();
    state.add_player(id, "Rusher".into(), Role::Human);
    stand_on_pad(&mut state, id, "pad_armor");
    state.tick(0.05);
    let player = state.players.iter().find(|p| p.id == id).unwrap();
    assert_eq!(player.armor, 25);
    let events = state.take_events();
    assert!(
        events.iter().any(|e| matches!(
            e,
            GameEvent::Pickup {
                kind,
                amount: Some(25),
                pickup_id,
                ..
            } if kind == "armor" && pickup_id == "pad_armor"
        )),
        "expected armor pickup event, got {:?}",
        events
    );

    let shooter = Uuid::new_v4();
    state.add_player(shooter, "Shooter".into(), Role::Agent);
    if let Some(p) = state.players.iter_mut().find(|p| p.id == id) {
        p.x = 0.0;
        p.z = 0.0;
        p.yaw = 0.0;
        p.armor = 10;
        p.hp = 100;
    }
    if let Some(p) = state.players.iter_mut().find(|p| p.id == shooter) {
        p.x = -5.0;
        p.z = 0.0;
        p.yaw = 0.0;
        p.weapon = WeaponType::Flechette;
        p.pending_action.fire = true;
    }
    state.tick(0.05);
    let victim = state.players.iter().find(|p| p.id == id).unwrap();
    assert_eq!(victim.armor, 0);
    assert_eq!(victim.hp, 85);
}

#[test]
fn test_sim_health_pad_respawns_after_timer() {
    let mut state = GameState::new();
    state.start_round();
    let id = Uuid::new_v4();
    state.add_player(id, "Rusher".into(), Role::Human);
    stand_on_pad(&mut state, id, "pad_health_n");
    if let Some(p) = state.players.iter_mut().find(|p| p.id == id) {
        p.hp = 50;
    }
    state.tick(0.05);
    assert!(
        !state
            .pickups
            .iter()
            .find(|p| p.id == "pad_health_n")
            .unwrap()
            .available
    );
    park_away_from_pads(&mut state, id);
    for _ in 0..HEALTH_PICKUP_RESPAWN_TICKS {
        state.tick(0.05);
    }
    let pad = state
        .pickups
        .iter()
        .find(|p| p.id == "pad_health_n")
        .unwrap();
    assert!(pad.available, "health pad should respawn");
}

#[test]
fn test_sim_weapon_pads_still_claim_with_health_pads_present() {
    let mut state = GameState::new();
    state.start_round();
    let id = Uuid::new_v4();
    state.add_player(id, "Rusher".into(), Role::Human);
    stand_on_pad(&mut state, id, "pad_scatter");
    if let Some(p) = state.players.iter_mut().find(|p| p.id == id) {
        p.weapon = WeaponType::Flechette;
    }
    state.tick(0.05);
    let player = state.players.iter().find(|p| p.id == id).unwrap();
    assert_eq!(player.weapon, WeaponType::Scatter);
}

#[test]
fn test_sim_choke_blocks_move_into_pillar() {
    let mut state = GameState::new();
    state.start_round();
    let id = Uuid::new_v4();
    state.add_player(id, "Rusher".into(), Role::Human);
    // Pick a real solid out of the map rather than copying coordinates that
    // move whenever the layout does, and stand south of it facing north.
    let solid = crate::sim::MapKind::ArenaDuel
        .solids()
        .into_iter()
        .find(|s| s.min_z < -2.0 && (s.max_x - s.min_x) > 1.5)
        .expect("the arena has a chunky solid south of the origin");
    let face_z = solid.min_z;
    let centre_x = (solid.min_x + solid.max_x) * 0.5;
    if let Some(p) = state.players.iter_mut().find(|p| p.id == id) {
        p.x = centre_x;
        p.z = face_z - 2.5;
        p.yaw = std::f32::consts::FRAC_PI_2; // face +z
    }
    for _ in 0..40 {
        state.set_action(
            id,
            Action {
                forward: true,
                ..Default::default()
            },
        );
        state.tick(0.05);
    }
    let player = state.players.iter().find(|p| p.id == id).unwrap();
    // The face is expanded by the fighter's radius, so that is the stop line.
    let stop = face_z - crate::sim::PLAYER_RADIUS;
    assert!(
        player.z <= stop + 0.05,
        "player should be stopped by the solid at z={stop}, got z={}",
        player.z
    );
    assert!(
        (player.x - centre_x).abs() < 0.2,
        "x should stay near {centre_x}, got {}",
        player.x
    );
}

#[test]
fn test_sim_choke_hitscan_blocked_by_low_wall() {
    let mut state = GameState::new();
    state.start_round();
    let shooter = Uuid::new_v4();
    let target = Uuid::new_v4();
    state.add_player(shooter, "Shooter".into(), Role::Agent);
    state.add_player(target, "Victim".into(), Role::Agent);
    // The walkway the rail pad sits on is taller than eye height, so two
    // fighters on the floor either side of it cannot see each other. Where it
    // is comes from the map rather than from a remembered coordinate.
    let rail = state
        .pickups
        .iter()
        .find(|p| p.id == "pad_rail")
        .map(|p| (p.x, p.z, p.floor))
        .unwrap();
    assert!(
        rail.2 > crate::movement::EYE_HEIGHT,
        "the rail walkway has to be taller than a fighter to block a shot"
    );
    let facing = if rail.1 < 0.0 {
        std::f32::consts::FRAC_PI_2
    } else {
        -std::f32::consts::FRAC_PI_2
    };
    let away = if rail.1 < 0.0 { -6.0 } else { 6.0 };
    if let Some(p) = state.players.iter_mut().find(|p| p.id == shooter) {
        p.x = rail.0;
        p.z = rail.1 + away;
        p.yaw = facing;
        p.weapon = WeaponType::Rail;
    }
    if let Some(p) = state.players.iter_mut().find(|p| p.id == target) {
        p.x = rail.0;
        p.z = rail.1 - away;
        p.hp = 100;
    }
    let hp_before = state.players.iter().find(|p| p.id == target).unwrap().hp;
    state.set_action(
        shooter,
        Action {
            fire: true,
            ..Default::default()
        },
    );
    state.tick(0.05);
    let hp_after = state.players.iter().find(|p| p.id == target).unwrap().hp;
    assert_eq!(hp_before, hp_after, "low wall must block hitscan");
}

#[test]
fn test_sim_choke_hitscan_clear_lane_still_hits() {
    let mut state = GameState::new();
    state.start_round();
    let shooter = Uuid::new_v4();
    let target = Uuid::new_v4();
    state.add_player(shooter, "Shooter".into(), Role::Agent);
    state.add_player(target, "Victim".into(), Role::Agent);
    if let Some(p) = state.players.iter_mut().find(|p| p.id == shooter) {
        // Open lane along +x through hub (no wall on x axis at z=0 between -5 and 5).
        p.x = -5.0;
        p.z = 0.0;
        p.yaw = 0.0;
        p.weapon = WeaponType::Flechette;
    }
    if let Some(p) = state.players.iter_mut().find(|p| p.id == target) {
        p.x = 5.0;
        p.z = 0.0;
        p.hp = 100;
    }
    let hp_before = state.players.iter().find(|p| p.id == target).unwrap().hp;
    state.set_action(
        shooter,
        Action {
            fire: true,
            ..Default::default()
        },
    );
    state.tick(0.05);
    let hp_after = state.players.iter().find(|p| p.id == target).unwrap().hp;
    assert!(hp_after < hp_before, "clear hub lane should still hit");
}

#[test]
fn test_sim_choke_health_pad_still_claimable_from_hub() {
    let mut state = GameState::new();
    state.start_round();
    let id = Uuid::new_v4();
    state.add_player(id, "Rusher".into(), Role::Human);
    stand_on_pad(&mut state, id, "pad_health_n");
    if let Some(p) = state.players.iter_mut().find(|p| p.id == id) {
        p.hp = 40;
    }
    state.tick(0.05);
    let player = state.players.iter().find(|p| p.id == id).unwrap();
    assert_eq!(player.hp, 80, "health pad north must remain claimable");
}

#[test]
fn test_sim_choke_spawn_points_clear_of_solids() {
    let mut state = GameState::new();
    for i in 0..8 {
        let id = Uuid::new_v4();
        state.add_player(id, format!("P{i}"), Role::Agent);
    }
    for p in &state.players {
        // Same predicate as move: inflated AABB must not contain spawn.
        // Probe by trying a zero move resolve: if blocked at spawn, circle_blocked is true.
        // We assert players are not inside the raw expanded solids by checking distance
        // to known pillar centers exceeds half+radius.
        for (cx, cz) in [(7.0_f32, -7.0), (-7.0, -7.0), (7.0, 7.0), (-7.0, 7.0)] {
            let dx = (p.x - cx).abs();
            let dz = (p.z - cz).abs();
            let inside = dx <= 1.25 + 0.5 && dz <= 1.25 + 0.5;
            assert!(
                !inside,
                "spawn ({}, {}) inside pillar at ({}, {})",
                p.x, p.z, cx, cz
            );
        }
    }
}

#[test]
fn test_sim_choke_compliance_drone_center_clear() {
    let mut state = GameState::new();
    state.config.boss_spawn_ticks = Some(1);
    state.start_round();
    // Advance into Active and to boss spawn tick.
    while state.round_state != RoundState::Active {
        state.tick(0.05);
    }
    for _ in 0..5 {
        state.tick(0.05);
        if state.boss_id.is_some() {
            break;
        }
    }
    assert!(state.boss_id.is_some(), "drone should spawn");
    let boss = state
        .players
        .iter()
        .find(|p| p.is_boss)
        .expect("boss player");
    assert!(boss.x.abs() < 0.1 && boss.z.abs() < 0.1, "drone at hub");
}

fn force_hitscan_frag(state: &mut GameState, shooter_id: Uuid, target_id: Uuid) {
    let shooter_idx = state
        .players
        .iter()
        .position(|p| p.id == shooter_id)
        .expect("shooter");
    let target_idx = state
        .players
        .iter()
        .position(|p| p.id == target_id)
        .expect("target");
    state.players[target_idx].x = 5.0;
    state.players[target_idx].z = 0.0;
    state.players[target_idx].y = 1.5;
    state.players[target_idx].hp = 20;
    state.players[target_idx].armor = 0;
    state.players[target_idx].respawn_timer = None;
    state.players[shooter_idx].x = 0.0;
    state.players[shooter_idx].z = 0.0;
    state.players[shooter_idx].y = 1.5;
    state.players[shooter_idx].yaw = 0.0;
    state.players[shooter_idx].fire_cooldown = 0;
    state.set_action(
        shooter_id,
        Action {
            fire: true,
            ..Default::default()
        },
    );
    state.tick(0.05);
}

#[test]
fn test_killstreak_emits_at_2_3_5_and_resets_on_death() {
    let mut state = GameState::new();
    state.config.compliance_ping_ticks = None;
    state.config.boss_spawn_ticks = None;
    state.config.frag_limit = Some(99);
    state.start_round();

    let shooter_id = Uuid::new_v4();
    let target_id = Uuid::new_v4();
    state.add_player(shooter_id, "Rusher".to_string(), Role::Agent);
    state.add_player(target_id, "Target".to_string(), Role::Agent);
    let _ = state.take_events();

    let mut seen_tiers: Vec<String> = Vec::new();
    for n in 1..=5 {
        // Wait out respawn if target died last frag.
        for _ in 0..100 {
            let tidx = state
                .players
                .iter()
                .position(|p| p.id == target_id)
                .unwrap();
            if state.players[tidx].respawn_timer.is_none()
                && state.players[tidx].hp > 0
                && !state.spawn_shields.contains_key(&target_id)
            {
                break;
            }
            state.tick(0.05);
        }
        let _ = state.take_events();
        force_hitscan_frag(&mut state, shooter_id, target_id);
        let events = state.take_events();
        assert!(
            events.iter().any(|e| matches!(
                e,
                GameEvent::Frag {
                    killer,
                    ..
                } if killer == "Rusher"
            )),
            "expected frag on kill {}",
            n
        );
        let sidx = state
            .players
            .iter()
            .position(|p| p.id == shooter_id)
            .unwrap();
        assert_eq!(state.players[sidx].killstreak, n, "streak after kill {}", n);
        for e in &events {
            if let GameEvent::Killstreak {
                streak,
                tier,
                message,
                player,
                ..
            } = e
            {
                assert_eq!(player, "Rusher");
                assert_eq!(*streak, n);
                assert!(message.starts_with("HOST:"));
                seen_tiers.push(tier.clone());
            }
        }
        if n == 1 || n == 4 {
            assert!(
                !events
                    .iter()
                    .any(|e| matches!(e, GameEvent::Killstreak { .. })),
                "no killstreak event at streak {}",
                n
            );
        }
    }
    assert_eq!(seen_tiers, vec!["double", "triple", "rampage"]);

    // Victim death resets victim streak; kill Rusher with Target to reset Rusher.
    let sidx = state
        .players
        .iter()
        .position(|p| p.id == shooter_id)
        .unwrap();
    assert_eq!(state.players[sidx].killstreak, 5);
    for _ in 0..70 {
        let tidx = state
            .players
            .iter()
            .position(|p| p.id == target_id)
            .unwrap();
        if state.players[tidx].respawn_timer.is_none() && state.players[tidx].hp > 0 {
            break;
        }
        state.tick(0.05);
    }
    let _ = state.take_events();
    force_hitscan_frag(&mut state, target_id, shooter_id);
    let sidx = state
        .players
        .iter()
        .position(|p| p.id == shooter_id)
        .unwrap();
    assert_eq!(state.players[sidx].killstreak, 0, "death resets streak");
}

#[test]
fn test_killstreak_resets_on_round_start() {
    let mut state = GameState::new();
    state.config.compliance_ping_ticks = None;
    state.config.boss_spawn_ticks = None;
    state.start_round();
    let a = Uuid::new_v4();
    state.add_player(a, "A".to_string(), Role::Agent);
    let idx = state.players.iter().position(|p| p.id == a).unwrap();
    state.players[idx].killstreak = 4;
    state.start_round();
    let idx = state.players.iter().position(|p| p.id == a).unwrap();
    assert_eq!(state.players[idx].killstreak, 0);
}

#[test]
fn test_weapon_range_units_distinct() {
    use crate::protocol::WeaponType;
    assert!(WeaponType::Scatter.range_units() < WeaponType::Flechette.range_units());
    assert!(WeaponType::Flechette.range_units() < WeaponType::Rail.range_units());
    assert_eq!(WeaponType::Flechette.preferred_range(), (8.0, 28.0));
    assert_eq!(WeaponType::Rail.preferred_range(), (18.0, 45.0));
    assert_eq!(WeaponType::Scatter.preferred_range(), (2.0, 10.0));
}

#[test]
fn test_scatter_misses_beyond_range() {
    use crate::protocol::WeaponType;

    let mut state = GameState::new();
    state.start_round();

    let shooter_id = Uuid::new_v4();
    let target_id = Uuid::new_v4();
    state.add_player(shooter_id, "Shooter".to_string(), Role::Agent);
    state.add_player(target_id, "Target".to_string(), Role::Agent);

    let shooter_idx = state
        .players
        .iter()
        .position(|p| p.id == shooter_id)
        .unwrap();
    let target_idx = state
        .players
        .iter()
        .position(|p| p.id == target_id)
        .unwrap();

    // Clear north lane (z=20): beyond Scatter 14u, inside Rail. Avoids mid choke walls.
    // Find ground the map says is clear rather than assuming a lane exists.
    let (lane_z, span) = clear_lane(20.0);
    state.players[shooter_idx].x = -span / 2.0;
    state.players[shooter_idx].z = lane_z;
    state.players[shooter_idx].yaw = 0.0;
    state.players[target_idx].x = -span / 2.0 + 16.0;
    state.players[target_idx].z = lane_z;

    state.players[shooter_idx].weapon = WeaponType::Scatter;
    state.players[shooter_idx].fire_cooldown = 0;
    state.set_action(
        shooter_id,
        Action {
            fire: true,
            ..Default::default()
        },
    );
    let hp_before = state.players[target_idx].hp;
    state.tick(0.05);
    assert_eq!(
        state.players[target_idx].hp, hp_before,
        "Scatter must miss beyond range_units"
    );

    state.players[shooter_idx].weapon = WeaponType::Rail;
    state.players[shooter_idx].fire_cooldown = 0;
    state.set_action(
        shooter_id,
        Action {
            fire: true,
            ..Default::default()
        },
    );
    state.tick(0.05);
    assert!(
        state.players[target_idx].hp < hp_before,
        "Rail must still hit at 20u"
    );
}

#[test]
fn test_bot_rail_holds_long_lane() {
    use crate::protocol::WeaponType;

    let mut state = GameState::new();
    state.start_round();

    let bot_id = Uuid::new_v4();
    let target_id = Uuid::new_v4();
    state.add_player(bot_id, "Bot".to_string(), Role::Agent);
    state.add_player(target_id, "Target".to_string(), Role::Agent);

    let bot_idx = state.players.iter().position(|p| p.id == bot_id).unwrap();
    let target_idx = state
        .players
        .iter()
        .position(|p| p.id == target_id)
        .unwrap();

    state.players[bot_idx].weapon = WeaponType::Rail;
    state.players[bot_idx].x = 0.0;
    state.players[bot_idx].z = 0.0;
    state.players[bot_idx].yaw = 0.0;
    // Target inside Rail preferred band (~25u).
    state.players[target_idx].x = 25.0;
    state.players[target_idx].z = 0.0;

    let bot = BotController::new(bot_id, BotBehavior::Defensive);
    let action = bot.update(&state);
    // At preferred band, Defensive should strafe (not rush) and be willing to fire.
    assert!(
        action.fire || action.left || action.right || action.back || action.forward,
        "Rail bot at preferred range should act"
    );
    // Not closing hard when already in band.
    assert!(
        !(action.forward && !action.left && !action.right && !action.back),
        "Rail defensive bot should not only rush when already mid-long"
    );
}

#[test]
fn test_bot_scatter_pushes_close() {
    use crate::protocol::WeaponType;

    let mut state = GameState::new();
    state.start_round();

    let bot_id = Uuid::new_v4();
    let target_id = Uuid::new_v4();
    state.add_player(bot_id, "Bot".to_string(), Role::Agent);
    state.add_player(target_id, "Target".to_string(), Role::Agent);

    let bot_idx = state.players.iter().position(|p| p.id == bot_id).unwrap();
    let target_idx = state
        .players
        .iter()
        .position(|p| p.id == target_id)
        .unwrap();

    state.players[bot_idx].weapon = WeaponType::Scatter;
    state.players[bot_idx].x = 0.0;
    state.players[bot_idx].z = 0.0;
    state.players[bot_idx].yaw = 0.0;
    // Target outside Scatter preferred band but inside fire range stretch.
    state.players[target_idx].x = 16.0;
    state.players[target_idx].z = 0.0;

    let bot = BotController::new(bot_id, BotBehavior::Aggressive);
    let action = bot.update(&state);
    assert!(
        action.forward,
        "Scatter aggressive bot should push toward close range"
    );
}

#[test]
fn test_round_end_emits_mvp_host_line_and_sticky_snapshot() {
    let mut state = GameState::new();
    state.config.frag_limit = Some(2);
    state.config.time_limit_ticks = None;
    state.config.compliance_ping_ticks = None;
    state.config.boss_spawn_ticks = None;
    state.config.warmup_ticks = 1;
    state.config.end_delay_ticks = 20 * 10;

    let a = uuid::Uuid::new_v4();
    let b = uuid::Uuid::new_v4();
    state.add_player(a, "Rusher".to_string(), Role::Agent);
    state.add_player(b, "Anchor".to_string(), Role::Agent);
    // Leave warmup
    state.tick(0.05);
    assert_eq!(state.round_state, RoundState::Active);

    *state.scores.get_mut(&a).unwrap() = 2;
    *state.scores.get_mut(&b).unwrap() = 1;
    state.end_round("Frag limit reached".to_string());

    let events = state.take_events();
    let end = events
        .iter()
        .find_map(|e| match e {
            GameEvent::RoundEnd {
                mvp,
                mvp_frags,
                host_line,
                winner,
                ..
            } => Some((mvp.clone(), *mvp_frags, host_line.clone(), winner.clone())),
            _ => None,
        })
        .expect("RoundEnd event");
    assert_eq!(end.0.as_deref(), Some("Rusher"));
    assert_eq!(end.1, Some(2));
    assert!(end.2.contains("ROUND MVP"));
    assert!(end.2.contains("Rusher"));
    assert_eq!(end.3.as_deref(), Some("Rusher"));

    assert_eq!(state.round_state, RoundState::Ended);
    let snap = state.snapshot();
    assert!(snap.host_line.contains("ROUND MVP"));
    assert!(snap.host_line.contains("Rusher"));
    assert_eq!(snap.mvp.as_deref(), Some("Rusher"));
    assert_eq!(snap.mvp_frags, Some(2));
    assert_eq!(
        state.ended_host_line.as_deref(),
        Some(snap.host_line.as_str())
    );
    assert_eq!(state.ended_mvp.as_deref(), Some("Rusher"));
    assert_eq!(state.ended_mvp_frags, Some(2));

    // Next round clears sticky MVP Host line and structured mvp fields.
    state.start_round();
    assert!(state.ended_host_line.is_none());
    assert!(state.ended_mvp.is_none());
    assert!(state.ended_mvp_frags.is_none());
    let warm = state.snapshot();
    assert_eq!(warm.host_line, default_host_line());
    assert!(warm.mvp.is_none());
    assert!(warm.mvp_frags.is_none());
}

#[test]
fn test_default_ended_linger_is_eight_seconds() {
    let cfg = MatchConfig::default();
    assert_eq!(
        cfg.end_delay_ticks,
        20 * 8,
        "Ended linger should be 8s at 20 Hz so podium/Host bumper can be read"
    );
}

#[test]
fn test_snapshot_omits_mvp_while_active() {
    let mut state = GameState::new();
    state.config.compliance_ping_ticks = None;
    state.config.boss_spawn_ticks = None;
    state.start_round();
    let snap = state.snapshot();
    assert_eq!(snap.round_state.as_deref(), Some("Active"));
    assert!(snap.mvp.is_none());
    assert!(snap.mvp_frags.is_none());
    let json = serde_json::to_value(&snap).unwrap();
    assert!(json.get("mvp").is_none());
    assert!(json.get("mvp_frags").is_none());
}

#[test]
fn test_snapshot_mvp_wire_round_trip_while_ended() {
    let mut state = GameState::new();
    state.config.compliance_ping_ticks = None;
    state.config.boss_spawn_ticks = None;
    let id = uuid::Uuid::new_v4();
    state.add_player(id, "Ghost".to_string(), Role::Agent);
    state.start_round();
    *state.scores.get_mut(&id).unwrap() = 3;
    state.end_round("Frag limit reached".to_string());
    let snap = state.snapshot();
    let json = serde_json::to_value(&snap).unwrap();
    assert_eq!(json["round_state"], "Ended");
    assert_eq!(json["mvp"], "Ghost");
    assert_eq!(json["mvp_frags"], 3);
    assert!(json["host_line"].as_str().unwrap().contains("Ghost"));
    let back: Snapshot = serde_json::from_value(json).unwrap();
    assert_eq!(back.mvp.as_deref(), Some("Ghost"));
    assert_eq!(back.mvp_frags, Some(3));
}

#[test]
fn test_round_end_empty_mvp_host_line() {
    let mut state = GameState::new();
    state.config.compliance_ping_ticks = None;
    state.config.boss_spawn_ticks = None;
    state.end_round("Time limit reached".to_string());
    let events = state.take_events();
    let host = events
        .iter()
        .find_map(|e| match e {
            GameEvent::RoundEnd { mvp, host_line, .. } => Some((mvp.clone(), host_line.clone())),
            _ => None,
        })
        .expect("RoundEnd");
    assert!(host.0.is_none());
    assert!(host.1.contains("NO MVP"));
    let snap = state.snapshot();
    assert!(snap.host_line.contains("NO MVP"));
    assert!(snap.mvp.is_none());
    assert!(snap.mvp_frags.is_none());
}

#[test]
fn test_map_kind_cli_and_names() {
    assert_eq!(MapKind::from_cli("1"), Some(MapKind::ArenaDuel));
    assert_eq!(MapKind::from_cli("arena"), Some(MapKind::ArenaDuel));
    assert_eq!(MapKind::from_cli("2"), Some(MapKind::ComplianceYard));
    assert_eq!(
        MapKind::from_cli("compliance-yard"),
        Some(MapKind::ComplianceYard)
    );
    assert_eq!(MapKind::from_cli("nope"), None);
    assert_eq!(MapKind::ArenaDuel.id(), 1);
    assert_eq!(MapKind::ComplianceYard.id(), 2);
    assert_eq!(MapKind::ArenaDuel.name(), "Arena Duel");
    assert_eq!(MapKind::ComplianceYard.name(), "Compliance Yard");
    assert_eq!(MapKind::ArenaDuel.next(), MapKind::ComplianceYard);
    assert_eq!(MapKind::ComplianceYard.next(), MapKind::Directive17);
    assert_eq!(
        MapKind::ALL.last().copied().unwrap().next(),
        MapKind::ArenaDuel,
        "rotation wraps"
    );
}

#[test]
fn test_sim_compliance_yard_blocks_move_into_post() {
    let mut state = GameState::with_map(MapKind::ComplianceYard, false);
    state.start_round();
    let id = Uuid::new_v4();
    state.add_player(id, "Rusher".into(), Role::Human);
    if let Some(p) = state.players.iter_mut().find(|p| p.id == id) {
        // South of NE post at (5, -5); walk north into it.
        p.x = 5.0;
        p.z = -7.5;
        p.yaw = std::f32::consts::FRAC_PI_2;
    }
    for _ in 0..40 {
        state.set_action(
            id,
            Action {
                forward: true,
                ..Default::default()
            },
        );
        state.tick(0.05);
    }
    let player = state.players.iter().find(|p| p.id == id).unwrap();
    assert!(
        player.z <= -6.4,
        "player should be stopped by yard post, z={}",
        player.z
    );
}

#[test]
fn test_sim_compliance_yard_pad_claim_and_hub_clear() {
    let mut state = GameState::with_map(MapKind::ComplianceYard, false);
    state.start_round();
    let snap = state.snapshot();
    assert_eq!(snap.map_id, 2);
    assert_eq!(snap.map_name, "Compliance Yard");
    assert_eq!(state.pickups.len(), 6);

    // Hub must stay clear for drone (circle at 0,0 not blocked).
    for obs in MapKind::ComplianceYard.obstacles() {
        assert!(
            !obs.expand(0.5).contains(0.0, 0.0),
            "hub blocked by {:?}",
            obs
        );
    }

    let id = Uuid::new_v4();
    state.add_player(id, "Scrapper".into(), Role::Human);
    stand_on_pad(&mut state, id, "pad_armor");
    if let Some(p) = state.players.iter_mut().find(|p| p.id == id) {
        p.armor = 0;
        p.hp = 100;
    }
    state.tick(0.05);
    let player = state.players.iter().find(|p| p.id == id).unwrap();
    assert!(player.armor > 0, "armor pad should claim on yard");
}

#[test]
fn test_sim_map_rotate_each_start_round() {
    let mut state = GameState::with_map(MapKind::ArenaDuel, true);
    assert_eq!(state.map, MapKind::ArenaDuel);
    state.start_round(); // round 1, stay Arena Duel
    assert_eq!(state.round_number, 1);
    assert_eq!(state.map, MapKind::ArenaDuel);
    state.end_round("test".into());
    state.start_round(); // round 2, rotate to yard
    assert_eq!(state.round_number, 2);
    assert_eq!(state.map, MapKind::ComplianceYard);
    assert_eq!(state.snapshot().map_id, 2);
    state.end_round("test".into());
    state.start_round(); // round 3, on to the next map in the roster
    assert_eq!(state.map, MapKind::ComplianceYard.next());
    // Round after round it walks the whole roster and comes back.
    for _ in 3..MapKind::ALL.len() as u32 + 1 {
        state.end_round("test".into());
        state.start_round();
    }
    assert_eq!(state.map, MapKind::ArenaDuel);
}

#[test]
fn test_protocol_snapshot_map_defaults_round_trip() {
    let json = serde_json::json!({
        "tick": 1,
        "players": [],
        "mode_name": "Contested Frequency",
        "playlist": "Arena Duel",
        "host_line": "HOST: CONTESTED FREQUENCY. PLAY VS COMPLIANCE. ARENA DUEL IS LIVE."
    });
    let snap: Snapshot = serde_json::from_value(json).unwrap();
    assert_eq!(snap.map_id, default_map_id());
    assert_eq!(snap.map_name, default_map_name());
}

#[test]
fn test_warmup_host_drama_roster_map_countdown() {
    let mut state = GameState::new();
    state.config.warmup_ticks = 40; // 2s
    state.set_roster_host_line_from_names(&["Dead Air Dan".into(), "Nightfall".into()]);
    assert_eq!(state.round_state, RoundState::Warmup);

    let snap = state.snapshot();
    assert_eq!(snap.round_time_left, Some(2));
    assert!(snap.host_line.contains("CONTESTED FREQUENCY"));
    assert!(snap.host_line.contains("ARENA DUEL"));
    assert!(snap.host_line.contains("DEAD AIR DAN"));
    assert!(snap.host_line.contains("ON THE SCRAP"));
    assert!(snap.host_line.contains("2."));
    assert_eq!(
        snap.host_line,
        warmup_host_line("Arena Duel", &state.roster_names, 2)
    );

    // Advance one second of Warmup; countdown should drop.
    for _ in 0..20 {
        state.tick(0.05);
    }
    assert_eq!(state.round_state, RoundState::Warmup);
    let mid = state.snapshot();
    assert_eq!(mid.round_time_left, Some(1));
    assert!(mid.host_line.ends_with("1."));

    // Finish Warmup -> RoundStart fight bumper with map + roster.
    for _ in 0..20 {
        state.tick(0.05);
    }
    assert_eq!(state.round_state, RoundState::Active);
    let start = state
        .take_events()
        .into_iter()
        .find_map(|e| match e {
            GameEvent::RoundStart { host_line, .. } => Some(host_line),
            _ => None,
        })
        .expect("RoundStart");
    assert_eq!(
        start,
        round_open_host_line("Arena Duel", &["Dead Air Dan".into(), "Nightfall".into()])
    );
    assert!(start.contains("FIGHT!"));
}

#[test]
fn rule_bot_taunt_emits_speak_and_respects_cooldown() {
    use crate::protocol::BotTauntKind;
    use crate::sim::{SpeakOutcome, SPEAK_COOLDOWN_TICKS};

    let mut state = GameState::new();
    let bot_id = Uuid::new_v4();
    state.add_player(bot_id, "Dead Air Dan".to_string(), Role::Agent);
    state
        .bots
        .push(BotController::new(bot_id, BotBehavior::Aggressive));

    assert_eq!(
        state.try_rule_bot_taunt(bot_id, BotTauntKind::Frag),
        SpeakOutcome::Sent
    );
    let speaks: Vec<_> = state
        .take_events()
        .into_iter()
        .filter_map(|e| match e {
            GameEvent::Speak { player, text, .. } => Some((player, text)),
            _ => None,
        })
        .collect();
    assert_eq!(speaks.len(), 1);
    assert_eq!(speaks[0].0, "Dead Air Dan");
    assert!(!speaks[0].1.is_empty());
    assert!(speaks[0].1.chars().count() <= 80);

    assert_eq!(
        state.try_rule_bot_taunt(bot_id, BotTauntKind::Death),
        SpeakOutcome::RateLimited
    );
    assert!(
        state
            .take_events()
            .iter()
            .all(|e| !matches!(e, GameEvent::Speak { .. })),
        "rate-limited taunt must not emit Speak"
    );

    state.tick += SPEAK_COOLDOWN_TICKS;
    assert_eq!(
        state.try_rule_bot_taunt(bot_id, BotTauntKind::Killstreak),
        SpeakOutcome::Sent
    );
    assert!(state
        .take_events()
        .iter()
        .any(|e| matches!(e, GameEvent::Speak { .. })));
}

#[test]
fn compliance_boss_does_not_get_scrap_radio_taunts() {
    use crate::protocol::BotTauntKind;
    use crate::sim::SpeakOutcome;

    let mut state = GameState::new();
    let boss_id = Uuid::new_v4();
    state.add_player(boss_id, "COMPLIANCE-DRONE".to_string(), Role::Agent);
    state
        .bots
        .push(BotController::new(boss_id, BotBehavior::Compliance));

    assert!(!state.is_named_rule_bot(boss_id));
    assert_eq!(
        state.try_rule_bot_taunt(boss_id, BotTauntKind::Frag),
        SpeakOutcome::Rejected
    );
    assert!(state
        .take_events()
        .iter()
        .all(|e| !matches!(e, GameEvent::Speak { .. })));
}

#[test]
fn warmup_rule_bot_taunt_path_can_emit_speak() {
    use crate::protocol::BotTauntKind;
    use crate::sim::SpeakOutcome;

    let mut state = GameState::new();
    state.config.warmup_ticks = 200;
    let bot_id = Uuid::new_v4();
    state.add_player(bot_id, "Static Kid".to_string(), Role::Agent);
    state
        .bots
        .push(BotController::new(bot_id, BotBehavior::Flanker));
    assert_eq!(state.round_state, RoundState::Warmup);

    assert_eq!(
        state.try_rule_bot_taunt(bot_id, BotTauntKind::Warmup),
        SpeakOutcome::Sent
    );
    let line = state
        .take_events()
        .into_iter()
        .find_map(|e| match e {
            GameEvent::Speak { text, .. } => Some(text),
            _ => None,
        })
        .expect("Warmup Speak");
    assert!(
        line.contains("glitch") || line.contains("static") || line.contains("tuning"),
        "{line}"
    );

    state.tick += 1;
    assert_eq!(
        state.try_rule_bot_taunt(bot_id, BotTauntKind::Warmup),
        SpeakOutcome::RateLimited
    );
}

#[test]
fn test_sim_respawn_lands_far_from_living_fighters() {
    use crate::sim::SPAWN_SHIELD_TICKS;
    let mut state = GameState::new();
    state.start_round();
    let a = Uuid::new_v4();
    let b = Uuid::new_v4();
    state.add_player(a, "A".into(), Role::Agent);
    state.add_player(b, "B".into(), Role::Agent);
    // Park B on the east ring slot and let A's respawn timer run out.
    for p in state.players.iter_mut() {
        if p.id == b {
            p.x = 15.0;
            p.z = 0.0;
        }
        if p.id == a {
            p.respawn_timer = Some(1);
        }
    }
    state.tick(0.05);
    let a_p = state.players.iter().find(|p| p.id == a).unwrap();
    assert!(a_p.respawn_timer.is_none(), "A should have respawned");
    let dist = ((a_p.x - 15.0).powi(2) + a_p.z.powi(2)).sqrt();
    assert!(dist > 20.0, "respawn lands on the far side, got {dist}");
    assert_eq!(
        state.spawn_shields.get(&a).copied(),
        Some(SPAWN_SHIELD_TICKS)
    );
    assert!(
        !state.spawn_shields.contains_key(&b),
        "joins are not shielded"
    );
}

#[test]
fn test_sim_spawn_shield_blocks_damage_for_one_second() {
    use crate::sim::SPAWN_SHIELD_TICKS;
    let mut state = GameState::new();
    state.start_round();
    let shooter = Uuid::new_v4();
    let target = Uuid::new_v4();
    state.add_player(shooter, "Shooter".into(), Role::Agent);
    state.add_player(target, "Victim".into(), Role::Agent);
    // Kill the victim and let it respawn: the shield is keyed by id, so it can
    // then be moved into the clear hub lane the choke tests use.
    for p in state.players.iter_mut() {
        if p.id == target {
            p.respawn_timer = Some(1);
        }
    }
    state.tick(0.05);
    assert!(state.spawn_shields.contains_key(&target));
    for p in state.players.iter_mut() {
        if p.id == shooter {
            p.x = -5.0;
            p.z = 0.0;
            p.yaw = 0.0;
            p.weapon = WeaponType::Flechette;
            p.fire_cooldown = 0;
        }
        if p.id == target {
            p.x = 5.0;
            p.z = 0.0;
        }
    }
    state.set_action(
        shooter,
        Action {
            fire: true,
            ..Default::default()
        },
    );
    state.tick(0.05);
    let hp = state.players.iter().find(|p| p.id == target).unwrap().hp;
    assert_eq!(hp, 100, "a shielded fighter takes no damage");
    for _ in 0..SPAWN_SHIELD_TICKS {
        state.set_action(shooter, Action::default());
        state.tick(0.05);
    }
    assert!(!state.spawn_shields.contains_key(&target), "shield expires");
    for p in state.players.iter_mut() {
        if p.id == shooter {
            p.fire_cooldown = 0;
        }
    }
    state.set_action(
        shooter,
        Action {
            fire: true,
            ..Default::default()
        },
    );
    state.tick(0.05);
    let hp = state.players.iter().find(|p| p.id == target).unwrap().hp;
    assert!(hp < 100, "the shot lands once the shield is down, hp {hp}");
}

#[test]
fn test_sim_respawn_and_all_joins_prefer_cover_to_an_exposed_ring_gap() {
    use crate::combat::{line_of_sight, FIGHTER_HEIGHT};
    use crate::movement::EYE_HEIGHT;
    use crate::sim::PLAYER_FLOOR_Y;

    // Living positions from a failing twelve-client Gulch session. The widest
    // ring gap is in a rail lane; the northern compound has an unexposed slot.
    let positions = [
        (76.50, 20.84),
        (51.50, -80.74),
        (-0.75, 67.62),
        (-72.56, -47.28),
        (0.73, -90.50),
        (-43.47, -81.87),
        (-71.21, 22.68),
        (76.52, -25.03),
        (-43.48, 80.87),
        (46.76, 75.74),
    ];
    for (sx, sz) in [(1.0, 1.0), (-1.0, 1.0), (1.0, -1.0), (-1.0, -1.0)] {
        for (respawning, warmup) in [(true, false), (false, false), (false, true)] {
            let mut state = GameState::with_map(MapKind::ReclamationGulch, false);
            state.config.boss_spawn_ticks = None;
            state.config.compliance_ping_ticks = None;
            let victim = Uuid::from_u128(1);
            state.add_player(victim, "Respawning".into(), Role::Human);
            for index in 0..positions.len() {
                state.add_player(
                    Uuid::from_u128(index as u128 + 2),
                    format!("Threat {index}"),
                    Role::Agent,
                );
            }
            for (player, &(x, z)) in state.players[1..].iter_mut().zip(&positions) {
                player.x = x * sx;
                player.z = z * sz;
                player.y = PLAYER_FLOOR_Y;
            }
            let solids = state.map.solids();
            let exposed = |state: &GameState, feet: [f32; 3]| {
                state
                    .players
                    .iter()
                    .filter(|enemy| enemy.id != victim)
                    .any(|enemy| {
                        let origin = [enemy.x, enemy.y - PLAYER_FLOOR_Y + EYE_HEIGHT, enemy.z];
                        let target = [feet[0], feet[1] + FIGHTER_HEIGHT * 0.5, feet[2]];
                        let distance = (origin[0] - target[0]).hypot(origin[2] - target[2]);
                        distance <= WeaponType::Rail.range_units()
                            && line_of_sight(origin, target, &solids)
                    })
            };
            assert!(
                !exposed(&state, [17.948314 * sx, 0.0, 90.23225 * sz]),
                "fixture has a covered alternative"
            );
            state.start_round();
            if warmup {
                state.round_state = RoundState::Warmup;
            }
            if respawning {
                state.players[0].respawn_timer = Some(1);
                state.tick(0.05);
            } else {
                state.remove_player(victim);
                state.add_player(victim, "Joining".into(), Role::Human);
            }
            let player = state
                .players
                .iter()
                .find(|player| player.id == victim)
                .unwrap();
            let feet = [player.x, player.y - PLAYER_FLOOR_Y, player.z];
            assert!(!exposed(&state, feet), "respawn exposed at {feet:?}");
            assert!(
                state
                    .players
                    .iter()
                    .filter(|other| other.id != victim)
                    .all(|other| {
                        (player.x - other.x).hypot(player.z - other.z)
                            >= crate::sim::PLAYER_RADIUS * 2.0
                    }),
                "cover never permits overlapping a living fighter"
            );
            assert_eq!(state.spawn_shields.contains_key(&victim), respawning);
        }
    }
}

#[test]
fn solo_broadcast_ep0_win_path() {
    let mut session = GameSession::new();
    session.spawn_bots(4);
    session.enable_solo_broadcast_ep0();
    assert!(session.state.solo_broadcast.enabled);
    assert_eq!(session.state.solo_broadcast.phase, EpisodePhase::Nods);

    let human = Uuid::new_v4();
    session
        .state
        .add_player(human, "Meatbag".to_string(), Role::Human);

    // Cold open during Warmup.
    for _ in 0..25 {
        session.state.tick(0.05);
    }
    let events = session.state.take_events();
    assert!(
        events
            .iter()
            .any(|e| matches!(e, GameEvent::EpisodeStart { .. })),
        "expected EpisodeStart, got {events:?}"
    );

    if session.state.round_state != RoundState::Active {
        session.state.start_round();
    }

    let nods: Vec<_> = session
        .state
        .players
        .iter()
        .filter(|p| p.name.starts_with("NODS-") && !p.is_boss)
        .map(|p| p.id)
        .collect();
    assert!(!nods.is_empty(), "expected NODS labels after enable");

    let mut nods_cycle = nods.iter().cycle();
    while session.state.solo_broadcast.nods_cleared < session.state.solo_broadcast.nods_goal {
        let victim = *nods_cycle.next().expect("NODS roster");
        session.state.note_nods_frag(human, victim);
    }
    assert_eq!(session.state.solo_broadcast.phase, EpisodePhase::Jammer);

    if let Some(p) = session.state.players.iter_mut().find(|p| p.id == human) {
        p.x = 0.0;
        p.z = 0.0;
        p.respawn_timer = None;
    }
    session.state.try_seize_jammer();
    assert_eq!(session.state.solo_broadcast.phase, EpisodePhase::Auditor);
    assert!(session.state.boss_id.is_some());
    assert_eq!(
        session
            .state
            .players
            .iter()
            .find(|p| p.is_boss)
            .map(|p| p.name.as_str()),
        Some(AUDITOR_NAME)
    );

    session
        .state
        .complete_episode("Auditor down. Frequency stays unmetered.".to_string());
    assert_eq!(session.state.solo_broadcast.phase, EpisodePhase::Won);
    let events = session.state.take_events();
    assert!(
        events
            .iter()
            .any(|e| matches!(e, GameEvent::EpisodeComplete { .. })),
        "expected EpisodeComplete, got {events:?}"
    );

    let snap = session.state.snapshot();
    assert_eq!(snap.map_name, EPISODE_MAP_LARAK_LOT);
    assert_eq!(snap.episode_id.as_deref(), Some(EPISODE_ID_EP0));
    assert_eq!(snap.episode_phase.as_deref(), Some("won"));
}

#[test]
fn solo_broadcast_ep0_fail_on_timeout() {
    let mut session = GameSession::new();
    session.spawn_bots(2);
    session.enable_solo_broadcast_ep0();
    session.state.config.warmup_ticks = 1;
    session.state.config.time_limit_ticks = Some(5);
    let human = Uuid::new_v4();
    session
        .state
        .add_player(human, "Meatbag".to_string(), Role::Human);
    for _ in 0..40 {
        session.state.tick(0.05);
        if session.state.solo_broadcast.phase == EpisodePhase::Failed {
            break;
        }
    }
    assert_eq!(session.state.solo_broadcast.phase, EpisodePhase::Failed);
    let events = session.state.take_events();
    assert!(
        events
            .iter()
            .any(|e| matches!(e, GameEvent::EpisodeFail { .. })),
        "expected EpisodeFail, got {events:?}"
    );
}

#[test]
fn note_nods_frag_credits_human_and_agent_meatbag_not_rule_bot() {
    let mut session = GameSession::new();
    session.spawn_bots(2);
    session.enable_solo_broadcast_ep0();
    session.state.start_round();

    let nods: Vec<_> = session
        .state
        .players
        .iter()
        .filter(|p| p.name.starts_with("NODS-") && !p.is_boss)
        .map(|p| p.id)
        .collect();
    assert!(!nods.is_empty());
    let victim = nods[0];

    let human = Uuid::new_v4();
    session
        .state
        .add_player(human, "Meatbag".to_string(), Role::Human);
    session.state.note_nods_frag(human, victim);
    assert_eq!(session.state.solo_broadcast.nods_cleared, 1);

    let agent = Uuid::new_v4();
    session
        .state
        .add_player(agent, "MCP-Agent".to_string(), Role::Agent);
    session.state.note_nods_frag(agent, victim);
    assert_eq!(session.state.solo_broadcast.nods_cleared, 2);

    // Rule bot frag must not credit.
    let rule_bot = session.state.bots[0].player_id;
    let before = session.state.solo_broadcast.nods_cleared;
    session.state.note_nods_frag(rule_bot, victim);
    assert_eq!(session.state.solo_broadcast.nods_cleared, before);

    // Non-NODS human victim must not credit.
    let bystander = Uuid::new_v4();
    session
        .state
        .add_player(bystander, "Bystander".to_string(), Role::Human);
    session.state.note_nods_frag(human, bystander);
    assert_eq!(session.state.solo_broadcast.nods_cleared, before);
}

#[test]
fn note_nods_frag_host_ticks_each_clear_until_jammer() {
    let mut session = GameSession::new();
    session.spawn_bots(2);
    session.enable_solo_broadcast_ep0();
    session.state.start_round();

    let nods: Vec<_> = session
        .state
        .players
        .iter()
        .filter(|p| p.name.starts_with("NODS-") && !p.is_boss)
        .map(|p| p.id)
        .collect();
    assert!(!nods.is_empty());
    let victim = nods[0];
    let human = Uuid::new_v4();
    session
        .state
        .add_player(human, "Meatbag".to_string(), Role::Human);

    let goal = session.state.solo_broadcast.nods_goal;
    assert!(goal >= 4, "expected Calibration NODS goal >= 4, got {goal}");

    session.state.note_nods_frag(human, victim);
    assert_eq!(session.state.solo_broadcast.nods_cleared, 1);
    let line1 = session
        .state
        .solo_broadcast
        .host_line
        .clone()
        .expect("host line after first NODS clear");
    assert_eq!(line1, crate::protocol::episode0_host_line_nods());

    session.state.note_nods_frag(human, victim);
    assert_eq!(session.state.solo_broadcast.nods_cleared, 2);
    let line2 = session
        .state
        .solo_broadcast
        .host_line
        .clone()
        .expect("host line after second NODS clear");
    assert_ne!(line2, line1, "each NODS clear should bump Host");
    assert!(
        line2.contains("NODS 2/"),
        "expected NODS 2 tick Host, got {line2}"
    );

    session.state.note_nods_frag(human, victim);
    session.state.note_nods_frag(human, victim);
    assert_eq!(session.state.solo_broadcast.nods_cleared, 4);
    let line4 = session
        .state
        .solo_broadcast
        .host_line
        .clone()
        .expect("host line after fourth NODS clear");
    assert!(
        line4.contains("NODS 4/"),
        "expected NODS 4 tick Host, got {line4}"
    );

    // Goal clear hands Host to jammer only.
    while session.state.solo_broadcast.nods_cleared < goal {
        session.state.note_nods_frag(human, victim);
    }
    assert_eq!(session.state.solo_broadcast.phase, EpisodePhase::Jammer);
    let jammer = session
        .state
        .solo_broadcast
        .host_line
        .clone()
        .expect("jammer host line");
    assert_eq!(jammer, crate::protocol::episode0_host_line_jammer());
    assert!(
        !jammer.contains("NODS 5/"),
        "goal clear must not leave NODS-tick Host: {jammer}"
    );
}

#[test]
fn note_nods_frag_via_lethal_hitscan_path() {
    let mut state = GameState::new();
    state.enable_solo_broadcast_ep0();
    state.start_round();

    let agent = Uuid::new_v4();
    let victim = Uuid::new_v4();
    state.add_player(agent, "MCP-Agent".to_string(), Role::Agent);
    state.add_player(victim, "NODS-01".to_string(), Role::Agent);
    // Victim is a rule bot (NODS), killer is Agent meatbag (not in bots).
    state
        .bots
        .push(BotController::new(victim, BotBehavior::Balanced));

    let (ai, vi) = {
        let ai = state.players.iter().position(|p| p.id == agent).unwrap();
        let vi = state.players.iter().position(|p| p.id == victim).unwrap();
        (ai, vi)
    };
    state.players[ai].x = 0.0;
    state.players[ai].z = 0.0;
    state.players[ai].yaw = 0.0;
    state.players[ai].weapon = WeaponType::Rail;
    state.players[vi].x = 4.0;
    state.players[vi].z = 0.0;
    state.players[vi].hp = 50; // one Rail (75) kills

    assert_eq!(state.solo_broadcast.nods_cleared, 0);
    state.set_action(
        agent,
        Action {
            fire: true,
            ..Default::default()
        },
    );
    state.tick(0.05);
    assert_eq!(
        state.solo_broadcast.nods_cleared, 1,
        "Agent meatbag Rail frag of NODS must credit via lethal path"
    );
    assert!(state.players[vi].respawn_timer.is_some() || state.players[vi].hp <= 0);

    // Rule-bot killer must not credit.
    let bot_killer = Uuid::new_v4();
    let nods2 = Uuid::new_v4();
    state.add_player(bot_killer, "NODS-02".to_string(), Role::Agent);
    state.add_player(nods2, "NODS-03".to_string(), Role::Agent);
    state
        .bots
        .push(BotController::new(bot_killer, BotBehavior::Aggressive));
    state
        .bots
        .push(BotController::new(nods2, BotBehavior::Defensive));
    let (bi, ni) = {
        let bi = state
            .players
            .iter()
            .position(|p| p.id == bot_killer)
            .unwrap();
        let ni = state.players.iter().position(|p| p.id == nods2).unwrap();
        (bi, ni)
    };
    state.players[bi].x = 0.0;
    state.players[bi].z = 8.0;
    state.players[bi].yaw = 0.0;
    state.players[bi].weapon = WeaponType::Rail;
    state.players[bi].fire_cooldown = 0;
    state.players[ni].x = 4.0;
    state.players[ni].z = 8.0;
    state.players[ni].hp = 50;
    state.set_action(
        bot_killer,
        Action {
            fire: true,
            ..Default::default()
        },
    );
    state.tick(0.05);
    assert_eq!(
        state.solo_broadcast.nods_cleared, 1,
        "rule-bot frag of NODS must not credit"
    );
}

#[test]
fn solo_broadcast_map_name_matches_map_kind() {
    let mut arena = GameState::with_map(MapKind::ArenaDuel, false);
    arena.enable_solo_broadcast_ep0();
    assert_eq!(arena.snapshot().map_name, EPISODE_MAP_LARAK_LOT);
    assert_eq!(arena.snapshot().map_id, 1);

    let mut yard = GameState::with_map(MapKind::ComplianceYard, false);
    yard.enable_solo_broadcast_ep0();
    let snap = yard.snapshot();
    assert_eq!(snap.map_id, 2);
    assert_eq!(snap.map_name, MapKind::ComplianceYard.name());
    assert_ne!(snap.map_name, EPISODE_MAP_LARAK_LOT);
}

#[test]
fn jammer_dish_appears_on_snapshot_in_jammer_phase() {
    let mut session = GameSession::new();
    session.spawn_bots(2);
    session.enable_solo_broadcast_ep0();
    session.state.start_round();
    let human = Uuid::new_v4();
    session
        .state
        .add_player(human, "Meatbag".to_string(), Role::Human);
    let victim = session
        .state
        .players
        .iter()
        .find(|p| p.name.starts_with("NODS-"))
        .map(|p| p.id)
        .expect("NODS");
    assert!(session.state.snapshot().jammer_dish.is_none());
    while session.state.solo_broadcast.nods_cleared < session.state.solo_broadcast.nods_goal {
        session.state.note_nods_frag(human, victim);
    }
    let dish = session
        .state
        .snapshot()
        .jammer_dish
        .expect("jammer dish live in jammer phase");
    assert!(dish.live);
    assert!(!dish.seized);
    if let Some(p) = session.state.players.iter_mut().find(|p| p.id == human) {
        p.x = 0.0;
        p.z = 0.0;
        p.respawn_timer = None;
    }
    session.state.try_seize_jammer();
    let seized = session
        .state
        .snapshot()
        .jammer_dish
        .expect("jammer dish seized marker");
    assert!(!seized.live);
    assert!(seized.seized);
}

#[test]
fn try_seize_jammer_matches_visible_pad_not_tiny_hub() {
    // Playtest calib1 soft-lock: meatbag at ~4.6m on the dish ring while radius was 3.0.
    // Soft touch must cover the visible pad; health pad at z=8 stays outside.
    let mut session = GameSession::new();
    session.spawn_bots(2);
    session.enable_solo_broadcast_ep0();
    session.state.start_round();
    let human = Uuid::new_v4();
    session
        .state
        .add_player(human, "CalibFox".to_string(), Role::Human);
    let victim = session
        .state
        .players
        .iter()
        .find(|p| p.name.starts_with("NODS-"))
        .map(|p| p.id)
        .expect("NODS");
    while session.state.solo_broadcast.nods_cleared < session.state.solo_broadcast.nods_goal {
        session.state.note_nods_frag(human, victim);
    }
    assert_eq!(session.state.solo_broadcast.phase, EpisodePhase::Jammer);

    if let Some(p) = session.state.players.iter_mut().find(|p| p.id == human) {
        // On-pad stance from the stalled playtest dump (z≈4.6).
        p.x = 0.13;
        p.z = 4.62;
        p.respawn_timer = None;
    }
    session.state.try_seize_jammer();
    assert_eq!(
        session.state.solo_broadcast.phase,
        EpisodePhase::Auditor,
        "meatbag on visible pad must seize"
    );
    assert!(session.state.solo_broadcast.jammer_seized);

    // Fresh jammer phase: outside pad must not seize.
    let mut session = GameSession::new();
    session.spawn_bots(2);
    session.enable_solo_broadcast_ep0();
    session.state.start_round();
    let human = Uuid::new_v4();
    session
        .state
        .add_player(human, "CalibFox".to_string(), Role::Human);
    let victim = session
        .state
        .players
        .iter()
        .find(|p| p.name.starts_with("NODS-"))
        .map(|p| p.id)
        .expect("NODS");
    while session.state.solo_broadcast.nods_cleared < session.state.solo_broadcast.nods_goal {
        session.state.note_nods_frag(human, victim);
    }
    if let Some(p) = session.state.players.iter_mut().find(|p| p.id == human) {
        p.x = 0.0;
        p.z = 8.0; // north health pad
        p.respawn_timer = None;
    }
    session.state.try_seize_jammer();
    assert_eq!(
        session.state.solo_broadcast.phase,
        EpisodePhase::Jammer,
        "outside pad must not seize"
    );
    assert!(!session.state.solo_broadcast.jammer_seized);
}

#[test]
fn solo_broadcast_off_leaves_mp_snapshot_clean() {
    let mut session = GameSession::new();
    session.spawn_bots(2);
    let snap = session.state.snapshot();
    assert!(snap.episode_id.is_none());
    assert!(snap.episode_title.is_none());
    assert!(snap.episode_objective.is_none());
    assert!(snap.episode_progress.is_none());
    assert!(snap.episode_phase.is_none());
    assert_ne!(snap.map_name, EPISODE_MAP_LARAK_LOT);
}

#[test]
fn client_owned_yaw_replaces_the_turn_bits_and_steers_the_same_tick() {
    let mut state = GameState::new();
    state.start_round();
    let id = Uuid::new_v4();
    state.add_player(id, "Aimer".to_string(), Role::Human);
    let idx = state.players.iter().position(|p| p.id == id).unwrap();
    state.players[idx].x = 0.0;
    state.players[idx].z = 0.0;
    state.players[idx].yaw = 0.0;

    // Facing east (yaw 0) but told to face north (yaw pi/2) while running
    // forward: the fighter must travel north on this tick, not east.
    let north = std::f32::consts::PI / 2.0;
    state.set_action(
        id,
        Action {
            forward: true,
            turn_left: true,
            yaw: Some(north),
            seq: Some(7),
            ..Default::default()
        },
    );
    state.tick(0.05);

    let p = &state.players[idx];
    assert!(
        (p.yaw - north).abs() < 1e-5,
        "client yaw wins over the turn bits: {}",
        p.yaw
    );
    assert!(p.z > 0.01, "moved along the new facing: z={}", p.z);
    assert!(
        p.x.abs() < 1e-3,
        "did not move along the old facing: x={}",
        p.x
    );
    assert_eq!(p.last_input_seq, Some(7));

    // Yaw is normalised into [0, 2 pi).
    state.set_action(
        id,
        Action {
            yaw: Some(-std::f32::consts::FRAC_PI_2),
            ..Default::default()
        },
    );
    state.tick(0.05);
    let yaw = state.players[idx].yaw;
    assert!(
        (0.0..2.0 * std::f32::consts::PI).contains(&yaw)
            && (yaw - (1.5 * std::f32::consts::PI)).abs() < 1e-4,
        "negative yaw wraps: {yaw}"
    );

    // Nonsense yaw is ignored and the turn bits take over again.
    let before = state.players[idx].yaw;
    state.set_action(
        id,
        Action {
            turn_right: true,
            yaw: Some(f32::NAN),
            ..Default::default()
        },
    );
    state.tick(0.05);
    let after = state.players[idx].yaw;
    assert!(after.is_finite(), "yaw stays finite");
    assert!(
        (after - before).abs() > 1e-6,
        "turn bits still work without a usable yaw"
    );
}

#[test]
fn agents_keep_turning_with_bits_when_they_send_no_yaw() {
    let mut state = GameState::new();
    state.start_round();
    let id = Uuid::new_v4();
    state.add_player(id, "Probe".to_string(), Role::Agent);
    let idx = state.players.iter().position(|p| p.id == id).unwrap();
    state.players[idx].yaw = 1.0;
    state.set_action(
        id,
        Action {
            turn_right: true,
            ..Default::default()
        },
    );
    state.tick(0.05);
    assert!(
        state.players[idx].yaw > 1.0,
        "turn bits unchanged for agents: {}",
        state.players[idx].yaw
    );
    assert_eq!(state.players[idx].last_input_seq, None);
    assert!(
        state.input_acks().is_empty(),
        "agents are not acknowledged; they do not predict"
    );
}

#[test]
fn acks_report_the_state_the_input_produced() {
    let mut state = GameState::new();
    state.start_round();
    let human = Uuid::new_v4();
    let quiet = Uuid::new_v4();
    state.add_player(human, "Runner".to_string(), Role::Human);
    state.add_player(quiet, "Watcher".to_string(), Role::Human);
    assert!(
        state.input_acks().is_empty(),
        "nothing to acknowledge before an input arrives"
    );

    state.set_action(
        human,
        Action {
            forward: true,
            yaw: Some(0.0),
            seq: Some(41),
            ..Default::default()
        },
    );
    state.tick(0.05);

    let acks = state.input_acks();
    assert_eq!(
        acks.len(),
        1,
        "one ack, only for the client that numbers inputs"
    );
    let (id, msg) = &acks[0];
    assert_eq!(*id, human);
    let idx = state.players.iter().position(|p| p.id == human).unwrap();
    match msg {
        ServerMessage::Ack {
            seq,
            tick,
            x,
            z,
            yaw,
            pitch,
        } => {
            assert!(pitch.is_finite());
            assert_eq!(*seq, 41);
            assert_eq!(*tick, state.tick);
            assert_eq!(*x, state.players[idx].x);
            assert_eq!(*z, state.players[idx].z);
            assert_eq!(*yaw, state.players[idx].yaw);
            assert_eq!(*pitch, state.players[idx].pitch);
        }
        other => panic!("expected an Ack, got {other:?}"),
    }

    // A later input replaces the acknowledged sequence.
    state.set_action(
        human,
        Action {
            seq: Some(42),
            ..Default::default()
        },
    );
    state.tick(0.05);
    match &state.input_acks()[0].1 {
        ServerMessage::Ack { seq, .. } => assert_eq!(*seq, 42),
        other => panic!("expected an Ack, got {other:?}"),
    }
}

#[test]
fn action_wire_accepts_yaw_and_seq_and_still_accepts_neither() {
    let with_both: Action =
        serde_json::from_str(r#"{"forward":true,"yaw":1.25,"seq":9}"#).expect("new client");
    assert_eq!(with_both.yaw, Some(1.25));
    assert_eq!(with_both.seq, Some(9));
    let without: Action =
        serde_json::from_str(r#"{"forward":true,"turn_left":true}"#).expect("old client");
    assert_eq!(without.yaw, None);
    assert_eq!(without.seq, None);
    // Unknown fields are still rejected.
    assert!(serde_json::from_str::<Action>(r#"{"yaww":1.0}"#).is_err());
    // Omitted on the wire when absent, present when set.
    let json = serde_json::to_string(&Action::default()).unwrap();
    assert!(!json.contains("yaw"), "{json}");
    assert!(!json.contains("seq"), "{json}");
    let json = serde_json::to_string(&with_both).unwrap();
    assert!(
        json.contains("\"yaw\":1.25") && json.contains("\"seq\":9"),
        "{json}"
    );
    // The Ack shape agents and clients read.
    let ack = ServerMessage::Ack {
        pitch: 0.25,
        seq: 3,
        tick: 12,
        x: 1.5,
        z: -2.0,
        yaw: 0.5,
    };
    let json = serde_json::to_string(&ack).unwrap();
    assert!(json.contains("\"type\":\"ack\""), "{json}");
    assert!(
        json.contains("\"seq\":3") && json.contains("\"tick\":12"),
        "{json}"
    );
}

/// A straight, unobstructed east-west lane in the arena: a shooter position
/// and a target position `span` apart with nothing between them.
///
/// Tests used to hard-code a lane along the south edge. When the arena grew
/// and its cover was laid out again, a pillar landed exactly on the target's
/// old position and two shooting tests started reporting that a rail could not
/// hit anything. A test that asserts something about weapons should find its
/// own clear ground rather than assume the map never moves.
fn clear_lane(span: f32) -> (f32, f32) {
    let map = crate::sim::MapKind::ArenaDuel;
    let half = map.half_extent();
    let mut z = -(half - 4.0);
    while z < half - 4.0 {
        let shooter_x = -span / 2.0;
        let target_x = span / 2.0;
        let mut clear = true;
        // Sample along the lane, with the fighter's radius accounted for.
        let mut x = shooter_x;
        while x <= target_x {
            if crate::sim::circle_blocked_for_test(map, x, z) {
                clear = false;
                break;
            }
            x += 0.5;
        }
        if clear {
            return (z, span);
        }
        z += 1.0;
    }
    panic!("no clear lane of {span} units anywhere in the arena");
}

#[test]
fn dispersion_is_dispersion_not_free_aim() {
    use crate::protocol::WeaponType;

    // A lane the map itself says is clear, so only the weapon decides.
    let lane = |offset: f32| {
        let mut state = GameState::new();
        state.seed(11);
        state.config = crate::sim::MatchConfig {
            warmup_ticks: 1,
            boss_spawn_ticks: None,
            compliance_ping_ticks: None,
            ..crate::sim::MatchConfig::default()
        };
        state.start_round();
        let shooter = Uuid::new_v4();
        let target = Uuid::new_v4();
        state.add_player(shooter, "Shooter".to_string(), Role::Agent);
        state.add_player(target, "Target".to_string(), Role::Agent);
        let si = state.players.iter().position(|p| p.id == shooter).unwrap();
        let ti = state.players.iter().position(|p| p.id == target).unwrap();
        let (lane_z, span) = clear_lane(20.0);
        state.players[si].x = -span / 2.0;
        state.players[si].y = crate::sim::PLAYER_FLOOR_Y;
        state.players[si].z = lane_z;
        state.players[si].yaw = 0.0;
        state.players[si].weapon = WeaponType::Rail;
        state.players[ti].x = span / 2.0;
        state.players[ti].y = crate::sim::PLAYER_FLOOR_Y;
        state.players[ti].z = lane_z + offset;
        (state, shooter, ti)
    };

    // Fire `shots` times, counting hits. Health is restored every tick so the
    // target never dies and respawns somewhere else, which would silently turn
    // the rest of the run into misses.
    let fire_many = |state: &mut GameState, shooter: Uuid, ti: usize, shots: usize| {
        let full = state.players[ti].hp;
        let mut hits = 0;
        let mut fired = 0;
        while fired < shots {
            state.set_action(
                shooter,
                Action {
                    fire: true,
                    ..Default::default()
                },
            );
            let before = state.players[ti].hp;
            state.tick(0.05);
            if !state.shot_results.is_empty() {
                fired += 1;
                if state.players[ti].hp < before {
                    hits += 1;
                }
            }
            state.players[ti].hp = full;
            state.players[ti].armor = 0;
            state.players[ti].respawn_timer = None;
        }
        hits
    };

    // Dead centre at twenty units: the rail's cone is 0.7 degrees, which is
    // 0.24 units of wander at this range, well inside a fighter's half metre.
    let (mut state, shooter, ti) = lane(0.0);
    let centred = fire_many(&mut state, shooter, ti, 20);
    assert_eq!(centred, 20, "a rail shot on target should always land");

    // Two units off the line is about 5.7 degrees. The old code accepted
    // anything inside the cone, so this counted as a hit; now the shot has to
    // pass within a fighter's radius, and it does not.
    let (mut state, shooter, ti) = lane(2.0);
    let missed = fire_many(&mut state, shooter, ti, 20);
    assert_eq!(missed, 0, "a shot that misses by two units should miss");

    // The scatter gun's wide cone does wander, which is the point: dispersion
    // at the edge of its reach, not a guaranteed hit.
    let (mut state, shooter, ti) = lane(0.0);
    let si = state.players.iter().position(|p| p.id == shooter).unwrap();
    // Eleven units down the same lane, measured from wherever the lane is.
    state.players[ti].x = state.players[si].x + 11.0;
    state.players[si].weapon = WeaponType::Scatter;
    let scattered = fire_many(&mut state, shooter, ti, 40);
    assert!(
        (1..40).contains(&scattered),
        "an eleven unit scatter shot should sometimes land and sometimes not, got {scattered} of 40"
    );
}

#[test]
fn the_scatter_gun_falls_off_with_distance() {
    use crate::protocol::{WeaponType, SCATTER_FAR_DAMAGE_SCALE, SCATTER_FULL_DAMAGE_UNITS};

    let scatter = WeaponType::Scatter;
    let full = scatter.damage();
    assert_eq!(scatter.damage_at(0.0), full, "point blank is full damage");
    assert_eq!(
        scatter.damage_at(SCATTER_FULL_DAMAGE_UNITS),
        full,
        "the full-damage band reaches four units"
    );
    let edge = scatter.damage_at(scatter.range_units());
    assert_eq!(
        edge,
        (full as f32 * SCATTER_FAR_DAMAGE_SCALE).round() as i32,
        "the far end keeps only its share"
    );
    assert!(edge < full && edge > 0);
    // Monotonic in between, never zero, and beyond the reach it stays at the floor.
    let mut previous = full;
    let mut d = SCATTER_FULL_DAMAGE_UNITS;
    while d <= scatter.range_units() {
        let dealt = scatter.damage_at(d);
        assert!(
            dealt <= previous,
            "falloff should never rise: {d} gave {dealt}"
        );
        assert!(dealt > 0);
        previous = dealt;
        d += 0.5;
    }
    assert_eq!(scatter.damage_at(1000.0), edge);
    assert_eq!(
        scatter.damage_at(f32::NAN),
        full,
        "nonsense distance is not a bonus"
    );

    // The other two do not fall off at all.
    for weapon in [WeaponType::Flechette, WeaponType::Rail] {
        for distance in [0.0, 5.0, 25.0, 60.0, 1000.0] {
            assert_eq!(
                weapon.damage_at(distance),
                weapon.damage(),
                "{weapon:?} should not fall off"
            );
        }
    }
}

#[cfg(test)]
mod jump_tests {
    use super::*;

    #[test]
    fn a_human_walks_up_the_arena_stairs_without_jumping() {
        let mut state = GameState::new();
        let id = Uuid::new_v4();
        state.add_player(id, "Walker".into(), Role::Human);
        state.start_round();
        state.players[0].x = 7.0;
        state.players[0].z = -4.0;
        state.players[0].y = crate::sim::PLAYER_FLOOR_Y;
        state.set_action(
            id,
            Action {
                forward: true,
                yaw: Some(-std::f32::consts::FRAC_PI_2),
                ..Action::default()
            },
        );
        for _ in 0..60 {
            state.tick(0.05);
        }
        let player = &state.players[0];
        assert!(
            player.z < -18.0,
            "stopped at ({}, {}, {})",
            player.x,
            player.y,
            player.z
        );
        assert!((player.y - crate::sim::PLAYER_FLOOR_Y - 2.6).abs() < 0.01);
    }

    fn jumping() -> Action {
        Action {
            jump: true,
            ..Action::default()
        }
    }

    #[test]
    fn a_short_jump_tap_survives_release_before_the_next_tick() {
        let mut state = GameState::new();
        let id = Uuid::new_v4();
        state.add_player(id, "Tapper".into(), Role::Human);
        state.start_round();
        state.set_action(id, jumping());
        state.set_action(id, Action::default());
        state.tick(0.05);
        assert!(state.players[0].y > crate::sim::PLAYER_FLOOR_Y);
        for _ in 0..80 {
            state.tick(0.05);
        }
        assert_eq!(state.players[0].y, crate::sim::PLAYER_FLOOR_Y);
        assert_eq!(state.players[0].vy, 0.0, "a released tap must not repeat");
    }

    /// A grounded fighter leaves the floor, rises, and comes back down to it.
    #[test]
    fn a_jump_goes_up_and_returns() {
        let mut state = GameState::new();
        let id = Uuid::new_v4();
        state.add_player(id, "Jumper".to_string(), Role::Human);
        state.start_round();
        let floor = crate::sim::PLAYER_FLOOR_Y;

        state.set_action(id, jumping());
        state.tick(0.05);
        let after_one = state.players[0].y;
        assert!(
            after_one > floor,
            "one tick of jump should leave the floor, got {after_one}"
        );

        // Climb, then fall. Hold nothing: a jump is not a thrust.
        state.set_action(id, Action::default());
        let mut peak = after_one;
        let mut ticks = 0;
        while ticks < 200 {
            state.tick(0.05);
            peak = peak.max(state.players[0].y);
            if state.players[0].y <= floor && ticks > 2 {
                break;
            }
            ticks += 1;
        }
        assert!(
            peak - floor > 0.8,
            "a jump should clear something, peaked {:.2} above the floor",
            peak - floor
        );
        assert!(
            (state.players[0].y - floor).abs() < 1e-3,
            "it has to come back down, ended at {}",
            state.players[0].y
        );
        assert!(
            ticks < 60,
            "and it should not hang in the air for {ticks} ticks"
        );
    }

    /// Holding jump in the air does not climb, which is what stops a held key
    /// from being flight.
    #[test]
    fn holding_jump_does_not_fly() {
        let mut state = GameState::new();
        let id = Uuid::new_v4();
        state.add_player(id, "Holder".to_string(), Role::Human);
        state.start_round();
        state.set_action(id, jumping());
        let mut peak: f32 = 0.0;
        for _ in 0..120 {
            state.tick(0.05);
            peak = peak.max(state.players[0].y);
        }
        assert!(
            peak - crate::sim::PLAYER_FLOOR_Y < 2.0,
            "held jump climbed to {:.2}, which is flight",
            peak - crate::sim::PLAYER_FLOOR_Y
        );
    }

    /// Dying mid-jump and respawning must not leave you falling.
    #[test]
    fn a_respawn_lands_you_standing() {
        let mut state = GameState::new();
        let id = Uuid::new_v4();
        state.add_player(id, "Faller".to_string(), Role::Human);
        state.start_round();
        state.set_action(id, jumping());
        state.tick(0.05);
        state.tick(0.05);
        assert!(
            state.players[0].vy != 0.0,
            "should be in the air to test this"
        );
        // Kill them mid-air and let the respawn clock run out.
        state.players[0].hp = 0;
        state.players[0].respawn_timer = Some(1);
        state.set_action(id, Action::default());
        state.tick(0.05);
        state.tick(0.05);
        assert_eq!(state.players[0].vy, 0.0, "respawned still falling");
        assert_eq!(state.players[0].y, crate::sim::PLAYER_FLOOR_Y);
    }
}

/// The map roster: every layout in `maps.rs`, checked against the rules that
/// have actually broken playtests rather than against remembered coordinates.
mod map_roster {
    use super::*;
    use crate::maps;
    use crate::movement::{STEP_UP, WALL_TOP};
    use crate::sim::{PickupKind, PLAYER_FLOOR_Y};

    #[test]
    fn every_map_validates() {
        for map in MapKind::ALL {
            let problems = maps::validate(map);
            assert!(
                problems.is_empty(),
                "{} is not safe to play:\n  {}",
                map.name(),
                problems.join("\n  ")
            );
        }
    }

    #[test]
    fn every_map_is_bigger_than_the_square_it_replaced() {
        // The tip was one flat hundred metre square, twice over. Nothing in
        // the roster may be smaller than that, which is the whole complaint.
        for map in MapKind::ALL {
            let extent = map.half_extent() * 2.0;
            assert!(
                extent > 100.0,
                "{} is {extent} m across, no bigger than the old square",
                map.name()
            );
        }
        let biggest = MapKind::ALL
            .iter()
            .map(|m| m.half_extent() * 2.0)
            .fold(0.0f32, f32::max);
        assert!(
            biggest >= 280.0,
            "the roster tops out at {biggest} m, which is not a field tier map"
        );
    }

    #[test]
    fn every_map_has_height_in_it() {
        for map in MapKind::ALL {
            let solids = map.obstacles();
            let treads = solids
                .iter()
                .filter(|s| s.top > 0.0 && s.top <= STEP_UP + 0.001)
                .count();
            assert!(
                treads > 0,
                "{} has no steps, so nothing on it can be climbed",
                map.name()
            );
            let decks = solids
                .iter()
                .filter(|s| s.top > STEP_UP && s.top < WALL_TOP)
                .count();
            assert!(decks > 0, "{} has no ground above the floor", map.name());
        }
    }

    #[test]
    fn every_map_has_a_full_pad_set_and_one_of_them_is_off_the_floor() {
        for map in MapKind::ALL {
            let pads = map.pickups();
            assert_eq!(pads.len(), 6, "{} pad count", map.name());
            for want in [
                "pad_rail",
                "pad_scatter",
                "pad_flechette",
                "pad_health_n",
                "pad_health_s",
                "pad_armor",
            ] {
                assert!(
                    pads.iter().any(|p| p.id == want),
                    "{} is missing {want}",
                    map.name()
                );
            }
            assert!(
                pads.iter().any(|p| p.floor > STEP_UP),
                "{} keeps every pad on the floor, so height buys nothing",
                map.name()
            );
            for pad in &pads {
                assert!(
                    (pad.y - (pad.floor + 0.4)).abs() < 1e-5,
                    "{} pad {} draws at {} but stands on {}",
                    map.name(),
                    pad.id,
                    pad.y,
                    pad.floor
                );
            }
        }
    }

    #[test]
    fn ids_names_and_rotation_cover_the_roster() {
        for (i, map) in MapKind::ALL.into_iter().enumerate() {
            assert_eq!(map.id(), i as u32 + 1);
            assert_eq!(map.index(), i);
            assert_eq!(MapKind::from_cli(&map.id().to_string()), Some(map));
            assert!(!map.name().is_empty());
            assert!(!map.blurb().is_empty());
        }
        let mut map = MapKind::ArenaDuel;
        let mut seen = Vec::new();
        for _ in 0..MapKind::ALL.len() {
            seen.push(map);
            map = map.next();
        }
        assert_eq!(map, MapKind::ArenaDuel, "rotation returns to the start");
        assert_eq!(seen.len(), MapKind::ALL.len());
        assert_eq!(
            MapKind::from_cli("Reclamation_Gulch"),
            Some(MapKind::ReclamationGulch)
        );
        assert_eq!(MapKind::from_cli("tripoint"), Some(MapKind::TripointWorks));
        assert_eq!(MapKind::from_cli("nope"), None);
    }

    #[test]
    fn a_fighter_walks_off_the_gantry_and_falls_to_the_floor() {
        // Coordinates come from the map, not from memory: the rail pad says
        // where the walkway is and how high it is.
        let map = MapKind::ArenaDuel;
        let rail = map
            .pickups()
            .into_iter()
            .find(|p| p.kind == PickupKind::Weapon(WeaponType::Rail))
            .expect("every map has a rail pad");
        assert!(rail.floor > STEP_UP, "Arena Duel's rail is on the walkway");

        let mut state = GameState::with_map(map, false);
        state.config = MatchConfig {
            warmup_ticks: 1,
            boss_spawn_ticks: None,
            compliance_ping_ticks: None,
            ..MatchConfig::default()
        };
        state.start_round();
        let id = Uuid::new_v4();
        state.add_player(id, "Walker".into(), Role::Human);
        let toward_middle = (-rail.z).atan2(-rail.x);
        if let Some(p) = state.players.iter_mut().find(|p| p.id == id) {
            p.x = rail.x;
            p.z = rail.z;
            p.y = PLAYER_FLOOR_Y + rail.floor;
            p.yaw = toward_middle;
        }
        state.tick(0.05);
        let standing = state.players.iter().find(|p| p.id == id).unwrap().y;
        assert!(
            (standing - (PLAYER_FLOOR_Y + rail.floor)).abs() < 1e-4,
            "standing still on the walkway stays on it, y={standing}"
        );

        for _ in 0..60 {
            state.set_action(
                id,
                Action {
                    forward: true,
                    yaw: Some(toward_middle),
                    ..Default::default()
                },
            );
            state.tick(0.05);
        }
        let player = state.players.iter().find(|p| p.id == id).unwrap();
        assert!(
            (player.y - PLAYER_FLOOR_Y).abs() < 1e-3,
            "walking off the walkway lands on the floor, y={}",
            player.y
        );
        assert!(
            (player.x - rail.x).hypot(player.z - rail.z) > 8.0,
            "walking off a deck must continue beyond the inflated edge: ({}, {})",
            player.x,
            player.z
        );
    }

    #[test]
    fn a_pad_on_a_deck_is_not_claimable_from_the_floor() {
        let map = MapKind::ArenaDuel;
        let config = MatchConfig {
            warmup_ticks: 1,
            boss_spawn_ticks: None,
            compliance_ping_ticks: None,
            ..MatchConfig::default()
        };
        let mut state = GameState::with_map(map, false);
        state.config = config.clone();
        state.start_round();
        let id = Uuid::new_v4();
        state.add_player(id, "Reacher".into(), Role::Human);
        let armor = state
            .pickups
            .iter()
            .find(|p| p.id == "pad_armor")
            .map(|p| (p.x, p.z))
            .unwrap();
        if let Some(p) = state.players.iter_mut().find(|p| p.id == id) {
            p.x = armor.0;
            p.z = armor.1;
            p.y = PLAYER_FLOOR_Y;
            p.armor = 0;
        }
        state.tick(0.05);
        assert!(
            state.players.iter().find(|p| p.id == id).unwrap().armor > 0,
            "a pad on the floor is claimed from the floor"
        );

        // The same pad three metres up is not, because the fighter is not on
        // the surface it lies on.
        let mut high = GameState::with_map(map, false);
        high.config = config;
        high.start_round();
        let id2 = Uuid::new_v4();
        high.add_player(id2, "Reacher".into(), Role::Human);
        if let Some(pad) = high.pickups.iter_mut().find(|p| p.id == "pad_armor") {
            pad.floor = 3.0;
            pad.y = 3.4;
        }
        if let Some(p) = high.players.iter_mut().find(|p| p.id == id2) {
            p.x = armor.0;
            p.z = armor.1;
            p.y = PLAYER_FLOOR_Y;
            p.armor = 0;
        }
        high.tick(0.05);
        assert_eq!(
            high.players.iter().find(|p| p.id == id2).unwrap().armor,
            0,
            "a pad above the fighter's head is not claimed by walking under it"
        );
    }

    #[test]
    fn a_deck_sees_the_floor_below_it() {
        // Directive 17's quadrant decks look down into the pit, which is what
        // makes the middle of that map a fishbowl rather than a safe hole.
        // The shot line runs from the shooter's eye to the target's, so the
        // deck the shooter is standing on does not block its own shot.
        let map = MapKind::Directive17;
        let low = map
            .obstacles()
            .iter()
            .filter(|s| s.top < crate::movement::EYE_HEIGHT)
            .count();
        assert!(low > 0, "the decks are reached by ramps, not by walls");

        let mut state = GameState::with_map(map, false);
        state.seed(7);
        state.config = MatchConfig {
            warmup_ticks: 1,
            boss_spawn_ticks: None,
            compliance_ping_ticks: None,
            ..MatchConfig::default()
        };
        state.start_round();
        let shooter = Uuid::new_v4();
        let target = Uuid::new_v4();
        state.add_player(shooter, "Deck".into(), Role::Human);
        state.add_player(target, "Pit".into(), Role::Human);
        // The shooter stands where the map says a deck is: on a pad whose own
        // floor is above the ground.
        let perch = state
            .pickups
            .iter()
            .find(|p| p.floor > crate::movement::STEP_UP)
            .map(|p| (p.x, p.z, p.floor))
            .expect("Directive 17 has a pad up on a deck");
        // The pit is where the rail is, on the floor at the middle of the map.
        let pit = state
            .pickups
            .iter()
            .find(|p| p.id == "pad_rail")
            .map(|p| (p.x, p.z))
            .unwrap();
        let aim = (pit.1 - perch.1).atan2(pit.0 - perch.0);
        for (id, x, z, y) in [
            (shooter, perch.0, perch.1, PLAYER_FLOOR_Y + perch.2),
            (target, pit.0, pit.1, PLAYER_FLOOR_Y),
        ] {
            if let Some(p) = state.players.iter_mut().find(|p| p.id == id) {
                p.x = x;
                p.z = z;
                p.y = y;
                p.yaw = aim;
                p.weapon = WeaponType::Rail;
            }
        }
        // Hold the two of them in place and fire until a shot actually leaves
        // the barrel: the first tick only ends the warmup.
        let mut hit = false;
        for _ in 0..20 {
            state.spawn_shields.clear();
            let ti = state.players.iter().position(|p| p.id == target).unwrap();
            state.players[ti].hp = 100;
            state.players[ti].x = pit.0;
            state.players[ti].z = pit.1;
            state.players[ti].y = PLAYER_FLOOR_Y;
            let si = state.players.iter().position(|p| p.id == shooter).unwrap();
            state.players[si].x = perch.0;
            state.players[si].z = perch.1;
            state.players[si].y = PLAYER_FLOOR_Y + perch.2;
            state.set_action(
                shooter,
                Action {
                    fire: true,
                    yaw: Some(aim),
                    look_at: Some(crate::protocol::LookAt {
                        // Aim at the exposed upper body. The deck correctly
                        // occludes a ray toward the target's lower torso.
                        x: Some(pit.0),
                        y: Some(crate::movement::EYE_HEIGHT),
                        z: Some(pit.1),
                        ..Default::default()
                    }),
                    ..Default::default()
                },
            );
            state.tick(0.05);
            if state.players[ti].hp < 100 {
                hit = true;
                break;
            }
        }
        assert!(
            hit,
            "a fighter on a deck can shoot a fighter on the floor: the deck it \
             stands on is below the line of its own shot"
        );
    }
}
#[test]
fn round_podium_uses_score_then_callsign_for_ties() {
    for names in [["Zulu", "Alpha", "Leader"], ["Leader", "Alpha", "Zulu"]] {
        let mut state = crate::sim::GameState::default();
        state.start_round();
        for (index, name) in names.into_iter().enumerate() {
            let id = uuid::Uuid::from_u128(index as u128 + 1);
            state.add_player(id, name.to_string(), crate::protocol::Role::Human);
            state
                .scores
                .insert(id, if name == "Leader" { 5 } else { 4 });
        }
        state.end_round("test".into());
        let event = state
            .take_events()
            .into_iter()
            .find_map(|event| match event {
                crate::protocol::GameEvent::RoundEnd {
                    winner,
                    final_scores,
                    ..
                } => Some((winner, final_scores)),
                _ => None,
            })
            .unwrap();
        assert_eq!(event.0.as_deref(), Some("Leader"));
        assert_eq!(
            event.1.iter().map(|s| s.name.as_str()).collect::<Vec<_>>(),
            ["Leader", "Alpha", "Zulu"]
        );
        for score in state.scores.values_mut() {
            *score = 5;
        }
        state.end_round("all tied".into());
        assert_eq!(state.ended_mvp.as_deref(), Some("Alpha"));
        state.events.clear();
        state.start_round();
        assert!(
            state.events.iter().any(|event| matches!(event,
                GameEvent::RoundStart { previous_winner: Some(name), .. } if name == "Alpha"
            )),
            "next-round identity must use the same podium ordering"
        );
    }
}

mod vertical_aim {
    use super::*;
    use crate::combat::{aim_at, PITCH_LIMIT};
    use crate::protocol::LookAt;
    use crate::sim::{BotBehavior, BotController, PLAYER_FLOOR_Y};

    fn pair(shooter_height: f32, target_height: f32) -> (GameState, Uuid, Uuid) {
        let mut state = GameState::new();
        state.seed(42);
        state.start_round();
        let shooter = Uuid::new_v4();
        let target = Uuid::new_v4();
        state.add_player(shooter, "Shooter".into(), Role::Human);
        state.add_player(target, "Target".into(), Role::Agent);
        let (z, span) = clear_lane(10.0);
        let x = -span * 0.5;
        state.players[0].x = x;
        state.players[0].z = z;
        state.players[0].y = PLAYER_FLOOR_Y + shooter_height;
        state.players[0].yaw = 0.0;
        state.players[0].weapon = WeaponType::Rail;
        state.players[1].x = x + 10.0;
        state.players[1].z = z;
        state.players[1].y = PLAYER_FLOOR_Y + target_height;
        state.spawn_shields.clear();
        (state, shooter, target)
    }

    #[test]
    fn shot_trace_describes_fighter_floor_and_clear_range() {
        use crate::protocol::ShotImpact;
        for pitch in [0.0, -1.2, 1.2] {
            let (mut state, shooter, _) = pair(0.0, 0.0);
            state.set_action(
                shooter,
                Action {
                    fire: true,
                    pitch: Some(pitch),
                    ..Default::default()
                },
            );
            state.tick(0.0);
            let result = &state.shot_results[0];
            let trace = result.trace.as_ref().unwrap();
            assert_eq!(trace.weapon, WeaponType::Rail);
            assert_eq!(trace.origin[1], crate::movement::EYE_HEIGHT);
            let distance = trace
                .end
                .iter()
                .zip(trace.origin)
                .map(|(a, b)| (a - b).powi(2))
                .sum::<f32>()
                .sqrt();
            match pitch {
                0.0 => {
                    assert!(matches!(trace.impact, ShotImpact::Fighter { .. }));
                    assert!((9.5..10.0).contains(&distance));
                    assert!(result.hit && !result.killed);
                }
                p if p < 0.0 => {
                    assert_eq!(
                        trace.impact,
                        ShotImpact::Solid {
                            normal: [0.0, 1.0, 0.0]
                        }
                    );
                    assert!(trace.end[1].abs() < 1e-5);
                    assert!(!result.hit);
                }
                _ => {
                    assert_eq!(trace.impact, ShotImpact::Range);
                    assert!((distance - WeaponType::Rail.range_units()).abs() < 1e-4);
                    assert!(!result.hit);
                }
            }
            let decoded: crate::protocol::ShotResult =
                serde_json::from_str(&serde_json::to_string(result).unwrap()).unwrap();
            assert_eq!(&decoded, result);
        }
        let old: crate::protocol::ShotResult = serde_json::from_value(serde_json::json!({
            "shooter_id": Uuid::nil(), "shooter": "Old", "hit": false, "damage": 0
        }))
        .unwrap();
        assert!(old.trace.is_none() && !old.killed);
    }

    #[test]
    fn simultaneous_trade_keeps_both_lethal_shots_without_surviving_pawns() {
        let (mut state, a, b) = pair(0.0, 0.0);
        for player in &mut state.players {
            player.hp = 80;
            player.weapon = WeaponType::Rail;
        }
        for (shooter, victim) in [(a, b), (b, a)] {
            state.set_action(
                shooter,
                Action {
                    fire: true,
                    look_at: Some(LookAt {
                        player_id: Some(victim),
                        ..Default::default()
                    }),
                    ..Default::default()
                },
            );
        }
        state.tick(0.0);
        assert!(state.snapshot().players.is_empty());
        assert_eq!(state.shot_results.len(), 2);
        assert!(state
            .shot_results
            .iter()
            .all(|shot| shot.killed && shot.hit && shot.trace.is_some()));
        assert_eq!(state.scores[&a], 1);
        assert_eq!(state.scores[&b], 1);
    }

    #[test]
    fn several_committed_hits_award_only_one_death() {
        let (mut state, a, victim) = pair(0.0, 0.0);
        let b = Uuid::new_v4();
        state.add_player(b, "Second".into(), Role::Agent);
        let (z, _) = clear_lane(20.0);
        for (player, x) in state.players.iter_mut().zip([-10.0, 0.0, 10.0]) {
            player.x = x;
            player.z = z;
            player.y = PLAYER_FLOOR_Y;
            player.weapon = WeaponType::Rail;
        }
        state.players[1].hp = 80;
        state.spawn_shields.clear();
        for shooter in [a, b] {
            state.set_action(
                shooter,
                Action {
                    fire: true,
                    look_at: Some(LookAt {
                        player_id: Some(victim),
                        ..Default::default()
                    }),
                    ..Default::default()
                },
            );
        }
        state.tick(0.0);
        assert_eq!(state.shot_results.len(), 2);
        assert_eq!(
            state.shot_results.iter().filter(|shot| shot.killed).count(),
            1
        );
        assert_eq!(
            state
                .shot_results
                .iter()
                .map(|shot| shot.damage)
                .sum::<i32>(),
            80
        );
        assert_eq!(state.scores.values().sum::<u32>(), 1);
        assert_eq!(
            state
                .events
                .iter()
                .filter(|event| matches!(event, GameEvent::Frag { .. }))
                .count(),
            1
        );
    }

    #[test]
    fn human_pitch_controls_hits_at_every_elevation() {
        for (from, to) in [(0.0, 0.0), (0.0, 4.0), (4.0, 0.0)] {
            let (base, _, _) = pair(from, to);
            let a = &base.players[0];
            let b = &base.players[1];
            let (_, correct) = aim_at(
                [a.x, from + crate::movement::EYE_HEIGHT, a.z],
                [b.x, to + 0.9, b.z],
            )
            .unwrap();
            for (pitch, should_hit) in [
                (correct, true),
                (correct + 0.6, false),
                (correct - 0.6, false),
            ] {
                let (mut state, shooter, _) = pair(from, to);
                state.set_action(
                    shooter,
                    Action {
                        fire: true,
                        yaw: Some(0.0),
                        pitch: Some(pitch),
                        ..Default::default()
                    },
                );
                // Zero dt holds airborne fixtures still while resolving a real sim tick.
                state.tick(0.0);
                assert_eq!(
                    state.players[1].hp < 100,
                    should_hit,
                    "from={from}, to={to}, pitch={pitch}"
                );
                assert_eq!(state.shot_results.len(), 1);
                assert_eq!(state.shot_results[0].hit, should_hit);
            }
        }
    }

    #[test]
    fn nearest_fighter_blocks_a_farther_fighter_regardless_of_roster_order() {
        for swap in [false, true] {
            let (mut state, shooter, far) = pair(0.0, 0.0);
            let near = Uuid::new_v4();
            state.add_player(near, "Near".into(), Role::Agent);
            state.players[2].x = state.players[0].x + 5.0;
            state.players[2].z = state.players[0].z;
            state.players[2].y = PLAYER_FLOOR_Y;
            state.spawn_shields.clear();
            if swap {
                state.players.swap(1, 2);
            }
            state.set_action(
                shooter,
                Action {
                    fire: true,
                    yaw: Some(0.0),
                    pitch: Some(0.0),
                    ..Default::default()
                },
            );
            state.tick(0.0);
            assert_eq!(state.shot_results[0].target_id, Some(near));
            assert_eq!(state.players.iter().find(|p| p.id == far).unwrap().hp, 100);
        }
    }

    #[test]
    fn looking_horizontally_does_not_auto_hit_a_fighter_on_another_level() {
        let (mut state, shooter, _) = pair(0.0, 4.0);
        state.set_action(
            shooter,
            Action {
                fire: true,
                yaw: Some(0.0),
                pitch: Some(0.0),
                ..Default::default()
            },
        );
        state.tick(0.0);
        assert_eq!(state.players[1].hp, 100);
    }

    #[test]
    fn target_actions_and_rule_bots_aim_at_height_through_the_same_contract() {
        let (mut state, shooter, target) = pair(0.0, 4.0);
        let bot = BotController::new(shooter, BotBehavior::Aggressive);
        let action = bot.update(&state);
        assert!(action.pitch.unwrap() > 0.2);
        state.set_action(
            shooter,
            Action {
                fire: true,
                yaw: Some(3.0),
                pitch: Some(-1.0),
                look_at: Some(LookAt {
                    player_id: Some(target),
                    ..Default::default()
                }),
                ..Default::default()
            },
        );
        state.tick(0.0);
        assert!(state.players[1].hp < 100);
        assert!(state.players[0].pitch > 0.2);
        let x = state.players[1].x;
        let z = state.players[1].z;
        state.set_action(
            shooter,
            Action {
                look_at: Some(LookAt {
                    x: Some(x),
                    z: Some(z),
                    ..Default::default()
                }),
                ..Default::default()
            },
        );
        state.tick(0.0);
        assert_eq!(
            state.players[0].pitch, 0.0,
            "legacy x/z target means horizontal aim"
        );
    }

    #[test]
    fn pitch_is_bounded_persistent_acknowledged_and_reset_on_respawn() {
        let (mut state, shooter, _) = pair(0.0, 0.0);
        state.set_action(
            shooter,
            Action {
                pitch: Some(10.0),
                seq: Some(3),
                ..Default::default()
            },
        );
        state.tick(0.0);
        assert_eq!(state.players[0].pitch, PITCH_LIMIT);
        state.set_action(shooter, Action::default());
        state.tick(0.0);
        assert_eq!(state.players[0].pitch, PITCH_LIMIT);
        state.set_action(
            shooter,
            Action {
                pitch: Some(f32::NAN),
                look_at: Some(LookAt {
                    x: Some(f32::INFINITY),
                    y: Some(2.0),
                    z: Some(0.0),
                    player_id: None,
                }),
                ..Default::default()
            },
        );
        state.tick(0.0);
        assert_eq!(state.players[0].pitch, PITCH_LIMIT);
        assert!(state.players[0].yaw.is_finite());
        assert_eq!(state.snapshot().players[0].pitch, PITCH_LIMIT);
        assert!(
            matches!(state.input_acks()[0].1, ServerMessage::Ack { pitch, .. } if pitch == PITCH_LIMIT)
        );
        state.players[0].respawn_timer = Some(1);
        state.tick(0.0);
        assert_eq!(state.players[0].pitch, 0.0);
    }

    #[test]
    fn old_messages_default_pitch_and_new_messages_round_trip() {
        let old: Action = serde_json::from_str(r#"{"fire":true,"yaw":1.0}"#).unwrap();
        assert_eq!(old.pitch, None);
        let old_ack: ServerMessage =
            serde_json::from_str(r#"{"type":"ack","seq":1,"tick":2,"x":0,"z":0,"yaw":0}"#).unwrap();
        assert!(matches!(old_ack, ServerMessage::Ack { pitch: 0.0, .. }));
        let action = Action {
            pitch: Some(0.4),
            look_at: Some(LookAt {
                x: Some(2.0),
                y: Some(3.0),
                z: Some(4.0),
                player_id: None,
            }),
            ..Default::default()
        };
        let decoded: Action =
            serde_json::from_str(&serde_json::to_string(&action).unwrap()).unwrap();
        assert_eq!(decoded.pitch, action.pitch);
        assert_eq!(decoded.look_at, action.look_at);
        let (state, _, _) = pair(0.0, 0.0);
        let mut player = serde_json::to_value(&state.snapshot().players[0]).unwrap();
        player.as_object_mut().unwrap().remove("pitch");
        assert_eq!(
            serde_json::from_value::<PlayerState>(player).unwrap().pitch,
            0.0
        );
    }
}
