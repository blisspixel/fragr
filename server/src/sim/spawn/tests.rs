use super::*;
use crate::protocol::{GameMode, VehicleKind};
use crate::vehicles::Jeep;

#[test]
fn holdfast_tdm_hangars_have_screened_supported_and_fair_walked_exits() {
    use crate::combat::line_of_sight;
    use crate::navigation::{NavigationGoal, Navigator};
    let mut game = GameState::with_map(MapKind::HoldfastAtoll, false);
    game.config.rules = crate::rules::RuleSet::new(GameMode::Tdm, &[], false).unwrap();
    let arena = world(&game);
    let spawns: Vec<_> = (0..16)
        .map(|slot| game.spawn_at_angle(slot as f32 * 2.0 * PI / 16.0))
        .collect();
    let mut times = Vec::new();
    for spawn in &spawns {
        let from = [spawn.0, spawn.3, spawn.1];
        assert!(fixed_fits(&arena, &[], *spawn), "{spawn:?}");
        for dx in [-RADIUS, RADIUS] {
            for dz in [-RADIUS, RADIUS] {
                assert!(
                    (arena.support_height(from[0] + dx, from[2] + dz, from[1] + STEP_UP) - from[1])
                        .abs()
                        < CONTACT_EPSILON
                );
            }
        }
        let eye = [from[0], from[1] + crate::movement::EYE_HEIGHT, from[2]];
        for other in spawns
            .iter()
            .filter(|other| other.0.signum() != spawn.0.signum())
        {
            for step in [0.0, 3.0] {
                assert!(
                    !line_of_sight(
                        [eye[0], eye[1], eye[2] + step],
                        [other.0, other.3 + crate::movement::EYE_HEIGHT, other.1],
                        &arena.solids
                    ),
                    "spawn or first steps exposed: {spawn:?} to {other:?}"
                );
            }
        }
        let to = [0.0, 3.0, -60.0];
        let mut state = GameState::with_map(MapKind::HoldfastAtoll, false);
        let id = Uuid::from_u128(999);
        state.add_player(id, "Route probe".into(), Role::Human);
        state.start_round();
        state.config.time_limit_ticks = None;
        state.players[0].x = from[0];
        state.players[0].z = from[2];
        state.players[0].y = from[1] + PLAYER_FLOOR_Y;
        let mut navigator = Navigator::default();
        let mut arrived = None;
        for tick in 0..300 {
            let p = &state.players[0];
            let here = [p.x, p.y - PLAYER_FLOOR_Y, p.z];
            if (here[0] - to[0]).hypot(here[2] - to[2]) < 0.6 && (here[1] - to[1]).abs() < 0.2 {
                arrived = Some(tick as f32 * 0.05);
                break;
            }
            let walking = state.walking_arena(&arena);
            let action = navigator.steer_with_visibility(
                crate::maps::navigation(MapKind::HoldfastAtoll),
                here,
                NavigationGoal {
                    feet: to,
                    combat: false,
                },
                crate::protocol::Action {
                    forward: true,
                    ..Default::default()
                },
                tick,
                true,
                &walking.solids,
            );
            state.set_action(id, action);
            state.tick(0.05);
            state.take_events();
            assert_eq!(state.players[0].hp, 100, "the route remains on safe land");
        }
        times.push(arrived.expect("walk from hangar to shared Rail within fifteen seconds"));
    }
    for slot in 0..8 {
        assert!(
            (times[slot] - times[slot + 8]).abs() <= 0.05,
            "mirrored route {slot}: {times:?}"
        );
    }
}

#[test]
fn holdfast_forward_deployment_is_tdm_only_and_keeps_crowded_admission_safe() {
    for mode in [
        GameMode::Ffa,
        GameMode::Duel,
        GameMode::Ctf,
        GameMode::Conquest,
        GameMode::Sabotage,
    ] {
        let mut state = GameState::with_map(MapKind::HoldfastAtoll, false);
        state.config.rules = crate::rules::RuleSet::new(mode, &[], false).unwrap();
        for slot in 0..16 {
            let angle = slot as f32 * 2.0 * PI / 16.0;
            assert_eq!(
                state.spawn_at_angle(angle),
                state.map.spawn(angle),
                "{mode:?}"
            );
        }
    }
    for mutators in [
        vec![],
        vec![crate::protocol::Mutator::GoldenRail],
        vec![crate::protocol::Mutator::RailOnly],
    ] {
        let mut state = GameState::with_map(MapKind::HoldfastAtoll, false);
        state.seed(17);
        state.apply_config(crate::sim::MatchConfig {
            rules: crate::rules::RuleSet::new(GameMode::Tdm, &mutators, false).unwrap(),
            ..Default::default()
        });
        for id in 1..=16 {
            state.add_player(Uuid::from_u128(id), format!("Fighter {id}"), Role::Human);
        }
        state.start_round();
        let arena = world(&state);
        for (index, player) in state.players.iter().enumerate() {
            assert_eq!(player.respawn_timer, None);
            assert_eq!(crate::rules::spawn_side(player.x), player.team);
            assert!(player.x.abs() <= 52.0 && player.z >= -88.0 && player.z <= -80.0);
            assert!(fixed_fits(&arena, &[], point(&state, player.id)));
            for other in &state.players[index + 1..] {
                assert!((player.x - other.x).hypot(player.z - other.z) >= RADIUS * 2.0);
            }
        }
        let id = state.players[0].id;
        state.players[0].hp = 0;
        state.players[0].respawn_timer = Some(1);
        state.tick(0.05);
        assert_eq!(state.players[0].respawn_timer, None);
        assert!(state.players[0].x.abs() <= 52.0);
        assert!(fixed_fits(&world(&state), &[], point(&state, id)));
    }
}

