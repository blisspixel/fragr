use super::*;

const BUDGET: Duration = Duration::from_millis(50);

fn ms(value: u64) -> Duration {
    Duration::from_millis(value)
}

#[test]
fn build_identity_is_sanitized() {
    let clean = build_info_from(Some(" 0123456789ABCDEF0123 "), Some("v0.46.0"));
    assert_eq!(clean.commit, "0123456789abcdef0123");
    assert_eq!(clean.release.as_deref(), Some("v0.46.0"));
    assert_eq!(clean.crate_version, env!("CARGO_PKG_VERSION"));
    for bad in [
        None,
        Some(""),
        Some("abc"),
        Some("not-a-commit!"),
        Some(&"a".repeat(41)[..]),
    ] {
        assert_eq!(build_info_from(bad, None).commit, "unknown", "{bad:?}");
    }
    assert_eq!(build_info_from(None, Some("v1 <script>")).release, None);
    assert_eq!(build_info_from(None, Some(&"v".repeat(65))).release, None);
    assert_eq!(
        build_info_from(None, Some("dev-abc1234"))
            .release
            .as_deref(),
        Some("dev-abc1234")
    );
    // The compiled identity passes the same rules.
    let compiled = build_info();
    assert!(compiled.commit == "unknown" || compiled.commit.chars().all(|c| c.is_ascii_hexdigit()));
}

#[test]
fn window_rotates_every_slot_and_forgets_after_a_minute() {
    let start = Instant::now();
    let mut window = TickWindow::new(start);
    for i in 0..200u64 {
        window.record_tick(start + ms(i * 50), ms(2), BUDGET);
    }
    window.record_tick(start + ms(10_000), ms(60), BUDGET);
    window.record_overflows(start + ms(10_050), 3);
    window.record_overflows(start + ms(10_060), 0);
    let (merged, over, overflows) = window.window(start + ms(10_100));
    assert_eq!(merged.count(), 201);
    assert_eq!((over, overflows), (1, 3));
    assert_eq!(window.lifetime.count(), 201);
    // Fifty seconds later the first slot has rotated out but the late one stays.
    let (merged, over, overflows) = window.window(start + ms(60_000));
    assert_eq!(merged.count(), 1);
    assert_eq!((over, overflows), (1, 3));
    // A long silence clears every slot at once; lifetime keeps everything.
    let (merged, over, overflows) = window.window(start + ms(600_000));
    assert_eq!((merged.count(), over, overflows), (0, 0, 0));
    assert_eq!(window.lifetime.count(), 201);
    assert_eq!(window.lifetime_over, 1);
    assert_eq!(window.overflows_total, 3);
    window.record_tick(start + ms(600_001), ms(1), BUDGET);
    assert_eq!(window.window(start + ms(600_002)).0.count(), 1);
}

#[test]
fn summaries_report_percentiles_in_milliseconds_with_exact_budget_counts() {
    let mut histogram = Histogram::new();
    for value in 1..=100u64 {
        histogram.record(value * 1_000_000);
    }
    let summary = summarize(&histogram, 7);
    assert_eq!(summary.count, 100);
    assert_eq!(summary.over_budget, 7);
    assert!(summary.p50_ms >= 50.0 && summary.p50_ms < 50.0 * 1.0625);
    assert!(summary.p95_ms >= 95.0 && summary.p95_ms < 95.0 * 1.0625);
    assert!(summary.p99_ms >= 99.0 && summary.p99_ms <= 100.0);
    assert_eq!(summary.max_ms, 100.0);
    let empty = summarize(&Histogram::new(), 0);
    assert_eq!((empty.count, empty.p99_ms, empty.max_ms), (0, 0.0, 0.0));
}

fn summary(count: u64, p99_ms: f64) -> TickSummary {
    TickSummary {
        count,
        p50_ms: 1.0,
        p95_ms: 1.0,
        p99_ms,
        max_ms: p99_ms,
        over_budget: 0,
    }
}

