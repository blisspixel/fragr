use super::*;

// Death-time positions retained by the October 15 eight-client roster and
// the first candidate's five-seed comparison (last four lanes).
// These reconstruct firing lanes, not the absent full match input stream.
const EXIT_LANES: [([f32; 2], [f32; 2]); 10] = [
    ([8.812198, 52.865448], [-14.51033, 48.751648]),
    ([-13.259776, 50.65444], [1.4269636, 51.194576]),
    ([1.4269636, 51.194576], [12.223119, 50.776054]),
    ([26.206514, 0.55550545], [46.692852, 14.119595]),
    ([-2.9486177, -50.277092], [-12.214906, -50.615456]),
    ([-12.214906, -50.615456], [-2.9486177, -50.277092]),
    ([-50.500004, -13.80267], [-47.715714, 17.727997]),
    ([-46.499954, -51.773575], [-46.033867, -23.499632]),
    ([50.750847, -14.797884], [34.49992, -37.76137]),
    ([34.499485, -36.94673], [50.55891, -13.472815]),
];

#[test]
fn sector9_recorded_respawn_exit_lanes_are_screened() {
    let state = GameState::with_map(MapKind::Sector9, false);
    let arena = state.map.arena();
    let mut exposed = Vec::new();
    for (index, (shooter, victim)) in EXIT_LANES.into_iter().enumerate() {
        assert!(
            !arena.blocked_body_at(victim[0], victim[1], 0.0, 0.0),
            "lane {index}: cover cannot replace the fighter's standing space"
        );
        if threatens(
            [shooter[0], 0.0, shooter[1]],
            [victim[0], 0.0, victim[1]],
            &arena.solids,
        ) {
            exposed.push(index);
        }
    }
    assert!(
        exposed.is_empty(),
        "recorded early-death lanes still exposed: {exposed:?}"
    );
}

#[test]
fn sector9_freight_bays_keep_inner_and_service_exits_walkable() {
    let state = GameState::with_map(MapKind::Sector9, false);
    let navigation = state.map.navigation();
    for bay in 0..16 {
        let angle = bay as f32 * std::f32::consts::TAU / 16.0;
        let (x, z, _, floor) = state.map.spawn(angle);
        for scale in [0.75, 1.25] {
            let mut goal = [x * scale, floor, z * scale];
            if scale > 1.0 && matches!(bay % 8, 3 | 5) {
                // These bays are in the middle hall. Its existing x=26 wall
                // is not an exit destination; follow the same aisle outward.
                goal[0] = x;
            }
            goal[1] = state.map.arena().support_height(goal[0], goal[2], floor);
            assert!(
                !state
                    .map
                    .arena()
                    .blocked_body_at(goal[0], goal[2], goal[1], goal[1]),
                "bay {bay} exit {scale}: destination must remain standing space"
            );
            crate::navigation::tests::assert_server_walks(
                MapKind::Sector9,
                navigation,
                [x, floor, z],
                goal,
            );
        }
    }
}

#[test]
fn sector9_freight_dividers_stop_resolved_unshielded_shots() {
    for (lane, (shooter, victim)) in EXIT_LANES.into_iter().enumerate() {
        let mut state = GameState::with_map(MapKind::Sector9, false);
        state.config.boss_spawn_ticks = None;
        state.config.compliance_ping_ticks = None;
        let a = Uuid::from_u128(1);
        let b = Uuid::from_u128(2);
        state.add_player(a, "Shooter".into(), Role::Agent);
        state.add_player(b, "Leaving bay".into(), Role::Human);
        state.start_round();
        state.spawn_shields.clear();
        for (player, at) in state.players.iter_mut().zip([shooter, victim]) {
            player.x = at[0];
            player.z = at[1];
            player.y = PLAYER_FLOOR_Y;
            player.weapon = WeaponType::Rail;
        }
        state.set_action(
            a,
            Action {
                fire: true,
                look_at: Some(LookAt {
                    player_id: Some(b),
                    ..Default::default()
                }),
                ..Default::default()
            },
        );
        state.tick(0.05);
        assert_eq!(
            state.shot_results.len(),
            1,
            "lane {lane}: actual shot required"
        );
        assert!(
            !state.shot_results[0].hit,
            "lane {lane}: the freight must stop the shot"
        );
        assert_eq!(
            state.players[1].hp, 100,
            "lane {lane}: cover owns protection"
        );
    }
}

#[test]
fn sector9_north_exit_protects_the_first_steps_then_rejoins_combat() {
    let mut state = GameState::with_map(MapKind::Sector9, false);
    state.config.boss_spawn_ticks = None;
    state.config.compliance_ping_ticks = None;
    let shooter = Uuid::from_u128(1);
    let runner = Uuid::from_u128(2);
    state.add_player(shooter, "Across the bays".into(), Role::Agent);
    state.add_player(runner, "Leaving bay".into(), Role::Human);
    state.start_round();
    state.spawn_shields.clear();
    for (player, at) in state
        .players
        .iter_mut()
        .zip([[-13.259776, 50.65444], [0.0, 55.0]])
    {
        player.x = at[0];
        player.z = at[1];
        player.y = PLAYER_FLOOR_Y;
        player.weapon = WeaponType::Rail;
    }
    // Allow the next ordinary Rail cooldown after the runner clears the
    // oblique lane. The four-second sample ended one tick before that shot.
    for tick in 0..100 {
        state.set_action(
            shooter,
            Action {
                fire: true,
                look_at: Some(LookAt {
                    player_id: Some(runner),
                    ..Default::default()
                }),
                ..Default::default()
            },
        );
        state.set_action(
            runner,
            Action {
                forward: true,
                yaw: Some(-std::f32::consts::FRAC_PI_2),
                ..Default::default()
            },
        );
        state.tick(0.05);
        if tick < 40 {
            assert_eq!(
                state.players[1].hp, 100,
                "step {tick}: immediate crossfire reached the exit"
            );
        }
        if state.players[1].hp < 100 {
            break;
        }
    }
    assert!(
        state.players[1].z < 43.0,
        "ordinary forward input must leave the bay"
    );
    assert!(
        state.players[1].hp < 100,
        "leaving the freight cover must restore the contested lane"
    );
    assert!(!state.spawn_shields.contains_key(&runner));
}
