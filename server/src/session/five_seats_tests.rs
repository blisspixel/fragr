use super::*;
use crate::movement::DT_LIVE as DT;
use crate::protocol::{GameMode, SabotagePhase, Team};
use crate::rules::{RuleSet, SabotageConfig};
use crate::sim::MatchConfig;

fn loadout(player: &crate::sim::Player) -> protocol::LoadoutState {
    player.inventory.state(player.id, player.weapon, 0).unwrap()
}

fn assert_pistol(player: &crate::sim::Player) {
    let state = loadout(player);
    assert_eq!(state.selected, protocol::WeaponType::Tack);
    assert_eq!(
        state.weapons,
        vec![protocol::WeaponType::Fists, protocol::WeaponType::Tack]
    );
    assert_eq!(
        state
            .ammo
            .iter()
            .map(|count| count.rounds)
            .collect::<Vec<_>>(),
        vec![50, 0, 0]
    );
}

#[test]
fn five_seats_watcher_waits_for_delayed_first_human_without_phantom_round() {
    let mut session = make_session(true);
    session.state.start_round();
    session.apply_command(GameCommand::Connected {
        id: Uuid::from_u128(1),
        role: Role::Spectator,
        name: "Waiting watcher".into(),
        player_id: None,
        body: protocol::BodyKind::Human,
    });
    assert!(session.state.players.is_empty());
    for _ in 0..100 {
        session.tick_messages(DT);
    }
    let wire = session.state.snapshot().sabotage.unwrap();
    assert_eq!(
        (wire.round, wire.phase, wire.clock_ticks),
        (1, SabotagePhase::Muster, 2)
    );
    assert_eq!((wire.score.union, wire.score.coalition), (0, 0));
    assert!(session.state.sabotage.as_ref().unwrap().result.is_none());

    let id = Uuid::from_u128(2);
    session.apply_command(GameCommand::Connected {
        id,
        role: Role::Human,
        name: "Delayed first human".into(),
        player_id: Some(id),
        body: protocol::BodyKind::Human,
    });
    assert_pistol(&session.state.players[0]);
    assert!(!session.state.players[0].eliminated);
    session.tick_messages(DT);
    assert_eq!(
        session.state.snapshot().sabotage.unwrap().phase,
        SabotagePhase::Muster
    );
    session.tick_messages(DT);
    let wire = session.state.snapshot().sabotage.unwrap();
    assert_eq!((wire.round, wire.phase), (1, SabotagePhase::Live));
    assert_eq!((wire.score.union, wire.score.coalition), (0, 0));
    assert!(!session.state.players[0].eliminated);
}

#[test]
fn five_seats_single_rule_bot_starts_without_a_two_side_quorum() {
    let mut session = make_session(true);
    session.state.start_round();
    for _ in 0..100 {
        session.tick_messages(DT);
    }
    session.spawn_bots(1);
    assert_eq!(session.state.players.len(), 1);
    session.tick_messages(DT);
    assert_eq!(
        session.state.snapshot().sabotage.unwrap().phase,
        SabotagePhase::Muster
    );
    session.tick_messages(DT);
    let wire = session.state.snapshot().sabotage.unwrap();
    assert_eq!((wire.round, wire.phase), (1, SabotagePhase::Live));
    assert_eq!((wire.score.union, wire.score.coalition), (0, 0));
}

#[test]
fn five_seats_pistol_first_round_survivor_carry_and_real_post_death_reset() {
    use protocol::WeaponType;
    let mut session = make_session(true);
    for n in 1..=4 {
        session
            .state
            .add_player(Uuid::from_u128(n), format!("P{n}"), Role::Agent);
        assert_pistol(session.state.players.last().unwrap());
    }
    session.state.start_round();
    for player in &session.state.players {
        assert_pistol(player);
    }
    while session.state.snapshot().sabotage.unwrap().phase == SabotagePhase::Muster {
        session.state.tick(DT);
    }
    let survivor = session.state.players[0].id;
    let victim = session.state.players[1].id;
    let pad = session
        .state
        .pickups
        .iter()
        .find(|p| p.kind.weapon() == Some(WeaponType::Rail))
        .unwrap()
        .clone();
    // The real contested map pad grants the stronger gun through tick_pickups.
    let player = &mut session.state.players[0];
    player.x = pad.x;
    player.y = pad.floor + crate::sim::PLAYER_FLOOR_Y;
    player.z = pad.z;
    assert!(player.inventory.try_fire(WeaponType::Tack));
    session.state.tick(DT);
    assert!(session.state.players[0].inventory.owns(WeaponType::Rail));
    session.state.players[0].weapon = WeaponType::Rail;
    assert!(session.state.players[0]
        .inventory
        .try_fire(WeaponType::Rail));
    let carried = loadout(&session.state.players[0]);
    assert!(session.state.hit_for_test(survivor, victim, 1000));
    assert!(session.state.players[1].eliminated);
    for _ in 0..12 {
        if session.state.snapshot().sabotage.unwrap().round == 2 {
            break;
        }
        session.state.tick(DT);
    }
    assert_eq!(session.state.snapshot().sabotage.unwrap().round, 2);
    let kept = loadout(&session.state.players[0]);
    assert_eq!(kept.weapons, carried.weapons);
    assert_eq!(kept.ammo, carried.ammo);
    assert_eq!(kept.selected, carried.selected);
    assert_pistol(&session.state.players[1]);
    assert_eq!(session.state.players[1].lives, Some(1));
    let mut generic = make_session(false);
    generic
        .state
        .add_player(Uuid::from_u128(50), "Generic".into(), Role::Human);
    assert_eq!(generic.state.players[0].weapon, WeaponType::Fists);
    assert_eq!(
        loadout(&generic.state.players[0]).weapons,
        vec![WeaponType::Fists]
    );
}

