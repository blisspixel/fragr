//! Seeded Jammer tells, real traveling damage and campaign reset behavior.
use crate::encounters::enemy::attack_timing;
use crate::maps::AuthoredMap;
use crate::protocol::{
    Action, CampaignActor, CampaignDifficulty, EnemyKind, EnemyPhase, LookAt, Role, WeaponType,
};
use crate::session::GameSession;
use crate::sim::traveling_shot::{DAMAGE, JAMMER_LIFE_TICKS};
use serde_json::json;
use uuid::Uuid;

fn fixture() -> (GameSession, Uuid, Uuid) {
    let doc = json!({
        "version":1,"map_id":1012,"name":"Jammer fixture","half_extent":20,
        "ground":"concrete","equipment":"discovery",
        "solids":[{"id":"side_cover","min":[3,0,-2],"max":[7,3,0],"surface":"service_steel"}],
        "spawns":[{"id":"entry","feet":[0,0,-6],"yaw":1.5707964}],
        "landmarks":[{"id":"flank","feet":[-6,0,12]}],
        "encounters":[{"id":"range","regions":[{"min":[-20,0,-20],"max":[20,2,20]}],
            "enemies":[{"id":"emitter","kind":"jammer","feet":[0,0,10],"yaw":4.712389}]}]
    });
    let map = AuthoredMap::read(serde_json::to_vec(&doc).unwrap().as_slice()).unwrap();
    let mut session = GameSession::with_authored_map(map);
    session.state.seed(42);
    let participant = Uuid::from_u128(0x0310);
    session
        .state
        .add_player(participant, "Visitor".into(), Role::Human);
    advance(&mut session, 2);
    let emitter = session
        .state
        .players
        .iter()
        .find(|p| p.is_campaign_enemy())
        .unwrap()
        .id;
    (session, participant, emitter)
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
        _ => panic!("expected Union actor"),
    }
}

fn place(session: &mut GameSession, id: Uuid, x: f32, z: f32) {
    let body = session
        .state
        .players
        .iter_mut()
        .find(|p| p.id == id)
        .unwrap();
    body.x = x;
    body.z = z;
}

fn launch(session: &mut GameSession, emitter: Uuid) {
    for _ in 0..100 {
        if session.state.has_traveling_shot(emitter) {
            return;
        }
        advance(session, 1);
    }
    panic!("Jammer never launched");
}

fn shoot(session: &mut GameSession, participant: Uuid, emitter: Uuid, weapon: WeaponType) {
    let player = session
        .state
        .players
        .iter_mut()
        .find(|p| p.id == participant)
        .unwrap();
    player.inventory.grant_weapon(weapon);
    player.weapon = weapon;
    player.fire_cooldown = 0;
    session.state.set_action(
        participant,
        Action {
            fire: true,
            look_at: Some(LookAt {
                player_id: Some(emitter),
                ..Default::default()
            }),
            ..Default::default()
        },
    );
    session.state.tick(0.05);
    session.state.set_action(participant, Action::default());
}

#[test]
fn jammer_tell_precedes_real_travel_and_does_not_emit_a_hitscan() {
    let (mut session, participant, emitter) = fixture();
    assert_eq!(body(&session, emitter).hp, 90);
    assert_eq!(body(&session, emitter).weapon, WeaponType::Fists);
    assert_eq!(phase(&session, emitter), EnemyPhase::Windup);
    advance(&mut session, 23);
    assert!(session.state.snapshot().projectiles.is_empty());
    assert_eq!(body(&session, participant).hp, 100);
    advance(&mut session, 1);
    assert_eq!(phase(&session, emitter), EnemyPhase::Firing);
    assert!(body(&session, emitter).just_fired);
    assert_eq!(session.state.snapshot().projectiles.len(), 1);
    assert!(session.state.shot_results.is_empty());
    assert_eq!(body(&session, participant).hp, 100);
    advance(&mut session, 1);
    assert_eq!(phase(&session, emitter), EnemyPhase::Recovery);
    advance(&mut session, 100);
    assert_eq!(body(&session, participant).hp, 100);
    for _ in 0..40 {
        if body(&session, participant).hp < 100 {
            break;
        }
        advance(&mut session, 1);
    }
    assert_eq!(body(&session, participant).hp, 100 - DAMAGE);
    assert!(!session.state.has_traveling_shot(emitter));
    assert_eq!(
        (body(&session, emitter).x, body(&session, emitter).z),
        (0.0, 10.0)
    );
}

