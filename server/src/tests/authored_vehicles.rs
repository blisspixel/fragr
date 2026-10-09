use crate::maps::AuthoredMap;
use crate::protocol::{Action, Role, VehicleSeat};
use crate::session::GameSession;
use serde_json::json;
use uuid::Uuid;

fn document() -> serde_json::Value {
    json!({"version":1,"map_id":1014,"name":"Vehicle development fixture","half_extent":12,
        "ground":"concrete","solids":[],"equipment":"discovery",
        "spawns":[{"id":"entry","feet":[0,0,-1.75],"yaw":0}],
        "landmarks":[{"id":"exit","feet":[0,0,8]}],
        "vehicles":[{"id":"jeep","feet":[0,0,0],"yaw":0}],
        "encounters":[{"id":"first","regions":[{"min":[-12,0,-12],"max":[12,2,12]}],
            "enemies":[{"id":"clerk","kind":"clerk","feet":[8,0,8],"yaw":0}]},
            {"id":"second","after":"first","regions":[{"min":[-12,0,-12],"max":[12,2,12]}],
            "enemies":[{"id":"second_clerk","kind":"clerk","feet":[-8,0,8],"yaw":0}]}]})
}

#[test]
fn authored_fleet_loads_before_first_tick_and_retry_restores_it_without_rewinding_input() {
    let map = AuthoredMap::read(serde_json::to_vec(&document()).unwrap().as_slice()).unwrap();
    let mut session = GameSession::with_authored_map(map);
    assert_eq!(session.state.vehicles.len(), 1);
    let id = Uuid::from_u128(1414);
    session.state.add_player(id, "Driver".into(), Role::Human);
    session.state.set_action(
        id,
        Action {
            interact: true,
            seq: Some(42),
            ..Default::default()
        },
    );
    session.tick_messages(0.05);
    assert_eq!(
        session.state.vehicle_seat(id),
        Some((0, VehicleSeat::Driver))
    );
    assert_eq!(
        session
            .state
            .players
            .iter()
            .filter(|p| p.is_campaign_enemy())
            .count(),
        1,
        "later group must stay unplaced until its predecessor completes"
    );
    session.state.vehicles[0].damage(400, None);
    let tick = session.state.tick;
    session
        .state
        .players
        .iter_mut()
        .find(|p| p.id == id)
        .unwrap()
        .hp = 0;
    session.tick_messages(0.05);
    let jeep = &session.state.vehicles[0].state;
    assert_eq!(jeep.position, [0.0; 3]);
    assert_eq!(jeep.hp, 400);
    assert_eq!(jeep.driver, None);
    assert_eq!(jeep.gunner, None);
    assert_eq!(jeep.gun_heat, 0.0);
    assert!(session.state.tick > tick);
    assert_eq!(
        session
            .state
            .players
            .iter()
            .find(|p| p.id == id)
            .unwrap()
            .last_input_seq,
        Some(42)
    );
    assert!(!session.state.encounters.is_complete(0));
    assert!(!session.state.players.iter().any(|p| p.is_campaign_enemy()));
}

#[test]
fn authored_fleet_departure_restores_owned_seats_and_destroyed_vehicles() {
    let map = AuthoredMap::read(serde_json::to_vec(&document()).unwrap().as_slice()).unwrap();
    let mut session = GameSession::with_authored_map(map);
    let id = Uuid::from_u128(1415);
    session.state.add_player(id, "Driver".into(), Role::Agent);
    session.tick_messages(0.05);
    session.state.vehicles[0].state.position = [4.0, 0.0, 4.0];
    session.state.vehicles[0].damage(400, None);
    session.state.remove_player(id);
    assert_eq!(session.state.vehicles[0].state.position, [0.0; 3]);
    assert_eq!(session.state.vehicles[0].state.hp, 400);
    assert!(session.state.players.is_empty());
}

