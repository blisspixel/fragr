use super::*;
use crate::movement::Solid;
use crate::protocol::Action;

fn arena(solids: Vec<Solid>) -> Arena {
    Arena { half: 20.0, solids }
}

fn wall(x: f32) -> Solid {
    Solid {
        min_x: x,
        max_x: x + 0.2,
        min_z: -6.0,
        max_z: 6.0,
        bottom: 0.0,
        top: 4.0,
    }
}

fn flying(position: [f32; 3], velocity: [f32; 3]) -> Mine {
    Mine {
        id: 1,
        owner_id: Uuid::from_u128(1),
        position,
        velocity,
        normal: [0.0; 3],
        phase: MinePhase::Flying,
        phase_started: 0,
        phase_ends: 0,
    }
}

/// Two participants on an open authored floor, with an optional wall at x = 3.
fn combat(walled: bool) -> (GameState, Uuid, Uuid) {
    let solids = if walled {
        serde_json::json!([{"id":"wall","min":[3,0,-6],"max":[3.2,4,6],"surface":"concrete"}])
    } else {
        serde_json::json!([])
    };
    let map = crate::maps::AuthoredMap::read(
        serde_json::to_vec(&serde_json::json!({
            "version":1,"map_id":1099,"name":"Mine fixture","half_extent":20,
            "ground":"concrete","equipment":"discovery","solids":solids,
            "spawns":[{"id":"entry","feet":[0,0,-6],"yaw":0}],
            "landmarks":[{"id":"exit","feet":[0,0,10]}]
        }))
        .unwrap()
        .as_slice(),
    )
    .unwrap();
    let mut state = GameState::with_authored_map(map);
    state.seed(42);
    let a = Uuid::from_u128(1);
    let b = Uuid::from_u128(2);
    state.add_player(a, "Placer".into(), crate::protocol::Role::Human);
    state.add_player(b, "Target".into(), crate::protocol::Role::Agent);
    for (i, player) in state.players.iter_mut().enumerate() {
        player.x = 0.5 + i as f32 * 14.0;
        player.z = 0.0;
        player.y = PLAYER_FLOOR_Y;
        player.yaw = 0.0;
        player.pitch = 0.0;
    }
    state.players[0].inventory.grant_mines(4);
    (state, a, b)
}

fn place(state: &mut GameState, owner: Uuid) {
    state.set_action(
        owner,
        Action {
            place_mine: true,
            ..Default::default()
        },
    );
    state.tick(0.05);
    state.set_action(owner, Action::default());
}

/// Tick until the newest mine leaves flight, returning ticks spent.
fn until_stuck(state: &mut GameState) -> u32 {
    for spent in 1..=FLIGHT_TICKS as u32 {
        state.tick(0.05);
        if state
            .mines
            .last()
            .is_some_and(|m| m.phase != MinePhase::Flying)
        {
            return spent;
        }
    }
    panic!("mine never stuck");
}

#[test]
fn flight_sticks_to_wall_floor_and_ceiling_with_their_normals() {
    let world = arena(vec![
        wall(2.0),
        Solid {
            min_x: -10.0,
            max_x: -4.0,
            min_z: -6.0,
            max_z: 6.0,
            bottom: 3.0,
            top: 3.2,
        },
    ]);
    let mut on_wall = flying([0.0, 1.6, 0.0], [8.0, 2.0, 0.0]);
    let normal = (0..20)
        .find_map(|_| fly(&mut on_wall, 0.05, &world))
        .unwrap();
    assert_eq!(normal, [-1.0, 0.0, 0.0]);
    assert!(on_wall.position[0] < 2.0 - grenade::RADIUS + 0.01);
    assert!(grenade::clear_sphere(on_wall.position, &world));
    let mut on_floor = flying([0.0, 1.6, 0.0], [0.0, -8.0, 0.0]);
    assert_eq!(
        (0..20).find_map(|_| fly(&mut on_floor, 0.05, &world)),
        Some([0.0, 1.0, 0.0])
    );
    assert!(on_floor.position[1] >= grenade::RADIUS);
    let mut on_ceiling = flying([-7.0, 1.6, 0.0], [0.0, 30.0, 0.0]);
    assert_eq!(
        (0..20).find_map(|_| fly(&mut on_ceiling, 0.05, &world)),
        Some([0.0, -1.0, 0.0])
    );
    let still = on_ceiling.position;
    assert_eq!(fly(&mut on_ceiling, f32::NAN, &world), None);
    assert_eq!(fly(&mut on_ceiling, -1.0, &world), None);
    assert_eq!(on_ceiling.position, still);
}

