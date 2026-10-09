use super::*;
use crate::protocol::Role;
use crate::sim::{BotBehavior, MapKind, MatchConfig};
use uuid::Uuid;

fn game() -> GameState {
    let mut state = GameState::with_map(MapKind::HoldfastAtoll, false);
    state.apply_config(MatchConfig {
        rules: crate::rules::RuleSet::new(GameMode::Conquest, &[], false).unwrap(),
        frag_limit: None,
        time_limit_ticks: None,
        boss_spawn_ticks: None,
        compliance_ping_ticks: None,
        ..Default::default()
    });
    state.round_state = RoundState::Active;
    state.round_number = 1;
    state.round_ticks = 1;
    state.seed(20261008);
    state
}

fn participant(state: &mut GameState, n: u128, team: Team, feet: [f32; 3]) -> Uuid {
    let id = Uuid::from_u128(n);
    state.add_player(id, format!("participant-{n}"), Role::Agent);
    let player = state.players.iter_mut().find(|p| p.id == id).unwrap();
    player.team = Some(team);
    player.x = feet[0];
    player.y = feet[1] + PLAYER_FLOOR_Y;
    player.z = feet[2];
    id
}

fn bot(state: &mut GameState, n: u128, team: Team, feet: [f32; 3]) -> BotController {
    let id = participant(state, n, team, feet);
    let controller = BotController::new(id, BotBehavior::Balanced);
    state.bots.push(controller.clone());
    controller
}

#[test]
fn capturing_bot_does_not_follow_waiting_teammates_ordinal() {
    let mut state = game();
    let waiting = bot(&mut state, 1, Team::Union, [-140.0, 3.0, 0.0]);
    state.players[0].hp = 0;
    state.players[0].respawn_timer = Some(1);
    let capturer = bot(&mut state, 2, Team::Union, POINTS[2].1);
    state.plan_conquest_orders(&state.bots.clone());
    let player = state
        .players
        .iter()
        .find(|p| p.id == capturer.player_id)
        .unwrap();
    let intent = capturer.conquest_intent(&state, player);
    assert!(
        !intent.action.forward,
        "an actual capturing body must stay at its site"
    );
    assert!(intent.goal.is_none());
    assert_eq!(waiting.player_id, state.bots[0].player_id);
}

#[test]
fn threatened_owned_site_precedes_empty_neutral_site() {
    let mut state = game();
    let defender = bot(&mut state, 1, Team::Union, [0.0, 3.0, -40.0]);
    participant(&mut state, 2, Team::Coalition, POINTS[0].1);
    let point = &mut state.conquest.as_mut().unwrap().points[0];
    point.owner = Some(Team::Union);
    point.contested = true;
    state.plan_conquest_orders(&state.bots.clone());
    let player = state
        .players
        .iter()
        .find(|p| p.id == defender.player_id)
        .unwrap();
    let intent = defender.conquest_intent(&state, player);
    assert_eq!(intent.goal.unwrap().feet, POINTS[0].1);
}

#[test]
fn defense_redirects_incoming_work_without_abandoning_an_active_capture() {
    let mut state = game();
    let capturer = bot(&mut state, 1, Team::Union, POINTS[2].1);
    let responder = bot(&mut state, 2, Team::Union, [-100.0, 3.0, 0.0]);
    state.plan_conquest_orders(&state.bots.clone());
    assert_eq!(destination(&state, responder.player_id), Some(POINTS[1].1));
    participant(&mut state, 3, Team::Coalition, POINTS[4].1);
    state.conquest.as_mut().unwrap().points[4].owner = Some(Team::Union);
    state.plan_conquest_orders(&state.bots.clone());
    assert_eq!(destination(&state, capturer.player_id), Some(POINTS[2].1));
    assert_eq!(destination(&state, responder.player_id), Some(POINTS[4].1));
}

fn destination(state: &GameState, id: Uuid) -> Option<[f32; 3]> {
    state
        .conquest_orders
        .point(id, state.conquest.as_ref()?)
        .map(|point| point.position)
}

