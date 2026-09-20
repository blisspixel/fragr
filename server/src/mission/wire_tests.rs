use super::MissionClient;
use crate::protocol::{Action, ClientMessage, MissionPhase, Role, ServerMessage};
use futures_util::{SinkExt, StreamExt};
use std::time::Duration;
use tokio_tungstenite::{connect_async, tungstenite::Message};

/// Verify world revisions, including repeated delivery at the first tick.
struct MissionProbe {
    observer: MissionClient,
    maps: [serde_json::Value; 2],
    revisions: Vec<usize>,
}

impl MissionProbe {
    fn new() -> Self {
        let map = crate::maps::AuthoredMap::read(
            serde_json::to_vec(&super::tests::definition())
                .unwrap()
                .as_slice(),
        )
        .unwrap();
        let state = crate::sim::GameState::with_authored_map(map);
        let closed = serde_json::to_value(state.map_info()).unwrap();
        let mut opened = state;
        opened.map = opened.map.opened_route().unwrap();
        Self {
            observer: MissionClient::default(),
            maps: [closed, serde_json::to_value(opened.map_info()).unwrap()],
            revisions: Vec::new(),
        }
    }

    fn ingest(&mut self, message: &ServerMessage) {
        match message {
            ServerMessage::MapInfo {
                mission,
                half_extent,
                solids,
                presentation,
                ..
            } => {
                let map = serde_json::to_value(message).unwrap();
                let revision = self
                    .maps
                    .iter()
                    .position(|expected| expected == &map)
                    .expect("unexpected geometry, presentation or mission contract");
                assert!(
                    self.revisions.last().is_none_or(|last| *last <= revision),
                    "geometry reverted after opening"
                );
                if self.revisions.last() != Some(&revision) {
                    self.revisions.push(revision);
                }
                self.observer
                    .replace_map(
                        mission.as_ref(),
                        *half_extent,
                        solids,
                        presentation.as_ref(),
                    )
                    .unwrap();
            }
            ServerMessage::Mission { tick, state } => {
                assert_eq!(state.attempt, 1, "unexpected party reset");
                let expected = usize::from(state.phase != MissionPhase::FindTransfer);
                assert_eq!(
                    self.revisions.last(),
                    Some(&expected),
                    "mission progress arrived before matching geometry"
                );
                self.observer.observe(*tick, state.clone()).unwrap();
            }
            ServerMessage::Error { code, message } => panic!("{code}: {message}"),
            _ => {}
        }
    }
}

#[test]
fn joining_on_either_side_of_first_tick_preserves_mission_geometry_order() {
    for join_before_tick in [false, true] {
        let mut session = crate::session::GameSession::with_authored_map(
            crate::maps::AuthoredMap::read(
                serde_json::to_vec(&super::tests::definition())
                    .unwrap()
                    .as_slice(),
            )
            .unwrap(),
        );
        if !join_before_tick {
            session.tick_messages(0.05);
        }
        let mut probe = MissionProbe::new();
        let connection = uuid::Uuid::new_v4();
        session.apply_command(crate::net::GameCommand::Connected {
            id: connection,
            role: Role::Human,
            name: "First arrival".into(),
            player_id: Some(uuid::Uuid::new_v4()),
        });
        let mut messages: Vec<_> = session
            .take_unicasts()
            .into_iter()
            .map(|(recipient, message)| {
                assert_eq!(recipient, crate::session::Recipient::Client(connection));
                message
            })
            .collect();
        messages.extend(session.tick_messages(0.05));
        let maps = messages
            .iter()
            .filter(|message| matches!(message, ServerMessage::MapInfo { .. }))
            .count();
        assert_eq!(maps, if join_before_tick { 2 } else { 1 });
        for message in &messages {
            probe.ingest(message);
        }
        assert_eq!(probe.revisions, [0]);
        assert_eq!(
            probe.observer.state.unwrap().phase,
            MissionPhase::FindTransfer
        );
    }
}

struct Fixture(std::path::PathBuf);
impl Drop for Fixture {
    fn drop(&mut self) {
        std::fs::remove_file(&self.0).expect("remove mission fixture");
    }
}

async fn connect(
    url: &str,
    role: Role,
) -> tokio_tungstenite::WebSocketStream<tokio_tungstenite::MaybeTlsStream<tokio::net::TcpStream>> {
    let (mut socket, _) = connect_async(url).await.unwrap();
    socket
        .send(Message::Text(
            serde_json::to_string(&ClientMessage::Hello {
                role,
                name: format!("{role:?}"),
                geometry_version: 2,
                gameplay_version: 4,
            })
            .unwrap(),
        ))
        .await
        .unwrap();
    socket
}

