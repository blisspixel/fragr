use super::*;
use crate::navigation::{NavigationGoal, Navigator, RouteStatus, SEARCH_LIMIT};
use crate::protocol::{Action, Role};
use crate::sim::{GameState, PLAYER_FLOOR_Y};

const SOURCE: &[u8] = include_bytes!("../../../maps/test/m11_tender_structure.json");

#[test]
fn m11_structure_is_an_explicit_nonmission_with_finite_stock() {
    let map = AuthoredMap::read(SOURCE).unwrap();
    assert_eq!(map.id, 1111);
    assert_eq!(map.name, "Right of Search structural study");
    assert!(map.mission.is_none());
    assert!(map.m10.is_none());
    assert!(map.encounters.is_empty());
    assert_eq!(map.supplies.len(), 6);
    assert_eq!(map.arena.solids.len(), 95);
    assert_eq!(map.spawns[0].feet, [-16.0, 0.3, -27.5]);
    let state = GameState::with_authored_map(map);
    assert_eq!(state.snapshot().mode_name, "Campaign development");
    assert!(state.mission_state().is_none());
}

#[test]
fn m11_structure_supports_every_named_room_stock_and_return_bidirectionally() {
    let map = AuthoredMap::read(SOURCE).unwrap();
    let entry = map.spawns[0].feet;
    for (name, feet) in map
        .landmarks
        .iter()
        .map(|place| (place.id.as_str(), place.feet))
        .chain(
            map.supplies
                .iter()
                .map(|stock| (stock.id.as_str(), [stock.x, stock.floor, stock.z])),
        )
    {
        assert!(standing(&map.arena, feet), "no standing clearance: {name}");
        for (from, to) in [(entry, feet), (feet, entry)] {
            let route = map.navigation.route(from, to, SEARCH_LIMIT);
            assert_eq!(
                route.status,
                RouteStatus::Complete,
                "{name} has no bounded route {from:?} -> {to:?}: {route:?}"
            );
        }
    }
}

#[test]
fn m11_pressure_shell_bulkheads_and_racks_have_truthful_shot_cover() {
    let map = AuthoredMap::read(SOURCE).unwrap();
    let visible = |from, to| crate::combat::line_of_sight(from, to, &map.arena.solids);
    for (from, to) in [
        ([0.0, 1.9, -29.0], [0.0, 1.9, -34.0]),
        ([0.0, 1.9, 31.0], [0.0, 1.9, 34.0]),
        ([8.0, 1.9, 8.0], [12.0, 1.9, 8.0]),
        ([-8.0, 1.9, 8.0], [-12.0, 1.9, 8.0]),
        ([0.0, 2.0, 0.0], [0.0, 6.0, 0.0]),
        ([6.0, 1.9, 4.0], [6.0, 1.9, 8.0]),
        ([3.0, 1.9, -23.0], [3.0, 1.9, -14.0]),
    ] {
        assert!(
            !visible(from, to),
            "untruthful enclosure/cover: {from:?} -> {to:?}"
        );
    }
    assert!(
        visible([0.0, 1.9, -29.0], [0.0, 1.9, 16.0]),
        "mine lesson retains its main sightline"
    );
    assert!(
        visible([3.4, 1.9, 4.0], [3.4, 1.9, 17.0]),
        "records outer aisle is exposed"
    );
    assert!(
        visible([-8.0, 1.9, -24.0], [-8.0, 1.9, 17.0]),
        "service route retains a distinct sightline"
    );
    for (feet, ceiling) in [
        ([0.0, 0.3, -23.0], 3.5),
        ([-8.0, 0.3, 0.0], 3.3),
        ([3.4, 0.3, 12.0], 5.1),
        ([3.0, 1.5, 27.0], 5.1),
        ([16.0, 1.5, 27.5], 4.7),
    ] {
        assert!(standing(&map.arena, feet));
        let actual = map
            .arena
            .ceiling_height_for_body(feet[0], feet[2], feet[1], BODY_HEIGHT);
        assert!(
            (actual - ceiling).abs() < 0.001,
            "wrong headroom at {feet:?}: {actual}"
        );
        assert!(actual - feet[1] >= BODY_HEIGHT);
    }
}

