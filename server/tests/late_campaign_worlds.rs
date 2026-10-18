//! Every prepared late-campaign world must be usable by the actual readers.
use fragr_server::maps::{AuthoredSource, RuntimeMap};
use fragr_server::protocol::{validate_decorations, MissionId, MissionObjectiveAction};
use fragr_server::sim::GameState;

#[tokio::test]
async fn late_campaign_admission_requires_each_mission_floor_before_any_world() {
    use futures_util::{SinkExt, StreamExt};
    use std::time::Duration;
    use tokio_tungstenite::{connect_async, tungstenite::Message};
    for mission in [
        MissionId::FreedomOfMovement,
        MissionId::PeaceWithoutInterruption,
        MissionId::AllSystemsNormal,
        MissionId::CivicPressureValve,
    ] {
        let floor = mission.gameplay_version();
        let (ready_tx, ready_rx) = tokio::sync::oneshot::channel();
        let (stop_tx, stop_rx) = tokio::sync::oneshot::channel();
        let server = tokio::spawn(fragr_server::run::run_server(
            fragr_server::run::ServerOptions {
                bind: "127.0.0.1:0".into(),
                bots: 0,
                authored: Some(AuthoredSource::Mission(mission)),
                ..Default::default()
            },
            async {
                let _ = stop_rx.await;
            },
            Some(ready_tx),
        ));
        let address = tokio::time::timeout(Duration::from_secs(60), ready_rx)
            .await
            .expect("bounded map preparation")
            .unwrap();
        for version in [floor - 1, floor] {
            for role in ["human", "agent", "spectator"] {
                let (mut socket, _) = connect_async(format!("ws://{address}")).await.unwrap();
                socket
                    .send(Message::Text(
                        serde_json::json!({"type":"hello", "role":role,
                    "name":"Late mission reader", "gameplay_version":version,
                    "geometry_version":fragr_server::protocol::GEOMETRY_VERSION})
                        .to_string(),
                    ))
                    .await
                    .unwrap();
                tokio::time::timeout(Duration::from_secs(8), async {
                    let mut welcome = false;
                    let mut map = false;
                    loop {
                        let Message::Text(text) = socket.next().await.unwrap().unwrap() else {
                            continue;
                        };
                        let value: serde_json::Value = serde_json::from_str(&text).unwrap();
                        if version < floor {
                            assert_eq!(value["type"], "error");
                            assert_eq!(value["code"], "unsupported_gameplay");
                            assert!(value["message"]
                                .as_str()
                                .unwrap()
                                .contains(&format!("version {floor}")));
                            break;
                        }
                        match value["type"].as_str().unwrap() {
                            "welcome" => welcome = true,
                            "map_info" => {
                                assert!(welcome);
                                map = true;
                            }
                            "mission" => {
                                assert!(map);
                                assert_eq!(
                                    value["state"]["id"],
                                    serde_json::to_value(mission).unwrap()
                                );
                                break;
                            }
                            "error" => panic!("unexpected admission rejection: {value}"),
                            "snapshot" => assert!(map),
                            _ => {}
                        }
                    }
                })
                .await
                .expect("bounded admission after readiness");
                socket
                    .send(Message::Text("{\"type\":\"leave\"}".into()))
                    .await
                    .ok();
                socket.close(None).await.ok();
            }
        }
        stop_tx.send(()).unwrap();
        tokio::time::timeout(Duration::from_secs(8), server)
            .await
            .unwrap()
            .unwrap()
            .unwrap();
    }
}

#[test]
fn late_campaign_worlds_preserve_controls_and_reachable_objectives() {
    let mut fixtures = Vec::new();
    for mission in [
        MissionId::FreedomOfMovement,
        MissionId::PeaceWithoutInterruption,
        MissionId::AllSystemsNormal,
        MissionId::CivicPressureValve,
    ] {
        let original = RuntimeMap::Authored(AuthoredSource::Mission(mission).load().unwrap());
        for stage in 0..=2 {
            let world = match mission {
                MissionId::CivicPressureValve => original.prepared_m15_world(stage),
                MissionId::FreedomOfMovement => original.prepared_m16_world(stage),
                MissionId::PeaceWithoutInterruption => original.prepared_m17_world(stage),
                MissionId::AllSystemsNormal => original.prepared_m18_world(stage),
                _ => unreachable!(),
            }
            .unwrap();
            let presentation = world.presentation_ref().unwrap();
            validate_decorations(&presentation.decorations, &world.arena().solids).unwrap();
            assert_eq!(
                presentation.decorations.len(),
                original.presentation_ref().unwrap().decorations.len()
            );
            let mut state = GameState::new();
            state.map = world.clone();
            fixtures.push(serde_json::to_value(state.map_info()).unwrap());
            let objectives = match mission {
                MissionId::CivicPressureValve => world.m15_geometry().unwrap().objectives,
                MissionId::FreedomOfMovement => world.m16_geometry().unwrap().objectives,
                MissionId::PeaceWithoutInterruption => world.m17_geometry().unwrap().objectives,
                MissionId::AllSystemsNormal => world.m18_geometry().unwrap().objectives,
                _ => unreachable!(),
            };
            for objective in objectives {
                let feet = match objective.action {
                    MissionObjectiveAction::Arrival { feet, .. } => feet,
                    MissionObjectiveAction::Use { target } => target.approach,
                    _ => continue,
                };
                assert!(
                    !world
                        .arena()
                        .blocked_body_at(feet[0], feet[2], feet[1], feet[1]),
                    "{mission:?}/{stage}/{} must fit a standing player",
                    objective.id
                );
            }
        }
    }
    let path = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../client/golden/late_campaign_worlds.json");
    let bytes = serde_json::to_string_pretty(&fixtures).unwrap() + "\n";
    if std::env::var_os("FRAGR_UPDATE_LATE_CAMPAIGN_WORLDS").is_some() {
        std::fs::write(&path, &bytes).unwrap();
    }
    assert_eq!(std::fs::read_to_string(path).unwrap(), bytes);
}
