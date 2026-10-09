use super::*;
use crate::inventory::Inventory;
use crate::protocol::{
    AmmoPool, CampaignActor, EnemyKind, EnemyPhase, EquipmentPolicy, Role, Team, WeaponType,
    NINE_COLUMN_RECORD_VERSION,
};
use crate::vehicles::Jeep;

fn world(solids: serde_json::Value) -> GameState {
    let document = serde_json::json!({
        "version": 1,
        "map_id": 1097,
        "name": "Rocket fixture",
        "half_extent": 80,
        "ground": "concrete",
        "equipment": "discovery",
        "solids": solids,
        "spawns": [{"id": "entry", "feet": [0.0, 0.0, 0.0], "yaw": 0.0}],
        "landmarks": [{"id": "exit", "feet": [20.0, 0.0, 0.0]}]
    });
    let map =
        crate::maps::AuthoredMap::read(serde_json::to_vec(&document).unwrap().as_slice()).unwrap();
    GameState::with_authored_map(map)
}

fn arm(state: &mut GameState, id: u128, x: f32, z: f32) -> Uuid {
    let id = Uuid::from_u128(id);
    state.add_player(id, format!("Fighter {id}"), Role::Agent);
    let player = state
        .players
        .iter_mut()
        .find(|player| player.id == id)
        .unwrap();
    player.x = x;
    player.z = z;
    player.y = PLAYER_FLOOR_Y;
    player.yaw = 0.0;
    player.pitch = 0.0;
    player.team = None;
    player.campaign = None;
    player.hp = 100;
    player.armor = 0;
    player.inventory = Inventory::new(EquipmentPolicy::Discovery);
    id
}

fn grant(state: &mut GameState, id: Uuid, rounds: u16) {
    let player = state
        .players
        .iter_mut()
        .find(|player| player.id == id)
        .unwrap();
    player.inventory = Inventory::new(EquipmentPolicy::Discovery);
    assert!(player.inventory.grant_weapon(WeaponType::Rocket));
    if rounds > 4 {
        assert!(player.inventory.grant_ammo(AmmoPool::Rockets, rounds - 4) > 0);
    }
    player.weapon = WeaponType::Rocket;
    player.fire_cooldown = 0;
}

fn fly(state: &mut GameState, steps: u32) {
    for _ in 0..steps {
        state.tick += 1;
        let arena = state.current_arena().into_owned();
        state.tick_rockets(0.05, &arena, &[], &[]);
    }
}

fn launch_and_hold(state: &mut GameState, id: Uuid) {
    assert!(state.launch_rocket(id));
    let arena = state.current_arena().into_owned();
    state.tick_rockets(0.05, &arena, &[], &[]);
}

fn column(state: &GameState, id: Uuid) -> crate::protocol::WeaponCounts {
    *state
        .player_record(id)
        .unwrap()
        .total
        .weapon(WeaponType::Rocket)
}

#[test]
fn launch_tick_does_not_hit_a_distant_body_and_later_flight_does() {
    let mut state = world(serde_json::json!([]));
    let shooter = arm(&mut state, 1, 0.0, 0.0);
    let target = arm(&mut state, 2, 9.0, 0.0);
    grant(&mut state, shooter, 4);
    launch_and_hold(&mut state, shooter);
    assert_eq!(state.players[1].hp, 100);
    assert!(state.explosion_results.is_empty());
    assert_eq!(state.rocket_states().len(), 1);
    assert_eq!(state.rocket_states()[0].age_ticks, 0);
    assert_eq!(column(&state, shooter).attacks, 1);
    fly(&mut state, 20);
    assert!(state.rockets.is_empty());
    assert_eq!(state.explosion_results.len(), 1);
    assert!(
        state
            .players
            .iter()
            .find(|player| player.id == target)
            .unwrap()
            .hp
            < 100
    );
    let counts = column(&state, shooter);
    assert_eq!(counts.attacks, 1);
    assert_eq!(counts.damaging_attacks, 1);
    assert_eq!(counts.connects, 1);
    assert_eq!(counts.heads, 0);
    assert!(counts.hp_damage > 0);
}