#[test]
fn incoming_objectives_survive_roster_reordering_and_removed_bodies() {
    let mut state = game();
    let first = bot(&mut state, 1, Team::Union, [0.0, 3.0, 0.0]);
    let second = bot(&mut state, 2, Team::Union, [0.0, 3.0, 0.0]);
    state.plan_conquest_orders(&state.bots.clone());
    let first_goal = destination(&state, first.player_id);
    let second_goal = destination(&state, second.player_id);
    assert_ne!(first_goal, second_goal, "empty sites need distribution");
    let newcomer = bot(&mut state, 3, Team::Union, [0.0, 3.0, 0.0]);
    state.bots.reverse();
    state.plan_conquest_orders(&state.bots.clone());
    assert_eq!(destination(&state, first.player_id), first_goal);
    assert_eq!(destination(&state, second.player_id), second_goal);
    assert_ne!(destination(&state, newcomer.player_id), first_goal);
    state.remove_player(newcomer.player_id);
    state.plan_conquest_orders(&state.bots.clone());
    assert_eq!(destination(&state, newcomer.player_id), None);
    assert_eq!(destination(&state, first.player_id), first_goal);
    assert_eq!(destination(&state, second.player_id), second_goal);
}

#[test]
fn inactive_bodies_neither_receive_orders_nor_fill_defense_demand() {
    let invalid: [fn(&mut Player); 8] = [
        |p| p.hp = 0,
        |p| p.respawn_timer = Some(1),
        |p| p.detached = true,
        |p| p.eliminated = true,
        |p| p.role = Role::Spectator,
        |p| p.is_boss = true,
        |p| p.team = None,
        |p| p.campaign = Some(crate::protocol::CampaignActor::Participant {}),
    ];
    for invalidate in invalid {
        let mut state = game();
        let dormant = bot(&mut state, 1, Team::Union, POINTS[0].1);
        invalidate(&mut state.players[0]);
        let defender = bot(&mut state, 2, Team::Union, [0.0, 3.0, 0.0]);
        participant(&mut state, 3, Team::Coalition, POINTS[0].1);
        state.conquest.as_mut().unwrap().points[0].owner = Some(Team::Union);
        state.plan_conquest_orders(&state.bots.clone());
        assert_eq!(destination(&state, dormant.player_id), None);
        assert_eq!(destination(&state, defender.player_id), Some(POINTS[0].1));
    }
}

#[test]
fn exposed_seat_counts_for_capture_without_infantry_driving_orders() {
    let mut state = game();
    let occupant = bot(&mut state, 1, Team::Union, [-105.0, 3.0, 65.0]);
    state
        .add_jeep([-103.0, 3.0, 65.0], std::f32::consts::FRAC_PI_2)
        .unwrap();
    state.set_action(
        occupant.player_id,
        crate::protocol::Action {
            interact: true,
            ..Default::default()
        },
    );
    state.tick(0.05);
    assert!(
        state.vehicle_seat(occupant.player_id).is_some(),
        "ordinary boarding must succeed"
    );
    for point in state.conquest.as_mut().unwrap().points.iter_mut().skip(1) {
        point.owner = Some(Team::Union);
    }
    let walker = bot(&mut state, 2, Team::Union, [-90.0, 3.0, 65.0]);
    state.plan_conquest_orders(&state.bots.clone());
    assert_eq!(destination(&state, occupant.player_id), None);
    assert_ne!(
        destination(&state, walker.player_id),
        Some(POINTS[0].1),
        "the occupied capture already has a contributor"
    );
    let player = state
        .players
        .iter()
        .find(|p| p.id == occupant.player_id)
        .unwrap();
    let intent = occupant.conquest_intent(&state, player);
    assert!(!intent.action.forward && !intent.action.fire && intent.goal.is_none());
    assert_eq!(state.conquest.as_ref().unwrap().points[0].progress, 1);
}

#[test]
fn vertical_distance_does_not_stop_a_bot_above_a_site() {
    let mut state = game();
    let high = bot(&mut state, 1, Team::Union, [0.0, 7.0, -70.0]);
    state.plan_conquest_orders(&state.bots.clone());
    let player = state
        .players
        .iter()
        .find(|p| p.id == high.player_id)
        .unwrap();
    let intent = high.conquest_intent(&state, player);
    assert!(intent.action.forward);
    assert_eq!(intent.goal.unwrap().feet, POINTS[2].1);
    state.tick_conquest();
    assert_eq!(state.conquest.as_ref().unwrap().points[2].progress, 0);
}

