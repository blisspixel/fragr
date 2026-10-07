use super::*;
use crate::protocol::{Action, Role, VehicleSeat, WeaponType};

fn scene() -> (GameState, Uuid) {
    let mut state = GameState::new();
    state.config.boss_spawn_ticks = None;
    state.config.compliance_ping_ticks = None;
    let id = Uuid::from_u128(501);
    state.add_player(id, "Driver".into(), Role::Human);
    state.start_round();
    state.add_jeep([0.0; 3], 0.0).unwrap();
    let p = &mut state.players[0];
    p.x = 0.0;
    p.z = -1.6;
    p.y = PLAYER_FLOOR_Y;
    (state, id)
}
fn use_vehicle(state: &mut GameState, id: Uuid) {
    state.set_action(
        id,
        Action {
            interact: true,
            ..Default::default()
        },
    );
    state.tick(0.05);
    state.set_action(id, Action::default());
}

#[test]
fn enter_drive_stop_switch_and_exit_share_the_normal_action_channel() {
    let (mut state, id) = scene();
    use_vehicle(&mut state, id);
    assert_eq!(state.vehicle_seat(id), Some((0, VehicleSeat::Driver)));
    state.set_action(
        id,
        Action {
            forward: true,
            seq: Some(2),
            ..Default::default()
        },
    );
    for _ in 0..30 {
        state.tick(0.05);
    }
    assert!(state.vehicles[0].state.position[0] > 1.0);
    assert!(state.vehicles[0].state.speed > 2.0);
    state.set_action(
        id,
        Action {
            interact: true,
            seq: Some(3),
            ..Default::default()
        },
    );
    state.tick(0.05);
    assert!(state.vehicle_seat(id).is_some());
    state.set_action(
        id,
        Action {
            jump: true,
            seq: Some(4),
            ..Default::default()
        },
    );
    for _ in 0..20 {
        state.tick(0.05);
    }
    state.set_action(
        id,
        Action {
            seat: Some(VehicleSeat::Gunner),
            seq: Some(5),
            ..Default::default()
        },
    );
    state.tick(0.05);
    assert_eq!(state.vehicle_seat(id), Some((0, VehicleSeat::Gunner)));
    state.set_action(
        id,
        Action {
            interact: true,
            seq: Some(6),
            ..Default::default()
        },
    );
    state.tick(0.05);
    assert!(state.vehicle_seat(id).is_none());
    assert!(!state.current_arena().blocked_body_at(
        state.players[0].x,
        state.players[0].z,
        state.players[0].y - PLAYER_FLOOR_Y,
        state.players[0].y - PLAYER_FLOOR_Y
    ));
}

#[test]
fn gunner_resolves_mounted_shots_without_changing_the_carried_weapon() {
    let (mut state, id) = scene();
    state.vehicles[0].assign(VehicleSeat::Gunner, Some(id));
    state.players[0].weapon = WeaponType::Rail;
    state.set_action(
        id,
        Action {
            fire: true,
            yaw: Some(0.0),
            pitch: Some(0.0),
            ..Default::default()
        },
    );
    state.tick(0.05);
    assert_eq!(state.players[0].weapon, WeaponType::Rail);
    assert!(state.shot_results.iter().any(|s| s
        .trace
        .as_ref()
        .is_some_and(|t| t.vehicle_id == Some(1) && t.weapon == WeaponType::Flechette)));
    assert!(state.vehicles[0].state.gun_heat > 0.0);
    let traces = state.shot_results.clone();
    state.remove_player(id);
    assert!(state.vehicles[0].state.gunner.is_none());
    assert_eq!(traces[0].trace.as_ref().unwrap().vehicle_id, Some(1));
}

#[test]
fn driver_cannot_fire_handheld_or_place_devices_and_dead_seats_clear() {
    let (mut state, id) = scene();
    use_vehicle(&mut state, id);
    state.set_action(
        id,
        Action {
            fire: true,
            throw_grenade: true,
            place_mine: true,
            ..Default::default()
        },
    );
    state.tick(0.05);
    assert!(state.shot_results.is_empty());
    assert!(state.snapshot().grenades.is_empty());
    assert!(state.snapshot().mines.is_empty());
    state.players[0].hp = 0;
    assert!(state.vehicle_facts()[0].driver.is_none());
    state.tick(0.05);
    assert!(state.vehicle_seat(id).is_none());
}

