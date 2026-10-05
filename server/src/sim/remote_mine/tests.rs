use super::*;
use crate::movement::Solid;

fn world() -> Arena {
    Arena {
        half: 20.0,
        solids: vec![Solid {
            min_x: 2.0,
            max_x: 2.2,
            min_z: -6.0,
            max_z: 6.0,
            bottom: 0.0,
            top: 4.0,
        }],
    }
}

fn launch(arena: &Arena, id: u32, owner: u128) -> RemoteMine {
    RemoteMine::launch(
        id,
        Uuid::from_u128(owner),
        [0.0, 1.6, 0.0],
        [0.0, 0.0],
        0,
        arena,
    )
    .unwrap()
}

fn stuck(charge: &mut RemoteMine, arena: &Arena) -> u64 {
    for tick in 1..FLIGHT_TICKS {
        assert_eq!(charge.advance(tick, 0.05, arena).unwrap(), RemoteStep::Live);
        charge.state().validate(tick).unwrap();
        if charge.state().phase == RemoteMinePhase::Arming {
            return tick;
        }
    }
    panic!("charge did not find an actual surface");
}

fn armed(charge: &mut RemoteMine, arena: &Arena) -> u64 {
    let contact = stuck(charge, arena);
    for tick in contact + 1..=contact + ARMING_TICKS {
        assert_eq!(charge.advance(tick, 0.05, arena).unwrap(), RemoteStep::Live);
        if tick < contact + ARMING_TICKS {
            assert_eq!(charge.state().phase, RemoteMinePhase::Arming);
        }
    }
    assert_eq!(charge.state().phase, RemoteMinePhase::Armed);
    contact + ARMING_TICKS
}

#[test]
fn remote_charge_uses_actual_swept_wall_floor_and_ceiling_contact() {
    let mut arena = world();
    let mut wall = launch(&arena, 1, 1);
    let contact = stuck(&mut wall, &arena);
    assert_eq!(wall.state().normal, [-1.0, 0.0, 0.0]);
    assert!(wall.state().position[0] < 2.0 - grenade::RADIUS + 0.01);
    assert!(grenade::clear_sphere(wall.state().position, &arena));
    assert_eq!(wall.state().phase_ends, contact + ARMING_TICKS);

    let mut floor = RemoteMine::launch(
        2,
        Uuid::from_u128(1),
        [0.0, 1.6, 0.0],
        [0.0, -1.2],
        0,
        &arena,
    )
    .unwrap();
    stuck(&mut floor, &arena);
    assert_eq!(floor.state().normal, [0.0, 1.0, 0.0]);
    assert!(floor.state().position[1] >= grenade::RADIUS);
    assert!(grenade::clear_sphere(floor.state().position, &arena));

    arena.solids.push(Solid {
        min_x: -10.0,
        max_x: -4.0,
        min_z: -6.0,
        max_z: 6.0,
        bottom: 2.0,
        top: 2.2,
    });
    let mut ceiling = RemoteMine::launch(
        3,
        Uuid::from_u128(1),
        [-7.0, 1.6, 0.0],
        [0.0, 1.2],
        0,
        &arena,
    )
    .unwrap();
    stuck(&mut ceiling, &arena);
    assert_eq!(ceiling.state().normal, [0.0, -1.0, 0.0]);
    assert!(ceiling.state().position[1] < 2.0 - grenade::RADIUS);
    assert!(grenade::clear_sphere(ceiling.state().position, &arena));
}

#[test]
fn remote_charge_refuses_early_commands_and_never_queues_them() {
    let arena = world();
    let mut charge = launch(&arena, 1, 1);
    assert!(!charge.trigger(0).unwrap());
    let contact = stuck(&mut charge, &arena);
    assert!(!charge.trigger(contact).unwrap());
    for tick in contact + 1..contact + ARMING_TICKS {
        charge.advance(tick, 0.05, &arena).unwrap();
        assert!(!charge.trigger(tick).unwrap());
    }
    let ready = contact + ARMING_TICKS;
    charge.advance(ready, 0.05, &arena).unwrap();
    let position = charge.state().position;
    for tick in ready + 1..ready + 200 {
        assert_eq!(
            charge.advance(tick, 0.05, &arena).unwrap(),
            RemoteStep::Live
        );
        assert_eq!(charge.state().phase, RemoteMinePhase::Armed);
        assert_eq!(charge.state().position, position);
    }
    // No automatic proximity, expiry or queued command can change an armed
    // device. A new explicit command is required after it becomes ready.
    assert!(charge.trigger(ready + 200).unwrap());
    let deadline = charge.state().phase_ends;
    assert_eq!(deadline, ready + 200 + TRIGGER_TICKS);
    assert!(!charge.trigger(ready + 201).unwrap());
    assert_eq!(charge.state().phase_ends, deadline);
    for tick in ready + 200..deadline {
        assert_eq!(
            charge.advance(tick, 0.05, &arena).unwrap(),
            RemoteStep::Live
        );
    }
    assert_eq!(
        charge.advance(deadline, 0.05, &arena).unwrap(),
        RemoteStep::Detonate
    );
    assert_eq!(
        charge.advance(deadline, 0.05, &arena).unwrap(),
        RemoteStep::Removed
    );
    assert_eq!(
        charge.advance(deadline + 1, 0.05, &arena).unwrap(),
        RemoteStep::Removed
    );
    assert!(!charge.trigger(deadline + 1).unwrap());
}

