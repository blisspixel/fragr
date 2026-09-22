use super::*;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::time::{timeout, Duration};
use tokio_tungstenite::connect_async;

#[tokio::test]
async fn raised_geometry_rejects_legacy_roles_before_welcome_or_join() {
    let (tx, mut commands) = mpsc::unbounded_channel();
    let server = NetServer::bind_with_geometry("127.0.0.1:0", tx, 2)
        .await
        .unwrap();
    let address = server.local_addr().unwrap();
    let clients = server.clients.clone();
    let accept = tokio::spawn(server.accept_loop());
    for role in ["human", "agent", "spectator"] {
        for version in [None, Some(0), Some(1)] {
            let (mut socket, _) = connect_async(format!("ws://{address}")).await.unwrap();
            let mut hello = serde_json::json!({"type":"hello", "role":role, "name":"Legacy"});
            if let Some(version) = version {
                hello["geometry_version"] = version.into();
            }
            socket.send(Message::Text(hello.to_string())).await.unwrap();
            let reply = timeout(Duration::from_secs(2), socket.next())
                .await
                .unwrap()
                .unwrap()
                .unwrap();
            let rejection: ServerMessage = serde_json::from_str(reply.to_text().unwrap()).unwrap();
            assert!(
                matches!(rejection, ServerMessage::Error { code, .. } if code == "unsupported_geometry")
            );
            assert!(matches!(
                timeout(Duration::from_secs(2), socket.next())
                    .await
                    .unwrap(),
                Some(Ok(Message::Close(_)))
            ));
            assert!(
                commands.try_recv().is_err(),
                "rejected client reached the game session"
            );
            assert!(clients.lock().await.is_empty());
        }
    }
    // A future client declaring support for all earlier formats can still join.
    for version in [2, 3] {
        let (mut socket, _) = connect_async(format!("ws://{address}")).await.unwrap();
        socket
            .send(Message::Text(
                serde_json::json!({
                    "type":"hello", "role":"human", "name":"Current", "geometry_version":version,
                })
                .to_string(),
            ))
            .await
            .unwrap();
        let reply = timeout(Duration::from_secs(2), socket.next())
            .await
            .unwrap()
            .unwrap()
            .unwrap();
        assert!(matches!(
            serde_json::from_str::<ServerMessage>(reply.to_text().unwrap()).unwrap(),
            ServerMessage::Welcome {
                player_id: Some(_),
                ..
            }
        ));
        assert!(matches!(
            timeout(Duration::from_secs(2), commands.recv())
                .await
                .unwrap(),
            Some(GameCommand::Connected { .. })
        ));
        socket.close(None).await.unwrap();
        assert!(matches!(
            timeout(Duration::from_secs(2), commands.recv())
                .await
                .unwrap(),
            Some(GameCommand::Disconnected { .. })
        ));
    }
    accept.abort();
}

async fn welcome_spectator(
    address: std::net::SocketAddr,
) -> tokio_tungstenite::WebSocketStream<tokio_tungstenite::MaybeTlsStream<tokio::net::TcpStream>> {
    let (mut socket, _) = connect_async(format!("ws://{address}")).await.unwrap();
    socket
        .send(Message::Text(
            r#"{"type":"hello","role":"spectator","name":"Cap"}"#.to_string(),
        ))
        .await
        .unwrap();
    let reply = timeout(Duration::from_secs(2), socket.next())
        .await
        .unwrap()
        .unwrap()
        .unwrap();
    assert!(matches!(
        serde_json::from_str::<ServerMessage>(reply.to_text().unwrap()).unwrap(),
        ServerMessage::Welcome {
            player_id: None,
            ..
        }
    ));
    socket
}

fn admission_code(message: Message) -> String {
    let ServerMessage::Error { code, .. } =
        serde_json::from_str(message.to_text().unwrap()).unwrap()
    else {
        panic!("expected an admission error");
    };
    code
}

#[test]
fn status_request_requires_the_exact_path() {
    assert!(is_status_request(b"GET /status HTTP/1.1"));
    assert!(is_status_request(b"GET /status?watch=1"));
    assert!(!is_status_request(b"GET /status-evil HTTP/1.1"));
    assert!(!is_status_request(b"POST /status HTTP/1.1"));
    assert_eq!(classify_opening(b"GET"), None);
    assert_eq!(classify_opening(b"GET /foo bar"), Some(false));
}

