//! The podium ready-up and the Duel: seats, series, the rematch line, and the
//! Continuance staying out of a one versus one.
use super::*;
use crate::protocol::{Action, GameEvent, Mutator};
use crate::rules::RuleSet;
use crate::sim::{BotController, MapKind, MatchConfig, RoundState};

const DT: f32 = 0.05;

fn room(mode: GameMode) -> GameState {
    let mut state = GameState::with_map(MapKind::ArenaDuel, false);
    state.seed(7);
    state.apply_config(MatchConfig {
        rules: RuleSet::new(mode, &[], false).unwrap(),
        warmup_ticks: 1,
        ..MatchConfig::default()
    });
    state.start_round();
    state
}

fn join(state: &mut GameState, n: u128, role: Role) -> Uuid {
    let id = Uuid::from_u128(n);
    state.add_player(id, format!("F{n}"), role);
    id
}

fn bot(state: &mut GameState, n: u128) -> Uuid {
    let id = join(state, n, Role::Agent);
    state
        .bots
        .push(BotController::new(id, crate::sim::BotBehavior::Balanced));
    id
}

fn again(state: &mut GameState, id: Uuid) {
    state.set_action(
        id,
        Action {
            again: true,
            ..Action::default()
        },
    );
}

fn score(state: &mut GameState, id: Uuid, frags: u32) {
    state.scores.insert(id, frags);
}

fn round_starts(state: &mut GameState) -> u32 {
    let before = state.round_number;
    for tick in 1..=state.config.end_delay_ticks + 2 {
        state.tick(DT);
        if state.round_number != before {
            return tick;
        }
    }
    panic!("the next round never started");
}

#[test]
fn a_room_that_all_presses_again_skips_the_podium_after_two_seconds() {
    let mut state = room(GameMode::Ffa);
    let a = join(&mut state, 1, Role::Human);
    let b = join(&mut state, 2, Role::Agent);
    bot(&mut state, 3);
    state.end_round("Frag limit reached".into());
    let podium = state.snapshot().podium.expect("a podium while ended");
    assert_eq!((podium.voters, podium.again.len()), (2, 0));
    again(&mut state, a);
    let podium = state.snapshot().podium.unwrap();
    assert_eq!(podium.again, vec![a]);
    // One of two is not a room: still waiting at the minimum.
    for _ in 0..crate::rules::AGAIN_MIN_TICKS {
        state.tick(DT);
    }
    assert_eq!(state.round_state, RoundState::Ended);
    again(&mut state, b);
    state.tick(DT);
    assert_eq!(state.round_state, RoundState::Active);
    assert!(state.again.is_empty(), "a new round forgets the ready-up");
    assert!(state.snapshot().podium.is_none());
}

#[test]
fn the_ready_up_waits_out_the_minimum_and_bots_never_hold_it_up() {
    let mut state = room(GameMode::Ffa);
    let human = join(&mut state, 1, Role::Human);
    bot(&mut state, 2);
    bot(&mut state, 3);
    state.end_round("Time limit reached".into());
    again(&mut state, human);
    let ticks = round_starts(&mut state);
    assert_eq!(ticks, crate::rules::AGAIN_MIN_TICKS, "{ticks}");
    // A rule bot pressing is ignored, and a bots-only room keeps the clock.
    let mut quiet = room(GameMode::Ffa);
    let only = bot(&mut quiet, 4);
    quiet.end_round("Time limit reached".into());
    again(&mut quiet, only);
    assert!(quiet.again.is_empty() && quiet.snapshot().podium.is_none());
    assert_eq!(round_starts(&mut quiet), quiet.config.end_delay_ticks);
}

