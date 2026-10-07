use super::*;
use crate::protocol::{Action, Role, VehicleKind};

fn scene() -> (GameState, Uuid, Arena) {
    let mut state = GameState::new();
    state.config.boss_spawn_ticks = None;
    state.config.compliance_ping_ticks = None;
    let actor = Uuid::from_u128(701);
    state.add_player(actor, "Boarding tester".into(), Role::Human);
    state.start_round();
    state.add_jeep([0.0; 3], 0.0).unwrap();
    let arena = Arena {
        half: 20.0,
        solids: Vec::new(),
    };
    (state, actor, arena)
}

#[test]
fn exit_uses_an_open_side_instead_of_crossing_low_cover() {
    let (mut state, actor, mut arena) = scene();
    state.vehicles[0].assign(VehicleSeat::Driver, Some(actor));
    state.follow_vehicle_seats();
    arena.solids.push(Solid {
        min_x: -6.0,
        max_x: 6.0,
        min_z: 1.6,
        max_z: 1.8,
        bottom: 0.0,
        top: 1.5,
    });
    assert!(crate::combat::line_of_sight(
        [0.0, 1.8, 0.0],
        [0.0, crate::movement::EYE_HEIGHT, 2.5],
        &arena.solids,
    ));
    assert!(state.exit_vehicle(0, actor, &arena));
    assert!(state.players[0].z < 0.0, "use the physically open side");
}

#[test]
fn low_enclosure_refuses_exit_even_when_every_eye_ray_is_clear() {
    let (mut state, actor, mut arena) = scene();
    state.vehicles[0].assign(VehicleSeat::Driver, Some(actor));
    state.follow_vehicle_seats();
    for (min_x, max_x, min_z, max_z) in [
        (-6.0, 6.0, 1.6, 1.8),
        (-6.0, 6.0, -1.8, -1.6),
        (2.6, 2.8, -6.0, 6.0),
        (-2.8, -2.6, -6.0, 6.0),
    ] {
        arena.solids.push(Solid {
            min_x,
            max_x,
            min_z,
            max_z,
            bottom: 0.0,
            top: 1.5,
        });
    }
    assert!(vehicles::clear_body([0.0; 3], 0.0, &arena));
    let before = [state.players[0].x, state.players[0].y, state.players[0].z];
    assert!(!state.exit_vehicle(0, actor, &arena));
    assert_eq!(state.vehicle_seat(actor), Some((0, VehicleSeat::Driver)));
    assert_eq!(
        [state.players[0].x, state.players[0].y, state.players[0].z],
        before
    );
}

#[test]
fn boarding_cannot_cross_low_cover_that_does_not_block_sight() {
    let (mut state, actor, mut arena) = scene();
    state.players[0].x = 0.0;
    state.players[0].z = -1.9;
    state.players[0].y = PLAYER_FLOOR_Y;
    state.players[0].interaction_requested = true;
    arena.solids.push(Solid {
        min_x: -6.0,
        max_x: 6.0,
        min_z: -1.3,
        max_z: -1.2,
        bottom: 0.0,
        top: 1.0,
    });
    assert!(vehicles::clear_body([0.0; 3], 0.0, &arena));
    assert!(crate::combat::line_of_sight(
        [0.0, crate::movement::EYE_HEIGHT, -1.9],
        [0.0, 1.2, 0.0],
        &arena.solids,
    ));
    state.vehicle_interactions(&arena);
    assert!(state.vehicle_seat(actor).is_none());
    arena.solids.clear();
    state.vehicle_interactions(&arena);
    assert_eq!(state.vehicle_seat(actor), Some((0, VehicleSeat::Driver)));
}

#[test]
fn aircraft_boarding_sweeps_headroom_outside_the_wing_hull() {
    let (mut state, actor, mut arena) = scene();
    state.vehicles[0] = vehicles::Jeep::of_kind(
        1,
        VehicleKind::LightAircraft,
        [0.0; 3],
        std::f32::consts::FRAC_PI_2,
    );
    state.players[0].x = 5.5;
    state.players[0].z = 0.0;
    state.players[0].y = PLAYER_FLOOR_Y;
    state.players[0].interaction_requested = true;
    arena.solids.push(Solid {
        min_x: 4.8,
        max_x: 4.9,
        min_z: -3.0,
        max_z: 3.0,
        bottom: 1.85,
        top: 2.1,
    });
    let aircraft = &state.vehicles[0].state;
    assert!(vehicles::clear_kind(
        aircraft.kind,
        aircraft.position,
        aircraft.yaw,
        &arena
    ));
    assert!(crate::combat::line_of_sight(
        [5.5, crate::movement::EYE_HEIGHT, 0.0],
        [0.0, 1.2, 0.0],
        &arena.solids,
    ));
    state.vehicle_interactions(&arena);
    assert!(state.vehicle_seat(actor).is_none());
    arena.solids.clear();
    state.vehicle_interactions(&arena);
    assert_eq!(state.vehicle_seat(actor), Some((0, VehicleSeat::Driver)));
}

#[test]
fn passage_excludes_its_own_chassis_but_blocks_another_hull() {
    let (mut state, actor, arena) = scene();
    state.vehicles[0].assign(VehicleSeat::Driver, Some(actor));
    let from = vehicles::seat_feet(&state.vehicles[0].state, VehicleSeat::Driver);
    let to = [0.0, 0.0, 5.0];
    assert!(state.vehicle_passage_clear(0, from, to, &arena));
    state
        .vehicles
        .push(vehicles::Jeep::new(2, [0.0, 0.0, 2.5], 0.0));
    assert!(!vehicles::hull(&state.vehicles[1].state).blocks(to[0], to[2], RADIUS));
    assert!(!state.vehicle_passage_clear(0, from, to, &arena));
}

#[test]
fn actual_island_dock_and_aircraft_keep_ordinary_boarding_and_exit() {
    for (kind, approach) in [
        (VehicleKind::Boat, [-60.0, 2.2, 75.0]),
        (VehicleKind::LightAircraft, [5.5, 3.0, -105.0]),
    ] {
        let mut state = GameState::with_map(crate::sim::MapKind::HoldfastAtoll, false);
        state.config.boss_spawn_ticks = None;
        state.config.compliance_ping_ticks = None;
        let actor = Uuid::from_u128(702);
        state.add_player(actor, "Island boarding tester".into(), Role::Human);
        state.start_round();
        state.players[0].x = approach[0];
        state.players[0].y = approach[1] + PLAYER_FLOOR_Y;
        state.players[0].z = approach[2];
        state.set_action(
            actor,
            Action {
                interact: true,
                ..Default::default()
            },
        );
        state.tick(0.05);
        let (index, seat) = state.vehicle_seat(actor).expect("ordinary boarding");
        assert_eq!(state.vehicles[index].state.kind, kind);
        assert_eq!(seat, VehicleSeat::Driver);
        state.set_action(actor, Action::default());
        state.tick(0.05);
        state.set_action(
            actor,
            Action {
                interact: true,
                ..Default::default()
            },
        );
        state.tick(0.05);
        assert!(state.vehicle_seat(actor).is_none(), "{kind:?} exit");
        let p = &state.players[0];
        assert!(!state.current_arena().blocked_body_at(
            p.x,
            p.z,
            p.y - PLAYER_FLOOR_Y,
            p.y - PLAYER_FLOOR_Y
        ));
        if kind == VehicleKind::Boat {
            assert!((p.y - PLAYER_FLOOR_Y - 2.2).abs() < 0.001, "dock return");
        }
    }
}
