//! Real executable desktop arena ownership, without a campaign run directory.
use fragr_server::local::ArenaReady;
use fragr_server::protocol::{ClientMessage, GameMode, Role, ServerMessage};
use futures_util::{SinkExt, StreamExt};
use std::io::{BufRead, BufReader, Read, Write};
use std::process::{Child, ChildStdout, Command, Stdio};
use std::time::{Duration, Instant};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio_tungstenite::{connect_async, tungstenite::Message};

type Socket =
    tokio_tungstenite::WebSocketStream<tokio_tungstenite::MaybeTlsStream<tokio::net::TcpStream>>;

async fn enter(
    ready: &ArenaReady,
    role: Role,
    resume: Option<String>,
) -> (Socket, Option<uuid::Uuid>, Option<String>) {
    let (mut socket, _) = connect_async(&ready.url).await.unwrap();
    socket
        .send(Message::Text(
            serde_json::to_string(&ClientMessage::Hello {
                role,
                name: "Dead Air Dan".into(),
                body: None,
                geometry_version: fragr_server::protocol::GEOMETRY_VERSION,
                gameplay_version: ready.gameplay_version,
                ticket: None,
                resume,
            })
            .unwrap(),
        ))
        .await
        .unwrap();
    let mut identity = None;
    let mut token = None;
    tokio::time::timeout(Duration::from_secs(5), async {
        let mut welcomed = false;
        while let Some(Ok(Message::Text(text))) = socket.next().await {
            match serde_json::from_str::<ServerMessage>(&text).unwrap() {
                ServerMessage::Welcome {
                    player_id, resume, ..
                } => {
                    identity = player_id;
                    token = resume;
                    welcomed = true;
                }
                ServerMessage::MapInfo { map_id, .. } => {
                    assert!(welcomed);
                    assert_eq!(map_id, ready.map_id);
                    return;
                }
                ServerMessage::Error { code, .. } => {
                    panic!("unexpected admission rejection {code}")
                }
                ServerMessage::Snapshot { .. } => panic!("snapshot before initial MapInfo"),
                _ => {}
            }
        }
        panic!("missing actual initial geometry");
    })
    .await
    .unwrap();
    (socket, identity, token)
}

async fn population(
    ready: &ArenaReady,
    humans: usize,
    agents: usize,
    bots: usize,
    bound: Duration,
) {
    let mut last = None;
    let reached = tokio::time::timeout(bound, async {
        loop {
            let mut stream =
                tokio::net::TcpStream::connect(ready.url.strip_prefix("ws://").unwrap())
                    .await
                    .unwrap();
            stream
                .write_all(b"GET /status HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n")
                .await
                .unwrap();
            let mut bytes = Vec::new();
            stream.take(65536).read_to_end(&mut bytes).await.unwrap();
            let text = String::from_utf8(bytes).unwrap();
            let body = text.split_once("\r\n\r\n").unwrap().1;
            // The existing nonblocking status endpoint reports only its legacy
            // schema marker while the authoritative tick holds the write lock.
            if body == "{\"schema_version\":1}" {
                tokio::time::sleep(Duration::from_millis(50)).await;
                continue;
            }
            let status: fragr_server::protocol::LiveStatus = serde_json::from_str(body).unwrap();
            last = Some((status.humans, status.agents, status.bots, status.tick));
            if (status.humans, status.agents, status.bots) == (humans, agents, bots) {
                assert_eq!(status.fighters, humans + agents + bots);
                return;
            }
            tokio::time::sleep(Duration::from_millis(50)).await;
        }
    })
    .await;
    assert!(reached.is_ok(), "authoritative population deadline: expected {humans}/{agents}/{bots}, actual {last:?}, mode {:?}", ready.mode);
}

struct OwnedChild(Child);
impl Drop for OwnedChild {
    fn drop(&mut self) {
        let _ = self.0.kill();
        let _ = self.0.wait();
    }
}

fn command() -> Command {
    let mut command = Command::new(env!("CARGO_BIN_EXE_fragr-server"));
    command
        .current_dir(std::env::temp_dir())
        .env_remove("FRAGR_JOIN_SECRET")
        .env("RUST_LOG", "fragr_server=debug")
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::null());
    command
}