#[test]
fn again_counts_only_on_an_ended_arena_podium() {
    let mut state = room(GameMode::Ffa);
    let a = join(&mut state, 1, Role::Human);
    again(&mut state, a);
    assert!(state.again.is_empty(), "nothing to skip mid-round");
    let mut sabotage = GameState::with_map(MapKind::Sector9, false);
    sabotage.apply_config(MatchConfig {
        rules: RuleSet::new(GameMode::Sabotage, &[], false).unwrap(),
        ..MatchConfig::default()
    });
    sabotage.start_round();
    let s = join(&mut sabotage, 2, Role::Human);
    sabotage.end_round("round".into());
    again(&mut sabotage, s);
    assert!(sabotage.again.is_empty(), "Sabotage keeps its own break");
    // An eliminated fighter on the podium still counts.
    let mut lives = GameState::with_map(MapKind::ArenaDuel, false);
    lives.apply_config(MatchConfig {
        rules: RuleSet::new(GameMode::Ffa, &[Mutator::TwoLives], false).unwrap(),
        ..MatchConfig::default()
    });
    lives.start_round();
    let out = join(&mut lives, 3, Role::Human);
    lives.players[0].eliminated = true;
    lives.end_round("Last fighter standing".into());
    again(&mut lives, out);
    assert!(lives.again.contains(&out));
}

#[test]
fn a_duel_seats_two_and_keeps_the_continuance_out() {
    let mut state = room(GameMode::Duel);
    assert_eq!(state.fighter_seats(), Some(2));
    let a = join(&mut state, 1, Role::Human);
    let b = join(&mut state, 2, Role::Human);
    join(&mut state, 3, Role::Human);
    assert_eq!(state.players.len(), 2, "a third fighter is not seated");
    assert!(state.players.iter().all(|p| [a, b].contains(&p.id)));
    // The free-for-all Pistol start and the lot's Rocket.
    assert_eq!(state.players[0].weapon, crate::protocol::WeaponType::Tack);
    assert!(state
        .pickups
        .iter()
        .any(|p| p.id == crate::maps::larak_lot::ROCKET_ID));
    assert!(!GameMode::Duel.pressure());
    state.config.compliance_ping_ticks = Some(1);
    state.config.boss_spawn_ticks = Some(1);
    for _ in 0..10 {
        state.tick(DT);
    }
    assert!(!state.compliance_fired && !state.boss_spawned);
}

#[test]
fn a_duel_series_follows_the_pair_and_the_host_calls_the_rematch() {
    let mut state = room(GameMode::Duel);
    let a = join(&mut state, 1, Role::Human);
    let b = join(&mut state, 2, Role::Agent);
    assert_eq!(state.duel_open_line(), None, "no rematch before a round");
    score(&mut state, a, 10);
    score(&mut state, b, 7);
    state.end_round("Frag limit reached".into());
    let duel = state.snapshot().podium.unwrap().duel.unwrap();
    assert_eq!(
        duel.iter().map(|d| (d.id, d.wins)).collect::<Vec<_>>(),
        vec![(a, 1), (b, 0)]
    );
    // Both press: the rematch opens with the Host on the series.
    again(&mut state, a);
    again(&mut state, b);
    round_starts(&mut state);
    let line = state
        .take_events()
        .into_iter()
        .rev()
        .find_map(|event| match event {
            GameEvent::RoundStart { host_line, .. } => Some(host_line),
            _ => None,
        })
        .unwrap();
    assert_eq!(line, "HOST: REMATCH. F1 LEADS 1 TO 0.");
    // A level round counts for nobody; the other side draws level after.
    score(&mut state, a, 3);
    score(&mut state, b, 3);
    state.end_round("Level after sudden death".into());
    assert_eq!(state.duel_series.as_ref().unwrap().wins, [1, 0]);
    state.start_round();
    score(&mut state, b, 5);
    state.end_round("Frag limit reached".into());
    assert_eq!(state.duel_series.as_ref().unwrap().wins, [1, 1]);
    assert_eq!(
        state.duel_open_line().unwrap(),
        "HOST: REMATCH. LEVEL AT 1 EACH."
    );
    // A new opponent starts a new series.
    state.remove_player(b);
    let c = join(&mut state, 3, Role::Human);
    state.start_round();
    score(&mut state, c, 2);
    state.end_round("Time limit reached".into());
    let series = state.duel_series.as_ref().unwrap();
    assert_eq!((series.ids, series.wins), ([a, c], [0, 1]));
    assert_eq!(
        state.duel_open_line().unwrap(),
        "HOST: REMATCH. F3 LEADS 1 TO 0."
    );
}

