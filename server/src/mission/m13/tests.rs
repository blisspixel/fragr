use super::*;
use crate::maps::AuthoredMap;
use crate::maps::RuntimeMap;
use crate::protocol::Role;
use crate::sim::GameState;
use std::io::Cursor;
use uuid::Uuid;

fn use_panel(state: &mut GameState, target: [f32; 3]) {
    let id = state.players[0].id;
    state.set_action(id, crate::protocol::Action::default());
    state.set_action(
        id,
        crate::protocol::Action {
            interact: true,
            look_at: Some(crate::protocol::LookAt {
                x: Some(target[0]),
                y: Some(target[1]),
                z: Some(target[2]),
                player_id: None,
            }),
            ..Default::default()
        },
    );
    state.tick(0.05);
}

fn clear_quarters(state: &mut GameState) {
    // Explicit initial placements isolate interaction authority. Combat still
    // uses the actual finite pickup and ordinary human actions.
    place(state, [-4.0, 0.0, 0.0]);
    state.tick(0.05);
    let ammunition = state.players[0]
        .inventory
        .state(state.players[0].id, state.players[0].weapon, state.tick)
        .unwrap()
        .ammo(crate::protocol::AmmoPool::Bullets);
    place(state, [8.0, 0.0, 0.0]);
    state.tick(0.05);
    let id = state.players[0].id;
    let group = state.map.m13_gates().unwrap().quarters_group;
    let mut resolved = 0;
    for _ in 0..100 {
        if state.encounters.is_complete(group) {
            break;
        }
        let Some(target) = state
            .players
            .iter()
            .find(|p| !p.is_participant() && p.hp > 0)
        else {
            state.tick(0.05);
            continue;
        };
        let look_at = crate::protocol::LookAt {
            x: Some(target.x),
            y: Some(target.y - PLAYER_FLOOR_Y + 0.9),
            z: Some(target.z),
            player_id: None,
        };
        state.set_action(
            id,
            crate::protocol::Action {
                weapon_swap: Some(crate::protocol::WeaponType::Flechette),
                fire: true,
                look_at: Some(look_at),
                ..Default::default()
            },
        );
        state.tick(0.05);
        resolved += state
            .shot_results
            .iter()
            .filter(|s| s.shooter_id == id)
            .count();
    }
    assert!(
        state.encounters.is_complete(group),
        "finite quarters fight did not clear"
    );
    assert!(resolved > 0);
    assert!(state.players[0].hp > 0);
    assert!(
        state.players[0]
            .inventory
            .state(id, state.players[0].weapon, state.tick)
            .unwrap()
            .ammo(crate::protocol::AmmoPool::Bullets)
            < ammunition
    );
    state.set_action(id, crate::protocol::Action::default());
}

fn release_point(state: &GameState) -> [f32; 3] {
    state
        .map
        .m13_gates()
        .unwrap()
        .release
        .point(
            state.map.presentation_ref().unwrap(),
            &state.current_arena().solids,
        )
        .unwrap()
}

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

#[test]
fn successor_carries_foundry_gates_and_connected_mission_identity() {
    let map = RuntimeMap::Authored(
        AuthoredMap::read(Cursor::new(include_bytes!(
            "../../../maps/m13-weight-of-permission.json"
        )))
        .expect("foundry successor"),
    );
    let gates = map.m13_gates().expect("successor gates");
    assert!(!gates.protected.is_empty());
    assert_ne!(gates.relay, gates.protected[0]);
    let deck = map.arena().solids[gates.deck_index];
    let thickness = deck.top - deck.bottom;
    assert!((0.05..=2.0).contains(&thickness));
    assert!(gates.lift_top > deck.top + 0.05);
    let landing = map
        .arena()
        .solids
        .iter()
        .find(|solid| (solid.top - solid.bottom - 3.0).abs() < 0.001 && solid.covers(0.0, 52.0))
        .expect("three metre landing");
    assert_ne!(landing.top, deck.top);
    assert_eq!(
        map.campaign_mission_id(),
        Some(crate::protocol::MissionId::WeightOfPermission)
    );
}

