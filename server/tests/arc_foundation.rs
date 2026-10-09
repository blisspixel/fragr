use fragr_server::maps::{AuthoredMap, RuntimeMap};
use fragr_server::movement::EYE_HEIGHT;
use fragr_server::navigation::{NavigationGoal, Navigator, RouteStatus, SEARCH_LIMIT};
use fragr_server::protocol::{
    Action, AmmoPool, CampaignActor, EnemyPhase, LookAt, Role, WeaponType,
};
use fragr_server::session::GameSession;
use fragr_server::sim::{GameState, PLAYER_FLOOR_Y};
use serde_json::{json, Value};
use std::collections::HashSet;
use uuid::Uuid;

const SOURCE: &[u8] = include_bytes!("../maps/test/arc_foundation_development.json");

fn document() -> Value {
    serde_json::from_slice(SOURCE).unwrap()
}
fn point(value: &Value) -> [f32; 3] {
    std::array::from_fn(|i| value[i].as_f64().unwrap() as f32)
}
fn feet(state: &GameState, id: Uuid) -> [f32; 3] {
    let p = state.players.iter().find(|p| p.id == id).unwrap();
    [p.x, p.y - PLAYER_FLOOR_Y, p.z]
}

#[test]
fn arc_lesson_has_one_finite_find_three_ordered_armored_guards_and_return_routes() {
    let map = AuthoredMap::read(SOURCE).unwrap();
    let world = RuntimeMap::Authored(map.clone());
    assert_eq!(world.id(), 1042);
    assert!(world.requires_arc_contract());
    let state = GameState::with_authored_map(map);
    assert!(state.mission_state().is_none());
    let value = document();
    assert_eq!(value["solids"].as_array().unwrap().len(), 16);
    assert_eq!(value["encounters"].as_array().unwrap().len(), 3);
    for (index, group) in value["encounters"].as_array().unwrap().iter().enumerate() {
        assert_eq!(group["enemies"][0]["kind"], "heavy_sweeper");
        assert_eq!(group["enemies"][0]["armor"], 100);
        if index > 0 {
            assert_eq!(group["after"], value["encounters"][index - 1]["id"]);
        }
    }
    assert_eq!(
        value["supplies"]
            .as_array()
            .unwrap()
            .iter()
            .filter(|p| p["grant"]["weapon"] == "arc")
            .count(),
        1
    );
    assert!(!value["supplies"]
        .as_array()
        .unwrap()
        .iter()
        .any(|p| p["grant"]["pool"] == "cells"));
    let start = point(&value["spawns"][0]["feet"]);
    let destinations = value["landmarks"]
        .as_array()
        .unwrap()
        .iter()
        .chain(value["supplies"].as_array().unwrap())
        .chain(
            value["encounters"]
                .as_array()
                .unwrap()
                .iter()
                .map(|g| &g["enemies"][0]),
        );
    let mut routes = 0;
    for destination in destinations {
        let end = point(&destination["feet"]);
        for (from, to) in [(start, end), (end, start)] {
            assert_eq!(
                world.navigation().route(from, to, SEARCH_LIMIT).status,
                RouteStatus::Complete
            );
            routes += 1;
        }
    }
    assert_eq!(routes, 26);
}

#[test]
fn authored_heavy_armor_is_optional_bounded_and_never_another_enemy_field() {
    for bad in [
        json!(-1),
        json!(101),
        json!(256),
        json!(1.5),
        json!("100"),
        Value::Null,
    ] {
        let mut value = document();
        value["encounters"][0]["enemies"][0]["armor"] = bad;
        assert!(AuthoredMap::read(serde_json::to_vec(&value).unwrap().as_slice()).is_err());
    }
    for kind in [
        "clerk", "sweeper", "auditor", "enforcer", "redactor", "turret",
    ] {
        for count in [0, 100] {
            let mut value = document();
            value["encounters"][0]["enemies"][0]["kind"] = kind.into();
            value["encounters"][0]["enemies"][0]["armor"] = count.into();
            assert!(
                AuthoredMap::read(serde_json::to_vec(&value).unwrap().as_slice()).is_err(),
                "{kind} armor {count}"
            );
        }
    }
    let mut value = document();
    value["encounters"][0]["enemies"][0]
        .as_object_mut()
        .unwrap()
        .remove("armor");
    let mut session = GameSession::with_authored_map(
        AuthoredMap::read(serde_json::to_vec(&value).unwrap().as_slice()).unwrap(),
    );
    let id = Uuid::from_u128(1042);
    session
        .state
        .add_player(id, "Original Heavy behavior".into(), Role::Human);
    session.state.start_round();
    session.tick_messages(0.05);
    assert_eq!(
        session
            .state
            .players
            .iter()
            .find(|p| p.name == "first_heavy")
            .unwrap()
            .armor,
        0
    );
}

