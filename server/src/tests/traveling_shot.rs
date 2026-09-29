//! A server-owned point that travels, hits, and stays in the air after the shooter dies.
use crate::maps::AuthoredMap;
use crate::protocol::{GameEvent, Role};
use crate::sim::traveling_shot::{DAMAGE, LIFE_TICKS, SPEED};
use crate::sim::{GameState, PLAYER_MAX_HP, RESPAWN_DELAY_TICKS, SPAWN_SHIELD_TICKS};
use serde_json::json;
use uuid::Uuid;

const DT: f32 = 0.05;

fn range(solids: serde_json::Value) -> GameState {
    let doc = json!({
        "version": 1,
        "map_id": 1011,
        "name": "Traveling shot range",
        "half_extent": 20,
        "ground": "concrete",
        "solids": solids,
        "spawns": [{"id": "entry", "feet": [0.0, 0.0, -16.0], "yaw": 0.0}],
        "landmarks": [{"id": "lane", "feet": [0.0, 0.0, 0.0]}]
    });
    let map = AuthoredMap::read(serde_json::to_vec(&doc).unwrap().as_slice()).unwrap();
    let mut state = GameState::with_authored_map(map);
    state.seed(42);
    state
}

fn place(state: &mut GameState, name: &str, x: f32, z: f32, yaw: f32) -> Uuid {
    let id = Uuid::new_v4();
    state.add_player(id, name.into(), Role::Human);
    let player = state
        .players
        .iter_mut()
        .find(|player| player.id == id)
        .unwrap();
    player.x = x;
    player.z = z;
    player.yaw = yaw;
    player.pitch = 0.0;
    id
}

fn advance(state: &mut GameState, ticks: u32) {
    for _ in 0..ticks {
        state.tick(DT);
    }
}

fn ticks_to_reach(distance: f32) -> u32 {
    let step = SPEED * DT;
    (distance / step).ceil() as u32
}

fn hp(state: &GameState, id: Uuid) -> i32 {
    state
        .players
        .iter()
        .find(|player| player.id == id)
        .unwrap()
        .hp
}

#[test]
fn a_point_hits_the_body_on_its_line_and_then_leaves_the_snapshot() {
    let mut state = range(json!([]));
    let shooter = place(&mut state, "Shooter", 0.0, 0.0, 0.0);
    let target = place(&mut state, "Target", 6.0, 0.0, 0.0);
    assert!(state.launch_traveling_shot(shooter));
    let ticks = ticks_to_reach(5.5);
    assert!(ticks < LIFE_TICKS);
    advance(&mut state, ticks - 1);
    assert_eq!(hp(&state, target), PLAYER_MAX_HP);
    assert_eq!(state.snapshot().projectiles.len(), 1);
    state.tick(DT);
    assert_eq!(hp(&state, target), PLAYER_MAX_HP - DAMAGE);
    assert_eq!(hp(&state, shooter), PLAYER_MAX_HP);
    assert!(state.snapshot().projectiles.is_empty());
    assert!(state.shot_results.is_empty());
    assert!(state.events.iter().any(|event| matches!(
        event,
        GameEvent::Hit { damage, target_id, .. } if *damage == DAMAGE && *target_id == target
    )));
    let wire = serde_json::to_value(state.snapshot()).unwrap();
    assert!(wire.get("projectiles").is_none());
}

#[test]
fn a_wall_stops_the_point_before_the_body_behind_it() {
    let mut state = range(json!([
        {"id": "lane_wall", "min": [3.0, 0.0, -2.0], "max": [3.4, 3.0, 2.0], "surface": "concrete"}
    ]));
    let shooter = place(&mut state, "Shooter", 0.0, 0.0, 0.0);
    let target = place(&mut state, "Target", 6.0, 0.0, 0.0);
    assert!(state.launch_traveling_shot(shooter));
    let ticks = ticks_to_reach(3.0);
    advance(&mut state, ticks);
    assert_eq!(hp(&state, target), PLAYER_MAX_HP);
    assert!(state.snapshot().projectiles.is_empty());
    assert!(ticks < LIFE_TICKS);
}

#[test]
fn a_miss_lasts_the_life_of_the_shot_and_then_expires() {
    let mut state = range(json!([]));
    let shooter = place(&mut state, "Shooter", 0.0, 0.0, 0.0);
    assert!(state.launch_traveling_shot(shooter));
    advance(&mut state, LIFE_TICKS - 1);
    assert_eq!(state.snapshot().projectiles.len(), 1);
    state.tick(DT);
    assert!(state.snapshot().projectiles.is_empty());
    assert_eq!(hp(&state, shooter), PLAYER_MAX_HP);
}

#[test]
fn the_point_keeps_traveling_after_the_shooter_dies() {
    let mut state = range(json!([]));
    let shooter = place(&mut state, "Shooter", 0.0, 0.0, 0.0);
    let target = place(&mut state, "Target", 6.0, 0.0, 0.0);
    assert!(state.launch_traveling_shot(shooter));
    let body = state
        .players
        .iter_mut()
        .find(|player| player.id == shooter)
        .unwrap();
    body.hp = 0;
    body.respawn_timer = Some(RESPAWN_DELAY_TICKS);
    advance(&mut state, ticks_to_reach(5.5));
    assert_eq!(hp(&state, target), PLAYER_MAX_HP - DAMAGE);
    assert_eq!(hp(&state, shooter), 0);
}