#[test]
fn remote_owner_trigger_commits_only_currently_armed_owned_charges() {
    let arena = world();
    let mut charges = vec![
        launch(&arena, 1, 1),
        launch(&arena, 2, 1),
        launch(&arena, 3, 2),
    ];
    let ready = armed(&mut charges[0], &arena);
    assert_eq!(armed(&mut charges[1], &arena), ready);
    assert_eq!(armed(&mut charges[2], &arena), ready);
    charges.push(
        RemoteMine::launch(
            4,
            Uuid::from_u128(1),
            [0.0, 1.6, 0.0],
            [0.0, 0.0],
            ready,
            &arena,
        )
        .unwrap(),
    );
    let mut arming_charge = launch(&arena, 5, 1);
    stuck(&mut arming_charge, &arena);
    charges.push(arming_charge);
    assert_eq!(
        trigger_owned(&mut charges, Uuid::from_u128(1), ready).unwrap(),
        2
    );
    assert_eq!(charges[0].state().phase, RemoteMinePhase::Triggered);
    assert_eq!(charges[1].state().phase, RemoteMinePhase::Triggered);
    assert_eq!(charges[2].state().phase, RemoteMinePhase::Armed);
    assert_eq!(charges[3].state().phase, RemoteMinePhase::Flying);
    assert_eq!(charges[4].state().phase, RemoteMinePhase::Arming);
    assert_eq!(
        trigger_owned(&mut charges, Uuid::from_u128(1), ready).unwrap(),
        0
    );
}

#[test]
fn remote_flight_is_bounded_and_bad_launch_or_tick_preserves_state() {
    let arena = Arena {
        half: 20.0,
        solids: vec![],
    };
    for (id, origin, facing) in [
        (0, [0.0, 1.6, 0.0], [0.0, 0.0]),
        (1, [0.0, 0.0, 0.0], [0.0, 0.0]),
        (1, [20.0, 1.6, 0.0], [0.0, 0.0]),
        (1, [0.0, 1.6, 0.0], [f32::NAN, 0.0]),
        (1, [0.0, 1.6, 0.0], [0.0, std::f32::consts::PI]),
    ] {
        assert!(RemoteMine::launch(id, Uuid::from_u128(1), origin, facing, 0, &arena).is_err());
    }
    assert!(RemoteMine::launch(
        1,
        Uuid::from_u128(1),
        [0.0, 1.6, 0.0],
        [0.0, 0.0],
        0,
        &world()
    )
    .is_ok());
    let mut charge = RemoteMine::launch(
        1,
        Uuid::from_u128(1),
        [0.0, 10.0, 0.0],
        [0.0, 0.0],
        0,
        &arena,
    )
    .unwrap();
    let original = charge.state().clone();
    for dt in [f32::NAN, -1.0, 0.0] {
        assert!(charge.advance(1, dt, &arena).is_err());
        assert_eq!(charge.state(), &original);
    }
    assert_eq!(charge.advance(0, 0.05, &arena).unwrap(), RemoteStep::Live);
    assert_eq!(charge.state(), &original);
    charge.advance(1, 0.05, &arena).unwrap();
    let one = charge.state().clone();
    assert!(charge.advance(0, 0.05, &arena).is_err());
    assert!(charge.trigger(0).is_err());
    assert_eq!(charge.state(), &one);
    assert_eq!(
        charge.advance(FLIGHT_TICKS, 0.05, &arena).unwrap(),
        RemoteStep::Expired
    );
    assert_eq!(
        charge.advance(FLIGHT_TICKS + 1, 0.05, &arena).unwrap(),
        RemoteStep::Removed
    );
}

#[test]
fn remote_multi_charge_command_rejects_bad_clock_without_partial_commit() {
    let arena = world();
    let mut a = launch(&arena, 1, 1);
    let ready = armed(&mut a, &arena);
    let mut b = launch(&arena, 2, 1);
    armed(&mut b, &arena);
    b.advance(ready + 1, 0.05, &arena).unwrap();
    let mut charges = vec![a, b];
    assert!(trigger_owned(&mut charges, Uuid::from_u128(1), ready).is_err());
    assert!(charges
        .iter()
        .all(|c| c.state().phase == RemoteMinePhase::Armed));
    let max = (1_u64 << 53) - 1;
    assert!(trigger_owned(&mut charges, Uuid::from_u128(1), max).is_err());
    assert!(charges
        .iter()
        .all(|c| c.state().phase == RemoteMinePhase::Armed));
}

#[test]
fn remote_contact_overflow_is_atomic_and_hitch_delta_is_bounded() {
    let arena = world();
    let max = (1_u64 << 53) - 1;
    let mut charge = RemoteMine::launch(
        1,
        Uuid::from_u128(1),
        [1.8, 1.6, 0.0],
        [0.0, 0.0],
        max - 1,
        &arena,
    )
    .unwrap();
    let before = charge.state().clone();
    // Actual wall contact would start an arming window beyond the supported
    // wire clock. Reject the whole update without a half-stuck flying state.
    assert!(charge.advance(max, 0.05, &arena).is_err());
    assert_eq!(charge.state(), &before);
    assert!(charge.advance(max, 0.05, &arena).is_err());
    assert_eq!(charge.state(), &before);

    let mut normal = launch(&arena, 2, 1);
    let mut hitch = normal.clone();
    normal.advance(1, 0.05, &arena).unwrap();
    hitch.advance(1, 10.0, &arena).unwrap();
    assert_eq!(normal.state(), hitch.state());
}
