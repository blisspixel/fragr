//! The Forever Office command galleries: raised decks over a working floor,
//! two ordinary stairs, the outer service stair from the assembly hall and the
//! bulkhead the core override opens onto the outer court stair.
use super::*;
use crate::combat::line_of_sight;
use crate::maps::RuntimeMap;
use crate::mission::m09_route_segment_valid as walkable;
use crate::movement::{GRAVITY, JUMP_SPEED, STEP_UP};
use crate::navigation::{RouteStatus, SEARCH_LIMIT};

const SOURCE: &str = include_str!("../../../maps/m17-peace-without-interruption.json");
const DECK: f32 = 3.0;

fn worlds() -> (RuntimeMap, RuntimeMap) {
    let map = AuthoredMap::read(SOURCE.as_bytes()).unwrap();
    let sealed = RuntimeMap::Authored(map);
    let unsealed = sealed.prepared_m17_world(1).unwrap();
    (sealed, unsealed)
}

fn walk(arena: &Arena, route: &[[f32; 3]]) -> bool {
    route
        .windows(2)
        .all(|pair| walkable(arena, pair[0], pair[1]))
}

fn reversed(route: &[[f32; 3]]) -> Vec<[f32; 3]> {
    route.iter().rev().copied().collect()
}

fn length(points: &[[f32; 3]]) -> f32 {
    points
        .windows(2)
        .map(|p| {
            let d: [f32; 3] = std::array::from_fn(|i| p[1][i] - p[0][i]);
            d.iter().map(|v| v * v).sum::<f32>().sqrt()
        })
        .sum()
}

/// The exposed direct stair rises in the open toward the bulkhead.
const EXPOSED: [[f32; 3]; 2] = [[-18.75, 0.0, 7.0], [-18.75, DECK, 15.0]];
/// The sheltered stair climbs inside its screen wall to the gallery's west end.
const SHELTERED: [[f32; 3]; 2] = [[-32.75, 0.0, 7.0], [-32.75, DECK, 15.0]];
/// From the assembly hall through the service door, up the steel stair, along
/// the walkway and over the threshold onto the east gallery.
const SERVICE: [[f32; 3]; 7] = [
    [-14.5, 0.0, -4.0],
    [-14.5, 0.0, 1.1],
    [-13.6, 0.0, 1.1],
    [-6.0, DECK, 1.1],
    [-6.0, DECK, 3.1],
    [-10.0, DECK, 3.1],
    [-10.0, DECK, 8.0],
];
/// From the north gallery through the opened bulkhead and down the court stair.
const COURT: [[f32; 3]; 3] = [
    [-18.25, DECK, 16.0],
    [-18.25, DECK, 20.5],
    [-18.25, 0.0, 27.4],
];

#[test]
fn m17_command_galleries_are_supported_decks_over_a_working_floor() {
    let (sealed, unsealed) = worlds();
    for world in [&sealed, &unsealed] {
        let arena = world.arena();
        for feet in [
            [-30.0, DECK, 16.0],
            [-24.0, DECK, 15.4],
            [-14.0, DECK, 16.5],
            [-9.5, DECK, 10.5],
            [-10.0, DECK, 5.0],
            [-10.0, DECK, 3.1],
            [-6.0, DECK, 2.0],
        ] {
            assert!(standing(arena, feet), "unsupported gallery feet {feet:?}");
            assert_eq!(arena.support_height(feet[0], feet[2], DECK + 0.1), DECK);
        }
        // The floor keeps real circulation under both decks and out through
        // the lintel to the flank court.
        for feet in [[-24.0, 0.0, 16.0], [-10.0, 0.0, 10.0], [-23.0, 0.0, 19.0]] {
            assert!(
                standing(arena, feet),
                "no headroom under the gallery {feet:?}"
            );
        }
        assert!(walk(
            arena,
            &[
                [-25.0, 0.0, 5.0],
                [-21.5, 0.0, 8.0],
                [-21.5, 0.0, 16.5],
                [-23.0, 0.0, 22.0],
            ]
        ));
        assert!(
            walk(arena, &[[-10.0, 0.0, 7.0], [-10.0, 0.0, 13.0]]),
            "the floor under the east gallery stays walkable"
        );
        // The console is on the deck, beyond reach from the floor beneath it.
        let g = world.m17_geometry().unwrap();
        assert!(g.core_override.approach[1] >= DECK - f32::EPSILON);
        let console = g
            .core_override
            .point(world.presentation_ref().unwrap(), &arena.solids)
            .unwrap();
        assert!(console[1] > DECK, "the console stands on the gallery");
        // In front of the rail it is out of reach; under the deck it is out of sight.
        let front = [console[0], crate::movement::EYE_HEIGHT, 13.5];
        let reach: f32 = (0..3)
            .map(|i| (console[i] - front[i]).powi(2))
            .sum::<f32>()
            .sqrt();
        assert!(reach > crate::protocol::USE_DISTANCE + 0.5);
        let under = [console[0], crate::movement::EYE_HEIGHT, 16.0];
        assert!(!line_of_sight(under, console, &arena.solids));
    }
}

