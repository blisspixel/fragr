use fragr_server::protocol::{CampaignActor, ClientMessage, EnemyKind, Role, ServerMessage};
use fragr_server::run::{run_server, ServerOptions};
use futures_util::{SinkExt, StreamExt};
use serde_json::json;
use std::path::PathBuf;
use std::time::Duration;
use tokio_tungstenite::{connect_async, tungstenite::Message, MaybeTlsStream, WebSocketStream};

type Socket = WebSocketStream<MaybeTlsStream<tokio::net::TcpStream>>;

struct MapFile(PathBuf);
impl Drop for MapFile {
    fn drop(&mut self) {
        std::fs::remove_file(&self.0).expect("remove temporary authored map");
    }
}

async fn message(socket: &mut Socket) -> ServerMessage {
    tokio::time::timeout(Duration::from_secs(3), async {
        loop {
            if let Message::Text(text) = socket.next().await.unwrap().unwrap() {
                return serde_json::from_str(&text).unwrap();
            }
        }
    })
    .await
    .expect("server message deadline")
}

#[tokio::test]
async fn encounter_capability_and_identity_reach_every_role_over_the_wire() {
    let path = std::env::temp_dir().join(format!("fragr-encounter-{}.json", uuid::Uuid::new_v4()));
    let file = MapFile(path);
    std::fs::write(
        &file.0,
        serde_json::to_vec(&json!({
            "version":1,"map_id":1002,"name":"Wire encounter","half_extent":12,
            "ground":"concrete","equipment":"discovery","solids":[],
            "spawns":[{"id":"entry","feet":[0,0,-4],"yaw":1.5707964}],
            "landmarks":[{"id":"exit","feet":[0,0,8]}],
            "encounters":[{"id":"intake","regions":[{"min":[-2,0,-5],"max":[2,2,-3]}],
                "enemies":[{"id":"clerk","kind":"clerk","feet":[0,0,4],"yaw":4.712389}]}]
        }))
        .unwrap(),
    )
    .unwrap();
    let (ready_tx, ready_rx) = tokio::sync::oneshot::channel();
    let (stop_tx, stop_rx) = tokio::sync::oneshot::channel();
    let host = tokio::spawn(run_server(
        ServerOptions {
            bind: "127.0.0.1:0".into(),
            bots: 0,
            authored: Some(fragr_server::maps::AuthoredSource::File(file.0.clone())),
            ..Default::default()
        },
        async {
            let _ = stop_rx.await;
        },
        Some(ready_tx),
    ));
    let url = format!("ws://{}", ready_rx.await.unwrap());
    for role in [Role::Human, Role::Agent, Role::Spectator] {
        let (mut old, _) = connect_async(&url).await.unwrap();
        old.send(Message::Text(
            serde_json::to_string(&ClientMessage::Hello {
                role,
                name: "Old client".into(),
                geometry_version: 2,
                // Encounter capability without the ammunition contract.
                gameplay_version: fragr_server::protocol::CAMPAIGN_GAMEPLAY_VERSION,

                ticket: None,
                resume: None,
            })
            .unwrap(),
        ))
        .await
        .unwrap();
        assert!(
            matches!(message(&mut old).await, ServerMessage::Error { code, .. } if code == "unsupported_gameplay")
        );
    }
    let mut sockets = Vec::new();
    for role in [Role::Human, Role::Agent, Role::Spectator] {
        let (mut socket, _) = connect_async(&url).await.unwrap();
        socket
            .send(Message::Text(
                serde_json::to_string(&ClientMessage::Hello {
                    role,
                    name: format!("{role:?}"),
                    geometry_version: 2,
                    gameplay_version: fragr_server::protocol::AMMO_GAMEPLAY_VERSION,

                    ticket: None,
                    resume: None,
                })
                .unwrap(),
            ))
            .await
            .unwrap();
        let id = match message(&mut socket).await {
            ServerMessage::Welcome { player_id, .. } => player_id,
            other => panic!("expected admission, got {other:?}"),
        };
        let mut seen = false;
        let mut seen_map = false;
        for _ in 0..40 {
            match message(&mut socket).await {
                ServerMessage::MapInfo {
                    map_id,
                    m02_objectives,
                    ..
                } => {
                    assert_eq!(map_id, 1002);
                    assert_eq!(m02_objectives, None);
                    seen_map = true;
                }
                ServerMessage::Snapshot(snapshot) => {
                    if let Some(me) = id.and_then(|id| snapshot.players.iter().find(|p| p.id == id))
                    {
                        assert_eq!(me.campaign, Some(CampaignActor::Participant {}));
                    }
                    if snapshot.players.iter().any(|p| {
                        matches!(
                            p.campaign,
                            Some(CampaignActor::Union {
                                kind: EnemyKind::Clerk,
                                ..
                            })
                        )
                    }) {
                        seen = true;
                        break;
                    }
                }
                ServerMessage::Loadout(_) => assert_ne!(role, Role::Spectator),
                _ => {}
            }
        }
        assert!(seen, "{role:?} must receive the authored actor");
        assert!(seen_map, "{role:?} must receive the legacy map");
        sockets.push(socket);
    }
    for socket in &mut sockets {
        socket.close(None).await.unwrap();
    }
    stop_tx.send(()).unwrap();
    host.await.unwrap().unwrap();
}