#[test]
fn authored_jeep_boards_switches_and_resolves_mounted_fire_against_a_flying_notary() {
    let mut doc = document();
    doc["encounters"] = json!([{"id":"hover_lesson",
        "regions":[{"min":[-12,0,-12],"max":[12,2,12]}],
        "enemies":[{"id":"notary","kind":"notary","feet":[8,3,8],"yaw":0,
            "hover":{"volume":{"min":[7,2.5,7],"max":[9,4,9]},"band":[2.5,4],
                "patrol":[[7.5,3,7.5],[8.5,3,8.5]],"approach":[5,0,5]}}]}]);
    let map = AuthoredMap::read(serde_json::to_vec(&doc).unwrap().as_slice()).unwrap();
    let mut session = GameSession::with_authored_map(map);
    session.state.seed(42);
    let id = Uuid::from_u128(1439);
    session
        .state
        .add_player(id, "Mounted lesson".into(), Role::Human);
    session.state.set_action(
        id,
        Action {
            interact: true,
            ..Default::default()
        },
    );
    session.tick_messages(0.05);
    assert_eq!(
        session.state.vehicle_seat(id),
        Some((0, VehicleSeat::Driver))
    );
    session.state.set_action(
        id,
        Action {
            seat: Some(VehicleSeat::Gunner),
            ..Default::default()
        },
    );
    session.tick_messages(0.05);
    assert_eq!(
        session.state.vehicle_seat(id),
        Some((0, VehicleSeat::Gunner))
    );
    let target = session
        .state
        .players
        .iter()
        .find(|p| p.is_campaign_enemy())
        .unwrap()
        .id;
    let mut mounted_hits = 0;
    for _ in 0..300 {
        session.state.set_action(
            id,
            Action {
                fire: true,
                look_at: Some(crate::protocol::LookAt {
                    player_id: Some(target),
                    ..Default::default()
                }),
                ..Default::default()
            },
        );
        session.tick_messages(0.05);
        mounted_hits += session
            .state
            .shot_results
            .iter()
            .filter(|shot| {
                shot.shooter_id == id
                    && shot.target_id == Some(target)
                    && shot.damage > 0
                    && shot
                        .trace
                        .as_ref()
                        .is_some_and(|trace| trace.vehicle_id == Some(1))
            })
            .count();
        if session.state.encounters.is_complete(0) {
            break;
        }
    }
    assert!(
        mounted_hits > 0,
        "ordinary mount must hit the raised airborne body"
    );
    assert!(session.state.encounters.is_complete(0));
    assert_eq!(session.state.vehicles[0].state.position, [0.0; 3]);
    session.state.set_action(
        id,
        Action {
            interact: true,
            ..Default::default()
        },
    );
    session.tick_messages(0.05);
    assert_eq!(session.state.vehicle_seat(id), None);
    assert!(
        session
            .state
            .players
            .iter()
            .find(|p| p.id == id)
            .unwrap()
            .hp
            > 0
    );
}

#[tokio::test]
async fn authored_fleet_requires_vehicle_capability_for_every_role_and_sends_geometry_first() {
    use futures_util::{SinkExt, StreamExt};
    use tokio_tungstenite::{connect_async, tungstenite::Message};
    let path = std::env::temp_dir().join(format!("fragr-vehicles-{}.json", Uuid::new_v4()));
    std::fs::write(&path, serde_json::to_vec(&document()).unwrap()).unwrap();
    let (ready_tx, ready_rx) = tokio::sync::oneshot::channel();
    let (stop_tx, stop_rx) = tokio::sync::oneshot::channel();
    let server = tokio::spawn(crate::run::run_server(
        crate::run::ServerOptions {
            bind: "127.0.0.1:0".into(),
            bots: 0,
            authored: Some(crate::maps::AuthoredSource::File(path.clone())),
            ..Default::default()
        },
        async {
            let _ = stop_rx.await;
        },
        Some(ready_tx),
    ));
    let address = ready_rx.await.unwrap();
    for role in ["human", "agent", "spectator"] {
        for version in [38, 39, crate::protocol::ASSESSOR_GAMEPLAY_VERSION] {
            let (mut socket, _) = connect_async(format!("ws://{address}")).await.unwrap();
            socket
                .send(Message::Text(
                    json!({"type":"hello","role":role,"name":"Vehicle probe",
                "gameplay_version":version,"geometry_version":crate::protocol::GEOMETRY_VERSION})
                    .to_string(),
                ))
                .await
                .unwrap();
            tokio::time::timeout(std::time::Duration::from_secs(3), async {
                let mut saw_map = false;
                while let Some(message) = socket.next().await {
                    let Message::Text(body) = message.unwrap() else {
                        continue;
                    };
                    let value: serde_json::Value = serde_json::from_str(&body).unwrap();
                    if value["type"] == "error" {
                        assert!(
                            version < crate::protocol::ASSESSOR_GAMEPLAY_VERSION,
                            "{value}"
                        );
                        assert_eq!(value["code"], "unsupported_gameplay");
                        assert!(value["message"].as_str().unwrap().contains(&format!(
                            "version {}",
                            crate::protocol::ASSESSOR_GAMEPLAY_VERSION
                        )));
                        return;
                    }
                    if value["type"] == "map_info" {
                        saw_map = true;
                    }
                    if value["type"] == "snapshot" {
                        assert_eq!(version, crate::protocol::ASSESSOR_GAMEPLAY_VERSION);
                        assert!(saw_map, "vehicle snapshot overtook initial geometry");
                        assert_eq!(value["vehicles"].as_array().unwrap().len(), 1);
                        return;
                    }
                }
                panic!("connection ended without admission or refusal");
            })
            .await
            .unwrap();
            socket.close(None).await.unwrap();
        }
    }
    stop_tx.send(()).unwrap();
    server.await.unwrap().unwrap();
    std::fs::remove_file(path).unwrap();
}