#[test]
fn established_stair_edge_bays_keep_their_step_clearance() {
    let game = GameState::with_map(MapKind::Directive17, false);
    for index in 0..game.map.spawn_slots() {
        let spawn = game
            .map
            .spawn(index as f32 * 2.0 * PI / game.map.spawn_slots() as f32);
        assert!(
            fixed_fits(&world(&game), &[], spawn),
            "slot {index}: {spawn:?}"
        );
    }
}

fn fixture() -> GameState {
    let value = serde_json::json!({
        "version": 1, "map_id": 1908, "name": "Spawn safety fixture",
        "half_extent": 24, "ground": "concrete", "solids": [],
        "spawns": [
            {"id":"east_south", "feet":[10,0,-6], "yaw":0},
            {"id":"east_north", "feet":[10,0,6], "yaw":0},
            {"id":"west_south", "feet":[-10,0,-6], "yaw":0},
            {"id":"west_north", "feet":[-10,0,6], "yaw":0}
        ], "landmarks": [{"id":"middle", "feet":[0,0,0]}]
    });
    let map =
        crate::maps::AuthoredMap::read(serde_json::to_vec(&value).unwrap().as_slice()).unwrap();
    let mut game = GameState::with_authored_map(map);
    game.config.rules = crate::rules::RuleSet::new(GameMode::Tdm, &[], false).unwrap();
    game.seed(1908);
    game
}

fn world(game: &GameState) -> Arena {
    game.walking_arena(&game.current_arena()).into_owned()
}

fn point(game: &GameState, id: Uuid) -> Spawn {
    let player = game.players.iter().find(|p| p.id == id).unwrap();
    (player.x, player.z, player.yaw, player.y - PLAYER_FLOOR_Y)
}

fn obstruct_east(game: &mut GameState) {
    for z in [-6.0, 6.0] {
        for (dx, dz) in [(-3.0, -3.0), (-3.0, 3.0), (3.0, -3.0), (3.0, 3.0)] {
            game.vehicles.push(Jeep::of_kind(
                game.vehicles.len() as u32 + 1,
                VehicleKind::LightAircraft,
                [10.0 + dx, 0.0, z + dz],
                0.0,
            ));
        }
    }
}

#[test]
fn initial_admission_and_respawn_avoid_every_kind_and_retained_hull_state() {
    for kind in [
        VehicleKind::Jeep,
        VehicleKind::Boat,
        VehicleKind::LightAircraft,
    ] {
        for (hp, burning_ticks) in [(400, 0), (0, 40), (0, 0)] {
            let mut game = fixture();
            game.config.rules = crate::rules::RuleSet::default();
            let original = game.map.spawn(0.0);
            let mut vehicle = Jeep::of_kind(1, kind, [original.0, original.3, original.1], 0.0);
            vehicle.state.hp = hp;
            vehicle.state.burning_ticks = burning_ticks;
            game.vehicles.push(vehicle);
            assert!(
                !fits(&world(&game), original),
                "legacy initial point intersects {kind:?}"
            );
            let id = Uuid::from_u128(1);
            game.add_player(id, "Arrival".into(), Role::Human);
            assert_eq!(game.players[0].respawn_timer, None);
            assert!(
                fits(&world(&game), point(&game, id)),
                "admission overlaps {kind:?} {hp}/{burning_ticks}"
            );
            let respawn = point(&game, id);
            game.vehicles.push(Jeep::of_kind(
                2,
                kind,
                [respawn.0, respawn.3, respawn.1],
                0.0,
            ));
            game.players[0].hp = 0;
            game.players[0].respawn_timer = Some(1);
            game.tick(0.05);
            assert_eq!(game.players[0].respawn_timer, None);
            assert!(
                fits(&world(&game), point(&game, id)),
                "respawn overlaps {kind:?} {hp}/{burning_ticks}"
            );
        }
    }
}

