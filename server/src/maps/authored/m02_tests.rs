use super::*;
use crate::navigation::RouteStatus;
use crate::protocol::EnemyKind;
use serde_json::{json, Value};

fn fixture() -> Value {
    json!({
        "version":1,"map_id":1002,"name":"M02 objective fixture","half_extent":8,
        "ground":"concrete","equipment":"discovery",
        "solids":[
            {"id":"ceiling","min":[-8,3,-8],"max":[8,4,8],"surface":"enamel"},
            {"id":"divider_west","min":[-8,0,-0.5],"max":[-1.5,3,0.5],"surface":"enamel"},
            {"id":"ward_gate","min":[-1.5,0,-0.5],"max":[1.5,3,0.5],"surface":"lift_panel"},
            {"id":"divider_east","min":[1.5,0,-0.5],"max":[8,3,0.5],"surface":"enamel"}
        ],
        "spawns":[{"id":"entry","feet":[0,0,-4],"yaw":0}],
        "landmarks":[{"id":"gallery","feet":[0,0,-3]}],
        "m02":{
            "objectives":[
                {"id":"ward_reached","action":{"kind":"arrival","region":{"min":[-1,0,-5],"max":[1,1,-3]},"feet":[0,0,-4]}},
                {"id":"correction_stopped","after":"ward_reached","action":{"kind":"use",
                 "panel":{"solid":"ceiling","face":"down","center":[0,-3],"size":[0.5,0.5],"kind":"terminal"},
                 "approach":[0,0,-3]}},
                {"id":"party_departed","after":"correction_stopped","action":{"kind":"arrival",
                 "region":{"min":[-1,0,3],"max":[1,1,5]},"feet":[0,0,4]}}
            ],
            "gates":[{"id":"ward_release","solid":"ward_gate","lift":4,"after":"correction_stopped","signals":[
                {"solid":"ward_gate","face":"north","center":[0,0.8],"size":[0.5,0.5],"kind":"gate_locked"},
                {"solid":"divider_west","face":"north","center":[-2.75,0.8],"size":[0.5,0.5],"kind":"gate_locked"}]}]
        }
    })
}

fn read(doc: &Value) -> io::Result<Arc<AuthoredMap>> {
    AuthoredMap::read(serde_json::to_vec(doc).unwrap().as_slice())
}

#[test]
fn bundled_guard_shells_require_a_step_off_every_gallery_spawn() {
    let map = AuthoredMap::read(include_str!("../../../maps/m02-persons-unknown.json").as_bytes())
        .unwrap();
    let shells = map
        .supplies
        .iter()
        .find(|supply| supply.id == "guard_room_shells")
        .unwrap();
    assert_eq!(shells.floor, 3.0);
    for spawn in &map.spawns {
        assert!(
            (spawn.feet[0] - shells.x).hypot(spawn.feet[2] - shells.z)
                > crate::sim::PICKUP_CLAIM_RADIUS + crate::movement::RADIUS,
            "{} starts inside the optional shell pickup reach",
            spawn.id
        );
    }
    assert_eq!(
        map.navigation
            .route(
                map.spawns[0].feet,
                [shells.x, shells.floor, shells.z],
                crate::navigation::SEARCH_LIMIT
            )
            .status,
        RouteStatus::Complete
    );
    // The shells stay on the open gallery path just north of the first guard trigger.
    assert!(shells.x > -3.0 && shells.z > -30.6 && shells.z < -26.0);
}