fn walk(map: &Arc<AuthoredMap>, from: [f32; 3], destinations: &[[f32; 3]]) {
    let mut state = GameState::with_authored_map(map.clone());
    state.config.time_limit_ticks = None;
    state.config.boss_spawn_ticks = None;
    state.config.compliance_ping_ticks = None;
    let id = uuid::Uuid::from_u128(1111);
    state.add_player(id, "Tender structure route".into(), Role::Human);
    state.start_round();
    state.players[0].x = from[0];
    state.players[0].y = from[1] + PLAYER_FLOOR_Y;
    state.players[0].z = from[2];
    let mut navigator = Navigator::default();
    for destination in destinations {
        let mut arrived = false;
        for _ in 0..1500 {
            let player = &state.players[0];
            let feet = [player.x, player.y - PLAYER_FLOOR_Y, player.z];
            if (feet[0] - destination[0]).hypot(feet[2] - destination[2]) <= 0.3
                && (feet[1] - destination[1]).abs() <= 0.04
            {
                arrived = true;
                break;
            }
            let action = navigator.steer(
                state.map.navigation(),
                feet,
                NavigationGoal {
                    feet: *destination,
                    combat: false,
                },
                Action::default(),
                state.tick,
                true,
            );
            assert!(!action.jump, "structural route requires ordinary walking");
            state.set_action(id, action);
            state.tick(0.05);
            state.take_events();
            assert_eq!(state.players[0].hp, 100, "supported route caused damage");
            let player = &state.players[0];
            let bottom = player.y - PLAYER_FLOOR_Y;
            assert!(
                !state.current_arena().solids.iter().any(|solid| {
                    solid.covers(player.x, player.z)
                        && solid.top > bottom + CONTACT_EPSILON
                        && solid.bottom < bottom + BODY_HEIGHT - CONTACT_EPSILON
                }),
                "ordinary body entered structural solid"
            );
        }
        assert!(
            arrived,
            "route stalled at {:?} before {destination:?}",
            [
                state.players[0].x,
                state.players[0].y - PLAYER_FLOOR_Y,
                state.players[0].z
            ]
        );
    }
}

#[test]
fn m11_both_bridge_approaches_rooms_and_distinct_umbilicals_use_real_walking() {
    let map = AuthoredMap::read(SOURCE).unwrap();
    walk(
        &map,
        map.spawns[0].feet,
        &[
            [-4.0, 0.3, -26.5],
            [0.0, 0.3, -23.0],
            [4.0, 0.3, -22.0],
            [4.0, 0.3, -8.0],
            [3.5, 0.3, 12.0],
            [0.0, 0.3, 16.0],
            [0.0, 1.5, 25.0],
            [3.0, 1.5, 27.0],
            [16.0, 1.5, 27.5],
            [3.0, 1.5, 27.0],
            [-8.0, 1.5, 27.0],
            [-8.0, 0.3, 18.0],
            [-8.0, 0.3, 0.0],
            [-8.0, 0.3, -26.5],
            [-16.0, 0.3, -27.5],
        ],
    );
    walk(
        &map,
        [-8.0, 0.3, 18.0],
        &[
            [-8.0, 1.5, 27.0],
            [0.0, 1.5, 25.0],
            [0.0, 0.3, 16.0],
            [-8.0, 0.3, 18.0],
        ],
    );
    for stock in &map.supplies {
        let point = [stock.x, stock.floor, stock.z];
        walk(&map, map.spawns[0].feet, &[point, map.spawns[0].feet]);
    }
}

#[test]
fn m11_structure_rejects_severed_route_crushed_return_and_fake_mission_field() {
    let mut source: serde_json::Value = serde_json::from_slice(SOURCE).unwrap();
    source["m11"] = serde_json::json!({"objectives": []});
    assert!(AuthoredMap::read(serde_json::to_vec(&source).unwrap().as_slice()).is_err());
    for (id, min_y) in [("stern_pressure_roof", 2.6), ("spine_ceiling", 2.0)] {
        let mut source: serde_json::Value = serde_json::from_slice(SOURCE).unwrap();
        let solid = source["solids"]
            .as_array_mut()
            .unwrap()
            .iter_mut()
            .find(|solid| solid["id"] == id)
            .unwrap();
        solid["min"][1] = min_y.into();
        assert!(
            AuthoredMap::read(serde_json::to_vec(&source).unwrap().as_slice()).is_err(),
            "crushed {id} was accepted"
        );
    }
    let mut source: serde_json::Value = serde_json::from_slice(SOURCE).unwrap();
    source["solids"].as_array_mut().unwrap().push(serde_json::json!({
        "id": "severed_entry", "min": [-10.0, 0.3, -29.0], "max": [-9.78, 3.5, -26.0], "surface": "enamel"
    }));
    let error = AuthoredMap::read(serde_json::to_vec(&source).unwrap().as_slice()).unwrap_err();
    assert!(error.to_string().contains("unreachable"));
}
