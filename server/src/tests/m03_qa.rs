//! Keep explicit rendered-tour waypoints honest against the shared movement.
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

#[test]
fn authored_m03_tour_segments_walk_in_both_mast_worlds() {
    let map = RuntimeMap::Authored(
        AuthoredSource::Mission(MissionId::ScheduledService)
            .load()
            .unwrap(),
    );
    let fallen = map.prepared_m03_world().unwrap();
    let tour: serde_json::Value = serde_json::from_slice(include_bytes!(
        "../../../client/qa/m03-scheduled-service.json"
    ))
    .unwrap();
    let mut checked = 0;
    for state in tour["states"].as_array().unwrap() {
        for (kind, points) in [
            ("walk", state.get("walk_to")),
            ("search", state["combat"].get("search_route")),
            ("approach", state["combat"].get("approach_route")),
        ] {
            let Some(points) = points else { continue };
            let points: Vec<[f32; 3]> = serde_json::from_value(points.clone()).unwrap();
            for pair in points.windows(2) {
                for world in [&map, &fallen] {
                    assert!(
                        walk_segment(world.arena(), pair[0], pair[1]),
                        "{} {kind} segment {:?} -> {:?} crosses collision (shutdown {})",
                        state["name"],
                        pair[0],
                        pair[1],
                        world.m03_geometry().unwrap().mast_shutdown
                    );
                }
                checked += 1;
            }
        }
    }
    assert!(checked > 50, "tour lost its ordinary walking route");
    // The two erroneous hut shortcuts caught in rendered runs stay refused.
    for (from, to) in [
        ([-20.0, 0.0, -3.0], [-20.0, 0.0, 5.5]),
        ([-20.0, 0.0, 6.0], [-17.0, 0.0, 8.0]),
    ] {
        assert!(!walk_segment(map.arena(), from, to));
    }
}
