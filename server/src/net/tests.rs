use super::*;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::time::{timeout, Duration};
use tokio_tungstenite::connect_async;

#[tokio::test]
async fn automatic_admission_validates_before_reservation_and_keeps_watchers_open() {
    let (tx, mut commands) = mpsc::unbounded_channel();
    let mut server =
        NetServer::bind_with_requirements("127.0.0.1:0", tx, 2, crate::protocol::GAMEPLAY_VERSION)
            .await
            .unwrap();
    server.set_sabotage_seats(Arc::new(Semaphore::new(0)));
    server.set_auto_fill();
    let secret = Arc::new(
        crate::join_ticket::JoinSecret::from_env_value("0123456789abcdef")
            .unwrap()
            .unwrap(),
    );
    server.set_join_secret(Arc::clone(&secret));
    let valid_ticket =
        crate::join_ticket::mint(&secret, Role::Agent, crate::join_ticket::unix_now() + 60)
            .unwrap();
    let address = server.local_addr().unwrap();
    let accept = tokio::spawn(server.accept_loop());
    for (version, code, ticket) in [
        (
            crate::protocol::GAMEPLAY_VERSION - 1,
            "unsupported_gameplay",
            valid_ticket.as_str(),
        ),
        (
            crate::protocol::GAMEPLAY_VERSION,
            "join_rejected",
            "invalid",
        ),
    ] {
        let (mut socket, _) = connect_async(format!("ws://{address}")).await.unwrap();
        socket.send(Message::Text(serde_json::json!({"type":"hello", "role":"agent", "name":"Dead Air Dan", "geometry_version":2, "gameplay_version":version,"ticket":ticket}).to_string())).await.unwrap();
        let message = timeout(Duration::from_secs(2), socket.next())
            .await
            .unwrap()
            .unwrap()
            .unwrap();
        assert_eq!(admission_code(message), code);
        assert!(
            commands.try_recv().is_err(),
            "invalid hello must never ask to yield a bot"
        );
    }
    let (mut watcher, _) = connect_async(format!("ws://{address}")).await.unwrap();
    watcher.send(Message::Text(serde_json::json!({"type":"hello", "role":"spectator", "name":"Watcher", "geometry_version":2, "gameplay_version":crate::protocol::GAMEPLAY_VERSION}).to_string())).await.unwrap();
    let message = timeout(Duration::from_secs(2), watcher.next())
        .await
        .unwrap()
        .unwrap()
        .unwrap();
    assert!(matches!(
        serde_json::from_str::<ServerMessage>(message.to_text().unwrap()).unwrap(),
        ServerMessage::Welcome {
            player_id: None,
            ..
        }
    ));
    assert!(matches!(
        timeout(Duration::from_secs(2), skip_seat_notes(&mut commands))
            .await
            .unwrap(),
        Some(GameCommand::Connected {
            player_id: None,
            ..
        })
    ));
    watcher.close(None).await.unwrap();
    accept.abort();
    let _ = accept.await;
}

#[tokio::test]
async fn automatic_abandoned_welcome_cancels_only_its_request_and_resume_arm() {
    let (tx, mut commands) = mpsc::unbounded_channel();
    let table = Arc::new(crate::resume::ResumeTable::new());
    let abandoned = Uuid::from_u128(101);
    let retained = Uuid::from_u128(102);
    let abandoned_token = table.arm(abandoned, Role::Human);
    let retained_token = table.arm(retained, Role::Agent);
    let abandoned_nonce = table.open(&abandoned_token).unwrap().2;
    let retained_nonce = table.open(&retained_token).unwrap().2;
    let gate = crate::bot_fill::admission_gate();
    let client_id = Uuid::from_u128(1);
    let guard = AutoJoinGuard {
        client_id,
        gate: Arc::clone(&gate),
        game_tx: tx,
        resume: Arc::clone(&table),
        player_id: Some(abandoned),
        armed: true,
    };
    // Cancellation after an offered Welcome must invalidate that offered arm,
    // not create a resumable pawn or affect another participant's reservation.
    drop(guard);
    assert_eq!(
        gate.lock().unwrap().phase,
        crate::bot_fill::AdmissionPhase::Cancelled
    );
    assert!(
        matches!(commands.try_recv().unwrap(), GameCommand::CancelAutoJoin { client_id: id } if id == client_id)
    );
    assert!(commands.try_recv().is_err());
    table.park(abandoned, None, 0);
    assert!(table
        .claim(abandoned, abandoned_nonce, Role::Human)
        .is_none());
    table.park(retained, None, 0);
    assert!(table.claim(retained, retained_nonce, Role::Agent).is_some());
}