#[test]
fn clear_fixed_bays_precede_offsets_and_offsets_keep_the_same_side() {
    let mut game = fixture();
    game.vehicles.push(Jeep::new(1, [10.0, 0.0, -6.0], 0.0));
    let id = Uuid::from_u128(1);
    assert_eq!(
        game.select_spawn(id, Some(Team::Coalition), None),
        Some((10.0, 6.0, 0.0, 0.0))
    );
    game.vehicles.push(Jeep::new(2, [10.0, 0.0, 6.0], 0.0));
    let result = game.select_spawn(id, Some(Team::Coalition), None).unwrap();
    assert!(fits(&world(&game), result));
    assert_eq!(crate::rules::spawn_side(result.0), Some(Team::Coalition));
    assert!([-6.0, 6.0]
        .into_iter()
        .any(|z| (result.0 - 10.0).hypot(result.1 - z) <= 6.01));
    assert_ne!(result, (10.0, -6.0, 0.0, 0.0));
    assert_ne!(result, (10.0, 6.0, 0.0, 0.0));
}

#[test]
fn completely_obstructed_side_waits_and_then_retries_without_duplicate_events() {
    let mut game = fixture();
    obstruct_east(&mut game);
    assert!(game
        .select_spawn(Uuid::nil(), Some(Team::Coalition), None)
        .is_none());
    assert!(
        game.select_spawn(Uuid::nil(), Some(Team::Union), None)
            .is_some(),
        "opposite side is still open"
    );
    let id = Uuid::from_u128(1);
    game.add_player(id, "Waiting".into(), Role::Human);
    assert_eq!(game.players[0].team, Some(Team::Coalition));
    assert_eq!(game.players[0].hp, 0);
    assert_eq!(game.players[0].respawn_timer, Some(1));
    assert!(game.snapshot().players.is_empty());
    game.arm_joined_magazines(id);
    let inventory = game.players[0]
        .inventory
        .state(id, game.players[0].weapon, 0)
        .unwrap();
    game.players[0].last_received_seq = Some(700);
    game.players[0].last_input_seq = Some(699);
    game.scores.insert(id, 8);
    for _ in 0..3 {
        game.tick(0.05);
        assert_eq!(game.players[0].respawn_timer, Some(1));
        assert_eq!(game.players[0].hp, 0);
        assert!(!game.contact_eligible(&game.players[0]));
        assert!(!game.spawn_shields.contains_key(&id));
        assert!(!game
            .events
            .iter()
            .any(|event| matches!(event, GameEvent::Respawn { .. })));
    }
    assert_eq!(
        game.players[0]
            .inventory
            .state(id, game.players[0].weapon, 0)
            .unwrap(),
        inventory
    );
    assert_eq!(game.players[0].last_received_seq, Some(700));
    assert_eq!(game.players[0].last_input_seq, Some(699));
    assert_eq!(game.scores[&id], 8);
    game.vehicles.clear();
    game.tick(0.05);
    assert_eq!(game.players[0].respawn_timer, None);
    assert_eq!(game.players[0].hp, PLAYER_MAX_HP);
    assert!(game.contact_eligible(&game.players[0]));
    assert_eq!(game.snapshot().players.len(), 1);
    assert_eq!(
        game.events
            .iter()
            .filter(|event| matches!(event, GameEvent::Respawn { .. }))
            .count(),
        1
    );
    assert!(game.spawn_shields.contains_key(&id));
    assert_eq!(game.players[0].last_received_seq, Some(700));
    assert_eq!(game.players[0].last_input_seq, Some(699));
    assert_eq!(game.scores[&id], 8);
}

#[test]
fn a_waiting_actor_cannot_board_drive_or_fire_even_with_retained_positive_health() {
    for role in [Role::Human, Role::Agent] {
        let mut game = fixture();
        let id = Uuid::from_u128(1);
        game.add_player(id, "Waiting beside jeep".into(), role);
        game.vehicles.push(Jeep::new(1, [0.0; 3], 0.0));
        let player = &mut game.players[0];
        player.x = 0.0;
        player.y = PLAYER_FLOOR_Y;
        player.z = -1.75;
        player.hp = 100;
        player.respawn_timer = Some(1);
        game.set_action(
            id,
            Action {
                interact: true,
                forward: true,
                fire: true,
                seat: Some(crate::protocol::VehicleSeat::Driver),
                seq: (role == Role::Human).then_some(700),
                ..Default::default()
            },
        );
        game.tick(0.05);
        assert!(
            game.vehicle_seat(id).is_none(),
            "{role:?} boarded during the waiting tick"
        );
        assert_eq!(game.vehicles[0].state.position, [0.0; 3]);
        assert_eq!(game.vehicles[0].state.speed, 0.0);
        assert!(game.shot_results.is_empty());
        assert_eq!(
            game.players[0].respawn_timer, None,
            "ordinary placement still succeeds afterward"
        );
        if role == Role::Human {
            assert_eq!(game.players[0].last_received_seq, Some(700));
        }
    }
}