#[tokio::test]
async fn broadcast_cannot_overtake_join_geometry_for_any_role() {
    let (commands_tx, mut commands_rx) = tokio::sync::mpsc::unbounded_channel();
    let net = crate::net::NetServer::bind_with_requirements("127.0.0.1:0", commands_tx, 2, 4)
        .await
        .unwrap();
    let url = format!("ws://{}", net.local_addr().unwrap());
    let clients = net.clients.clone();
    let accept = tokio::spawn(net.accept_loop());
    let map = crate::maps::AuthoredMap::read(
        serde_json::to_vec(&super::tests::definition())
            .unwrap()
            .as_slice(),
    )
    .unwrap();
    let mut session = crate::session::GameSession::with_authored_map(map);
    let mut sockets = Vec::new();
    for role in [Role::Human, Role::Agent, Role::Spectator] {
        let mut socket = connect(&url, role).await;
        let welcome = tokio::time::timeout(Duration::from_secs(2), socket.next())
            .await
            .unwrap()
            .unwrap()
            .unwrap();
        assert!(matches!(
            serde_json::from_str::<ServerMessage>(welcome.to_text().unwrap()).unwrap(),
            ServerMessage::Welcome { .. }
        ));
        let connected = tokio::time::timeout(Duration::from_secs(2), commands_rx.recv())
            .await
            .unwrap()
            .unwrap();
        assert!(matches!(
            connected,
            crate::net::GameCommand::Connected { .. }
        ));
        // Reproduce a tick winning the select before the new connection's command.
        // Initial broadcasts need not contain a map, especially for late joins.
        let messages = [
            session.state.mission_message().unwrap(),
            ServerMessage::Snapshot(session.state.snapshot()),
        ];
        crate::session::broadcast_to_clients(&clients, &messages).await;
        session.apply_command(connected);
        let unicasts = session.take_unicasts();
        crate::session::send_unicasts(&clients, &session.client_to_player, &unicasts).await;
        let messages = session.tick_messages(0.05);
        crate::session::broadcast_to_clients(&clients, &messages).await;
        tokio::time::timeout(Duration::from_secs(2), async {
            let first = socket.next().await.unwrap().unwrap();
            let first = serde_json::from_str::<ServerMessage>(first.to_text().unwrap()).unwrap();
            assert!(
                matches!(first, ServerMessage::MapInfo { .. }),
                "{role:?} received state before geometry: {first:?}"
            );
            let mut probe = MissionProbe::new();
            probe.ingest(&first);
            loop {
                let message = socket.next().await.unwrap().unwrap();
                let message =
                    serde_json::from_str::<ServerMessage>(message.to_text().unwrap()).unwrap();
                probe.ingest(&message);
                if matches!(message, ServerMessage::Snapshot(_)) {
                    assert!(probe.observer.state.is_some());
                    break;
                }
            }
        })
        .await
        .expect("initialized client receives mission and snapshots");
        sockets.push(socket);
    }
    for mut socket in sockets {
        socket.close(None).await.unwrap();
    }
    accept.abort();
}

async fn drive(
    url: String,
    role: Role,
    reached: tokio::sync::mpsc::UnboundedSender<()>,
    proceed: tokio::sync::watch::Receiver<bool>,
    finish: tokio::sync::oneshot::Receiver<()>,
) -> Vec<usize> {
    let mut socket = connect(&url, role).await;
    let mut probe = MissionProbe::new();
    let mut navigator = crate::navigation::Navigator::default();
    let mut world = None;
    let mut id = None;
    let mut reported_record = false;
    while let Some(Ok(Message::Text(text))) = socket.next().await {
        let message = serde_json::from_str::<ServerMessage>(&text).unwrap();
        probe.ingest(&message);
        match message {
            ServerMessage::Welcome { player_id, .. } => id = player_id,
            ServerMessage::MapInfo {
                half_extent,
                solids,
                ..
            } => {
                world = Some(
                    crate::navigation::Navigation::shared(crate::movement::Arena {
                        half: half_extent,
                        solids,
                    })
                    .unwrap(),
                );
                navigator.clear();
            }
            ServerMessage::Mission { state, .. } => {
                let phase = state.phase;
                if phase == MissionPhase::ReachLift && !reported_record {
                    reached.send(()).unwrap();
                    reported_record = true;
                }
                if phase == MissionPhase::Departed {
                    break;
                }
            }
            ServerMessage::Snapshot(snapshot) => {
                if let (Some(id), Some(world)) = (id, world.as_ref()) {
                    let can_advance = probe.observer.state.as_ref().is_some_and(|state| {
                        state.party.len() == 2
                            && (state.phase == MissionPhase::FindTransfer || *proceed.borrow())
                    });
                    let action = if can_advance {
                        probe.observer.steer(
                            &mut navigator,
                            world,
                            id,
                            &snapshot,
                            Action::default(),
                        )
                    } else {
                        Action::default()
                    };
                    socket
                        .send(Message::Text(
                            serde_json::to_string(&ClientMessage::Action(action)).unwrap(),
                        ))
                        .await
                        .unwrap();
                }
            }
            _ => {}
        }
    }
    assert_eq!(probe.observer.state.unwrap().phase, MissionPhase::Departed);
    finish
        .await
        .expect("spectator must see the shared result before fighters leave");
    socket.close(None).await.unwrap();
    probe.revisions
}