fn start(args: &[&str]) -> (OwnedChild, ArenaReady, BufReader<ChildStdout>) {
    let mut child = OwnedChild(command().args(args).spawn().unwrap());
    let stdout = child.0.stdout.take().unwrap();
    let (tx, rx) = std::sync::mpsc::channel();
    std::thread::spawn(move || {
        let mut reader = BufReader::new(stdout);
        let mut line = String::new();
        let result = reader.by_ref().take(4096).read_line(&mut line);
        let _ = tx.send((result, line, reader));
    });
    let (result, line, reader) = rx
        .recv_timeout(Duration::from_secs(30))
        .expect("readiness deadline");
    result.unwrap();
    assert!(line.ends_with('\n'));
    let ready: ArenaReady = serde_json::from_str(&line).expect("strict arena readiness only");
    assert_eq!(ready.version, 1);
    assert_eq!(ready.kind, "arena");
    assert_eq!(
        ready.gameplay_version,
        fragr_server::protocol::GAMEPLAY_VERSION
    );
    (child, ready, reader)
}

fn finish(child: &mut OwnedChild, reader: &mut BufReader<ChildStdout>, success: bool) {
    let deadline = Instant::now() + Duration::from_secs(10);
    loop {
        if let Some(status) = child.0.try_wait().unwrap() {
            assert_eq!(status.success(), success);
            break;
        }
        assert!(Instant::now() < deadline, "owned child did not retire");
        std::thread::sleep(Duration::from_millis(10));
    }
    let mut remainder = String::new();
    reader.read_to_string(&mut remainder).unwrap();
    assert!(
        remainder.is_empty(),
        "stdout contained extra records: {remainder}"
    );
}

async fn prove_wire(ready: &ArenaReady) {
    for role in [Role::Human, Role::Spectator] {
        let (mut socket, _) = connect_async(&ready.url).await.unwrap();
        socket
            .send(Message::Text(
                serde_json::to_string(&ClientMessage::Hello {
                    role,
                    name: "Desktop room witness".into(),
                    body: None,
                    geometry_version: fragr_server::protocol::GEOMETRY_VERSION,
                    gameplay_version: ready.gameplay_version,
                    ticket: None,
                    resume: None,
                })
                .unwrap(),
            ))
            .await
            .unwrap();
        tokio::time::timeout(Duration::from_secs(5), async {
            let mut welcomed = false;
            while let Some(Ok(Message::Text(text))) = socket.next().await {
                match serde_json::from_str::<ServerMessage>(&text).unwrap() {
                    ServerMessage::Welcome { .. } => welcomed = true,
                    ServerMessage::MapInfo {
                        map_id,
                        rules,
                        sabotage,
                        mission,
                        ..
                    } => {
                        assert!(welcomed);
                        assert_eq!(map_id, ready.map_id);
                        assert_eq!(rules.unwrap().mode, ready.mode);
                        assert_eq!(sabotage.is_some(), ready.mode == GameMode::Sabotage);
                        assert!(mission.is_none());
                        return;
                    }
                    _ => {}
                }
            }
            panic!("matching arena map was not delivered");
        })
        .await
        .unwrap();
        socket.close(None).await.unwrap();
    }
}

#[tokio::test]
async fn tdm_child_serves_real_players_and_eof_retires_listener_without_campaign_storage() {
    let run = std::env::temp_dir().join(format!("fragr-arena-no-run-{}", uuid::Uuid::new_v4()));
    let mut cmd = command();
    cmd.env("FRAGR_RUN_DIR", &run).args([
        "--desktop-host",
        "--mode",
        "tdm",
        "--map",
        "3",
        "--bots",
        "0",
        "--bind",
        "127.0.0.1:0",
    ]);
    let mut child = OwnedChild(cmd.spawn().unwrap());
    let mut reader = BufReader::new(child.0.stdout.take().unwrap());
    let mut line = String::new();
    // Read on a bounded owning thread, so a startup failure cannot hang this test.
    let (tx, rx) = std::sync::mpsc::channel();
    std::thread::spawn(move || {
        let result = reader.by_ref().take(4096).read_line(&mut line);
        let _ = tx.send((result, line, reader));
    });
    let (result, line, mut reader) = rx.recv_timeout(Duration::from_secs(30)).unwrap();
    result.unwrap();
    let ready: ArenaReady = serde_json::from_str(&line).unwrap();
    assert_eq!(ready.mode, GameMode::Tdm);
    assert_eq!(ready.map_id, 3);
    assert!(!ready.five_vs_five);
    assert_eq!(ready.bots, 0);
    assert_eq!(ready.url, format!("ws://{}", ready.listen));
    prove_wire(&ready).await;
    assert!(!run.exists());
    drop(child.0.stdin.take());
    finish(&mut child, &mut reader, true);
    assert!(std::net::TcpListener::bind(&ready.listen).is_ok());
    assert!(!run.exists());
}

