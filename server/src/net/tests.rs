use super::*;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::{TcpListener, TcpStream};
use tokio::time::{timeout, Duration};
use tokio_tungstenite::connect_async;

#[test]
fn an_older_client_is_sent_to_the_release_and_its_checksum() {
    let older = version_refusal("gameplay", 36, 37, 37).expect("older than the floor");
    match older {
        ServerMessage::Error { code, message } => {
            assert_eq!(code, "unsupported_gameplay");
            assert!(
                message.contains("requires gameplay version 37"),
                "{message}"
            );
            assert!(message.contains("update your client"), "{message}");
            assert!(message.contains(crate::protocol::RELEASES_URL), "{message}");
            assert!(message.contains("SHA256SUMS.txt"), "{message}");
        }
        other => panic!("expected an error: {other:?}"),
    }
    let geometry = version_refusal("geometry", 1, 2, 2).expect("older geometry");
    match geometry {
        ServerMessage::Error { code, message } => {
            assert_eq!(code, "unsupported_geometry");
            assert!(message.contains("SHA256SUMS.txt"), "{message}");
        }
        other => panic!("expected an error: {other:?}"),
    }
    let newer = version_refusal("gameplay", 38, 37, 37).expect("newer than this binary");
    match newer {
        ServerMessage::Error { code, message } => {
            assert_eq!(code, "unsupported_gameplay");
            assert!(message.contains("speaks gameplay version 37"), "{message}");
            assert!(!message.contains("SHA256SUMS.txt"), "{message}");
            assert!(
                !message.contains(crate::protocol::RELEASES_URL),
                "{message}"
            );
        }
        other => panic!("expected an error: {other:?}"),
    }
    assert!(version_refusal("gameplay", 37, 37, 37).is_none());
}

#[tokio::test]
async fn a_taken_port_names_the_address_and_the_next_bind() {
    let hold = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = hold.local_addr().unwrap();
    let (tx, _rx) = game_channel();
    let error = match NetServer::bind(&addr.to_string(), tx).await {
        Err(error) => error,
        Ok(_) => panic!("bind on a held port must fail"),
    };
    assert_eq!(error.kind(), std::io::ErrorKind::AddrInUse);
    let message = error.to_string();
    assert!(message.contains(&addr.to_string()), "{message}");
    assert!(message.contains("--bind 127.0.0.1:"), "{message}");
    assert!(
        message.contains(&format!("ss -ltnp 'sport = :{}'", addr.port())),
        "{message}"
    );
    let line = address_in_use_line(&error).expect("taken bind");
    assert_eq!(line, message);
}

#[tokio::test]
async fn accepted_socket_disables_nagle() {
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let port = listener.local_addr().unwrap().port();
    let connector =
        tokio::spawn(async move { TcpStream::connect(("127.0.0.1", port)).await.unwrap() });
    let (accepted, _) = listener.accept().await.unwrap();
    assert!(
        !accepted.nodelay().unwrap(),
        "a new socket still coalesces short writes"
    );
    disable_nagle(&accepted);
    assert!(
        accepted.nodelay().unwrap(),
        "an accepted game socket must send the snapshot tail immediately"
    );
    connector.abort();
}