#[tokio::test]
async fn status_get_reports_the_match_without_taking_a_slot() {
    let (tx, mut commands) = mpsc::unbounded_channel();
    let mut server = NetServer::bind("127.0.0.1:0", tx).await.unwrap();
    server.tighten_admission(1, 8, Duration::from_secs(2), Duration::from_secs(2));
    let status = std::sync::Arc::new(tokio::sync::RwLock::new(crate::protocol::LiveStatus {
        schema_version: 2,
        kind: "arena".into(),
        map: "Arena Duel".into(),
        round: 3,
        tick: 40,
        fighters: 4,
        humans: 1,
        agents: 1,
        bots: 2,
        connections: 2,
    }));
    server.share_status(std::sync::Arc::clone(&status));
    let address = server.local_addr().unwrap();
    let accept = tokio::spawn(server.accept_loop());

    let mut tcp = tokio::net::TcpStream::connect(address).await.unwrap();
    tcp.write_all(b"GET /status HTTP/1.1\r\nHost: localhost\r\n\r\n")
        .await
        .unwrap();
    let mut buf = vec![0u8; 2048];
    let n = timeout(Duration::from_secs(2), tcp.read(&mut buf))
        .await
        .unwrap()
        .unwrap();
    let text = String::from_utf8_lossy(&buf[..n]);
    assert!(text.starts_with("HTTP/1.1 200"), "{text}");
    assert!(!text.contains("Access-Control-Allow-Origin"));
    let body = text.split("\r\n\r\n").nth(1).unwrap();
    let live: crate::protocol::LiveStatus = serde_json::from_str(body).unwrap();
    assert_eq!(live.map, "Arena Duel");
    assert_eq!(live.round, 3);
    assert_eq!(live.fighters, 4);
    assert_eq!(live.bots, 2);
    assert!(commands.try_recv().is_err());

    let _held = welcome_spectator(address).await;
    accept.abort();
}

#[tokio::test]
async fn connection_caps_reject_without_admitting_the_game() {
    let (tx, mut commands) = mpsc::unbounded_channel();
    let mut server = NetServer::bind("127.0.0.1:0", tx).await.unwrap();
    server.tighten_admission(1, 8, Duration::from_secs(2), Duration::from_secs(2));
    let address = server.local_addr().unwrap();
    let accept = tokio::spawn(server.accept_loop());
    let held = welcome_spectator(address).await;
    assert!(matches!(
        timeout(Duration::from_secs(2), commands.recv())
            .await
            .unwrap(),
        Some(GameCommand::Connected { .. })
    ));

    let (mut extra, _) = connect_async(format!("ws://{address}")).await.unwrap();
    extra
        .send(Message::Text(
            r#"{"type":"hello","role":"spectator","name":"Extra"}"#.to_string(),
        ))
        .await
        .unwrap();
    let reply = timeout(Duration::from_secs(2), extra.next())
        .await
        .unwrap()
        .unwrap()
        .unwrap();
    assert_eq!(admission_code(reply), "connection_limit");
    assert!(commands.try_recv().is_err());

    drop(held);
    assert!(matches!(
        timeout(Duration::from_secs(2), commands.recv())
            .await
            .unwrap(),
        Some(GameCommand::Disconnected { .. })
    ));
    let _again = welcome_spectator(address).await;
    accept.abort();
}

#[tokio::test]
async fn loopback_roster_of_sixteen_agents_plus_an_observer_fits() {
    let (tx, mut commands) = mpsc::unbounded_channel();
    let mut server = NetServer::bind("127.0.0.1:0", tx).await.unwrap();
    server.tighten_admission(24, 17, Duration::from_secs(2), Duration::from_secs(2));
    let address = server.local_addr().unwrap();
    let accept = tokio::spawn(server.accept_loop());
    let mut held = Vec::new();
    for _ in 0..17 {
        held.push(welcome_spectator(address).await);
    }
    for _ in 0..17 {
        assert!(matches!(
            timeout(Duration::from_secs(2), commands.recv())
                .await
                .unwrap(),
            Some(GameCommand::Connected { .. })
        ));
    }
    let (mut extra, _) = connect_async(format!("ws://{address}")).await.unwrap();
    extra
        .send(Message::Text(
            r#"{"type":"hello","role":"spectator","name":"Extra"}"#.to_string(),
        ))
        .await
        .unwrap();
    let reply = timeout(Duration::from_secs(2), extra.next())
        .await
        .unwrap()
        .unwrap()
        .unwrap();
    assert_eq!(admission_code(reply), "address_limit");
    drop(held);
    accept.abort();
}