#[test]
fn arming_is_exact_and_a_body_cannot_trip_it_before_it_is_live() {
    let (mut state, owner, target) = combat(true);
    place(&mut state, owner);
    assert_eq!(state.players[0].inventory.mines(), 3);
    assert_eq!(state.mines.len(), 1);
    assert_eq!(state.mines[0].phase, MinePhase::Flying);
    until_stuck(&mut state);
    let mine = &state.mines[0];
    assert_eq!(mine.phase, MinePhase::Arming);
    assert_eq!(mine.normal, [-1.0, 0.0, 0.0]);
    assert_eq!(mine.phase_ends - mine.phase_started, ARMING_TICKS);
    let position = mine.position;
    // The target stands right on the mine while it arms: nothing happens.
    let index = state.players.iter().position(|p| p.id == target).unwrap();
    state.players[index].x = position[0] - 1.0;
    state.players[index].z = position[2];
    let mut arming = 0;
    while state.mines[0].phase == MinePhase::Arming {
        state.tick(0.05);
        arming += 1;
        assert!(state.explosion_results.is_empty());
    }
    assert_eq!(arming, ARMING_TICKS);
    assert_eq!(state.mines[0].phase, MinePhase::Armed);
    // The next tick sees the body inside the radius and trips.
    state.tick(0.05);
    assert_eq!(state.mines[0].phase, MinePhase::Tripped);
    assert_eq!(
        state.mines[0].phase_ends - state.mines[0].phase_started,
        TRIP_TICKS
    );
    let mut fuse = 0;
    while !state.mines.is_empty() {
        assert!(state.explosion_results.is_empty());
        state.tick(0.05);
        fuse += 1;
    }
    assert_eq!(fuse, TRIP_TICKS);
    assert_eq!(state.explosion_results.len(), 1);
    let blast = &state.explosion_results[0];
    assert_eq!(blast.owner_id, owner);
    assert_eq!(blast.radius, BLAST_RADIUS);
    assert!(blast.hits.iter().any(|hit| hit.target_id == target));
    let record = state.player_record(owner).unwrap();
    assert_eq!(record.total.mines.attacks, 1);
    assert_eq!(record.total.mines.damaging_attacks, 1);
    assert_eq!(
        record.total.grenades,
        crate::protocol::WeaponCounts::default()
    );
    record.validate_for(Some(owner), None).unwrap();
}

#[test]
fn a_body_outside_the_radius_or_behind_cover_never_trips_it() {
    let (mut state, owner, target) = combat(false);
    state.players[0].pitch = -1.2;
    place(&mut state, owner);
    until_stuck(&mut state);
    assert_eq!(state.mines[0].normal, [0.0, 1.0, 0.0]);
    let position = state.mines[0].position;
    let index = state.players.iter().position(|p| p.id == target).unwrap();
    state.players[index].x = position[0] + TRIGGER_RADIUS + 0.6;
    state.players[0].x = position[0] - TRIGGER_RADIUS - 0.6;
    state.players[0].z = position[2];
    for _ in 0..(ARMING_TICKS + 20) {
        state.tick(0.05);
    }
    assert_eq!(state.mines[0].phase, MinePhase::Armed);
    // Inside the radius but behind a full-height wall: still no trip.
    let mut covered = Mine {
        position,
        ..flying(position, [0.0; 3])
    };
    covered.phase = MinePhase::Armed;
    let screened = arena(vec![Solid {
        min_x: position[0] + 0.5,
        max_x: position[0] + 0.7,
        min_z: -6.0,
        max_z: 6.0,
        bottom: 0.0,
        top: 4.0,
    }]);
    state.players[index].x = position[0] + 1.5;
    assert!(!state.mine_tripped(&covered, &screened));
    assert!(state.mine_tripped(&covered, &arena(vec![])));
}

