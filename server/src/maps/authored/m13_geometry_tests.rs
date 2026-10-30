//! Foundry layout: a closed hall, a walked maintenance flank and the
//! sightlines each approach to the ladle galleries is meant to offer.
use super::*;
use crate::combat::line_of_sight;
use crate::movement::EYE_HEIGHT;
use crate::navigation::{NavigationGoal, Navigator, RouteStatus, SEARCH_LIMIT};
use crate::protocol::{Action, MissionObjectiveAction, Role};
use crate::sim::{GameState, PLAYER_FLOOR_Y};

const SOURCE: &[u8] = include_bytes!("../../../maps/m13-weight-of-permission.json");

fn eye(feet: [f32; 3]) -> [f32; 3] {
    [feet[0], feet[1] + EYE_HEIGHT, feet[2]]
}

/// Rooms a body can occupy: entrance, service corridor, maintenance ring,
/// machine and freight hall, and the ladle hall under its higher roof.
const ROOMS: [([f32; 2], [f32; 2]); 5] = [
    ([-7.6, -53.5], [7.6, -39.4]),
    ([-39.5, -43.5], [-8.0, -39.4]),
    ([-39.5, -39.0], [-29.4, 27.0]),
    ([-29.0, -39.0], [39.5, 27.0]),
    ([-39.5, 27.0], [39.5, 53.5]),
];

#[test]
fn m13_foundry_reads_closed_overhead_and_through_every_clerestory() {
    let map = AuthoredMap::read(SOURCE).unwrap();
    let solids = &map.arena.solids;
    let mut sampled = 0;
    for (min, max) in ROOMS {
        let mut x = min[0] + 0.75;
        while x < max[0] {
            let mut z = min[1] + 0.75;
            while z < max[1] {
                // The freight lift climbs through its open shaft into daylight.
                let shaft = x.abs() < 5.25 && z > 46.75;
                if !shaft {
                    for floor in [0.3, 3.3] {
                        if standing(&map.arena, [x, floor, z]) {
                            assert!(
                                !line_of_sight(eye([x, floor, z]), [x, 40.0, z], solids),
                                "open roof above {x},{floor},{z}"
                            );
                            sampled += 1;
                        }
                    }
                }
                z += 1.5;
            }
            x += 1.5;
        }
    }
    assert!(sampled > 1500, "only {sampled} standing samples");
    // Clerestories: the step from hall roof to ladle roof, the ring's low
    // roof, the entrance roof and the ladle hall's raised side walls.
    for (from, to) in [
        ([0.0, 8.5, 20.0], [0.0, 12.5, 30.0]),
        ([-20.0, 12.5, 40.0], [-20.0, 12.5, 20.0]),
        ([-20.0, 7.0, 0.0], [-36.0, 7.0, 0.0]),
        ([0.0, 7.0, -30.0], [0.0, 7.0, -48.0]),
        ([20.0, 12.0, 40.0], [57.0, 12.0, 40.0]),
        ([-20.0, 12.0, 40.0], [-57.0, 12.0, 40.0]),
        ([-36.0, 8.0, 40.0], [-36.0, 8.0, 20.0]),
    ] {
        assert!(!line_of_sight(from, to, solids), "clerestory gap {from:?}");
    }
}

#[test]
fn m13_empty_yards_are_sealed_and_every_fact_stock_and_defender_routes_both_ways() {
    let map = AuthoredMap::read(SOURCE).unwrap();
    let entry = map.spawns[0].feet;
    let nav = &map.navigation;
    // The old open yards beside the entrance are no longer playable margin.
    for void in [[20.0, 0.3, -46.0], [-20.0, 0.3, -49.0], [35.0, 0.3, -50.0]] {
        assert_ne!(
            nav.route(entry, void, SEARCH_LIMIT).status,
            RouteStatus::Complete,
            "sealed yard {void:?} is reachable"
        );
    }
    let g = map.m13.as_ref().unwrap().geometry.clone().unwrap();
    let mut count = 0;
    for feet in g
        .objectives
        .iter()
        .filter_map(|o| match o.action {
            MissionObjectiveAction::Arrival { feet, .. } => Some(feet),
            MissionObjectiveAction::Shoot { approach, .. } => Some(approach),
            _ => None,
        })
        .chain([g.release.approach, g.departure.approach])
        .chain(g.workers.iter().copied())
        .chain(g.worker_destinations.iter().copied())
        .chain(map.supplies.iter().map(|p| [p.x, p.floor, p.z]))
        .chain(map.landmarks.iter().map(|l| l.feet))
        .chain(
            map.encounters
                .iter()
                .flat_map(|e| e.enemies.iter().map(|a| a.feet))
                .filter(|feet| standing(&map.arena, *feet)),
        )
    {
        for (from, to) in [(entry, feet), (feet, entry)] {
            assert_eq!(
                nav.route(from, to, SEARCH_LIMIT).status,
                RouteStatus::Complete,
                "unreachable {from:?} to {to:?}"
            );
            count += 1;
        }
    }
    assert!(count >= 120, "{count} routes");
}