#[test]
fn overhead_aircraft_leaves_ground_spawn_available() {
    let mut game = fixture();
    game.vehicles.push(Jeep::of_kind(
        1,
        VehicleKind::LightAircraft,
        [10.0, 8.0, -6.0],
        0.0,
    ));
    let spawn = game.select_spawn(Uuid::nil(), None, Some(0.0)).unwrap();
    assert_eq!(spawn, game.map.spawn(0.0));
}

#[test]
fn live_hulls_change_cover_ranking_without_becoming_hostile_bodies() {
    let mut game = fixture();
    game.add_player(Uuid::from_u128(1), "Threat".into(), Role::Human);
    game.players[0].team = Some(Team::Union);
    game.players[0].x = 0.0;
    game.players[0].z = 0.0;
    game.players[0].ducking = true;
    let id = Uuid::from_u128(2);
    let plain = game.select_spawn(id, Some(Team::Coalition), None).unwrap();
    assert_eq!(plain.1, -6.0);
    game.vehicles.push(Jeep::new(1, [5.0, 0.0, 3.0], 0.0));
    let covered = game.select_spawn(id, Some(Team::Coalition), None).unwrap();
    assert_eq!(covered.1, 6.0, "a real hull screens the other bay");
    let eye = [0.0, crate::movement::DUCK_EYE_HEIGHT, 0.0];
    for height in [crate::combat::FIGHTER_HEIGHT * 0.5, EYE_HEIGHT] {
        assert!(!crate::combat::line_of_sight(
            eye,
            [covered.0, height, covered.1],
            &world(&game).solids
        ));
    }
}

#[test]
fn inactive_bodies_and_separate_vertical_spans_do_not_occupy_a_bay() {
    let mut game = fixture();
    for id in [1, 2] {
        game.add_player(Uuid::from_u128(id), format!("Body {id}"), Role::Human);
    }
    for player in &mut game.players {
        player.team = Some(Team::Coalition);
        player.x = 10.0;
    }
    game.players[0].z = -6.0;
    game.players[0].y = 10.0 + PLAYER_FLOOR_Y;
    game.players[1].z = 6.0;
    assert_eq!(
        game.select_spawn(Uuid::nil(), Some(Team::Coalition), None)
            .unwrap()
            .1,
        -6.0
    );
    game.players[0].y = PLAYER_FLOOR_Y;
    for excluded in 0..4 {
        game.players[0].hp = if excluded == 0 { 0 } else { 100 };
        game.players[0].detached = excluded == 1;
        game.players[0].eliminated = excluded == 2;
        game.players[0].role = if excluded == 3 {
            Role::Spectator
        } else {
            Role::Human
        };
        assert_eq!(
            game.select_spawn(Uuid::nil(), Some(Team::Coalition), None)
                .unwrap()
                .1,
            -6.0
        );
    }
}

#[test]
fn unobstructed_openings_preserve_seeded_placement_and_rng_progress() {
    for team in [None, Some(Team::Coalition), Some(Team::Union)] {
        let mut game = fixture();
        let mut expected = fixture();
        let selected = game.select_spawn(Uuid::nil(), team, None).unwrap();
        let old = if let Some(team) = team {
            let choices: Vec<_> = (0..expected.map.spawn_slots())
                .map(|index| {
                    expected
                        .map
                        .spawn(index as f32 * 2.0 * PI / expected.map.spawn_slots() as f32)
                })
                .filter(|point| crate::rules::spawn_side(point.0) == Some(team))
                .collect();
            choices[(expected.next_u64() % choices.len() as u64) as usize]
        } else {
            let angle = expected.next_f32() * 2.0 * PI;
            expected.map.spawn(angle)
        };
        assert_eq!(selected, old);
        assert_eq!(game.next_u64(), expected.next_u64());
    }
    let mut game = fixture();
    let mut expected = fixture();
    assert_eq!(
        game.select_spawn(Uuid::nil(), None, Some(0.0)),
        Some(expected.map.spawn(0.0))
    );
    assert_eq!(game.next_u64(), expected.next_u64());
}