#[test]
fn gallery_entry_frames_latch_without_exposing_the_ward_guards() {
    let map = AuthoredMap::read(include_str!("../../../maps/m02-persons-unknown.json").as_bytes())
        .unwrap();
    let spawn = map
        .spawns
        .iter()
        .find(|spawn| spawn.id == "gallery_entry")
        .unwrap();
    let eye = [
        spawn.feet[0],
        spawn.feet[1] + crate::movement::EYE_HEIGHT,
        spawn.feet[2],
    ];
    let solids = &map.arena.solids;
    assert!(
        crate::combat::line_of_sight(eye, [7.55, 1.9, -10.0], solids),
        "the primary standing entry eye must see Latch on the restraint"
    );
    assert!(
        crate::combat::line_of_sight(eye, [7.9, 2.45, -11.0], solids),
        "the primary entry must see the front of the restraint frame"
    );
    let window_eye = [0.0, 3.0 + crate::movement::EYE_HEIGHT, -27.0];
    assert!(crate::combat::line_of_sight(
        window_eye,
        [7.55, 1.9, -10.0],
        solids
    ));
    for spawn in &map.spawns {
        assert_eq!(
            map.navigation
                .route(
                    spawn.feet,
                    [0.0, 3.0, -27.0],
                    crate::navigation::SEARCH_LIMIT
                )
                .status,
            RouteStatus::Complete,
            "{} must be able to reach the unobstructed window view",
            spawn.id
        );
    }
    for id in ["ward_clerk", "ward_sweeper", "machine_clerk"] {
        let guard = map
            .encounters
            .iter()
            .flat_map(|group| &group.enemies)
            .find(|enemy| enemy.id == id)
            .unwrap();
        assert!(
            !crate::combat::line_of_sight(
                eye,
                [guard.feet[0], guard.feet[1] + 1.1, guard.feet[2]],
                solids
            ),
            "{id} must not become an opening-gallery shooting target"
        );
    }
    assert!(
        !crate::combat::line_of_sight(eye, [7.55, 0.5, -10.0], solids),
        "the lower wall must still cover the ward floor"
    );
    let sill = solids
        .iter()
        .find(|solid| solid.min_z == -26.0 && solid.max_z == -25.0 && solid.min_x == -9.0)
        .unwrap();
    assert!(
        sill.top - spawn.feet[1] > crate::movement::STEP_UP + 0.1,
        "the player must not step onto the window sill and bypass the stairs"
    );
    assert_eq!(
        map.navigation
            .route(
                spawn.feet,
                [-12.5, 0.0, -22.0],
                crate::navigation::SEARCH_LIMIT
            )
            .status,
        RouteStatus::Complete,
        "the ordinary service stair and ward route must stay walkable"
    );
}

#[test]
fn floor_officer_uses_the_reachable_upper_mezzanine() {
    let map = AuthoredMap::read(include_str!("../../../maps/m02-persons-unknown.json").as_bytes())
        .unwrap();
    let officer = map
        .encounters
        .iter()
        .find(|encounter| encounter.id == "floor_entry")
        .unwrap()
        .enemies
        .iter()
        .find(|enemy| enemy.id == "floor_officer")
        .unwrap();
    assert_eq!(officer.kind, crate::protocol::EnemyKind::Clerk);
    assert!(
        officer.feet[1] >= 2.5,
        "officer must own the upper sightline"
    );
    assert!((-14.0..=-6.0).contains(&officer.feet[0]));
    assert!((1.0..=14.0).contains(&officer.feet[2]));
    assert_eq!(
        map.arena
            .support_height(officer.feet[0], officer.feet[2], officer.feet[1] + 0.01),
        officer.feet[1]
    );
    assert_eq!(
        map.navigation
            .route(
                [-4.0, 0.0, -5.0],
                officer.feet,
                crate::navigation::SEARCH_LIMIT
            )
            .status,
        RouteStatus::Complete
    );
    assert!(map.navigation.line_of_sight(
        [-4.0, crate::movement::EYE_HEIGHT, -5.0],
        [officer.feet[0], officer.feet[1] + 0.9, officer.feet[2]]
    ));
}

