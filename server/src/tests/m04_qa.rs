//! Replay declared M04 input-tour segments through authoritative movement.
use crate::maps::{AuthoredSource, RuntimeMap};
use crate::movement::{integrate, Arena, MoveState};
use crate::protocol::MissionId;

fn walk_segment(arena: &Arena, from: [f32; 3], to: [f32; 3]) -> bool {
    let mut body = MoveState {
        x: from[0],
        y: from[1],
        z: from[2],
        vx: 0.0,
        vz: 0.0,
        vy: 0.0,
        yaw: 0.0,
    };
    for _ in 0..600 {
        let dx = to[0] - body.x;
        let dz = to[2] - body.z;
        let distance = dx.hypot(dz);
        if distance < 0.2 && (body.y - to[1]).abs() < 0.2 {
            return true;
        }
        let speed = 4.0_f32.min(distance / 0.05);
        body.vx = if distance > 0.001 {
            dx / distance * speed
        } else {
            0.0
        };
        body.vz = if distance > 0.001 {
            dz / distance * speed
        } else {
            0.0
        };
        body = integrate(body, false, 0.05, arena);
    }
    false
}

fn worlds() -> (RuntimeMap, RuntimeMap) {
    let closed = RuntimeMap::Authored(
        AuthoredSource::Mission(MissionId::NoticeToVacate)
            .load()
            .unwrap(),
    );
    let opened = closed.prepared_m04_world().unwrap();
    (closed, opened)
}

#[test]
fn authored_m04_tour_segments_walk_in_valid_clinic_worlds() {
    let (closed, opened) = worlds();
    let tour: serde_json::Value =
        serde_json::from_slice(include_bytes!("../../../client/qa/m04-market.json")).unwrap();
    let mut checked = 0;
    let mut interior = 0;
    for state in tour["states"].as_array().unwrap() {
        for (kind, points) in [
            ("walk", state.get("walk_to")),
            ("search", state["combat"].get("search_route")),
            ("approach", state["combat"].get("approach_route")),
        ] {
            let Some(points) = points else { continue };
            let points: Vec<[f32; 3]> = serde_json::from_value(points.clone()).unwrap();
            for pair in points.windows(2) {
                // The clinic deliberately blocks its interior when closed. All
                // exterior and roof routes remain ordinary walks in both worlds.
                let clinic_interior = pair
                    .iter()
                    .any(|p| p[0] < -23.0 && p[2] > -7.5 && p[2] < 13.5);
                for world in [&closed, &opened] {
                    if clinic_interior && !world.m04_geometry().unwrap().clinic_open {
                        continue;
                    }
                    assert!(
                        walk_segment(world.arena(), pair[0], pair[1]),
                        "{} {kind} segment {:?} -> {:?} crosses collision (clinic {})",
                        state["name"],
                        pair[0],
                        pair[1],
                        world.m04_geometry().unwrap().clinic_open
                    );
                }
                checked += 1;
                interior += usize::from(clinic_interior);
            }
        }
    }
    assert!(checked > 70, "tour lost its ordinary walking route");
    assert!(interior >= 3, "tour lost its optional clinic visit");
}

#[test]
fn authored_m04_shutter_and_shortcuts_preserve_physical_routes() {
    let (closed, opened) = worlds();
    let door = ([-20.5, 0.0, 2.0], [-25.5, 0.0, 2.0]);
    assert!(!walk_segment(closed.arena(), door.0, door.1));
    assert!(walk_segment(opened.arena(), door.0, door.1));
    for world in [&closed, &opened] {
        assert!(!walk_segment(
            world.arena(),
            [-21.0, 0.0, -10.0],
            [-29.0, 0.0, 2.0]
        ));
        assert!(!walk_segment(
            world.arena(),
            [10.0, 0.0, 19.0],
            [13.5, 4.0, 36.5]
        ));
        assert!(!walk_segment(
            world.arena(),
            [-2.3, 0.0, 26.0],
            [0.0, 0.0, 28.5]
        ));
    }
}

#[test]
fn authored_m04_enclosed_rooms_stop_vertical_shots_and_keep_open_air_routes() {
    let (closed, opened) = worlds();
    for world in [&closed, &opened] {
        for room in [[-29.0, 1.6, 6.0], [28.0, 1.6, -23.0]] {
            assert!(
                !crate::combat::line_of_sight(room, [room[0], 8.0, room[2]], &world.arena().solids),
                "room roof must use the actual shot volumes"
            );
        }
        assert!(crate::combat::line_of_sight(
            [0.0, 1.6, 24.0],
            [0.0, 8.0, 24.0],
            &world.arena().solids
        ));
        assert!(crate::combat::line_of_sight(
            [-22.25, 6.0, 2.0],
            [-22.25, 6.15, 2.0],
            &world.arena().solids
        ));
        assert!(!crate::combat::line_of_sight(
            [-22.25, 6.0, 2.0],
            [-22.25, 7.0, 2.0],
            &world.arena().solids
        ));
    }
}

