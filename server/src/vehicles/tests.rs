use super::*;

fn flat() -> Arena {
    Arena {
        half: 100.0,
        solids: Vec::new(),
    }
}
fn motion() -> VehicleMotion {
    VehicleMotion {
        position: [0.0, 0.0, 0.0],
        yaw: 0.0,
        speed: 0.0,
        vy: 0.0,
    }
}

#[test]
fn speed_reverse_brake_and_yaw_are_bounded() {
    let arena = flat();
    let mut state = motion();
    for _ in 0..200 {
        state = vehicle_step(
            state,
            VehicleInput {
                forward: true,
                right: true,
                ..Default::default()
            },
            0.05,
            &arena,
        );
        assert!(state.speed <= 16.0);
        assert!((0.0..std::f32::consts::TAU).contains(&state.yaw));
    }
    for _ in 0..40 {
        state = vehicle_step(
            state,
            VehicleInput {
                brake: true,
                ..Default::default()
            },
            0.05,
            &arena,
        );
    }
    assert_eq!(state.speed, 0.0);
    for _ in 0..100 {
        state = vehicle_step(
            state,
            VehicleInput {
                back: true,
                ..Default::default()
            },
            0.05,
            &arena,
        );
        assert!(state.speed >= -6.0);
    }
    assert_eq!(state.speed, -6.0);
}

#[test]
fn swept_body_cannot_tunnel_through_a_thin_wall_or_leave_bounds() {
    let arena = Arena {
        half: 20.0,
        solids: vec![Solid {
            min_x: 3.0,
            max_x: 3.02,
            min_z: -10.0,
            max_z: 10.0,
            bottom: 0.0,
            top: 4.0,
        }],
    };
    let mut state = motion();
    state.speed = 16.0;
    for _ in 0..10 {
        state = vehicle_step(
            state,
            VehicleInput {
                forward: true,
                ..Default::default()
            },
            0.05,
            &arena,
        );
    }
    assert!(state.position[0] <= 1.1);
    assert_eq!(state.speed, 0.0);
    assert!(!clear_body([19.0, 0.0, 0.0], 0.0, &arena));
}

#[test]
fn airborne_jeep_lands_without_reversing_vertical_velocity() {
    let arena = flat();
    let mut state = motion();
    state.position[1] = 3.0;
    state.speed = 8.0;
    for _ in 0..50 {
        state = vehicle_step(state, VehicleInput::default(), 0.05, &arena);
        assert!(state.position[1] >= 0.0);
    }
    assert_eq!(state.position[1], 0.0);
    assert_eq!(state.vy, 0.0);
    assert!(state.position[0] > 0.0);
}

#[test]
fn mounted_heat_has_a_cooldown_and_recovers_after_overheat() {
    let mut jeep = Jeep::new(1, [0.0; 3], 0.0);
    let mut count = 0;
    for tick in 0..200 {
        jeep.cool();
        if jeep.fire(tick) {
            count += 1;
        }
    }
    assert!(count > 5 && count < 50, "accepted {count} shots");
    for _ in 0..100 {
        jeep.cool();
    }
    assert!(jeep.fire(500));
    assert!(!jeep.fire(501));
    jeep.damage(999, None);
    assert_eq!(jeep.state.hp, 0);
    assert_eq!(jeep.state.burning_ticks, 40);
    assert!(!jeep.fire(600));
}

#[test]
fn wire_and_oriented_ray_box_match_the_registered_body() {
    let jeep = Jeep::new(1, [0.0; 3], std::f32::consts::FRAC_PI_2);
    assert!(jeep.state.validate());
    let ray = crate::combat::Ray {
        origin: [-10.0, 0.7, 0.0],
        direction: [1.0, 0.0, 0.0],
    };
    let hit = ray_hit(&jeep.state, ray, 20.0).unwrap();
    assert!((hit.distance - 9.05).abs() < 0.001);
    let mut invalid = jeep.state;
    invalid.gun_heat = f32::NAN;
    assert!(!invalid.validate());
}

#[test]
fn shared_vehicle_vectors_remain_the_native_movement_contract() {
    let document: serde_json::Value =
        serde_json::from_str(include_str!("../../../client/golden/vehicle_vectors.json")).unwrap();
    assert_eq!(document["version"], 1);
    for case in document["vectors"].as_array().unwrap() {
        let mut state: VehicleMotion = serde_json::from_value(case["initial"].clone()).unwrap();
        let input: VehicleInput = serde_json::from_value(case["input"].clone()).unwrap();
        let arena: Arena = serde_json::from_value(case["arena"].clone()).unwrap();
        let expected: VehicleMotion = serde_json::from_value(case["expected"].clone()).unwrap();
        for _ in 0..case["steps"].as_u64().unwrap() {
            state = vehicle_step(state, input, case["dt"].as_f64().unwrap() as f32, &arena);
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
                "{}: native {a}, fixture {b}",
                case["name"]
            );
        }
    }
}

#[test]
fn vehicle_clearance_keeps_exposed_occupants_below_overhangs() {
    let arena = Arena {
        half: 20.0,
        solids: vec![Solid {
            min_x: -5.0,
            max_x: 5.0,
            min_z: -5.0,
            max_z: 5.0,
            bottom: 2.0,
            top: 3.0,
        }],
    };
    assert!(!clear_body([0.0; 3], 0.0, &arena));
}
