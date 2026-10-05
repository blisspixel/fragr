use super::*;
use crate::movement::{live_step, MoveInput, MoveState};
use crate::navigation::{NavigationGoal, Navigator, RouteStatus, SEARCH_LIMIT};
use crate::protocol::{Action, Role};
use crate::sim::{GameState, PLAYER_FLOOR_Y};

const SOURCE: &[u8] = include_bytes!("../../../maps/m10_common_carrier.json");

fn straight(arena: &Arena, mut body: MoveState, target: [f32; 3]) -> (MoveState, bool) {
    for _ in 0..300 {
        if (body.x - target[0]).hypot(body.z - target[2]) <= 0.3
            && (body.y - target[1]).abs() <= 0.03
        {
            return (body, true);
        }
        body = live_step(
            body,
            &MoveInput {
                forward: true,
                yaw: (target[2] - body.z).atan2(target[0] - body.x),
                ..MoveInput::default()
            },
            5.0,
            0.05,
            arena,
        );
    }
    (body, false)
}

#[test]
fn m10_tour_literal_segments_use_the_actual_open_working_aisles() {
    let map = AuthoredMap::read(SOURCE).unwrap();
    let tour: serde_json::Value = serde_json::from_str(include_str!(
        "../../../../client/qa/m10_common_carrier.json"
    ))
    .unwrap();
    let mut previous = [0.0, 4.8, -12.1];
    let mut invalid = Vec::new();
    for state in tour["states"].as_array().unwrap() {
        if let Some(points) = state["walk_to"].as_array() {
            for point in points {
                let target = std::array::from_fn(|i| point[i].as_f64().unwrap() as f32);
                // Independent literal-segment fixtures, not a completed fight
                // or living-contact proof. Actual combat can end off-anchor.
                let from = MoveState {
                    x: previous[0],
                    y: previous[1],
                    z: previous[2],
                    vx: 0.0,
                    vz: 0.0,
                    vy: 0.0,
                    yaw: 0.0,
                };
                let (body, arrived) = straight(&map.arena, from, target);
                if !arrived {
                    invalid.push((
                        state["name"].as_str().unwrap(),
                        previous,
                        target,
                        [body.x, body.y, body.z],
                    ));
                }
                previous = target;
            }
        }
    }
    assert!(
        invalid.is_empty(),
        "blocked authored route segments: {invalid:?}"
    );
}

#[test]
fn m10_tour_waypoints_have_actual_body_clearance_and_support() {
    let map = AuthoredMap::read(SOURCE).unwrap();
    let tour: serde_json::Value = serde_json::from_str(include_str!(
        "../../../../client/qa/m10_common_carrier.json"
    ))
    .unwrap();
    let mut invalid = Vec::new();
    for state in tour["states"].as_array().unwrap() {
        if let Some(points) = state["walk_to"].as_array() {
            for point in points {
                let feet = std::array::from_fn(|i| point[i].as_f64().unwrap() as f32);
                if !standing(&map.arena, feet) {
                    invalid.push((state["name"].as_str().unwrap(), feet));
                }
            }
        }
    }
    assert!(
        invalid.is_empty(),
        "unsupported or body-obstructed authored tour points: {invalid:?}"
    );
}

