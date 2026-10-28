//! Guns dropped on death: what drops, what it carries, who takes it, how
//! long it lies, and every rule sheet that keeps its guns instead.
use super::*;
use crate::protocol::{AmmoPool, GameMode, Mutator, Role};
use crate::rules::RuleSet;
use crate::sim::{MapKind, MatchConfig};
use uuid::Uuid;

const DT: f32 = 0.05;

fn arena(rules: RuleSet) -> GameState {
    let mut state = GameState::with_map(MapKind::ArenaDuel, false);
    state.seed(42);
    state.config = MatchConfig {
        warmup_ticks: 1,
        boss_spawn_ticks: None,
        compliance_ping_ticks: None,
        time_limit_ticks: None,
        frag_limit: None,
        rules,
        ..MatchConfig::default()
    };
    state.start_round();
    state
}

fn ffa() -> GameState {
    arena(RuleSet::default())
}

fn join(state: &mut GameState, n: u128) -> Uuid {
    let id = Uuid::from_u128(n);
    state.add_player(id, format!("F{n}"), Role::Human);
    id
}

fn fighter(state: &mut GameState, id: Uuid) -> &mut Player {
    state.players.iter_mut().find(|p| p.id == id).unwrap()
}

/// Put `id` somewhere quiet on the lot's ground floor, holding `weapon`.
fn arm(state: &mut GameState, id: Uuid, weapon: WeaponType, x: f32) {
    let p = fighter(state, id);
    p.inventory.grant_weapon(weapon);
    p.weapon = weapon;
    p.x = x;
    p.z = -30.0;
    p.y = PLAYER_FLOOR_Y;
}

fn step_onto(state: &mut GameState, id: Uuid, x: f32, z: f32) {
    let p = fighter(state, id);
    p.x = x;
    p.z = z;
    p.y = PLAYER_FLOOR_Y;
    state.tick(DT);
}

#[test]
fn a_fragged_rocket_holder_leaves_the_launcher_and_the_winner_takes_it() {
    let mut state = ffa();
    let killer = join(&mut state, 1);
    let victim = join(&mut state, 2);
    arm(&mut state, victim, WeaponType::Rocket, 10.0);
    arm(&mut state, killer, WeaponType::Tack, 4.0);
    let (x, z) = {
        let p = fighter(&mut state, victim);
        (p.x, p.z)
    };
    assert!(state.hit_for_test(killer, victim, 1000));
    assert_eq!(state.dropped_guns.len(), 1);
    let gun = state.dropped_guns[0].clone();
    assert_eq!(gun.weapon, WeaponType::Rocket);
    assert_eq!(gun.rounds, WeaponType::Rocket.pickup_rounds());
    assert_eq!((gun.x, gun.z), (x, z));

    let row = state
        .snapshot()
        .pickups
        .into_iter()
        .find(|p| p.dropped)
        .expect("the drop is on the wire");
    assert_eq!(row.id, "drop_1");
    assert_eq!(row.weapon, "Rocket");
    assert_eq!(row.amount, Some(4));
    let json = serde_json::to_value(&row).unwrap();
    assert_eq!(json["dropped"], true);
    let pad = state
        .snapshot()
        .pickups
        .into_iter()
        .find(|p| !p.dropped)
        .unwrap();
    assert!(serde_json::to_value(&pad).unwrap().get("dropped").is_none());

    state.take_events();
    step_onto(&mut state, killer, x, z);
    assert!(state.dropped_guns.is_empty());
    let p = fighter(&mut state, killer);
    assert!(p.inventory.owns(WeaponType::Rocket));
    assert_eq!(p.weapon, WeaponType::Rocket, "a found gun comes to hand");
    assert_eq!(p.inventory.carried(AmmoPool::Rockets), 4);
    let claimed = state.take_events().into_iter().any(|event| {
        matches!(event, crate::protocol::GameEvent::Pickup { pickup_id, weapon, amount, .. }
            if pickup_id == "drop_1" && weapon == "Rocket" && amount == Some(4))
    });
    assert!(claimed, "the claim is a pickup event");
}

