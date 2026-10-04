use super::*;
use crate::maps::RuntimeMap;
use crate::navigation::{RouteStatus, SEARCH_LIMIT};

const SOURCE: &str = include_str!("../../../maps/m09_passenger_manifest.json");

#[test]
fn m09_loading_search_detour_preserves_actual_cover_and_visible_remaining_guard() {
    let map = AuthoredMap::read(SOURCE.as_bytes()).unwrap();
    let arena = &map.arena;
    assert!(
        !crate::mission::m09_route_segment_valid(arena, [-32.0, 0.0, -44.0], [-32.0, 0.0, -37.0]),
        "the rejected search crossed the existing west cargo"
    );
    let route = [
        [-36.0, 0.0, -38.5],
        [-35.0, 0.0, -44.0],
        [-35.0, 0.0, -36.5],
        [-28.0, 0.0, -36.5],
        [-22.0, 0.0, -38.0],
        [-18.0, 0.0, -36.5],
    ];
    for points in route.windows(2) {
        assert!(
            crate::mission::m09_route_segment_valid(arena, points[0], points[1]),
            "unsupported detour {:?} -> {:?}",
            points[0],
            points[1]
        );
    }
    assert!(
        crate::combat::line_of_sight(
            [-28.0, 1.6, -36.5],
            [-18.344017, 1.0, -36.46885],
            &arena.solids
        ),
        "the supported detour exposes the actual rejected Sweeper position"
    );
}

#[test]
fn m09_ordinary_capture_routes_use_supported_walks_in_the_matching_world() {
    let map = AuthoredMap::read(SOURCE.as_bytes()).unwrap();
    let runtime = RuntimeMap::Authored(map);
    let opened = runtime.prepared_m09_world().unwrap();
    let qa: serde_json::Value = serde_json::from_str(include_str!(
        "../../../../client/qa/m09_passenger_manifest.json"
    ))
    .unwrap();
    let mut hatch_open = false;
    let mut unsupported = Vec::new();
    for state in qa["states"].as_array().unwrap() {
        let arena = if hatch_open {
            opened.arena()
        } else {
            runtime.arena()
        };
        for route in [state.get("walk_to"), state["combat"].get("search_route")]
            .into_iter()
            .flatten()
        {
            let points: Vec<[f32; 3]> = serde_json::from_value(route.clone()).unwrap();
            for pair in points.windows(2) {
                if !crate::mission::m09_route_segment_valid(arena, pair[0], pair[1]) {
                    unsupported.push(format!("{}: {:?} -> {:?}", state["name"], pair[0], pair[1]));
                }
            }
        }
        if state["expect_m09_hatch_open"] == true {
            hatch_open = true;
        }
    }
    assert!(
        hatch_open,
        "the ordinary route must demand the actual raised hatch"
    );
    assert!(
        unsupported.is_empty(),
        "unsupported ordinary routes: {unsupported:?}"
    );
}

#[test]
fn m09_stairs_use_shared_supported_movement() {
    let doc: Document = serde_json::from_str(SOURCE).unwrap();
    let arena = Arena {
        half: doc.half_extent,
        solids: doc
            .solids
            .iter()
            .map(|v| Solid {
                min_x: v.min[0],
                bottom: v.min[1],
                min_z: v.min[2],
                max_x: v.max[0],
                top: v.max[1],
                max_z: v.max[2],
            })
            .collect(),
    };
    assert!(crate::mission::m09_route_segment_valid(
        &arena,
        [-41.0, 0.0, -36.0],
        [-41.0, 4.0, -26.0]
    ));
    assert!(crate::mission::m09_route_segment_valid(
        &arena,
        [-41.0, 4.0, -26.0],
        [-29.0, 4.0, -26.0]
    ));
}

#[test]
fn m09_berth_routes_and_physical_hatch_are_prepared() {
    let map = AuthoredMap::read(SOURCE.as_bytes()).unwrap();
    let runtime = RuntimeMap::Authored(map);
    let g = runtime.m09_geometry().unwrap();
    assert!(!g.hatch_open);
    assert_eq!(
        runtime
            .encounters()
            .iter()
            .map(|group| group.enemies.len())
            .sum::<usize>(),
        21
    );
    let prepared = runtime.m09_objectives().unwrap();
    assert_eq!(prepared.encounters, [0, 1, 2, 3, 4, 5, 6, 7]);
    let start = [-35.0, 0.0, -46.0];
    assert_ne!(
        runtime
            .navigation()
            .route(start, g.departure.approach, SEARCH_LIMIT)
            .status,
        RouteStatus::Complete
    );
    let opened = runtime.prepared_m09_world().unwrap();
    assert!(opened.m09_geometry().unwrap().hatch_open);
    assert_eq!(
        opened
            .navigation()
            .route(start, g.departure.approach, SEARCH_LIMIT)
            .status,
        RouteStatus::Complete
    );
    for (index, solid) in runtime.arena().solids.iter().enumerate() {
        assert_eq!(*solid == opened.arena().solids[index], index != g.hatch);
    }
    for crew in &g.crew {
        for segment in crew.route.windows(2) {
            assert!(crate::mission::m09_route_segment_valid(
                opened.arena(),
                segment[0],
                segment[1]
            ));
        }
    }
}

#[test]
fn m09_loader_refuses_false_role_roster_mixed_mission_and_unheld_crew() {
    let original: serde_json::Value = serde_json::from_str(SOURCE).unwrap();
    let mut wrong_role = original.clone();
    wrong_role["encounters"][1]["enemies"][0]["kind"] = "sweeper".into();
    assert!(AuthoredMap::read(serde_json::to_vec(&wrong_role).unwrap().as_slice()).is_err());
    let mut mixed = original.clone();
    mixed["m08"] = serde_json::json!({});
    assert!(AuthoredMap::read(serde_json::to_vec(&mixed).unwrap().as_slice()).is_err());
    let mut moving_before_release = original;
    moving_before_release["m09"]["crew"][0]["held_until"][1] = 1.into();
    assert!(AuthoredMap::read(
        serde_json::to_vec(&moving_before_release)
            .unwrap()
            .as_slice()
    )
    .is_err());
}

#[test]
fn m09_route_segment_refuses_wall_teleport_and_unsupported_target() {
    let arena = Arena {
        half: 10.0,
        solids: vec![Solid {
            min_x: -1.0,
            max_x: 1.0,
            min_z: -2.0,
            max_z: 2.0,
            bottom: 0.0,
            top: 4.0,
        }],
    };
    assert!(!crate::mission::m09_route_segment_valid(
        &arena,
        [-3.0, 0.0, 0.0],
        [3.0, 0.0, 0.0]
    ));
    assert!(!crate::mission::m09_route_segment_valid(
        &arena,
        [-3.0, 0.0, 0.0],
        [-3.0, 2.0, 0.0]
    ));
    assert!(!crate::mission::m09_route_segment_valid(
        &arena,
        [-3.0, 2.0, 0.0],
        [-3.0, 2.0, 0.0]
    ));
    assert!(crate::mission::m09_route_segment_valid(
        &arena,
        [-3.0, 0.0, -4.0],
        [3.0, 0.0, -4.0]
    ));
}