#[tokio::test]
async fn one_address_cannot_hold_every_connection_slot() {
    let (tx, mut commands) = mpsc::unbounded_channel();
    let mut server = NetServer::bind("127.0.0.1:0", tx).await.unwrap();
    server.tighten_admission(8, 2, Duration::from_secs(2), Duration::from_secs(2));
    let address = server.local_addr().unwrap();
    let accept = tokio::spawn(server.accept_loop());
    let first = welcome_spectator(address).await;
    let second = welcome_spectator(address).await;
    for _ in 0..2 {
        assert!(matches!(
            timeout(Duration::from_secs(2), commands.recv())
                .await
                .unwrap(),
            Some(GameCommand::Connected { .. })
        ));
    }
    let (mut extra, _) = connect_async(format!("ws://{address}")).await.unwrap();
    extra
        .send(Message::Text(
            r#"{"type":"hello","role":"spectator","name":"Extra"}"#.to_string(),
        ))
        .await
        .unwrap();
    let reply = timeout(Duration::from_secs(2), extra.next())
        .await
        .unwrap()
        .unwrap()
        .unwrap();
    assert_eq!(admission_code(reply), "address_limit");
    assert!(commands.try_recv().is_err());
    drop((first, second));
    accept.abort();
}

#[tokio::test]
async fn oversized_text_closes_without_blocking_the_next_client() {
    let (tx, mut commands) = mpsc::unbounded_channel();
    let server = NetServer::bind("127.0.0.1:0", tx).await.unwrap();
    let address = server.local_addr().unwrap();
    let accept = tokio::spawn(server.accept_loop());
    let (mut socket, _) = connect_async(format!("ws://{address}")).await.unwrap();
    let huge = format!(
        r#"{{"type":"hello","role":"spectator","name":"{}"}}"#,
        "n".repeat(70_000)
    );
    socket.send(Message::Text(huge)).await.unwrap();
    let reply = timeout(Duration::from_secs(2), socket.next())
        .await
        .unwrap();
    assert!(
        matches!(reply, Some(Err(_)) | Some(Ok(Message::Close(_))) | None),
        "an oversized frame must not become a session: {reply:?}"
    );
    assert!(commands.try_recv().is_err());
    let _next = welcome_spectator(address).await;
    accept.abort();
}

#[tokio::test]
async fn action_flood_is_dropped_before_the_tick_queue() {
    let (tx, mut commands) = mpsc::unbounded_channel();
    let server = NetServer::bind("127.0.0.1:0", tx).await.unwrap();
    let address = server.local_addr().unwrap();
    let accept = tokio::spawn(server.accept_loop());
    let (mut socket, _) = connect_async(format!("ws://{address}")).await.unwrap();
    socket
        .send(Message::Text(
            r#"{"type":"hello","role":"human","name":"Flood"}"#.to_string(),
        ))
        .await
        .unwrap();
    let reply = timeout(Duration::from_secs(2), socket.next())
        .await
        .unwrap()
        .unwrap()
        .unwrap();
    assert!(matches!(
        serde_json::from_str::<ServerMessage>(reply.to_text().unwrap()).unwrap(),
        ServerMessage::Welcome {
            player_id: Some(_),
            ..
        }
    ));
    assert!(matches!(
        timeout(Duration::from_secs(2), commands.recv())
            .await
            .unwrap(),
        Some(GameCommand::Connected { .. })
    ));
    for _ in 0..200 {
        socket
            .send(Message::Text(
                r#"{"type":"action","forward":true}"#.to_string(),
            ))
            .await
            .unwrap();
    }
    let mut actions = 0;
    while timeout(Duration::from_millis(50), commands.recv())
        .await
        .ok()
        .and_then(|message| message)
        .is_some_and(|command| {
            if matches!(command, GameCommand::Action { .. }) {
                actions += 1;
            }
            true
        })
    {}
    assert!(
        (1..80).contains(&actions),
        "flood reached the tick queue: {actions}"
    );
    accept.abort();
}

