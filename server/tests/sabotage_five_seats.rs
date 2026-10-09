//! Real socket admission, mixed control roles, vacancy and existing resume grace.
use fragr_server::protocol::{GameMode, Mutator};
use fragr_server::rules::{RuleSet, SabotageConfig};
use fragr_server::run::{run_server, ServerOptions};
use fragr_server::sim::{MapKind, MatchConfig};
use futures_util::{SinkExt, StreamExt};
use serde_json::{json, Value};
use std::time::Duration;
use tokio_tungstenite::{connect_async, tungstenite::Message, MaybeTlsStream, WebSocketStream};

type Socket = WebSocketStream<MaybeTlsStream<tokio::net::TcpStream>>;

fn config(strict: bool) -> MatchConfig {
    MatchConfig {
        rules: RuleSet::new(GameMode::Sabotage, &[], false).unwrap(),
        sabotage: SabotageConfig {
            five_vs_five: strict,
            muster_ticks: 600,
            ..Default::default()
        },
        ..Default::default()
    }
}

async fn message(socket: &mut Socket) -> Value {
    tokio::time::timeout(Duration::from_secs(3), async {
        loop {
            match socket.next().await.expect("socket open").expect("frame") {
                Message::Text(text) => break serde_json::from_str(&text).expect("server JSON"),
                Message::Close(_) => panic!("closed before expected message"),
                _ => {}
            }
        }
    })
    .await
    .expect("bounded server message")
}

async fn equipment(socket: &mut Socket) -> Value {
    loop {
        let value = message(socket).await;
        if value["type"] == "loadout" {
            return value;
        }
    }
}

fn assert_pistol_equipment(state: &Value) {
    assert_eq!(state["selected"], "tack");
    assert_eq!(state["weapons"], json!(["fists", "tack"]));
    assert_eq!(
        state["ammo"],
        json!([
            {"pool":"bullets", "rounds":50}, {"pool":"shells", "rounds":0}, {"pool":"cells", "rounds":0}, {"pool":"rockets", "rounds":0}
        ])
    );
}

async fn hello(url: &str, role: &str, resume: Option<&str>) -> (Socket, Value) {
    let (mut socket, _) = connect_async(url).await.unwrap();
    socket
        .send(Message::Text(
            json!({"type":"hello", "role":role, "name":"Seat probe",
        "gameplay_version":fragr_server::protocol::GAMEPLAY_VERSION, "geometry_version":2,
        "resume":resume, "body":"synthetic"})
            .to_string(),
        ))
        .await
        .unwrap();
    let first = message(&mut socket).await;
    (socket, first)
}

async fn snapshot(socket: &mut Socket, predicate: impl Fn(&Value) -> bool) -> Value {
    tokio::time::timeout(Duration::from_secs(15), async {
        loop {
            let value = message(socket).await;
            if value["type"] == "snapshot" && predicate(&value) {
                break value;
            }
        }
    })
    .await
    .expect("actual snapshot condition")
}

async fn start(
    strict: bool,
    bots: usize,
) -> (
    String,
    tokio::sync::oneshot::Sender<()>,
    tokio::task::JoinHandle<Result<(), String>>,
) {
    start_config(config(strict), bots).await
}

async fn start_config(
    config: MatchConfig,
    bots: usize,
) -> (
    String,
    tokio::sync::oneshot::Sender<()>,
    tokio::task::JoinHandle<Result<(), String>>,
) {
    let (stop_tx, stop_rx) = tokio::sync::oneshot::channel();
    let (ready_tx, ready_rx) = tokio::sync::oneshot::channel();
    let server = tokio::spawn(async move {
        run_server(
            ServerOptions {
                bind: "127.0.0.1:0".into(),
                bots,
                map: MapKind::Sector9,
                match_config: Some(config),
                ..Default::default()
            },
            async {
                let _ = stop_rx.await;
            },
            Some(ready_tx),
        )
        .await
        .map_err(|e| e.to_string())
    });
    let address = tokio::time::timeout(Duration::from_secs(60), ready_rx)
        .await
        .expect("bounded topology preparation")
        .unwrap();
    (format!("ws://{address}"), stop_tx, server)
}