#[test]
fn processing_floor_has_the_accepted_roster_and_both_route_triggers() {
    let map = AuthoredMap::read(include_str!("../../../maps/m02-persons-unknown.json").as_bytes())
        .unwrap();
    let floor = ["floor_entry", "floor_crossfire", "floor_crew"].map(|id| {
        map.encounters
            .iter()
            .find(|encounter| encounter.id == id)
            .unwrap()
    });
    assert_eq!(floor[0].after.as_deref(), Some("ward_guards"));
    assert_eq!(floor[1].after.as_deref(), Some("floor_entry"));
    assert_eq!(floor[2].after.as_deref(), Some("floor_crossfire"));
    assert_eq!(floor.map(|group| group.enemies.len()), [4, 4, 2]);
    let kinds: Vec<_> = floor
        .iter()
        .flat_map(|group| group.enemies.iter().map(|enemy| enemy.kind))
        .collect();
    assert_eq!(
        kinds
            .iter()
            .filter(|&&kind| kind == EnemyKind::Clerk)
            .count(),
        4
    );
    assert_eq!(
        kinds
            .iter()
            .filter(|&&kind| kind == EnemyKind::Sweeper)
            .count(),
        4
    );
    assert_eq!(
        kinds
            .iter()
            .filter(|&&kind| kind == EnemyKind::Crawler)
            .count(),
        2
    );
    assert!(floor[0]
        .regions
        .iter()
        .any(|region| region.contains([5.0, 0.0, -6.0])));
    assert!(floor[1]
        .regions
        .iter()
        .any(|region| region.contains([0.0, 0.0, 5.0])));
    assert!(floor[1]
        .regions
        .iter()
        .any(|region| region.contains([12.0, 0.0, 8.0])));
    assert!(floor[1]
        .regions
        .iter()
        .any(|region| region.contains([-8.0, 2.5, 5.0])));
    assert!(floor[2]
        .regions
        .iter()
        .any(|region| region.contains([0.0, 0.0, 12.0])));
    let dock = map
        .encounters
        .iter()
        .find(|group| group.id == "dock_watch")
        .unwrap();
    assert_eq!(dock.after.as_deref(), Some("floor_crew"));
    assert!(!dock
        .regions
        .iter()
        .any(|region| region.contains([0.0, 0.0, 12.0])));
    assert!(dock
        .regions
        .iter()
        .any(|region| region.contains([0.0, 0.0, 17.0])));
}

#[test]
fn side_ward_is_reachable_but_the_dock_route_stays_on_the_floor() {
    let map = AuthoredMap::read(include_str!("../../../maps/m02-persons-unknown.json").as_bytes())
        .unwrap();
    let opened = map.m02.as_ref().unwrap().world(1).unwrap().1;
    let entry = [0.0, 3.0, -31.0];
    assert_eq!(
        map.navigation
            .route(
                [-16.7, 0.0, -21.9],
                [7.0, 0.0, -11.0],
                crate::navigation::SEARCH_LIMIT
            )
            .status,
        RouteStatus::Complete
    );
    let branch = map
        .landmarks
        .iter()
        .find(|place| place.id == "side_ward")
        .unwrap()
        .feet;
    assert_eq!(
        map.navigation
            .route(entry, branch, crate::navigation::SEARCH_LIMIT)
            .status,
        RouteStatus::Unreachable,
        "the side ward must wait for Latch's release"
    );
    assert_eq!(
        opened
            .route(entry, branch, crate::navigation::SEARCH_LIMIT)
            .status,
        RouteStatus::Complete
    );
    assert_eq!(
        opened
            .route(
                [7.0, 0.0, -11.0],
                [5.0, 0.0, -5.5],
                crate::navigation::SEARCH_LIMIT
            )
            .status,
        RouteStatus::Complete,
        "the floor-entry recovery is reachable after release"
    );
    assert_eq!(
        map.navigation
            .route([-4.0, 0.0, -5.0], branch, crate::navigation::SEARCH_LIMIT)
            .status,
        RouteStatus::Complete
    );
    let dock = map.navigation.route(
        [-4.0, 0.0, -5.0],
        [0.0, 0.0, 21.0],
        crate::navigation::SEARCH_LIMIT,
    );
    assert_eq!(dock.status, RouteStatus::Complete);
    assert!(dock.points.iter().all(|point| point[0] < 15.0));
    assert!(map
        .navigation
        .line_of_sight([18.5, crate::movement::EYE_HEIGHT, 4.0], [23.4, 1.45, 8.8]));
    let side = map
        .encounters
        .iter()
        .find(|encounter| encounter.id == "side_ward_guards")
        .unwrap();
    assert_eq!(side.after.as_deref(), Some("ward_guards"));
    assert_eq!(side.enemies.len(), 2);
    assert!(map
        .encounters
        .iter()
        .filter(|encounter| matches!(encounter.id.as_str(), "floor_crew" | "dock_watch"))
        .all(|encounter| encounter.after.as_deref() != Some("side_ward_guards")));
}