#[test]
fn a_drop_carries_what_was_left_and_never_more_than_a_pad() {
    let mut state = ffa();
    let killer = join(&mut state, 1);
    let victim = join(&mut state, 2);
    arm(&mut state, victim, WeaponType::Rocket, 10.0);
    fighter(&mut state, victim)
        .inventory
        .grant_ammo(AmmoPool::Rockets, 20);
    assert!(state.hit_for_test(killer, victim, 1000));
    assert_eq!(state.dropped_guns[0].rounds, 4, "capped at the pad's rack");

    let mut state = ffa();
    let killer = join(&mut state, 1);
    let victim = join(&mut state, 2);
    arm(&mut state, victim, WeaponType::Scatter, 10.0);
    // Fire most of the tube's worth away by hand: three shells left.
    let p = fighter(&mut state, victim);
    for _ in 0..9 {
        assert!(p.inventory.try_fire(WeaponType::Scatter));
    }
    assert!(state.hit_for_test(killer, victim, 1000));
    assert_eq!(state.dropped_guns[0].rounds, 3);
}

#[test]
fn the_pistol_fists_the_flechette_and_an_empty_gun_stay_behind() {
    for (weapon, empty) in [
        (WeaponType::Tack, false),
        (WeaponType::Fists, false),
        (WeaponType::Flechette, false),
        (WeaponType::Rocket, true),
    ] {
        let mut state = ffa();
        let killer = join(&mut state, 1);
        let victim = join(&mut state, 2);
        arm(&mut state, victim, weapon, 10.0);
        if empty {
            let p = fighter(&mut state, victim);
            while p.inventory.try_fire(weapon) {}
        }
        assert!(state.hit_for_test(killer, victim, 1000));
        assert!(state.dropped_guns.is_empty(), "{weapon:?} empty {empty}");
    }
}

#[test]
fn a_dropped_gun_lies_fifteen_seconds_then_is_gone() {
    let mut state = ffa();
    let killer = join(&mut state, 1);
    let victim = join(&mut state, 2);
    arm(&mut state, victim, WeaponType::Rail, 10.0);
    arm(&mut state, killer, WeaponType::Tack, -20.0);
    assert!(state.hit_for_test(killer, victim, 1000));
    for _ in 0..DROPPED_GUN_TICKS - 1 {
        // The killer stands still away from it; nobody takes it.
        let p = fighter(&mut state, killer);
        p.x = -20.0;
        p.z = -30.0;
        state.tick(DT);
    }
    assert_eq!(state.dropped_guns.len(), 1);
    state.tick(DT);
    assert!(state.dropped_guns.is_empty());
}

#[test]
fn a_full_bag_walks_over_a_drop_and_leaves_it_for_someone_else() {
    let mut state = ffa();
    let killer = join(&mut state, 1);
    let victim = join(&mut state, 2);
    arm(&mut state, victim, WeaponType::Rocket, 10.0);
    arm(&mut state, killer, WeaponType::Rocket, 4.0);
    fighter(&mut state, killer)
        .inventory
        .grant_ammo(AmmoPool::Rockets, 20);
    let (x, z) = {
        let p = fighter(&mut state, victim);
        (p.x, p.z)
    };
    assert!(state.hit_for_test(killer, victim, 1000));
    step_onto(&mut state, killer, x, z);
    assert_eq!(state.dropped_guns.len(), 1);
    // One rocket short: now it is worth taking, as ammunition.
    assert!(fighter(&mut state, killer)
        .inventory
        .try_fire(WeaponType::Rocket));
    step_onto(&mut state, killer, x, z);
    assert!(state.dropped_guns.is_empty());
    assert_eq!(
        fighter(&mut state, killer)
            .inventory
            .carried(AmmoPool::Rockets),
        20
    );
}

#[test]
fn a_new_round_clears_the_floor() {
    let mut state = ffa();
    let killer = join(&mut state, 1);
    let victim = join(&mut state, 2);
    arm(&mut state, victim, WeaponType::Scatter, 10.0);
    assert!(state.hit_for_test(killer, victim, 1000));
    assert_eq!(state.dropped_guns.len(), 1);
    state.start_round();
    assert!(state.dropped_guns.is_empty());
}