#[tokio::test]
async fn live_mixed_party_and_late_spectator_observe_the_same_gate_and_departure() {
    let fixture =
        Fixture(std::env::temp_dir().join(format!("fragr-mission-{}.json", uuid::Uuid::new_v4())));
    std::fs::write(
        &fixture.0,
        serde_json::to_vec(&super::tests::definition()).unwrap(),
    )
    .unwrap();
    let (ready_tx, ready_rx) = tokio::sync::oneshot::channel();
    let (stop_tx, stop_rx) = tokio::sync::oneshot::channel();
    let server = tokio::spawn(crate::run::run_server(
        crate::run::ServerOptions {
            bind: "127.0.0.1:0".into(),
            bots: 0,
            authored: Some(crate::maps::AuthoredSource::File(fixture.0.clone())),
            ..Default::default()
        },
        async {
            let _ = stop_rx.await;
        },
        Some(ready_tx),
    ));
    let url = format!("ws://{}", ready_rx.await.unwrap());
    let (reached_tx, mut reached_rx) = tokio::sync::mpsc::unbounded_channel();
    let (proceed_tx, proceed_rx) = tokio::sync::watch::channel(false);
    let (human_finish_tx, human_finish_rx) = tokio::sync::oneshot::channel();
    let (agent_finish_tx, agent_finish_rx) = tokio::sync::oneshot::channel();
    let human = tokio::spawn(drive(
        url.clone(),
        Role::Human,
        reached_tx.clone(),
        proceed_rx.clone(),
        human_finish_rx,
    ));
    let agent = tokio::spawn(drive(
        url.clone(),
        Role::Agent,
        reached_tx,
        proceed_rx,
        agent_finish_rx,
    ));
    tokio::time::timeout(Duration::from_secs(20), reached_rx.recv())
        .await
        .expect("party reaches record")
        .unwrap();
    let mut spectator = connect(&url, Role::Spectator).await;
    let mut probe = MissionProbe::new();
    let mut saw_progress = false;
    let mut saw_departure = false;
    tokio::time::timeout(Duration::from_secs(20), async {
        while let Some(Ok(Message::Text(text))) = spectator.next().await {
            let message = serde_json::from_str::<ServerMessage>(&text).unwrap();
            probe.ingest(&message);
            if let ServerMessage::Mission { state, .. } = message {
                assert_eq!(
                    state.party.len(),
                    2,
                    "spectator took a participant identity"
                );
                if state.phase == MissionPhase::ReachLift {
                    saw_progress = true;
                    proceed_tx.send(true).unwrap();
                }
                if state.phase == MissionPhase::Departed {
                    assert!(state.party.iter().all(|p| p.aboard));
                    saw_departure = true;
                    break;
                }
            }
        }
    })
    .await
    .expect("mixed party departs");
    assert!(saw_progress);
    assert!(saw_departure, "spectator never received the party result");
    assert_eq!(probe.revisions, [1]);
    human_finish_tx.send(()).unwrap();
    agent_finish_tx.send(()).unwrap();
    tokio::time::timeout(Duration::from_secs(5), async {
        assert_eq!(human.await.unwrap(), [0, 1]);
        assert_eq!(agent.await.unwrap(), [0, 1]);
    })
    .await
    .expect("both fighters observe departure");
    spectator.close(None).await.unwrap();
    stop_tx.send(()).unwrap();
    server.await.unwrap().unwrap();
    eprintln!("Mission wire: human + agent walked, read, boarded and departed; late spectator saw open geometry before shared progress");
}
