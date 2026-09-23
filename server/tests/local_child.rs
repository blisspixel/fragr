//! Real executable ownership checks, including launch outside the checkout.
use fragr_server::local::Ready;
use fragr_server::protocol::{ClientMessage, MissionId, Role, ServerMessage};
use futures_util::{SinkExt, StreamExt};
use std::io::{BufRead, BufReader, Read, Write};
use std::path::Path;
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
        fragr_server::protocol::RECORD_GAMEPLAY_VERSION
    );
    assert!(ready.url.starts_with("ws://127.0.0.1:"));
    (child, ready)
}

fn spawn_persistent(directory: &Path, mode: &str, difficulty: Option<&str>) -> (OwnedChild, Ready) {
    let mut command = Command::new(env!("CARGO_BIN_EXE_fragr-server"));
    command
        .args(["--local-mission", "recall_notice", "--run-mode", mode])
        .current_dir(std::env::temp_dir())
        .env("FRAGR_RUN_DIR", directory)
        .env("RUST_LOG", "warn")
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::inherit());
    if let Some(difficulty) = difficulty {
        command.args(["--difficulty", difficulty]);
    }
    let mut child = OwnedChild(command.spawn().unwrap());
    let output = child.0.stdout.take().unwrap();
    let (tx, rx) = std::sync::mpsc::channel();
    std::thread::spawn(move || {
        let mut line = String::new();
        let result = BufReader::new(output).take(4096).read_line(&mut line);
        tx.send((result, line)).unwrap();
    });
    let (result, line) = rx
        .recv_timeout(Duration::from_secs(10))
        .expect("persistent child readiness deadline");
    result.unwrap();
    let ready: Ready = serde_json::from_str(&line).expect("typed persistent readiness");
    (child, ready)
}

fn preview(directory: &Path) -> serde_json::Value {
    let output = Command::new(env!("CARGO_BIN_EXE_fragr-server"))
        .arg("--local-run-preview")
        .env("FRAGR_RUN_DIR", directory)
        .output()
        .unwrap();
    assert!(output.status.success());
    serde_json::from_slice(&output.stdout).unwrap()
}