#[test]
fn degraded_thresholds_are_the_documented_ones() {
    assert!(evaluate(&summary(1200, 49.9), 50.0, 0).is_empty());
    assert_eq!(
        evaluate(&summary(1200, 50.0), 50.0, 0),
        vec![HealthReason::TickP99OverBudget]
    );
    // A cold start with a slow first map load is not a verdict yet.
    assert!(evaluate(&summary(MIN_WINDOW_TICKS - 1, 400.0), 50.0, 0).is_empty());
    assert_eq!(
        evaluate(&summary(MIN_WINDOW_TICKS, 400.0), 50.0, 0),
        vec![HealthReason::TickP99OverBudget]
    );
    assert_eq!(
        evaluate(&summary(10, 1.0), 50.0, 1),
        vec![HealthReason::OutboundDrops]
    );
    assert_eq!(
        evaluate(&summary(1200, 80.0), 50.0, 2),
        vec![HealthReason::TickP99OverBudget, HealthReason::OutboundDrops]
    );
    assert!(Health::from_reasons(Vec::new()).is_ok());
    assert!(!Health::from_reasons(vec![HealthReason::Stale]).is_ok());
}

#[test]
fn traffic_counts_per_session_and_in_total() {
    let totals = Arc::new(TrafficCounters::default());
    let agent = ClientTraffic::new(Role::Agent, Arc::clone(&totals));
    let watcher = ClientTraffic::new(Role::Spectator, Arc::clone(&totals));
    agent.sent(100);
    agent.sent(50);
    agent.received(20);
    watcher.sent(300);
    watcher.received(8);
    assert_eq!(
        agent.snapshot(),
        Counters {
            out_bytes: 150,
            out_msgs: 2,
            in_bytes: 20,
            in_msgs: 1
        }
    );
    assert_eq!(watcher.role(), Role::Spectator);
    drop(watcher);
    // Totals survive a closed session.
    assert_eq!(
        totals.snapshot(),
        Counters {
            out_bytes: 450,
            out_msgs: 3,
            in_bytes: 28,
            in_msgs: 2
        }
    );
    let zero = Counters::default();
    assert_eq!(
        totals.snapshot().per_second_since(&zero, 0.0),
        Rates::default()
    );
    let rates = totals.snapshot().per_second_since(&zero, 2.0);
    assert_eq!((rates.out_bytes, rates.out_msgs), (225.0, 1.5));
    assert_eq!((rates.in_bytes, rates.in_msgs), (14.0, 1.0));
}

#[test]
fn rates_use_a_rolling_window_baseline() {
    let start = Instant::now();
    let mut history = VecDeque::from([(start, Counters::default())]);
    for second in 1..=120u64 {
        let counters = Counters {
            out_bytes: second * 1000,
            ..Counters::default()
        };
        push_sample(&mut history, start + Duration::from_secs(second), counters);
        assert!(history.len() <= 62, "{}", history.len());
    }
    let baseline = history.front().unwrap().0;
    let span = (start + Duration::from_secs(120)).duration_since(baseline);
    assert!(
        span >= WINDOW && span < WINDOW + Duration::from_secs(2),
        "{span:?}"
    );
    assert!((history_rate(&history).out_bytes - 1000.0).abs() < 1e-9);
    assert_eq!(history_rate(&VecDeque::new()), Rates::default());
}

