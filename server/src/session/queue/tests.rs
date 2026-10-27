//! The Duel line: joining and leaving it, calls to an open seat, the held
//! seat's admission, winner-stays at a decided round and nothing at a level
//! one.
use super::*;
use crate::protocol::{BodyKind, GameEvent, Role};
use crate::rules::RuleSet;
use crate::sim::{MapKind, MatchConfig};

fn room(mode: GameMode) -> GameSession {
    let mut session = GameSession::with_map(MapKind::ArenaDuel, false);
    session.state.apply_config(MatchConfig {
        rules: RuleSet::new(mode, &[], false).unwrap(),
        warmup_ticks: 1,
        boss_spawn_ticks: None,
        compliance_ping_ticks: None,
        ..MatchConfig::default()
    });
    session.state.start_round();
    session
}

fn watcher(session: &mut GameSession, n: u128, name: &str) -> Uuid {
    let id = Uuid::from_u128(n);
    session.apply_command(GameCommand::Connected {
        id,
        role: Role::Spectator,
        name: name.into(),
        player_id: None,
        body: BodyKind::Human,
    });
    id
}

fn fighter(session: &mut GameSession, n: u128, name: &str) -> (Uuid, Uuid) {
    let (client, player) = (Uuid::from_u128(n), Uuid::from_u128(n + 1000));
    session.apply_command(GameCommand::Connected {
        id: client,
        role: Role::Human,
        name: name.into(),
        player_id: Some(player),
        body: BodyKind::Human,
    });
    (client, player)
}

fn queue(session: &mut GameSession, client_id: Uuid, wait: bool) {
    session.apply_command(GameCommand::Queue { client_id, wait });
}

fn calls(session: &mut GameSession) -> Vec<(Uuid, String)> {
    session
        .take_unicasts()
        .into_iter()
        .filter_map(|(to, message)| match (to, message) {
            (Recipient::Client(id), ServerMessage::SeatCall { seat }) => Some((id, seat)),
            _ => None,
        })
        .collect()
}

fn next_up(session: &mut GameSession) -> Vec<(Option<String>, Option<String>)> {
    session
        .state
        .take_events()
        .into_iter()
        .filter_map(|event| match event {
            GameEvent::HostReaction {
                kind: HostReactionKind::NextUp,
                player,
                other,
                ..
            } => Some((player, other)),
            _ => None,
        })
        .collect()
}

#[test]
fn watchers_join_and_leave_the_line_in_order_and_only_in_a_duel() {
    let mut ffa = room(GameMode::Ffa);
    let w = watcher(&mut ffa, 1, "Nana");
    queue(&mut ffa, w, true);
    assert!(ffa.state.snapshot().duel_queue.is_empty());

    let mut duel = room(GameMode::Duel);
    let a = watcher(&mut duel, 1, "Nana");
    let b = watcher(&mut duel, 2, "Static");
    let (f, _) = fighter(&mut duel, 3, "Fighter");
    queue(&mut duel, a, true);
    queue(&mut duel, b, true);
    queue(&mut duel, a, true);
    queue(&mut duel, f, true);
    assert_eq!(duel.state.snapshot().duel_queue, ["Nana", "Static"]);
    let json = serde_json::to_value(duel.state.snapshot()).unwrap();
    assert_eq!(json["duel_queue"][1], "Static");
    queue(&mut duel, a, false);
    assert_eq!(duel.state.snapshot().duel_queue, ["Static"]);
    duel.apply_command(GameCommand::Disconnected { id: b });
    assert!(duel.state.snapshot().duel_queue.is_empty());
    assert!(serde_json::to_value(duel.state.snapshot())
        .unwrap()
        .get("duel_queue")
        .is_none());
}

