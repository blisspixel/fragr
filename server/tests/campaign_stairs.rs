//! Supported stairs, protected edges and cover in the corrected campaign worlds.
//! These fixtures use explicit initial feet and ordinary movement. Full finite
//! mission combat and eye-height renderer acceptance are separate checks.
use fragr_server::combat::line_of_sight;
use fragr_server::maps::{AuthoredMap, RuntimeMap};
use fragr_server::movement::{
    live_step, Arena, MoveInput, MoveState, BODY_HEIGHT, CONTACT_EPSILON, RADIUS,
};
use serde_json::{json, Value};
use std::path::Path;

fn filename(stage: u8) -> &'static str {
    match stage {
        8 => "m08_custodian_of_record.json",
        9 => "m09_passenger_manifest.json",
        10 => "m10_common_carrier.json",
        12 => "m12-terms-of-cooperation.json",
        _ => panic!("unregistered stair fixture"),
    }
}

fn source(stage: u8) -> Vec<u8> {
    std::fs::read(
        Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("maps")
            .join(filename(stage)),
    )
    .unwrap()
}

fn world(stage: u8) -> RuntimeMap {
    RuntimeMap::Authored(AuthoredMap::read(source(stage).as_slice()).unwrap())
}

fn predecessor(stage: u8) -> RuntimeMap {
    RuntimeMap::Authored(
        AuthoredMap::load(
            &Path::new(env!("CARGO_MANIFEST_DIR"))
                .join("src/mission/run_file/store/fixtures/stair-predecessors-20261008")
                .join(filename(stage)),
        )
        .unwrap(),
    )
}

fn body(feet: [f32; 3]) -> MoveState {
    MoveState {
        x: feet[0],
        y: feet[1],
        z: feet[2],
        vx: 0.0,
        vy: 0.0,
        vz: 0.0,
        yaw: 0.0,
    }
}

fn near(body: MoveState, feet: [f32; 3]) -> bool {
    (body.x - feet[0]).hypot(body.z - feet[2]) < 0.25 && (body.y - feet[1]).abs() < 0.04
}

fn toward(arena: &Arena, mut body: MoveState, feet: [f32; 3], limit: u32) -> (MoveState, u32) {
    for tick in 0..limit {
        if near(body, feet) {
            return (body, tick);
        }
        let dx = feet[0] - body.x;
        let dz = feet[2] - body.z;
        body = live_step(
            body,
            &MoveInput {
                forward: true,
                yaw: dz.atan2(dx),
                ..MoveInput::default()
            },
            5.0_f32.min(dx.hypot(dz) / 0.05),
            0.05,
            arena,
        );
    }
    (body, limit)
}

fn walk(arena: &Arena, points: &[[f32; 3]]) -> u32 {
    let mut current = body(points[0]);
    let mut ticks = 0;
    for feet in &points[1..] {
        let (next, elapsed) = toward(arena, current, *feet, 900);
        assert!(
            near(next, *feet),
            "blocked {current:?} -> {feet:?}, ended {next:?}"
        );
        assert!(
            !arena.solids.iter().any(|solid| solid.covers(next.x, next.z)
                && solid.top > next.y + CONTACT_EPSILON
                && solid.bottom < next.y + BODY_HEIGHT - CONTACT_EPSILON),
            "standing body entered a wall at {next:?}"
        );
        current = next;
        ticks += elapsed;
    }
    ticks
}

fn refuses(arena: &Arena, from: [f32; 3], to: [f32; 3], kept_x: std::ops::Range<f32>) {
    let (stopped, _) = toward(arena, body(from), to, 120);
    assert!(
        !near(stopped, to),
        "protected edge was crossed: {from:?} -> {to:?}"
    );
    assert!(
        kept_x.contains(&stopped.x),
        "body left the protected flight: {stopped:?}"
    );
    assert!(
        stopped.y >= from[1] - 0.04,
        "body dropped sideways off its stair: {stopped:?}"
    );
}