#[test]
fn a_body_that_leaves_the_line_is_missed() {
    let mut state = world(serde_json::json!([]));
    let shooter = arm(&mut state, 1, 0.0, 0.0);
    let target = arm(&mut state, 2, 12.0, 0.0);
    grant(&mut state, shooter, 4);
    launch_and_hold(&mut state, shooter);
    for _ in 0..30 {
        let player = state
            .players
            .iter_mut()
            .find(|player| player.id == target)
            .unwrap();
        player.z += 3.0;
        state.tick += 1;
        let arena = state.current_arena().into_owned();
        state.tick_rockets(0.05, &arena, &[], &[]);
    }
    assert_eq!(
        state
            .players
            .iter()
            .find(|player| player.id == target)
            .unwrap()
            .hp,
        100
    );
    assert!(state.explosion_results.is_empty());
}

#[test]
fn thin_wall_stops_the_rocket_and_blocks_splash() {
    let mut state = world(serde_json::json!([{
        "id": "pane",
        "min": [4.0, 0.0, -8.0],
        "max": [4.05, 4.0, 8.0],
        "surface": "service_steel"
    }]));
    let shooter = arm(&mut state, 1, -2.0, 0.0);
    let target = arm(&mut state, 2, 7.0, 0.0);
    grant(&mut state, shooter, 4);
    launch_and_hold(&mut state, shooter);
    fly(&mut state, 20);
    assert!(state.rockets.is_empty());
    assert_eq!(state.explosion_results.len(), 1);
    assert!(state.explosion_results[0].position[0] < 4.0);
    assert!(state.explosion_results[0].hits.is_empty());
    assert_eq!(
        state
            .players
            .iter()
            .find(|player| player.id == target)
            .unwrap()
            .hp,
        100
    );
    assert_eq!(
        state
            .players
            .iter()
            .find(|player| player.id == shooter)
            .unwrap()
            .hp,
        100
    );
}

#[test]
fn a_blocked_origin_detonates_on_the_launch_tick() {
    let mut state = world(serde_json::json!([{
        "id": "muzzle",
        "min": [10.0, 0.0, -1.0],
        "max": [12.0, 3.0, 1.0],
        "surface": "service_steel"
    }]));
    let shooter = arm(&mut state, 1, 11.0, 0.0);
    grant(&mut state, shooter, 4);
    assert!(state.launch_rocket(shooter));
    let arena = state.current_arena().into_owned();
    state.tick_rockets(0.05, &arena, &[], &[]);
    assert!(state.rockets.is_empty());
    assert_eq!(state.explosion_results.len(), 1);
    assert_eq!(column(&state, shooter).attacks, 1);
}

#[test]
fn one_hull_commit_adds_direct_and_covered_splash() {
    let mut state = world(serde_json::json!([]));
    let shooter = arm(&mut state, 1, 0.0, 0.0);
    grant(&mut state, shooter, 4);
    state.vehicles.push(Jeep::new(1, [8.0, 0.5, 0.0], 0.0));
    let before = state.vehicles[0].state.hp;
    launch_and_hold(&mut state, shooter);
    fly(&mut state, 20);
    let after = state.vehicles[0].state.hp;
    let lost = before - after;
    assert!(lost > DIRECT, "direct damage is part of the one commit");
    assert!(lost <= DIRECT + SPLASH_PEAK as i32);
    assert!(state.explosion_results.len() <= 1);
}

#[test]
fn plate_applies_to_direct_damage_only() {
    let mut state = world(serde_json::json!([]));
    let shooter = arm(&mut state, 1, 0.0, 0.0);
    let target = arm(&mut state, 2, 8.0, 0.0);
    grant(&mut state, shooter, 4);
    state
        .players
        .iter_mut()
        .find(|player| player.id == shooter)
        .unwrap()
        .campaign = Some(CampaignActor::Participant {});
    let player = state
        .players
        .iter_mut()
        .find(|player| player.id == target)
        .unwrap();
    player.hp = 200;
    player.yaw = std::f32::consts::PI;
    player.campaign = Some(CampaignActor::Union {
        kind: EnemyKind::Auditor,
        phase: EnemyPhase::Firing,
        phase_started: 0,
        phase_ends: 40,
        seated: false,
    });
    launch_and_hold(&mut state, shooter);
    fly(&mut state, 20);
    let hp = state
        .players
        .iter()
        .find(|player| player.id == target)
        .unwrap()
        .hp;
    let lost = 200 - hp;
    assert!((60..=95).contains(&lost), "lost {lost}");
    assert_eq!(column(&state, shooter).hp_damage, lost as u64);
    assert_eq!(column(&state, shooter).heads, 0);
}

