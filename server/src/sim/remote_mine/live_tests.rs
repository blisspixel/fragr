use super::*;
use crate::protocol::{Action, Role, WeaponCounts, WeaponType};

fn combat(walled: bool) -> (GameState, Uuid, Uuid) {
    let solids = if walled {
        serde_json::json!([{"id":"wall","min":[3,0,-6],"max":[3.2,4,6],"surface":"concrete"}])
    } else {
        serde_json::json!([])
    };
    let map = crate::maps::AuthoredMap::read(
        serde_json::to_vec(&serde_json::json!({
            "version":1,"map_id":1112,"name":"Remote fixture","half_extent":20,
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
    let owner = Uuid::from_u128(1);
    let target = Uuid::from_u128(2);
    state.add_player(owner, "Placer".into(), Role::Human);
    state.add_player(target, "Target".into(), Role::Agent);
    for (index, player) in state.players.iter_mut().enumerate() {
        player.x = 0.5 + index as f32 * 14.0;
        player.z = 0.0;
        player.y = PLAYER_FLOOR_Y;
        player.yaw = 0.0;
        player.pitch = 0.0;
    }
    state.players[0].inventory.grant_remote_mines(6);
    (state, owner, target)
}

fn place(state: &mut GameState, owner: Uuid) {
    state.set_action(
        owner,
        Action {
            place_remote_mine: true,
            ..Default::default()
        },
    );
    state.tick(0.05);
    state.set_action(owner, Action::default());
}

fn until_stuck(state: &mut GameState) {
    for _ in 0..FLIGHT_TICKS {
        state.tick(0.05);
        if state
            .remote_mines
            .last()
            .is_some_and(|mine| mine.state.phase != RemoteMinePhase::Flying)
        {
            return;
        }
    }
    panic!("remote did not reach its actual surface");
}

#[test]
fn remote_live_exact_arming_requires_a_new_trigger_and_records_actual_covered_damage() {
    let (mut state, owner, target) = combat(true);
    place(&mut state, owner);
    until_stuck(&mut state);
    let device = state.remote_mines[0].state.clone();
    assert_eq!(device.phase, RemoteMinePhase::Arming);
    assert_eq!(device.phase_ends - device.phase_started, ARMING_TICKS);
    state.players[0].x = -6.0;
    state.players[1].x = device.position[0] - 1.0;
    state.players[1].z = device.position[2];
    state.players[1].armor = 20;
    state.set_action(
        owner,
        Action {
            trigger_remote_mines: true,
            ..Default::default()
        },
    );
    for _ in 0..ARMING_TICKS + 20 {
        state.tick(0.05);
        assert!(state.explosion_results.is_empty());
        assert_eq!(state.players[1].hp, 100);
    }
    assert_eq!(state.remote_mines[0].state.phase, RemoteMinePhase::Armed);
    assert_eq!(state.remote_mines[0].state.phase_started, device.phase_ends);
    state.set_action(owner, Action::default());
    state.set_action(
        owner,
        Action {
            trigger_remote_mines: true,
            ..Default::default()
        },
    );
    state.tick(0.05);
    let start = state.tick;
    assert_eq!(
        state.remote_mines[0].state.phase,
        RemoteMinePhase::Triggered
    );
    assert_eq!(
        state.remote_mines[0].state.phase_ends,
        start + TRIGGER_TICKS
    );
    for _ in 1..TRIGGER_TICKS {
        state.tick(0.05);
        assert!(state.explosion_results.is_empty());
    }
    state.tick(0.05);
    assert!(state.remote_mines.is_empty());
    assert_eq!(state.explosion_results.len(), 1);
    let hit = state.explosion_results[0]
        .hits
        .iter()
        .find(|hit| hit.target_id == target)
        .unwrap();
    assert!(hit.hp_damage > 0);
    assert_eq!(hit.armor_damage, 20);
    let record = state.player_record(owner).unwrap();
    assert_eq!(record.total.remote_mines.attacks, 1);
    assert_eq!(record.total.remote_mines.damaging_attacks, 1);
    assert_eq!(
        record.total.remote_mines.hp_damage,
        u64::from(hit.hp_damage)
    );
    assert_eq!(record.total.remote_mines.armor_damage, 20);
    assert_eq!(record.total.grenades, WeaponCounts::default());
    assert_eq!(record.total.mines, WeaponCounts::default());
    record.validate_for(Some(owner), None).unwrap();
    state.tick(0.05);
    assert!(state.explosion_results.is_empty());
}

#[test]
fn remote_live_held_placement_short_press_priority_caps_and_refusals_preserve_stock() {
    let (mut state, owner, _) = combat(true);
    state.set_action(
        owner,
        Action {
            place_remote_mine: true,
            fire: true,
            ..Default::default()
        },
    );
    state.tick(0.05);
    assert!(state.shot_results.is_empty());
    for _ in 0..PLACE_COOLDOWN + 2 {
        state.tick(0.05);
    }
    assert_eq!(state.remote_mines.len(), 1);
    assert_eq!(state.players[0].inventory.remote_mines(), 5);
    state.set_action(owner, Action::default());
    // A short press released before the tick must still place exactly once.
    state.set_action(
        owner,
        Action {
            place_remote_mine: true,
            ..Default::default()
        },
    );
    state.set_action(owner, Action::default());
    state.tick(0.05);
    assert_eq!(state.remote_mines.len(), 2);
    assert_eq!(state.players[0].inventory.remote_mines(), 4);
    place(&mut state, owner);
    assert_eq!(state.players[0].inventory.remote_mines(), 4);
    for _ in 2..LIVE_PER_OWNER {
        for _ in 0..PLACE_COOLDOWN {
            state.tick(0.05);
        }
        place(&mut state, owner);
    }
    assert_eq!(state.remote_mines.len(), LIVE_PER_OWNER);
    for _ in 0..PLACE_COOLDOWN {
        state.tick(0.05);
    }
    place(&mut state, owner);
    assert_eq!(state.players[0].inventory.remote_mines(), 2);
    assert_eq!(
        state
            .player_record(owner)
            .unwrap()
            .total
            .remote_mines
            .attacks,
        4
    );
    state.remote_mines.clear();
    state.players[0].inventory.grant_grenades(1);
    state.players[0].inventory.grant_mines(1);
    state.set_action(
        owner,
        Action {
            throw_grenade: true,
            place_mine: true,
            place_remote_mine: true,
            ..Default::default()
        },
    );
    state.tick(0.05);
    assert_eq!(state.grenades.len(), 1);
    assert!(state.mines.is_empty() && state.remote_mines.is_empty());
    assert_eq!(state.players[0].inventory.remote_mines(), 2);
    assert_eq!(state.players[0].inventory.mines(), 1);
}

#[test]
fn remote_live_blind_side_cover_and_gunfire_do_not_trigger_or_hurt_through_wall() {
    let (mut state, owner, _) = combat(true);
    place(&mut state, owner);
    until_stuck(&mut state);
    state.players[0].x = -6.0;
    state.players[1].x = 3.9;
    for _ in 0..ARMING_TICKS {
        state.tick(0.05);
    }
    state.players[0].inventory.grant_weapon(WeaponType::Tack);
    state.players[0].weapon = WeaponType::Tack;
    state.set_action(
        owner,
        Action {
            fire: true,
            look_at: Some(crate::protocol::LookAt {
                x: Some(3.0),
                y: Some(1.6),
                z: Some(0.0),
                player_id: None,
            }),
            ..Default::default()
        },
    );
    state.tick(0.05);
    assert!(!state.shot_results.is_empty());
    assert_eq!(state.remote_mines[0].state.phase, RemoteMinePhase::Armed);
    state.set_action(
        owner,
        Action {
            trigger_remote_mines: true,
            ..Default::default()
        },
    );
    state.tick(0.05);
    for _ in 0..TRIGGER_TICKS {
        state.tick(0.05);
    }
    assert_eq!(state.players[1].hp, 100);
    assert_eq!(state.explosion_results.len(), 1);
    assert!(state.explosion_results[0].hits.is_empty());
    assert_eq!(
        state
            .player_record(owner)
            .unwrap()
            .total
            .remote_mines
            .damaging_attacks,
        0
    );
}

#[test]
fn remote_live_dead_left_reset_invalid_origin_and_serial_refuse_without_gifts() {
    let (mut state, owner, _) = combat(true);
    place(&mut state, owner);
    state.remove_player(owner);
    assert!(state.remote_mines.is_empty());
    let (mut state, owner, _) = combat(true);
    place(&mut state, owner);
    state.players[0].hp = 0;
    state.tick(0.05);
    assert!(state.remote_mines.is_empty() && state.explosion_results.is_empty());
    let (mut state, owner, _) = combat(true);
    place(&mut state, owner);
    state.players[0].clear_input();
    assert!(!state.players[0].remote_place_requested && !state.players[0].remote_trigger_requested);
    state.clear_traveling_shots();
    assert!(state.remote_mines.is_empty());
    assert_eq!(state.players[0].remote_cooldown, 0);
    state.projectile_serial = u32::MAX;
    place(&mut state, owner);
    assert_eq!(state.players[0].inventory.remote_mines(), 5);
    assert!(state.remote_mines.is_empty());
    state.projectile_serial = 0;
    state.players[0].x = 3.1;
    place(&mut state, owner);
    assert_eq!(state.players[0].inventory.remote_mines(), 5);
    assert!(state.remote_mines.is_empty());
}

#[test]
fn remote_live_states_are_actual_strict_snapshot_facts() {
    let (mut state, owner, _) = combat(true);
    place(&mut state, owner);
    let snapshot = state.snapshot();
    assert_eq!(snapshot.remote_mines.len(), 1);
    snapshot.remote_mines[0].validate(snapshot.tick).unwrap();
    until_stuck(&mut state);
    let snapshot = state.snapshot();
    snapshot.remote_mines[0].validate(snapshot.tick).unwrap();
    let wire = serde_json::to_value(&snapshot).unwrap();
    assert_eq!(wire["remote_mines"][0]["phase"], "arming");
    assert_eq!(
        serde_json::from_value::<crate::protocol::Snapshot>(wire)
            .unwrap()
            .remote_mines,
        snapshot.remote_mines
    );
    state.clear_remote_mines();
    assert!(serde_json::to_value(state.snapshot())
        .unwrap()
        .get("remote_mines")
        .is_none());
}

#[test]
fn remote_live_fresh_command_only_commits_armed_owner_charges_without_spending_twice() {
    let (mut state, owner, other) = combat(true);
    state.players[0].x = -6.0;
    state.players[1].inventory.grant_remote_mines(2);
    state.players[1].yaw = std::f32::consts::PI;
    place(&mut state, owner);
    until_stuck(&mut state);
    for _ in 0..ARMING_TICKS {
        state.tick(0.05);
    }
    place(&mut state, owner);
    until_stuck(&mut state);
    place(&mut state, other);
    until_stuck(&mut state);
    for _ in 0..ARMING_TICKS {
        state.tick(0.05);
    }
    // The player is distant from both charged wall faces.
    state.players[0].x = -6.0;
    state.players[1].x = 14.5;
    let before = state.players[0].inventory.remote_mines();
    state.set_action(
        owner,
        Action {
            trigger_remote_mines: true,
            ..Default::default()
        },
    );
    state.tick(0.05);
    assert_eq!(
        state
            .remote_mines
            .iter()
            .filter(|mine| mine.state.owner_id == owner
                && mine.state.phase == RemoteMinePhase::Triggered)
            .count(),
        2
    );
    assert_eq!(
        state
            .remote_mines
            .iter()
            .find(|mine| mine.state.owner_id == other)
            .unwrap()
            .state
            .phase,
        RemoteMinePhase::Armed
    );
    assert_eq!(state.players[0].inventory.remote_mines(), before);
    for _ in 0..TRIGGER_TICKS {
        state.tick(0.05);
    }
    assert_eq!(state.explosion_results.len(), 2);
    assert_eq!(state.remote_mines.len(), 1);
    assert_eq!(state.remote_mines[0].state.owner_id, other);
    assert_eq!(
        state
            .player_record(owner)
            .unwrap()
            .total
            .remote_mines
            .attacks,
        2
    );
}

#[test]
fn remote_live_control_preserves_placement_aim_and_empty_carry_trigger() {
    let (state, owner, _) = combat(true);
    let snapshot = state.snapshot();
    let mut loadout = state.players[0]
        .inventory
        .state(owner, state.players[0].weapon, state.tick)
        .unwrap();
    let action = Action {
        place_remote_mine: true,
        look_at: Some(crate::protocol::LookAt {
            x: Some(3.0),
            y: Some(0.0),
            z: Some(0.0),
            player_id: None,
        }),
        ..Default::default()
    };
    let kept = crate::inventory::control_action(owner, &snapshot, Some(&loadout), action.clone());
    assert!(kept.place_remote_mine);
    assert_eq!(
        serde_json::to_value(kept.look_at).unwrap(),
        serde_json::to_value(&action.look_at).unwrap()
    );
    loadout.remote_mines = 0;
    assert!(
        !crate::inventory::control_action(owner, &snapshot, Some(&loadout), action)
            .place_remote_mine
    );
    let triggered = crate::inventory::control_action(
        owner,
        &snapshot,
        Some(&loadout),
        Action {
            trigger_remote_mines: true,
            ..Default::default()
        },
    );
    assert!(triggered.trigger_remote_mines && !triggered.place_remote_mine);
}