#[test]
fn sixty_four_controller_plan_is_bounded_and_stable() {
    let mut state = game();
    for n in 1..=64 {
        bot(&mut state, n, Team::Union, [0.0, 3.0, -5.0]);
    }
    let mut expected = Vec::new();
    for pass in 0..3 {
        state.plan_conquest_orders(&state.bots.clone());
        let mut counts = [0usize; 5];
        let goals: Vec<_> = state
            .players
            .iter()
            .map(|p| destination(&state, p.id).unwrap())
            .collect();
        for goal in &goals {
            counts[POINTS.iter().position(|(_, point)| point == goal).unwrap()] += 1;
        }
        assert!(
            counts.iter().max().unwrap() - counts.iter().min().unwrap() <= 1,
            "{counts:?}"
        );
        let work = state.conquest_orders.evaluations;
        assert!(
            work <= 5 * state.players.len() + 33 * state.bots.len(),
            "bounded site examinations: {work}"
        );
        println!(
            "64-controller planning pass {pass}: {work} site examinations, allocation {counts:?}"
        );
        if pass == 0 {
            expected = goals;
        } else {
            assert_eq!(goals, expected);
        }
        state.bots.reverse();
    }
}

#[test]
fn reset_discards_orders_and_non_conquest_has_no_planning_work() {
    let mut state = game();
    let fighter = bot(&mut state, 1, Team::Union, [0.0, 3.0, 0.0]);
    state.plan_conquest_orders(&state.bots.clone());
    assert!(destination(&state, fighter.player_id).is_some());
    state.reset_conquest();
    assert_eq!(destination(&state, fighter.player_id), None);
    state.config.rules = crate::rules::RuleSet::default();
    state.reset_conquest();
    state.plan_conquest_orders(&state.bots.clone());
    assert_eq!(state.conquest_orders.evaluations, 0);
    assert!(state
        .conquest_orders
        .point(fighter.player_id, &initial())
        .is_none());
}

fn session(count: usize) -> crate::session::GameSession {
    session_with_first_id(count, Uuid::from_u128(1))
}

fn session_with_first_id(count: usize, first_id: Uuid) -> crate::session::GameSession {
    let mut session = crate::session::GameSession::with_map(MapKind::HoldfastAtoll, false);
    session.state = game();
    // Fix identity before ordinary admission; sensed aim also depends on UUIDs.
    session.state.use_replay_ids();
    session.state.replay_id_counter = Some(first_id.as_u128().checked_sub(1).unwrap());
    session.spawn_bots(count);
    session
}

fn position(state: &mut GameState, id: Uuid, feet: [f32; 3]) {
    let player = state.players.iter_mut().find(|p| p.id == id).unwrap();
    player.x = feet[0];
    player.y = feet[1] + PLAYER_FLOOR_Y;
    player.z = feet[2];
    player.vy = 0.0;
    player.reset_movement_baseline();
}

#[test]
fn actual_spawn_and_resolved_death_respawn_preserve_another_bots_capture() {
    let mut session = session(3);
    let ids: Vec<_> = session.bots.iter().map(|bot| bot.player_id).collect();
    for player in &mut session.state.players {
        player.team = Some(Team::Union);
    }
    position(&mut session.state, ids[0], [-105.0, 3.0, 0.0]);
    position(&mut session.state, ids[1], [-100.0, 3.0, 0.0]);
    position(&mut session.state, ids[2], POINTS[2].1);
    for _ in 0..40 {
        session.tick_messages(0.05);
    }
    assert_eq!(
        session.state.conquest.as_ref().unwrap().points[2].progress,
        40
    );
    participant(
        &mut session.state,
        800,
        Team::Coalition,
        [145.0, 3.0, -50.0],
    );
    let killer = session
        .state
        .players
        .iter()
        .position(|p| p.id == Uuid::from_u128(800))
        .unwrap();
    let victim = session
        .state
        .players
        .iter()
        .position(|p| p.id == ids[0])
        .unwrap();
    // The shared resolved damage seam creates a real death and respawn timer.
    // This fixture makes no traced shot or aim claim.
    let (_, _, died) = session
        .state
        .resolve_fighter_hit(killer, victim, 1000, None);
    assert!(died);
    assert_eq!(session.state.conquest.as_ref().unwrap().tickets.union, 199);
    assert_eq!(
        session.state.players[victim].respawn_timer,
        Some(crate::sim::RESPAWN_DELAY_TICKS)
    );
    for progress in 41..=101 {
        session.tick_messages(0.05);
        assert_eq!(
            session.state.conquest.as_ref().unwrap().points[2].progress,
            progress
        );
        assert_eq!(destination(&session.state, ids[2]), Some(POINTS[2].1));
    }
    assert!(
        session.state.players[victim].hp > 0
            && session.state.players[victim].respawn_timer.is_none()
    );
    session.spawn_bots(1);
    assert_eq!(session.bots.len(), 4);
    session.tick_messages(0.05);
    assert_eq!(
        session.state.conquest.as_ref().unwrap().points[2].progress,
        102
    );
    assert_eq!(destination(&session.state, ids[2]), Some(POINTS[2].1));
}

