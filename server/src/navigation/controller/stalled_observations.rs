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