#[test]
fn maintenance_cut_skips_only_the_pack_landing() {
    let map = AuthoredMap::read(include_str!("../../../maps/m02-persons-unknown.json").as_bytes())
        .unwrap();
    let pack = map
        .encounters
        .iter()
        .find(|encounter| encounter.id == "crawler_pack")
        .unwrap();
    let first = [-12.0, 0.0, -27.0];
    let west_turn = [-16.0, 0.0, -26.0];
    let rejoin = [-15.5, 0.0, -22.0];
    let antechamber = [-14.0, 0.0, -21.5];
    let direct = [-12.5, 0.0, -24.5];
    let landing = [-16.0, 1.2, -27.6];
    assert!(pack.regions.iter().any(|region| region.contains(direct)));
    assert!(pack.regions.iter().any(|region| region.contains(landing)));
    assert!(!pack.regions.iter().any(|region| region.contains(first)));
    for (from, to) in [
        (first, west_turn),
        (west_turn, rejoin),
        (rejoin, antechamber),
    ] {
        let route = map
            .navigation
            .route(from, to, crate::navigation::SEARCH_LIMIT);
        assert_eq!(route.status, RouteStatus::Complete, "{from:?} to {to:?}");
        assert!(
            route
                .points
                .iter()
                .all(|point| pack.regions.iter().all(|region| !region.contains(*point))),
            "maintenance cut touched the pack trigger: {:?}",
            route.points
        );
    }
    assert_eq!(
        map.navigation
            .route(first, direct, crate::navigation::SEARCH_LIMIT)
            .status,
        RouteStatus::Complete
    );
}

#[test]
fn pack_stays_dormant_at_the_fork_and_wakes_on_the_direct_lane() {
    let map = AuthoredMap::read(include_str!("../../../maps/m02-persons-unknown.json").as_bytes())
        .unwrap();
    let mut state = crate::sim::GameState::with_authored_map(map);
    let id = uuid::Uuid::from_u128(0x02bc);
    state.add_player(id, "Route probe".into(), crate::protocol::Role::Human);
    assert!(state.acknowledge_m02(id, 1));
    let place = |state: &mut crate::sim::GameState, feet: [f32; 3]| {
        let player = state
            .players
            .iter_mut()
            .find(|player| player.id == id)
            .unwrap();
        player.x = feet[0];
        player.y = feet[1] + crate::sim::PLAYER_FLOOR_Y;
        player.z = feet[2];
        state.update_encounters();
    };
    place(&mut state, [-3.2, 3.0, -31.0]);
    for guard in state
        .players
        .iter_mut()
        .filter(|player| player.name.starts_with("guard_room_clerk_"))
    {
        guard.hp = 0;
    }
    state.update_encounters();
    place(&mut state, [-10.5, 1.0, -29.5]);
    let first = state
        .players
        .iter()
        .find(|player| player.name == "stair_crawler_first")
        .unwrap()
        .id;
    state
        .players
        .iter_mut()
        .find(|player| player.id == first)
        .unwrap()
        .hp = 0;
    state.update_encounters();
    let pack = state
        .players
        .iter()
        .find(|player| player.name == "stair_crawler_pack_a")
        .unwrap()
        .id;
    for feet in [
        [-12.0, 0.0, -27.0],
        [-13.5, 0.0, -26.5],
        [-16.0, 0.0, -26.0],
        [-15.5, 0.0, -24.5],
        [-15.5, 0.0, -22.0],
    ] {
        place(&mut state, feet);
        assert!(
            !state.encounters.is_active_enemy(pack),
            "the pack woke on the maintenance cut at {feet:?}"
        );
    }
    place(&mut state, [-12.5, 0.0, -24.5]);
    assert!(state.encounters.is_active_enemy(pack));
}