#[test]
fn the_owner_trips_their_own_mine_and_takes_damage_without_credit() {
    let (mut state, owner, target) = combat(false);
    state.players[0].pitch = -1.2;
    place(&mut state, owner);
    until_stuck(&mut state);
    let position = state.mines[0].position;
    let index = state.players.iter().position(|p| p.id == target).unwrap();
    state.players[index].x = 15.0;
    // Step back out of the radius while it arms, then walk onto it. Armor
    // keeps the owner standing to read the record.
    state.players[0].armor = 50;
    state.players[0].x = position[0] - 3.5;
    for _ in 0..ARMING_TICKS + 2 {
        state.tick(0.05);
    }
    assert_eq!(state.mines[0].phase, MinePhase::Armed);
    state.players[0].x = position[0] - 1.0;
    let mut ticks = 0;
    while !state.mines.is_empty() {
        state.tick(0.05);
        ticks += 1;
    }
    assert_eq!(ticks, TRIP_TICKS + 1);
    let hits = &state.explosion_results[0].hits;
    assert_eq!(hits.len(), 1);
    assert_eq!(hits[0].target_id, owner);
    assert!(state.players[0].hp > 0 && state.players[0].hp < 100);
    let record = state.player_record(owner).unwrap();
    assert!(record.total.hp_lost > 0);
    assert_eq!(record.total.mines.damaging_attacks, 0);
    assert_eq!(record.total.mines.kills, 0);
    assert_eq!(state.scores[&owner], 0);
}

#[test]
fn a_wall_stops_the_blast_and_the_far_side_takes_nothing() {
    let (mut state, owner, target) = combat(true);
    let index = state.players.iter().position(|p| p.id == target).unwrap();
    state.players[index].x = 3.9;
    state.players[0].x = -6.0;
    let walled = state.current_arena().into_owned();
    state.resolve_blast(
        &Blast {
            id: 9,
            owner_id: owner,
            position: [2.6, 0.5, 0.0],
            radius: BLAST_RADIUS,
            peak: BLAST_DAMAGE,
            source: BlastSource::Mine,
        },
        &walled,
    );
    assert_eq!(state.players[index].hp, 100);
    assert!(state.explosion_results[0].hits.is_empty());
    // The same blast without the wall lands on the target.
    state.resolve_blast(
        &Blast {
            id: 10,
            owner_id: owner,
            position: [2.6, 0.5, 0.0],
            radius: BLAST_RADIUS,
            peak: BLAST_DAMAGE,
            source: BlastSource::Mine,
        },
        &arena(vec![]),
    );
    assert!(state.players[index].hp < 100);
}

#[test]
fn the_live_cap_cooldown_and_empty_count_refuse_without_spending() {
    let (mut state, owner, _) = combat(true);
    for _ in 0..LIVE_PER_OWNER {
        place(&mut state, owner);
        for _ in 0..PLACE_COOLDOWN {
            state.tick(0.05);
        }
    }
    assert_eq!(state.mines.len(), LIVE_PER_OWNER);
    assert_eq!(state.players[0].inventory.mines(), 1);
    place(&mut state, owner);
    assert_eq!(state.mines.len(), LIVE_PER_OWNER);
    assert_eq!(state.players[0].inventory.mines(), 1);
    // A fresh placement after clearing the field succeeds once.
    state.mines.clear();
    place(&mut state, owner);
    assert_eq!(state.mines.len(), 1);
    assert_eq!(state.players[0].inventory.mines(), 0);
    // The cooldown refuses the very next press.
    state.players[0].inventory.grant_mines(1);
    place(&mut state, owner);
    assert_eq!(state.mines.len(), 1);
    assert_eq!(state.players[0].inventory.mines(), 1);
    for _ in 0..PLACE_COOLDOWN {
        state.tick(0.05);
    }
    state.mines.clear();
    place(&mut state, owner);
    assert_eq!(state.mines.len(), 1);
    assert_eq!(state.players[0].inventory.mines(), 0);
    // An empty count refuses and spends nothing.
    for _ in 0..PLACE_COOLDOWN {
        state.tick(0.05);
    }
    place(&mut state, owner);
    assert_eq!(state.mines.len(), 1);
    assert_eq!(state.player_record(owner).unwrap().total.mines.attacks, 5);
    // A grenade throw on the same tick takes the attack instead.
    state.mines.clear();
    for _ in 0..PLACE_COOLDOWN {
        state.tick(0.05);
    }
    state.players[0].inventory.grant_mines(1);
    state.players[0].inventory.grant_grenades(1);
    state.set_action(
        owner,
        Action {
            place_mine: true,
            throw_grenade: true,
            ..Default::default()
        },
    );
    state.tick(0.05);
    assert_eq!(state.grenades.len(), 1);
    assert!(state.mines.is_empty());
    assert_eq!(state.players[0].inventory.mines(), 1);
}