#[tokio::test]
async fn stalled_handshake_and_hello_release_their_slot() {
    let (tx, mut commands) = mpsc::unbounded_channel();
    let mut server = NetServer::bind("127.0.0.1:0", tx).await.unwrap();
    server.tighten_admission(1, 8, Duration::from_millis(200), Duration::from_millis(200));
    let address = server.local_addr().unwrap();
    let accept = tokio::spawn(server.accept_loop());

    let stalled = tokio::net::TcpStream::connect(address).await.unwrap();
    tokio::time::sleep(Duration::from_millis(400)).await;
    drop(stalled);
    let held = welcome_spectator(address).await;
    assert!(matches!(
        timeout(Duration::from_secs(2), commands.recv())
            .await
            .unwrap(),
        Some(GameCommand::Connected { .. })
    ));
    drop(held);
    let _ = timeout(Duration::from_secs(2), commands.recv()).await;

    let (socket, _) = connect_async(format!("ws://{address}")).await.unwrap();
    tokio::time::sleep(Duration::from_millis(400)).await;
    drop(socket);
    let _after = welcome_spectator(address).await;
    accept.abort();
}

#[tokio::test]
async fn server_rejects_unsupported_geometry_configuration() {
    for version in [0, crate::protocol::GEOMETRY_VERSION + 1] {
        let (tx, _) = mpsc::unbounded_channel();
        let result = NetServer::bind_with_geometry("127.0.0.1:0", tx, version).await;
        assert!(matches!(result, Err(error) if error.kind() == std::io::ErrorKind::InvalidInput));
    }
}

#[tokio::test]
async fn solo_run_admission_reserves_one_lifetime_seat_and_spectators_cannot_continue() {
    let (tx, mut commands) = mpsc::unbounded_channel();
    let mut server = NetServer::bind_with_requirements(
        "127.0.0.1:0",
        tx,
        2,
        crate::protocol::CONTINUES_GAMEPLAY_VERSION,
    )
    .await
    .unwrap();
    server.reserve_solo_run().unwrap();
    let address = server.local_addr().unwrap();
    let accept = tokio::spawn(server.accept_loop());
    for (role, version, expected) in [
        ("human", 6, "unsupported_gameplay"),
        ("agent", 7, "welcome"),
        ("human", 7, "run_seat_closed"),
        ("agent", 7, "run_seat_closed"),
        ("spectator", 7, "welcome"),
    ] {
        let (mut socket, _) = connect_async(format!("ws://{address}")).await.unwrap();
        socket.send(Message::Text(serde_json::json!({"type":"hello", "role":role, "name":"Run reader", "geometry_version":2, "gameplay_version":version}).to_string())).await.unwrap();
        let reply = timeout(Duration::from_secs(2), socket.next())
            .await
            .unwrap()
            .unwrap()
            .unwrap();
        let reply: ServerMessage = serde_json::from_str(reply.to_text().unwrap()).unwrap();
        if expected != "welcome" {
            assert!(matches!(reply, ServerMessage::Error { code, .. } if code == expected));
            let close = timeout(Duration::from_secs(2), socket.next())
                .await
                .unwrap()
                .unwrap()
                .unwrap();
            assert!(matches!(close, Message::Close(Some(frame)) if frame.reason == expected));
            let _ = socket.flush().await;
            assert!(commands.try_recv().is_err());
            continue;
        }
        let ServerMessage::Welcome { player_id, .. } = reply else {
            panic!("expected welcome")
        };
        assert!(matches!(
            timeout(Duration::from_secs(2), commands.recv())
                .await
                .unwrap(),
            Some(GameCommand::Connected { .. })
        ));
        let request = crate::protocol::MissionContinue {
            id: crate::protocol::MissionId::RecallNotice,
            run_id: Uuid::new_v4(),
            attempt: 1,
        };
        socket
            .send(Message::Text(
                serde_json::to_string(&ClientMessage::MissionContinue(request)).unwrap(),
            ))
            .await
            .unwrap();
        socket.close(None).await.unwrap();
        if let Some(id) = player_id {
            assert!(
                matches!(timeout(Duration::from_secs(2), commands.recv()).await.unwrap(), Some(GameCommand::MissionContinue { player_id, request: received }) if player_id == id && received == request)
            );
        }
        // The ordered disconnect proves a spectator's preceding continue was ignored.
        assert!(matches!(
            timeout(Duration::from_secs(2), commands.recv())
                .await
                .unwrap(),
            Some(GameCommand::Disconnected { .. })
        ));
    }
    accept.abort();
}