#[test]
fn release_requires_the_visible_terminal_and_preserves_each_workers_choice() {
    let mut state = session();
    clear_quarters(&mut state);
    place(&mut state, [8.0, 0.0, 5.0]);
    use_panel(&mut state, [12.0, 1.1, 5.0]);
    assert!(
        state.foundry.as_ref().unwrap().workers.is_none(),
        "facing away cannot release"
    );
    let target = release_point(&state);
    // The reverse side is still close to the approach marker but the post
    // blocks line of sight to its east-face terminal.
    place(&mut state, [5.5, 0.0, 5.0]);
    use_panel(&mut state, target);
    assert!(
        state.foundry.as_ref().unwrap().workers.is_none(),
        "terminal cannot be used through its host"
    );
    place(&mut state, [8.0, 0.0, 5.0]);
    use_panel(&mut state, target);
    assert_eq!(
        state.foundry.as_ref().unwrap().workers,
        Some(workers::RESPONSES)
    );
    use_panel(&mut state, target);
    assert_eq!(
        state.foundry.as_ref().unwrap().workers,
        Some(workers::RESPONSES)
    );
    assert_eq!(
        state.foundry.as_ref().unwrap().lift_phase,
        lift::Phase::Parked
    );
}

#[test]
fn departing_last_participant_resets_foundry_with_the_encounters() {
    let mut state = session();
    clear_quarters(&mut state);
    let target = release_point(&state);
    place(&mut state, [8.0, 0.0, 5.0]);
    use_panel(&mut state, target);
    assert!(state.foundry.as_ref().unwrap().workers.is_some());
    let id = state.players[0].id;
    place(&mut state, [0.0, 0.3, 0.0]);
    use_panel(&mut state, [0.0, 1.0, 1.0]);
    state.tick(0.05);
    assert!(state.foundry_arena().is_some());
    let gates = state.map.m13_gates().unwrap().clone();
    let relay = state.map.arena().solids[gates.relay];
    state.damage_foundry_relay(
        id,
        gates.relay,
        [relay.max_x, 1.0, -3.0],
        [1.0, 0.0, 0.0],
        25,
    );
    assert!(state.foundry.as_ref().unwrap().relay_disabled);
    let tick = state.tick;
    state.remove_player(id);
    assert_eq!(state.tick, tick);
    let progress = state.foundry.as_ref().unwrap();
    assert!(!progress.relay_disabled);
    assert!(progress.workers.is_none());
    assert_eq!(progress.hazard_hurt, 0);
    assert_eq!(progress.lift_phase, lift::Phase::Parked);
    assert_eq!(progress.lift_top, gates.deck.top);
    assert!(state.foundry_arena().is_none());
    state.add_player(id, "Returning participant".into(), Role::Human);
    assert!(!state.encounters.is_complete(gates.quarters_group));
}