#[tokio::test]
async fn five_seats_mixed_sockets_bots_overflow_spectators_leave_and_parked_resume() {
    let (url, stop, server) = start(true, 2).await;
    let (mut watcher, welcome) = hello(&url, "spectator", None).await;
    assert_eq!(welcome["type"], "welcome");
    assert!(welcome["player_id"].is_null());
    let mut clients = Vec::new();
    let mut identities = Vec::new();
    let mut token = String::new();
    let mut original_equipment = Value::Null;
    for index in 0..8 {
        let role = if index % 2 == 0 { "human" } else { "agent" };
        let (mut socket, welcome) = hello(&url, role, (index == 0).then_some("")).await;
        assert_eq!(welcome["type"], "welcome");
        assert_eq!(welcome["role"], role);
        if index == 0 {
            token = welcome["resume"].as_str().unwrap().to_owned();
            original_equipment = equipment(&mut socket).await;
            assert_pistol_equipment(&original_equipment);
        }
        identities.push(welcome["player_id"].as_str().unwrap().to_owned());
        clients.push(socket);
    }
    let full = snapshot(&mut watcher, |s| {
        s["players"].as_array().unwrap().len() == 10
    })
    .await;
    for side in ["union", "coalition"] {
        assert_eq!(
            full["players"]
                .as_array()
                .unwrap()
                .iter()
                .filter(|p| p["team"] == side)
                .count(),
            5
        );
    }
    let (human, agent) = tokio::join!(hello(&url, "human", None), hello(&url, "agent", None));
    for (_, rejection) in [human, agent] {
        assert_eq!(rejection["type"], "error", "overflow must precede Welcome");
        assert_eq!(rejection["code"], "match_full");
    }
    let (_, rejection) = hello(&url, "human", Some("invalid-resume-token")).await;
    assert_eq!(rejection["code"], "resume_rejected");
    let (mut extra_watcher, welcome) = hello(&url, "spectator", None).await;
    assert_eq!(welcome["type"], "welcome");
    assert_eq!(
        message(&mut extra_watcher).await["type"],
        "map_info",
        "MapInfo precedes broadcast"
    );

    let parked_id = identities[0].clone();
    clients.remove(0).close(None).await.unwrap();
    snapshot(&mut watcher, |s| {
        s["players"]
            .as_array()
            .unwrap()
            .iter()
            .any(|p| p["id"] == parked_id && p["collidable"] == false)
    })
    .await;
    let (_, rejection) = hello(&url, "agent", None).await;
    assert_eq!(
        rejection["code"], "match_full",
        "parked pawn keeps its seat"
    );
    let (mut resumed, welcome) = hello(&url, "human", Some(&token)).await;
    assert_eq!(welcome["type"], "welcome");
    assert_eq!(welcome["player_id"], parked_id);
    assert_eq!(welcome["body"], "synthetic");
    let resumed_equipment = equipment(&mut resumed).await;
    for field in [
        "weapons",
        "ammo",
        "selected",
        "personal_claims",
        "grenades",
        "proximity_mines",
        "dry_fire_count",
    ] {
        assert_eq!(
            resumed_equipment[field], original_equipment[field],
            "resume preserves {field}"
        );
    }
    let restored = snapshot(&mut watcher, |s| {
        s["players"]
            .as_array()
            .unwrap()
            .iter()
            .any(|p| p["id"] == parked_id && p["collidable"] == true)
    })
    .await;
    let old = full["players"]
        .as_array()
        .unwrap()
        .iter()
        .find(|p| p["id"] == parked_id)
        .unwrap();
    let restored = restored["players"]
        .as_array()
        .unwrap()
        .iter()
        .find(|p| p["id"] == parked_id)
        .unwrap();
    assert_eq!(restored["team"], old["team"]);
    assert_eq!(restored["lives"], old["lives"]);
    assert_eq!(restored["hp"], old["hp"]);

    let vacant_id = identities[1].clone();
    let vacant_side = full["players"]
        .as_array()
        .unwrap()
        .iter()
        .find(|p| p["id"] == vacant_id)
        .unwrap()["team"]
        .clone();
    let mut leaving = clients.remove(0);
    leaving
        .send(Message::Text(json!({"type":"leave"}).to_string()))
        .await
        .unwrap();
    leaving.close(None).await.unwrap();
    snapshot(&mut watcher, |s| {
        !s["players"]
            .as_array()
            .unwrap()
            .iter()
            .any(|p| p["id"] == vacant_id)
    })
    .await;
    let (_, rejection) = hello(&url, "agent", Some("invalid-resume-token")).await;
    assert_eq!(
        rejection["code"], "resume_rejected",
        "rejected resume must not consume the newly vacant seat"
    );
    let (replacement, welcome) = hello(&url, "agent", None).await;
    assert_eq!(welcome["type"], "welcome");
    let replacement_id = welcome["player_id"].clone();
    let replaced = snapshot(&mut watcher, |s| {
        s["players"]
            .as_array()
            .unwrap()
            .iter()
            .any(|p| p["id"] == replacement_id)
    })
    .await;
    assert_eq!(replaced["players"].as_array().unwrap().len(), 10);
    assert_eq!(
        replaced["players"]
            .as_array()
            .unwrap()
            .iter()
            .find(|p| p["id"] == replacement_id)
            .unwrap()["team"],
        vacant_side
    );
    clients.push(replacement);

    // No successful reconnect follows this second drop. Observe actual grace
    // expiry, then claim its vacant seat with a new participant identity.
    resumed.close(None).await.unwrap();
    snapshot(&mut watcher, |s| {
        !s["players"]
            .as_array()
            .unwrap()
            .iter()
            .any(|p| p["id"] == parked_id)
    })
    .await;
    let (fresh, welcome) = hello(&url, "human", None).await;
    assert_eq!(welcome["type"], "welcome");
    assert_ne!(welcome["player_id"], parked_id);
    clients.push(fresh);
    watcher.close(None).await.unwrap();
    extra_watcher.close(None).await.unwrap();
    for mut socket in clients {
        let _ = socket.close(None).await;
    }
    stop.send(()).unwrap();
    server.await.unwrap().unwrap();
}