#[test]
fn pack_wakes_when_the_west_approach_enters_its_landing() {
    for jump_from_staging in [false, true] {
        let map =
            AuthoredMap::read(include_str!("../../../maps/m02-persons-unknown.json").as_bytes())
                .unwrap();
        let arena = map.arena.clone();
        let mut state = crate::sim::GameState::with_authored_map(map);
        let id = uuid::Uuid::from_u128(0x02bd);
        state.add_player(id, "Landing probe".into(), crate::protocol::Role::Human);
        assert!(state.acknowledge_m02(id, 1));
        let place = |state: &mut crate::sim::GameState, feet: [f32; 3]| {
            let player = state
                .players
                .iter_mut()
                .find(|player| player.id == id)
                .unwrap();
            player.x = feet[0];
            player.y = feet[1] + crate::sim::PLAYER_FLOOR_Y;
            player.z = feet[2];
            state.update_encounters();
        };
        place(&mut state, [-3.2, 3.0, -31.0]);
        for guard in state
            .players
            .iter_mut()
            .filter(|player| player.name.starts_with("guard_room_clerk_"))
        {
            guard.hp = 0;
        }
        state.update_encounters();
        place(&mut state, [-10.5, 1.0, -29.5]);
        let first = state
            .players
            .iter()
            .find(|player| player.name == "stair_crawler_first")
            .unwrap()
            .id;
        state
            .players
            .iter_mut()
            .find(|player| player.id == first)
            .unwrap()
            .hp = 0;
        state.update_encounters();
        let pack = state
            .players
            .iter()
            .find(|player| player.name == "stair_crawler_pack_a")
            .unwrap()
            .id;
        place(&mut state, [-12.0, 0.0, -27.0]);
        place(&mut state, [-16.0, 0.0, -26.0]);
        assert!(!state.encounters.is_active_enemy(pack));
        let mut body = crate::movement::MoveState {
            x: -16.0,
            z: -26.0,
            y: 0.0,
            vx: 0.0,
            vz: -crate::movement::TOP_SPEED,
            vy: 0.0,
            yaw: 0.0,
        };
        for step in 0..8 {
            body = crate::movement::integrate(body, jump_from_staging && step == 0, 0.05, &arena);
            place(&mut state, [body.x, body.y, body.z]);
        }
        assert!(body.z <= -27.5, "body did not reach the pack landing");
        if jump_from_staging {
            assert!(
                body.y > 1.0,
                "the jump did not clear the old trigger height"
            );
        }
        assert!(state.encounters.is_active_enemy(pack));
    }
}

#[test]
fn side_ward_has_a_grounded_north_return_after_release() {
    let map = AuthoredMap::read(include_str!("../../../maps/m02-persons-unknown.json").as_bytes())
        .unwrap();
    let opened = map.m02.as_ref().unwrap().world(1).unwrap().1;
    let floor = [13.0, 0.0, 9.0];
    let side = [16.0, 0.0, 9.0];
    assert_eq!(
        map.navigation
            .route(map.spawns[0].feet, side, crate::navigation::SEARCH_LIMIT)
            .status,
        RouteStatus::Unreachable,
        "the maintenance return must not bypass Latch's release"
    );
    for (from, to) in [(floor, side), (side, floor)] {
        let route = opened.route(from, to, crate::navigation::SEARCH_LIMIT);
        assert_eq!(route.status, RouteStatus::Complete, "{from:?} to {to:?}");
        assert!(
            route.points.iter().any(|point| {
                (13.5..=15.5).contains(&point[0]) && (7.0..=10.0).contains(&point[2])
            }),
            "route used the old south entry instead of the north return: {:?}",
            route.points
        );
    }
    assert!(
        !map.arena
            .blocked_motion((side[0], side[2]), (floor[0], floor[2]), 0.6),
        "the return opening needs player-body clearance"
    );
}

#[test]
fn side_ward_captive_route_is_rejected_at_map_load_if_return_is_closed() {
    let source = include_str!("../../../maps/m02-persons-unknown.json");
    let blocked = source.replace(
        "\"floor_east_return_header\",\"min\":[14,3,7]",
        "\"floor_east_return_header\",\"min\":[14,0,7]",
    );
    assert_ne!(blocked, source);
    let reason = AuthoredMap::read(blocked.as_bytes())
        .unwrap_err()
        .to_string();
    assert!(
        reason.contains("M02 captive northern return is blocked"),
        "unexpected rejection: {reason}"
    );
}