#[tokio::test]
async fn mission_admission_bounds_participants_and_keeps_spectators_separate() {
    let (tx, mut commands) = mpsc::unbounded_channel();
    let server = NetServer::bind_with_requirements(
        "127.0.0.1:0",
        tx,
        2,
        crate::protocol::READINESS_GAMEPLAY_VERSION,
    )
    .await
    .unwrap();
    let address = server.local_addr().unwrap();
    let accept = tokio::spawn(server.accept_loop());
    let mut joined = Vec::new();
    for (role, version, expected) in [
        ("human", 4, "unsupported_gameplay"),
        ("agent", 4, "unsupported_gameplay"),
        ("spectator", 4, "unsupported_gameplay"),
        ("human", 5, "welcome"),
        ("agent", 5, "welcome"),
        ("human", 5, "welcome"),
        ("agent", 5, "welcome"),
        ("human", 5, "party_full"),
        ("agent", 5, "party_full"),
        ("spectator", 5, "welcome"),
    ] {
        let (mut socket, _) = connect_async(format!("ws://{address}")).await.unwrap();
        socket.send(Message::Text(serde_json::json!({
            "type":"hello","role":role,"name":"Visitor","geometry_version":2,"gameplay_version":version
        }).to_string())).await.unwrap();
        let reply = timeout(Duration::from_secs(2), socket.next())
            .await
            .unwrap()
            .unwrap()
            .unwrap();
        let reply: ServerMessage = serde_json::from_str(reply.to_text().unwrap()).unwrap();
        if expected == "welcome" {
            assert!(matches!(reply, ServerMessage::Welcome { .. }));
            assert!(matches!(
                timeout(Duration::from_secs(2), commands.recv())
                    .await
                    .unwrap(),
                Some(GameCommand::Connected { .. })
            ));
            joined.push(socket);
        } else {
            assert!(matches!(reply, ServerMessage::Error { code, .. } if code == expected));
            assert!(commands.try_recv().is_err());
        }
    }
    assert_eq!(joined.len(), 5);
    let mut departed = joined.remove(0);
    departed.close(None).await.unwrap();
    assert!(matches!(
        timeout(Duration::from_secs(2), commands.recv())
            .await
            .unwrap(),
        Some(GameCommand::Disconnected { .. })
    ));
    let (mut replacement, _) = connect_async(format!("ws://{address}")).await.unwrap();
    replacement.send(Message::Text(serde_json::json!({"type":"hello","role":"agent","name":"Replacement","geometry_version":2,"gameplay_version":5}).to_string())).await.unwrap();
    let reply = timeout(Duration::from_secs(2), replacement.next())
        .await
        .unwrap()
        .unwrap()
        .unwrap();
    assert!(matches!(
        serde_json::from_str::<ServerMessage>(reply.to_text().unwrap()).unwrap(),
        ServerMessage::Welcome {
            player_id: Some(_),
            ..
        }
    ));
    for mut socket in joined {
        socket.close(None).await.unwrap();
    }
    replacement.close(None).await.unwrap();
    accept.abort();
}

