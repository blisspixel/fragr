use super::*;
use crate::movement::EYE_HEIGHT;
use crate::navigation::{NavigationGoal, Navigator, RouteStatus, SEARCH_LIMIT};
use crate::protocol::{Action, Role};
use crate::sim::{GameState, PLAYER_FLOOR_Y};

const SOURCE: &[u8] = include_bytes!("../../../maps/test/m11_tender_structure.json");
const MISSION_SOURCE: &[u8] = include_bytes!("../../../maps/m11_right_of_search.json");

#[test]
fn m11_authored_tender_prepares_exact_actors_targets_stocks_and_window_cover() {
    let map = AuthoredMap::read(MISSION_SOURCE).unwrap();
    assert_eq!(map.id, 1011);
    assert_eq!(map.arena.solids.len(), 107);
    assert_eq!(
        map.encounters
            .iter()
            .map(|g| g.enemies.len())
            .sum::<usize>(),
        13
    );
    assert_eq!(map.supplies.len(), 8);
    let prepared = map.m11.as_ref().unwrap();
    prepared
        .geometry
        .validate(map.arena.half, &map.arena.solids, Some(&map.presentation))
        .unwrap();
    assert_eq!(prepared.geometry.transfer_people.len(), 3);
    for feet in &prepared.geometry.transfer_people {
        assert!(standing(&map.arena, *feet));
    }
    for target in [
        &prepared.geometry.transfer_release,
        &prepared.geometry.records_document,
        &prepared.geometry.departure,
    ] {
        assert!(standing(&map.arena, target.approach));
        let point = target.point(&map.presentation, &map.arena.solids).unwrap();
        let eye = [
            target.approach[0],
            target.approach[1] + EYE_HEIGHT,
            target.approach[2],
        ];
        assert!(crate::combat::line_of_sight(eye, point, &map.arena.solids));
    }
    assert_eq!(
        map.presentation
            .solids
            .iter()
            .filter(|surface| **surface == crate::protocol::MapSurface::InspectionGlass)
            .count(),
        5
    );
    assert!(
        !crate::combat::line_of_sight([-8.0, 1.9, 6.0], [-12.0, 1.9, 6.0], &map.arena.solids),
        "observation glass retains world shot interception"
    );
    let runtime = crate::maps::RuntimeMap::Authored(map);
    assert!(runtime.requires_m11_contract());
    assert!(runtime.m11_geometry().is_some());
    assert_eq!(
        crate::protocol::GAMEPLAY_VERSION,
        crate::protocol::M11_GAMEPLAY_VERSION,
        "typed tender admission requires its own current capability"
    );
}

#[test]
fn m11_authored_targets_people_and_patrol_refuse_real_boundary_defects() {
    let original: serde_json::Value = serde_json::from_slice(MISSION_SOURCE).unwrap();
    for (field, value) in [
        ("cycle_ticks", serde_json::json!(239)),
        ("spacing", serde_json::json!(1.0)),
        ("from", serde_json::json!([1, 0.3, -22])),
    ] {
        let mut bad = original.clone();
        bad["m11"]["spine_patrol"][field] = value;
        assert!(
            AuthoredMap::read(serde_json::to_vec(&bad).unwrap().as_slice()).is_err(),
            "invalid patrol {field}"
        );
    }
    let mut bad = original.clone();
    bad["m11"]["spine_patrol"]["cycle_ticks"] = 240.into();
    bad["m11"]["spine_patrol"]["to"] = serde_json::json!([0, 0.3, -6]);
    assert!(
        AuthoredMap::read(serde_json::to_vec(&bad).unwrap().as_slice())
            .unwrap_err()
            .to_string()
            .contains("cadence"),
        "a cadence cannot outrun the actual Clerk walking step"
    );
    bad = original.clone();
    bad["encounters"][0]["enemies"][1]["feet"][2] = (-23.1).into();
    assert!(AuthoredMap::read(serde_json::to_vec(&bad).unwrap().as_slice()).is_err());
    bad = original.clone();
    bad["m11"]["transfer_people"][0][0] = 8.35.into();
    assert!(
        AuthoredMap::read(serde_json::to_vec(&bad).unwrap().as_slice()).is_err(),
        "a transfer body cannot overlap the restraint bench"
    );
    bad = original.clone();
    bad["m11"]["records_document"]["approach"] = serde_json::json!([3.4, 0.3, 17]);
    assert!(
        AuthoredMap::read(serde_json::to_vec(&bad).unwrap().as_slice()).is_err(),
        "reachable is not physically usable from five metres away"
    );
    bad = original.clone();
    bad["m11"]["departure"]["panel"]["kind"] = "m11_transfer_release".into();
    assert!(AuthoredMap::read(serde_json::to_vec(&bad).unwrap().as_slice()).is_err());
    bad = original.clone();
    bad["solids"].as_array_mut().unwrap().push(serde_json::json!({"id":"blocked_patrol","min":[-0.6,0.3,-18.1],"max":[0.6,2.3,-17.9],"surface":"service_steel"}));
    assert!(
        AuthoredMap::read(serde_json::to_vec(&bad).unwrap().as_slice()).is_err(),
        "routeable endpoints cannot permit a solid through the fixed march"
    );
    bad = original;
    bad["map_id"] = 1111.into();
    assert!(AuthoredMap::read(serde_json::to_vec(&bad).unwrap().as_slice()).is_err());
}

#[test]
fn m11_authored_all_targets_supplies_guards_and_returns_have_real_routes() {
    let map = AuthoredMap::read(MISSION_SOURCE).unwrap();
    let prepared = map.m11.as_ref().unwrap();
    let entry = map.spawns[0].feet;
    let mut count = 0;
    for feet in prepared
        .geometry
        .objectives
        .iter()
        .filter_map(|o| match o.action {
            crate::protocol::MissionObjectiveAction::Arrival { feet, .. } => Some(feet),
            _ => None,
        })
        .chain([
            prepared.geometry.transfer_release.approach,
            prepared.geometry.records_document.approach,
            prepared.geometry.departure.approach,
        ])
        .chain(prepared.geometry.transfer_people.iter().copied())
        .chain(map.supplies.iter().map(|p| [p.x, p.floor, p.z]))
        .chain(
            map.encounters
                .iter()
                .flat_map(|g| g.enemies.iter().map(|p| p.feet)),
        )
    {
        for (from, to) in [(entry, feet), (feet, entry)] {
            assert_eq!(
                prepared.navigation.route(from, to, SEARCH_LIMIT).status,
                RouteStatus::Complete,
                "unreachable {from:?} to {to:?}"
            );
            count += 1;
        }
    }
    assert_eq!(count, 66);
    // This owning fixture isolates geometry and ordinary integration. It is
    // not a claim that a participant has completed the thirteen-guard mission.
    let mut unpopulated = map.as_ref().clone();
    unpopulated.encounters.clear();
    unpopulated.m11 = None;
    walk(
        &Arc::new(unpopulated),
        entry,
        &[
            [-4.0, 0.3, -24.3],
            [0.0, 0.3, -17.5],
            [4.0, 0.3, -8.0],
            [4.3, 0.3, -13.5],
            [3.5, 0.3, 12.0],
            [7.9, 0.3, 17.0],
            [0.0, 0.3, 14.0],
            [3.0, 1.5, 27.0],
            [16.8, 1.5, 27.5],
            [-8.0, 1.5, 27.0],
            [-8.0, 0.3, 10.0],
            [-4.0, 0.3, -25.0],
            entry,
        ],
    );
}

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