#[test]
fn m17_both_gallery_stairs_and_the_service_stair_walk_up_and_down() {
    let (sealed, unsealed) = worlds();
    for world in [&sealed, &unsealed] {
        let arena = world.arena();
        for (name, route) in [
            ("exposed", EXPOSED.to_vec()),
            ("sheltered", SHELTERED.to_vec()),
            ("service", SERVICE.to_vec()),
        ] {
            assert!(walk(arena, &route), "{name} stair cannot be climbed");
            assert!(
                walk(arena, &reversed(&route)),
                "{name} stair cannot be descended"
            );
        }
        // Each step is an ordinary step, not a ledge that needs a jump.
        for x in [-18.75, -32.75] {
            let mut previous = 0.0;
            for i in 0..=16 {
                let z = 7.8 + i as f32 * 0.4;
                let top = arena.support_height(x, z, DECK + 0.1);
                assert!(top - previous <= STEP_UP / 2.0, "stair riser at {x}, {z}");
                previous = top;
            }
            assert_eq!(previous, DECK);
        }
        // Navigation (the bots' and controllers' route) agrees with the walk.
        for (from, to) in [
            (EXPOSED[0], EXPOSED[1]),
            (SHELTERED[0], SHELTERED[1]),
            (SERVICE[0], SERVICE[6]),
            (SERVICE[6], SERVICE[0]),
        ] {
            assert_eq!(
                world.navigation().route(from, to, SEARCH_LIMIT).status,
                RouteStatus::Complete,
                "navigation misses {from:?} -> {to:?}"
            );
        }
    }
}

#[test]
fn m17_the_core_override_opens_the_bulkhead_and_shortens_the_way_to_the_core() {
    let (sealed, unsealed) = worlds();
    assert!(
        !walkable(sealed.arena(), COURT[0], COURT[1]),
        "the bulkhead is shut before the override"
    );
    assert!(walk(unsealed.arena(), &COURT));
    assert!(walk(unsealed.arena(), &reversed(&COURT)));
    // In the sealed world the court stair is a dead end below a shut door.
    assert!(walk(
        sealed.arena(),
        &[[-18.25, 0.0, 27.4], [-18.25, DECK, 20.7]]
    ));
    let g = unsealed.m17_geometry().unwrap();
    let from = g.core_override.approach;
    let to = g.voss_rostrum.approach;
    let before = sealed.navigation().route(from, to, SEARCH_LIMIT);
    let after = unsealed.navigation().route(from, to, SEARCH_LIMIT);
    assert_eq!(before.status, RouteStatus::Complete);
    assert_eq!(after.status, RouteStatus::Complete);
    assert!(
        length(&after.points) + 8.0 < length(&before.points),
        "opened routes must shorten the way down: {} vs {}",
        length(&after.points),
        length(&before.points)
    );
}