#[test]
fn a_level_duel_names_no_winner_while_a_level_free_for_all_keeps_its_podium_order() {
    for (mode, expected) in [(GameMode::Duel, None), (GameMode::Ffa, Some("F1"))] {
        let mut state = room(mode);
        let a = join(&mut state, 1, Role::Human);
        let b = join(&mut state, 2, Role::Human);
        score(&mut state, a, 3);
        score(&mut state, b, 3);
        state.end_round("Level after sudden death".into());
        assert_eq!(state.ended_mvp.as_deref(), expected, "{mode:?}");
    }
    let mut goalless = room(GameMode::Duel);
    join(&mut goalless, 1, Role::Human);
    join(&mut goalless, 2, Role::Human);
    goalless.end_round("Time limit reached".into());
    assert_eq!(goalless.ended_mvp, None);
    assert_eq!(goalless.duel_series.as_ref().unwrap().wins, [0, 0]);
}

#[test]
fn a_fighter_fragged_at_the_whistle_starts_the_rematch_alive() {
    let mut state = room(GameMode::Duel);
    let a = join(&mut state, 1, Role::Human);
    let b = join(&mut state, 2, Role::Human);
    assert!(state.hit_for_test(a, b, 1000));
    let down = state.players.iter().find(|p| p.id == b).unwrap();
    assert!(down.hp <= 0 && down.respawn_timer.is_some());
    state.players.iter_mut().find(|p| p.id == a).unwrap().hp = 30;
    state.end_round("Frag limit reached".into());
    again(&mut state, a);
    again(&mut state, b);
    round_starts(&mut state);
    let winner = state.players.iter().find(|p| p.id == a).unwrap();
    assert_eq!(winner.hp, 100, "the winner starts the rematch fresh too");
    let back = state.players.iter().find(|p| p.id == b).unwrap();
    assert!(
        back.hp > 0 && back.respawn_timer.is_none(),
        "{} {:?}",
        back.hp,
        back.respawn_timer
    );
    assert_eq!(back.weapon, crate::protocol::WeaponType::Tack);
}

#[test]
fn the_last_fighter_standing_takes_a_two_lives_duel_round() {
    let mut state = GameState::with_map(MapKind::ArenaDuel, false);
    state.apply_config(MatchConfig {
        rules: RuleSet::new(GameMode::Duel, &[Mutator::TwoLives], false).unwrap(),
        ..MatchConfig::default()
    });
    state.start_round();
    let a = join(&mut state, 1, Role::Human);
    let b = join(&mut state, 2, Role::Human);
    score(&mut state, a, 1);
    state.settle_duel(Some("F2"));
    let series = state.duel_series.as_ref().unwrap();
    assert_eq!((series.ids, series.wins), ([a, b], [0, 1]));
    assert_eq!(
        state.duel_open_line().unwrap(),
        "HOST: REMATCH. F2 LEADS 1 TO 0."
    );
    // Without two fighters there is no series.
    state.remove_player(b);
    state.settle_duel(None);
    assert!(state.duel_series.is_none());
    assert_eq!(state.duel_open_line(), None);
}

