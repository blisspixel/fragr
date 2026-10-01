//! Declared ordinary input routes, separate from combat drift and real tram riding.
use crate::maps::{AuthoredSource, RuntimeMap};
use crate::movement::{integrate, Arena, MoveState};
use crate::protocol::MissionId;
fn walk(arena: &Arena, from: [f32; 3], to: [f32; 3]) -> bool {
    let mut b = MoveState {
        x: from[0],
        y: from[1],
        z: from[2],
        vx: 0.0,
        vz: 0.0,
        vy: 0.0,
        yaw: 0.0,
    };
    for _ in 0..600 {
        let dx = to[0] - b.x;
        let dz = to[2] - b.z;
        let d = dx.hypot(dz);
        if d < 0.2 && (b.y - to[1]).abs() < 0.03 {
            return true;
        }
        let speed = 4.0_f32.min(d / 0.05);
        b.vx = dx / d.max(0.001) * speed;
        b.vz = dz / d.max(0.001) * speed;
        b = integrate(b, false, 0.05, arena);
    }
    false
}
fn tour() -> serde_json::Value {
    let path =
        std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../client/qa/m05-rooftops.json");
    serde_json::from_slice(&std::fs::read(path).unwrap()).unwrap()
}
#[test]
fn authored_m05_tour_walks_both_freight_worlds() {
    let closed = RuntimeMap::Authored(
        AuthoredSource::Mission(MissionId::NoForwardingAddress)
            .load()
            .unwrap(),
    );
    let opened = closed.prepared_m05_world().unwrap();
    let mut count = 0;
    for state in tour()["states"].as_array().unwrap() {
        for (kind, points) in [
            ("walk", state.get("walk_to")),
            ("approach", state["combat"].get("approach_route")),
            ("search", state["combat"].get("search_route")),
        ] {
            let Some(points) = points else {
                continue;
            };
            let points: Vec<[f32; 3]> = serde_json::from_value(points.clone()).unwrap();
            for p in points.windows(2) {
                for world in [&closed, &opened] {
                    if !world.m05_geometry().unwrap().freight_open && p.iter().any(|p| p[2] > 33.0)
                    {
                        continue;
                    }
                    assert!(
                        walk(world.arena(), p[0], p[1]),
                        "{} {kind} {:?}->{:?} blocked (freight {})",
                        state["name"],
                        p[0],
                        p[1],
                        world.m05_geometry().unwrap().freight_open
                    );
                }
                count += 1;
            }
        }
    }
    assert!(count > 45, "tour lost ordinary route coverage");
    assert!(!walk(closed.arena(), [-5.0, 0.0, 32.0], [-5.0, 0.0, 35.0]));
    assert!(walk(opened.arena(), [-5.0, 0.0, 32.0], [-5.0, 0.0, 35.0]));
    assert!(
        !walk(opened.arena(), [-8.0, 4.0, -25.0], [8.0, 4.0, -25.0]),
        "unsupported roof shortcut cannot replace plank bridge"
    );
    for world in [&closed, &opened] {
        let detail = world
            .presentation_ref()
            .unwrap()
            .decorations
            .iter()
            .find(|d| d.kind == crate::protocol::MapDecorationKind::M05TramService)
            .unwrap();
        let target = detail.point(&world.arena().solids[detail.solid]);
        assert!(walk(world.arena(), [-6.0, 0.0, -12.0], [-8.0, 0.0, -11.5]));
        assert!(
            crate::combat::line_of_sight([-8.0, 1.65, -11.5], target, &world.arena().solids,),
            "ordinary service-bay approach must see the registered secret clue"
        );
    }
}
#[test]
fn authored_m05_tour_requires_all_guards_and_three_secret_locations() {
    let map: serde_json::Value =
        serde_json::from_slice(include_bytes!("../../maps/m05_no_forwarding_address.json"))
            .unwrap();
    let tour = tour();
    let actual: std::collections::BTreeSet<_> = map["encounters"]
        .as_array()
        .unwrap()
        .iter()
        .flat_map(|g| g["enemies"].as_array().unwrap())
        .map(|e| e["id"].as_str().unwrap())
        .collect();
    let required: std::collections::BTreeSet<_> = tour["states"]
        .as_array()
        .unwrap()
        .iter()
        .filter_map(|s| s["combat"]["required"].as_array())
        .flatten()
        .map(|e| e.as_str().unwrap())
        .collect();
    assert_eq!(actual.len(), 21);
    assert_eq!(actual, required);
    for name in [
        "tank_armor_secret",
        "service_pit_secret",
        "market_return_secret",
    ] {
        assert!(tour["states"]
            .as_array()
            .unwrap()
            .iter()
            .any(|s| s["name"] == name));
    }
}