#[test]
fn splash_can_hurt_the_owner_and_armor_is_debited_once() {
    let mut state = world(serde_json::json!([{
        "id": "close",
        "min": [1.5, 0.0, -2.0],
        "max": [1.7, 4.0, 2.0],
        "surface": "service_steel"
    }]));
    let shooter = arm(&mut state, 1, 0.0, 0.0);
    grant(&mut state, shooter, 4);
    state.players[0].armor = 80;
    state.players[0].hp = 100;
    launch_and_hold(&mut state, shooter);
    fly(&mut state, 8);
    let owner = state
        .players
        .iter()
        .find(|player| player.id == shooter)
        .unwrap();
    assert!(owner.hp + owner.armor < 180);
    let counts = column(&state, shooter);
    assert_eq!(counts.attacks, 1);
    assert_eq!(
        counts.hp_damage + counts.armor_damage,
        (100 - owner.hp + 80 - owner.armor) as u64
    );
    assert!(counts.hp_damage + counts.armor_damage > 0);
}

#[test]
fn friendly_fire_off_and_spawn_shield_connect_without_damage() {
    let mut state = world(serde_json::json!([]));
    let shooter = arm(&mut state, 1, 0.0, 0.0);
    let target = arm(&mut state, 2, 8.0, 0.0);
    grant(&mut state, shooter, 4);
    for player in &mut state.players {
        player.team = Some(Team::Union);
    }
    launch_and_hold(&mut state, shooter);
    fly(&mut state, 20);
    assert_eq!(
        state
            .players
            .iter()
            .find(|player| player.id == target)
            .unwrap()
            .hp,
        100
    );
    assert!(state
        .explosion_results
        .iter()
        .all(|result| result.hits.is_empty()));
    assert_eq!(column(&state, shooter).connects, 1);
    assert_eq!(column(&state, shooter).damaging_attacks, 0);

    let mut state = world(serde_json::json!([]));
    let shooter = arm(&mut state, 1, 0.0, 0.0);
    let target = arm(&mut state, 2, 8.0, 0.0);
    grant(&mut state, shooter, 4);
    state.spawn_shields.insert(target, 8);
    launch_and_hold(&mut state, shooter);
    fly(&mut state, 20);
    assert_eq!(
        state
            .players
            .iter()
            .find(|player| player.id == target)
            .unwrap()
            .hp,
        100
    );
    assert_eq!(column(&state, shooter).connects, 1);
    assert!(state
        .explosion_results
        .iter()
        .all(|result| result.hits.is_empty()));
}

#[test]
fn death_retains_a_rocket_and_leave_removes_it() {
    let mut state = world(serde_json::json!([]));
    let shooter = arm(&mut state, 1, 0.0, 0.0);
    grant(&mut state, shooter, 4);
    launch_and_hold(&mut state, shooter);
    state.players[0].hp = 0;
    assert_eq!(state.rockets.len(), 1);
    state.remove_player(shooter);
    assert!(state.rockets.is_empty());
}

#[test]
fn reset_clears_rockets_and_expiry_has_no_blast() {
    let mut state = world(serde_json::json!([]));
    let shooter = arm(&mut state, 1, 0.0, 0.0);
    grant(&mut state, shooter, 4);
    launch_and_hold(&mut state, shooter);
    state.clear_grenades();
    assert!(state.rockets.is_empty());
    launch_and_hold(&mut state, shooter);
    fly(&mut state, LIFE_TICKS);
    assert!(state.rockets.is_empty());
    assert!(state.explosion_results.is_empty());
}

