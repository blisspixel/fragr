//! Grudges from the book: who a rule bot owes, the words when it settles,
//! and the fighter it looks for first.
use super::super::{BotBehavior, BotController, GameState, PLAYER_FLOOR_Y};
use crate::protocol::{GameEvent, Role, WeaponType};
use uuid::Uuid;

/// A live free-for-all round on Larak Lot with Nightfall (a rule bot) and
/// two people, everyone on the ground floor and past their spawn shields.
fn room() -> (GameState, Uuid, Uuid, Uuid) {
    let mut state = GameState::arsenal();
    state.seed(9);
    state.start_round();
    let (bot, owed, other) = (Uuid::from_u128(1), Uuid::from_u128(2), Uuid::from_u128(3));
    state.add_player(bot, "Nightfall".into(), Role::Agent);
    state
        .bots
        .push(BotController::new(bot, BotBehavior::Defensive));
    state.add_player(owed, "Meat Proxy".into(), Role::Human);
    state.add_player(other, "Hermes".into(), Role::Human);
    for (player, x) in state.players.iter_mut().zip([-5.0, 5.0, 2.0]) {
        player.x = x;
        player.z = 0.0;
        player.y = PLAYER_FLOOR_Y;
        player.yaw = 0.0;
        player.weapon = WeaponType::Rail;
    }
    state.spawn_shields.clear();
    (state, bot, owed, other)
}

fn frag(state: &mut GameState, killer: usize, victim: usize) {
    state.players[victim].hp = 1;
    state.players[victim].armor = 0;
    let _ = state.resolve_fighter_hit_for(killer, victim, 500, None, false, Some(WeaponType::Rail));
}

fn spoken(state: &mut GameState) -> Vec<(String, Option<Uuid>)> {
    state
        .take_events()
        .into_iter()
        .filter_map(|event| match event {
            GameEvent::Speak { text, to_id, .. } => Some((text, to_id)),
            _ => None,
        })
        .collect()
}

fn revive(state: &mut GameState, index: usize) {
    let player = &mut state.players[index];
    player.hp = 100;
    player.respawn_timer = None;
    player.last_speak_tick = None;
    state.players[0].last_speak_tick = None;
}

#[test]
fn a_bot_owes_the_fighter_present_who_fragged_it_most() {
    let (mut state, bot, owed, _) = room();
    assert_eq!(
        state.grudge_of("Nightfall"),
        None,
        "a clean book holds nothing"
    );
    state.head_to_head.record("Meat Proxy", "Nightfall");
    state.head_to_head.record("Meat Proxy", "Nightfall");
    state.head_to_head.record("Hermes", "Nightfall");
    state.head_to_head.record("Nightfall", "Hermes");
    assert_eq!(state.grudge_of("Nightfall"), Some(owed));
    assert!(state.settles_grudge(bot, "Nightfall", "Meat Proxy"));
    assert!(!state.settles_grudge(bot, "Nightfall", "Hermes"));
    // People do not taunt from the table: only a named rule bot settles.
    assert!(!state.settles_grudge(owed, "Meat Proxy", "Nightfall"));
    // Somebody who left is not owed in this room.
    state.remove_player(owed);
    assert_eq!(state.grudge_of("Nightfall"), None);
}

#[test]
fn settling_a_grudge_is_said_to_the_fighter_owed_and_written_in_the_book() {
    let (mut state, _, owed, _) = room();
    state.head_to_head.record("Meat Proxy", "Nightfall");
    state.head_to_head.record("Meat Proxy", "Nightfall");
    let _ = state.take_events();
    frag(&mut state, 0, 1);
    assert_eq!(state.head_to_head.frags("Nightfall", "Meat Proxy"), 1);
    // The podium's session book takes the same frag.
    assert_eq!(state.session_book.frags("Nightfall", "Meat Proxy"), 1);
    let said = spoken(&mut state);
    let (line, to) = said
        .iter()
        .find(|(_, to)| *to == Some(owed))
        .expect("the payback is said to the fighter owed");
    assert_eq!(*to, Some(owed));
    // The Night Watch register: capitals, no punctuation, the name in it.
    assert!(line.ends_with("MEAT PROXY"), "{line}");
    assert!(
        line.chars()
            .all(|c| c.is_ascii_uppercase() || c.is_ascii_digit() || c == ' '),
        "{line}"
    );
    // Still owed one: the next frag settles again. Then the book is square
    // and a third frag is an ordinary one.
    revive(&mut state, 1);
    frag(&mut state, 0, 1);
    assert!(spoken(&mut state)
        .iter()
        .any(|(text, to)| *to == Some(owed) && text.ends_with("MEAT PROXY")));
    assert_eq!(state.grudge_of("Nightfall"), None);
    revive(&mut state, 1);
    state.tick += 1;
    frag(&mut state, 0, 1);
    assert!(
        spoken(&mut state)
            .iter()
            .all(|(text, _)| !text.ends_with("MEAT PROXY")),
        "no grudge left to settle"
    );
    assert_eq!(state.head_to_head.frags("Nightfall", "Meat Proxy"), 3);
}
