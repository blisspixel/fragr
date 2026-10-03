//! Ordinary declared port routes. Combat drift and rendered timing need the live tour.
use crate::maps::{AuthoredSource, RuntimeMap};
use crate::movement::{integrate, Arena, MoveState, EYE_HEIGHT};
use crate::protocol::MissionId;
use serde_json::Value;

fn walk(arena: &Arena, from: [f32; 3], to: [f32; 3]) -> bool {
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
        if distance < 0.2 && (body.y - to[1]).abs() < 0.03 {
            return true;
        }
        let speed = 4.0_f32.min(distance / 0.05);
        body.vx = dx / distance.max(0.001) * speed;
        body.vz = dz / distance.max(0.001) * speed;
        body = integrate(body, false, 0.05, arena);
    }
    false
}

fn tour() -> Value {
    let path = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../client/qa/m06_port_of_entry.json");
    serde_json::from_slice(&std::fs::read(path).unwrap()).unwrap()
}

#[test]
fn authored_m06_tour_walks_static_port_stairs_and_flanks() {
    let map = RuntimeMap::Authored(
        AuthoredSource::Mission(MissionId::PortOfEntry)
            .load()
            .unwrap(),
    );
    let mut count = 0;
    for state in tour()["states"].as_array().unwrap() {
        let mut previous_end: Option<[f32; 3]> = None;
        for (kind, points) in [
            ("walk", state.get("walk_to")),
            ("approach", state["combat"].get("approach_route")),
            ("search", state["combat"].get("search_route")),
        ] {
            let Some(points) = points else {
                continue;
            };
            let points: Vec<[f32; 3]> = serde_json::from_value(points.clone()).unwrap();
            if let (Some(from), Some(to)) = (previous_end, points.first()) {
                assert!(
                    walk(map.arena(), from, *to),
                    "{} route handoff {kind} {:?}->{:?} blocked",
                    state["name"],
                    from,
                    to
                );
            }
            for segment in points.windows(2) {
                assert!(
                    walk(map.arena(), segment[0], segment[1]),
                    "{} {kind} {:?}->{:?} blocked",
                    state["name"],
                    segment[0],
                    segment[1]
                );
                count += 1;
            }
            previous_end = points.last().copied();
        }
    }
    assert!(count > 120, "tour lost ordinary route coverage");
    assert!(
        !walk(map.arena(), [0.0, 0.0, 16.0], [-18.5, 3.0, 16.0]),
        "a gallery cannot be reached by walking through its side slab"
    );
    assert!(
        !walk(map.arena(), [-30.0, 0.0, 18.0], [-38.0, 0.0, 18.0]),
        "inhabited room remains physically sealed by pressure glass"
    );
    // The required path reaches customs without entering the optional service fight.
    for segment in [
        [[12.0, 0.0, 3.0], [0.0, 0.0, 3.0]],
        [[0.0, 0.0, 3.0], [0.0, 0.0, 10.0]],
    ] {
        assert!(walk(map.arena(), segment[0], segment[1]));
        assert!(segment
            .iter()
            .all(|p| map.encounters()[6].regions.iter().all(|r| !r.contains(*p))));
    }
}

#[test]
fn authored_m06_tour_covers_all_guards_secrets_and_quiet_entry() {
    let map: Value =
        serde_json::from_slice(include_bytes!("../../maps/m06_port_of_entry.json")).unwrap();
    let tour = tour();
    let actual: std::collections::BTreeSet<_> = map["encounters"]
        .as_array()
        .unwrap()
        .iter()
        .flat_map(|group| group["enemies"].as_array().unwrap())
        .map(|enemy| enemy["id"].as_str().unwrap())
        .collect();
    let required: std::collections::BTreeSet<_> = tour["states"]
        .as_array()
        .unwrap()
        .iter()
        .filter_map(|state| state["combat"]["required"].as_array())
        .flatten()
        .map(|name| name.as_str().unwrap())
        .collect();
    assert_eq!(actual.len(), 21);
    assert_eq!(actual, required);
    assert_eq!(
        map["supplies"]
            .as_array()
            .unwrap()
            .iter()
            .filter(|s| s["secret"] == true)
            .count(),
        3
    );
    let activation: crate::protocol::Region3 =
        serde_json::from_value(map["encounters"][0]["regions"][0].clone()).unwrap();
    let quiet = tour["states"]
        .as_array()
        .unwrap()
        .iter()
        .find(|s| s["name"] == "earth_over_gantry")
        .unwrap();
    let points: Vec<[f32; 3]> = serde_json::from_value(quiet["walk_to"].clone()).unwrap();
    for segment in points.windows(2) {
        for sample in 0..=100 {
            let t = sample as f32 / 100.0;
            let feet = std::array::from_fn(|i| segment[0][i] + (segment[1][i] - segment[0][i]) * t);
            assert!(
                !activation.contains(feet),
                "quiet window route activated the first fight"
            );
        }
    }
    for spawn in map["spawns"].as_array().unwrap() {
        let feet: [f32; 3] = serde_json::from_value(spawn["feet"].clone()).unwrap();
        for supply in map["supplies"].as_array().unwrap() {
            let pickup: [f32; 3] = serde_json::from_value(supply["feet"].clone()).unwrap();
            assert!(
                (feet[0] - pickup[0]).hypot(feet[2] - pickup[2]) > crate::sim::PICKUP_CLAIM_RADIUS,
                "entry may not silently claim {}",
                supply["id"]
            );
        }
    }
}