#[test]
fn tracker_reports_roles_rates_and_health_transitions() {
    let totals = Arc::new(TrafficCounters::default());
    let mut tracker = StatusTracker::new(Arc::clone(&totals), BUDGET);
    let agent = ClientTraffic::new(Role::Agent, Arc::clone(&totals));
    let human = ClientTraffic::new(Role::Human, Arc::clone(&totals));
    let watcher = ClientTraffic::new(Role::Spectator, Arc::clone(&totals));
    let ids = [Uuid::new_v4(), Uuid::new_v4(), Uuid::new_v4()];
    let now = Instant::now() + Duration::from_secs(2);
    assert!(tracker.due(now));
    assert!(tracker.health().is_none());
    for i in 0..200u64 {
        tracker.record_tick(now + ms(i), ms(3));
    }
    agent.sent(4000);
    watcher.sent(8000);
    human.received(100);
    let samples = [
        ClientSample {
            id: ids[2],
            traffic: &watcher,
            queue_depth: 4,
        },
        ClientSample {
            id: ids[0],
            traffic: &agent,
            queue_depth: 0,
        },
        ClientSample {
            id: ids[1],
            traffic: &human,
            queue_depth: 1,
        },
    ];
    let at = now + ms(300);
    tracker.refresh(at, &samples);
    assert!(!tracker.due(at + ms(999)));
    assert!(tracker.due(at + REFRESH_EVERY));
    let mut live = LiveStatus::default();
    tracker.apply(&mut live, at + ms(20));
    let health = live.health.clone().unwrap();
    assert!(health.is_ok(), "{health:?}");
    let ops = live.ops.clone().unwrap();
    assert_eq!(ops.version, OPS_VERSION);
    assert_eq!(ops.tick.scope, TICK_SCOPE);
    assert_eq!(ops.tick.window_s, 60);
    assert_eq!(ops.tick.budget_ms, 50.0);
    assert_eq!(ops.tick.window.count, 200);
    assert_eq!(ops.tick.lifetime.count, 200);
    assert!(ops.tick.window.p99_ms >= 3.0 && ops.tick.window.p99_ms < 3.2);
    assert_eq!(
        ops.connections,
        RoleCounts {
            total: 3,
            spectators: 1,
            humans: 1,
            agents: 1
        }
    );
    assert_eq!(ops.traffic.out_bytes, 12_000);
    assert_eq!(ops.traffic.in_bytes, 100);
    assert!(ops.traffic.out_bytes_per_s > 0.0);
    assert!(
        ops.traffic.per_client_out_bytes_per_s_max >= ops.traffic.per_client_out_bytes_per_s_mean
    );
    assert!(ops.process.uptime_s > 0.0);
    let clients = ops.clients.unwrap();
    let roles: Vec<Role> = clients.iter().map(|client| client.role).collect();
    assert_eq!(roles, vec![Role::Human, Role::Agent, Role::Spectator]);
    assert_eq!(clients[2].out_bytes, 8000);
    assert_eq!(clients[2].queue_depth, 4);
    assert!(clients[2].out_bytes_per_s > clients[1].out_bytes_per_s);

    // Slow ticks and a dropped reader degrade; the next clean window recovers.
    for i in 0..200u64 {
        tracker.record_tick(at + ms(1000 + i), ms(80));
    }
    tracker.record_overflows(at + ms(1300), 1);
    tracker.refresh(at + ms(1400), &samples[..1]);
    let degraded = tracker.health().unwrap().clone();
    assert_eq!(
        degraded.reasons,
        vec![HealthReason::TickP99OverBudget, HealthReason::OutboundDrops]
    );
    // A change of reasons while degraded is logged again, not a panic.
    let later = at + Duration::from_secs(62);
    for i in 0..200u64 {
        tracker.record_tick(later + ms(i), ms(90));
    }
    tracker.refresh(later + ms(300), &[]);
    assert_eq!(
        tracker.health().unwrap().reasons,
        vec![HealthReason::TickP99OverBudget]
    );
    let recovered = later + Duration::from_secs(70);
    for i in 0..200u64 {
        tracker.record_tick(recovered + ms(i), ms(1));
    }
    tracker.refresh(recovered + ms(300), &[]);
    assert!(tracker.health().unwrap().is_ok());
    let mut live = LiveStatus::default();
    tracker.apply(&mut live, recovered + ms(301));
    let ops = live.ops.unwrap();
    assert_eq!(ops.tick.lifetime.count, 800);
    assert_eq!(ops.tick.lifetime.over_budget, 400);
    assert_eq!(ops.traffic.queue_overflows_total, 1);
    assert_eq!(ops.traffic.queue_overflows_window, 0);
    assert_eq!(ops.connections.total, 0);
    assert_eq!(ops.clients.unwrap().len(), 0);
}