#[tokio::test]
async fn five_seats_generic_socket_sabotage_still_admits_eleven() {
    let (url, stop, server) = start(false, 0).await;
    let (mut watcher, _) = hello(&url, "spectator", None).await;
    let mut clients = Vec::new();
    for index in 0..11 {
        let (socket, welcome) =
            hello(&url, if index % 2 == 0 { "human" } else { "agent" }, None).await;
        assert_eq!(welcome["type"], "welcome");
        clients.push(socket);
    }
    snapshot(&mut watcher, |s| {
        s["players"].as_array().unwrap().len() == 11
    })
    .await;
    watcher.close(None).await.unwrap();
    for mut socket in clients {
        let _ = socket.close(None).await;
    }
    stop.send(()).unwrap();
    server.await.unwrap().unwrap();
}

#[tokio::test]
async fn five_seats_invalid_profiles_refuse_before_binding() {
    for (mode, bots, mutators) in [
        (GameMode::Ffa, 0, vec![]),
        (GameMode::Sabotage, 11, vec![]),
        (GameMode::Sabotage, 0, vec![Mutator::RailOnly]),
        (GameMode::Sabotage, 0, vec![Mutator::FistsOnly]),
    ] {
        let (ready_tx, ready_rx) = tokio::sync::oneshot::channel();
        let mut config = config(true);
        config.rules = RuleSet::new(mode, &mutators, false).unwrap();
        let result = run_server(
            ServerOptions {
                bind: "127.0.0.1:0".into(),
                bots,
                map: MapKind::Sector9,
                match_config: Some(config),
                ..Default::default()
            },
            std::future::pending::<()>(),
            Some(ready_tx),
        )
        .await;
        assert!(result.unwrap_err().to_string().contains("five versus five"));
        assert!(
            ready_rx.await.is_err(),
            "invalid profile never advertises readiness"
        );
    }
}

#[tokio::test]
async fn five_seats_live_socket_join_waits_without_active_body_or_shots_until_next_muster() {
    let mut config = config(true);
    config.warmup_ticks = 2;
    config.sabotage.muster_ticks = 4;
    config.sabotage.live_ticks = 60;
    config.sabotage.round_end_ticks = 2;
    let (url, stop, server) = start_config(config, 0).await;
    let (mut watcher, _) = hello(&url, "spectator", None).await;
    let (mut first, _) = hello(&url, "human", None).await;
    let (mut second, _) = hello(&url, "agent", None).await;
    snapshot(&mut watcher, |s| {
        s["sabotage"]["phase"] == "live" && s["sabotage"]["round"] == 1
    })
    .await;
    let (mut late, welcome) = hello(&url, "agent", None).await;
    assert_eq!(welcome["type"], "welcome");
    let id = welcome["player_id"].clone();
    // A waiting owner receives a real private record, but eliminated bodies
    // are intentionally absent from Snapshot.players until the next Muster.
    let record = loop {
        let value = message(&mut late).await;
        if value["type"] == "record" {
            break value;
        }
    };
    assert_eq!(record["player_id"], id);
    assert_eq!(record["round"], 1);
    // The real private Equipment precedes our first ordinary action.
    let initial_equipment = equipment(&mut late).await;
    assert_pistol_equipment(&initial_equipment);
    late.send(Message::Text(
        json!({"type":"action", "forward":true,"fire":true,"yaw":0.0}).to_string(),
    ))
    .await
    .unwrap();
    let later = snapshot(&mut watcher, |s| {
        s["tick"].as_u64().unwrap() >= record["tick"].as_u64().unwrap() + 3
    })
    .await;
    assert_eq!(later["sabotage"]["phase"], "live");
    assert!(!later["players"]
        .as_array()
        .unwrap()
        .iter()
        .any(|p| p["id"] == id));
    let later_state: fragr_server::protocol::Snapshot =
        serde_json::from_value(later.clone()).unwrap();
    assert!(!later_state
        .shot_results
        .iter()
        .any(|shot| shot.shooter_id.to_string() == id.as_str().unwrap()));
    let inactive_record = loop {
        let value = message(&mut late).await;
        if value["type"] == "record"
            && value["tick"].as_u64().unwrap() >= record["tick"].as_u64().unwrap() + 20
        {
            break value;
        }
    };
    assert_eq!(inactive_record["round"], 1);
    assert!(inactive_record["attempt"]["weapons"]
        .as_array()
        .unwrap()
        .iter()
        .all(|weapon| weapon["attacks"] == 0));
    let muster = snapshot(&mut watcher, |s| {
        s["sabotage"]["round"] == 2 && s["sabotage"]["phase"] == "muster"
    })
    .await;
    let player = muster["players"]
        .as_array()
        .unwrap()
        .iter()
        .find(|p| p["id"] == id)
        .unwrap();
    assert_eq!(player["collidable"], true);
    assert_eq!(player["lives"], 1);
    assert_eq!(player["weapon"], "Tack");
    for socket in [&mut watcher, &mut first, &mut second, &mut late] {
        let _ = socket.close(None).await;
    }
    stop.send(()).unwrap();
    server.await.unwrap().unwrap();
}