#[test]
fn m02_worlds_are_prepared_and_the_closed_gate_blocks_departure() {
    let map = read(&fixture()).unwrap();
    let closed = crate::maps::RuntimeMap::Authored(map.clone());
    let wire = crate::sim::GameState::with_authored_map(map).map_info();
    assert!(matches!(
        wire,
        crate::protocol::ServerMessage::MapInfo {
            m02_objectives: Some(3),
            ..
        }
    ));
    let initial_hash = closed.content_sha256();
    let opened = closed.prepared_gate_world(1).unwrap();
    assert_eq!(initial_hash, opened.content_sha256());
    assert_eq!(closed.arena().solids[2].bottom, 0.0);
    assert_eq!(opened.arena().solids[2].bottom, 4.0);
    assert_eq!(
        closed
            .navigation()
            .route(
                [0.0, 0.0, -4.0],
                [0.0, 0.0, 4.0],
                crate::navigation::SEARCH_LIMIT
            )
            .status,
        RouteStatus::Unreachable
    );
    assert_eq!(
        opened
            .navigation()
            .route(
                [0.0, 0.0, -4.0],
                [0.0, 0.0, 4.0],
                crate::navigation::SEARCH_LIMIT
            )
            .status,
        RouteStatus::Complete
    );
    assert!(closed.prepared_gate_world(2).is_none());
    assert!(closed.opened_route().is_none());
    assert!(closed.mission().is_none());
    assert!(closed.is_campaign());
}

#[test]
fn m02_rejects_bad_prerequisites_gate_triggers_and_budget() {
    let mut bad = fixture();
    bad["m02"]["objectives"][1]["after"] = json!("missing");
    assert!(read(&bad).unwrap_err().to_string().contains("linear"));
    let mut bad = fixture();
    bad["m02"]["objectives"][1]["after"] = json!("party_departed");
    assert!(read(&bad).is_err());
    let mut bad = fixture();
    bad["m02"]["objectives"][2]["id"] = json!("ward_reached");
    assert!(read(&bad).is_err());
    let mut bad = fixture();
    bad["m02"]["objectives"][2]["action"] = bad["m02"]["objectives"][1]["action"].clone();
    assert!(read(&bad)
        .unwrap_err()
        .to_string()
        .contains("party_departed arrival"));
    let mut bad = fixture();
    bad["m02"]["gates"][0]["after"] = json!("unknown");
    assert!(read(&bad).unwrap_err().to_string().contains("trigger"));
    let mut bad = fixture();
    bad["m02"]["gates"][0]["after"] = json!("ward_reached");
    assert!(read(&bad)
        .unwrap_err()
        .to_string()
        .contains("next required"));
    let mut bad = fixture();
    bad["m02"]["objectives"] = json!(vec![bad["m02"]["objectives"][0].clone(); 9]);
    assert!(read(&bad).unwrap_err().to_string().contains("budget"));
    let mut bad = fixture();
    bad["map_id"] = json!(1001);
    assert!(read(&bad).is_err());
}

#[test]
fn m02_rejects_an_unknown_encounter_requirement_before_readiness() {
    let mut bad = fixture();
    bad["m02"]["objectives"][1]["requires_encounter"] = json!("ward_guards");
    assert!(read(&bad)
        .unwrap_err()
        .to_string()
        .contains("unknown encounter"));
}

#[test]
fn m02_rejects_unusable_controls_and_routes() {
    let mut bad = fixture();
    bad["m02"]["objectives"][1]["action"]["panel"]["solid"] = json!("ward_gate");
    assert!(read(&bad).unwrap_err().to_string().contains("static host"));
    let mut bad = fixture();
    bad["m02"]["objectives"][1]["action"]["approach"] = json!([0, 0, 1]);
    assert!(read(&bad).is_err());
    let mut bad = fixture();
    bad["m02"]["objectives"][2]["action"]["feet"] = json!([0, 0, 6]);
    assert!(read(&bad).is_err());
    let mut bad = fixture();
    bad["m02"]["gates"][0]["lift"] = json!(1);
    assert!(read(&bad).unwrap_err().to_string().contains("unreachable"));
    let mut bad = fixture();
    bad["m02"]["gates"].as_array_mut().unwrap().clear();
    assert!(read(&bad).unwrap_err().to_string().contains("unreachable"));
    let mut bad = fixture();
    bad["solids"][2]["min"][1] = json!(3);
    bad["solids"][2]["max"][1] = json!(6);
    assert!(read(&bad)
        .unwrap_err()
        .to_string()
        .contains("next required"));
    let mut bad = fixture();
    bad["m02"]["objectives"][2]["action"]["region"]["min"][2] = json!(-4);
    assert!(read(&bad)
        .unwrap_err()
        .to_string()
        .contains("arrival region spans"));
}