fn populated_status(clients: usize) -> LiveStatus {
    let totals = Arc::new(TrafficCounters::default());
    let mut tracker = StatusTracker::new(Arc::clone(&totals), BUDGET);
    let traffic: Vec<Arc<ClientTraffic>> = (0..clients)
        .map(|i| {
            let role = [Role::Agent, Role::Spectator, Role::Human][i % 3];
            let client = ClientTraffic::new(role, Arc::clone(&totals));
            client.sent(u32::MAX as usize);
            client.received(123_456);
            client
        })
        .collect();
    let samples: Vec<ClientSample<'_>> = traffic
        .iter()
        .map(|traffic| ClientSample {
            id: Uuid::new_v4(),
            traffic,
            queue_depth: 63,
        })
        .collect();
    let now = Instant::now();
    for i in 0..1200u64 {
        tracker.record_tick(now + ms(i), Duration::from_micros(1234 + i));
    }
    tracker.refresh(now + ms(1300), &samples);
    let mut live = LiveStatus {
        map: "Recall Notice: intake prototype".into(),
        kind: "campaign".into(),
        tick: u64::from(u32::MAX),
        round: 999,
        fighters: 64,
        humans: 16,
        agents: 16,
        bots: 32,
        connections: clients,
        ..LiveStatus::default()
    };
    tracker.apply(&mut live, now + ms(1301));
    live
}

#[test]
fn plain_status_stays_small_and_keeps_schema_two() {
    let live = populated_status(64);
    let served = served_status(&live, false, process_uptime());
    let body = serde_json::to_string(&served).unwrap();
    // The v0.37.0 client reads at most 4096 bytes.
    assert!(body.len() < 2048, "{} bytes: {body}", body.len());
    let json: serde_json::Value = serde_json::from_str(&body).unwrap();
    assert_eq!(json["schema_version"], 2);
    for key in [
        "kind",
        "map",
        "round",
        "tick",
        "fighters",
        "humans",
        "agents",
        "bots",
        "connections",
    ] {
        assert!(json.get(key).is_some(), "{key}");
    }
    assert_eq!(json["health"]["status"], "ok");
    assert!(json["health"]["reasons"].as_array().unwrap().is_empty());
    let ops = &json["ops"];
    assert_eq!(ops["version"], 1);
    assert!(ops.get("clients").is_none());
    for key in ["build", "process", "tick", "connections", "traffic"] {
        assert!(ops.get(key).is_some(), "{key}");
    }
    for key in [
        "p50_ms",
        "p95_ms",
        "p99_ms",
        "max_ms",
        "over_budget",
        "count",
    ] {
        assert!(ops["tick"]["window"].get(key).is_some(), "{key}");
        assert!(ops["tick"]["lifetime"].get(key).is_some(), "{key}");
    }
    assert_eq!(ops["connections"]["total"], 64);
    assert!(ops["process"]["started_unix_s"].as_u64().unwrap() > 1_600_000_000);
    // The detailed view lists every session and still names nobody.
    let detailed = serde_json::to_string(&served_status(&live, true, process_uptime())).unwrap();
    let json: serde_json::Value = serde_json::from_str(&detailed).unwrap();
    let clients = json["ops"]["clients"].as_array().unwrap();
    assert_eq!(clients.len(), 64);
    assert_eq!(
        clients[0]
            .as_object()
            .unwrap()
            .keys()
            .cloned()
            .collect::<Vec<_>>(),
        [
            "connected_s",
            "in_bytes",
            "in_bytes_per_s",
            "in_msgs_per_s",
            "out_bytes",
            "out_bytes_per_s",
            "out_msgs_per_s",
            "queue_depth",
            "role"
        ]
    );
    for forbidden in [
        "127.0.0.1",
        "peer",
        "addr",
        "name",
        "ticket",
        "token",
        "id\"",
    ] {
        assert!(!detailed.contains(forbidden), "{forbidden}");
    }
    // A reader that only knows schema 2 still parses it.
    let round_trip: LiveStatus = serde_json::from_str(&detailed).unwrap();
    assert_eq!(round_trip.fighters, 64);
    let old: LiveStatus = serde_json::from_str(
        r#"{"schema_version":2,"kind":"arena","map":"Arena Duel","round":1,"tick":5,"fighters":4,"humans":0,"agents":0,"bots":4,"connections":1}"#,
    )
    .unwrap();
    assert!(old.health.is_none() && old.ops.is_none());
    assert!(!serde_json::to_string(&old).unwrap().contains("ops"));
}