#[tokio::test]
async fn automatic_registration_lock_uses_the_shared_finite_deadline_and_cancels_exact_request() {
    let (tx, mut commands) = mpsc::unbounded_channel();
    let mut server =
        NetServer::bind_with_requirements("127.0.0.1:0", tx, 2, crate::protocol::GAMEPLAY_VERSION)
            .await
            .unwrap();
    server.set_sabotage_seats(Arc::new(Semaphore::new(0)));
    server.set_auto_fill();
    let address = server.local_addr().unwrap();
    let clients = Arc::clone(&server.clients);
    let held_registry = clients.lock().await;
    let accept = tokio::spawn(server.accept_loop());
    let (mut socket, _) = connect_async(format!("ws://{address}")).await.unwrap();
    socket.send(Message::Text(serde_json::json!({"type":"hello", "role":"human", "name":"Held registration", "geometry_version":2, "gameplay_version":crate::protocol::GAMEPLAY_VERSION}).to_string())).await.unwrap();
    let request = timeout(Duration::from_secs(2), skip_seat_notes(&mut commands))
        .await
        .unwrap()
        .unwrap();
    let (client_id, gate) = match request {
        GameCommand::PrepareAutoJoin {
            client_id,
            gate,
            reply,
        } => {
            reply.send(Ok(())).unwrap();
            (client_id, gate)
        }
        _ => panic!("expected bounded preparation"),
    };
    let message = timeout(Duration::from_secs(2), socket.next())
        .await
        .unwrap()
        .unwrap()
        .unwrap();
    assert!(matches!(
        serde_json::from_str::<ServerMessage>(message.to_text().unwrap()).unwrap(),
        ServerMessage::Welcome { .. }
    ));
    let rejection = timeout(Duration::from_secs(3), socket.next())
        .await
        .unwrap()
        .unwrap()
        .unwrap();
    assert_eq!(admission_code(rejection), "bot_fill_cancelled");
    assert!(
        matches!(timeout(Duration::from_secs(2), skip_seat_notes(&mut commands)).await.unwrap(), Some(GameCommand::CancelAutoJoin { client_id: cancelled }) if cancelled == client_id)
    );
    assert_eq!(
        gate.lock().unwrap().phase,
        crate::bot_fill::AdmissionPhase::Cancelled
    );
    assert!(
        held_registry.is_empty(),
        "timeout must not register a client or send Commit"
    );
    assert!(commands.try_recv().is_err());
    drop(held_registry);
    accept.abort();
    let _ = accept.await;
}

struct StalledSink;

impl futures_util::Sink<Message> for StalledSink {
    type Error = std::io::Error;

    fn poll_ready(
        self: std::pin::Pin<&mut Self>,
        _: &mut std::task::Context<'_>,
    ) -> std::task::Poll<Result<(), Self::Error>> {
        std::task::Poll::Pending
    }

    fn start_send(self: std::pin::Pin<&mut Self>, _: Message) -> Result<(), Self::Error> {
        unreachable!("a stalled sink never accepts a frame")
    }

    fn poll_flush(
        self: std::pin::Pin<&mut Self>,
        _: &mut std::task::Context<'_>,
    ) -> std::task::Poll<Result<(), Self::Error>> {
        std::task::Poll::Pending
    }

    fn poll_close(
        self: std::pin::Pin<&mut Self>,
        _: &mut std::task::Context<'_>,
    ) -> std::task::Poll<Result<(), Self::Error>> {
        std::task::Poll::Pending
    }
}

