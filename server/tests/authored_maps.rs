use fragr_server::protocol::{ClientMessage, Role, ServerMessage, GEOMETRY_VERSION};
use fragr_server::run::{run_server, ServerOptions};
use futures_util::{SinkExt, StreamExt};
use std::path::PathBuf;
use std::time::Duration;
use tokio_tungstenite::{connect_async, tungstenite::Message, MaybeTlsStream, WebSocketStream};

type Socket = WebSocketStream<MaybeTlsStream<tokio::net::TcpStream>>;

fn map_path() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("maps/m01-recall-notice.json")
}

async fn receive(socket: &mut Socket) -> ServerMessage {
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
async fn invalid_authoring_configuration_fails_before_readiness() {
    let base = ServerOptions {
        bind: "127.0.0.1:0".into(),
        bots: 0,
        authored: Some(fragr_server::maps::AuthoredSource::File(map_path())),
        ..Default::default()
    };
    let mut cases = vec![
        ServerOptions {
            authored: None,
            difficulty: Some(fragr_server::protocol::CampaignDifficulty::Severe),
            ..base.clone()
        },
        ServerOptions {
            bots: 1,
            ..base.clone()
        },
        ServerOptions {
            map_rotate: true,
            ..base.clone()
        },
        ServerOptions {
            solo_broadcast: true,
            ..base.clone()
        },
        ServerOptions {
            match_config: Some(Default::default()),
            ..base.clone()
        },
        ServerOptions {
            map: fragr_server::sim::MapKind::ComplianceYard,
            ..base.clone()
        },
    ];
    cases.push(ServerOptions {
        authored: Some(fragr_server::maps::AuthoredSource::File(
            map_path().with_extension("missing"),
        )),
        ..base
    });
    for options in cases {
        let (ready, observed) = tokio::sync::oneshot::channel();
        assert!(
            run_server(options, std::future::pending::<()>(), Some(ready))
                .await
                .is_err()
        );
        assert!(observed.await.is_err());
    }
}

#[tokio::test]
async fn authored_map_is_shared_by_humans_agents_and_spectators() {
    let (ready_tx, ready_rx) = tokio::sync::oneshot::channel();
    let (stop_tx, stop_rx) = tokio::sync::oneshot::channel();
    let server = tokio::spawn(run_server(
        ServerOptions {
            bind: "127.0.0.1:0".into(),
            bots: 0,
            authored: Some(fragr_server::maps::AuthoredSource::File(map_path())),
            difficulty: Some(fragr_server::protocol::CampaignDifficulty::Severe),
            ..Default::default()
        },
        async {
            let _ = stop_rx.await;
        },
        Some(ready_tx),
    ));
    let url = format!("ws://{}", ready_rx.await.unwrap());
    let (mut legacy, _) = connect_async(&url).await.unwrap();
    legacy
        .send(Message::Text(
            serde_json::json!({"type":"hello", "role":"human", "name":"Legacy geometry",
                "gameplay_version":fragr_server::protocol::GAMEPLAY_VERSION})
            .to_string(),
        ))
        .await
        .unwrap();
    assert!(
        matches!(receive(&mut legacy).await, ServerMessage::Error { code,.. } if code == "unsupported_geometry")
    );
    for role in ["human", "agent", "spectator"] {
        let (mut old_rules, _) = connect_async(&url).await.unwrap();
        old_rules
            .send(Message::Text(
                serde_json::json!({
                    "type":"hello", "role":role, "name":"Old equipment", "geometry_version":2, "gameplay_version":5,
                })
                .to_string(),
            ))
            .await
            .unwrap();
        assert!(
            matches!(receive(&mut old_rules).await, ServerMessage::Error { code, .. } if code == "unsupported_gameplay")
        );
    }
    let mut sockets = Vec::new();
    for role in [Role::Human, Role::Agent, Role::Spectator] {
        let (mut socket, _) = connect_async(&url).await.unwrap();
        socket
            .send(Message::Text(
                serde_json::to_string(&ClientMessage::Hello {
                    gameplay_version: fragr_server::protocol::GAMEPLAY_VERSION,
                    geometry_version: GEOMETRY_VERSION,
                    role,
                    name: format!("{role:?} walker"),
                })
                .unwrap(),
            ))
            .await
            .unwrap();
        let id = match receive(&mut socket).await {
            ServerMessage::Welcome { player_id, .. } => player_id,
            message => panic!("unexpected {message:?}"),
        };
        assert_eq!(id.is_some(), role != Role::Spectator);
        loop {
            if let ServerMessage::MapInfo {
                map_id,
                geometry_version,
                solids,
                presentation,
                ..
            } = receive(&mut socket).await
            {
                assert_eq!(map_id, 1001);
                assert_eq!(geometry_version, 2);
                assert!(solids.iter().any(|s| s.bottom == 2.4 && s.top == 3.0));
                assert_eq!(presentation.unwrap().solids.len(), solids.len());
                break;
            }
        }
        if id.is_none() {
            loop {
                if let ServerMessage::Mission { state, .. } = receive(&mut socket).await {
                    assert_eq!(
                        state.rules,
                        fragr_server::protocol::CampaignRules::new(
                            fragr_server::protocol::CampaignDifficulty::Severe
                        )
                    );
                    break;
                }
            }
        }
        if id.is_some() {
            let state = tokio::time::timeout(Duration::from_secs(3), async {
                let mut mission = None;
                let mut has_loadout = false;
                loop {
                    match receive(&mut socket).await {
                        ServerMessage::Loadout(loadout) => {
                            loadout.validate_for(id, None).unwrap();
                            assert_eq!(loadout.selected, fragr_server::protocol::WeaponType::Fists);
                            assert_eq!(loadout.weapons.len(), 1);
                            has_loadout = true;
                        }
                        ServerMessage::Mission { state, .. } => {
                            assert_eq!(
                                state.rules,
                                fragr_server::protocol::CampaignRules::new(
                                    fragr_server::protocol::CampaignDifficulty::Severe
                                )
                            );
                            mission = Some(state);
                        }
                        _ => {}
                    }
                    if has_loadout {
                        if let Some(state) = mission {
                            break state;
                        }
                    }
                }
            })
            .await
            .expect("initial equipment and mission deadline");
            socket
                .send(Message::Text(
                    serde_json::to_string(&ClientMessage::MissionReady(
                        fragr_server::protocol::MissionReady {
                            id: state.id,
                            attempt: state.attempt,
                        },
                    ))
                    .unwrap(),
                ))
                .await
                .unwrap();
            socket
                .send(Message::Text(
                    serde_json::to_string(&ClientMessage::Action(fragr_server::protocol::Action {
                        forward: true,
                        yaw: Some(std::f32::consts::FRAC_PI_2),
                        ..Default::default()
                    }))
                    .unwrap(),
                ))
                .await
                .unwrap();
        }
        sockets.push(socket);
    }
    let observer = sockets.last_mut().unwrap();
    let mut moved = false;
    for _ in 0..45 {
        let message = receive(observer).await;
        assert!(
            !matches!(message, ServerMessage::Loadout(_)),
            "private ammunition leaked to a spectator"
        );
        if let ServerMessage::Snapshot(snapshot) = message {
            assert_eq!(snapshot.map_id, 1001);
            assert_eq!(snapshot.mode_name, "Campaign development");
            let participants: Vec<_> = snapshot
                .players
                .iter()
                .filter(|p| p.is_participant())
                .collect();
            assert!(participants.iter().all(|p| (p.y - 1.5).abs() < 0.01));
            if participants.len() == 2 && participants.iter().all(|p| p.z > -30.5) {
                let guards: Vec<_> = snapshot
                    .players
                    .iter()
                    .filter(|p| !p.is_participant())
                    .collect();
                assert_eq!(
                    guards.len(),
                    20,
                    "spectator receives the prepared M01 roster"
                );
                assert!(guards.iter().all(|p| matches!(
                    p.campaign,
                    Some(fragr_server::protocol::CampaignActor::Union {
                        phase: fragr_server::protocol::EnemyPhase::Idle,
                        ..
                    })
                )));
                moved = true;
                break;
            }
        }
    }
    assert!(
        moved,
        "both roles must move through live input below the roof"
    );
    use fragr_server::protocol::{Action, LookAt, WeaponType};
    let human = &mut sockets[0];
    let mut discovered = None;
    send_action(
        human,
        Action {
            forward: true,
            look_at: Some(LookAt {
                x: Some(0.0),
                z: Some(-26.0),
                ..Default::default()
            }),
            ..Default::default()
        },
    )
    .await;
    for _ in 0..120 {
        if let ServerMessage::Loadout(loadout) = receive(human).await {
            if loadout.selected == WeaponType::Tack {
                loadout.validate().unwrap();
                assert!(loadout.personal_claims.contains(&"bay_tack".into()));
                discovered = Some(loadout);
                break;
            }
        }
    }
    let loadout = discovered.expect("human discovers a personal Tack through the actual socket");
    send_action(
        human,
        Action {
            fire: true,
            yaw: Some(0.0),
            ..Default::default()
        },
    )
    .await;
    loop {
        if let ServerMessage::Loadout(fired) = receive(human).await {
            fired
                .validate_for(Some(loadout.player_id), Some(&loadout))
                .unwrap();
            if fired.weapon(WeaponType::Tack).unwrap().magazine == Some(11) {
                break;
            }
        }
    }
    send_action(
        human,
        Action {
            reload: true,
            ..Default::default()
        },
    )
    .await;
    send_action(human, Action::default()).await;
    let mut completion = None;
    let mut completed = false;
    for _ in 0..80 {
        if let ServerMessage::Loadout(update) = receive(human).await {
            update
                .validate_for(Some(loadout.player_id), Some(&loadout))
                .unwrap();
            if let Some(reload) = update.reload {
                completion = Some(reload.complete_at);
            } else if completion.is_some() {
                assert_eq!(Some(update.tick), completion);
                assert_eq!(update.weapon(WeaponType::Tack).unwrap().magazine, Some(12));
                assert_eq!(update.reserve(fragr_server::protocol::AmmoPool::Tacks), 35);
                completed = true;
                break;
            }
        }
    }
    assert!(
        completion.is_some(),
        "short reload request survives another input frame"
    );
    assert!(completed, "reload completion must reach the owning socket");
    for socket in &mut sockets {
        socket.close(None).await.unwrap();
    }
    stop_tx.send(()).unwrap();
    server.await.unwrap().unwrap();
}

async fn send_action(socket: &mut Socket, action: fragr_server::protocol::Action) {
    socket
        .send(Message::Text(
            serde_json::to_string(&ClientMessage::Action(action)).unwrap(),
        ))
        .await
        .unwrap();
}