#[test]
fn a_duel_drops_like_the_free_for_all() {
    let mut state = arena(RuleSet::new(GameMode::Duel, &[], false).unwrap());
    let killer = join(&mut state, 1);
    let victim = join(&mut state, 2);
    arm(&mut state, victim, WeaponType::Scatter, 10.0);
    assert!(state.hit_for_test(killer, victim, 1000));
    assert_eq!(state.dropped_guns.len(), 1);
}

#[test]
fn issued_kits_and_one_gun_rules_keep_their_guns() {
    for rules in [
        RuleSet::new(GameMode::Ffa, &[Mutator::FullArsenal], false).unwrap(),
        RuleSet::new(GameMode::Ffa, &[Mutator::RailOnly], false).unwrap(),
        RuleSet::new(GameMode::Ffa, &[Mutator::ShotgunOnly], false).unwrap(),
        RuleSet::new(GameMode::Ffa, &[Mutator::GoldenRail], false).unwrap(),
        RuleSet::new(GameMode::Tdm, &[], false).unwrap(),
    ] {
        let mut state = arena(rules.clone());
        assert!(!state.drops_guns(), "{}", rules.name());
        let killer = join(&mut state, 1);
        let victim = join(&mut state, 2);
        let weapon = rules.only_weapon().unwrap_or(WeaponType::Scatter);
        let p = fighter(&mut state, victim);
        p.weapon = weapon;
        assert!(state.hit_for_test(killer, victim, 1000));
        assert!(state.dropped_guns.is_empty(), "{}", rules.name());
    }
}

#[test]
fn licence_to_kill_still_drops_because_its_guns_are_found() {
    let state = arena(RuleSet::new(GameMode::Ffa, &[Mutator::LicenceToKill], false).unwrap());
    assert!(state.drops_guns());
}

#[test]
fn a_fighter_killed_by_their_own_blast_drops_too() {
    let mut state = ffa();
    let victim = join(&mut state, 2);
    arm(&mut state, victim, WeaponType::Rocket, 10.0);
    let index = state.players.iter().position(|p| p.id == victim).unwrap();
    state.environmental_self_damage(index, 1000);
    assert_eq!(state.dropped_guns.len(), 1);
    assert_eq!(state.dropped_guns[0].weapon, WeaponType::Rocket);
}

#[test]
fn a_repeater_carries_rounds_from_the_bullets_it_shares_with_the_pistol() {
    let mut state = ffa();
    let killer = join(&mut state, 1);
    let victim = join(&mut state, 2);
    // The Pistol's fifty Bullets and the Repeater's sixty are one count.
    arm(&mut state, victim, WeaponType::Repeater, 10.0);
    assert_eq!(
        fighter(&mut state, victim)
            .inventory
            .carried(AmmoPool::Bullets),
        50 + WeaponType::Repeater.pickup_rounds()
    );
    let (x, z) = {
        let p = fighter(&mut state, victim);
        (p.x, p.z)
    };
    assert!(state.hit_for_test(killer, victim, 1000));
    assert_eq!(
        state.dropped_guns[0].rounds,
        WeaponType::Repeater.pickup_rounds()
    );
    step_onto(&mut state, killer, x, z);
    let p = fighter(&mut state, killer);
    assert!(p.inventory.owns(WeaponType::Repeater));
    assert_eq!(
        p.inventory.carried(AmmoPool::Bullets),
        50 + WeaponType::Repeater.pickup_rounds()
    );
}

