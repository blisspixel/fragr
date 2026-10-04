//! Real server movement and damage for the committed powered-armor role.
use crate::maps::AuthoredMap;
use crate::protocol::{Action, CampaignActor, EnemyPhase, LookAt, Role, WeaponType};
use crate::session::GameSession;
use crate::sim::PLAYER_FLOOR_Y;
use serde_json::json;
use uuid::Uuid;

fn document(elevated: bool, backstop: bool) -> serde_json::Value {
    let floor = if elevated { 4.0 } else { 0.0 };
    let mut solids = Vec::new();
    if elevated {
        solids.push(
            json!({"id":"landing","min":[-6,3.5,-5],"max":[2,4,5],"surface":"service_steel"}),
        );
    }
    if backstop {
        solids.push(json!({"id":"backstop","min":[2.5,0,-2],"max":[3,3,2],"surface":"concrete"}));
    }
    json!({
        "version":1,"map_id":1099,"name":"Enforcer movement fixture","half_extent":12,
        "ground":"concrete","equipment":"discovery","solids":solids,
        "spawns":[{"id":"entry","feet":[1,floor,0],"yaw":0}],
        "landmarks":[{"id":"landing_route","feet":[-4,floor,3]}],
        "encounters":[{"id":"charge_lesson","regions":[{"min":[-6,floor,-5],"max":[2,floor+2.0,5]}],
            "enemies":[{"id":"enforcer","kind":"enforcer","feet":[-2,floor,0],"yaw":0}]}]
    })
}

fn fixture(elevated: bool, backstop: bool) -> (GameSession, Uuid, Uuid) {
    let doc = document(elevated, backstop);
    let map = AuthoredMap::read(serde_json::to_vec(&doc).unwrap().as_slice()).unwrap();
    let mut session = GameSession::with_authored_map(map);
    session.state.seed(42);
    let player = Uuid::from_u128(1099);
    session
        .state
        .add_player(player, "Walker".into(), Role::Human);
    advance(&mut session, 1);
    let enemy = session
        .state
        .players
        .iter()
        .find(|p| p.is_campaign_enemy())
        .unwrap()
        .id;
    (session, player, enemy)
}

fn advance(session: &mut GameSession, ticks: usize) {
    for _ in 0..ticks {
        session.tick_messages(0.05);
    }
}
fn body(session: &GameSession, id: Uuid) -> &crate::sim::Player {
    session.state.players.iter().find(|p| p.id == id).unwrap()
}
fn phase(session: &GameSession, id: Uuid) -> EnemyPhase {
    match body(session, id).campaign.unwrap() {
        CampaignActor::Union { phase, .. } => phase,
        _ => panic!("expected Union role"),
    }
}
fn until(session: &mut GameSession, id: Uuid, expected: EnemyPhase) {
    for _ in 0..80 {
        if phase(session, id) == expected {
            return;
        }
        advance(session, 1);
    }
    panic!("Enforcer never reached {expected:?}");
}

#[test]
fn actual_charge_hits_once_and_knockback_stops_at_authoritative_cover() {
    for backstop in [false, true] {
        let (mut session, player, enemy) = fixture(false, backstop);
        until(&mut session, enemy, EnemyPhase::Windup);
        assert_eq!(body(&session, enemy).hp, 140);
        assert_eq!(body(&session, enemy).weapon, WeaponType::Fists);
        assert_eq!(body(&session, player).hp, 100);
        until(&mut session, enemy, EnemyPhase::Charging);
        let mut contacts = 0;
        for _ in 0..14 {
            advance(&mut session, 1);
            contacts += session
                .state
                .shot_results
                .iter()
                .filter(|s| s.shooter_id == enemy && s.target_id == Some(player))
                .count();
        }
        assert_eq!(contacts, 1);
        assert_eq!(body(&session, player).hp, 70);
        let x = body(&session, player).x;
        assert!(x > 1.0 && x <= 2.501, "real shove {x}");
        if backstop {
            assert!(x <= 2.0001, "shove crossed cover: {x}");
        }
        assert_eq!(body(&session, player).z, 0.0);
    }
}

#[test]
fn ordinary_sidestep_baits_real_descent_without_a_fake_player_frag() {
    let (mut session, player, enemy) = fixture(true, false);
    until(&mut session, enemy, EnemyPhase::Windup);
    session.state.set_action(
        player,
        Action {
            right: true,
            yaw: Some(0.0),
            ..Action::default()
        },
    );
    advance(&mut session, 10);
    session.state.set_action(player, Action::default());
    assert!(body(&session, player).z.abs() >= 2.4);
    assert_eq!(body(&session, player).y, PLAYER_FLOOR_Y + 4.0);
    let mut lowest = 4.0_f32;
    for _ in 0..65 {
        advance(&mut session, 1);
        if let Some(p) = session.state.players.iter().find(|p| p.id == enemy) {
            lowest = lowest.min(p.y - PLAYER_FLOOR_Y);
            if p.hp <= 0 {
                break;
            }
        }
    }
    assert!(
        lowest < 1.5,
        "the supported charge never actually fell: {lowest}"
    );
    assert_eq!(phase(&session, enemy), EnemyPhase::Dead);
    assert!(body(&session, enemy).hp <= 0);
    assert_eq!(body(&session, player).hp, 100);
    assert_eq!(session.state.scores.get(&player), Some(&0));
    let record = session.state.player_record(player).unwrap();
    assert!(record.total.weapons.iter().all(|w| w.kills == 0));
    assert_eq!(record.total.deaths, 0);
}