#[test]
fn destruction_ejects_to_valid_ground_and_emits_shared_explosion() {
    let (mut state, id) = scene();
    use_vehicle(&mut state, id);
    state.damage_vehicle(1, 500, Some(id));
    for _ in 0..40 {
        state.tick(0.05);
    }
    assert!(state.vehicle_seat(id).is_none());
    assert_eq!(state.vehicles[0].state.burning_ticks, 0);
    assert_eq!(state.vehicles[0].state.hp, 0);
    assert!(!state.snapshot().explosions.is_empty());
    assert!(state.players[0].y >= PLAYER_FLOOR_Y);
}

#[test]
fn an_enclosed_exit_is_refused_instead_of_crossing_a_wall() {
    let (mut state, id) = scene();
    state.vehicles[0].assign(VehicleSeat::Driver, Some(id));
    state.follow_vehicle_seats();
    let mut arena = Arena {
        half: 20.0,
        solids: Vec::new(),
    };
    for (min_x, max_x, min_z, max_z) in [
        (-2.6, -2.4, -6.0, 6.0),
        (2.4, 2.6, -6.0, 6.0),
        (-6.0, 6.0, -2.6, -2.4),
        (-6.0, 6.0, 2.4, 2.6),
    ] {
        arena.solids.push(Solid {
            min_x,
            max_x,
            min_z,
            max_z,
            bottom: 0.0,
            top: 4.0,
        });
    }
    assert!(!state.exit_vehicle(0, id, &arena));
    assert_eq!(state.vehicle_seat(id), Some((0, VehicleSeat::Driver)));
    state.vehicles[0].damage(400, None);
    state.vehicles[0].state.burning_ticks = 1;
    state.tick_vehicles(0.05, &arena);
    assert_eq!(state.vehicles[0].state.burning_ticks, 0);
    assert!(state.vehicle_seat(id).is_none());
    assert!(
        state.players[0].hp <= 0,
        "destruction cannot trap a living seat indefinitely"
    );
    assert_eq!(state.explosion_results.len(), 1);
}

#[test]
fn full_seats_cannot_be_taken_by_a_third_fighter() {
    let (mut state, id) = scene();
    use_vehicle(&mut state, id);
    for n in [502, 503] {
        let pid = Uuid::from_u128(n);
        state.add_player(pid, format!("Rider{n}"), Role::Human);
        let p = state.players.last_mut().unwrap();
        p.x = 0.0;
        p.z = 1.6;
        p.y = PLAYER_FLOOR_Y;
        use_vehicle(&mut state, pid);
    }
    assert_eq!(state.vehicles[0].state.driver, Some(id));
    assert_eq!(state.vehicles[0].state.gunner, Some(Uuid::from_u128(502)));
    assert!(state.vehicle_seat(Uuid::from_u128(503)).is_none());
}

#[test]
fn abandoned_wreck_returns_only_when_its_spawn_is_clear() {
    let (mut state, id) = scene();
    state.remove_player(id);
    state.vehicles[0].state.hp = 0;
    state.vehicles[0].state.position = [12.0, 0.0, 12.0];
    state.vehicles[0].abandoned_ticks = 599;
    state.tick(0.05);
    assert_eq!(state.vehicles[0].state.hp, 400);
    assert_eq!(state.vehicles[0].state.position, [0.0; 3]);
}