#[test]
fn live_caps_and_serial_overflow_refuse_before_ammo_or_stats_change() {
    let mut state = world(serde_json::json!([]));
    let shooter = arm(&mut state, 1, 0.0, 0.0);
    grant(&mut state, shooter, 20);
    for _ in 0..8 {
        state.players[0].fire_cooldown = 0;
        assert!(state.launch_rocket(shooter));
    }
    let ammo = state.players[0]
        .inventory
        .state(shooter, WeaponType::Rocket, 0)
        .unwrap()
        .ammo(AmmoPool::Rockets);
    let attacks = column(&state, shooter).attacks;
    assert!(!state.launch_rocket(shooter));
    assert_eq!(
        state.players[0]
            .inventory
            .state(shooter, WeaponType::Rocket, 0)
            .unwrap()
            .ammo(AmmoPool::Rockets),
        ammo
    );
    assert_eq!(column(&state, shooter).attacks, attacks);

    state.rockets.clear();
    state.projectile_serial = u32::MAX;
    let ammo = state.players[0]
        .inventory
        .state(shooter, WeaponType::Rocket, 0)
        .unwrap()
        .ammo(AmmoPool::Rockets);
    assert!(!state.launch_rocket(shooter));
    assert_eq!(
        state.players[0]
            .inventory
            .state(shooter, WeaponType::Rocket, 0)
            .unwrap()
            .ammo(AmmoPool::Rockets),
        ammo
    );

    state.projectile_serial = 1;
    for index in 0..MAX_LIVE {
        state.rockets.push(Rocket {
            id: 10 + index as u32,
            owner_id: Uuid::from_u128(50 + index as u128),
            position: [0.0, 2.0, 0.0],
            velocity: [SPEED, 0.0, 0.0],
            launched_at: 0,
            age_ticks: 1,
            blocked_origin: false,
        });
    }
    assert!(!state.launch_rocket(shooter));
    assert_eq!(
        state.players[0]
            .inventory
            .state(shooter, WeaponType::Rocket, 0)
            .unwrap()
            .ammo(AmmoPool::Rockets),
        ammo
    );
}

#[test]
fn one_rocket_records_every_victim_once() {
    let mut state = world(serde_json::json!([]));
    let shooter = arm(&mut state, 1, 0.0, 0.0);
    let first = arm(&mut state, 2, 8.0, 0.0);
    let second = arm(&mut state, 3, 8.0, 1.2);
    grant(&mut state, shooter, 4);
    state
        .players
        .iter_mut()
        .find(|player| player.id == first)
        .unwrap()
        .hp = 40;
    state
        .players
        .iter_mut()
        .find(|player| player.id == second)
        .unwrap()
        .hp = 20;
    launch_and_hold(&mut state, shooter);
    fly(&mut state, 20);
    assert!(
        state
            .players
            .iter()
            .find(|player| player.id == first)
            .unwrap()
            .hp
            <= 0
    );
    assert!(
        state
            .players
            .iter()
            .find(|player| player.id == second)
            .unwrap()
            .hp
            <= 0
    );
    let counts = column(&state, shooter);
    assert_eq!(counts.attacks, 1);
    assert_eq!(counts.kills, 2);
    assert_eq!(counts.connects, 1);
    assert_eq!(counts.heads, 0);
    let record = state.player_record(shooter).unwrap();
    assert!(record
        .record_for_version(NINE_COLUMN_RECORD_VERSION)
        .is_err());
    let wire = serde_json::to_value(&record).unwrap();
    assert_eq!(wire["total"]["weapons"].as_array().unwrap().len(), 10);
    assert_eq!(
        serde_json::from_value::<crate::protocol::PlayerRecord>(wire).unwrap(),
        record
    );
}

#[test]
fn a_dead_owner_still_owns_the_impact() {
    let mut state = world(serde_json::json!([]));
    let shooter = arm(&mut state, 1, 0.0, 0.0);
    let target = arm(&mut state, 2, 8.0, 0.0);
    grant(&mut state, shooter, 4);
    launch_and_hold(&mut state, shooter);
    state
        .players
        .iter_mut()
        .find(|player| player.id == shooter)
        .unwrap()
        .hp = 0;
    fly(&mut state, 20);
    assert!(
        state
            .players
            .iter()
            .find(|player| player.id == target)
            .unwrap()
            .hp
            < 100
    );
    assert_eq!(column(&state, shooter).damaging_attacks, 1);
}

