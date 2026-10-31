use super::*;
use crate::movement::STEP_UP;
use crate::sim::MapKind;

const KIND: MapKind = MapKind::ComplianceYard;

/// A plan point (metres on the drawn grid) as built.
fn at(p: [f32; 3]) -> [f32; 3] {
    [p[0] * SCALE, p[1], p[2] * SCALE]
}

/// A standing spot in every room and on every raised floor, used as route
/// ends: (name, feet).
const SPOTS: [(&str, [f32; 3]); 13] = [
    ("records", [-24.0, 0.0, -23.5]),
    ("inspection", [2.0, 0.0, -20.0]),
    ("gantry", [-2.0, GANTRY_TOP, -33.0]),
    ("lockup", [24.5, 0.0, -31.0]),
    ("intake", [-31.0, 0.0, 1.5]),
    ("court", [0.0, 0.0, 0.0]),
    ("table", [-5.5, TABLE_TOP, -1.5]),
    ("relay", [26.0, 0.0, 3.0]),
    ("weighbridge", [-30.0, 0.0, 31.0]),
    ("weighbridge_deck", [-22.0, PLATFORM_TOP, 25.0]),
    ("offices", [2.0, 0.0, 30.0]),
    ("dock", [18.0, 0.0, 30.0]),
    ("dock_platform", [31.0, PLATFORM_TOP, 27.0]),
];

fn room_at(x: f32, z: f32) -> &'static str {
    let (x, z) = (x / SCALE, z / SCALE);
    ROOMS
        .iter()
        .find(|(_, [x0, z0, x1, z1])| x > *x0 && x < *x1 && z > *z0 && z < *z1)
        .map_or("corridor", |(name, _)| *name)
}

#[test]
fn yard_validates_reaches_everything_and_presents_every_solid() {
    assert!(
        crate::maps::validate(KIND).is_empty(),
        "{:?}",
        crate::maps::validate(KIND)
    );
    let arena = crate::maps::arena(KIND);
    crate::protocol::validate_map_presentation(Some(presentation()), &arena.solids).unwrap();
    assert!(crate::maps::ledge_traps(KIND).is_empty());
    let reach = crate::maps::Reach::from_origin(KIND);
    for (name, spot) in SPOTS {
        let [x, floor, z] = at(spot);
        assert!(
            !arena.blocked_at(x, z, floor + STEP_UP),
            "{name} is blocked"
        );
        assert_eq!(
            reach.floor_near(x, z, floor),
            Some(floor),
            "{name} is not a reached floor"
        );
    }
    // The gantry's deck is out of a jump from the hall floor and the sill
    // out of a jump from either side, so both are reached only as built.
    const { assert!(GANTRY_TOP > STEP_UP + 1.3 && SILL_TOP > STEP_UP + 1.3) };
}

#[test]
fn no_sightline_runs_longer_than_the_rail_reach() {
    // The old block's aligned doors gave six lines of 110 m, wall to wall
    // through three rooms and both corridors. The small-map rule sheet allows
    // nothing past 60 m.
    let (length, eye, dir) = crate::maps::longest_sightline(KIND, |_| true);
    eprintln!("compliance yard longest sightline {length:.1} m from {eye:?} along {dir:?}");
    assert!(length < 60.0, "{length} m from {eye:?} along {dir:?}");
    // Inside the block the longest line is the Relay lane into the Dock.
    let (inside, eye, dir) = crate::maps::longest_sightline(KIND, |[x, _, z]| {
        x.abs() < BLOCK * SCALE && z.abs() < BLOCK * SCALE
    });
    eprintln!(
        "compliance yard longest line inside the block {inside:.1} m from {eye:?} along {dir:?}"
    );
    assert!(inside < 50.0, "{inside} m from {eye:?} along {dir:?}");
    // The corridor is a chicane: no line runs the length of a side.
    let (corridor, eye, dir) = crate::maps::longest_sightline(KIND, |[x, _, z]| {
        x.abs() > BLOCK * SCALE + 1.0 || z.abs() > BLOCK * SCALE + 1.0
    });
    eprintln!("compliance yard longest corridor line {corridor:.1} m from {eye:?} along {dir:?}");
    assert!(corridor < 45.0, "{corridor} m from {eye:?} along {dir:?}");
}