#[test]
fn authored_m04_court_roofs_survive_real_waypoint_arrival_tolerance() {
    let (closed, opened) = worlds();
    let tour: serde_json::Value =
        serde_json::from_slice(include_bytes!("../../../client/qa/m04-market.json")).unwrap();
    for world in [&closed, &opened] {
        assert!(
            !walk_segment(world.arena(), [17.0, 3.0, 30.75], [8.0, 3.0, 31.0]),
            "the old tolerance endpoint must expose its unsupported edge crossing"
        );
        let mut body = MoveState {
            x: 0.0,
            y: 0.0,
            z: 26.0,
            vx: 0.0,
            vz: 0.0,
            vy: 0.0,
            yaw: 0.0,
        };
        for state in tour["states"].as_array().unwrap().iter().filter(|s| {
            matches!(
                s["name"].as_str(),
                Some("court_balcony_stairs" | "court_roof_stairs")
            )
        }) {
            let points: Vec<[f32; 3]> = serde_json::from_value(state["walk_to"].clone()).unwrap();
            for goal in points {
                let mut arrived = false;
                for _ in 0..300 {
                    let dx = goal[0] - body.x;
                    let dz = goal[2] - body.z;
                    let distance = dx.hypot(dz);
                    // The input tour stops inside a 0.3m disk, then retains
                    // that actual body for the next leg. Exact-centre sweeps
                    // cannot prove a crossing authored on a support edge.
                    if distance < 0.3 && (body.y - goal[1]).abs() < 0.03 {
                        arrived = true;
                        break;
                    }
                    body.vx = dx / distance.max(0.001) * 4.0;
                    body.vz = dz / distance.max(0.001) * 4.0;
                    body = integrate(body, false, 0.05, world.arena());
                }
                assert!(
                    arrived,
                    "{} tolerance leg {:?} stopped at {:?}",
                    state["name"],
                    goal,
                    [body.x, body.y, body.z]
                );
            }
        }
    }
}

#[test]
fn authored_m04_tour_requires_every_guard_and_three_secrets() {
    let map: serde_json::Value =
        serde_json::from_slice(include_bytes!("../../maps/m04_notice_to_vacate.json")).unwrap();
    let tour: serde_json::Value =
        serde_json::from_slice(include_bytes!("../../../client/qa/m04-market.json")).unwrap();
    let authored: std::collections::BTreeSet<_> = map["encounters"]
        .as_array()
        .unwrap()
        .iter()
        .flat_map(|e| e["enemies"].as_array().unwrap())
        .map(|e| e["id"].as_str().unwrap())
        .collect();
    let required: Vec<_> = tour["states"]
        .as_array()
        .unwrap()
        .iter()
        .filter_map(|s| s["combat"]["required"].as_array())
        .flatten()
        .map(|id| id.as_str().unwrap())
        .collect();
    let required_set: std::collections::BTreeSet<_> = required.iter().copied().collect();
    assert_eq!(authored.len(), 28);
    assert_eq!(required.len(), required_set.len(), "duplicate guard proof");
    assert_eq!(required_set, authored);
    let secrets: Vec<_> = map["supplies"]
        .as_array()
        .unwrap()
        .iter()
        .filter(|s| s["secret"] == true)
        .collect();
    assert_eq!(secrets.len(), 3);
    for secret in secrets {
        let feet = &secret["feet"];
        assert!(tour["states"].as_array().unwrap().iter().any(|state| {
            state["walk_to"]
                .as_array()
                .is_some_and(|points| points.iter().any(|point| point == feet))
        }));
    }
    assert_eq!(
        tour["states"].as_array().unwrap().last().unwrap()["interact"],
        "party_departed"
    );
}