#[test]
fn authored_m06_rail_lane_and_turret_cover_are_physical() {
    let map = RuntimeMap::Authored(
        AuthoredSource::Mission(MissionId::PortOfEntry)
            .load()
            .unwrap(),
    );
    let solids = &map.arena().solids;
    let rail_eye = [-29.0, EYE_HEIGHT, -11.0];
    let distant = [29.25, EYE_HEIGHT, -11.0];
    assert!((distant[0] - rail_eye[0] - 58.25).abs() < 0.001);
    assert!(crate::combat::line_of_sight(rail_eye, distant, solids));
    let turret = [-18.5, 4.0, 16.0];
    assert!(crate::combat::line_of_sight(
        [4.0, EYE_HEIGHT, 16.0],
        turret,
        solids
    ));
    assert!(
        !crate::combat::line_of_sight([0.0, EYE_HEIGHT, 10.0], turret, solids),
        "charge-cancel cover must block the actual shot ray"
    );
    assert!(crate::combat::line_of_sight(
        [-20.0, 3.0 + EYE_HEIGHT, 16.0],
        turret,
        solids
    ));
}

#[test]
fn authored_m06_port_is_a_closed_pressure_hull() {
    // A pressure port must not show open space through its ceiling or let a
    // player walk out onto the surface. The freight hall's south side, the
    // dock's east side, the north thresholds, the service corridor and the
    // transit vestibule used to open straight onto the airless yard.
    let map = RuntimeMap::Authored(
        AuthoredSource::Mission(MissionId::PortOfEntry)
            .load()
            .unwrap(),
    );
    let arena = map.arena();
    for (inside, outside, place) in [
        ([0.0, 0.0, -20.0], [0.0, 0.0, -36.0], "freight hall south yard"),
        ([-30.0, 0.0, -36.0], [-12.0, 0.0, -36.0], "dock east side"),
        ([30.0, 0.0, 3.0], [30.0, 0.0, 10.0], "loading bay north corner"),
        ([-30.0, 0.0, 22.0], [-30.0, 0.0, 32.0], "service corridor north"),
        ([-13.0, 0.0, 39.0], [-30.0, 0.0, 42.0], "customs north west"),
        ([0.0, 0.0, 42.0], [0.0, 0.0, 47.0], "transit vestibule end"),
        ([5.0, 0.0, 43.0], [20.0, 0.0, 43.0], "transit vestibule side"),
    ] {
        assert!(!walk(arena, inside, outside), "{place} opens onto the surface");
    }
    // Every point the ordinary route stands on has a roof above it.
    let covered = |p: [f32; 3]| {
        arena.solids.iter().any(|s| {
            s.min_x <= p[0]
                && p[0] < s.max_x
                && s.min_z <= p[2]
                && p[2] < s.max_z
                && s.bottom >= p[1] + 2.5
        })
    };
    let mut checked = 0;
    for state in tour()["states"].as_array().unwrap() {
        for key in ["walk_to"] {
            let Some(points) = state.get(key) else {
                continue;
            };
            let points: Vec<[f32; 3]> = serde_json::from_value(points.clone()).unwrap();
            for segment in points.windows(2) {
                for step in 0..=8 {
                    let t = step as f32 / 8.0;
                    let p = [
                        segment[0][0] + (segment[1][0] - segment[0][0]) * t,
                        segment[0][1] + (segment[1][1] - segment[0][1]) * t,
                        segment[0][2] + (segment[1][2] - segment[0][2]) * t,
                    ];
                    assert!(covered(p), "{} passes under open space at {p:?}", state["name"]);
                    checked += 1;
                }
            }
        }
    }
    assert!(checked > 500, "route roof coverage sampled too little");
}