#[test]
fn m02_gate_signals_flip_with_their_prepared_world() {
    use crate::protocol::MapDecorationKind;
    let map = read(&fixture()).unwrap();
    let closed = crate::maps::RuntimeMap::Authored(map);
    let kinds = |map: &crate::maps::RuntimeMap| -> Vec<MapDecorationKind> {
        map.presentation_ref()
            .unwrap()
            .decorations
            .iter()
            .map(|detail| detail.kind)
            .collect()
    };
    assert_eq!(
        kinds(&closed),
        [
            MapDecorationKind::GateLocked,
            MapDecorationKind::GateLocked,
            MapDecorationKind::Terminal
        ]
    );
    let opened = closed.prepared_gate_world(1).unwrap();
    assert_eq!(
        kinds(&opened),
        [
            MapDecorationKind::GateOpen,
            MapDecorationKind::GateOpen,
            MapDecorationKind::Terminal
        ]
    );
    // The lamp on the gate rides up with it and stays on its face.
    let lamp = &opened.presentation_ref().unwrap().decorations[0];
    assert_eq!(lamp.solid, 2);
    assert!(lamp.point(&opened.arena().solids[2])[1] > 4.0);
    assert!(crate::protocol::validate_map_presentation(
        opened.presentation_ref(),
        &opened.arena().solids
    )
    .is_ok());
}

#[test]
fn m02_rejects_unlinked_or_distant_openers_and_loose_signals() {
    let mut bad = fixture();
    bad["m02"]["gates"][0]["signals"]
        .as_array_mut()
        .unwrap()
        .truncate(1);
    assert!(read(&bad)
        .unwrap_err()
        .to_string()
        .contains("matching signals"));
    let mut bad = fixture();
    bad["m02"]["gates"][0]["signals"][1]["kind"] = json!("gate_open");
    assert!(read(&bad)
        .unwrap_err()
        .to_string()
        .contains("authored locked"));
    let mut bad = fixture();
    bad["m02"]["gates"][0]["signals"][1]["solid"] = json!("missing");
    assert!(read(&bad).is_err());
    let mut bad = fixture();
    bad["m02"]["gates"][0]
        .as_object_mut()
        .unwrap()
        .remove("signals");
    assert!(read(&bad).is_err());
    let mut bad = fixture();
    bad["decorations"] = json!([
        {"solid":"divider_east","face":"north","center":[0,0],"size":[0.5,0.5],"kind":"gate_open"}
    ]);
    assert!(read(&bad)
        .unwrap_err()
        .to_string()
        .contains("belong to an M02 gate"));
    // A switch across the room from its door is a hunt, not a Doom switch.
    let mut far = fixture();
    far["half_extent"] = json!(20);
    far["solids"][0]["min"] = json!([-20, 3, -20]);
    far["solids"][0]["max"] = json!([20, 4, 20]);
    far["solids"][1]["min"][0] = json!(-20);
    far["solids"][3]["max"][0] = json!(20);
    far["m02"]["objectives"][1]["action"]["panel"]["center"] = json!([0, -14]);
    far["m02"]["objectives"][1]["action"]["approach"] = json!([0, 0, -14.5]);
    assert!(read(&far)
        .unwrap_err()
        .to_string()
        .contains("beside the control"));
    far["m02"]["objectives"][1]["action"]["panel"]["center"] = json!([0, -5]);
    far["m02"]["objectives"][1]["action"]["approach"] = json!([0, 0, -5.5]);
    assert!(read(&far).is_ok());
}

#[test]
fn m02_allows_one_required_switch_at_most() {
    let mut doc = fixture();
    let second = json!({"id":"second_switch","after":"correction_stopped","action":{"kind":"use",
        "panel":{"solid":"ceiling","face":"down","center":[1,-3],"size":[0.5,0.5],"kind":"terminal"},
        "approach":[1,0,-3]}});
    let objectives = doc["m02"]["objectives"].as_array_mut().unwrap();
    objectives.insert(2, second);
    objectives[3]["after"] = json!("second_switch");
    assert!(read(&doc)
        .unwrap_err()
        .to_string()
        .contains("at most one required use switch"));
}