#[test]
fn a_sidestep_during_the_tell_evades_committed_aim() {
    let (mut session, participant, emitter) = fixture();
    advance(&mut session, 10);
    place(&mut session, participant, -4.0, -6.0);
    launch(&mut session, emitter);
    let pulse = session.state.snapshot().projectiles[0];
    assert!(
        pulse.x.abs() < 0.001,
        "aim must remain committed to the original lane"
    );
    advance(&mut session, JAMMER_LIFE_TICKS as usize);
    assert_eq!(body(&session, participant).hp, 100);
}

#[test]
fn a_sidestep_after_launch_evades_the_actual_pulse() {
    let (mut session, participant, emitter) = fixture();
    launch(&mut session, emitter);
    session.state.set_action(
        participant,
        Action {
            left: true,
            yaw: Some(std::f32::consts::FRAC_PI_2),
            ..Default::default()
        },
    );
    advance(&mut session, 20);
    session.state.set_action(participant, Action::default());
    assert!(
        body(&session, participant).x.abs() > 1.5,
        "a real sidestep must leave the pulse lane"
    );
    advance(&mut session, 160);
    assert_eq!(body(&session, participant).hp, 100);
    assert!(session.state.snapshot().projectiles.len() <= 1);
}

#[test]
fn broken_sight_cancels_the_tell_without_a_pulse() {
    let (mut session, participant, emitter) = fixture();
    place(&mut session, participant, 6.0, -6.0);
    advance(&mut session, 1);
    assert_eq!(phase(&session, emitter), EnemyPhase::Recovery);
    advance(&mut session, 60);
    assert!(session.state.snapshot().projectiles.is_empty());
    assert_eq!(body(&session, participant).hp, 100);
}

#[test]
fn an_ordinary_pistol_hit_interrupts_the_tell() {
    let (mut session, participant, emitter) = fixture();
    shoot(&mut session, participant, emitter, WeaponType::Tack);
    assert!(body(&session, emitter).hp < 90);
    assert_eq!(phase(&session, emitter), EnemyPhase::Hit);
    advance(&mut session, 5);
    assert!(session.state.snapshot().projectiles.is_empty());
    assert_eq!(body(&session, participant).hp, 100);
}

#[test]
fn a_dead_emitter_keeps_its_launched_attack_past_corpse_cleanup() {
    let (mut session, participant, emitter) = fixture();
    launch(&mut session, emitter);
    shoot(&mut session, participant, emitter, WeaponType::Rail);
    shoot(&mut session, participant, emitter, WeaponType::Rail);
    assert_eq!(phase(&session, emitter), EnemyPhase::Dead);
    advance(&mut session, 45);
    assert!(body(&session, emitter).hp <= 0);
    assert!(session.state.has_traveling_shot(emitter));
    for _ in 0..110 {
        if body(&session, participant).hp < 100 {
            break;
        }
        advance(&mut session, 1);
    }
    assert_eq!(body(&session, participant).hp, 100 - DAMAGE);
    advance(&mut session, 1);
    assert!(!session.state.players.iter().any(|p| p.id == emitter));
}

#[test]
fn a_union_body_stops_the_pulse_without_friendly_damage() {
    let (mut session, participant, emitter) = fixture();
    launch(&mut session, emitter);
    let friendly = Uuid::from_u128(0x0311);
    session
        .state
        .add_player(friendly, "Friendly".into(), Role::Agent);
    let player = session
        .state
        .players
        .iter_mut()
        .find(|p| p.id == friendly)
        .unwrap();
    player.x = 0.0;
    player.z = 2.0;
    player.campaign = Some(CampaignActor::Union {
        kind: EnemyKind::Jammer,
        phase: EnemyPhase::Idle,
        phase_started: session.state.tick,
        phase_ends: session.state.tick,
        seated: false,
    });
    advance(&mut session, 75);
    assert_eq!(body(&session, friendly).hp, 100);
    assert_eq!(body(&session, participant).hp, 100);
    assert!(!session.state.has_traveling_shot(emitter));
}