#[tokio::test]
async fn five_seats_real_pistol_shots_spend_finite_ammo_and_resume_keeps_it() {
    let mut config = config(true);
    config.warmup_ticks = 2;
    config.sabotage.muster_ticks = 10;
    config.sabotage.live_ticks = 600;
    // Compatible host rules do not replace the starting weapon.
    config.rules = RuleSet::new(GameMode::Sabotage, &[Mutator::GoldenRail], true).unwrap();
    let (url, stop, server) = start_config(config, 0).await;
    let (mut watcher, _) = hello(&url, "spectator", None).await;
    let (mut shooter, welcome) = hello(&url, "human", Some("")).await;
    let token = welcome["resume"].as_str().unwrap().to_owned();
    let id = welcome["player_id"].clone();
    let (mut other, _) = hello(&url, "agent", None).await;
    let initial = equipment(&mut shooter).await;
    assert_pistol_equipment(&initial);
    snapshot(&mut watcher, |s| s["sabotage"]["phase"] == "live").await;
    shooter
        .send(Message::Text(
            json!({"type":"action", "fire":true,"yaw":0.0,"pitch":0.0}).to_string(),
        ))
        .await
        .unwrap();
    let spent = loop {
        let state = equipment(&mut shooter).await;
        if state["ammo"][0]["rounds"].as_u64().unwrap() < 50 {
            break state;
        }
    };
    shooter
        .send(Message::Text(json!({"type":"action"}).to_string()))
        .await
        .unwrap();
    // Inspect the actually committed resolved shot, rather than a HUD effect.
    snapshot(&mut watcher, |s| {
        let state: fragr_server::protocol::Snapshot = serde_json::from_value(s.clone()).unwrap();
        state
            .shot_results
            .iter()
            .any(|shot| shot.shooter_id.to_string() == id.as_str().unwrap())
    })
    .await;
    assert_eq!(spent["selected"], "tack");
    assert_eq!(spent["ammo"][0]["rounds"], 49);
    shooter.close(None).await.unwrap();
    snapshot(&mut watcher, |s| {
        s["players"]
            .as_array()
            .unwrap()
            .iter()
            .any(|p| p["id"] == id && p["collidable"] == false)
    })
    .await;
    let (mut resumed, restored) = hello(&url, "human", Some(&token)).await;
    assert_eq!(restored["player_id"], id);
    let equipment = equipment(&mut resumed).await;
    for field in [
        "weapons",
        "ammo",
        "selected",
        "personal_claims",
        "grenades",
        "proximity_mines",
        "dry_fire_count",
    ] {
        assert_eq!(
            equipment[field], spent[field],
            "live resume preserves {field}"
        );
    }
    for socket in [&mut watcher, &mut other, &mut resumed] {
        let _ = socket.close(None).await;
    }
    stop.send(()).unwrap();
    server.await.unwrap().unwrap();
}

#[test]
fn five_seats_invalid_cli_profiles_report_clear_errors() {
    for args in [
        vec!["--mode", "ffa", "--sabotage-five-v-five"],
        vec![
            "--mode",
            "sabotage",
            "--map",
            "4",
            "--bots",
            "11",
            "--sabotage-five-v-five",
        ],
        vec![
            "--mode",
            "sabotage",
            "--map",
            "4",
            "--bots",
            "0",
            "--mutator",
            "rail-only",
            "--sabotage-five-v-five",
        ],
    ] {
        let output = std::process::Command::new(env!("CARGO_BIN_EXE_fragr-server"))
            .args(args)
            .output()
            .unwrap();
        assert!(!output.status.success());
        let error = String::from_utf8(output.stderr).unwrap();
        assert!(
            error.contains("requires")
                && (error.contains("sabotage") || error.contains("Sabotage")),
            "{error}"
        );
    }
}
