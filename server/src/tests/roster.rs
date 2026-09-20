//! Roster checks through the production session and network loop.
use super::*;
use futures_util::{SinkExt, StreamExt};
use std::collections::{BTreeMap, HashMap};
use std::time::Duration;
use tokio_tungstenite::{connect_async, tungstenite::Message, MaybeTlsStream, WebSocketStream};

type Socket = WebSocketStream<MaybeTlsStream<tokio::net::TcpStream>>;

async fn receive(socket: &mut Socket) -> ServerMessage {
    tokio::time::timeout(Duration::from_secs(3), async {
        loop {
            let message = socket.next().await.expect("open stream").expect("frame");
            if let Message::Text(text) = message {
                return serde_json::from_str(&text).expect("server wire message");
            }
        }
    })
    .await
    .expect("server response deadline")
}

async fn join(url: &str, role: Role, name: &str) -> (Socket, Option<Uuid>) {
    let (mut socket, _) = connect_async(url).await.expect("connect");
    socket
        .send(Message::Text(
            serde_json::to_string(&ClientMessage::Hello {
                gameplay_version: crate::protocol::GAMEPLAY_VERSION,
                geometry_version: crate::protocol::GEOMETRY_VERSION,
                role,
                name: name.into(),
            })
            .unwrap(),
        ))
        .await
        .unwrap();
    match receive(&mut socket).await {
        ServerMessage::Welcome {
            player_id,
            role: actual,
            ..
        } => {
            assert_eq!(actual, role);
            (socket, player_id)
        }
        message => panic!("expected welcome, got {message:?}"),
    }
}

#[tokio::test]
async fn mixed_roles_share_movement_and_leave_cleanly_on_every_map() {
    for map in MapKind::ALL {
        let (ready_tx, ready_rx) = tokio::sync::oneshot::channel();
        let (stop_tx, stop_rx) = tokio::sync::oneshot::channel();
        let server = tokio::spawn(crate::run::run_server(
            crate::run::ServerOptions {
                bind: "127.0.0.1:0".into(),
                bots: 0,
                map,
                match_config: Some(MatchConfig {
                    warmup_ticks: 1,
                    boss_spawn_ticks: None,
                    compliance_ping_ticks: None,
                    ..MatchConfig::default()
                }),
                ..Default::default()
            },
            async {
                let _ = stop_rx.await;
            },
            Some(ready_tx),
        ));
        let url = format!("ws://{}", ready_rx.await.unwrap());
        let exercise = async {
            let (mut human, human_id) = join(&url, Role::Human, "Meat Proxy").await;
            let (mut agent, agent_id) = join(&url, Role::Agent, "Free Agent").await;
            let (mut spectator, spectator_id) = join(&url, Role::Spectator, "Observer").await;
            assert!(spectator_id.is_none());
            let ids = [human_id.unwrap(), agent_id.unwrap()];
            let baseline = loop {
                if let ServerMessage::Snapshot(snapshot) = receive(&mut spectator).await {
                    if snapshot.players.len() == 2 {
                        assert_eq!(snapshot.map_id, map.id());
                        break snapshot;
                    }
                }
            };
            for (index, socket) in [&mut human, &mut agent].into_iter().enumerate() {
                socket
                    .send(Message::Text(
                        serde_json::to_string(&ClientMessage::Action(Action {
                            forward: true,
                            jump: true,
                            seq: Some(67),
                            ..Default::default()
                        }))
                        .unwrap(),
                    ))
                    .await
                    .unwrap();
                // Acks support human prediction; agents observe snapshots.
                if index == 0 {
                    loop {
                        if let ServerMessage::Ack { seq: 67, .. } = receive(socket).await {
                            break;
                        }
                    }
                }
            }
            let mut moved = [false; 2];
            let mut jumped = [false; 2];
            for _ in 0..40 {
                let ServerMessage::Snapshot(snapshot) = receive(&mut spectator).await else {
                    continue;
                };
                for (index, id) in ids.iter().enumerate() {
                    let before = baseline.players.iter().find(|p| p.id == *id).unwrap();
                    let now = snapshot.players.iter().find(|p| p.id == *id).unwrap();
                    moved[index] |= (now.x - before.x).hypot(now.z - before.z) > 0.2;
                    jumped[index] |= now.y - before.y > 0.3;
                }
                if moved.iter().chain(&jumped).all(|done| *done) {
                    break;
                }
            }
            assert!(
                moved.iter().chain(&jumped).all(|done| *done),
                "{map:?}: movement {moved:?}, jump {jumped:?}"
            );
            human.close(None).await.unwrap();
            let mut left = false;
            for _ in 0..40 {
                if let ServerMessage::Snapshot(snapshot) = receive(&mut spectator).await {
                    if !snapshot.players.iter().any(|p| p.id == ids[0]) {
                        assert_eq!(snapshot.players.len(), 1);
                        assert_eq!(snapshot.players[0].id, ids[1]);
                        left = true;
                        break;
                    }
                }
            }
            assert!(
                left,
                "{map:?}: leaving must remove only the departing fighter"
            );
            let (mut rejoined, rejoined_id) = join(&url, Role::Human, "Meat Proxy").await;
            assert_ne!(rejoined_id, human_id, "rejoin creates a fresh fighter");
            for socket in [&mut agent, &mut spectator, &mut rejoined] {
                socket.close(None).await.unwrap();
            }
        };
        let result = tokio::time::timeout(Duration::from_secs(5), exercise).await;
        stop_tx.send(()).unwrap();
        server.await.unwrap().unwrap();
        result.expect("bounded mixed-session exercise");
    }
}