#[test]
fn ordinary_bots_walk_capture_and_win_through_unchanged_majority_bleed() {
    let mut session = session(3);
    let starts = [[-105.0, 3.0, 45.0], [-100.0, 3.0, -55.0], [0.0, 3.0, -50.0]];
    let ids: Vec<_> = session.bots.iter().map(|bot| bot.player_id).collect();
    for (id, start) in ids.iter().zip(starts) {
        position(&mut session.state, *id, start);
        session
            .state
            .players
            .iter_mut()
            .find(|p| p.id == *id)
            .unwrap()
            .team = Some(Team::Union);
    }
    let mut winner = None;
    for _ in 0..4500 {
        let messages = session.tick_messages(0.05);
        for message in messages {
            if let crate::protocol::ServerMessage::Event(crate::protocol::GameEvent::RoundEnd {
                winning_team,
                ..
            }) = message
            {
                winner = Some(winning_team);
            }
        }
        if session.state.round_state == RoundState::Ended {
            break;
        }
    }
    let conquest = session.state.conquest.as_ref().unwrap();
    assert_eq!(session.state.round_state, RoundState::Ended);
    assert_eq!(winner, Some(Some(Team::Union)));
    assert_eq!(conquest.tickets.coalition, 0);
    assert_eq!(conquest.tickets.union, 200);
    assert!(
        conquest
            .points
            .iter()
            .filter(|p| p.owner == Some(Team::Union))
            .count()
            >= 3
    );
    assert!(session
        .state
        .players
        .iter()
        .all(|p| p.statistics.board().0 == 0));
    println!(
        "ordinary Conquest majority win: tick {}, tickets {:?}, held {}",
        session.state.tick,
        conquest.tickets,
        conquest
            .points
            .iter()
            .filter(|p| p.owner == Some(Team::Union))
            .count()
    );
}

#[test]
fn ordinary_movement_contests_then_neutralizes_and_captures_after_withdrawal() {
    let mut session = session(1);
    let id = session.bots[0].player_id;
    position(&mut session.state, id, [-90.0, 3.0, 65.0]);
    session.state.players[0].team = Some(Team::Union);
    // Keep this controller outside striking range so the fixture isolates
    // ordinary presence and withdrawal, rather than substituting a death.
    session.state.players[0].inventory =
        crate::inventory::Inventory::restricted(crate::protocol::WeaponType::Fists);
    session.state.players[0].weapon = crate::protocol::WeaponType::Fists;
    let enemy = participant(
        &mut session.state,
        800,
        Team::Coalition,
        [-111.5, 3.0, 65.0],
    );
    session.state.conquest.as_mut().unwrap().points[0].owner = Some(Team::Coalition);
    for _ in 0..100 {
        session.tick_messages(0.05);
        if session.state.conquest.as_ref().unwrap().points[0].contested {
            break;
        }
    }
    let point = &session.state.conquest.as_ref().unwrap().points[0];
    assert!(
        point.contested,
        "ordinary walking must enter the capture radius"
    );
    let retained = point.progress;
    for _ in 0..30 {
        session.tick_messages(0.05);
        let point = &session.state.conquest.as_ref().unwrap().points[0];
        assert!(point.contested);
        assert_eq!(point.progress, retained);
        assert_eq!(point.owner, Some(Team::Coalition));
    }
    session.state.set_action(
        enemy,
        crate::protocol::Action {
            forward: true,
            yaw: Some(std::f32::consts::PI),
            ..Default::default()
        },
    );
    let mut neutral_tick = None;
    let mut capture_tick = None;
    for _ in 0..400 {
        session.tick_messages(0.05);
        let point = &session.state.conquest.as_ref().unwrap().points[0];
        if point.owner.is_none() && neutral_tick.is_none() {
            neutral_tick = Some(session.state.tick);
        }
        if point.owner == Some(Team::Union) {
            capture_tick = Some(session.state.tick);
            break;
        }
    }
    assert_eq!(
        capture_tick.unwrap() - neutral_tick.unwrap(),
        u64::from(CAPTURE_TICKS)
    );
    assert_eq!(
        session
            .state
            .players
            .iter()
            .find(|p| p.id == enemy)
            .unwrap()
            .statistics
            .board()
            .0,
        0
    );
    println!(
        "ordinary contested withdrawal: neutral tick {}, capture tick {}",
        neutral_tick.unwrap(),
        capture_tick.unwrap()
    );
}