#[test]
fn the_podium_and_the_again_key_round_trip_on_the_wire() {
    let podium = Podium {
        again: vec![Uuid::from_u128(1)],
        voters: 2,
        duel: Some([
            DuelRecord {
                id: Uuid::from_u128(1),
                name: "Nightfall".into(),
                wins: 2,
            },
            DuelRecord {
                id: Uuid::from_u128(2),
                name: "You".into(),
                wins: 1,
            },
        ]),
    };
    let text = serde_json::to_string(&podium).unwrap();
    assert_eq!(serde_json::from_str::<Podium>(&text).unwrap(), podium);
    let empty = serde_json::to_value(Podium {
        again: Vec::new(),
        voters: 1,
        duel: None,
    })
    .unwrap();
    assert_eq!(empty, serde_json::json!({"voters": 1}));
    let action: Action = serde_json::from_str(r#"{"again": true}"#).unwrap();
    assert!(action.again);
    assert!(!serde_json::to_string(&Action::default())
        .unwrap()
        .contains("again"));
}

/// One rule-bot round on Larak Lot under a mode: frags, the first frag's
/// second, Rocket frags, and claims of the Plate and the Rocket.
fn lot_probe(mode: GameMode, bots: usize, seconds: u32, seed: u64) -> [u32; 5] {
    use crate::protocol::{GameEvent, ServerMessage, WeaponType};
    let mut session = crate::session::GameSession::with_map(MapKind::ArenaDuel, false);
    session.state.seed(seed);
    session.state.apply_config(MatchConfig {
        rules: RuleSet::new(mode, &[], false).unwrap(),
        frag_limit: None,
        time_limit_ticks: None,
        ..MatchConfig::default()
    });
    session.spawn_bots(bots);
    session.state.start_round();
    let mut out = [0, 0, 0, 0, 0];
    for tick in 0..seconds * 20 {
        for message in session.tick_messages(0.05) {
            match message {
                ServerMessage::Event(GameEvent::Frag { weapon, .. }) => {
                    if out[0] == 0 {
                        out[1] = tick / 20;
                    }
                    out[0] += 1;
                    if weapon == Some(WeaponType::Rocket) {
                        out[2] += 1;
                    }
                }
                ServerMessage::Event(GameEvent::Pickup { pickup_id, .. }) => {
                    if pickup_id == crate::maps::larak_lot::PLATE_ID {
                        out[3] += 1;
                    }
                    if pickup_id == crate::maps::larak_lot::ROCKET_ID {
                        out[4] += 1;
                    }
                }
                _ => {}
            }
        }
    }
    out
}

/// Prints how rule bots use the lot's power items and how often they meet:
/// `cargo test -p fragr-server --lib lot_power_probe -- --ignored --nocapture`.
#[test]
#[ignore = "prints the rule-bot Duel and free-for-all power-item probe"]
fn lot_power_probe() {
    println!("| Mode | Bots | Seed | Frags/min | First frag | Rocket frags | Plate claims | Rocket claims |");
    for (mode, bots) in [(GameMode::Duel, 2), (GameMode::Ffa, 4), (GameMode::Ffa, 6)] {
        for seed in [42, 67, 1993] {
            let [frags, first, rocket, plate, launcher] = lot_probe(mode, bots, 180, seed);
            println!(
                "| {} | {bots} | {seed} | {:.1} | {first} s | {rocket} | {plate} | {launcher} |",
                mode.id(),
                frags as f32 / 3.0
            );
        }
    }
}

/// A rocket outlives its owner's life. Snapshots list only living fighters,
/// so a Pit Rocket still in flight after its owner dies has an owner absent
/// from `players`, and every other documented rocket bound still holds.
#[test]
fn larak_rockets_outlive_their_owners_on_the_wire() {
    use crate::protocol::ServerMessage;
    let mut session = crate::session::GameSession::with_map(MapKind::ArenaDuel, false);
    session.state.seed(1993);
    session.state.apply_config(MatchConfig {
        rules: RuleSet::new(GameMode::Ffa, &[], false).unwrap(),
        frag_limit: None,
        time_limit_ticks: None,
        ..MatchConfig::default()
    });
    session.spawn_bots(6);
    session.state.start_round();
    let mut orphans = 0;
    for _ in 0..60 * 20 {
        for message in session.tick_messages(DT) {
            let ServerMessage::Snapshot(snapshot) = message else {
                continue;
            };
            let mut ids: Vec<u32> = Vec::new();
            ids.extend(snapshot.grenades.iter().map(|fact| fact.id));
            ids.extend(snapshot.mines.iter().map(|fact| fact.id));
            ids.extend(snapshot.remote_mines.iter().map(|fact| fact.id));
            ids.extend(snapshot.projectiles.iter().map(|fact| fact.id));
            ids.extend(snapshot.explosions.iter().map(|fact| fact.id));
            ids.extend(snapshot.assessor_canisters.iter().map(|fact| fact.id));
            for rocket in &snapshot.rockets {
                assert!(rocket.validate().is_ok(), "{rocket:?}");
                assert!(!ids.contains(&rocket.id), "serial {} reused", rocket.id);
                assert!(u64::from(rocket.age_ticks) <= snapshot.tick);
                assert!(session
                    .state
                    .players
                    .iter()
                    .any(|p| p.id == rocket.owner_id));
                if !snapshot.players.iter().any(|p| p.id == rocket.owner_id) {
                    orphans += 1;
                }
                ids.push(rocket.id);
            }
        }
    }
    assert!(
        orphans > 0,
        "seed 1993 flies a rocket past its owner's death"
    );
}