#[test]
fn m08_all_four_enclosed_flights_keep_both_directions_and_refuse_sideways_drops() {
    let sealed = world(8);
    let opened = sealed.prepared_m08_world(1).unwrap();
    let fallen = sealed.prepared_m08_world(2).unwrap();
    let routes: &[&[[f32; 3]]] = &[
        &[
            [-19.0, 0.0, -5.0],
            [-23.0, 0.0, -5.0],
            [-28.0, 0.0, -5.0],
            [-28.0, 3.0, 4.0],
            [-22.0, 3.0, 6.0],
            [-18.0, 3.0, 6.0],
            [-22.0, 3.0, 6.0],
            [-28.0, 3.0, 4.0],
            [-28.0, 0.0, -5.0],
            [-23.0, 0.0, -5.0],
            [-19.0, 0.0, -5.0],
        ],
        &[
            [19.0, 3.0, -6.0],
            [23.0, 3.0, -6.0],
            [28.0, 3.0, -6.0],
            [28.0, 6.0, 4.0],
            [22.0, 6.0, 3.0],
            [18.0, 6.0, 2.0],
            [22.0, 6.0, 3.0],
            [28.0, 6.0, 4.0],
            [28.0, 3.0, -6.0],
            [23.0, 3.0, -6.0],
            [19.0, 3.0, -6.0],
        ],
        &[
            [-8.5, 6.0, 22.0],
            [-8.5, 0.0, 34.5],
            [-5.0, 0.0, 34.8],
            [-4.5, 0.0, 31.0],
            [0.0, 0.0, 27.0],
            [-4.5, 0.0, 31.0],
            [-5.0, 0.0, 34.8],
            [-8.5, 0.0, 34.5],
            [-8.5, 6.0, 22.0],
        ],
        &[
            [8.5, 6.0, 22.0],
            [8.5, 0.0, 34.5],
            [5.0, 0.0, 34.8],
            [4.5, 0.0, 31.0],
            [0.0, 0.0, 27.0],
            [4.5, 0.0, 31.0],
            [5.0, 0.0, 34.8],
            [8.5, 0.0, 34.5],
            [8.5, 6.0, 22.0],
        ],
    ];
    let mut ticks = 0;
    for stage in [&sealed, &opened, &fallen] {
        for route in routes {
            ticks += walk(stage.arena(), route);
        }
        for (from, to, span) in [
            ([-28.0, 1.5, -0.5], [-23.0, 1.5, -0.5], -30.0..-26.0),
            ([28.0, 4.5, -1.5], [23.0, 4.5, -1.5], 26.0..30.0),
            ([-8.5, 3.0, 28.5], [0.0, 0.0, 27.0], -11.0..-6.0),
            ([8.5, 3.0, 28.5], [0.0, 0.0, 27.0], 6.0..11.0),
        ] {
            refuses(stage.arena(), from, to, span);
        }
        assert!(!line_of_sight(
            [8.5, 4.6, 28.5],
            [0.0, 4.6, 28.5],
            &stage.arena().solids
        ));
    }
    println!("M08: 108 ordinary stair segments across three prepared worlds, {ticks} ticks, 12 edge refusals");
}

#[test]
fn m08_old_halfway_side_drop_is_refused_and_the_bottom_descent_replaces_it() {
    let old = predecessor(8);
    let current = world(8);
    let from = [8.5, 3.0, 28.5];
    let to = [0.0, 0.0, 27.0];
    let (dropped, _) = toward(old.arena(), body(from), to, 120);
    assert!(
        near(dropped, to),
        "predecessor must reproduce the old three-metre sideways shortcut"
    );
    refuses(current.arena(), from, to, 6.0..11.0);
    assert!(line_of_sight(
        [8.5, 4.6, 28.5],
        [0.0, 4.6, 28.5],
        &old.arena().solids
    ));
    assert!(!line_of_sight(
        [8.5, 4.6, 28.5],
        [0.0, 4.6, 28.5],
        &current.arena().solids
    ));
    walk(
        current.arena(),
        &[
            [8.5, 6.0, 22.0],
            [8.5, 0.0, 34.5],
            [5.0, 0.0, 34.8],
            [4.5, 0.0, 31.0],
            to,
        ],
    );
}

