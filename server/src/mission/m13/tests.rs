use super::*;
use crate::maps::AuthoredMap;
use crate::maps::RuntimeMap;
use crate::protocol::Role;
use crate::sim::GameState;
use std::io::Cursor;
use uuid::Uuid;

fn gates() -> std::sync::Arc<AuthoredMap> {
    AuthoredMap::read(Cursor::new(include_bytes!(
        "../../../maps/test/m13_gates.json"
    )))
    .expect("foundry gate fixture")
}

fn place(state: &mut GameState, feet: [f32; 3]) {
    let player = &mut state.players[0];
    player.hp = 100;
    player.armor = 0;
    player.respawn_timer = None;
    player.x = feet[0];
    player.y = feet[1] + PLAYER_FLOOR_Y;
    player.z = feet[2];
    player.vy = 0.0;
    player.pending_action = crate::protocol::Action::default();
}

fn session() -> GameState {
    let mut state = GameState::with_authored_map(gates());
    state.add_player(Uuid::from_u128(7), "Proxy".into(), Role::Human);
    state
}

#[test]
fn fixture_loads_gates_without_becoming_a_mission() {
    let map = RuntimeMap::Authored(gates());
    let gates = map.m13_gates().expect("gates");
    assert_eq!(gates.cycle.period, 100);
    assert_eq!(gates.protected.len(), 1);
    assert_ne!(gates.relay, gates.protected[0]);
    assert!(map.campaign_mission_id().is_none());
    let practice = AuthoredMap::read(Cursor::new(include_bytes!(
        "../../../maps/test/m13_foundry_development.json"
    )))
    .expect("practice foundry");
    assert!(RuntimeMap::Authored(practice).m13_gates().is_none());
}

#[test]
fn hazard_hurts_only_an_active_body_inside_the_volume() {
    let mut quiet = session();
    place(&mut quiet, [13.0, 0.0, 7.0]);
    quiet.tick = 0;
    let before = quiet.players[0].hp;
    quiet.tick(0.05);
    assert_eq!(quiet.players[0].hp, before);
    assert_eq!(quiet.foundry.as_ref().unwrap().hazard_hurt, 0);

    let mut active = session();
    place(&mut active, [13.0, 0.0, 7.0]);
    active.tick = 69;
    active.tick(0.05);
    assert!(active.players[0].hp < before);
    assert!(active.foundry.as_ref().unwrap().hazard_hurt > 0);

    let mut outside = session();
    place(&mut outside, [0.0, 0.3, 0.0]);
    outside.tick = 69;
    outside.tick(0.05);
    assert_eq!(outside.players[0].hp, before);
    assert_eq!(outside.foundry.as_ref().unwrap().hazard_hurt, 0);

    let mut bypass = session();
    place(&mut bypass, [13.0, 0.0, 10.0]);
    bypass.tick = 69;
    bypass.tick(0.05);
    assert_eq!(bypass.players[0].hp, before);
    assert_eq!(bypass.foundry.as_ref().unwrap().hazard_hurt, 0);
}

#[test]
fn relay_face_hit_disables_it_and_the_feed_stays_on() {
    let mut state = session();
    let gates = state.map.m13_gates().unwrap().clone();
    let relay = state.map.arena().solids[gates.relay];
    let feed = state.map.arena().solids[gates.protected[0]];
    let shooter = state.players[0].id;
    state.damage_foundry_relay(
        shooter,
        gates.protected[0],
        [feed.max_x, 1.0, (feed.min_z + feed.max_z) * 0.5],
        [1.0, 0.0, 0.0],
        40,
    );
    assert!(!state.foundry.as_ref().unwrap().relay_disabled);
    assert!(state.foundry.is_some());
    state.damage_foundry_relay(
        shooter,
        gates.relay,
        [(relay.min_x + relay.max_x) * 0.5, 1.0, 10.0],
        [0.0, 1.0, 0.0],
        40,
    );
    assert!(!state.foundry.as_ref().unwrap().relay_disabled);
    state.damage_foundry_relay(
        shooter,
        gates.relay,
        [relay.max_x, 1.0, (relay.min_z + relay.max_z) * 0.5],
        [1.0, 0.0, 0.0],
        40,
    );
    assert!(state.foundry.as_ref().unwrap().relay_disabled);
    assert!(state.foundry.is_some());
    state.damage_foundry_relay(
        shooter,
        gates.deck_index,
        [0.0, 0.3, 0.0],
        [0.0, 1.0, 0.0],
        40,
    );
    assert!(state.foundry.is_some());
}

#[test]
fn release_refuses_an_uncleared_quarters_and_the_lift_carries_a_rider() {
    let mut state = session();
    place(&mut state, [8.0, 0.0, 5.0]);
    state.players[0].interaction_requested = true;
    state.tick(0.05);
    assert!(state.foundry.as_ref().unwrap().workers.is_none());
    assert_eq!(
        state.foundry.as_ref().unwrap().lift_phase,
        lift::Phase::Parked
    );

    let mut riding = session();
    place(&mut riding, [0.0, 0.3, 0.0]);
    riding.players[0].interaction_requested = true;
    riding.tick(0.05);
    assert_eq!(
        riding.foundry.as_ref().unwrap().lift_phase,
        lift::Phase::Moving
    );
    let y = riding.players[0].y;
    riding.tick(0.05);
    assert!((riding.players[0].y - y - lift::MAX_STEP).abs() < 0.0001);
    assert!((riding.foundry.as_ref().unwrap().lift_top - 0.3 - lift::MAX_STEP).abs() < 0.0001);
    let deck = riding.map.arena().solids[riding.map.m13_gates().unwrap().deck_index];
    let moved = riding.foundry_arena().unwrap();
    assert!((moved.solids[riding.map.m13_gates().unwrap().deck_index].top - deck.top).abs() > 0.05);
}

#[test]
fn overlapping_hazard_and_shared_relay_fail_closed() {
    let mut value: serde_json::Value =
        serde_json::from_slice(include_bytes!("../../../maps/test/m13_gates.json")).unwrap();
    value["m13"]["hazard"]["max"][2] = serde_json::json!(10.0);
    let error = AuthoredMap::read(Cursor::new(serde_json::to_vec(&value).unwrap()))
        .err()
        .unwrap();
    assert!(error
        .to_string()
        .contains("foundry hazard overlaps its bypass"));
    value = serde_json::from_slice(include_bytes!("../../../maps/test/m13_gates.json")).unwrap();
    value["m13"]["protected"][0] = serde_json::json!("relay_housing");
    let error = AuthoredMap::read(Cursor::new(serde_json::to_vec(&value).unwrap()))
        .err()
        .unwrap();
    assert!(error
        .to_string()
        .contains("foundry utility shares the relay"));
}
