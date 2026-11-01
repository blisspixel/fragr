use super::*;
use crate::protocol::{LookAt, Role, WeaponType};
use crate::sim::{GameState, MapKind};

#[test]
fn gulch_corners_recover_with_coalesced_snapshot_observations() {
    for feet in [[73.28353, 0.0, 21.406975], [54.56577, 0.0, 37.4444]] {
        for cadence in [1, 2, 4] {
            let me = Uuid::from_u128(1);
            let enemy = Uuid::from_u128(2);
            let mut state = GameState::with_map(MapKind::ReclamationGulch, false);
            state.seed(42);
            state.add_player(me, "corner mover".into(), Role::Agent);
            state.add_player(enemy, "visible target".into(), Role::Human);
            state.round_state = crate::sim::RoundState::Active;
            for player in &mut state.players {
                player.x = feet[0];
                player.y = PLAYER_FLOOR_Y;
                player.z = feet[2] - if player.id == enemy { 15.0 } else { 0.0 };
                player.yaw = -std::f32::consts::FRAC_PI_2;
                player.hp = 10_000;
            }
            let mut navigator = Navigator::default();
            let mut stationary = 0;
            let mut longest = 0;
            let intent = Action {
                back: true,
                fire: true,
                pitch: Some(0.125),
                weapon_swap: Some(WeaponType::Rail),
                look_at: Some(LookAt {
                    player_id: Some(enemy),
                    ..Default::default()
                }),
                ..Default::default()
            };
            for tick in 0..120 {
                if tick % cadence == 0 {
                    let snapshot = state.snapshot();
                    let mut wanted = intent.clone();
                    wanted.seq = Some(tick + 1);
                    let action = navigator.steer_snapshot(
                        state.map.navigation(),
                        me,
                        &snapshot,
                        wanted.clone(),
                    );
                    assert_eq!(action.look_at, wanted.look_at);
                    assert_eq!(action.fire, wanted.fire);
                    assert_eq!(action.pitch, wanted.pitch);
                    assert_eq!(action.weapon_swap, wanted.weapon_swap);
                    assert_eq!(action.seq, wanted.seq);
                    state.set_action(me, action);
                }
                let before = [state.players[0].x, state.players[0].z];
                // The server continues applying the last ordinary input between
                // observations, just as it does for a reading wire client.
                state.tick(0.05);
                let mover = &state.players[0];
                let moved = (mover.x - before[0]).hypot(mover.z - before[1]);
                stationary = if moved < 0.01 { stationary + 1 } else { 0 };
                longest = longest.max(stationary);
                let feet_y = mover.y - PLAYER_FLOOR_Y;
                let support =
                    state
                        .current_arena()
                        .support_height(mover.x, mover.z, feet_y + 0.001);
                assert!(
                    (feet_y - support).abs() < 0.001,
                    "escape must stay supported"
                );
                assert_eq!(mover.vy, 0.0, "ordinary escape must not jump or fall");
                assert!(state.current_arena().solids.iter().all(|solid| {
                    !solid.covers(mover.x, mover.z)
                        || solid.top <= mover.y - PLAYER_FLOOR_Y + STEP_UP
                }));
            }
            let mover = &state.players[0];
            let progress = (mover.x - feet[0]).hypot(mover.z - feet[2]);
            eprintln!(
                "gulch feet={feet:?} observation_cadence={cadence} longest_stationary={longest} progress={progress:.3}"
            );
            assert!(longest <= 32, "cadence {cadence} stalled at {feet:?}");
            assert!(
                progress > 4.0,
                "cadence {cadence} needs real escape at {feet:?}"
            );
        }
    }
}