#[test]
fn m09_office_stair_turn_and_protected_landing_keep_the_actual_room_connection() {
    let closed = world(9);
    let opened = closed.prepared_m09_world().unwrap();
    for stage in [&closed, &opened] {
        walk(
            stage.arena(),
            &[
                [-45.0, 0.0, -39.0],
                [-41.0, 0.0, -36.0],
                [-41.0, 4.0, -26.5],
                [-29.0, 4.0, -26.5],
                [-29.0, 4.0, -31.0],
                [-29.0, 4.0, -26.5],
                [-41.0, 4.0, -26.5],
                [-41.0, 0.0, -36.0],
                [-45.0, 0.0, -39.0],
            ],
        );
        refuses(
            stage.arena(),
            [-41.0, 2.4, -30.5],
            [-35.0, 2.4, -30.5],
            -44.0..-38.0,
        );
        refuses(
            stage.arena(),
            [-41.0, 2.4, -30.5],
            [-47.0, 2.4, -30.5],
            -44.0..-38.0,
        );
        refuses(
            stage.arena(),
            [-19.0, 4.0, -33.5],
            [-15.5, 0.0, -33.5],
            -20.0..-18.5,
        );
        let (stopped, _) = toward(
            stage.arena(),
            body([-25.0, 4.0, -34.0]),
            [-25.0, 0.0, -39.0],
            100,
        );
        assert!(
            stopped.z > -35.0 && (stopped.y - 4.0).abs() < 0.04,
            "landing guard must stop its real edge: {stopped:?}"
        );
        assert!(!line_of_sight(
            [-41.0, 3.6, -30.5],
            [-35.0, 3.6, -30.5],
            &stage.arena().solids
        ));
        // The predecessor's office landing is ground filled. Preserve the
        // real loading-yard route along its lower frontage.
        walk(
            stage.arena(),
            &[
                [-37.0, 0.0, -36.0],
                [-29.0, 0.0, -36.0],
                [-19.0, 0.0, -36.0],
                [-29.0, 0.0, -36.0],
            ],
        );
    }
}

#[test]
fn m09_charge_transfer_keeps_the_original_opening_and_adjacent_guard_cover() {
    let old = predecessor(9);
    let continuous = RuntimeMap::Authored(
        AuthoredMap::load(
            &Path::new(env!("CARGO_MANIFEST_DIR"))
                .join("src/mission/run_file/store/fixtures/stair-predecessors-20261008")
                .join("m09_passenger_manifest_enclosed.json"),
        )
        .unwrap(),
    );
    let current = world(9);
    let opened = current.prepared_m09_world().unwrap();
    let from = [-19.0, 4.0, -31.0];
    let below = [-15.5, 0.0, -31.0];
    for stage in [&old, &current, &opened] {
        walk(stage.arena(), &[from, below]);
        assert!(line_of_sight(
            [-19.0, 4.6, -31.0],
            [-16.0, 4.6, -31.0],
            &stage.arena().solids
        ));
    }
    refuses(continuous.arena(), from, below, -20.0..-18.5);
    assert!(!line_of_sight(
        [-19.0, 4.6, -31.0],
        [-16.0, 4.6, -31.0],
        &continuous.arena().solids
    ));
    for stage in [&current, &opened] {
        assert!(!line_of_sight(
            [-19.0, 4.6, -33.5],
            [-16.0, 4.6, -33.5],
            &stage.arena().solids
        ));
    }
}

#[test]
fn m10_both_pressure_stairs_keep_all_four_storey_connections_and_real_cover() {
    let world = world(10);
    let arena = world.arena();
    let mut ticks = 0;
    for (first_x, second_x, mouth_z, flight_z, turn_z) in [
        (-6.55, -4.45, -15.5, -14.5, -4.5),
        (4.55, 6.65, 15.5, 14.5, 4.5),
    ] {
        for base in [2.0, 4.8] {
            ticks += walk(
                arena,
                &[
                    [0.0, base, mouth_z],
                    [first_x, base, mouth_z],
                    [first_x, base, flight_z],
                    [first_x, base + 1.4, turn_z],
                    [second_x, base + 1.4, turn_z],
                    [second_x, base + 2.8, flight_z],
                    [second_x, base + 2.8, mouth_z],
                    [0.0, base + 2.8, mouth_z],
                    [second_x, base + 2.8, mouth_z],
                    [second_x, base + 2.8, flight_z],
                    [second_x, base + 1.4, turn_z],
                    [first_x, base + 1.4, turn_z],
                    [first_x, base, flight_z],
                    [first_x, base, mouth_z],
                    [0.0, base, mouth_z],
                ],
            );
        }
    }
    refuses(arena, [-4.45, 4.4, -10.5], [0.0, 2.0, -10.5], -5.35..-3.55);
    refuses(arena, [4.55, 2.6, 10.5], [0.0, 2.0, 10.5], 3.65..5.45);
    assert!(!line_of_sight(
        [-4.45, 5.6, -10.5],
        [0.0, 5.6, -10.5],
        &arena.solids
    ));
    assert!(!line_of_sight(
        [4.55, 5.6, 10.5],
        [0.0, 5.6, 10.5],
        &arena.solids
    ));
    println!("M10: 56 ordinary walk segments, {ticks} ticks, all four floor connections and two side refusals");
}