#[tokio::test]
async fn five_per_side_lan_child_reports_chosen_port_and_shutdown_retires_it() {
    let reservation = std::net::TcpListener::bind("0.0.0.0:0").unwrap();
    let address = reservation.local_addr().unwrap();
    drop(reservation);
    let bind = address.to_string();
    let (mut child, ready, mut reader) = start(&[
        "--desktop-host",
        "--mode",
        "sabotage",
        "--map",
        "4",
        "--sabotage-five-v-five",
        "--bots",
        "4",
        "--bind",
        &bind,
    ]);
    assert_eq!(ready.listen, bind);
    assert_eq!(ready.mode, GameMode::Sabotage);
    assert!(ready.five_vs_five);
    assert_eq!(ready.bots, 4);
    assert_eq!(ready.url, format!("ws://127.0.0.1:{}", address.port()));
    prove_wire(&ready).await;
    child
        .0
        .stdin
        .as_mut()
        .unwrap()
        .write_all(b"{\"type\":\"shutdown\"}\n")
        .unwrap();
    finish(&mut child, &mut reader, true);
    assert!(std::net::TcpListener::bind(address).is_ok());
}

#[test]
fn malformed_owner_control_retires_child_with_error_and_no_second_stdout_record() {
    let (mut child, ready, mut reader) = start(&[
        "--desktop-host",
        "--mode",
        "tdm",
        "--bots",
        "0",
        "--bind",
        "127.0.0.1:0",
    ]);
    child
        .0
        .stdin
        .as_mut()
        .unwrap()
        .write_all(b"{\"type\":\"restart\"}\n")
        .unwrap();
    finish(&mut child, &mut reader, false);
    assert!(std::net::TcpListener::bind(&ready.listen).is_ok());
}

#[tokio::test]
async fn automatic_owned_rooms_yield_real_seats_preserve_resume_and_refill_after_leave_and_grace() {
    for (mode, map, target, five) in [("tdm", "3", "4", false), ("sabotage", "4", "10", true)] {
        let mut args = vec![
            "--desktop-host",
            "--mode",
            mode,
            "--map",
            map,
            "--bots",
            "0",
            "--bot-policy",
            "auto",
            "--fill-target",
            target,
            "--bind",
            "127.0.0.1:0",
        ];
        if five {
            args.push("--sabotage-five-v-five");
        }
        let (mut child, ready, mut reader) = start(&args);
        let count = target.parse::<usize>().unwrap();
        assert_eq!(ready.bot_policy, fragr_server::bot_fill::BotPolicy::Auto);
        assert_eq!((ready.bots, ready.fill_target), (0, count));
        let (mut watcher, _, _) = enter(&ready, Role::Spectator, None).await;
        let watcher_reader = tokio::spawn(async move { while watcher.next().await.is_some() {} });
        population(&ready, 0, 0, count, Duration::from_secs(5)).await;
        let (mut human, human_id, token) = enter(&ready, Role::Human, Some(String::new())).await;
        let (mut agent, agent_id, _) = enter(&ready, Role::Agent, None).await;
        assert!(human_id.is_some() && agent_id.is_some() && human_id != agent_id);
        population(&ready, 1, 1, count - 2, Duration::from_secs(5)).await;
        human.close(None).await.unwrap();
        population(&ready, 1, 1, count - 2, Duration::from_secs(5)).await;
        tokio::time::sleep(Duration::from_millis(200)).await;
        let (mut resumed, resumed_id, _) = enter(&ready, Role::Human, token).await;
        assert_eq!(resumed_id, human_id);
        population(&ready, 1, 1, count - 2, Duration::from_secs(5)).await;
        resumed
            .send(Message::Text(
                serde_json::to_string(&ClientMessage::Leave).unwrap(),
            ))
            .await
            .unwrap();
        agent
            .send(Message::Text(
                serde_json::to_string(&ClientMessage::Leave).unwrap(),
            ))
            .await
            .unwrap();
        resumed.close(None).await.unwrap();
        agent.close(None).await.unwrap();
        population(&ready, 0, 0, count, Duration::from_secs(5)).await;
        let (mut abandoned, _, _) = enter(&ready, Role::Human, Some(String::new())).await;
        abandoned.close(None).await.unwrap();
        population(&ready, 1, 0, count - 1, Duration::from_secs(5)).await;
        population(&ready, 0, 0, count, Duration::from_secs(15)).await;
        watcher_reader.abort();
        let _ = watcher_reader.await;
        drop(child.0.stdin.take());
        finish(&mut child, &mut reader, true);
        assert!(std::net::TcpListener::bind(&ready.listen).is_ok());
    }
}