async fn campaign_run_id(ready: &Ready) -> uuid::Uuid {
    let (mut socket, _) = connect_async(&ready.url).await.unwrap();
    socket
        .send(Message::Text(
            serde_json::to_string(&ClientMessage::Hello {
                role: Role::Spectator,
                name: "Run witness".into(),
                geometry_version: 2,
                gameplay_version: fragr_server::protocol::GAMEPLAY_VERSION,
                ticket: None,
                resume: None,
            })
            .unwrap(),
        ))
        .await
        .unwrap();
    tokio::time::timeout(Duration::from_secs(3), async {
        while let Some(Ok(Message::Text(text))) = socket.next().await {
            if let ServerMessage::Mission { state, .. } =
                serde_json::from_str::<ServerMessage>(&text).unwrap()
            {
                return state.run.unwrap().id;
            }
        }
        panic!("child ended before run state");
    })
    .await
    .unwrap()
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
                resume: None,
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

#[tokio::test]
async fn persistent_local_child_restarts_same_run_and_keeps_saved_difficulty() {
    let directory =
        std::env::temp_dir().join(format!("fragr-run-restart-{}", uuid::Uuid::new_v4()));
    assert_eq!(preview(&directory)["status"], "missing");
    let (mut first, ready) = spawn_persistent(&directory, "new", Some("severe"));
    assert_eq!(
        ready.difficulty,
        fragr_server::protocol::CampaignDifficulty::Severe
    );
    let run_id = campaign_run_id(&ready).await;
    first
        .0
        .stdin
        .as_mut()
        .unwrap()
        .write_all(b"{\"type\":\"shutdown\"}\n")
        .unwrap();
    exited(&mut first, &ready, true);
    let saved: serde_json::Value =
        serde_json::from_slice(&std::fs::read(directory.join("run.json")).unwrap()).unwrap();
    assert_eq!(saved["id"], run_id.to_string());
    let available = preview(&directory);
    assert_eq!(available["status"], "ready");
    assert_eq!(available["difficulty"], "severe");
    assert_eq!(available["attempt"], 1);
    assert_eq!(available["continues"], 3);
    let (mut resumed, second_ready) = spawn_persistent(&directory, "resume", None);
    assert_eq!(
        second_ready.difficulty,
        fragr_server::protocol::CampaignDifficulty::Severe
    );
    assert_eq!(campaign_run_id(&second_ready).await, run_id);
    resumed
        .0
        .stdin
        .as_mut()
        .unwrap()
        .write_all(b"{\"type\":\"shutdown\"}\n")
        .unwrap();
    exited(&mut resumed, &second_ready, true);
    std::fs::remove_dir_all(directory).unwrap();
}

#[tokio::test]
async fn explicit_leave_durably_abandons_a_local_run() {
    let directory =
        std::env::temp_dir().join(format!("fragr-run-abandon-{}", uuid::Uuid::new_v4()));
    let (mut child, ready) = spawn_persistent(&directory, "new", None);
    let (mut socket, _) = connect_async(&ready.url).await.unwrap();
    socket
        .send(Message::Text(
            serde_json::to_string(&ClientMessage::Hello {
                role: Role::Human,
                name: "Run owner".into(),
                geometry_version: 2,
                gameplay_version: fragr_server::protocol::GAMEPLAY_VERSION,
                ticket: None,
                resume: None,
            })
            .unwrap(),
        ))
        .await
        .unwrap();
    tokio::time::timeout(Duration::from_secs(3), async {
        while let Some(Ok(Message::Text(text))) = socket.next().await {
            if let ServerMessage::Mission { state, .. } =
                serde_json::from_str::<ServerMessage>(&text).unwrap()
            {
                if state.party.len() == 1 {
                    return;
                }
            }
        }
        panic!("owner did not enter the local run");
    })
    .await
    .unwrap();
    socket
        .send(Message::Text(
            serde_json::to_string(&ClientMessage::Leave).unwrap(),
        ))
        .await
        .unwrap();
    socket.close(None).await.unwrap();
    let deadline = Instant::now() + Duration::from_secs(3);
    while preview(&directory)["status"] != "abandoned" {
        assert!(Instant::now() < deadline, "abandonment was not persisted");
        tokio::time::sleep(Duration::from_millis(25)).await;
    }
    child
        .0
        .stdin
        .as_mut()
        .unwrap()
        .write_all(b"{\"type\":\"shutdown\"}\n")
        .unwrap();
    exited(&mut child, &ready, true);
    assert_eq!(preview(&directory)["status"], "abandoned");
    std::fs::remove_dir_all(directory).unwrap();
}

#[tokio::test]
async fn second_local_child_cannot_take_an_active_run() {
    let directory = std::env::temp_dir().join(format!("fragr-run-lock-{}", uuid::Uuid::new_v4()));
    let (mut first, ready) = spawn_persistent(&directory, "new", None);
    let original = campaign_run_id(&ready).await;
    let mut second = Command::new(env!("CARGO_BIN_EXE_fragr-server"))
        .args(["--local-mission", "recall_notice", "--run-mode", "resume"])
        .env("FRAGR_RUN_DIR", &directory)
        .env("RUST_LOG", "warn")
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()
        .unwrap();
    let deadline = Instant::now() + Duration::from_secs(10);
    let status = loop {
        if let Some(status) = second.try_wait().unwrap() {
            break status;
        }
        assert!(Instant::now() < deadline, "second writer was not refused");
        std::thread::sleep(Duration::from_millis(10));
    };
    assert!(!status.success());
    let mut output = Vec::new();
    second
        .stdout
        .take()
        .unwrap()
        .read_to_end(&mut output)
        .unwrap();
    assert!(output.is_empty());
    assert_eq!(campaign_run_id(&ready).await, original);
    first
        .0
        .stdin
        .as_mut()
        .unwrap()
        .write_all(b"{\"type\":\"shutdown\"}\n")
        .unwrap();
    exited(&mut first, &ready, true);
    std::fs::remove_dir_all(directory).unwrap();
}

#[test]
fn read_only_preview_distinguishes_corrupt_and_incompatible_without_deleting() {
    let directory =
        std::env::temp_dir().join(format!("fragr-run-preview-{}", uuid::Uuid::new_v4()));
    std::fs::create_dir(&directory).unwrap();
    let path = directory.join("run.json");
    std::fs::write(&path, b"broken").unwrap();
    assert_eq!(preview(&directory)["status"], "corrupt");
    assert_eq!(std::fs::read(&path).unwrap(), b"broken");
    let (mut child, ready) = spawn_persistent(&directory, "new", None);
    child
        .0
        .stdin
        .as_mut()
        .unwrap()
        .write_all(b"{\"type\":\"shutdown\"}\n")
        .unwrap();
    exited(&mut child, &ready, true);
    let mut saved: serde_json::Value =
        serde_json::from_slice(&std::fs::read(&path).unwrap()).unwrap();
    saved["version"] = 999.into();
    let bytes = serde_json::to_vec(&saved).unwrap();
    std::fs::write(&path, &bytes).unwrap();
    assert_eq!(preview(&directory)["status"], "incompatible");
    assert_eq!(std::fs::read(&path).unwrap(), bytes);
    std::fs::remove_dir_all(directory).unwrap();
}
