use super::*;
use crate::navigation::{NavigationGoal, Navigator, RouteStatus, SEARCH_LIMIT};
use crate::protocol::{Action, Role};
use crate::sim::{GameState, PLAYER_FLOOR_Y};

const SOURCE: &[u8] = include_bytes!("../../../maps/m10_common_carrier.json");

#[test]
fn m10_each_stair_flight_and_turn_has_a_real_navigation_connection() {
    let doc: Document = serde_json::from_slice(SOURCE).unwrap();
    let arena = Arena {
        half: doc.half_extent,
        solids: doc
            .solids
            .into_iter()
            .map(|s| Solid {
                min_x: s.min[0],
                max_x: s.max[0],
                min_z: s.min[2],
                max_z: s.max[2],
                bottom: s.min[1],
                top: s.max[1],
            })
            .collect(),
    };
    crate::movement::validate_geometry(arena.half, &arena.solids).unwrap();
    let nav = Navigation::new(arena.clone()).unwrap();
    for (xa, xb, z_start, z_turn) in [(-6.55, -4.45, -14.5, -4.5), (4.55, 6.65, 14.5, 4.5)] {
        for base in [2.0, 4.8] {
            let points = [
                [xa, base, z_start],
                [xa, base + 1.4, z_turn],
                [xb, base + 1.4, z_turn],
                [xb, base + 2.8, z_start],
            ];
            for feet in points {
                assert!(
                    standing(&arena, feet),
                    "stair point lacks supported body clearance {feet:?}"
                );
            }
            for segment in points.windows(2) {
                let route = nav.route(segment[0], segment[1], SEARCH_LIMIT);
                assert_eq!(
                    route.status,
                    RouteStatus::Complete,
                    "stair segment {:?} -> {:?}, direct walkable={}, route={route:?}",
                    segment[0],
                    segment[1],
                    nav.walkable(segment[0], segment[1])
                );
            }
        }
    }
}

#[test]
fn m10_collision_shell_has_three_supported_decks_and_a_sealed_freight_volume() {
    let map = AuthoredMap::read(SOURCE).unwrap();
    assert_eq!(map.id, 1010);
    assert!(
        map.mission.is_none(),
        "collision work alone is not a mission"
    );
    assert!(
        map.supplies.is_empty(),
        "no gun grant before the lesson contract"
    );
    assert!(map.arena.solids.len() <= 128);
    for (feet, expected_ceiling) in [
        ([0.0, 2.0, -15.0], 4.6),
        ([0.0, 4.8, -15.0], 7.4),
        ([0.0, 7.6, -15.0], 10.1),
    ] {
        assert!(
            standing(&map.arena, feet),
            "full body clearance at {feet:?}"
        );
        let ceiling = map
            .arena
            .ceiling_height_for_body(feet[0], feet[2], feet[1], 2.4);
        assert!((ceiling - expected_ceiling).abs() < 0.001);
        assert!(
            ceiling - feet[1] >= 2.4,
            "working deck headroom at {feet:?}"
        );
    }
    assert!(!crate::combat::line_of_sight(
        [0.0, 9.0, 1.0],
        [0.0, 12.0, 1.0],
        &map.arena.solids,
    ));
    assert!(!crate::combat::line_of_sight(
        [-7.0, 6.0, 14.0],
        [-10.0, 6.0, 14.0],
        &map.arena.solids,
    ));
    for y in [4.8, 7.6] {
        assert_eq!(map.arena.support_height(0.0, 1.0, y + 0.01), 2.0);
    }
    let mut crushed: serde_json::Value = serde_json::from_slice(SOURCE).unwrap();
    let roof = crushed["solids"]
        .as_array_mut()
        .unwrap()
        .iter_mut()
        .find(|solid| solid["id"] == "pressure_roof")
        .unwrap();
    roof["min"][1] = 8.8.into();
    assert!(AuthoredMap::read(serde_json::to_vec(&crushed).unwrap().as_slice()).is_err());
}

fn walk(map: &Arc<AuthoredMap>, from: [f32; 3], waypoints: &[[f32; 3]]) {
    let mut state = GameState::with_authored_map(map.clone());
    state.config.time_limit_ticks = None;
    state.config.boss_spawn_ticks = None;
    state.config.compliance_ping_ticks = None;
    let id = uuid::Uuid::from_u128(1010);
    state.add_player(id, "Deck route".into(), Role::Human);
    state.start_round();
    state.players[0].x = from[0];
    state.players[0].y = from[1] + PLAYER_FLOOR_Y;
    state.players[0].z = from[2];
    let mut navigator = Navigator::default();
    let mut tick = 0;
    for target in waypoints {
        let from = [
            state.players[0].x,
            state.players[0].y - PLAYER_FLOOR_Y,
            state.players[0].z,
        ];
        assert_eq!(
            map.navigation.route(from, *target, SEARCH_LIMIT).status,
            RouteStatus::Complete
        );
        let mut arrived = false;
        for _ in 0..1000 {
            let player = &state.players[0];
            let here = [player.x, player.y - PLAYER_FLOOR_Y, player.z];
            if (here[0] - target[0]).hypot(here[2] - target[2]) < 0.3
                && (here[1] - target[1]).abs() < 0.1
            {
                arrived = true;
                break;
            }
            let action = navigator.steer(
                &map.navigation,
                here,
                NavigationGoal {
                    feet: *target,
                    combat: false,
                },
                Action {
                    forward: true,
                    ..Default::default()
                },
                tick,
                true,
            );
            assert!(!action.jump, "walking stairs must not require jumps");
            state.set_action(id, action);
            state.tick(0.05);
            state.take_events();
            assert_eq!(
                state.players[0].hp, 100,
                "ordinary supported traversal cannot cause damage"
            );
            tick += 1;
        }
        assert!(
            arrived,
            "{from:?} -> {target:?} stalled at ({}, {}, {})",
            state.players[0].x,
            state.players[0].y - PLAYER_FLOOR_Y,
            state.players[0].z
        );
    }
}

#[test]
fn m10_both_stair_trunks_and_cargo_routes_use_real_server_walking() {
    let map = AuthoredMap::read(SOURCE).unwrap();
    for (x_first, x_second, z_start, z_turn) in
        [(-6.55, -4.45, -14.5, -4.5), (4.55, 6.65, 14.5, 4.5)]
    {
        for base in [2.0, 4.8] {
            let route = [
                [x_first, base + 1.4, z_turn],
                [x_second, base + 1.4, z_turn],
                [x_second, base + 2.8, z_start],
            ];
            walk(&map, [x_first, base, z_start], &route);
            let reverse = [
                [x_second, base + 1.4, z_turn],
                [x_first, base + 1.4, z_turn],
                [x_first, base, z_start],
            ];
            walk(&map, [x_second, base + 2.8, z_start], &reverse);
        }
    }
    walk(
        &map,
        [0.0, 4.8, -15.0],
        &[
            [0.0, 2.0, -12.0],
            [-4.0, 2.0, 1.0],
            [0.0, 2.0, 14.0],
            [0.0, 7.6, 14.0],
            [-4.0, 7.6, 1.0],
            [0.0, 7.6, -15.0],
            [0.0, 4.8, -15.0],
        ],
    );
}