#[test]
fn m17_cross_floor_sightlines_and_rail_cover() {
    let (sealed, _) = worlds();
    let solids = &sealed.arena().solids;
    let floor_eye = [-24.0, 1.6, 7.0];
    // A fighter standing at the north rail shows head and chest to the floor;
    // crouched behind it the rail breaks the line.
    assert!(line_of_sight(floor_eye, [-24.0, DECK + 1.3, 14.8], solids));
    assert!(!line_of_sight(floor_eye, [-24.0, DECK + 1.0, 14.8], solids));
    // A fighter standing back from the rail is out of the floor's sight.
    assert!(!line_of_sight(floor_eye, [-24.0, DECK + 1.3, 17.0], solids));
    // The Enforcer's post at the north rail commands the exposed stair and the
    // floor, not the sheltered stair inside its screen.
    let post = [-15.5, DECK + 1.6, 14.9];
    assert!(line_of_sight(post, [-18.75, 1.6 + 1.3, 11.0], solids));
    assert!(line_of_sight(post, [-25.0, 1.3, 7.0], solids));
    assert!(!line_of_sight(post, [-32.75, 1.6 + 1.3, 11.0], solids));
    // The east gallery watches the service stair's arrival over the threshold.
    assert!(line_of_sight(
        [-9.5, DECK + 1.6, 10.5],
        [-10.0, DECK + 1.3, 4.0],
        solids
    ));
    // The floor's desks and plotting table are real cover from the gallery.
    assert!(!line_of_sight(post, [-26.0, 0.5, 9.0], solids));
    // The command block's walls keep gallery height from reading other rooms.
    for (from, to) in [
        ([-30.0, DECK + 1.6, 16.0], [-30.0, 1.6, -8.0]),
        ([-10.0, DECK + 1.6, 3.1], [-8.0, 1.6, -10.0]),
        ([-6.0, DECK + 1.6, 2.0], [0.0, 1.6, 9.0]),
        ([-24.0, DECK + 1.6, 16.0], [-24.0, 1.6, 30.0]),
    ] {
        assert!(!line_of_sight(from, to, solids), "{from:?} sees {to:?}");
    }
}

#[test]
fn m17_gallery_height_cannot_climb_out_of_the_command_block() {
    let (sealed, unsealed) = worlds();
    let reach = JUMP_SPEED * JUMP_SPEED / (2.0 * GRAVITY);
    for world in [&sealed, &unsealed] {
        let arena = world.arena();
        // The highest standing surface inside the block is the rail top.
        let rail = arena.support_height(-24.0, 14.1, 6.0);
        assert!((rail - (DECK + 1.0)).abs() < 1e-4);
        let peak = rail + reach + crate::movement::BODY_HEIGHT;
        // Every wall around the decks, stairs and service landing rises past it.
        for (x, z) in [
            (-34.5, 10.0),
            (-30.0, 18.5),
            (-12.0, 18.5),
            (-6.5, 12.0),
            (-16.0, 5.0),
            (-6.5, 5.0),
            (-4.0, 2.0),
            (-8.0, -1.0),
            (-17.0, 0.0),
            (-19.0, 3.0),
            (-23.0, 19.0),
        ] {
            assert!(
                arena.blocked_body_at(x, z, peak - 0.1, peak),
                "a jump from the rail tops the wall at {x}, {z}"
            );
        }
    }
}

#[test]
fn m17_solids_never_overlap_so_no_face_fights_another() {
    let (sealed, unsealed) = worlds();
    for world in [&sealed, &unsealed] {
        let solids = &world.arena().solids;
        let mut overlaps = Vec::new();
        for (i, a) in solids.iter().enumerate() {
            for (j, b) in solids.iter().enumerate().skip(i + 1) {
                let x = a.max_x.min(b.max_x) - a.min_x.max(b.min_x);
                let y = a.top.min(b.top) - a.bottom.max(b.bottom);
                let z = a.max_z.min(b.max_z) - a.min_z.max(b.min_z);
                if x > 1e-4 && y > 1e-4 && z > 1e-4 {
                    overlaps.push((i, j));
                }
            }
        }
        assert!(overlaps.is_empty(), "overlapping solids: {overlaps:?}");
    }
}
