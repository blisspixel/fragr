//! Actual shared movement, contact, shot resolution and commitment for the prototype.
use crate::maps::AuthoredMap;
use crate::protocol::{Action, CampaignActor, EnemyPhase, LookAt, Role, WeaponType};
use crate::session::GameSession;
use crate::sim::PLAYER_FLOOR_Y;
use serde_json::json;
use uuid::Uuid;

fn document(distance: f32, cover: bool) -> serde_json::Value {
    let solids = if cover {
        vec![
            json!({"id":"record_rack","min":[-0.1,0,-0.7],"max":[0.1,3.35,0.7],"surface":"service_steel"}),
        ]
    } else {
        Vec::new()
    };
    json!({
        "version":1,"map_id":1112,"name":"Redactor commitment fixture","half_extent":12,
        "ground":"concrete","equipment":"discovery","solids":solids,
        "spawns":[{"id":"entry","feet":[distance,0,0],"yaw":std::f32::consts::PI}],
        "landmarks":[{"id":"record_return","feet":[-4,0,3]}],
        "encounters":[{"id":"record_guard","regions":[{"min":[-8,0,-8],"max":[8,2,8]}],
            "enemies":[{"id":"redactor","kind":"redactor","feet":[-1,0,0],"yaw":0}]}]
    })
}

fn fixture(distance: f32, cover: bool) -> (GameSession, Uuid, Uuid) {
    let map = AuthoredMap::read(
        serde_json::to_vec(&document(distance, cover))
            .unwrap()
            .as_slice(),
    )
    .unwrap();
    let mut session = GameSession::with_authored_map(map);
    session.state.seed(42);
    let participant = Uuid::from_u128(1112);
    session
        .state
        .add_player(participant, "Walker".into(), Role::Human);
    advance(&mut session, 1);
    let enemy = session
        .state
        .players
        .iter()
        .find(|p| p.is_campaign_enemy())
        .unwrap()
        .id;
    (session, participant, enemy)
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
        _ => panic!("expected Union guard"),
    }
}
fn until(session: &mut GameSession, enemy: Uuid, expected: EnemyPhase) {
    for _ in 0..100 {
        if phase(session, enemy) == expected {
            return;
        }
        advance(session, 1);
    }
    panic!("Redactor never reached {expected:?}");
}

#[test]
fn redactor_real_lateral_approach_preserves_human_body_and_shared_walking() {
    let (mut session, participant, enemy) = fixture(4.0, false);
    assert!(session.state.map.requires_m11_contract());
    assert_eq!(body(&session, enemy).hp, 90);
    assert_eq!(body(&session, enemy).weapon, WeaponType::Shiv);
    assert_eq!(
        crate::combat::target_height(body(&session, enemy).campaign),
        1.8
    );
    assert!(body(&session, enemy).is_campaign_enemy());
    let mut highest_lateral = 0.0_f32;
    let mut previous = [body(&session, enemy).x, body(&session, enemy).z];
    for _ in 0..60 {
        let current = body(&session, enemy);
        highest_lateral = highest_lateral.max(current.z.abs());
        assert!((current.y - PLAYER_FLOOR_Y).abs() <= 0.001);
        assert!(
            (current.x - body(&session, participant).x)
                .hypot(current.z - body(&session, participant).z)
                >= crate::movement::RADIUS * 2.0 - 0.001
        );
        if phase(&session, enemy) == EnemyPhase::Windup {
            break;
        }
        advance(&mut session, 1);
        let current = body(&session, enemy);
        assert!(
            (current.x - previous[0]).hypot(current.z - previous[1]) <= 0.151,
            "ordinary .6 gait cannot warp {previous:?} -> {},{}",
            current.x,
            current.z
        );
        previous = [current.x, current.z];
    }
    assert_eq!(phase(&session, enemy), EnemyPhase::Windup);
    assert!(
        highest_lateral >= 0.5,
        "visible diagonal approach: {highest_lateral}"
    );
    assert_eq!(body(&session, participant).hp, 100);
}

#[test]
fn redactor_locked_windup_one_actual_shiv_and_recovery_have_no_extra_attacks() {
    let (mut session, participant, enemy) = fixture(0.8, false);
    until(&mut session, enemy, EnemyPhase::Windup);
    let origin = [
        body(&session, enemy).x,
        body(&session, enemy).y,
        body(&session, enemy).z,
    ];
    let yaw = body(&session, enemy).yaw;
    let start = session.state.tick;
    let mut attacks = 0;
    while session.state.tick < start + 42 {
        advance(&mut session, 1);
        attacks += session
            .state
            .shot_results
            .iter()
            .filter(|shot| shot.shooter_id == enemy)
            .count();
        assert_eq!(
            [
                body(&session, enemy).x,
                body(&session, enemy).y,
                body(&session, enemy).z
            ],
            origin
        );
        assert_eq!(body(&session, enemy).yaw, yaw);
        if session.state.tick < start + 18 {
            assert_eq!(body(&session, participant).hp, 100);
        }
    }
    assert_eq!(attacks, 1);
    assert_eq!(body(&session, participant).hp, 65);
    assert!(
        session.state.player_record(enemy).is_none(),
        "Union guards do not gain participant records"
    );
}