fn clear_sensed_defender(
    mut session: crate::session::GameSession,
) -> crate::protocol::PlayerRecord {
    let id = session.bots[0].player_id;
    position(&mut session.state, id, [-90.0, 3.0, 65.0]);
    session.state.players[0].team = Some(Team::Union);
    session.state.players[0].yaw = std::f32::consts::PI;
    session.state.players[0].pitch = 0.0;
    let enemy = participant(&mut session.state, 800, Team::Coalition, POINTS[0].1);
    session.state.conquest.as_mut().unwrap().points[0].owner = Some(Team::Coalition);
    let mut hits = 0;
    let mut resolved_death = false;
    let mut effective_hp = 0_u64;
    let mut effective_armor = 0_u64;
    let mut neutralization_started = None;
    let mut neutral_tick = None;
    for _ in 0..600 {
        let defender = session
            .state
            .players
            .iter()
            .find(|p| p.id == enemy)
            .unwrap();
        // Dead internal HP can be negative. Pickups report actual gained stock.
        let before = (defender.hp.max(0), defender.armor.max(0));
        let mut resolved_hits = 0;
        let mut hp_gained = 0;
        let mut armor_gained = 0;
        for message in session.tick_messages(0.05) {
            match message {
                crate::protocol::ServerMessage::Snapshot(snapshot) => {
                    for shot in snapshot.shot_results {
                        if shot.shooter_id == id && shot.target_id == Some(enemy) {
                            if shot.hit && shot.damage > 0 {
                                resolved_hits += 1;
                            }
                            resolved_death |= shot.killed;
                        }
                    }
                }
                crate::protocol::ServerMessage::Event(crate::protocol::GameEvent::Pickup {
                    player_id,
                    kind,
                    amount: Some(gained),
                    ..
                }) if player_id == enemy => {
                    assert!(gained >= 0);
                    match kind.as_str() {
                        "health" => hp_gained += gained,
                        "armor" => armor_gained += gained,
                        _ => {}
                    }
                }
                _ => {}
            }
        }
        let defender = session
            .state
            .players
            .iter()
            .find(|p| p.id == enemy)
            .unwrap();
        let hp = u64::try_from((before.0 + hp_gained - defender.hp.max(0)).max(0)).unwrap();
        let armor =
            u64::try_from((before.1 + armor_gained - defender.armor.max(0)).max(0)).unwrap();
        if hp + armor > 0 {
            assert!(
                resolved_hits > 0,
                "effective loss needs an actual resolved shot"
            );
            hits += resolved_hits;
            effective_hp += hp;
            effective_armor += armor;
        }
        let point = &session.state.conquest.as_ref().unwrap().points[0];
        if neutralization_started.is_none()
            && point.owner == Some(Team::Coalition)
            && point.capturing == Some(Team::Union)
            && point.progress > 0
        {
            assert_eq!(point.progress, 1);
            neutralization_started = Some(session.state.tick);
        }
        if point.owner.is_none() && neutral_tick.is_none() {
            neutral_tick = Some(session.state.tick);
        }
        if point.owner == Some(Team::Union) {
            break;
        }
    }
    assert!(
        resolved_death && hits >= 1,
        "ordinary sensed damaging shots must resolve the opposing body, id={id}, hits={hits}, effective_hp={effective_hp}, effective_armor={effective_armor}"
    );
    assert_eq!(
        session.state.conquest.as_ref().unwrap().points[0].owner,
        Some(Team::Union)
    );
    assert_eq!(
        neutral_tick.unwrap() - neutralization_started.unwrap() + 1,
        u64::from(CAPTURE_TICKS)
    );
    assert_eq!(
        session.state.tick - neutral_tick.unwrap(),
        u64::from(CAPTURE_TICKS)
    );
    assert_eq!(
        session.state.conquest.as_ref().unwrap().tickets.coalition,
        199
    );
    assert_eq!(
        session
            .state
            .players
            .iter()
            .find(|p| p.id == enemy)
            .unwrap()
            .statistics
            .board()
            .0,
        1
    );
    let record = session.state.player_record(id).unwrap();
    record.validate_for(Some(id), None).unwrap();
    assert_eq!(record.total.damage_dealt(), effective_hp + effective_armor);
    assert_eq!(record.total.kills(), 1);
    assert_eq!(
        record
            .total
            .weapons
            .iter()
            .map(|weapon| weapon.hp_damage)
            .sum::<u64>(),
        effective_hp
    );
    assert_eq!(
        record
            .total
            .weapons
            .iter()
            .map(|weapon| weapon.armor_damage)
            .sum::<u64>(),
        effective_armor
    );
    assert_eq!(
        record
            .total
            .weapons
            .iter()
            .map(|weapon| weapon.damaging_attacks)
            .sum::<u64>(),
        hits
    );
    let shown = session.state.snapshot();
    let attacker = shown.players.iter().find(|player| player.id == id).unwrap();
    assert_eq!(
        attacker.damage,
        u32::try_from(effective_hp + effective_armor).unwrap()
    );
    let defender_record = session.state.player_record(enemy).unwrap();
    defender_record.validate_for(Some(enemy), None).unwrap();
    assert_eq!(
        (
            defender_record.total.hp_lost,
            defender_record.total.armor_lost
        ),
        (effective_hp, effective_armor)
    );
    assert_eq!(defender_record.total.deaths, 1);
    println!(
        "ordinary sensed defender clear: id={id}, {hits} actual damaging hits, {effective_hp} effective HP, {effective_armor} effective armor, neutral tick {}, captured tick {}",
        neutral_tick.unwrap(),
        session.state.tick
    );
    record
}