#[test]
fn a_snapshot_the_tick_loop_stopped_refreshing_is_stale() {
    let live = populated_status(2);
    let taken = Duration::from_secs_f64(live.ops.as_ref().unwrap().process.uptime_s);
    let fresh = served_status(&live, false, taken + Duration::from_millis(1500));
    assert!(fresh.health.unwrap().is_ok());
    let stale = served_status(&live, true, taken + Duration::from_secs(5));
    let health = stale.health.unwrap();
    assert_eq!(health.status, HealthState::Degraded);
    assert_eq!(health.reasons, vec![HealthReason::Stale]);
    assert_eq!(stale.ops.unwrap().clients.unwrap().len(), 2);
    // Stale is added once, and a missing health block is created.
    let mut no_health = live.clone();
    no_health.health = None;
    let served = served_status(&no_health, false, taken + Duration::from_secs(9));
    let again = served_status(&served, false, taken + Duration::from_secs(9));
    assert_eq!(again.health.unwrap().reasons, vec![HealthReason::Stale]);
    // Without an operator block there is nothing to judge.
    let bare = LiveStatus::default();
    assert_eq!(served_status(&bare, true, Duration::from_secs(99)), bare);
}

#[test]
fn only_an_explicit_clients_query_adds_the_list() {
    assert!(wants_clients(
        b"GET /status?clients=1 HTTP/1.1\r\nHost: x\r\n\r\n"
    ));
    assert!(wants_clients(b"GET /status?x=2&clients HTTP/1.1\r\n"));
    assert!(wants_clients(b"GET /status?clients=true HTTP/1.1"));
    assert!(!wants_clients(b"GET /status HTTP/1.1\r\n"));
    assert!(!wants_clients(b"GET /status?clients=0 HTTP/1.1\r\n"));
    assert!(!wants_clients(b"GET /status?clientsx=1 HTTP/1.1\r\n"));
    assert!(!wants_clients(b"GET /other?clients=1 HTTP/1.1\r\n"));
    assert!(!wants_clients(b"GET"));
    assert!(!wants_clients(b""));
}

#[test]
fn process_clock_is_fixed_once() {
    mark_process_start();
    let first = process_info(Instant::now());
    mark_process_start();
    let second = process_info(Instant::now());
    assert_eq!(first.started_unix_s, second.started_unix_s);
    assert!(second.uptime_s >= first.uptime_s);
    assert!(process_uptime() > Duration::ZERO || first.uptime_s == 0.0);
}