#[test]
fn parent_closed_before_startup_does_not_advertise_a_room() {
    let mut child = OwnedChild(
        command()
            .args([
                "--desktop-host",
                "--mode",
                "tdm",
                "--map",
                "5",
                "--bots",
                "0",
                "--bind",
                "127.0.0.1:0",
            ])
            .stdin(Stdio::null())
            .spawn()
            .unwrap(),
    );
    let mut reader = BufReader::new(child.0.stdout.take().unwrap());
    finish(&mut child, &mut reader, true);
}

#[test]
fn invalid_desktop_configuration_and_busy_bind_never_emit_readiness() {
    for args in [
        vec!["--mode", "ffa"],
        vec!["--mode", "ctf"],
        vec!["--mode", "sabotage", "--map", "4"],
        vec!["--mode", "sabotage", "--map", "1", "--sabotage-five-v-five"],
        vec!["--mode", "tdm", "--bots", "11"],
        vec![
            "--mode",
            "tdm",
            "--bots",
            "0",
            "--bot-policy",
            "auto",
            "--fill-target",
            "0",
        ],
        vec![
            "--mode",
            "tdm",
            "--bots",
            "0",
            "--bot-policy",
            "auto",
            "--fill-target",
            "11",
        ],
        vec![
            "--mode",
            "tdm",
            "--bots",
            "4",
            "--bot-policy",
            "auto",
            "--fill-target",
            "4",
        ],
        vec!["--mode", "tdm", "--bots", "4", "--bot-policy", "none"],
        vec!["--mode", "tdm", "--bots", "0", "--bot-policy", "unknown"],
        vec![
            "--mode",
            "tdm",
            "--bots",
            "0",
            "--bot-policy",
            "fixed",
            "--fill-target",
            "4",
        ],
        vec!["--mode", "tdm", "--bind", "0.0.0.0:0"],
        vec!["--mode", "tdm", "--bind", "[::1]:0"],
        vec!["--mode", "tdm", "--bind", "invalid"],
        vec!["--mode", "tdm", "--mutator", "rail-only"],
        vec!["--mode", "tdm", "--friendly-fire"],
        vec!["--mode", "tdm", "--map-rotate"],
        vec!["--local-mission", "recall_notice"],
        vec!["--local-run-preview"],
        vec!["--bench", "4"],
        vec!["--mode", "tdm", "--campaign-run"],
    ] {
        let mut cmd = command();
        cmd.arg("--desktop-host").args(&args);
        if !args.contains(&"--bind") {
            cmd.args(["--bind", "127.0.0.1:0"]);
        }
        let output = cmd.output().unwrap();
        assert!(!output.status.success(), "accepted {args:?}");
        assert!(output.stdout.is_empty(), "advertised invalid {args:?}");
    }
    let no_bind = command()
        .args(["--desktop-host", "--mode", "tdm"])
        .output()
        .unwrap();
    assert!(
        !no_bind.status.success(),
        "default wildcard must not imply LAN consent"
    );
    assert!(no_bind.stdout.is_empty());
    let reserved = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
    let address = reserved.local_addr().unwrap().to_string();
    let mut child = OwnedChild(
        command()
            .args([
                "--desktop-host",
                "--mode",
                "tdm",
                "--bots",
                "0",
                "--bind",
                &address,
            ])
            .spawn()
            .unwrap(),
    );
    let mut reader = BufReader::new(child.0.stdout.take().unwrap());
    finish(&mut child, &mut reader, false);
}

#[tokio::test]
async fn ordinary_dedicated_server_does_not_treat_stdin_eof_as_shutdown() {
    let reserved = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
    let address = reserved.local_addr().unwrap();
    drop(reserved);
    let bind = address.to_string();
    let mut child = OwnedChild(
        command()
            .args(["--mode", "tdm", "--bots", "0", "--bind", &bind])
            .stdin(Stdio::null())
            .spawn()
            .unwrap(),
    );
    let deadline = Instant::now() + Duration::from_secs(30);
    loop {
        if tokio::net::TcpStream::connect(address).await.is_ok() {
            break;
        }
        assert!(Instant::now() < deadline, "dedicated server did not bind");
        assert!(child.0.try_wait().unwrap().is_none());
        tokio::time::sleep(Duration::from_millis(10)).await;
    }
    prove_wire(&ArenaReady {
        version: 1,
        kind: "arena".into(),
        url: format!("ws://{address}"),
        listen: bind,
        map_id: 1,
        mode: GameMode::Tdm,
        five_vs_five: false,
        bots: 0,
        bot_policy: fragr_server::bot_fill::BotPolicy::Fixed,
        fill_target: 0,
        gameplay_version: fragr_server::protocol::GAMEPLAY_VERSION,
    })
    .await;
    assert!(child.0.try_wait().unwrap().is_none());
    // Drop retires only this test's owned process.
}