#[test]
fn successor_lift_accepts_an_ordinary_step_on_and_carries_a_rider_to_daylight() {
    let mut source: serde_json::Value = serde_json::from_slice(include_bytes!(
        "../../../maps/m13-weight-of-permission.json"
    ))
    .unwrap();
    // Isolate the preserved standalone gate contract; connected admission is
    // exercised separately through real ready-party controls.
    source["m13"].as_object_mut().unwrap().remove("connected");
    let map = AuthoredMap::read(Cursor::new(serde_json::to_vec(&source).unwrap())).unwrap();
    let mut state = GameState::with_authored_map(map);
    let id = Uuid::from_u128(13);
    state.add_player(id, "Foundry lift rider".into(), Role::Human);
    // This is a lift acceptance fixture, not a campaign or a full foundry clear.
    // Only the initial landing placement is arranged; entry and the full rise
    // use ordinary movement and the real successor collision world.
    place(&mut state, [0.0, 3.3, 52.0]);
    let gates = state.map.m13_gates().unwrap().clone();
    for _ in 0..80 {
        if state.players[0].z <= 49.5 {
            break;
        }
        state.set_action(
            id,
            crate::protocol::Action {
                forward: true,
                look_at: Some(crate::protocol::LookAt {
                    x: Some(0.0),
                    y: Some(5.0),
                    z: Some(48.0),
                    player_id: None,
                }),
                ..Default::default()
            },
        );
        state.tick(0.05);
    }
    assert!(state.players[0].z >= gates.inset_min[1] && state.players[0].z <= gates.inset_max[1]);
    assert!((state.players[0].y - PLAYER_FLOOR_Y - gates.deck.top).abs() < 0.001);
    use_panel(&mut state, [0.0, 5.0, 48.0]);
    assert_eq!(
        state.foundry.as_ref().unwrap().lift_phase,
        lift::Phase::Moving
    );
    state.set_action(id, crate::protocol::Action::default());

    let blocker = Uuid::from_u128(14);
    state.add_player(blocker, "Lift obstruction".into(), Role::Human);
    let rider_feet = state.players[0].y - PLAYER_FLOOR_Y;
    let rider_z = state.players[0].z;
    let body = state.players.iter_mut().find(|p| p.id == blocker).unwrap();
    body.hp = 100;
    body.respawn_timer = None;
    body.x = 0.0;
    body.z = rider_z;
    body.y = rider_feet + crate::movement::BODY_HEIGHT + PLAYER_FLOOR_Y;
    body.vy = 0.0;
    state.advance_foundry_lift(0.05);
    assert_eq!(
        state.foundry.as_ref().unwrap().lift_phase,
        lift::Phase::Blocked
    );
    assert_eq!(state.foundry.as_ref().unwrap().lift_top, gates.deck.top);
    assert_eq!(state.players[0].y - PLAYER_FLOOR_Y, rider_feet);
    state.remove_player(blocker);

    let started = state.tick;
    for _ in 0..200 {
        let previous = state.foundry.as_ref().unwrap().lift_top;
        state.tick(0.05);
        let progress = state.foundry.as_ref().unwrap();
        assert!(progress.lift_top >= previous);
        assert!(progress.lift_top - previous <= lift::MAX_STEP + 0.0001);
        assert!((state.players[0].y - PLAYER_FLOOR_Y - progress.lift_top).abs() < 0.001);
        assert_eq!(
            state.current_arena().solids[gates.deck_index].top,
            progress.lift_top
        );
        if progress.lift_phase == lift::Phase::Arrived {
            break;
        }
    }
    assert!(state.tick > started + 100);
    assert_eq!(
        state.foundry.as_ref().unwrap().lift_phase,
        lift::Phase::Arrived
    );
    assert!((state.players[0].y - PLAYER_FLOOR_Y - gates.lift_top).abs() < 0.001);
    assert!(state.mission_state().is_none());
}

#[test]
fn last_participant_death_clears_actual_hazard_damage_for_the_next_attempt() {
    let mut state = session();
    place(&mut state, [13.0, 0.0, 7.0]);
    state.tick = 69;
    state.tick(0.05);
    assert_eq!(state.players[0].hp, 100 - hazard::TICK_DAMAGE);
    assert_eq!(
        state.foundry.as_ref().unwrap().hazard_hurt,
        hazard::TICK_DAMAGE as u64
    );
    state.players[0].hp = 0;
    state.tick(0.05);
    assert_eq!(state.foundry.as_ref().unwrap().hazard_hurt, 0);
    assert_eq!(state.tick, 71);
}

#[test]
fn detached_eliminated_dead_or_waiting_bodies_cannot_operate_foundry_gates() {
    for invalid in 0..4 {
        let mut state = session();
        place(&mut state, [0.0, 0.3, 0.0]);
        match invalid {
            0 => state.players[0].detached = true,
            1 => state.players[0].eliminated = true,
            2 => state.players[0].respawn_timer = Some(1),
            _ => state.players[0].hp = 0,
        }
        state.players[0].interaction_requested = true;
        state.advance_foundry();
        assert_eq!(
            state.foundry.as_ref().unwrap().lift_phase,
            lift::Phase::Parked
        );
        let gates = state.map.m13_gates().unwrap().clone();
        let relay = state.map.arena().solids[gates.relay];
        state.damage_foundry_relay(
            state.players[0].id,
            gates.relay,
            [relay.max_x, 1.0, -3.0],
            [1.0, 0.0, 0.0],
            25,
        );
        assert!(!state.foundry.as_ref().unwrap().relay_disabled);
        state.players[0].x = 13.0;
        state.players[0].y = PLAYER_FLOOR_Y;
        state.players[0].z = 7.0;
        state.tick = 70;
        let hp = state.players[0].hp;
        state.tick_foundry_hazards();
        assert_eq!(state.players[0].hp, hp);
        assert_eq!(state.foundry.as_ref().unwrap().hazard_hurt, 0);
    }
}