#[test]
fn m10_service_approach_routes_around_the_actual_cargo_and_stair_corner() {
    let map = AuthoredMap::read(SOURCE).unwrap();
    let from = MoveState {
        x: 0.0,
        y: 2.0,
        z: -8.0,
        vx: 0.0,
        vz: 0.0,
        vy: 0.0,
        yaw: 0.0,
    };
    let target = [-4.0, 2.0, 1.0];
    let (blocked, arrived) = straight(&map.arena, from, target);
    assert!(
        !arrived,
        "a direct diagonal is blocked by real cargo and stair cover"
    );
    assert!(
        (blocked.x + 3.019265).hypot(blocked.z + 6.527389) < 0.4,
        "shared collision reproduces the played corner: {blocked:?}"
    );
    // Causal geometry fixture only, never a production obstacle removal.
    let document: Document = serde_json::from_slice(SOURCE).unwrap();
    let cargo_index = document
        .solids
        .iter()
        .position(|s| s.id == "cargo_transfer_stack")
        .unwrap();
    let mut without_cargo = map.arena.clone();
    without_cargo.solids.remove(cargo_index);
    assert!(straight(&without_cargo, from, target).1);
    let mut body = from;
    for destination in [[0.0, 2.0, -2.0], [-4.0, 2.0, -2.0], target] {
        let (next, arrived) = straight(&map.arena, body, destination);
        assert!(
            arrived,
            "open-side walking failed at {destination:?}: {next:?}"
        );
        assert!((next.y - 2.0).abs() <= 0.03, "ordinary lower-deck support");
        body = next;
    }
    assert_eq!(map.arena.solids.len(), 112);
}

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
    assert_eq!(map.supplies.len(), 8, "only authored finite ship stock");
    assert!(
        map.supplies
            .iter()
            .all(|s| !matches!(s.kind, crate::sim::PickupKind::Weapon(_))),
        "no gun grant before the real lesson presentation"
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
    for height in [7.0, 8.8, 9.8] {
        assert!(
            !crate::combat::line_of_sight(
                [0.0, height, -17.0],
                [0.0, height, -20.0],
                &map.arena.solids
            ),
            "fore bulkhead and command pane remain physically pressure sealed at {height}"
        );
    }
    assert!(
        !crate::combat::line_of_sight([3.5, 3.55, -14.0], [3.5, 3.55, -10.0], &map.arena.solids),
        "cargo cover blocks a real standing-height shot"
    );
    assert!(
        crate::combat::line_of_sight([0.0, 3.55, -14.0], [0.0, 3.55, -10.0], &map.arena.solids),
        "cargo handling aisle retains the exposed alternative"
    );
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
    // This fixture proves collision walking, independently of authored combat.
    let mut walking_map = map.as_ref().clone();
    walking_map.encounters.clear();
    walking_map.m10 = None;
    let mut state = GameState::with_authored_map(Arc::new(walking_map));
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

#[test]
fn m10_authored_defense_binds_real_decks_roles_crew_and_a_physical_confirmation() {
    let map = AuthoredMap::read(SOURCE).unwrap();
    let geometry = crate::maps::RuntimeMap::Authored(map.clone())
        .m10_geometry()
        .unwrap();
    assert_eq!(
        map.encounters
            .iter()
            .map(|g| g.enemies.len())
            .collect::<Vec<_>>(),
        [4, 5, 4, 4]
    );
    assert_eq!(
        geometry
            .objectives
            .iter()
            .map(|o| o.id.as_str())
            .collect::<Vec<_>>(),
        crate::protocol::M10_OBJECTIVE_IDS
    );
    assert!(standing(&map.arena, geometry.pilot));
    for person in &geometry.passengers {
        assert!(standing(&map.arena, person.feet));
    }
    for (field, bad) in [
        ("map_id", serde_json::json!(1009)),
        ("equipment", serde_json::json!("full_arsenal")),
    ] {
        let mut forged: serde_json::Value = serde_json::from_slice(SOURCE).unwrap();
        forged[field] = bad;
        assert!(AuthoredMap::read(serde_json::to_vec(&forged).unwrap().as_slice()).is_err());
    }
    let mut forged: serde_json::Value = serde_json::from_slice(SOURCE).unwrap();
    forged["m10"]["objectives"][0]["requires_encounter"] = "passenger_defense".into();
    assert!(AuthoredMap::read(serde_json::to_vec(&forged).unwrap().as_slice()).is_err());
    let mut forged: serde_json::Value = serde_json::from_slice(SOURCE).unwrap();
    forged["m10"]["passengers"][0]["id"] = "orrin".into();
    assert!(AuthoredMap::read(serde_json::to_vec(&forged).unwrap().as_slice()).is_err());
    let mut forged: serde_json::Value = serde_json::from_slice(SOURCE).unwrap();
    forged["encounters"][1]["enemies"][0]["kind"] = "clerk".into();
    assert!(AuthoredMap::read(serde_json::to_vec(&forged).unwrap().as_slice()).is_err());
}
