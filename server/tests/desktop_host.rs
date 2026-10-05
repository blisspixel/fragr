//! Real executable desktop arena ownership, without a campaign run directory.
use fragr_server::local::ArenaReady;
use fragr_server::protocol::{ClientMessage, GameMode, Role, ServerMessage};
use futures_util::{SinkExt, StreamExt};
use std::io::{BufRead, BufReader, Read, Write};
use std::process::{Child, ChildStdout, Command, Stdio};
use std::time::{Duration, Instant};
use tokio_tungstenite::{connect_async, tungstenite::Message};

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
        gameplay_version: fragr_server::protocol::GAMEPLAY_VERSION,
    })
    .await;
    assert!(child.0.try_wait().unwrap().is_none());
    // Drop retires only this test's owned process.
}