#[test]
fn discovery_loads_four_rounds_and_a_one_round_tube() {
    let mut inventory = Inventory::new(EquipmentPolicy::Discovery);
    inventory.arm_magazines();
    assert!(inventory.grant_weapon(WeaponType::Rocket));
    let view = inventory.state(Uuid::nil(), WeaponType::Rocket, 0).unwrap();
    assert_eq!(view.ammo(AmmoPool::Rockets), 4);
    assert_eq!(view.shots(WeaponType::Rocket), Some(1));
    assert!(inventory.try_fire(WeaponType::Rocket));
    let spent = inventory.state(Uuid::nil(), WeaponType::Rocket, 1).unwrap();
    assert_eq!(spent.ammo(AmmoPool::Rockets), 3);
    assert_eq!(spent.shots(WeaponType::Rocket), Some(0));
    let dry = inventory.dry_fire_count();
    assert!(!inventory.try_fire(WeaponType::Rocket));
    assert!(inventory.dry_fire_count() > dry);
    assert!(inventory.grant_weapon(WeaponType::Rocket));
    let duplicate = inventory.state(Uuid::nil(), WeaponType::Rocket, 2).unwrap();
    assert_eq!(duplicate.shots(WeaponType::Rocket), Some(0));
    assert!(duplicate.ammo(AmmoPool::Rockets) > 3);
    assert!(inventory.request_reload(WeaponType::Rocket, 2));
    inventory.finish_reload(17);
    assert_eq!(
        inventory
            .state(Uuid::nil(), WeaponType::Rocket, 18)
            .unwrap()
            .shots(WeaponType::Rocket),
        Some(0)
    );
    inventory.finish_reload(18);
    assert_eq!(
        inventory
            .state(Uuid::nil(), WeaponType::Rocket, 18)
            .unwrap()
            .shots(WeaponType::Rocket),
        Some(1)
    );

    let mut agent = Inventory::new(EquipmentPolicy::Discovery);
    assert!(agent.grant_weapon(WeaponType::Rocket));
    assert_eq!(
        agent
            .state(Uuid::nil(), WeaponType::Rocket, 0)
            .unwrap()
            .shots(WeaponType::Rocket),
        Some(4)
    );
    assert!(agent.try_fire(WeaponType::Rocket));
    assert_eq!(
        agent
            .state(Uuid::nil(), WeaponType::Rocket, 1)
            .unwrap()
            .ammo(AmmoPool::Rockets),
        3
    );

    let mut arcade = Inventory::new(EquipmentPolicy::FullArsenal);
    arcade.arm_magazines();
    assert!(!arcade.grant_weapon(WeaponType::Rocket));
    assert_eq!(
        arcade
            .state(Uuid::nil(), WeaponType::Flechette, 0)
            .unwrap()
            .ammo(AmmoPool::Rockets),
        0
    );
}

#[test]
fn non_finite_aim_and_a_dry_tube_create_no_rocket() {
    let mut state = world(serde_json::json!([]));
    let shooter = arm(&mut state, 1, 0.0, 0.0);
    grant(&mut state, shooter, 4);
    state.players[0].yaw = f32::NAN;
    assert!(!state.launch_rocket(shooter));
    assert!(state.rockets.is_empty());
    assert_eq!(column(&state, shooter).attacks, 0);
    state.players[0].yaw = 0.0;
    state.players[0].inventory = Inventory::new(EquipmentPolicy::Discovery);
    state.players[0].inventory.arm_magazines();
    assert!(state.players[0].inventory.grant_weapon(WeaponType::Rocket));
    assert!(state.players[0].inventory.try_fire(WeaponType::Rocket));
    assert!(!state.launch_rocket(shooter));
    assert!(state.rockets.is_empty());
    assert!(state.players[0].inventory.dry_fire_count() > 0);
}