#[tokio::test]
async fn join_secret_rejects_before_the_solo_seat_and_leaves_watchers_open() {
    let secret = Arc::new(
        crate::join_ticket::JoinSecret::from_env_value("0123456789abcdef")
            .unwrap()
            .unwrap(),
    );
    let (tx, mut commands) = mpsc::unbounded_channel();
    let mut server =
        NetServer::bind_with_requirements("127.0.0.1:0", tx, 2, crate::protocol::GAMEPLAY_VERSION)
            .await
            .unwrap();
    server.reserve_solo_run().unwrap();
    server.set_join_secret(Arc::clone(&secret));
    let address = server.local_addr().unwrap();
    let accept = tokio::spawn(server.accept_loop());
    let now = crate::join_ticket::unix_now();
    let human = crate::join_ticket::mint(&secret, Role::Human, now + 60).unwrap();
    let rejected = [
        None,
        Some("nope".to_string()),
        Some(crate::join_ticket::mint(&secret, Role::Agent, now + 60).unwrap()),
        Some(crate::join_ticket::mint(&secret, Role::Human, now.saturating_sub(30)).unwrap()),
        Some(crate::join_ticket::mint(&secret, Role::Human, now.saturating_add(120)).unwrap()),
    ];
    for ticket in rejected {
        let (mut socket, _) = connect_async(format!("ws://{address}")).await.unwrap();
        let mut hello = serde_json::json!({
            "type": "hello",
            "role": "human",
            "name": "Locked",
            "geometry_version": 2,
            "gameplay_version": crate::protocol::GAMEPLAY_VERSION,
        });
        if let Some(ticket) = ticket {
            hello["ticket"] = serde_json::Value::String(ticket);
        }
        socket.send(Message::Text(hello.to_string())).await.unwrap();
        let reply = timeout(Duration::from_secs(2), socket.next())
            .await
            .unwrap()
            .unwrap()
            .unwrap();
        assert_eq!(admission_code(reply), "join_rejected");
        let close = timeout(Duration::from_secs(2), socket.next())
            .await
            .unwrap()
            .unwrap()
            .unwrap();
        assert!(matches!(close, Message::Close(Some(frame)) if frame.reason == "join_rejected"));
        assert!(commands.try_recv().is_err());
    }

    let (mut spectator, _) = connect_async(format!("ws://{address}")).await.unwrap();
    spectator
        .send(Message::Text(
            serde_json::json!({
                "type": "hello",
                "role": "spectator",
                "name": "Watch",
                "geometry_version": 2,
                "gameplay_version": crate::protocol::GAMEPLAY_VERSION,
                "ticket": "not-a-ticket",
            })
            .to_string(),
        ))
        .await
        .unwrap();
    let reply = timeout(Duration::from_secs(2), spectator.next())
        .await
        .unwrap()
        .unwrap()
        .unwrap();
    assert!(matches!(
        serde_json::from_str::<ServerMessage>(reply.to_text().unwrap()).unwrap(),
        ServerMessage::Welcome {
            player_id: None,
            ..
        }
    ));
    assert!(matches!(
        timeout(Duration::from_secs(2), commands.recv())
            .await
            .unwrap(),
        Some(GameCommand::Connected {
            role: Role::Spectator,
            ..
        })
    ));

    let (mut owner, _) = connect_async(format!("ws://{address}")).await.unwrap();
    owner
        .send(Message::Text(
            serde_json::json!({
                "type": "hello",
                "role": "human",
                "name": "Owner",
                "geometry_version": 2,
                "gameplay_version": crate::protocol::GAMEPLAY_VERSION,
                "ticket": human,
            })
            .to_string(),
        ))
        .await
        .unwrap();
    let reply = timeout(Duration::from_secs(2), owner.next())
        .await
        .unwrap()
        .unwrap()
        .unwrap();
    assert!(matches!(
        serde_json::from_str::<ServerMessage>(reply.to_text().unwrap()).unwrap(),
        ServerMessage::Welcome {
            player_id: Some(_),
            ..
        }
    ));
    assert!(matches!(
        timeout(Duration::from_secs(2), commands.recv())
            .await
            .unwrap(),
        Some(GameCommand::Connected {
            role: Role::Human,
            ..
        })
    ));

    let again = crate::join_ticket::mint(&secret, Role::Human, crate::join_ticket::unix_now() + 60)
        .unwrap();
    let (mut second, _) = connect_async(format!("ws://{address}")).await.unwrap();
    second
        .send(Message::Text(
            serde_json::json!({
                "type": "hello",
                "role": "human",
                "name": "Second",
                "geometry_version": 2,
                "gameplay_version": crate::protocol::GAMEPLAY_VERSION,
                "ticket": again,
            })
            .to_string(),
        ))
        .await
        .unwrap();
    let reply = timeout(Duration::from_secs(2), second.next())
        .await
        .unwrap()
        .unwrap()
        .unwrap();
    assert_eq!(admission_code(reply), "run_seat_closed");
    assert!(commands.try_recv().is_err());
    accept.abort();
}

#[tokio::test]
async fn an_open_server_ignores_a_presented_ticket() {
    let (tx, mut commands) = mpsc::unbounded_channel();
    let server =
        NetServer::bind_with_requirements("127.0.0.1:0", tx, 2, crate::protocol::GAMEPLAY_VERSION)
            .await
            .unwrap();
    let address = server.local_addr().unwrap();
    let accept = tokio::spawn(server.accept_loop());
    let (mut socket, _) = connect_async(format!("ws://{address}")).await.unwrap();
    socket
        .send(Message::Text(
            serde_json::json!({
                "type": "hello",
                "role": "human",
                "name": "Open",
                "geometry_version": 2,
                "gameplay_version": crate::protocol::GAMEPLAY_VERSION,
                "ticket": "garbage",
            })
            .to_string(),
        ))
        .await
        .unwrap();
    let reply = timeout(Duration::from_secs(2), socket.next())
        .await
        .unwrap()
        .unwrap()
        .unwrap();
    assert!(matches!(
        serde_json::from_str::<ServerMessage>(reply.to_text().unwrap()).unwrap(),
        ServerMessage::Welcome {
            player_id: Some(_),
            ..
        }
    ));
    assert!(matches!(
        timeout(Duration::from_secs(2), commands.recv())
            .await
            .unwrap(),
        Some(GameCommand::Connected { .. })
    ));
    accept.abort();
}