#[test]
fn leave_owner_death_reset_and_flight_bound_clear_mines() {
    let (mut state, owner, target) = combat(true);
    place(&mut state, owner);
    assert_eq!(state.mines.len(), 1);
    state.remove_player(owner);
    assert!(state.mines.is_empty());

    let (mut state, owner, _) = combat(true);
    place(&mut state, owner);
    until_stuck(&mut state);
    state.players[0].hp = 0;
    state.tick(0.05);
    assert!(state.mines.is_empty(), "a dead owner's mine goes dark");

    let (mut state, owner, _) = combat(true);
    place(&mut state, owner);
    state.players[0].clear_input();
    assert!(!state.players[0].place_requested);
    state.clear_traveling_shots();
    assert!(state.mines.is_empty());
    assert_eq!(state.players[0].mine_cooldown, 0);

    let (mut state, _, _) = combat(true);
    let mut lost = flying([0.0, 10.0, 0.0], [0.0; 3]);
    lost.owner_id = target;
    lost.phase_started = state.tick;
    state.mines.push(lost);
    state.tick = state.tick.saturating_add(FLIGHT_TICKS);
    state.tick(0.05);
    assert!(state.mines.is_empty());
    assert!(state.explosion_results.is_empty());
}

#[test]
fn a_body_the_owner_cannot_hurt_never_trips_the_mine() {
    let (mut state, owner, _) = combat(false);
    let latch = state
        .spawn_campaign_companion([6.0, 0.0, 0.0], false)
        .unwrap();
    let mut mine = flying([6.5, 0.2, 0.0], [0.0; 3]);
    mine.owner_id = owner;
    mine.phase = MinePhase::Armed;
    state.players[0].x = -10.0;
    let index = state.players.iter().position(|p| p.id == latch).unwrap();
    assert!(!state.damage_lands(0, index));
    let target = state
        .players
        .iter()
        .position(|p| p.id == Uuid::from_u128(2))
        .unwrap();
    state.players[target].x = 15.0;
    assert!(!state.mine_tripped(&mine, &arena(vec![])));
    state.players[target].x = 7.0;
    assert!(state.mine_tripped(&mine, &arena(vec![])));
}

#[test]
fn mine_states_are_strict_wire_facts() {
    let (mut state, owner, _) = combat(true);
    place(&mut state, owner);
    let snapshot = state.snapshot();
    assert_eq!(snapshot.mines.len(), 1);
    snapshot.mines[0].validate(snapshot.tick).unwrap();
    until_stuck(&mut state);
    let snapshot = state.snapshot();
    let mine = &snapshot.mines[0];
    mine.validate(snapshot.tick).unwrap();
    let json = serde_json::to_value(mine).unwrap();
    assert_eq!(json["phase"], "arming");
    for bad in [
        MineState {
            normal: [0.0; 3],
            ..mine.clone()
        },
        MineState {
            phase_ends: mine.phase_started,
            ..mine.clone()
        },
        MineState {
            phase_started: snapshot.tick + 1,
            ..mine.clone()
        },
        MineState {
            position: [f32::NAN, 0.0, 0.0],
            ..mine.clone()
        },
        MineState {
            phase: MinePhase::Flying,
            ..mine.clone()
        },
        MineState {
            phase: MinePhase::Armed,
            ..mine.clone()
        },
    ] {
        assert!(bad.validate(snapshot.tick).is_err());
    }
    assert!(serde_json::from_value::<MineState>(serde_json::json!({
        "id":1,"owner_id":owner,"position":[0,0,0],"normal":[0,1,0],
        "phase":"armed","phase_started":0,"phase_ends":0,"extra":1
    }))
    .is_err());
}

#[test]
fn an_explicit_placement_keeps_its_aim_and_never_invents_a_mine() {
    let (state, owner, _) = combat(true);
    let snapshot = state.snapshot();
    let mut loadout = state.players[0]
        .inventory
        .state(owner, state.players[0].weapon, state.tick)
        .unwrap();
    let action = Action {
        place_mine: true,
        look_at: Some(crate::protocol::LookAt {
            x: Some(3.0),
            y: Some(0.0),
            z: Some(0.0),
            player_id: None,
        }),
        ..Default::default()
    };
    let kept = crate::inventory::control_action(owner, &snapshot, Some(&loadout), action.clone());
    assert!(kept.place_mine);
    assert_eq!(
        serde_json::to_value(&kept.look_at).unwrap(),
        serde_json::to_value(&action.look_at).unwrap()
    );
    loadout.proximity_mines = 0;
    assert!(!crate::inventory::control_action(owner, &snapshot, Some(&loadout), action).place_mine);
}