#[test]
fn m12_bridge_flights_and_all_four_protected_edges_match_authoritative_cover() {
    let closed = world(12);
    let opened = closed.prepared_m12_world().unwrap();
    for world in [&closed, &opened] {
        let arena = world.arena();
        walk(
            arena,
            &[
                [0.0, 0.3, -7.0],
                [0.0, 1.3, 2.4],
                [0.0, 0.3, 9.0],
                [0.0, 1.3, 2.4],
                [0.0, 0.3, -7.0],
            ],
        );
        for (from, to) in [
            ([3.0, 1.3, 2.4], [3.0, 0.3, -3.0]),
            ([3.0, 1.3, 2.4], [3.0, 0.3, 8.0]),
            ([0.0, 1.3, 2.4], [-10.0, 0.3, 2.4]),
            ([0.0, 1.3, 2.4], [10.0, 0.3, 2.4]),
        ] {
            let (stopped, _) = toward(arena, body(from), to, 100);
            assert!(
                (stopped.y - 1.3).abs() < 0.04
                    && stopped.x.abs() < 8.0 - RADIUS
                    && stopped.z > 1.4
                    && stopped.z < 3.4,
                "bridge edge did not keep supported feet: {stopped:?}"
            );
        }
        assert!(!line_of_sight(
            [3.0, 1.8, 2.4],
            [3.0, 1.8, 0.0],
            &arena.solids
        ));
        assert!(
            line_of_sight([0.0, 1.8, 2.4], [0.0, 1.8, 0.0], &arena.solids),
            "actual stair mouth stays open to rays"
        );
    }
}

fn numeric_equal(left: &Value, right: &Value) -> bool {
    match (left, right) {
        (Value::Number(a), Value::Number(b)) => a.as_f64() == b.as_f64(),
        (Value::Array(a), Value::Array(b)) => {
            a.len() == b.len() && a.iter().zip(b).all(|(a, b)| numeric_equal(a, b))
        }
        (Value::Object(a), Value::Object(b)) => {
            a.len() == b.len()
                && a.iter()
                    .all(|(key, a)| b.get(key).is_some_and(|b| numeric_equal(a, b)))
        }
        _ => left == right,
    }
}

#[test]
fn enclosure_changes_only_append_the_bounded_registered_solids() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"));
    for (stage, prefix, added) in [(8, 144, 9), (9, 132, 7), (10, 123, 6), (12, 114, 18)] {
        let old: Value = serde_json::from_slice(
            &std::fs::read(
                root.join("src/mission/run_file/store/fixtures/stair-predecessors-20261008")
                    .join(filename(stage)),
            )
            .unwrap(),
        )
        .unwrap();
        let mut current: Value = serde_json::from_slice(&source(stage)).unwrap();
        assert_eq!(
            old["solids"].as_array().unwrap().len(),
            prefix,
            "registered predecessor count"
        );
        assert_eq!(
            current["solids"].as_array().unwrap().len(),
            prefix + added,
            "exact bounded addition count"
        );
        let first = current["solids"].as_array().unwrap()[..prefix].to_vec();
        assert!(
            numeric_equal(&Value::Array(first), &old["solids"]),
            "an original solid or host index changed in M{stage:02}"
        );
        current["solids"] = old["solids"].clone();
        assert!(numeric_equal(&current,&old),"an unrelated objective, spawn, supply, encounter or presentation contract changed in M{stage:02}");
    }
}

fn refuse_added_obstruction(stage: u8, id: &str, min: [f32; 3], max: [f32; 3]) {
    let mut document: Value = serde_json::from_slice(&source(stage)).unwrap();
    document["solids"]
        .as_array_mut()
        .unwrap()
        .push(json!({"id":id,"min":min,"max":max,"surface":"enamel"}));
    let error = AuthoredMap::read(serde_json::to_vec(&document).unwrap().as_slice()).unwrap_err();
    assert_eq!(error.kind(), std::io::ErrorKind::InvalidData);
}

#[test]
fn strict_loader_refuses_a_closed_pressure_stair_mouth() {
    refuse_added_obstruction(
        10,
        "blocked_west_pressure_mouth",
        [-7.8, 2.0, -16.0],
        [-3.25, 10.1, -13.05],
    );
}

#[test]
fn strict_loader_refuses_an_office_turn_without_standing_headroom() {
    refuse_added_obstruction(
        9,
        "low_office_turn_ceiling",
        [-44.0, 4.9, -28.0],
        [-38.0, 5.2, -25.0],
    );
}

#[test]
fn strict_loader_refuses_an_obstructed_archive_upper_landing() {
    refuse_added_obstruction(
        8,
        "blocked_west_tower_turn",
        [-31.0, 3.0, 3.0],
        [-21.0, 6.3, 9.0],
    );
}