#[test]
fn five_seats_eliminated_guard_also_blocks_generic_limited_life_actions_and_pickups() {
    use protocol::{Action, Mutator, WeaponType};
    for mode in [GameMode::Ffa, GameMode::Tdm] {
        let mut session = GameSession::with_map(MapKind::Sector9, false);
        session.state.apply_config(MatchConfig {
            rules: RuleSet::new(mode, &[Mutator::TwoLives], false).unwrap(),
            frag_limit: Some(100),
            ..Default::default()
        });
        for n in 1..=4 {
            session
                .state
                .add_player(Uuid::from_u128(n), format!("L{n}"), Role::Human);
        }
        session.state.start_round();
        let id = session.state.players[0].id;
        let killer = session.state.players[1].id;
        assert!(session.state.hit_for_test(killer, id, 1000));
        for _ in 0..70 {
            session.state.tick(DT);
        }
        assert!(session.state.hit_for_test(killer, id, 1000));
        assert!(session.state.players[0].eliminated);
        let pad = session
            .state
            .pickups
            .iter()
            .find(|p| matches!(p.kind, crate::sim::PickupKind::Health))
            .unwrap()
            .clone();
        let player = &mut session.state.players[0];
        player.x = pad.x;
        player.y = pad.floor + crate::sim::PLAYER_FLOOR_Y;
        player.z = pad.z;
        // Queued work from before elimination must be cleared even without new ingress.
        player.pending_action = Action {
            forward: true,
            jump: true,
            fire: true,
            weapon_swap: Some(WeaponType::Rail),
            ..Default::default()
        };
        let position = [player.x, player.y, player.z];
        let weapon = player.weapon;
        let dead_hp = player.hp;
        session.state.set_action(
            id,
            Action {
                forward: true,
                fire: true,
                jump: true,
                weapon_swap: Some(WeaponType::Scatter),
                ..Default::default()
            },
        );
        for _ in 0..3 {
            session.state.tick(DT);
        }
        let player = &session.state.players[0];
        assert_eq!([player.x, player.y, player.z], position);
        assert_eq!(player.weapon, weapon);
        assert_eq!(player.hp, dead_hp);
        assert!(!player.just_fired);
        assert!(
            session
                .state
                .pickups
                .iter()
                .find(|p| p.id == pad.id)
                .unwrap()
                .available
        );
        assert!(!session
            .state
            .shot_results
            .iter()
            .any(|s| s.shooter_id == id));
        session.state.start_round();
        assert!(!session.state.players[0].eliminated);
        assert_eq!(session.state.players[0].lives, Some(2));
    }
}

fn make_session(strict: bool) -> GameSession {
    let mut session = GameSession::with_map(MapKind::Sector9, false);
    session.state.apply_config(MatchConfig {
        rules: RuleSet::new(GameMode::Sabotage, &[], false).unwrap(),
        sabotage: SabotageConfig {
            five_vs_five: strict,
            muster_ticks: 2,
            live_ticks: 3,
            round_end_ticks: 2,
            swap_end_ticks: 2,
            ..Default::default()
        },
        ..Default::default()
    });
    session
}

#[test]
fn five_seats_sim_preserves_dead_parked_capacity_and_vacant_side() {
    let mut session = make_session(true);
    for n in 1..=10 {
        session.state.add_player(
            Uuid::from_u128(n),
            format!("P{n}"),
            if n % 2 == 0 { Role::Human } else { Role::Agent },
        );
    }
    assert_eq!(session.state.team_counts(), [5, 5]);
    session.state.players[0].hp = 0;
    session.state.players[0].eliminated = true;
    session.state.players[1].detached = true;
    session
        .state
        .add_player(Uuid::from_u128(11), "Overflow".into(), Role::Agent);
    assert_eq!(session.state.players.len(), 10);
    assert!(!session.state.scores.contains_key(&Uuid::from_u128(11)));
    let vacated = session.state.players[2].team;
    let old_id = session.state.players[2].id;
    session.state.remove_player(old_id);
    session
        .state
        .add_player(Uuid::from_u128(12), "Replacement".into(), Role::Human);
    assert_eq!(session.state.players.last().unwrap().team, vacated);
    assert_eq!(session.state.team_counts(), [5, 5]);
}