#[test]
fn a_heavy_resolved_hit_interrupts_before_contact() {
    let (mut session, player, enemy) = fixture(false, false);
    until(&mut session, enemy, EnemyPhase::Windup);
    let p = session
        .state
        .players
        .iter_mut()
        .find(|p| p.id == player)
        .unwrap();
    p.inventory.grant_weapon(WeaponType::Rail);
    p.weapon = WeaponType::Rail;
    session.state.set_action(
        player,
        Action {
            fire: true,
            look_at: Some(LookAt {
                player_id: Some(enemy),
                ..LookAt::default()
            }),
            ..Action::default()
        },
    );
    advance(&mut session, 1);
    session.state.set_action(player, Action::default());
    assert!(body(&session, enemy).hp < 140 && body(&session, enemy).hp > 0);
    advance(&mut session, 1);
    assert_eq!(phase(&session, enemy), EnemyPhase::Hit);
    assert_eq!(body(&session, player).hp, 100);
    advance(&mut session, 10);
    assert_eq!(phase(&session, enemy), EnemyPhase::Hit);
    assert_eq!(body(&session, player).hp, 100);
}

#[test]
fn ordinary_resolved_gunfire_does_not_cancel_the_armored_charge() {
    let (mut session, player, enemy) = fixture(false, false);
    until(&mut session, enemy, EnemyPhase::Windup);
    let p = session
        .state
        .players
        .iter_mut()
        .find(|p| p.id == player)
        .unwrap();
    p.inventory.grant_weapon(WeaponType::Tack);
    p.weapon = WeaponType::Tack;
    session.state.set_action(
        player,
        Action {
            fire: true,
            look_at: Some(LookAt {
                player_id: Some(enemy),
                ..Default::default()
            }),
            ..Default::default()
        },
    );
    advance(&mut session, 1);
    session.state.set_action(player, Action::default());
    assert!(body(&session, enemy).hp < 140 && body(&session, enemy).hp > 0);
    assert_eq!(phase(&session, enemy), EnemyPhase::Windup);
    until(&mut session, enemy, EnemyPhase::Charging);
    advance(&mut session, 14);
    assert_eq!(body(&session, player).hp, 70);
}

#[tokio::test]
async fn enforcer_requires_capability_34_for_every_role_and_orders_geometry_first() {
    use futures_util::{SinkExt, StreamExt};
    use std::time::Duration;
    use tokio_tungstenite::{connect_async, tungstenite::Message};

    let directory = std::env::temp_dir().join(format!("fragr-enforcer-{}", Uuid::new_v4()));
    std::fs::create_dir(&directory).unwrap();
    let path = directory.join("range.json");
    std::fs::write(&path, serde_json::to_vec(&document(false, false)).unwrap()).unwrap();
    let (ready_tx, ready_rx) = tokio::sync::oneshot::channel();
    let (stop_tx, stop_rx) = tokio::sync::oneshot::channel();
    let server = tokio::spawn(crate::run::run_server(
        crate::run::ServerOptions {
            bind: "127.0.0.1:0".into(),
            bots: 0,
            authored: Some(crate::maps::AuthoredSource::File(path)),
            ..Default::default()
        },
        async {
            let _ = stop_rx.await;
        },
        Some(ready_tx),
    ));
    let address = tokio::time::timeout(Duration::from_secs(30), ready_rx)
        .await
        .unwrap()
        .unwrap();
    let mut participants = Vec::new();
    for version in [
        crate::protocol::MISSION_RESULTS_GAMEPLAY_VERSION,
        crate::protocol::M09_GAMEPLAY_VERSION,
    ] {
        for role in ["human", "agent", "spectator"] {
            let (mut socket, _) = connect_async(format!("ws://{address}")).await.unwrap();
            socket.send(Message::Text(json!({
                "type":"hello", "role":role, "name":"ChargeProbe",
                "gameplay_version":version, "geometry_version":crate::protocol::GEOMETRY_VERSION
            }).to_string())).await.unwrap();
            tokio::time::timeout(Duration::from_secs(5), async {
                let mut saw_map = false;
                let mut saw_welcome = false;
                loop {
                    let message = socket.next().await.unwrap().unwrap();
                    let Message::Text(text) = message else {
                        continue;
                    };
                    let value: serde_json::Value = serde_json::from_str(&text).unwrap();
                    if version < crate::protocol::M09_GAMEPLAY_VERSION {
                        assert_eq!(value["type"], "error", "old reader admitted");
                        assert_eq!(value["code"], "unsupported_gameplay");
                        assert!(value["message"].as_str().unwrap().contains("34"));
                        break;
                    }
                    match value["type"].as_str().unwrap() {
                        "welcome" => saw_welcome = true,
                        "map_info" => {
                            assert_eq!(value["map_id"], 1099);
                            saw_map = true;
                        }
                        "snapshot" => {
                            assert!(saw_map && saw_welcome, "snapshot overtook geometry");
                            if !value["players"]
                                .as_array()
                                .unwrap()
                                .iter()
                                .any(|p| p["campaign"]["kind"] == "enforcer")
                            {
                                // The initial queued snapshot can predate
                                // admission and authored body placement.
                                continue;
                            }
                            break;
                        }
                        "error" => panic!("current reader rejected: {value}"),
                        _ => {}
                    }
                }
            })
            .await
            .unwrap_or_else(|error| panic!("bounded Enforcer admission {version}/{role}: {error}"));
            if version == crate::protocol::M09_GAMEPLAY_VERSION && role != "spectator" {
                // Keep an actual participant while inspecting the spectator
                // roster. An empty party may reset authored encounter bodies.
                participants.push(socket);
            } else {
                let _ = socket.close(None).await;
            }
        }
    }
    for mut socket in participants {
        let _ = socket.close(None).await;
    }
    stop_tx.send(()).unwrap();
    server.await.unwrap().unwrap();
    std::fs::remove_dir_all(directory).unwrap();
}