#[test]
fn a_party_reset_clears_pulses_before_the_next_attempt() {
    let (mut session, participant, emitter) = fixture();
    launch(&mut session, emitter);
    session
        .state
        .players
        .iter_mut()
        .find(|p| p.id == participant)
        .unwrap()
        .hp = 0;
    advance(&mut session, 1);
    assert!(session.state.snapshot().projectiles.is_empty());
    assert!(!session.state.players.iter().any(|p| p.id == emitter));
}

#[test]
fn explicit_campaign_encounter_retry_clears_pulses() {
    let (mut session, _, emitter) = fixture();
    launch(&mut session, emitter);
    session.state.reset_campaign_encounters();
    assert!(session.state.snapshot().projectiles.is_empty());
    advance(&mut session, 1);
    assert!(session
        .state
        .players
        .iter()
        .any(|p| p.is_campaign_enemy() && p.id != emitter));
}

#[test]
fn difficulty_keeps_the_new_tell_identical_and_existing_rules_unchanged() {
    for difficulty in [
        CampaignDifficulty::Assisted,
        CampaignDifficulty::Standard,
        CampaignDifficulty::Severe,
    ] {
        assert_eq!(attack_timing(EnemyKind::Jammer, difficulty), (24, 40));
    }
    assert_eq!(crate::protocol::CAMPAIGN_RULES_REVISION, 3);
    assert_eq!(
        attack_timing(EnemyKind::Clerk, CampaignDifficulty::Standard),
        (12, 20)
    );
}

#[test]
fn the_playable_range_loads_with_a_flank_and_registered_supply() {
    let map =
        AuthoredMap::read(include_bytes!("../../maps/test/jammer-range.json").as_slice()).unwrap();
    let mut session = GameSession::with_authored_map(map);
    session
        .state
        .add_player(Uuid::from_u128(0x0312), "Visitor".into(), Role::Human);
    advance(&mut session, 1);
    assert_eq!(session.state.map.name(), "Jammer interference range");
    assert_eq!(session.state.map.encounters().len(), 2);
    assert!(session.state.map.encounters().iter().any(|group| group
        .enemies
        .iter()
        .any(|enemy| enemy.kind == EnemyKind::Jammer)));
}

#[test]
fn a_pulse_stops_at_real_cover_and_never_damages_through_it() {
    let (mut session, participant, emitter) = fixture();
    place(&mut session, participant, 6.0, -6.0);
    let aim =
        crate::combat::aim_at([0.0, crate::movement::EYE_HEIGHT, 10.0], [6.0, 0.9, -6.0]).unwrap();
    // Drive the attack boundary directly so the collision test is independent
    // of the controller correctly refusing to aim through this cover.
    session.state.set_action(
        emitter,
        Action {
            fire: true,
            yaw: Some(aim.0),
            pitch: Some(aim.1),
            ..Default::default()
        },
    );
    session.state.tick(0.05);
    session.state.set_action(emitter, Action::default());
    assert!(session.state.has_traveling_shot(emitter));
    advance(&mut session, 120);
    assert!(!session.state.has_traveling_shot(emitter));
    assert_eq!(body(&session, participant).hp, 100);
}

#[test]
fn one_pulse_blocks_another_attack_until_its_twelve_second_expiry() {
    let (mut session, participant, emitter) = fixture();
    launch(&mut session, emitter);
    place(&mut session, participant, -4.0, -6.0);
    let serial = session.state.snapshot().projectiles[0].id;
    advance(&mut session, 100);
    assert_eq!(session.state.snapshot().projectiles.len(), 1);
    assert_eq!(session.state.snapshot().projectiles[0].id, serial);
    assert_eq!(phase(&session, emitter), EnemyPhase::Idle);
    advance(&mut session, 138);
    assert!(session.state.has_traveling_shot(emitter));
    advance(&mut session, 1);
    assert!(!session.state.has_traveling_shot(emitter));
    launch(&mut session, emitter);
    assert!(session.state.snapshot().projectiles[0].id > serial);
}