async fn http_status(address: std::net::SocketAddr, path: &str) -> LiveStatus {
    use tokio::io::{AsyncReadExt, AsyncWriteExt};
    let mut tcp = tokio::net::TcpStream::connect(address).await.unwrap();
    tcp.write_all(format!("GET {path} HTTP/1.1\r\nHost: localhost\r\n\r\n").as_bytes())
        .await
        .unwrap();
    let mut response = Vec::new();
    tokio::time::timeout(Duration::from_secs(3), tcp.read_to_end(&mut response))
        .await
        .unwrap()
        .unwrap();
    let text = String::from_utf8(response).unwrap();
    assert!(text.starts_with("HTTP/1.1 200"), "{text}");
    serde_json::from_str(text.split("\r\n\r\n").nth(1).unwrap()).unwrap()
}

#[tokio::test]
async fn a_live_server_reports_ticks_traffic_and_roles_on_status() {
    use futures_util::{SinkExt, StreamExt};
    use tokio_tungstenite::tungstenite::Message;
    let (ready_tx, ready_rx) = tokio::sync::oneshot::channel();
    let (stop_tx, stop_rx) = tokio::sync::oneshot::channel::<()>();
    let server = tokio::spawn(crate::run::run_server(
        crate::run::ServerOptions {
            bind: "127.0.0.1:0".into(),
            bots: 2,
            status_every_s: 0,
            ..crate::run::ServerOptions::default()
        },
        async move {
            let _ = stop_rx.await;
        },
        Some(ready_tx),
    ));
    let address = tokio::time::timeout(Duration::from_secs(30), ready_rx)
        .await
        .unwrap()
        .unwrap();
    let (mut socket, _) = tokio_tungstenite::connect_async(format!("ws://{address}"))
        .await
        .unwrap();
    let hello = r#"{"type":"hello","role":"spectator","name":"Probe"}"#;
    socket.send(Message::Text(hello.to_string())).await.unwrap();
    let mut received = 0usize;
    let mut snapshots = 0;
    while snapshots < 30 {
        let frame = tokio::time::timeout(Duration::from_secs(5), socket.next())
            .await
            .unwrap()
            .unwrap()
            .unwrap();
        if let Message::Text(text) = frame {
            received += text.len();
            snapshots += usize::from(text.contains("\"type\":\"snapshot\""));
        }
    }
    // Past one refresh, so the operator block has seen this session.
    tokio::time::sleep(REFRESH_EVERY + Duration::from_millis(200)).await;
    let plain = http_status(address, "/status").await;
    assert_eq!(plain.schema_version, 2);
    assert_eq!(plain.bots, 2);
    assert_eq!(plain.connections, 1);
    let ops = plain.ops.expect("operator block");
    assert!(ops.clients.is_none());
    assert!(plain.health.is_some());
    assert_eq!(ops.connections.spectators, 1);
    assert_eq!(ops.connections.total, 1);
    assert!(ops.tick.lifetime.count >= 30, "{:?}", ops.tick);
    assert!(ops.tick.window.p99_ms > 0.0);
    assert!(ops.tick.window.max_ms >= ops.tick.window.p99_ms);
    assert!(ops.tick.window.p99_ms >= ops.tick.window.p50_ms);
    assert_eq!(ops.traffic.in_bytes, hello.len() as u64);
    assert_eq!(ops.traffic.in_msgs, 1);
    assert!(
        ops.traffic.out_bytes >= received as u64 / 2,
        "{:?}",
        ops.traffic
    );
    assert!(ops.traffic.out_bytes_per_s > 0.0);
    assert!(ops.process.uptime_s > 0.0);
    let detailed = http_status(address, "/status?clients=1").await;
    let clients = detailed.ops.unwrap().clients.expect("client list");
    assert_eq!(clients.len(), 1);
    assert_eq!(clients[0].role, Role::Spectator);
    assert_eq!(clients[0].in_bytes, hello.len() as u64);
    assert!(clients[0].out_bytes > 0 && clients[0].out_bytes_per_s > 0.0);
    drop(socket);
    let _ = stop_tx.send(());
    tokio::time::timeout(Duration::from_secs(5), server)
        .await
        .unwrap()
        .unwrap()
        .unwrap();
}