#[tokio::test]
async fn stalled_writer_times_out_and_wakes_connection_cleanup() {
    let (tx, rx) = mpsc::channel(1);
    let (shutdown, mut changed) = tokio::sync::watch::channel(StopSignal::Open);
    tx.send(ServerMessage::Error {
        code: "queued".into(),
        message: "queued".into(),
    })
    .await
    .unwrap();
    let (_stop, stop) = tokio::sync::oneshot::channel();
    let writer = tokio::spawn(run_outbound_writer(
        StalledSink,
        rx,
        shutdown,
        Duration::from_millis(20),
        Duration::from_secs(60),
        stop,
        crate::metrics::ClientTraffic::new(Role::Spectator, Default::default()),
    ));
    timeout(Duration::from_secs(1), changed.changed())
        .await
        .unwrap()
        .unwrap();
    assert_eq!(*changed.borrow_and_update(), StopSignal::Quiet);
    writer.await.unwrap();
}

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
            timeout(Duration::from_secs(2), skip_seat_notes(&mut commands))
                .await
                .unwrap(),
            Some(GameCommand::Connected { .. })
        ));
        socket.close(None).await.unwrap();
        assert!(matches!(
            timeout(Duration::from_secs(2), skip_seat_notes(&mut commands))
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
    assert_eq!(classify_opening(b"GET /status HTTP/1.1"), Some(true));
    assert_eq!(classify_opening(b"GET /status?watch=1"), Some(true));
    assert_eq!(classify_opening(b"GET /status-evil HTTP/1.1"), Some(false));
    assert_eq!(classify_opening(b"POST /status HTTP/1.1"), Some(false));
    assert_eq!(classify_opening(b"GET"), None);
    assert_eq!(classify_opening(b"GET /status"), None);
    assert_eq!(classify_opening(b"GET /status "), Some(true));
    assert_eq!(classify_opening(b"GET /status-evil"), Some(false));
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
        ..crate::protocol::LiveStatus::default()
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
async fn status_reads_stop_at_their_own_cap_and_leave_game_slots_free() {
    let (tx, mut commands) = mpsc::unbounded_channel();
    let mut server = NetServer::bind("127.0.0.1:0", tx).await.unwrap();
    server.tighten_admission(4, 8, Duration::from_secs(2), Duration::from_secs(2));
    server.tighten_status_slots(1);
    let address = server.local_addr().unwrap();
    let accept = tokio::spawn(server.accept_loop());

    let mut slow = tokio::net::TcpStream::connect(address).await.unwrap();
    slow.write_all(b"GET /status HTTP/1.1\r\nHost: x\r\n")
        .await
        .unwrap();
    tokio::time::sleep(Duration::from_millis(80)).await;

    let mut extra = tokio::net::TcpStream::connect(address).await.unwrap();
    extra
        .write_all(b"GET /status HTTP/1.1\r\nHost: x\r\n\r\n")
        .await
        .unwrap();
    let mut buf = [0u8; 32];
    let read = timeout(Duration::from_millis(400), extra.read(&mut buf)).await;
    let bytes = read.expect("a capped status probe closes").unwrap();
    assert_eq!(bytes, 0, "the extra status probe is closed: {buf:?}");

    let _held = welcome_spectator(address).await;
    assert!(matches!(
        timeout(Duration::from_secs(2), skip_seat_notes(&mut commands))
            .await
            .unwrap(),
        Some(GameCommand::Connected { .. })
    ));
    accept.abort();
}

#[tokio::test]
async fn unadmitted_connections_stop_at_the_connection_cap() {
    let (tx, _commands) = mpsc::unbounded_channel();
    let mut server = NetServer::bind("127.0.0.1:0", tx).await.unwrap();
    server.tighten_admission(1, 8, Duration::from_secs(2), Duration::from_secs(2));
    let address = server.local_addr().unwrap();
    let accept = tokio::spawn(server.accept_loop());

    let mut first = tokio::net::TcpStream::connect(address).await.unwrap();
    // An unfinished request line stays in classification and holds the permit.
    first.write_all(b"GET").await.unwrap();
    tokio::time::sleep(Duration::from_millis(40)).await;
    let mut second = tokio::net::TcpStream::connect(address).await.unwrap();
    let mut buf = [0u8; 16];
    let read = timeout(Duration::from_millis(200), second.read(&mut buf)).await;
    let bytes = read
        .expect("a connection past the pre-hello cap closes")
        .unwrap();
    assert_eq!(bytes, 0);
    accept.abort();
}

#[tokio::test]
async fn a_full_server_drops_refusals_past_the_explanation_cap() {
    let (tx, mut commands) = mpsc::unbounded_channel();
    let mut server = NetServer::bind("127.0.0.1:0", tx).await.unwrap();
    server.tighten_admission(1, 8, Duration::from_secs(2), Duration::from_secs(2));
    server.tighten_rejection_slots(0);
    let address = server.local_addr().unwrap();
    let accept = tokio::spawn(server.accept_loop());
    let _held = welcome_spectator(address).await;
    assert!(matches!(
        timeout(Duration::from_secs(2), skip_seat_notes(&mut commands))
            .await
            .unwrap(),
        Some(GameCommand::Connected { .. })
    ));
    let refused = timeout(
        Duration::from_secs(2),
        connect_async(format!("ws://{address}")),
    )
    .await;
    assert!(
        refused.unwrap().is_err(),
        "past the explanation cap the socket closes without a handshake"
    );
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
        timeout(Duration::from_secs(2), skip_seat_notes(&mut commands))
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
        timeout(Duration::from_secs(2), skip_seat_notes(&mut commands))
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
            timeout(Duration::from_secs(2), skip_seat_notes(&mut commands))
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
            timeout(Duration::from_secs(2), skip_seat_notes(&mut commands))
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
        timeout(Duration::from_secs(2), skip_seat_notes(&mut commands))
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
    while timeout(Duration::from_millis(50), skip_seat_notes(&mut commands))
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
        timeout(Duration::from_secs(2), skip_seat_notes(&mut commands))
            .await
            .unwrap(),
        Some(GameCommand::Connected { .. })
    ));
    drop(held);
    let _ = timeout(Duration::from_secs(2), skip_seat_notes(&mut commands)).await;

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
            timeout(Duration::from_secs(2), skip_seat_notes(&mut commands))
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
                matches!(timeout(Duration::from_secs(2), skip_seat_notes(&mut commands)).await.unwrap(), Some(GameCommand::MissionContinue { player_id, request: received }) if player_id == id && received == request)
            );
        }
        // The ordered disconnect proves a spectator's preceding continue was ignored.
        assert!(matches!(
            timeout(Duration::from_secs(2), skip_seat_notes(&mut commands))
                .await
                .unwrap(),
            Some(GameCommand::Disconnected { .. })
        ));
    }
    accept.abort();
}