#[test]
fn sensed_ordinary_attacks_clear_a_defender_then_finish_both_capture_stages() {
    clear_sensed_defender(session(1));
}

#[test]
fn retained_identity_one_shot_head_kill_still_finishes_both_capture_stages() {
    let id = Uuid::from_u128(0xb56644a2_130f_41d8_b221_8f37b87f0892);
    let record = clear_sensed_defender(session_with_first_id(1, id));
    assert_eq!(record.player_id, id);
    assert_eq!(record.total.attacks(), 1);
    let shot = record.total.weapon(crate::protocol::WeaponType::Scatter);
    assert_eq!(
        (
            shot.damaging_attacks,
            shot.kills,
            shot.hp_damage,
            shot.heads
        ),
        (1, 1, 100, 1)
    );
}

#[test]
fn parked_hull_obstruction_cannot_capture_by_assignment_and_recovers_when_opened() {
    let mut session = session(1);
    let id = session.bots[0].player_id;
    position(&mut session.state, id, [0.0, 3.0, -50.0]);
    session.state.players[0].team = Some(Team::Union);
    let mut parked = Vec::new();
    for (x, z, yaw) in [
        (2.85, -50.0, std::f32::consts::FRAC_PI_2),
        (-2.85, -50.0, std::f32::consts::FRAC_PI_2),
        (0.0, -47.15, 0.0),
        (0.0, -52.85, 0.0),
    ] {
        parked.push(session.state.add_jeep([x, 3.0, z], yaw).unwrap());
    }
    for _ in 0..200 {
        session.tick_messages(0.05);
    }
    let player = &session.state.players[0];
    assert!(
        player.x.abs() < 1.9 && (player.z + 50.0).abs() < 1.9,
        "blocked body escaped parked hulls: [{},{},{}]",
        player.x,
        player.y,
        player.z
    );
    assert_eq!(
        session.state.conquest.as_ref().unwrap().points[2].progress,
        0
    );
    assert_eq!(
        session.state.conquest.as_ref().unwrap().points[2].owner,
        None
    );
    session.state.vehicles.retain(|v| v.state.id != parked[3]);
    for _ in 0..600 {
        session.tick_messages(0.05);
        if session.state.conquest.as_ref().unwrap().points[2].owner == Some(Team::Union) {
            break;
        }
    }
    assert_eq!(
        session.state.conquest.as_ref().unwrap().points[2].owner,
        Some(Team::Union)
    );
}