#[tokio::test]
async fn automatic_admission_validates_before_reservation_and_keeps_watchers_open() {
    let (tx, mut commands) = game_channel();
    let mut server =
        NetServer::bind_with_requirements("127.0.0.1:0", tx, 2, crate::protocol::GAMEPLAY_VERSION)
            .await
            .unwrap();
    server.set_fighter_seats(
        Arc::new(Semaphore::new(0)),
        crate::protocol::GameMode::Sabotage,
    );
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
    let (tx, mut commands) = game_channel();
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
    let (tx, mut commands) = game_channel();
    let mut server =
        NetServer::bind_with_requirements("127.0.0.1:0", tx, 2, crate::protocol::GAMEPLAY_VERSION)
            .await
            .unwrap();
    server.set_fighter_seats(
        Arc::new(Semaphore::new(0)),
        crate::protocol::GameMode::Sabotage,
    );
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

/// Accepts every frame at once and keeps it, in order.
#[derive(Default)]
struct RecordingSink(Vec<Message>);

impl futures_util::Sink<Message> for RecordingSink {
    type Error = std::io::Error;

    fn poll_ready(
        self: std::pin::Pin<&mut Self>,
        _: &mut std::task::Context<'_>,
    ) -> std::task::Poll<Result<(), Self::Error>> {
        std::task::Poll::Ready(Ok(()))
    }

    fn start_send(mut self: std::pin::Pin<&mut Self>, frame: Message) -> Result<(), Self::Error> {
        self.0.push(frame);
        Ok(())
    }

    fn poll_flush(
        self: std::pin::Pin<&mut Self>,
        _: &mut std::task::Context<'_>,
    ) -> std::task::Poll<Result<(), Self::Error>> {
        std::task::Poll::Ready(Ok(()))
    }

    fn poll_close(
        self: std::pin::Pin<&mut Self>,
        _: &mut std::task::Context<'_>,
    ) -> std::task::Poll<Result<(), Self::Error>> {
        std::task::Poll::Ready(Ok(()))
    }
}

/// Consecutive worlds of a seeded fight, encoded as the tick encodes them.
fn fought_worlds(count: usize) -> Vec<Arc<Broadcast>> {
    let mut session = crate::session::GameSession::with_map(crate::sim::MapKind::ArenaDuel, false);
    session.state.seed(42);
    session.state.use_replay_ids();
    session.state.config = crate::bench::fixture_config();
    session.spawn_bots(4);
    let mut encoder = crate::protocol::delta::WorldEncoder::default();
    let mut worlds = Vec::new();
    while worlds.len() < count {
        let messages = session.tick_messages(crate::run::TICK.as_secs_f32());
        for broadcast in Broadcast::encode_tick(messages, &mut encoder).unwrap() {
            if broadcast.world().is_some() {
                worlds.push(broadcast);
            }
        }
    }
    worlds
}

/// What a writer puts on its socket for `frames`, fed one at a time so no
/// queued world replaces another.
async fn written(frames: Vec<Outbound>, deltas: bool) -> Vec<String> {
    let (tx, rx) = outbound_channel(4);
    let (shutdown, _) = tokio::sync::watch::channel(StopSignal::Open);
    let (_stop, stop) = tokio::sync::oneshot::channel();
    let probe = Arc::new(WriterProbe::default());
    let writer = tokio::spawn(run_outbound_writer(
        RecordingSink::default(),
        rx,
        shutdown,
        WriterPolicy {
            deltas,
            ..limits(Duration::from_secs(1))
        },
        Duration::from_secs(60),
        stop,
        spectator_meters(&probe),
    ));
    for frame in frames {
        tx.try_send(frame).unwrap();
        timeout(Duration::from_secs(1), async {
            while tx.depth() > 0 {
                tokio::task::yield_now().await;
            }
        })
        .await
        .unwrap();
    }
    drop(tx);
    let RecordingSink(sent) = writer.await.unwrap();
    sent.into_iter()
        .map(|frame| match frame {
            Message::Text(text) => text,
            other => panic!("unexpected frame {other:?}"),
        })
        .collect()
}

#[tokio::test]
async fn a_writer_sends_a_delta_only_against_the_world_its_reader_holds() {
    let worlds = fought_worlds(5);
    let delta_of = |index: usize| worlds[index].world().unwrap().delta.as_ref().unwrap();
    let map = crate::sim::GameState::with_map(crate::sim::MapKind::ArenaDuel, false).map_info();
    let shared = |index: usize| Outbound::from(Arc::clone(&worlds[index]));
    // 0 whole, 1 against 0, then a map: 2 whole, then 3 skipped (a replaced
    // world), so 4 goes whole as well.
    let sent = written(
        vec![
            shared(0),
            shared(1),
            map.clone().into(),
            shared(2),
            shared(4),
        ],
        true,
    )
    .await;
    assert_eq!(
        sent,
        vec![
            worlds[0].text().to_owned(),
            delta_of(1).text.clone(),
            serde_json::to_string(&map).unwrap(),
            worlds[2].text().to_owned(),
            worlds[4].text().to_owned(),
        ]
    );
    assert!(delta_of(1).text.len() < worlds[1].text().len());
    // Its reader rebuilds every world exactly.
    let mut reader = crate::protocol::WorldReader::new();
    let read: Vec<ServerMessage> = sent.iter().map(|text| reader.read(text).unwrap()).collect();
    for (index, world) in [(1, 1), (3, 2), (4, 4)] {
        assert_eq!(
            serde_json::to_string(&read[index]).unwrap(),
            worlds[world].text()
        );
    }
    // A targeted world is not the base a shared delta names.
    let sent = written(
        vec![shared(0), worlds[1].message().clone().into(), shared(2)],
        true,
    )
    .await;
    assert_eq!(sent[2], worlds[2].text());
    // Consecutive shared worlds go as deltas.
    let sent = written(vec![shared(0), shared(1), shared(2)], true).await;
    assert_eq!(sent[2], delta_of(2).text);
}

#[tokio::test]
async fn a_reader_below_the_delta_contract_gets_every_world_whole() {
    let worlds = fought_worlds(3);
    let frames = worlds
        .iter()
        .map(|world| Outbound::from(Arc::clone(world)))
        .collect();
    let sent = written(frames, false).await;
    let whole: Vec<String> = worlds.iter().map(|world| world.text().to_owned()).collect();
    assert_eq!(sent, whole);
    // A world encoded without a tick encoder has no delta at all.
    let alone = Broadcast::encode(worlds[1].message().clone()).unwrap();
    assert!(alone.world().unwrap().delta.is_none());
}

#[tokio::test]
async fn writer_sends_a_shared_broadcast_unchanged_and_encodes_only_targeted_messages() {
    let (tx, rx) = outbound_channel(4);
    let snapshot = ServerMessage::Snapshot(crate::sim::GameState::new().snapshot());
    let broadcast = Broadcast::encode(snapshot.clone()).unwrap();
    let private = ServerMessage::Error {
        code: "private".into(),
        message: "only this socket".into(),
    };
    tx.try_send(Arc::clone(&broadcast)).unwrap();
    tx.try_send(private.clone()).unwrap();
    drop(tx);
    let probe = Arc::new(WriterProbe::default());
    let (shutdown, _) = tokio::sync::watch::channel(StopSignal::Open);
    let (_stop, stop) = tokio::sync::oneshot::channel();
    let RecordingSink(sent) = run_outbound_writer(
        RecordingSink::default(),
        rx,
        shutdown,
        limits(Duration::from_secs(1)),
        Duration::from_secs(60),
        stop,
        WriterMeters {
            traffic: crate::metrics::ClientTraffic::new(Role::Spectator, Default::default()),
            probe: Some(Arc::clone(&probe)),
        },
    )
    .await;
    // The wire is unchanged: the shared payload is the message's own encoding.
    assert_eq!(
        sent,
        vec![
            Message::Text(serde_json::to_string(&snapshot).unwrap()),
            Message::Text(serde_json::to_string(&private).unwrap()),
        ]
    );
    let report = probe.report();
    assert_eq!(report.shared_frames, 1);
    assert_eq!(report.shared_bytes, broadcast.text().len() as u64);
    assert_eq!(report.encodes, 1);
    assert_eq!(report.encode_ms.count, 1);
    assert_eq!(report.residence_ms.count, 2);
    assert_eq!(report.send_ms.count, 2);
    // Neither the queue nor the writer keeps the payload once it is sent.
    assert_eq!(Arc::strong_count(&broadcast), 1);
    probe.reset();
    assert_eq!(probe.report().residence_ms.count, 0);
}

#[tokio::test]
async fn cancelled_stalled_writer_releases_every_shared_payload() {
    let (tx, rx) = outbound_channel(4);
    let broadcast = Broadcast::encode(ServerMessage::Event(crate::protocol::GameEvent::Respawn {
        player: "Watcher".into(),
    }))
    .unwrap();
    // One copy reaches the stalled send; the other waits in the queue.
    tx.try_send(Arc::clone(&broadcast)).unwrap();
    tx.try_send(Arc::clone(&broadcast)).unwrap();
    let (shutdown, _) = tokio::sync::watch::channel(StopSignal::Open);
    let (_stop, stop) = tokio::sync::oneshot::channel();
    let writer = tokio::spawn(run_outbound_writer(
        StalledSink,
        rx,
        shutdown,
        limits(Duration::from_secs(60)),
        Duration::from_secs(60),
        stop,
        WriterMeters {
            traffic: crate::metrics::ClientTraffic::new(Role::Spectator, Default::default()),
            probe: None,
        },
    ));
    timeout(Duration::from_secs(1), async {
        while tx.depth() != 1 {
            tokio::task::yield_now().await;
        }
    })
    .await
    .unwrap();
    writer.abort();
    assert!(writer.await.is_err_and(|error| error.is_cancelled()));
    assert_eq!(tx.try_send(Arc::clone(&broadcast)), Err(QueueError::Closed));
    assert_eq!(Arc::strong_count(&broadcast), 1);
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
    // Nothing is queued: the stalled send is the keepalive ping, which has
    // the plain send timeout rather than a frame age.
    let (tx, rx) = outbound_channel(1);
    let (shutdown, mut changed) = tokio::sync::watch::channel(StopSignal::Open);
    let (_stop, stop) = tokio::sync::oneshot::channel();
    let probe = Arc::new(WriterProbe::default());
    probe.reset();
    let writer = tokio::spawn(run_outbound_writer(
        StalledSink,
        rx,
        shutdown,
        limits(Duration::from_millis(20)),
        Duration::from_millis(5),
        stop,
        WriterMeters {
            traffic: crate::metrics::ClientTraffic::new(Role::Spectator, Default::default()),
            probe: Some(Arc::clone(&probe)),
        },
    ));
    timeout(Duration::from_secs(1), changed.changed())
        .await
        .unwrap()
        .unwrap();
    assert_eq!(*changed.borrow_and_update(), StopSignal::Quiet);
    writer.await.unwrap();
    // The measured window records when the send gave up.
    let failures = probe.report().send_failures_ms;
    assert_eq!(failures.len(), 1);
    assert!(failures[0] >= 20.0, "{failures:?}");
    assert_eq!(probe.report().stale_closes, 0);
    probe.reset();
    assert!(probe.report().send_failures_ms.is_empty());
    drop(tx);
}

/// Writer limits for tests that are not about staleness.
fn limits(send_timeout: Duration) -> WriterPolicy {
    WriterPolicy {
        send_timeout,
        stale_after: Duration::from_secs(60),
        read_behind_after: Duration::from_secs(60),
        deltas: false,
    }
}

fn spectator_meters(probe: &Arc<WriterProbe>) -> WriterMeters {
    WriterMeters {
        traffic: crate::metrics::ClientTraffic::new(Role::Spectator, Default::default()),
        probe: Some(Arc::clone(probe)),
    }
}

fn reliable_fact(index: u32) -> ServerMessage {
    ServerMessage::Event(crate::protocol::GameEvent::Respawn {
        player: format!("Fighter {index}"),
    })
}

/// A peer that takes one frame per `every`, like a reader on a link of that
/// rate, and counts the text frames it took.
struct PacedSink {
    every: Duration,
    next: std::pin::Pin<Box<tokio::time::Sleep>>,
    taken: Arc<std::sync::atomic::AtomicUsize>,
}

impl PacedSink {
    fn new(every: Duration) -> (Self, Arc<std::sync::atomic::AtomicUsize>) {
        let taken = Arc::new(std::sync::atomic::AtomicUsize::new(0));
        (
            Self {
                every,
                next: Box::pin(tokio::time::sleep(Duration::ZERO)),
                taken: Arc::clone(&taken),
            },
            taken,
        )
    }
}

impl futures_util::Sink<Message> for PacedSink {
    type Error = std::io::Error;

    fn poll_ready(
        mut self: std::pin::Pin<&mut Self>,
        cx: &mut std::task::Context<'_>,
    ) -> std::task::Poll<Result<(), Self::Error>> {
        std::future::Future::poll(self.next.as_mut(), cx).map(Ok)
    }

    fn start_send(mut self: std::pin::Pin<&mut Self>, frame: Message) -> Result<(), Self::Error> {
        if matches!(frame, Message::Text(_)) {
            self.taken.fetch_add(1, std::sync::atomic::Ordering::SeqCst);
        }
        let next = tokio::time::Instant::now() + self.every;
        self.next.as_mut().reset(next);
        Ok(())
    }

    fn poll_flush(
        self: std::pin::Pin<&mut Self>,
        _: &mut std::task::Context<'_>,
    ) -> std::task::Poll<Result<(), Self::Error>> {
        std::task::Poll::Ready(Ok(()))
    }

    fn poll_close(
        self: std::pin::Pin<&mut Self>,
        _: &mut std::task::Context<'_>,
    ) -> std::task::Poll<Result<(), Self::Error>> {
        std::task::Poll::Ready(Ok(()))
    }
}

#[tokio::test]
async fn a_frame_queued_past_its_age_closes_the_writer_before_it_is_sent() {
    let (tx, rx) = outbound_channel(4);
    tx.try_send(reliable_fact(0)).unwrap();
    // The writer reaches the frame only after it has gone stale.
    tokio::time::sleep(Duration::from_millis(60)).await;
    let (shutdown, mut changed) = tokio::sync::watch::channel(StopSignal::Open);
    let (_stop, stop) = tokio::sync::oneshot::channel();
    let probe = Arc::new(WriterProbe::default());
    probe.reset();
    let RecordingSink(sent) = run_outbound_writer(
        RecordingSink::default(),
        rx,
        shutdown,
        WriterPolicy {
            send_timeout: Duration::from_secs(60),
            stale_after: Duration::from_millis(50),
            read_behind_after: Duration::from_secs(60),
            deltas: false,
        },
        Duration::from_secs(60),
        stop,
        spectator_meters(&probe),
    )
    .await;
    assert!(sent.is_empty(), "a stale frame is never sent: {sent:?}");
    assert_eq!(*changed.borrow_and_update(), StopSignal::Quiet);
    let report = probe.report();
    assert_eq!(report.stale_closes, 1);
    assert_eq!(report.send_failures_ms.len(), 1);
    // The queue closed with its writer, so the tick stops feeding it.
    assert_eq!(tx.try_send(reliable_fact(1)), Err(QueueError::Closed));
}

#[tokio::test]
async fn a_blocked_send_closes_when_its_frame_goes_stale_not_at_the_send_timeout() {
    let (tx, rx) = outbound_channel(4);
    tx.try_send(reliable_fact(0)).unwrap();
    let (shutdown, mut changed) = tokio::sync::watch::channel(StopSignal::Open);
    let (_stop, stop) = tokio::sync::oneshot::channel();
    let probe = Arc::new(WriterProbe::default());
    probe.reset();
    let started = std::time::Instant::now();
    let writer = tokio::spawn(run_outbound_writer(
        StalledSink,
        rx,
        shutdown,
        WriterPolicy {
            send_timeout: Duration::from_secs(60),
            stale_after: Duration::from_millis(40),
            read_behind_after: Duration::from_secs(60),
            deltas: false,
        },
        Duration::from_secs(60),
        stop,
        spectator_meters(&probe),
    ));
    timeout(Duration::from_secs(5), changed.changed())
        .await
        .unwrap()
        .unwrap();
    assert_eq!(*changed.borrow_and_update(), StopSignal::Quiet);
    writer.await.unwrap();
    let elapsed = started.elapsed();
    assert!(elapsed >= Duration::from_millis(40), "{elapsed:?}");
    let report = probe.report();
    assert_eq!(report.stale_closes, 1);
    assert_eq!(report.send_failures_ms.len(), 1);
    drop(tx);
}

/// Queue a reliable fact every `every` until the writer closes or `window`
/// ends. Returns whether the queue was closed and how many were queued.
async fn produce(tx: &WsTx, every: Duration, window: Duration) -> (bool, u32) {
    let end = tokio::time::Instant::now() + window;
    let mut queued = 0;
    let mut cadence = tokio::time::interval(every);
    while tokio::time::Instant::now() < end {
        cadence.tick().await;
        match tx.try_send(reliable_fact(queued)) {
            Ok(_) => queued += 1,
            Err(QueueError::Closed) => return (true, queued),
            Err(QueueError::Full) => panic!("the queue filled before the writer closed"),
        }
    }
    (false, queued)
}

#[tokio::test]
async fn a_reader_slower_than_the_tick_is_closed_once_its_backlog_goes_stale() {
    let (tx, rx) = outbound_channel(256);
    let (shutdown, _) = tokio::sync::watch::channel(StopSignal::Open);
    let (_stop, stop) = tokio::sync::oneshot::channel();
    let probe = Arc::new(WriterProbe::default());
    probe.reset();
    // Facts every 20 ms, a peer that takes one every 60 ms: the backlog, and
    // the age of its oldest frame, grow without bound.
    let (sink, taken) = PacedSink::new(Duration::from_millis(60));
    let writer = tokio::spawn(run_outbound_writer(
        sink,
        rx,
        shutdown,
        WriterPolicy {
            send_timeout: Duration::from_secs(60),
            stale_after: Duration::from_millis(300),
            read_behind_after: Duration::from_secs(60),
            deltas: false,
        },
        Duration::from_secs(60),
        stop,
        spectator_meters(&probe),
    ));
    let (closed, queued) = produce(&tx, Duration::from_millis(20), Duration::from_secs(4)).await;
    assert!(closed, "the slow reader was never closed");
    timeout(Duration::from_secs(1), writer)
        .await
        .unwrap()
        .unwrap();
    let delivered = taken.load(std::sync::atomic::Ordering::SeqCst);
    assert!(
        delivered > 0 && delivered < queued as usize,
        "{delivered} of {queued}"
    );
    assert_eq!(probe.report().stale_closes, 1);
}

#[tokio::test]
async fn a_slow_but_sufficient_link_is_never_closed() {
    let (tx, rx) = outbound_channel(64);
    let (shutdown, changed) = tokio::sync::watch::channel(StopSignal::Open);
    let (stop_writer, stop) = tokio::sync::oneshot::channel();
    let probe = Arc::new(WriterProbe::default());
    probe.reset();
    // Every frame takes most of a tick to leave, but the link keeps up.
    let (sink, taken) = PacedSink::new(Duration::from_millis(35));
    let writer = tokio::spawn(run_outbound_writer(
        sink,
        rx,
        shutdown,
        WriterPolicy {
            send_timeout: Duration::from_secs(60),
            stale_after: Duration::from_millis(300),
            read_behind_after: Duration::from_secs(60),
            deltas: false,
        },
        Duration::from_secs(60),
        stop,
        spectator_meters(&probe),
    ));
    let (closed, queued) =
        produce(&tx, Duration::from_millis(50), Duration::from_millis(1500)).await;
    assert!(!closed, "a reader that keeps up was closed");
    assert_eq!(*changed.borrow(), StopSignal::Open);
    timeout(Duration::from_secs(1), async {
        while taken.load(std::sync::atomic::Ordering::SeqCst) < queued as usize {
            tokio::time::sleep(Duration::from_millis(5)).await;
        }
    })
    .await
    .unwrap();
    let _ = stop_writer.send(());
    timeout(Duration::from_secs(1), writer)
        .await
        .unwrap()
        .unwrap();
    let report = probe.report();
    assert_eq!(report.stale_closes, 0);
    assert!(report.send_failures_ms.is_empty());
}

/// A peer that takes every frame at once and, while `answering`, answers
/// each ping the way a reading client does.
struct PingAnswerer {
    traffic: Arc<crate::metrics::ClientTraffic>,
    answering: Arc<std::sync::atomic::AtomicBool>,
}

impl futures_util::Sink<Message> for PingAnswerer {
    type Error = std::io::Error;

    fn poll_ready(
        self: std::pin::Pin<&mut Self>,
        _: &mut std::task::Context<'_>,
    ) -> std::task::Poll<Result<(), Self::Error>> {
        std::task::Poll::Ready(Ok(()))
    }

    fn start_send(self: std::pin::Pin<&mut Self>, frame: Message) -> Result<(), Self::Error> {
        if let Message::Ping(payload) = frame {
            if self.answering.load(std::sync::atomic::Ordering::SeqCst) {
                self.traffic.pong(&payload);
            }
        }
        Ok(())
    }

    fn poll_flush(
        self: std::pin::Pin<&mut Self>,
        _: &mut std::task::Context<'_>,
    ) -> std::task::Poll<Result<(), Self::Error>> {
        std::task::Poll::Ready(Ok(()))
    }

    fn poll_close(
        self: std::pin::Pin<&mut Self>,
        _: &mut std::task::Context<'_>,
    ) -> std::task::Poll<Result<(), Self::Error>> {
        std::task::Poll::Ready(Ok(()))
    }
}

#[tokio::test]
async fn a_reader_that_stops_answering_pings_is_closed_once_it_falls_behind() {
    let (tx, rx) = outbound_channel(4);
    let (shutdown, mut changed) = tokio::sync::watch::channel(StopSignal::Open);
    let (_stop, stop) = tokio::sync::oneshot::channel();
    let probe = Arc::new(WriterProbe::default());
    probe.reset();
    let traffic = crate::metrics::ClientTraffic::new(Role::Spectator, Default::default());
    let answering = Arc::new(std::sync::atomic::AtomicBool::new(true));
    let writer = tokio::spawn(run_outbound_writer(
        PingAnswerer {
            traffic: Arc::clone(&traffic),
            answering: Arc::clone(&answering),
        },
        rx,
        shutdown,
        WriterPolicy {
            read_behind_after: Duration::from_millis(150),
            ..limits(Duration::from_secs(60))
        },
        Duration::from_millis(10),
        stop,
        WriterMeters {
            traffic: Arc::clone(&traffic),
            probe: Some(Arc::clone(&probe)),
        },
    ));
    // A reader that answers every ping stays, however long it is open.
    tokio::time::sleep(Duration::from_millis(400)).await;
    assert_eq!(*changed.borrow(), StopSignal::Open);
    assert_eq!(probe.report().behind_closes, 0);
    assert!(
        traffic.ping_ms().is_some(),
        "its answers time the round trip"
    );
    // Once it stops reading, the oldest unanswered ping ages past the bound.
    answering.store(false, std::sync::atomic::Ordering::SeqCst);
    let stopped = std::time::Instant::now();
    timeout(Duration::from_secs(5), changed.changed())
        .await
        .unwrap()
        .unwrap();
    assert_eq!(*changed.borrow_and_update(), StopSignal::Quiet);
    assert!(stopped.elapsed() >= Duration::from_millis(140));
    writer.await.unwrap();
    let report = probe.report();
    assert_eq!(report.behind_closes, 1);
    assert_eq!(report.stale_closes, 0);
    assert_eq!(report.send_failures_ms.len(), 1);
    drop(tx);
}

#[tokio::test]
async fn accepted_game_socket_bounds_its_send_buffer() {
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let port = listener.local_addr().unwrap().port();
    let connector =
        tokio::spawn(async move { TcpStream::connect(("127.0.0.1", port)).await.unwrap() });
    let (accepted, _) = listener.accept().await.unwrap();
    bound_send_buffer(&accepted);
    let size = socket2::SockRef::from(&accepted)
        .send_buffer_size()
        .unwrap();
    // Linux reports double the request for its own bookkeeping; others report
    // the request. Either way it is far below the 4 MiB autotuning ceiling.
    assert!(
        (SEND_BUFFER_BYTES..=2 * SEND_BUFFER_BYTES).contains(&size),
        "{size}"
    );
    connector.abort();
}

#[tokio::test]
async fn raised_geometry_rejects_legacy_roles_before_welcome_or_join() {
    let (tx, mut commands) = game_channel();
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
    // This binary speaks geometry 2. A newer claim is not a compatible client.
    for (version, admitted) in [(2, true), (3, false)] {
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
        let message = serde_json::from_str::<ServerMessage>(reply.to_text().unwrap()).unwrap();
        if admitted {
            assert!(matches!(
                message,
                ServerMessage::Welcome {
                    player_id: Some(_),
                    ..
                }
            ));
        } else {
            assert!(
                matches!(&message, ServerMessage::Error { code, message } if code == "unsupported_geometry" && message.contains("speaks geometry version 2")),
                "{version}: {message:?}"
            );
            assert!(commands.try_recv().is_err());
            continue;
        }
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

#[tokio::test]
async fn a_hello_newer_than_this_binary_is_refused_on_a_floor_listener() {
    let (tx, mut commands) = game_channel();
    let server = NetServer::bind_with_requirements("127.0.0.1:0", tx, 1, 1)
        .await
        .unwrap();
    let address = server.local_addr().unwrap();
    let accept = tokio::spawn(server.accept_loop());
    let too_new = crate::protocol::GAMEPLAY_VERSION + 1;
    for (gameplay, geometry, code) in [
        (too_new, 1, "unsupported_gameplay"),
        (
            1,
            crate::protocol::GEOMETRY_VERSION + 1,
            "unsupported_geometry",
        ),
    ] {
        let (mut socket, _) = connect_async(format!("ws://{address}")).await.unwrap();
        socket
            .send(Message::Text(
                serde_json::json!({
                    "type":"hello", "role":"human", "name":"Future",
                    "gameplay_version": gameplay, "geometry_version": geometry,
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
        assert!(
            matches!(&message, ServerMessage::Error { code: got, message } if got == code && message.contains("speaks")),
            "{gameplay}/{geometry}: {message:?}"
        );
        assert!(commands.try_recv().is_err());
    }
    let (mut current, _) = connect_async(format!("ws://{address}")).await.unwrap();
    current
        .send(Message::Text(
            serde_json::json!({
                "type":"hello", "role":"spectator", "name":"Legacy",
                "gameplay_version": 1, "geometry_version": 1,
            })
            .to_string(),
        ))
        .await
        .unwrap();
    let reply = timeout(Duration::from_secs(2), current.next())
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
    accept.abort();
}

#[tokio::test]
async fn human_socket_drops_server_aim_and_an_agent_keeps_it() {
    let (tx, mut commands) = game_channel();
    let mut server = NetServer::bind("127.0.0.1:0", tx).await.unwrap();
    server.require_client_aim();
    let address = server.local_addr().unwrap();
    let accept = tokio::spawn(server.accept_loop());
    let look = r#"{"player_id":"00000000-0000-0000-0000-000000000001"}"#;
    for (role, dropped) in [("human", true), ("agent", false)] {
        let mut socket = hello(
            address,
            &format!(r#"{{"type":"hello","role":"{role}","name":"Aim"}}"#),
        )
        .await;
        let welcome = timeout(Duration::from_secs(2), socket.next())
            .await
            .unwrap()
            .unwrap()
            .unwrap();
        assert!(matches!(
            serde_json::from_str::<ServerMessage>(welcome.to_text().unwrap()).unwrap(),
            ServerMessage::Welcome { .. }
        ));
        assert!(matches!(
            timeout(Duration::from_secs(2), skip_seat_notes(&mut commands))
                .await
                .unwrap(),
            Some(GameCommand::Connected { .. })
        ));
        socket
            .send(Message::Text(format!(
                r#"{{"type":"action","fire":true,"yaw":1.25,"look_at":{look}}}"#
            )))
            .await
            .unwrap();
        let command = timeout(Duration::from_secs(2), skip_seat_notes(&mut commands))
            .await
            .unwrap()
            .unwrap();
        let GameCommand::Action { action, .. } = command else {
            panic!("expected the action");
        };
        assert_eq!(action.look_at.is_none(), dropped, "{role}");
        assert_eq!(action.yaw, Some(1.25));
        assert!(action.fire);
        socket.close(None).await.unwrap();
        for _ in 0..4 {
            match timeout(Duration::from_secs(2), skip_seat_notes(&mut commands)).await {
                Ok(Some(GameCommand::Disconnected { .. })) => break,
                Ok(Some(_)) => continue,
                _ => break,
            }
        }
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
async fn a_status_line_that_arrives_after_connect_is_still_status() {
    let (tx, _commands) = game_channel();
    let mut server = NetServer::bind("127.0.0.1:0", tx).await.unwrap();
    server.share_status(std::sync::Arc::new(tokio::sync::RwLock::new(
        crate::protocol::LiveStatus {
            schema_version: 2,
            kind: "arena".into(),
            map: "Arena Duel".into(),
            ..crate::protocol::LiveStatus::default()
        },
    )));
    let address = server.local_addr().unwrap();
    let accept = tokio::spawn(server.accept_loop());

    let mut tcp = tokio::net::TcpStream::connect(address).await.unwrap();
    tokio::time::sleep(Duration::from_millis(400)).await;
    tcp.write_all(b"GET /status HTTP/1.1\r\nHost: localhost\r\n\r\n")
        .await
        .unwrap();
    let mut buf = vec![0u8; 2048];
    let n = timeout(Duration::from_secs(2), tcp.read(&mut buf))
        .await
        .expect("delayed status probe timed out")
        .expect("delayed status probe read");
    let text = String::from_utf8_lossy(&buf[..n]);
    assert!(
        text.starts_with("HTTP/1.1 200"),
        "a pause before the request must stay a status probe, not a websocket: {text}"
    );
    accept.abort();
}

#[tokio::test]
async fn status_get_reports_the_match_without_taking_a_slot() {
    let (tx, mut commands) = game_channel();
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
async fn a_busy_status_lock_answers_503_and_not_schema_one() {
    let (tx, _commands) = game_channel();
    let mut server = NetServer::bind("127.0.0.1:0", tx).await.unwrap();
    let status = std::sync::Arc::new(tokio::sync::RwLock::new(crate::protocol::LiveStatus {
        schema_version: 2,
        kind: "arena".into(),
        map: "Arena Duel".into(),
        ..crate::protocol::LiveStatus::default()
    }));
    server.share_status(std::sync::Arc::clone(&status));
    let address = server.local_addr().unwrap();
    let accept = tokio::spawn(server.accept_loop());
    let _held = status.write().await;

    let mut tcp = tokio::net::TcpStream::connect(address).await.unwrap();
    tcp.write_all(b"GET /status HTTP/1.1\r\nHost: localhost\r\n\r\n")
        .await
        .unwrap();
    let mut buf = Vec::new();
    let mut tmp = [0u8; 512];
    loop {
        let n = timeout(Duration::from_secs(2), tcp.read(&mut tmp))
            .await
            .expect("busy status timeout")
            .expect("busy status read");
        if n == 0 {
            break;
        }
        buf.extend_from_slice(&tmp[..n]);
    }
    let text = String::from_utf8_lossy(&buf);
    assert!(text.starts_with("HTTP/1.1 503"), "{text}");
    assert!(text.contains("\"busy\":true"), "{text}");
    assert!(!text.contains("\"schema_version\":1"), "{text}");
    assert!(!text.contains("Arena Duel"), "{text}");
    drop(_held);

    let mut again = tokio::net::TcpStream::connect(address).await.unwrap();
    again
        .write_all(b"GET /status HTTP/1.1\r\nHost: localhost\r\n\r\n")
        .await
        .unwrap();
    let mut recovered = vec![0u8; 2048];
    let n = timeout(Duration::from_secs(2), again.read(&mut recovered))
        .await
        .unwrap()
        .unwrap();
    let recovered = String::from_utf8_lossy(&recovered[..n]);
    assert!(recovered.starts_with("HTTP/1.1 200"), "{recovered}");
    let live: crate::protocol::LiveStatus =
        serde_json::from_str(recovered.split("\r\n\r\n").nth(1).unwrap()).unwrap();
    assert_eq!(live.map, "Arena Duel");
    assert_eq!(live.schema_version, 2);
    accept.abort();
}

#[tokio::test]
async fn status_reads_stop_at_their_own_cap_and_leave_game_slots_free() {
    let (tx, mut commands) = game_channel();
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
    // The server closes without reading the request. Linux and Windows often
    // report that as an empty read. macOS reports the unread close as a reset.
    match read.expect("a capped status probe closes") {
        Ok(0) => {}
        Err(error)
            if matches!(
                error.kind(),
                std::io::ErrorKind::ConnectionReset | std::io::ErrorKind::ConnectionAborted
            ) => {}
        other => panic!("the extra status probe is closed: {other:?} {buf:?}"),
    }

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
    let (tx, _commands) = game_channel();
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
    let (tx, mut commands) = game_channel();
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
    let (tx, mut commands) = game_channel();
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
    let (tx, mut commands) = game_channel();
    let mut server = NetServer::bind("127.0.0.1:0", tx).await.unwrap();
    server.tighten_admission(24, 17, Duration::from_secs(2), Duration::from_secs(2));
    let address = server.local_addr().unwrap();
    let accept = tokio::spawn(server.accept_loop());
    let mut held = Vec::new();
    for _ in 0..16 {
        held.push(welcome_fighter(address, false).await);
    }
    held.push(welcome_spectator(address).await);
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
    let (tx, mut commands) = game_channel();
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
    let (tx, mut commands) = game_channel();
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
    let (tx, mut commands) = game_channel();
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
    let (tx, mut commands) = game_channel();
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
        let (tx, _) = game_channel();
        let result = NetServer::bind_with_geometry("127.0.0.1:0", tx, version).await;
        assert!(matches!(result, Err(error) if error.kind() == std::io::ErrorKind::InvalidInput));
    }
}

#[tokio::test]
async fn solo_run_admission_reserves_one_lifetime_seat_and_spectators_cannot_continue() {
    let (tx, mut commands) = game_channel();
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
    let (tx, mut commands) = game_channel();
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
    let (tx, mut commands) = game_channel();
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
    let (tx, mut commands) = game_channel();
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
    let (tx, mut commands) = game_channel();
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
    let (tx, mut commands) = game_channel();
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
    let (tx, mut commands) = game_channel();
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
        &crate::net::Broadcast::copies(&[ServerMessage::Snapshot(session.state.snapshot())]),
        &std::collections::HashSet::new(),
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

async fn next_command(commands: &mut mpsc::Receiver<GameCommand>) -> GameCommand {
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
    let (tx, mut commands) = game_channel();
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
    let version = timeout(Duration::from_secs(2), commands.recv())
        .await
        .unwrap()
        .unwrap();
    let GameCommand::NoteClientVersion {
        client_id: noted_id,
        gameplay_version,
    } = version
    else {
        panic!("the desk hears the client version before the join");
    };
    assert_eq!(noted_id, client_id);
    // This hello omits gameplay_version, which the server reads as legacy 1.
    assert_eq!(gameplay_version, crate::protocol::legacy_gameplay_version());
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
    let (tx, mut commands) = game_channel();
    let mut server = NetServer::bind("127.0.0.1:0", tx).await.unwrap();
    server.tighten_session(quick_limits());
    let address = server.local_addr().unwrap();
    let clients = server.clients.clone();
    let accept = tokio::spawn(server.accept_loop());
    let mut watcher = welcome_spectator(address).await;
    let GameCommand::Connected { id: watcher_id, .. } = next_command(&mut commands).await else {
        panic!("expected a connection");
    };
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
    // Each answer timed the round trip, which a loopback keeps under a beat.
    let ping = clients
        .lock()
        .await
        .iter()
        .find(|client| client.id == watcher_id)
        .and_then(|client| client.traffic().ping_ms());
    assert!(
        ping.is_some_and(|ms| ms < 500),
        "the pong timed the session: {ping:?}"
    );
    accept.abort();
}

#[tokio::test]
async fn silent_fighter_is_dropped_as_idle_and_keeps_a_resumable_pawn() {
    let (tx, mut commands) = game_channel();
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
    let (tx, mut commands) = game_channel();
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
    let (tx, mut commands) = game_channel();
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
    let (tx, mut commands) = game_channel();
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
    let (tx, _commands) = game_channel();
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
        let (tx, mut commands) = game_channel();
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
    let (tx, mut commands) = game_channel();
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

/// A Duel listener with `free` open fighter seats and, when `held`, the next
/// seat held for token "c0ffee" until `lapse` from now.
async fn duel_listener(
    free: usize,
    held: Option<Duration>,
) -> (
    std::net::SocketAddr,
    Arc<Semaphore>,
    crate::session::queue::SeatHolds,
    mpsc::Receiver<GameCommand>,
    tokio::task::JoinHandle<()>,
) {
    let (tx, commands) = game_channel();
    let mut server =
        NetServer::bind_with_requirements("127.0.0.1:0", tx, 2, crate::protocol::GAMEPLAY_VERSION)
            .await
            .unwrap();
    let slots = Arc::new(Semaphore::new(free));
    server.set_fighter_seats(Arc::clone(&slots), crate::protocol::GameMode::Duel);
    let holds = crate::session::queue::SeatHolds::default();
    if let Some(lapse) = held {
        crate::session::queue::place_hold(
            &holds,
            "c0ffee".into(),
            std::time::Instant::now() + lapse,
        );
    }
    server.set_seat_holds(Arc::clone(&holds));
    let address = server.local_addr().unwrap();
    let accept = tokio::spawn(server.accept_loop());
    (address, slots, holds, commands, accept)
}

async fn duel_hello(address: std::net::SocketAddr, seat: Option<&str>) -> ServerMessage {
    let mut hello = serde_json::json!({"type":"hello", "role":"human", "name":"Next", "geometry_version":2, "gameplay_version":crate::protocol::GAMEPLAY_VERSION});
    if let Some(seat) = seat {
        hello["seat"] = serde_json::json!(seat);
    }
    let (mut socket, _) = connect_async(format!("ws://{address}")).await.unwrap();
    socket.send(Message::Text(hello.to_string())).await.unwrap();
    loop {
        let frame = timeout(Duration::from_secs(5), socket.next())
            .await
            .unwrap()
            .unwrap()
            .unwrap();
        if let Message::Text(text) = frame {
            return serde_json::from_str(&text).unwrap();
        }
    }
}

fn held_now(holds: &crate::session::queue::SeatHolds) -> bool {
    crate::session::queue::admit(holds, None, std::time::Instant::now())
        == crate::session::queue::Admit::Held
}

#[tokio::test]
async fn a_held_duel_seat_admits_only_its_token_and_is_spent_once_taken() {
    let (address, _slots, holds, _commands, accept) =
        duel_listener(1, Some(Duration::from_secs(10))).await;
    for seat in [None, Some("not-it")] {
        let reply = duel_hello(address, seat).await;
        assert!(
            matches!(&reply, ServerMessage::Error { code, .. } if code == "match_full"),
            "{seat:?}: {reply:?}"
        );
    }
    assert!(held_now(&holds), "refusals leave the hold standing");
    let reply = duel_hello(address, Some("c0ffee")).await;
    assert!(
        matches!(
            reply,
            ServerMessage::Welcome {
                player_id: Some(_),
                ..
            }
        ),
        "{reply:?}"
    );
    assert!(
        !held_now(&holds),
        "the hold is spent once the seat is taken"
    );
    accept.abort();
}

#[tokio::test]
async fn a_lapsed_call_or_a_second_free_seat_admits_anybody() {
    let (address, _slots, _holds, _commands, accept) = duel_listener(1, Some(Duration::ZERO)).await;
    let reply = duel_hello(address, None).await;
    assert!(
        matches!(reply, ServerMessage::Welcome { .. }),
        "lapsed: {reply:?}"
    );
    accept.abort();
    let (address, _slots, holds, _commands, accept) =
        duel_listener(2, Some(Duration::from_secs(10))).await;
    let reply = duel_hello(address, None).await;
    assert!(
        matches!(reply, ServerMessage::Welcome { .. }),
        "the second free seat is anybody's: {reply:?}"
    );
    assert!(held_now(&holds), "the caller's seat stays held");
    accept.abort();
}

#[tokio::test]
async fn the_caller_waits_for_the_passing_fighter_to_let_the_seat_go() {
    let (address, slots, holds, _commands, accept) =
        duel_listener(0, Some(Duration::from_secs(10))).await;
    let freed = Arc::clone(&slots);
    tokio::spawn(async move {
        tokio::time::sleep(Duration::from_millis(400)).await;
        freed.add_permits(1);
    });
    let reply = duel_hello(address, Some("c0ffee")).await;
    assert!(
        matches!(
            reply,
            ServerMessage::Welcome {
                player_id: Some(_),
                ..
            }
        ),
        "{reply:?}"
    );
    assert!(!held_now(&holds));
    accept.abort();
}

#[tokio::test]
async fn a_passed_seat_closes_with_its_code_and_forgets_the_resume_token() {
    let (tx, mut commands) = game_channel();
    let server = NetServer::bind("127.0.0.1:0", tx).await.unwrap();
    let address = server.local_addr().unwrap();
    let clients = server.clients.clone();
    let accept = tokio::spawn(server.accept_loop());
    let mut fighter = welcome_fighter(address, true).await;
    let GameCommand::Connected { id, .. } = next_command(&mut commands).await else {
        panic!("expected the join");
    };
    clients
        .lock()
        .await
        .iter()
        .find(|client| client.id == id)
        .unwrap()
        .seat_passed();
    let (code, reason) = closing_code(&mut fighter).await;
    assert_eq!(
        (code.as_str(), reason.as_str()),
        ("duel_seat_passed", "duel_seat_passed")
    );
    let gone = next_command(&mut commands).await;
    assert!(
        matches!(gone, GameCommand::Disconnected { id: dropped } if dropped == id),
        "a passed seat removes the pawn and its resume token instead of parking it"
    );
    accept.abort();
}