#[tokio::test]
async fn rules_three_missions_refuse_retired_readers_before_any_role_is_admitted() {
    let (tx, mut commands) = mpsc::unbounded_channel();
    let server = NetServer::bind_with_requirements(
        "127.0.0.1:0",
        tx,
        2,
        crate::protocol::M04_GAMEPLAY_VERSION,
    )
    .await
    .unwrap();
    let address = server.local_addr().unwrap();
    let accept = tokio::spawn(server.accept_loop());
    for role in ["human", "agent", "spectator"] {
        let (mut socket, _) = connect_async(format!("ws://{address}")).await.unwrap();
        socket
            .send(Message::Text(
                serde_json::json!({
                    "type":"hello", "role":role, "name":"Reader", "geometry_version":2,
                    "gameplay_version":24
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
            ServerMessage::Error { code, .. } if code == "unsupported_gameplay"
        ));
        assert!(commands.try_recv().is_err());
    }
    let (mut socket, _) = connect_async(format!("ws://{address}")).await.unwrap();
    socket
        .send(Message::Text(
            serde_json::json!({
                "type":"hello", "role":"agent", "name":"Reader", "geometry_version":2,
                "gameplay_version":crate::protocol::GAMEPLAY_VERSION
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
        timeout(Duration::from_secs(2), skip_seat_notes(&mut commands))
            .await
            .unwrap(),
        Some(GameCommand::Connected { .. })
    ));
    accept.abort();
}

/// Discovery maps, M01 included, need the Shiv contract: a magazine-era or
/// Shiv-blind reader is refused before Welcome and the current reader is admitted.
#[tokio::test]
async fn m01_refuses_shiv_blind_capability_ten_and_admits_eleven() {
    let (tx, mut commands) = mpsc::unbounded_channel();
    let server = NetServer::bind_with_requirements(
        "127.0.0.1:0",
        tx,
        2,
        crate::protocol::SHIV_GAMEPLAY_VERSION,
    )
    .await
    .unwrap();
    let address = server.local_addr().unwrap();
    let accept = tokio::spawn(server.accept_loop());
    for (version, admitted) in [(8, false), (10, false), (11, true)] {
        let (mut socket, _) = connect_async(format!("ws://{address}")).await.unwrap();
        socket
            .send(Message::Text(
                serde_json::json!({
                    "type":"hello", "role":"human", "name":"Reader", "geometry_version":2,
                    "gameplay_version":version
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
        let message = serde_json::from_str::<ServerMessage>(reply.to_text().unwrap()).unwrap();
        if admitted {
            assert!(matches!(
                message,
                ServerMessage::Welcome {
                    player_id: Some(_),
                    ..
                }
            ));
            assert!(matches!(
                timeout(Duration::from_secs(2), skip_seat_notes(&mut commands))
                    .await
                    .unwrap(),
                Some(GameCommand::Connected { .. })
            ));
        } else {
            assert!(
                matches!(&message, ServerMessage::Error { code, .. } if code == "unsupported_gameplay"),
                "{version}: {message:?}"
            );
        }
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
                timeout(Duration::from_secs(2), skip_seat_notes(&mut commands))
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
        timeout(Duration::from_secs(2), skip_seat_notes(&mut commands))
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
        timeout(Duration::from_secs(2), skip_seat_notes(&mut commands))
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
        timeout(Duration::from_secs(2), skip_seat_notes(&mut commands))
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
        timeout(Duration::from_secs(2), skip_seat_notes(&mut commands))
            .await
            .unwrap(),
        Some(GameCommand::Connected { .. })
    ));
    accept.abort();
}

#[tokio::test]
async fn server_close_signal_releases_idle_spectator_without_stalling_peers() {
    let (tx, mut commands) = mpsc::unbounded_channel();
    let mut server = NetServer::bind("127.0.0.1:0", tx).await.unwrap();
    server.tighten_admission(3, 3, Duration::from_secs(2), Duration::from_secs(2));
    let address = server.local_addr().unwrap();
    let clients = server.clients.clone();
    let accept = tokio::spawn(server.accept_loop());
    let _slow = welcome_spectator(address).await;
    let mut healthy = welcome_spectator(address).await;
    let (mut fighter, _) = connect_async(format!("ws://{address}")).await.unwrap();
    fighter
        .send(Message::Text(
            r#"{"type":"hello","role":"human","name":"Fighter","resume":""}"#.to_string(),
        ))
        .await
        .unwrap();
    let welcome = timeout(Duration::from_secs(2), fighter.next())
        .await
        .unwrap()
        .unwrap()
        .unwrap();
    assert!(matches!(
        serde_json::from_str::<ServerMessage>(welcome.to_text().unwrap()).unwrap(),
        ServerMessage::Welcome {
            player_id: Some(_),
            resume: Some(_),
            ..
        }
    ));
    let mut ids = Vec::new();
    for _ in 0..3 {
        let command = timeout(Duration::from_secs(2), skip_seat_notes(&mut commands))
            .await
            .unwrap()
            .unwrap();
        let GameCommand::Connected { id, .. } = command else {
            panic!("expected connection");
        };
        ids.push(id);
    }
    assert_eq!(clients.lock().await.len(), 3);
    clients.lock().await[0].request_close();
    let disconnected = timeout(Duration::from_secs(2), skip_seat_notes(&mut commands))
        .await
        .unwrap()
        .unwrap();
    assert!(matches!(disconnected, GameCommand::Disconnected { id } if id == ids[0]));
    assert_eq!(clients.lock().await.len(), 2);
    let _replacement = welcome_spectator(address).await;
    assert!(matches!(
        timeout(Duration::from_secs(2), skip_seat_notes(&mut commands))
            .await
            .unwrap(),
        Some(GameCommand::Connected {
            role: Role::Spectator,
            ..
        })
    ));

    let session = crate::session::GameSession::new();
    let map = session.state.map_info();
    crate::session::send_unicasts(
        &clients,
        &std::collections::HashMap::new(),
        &[
            (crate::session::Recipient::Client(ids[1]), map.clone()),
            (crate::session::Recipient::Client(ids[2]), map),
        ],
    )
    .await;
    crate::session::broadcast_to_clients(
        &clients,
        &[ServerMessage::Snapshot(session.state.snapshot())],
    )
    .await;
    for socket in [&mut healthy, &mut fighter] {
        let map = timeout(Duration::from_secs(2), socket.next())
            .await
            .unwrap()
            .unwrap()
            .unwrap();
        assert!(matches!(
            serde_json::from_str::<ServerMessage>(map.to_text().unwrap()).unwrap(),
            ServerMessage::MapInfo { .. }
        ));
        let snapshot = timeout(Duration::from_secs(2), socket.next())
            .await
            .unwrap()
            .unwrap()
            .unwrap();
        assert!(matches!(
            serde_json::from_str::<ServerMessage>(snapshot.to_text().unwrap()).unwrap(),
            ServerMessage::Snapshot(_)
        ));
    }
    let fighter_id = ids[2];
    clients
        .lock()
        .await
        .iter()
        .find(|client| client.id == fighter_id)
        .unwrap()
        .request_close();
    let detached = timeout(Duration::from_secs(2), skip_seat_notes(&mut commands))
        .await
        .unwrap()
        .unwrap();
    assert!(matches!(detached, GameCommand::Detached { id } if id == fighter_id));
    assert_eq!(clients.lock().await.len(), 2);
    accept.abort();
}

fn quick_limits() -> SessionLimits {
    SessionLimits {
        ping_every: Duration::from_millis(50),
        idle_after: Duration::from_millis(400),
        ..SessionLimits::default()
    }
}

type ClientSocket =
    tokio_tungstenite::WebSocketStream<tokio_tungstenite::MaybeTlsStream<tokio::net::TcpStream>>;

async fn hello(address: std::net::SocketAddr, body: &str) -> ClientSocket {
    let (mut socket, _) = connect_async(format!("ws://{address}")).await.unwrap();
    socket.send(Message::Text(body.to_string())).await.unwrap();
    socket
}

async fn welcome_fighter(address: std::net::SocketAddr, resume: bool) -> ClientSocket {
    let body = if resume {
        r#"{"type":"hello","role":"human","name":"Kick","resume":""}"#
    } else {
        r#"{"type":"hello","role":"human","name":"Kick"}"#
    };
    let mut socket = hello(address, body).await;
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
    socket
}

/// Skip pings until the final server error, and return its code plus the
/// close reason that follows it.
async fn closing_code(socket: &mut ClientSocket) -> (String, String) {
    let mut code = None;
    loop {
        let frame = timeout(Duration::from_secs(3), socket.next())
            .await
            .expect("server should close");
        match frame {
            Some(Ok(Message::Text(text))) => {
                if let Ok(ServerMessage::Error { code: found, .. }) = serde_json::from_str(&text) {
                    code = Some(found);
                }
            }
            Some(Ok(Message::Close(Some(frame)))) => {
                return (code.expect("error before close"), frame.reason.to_string());
            }
            Some(Ok(_)) => {}
            other => panic!("expected a policy close, got {other:?}"),
        }
    }
}

async fn next_command(commands: &mut mpsc::UnboundedReceiver<GameCommand>) -> GameCommand {
    timeout(Duration::from_secs(3), skip_seat_notes(commands))
        .await
        .expect("command timeout")
        .expect("command channel open")
}

#[test]
fn strikes_drain_over_time_and_trip_past_the_limit() {
    let start = std::time::Instant::now();
    let mut strikes = Strikes::new(start);
    for _ in 0..3 {
        assert!(!strikes.add(start, 1.0, 3.0));
    }
    assert!(strikes.add(start, 1.0, 3.0), "fourth strike trips");
    let mut forgiven = Strikes::new(start);
    for second in 0..20 {
        let now = start + Duration::from_secs(second);
        assert!(!forgiven.add(now, 1.0, 3.0), "one a second drains away");
    }
}

#[test]
fn junk_is_only_text_without_a_typed_envelope() {
    assert!(is_junk("not json"));
    assert!(is_junk("[1,2,3]"));
    assert!(is_junk(r#"{"forward":true}"#));
    assert!(is_junk(r#"{"type":7}"#));
    assert!(!is_junk(r#"{"type":"from_a_newer_client"}"#));
    assert!(!is_junk(r#"{"type":"action","forward":"bad"}"#));
    assert_eq!(audit_name(&"n".repeat(100)).chars().count(), 32);
}

#[test]
fn kick_codes_and_pawn_rules_are_stable() {
    assert_eq!(Kick::Idle.code(), "idle_timeout");
    assert!(!Kick::Idle.removes_pawn());
    assert_eq!(Kick::RateLimited.code(), "rate_limited");
    assert_eq!(Kick::Malformed.code(), "malformed");
    assert!(Kick::RateLimited.removes_pawn() && Kick::Malformed.removes_pawn());
    let banned = Kick::Refused(crate::access::Verdict::Banned {
        line: 1,
        reason: None,
    });
    assert_eq!(banned.code(), "address_banned");
    assert_eq!(banned.audit_event(), "ban");
    let listed = Kick::Refused(crate::access::Verdict::NotAllowed);
    assert_eq!(listed.code(), "address_not_allowed");
    assert_eq!(listed.audit_event(), "kick");
    let venue = Kick::Venue { banned: false };
    assert_eq!(venue.code(), "venue_kick");
    assert_eq!(venue.message(), "The venue asked you to step outside.");
    assert!(venue.removes_pawn());
    assert_eq!(venue.audit_event(), "kick");
    let venue_ban = Kick::Venue { banned: true };
    assert_eq!(venue_ban.code(), "address_banned");
    assert_eq!(venue_ban.audit_event(), "ban");
    for kick in [
        Kick::Idle,
        Kick::RateLimited,
        Kick::Malformed,
        banned,
        listed,
        venue,
        venue_ban,
    ] {
        assert!(!kick.message().is_empty());
    }
    assert_eq!(
        refusal_message("connection_limit"),
        "This server is not taking more connections."
    );
}

#[tokio::test]
async fn venue_close_removes_a_resume_armed_human_and_says_why() {
    let (tx, mut commands) = mpsc::unbounded_channel();
    let server = NetServer::bind("127.0.0.1:0", tx).await.unwrap();
    let address = server.local_addr().unwrap();
    let clients = server.clients.clone();
    let accept = tokio::spawn(server.accept_loop());
    let mut fighter = welcome_fighter(address, true).await;
    let noted = timeout(Duration::from_secs(2), commands.recv())
        .await
        .unwrap()
        .unwrap();
    let GameCommand::NoteSeat { client_id, peer } = noted else {
        panic!("the desk hears the address before the join");
    };
    assert_eq!(
        peer.ip().to_canonical(),
        std::net::IpAddr::from([127, 0, 0, 1])
    );
    let joined = timeout(Duration::from_secs(2), commands.recv())
        .await
        .unwrap()
        .unwrap();
    let GameCommand::Connected { id, .. } = joined else {
        panic!("expected the join after the address");
    };
    assert_eq!(id, client_id);
    clients
        .lock()
        .await
        .iter()
        .find(|client| client.id == id)
        .unwrap()
        .venue_close(false);
    let mut code = String::new();
    let mut message = String::new();
    loop {
        let frame = timeout(Duration::from_secs(2), fighter.next())
            .await
            .unwrap()
            .unwrap()
            .unwrap();
        match frame {
            Message::Text(text) => {
                let ServerMessage::Error {
                    code: found,
                    message: line,
                } = serde_json::from_str(&text).unwrap()
                else {
                    continue;
                };
                code = found;
                message = line;
            }
            Message::Ping(_) => {}
            Message::Close(_) => break,
            other => panic!("expected the venue error, got {other:?}"),
        }
    }
    assert_eq!(code, "venue_kick");
    assert_eq!(message, "The venue asked you to step outside.");
    let gone = timeout(Duration::from_secs(2), commands.recv())
        .await
        .unwrap()
        .unwrap();
    assert!(
        matches!(gone, GameCommand::Disconnected { id: dropped } if dropped == id),
        "a venue kick removes the pawn instead of parking it"
    );
    accept.abort();
}

#[tokio::test]
async fn quiet_spectator_that_answers_pings_is_not_idle() {
    let (tx, mut commands) = mpsc::unbounded_channel();
    let mut server = NetServer::bind("127.0.0.1:0", tx).await.unwrap();
    server.tighten_session(quick_limits());
    let address = server.local_addr().unwrap();
    let accept = tokio::spawn(server.accept_loop());
    let mut watcher = welcome_spectator(address).await;
    assert!(matches!(
        next_command(&mut commands).await,
        GameCommand::Connected { .. }
    ));
    // Read only: the client library answers each ping while it reads.
    let mut pings = 0;
    let deadline = tokio::time::Instant::now() + Duration::from_millis(1200);
    while tokio::time::Instant::now() < deadline {
        if let Ok(Some(Ok(Message::Ping(_)))) =
            timeout(Duration::from_millis(100), watcher.next()).await
        {
            pings += 1;
        }
    }
    assert!(pings >= 5, "server should ping a quiet session: {pings}");
    assert!(
        commands.try_recv().is_err(),
        "three idle windows passed and the watcher stayed"
    );
    accept.abort();
}

#[tokio::test]
async fn silent_fighter_is_dropped_as_idle_and_keeps_a_resumable_pawn() {
    let (tx, mut commands) = mpsc::unbounded_channel();
    let mut server = NetServer::bind("127.0.0.1:0", tx).await.unwrap();
    server.tighten_session(quick_limits());
    let address = server.local_addr().unwrap();
    let accept = tokio::spawn(server.accept_loop());
    let mut fighter = welcome_fighter(address, true).await;
    let GameCommand::Connected { id, .. } = next_command(&mut commands).await else {
        panic!("expected a connection");
    };
    // Not reading means no pong goes back.
    let detached = next_command(&mut commands).await;
    assert!(
        matches!(detached, GameCommand::Detached { id: gone } if gone == id),
        "an idle drop parks the pawn like any lost network"
    );
    let (code, reason) = closing_code(&mut fighter).await;
    assert_eq!(code, "idle_timeout");
    assert_eq!(reason, "idle_timeout");
    accept.abort();
}

#[tokio::test]
async fn sustained_flood_is_kicked_and_loses_its_pawn() {
    let (tx, mut commands) = mpsc::unbounded_channel();
    let mut server = NetServer::bind("127.0.0.1:0", tx).await.unwrap();
    server.tighten_session(SessionLimits {
        flood_drain_per_sec: 0.0,
        flood_limit: 32.0,
        ..SessionLimits::default()
    });
    let address = server.local_addr().unwrap();
    let accept = tokio::spawn(server.accept_loop());
    let mut fighter = welcome_fighter(address, true).await;
    let GameCommand::Connected { id, .. } = next_command(&mut commands).await else {
        panic!("expected a connection");
    };
    for _ in 0..200 {
        if fighter
            .send(Message::Text(r#"{"type":"action","forward":true}"#.into()))
            .await
            .is_err()
        {
            break;
        }
    }
    loop {
        match next_command(&mut commands).await {
            GameCommand::Action { .. } => {}
            GameCommand::Disconnected { id: gone } => {
                assert_eq!(gone, id, "abuse removes the pawn, even with resume");
                break;
            }
            _ => panic!("unexpected command"),
        }
    }
    let (code, reason) = closing_code(&mut fighter).await;
    assert_eq!(
        (code.as_str(), reason.as_str()),
        ("rate_limited", "rate_limited")
    );
    accept.abort();
}

#[tokio::test]
async fn ping_flood_is_rate_limited_like_a_text_flood() {
    let (tx, mut commands) = mpsc::unbounded_channel();
    let mut server = NetServer::bind("127.0.0.1:0", tx).await.unwrap();
    server.tighten_session(SessionLimits {
        flood_drain_per_sec: 0.0,
        flood_limit: 32.0,
        ..SessionLimits::default()
    });
    let address = server.local_addr().unwrap();
    let accept = tokio::spawn(server.accept_loop());
    let mut fighter = welcome_fighter(address, true).await;
    let GameCommand::Connected { id, .. } = next_command(&mut commands).await else {
        panic!("expected a connection");
    };
    for _ in 0..200 {
        if fighter.send(Message::Ping(vec![1])).await.is_err() {
            break;
        }
    }
    match next_command(&mut commands).await {
        GameCommand::Disconnected { id: gone } => {
            assert_eq!(gone, id, "a control-frame flood removes the pawn");
        }
        _ => panic!("a ping flood must not enter the match"),
    }
    let (code, reason) = closing_code(&mut fighter).await;
    assert_eq!(
        (code.as_str(), reason.as_str()),
        ("rate_limited", "rate_limited")
    );
    accept.abort();
}

#[tokio::test]
async fn repeated_junk_is_kicked_but_unknown_types_are_ignored() {
    let (tx, mut commands) = mpsc::unbounded_channel();
    let mut server = NetServer::bind("127.0.0.1:0", tx).await.unwrap();
    server.tighten_session(SessionLimits {
        junk_drain_per_sec: 0.0,
        junk_limit: 3.0,
        ..SessionLimits::default()
    });
    let address = server.local_addr().unwrap();
    let accept = tokio::spawn(server.accept_loop());
    let mut watcher = welcome_spectator(address).await;
    assert!(matches!(
        next_command(&mut commands).await,
        GameCommand::Connected { .. }
    ));
    for _ in 0..10 {
        watcher
            .send(Message::Text(r#"{"type":"from_a_newer_client"}"#.into()))
            .await
            .unwrap();
    }
    watcher.send(Message::Binary(vec![1, 2, 3])).await.unwrap();
    for _ in 0..2 {
        watcher
            .send(Message::Text("{not json".into()))
            .await
            .unwrap();
    }
    assert!(
        timeout(Duration::from_millis(200), skip_seat_notes(&mut commands))
            .await
            .is_err(),
        "three strikes are still inside the limit"
    );
    watcher.send(Message::Text("[]".into())).await.unwrap();
    assert!(matches!(
        next_command(&mut commands).await,
        GameCommand::Disconnected { .. }
    ));
    let (code, _) = closing_code(&mut watcher).await;
    assert_eq!(code, "malformed");
    accept.abort();
}

fn policy_from(ban: &str, allow: Option<&str>) -> Arc<crate::access::AccessPolicy> {
    Arc::new(crate::access::AccessPolicy::new(
        Some(crate::access::AccessList::parse(ban).unwrap()),
        allow.map(|text| crate::access::AccessList::parse(text).unwrap()),
    ))
}

#[tokio::test]
async fn a_listed_refusal_does_not_hold_a_game_slot() {
    let (tx, _commands) = mpsc::unbounded_channel();
    let mut server = NetServer::bind("127.0.0.1:0", tx).await.unwrap();
    server.tighten_admission(1, 32, Duration::from_secs(5), Duration::from_secs(5));
    server.tighten_rejection_slots(0);
    let (policy_tx, policy_rx) = watch::channel(policy_from("127.0.0.0/8 reason=test\n", None));
    server.set_access(policy_rx);
    let address = server.local_addr().unwrap();
    let accept = tokio::spawn(server.accept_loop());

    let mut held = tokio::net::TcpStream::connect(address).await.unwrap();
    let mut buf = [0u8; 8];
    let read = timeout(Duration::from_millis(500), held.read(&mut buf)).await;
    assert!(
        matches!(read, Ok(Ok(0))),
        "past the explanation cap a listed address closes without a handshake: {read:?}"
    );

    policy_tx.send_replace(policy_from("", None));
    let joined = timeout(Duration::from_secs(2), welcome_spectator(address)).await;
    assert!(
        joined.is_ok(),
        "a listed refusal must leave the game slot free: {joined:?}"
    );
    accept.abort();
}

#[tokio::test]
async fn listed_addresses_are_refused_before_any_seat_or_status() {
    for (policy, expected) in [
        (
            policy_from("127.0.0.0/8 reason=test\n", None),
            "address_banned",
        ),
        (policy_from("", Some("10.0.0.0/8\n")), "address_not_allowed"),
    ] {
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
        let (policy_tx, policy_rx) = watch::channel(policy);
        server.set_access(policy_rx);
        let address = server.local_addr().unwrap();
        let accept = tokio::spawn(server.accept_loop());

        let mut fighter = hello(
            address,
            r#"{"type":"hello","role":"human","name":"Owner","gameplay_version":9,"geometry_version":2}"#,
        )
        .await;
        let reply = timeout(Duration::from_secs(2), fighter.next())
            .await
            .unwrap()
            .unwrap()
            .unwrap();
        assert_eq!(admission_code(reply), expected);
        let mut watcher = hello(
            address,
            r#"{"type":"hello","role":"spectator","name":"Watch","gameplay_version":9,"geometry_version":2}"#,
        )
        .await;
        let (code, reason) = closing_code(&mut watcher).await;
        assert_eq!((code.as_str(), reason.as_str()), (expected, expected));

        let mut tcp = tokio::net::TcpStream::connect(address).await.unwrap();
        tcp.write_all(b"GET /status HTTP/1.1\r\nHost: localhost\r\n\r\n")
            .await
            .unwrap();
        let mut buf = vec![0u8; 2048];
        let read = timeout(Duration::from_secs(7), tcp.read(&mut buf))
            .await
            .unwrap();
        let text = String::from_utf8_lossy(&buf[..read.unwrap_or(0)]).to_string();
        assert!(!text.starts_with("HTTP/1.1 200"), "{text}");
        assert!(commands.try_recv().is_err(), "no seat, no session");

        // The refused owner never consumed the lifetime run seat.
        policy_tx.send_replace(policy_from("", None));
        let mut owner = hello(
            address,
            r#"{"type":"hello","role":"human","name":"Owner","gameplay_version":9,"geometry_version":2}"#,
        )
        .await;
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
        accept.abort();
    }
}

#[tokio::test]
async fn a_new_ban_closes_a_live_session_and_an_unrelated_edit_does_not() {
    let (tx, mut commands) = mpsc::unbounded_channel();
    let mut server = NetServer::bind("127.0.0.1:0", tx).await.unwrap();
    let (policy_tx, policy_rx) = watch::channel(policy_from("", None));
    server.set_access(policy_rx);
    let address = server.local_addr().unwrap();
    let accept = tokio::spawn(server.accept_loop());
    let mut fighter = welcome_fighter(address, true).await;
    let GameCommand::Connected { id, .. } = next_command(&mut commands).await else {
        panic!("expected a connection");
    };
    policy_tx.send_replace(policy_from("203.0.113.7\n", None));
    assert!(
        timeout(Duration::from_millis(200), skip_seat_notes(&mut commands))
            .await
            .is_err(),
        "a ban on someone else leaves this session alone"
    );
    policy_tx.send_replace(policy_from("127.0.0.1 reason=reload\n", None));
    assert!(matches!(
        next_command(&mut commands).await,
        GameCommand::Disconnected { id: gone } if gone == id
    ));
    let (code, _) = closing_code(&mut fighter).await;
    assert_eq!(code, "address_banned");
    accept.abort();
}