#[test]
fn m13_maintenance_flank_and_front_stairs_form_one_walked_loop() {
    let map = AuthoredMap::read(SOURCE).unwrap();
    // Geometry only: no defenders, mission or foundry gates in the way.
    let mut unpopulated = map.as_ref().clone();
    unpopulated.encounters.clear();
    unpopulated.m13 = None;
    let unpopulated = Arc::new(unpopulated);
    let entry = map.spawns[0].feet;
    // Service door, corridor, ring, walled stairwell, landing, west gallery,
    // front bridge, west stair down, machine hall and back to the entrance.
    walk(
        &unpopulated,
        entry,
        &[
            [-5.0, 0.3, -41.7],
            [-20.0, 0.3, -41.5],
            [-34.0, 0.3, -38.0],
            [-34.0, 0.3, -12.0],
            [-34.0, 0.3, 25.0],
            [-37.75, 0.3, 27.5],
            [-37.75, 3.3, 41.75],
            [-28.0, 3.3, 41.75],
            [-23.5, 3.3, 41.75],
            [-23.5, 3.3, 29.5],
            [-23.5, 0.3, 15.0],
            [-20.0, 0.3, -8.0],
            [0.0, 0.3, -35.0],
            entry,
        ],
    );
    // And the loop in reverse: up the front stairs, out over the landing.
    walk(
        &unpopulated,
        [-23.5, 0.3, 15.0],
        &[
            [-23.5, 3.3, 29.5],
            [-23.5, 3.3, 41.75],
            [-37.75, 3.3, 41.75],
            [-37.75, 0.3, 27.5],
            [-34.0, 0.3, -38.0],
            [-12.0, 0.3, -41.5],
            entry,
        ],
    );
}

#[test]
fn m13_sightlines_separate_the_exposed_front_from_the_covered_flank() {
    let map = AuthoredMap::read(SOURCE).unwrap();
    let solids = &map.arena.solids;
    let marksman = eye([16.0, 3.3, 29.5]);
    let heavy = eye([-15.0, 3.3, 49.0]);
    // The front stair top duels the gallery marksman across the ladle.
    assert!(line_of_sight(eye([-23.5, 3.3, 29.5]), marksman, solids));
    // The stairwell is walled: no climbing body is visible from the
    // marksman's bridge or from the floor of the ladle hall.
    for step in 0..12 {
        let z = 28.5 + step as f32;
        let feet = [-37.75, 0.55 + 0.25 * step as f32, z];
        assert!(!line_of_sight(marksman, eye(feet), solids), "stair {step}");
        assert!(!line_of_sight(eye([-20.0, 0.3, 36.0]), eye(feet), solids));
    }
    // The landing pays off: the heavy on the back bridge is in view from
    // behind the front defenders, at short range.
    let landing = eye([-30.0, 3.3, 41.75]);
    assert!(line_of_sight(landing, heavy, solids));
    assert!(line_of_sight(landing, eye([-23.5, 3.3, 35.0]), solids));
    // The service corridor is hidden from the foundry edge.
    assert!(!line_of_sight(
        eye([0.0, 0.3, -32.0]),
        eye([-20.0, 0.3, -41.5]),
        solids
    ));
    // The centre press has a real window between bolster and ram; its ram
    // and the lathe headstock block what they draw.
    assert!(line_of_sight([0.0, 1.9, -8.0], [0.0, 1.9, 3.0], solids));
    assert!(!line_of_sight([0.0, 4.0, -8.0], [0.0, 4.0, 3.0], solids));
    assert!(line_of_sight(
        [-28.5, 2.2, -16.5],
        [-20.0, 2.2, -16.5],
        solids
    ));
    assert!(!line_of_sight(
        [-28.5, 4.2, -16.5],
        [-20.0, 4.2, -16.5],
        solids
    ));
    assert!(!line_of_sight(
        [-14.0, 1.6, -13.5],
        [-4.0, 1.6, -13.5],
        solids
    ));
    // The lathe bed is waist cover a shot clears; its rear guard is not.
    assert!(line_of_sight([-8.5, 1.6, -9.0], [-8.5, 1.6, -14.5], solids));
    assert!(!line_of_sight(
        [-8.5, 1.6, -9.0],
        [-8.5, 1.6, -18.0],
        solids
    ));
}

fn walk(map: &Arc<AuthoredMap>, from: [f32; 3], destinations: &[[f32; 3]]) {
    let mut state = GameState::with_authored_map(map.clone());
    state.config.time_limit_ticks = None;
    state.config.boss_spawn_ticks = None;
    state.config.compliance_ping_ticks = None;
    let id = uuid::Uuid::from_u128(1313);
    state.add_player(id, "Foundry route".into(), Role::Human);
    state.start_round();
    state.players[0].x = from[0];
    state.players[0].y = from[1] + PLAYER_FLOOR_Y;
    state.players[0].z = from[2];
    let mut navigator = Navigator::default();
    for destination in destinations {
        let mut arrived = false;
        for _ in 0..2400 {
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
            assert!(!action.jump, "foundry route requires ordinary walking");
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
                "ordinary body entered a foundry solid"
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
