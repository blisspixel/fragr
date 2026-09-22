//! Real executable ownership checks, including launch outside the checkout.
use fragr_server::local::Ready;
use fragr_server::protocol::{ClientMessage, MissionId, Role, ServerMessage};
use futures_util::{SinkExt, StreamExt};
use std::io::{BufRead, BufReader, Read, Write};
use std::process::{Child, Command, Stdio};
use std::time::{Duration, Instant};
use tokio_tungstenite::{connect_async, tungstenite::Message};

struct OwnedChild(Child);

impl Drop for OwnedChild {
    fn drop(&mut self) {
        let _ = self.0.kill();
        let _ = self.0.wait();
    }
}

fn spawn() -> (OwnedChild, Ready) {
    let mut child = OwnedChild(
        Command::new(env!("CARGO_BIN_EXE_fragr-server"))
            .args(["--local-mission", "recall_notice", "--seed", "67"])
            .current_dir(std::env::temp_dir())
            .env("RUST_LOG", "warn")
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::inherit())
            .spawn()
            .unwrap(),
    );
    let output = child.0.stdout.take().unwrap();
    let (tx, rx) = std::sync::mpsc::channel();
    std::thread::spawn(move || {
        let mut line = String::new();
        let result = BufReader::new(output).take(4096).read_line(&mut line);
        tx.send((result, line)).unwrap();
    });
    let (result, line) = rx
        .recv_timeout(Duration::from_secs(10))
        .expect("child readiness deadline");
    result.unwrap();
    let ready: Ready = serde_json::from_str(&line).expect("typed child readiness");
    assert_eq!(ready.version, 2);
    assert_eq!(ready.mission, MissionId::RecallNotice);
    assert_eq!(
        ready.gameplay_version,
        fragr_server::protocol::GAMEPLAY_VERSION
    );
    assert!(ready.url.starts_with("ws://127.0.0.1:"));
    (child, ready)
}

fn exited(child: &mut OwnedChild, ready: &Ready, success: bool) {
    let deadline = Instant::now() + Duration::from_secs(5);
    loop {
        if let Some(status) = child.0.try_wait().unwrap() {
            assert_eq!(status.success(), success);
            break;
        }
        assert!(Instant::now() < deadline, "owned server did not stop");
        std::thread::sleep(Duration::from_millis(10));
    }
    assert!(std::net::TcpStream::connect(ready.url.trim_start_matches("ws://")).is_err());
}

#[tokio::test]
async fn bundled_mission_serves_the_normal_wire_and_stops_on_explicit_shutdown() {
    let (mut child, ready) = spawn();
    let (mut socket, _) = connect_async(&ready.url).await.unwrap();
    socket
        .send(Message::Text(
            serde_json::to_string(&ClientMessage::Hello {
                role: Role::Spectator,
                name: "Local observer".into(),
                geometry_version: 2,
                gameplay_version: fragr_server::protocol::GAMEPLAY_VERSION,

                ticket: None,
            })
            .unwrap(),
        ))
        .await
        .unwrap();
    tokio::time::timeout(Duration::from_secs(3), async {
        let mut saw_map = false;
        while let Some(Ok(Message::Text(text))) = socket.next().await {
            match serde_json::from_str::<ServerMessage>(&text).unwrap() {
                ServerMessage::MapInfo {
                    map_id, mission, ..
                } => {
                    assert_eq!(map_id, 1001);
                    assert_eq!(mission.unwrap().id, MissionId::RecallNotice);
                    saw_map = true;
                }
                ServerMessage::Mission { state, .. } => {
                    assert!(saw_map);
                    assert!(state.party.is_empty());
                    return;
                }
                _ => {}
            }
        }
        panic!("child ended before mission state");
    })
    .await
    .unwrap();
    child
        .0
        .stdin
        .as_mut()
        .unwrap()
        .write_all(b"{\"type\":\"shutdown\"}\n")
        .unwrap();
    exited(&mut child, &ready, true);
}

#[test]
fn parent_eof_stops_the_owned_process_and_releases_its_port() {
    let (mut child, ready) = spawn();
    drop(child.0.stdin.take());
    exited(&mut child, &ready, true);
}

#[test]
fn malformed_parent_control_stops_with_an_error() {
    let (mut child, ready) = spawn();
    child
        .0
        .stdin
        .as_mut()
        .unwrap()
        .write_all(b"invalid\n")
        .unwrap();
    exited(&mut child, &ready, false);
}

#[test]
fn local_child_options_cannot_override_its_hosting_contract() {
    for extra in [
        vec!["--bind", "0.0.0.0:6767"],
        vec!["--bots", "0"],
        vec!["--map", "1"],
        vec!["--map-file", "missing.json"],
        vec!["--map-rotate"],
        vec!["--solo-broadcast"],
        vec!["--no-round-events"],
        vec!["--bench", "4"],
        vec!["--bench-verify-trace", "missing.json"],
        vec!["--status-every-s", "1"],
    ] {
        let result = Command::new(env!("CARGO_BIN_EXE_fragr-server"))
            .args(["--local-mission", "recall_notice"])
            .args(extra)
            .output()
            .unwrap();
        assert!(!result.status.success());
        assert!(result.stdout.is_empty());
    }
}