#[test]
fn an_open_seat_calls_the_head_of_the_line_and_holds_it_for_them() {
    let mut duel = room(GameMode::Duel);
    let slots = duel.configure_fighter_seats().unwrap();
    let _taken = Arc::clone(&slots).try_acquire_owned().unwrap();
    let a = watcher(&mut duel, 1, "Nana");
    let b = watcher(&mut duel, 2, "Static");
    queue(&mut duel, a, true);
    queue(&mut duel, b, true);
    duel.take_unicasts();
    duel.state.take_events();
    duel.tick_duel_queue();
    let called = calls(&mut duel);
    assert_eq!(called.len(), 1);
    assert_eq!(called[0].0, a);
    assert_eq!(next_up(&mut duel), [(Some("Nana".to_string()), None)]);
    assert_eq!(duel.state.snapshot().duel_queue, ["Static"]);
    // Held: nobody else is called, and only the token is admitted.
    duel.tick_duel_queue();
    assert!(calls(&mut duel).is_empty());
    assert_eq!(duel.held_seats(), 1);
    let holds = duel.seat_holds();
    let now = Instant::now();
    assert_eq!(admit(&holds, None, now), Admit::Held);
    assert_eq!(admit(&holds, Some("not-it"), now), Admit::Held);
    assert_eq!(admit(&holds, Some(&called[0].1), now), Admit::Holder);
    assert_eq!(admit(&holds, None, now), Admit::Open);
    // The next open seat goes to the next in line.
    duel.tick_duel_queue();
    assert_eq!(calls(&mut duel)[0].0, b);
}

#[test]
fn a_lapsed_call_frees_the_seat() {
    let holds = SeatHolds::default();
    *holds.lock().unwrap() = Some(SeatHold {
        token: "abc".into(),
        deadline: Instant::now(),
    });
    assert_eq!(admit(&holds, None, Instant::now()), Admit::Open);
    assert!(holds.lock().unwrap().is_none());
}

#[test]
fn the_winner_stays_and_the_loser_passes_the_seat_to_the_line() {
    let mut duel = room(GameMode::Duel);
    let slots = duel.configure_fighter_seats().unwrap();
    let _one = Arc::clone(&slots).try_acquire_owned().unwrap();
    let _two = Arc::clone(&slots).try_acquire_owned().unwrap();
    let (_winner_client, winner) = fighter(&mut duel, 1, "Winner");
    let (loser_client, loser) = fighter(&mut duel, 2, "Loser");
    let w = watcher(&mut duel, 3, "Next");
    queue(&mut duel, w, true);
    duel.tick_duel_queue();
    assert!(calls(&mut duel).is_empty(), "both seats are people's");
    duel.state.scores.insert(winner, 3);
    duel.state.scores.insert(loser, 1);
    duel.state.end_round("Time".into());
    duel.state.take_events();
    duel.tick_duel_queue();
    assert_eq!(duel.take_seat_passes(), [loser_client]);
    assert_eq!(calls(&mut duel)[0].0, w);
    assert_eq!(
        next_up(&mut duel),
        [(Some("Next".to_string()), Some("Winner".to_string()))]
    );
    // Once a round.
    duel.tick_duel_queue();
    assert!(duel.take_seat_passes().is_empty());
}

#[test]
fn a_level_round_passes_nobody() {
    let mut duel = room(GameMode::Duel);
    let slots = duel.configure_fighter_seats().unwrap();
    let _one = Arc::clone(&slots).try_acquire_owned().unwrap();
    let _two = Arc::clone(&slots).try_acquire_owned().unwrap();
    let (_, a) = fighter(&mut duel, 1, "A");
    let (_, b) = fighter(&mut duel, 2, "B");
    let w = watcher(&mut duel, 3, "Next");
    queue(&mut duel, w, true);
    duel.state.scores.insert(a, 2);
    duel.state.scores.insert(b, 2);
    duel.state.end_round("Time".into());
    duel.tick_duel_queue();
    assert!(duel.take_seat_passes().is_empty());
    assert!(calls(&mut duel).is_empty());
    assert_eq!(duel.state.snapshot().duel_queue, ["Next"]);
}

#[test]
fn leaving_duel_empties_the_line() {
    let mut duel = room(GameMode::Duel);
    let a = watcher(&mut duel, 1, "Nana");
    queue(&mut duel, a, true);
    duel.state.apply_config(MatchConfig {
        rules: RuleSet::new(GameMode::Ffa, &[], false).unwrap(),
        ..MatchConfig::default()
    });
    duel.tick_duel_queue();
    assert!(duel.state.snapshot().duel_queue.is_empty());
}