#[test]
fn several_drops_go_to_several_fighters_in_one_tick() {
    let mut state = ffa();
    let a = join(&mut state, 1);
    let b = join(&mut state, 2);
    for (serial, weapon, x) in [(1, WeaponType::Rocket, 4.0), (2, WeaponType::Scatter, -8.0)] {
        state.dropped_guns.push(DroppedGun {
            serial,
            weapon,
            rounds: 3,
            x,
            y: 0.4,
            z: -30.0,
            floor: 0.0,
            expires_at: 10_000,
        });
    }
    for (id, x) in [(a, 4.0), (b, -8.0)] {
        let p = fighter(&mut state, id);
        p.x = x;
        p.z = -30.0;
        p.y = PLAYER_FLOOR_Y;
    }
    state.tick(DT);
    assert!(state.dropped_guns.is_empty());
    assert!(fighter(&mut state, a).inventory.owns(WeaponType::Rocket));
    assert!(fighter(&mut state, b).inventory.owns(WeaponType::Scatter));
}

#[test]
fn the_floor_holds_at_most_sixteen_and_the_oldest_goes_first() {
    let mut state = ffa();
    let killer = join(&mut state, 1);
    let victim = join(&mut state, 2);
    for _ in 0..MAX_DROPPED_GUNS + 3 {
        arm(&mut state, victim, WeaponType::Scatter, 10.0);
        let p = fighter(&mut state, victim);
        p.hp = 100;
        p.respawn_timer = None;
        assert!(state.hit_for_test(killer, victim, 1000));
    }
    assert_eq!(state.dropped_guns.len(), MAX_DROPPED_GUNS);
    assert_eq!(state.dropped_guns[0].serial, 4, "the three oldest went");
    assert_eq!(state.guns_dropped(), 19);
}

#[test]
fn a_gun_dropped_off_a_ledge_rests_where_a_body_can_stand_and_be_routed_to() {
    // Fighters on the lip of a Tripoint Works yard deck and stair, their
    // centres out over the ground: the roster stall of 2026-10-27, where a
    // gun at the foot of the face had no floor for the navigator and froze a
    // Pistol-only fighter routing to it for its whole fifteen seconds.
    for (x, z, feet) in [(57.541_02, 22.610_464, 2.0), (65.179_665, 28.280_99, 1.5)] {
        let mut state = GameState::with_map(MapKind::TripointWorks, false);
        state.seed(42);
        state.config = MatchConfig {
            warmup_ticks: 1,
            boss_spawn_ticks: None,
            compliance_ping_ticks: None,
            time_limit_ticks: None,
            frag_limit: None,
            ..MatchConfig::default()
        };
        state.start_round();
        let killer = join(&mut state, 1);
        let victim = join(&mut state, 2);
        arm(&mut state, killer, WeaponType::Tack, -20.0);
        let p = fighter(&mut state, victim);
        p.inventory.grant_weapon(WeaponType::Scatter);
        p.weapon = WeaponType::Scatter;
        p.x = x;
        p.z = z;
        p.y = feet + PLAYER_FLOOR_Y;
        let arena = state.current_arena().into_owned();
        let fell_at = arena.support_height(x, z, feet);
        assert!(
            arena.blocked_body_at(x, z, fell_at, fell_at + crate::movement::STEP_UP),
            "the fall spot itself is inside the face"
        );

        assert!(state.hit_for_test(killer, victim, 1000));
        let gun = state.dropped_guns[0].clone();
        assert_eq!(gun.floor, fell_at);
        assert!(!arena.blocked_body_at(
            gun.x,
            gun.z,
            gun.floor,
            gun.floor + crate::movement::STEP_UP
        ));
        assert!(
            (gun.x - x).hypot(gun.z - z) <= 1.2,
            "it slides off the face, no further: ({}, {})",
            gun.x,
            gun.z
        );
        let world = crate::navigation::Navigation::shared(arena).unwrap();
        assert_eq!(
            world.coordinate_floor([gun.x, gun.y, gun.z]),
            Some(gun.floor),
            "a controller routing to the gun finds its floor"
        );

        // And it is still a gun someone walks up and takes.
        let taker = join(&mut state, 3);
        step_onto(&mut state, taker, gun.x, gun.z);
        assert!(state.dropped_guns.is_empty());
        assert!(fighter(&mut state, taker)
            .inventory
            .owns(WeaponType::Scatter));
    }
}