#[test]
fn five_seats_halftime_and_live_replacement_keep_one_life_rules() {
    let mut session = make_session(true);
    session.spawn_bots(10);
    session.state.start_round();
    let original: Vec<_> = session
        .state
        .players
        .iter()
        .map(|p| (p.id, p.team))
        .collect();
    for _ in 0..100 {
        if session.state.snapshot().sabotage.unwrap().round >= 5 {
            break;
        }
        session.state.tick(DT);
    }
    let wire = session.state.snapshot().sabotage.unwrap();
    assert_eq!((wire.round, wire.half), (5, 2));
    assert_eq!(session.state.team_counts(), [5, 5]);
    for (id, old_team) in original {
        assert_eq!(
            session
                .state
                .players
                .iter()
                .find(|p| p.id == id)
                .unwrap()
                .team,
            old_team.map(Team::other)
        );
    }
    while session.state.snapshot().sabotage.unwrap().phase == SabotagePhase::Muster {
        session.state.tick(DT);
    }
    let removed = session.state.players[0].id;
    session.state.remove_player(removed);
    session
        .state
        .add_player(Uuid::from_u128(101), "Late".into(), Role::Agent);
    let pad = session
        .state
        .pickups
        .iter()
        .find(|p| p.kind.weapon() == Some(protocol::WeaponType::Rail))
        .unwrap()
        .clone();
    let late = session.state.players.last_mut().unwrap();
    assert!(late.eliminated);
    assert_eq!(late.lives, Some(0));
    assert_eq!(late.hp, 100);
    late.x = pad.x;
    late.y = pad.floor + crate::sim::PLAYER_FLOOR_Y;
    late.z = pad.z;
    let position = [late.x, late.y, late.z];
    session.state.set_action(
        Uuid::from_u128(101),
        protocol::Action {
            forward: true,
            fire: true,
            yaw: Some(0.0),
            ..Default::default()
        },
    );
    session.state.tick(DT);
    let late = session
        .state
        .players
        .iter()
        .find(|p| p.id == Uuid::from_u128(101))
        .unwrap();
    assert_eq!([late.x, late.y, late.z], position);
    assert!(!late.inventory.owns(protocol::WeaponType::Rail));
    assert!(
        session
            .state
            .pickups
            .iter()
            .find(|p| p.id == pad.id)
            .unwrap()
            .available
    );
    assert!(!session
        .state
        .shot_results
        .iter()
        .any(|shot| shot.shooter_id == Uuid::from_u128(101)));
    for _ in 0..10 {
        session.state.tick(DT);
    }
    let late = session
        .state
        .players
        .iter()
        .find(|p| p.id == Uuid::from_u128(101))
        .unwrap();
    assert!(!late.eliminated);
    assert_eq!(late.lives, Some(1));
    assert_eq!(session.state.team_counts(), [5, 5]);
}

#[test]
fn five_seats_rule_bot_refill_uses_the_network_pool_and_stops_at_capacity() {
    let mut session = make_session(true);
    let pool = session.configure_sabotage_seats().unwrap();
    session.spawn_bots(4);
    assert_eq!(pool.available_permits(), 6);
    let mut sockets: Vec<_> = (0..6)
        .map(|_| Arc::clone(&pool).try_acquire_owned().unwrap())
        .collect();
    session.set_min_bots(8);
    assert_eq!(session.bots.len(), 4);
    drop(sockets.pop());
    session.ensure_min_bots();
    assert_eq!(session.bots.len(), 5);
    assert_eq!(pool.available_permits(), 0);
    session.state.players.clear();
    session.bots.clear();
    session.state.bots.clear();
    session.ensure_min_bots();
    assert_eq!(
        session.bots.len(),
        5,
        "only five seats are available beside retained socket permits"
    );
    assert_eq!(session.state.team_counts(), [2, 3]);
}

#[test]
fn five_seats_generic_sabotage_keeps_larger_rosters() {
    let mut session = make_session(false);
    session.spawn_bots(12);
    assert_eq!(session.state.players.len(), 12);
    assert_eq!(session.state.team_counts(), [6, 6]);
    assert!(session.configure_sabotage_seats().is_none());
    session.state.config.rules =
        RuleSet::new(GameMode::Sabotage, &[protocol::Mutator::RailOnly], false).unwrap();
    session.state.start_round();
    for player in &mut session.state.players {
        assert_eq!(player.weapon, protocol::WeaponType::Rail);
        assert_eq!(player.inventory.only(), Some(protocol::WeaponType::Rail));
        for _ in 0..210 {
            assert!(player.inventory.try_fire(protocol::WeaponType::Rail));
        }
    }
}