#[test]
fn authored_jammers_cannot_claim_a_clerks_seated_pose() {
    let mut doc: serde_json::Value =
        serde_json::from_slice(include_bytes!("../../maps/test/jammer-range.json")).unwrap();
    doc["encounters"][0]["enemies"][0]["seated"] = json!(true);
    assert!(AuthoredMap::read(serde_json::to_vec(&doc).unwrap().as_slice()).is_err());
}

#[tokio::test]
async fn live_jammer_admission_rejects_old_roles_and_sends_geometry_before_snapshots() {
    use futures_util::{SinkExt, StreamExt};
    use std::time::Duration;
    use tokio_tungstenite::{connect_async, tungstenite::Message};

    let (ready_tx, ready_rx) = tokio::sync::oneshot::channel();
    let (stop_tx, stop_rx) = tokio::sync::oneshot::channel();
    let server = tokio::spawn(crate::run::run_server(
        crate::run::ServerOptions {
            bind: "127.0.0.1:0".into(),
            bots: 0,
            authored: Some(crate::maps::AuthoredSource::File(
                std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
                    .join("maps/test/jammer-range.json"),
            )),
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
    for version in [
        22,
        crate::protocol::JAMMER_GAMEPLAY_VERSION,
        25,
        crate::protocol::GAMEPLAY_VERSION,
    ] {
        for role in ["human", "agent", "spectator"] {
            let (mut socket, _) = connect_async(format!("ws://{address}")).await.unwrap();
            socket.send(Message::Text(json!({
                "type":"hello", "role":role, "name":"PulseProbe",
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
                    if version < crate::protocol::GAMEPLAY_VERSION {
                        assert_eq!(
                            value["type"], "error",
                            "old actor reader received a game message"
                        );
                        assert_eq!(value["code"], "unsupported_gameplay");
                        assert!(value["message"].as_str().unwrap().contains("26"));
                        break;
                    }
                    match value["type"].as_str().unwrap() {
                        "welcome" => saw_welcome = true,
                        "map_info" => {
                            assert_eq!(value["map_id"], 1012);
                            saw_map = true;
                        }
                        "snapshot" => {
                            assert!(saw_welcome, "snapshot overtook welcome");
                            assert!(saw_map, "snapshot overtook geometry for {role}");
                            break;
                        }
                        "error" => panic!("current reader was rejected: {value}"),
                        _ => {}
                    }
                }
            })
            .await
            .expect("bounded actor admission and first snapshot");
            let _ = socket.close(None).await;
        }
    }
    stop_tx.send(()).unwrap();
    server.await.unwrap().unwrap();
}

#[tokio::test]
async fn current_rules_three_readers_join_m02() {
    use futures_util::{SinkExt, StreamExt};
    use std::time::Duration;
    use tokio_tungstenite::{connect_async, tungstenite::Message};

    let (ready_tx, ready_rx) = tokio::sync::oneshot::channel();
    let (stop_tx, stop_rx) = tokio::sync::oneshot::channel();
    let server = tokio::spawn(crate::run::run_server(
        crate::run::ServerOptions {
            bind: "127.0.0.1:0".into(),
            bots: 0,
            authored: Some(crate::maps::AuthoredSource::Mission(
                crate::protocol::MissionId::PersonsUnknown,
            )),
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
    let (mut socket, _) = connect_async(format!("ws://{address}")).await.unwrap();
    socket
        .send(Message::Text(
            json!({
                "type":"hello", "role":"human", "name":"Compatible",
                "gameplay_version":crate::protocol::GAMEPLAY_VERSION, "geometry_version":crate::protocol::GEOMETRY_VERSION
            })
            .to_string(),
        ))
        .await
        .unwrap();
    tokio::time::timeout(Duration::from_secs(5), async {
        let mut saw_map = false;
        loop {
            let message = socket.next().await.unwrap().unwrap();
            let Message::Text(text) = message else {
                continue;
            };
            let value: serde_json::Value = serde_json::from_str(&text).unwrap();
            assert_ne!(value["type"], "error", "current M02 reader was rejected");
            if value["type"] == "map_info" {
                saw_map = true;
            }
            if value["type"] == "snapshot" {
                assert!(saw_map);
                break;
            }
        }
    })
    .await
    .expect("M02 current reader reaches rules-three gameplay");
    let _ = socket.close(None).await;
    stop_tx.send(()).unwrap();
    server.await.unwrap().unwrap();
}
