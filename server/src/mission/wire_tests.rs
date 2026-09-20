use super::MissionClient;
use crate::protocol::{Action, ClientMessage, MissionPhase, Role, ServerMessage};
use futures_util::{SinkExt, StreamExt};
use std::time::Duration;
use tokio_tungstenite::{connect_async, tungstenite::Message};

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

async fn drive(url: String, role: Role, reached: tokio::sync::mpsc::UnboundedSender<()>) -> usize {
    let mut socket = connect(&url, role).await;
    let mut observer = MissionClient::default();
    let mut navigator = crate::navigation::Navigator::default();
    let mut world = None;
    let mut id = None;
    let mut changes = 0;
    while let Some(Ok(Message::Text(text))) = socket.next().await {
        match serde_json::from_str::<ServerMessage>(&text).unwrap() {
            ServerMessage::Welcome { player_id, .. } => id = player_id,
            ServerMessage::MapInfo {
                mission,
                half_extent,
                solids,
                presentation,
                ..
            } => {
                changes += 1;
                observer
                    .replace_map(
                        mission.as_ref(),
                        half_extent,
                        &solids,
                        presentation.as_ref(),
                    )
                    .unwrap();
                world = Some(
                    crate::navigation::Navigation::shared(crate::movement::Arena {
                        half: half_extent,
                        solids,
                    })
                    .unwrap(),
                );
                navigator.clear();
            }
            ServerMessage::Mission { tick, state } => {
                let phase = state.phase;
                observer.observe(tick, state).unwrap();
                if phase == MissionPhase::ReachLift {
                    let _ = reached.send(());
                }
                if phase == MissionPhase::Departed {
                    break;
                }
            }
            ServerMessage::Snapshot(snapshot) => {
                if let (Some(id), Some(world)) = (id, world.as_ref()) {
                    let action =
                        observer.steer(&mut navigator, world, id, &snapshot, Action::default());
                    socket
                        .send(Message::Text(
                            serde_json::to_string(&ClientMessage::Action(action)).unwrap(),
                        ))
                        .await
                        .unwrap();
                }
            }
            ServerMessage::Error { code, message } => panic!("{code}: {message}"),
            _ => {}
        }
    }
    socket.close(None).await.unwrap();
    assert_eq!(observer.state.unwrap().phase, MissionPhase::Departed);
    changes
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
            map_file: Some(fixture.0.clone()),
            ..Default::default()
        },
        async {
            let _ = stop_rx.await;
        },
        Some(ready_tx),
    ));
    let url = format!("ws://{}", ready_rx.await.unwrap());
    let (reached_tx, mut reached_rx) = tokio::sync::mpsc::unbounded_channel();
    let human = tokio::spawn(drive(url.clone(), Role::Human, reached_tx.clone()));
    let agent = tokio::spawn(drive(url.clone(), Role::Agent, reached_tx));
    tokio::time::timeout(Duration::from_secs(20), reached_rx.recv())
        .await
        .expect("party reaches record")
        .unwrap();
    let mut spectator = connect(&url, Role::Spectator).await;
    let mut has_open_map = false;
    let mut saw_progress = false;
    let mut saw_departure = false;
    tokio::time::timeout(Duration::from_secs(20), async {
        while let Some(Ok(Message::Text(text))) = spectator.next().await {
            match serde_json::from_str::<ServerMessage>(&text).unwrap() {
                ServerMessage::MapInfo { solids, .. } => has_open_map = solids[3].bottom == 3.,
                ServerMessage::Mission { state, tick } => {
                    state.validate(tick).unwrap();
                    assert!(has_open_map, "shared progress arrived before its geometry");
                    assert_eq!(state.attempt, 1);
                    assert_eq!(
                        state.party.len(),
                        2,
                        "spectator took a participant identity"
                    );
                    if state.phase == MissionPhase::ReachLift {
                        saw_progress = true;
                    }
                    if state.phase == MissionPhase::Departed {
                        assert!(state.party.iter().all(|p| p.aboard));
                        saw_departure = true;
                        break;
                    }
                }
                _ => {}
            }
        }
    })
    .await
    .expect("mixed party departs");
    assert!(saw_progress);
    assert!(saw_departure, "spectator never received the party result");
    assert_eq!(human.await.unwrap(), 2);
    assert_eq!(agent.await.unwrap(), 2);
    spectator.close(None).await.unwrap();
    stop_tx.send(()).unwrap();
    server.await.unwrap().unwrap();
    eprintln!("Mission wire: human + agent walked, read, boarded and departed; late spectator saw open geometry before shared progress");
}