#[test]
fn joining_sixteen_fighters_does_not_reuse_occupied_spawn_slots() {
    for map in MapKind::ALL {
        let mut state = GameState::with_map(map, false);
        for index in 0..16 {
            state.add_player(Uuid::new_v4(), format!("Fighter {index}"), Role::Agent);
        }
        for (index, player) in state.players.iter().enumerate() {
            for other in &state.players[index + 1..] {
                assert!(
                    (player.x - other.x).hypot(player.z - other.z) >= 1.0,
                    "{map:?}: {} and {} overlap on join",
                    player.name,
                    other.name
                );
            }
        }
    }
}

#[test]
fn every_existing_bot_behavior_moves_and_fights_across_the_roster() {
    for map in MapKind::ALL {
        let mut session = GameSession::with_map(map, false);
        session.state.seed(67);
        session.spawn_bots(8);
        session.state.config.frag_limit = None;
        session.state.config.time_limit_ticks = None;
        session.state.config.compliance_ping_ticks = None;
        session.state.config.boss_spawn_ticks = Some(20);
        session.state.start_round();
        let mut behavior_by_id = HashMap::new();
        let mut previous = HashMap::new();
        let mut evidence: BTreeMap<String, (f32, u32, u32)> = BTreeMap::new();
        for _ in 0..2400 {
            for message in session.tick_messages(0.05) {
                if let ServerMessage::Snapshot(snapshot) = message {
                    for player in &snapshot.players {
                        let behavior = player.behavior.as_deref().expect("rule bot behavior");
                        behavior_by_id.insert(player.id, behavior.to_string());
                        let row = evidence.entry(behavior.to_string()).or_default();
                        if let Some((x, z)) = previous.insert(player.id, (player.x, player.z)) {
                            let distance = (player.x - x).hypot(player.z - z);
                            // A respawn is not traversed ground.
                            if distance < 1.0 {
                                row.0 += distance;
                            }
                        }
                    }
                    for shot in snapshot.shot_results {
                        let behavior = behavior_by_id.get(&shot.shooter_id).expect("known fighter");
                        let row = evidence.get_mut(behavior).unwrap();
                        row.1 += 1;
                        row.2 += u32::from(shot.hit);
                    }
                }
            }
        }
        for behavior in [
            "Aggressive",
            "Defensive",
            "Flanker",
            "Balanced",
            "Compliance",
        ] {
            let &(distance, shots, hits) =
                evidence.get(behavior).expect("roster contains behavior");
            assert!(
                distance > 3.0 && shots > 0 && hits > 0,
                "{map:?}/{behavior}: moved {distance:.1} m, {shots} shots, {hits} hits"
            );
        }
        println!("roster: {map:?}: {evidence:?}");
    }
}
