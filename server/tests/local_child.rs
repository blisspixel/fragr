//! Real executable ownership checks, including launch outside the checkout.
use fragr_server::local::Ready;
use fragr_server::protocol::{BodyKind, ClientMessage, MissionId, Role, ServerMessage};
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
        fragr_server::protocol::M05_GAMEPLAY_VERSION
    );
    assert!(ready.url.starts_with("ws://127.0.0.1:"));
    (child, ready)
}

fn spawn_persistent(directory: &Path, mode: &str, difficulty: Option<&str>) -> (OwnedChild, Ready) {
    spawn_persistent_mission(directory, "recall_notice", mode, difficulty)
}

fn spawn_persistent_mission(
    directory: &Path,
    mission: &str,
    mode: &str,
    difficulty: Option<&str>,
) -> (OwnedChild, Ready) {
    let mut command = Command::new(env!("CARGO_BIN_EXE_fragr-server"));
    command
        .args(["--local-mission", mission, "--run-mode", mode])
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

/// Set FRAGR_TEST_RUN_FIXTURE_DIR to an unused absolute directory to retain
/// this validated file for the client integration harness.
#[tokio::test]
async fn isolated_m01_departure_fixture_for_m02_client_smoke() {
    let retained = std::env::var_os("FRAGR_TEST_RUN_FIXTURE_DIR");
    let directory = retained.as_ref().map_or_else(
        || std::env::temp_dir().join(format!("fragr-carry-fixture-{}", uuid::Uuid::new_v4())),
        std::path::PathBuf::from,
    );
    assert!(
        directory.is_absolute(),
        "fixture directory must be absolute"
    );
    std::fs::create_dir_all(&directory).unwrap();
    let m01 = fragr_server::maps::RuntimeMap::Authored(
        fragr_server::maps::AuthoredSource::Mission(MissionId::RecallNotice)
            .load()
            .unwrap(),
    );
    let hash = m01.content_sha256().unwrap();
    let document = serde_json::json!({
        "version": 3,
        "id": uuid::Uuid::from_u128(0x12712898),
        "starting_continues": 3,
        "remaining_continues": 2,
        "level_start_continues": 3,
        "body": "synthetic",
        "rules": {"difficulty":"severe", "revision":2},
        "content_sha256": hash,
        "step": {
            "kind":"awaiting_mission",
            "completed_mission":"recall_notice",
            "next_mission":"persons_unknown",
            "exit": {
                "hp":61, "armor":7,
                "equipment": {
                    "selected":"tack",
                    "weapons":["fists","tack"],
                    "ammo":[
                        {"pool":"bullets","rounds":29},
                        {"pool":"shells","rounds":0},
                        {"pool":"cells","rounds":0}
                    ],
                    "personal_claims":["bay_tack"]
                }
            }
        }
    });
    let path = directory.join("run.json");
    let mut file = std::fs::OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(&path)
        .unwrap();
    serde_json::to_writer(&mut file, &document).unwrap();
    file.sync_all().unwrap();
    drop(file);
    let shown = preview(&directory);
    assert_eq!(shown["status"], "awaiting_mission");
    assert_eq!(shown["mission"], "persons_unknown");
    assert_eq!(shown["body"], "synthetic");
    assert_eq!(shown["continues"], 2);
    if retained.is_none() {
        let (child, ready) =
            spawn_persistent_mission(&directory, "persons_unknown", "resume", Some("severe"));
        assert_eq!(ready.mission, MissionId::PersonsUnknown);
        assert_eq!(
            ready.difficulty,
            fragr_server::protocol::CampaignDifficulty::Severe
        );
        assert_eq!(
            ready.gameplay_version,
            fragr_server::protocol::M05_GAMEPLAY_VERSION
        );
        let (mut socket, _) = connect_async(&ready.url).await.unwrap();
        socket
            .send(Message::Text(
                serde_json::to_string(&ClientMessage::Hello {
                    body: Some(BodyKind::Human),
                    role: Role::Human,
                    name: "Saved owner".into(),
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
            let mut joined_id = None;
            while let Some(Ok(Message::Text(text))) = socket.next().await {
                match serde_json::from_str::<ServerMessage>(&text).unwrap() {
                    ServerMessage::Welcome {
                        player_id, body, ..
                    } => {
                        assert_eq!(body, Some(BodyKind::Synthetic));
                        joined_id = player_id;
                    }
                    ServerMessage::Snapshot(snapshot) => {
                        if let Some(player) = snapshot
                            .players
                            .iter()
                            .find(|player| Some(player.id) == joined_id)
                        {
                            assert_eq!(player.body, Some(BodyKind::Synthetic));
                            assert_eq!(player.hp, 61);
                            assert_eq!(player.armor, 7);
                            return;
                        }
                    }
                    _ => {}
                }
            }
            panic!("owner did not receive its authoritative body");
        })
        .await
        .unwrap();
        drop(socket);
        drop(child);
        let promoted = preview(&directory);
        assert_eq!(promoted["status"], "ready");
        assert_eq!(promoted["mission"], "persons_unknown");
        assert_eq!(promoted["attempt"], 1);
        assert_eq!(promoted["continues"], 2);
        assert_eq!(promoted["body"], "synthetic");
        let archives: Vec<_> = std::fs::read_dir(&directory)
            .unwrap()
            .filter_map(Result::ok)
            .filter(|entry| {
                entry
                    .file_name()
                    .to_string_lossy()
                    .starts_with("run.prior-")
            })
            .collect();
        assert_eq!(archives.len(), 1);
        std::fs::remove_dir_all(&directory).unwrap();
    }
}

#[test]
fn wrong_mission_resume_does_not_migrate_v2_departure() {
    let directory =
        std::env::temp_dir().join(format!("fragr-wrong-mission-{}", uuid::Uuid::new_v4()));
    let (mut first, ready) = spawn_persistent(&directory, "new", None);
    first
        .0
        .stdin
        .as_mut()
        .unwrap()
        .write_all(b"{\"type\":\"shutdown\"}\n")
        .unwrap();
    exited(&mut first, &ready, true);
    let path = directory.join("run.json");
    let mut legacy: serde_json::Value =
        serde_json::from_slice(&std::fs::read(&path).unwrap()).unwrap();
    legacy["version"] = 2.into();
    legacy["rules"]["revision"] = 2.into();
    legacy
        .as_object_mut()
        .unwrap()
        .remove("level_start_continues");
    legacy.as_object_mut().unwrap().remove("body");
    // A historical v2 document has no counted-grenade field. Keep this a valid
    // legacy save so the first refusal proves the requested mission is wrong.
    legacy["step"]["entry"]["equipment"]
        .as_object_mut()
        .unwrap()
        .remove("grenades");
    let entry = legacy["step"]["entry"].clone();
    legacy["step"] = serde_json::json!({
        "kind":"awaiting_mission",
        "completed_mission":"recall_notice",
        "next_mission":"persons_unknown",
        "exit":entry
    });
    let source = serde_json::to_vec(&legacy).unwrap();
    std::fs::write(&path, &source).unwrap();
    let mut wrong = Command::new(env!("CARGO_BIN_EXE_fragr-server"))
        .args(["--local-mission", "recall_notice", "--run-mode", "resume"])
        .env("FRAGR_RUN_DIR", &directory)
        .env("RUST_LOG", "warn")
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()
        .unwrap();
    let deadline = Instant::now() + Duration::from_secs(10);
    loop {
        if let Some(status) = wrong.try_wait().unwrap() {
            assert!(!status.success());
            break;
        }
        assert!(Instant::now() < deadline, "wrong mission was not refused");
        std::thread::sleep(Duration::from_millis(10));
    }
    let mut output = Vec::new();
    wrong
        .stdout
        .take()
        .unwrap()
        .read_to_end(&mut output)
        .unwrap();
    assert!(output.is_empty(), "refused resume advertised readiness");
    assert_eq!(std::fs::read(&path).unwrap(), source);
    assert_eq!(
        std::fs::read_dir(&directory)
            .unwrap()
            .filter_map(Result::ok)
            .filter(|entry| entry
                .file_name()
                .to_string_lossy()
                .starts_with("run.prior-"))
            .count(),
        0
    );
    let (child, ready) = spawn_persistent_mission(&directory, "persons_unknown", "resume", None);
    assert_eq!(
        ready.gameplay_version,
        fragr_server::protocol::M05_GAMEPLAY_VERSION
    );
    drop(child);
    assert_eq!(preview(&directory)["mission"], "persons_unknown");
    std::fs::remove_dir_all(directory).unwrap();
}

#[tokio::test]
async fn released_m02_run_promotes_once_and_restarts_at_m03_entry() {
    let directory = std::env::temp_dir().join(format!("fragr-m03-carry-{}", uuid::Uuid::new_v4()));
    std::fs::create_dir_all(&directory).unwrap();
    let source_hash = fragr_server::maps::RuntimeMap::Authored(
        fragr_server::maps::AuthoredSource::Mission(MissionId::PersonsUnknown)
            .load()
            .unwrap(),
    )
    .content_sha256()
    .unwrap();
    let run_id = uuid::Uuid::new_v4();
    let prior = serde_json::json!({
        "version":3,"id":run_id,"starting_continues":3,"remaining_continues":1,"level_start_continues":2,"body":"synthetic",
        "rules":{"difficulty":"severe","revision":2},"content_sha256":source_hash,
        "step":{"kind":"awaiting_mission","completed_mission":"persons_unknown","next_mission":"scheduled_service",
            "exit":{"hp":61,"armor":7,"equipment":{"selected":"flechette","weapons":["fists","flechette","scatter"],
                "ammo":[{"pool":"bullets","rounds":29},{"pool":"shells","rounds":8},{"pool":"cells","rounds":0}],"personal_claims":["m02_rifle"]}}}
    });
    let bytes = serde_json::to_vec(&prior).unwrap();
    let path = directory.join("run.json");
    std::fs::write(&path, &bytes).unwrap();
    assert_eq!(preview(&directory)["mission"], "scheduled_service");
    for _ in 0..2 {
        let (mut child, ready) =
            spawn_persistent_mission(&directory, "scheduled_service", "resume", None);
        assert_eq!(ready.mission, MissionId::ScheduledService);
        assert_eq!(
            ready.gameplay_version,
            fragr_server::protocol::M05_GAMEPLAY_VERSION
        );
        assert_eq!(
            ready.difficulty,
            fragr_server::protocol::CampaignDifficulty::Severe
        );
        let (mut socket, _) = connect_async(&ready.url).await.unwrap();
        socket
            .send(Message::Text(
                serde_json::to_string(&ClientMessage::Hello {
                    role: Role::Human,
                    name: "Yard runner".into(),
                    body: Some(BodyKind::Human),
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
            let mut owner = None;
            let mut mapped = false;
            while let Some(Ok(Message::Text(text))) = socket.next().await {
                match serde_json::from_str::<ServerMessage>(&text).unwrap() {
                    ServerMessage::Welcome {
                        player_id, body, ..
                    } => {
                        owner = player_id;
                        assert_eq!(body, Some(BodyKind::Synthetic));
                    }
                    ServerMessage::MapInfo { m03, .. } => {
                        assert!(m03.is_some());
                        mapped = true;
                    }
                    ServerMessage::Mission { state, .. } => {
                        assert!(mapped);
                        let run = state.run.unwrap();
                        assert_eq!(
                            (
                                run.id,
                                run.continues,
                                run.level_start_continues,
                                state.attempt
                            ),
                            (run_id, 1, 1, 1)
                        );
                    }
                    ServerMessage::Snapshot(snapshot) => {
                        assert!(mapped);
                        if let Some(player) = snapshot.players.iter().find(|p| Some(p.id) == owner)
                        {
                            assert_eq!(
                                (player.hp, player.armor, player.weapon.as_str()),
                                (61, 7, "Flechette")
                            );
                            assert_eq!(player.body, Some(BodyKind::Synthetic));
                            return;
                        }
                    }
                    _ => {}
                }
            }
            panic!("M03 owner snapshot missing");
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
        drop(socket);
        drop(child);
        let live: serde_json::Value =
            serde_json::from_slice(&std::fs::read(&path).unwrap()).unwrap();
        assert_eq!(live["version"], 7);
        assert_eq!(live["step"]["mission"], "scheduled_service");
        assert_eq!(
            live["step"]["entry"]["equipment"]["personal_claims"],
            serde_json::json!([])
        );
        assert_eq!(
            live["step"]["entry"]["equipment"]["ammo"],
            prior["step"]["exit"]["equipment"]["ammo"]
        );
    }
    let archives: Vec<_> = std::fs::read_dir(&directory)
        .unwrap()
        .filter_map(Result::ok)
        .filter(|entry| {
            entry
                .file_name()
                .to_string_lossy()
                .starts_with("run.prior-")
        })
        .collect();
    assert_eq!(archives.len(), 1);
    assert_eq!(std::fs::read(archives[0].path()).unwrap(), bytes);
    std::fs::remove_dir_all(directory).unwrap();
}

#[tokio::test]
async fn completed_m03_run_promotes_once_and_retains_choices_at_m04_entry() {
    let directory = std::env::temp_dir().join(format!("fragr-m04-carry-{}", uuid::Uuid::new_v4()));
    std::fs::create_dir_all(&directory).unwrap();
    let source_hash = fragr_server::maps::RuntimeMap::Authored(
        fragr_server::maps::AuthoredSource::Mission(MissionId::ScheduledService)
            .load()
            .unwrap(),
    )
    .content_sha256()
    .unwrap();
    let run_id = uuid::Uuid::new_v4();
    let prior = serde_json::json!({
        "version":4,"id":run_id,"starting_continues":3,"remaining_continues":1,"level_start_continues":2,"body":"synthetic",
        "rules":{"difficulty":"severe","revision":2},"content_sha256":source_hash,
        "m03_outcome":{"liberated_cars":["platform_car","roof_car"]},
        "step":{"kind":"awaiting_mission","completed_mission":"scheduled_service","next_mission":"notice_to_vacate",
            "exit":{"hp":61,"armor":7,"equipment":{"selected":"flechette","weapons":["fists","flechette","scatter"],
                "ammo":[{"pool":"bullets","rounds":29},{"pool":"shells","rounds":8},{"pool":"cells","rounds":0}],"personal_claims":["m02_rifle"]}}}
    });
    let bytes = serde_json::to_vec(&prior).unwrap();
    let path = directory.join("run.json");
    std::fs::write(&path, &bytes).unwrap();
    assert_eq!(preview(&directory)["mission"], "notice_to_vacate");
    for _ in 0..2 {
        let (mut child, ready) =
            spawn_persistent_mission(&directory, "notice_to_vacate", "resume", None);
        assert_eq!(ready.mission, MissionId::NoticeToVacate);
        assert_eq!(
            ready.gameplay_version,
            fragr_server::protocol::M05_GAMEPLAY_VERSION
        );
        assert_eq!(
            ready.difficulty,
            fragr_server::protocol::CampaignDifficulty::Severe
        );
        let (mut socket, _) = connect_async(&ready.url).await.unwrap();
        socket
            .send(Message::Text(
                serde_json::to_string(&ClientMessage::Hello {
                    role: Role::Human,
                    name: "Yard runner".into(),
                    body: Some(BodyKind::Human),
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
            let mut owner = None;
            let mut mapped = false;
            while let Some(Ok(Message::Text(text))) = socket.next().await {
                match serde_json::from_str::<ServerMessage>(&text).unwrap() {
                    ServerMessage::Welcome {
                        player_id, body, ..
                    } => {
                        owner = player_id;
                        assert_eq!(body, Some(BodyKind::Synthetic));
                    }
                    ServerMessage::MapInfo { m04, .. } => {
                        assert!(m04.is_some());
                        mapped = true;
                    }
                    ServerMessage::Mission { state, .. } => {
                        assert!(mapped);
                        assert_eq!(
                            state.m04.as_ref().unwrap().carried_recall_cars,
                            ["platform_car", "roof_car"]
                        );
                        let run = state.run.unwrap();
                        assert_eq!(
                            (
                                run.id,
                                run.continues,
                                run.level_start_continues,
                                state.attempt
                            ),
                            (run_id, 1, 1, 1)
                        );
                    }
                    ServerMessage::Snapshot(snapshot) => {
                        assert!(mapped);
                        if let Some(player) = snapshot.players.iter().find(|p| Some(p.id) == owner)
                        {
                            assert_eq!(
                                (player.hp, player.armor, player.weapon.as_str()),
                                (61, 7, "Flechette")
                            );
                            assert_eq!(player.body, Some(BodyKind::Synthetic));
                            return;
                        }
                    }
                    _ => {}
                }
            }
            panic!("M04 owner snapshot missing");
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
        drop(socket);
        drop(child);
        let live: serde_json::Value =
            serde_json::from_slice(&std::fs::read(&path).unwrap()).unwrap();
        assert_eq!(live["version"], 7);
        assert_eq!(live["step"]["mission"], "notice_to_vacate");
        assert_eq!(
            live["step"]["entry"]["equipment"]["personal_claims"],
            serde_json::json!([])
        );
        assert_eq!(
            live["step"]["entry"]["equipment"]["ammo"],
            prior["step"]["exit"]["equipment"]["ammo"]
        );
    }
    let archives: Vec<_> = std::fs::read_dir(&directory)
        .unwrap()
        .filter_map(Result::ok)
        .filter(|entry| {
            entry
                .file_name()
                .to_string_lossy()
                .starts_with("run.prior-")
        })
        .collect();
    assert_eq!(archives.len(), 1);
    assert_eq!(std::fs::read(archives[0].path()).unwrap(), bytes);
    std::fs::remove_dir_all(directory).unwrap();
}

#[tokio::test]
async fn completed_v6_m05_run_refills_once_and_retains_actual_counts_at_m06_entry() {
    let directory = std::env::temp_dir().join(format!("fragr-m06-carry-{}", uuid::Uuid::new_v4()));
    std::fs::create_dir_all(&directory).unwrap();
    let source_hash = fragr_server::maps::RuntimeMap::Authored(
        fragr_server::maps::AuthoredSource::Mission(MissionId::NoForwardingAddress)
            .load()
            .unwrap(),
    )
    .content_sha256()
    .unwrap();
    let run_id = uuid::Uuid::new_v4();
    let prior = serde_json::json!({
        "version":6,"id":run_id,"starting_continues":3,"remaining_continues":0,"level_start_continues":1,"body":"synthetic",
        "rules":{"difficulty":"severe","revision":3},"content_sha256":source_hash,
        "m03_outcome":{"liberated_cars":["roof_car","platform_car"]},
        "m04_outcome":{"rescued_patients":["edda_team_a"],"photos_completed":3},
        "m05_outcome":{"released_workers":["workshop_agent_b","splice","workshop_agent_a"],"evacuated_workers":["workshop_agent_b"]},
        "step":{"kind":"awaiting_mission","completed_mission":"no_forwarding_address","next_mission":"port_of_entry",
            "exit":{"hp":61,"armor":7,"equipment":{"selected":"flechette","weapons":["fists","flechette","scatter"],
                "ammo":[{"pool":"bullets","rounds":29},{"pool":"shells","rounds":8},{"pool":"cells","rounds":0}],
                "grenades":2,"personal_claims":["workshop_grenade"]}}}
    });
    let bytes = serde_json::to_vec_pretty(&prior).unwrap();
    let path = directory.join("run.json");
    std::fs::write(&path, &bytes).unwrap();
    let before = preview(&directory);
    assert_eq!(before["mission"], "port_of_entry");
    assert_eq!(before["continues"], 0);
    assert_eq!(std::fs::read(&path).unwrap(), bytes);
    for expected_continues in [3, 1] {
        let (mut child, ready) =
            spawn_persistent_mission(&directory, "port_of_entry", "resume", None);
        assert_eq!(ready.mission, MissionId::PortOfEntry);
        assert_eq!(
            ready.gameplay_version,
            fragr_server::protocol::M06_GAMEPLAY_VERSION
        );
        assert_eq!(
            ready.difficulty,
            fragr_server::protocol::CampaignDifficulty::Severe
        );
        let (mut socket, _) = connect_async(&ready.url).await.unwrap();
        socket
            .send(Message::Text(
                serde_json::to_string(&ClientMessage::Hello {
                    role: Role::Human,
                    name: "Port runner".into(),
                    body: Some(BodyKind::Human),
                    geometry_version: 2,
                    gameplay_version: fragr_server::protocol::GAMEPLAY_VERSION,
                    ticket: None,
                    resume: None,
                })
                .unwrap(),
            ))
            .await
            .unwrap();
        tokio::time::timeout(Duration::from_secs(5), async {
            let mut owner = None;
            let mut mapped = false;
            let mut saw_mission = false;
            let mut saw_loadout = false;
            let mut saw_snapshot = false;
            while let Some(Ok(Message::Text(text))) = socket.next().await {
                match serde_json::from_str::<ServerMessage>(&text).unwrap() {
                    ServerMessage::Welcome {
                        player_id, body, ..
                    } => {
                        owner = player_id;
                        assert_eq!(body, Some(BodyKind::Synthetic));
                    }
                    ServerMessage::MapInfo { m06, .. } => {
                        assert!(m06.is_some());
                        mapped = true;
                    }
                    ServerMessage::Mission { state, .. } => {
                        assert!(mapped);
                        let f = state.m06.as_ref().unwrap();
                        assert_eq!(f.carried_recall_cars, ["roof_car", "platform_car"]);
                        assert_eq!(f.carried_patients, ["edda_team_a"]);
                        assert_eq!(f.carried_photos, 3);
                        assert_eq!(
                            f.carried_released_workers,
                            ["workshop_agent_b", "splice", "workshop_agent_a"]
                        );
                        assert_eq!(f.carried_evacuated_workers, ["workshop_agent_b"]);
                        let run = state.run.unwrap();
                        assert_eq!(
                            (
                                run.id,
                                run.continues,
                                run.level_start_continues,
                                state.attempt
                            ),
                            (
                                run_id,
                                expected_continues,
                                3,
                                4 - u32::from(expected_continues)
                            )
                        );
                        saw_mission = true;
                    }
                    ServerMessage::Loadout(loadout) => {
                        assert_eq!(loadout.grenades, 2);
                        assert_eq!(
                            loadout.selected,
                            fragr_server::protocol::WeaponType::Flechette
                        );
                        assert!(loadout.personal_claims.is_empty());
                        assert_eq!(
                            serde_json::to_value(loadout.ammo).unwrap(),
                            prior["step"]["exit"]["equipment"]["ammo"]
                        );
                        saw_loadout = true;
                    }
                    ServerMessage::Snapshot(snapshot) => {
                        assert!(mapped);
                        if let Some(p) = snapshot.players.iter().find(|p| Some(p.id) == owner) {
                            assert_eq!((p.hp, p.armor, p.weapon.as_str()), (61, 7, "Flechette"));
                            assert_eq!(p.body, Some(BodyKind::Synthetic));
                            saw_snapshot = true;
                        }
                    }
                    _ => {}
                }
                if saw_mission && saw_loadout && saw_snapshot {
                    return;
                }
            }
            panic!("M06 carried entry facts incomplete");
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
        drop(socket);
        drop(child);
        let mut live: serde_json::Value =
            serde_json::from_slice(&std::fs::read(&path).unwrap()).unwrap();
        assert_eq!(live["version"], 7);
        assert_eq!(live["remaining_continues"], expected_continues);
        assert_eq!(live["level_start_continues"], 3);
        assert_eq!(live["m05_outcome"], prior["m05_outcome"]);
        assert_eq!(live["step"]["entry"]["equipment"]["grenades"], 2);
        assert_eq!(live["step"]["mission"], "port_of_entry");
        live["remaining_continues"] = 1.into();
        std::fs::write(&path, serde_json::to_vec(&live).unwrap()).unwrap();
    }
    let archives: Vec<_> = std::fs::read_dir(&directory)
        .unwrap()
        .filter_map(Result::ok)
        .filter(|p| p.file_name().to_string_lossy().starts_with("run.prior-"))
        .collect();
    assert_eq!(archives.len(), 1);
    assert_eq!(std::fs::read(archives[0].path()).unwrap(), bytes);
    assert_eq!(preview(&directory)["continues"], 1);
    std::fs::remove_dir_all(directory).unwrap();
}

#[tokio::test]
async fn completed_v5_m04_run_promotes_once_and_retains_choices_at_m05_entry() {
    let directory = std::env::temp_dir().join(format!("fragr-m05-carry-{}", uuid::Uuid::new_v4()));
    std::fs::create_dir_all(&directory).unwrap();
    let source_hash = fragr_server::maps::RuntimeMap::Authored(
        fragr_server::maps::AuthoredSource::Mission(MissionId::NoticeToVacate)
            .load()
            .unwrap(),
    )
    .content_sha256()
    .unwrap();
    let run_id = uuid::Uuid::new_v4();
    let prior = serde_json::json!({
        "version":5,"id":run_id,"starting_continues":3,"remaining_continues":1,"level_start_continues":2,"body":"synthetic",
        "rules":{"difficulty":"severe","revision":3},"content_sha256":source_hash,
        "m03_outcome":{"liberated_cars":["platform_car","roof_car"]},
        "m04_outcome":{"rescued_patients":["patient_a","patient_b"],"photos_completed":3},
        "step":{"kind":"awaiting_mission","completed_mission":"notice_to_vacate","next_mission":"no_forwarding_address",
            "exit":{"hp":61,"armor":7,"equipment":{"selected":"flechette","weapons":["fists","flechette","scatter"],
                "ammo":[{"pool":"bullets","rounds":29},{"pool":"shells","rounds":8},{"pool":"cells","rounds":0}],"personal_claims":["m02_rifle"]}}}
    });
    let bytes = serde_json::to_vec(&prior).unwrap();
    let path = directory.join("run.json");
    std::fs::write(&path, &bytes).unwrap();
    assert_eq!(preview(&directory)["mission"], "no_forwarding_address");
    for _ in 0..2 {
        let (mut child, ready) =
            spawn_persistent_mission(&directory, "no_forwarding_address", "resume", None);
        assert_eq!(ready.mission, MissionId::NoForwardingAddress);
        assert_eq!(
            ready.gameplay_version,
            fragr_server::protocol::M05_GAMEPLAY_VERSION
        );
        assert_eq!(
            ready.difficulty,
            fragr_server::protocol::CampaignDifficulty::Severe
        );
        let (mut socket, _) = connect_async(&ready.url).await.unwrap();
        socket
            .send(Message::Text(
                serde_json::to_string(&ClientMessage::Hello {
                    role: Role::Human,
                    name: "Yard runner".into(),
                    body: Some(BodyKind::Human),
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
            let mut owner = None;
            let mut mapped = false;
            while let Some(Ok(Message::Text(text))) = socket.next().await {
                match serde_json::from_str::<ServerMessage>(&text).unwrap() {
                    ServerMessage::Welcome {
                        player_id, body, ..
                    } => {
                        owner = player_id;
                        assert_eq!(body, Some(BodyKind::Synthetic));
                    }
                    ServerMessage::MapInfo { m05, .. } => {
                        assert!(m05.is_some());
                        mapped = true;
                    }
                    ServerMessage::Mission { state, .. } => {
                        assert!(mapped);
                        assert_eq!(
                            state.m05.as_ref().unwrap().carried_recall_cars,
                            ["platform_car", "roof_car"]
                        );
                        assert_eq!(
                            state.m05.as_ref().unwrap().carried_patients,
                            ["patient_a", "patient_b"]
                        );
                        assert_eq!(state.m05.as_ref().unwrap().carried_photos, 3);
                        let run = state.run.unwrap();
                        assert_eq!(
                            (
                                run.id,
                                run.continues,
                                run.level_start_continues,
                                state.attempt
                            ),
                            (run_id, 1, 1, 1)
                        );
                    }
                    ServerMessage::Snapshot(snapshot) => {
                        assert!(mapped);
                        if let Some(player) = snapshot.players.iter().find(|p| Some(p.id) == owner)
                        {
                            assert_eq!(
                                (player.hp, player.armor, player.weapon.as_str()),
                                (61, 7, "Flechette")
                            );
                            assert_eq!(player.body, Some(BodyKind::Synthetic));
                            return;
                        }
                    }
                    _ => {}
                }
            }
            panic!("M05 owner snapshot missing");
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
        drop(socket);
        drop(child);
        let live: serde_json::Value =
            serde_json::from_slice(&std::fs::read(&path).unwrap()).unwrap();
        assert_eq!(live["version"], 7);
        assert_eq!(live["step"]["entry"]["equipment"]["grenades"], 0);
        assert_eq!(live["m04_outcome"], prior["m04_outcome"]);
        assert_eq!(live["step"]["mission"], "no_forwarding_address");
        assert_eq!(
            live["step"]["entry"]["equipment"]["personal_claims"],
            serde_json::json!([])
        );
        assert_eq!(
            live["step"]["entry"]["equipment"]["ammo"],
            prior["step"]["exit"]["equipment"]["ammo"]
        );
    }
    let archives: Vec<_> = std::fs::read_dir(&directory)
        .unwrap()
        .filter_map(Result::ok)
        .filter(|entry| {
            entry
                .file_name()
                .to_string_lossy()
                .starts_with("run.prior-")
        })
        .collect();
    assert_eq!(archives.len(), 1);
    assert_eq!(std::fs::read(archives[0].path()).unwrap(), bytes);
    std::fs::remove_dir_all(directory).unwrap();
}

async fn campaign_run_id(ready: &Ready) -> uuid::Uuid {
    let (mut socket, _) = connect_async(&ready.url).await.unwrap();
    socket
        .send(Message::Text(
            serde_json::to_string(&ClientMessage::Hello {
                body: None,
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
                body: None,
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
                body: None,
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

#[tokio::test]
async fn m02_development_child_serves_the_graybox_without_a_durable_run() {
    let refused = Command::new(env!("CARGO_BIN_EXE_fragr-server"))
        .args(["--local-mission", "persons_unknown", "--run-mode", "new"])
        .current_dir(std::env::temp_dir())
        .env(
            "FRAGR_RUN_DIR",
            std::env::temp_dir().join("fragr-m02-no-run"),
        )
        .env("RUST_LOG", "warn")
        .stdin(Stdio::null())
        .output()
        .unwrap();
    assert!(!refused.status.success());
    assert!(refused.stdout.is_empty(), "no readiness for a refused run");
    let mut child = OwnedChild(
        Command::new(env!("CARGO_BIN_EXE_fragr-server"))
            .args(["--local-mission", "persons_unknown", "--seed", "67"])
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
        .expect("M02 child readiness deadline");
    result.unwrap();
    let ready: Ready = serde_json::from_str(&line).unwrap();
    assert_eq!(ready.mission, MissionId::PersonsUnknown);
    assert_eq!(
        ready.gameplay_version,
        fragr_server::protocol::M05_GAMEPLAY_VERSION
    );
    let (mut old, _) = connect_async(&ready.url).await.unwrap();
    old.send(Message::Text(
        serde_json::to_string(&ClientMessage::Hello {
            body: None,
            role: Role::Spectator,
            name: "Old side ward reader".into(),
            geometry_version: 2,
            gameplay_version: fragr_server::protocol::COMPANION_GAMEPLAY_VERSION,
            ticket: None,
            resume: None,
        })
        .unwrap(),
    ))
    .await
    .unwrap();
    let rejection = tokio::time::timeout(Duration::from_secs(3), old.next())
        .await
        .unwrap()
        .unwrap()
        .unwrap();
    assert!(matches!(
        rejection,
        Message::Text(text)
            if matches!(serde_json::from_str::<ServerMessage>(&text),
                Ok(ServerMessage::Error { code, .. }) if code == "unsupported_gameplay")
    ));
    let (mut socket, _) = connect_async(&ready.url).await.unwrap();
    socket
        .send(Message::Text(
            serde_json::to_string(&ClientMessage::Hello {
                body: None,
                role: Role::Human,
                name: "Ward walker".into(),
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
                    map_id,
                    mission,
                    m02_objectives,
                    ..
                } => {
                    assert_eq!(map_id, 1002);
                    assert!(mission.is_none());
                    assert_eq!(m02_objectives, Some(3));
                    saw_map = true;
                }
                ServerMessage::Mission { state, .. } => {
                    assert!(saw_map);
                    assert_eq!(state.id, MissionId::PersonsUnknown);
                    assert!(state.run.is_none(), "M02 has no durable solo run yet");
                    assert_eq!(state.party.len(), 1);
                    let m02 = state.m02.unwrap();
                    assert!(!m02.ward_secured);
                    assert!(!m02.side_ward_secured);
                    assert_eq!(m02.current.unwrap().id, "ward_reached");
                    return;
                }
                _ => {}
            }
        }
        panic!("child ended before M02 mission state");
    })
    .await
    .unwrap();
    drop(child.0.stdin.take());
    exited(&mut child, &ready, true);
}

#[tokio::test]
async fn m08_development_child_serves_the_archive_to_current_readers_only() {
    let mut child = OwnedChild(
        Command::new(env!("CARGO_BIN_EXE_fragr-server"))
            .args(["--local-mission", "custodian_of_record", "--seed", "8"])
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
        .recv_timeout(Duration::from_secs(30))
        .expect("M08 child readiness deadline");
    result.unwrap();
    let ready: Ready = serde_json::from_str(&line).unwrap();
    assert_eq!(ready.mission, MissionId::CustodianOfRecord);
    assert_eq!(
        ready.gameplay_version,
        fragr_server::protocol::M08_GAMEPLAY_VERSION
    );
    for (version, admitted) in [
        (fragr_server::protocol::CUSTODY_GAMEPLAY_VERSION, false),
        (fragr_server::protocol::GAMEPLAY_VERSION, true),
    ] {
        let (mut socket, _) = connect_async(&ready.url).await.unwrap();
        socket
            .send(Message::Text(
                serde_json::to_string(&ClientMessage::Hello {
                    body: None,
                    role: Role::Spectator,
                    name: "Archive reader".into(),
                    geometry_version: 2,
                    gameplay_version: version,
                    ticket: None,
                    resume: None,
                })
                .unwrap(),
            ))
            .await
            .unwrap();
        let mut saw_archive = false;
        let mut refused = false;
        for _ in 0..6 {
            let Ok(Some(Ok(Message::Text(text)))) =
                tokio::time::timeout(Duration::from_secs(5), socket.next()).await
            else {
                break;
            };
            match serde_json::from_str::<ServerMessage>(&text) {
                Ok(ServerMessage::MapInfo { map_id, m08, .. }) => {
                    saw_archive = map_id == 1008 && m08.is_some_and(|g| !g.seal_open);
                    break;
                }
                Ok(ServerMessage::Error { code, .. }) if code == "unsupported_gameplay" => {
                    refused = true;
                    break;
                }
                _ => {}
            }
        }
        assert_eq!(saw_archive, admitted, "capability {version}");
        assert_eq!(refused, !admitted, "capability {version}");
    }
}