#[test]
fn authored_m04_west_homes_are_physical_without_changing_court_shot_lanes() {
    use crate::maps::AuthoredMap;
    use crate::navigation::{RouteStatus, SEARCH_LIMIT};
    let document: serde_json::Value =
        serde_json::from_slice(include_bytes!("../../maps/m04_notice_to_vacate.json")).unwrap();
    let mut prior = document.clone();
    prior["solids"]
        .as_array_mut()
        .unwrap()
        .retain(|solid| !solid["id"].as_str().unwrap().starts_with("west_home_"));
    let baseline = RuntimeMap::Authored(
        AuthoredMap::read(serde_json::to_vec(&prior).unwrap().as_slice()).unwrap(),
    );
    let (closed, opened) = worlds();
    for world in [&closed, &opened] {
        for (z, roof) in [(21.0, 5.5), (27.0, 6.2), (35.0, 5.15)] {
            assert!(!walk_segment(
                world.arena(),
                [-29.0, 0.0, z],
                [-22.0, 0.0, z]
            ));
            assert!(!crate::combat::line_of_sight(
                [-22.0, roof + 1.0, z],
                [-22.0, 1.6, z],
                &world.arena().solids
            ));
            // Ordinary balcony walking cannot enter a sealed home body.
            assert!(!walk_segment(
                world.arena(),
                [-18.0, 3.0, z],
                [-22.0, roof, z]
            ));
        }
        let watchers = &document["encounters"][5]["enemies"];
        for enemy in watchers.as_array().unwrap().iter().take(2) {
            for target in enemy["hover"]["patrol"].as_array().unwrap() {
                let point: [f32; 3] = serde_json::from_value(target.clone()).unwrap();
                for origin in [[0.0, 1.6, 23.0], [-17.0, 4.6, 32.0], [13.5, 5.6, 36.5]] {
                    assert_eq!(
                        crate::combat::line_of_sight(origin, point, &world.arena().solids),
                        crate::combat::line_of_sight(origin, point, &baseline.arena().solids),
                        "new home changed a court Notary shot lane"
                    );
                }
            }
        }
        // Preparation, finite supplies, tank approach and departure remain
        // reachable in the actual prepared navigation world.
        for target in [
            [-18.0, 0.0, 20.0],
            [-6.0, 0.0, 20.0],
            [-16.5, 3.0, 34.0],
            [13.5, 4.0, 36.5],
        ] {
            assert_eq!(
                world
                    .navigation()
                    .route([0.0, 0.0, 23.0], target, SEARCH_LIMIT)
                    .status,
                RouteStatus::Complete
            );
        }
    }
    assert_ne!(
        closed.content_sha256(),
        baseline.content_sha256(),
        "new collision must change content identity"
    );
}

#[test]
fn authored_m04_new_home_roofs_keep_truthful_post_stair_access_and_return() {
    let (closed, opened) = worlds();
    for world in [&closed, &opened] {
        for z in [21.0, 27.0, 35.0] {
            let mut body = MoveState {
                x: -18.8,
                y: 3.0,
                z,
                vx: -4.0,
                vz: 0.0,
                vy: 0.0,
                yaw: 0.0,
            };
            for tick in 0..50 {
                body.vx = -4.0;
                body = integrate(body, tick == 0, 0.05, world.arena());
            }
            assert!(
                body.x > -19.5 && (body.y - 3.0).abs() < 0.01,
                "balcony jump bypassed the existing sealed wall"
            );
        }
        // The existing 4m exit deck permits a jump onto the existing 5m north
        // wall. New roofs are truthful optional side platforms after this stair,
        // rather than inaccessible scenery or an early departure shortcut.
        let mut body = MoveState {
            x: 13.5,
            y: 4.0,
            z: 38.0,
            vx: 0.0,
            vz: 0.0,
            vy: 0.0,
            yaw: 0.0,
        };
        for tick in 0..25 {
            body.vz = if body.z < 39.15 { 2.0 } else { 0.0 };
            body = integrate(body, tick == 0, 0.05, world.arena());
        }
        assert!((body.y - 5.0).abs() < 0.01);
        for _ in 0..175 {
            body.vx = if body.x > -19.65 { -4.0 } else { 0.0 };
            body.vz = 0.0;
            body = integrate(body, false, 0.05, world.arena());
        }
        for _ in 0..15 {
            body.vx = if body.x > -21.0 { -2.0 } else { 0.0 };
            body.vz = if body.z > 38.6 { -2.0 } else { 0.0 };
            body = integrate(body, false, 0.05, world.arena());
        }
        assert!(body.x < -20.5 && (body.y - 5.15).abs() < 0.01);
        assert!(
            walk_segment(world.arena(), [body.x, body.y, body.z], [-19.75, 5.0, 37.6]),
            "new roof must allow an ordinary return onto the registered west wall"
        );
        assert!(walk_segment(
            world.arena(),
            [-19.75, 5.0, 37.6],
            [-18.8, 3.0, 37.6]
        ));
        assert!(walk_segment(
            world.arena(),
            [-18.8, 3.0, 37.6],
            [-18.8, 3.0, 34.25]
        ));
        assert!(walk_segment(
            world.arena(),
            [-18.8, 3.0, 34.25],
            [-12.0, 3.0, 34.25]
        ));
    }
}