#[test]
fn the_gantry_sees_into_the_court_over_the_sill_and_the_court_floor_does_not_see_the_hall() {
    let solids = &crate::maps::arena(KIND).solids;
    let los = |a: [f32; 3], b: [f32; 3]| crate::combat::line_of_sight(a, b, solids);
    let gantry_eye = at([-2.0, GANTRY_TOP + 1.6, -32.0]);
    assert!(
        los(gantry_eye, at([-1.0, 1.0, 0.0])),
        "gantry sees the court's middle"
    );
    assert!(
        los(at([-1.0, 1.6, 0.0]), at([-2.0, GANTRY_TOP + 1.2, -32.0])),
        "and is seen back"
    );
    assert!(
        !los(at([0.0, 1.6, -4.0]), at([2.0, 1.2, -20.0])),
        "the court floor does not see through the sill into the hall"
    );
}

#[test]
fn every_room_has_exits_to_different_places_and_the_court_has_four() {
    let arena = crate::maps::arena(KIND);
    for (name, rect) in ROOMS {
        let [x0, z0, x1, z1] = rect.map(|v| v * SCALE);
        let mut destinations = std::collections::BTreeSet::new();
        let mut doorways = 0;
        // Walk each wall line and find clear standing gaps; the destination
        // is whatever lies a body and a half beyond.
        for (fixed, along_x, outward) in [
            (z0, true, -1.0f32),
            (z1, true, 1.0),
            (x0, false, -1.0),
            (x1, false, 1.0),
        ] {
            let (lo, hi) = if along_x { (x0, x1) } else { (z0, z1) };
            let mut open = false;
            let mut t = lo + 0.25;
            while t < hi {
                let (x, z) = if along_x { (t, fixed) } else { (fixed, t) };
                let clear = !arena.blocked_at(x, z, STEP_UP);
                if clear && !open {
                    doorways += 1;
                    let (bx, bz) = if along_x {
                        (x + 1.5, fixed + outward * 1.5)
                    } else {
                        (fixed + outward * 1.5, z + 1.5)
                    };
                    destinations.insert(room_at(bx, bz));
                }
                open = clear;
                t += 0.25;
            }
        }
        destinations.remove(name);
        eprintln!("compliance yard {name}: {doorways} doorways to {destinations:?}");
        let want = if name == "court" { 4 } else { 2 };
        assert!(destinations.len() >= want, "{name}: {destinations:?}");
    }
}