#[test]
fn runover_respects_hostility_and_stops_for_allies() {
    for friendly in [false, true] {
        let (mut state, driver) = scene();
        state.config.rules =
            crate::rules::RuleSet::new(crate::protocol::GameMode::Tdm, &[], true).unwrap();
        let victim = Uuid::from_u128(509);
        state.add_player(victim, "Crossing".into(), Role::Human);
        state.vehicles[0].assign(VehicleSeat::Driver, Some(driver));
        state.vehicles[0].state.speed = 12.0;
        state.players[0].team = Some(crate::protocol::Team::Union);
        state.players[1].team = if friendly {
            Some(crate::protocol::Team::Union)
        } else {
            Some(crate::protocol::Team::Coalition)
        };
        state.players[1].x = 2.7;
        state.players[1].z = 0.0;
        state.players[1].y = PLAYER_FLOOR_Y;
        state.set_action(
            driver,
            Action {
                forward: true,
                ..Default::default()
            },
        );
        state.tick(0.05);
        if friendly {
            assert_eq!(state.players[1].hp, 100);
        } else {
            assert!(state.players[1].hp < 100);
        }
        assert!(state.vehicles[0].state.position[0] < 1.0);
    }
}

#[test]
fn driver_ack_pairs_the_selected_input_with_the_same_vehicle_snapshot_tick() {
    let (mut state, id) = scene();
    use_vehicle(&mut state, id);
    state.set_action(
        id,
        Action {
            forward: true,
            seq: Some(42),
            ..Default::default()
        },
    );
    state.tick(0.05);
    let snapshot = state.snapshot();
    assert!(snapshot.vehicles[0].speed > 0.0);
    let acks = state.input_acks();
    assert_eq!(acks.len(), 1);
    match &acks[0].1 {
        crate::protocol::ServerMessage::Ack {
            seq,
            tick,
            movement: Some(movement),
            ..
        } => {
            assert_eq!((*seq, *tick), (42, snapshot.tick));
            assert!(
                !movement.applied,
                "vehicle input must not claim ordinary pawn integration"
            );
            assert_eq!(movement.y, snapshot.players[0].y);
        }
        other => panic!("expected movement ACK, got {other:?}"),
    }
    state.set_action(
        id,
        Action {
            back: true,
            seq: Some(41),
            ..Default::default()
        },
    );
    state.tick(0.05);
    assert!(state.vehicles[0].state.speed > snapshot.vehicles[0].speed);
    assert!(matches!(
        state.input_acks()[0].1,
        crate::protocol::ServerMessage::Ack { seq: 42, .. }
    ));
}

#[test]
fn seat_switch_lock_blocks_mount_fire_until_the_advertised_tick() {
    let (mut state, id) = scene();
    use_vehicle(&mut state, id);
    state.set_action(
        id,
        Action {
            seat: Some(VehicleSeat::Gunner),
            fire: true,
            ..Default::default()
        },
    );
    state.tick(0.05);
    let ready = state.vehicles[0].state.control_ready_tick;
    assert_eq!(ready, state.tick + vehicles::SWITCH_TICKS);
    assert!(state.shot_results.is_empty());
    while state.tick + 1 < ready {
        state.tick(0.05);
        assert!(state.shot_results.is_empty());
    }
    state.tick(0.05);
    assert!(!state.shot_results.is_empty());
}

#[test]
fn boarding_requires_clear_sight_and_a_slow_vehicle() {
    let (mut state, id) = scene();
    state.vehicles[0].state.speed = vehicles::ENTRY_SPEED + 0.1;
    state.players[0].interaction_requested = true;
    let arena = state.current_arena().into_owned();
    state.vehicle_interactions(&arena);
    assert!(state.vehicle_seat(id).is_none());
    state.vehicles[0].state.speed = 0.0;
    let mut wall = arena;
    wall.solids.push(Solid {
        min_x: -5.0,
        max_x: 5.0,
        min_z: -1.2,
        max_z: -1.1,
        bottom: 0.0,
        top: 4.0,
    });
    state.vehicle_interactions(&wall);
    assert!(state.vehicle_seat(id).is_none());
}

fn island() -> (GameState, Uuid) {
    let mut state = GameState::with_map(crate::sim::MapKind::HoldfastAtoll, false);
    state.config.boss_spawn_ticks = None;
    state.config.compliance_ping_ticks = None;
    let id = Uuid::from_u128(650);
    state.add_player(id, "Island pilot".into(), Role::Human);
    state.start_round();
    (state, id)
}