#[test]
fn stationary_recovery_requires_fresh_bounded_observations() {
    let me = Uuid::from_u128(1);
    let mut state = GameState::with_map(MapKind::ReclamationGulch, false);
    state.add_player(me, "stationary observer".into(), Role::Agent);
    state.players[0].x = 73.28353;
    state.players[0].z = 21.406975;
    state.players[0].y = PLAYER_FLOOR_Y;
    state.players[0].yaw = -std::f32::consts::FRAC_PI_2;
    let bodies = Navigator::snapshot_bodies(&state.snapshot());
    let mut navigator = Navigator::default();
    let intent = Action {
        back: true,
        ..Default::default()
    };
    let observe = |navigator: &mut Navigator, tick| {
        navigator.avoid_bodies(&state.current_arena(), me, &bodies, intent.clone(), tick)
    };
    for tick in 1..=6 {
        observe(&mut navigator, tick);
    }
    assert_eq!(navigator.avoidance_stalled, 5);
    observe(&mut navigator, 6);
    assert_eq!(
        navigator.avoidance_stalled, 5,
        "duplicate is not fresh evidence"
    );
    observe(&mut navigator, 20);
    assert_eq!(navigator.avoidance_stalled, 0, "a stale gap starts over");
    observe(&mut navigator, 18);
    assert_eq!(navigator.avoidance_stalled, 0, "reversed time starts over");
    for tick in 19..=23 {
        observe(&mut navigator, tick);
    }
    assert!(navigator.avoidance_motion.is_none());
    observe(&mut navigator, 24);
    assert_eq!(navigator.avoidance_stalled, 6);
    assert!(navigator.avoidance_motion.is_some());
    for tick in (26..50).step_by(2) {
        let idle =
            navigator.avoid_bodies(&state.current_arena(), me, &bodies, Action::default(), tick);
        assert!(!(idle.forward || idle.back || idle.left || idle.right));
        assert_eq!(navigator.avoidance_stalled, 0);
        assert!(navigator.avoidance_motion.is_none());
    }
}

/// Two bodies pushing into each other on open ground: after a second of
/// observed immobility only the later id yields, backing away from the
/// earlier one for a short lease, so the pair cannot stay wedged.
#[test]
fn wedged_bodies_break_the_tie_by_id_and_the_later_one_backs_away() {
    let arena = crate::movement::Arena {
        half: 40.0,
        solids: Vec::new(),
    };
    let body = |key: Uuid, x: f32, yaw: f32| crate::movement::contact::ContactBody {
        key: key.to_string(),
        from: crate::movement::MoveState {
            x,
            y: 0.0,
            z: 0.0,
            vx: 0.0,
            vz: 0.0,
            vy: 0.0,
            yaw,
        },
        proposed: crate::movement::MoveState {
            x,
            y: 0.0,
            z: 0.0,
            vx: 0.0,
            vz: 0.0,
            vy: 0.0,
            yaw,
        },
        height: FIGHTER_HEIGHT,
        radius: crate::movement::RADIUS,
        jump: false,
    };
    let (early, late) = (Uuid::from_u128(1), Uuid::from_u128(2));
    // Face to face, touching, each walking into the other.
    let bodies = [body(early, 0.0, 0.0), body(late, 1.0, std::f32::consts::PI)];
    let walk = |yaw: f32| Action {
        forward: true,
        yaw: Some(yaw),
        ..Default::default()
    };
    let mut earlier = Navigator::default();
    let mut later = Navigator::default();
    let mut yielded = None;
    for tick in 1..=YIELD_STALL_TICKS as u64 + 2 {
        let first = earlier.avoid_bodies(&arena, early, &bodies, walk(0.0), tick);
        let second = later.avoid_bodies(&arena, late, &bodies, walk(std::f32::consts::PI), tick);
        assert!(
            !first.back,
            "the earlier id never yields at tick {tick}: {first:?}"
        );
        if later.avoidance_stalled < YIELD_STALL_TICKS {
            assert!(!second.back, "no yield before a second of contact");
        } else if yielded.is_none() {
            yielded = Some((tick, second));
        }
    }
    let (tick, second) = yielded.expect("the later id yields once wedged");
    // Facing the earlier body, backing away is the yield.
    assert!(second.back && !second.forward, "{second:?}");
    assert_eq!(later.avoidance_until, tick + YIELD_LEASE_TICKS);
    // A body with no earlier neighbour in contact keeps its own choice.
    let mut alone = Navigator::default();
    let far = [body(early, 0.0, 0.0), body(late, 5.0, std::f32::consts::PI)];
    for tick in 1..=YIELD_STALL_TICKS as u64 + 2 {
        let action = alone.avoid_bodies(&arena, late, &far, walk(std::f32::consts::PI), tick);
        assert!(!action.back, "nothing to yield to at tick {tick}");
    }
}