#[test]
fn bots_walk_every_neighbouring_room_both_ways_and_reach_every_pad() {
    let spot = |name: &str| at(SPOTS.iter().find(|(n, _)| *n == name).unwrap().1);
    let pairs = [
        ("records", "inspection"),
        ("records", "intake"),
        ("inspection", "gantry"),
        ("inspection", "court"),
        ("inspection", "lockup"),
        ("lockup", "relay"),
        ("intake", "court"),
        ("intake", "weighbridge"),
        ("court", "table"),
        ("court", "relay"),
        ("court", "offices"),
        ("relay", "dock_platform"),
        ("weighbridge", "weighbridge_deck"),
        ("weighbridge", "offices"),
        ("offices", "dock"),
        ("dock", "dock_platform"),
    ];
    let mut longest = 0;
    for (a, b) in pairs {
        for (from, to) in [(spot(a), spot(b)), (spot(b), spot(a))] {
            let ticks = crate::maps::walk_route(KIND, from, to, 900)
                .unwrap_or_else(|| panic!("no walk {from:?} -> {to:?}"));
            longest = longest.max(ticks);
        }
    }
    eprintln!(
        "compliance yard longest neighbour walk {:.1} s",
        longest as f32 / 20.0
    );
    // Corner to corner, the farthest two points: the old 110 m block took
    // 26 s at the arena run; the small-map rule is 25 s.
    // Each corner of the corridor offers three far spots: its turn and the
    // ends of the two legs against the guard post.
    let wall = (BLOCK + 0.3) * SCALE - 0.6;
    let turn = (BLOCK + 0.3 + 3.2) * SCALE - 0.6;
    let far = HALF * SCALE - 0.6;
    let corner = |sx: f32, sz: f32| -> [[f32; 3]; 3] {
        [
            [sx * turn, 0.0, sz * turn],
            [sx * far, 0.0, sz * wall],
            [sx * wall, 0.0, sz * far],
        ]
    };
    let pairs = [
        (corner(-1.0, -1.0), corner(1.0, 1.0)),
        (corner(1.0, -1.0), corner(-1.0, 1.0)),
    ];
    for (from, to) in pairs.iter().flat_map(|(a, b)| {
        a.iter()
            .flat_map(move |from| b.iter().map(move |to| (*from, *to)))
    }) {
        let ticks = crate::maps::walk_route(KIND, from, to, 20 * 60).unwrap_or(9999);
        assert!(
            ticks < 20 * 25,
            "corner to corner {from:?} -> {to:?}: {ticks} ticks"
        );
        eprintln!(
            "compliance yard corner {from:?} -> {to:?}: {:.1} s",
            ticks as f32 / 20.0
        );
    }
    let def = crate::maps::def(KIND);
    for pad in def.pickups.iter().chain(&def.scrap_pads) {
        let ticks = crate::maps::walk_route(KIND, [0.0, 0.0, 0.0], [pad.x, pad.floor, pad.z], 900);
        assert!(ticks.is_some(), "no walk to {}", pad.id);
    }
}

#[test]
fn navigation_builds_within_its_budget() {
    let started = std::time::Instant::now();
    let navigation = crate::navigation::Navigation::shared(crate::maps::arena(KIND).clone())
        .expect("Compliance Yard builds within the navigation budget");
    let (nodes, edges) = navigation.size();
    eprintln!(
        "compliance yard navigation {nodes} nodes, {edges} edges, built in {:.0} ms",
        started.elapsed().as_secs_f64() * 1000.0
    );
}

/// The client's presenter is held to the server's solids through
/// `client/golden/compliance_yard_map_info.json` (`client/scripts/test_yard_water_dressing.gd`).
/// Regenerate with `FRAGR_MAP_INFO_OUT=$PWD/client/golden/compliance_yard_map_info.json cargo test
/// -p fragr-server --lib compliance_yard_write_map_info -- --ignored`.
#[test]
fn compliance_yard_client_golden_is_the_server_map_info() {
    let state = crate::sim::GameState::with_map(MapKind::ComplianceYard, false);
    let wire = serde_json::to_string(&state.map_info()).expect("serialize MapInfo");
    let live: serde_json::Value = serde_json::from_str(&wire).expect("parse MapInfo");
    let golden: serde_json::Value = serde_json::from_str(include_str!(
        "../../../../client/golden/compliance_yard_map_info.json"
    ))
    .expect("parse the client golden");
    assert_eq!(
        live, golden,
        "client/golden/compliance_yard_map_info.json is stale"
    );
}

#[test]
#[ignore = "writes the client golden MapInfo"]
fn compliance_yard_write_map_info() {
    let Ok(path) = std::env::var("FRAGR_MAP_INFO_OUT") else {
        return;
    };
    let state = crate::sim::GameState::with_map(MapKind::ComplianceYard, false);
    let message = serde_json::to_string(&state.map_info()).expect("serialize MapInfo");
    std::fs::write(path, message).expect("write MapInfo");
}