#[test]
fn island_fleet_has_valid_boats_aircraft_and_jeeps() {
    let (state, _) = island();
    assert_eq!(
        state.vehicles.len(),
        6,
        "every authored fleet placement must fit the island"
    );
    assert_eq!(
        state
            .vehicles
            .iter()
            .filter(|v| v.state.kind == crate::protocol::VehicleKind::Boat)
            .count(),
        2
    );
    assert_eq!(
        state
            .vehicles
            .iter()
            .filter(|v| v.state.kind == crate::protocol::VehicleKind::LightAircraft)
            .count(),
        1
    );
    assert!(state.vehicles.iter().all(|v| v.state.validate()));
    for (index, vehicle) in state.vehicles.iter().enumerate() {
        let hull = vehicles::hull(&vehicle.state);
        for other in &state.vehicles[..index] {
            let hull_other = vehicles::hull(&other.state);
            let clearance = 1.0;
            assert!(
                hull.max_x + clearance < hull_other.min_x
                    || hull_other.max_x + clearance < hull.min_x
                    || hull.max_z + clearance < hull_other.min_z
                    || hull_other.max_z + clearance < hull.min_z,
                "fleet bodies {} and {} need at least one metre of clear approach",
                vehicle.state.id,
                other.state.id
            );
        }
    }
}

#[test]
fn boat_boards_at_dock_drives_and_exits_to_swimming_support() {
    let (mut state, id) = island();
    state.players[0].x = -59.5;
    state.players[0].z = 75.0;
    state.players[0].y = 2.2 + PLAYER_FLOOR_Y;
    use_vehicle(&mut state, id);
    assert_eq!(
        state.vehicles[state.vehicle_seat(id).unwrap().0].state.kind,
        crate::protocol::VehicleKind::Boat
    );
    state.set_action(
        id,
        Action {
            forward: true,
            ..Default::default()
        },
    );
    for _ in 0..50 {
        state.tick(0.05);
    }
    let index = state.vehicle_seat(id).unwrap().0;
    assert!(state.vehicles[index].state.position[2] > 80.0);
    assert_eq!(state.vehicles[index].state.position[1], 2.2);
    state.set_action(
        id,
        Action {
            jump: true,
            ..Default::default()
        },
    );
    for _ in 0..30 {
        state.tick(0.05);
    }
    use_vehicle(&mut state, id);
    assert!(state.vehicle_seat(id).is_none());
    assert!(state.players[0].y - PLAYER_FLOOR_Y >= 1.3 - 0.001);
}

#[test]
fn aircraft_single_seat_takes_off_and_water_crash_releases_occupant() {
    let (mut state, id) = island();
    state.players[0].x = 5.5;
    state.players[0].z = -105.0;
    state.players[0].y = 3.0 + PLAYER_FLOOR_Y;
    use_vehicle(&mut state, id);
    let index = state.vehicle_seat(id).unwrap().0;
    assert_eq!(
        state.vehicles[index].state.kind,
        crate::protocol::VehicleKind::LightAircraft
    );
    state.set_action(
        id,
        Action {
            seat: Some(VehicleSeat::Gunner),
            forward: true,
            jump: true,
            ..Default::default()
        },
    );
    for _ in 0..120 {
        state.tick(0.05);
    }
    assert_eq!(state.vehicle_seat(id), Some((index, VehicleSeat::Driver)));
    assert!(state.vehicles[index].state.position[1] > 10.0);
    assert!(state.vehicles[index].state.position[2] > -80.0);
    state.vehicles[index].state.position = [0.0, 2.3, 60.0];
    state.vehicles[index].state.speed = 0.0;
    state.vehicles[index].state.vy = -6.0;
    state.set_action(id, Action::default());
    state.tick(0.05);
    assert_eq!(state.vehicles[index].state.hp, 0);
    for _ in 0..45 {
        state.tick(0.05);
    }
    assert!(state.vehicle_seat(id).is_none());
    assert_eq!(state.vehicles[index].state.burning_ticks, 0);
}