#[test]
fn redactor_ordinary_windup_sidestep_evades_locked_ray() {
    let (mut session, participant, enemy) = fixture(0.8, false);
    until(&mut session, enemy, EnemyPhase::Windup);
    let locked = body(&session, enemy).yaw;
    session.state.set_action(
        participant,
        Action {
            right: true,
            yaw: Some(0.0),
            ..Action::default()
        },
    );
    advance(&mut session, 10);
    session.state.set_action(participant, Action::default());
    assert!(body(&session, participant).z.abs() >= 2.4);
    let mut attacks = 0;
    for _ in 0..25 {
        advance(&mut session, 1);
        attacks += session
            .state
            .shot_results
            .iter()
            .filter(|shot| shot.shooter_id == enemy)
            .count();
        assert_eq!(body(&session, enemy).yaw, locked);
    }
    assert_eq!(attacks, 1);
    assert_eq!(body(&session, participant).hp, 100);
}

#[test]
fn redactor_record_rack_blocks_strike_and_ordinary_route_goes_around_it() {
    let (mut session, participant, enemy) = fixture(0.8, true);
    let mut attacks = 0;
    let mut bypassed = false;
    for _ in 0..70 {
        advance(&mut session, 1);
        let guard = body(&session, enemy);
        assert!(!session.state.current_arena().blocked_body_at(
            guard.x,
            guard.z,
            0.0,
            crate::movement::STEP_UP
        ));
        bypassed |= guard.z.abs() > 1.15;
        attacks += session
            .state
            .shot_results
            .iter()
            .filter(|shot| shot.shooter_id == enemy)
            .count();
        if attacks > 0 {
            break;
        }
    }
    assert!(
        bypassed,
        "the authoritative rack must require a real walking return"
    );
    assert_eq!(attacks, 1);
    assert_eq!(body(&session, participant).hp, 65);
}

#[test]
fn redactor_normal_resolved_hit_interrupts_and_death_preserves_ordinary_volume() {
    let (mut session, participant, enemy) = fixture(0.8, false);
    until(&mut session, enemy, EnemyPhase::Windup);
    {
        let player = session
            .state
            .players
            .iter_mut()
            .find(|p| p.id == participant)
            .unwrap();
        player.inventory.grant_weapon(WeaponType::Tack);
        player.weapon = WeaponType::Tack;
    }
    session.state.set_action(
        participant,
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
    session.state.set_action(participant, Action::default());
    assert!(body(&session, enemy).hp < 90 && body(&session, enemy).hp > 0);
    assert_eq!(phase(&session, enemy), EnemyPhase::Hit);
    advance(&mut session, 5);
    assert_eq!(body(&session, participant).hp, 100);
    session.state.set_action(
        participant,
        Action {
            fire: true,
            look_at: Some(LookAt {
                player_id: Some(enemy),
                ..LookAt::default()
            }),
            ..Action::default()
        },
    );
    for _ in 0..60 {
        advance(&mut session, 1);
        if body(&session, enemy).hp <= 0 {
            break;
        }
    }
    assert_eq!(phase(&session, enemy), EnemyPhase::Dead);
    assert_eq!(body(&session, enemy).y, PLAYER_FLOOR_Y);
    assert_eq!(
        session
            .state
            .player_record(participant)
            .unwrap()
            .total
            .weapons
            .iter()
            .map(|w| w.kills)
            .sum::<u64>(),
        1
    );
}

#[test]
fn redactor_ordinary_walk_behind_record_rack_cancels_committed_strike() {
    let mut doc = document(0.8, false);
    doc["solids"] = json!([{"id":"return_rack","min":[-0.1,0,0.8],"max":[0.1,3.35,3],"surface":"service_steel"}]);
    let map = AuthoredMap::read(serde_json::to_vec(&doc).unwrap().as_slice()).unwrap();
    let mut session = GameSession::with_authored_map(map);
    let participant = Uuid::from_u128(1112);
    session
        .state
        .add_player(participant, "Walker".into(), Role::Human);
    advance(&mut session, 1);
    let enemy = session
        .state
        .players
        .iter()
        .find(|p| p.is_campaign_enemy())
        .unwrap()
        .id;
    until(&mut session, enemy, EnemyPhase::Windup);
    session.state.set_action(
        participant,
        Action {
            right: true,
            yaw: Some(0.0),
            ..Action::default()
        },
    );
    let mut attacks = 0;
    for _ in 0..12 {
        advance(&mut session, 1);
        attacks += session
            .state
            .shot_results
            .iter()
            .filter(|shot| shot.shooter_id == enemy)
            .count();
    }
    session.state.set_action(participant, Action::default());
    assert!(body(&session, participant).z > 2.0);
    assert_eq!(phase(&session, enemy), EnemyPhase::Recovery);
    assert_eq!(
        attacks, 0,
        "lost real sight cancels rather than traces through racks"
    );
    assert_eq!(body(&session, participant).hp, 100);
}

#[tokio::test]
async fn redactor_current_contract_starts_the_registered_network_range() {
    use std::time::Duration;
    let directory = std::env::temp_dir().join(format!("fragr-redactor-{}", Uuid::new_v4()));
    std::fs::create_dir(&directory).unwrap();
    let path = directory.join("range.json");
    std::fs::write(&path, serde_json::to_vec(&document(4.0, false)).unwrap()).unwrap();
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
    let address = tokio::time::timeout(Duration::from_secs(30), ready_rx)
        .await
        .unwrap()
        .unwrap();
    assert!(address.port() > 0);
    stop_tx.send(()).unwrap();
    tokio::time::timeout(Duration::from_secs(3), server)
        .await
        .unwrap()
        .unwrap()
        .unwrap();
    std::fs::remove_file(path).unwrap();
    std::fs::remove_dir(directory).unwrap();
}