#[test]
fn an_empty_list_is_omitted_and_a_live_point_round_trips() {
    let mut state = range(json!([]));
    let shooter = place(&mut state, "Shooter", 0.0, 0.0, 0.0);
    let empty = serde_json::to_value(state.snapshot()).unwrap();
    assert!(empty.get("projectiles").is_none());
    let restored = serde_json::from_value::<crate::protocol::Snapshot>(empty).unwrap();
    assert!(restored.projectiles.is_empty());
    assert!(state.launch_traveling_shot(shooter));
    let live = serde_json::to_value(state.snapshot()).unwrap();
    let point = &live["projectiles"][0];
    assert_eq!(point["id"], 1);
    assert_eq!(point["x"], 0.0);
    assert!((point["y"].as_f64().unwrap() - 1.6).abs() < 1e-4);
    assert_eq!(point["z"], 0.0);
    let restored = serde_json::from_value::<crate::protocol::Snapshot>(live).unwrap();
    assert_eq!(restored.projectiles.len(), 1);
    assert_eq!(restored.projectiles[0].id, 1);
}

#[test]
fn one_shooter_holds_one_point_and_another_shooter_can_launch() {
    let mut state = range(json!([]));
    let first = place(&mut state, "First", 0.0, 0.0, 0.0);
    let second = place(&mut state, "Second", 0.0, 4.0, std::f32::consts::FRAC_PI_2);
    assert!(state.launch_traveling_shot(first));
    assert!(!state.launch_traveling_shot(first));
    assert!(state.launch_traveling_shot(second));
    assert_eq!(state.snapshot().projectiles.len(), 2);
    advance(&mut state, LIFE_TICKS);
    assert!(state.snapshot().projectiles.is_empty());
    assert!(state.launch_traveling_shot(first));
    assert_eq!(state.snapshot().projectiles.len(), 1);
}

#[test]
fn the_point_does_not_steer_toward_a_body_that_leaves_its_line() {
    let mut state = range(json!([]));
    let shooter = place(&mut state, "Shooter", 0.0, 0.0, 0.0);
    let target = place(&mut state, "Target", 6.0, 4.0, 0.0);
    assert!(state.launch_traveling_shot(shooter));
    advance(&mut state, ticks_to_reach(5.5));
    assert_eq!(hp(&state, target), PLAYER_MAX_HP);
    let point = &state.snapshot().projectiles[0];
    assert!(point.x > 5.0);
    assert!(point.z.abs() < 1e-4);
}

#[test]
fn a_spawn_shield_does_not_stop_the_point() {
    let mut state = range(json!([]));
    let shooter = place(&mut state, "Shooter", 0.0, 0.0, 0.0);
    let target = place(&mut state, "Target", 2.0, 0.0, 0.0);
    state.spawn_shields.insert(target, SPAWN_SHIELD_TICKS);
    assert!(state.launch_traveling_shot(shooter));
    advance(&mut state, ticks_to_reach(2.0));
    assert_eq!(hp(&state, target), PLAYER_MAX_HP);
    assert!(state.snapshot().projectiles[0].x > 1.5);
}

#[test]
fn a_downward_point_ends_on_the_floor() {
    let mut state = range(json!([]));
    let shooter = place(&mut state, "Shooter", 0.0, 0.0, 0.0);
    let target = place(&mut state, "Target", 6.0, 0.0, 0.0);
    state
        .players
        .iter_mut()
        .find(|player| player.id == shooter)
        .unwrap()
        .pitch = -85.0_f32.to_radians();
    assert!(state.launch_traveling_shot(shooter));
    advance(&mut state, 30);
    assert!(state.snapshot().projectiles.is_empty());
    assert_eq!(hp(&state, target), PLAYER_MAX_HP);
    assert_eq!(hp(&state, shooter), PLAYER_MAX_HP);
}

#[test]
fn a_non_finite_step_does_not_move_the_point() {
    let mut state = range(json!([]));
    let shooter = place(&mut state, "Shooter", 0.0, 0.0, 0.0);
    assert!(state.launch_traveling_shot(shooter));
    state.tick(f32::NAN);
    let point = &state.snapshot().projectiles[0];
    assert_eq!(point.x, 0.0);
    assert!(point.y.is_finite());
    state.tick(0.0);
    assert_eq!(state.snapshot().projectiles[0].x, 0.0);
}

#[test]
fn ending_the_round_clears_a_point_still_in_flight() {
    let mut state = range(json!([]));
    let shooter = place(&mut state, "Shooter", 0.0, 0.0, 0.0);
    assert!(state.launch_traveling_shot(shooter));
    state.end_round("test".into());
    assert!(state.snapshot().projectiles.is_empty());
}

#[test]
fn the_point_passes_through_its_shooter_when_that_body_returns() {
    let mut state = range(json!([]));
    let shooter = place(&mut state, "Shooter", 0.0, 0.0, 0.0);
    assert!(state.launch_traveling_shot(shooter));
    let body = state
        .players
        .iter_mut()
        .find(|player| player.id == shooter)
        .unwrap();
    body.x = 3.0;
    advance(&mut state, ticks_to_reach(3.0));
    assert_eq!(hp(&state, shooter), PLAYER_MAX_HP);
    assert!(state.snapshot().projectiles[0].x > 2.5);
}

#[test]
fn a_departed_shooter_leaves_no_damage() {
    let mut state = range(json!([]));
    let shooter = place(&mut state, "Shooter", 0.0, 0.0, 0.0);
    let target = place(&mut state, "Target", 6.0, 0.0, 0.0);
    assert!(state.launch_traveling_shot(shooter));
    state.remove_player(shooter);
    advance(&mut state, ticks_to_reach(5.5));
    assert_eq!(hp(&state, target), PLAYER_MAX_HP);
    assert!(state.snapshot().projectiles.is_empty());
}
