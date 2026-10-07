use super::*;

#[test]
fn shared_water_air_vectors_match_native_contract() {
    let document: serde_json::Value = serde_json::from_str(include_str!(
        "../../../../client/golden/water_air_vectors.json"
    ))
    .unwrap();
    assert_eq!(document["version"], 1);
    assert_eq!(document["vectors"].as_array().unwrap().len(), 11);
    for case in document["vectors"].as_array().unwrap() {
        let kind: VehicleKind = serde_json::from_value(case["kind"].clone()).unwrap();
        let mut state: VehicleMotion = serde_json::from_value(case["initial"].clone()).unwrap();
        let expected: VehicleMotion = serde_json::from_value(case["expected"].clone()).unwrap();
        let input: VehicleInput = serde_json::from_value(case["input"].clone()).unwrap();
        let arena: Arena = serde_json::from_value(case["arena"].clone()).unwrap();
        let water: Vec<WaterRegion> =
            serde_json::from_value(case["water_regions"].clone()).unwrap();
        for _ in 0..case["steps"].as_u64().unwrap() {
            state = vehicle_step_kind(
                kind,
                state,
                input,
                case["dt"].as_f64().unwrap() as f32,
                &arena,
                &water,
            );
        }
        for (a, b) in state
            .position
            .into_iter()
            .chain([state.yaw, state.speed, state.vy])
            .zip(
                expected
                    .position
                    .into_iter()
                    .chain([expected.yaw, expected.speed, expected.vy]),
            )
        {
            assert!(
                (a - b).abs() < 0.001,
                "{} native{a} fixture{b}",
                case["name"]
            );
        }
    }
}

fn flat() -> Arena {
    Arena {
        half: 220.0,
        solids: Vec::new(),
    }
}
fn water() -> Vec<WaterRegion> {
    vec![WaterRegion {
        min: [-100.0, -100.0],
        max: [100.0, 100.0],
        level: 2.2,
        depth: 2.2,
    }]
}
fn motion(y: f32) -> VehicleMotion {
    VehicleMotion {
        position: [0.0, y, 0.0],
        yaw: 0.0,
        speed: 0.0,
        vy: 0.0,
    }
}

#[test]
fn boat_float_speed_turn_and_shoreline_are_bounded() {
    let arena = flat();
    let water = water();
    let mut state = motion(2.2);
    for _ in 0..120 {
        state = vehicle_step_kind(
            VehicleKind::Boat,
            state,
            VehicleInput {
                forward: true,
                right: true,
                ..Default::default()
            },
            0.05,
            &arena,
            &water,
        );
        assert_eq!(state.position[1], 2.2);
        assert_eq!(state.vy, 0.0);
        assert!(state.speed <= 14.0);
    }
    assert!(state.speed > 10.0);
    let before = VehicleMotion {
        position: [96.0, 2.2, 0.0],
        yaw: 0.0,
        speed: 14.0,
        vy: 0.0,
    };
    let mut edge = before;
    for _ in 0..10 {
        edge = vehicle_step_kind(
            VehicleKind::Boat,
            edge,
            VehicleInput {
                forward: true,
                ..Default::default()
            },
            0.05,
            &arena,
            &water,
        );
    }
    assert!(edge.position[0] <= 97.6);
    assert_eq!(edge.speed, 0.0);
    let mut shallow = water;
    shallow[0].depth = 0.4;
    let refused = vehicle_step_kind(
        VehicleKind::Boat,
        motion(2.2),
        VehicleInput {
            forward: true,
            ..Default::default()
        },
        0.05,
        &arena,
        &shallow,
    );
    assert_eq!(refused.position, motion(2.2).position);
    assert_eq!(refused.speed, 0.0);
}

#[test]
fn boat_swept_body_refuses_thin_dock_wall() {
    let mut arena = flat();
    arena.solids.push(crate::movement::Solid {
        min_x: 4.0,
        max_x: 4.01,
        min_z: -20.0,
        max_z: 20.0,
        bottom: 0.0,
        top: 6.0,
    });
    let mut state = motion(2.2);
    state.speed = 14.0;
    for _ in 0..20 {
        state = vehicle_step_kind(
            VehicleKind::Boat,
            state,
            VehicleInput {
                forward: true,
                ..Default::default()
            },
            0.05,
            &arena,
            &water(),
        );
    }
    assert!(state.position[0] <= 1.6);
    assert_eq!(state.speed, 0.0);
}

#[test]
fn aircraft_taxis_takes_off_turns_and_respects_ceiling() {
    let mut state = motion(0.0);
    let arena = flat();
    for _ in 0..20 {
        state = vehicle_step_kind(
            VehicleKind::LightAircraft,
            state,
            VehicleInput {
                forward: true,
                brake: true,
                ..Default::default()
            },
            0.05,
            &arena,
            &[],
        );
    }
    assert_eq!(state.position[1], 0.0, "no lift below takeoff speed");
    for _ in 0..420 {
        state = vehicle_step_kind(
            VehicleKind::LightAircraft,
            state,
            VehicleInput {
                forward: true,
                brake: true,
                right: true,
                ..Default::default()
            },
            0.05,
            &arena,
            &[],
        );
        assert!(state.position[1] <= 60.0);
    }
    assert!(state.position[1] > 50.0);
    assert_eq!(state.speed, 32.0);
}

#[test]
fn aircraft_stalls_lands_and_marks_water_contact() {
    let arena = flat();
    let mut state = motion(8.0);
    for _ in 0..50 {
        state = vehicle_step_kind(
            VehicleKind::LightAircraft,
            state,
            VehicleInput::default(),
            0.05,
            &arena,
            &[],
        );
    }
    assert_eq!(state.position[1], 0.0);
    assert_eq!(state.vy, 0.0);
    let mut state = motion(3.0);
    state.vy = -4.0;
    for _ in 0..12 {
        state = vehicle_step_kind(
            VehicleKind::LightAircraft,
            state,
            VehicleInput::default(),
            0.05,
            &arena,
            &water(),
        );
    }
    assert_eq!(state.position[1], 2.2);
    assert_eq!(state.speed, 0.0);
}

#[test]
fn aircraft_wings_and_bounds_are_real_collision() {
    let arena = Arena {
        half: 20.0,
        solids: vec![crate::movement::Solid {
            min_x: -2.0,
            max_x: 2.0,
            min_z: 4.0,
            max_z: 4.01,
            bottom: 0.0,
            top: 4.0,
        }],
    };
    assert!(!clear_kind(
        VehicleKind::LightAircraft,
        [0.0; 3],
        0.0,
        &arena
    ));
    assert!(!clear_kind(
        VehicleKind::LightAircraft,
        [17.0, 8.0, 0.0],
        0.0,
        &arena
    ));
}