#[tokio::test]
async fn arc_lesson_admits_all_roles_only_at_the_current_live_campaign_rules_floor() {
    use fragr_server::protocol::{
        ARC_GAMEPLAY_VERSION, ASSESSOR_GAMEPLAY_VERSION, GAMEPLAY_VERSION, GEOMETRY_VERSION,
        WATER_GAMEPLAY_VERSION,
    };
    use futures_util::{SinkExt, StreamExt};
    use std::time::Duration;
    use tokio_tungstenite::{connect_async, tungstenite::Message};
    let directory = std::env::temp_dir().join(format!("fragr-arc-admission-{}", Uuid::new_v4()));
    std::fs::create_dir(&directory).unwrap();
    let path = directory.join("arc.json");
    std::fs::write(&path, SOURCE).unwrap();
    let (ready_tx, ready_rx) = tokio::sync::oneshot::channel();
    let (stop_tx, stop_rx) = tokio::sync::oneshot::channel();
    let server = tokio::spawn(fragr_server::run::run_server(
        fragr_server::run::ServerOptions {
            bind: "127.0.0.1:0".into(),
            bots: 0,
            authored: Some(fragr_server::maps::AuthoredSource::File(path)),
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
        WATER_GAMEPLAY_VERSION,
        ARC_GAMEPLAY_VERSION,
        ASSESSOR_GAMEPLAY_VERSION,
        GAMEPLAY_VERSION,
    ] {
        for role in ["human", "agent", "spectator"] {
            let (mut socket, _) = connect_async(format!("ws://{address}")).await.unwrap();
            socket.send(Message::Text(json!({"type":"hello", "role":role, "name":"Arc reader", "gameplay_version":version, "geometry_version":GEOMETRY_VERSION}).to_string())).await.unwrap();
            tokio::time::timeout(Duration::from_secs(5), async {
                let mut welcomed = false;
                let mut mapped = false;
                loop {
                    let Message::Text(text) = socket.next().await.unwrap().unwrap() else {
                        continue;
                    };
                    let value: Value = serde_json::from_str(&text).unwrap();
                    if version < ASSESSOR_GAMEPLAY_VERSION {
                        assert_eq!(
                            value["type"], "error",
                            "unsupported {role} must not see new geometry or Welcome"
                        );
                        assert_eq!(value["code"], "unsupported_gameplay");
                        break;
                    }
                    match value["type"].as_str().unwrap() {
                        "welcome" => welcomed = true,
                        "map_info" => mapped = true,
                        "snapshot" => {
                            assert!(welcomed && mapped);
                            break;
                        }
                        "error" => panic!("supported {role} refused: {value}"),
                        _ => {}
                    }
                }
            })
            .await
            .expect("bounded Arc/rules admission");
            let _ = socket.close(None).await;
        }
    }
    stop_tx.send(()).unwrap();
    server.await.unwrap().unwrap();
    std::fs::remove_dir_all(directory).unwrap();
}

#[derive(Default)]
struct Evidence {
    killed: HashSet<String>,
    arc_shots: usize,
    enemy_shots: usize,
    reloads: usize,
    last_reload: Option<u64>,
    retained_armor: usize,
}

fn advance(
    session: &mut GameSession,
    id: Uuid,
    goals: &[[f32; 3]],
    required: &[&str],
    evidence: &mut Evidence,
) {
    let mut navigator = Navigator::default();
    let mut next = 0;
    for _ in 0..1800 {
        let state = &session.state;
        let from = feet(state, id);
        let me = state.players.iter().find(|p| p.id == id).unwrap();
        assert!(
            me.hp > 0,
            "finite Arc route died at {} {from:?}",
            state.tick
        );
        while next < goals.len()
            && (from[0] - goals[next][0]).hypot(from[2] - goals[next][2]) < 0.35
        {
            next += 1;
        }
        if next == goals.len() && required.iter().all(|name| evidence.killed.contains(*name)) {
            session.state.set_action(id, Action::default());
            return;
        }
        let loadout = me.inventory.state(id, me.weapon, state.tick).unwrap();
        if let Some(ready) = loadout
            .loaded
            .iter()
            .find(|m| m.weapon == WeaponType::Arc)
            .and_then(|m| m.ready_at)
        {
            if evidence.last_reload != Some(ready) {
                evidence.reloads += 1;
                evidence.last_reload = Some(ready);
            }
        }
        let arc_owned = loadout.owns(WeaponType::Arc);
        let aim = |p: &fragr_server::sim::Player| [p.x, p.y - PLAYER_FLOOR_Y + 0.9, p.z];
        let eye = [from[0], from[1] + EYE_HEIGHT, from[2]];
        let target = state.players.iter().filter(|p| required.contains(&p.name.as_str()) && p.hp > 0)
            .filter(|p| matches!(p.campaign, Some(CampaignActor::Union { phase, .. }) if phase != EnemyPhase::Idle && phase != EnemyPhase::Dead))
            .find(|p| fragr_server::combat::line_of_sight(eye, aim(p), &state.current_arena().solids));
        let mut action = if let Some(target) = target {
            let point = aim(target);
            Action {
                weapon_swap: arc_owned.then_some(WeaponType::Arc),
                fire: arc_owned,
                look_at: Some(LookAt {
                    x: Some(point[0]),
                    y: Some(point[1]),
                    z: Some(point[2]),
                    player_id: None,
                }),
                left: (state.tick / 16).is_multiple_of(2),
                right: !(state.tick / 16).is_multiple_of(2),
                ..Default::default()
            }
        } else {
            navigator.steer(
                state.map.navigation(),
                from,
                NavigationGoal {
                    feet: *goals.get(next).unwrap_or_else(|| goals.last().unwrap()),
                    combat: false,
                },
                Action {
                    weapon_swap: arc_owned.then_some(WeaponType::Arc),
                    ..Default::default()
                },
                state.tick,
                true,
            )
        };
        if arc_owned && loadout.shots(WeaponType::Arc) == Some(0) {
            action.fire = false;
            action.reload = state.tick.is_multiple_of(2);
        }
        assert!(!action.jump);
        session.state.set_action(id, action);
        session.tick_messages(0.05);
        for shot in &session.state.shot_results {
            if shot.shooter_id == id {
                assert_eq!(shot.trace.as_ref().unwrap().weapon, WeaponType::Arc);
                evidence.arc_shots += 1;
                if shot.killed {
                    evidence.killed.insert(shot.target.clone().unwrap());
                    let target = session
                        .state
                        .players
                        .iter()
                        .find(|p| Some(p.id) == shot.target_id)
                        .unwrap();
                    assert_eq!(
                        target.armor, 100,
                        "resolved Arc leaves the actual Heavy armor intact"
                    );
                    evidence.retained_armor += 1;
                }
            } else {
                evidence.enemy_shots += 1;
            }
        }
    }
    panic!(
        "Arc lesson stalled at {:?}, killed {:?}",
        feet(&session.state, id),
        evidence.killed
    );
}

#[test]
fn actual_human_discovers_forty_cells_reloads_and_clears_three_armored_heavies() {
    let mut session = GameSession::with_authored_map(AuthoredMap::read(SOURCE).unwrap());
    session.state.seed(1042);
    let id = Uuid::from_u128(1042);
    session
        .state
        .add_player(id, "Finite Arc lesson".into(), Role::Human);
    session.state.start_round();
    session.state.arm_joined_magazines(id);
    let mut evidence = Evidence::default();
    advance(
        &mut session,
        id,
        &[[2., 0., -18.], [-2., 0., -18.], [-8., 0., -16.]],
        &[],
        &mut evidence,
    );
    let player = session.state.players.iter().find(|p| p.id == id).unwrap();
    let found = player
        .inventory
        .state(id, player.weapon, session.state.tick)
        .unwrap();
    assert!(found.owns(WeaponType::Arc));
    assert_eq!(found.ammo(AmmoPool::Cells), 40);
    assert_eq!(found.shots(WeaponType::Arc), Some(12));
    advance(
        &mut session,
        id,
        &[[0., 0., -5.]],
        &["first_heavy"],
        &mut evidence,
    );
    advance(
        &mut session,
        id,
        &[[0., 0., 8.]],
        &["court_heavy"],
        &mut evidence,
    );
    advance(&mut session, id, &[[-2., 0., 13.5]], &[], &mut evidence);
    assert!(
        feet(&session.state, id)[2] < 16.0,
        "pre-final medical does not wake the final group"
    );
    advance(
        &mut session,
        id,
        &[[0., 0., 17.], [0., 0., 21.]],
        &["final_heavy"],
        &mut evidence,
    );
    let record = session.state.player_record(id).unwrap();
    assert_eq!(evidence.killed.len(), 3);
    assert_eq!(evidence.retained_armor, 3);
    assert_eq!(record.total.weapon(WeaponType::Arc).kills, 3);
    assert_eq!(record.total.weapon(WeaponType::Arc).hp_damage, 480);
    assert_eq!(record.total.weapon(WeaponType::Arc).armor_damage, 0);
    assert_eq!(record.total.deaths, 0);
    assert!(evidence.reloads >= 2);
    assert!(
        evidence.enemy_shots > 0,
        "actual GameSession enemy decisions must resolve normal attacks"
    );
    assert!((27..=40).contains(&evidence.arc_shots));
    let player = session.state.players.iter().find(|p| p.id == id).unwrap();
    let final_loadout = player
        .inventory
        .state(id, player.weapon, session.state.tick)
        .unwrap();
    assert_eq!(
        final_loadout.ammo(AmmoPool::Cells),
        40 - evidence.arc_shots as u16
    );
    println!("Arc actual finite human lesson: ticks={}, kills=3, Arc shots={}, ordinary reload presses={}, enemy shots={}, HP loss={}, armor loss={}, Cells={}", session.state.tick, evidence.arc_shots, evidence.reloads, evidence.enemy_shots, record.total.hp_lost, record.total.armor_lost, final_loadout.ammo(AmmoPool::Cells));
}
