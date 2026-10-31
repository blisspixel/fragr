//! The rotation switch, the podium's map vote and its tie-break, rule bots
//! voting only in an empty room, and the podium story of nemesis and rivals.
use super::*;
use crate::protocol::{Action, FighterKind, Role};
use crate::rules::RuleSet;
use crate::sim::{BotBehavior, BotController, MatchConfig};

const DT: f32 = 0.05;

fn rotating(map: MapKind, mode: GameMode) -> GameState {
    let mut state = GameState::with_map(map, true);
    state.seed(7);
    state.apply_config(MatchConfig {
        rules: RuleSet::new(mode, &[], false).unwrap(),
        warmup_ticks: 1,
        ..MatchConfig::default()
    });
    state.start_round();
    state
}

fn join(state: &mut GameState, n: u128, name: &str, role: Role) -> Uuid {
    let id = Uuid::from_u128(n);
    state.add_player(id, name.into(), role);
    id
}

fn bot(state: &mut GameState, n: u128, name: &str) -> Uuid {
    let id = join(state, n, name, Role::Agent);
    state
        .bots
        .push(BotController::new(id, BotBehavior::Balanced));
    id
}

fn vote(state: &mut GameState, id: Uuid, map: MapKind) {
    state.set_action(
        id,
        Action {
            vote: Some(map.id()),
            ..Action::default()
        },
    );
}

fn wire(state: &GameState) -> MapVote {
    state
        .snapshot()
        .podium
        .and_then(|podium| podium.vote)
        .expect("a vote on the podium")
}

fn ids(vote: &MapVote) -> Vec<u32> {
    vote.options.iter().map(|option| option.map_id).collect()
}

#[test]
fn the_rotation_walks_the_roster_after_the_live_map_and_skips_what_cannot_host() {
    let rotation = Rotation::default();
    assert_eq!(
        rotation.after(MapKind::Sector9, GameMode::Ffa)[..3],
        [
            MapKind::ReclamationGulch,
            MapKind::TripointWorks,
            MapKind::HoldfastAtoll
        ]
    );
    // The live map comes last.
    assert_eq!(
        rotation.after(MapKind::Sector9, GameMode::Ffa).last(),
        Some(&MapKind::Sector9)
    );
    // Capture the flag only visits maps with flag stands.
    let flags = rotation.after(MapKind::Sector9, GameMode::Ctf);
    assert!(!flags.is_empty());
    assert!(flags.iter().all(|map| map.ctf_stands().is_some()));
    assert_eq!(
        rotation.after(MapKind::ArenaDuel, GameMode::Conquest),
        [MapKind::HoldfastAtoll]
    );
    let off = Rotation::without(&[MapKind::ReclamationGulch, MapKind::LowWater]).unwrap();
    let walk = off.after(MapKind::Sector9, GameMode::Tdm);
    assert!(!walk.contains(&MapKind::ReclamationGulch));
    assert!(!walk.contains(&MapKind::LowWater));
    assert_eq!(walk[0], MapKind::TripointWorks);
}

#[test]
fn a_host_cannot_switch_every_map_off() {
    assert!(Rotation::without(&MapKind::ALL).is_err());
    let mut rotation = Rotation::without(&MapKind::ALL[1..]).unwrap();
    assert!(rotation.set(MapKind::ArenaDuel, false).is_err());
    assert!(rotation.is_on(MapKind::ArenaDuel));
    rotation.set(MapKind::LowWater, true).unwrap();
    rotation.set(MapKind::ArenaDuel, false).unwrap();
    assert!(!rotation.is_on(MapKind::ArenaDuel));
}

#[test]
fn a_rotating_round_end_offers_the_next_three_switched_on_maps() {
    let mut state = rotating(MapKind::ArenaDuel, GameMode::Ffa);
    state.rotation = Rotation::without(&[MapKind::Directive17]).unwrap();
    join(&mut state, 1, "Probe", Role::Human);
    state.end_round("Frag limit reached".into());
    let offer = wire(&state);
    assert_eq!(ids(&offer), [2, 4, 5]);
    assert_eq!(offer.leader, 2, "no votes: the first option leads");
    assert!(!offer.bots_vote);
    assert_eq!(offer.closes_in, MAP_VOTE_TICKS);
    assert_eq!(offer.options[0].map_name, "Compliance Yard");
}

#[test]
fn a_fixed_map_or_a_single_choice_opens_no_vote() {
    let mut fixed = GameState::with_map(MapKind::ArenaDuel, false);
    fixed.start_round();
    join(&mut fixed, 1, "Probe", Role::Human);
    fixed.end_round("done".into());
    assert!(fixed.map_vote.is_none());

    // Conquest has one island: it stays on it without a vote.
    let mut island = rotating(MapKind::HoldfastAtoll, GameMode::Conquest);
    join(&mut island, 1, "Probe", Role::Human);
    island.end_round("done".into());
    assert!(island.map_vote.is_none());
    island.start_round();
    assert_eq!(island.map, MapKind::HoldfastAtoll);
}

#[test]
fn seated_votes_count_change_and_decide_the_next_map() {
    let mut state = rotating(MapKind::ArenaDuel, GameMode::Ffa);
    let a = join(&mut state, 1, "Probe", Role::Human);
    let b = join(&mut state, 2, "Jev", Role::Agent);
    let watcher = join(&mut state, 3, "Couch", Role::Spectator);
    state.end_round("Frag limit reached".into());
    vote(&mut state, a, MapKind::Sector9);
    vote(&mut state, b, MapKind::Sector9);
    vote(&mut state, watcher, MapKind::Directive17);
    // A map the vote does not offer is not a ballot.
    vote(&mut state, a, MapKind::LowWater);
    let offer = wire(&state);
    assert_eq!(offer.leader, 4);
    assert_eq!(offer.ballots.len(), 2, "the spectator never votes");
    assert_eq!(
        offer.options.iter().map(|o| o.votes).collect::<Vec<_>>(),
        [0, 0, 2]
    );
    // A changed mind: one each. The tie goes to the earlier option.
    vote(&mut state, b, MapKind::ComplianceYard);
    assert_eq!(wire(&state).leader, 2);
    vote(&mut state, a, MapKind::Directive17);
    vote(&mut state, b, MapKind::Directive17);
    state.start_round();
    assert_eq!(state.map, MapKind::Directive17);
    assert!(state.map_vote.is_none());
}

#[test]
fn a_vote_keeps_the_podium_up_its_window_unless_the_room_presses_again() {
    let mut state = rotating(MapKind::ArenaDuel, GameMode::Tdm);
    let a = join(&mut state, 1, "Probe", Role::Human);
    state.end_round("Frag limit reached".into());
    assert!(state.vote_window() > state.config.end_delay_ticks);
    for _ in 0..state.config.end_delay_ticks + 1 {
        state.tick(DT);
    }
    assert_eq!(
        state.round_state,
        RoundState::Ended,
        "the vote outlasts the plain podium"
    );
    vote(&mut state, a, MapKind::Sector9);
    state.set_action(
        a,
        Action {
            again: true,
            ..Action::default()
        },
    );
    state.tick(DT);
    assert_eq!(state.round_state, RoundState::Active);
    assert_eq!(state.map, MapKind::Sector9);
}

#[test]
fn the_vote_closes_on_its_own_clock() {
    let mut state = rotating(MapKind::ArenaDuel, GameMode::Ffa);
    let a = join(&mut state, 1, "Probe", Role::Human);
    state.end_round("Frag limit reached".into());
    vote(&mut state, a, MapKind::Directive17);
    let mut ticks = 0;
    while state.round_state == RoundState::Ended {
        state.tick(DT);
        ticks += 1;
        assert!(ticks <= MAP_VOTE_TICKS + 2, "the podium never closed");
    }
    assert_eq!(ticks, MAP_VOTE_TICKS);
    assert_eq!(state.map, MapKind::Directive17);
}

#[test]
fn rule_bots_vote_on_their_beats_only_when_nobody_else_is_seated() {
    let mut first = rotating(MapKind::ArenaDuel, GameMode::Ffa);
    for (n, name) in [(1, "Aunt Linda"), (2, "Dead Air Dan"), (3, "Nightfall")] {
        bot(&mut first, n, name);
    }
    let mut second = rotating(MapKind::ArenaDuel, GameMode::Ffa);
    for (n, name) in [(1, "Aunt Linda"), (2, "Dead Air Dan"), (3, "Nightfall")] {
        bot(&mut second, n, name);
    }
    for state in [&mut first, &mut second] {
        state.end_round("Frag limit reached".into());
        assert!(wire(state).bots_vote);
        assert!(wire(state).ballots.is_empty());
        for _ in 0..BOT_BALLOT_FIRST_TICK {
            state.tick(DT);
        }
        assert_eq!(wire(state).ballots.len(), 1, "the first bot votes first");
        for _ in 0..BOT_BALLOT_STEP_TICKS * 2 {
            state.tick(DT);
        }
        assert_eq!(wire(state).ballots.len(), 3);
    }
    assert_eq!(wire(&first), wire(&second), "a replay votes the same way");

    // A person sits down: the bots' ballots stop counting and the room decides.
    let a = join(&mut first, 9, "Probe", Role::Human);
    let offer = wire(&first);
    assert!(!offer.bots_vote);
    assert!(offer.ballots.is_empty());
    assert!(offer.options.iter().all(|o| o.votes == 0));
    vote(&mut first, a, MapKind::Sector9);
    assert_eq!(wire(&first).leader, 4);
}

#[test]
fn a_sabotage_match_keeps_its_map_between_its_rounds() {
    let mut state = rotating(MapKind::Sector9, GameMode::Sabotage);
    join(&mut state, 1, "Probe", Role::Human);
    state.end_round("round".into());
    assert!(state.map_vote.is_none());
    state.start_round();
    assert_eq!(state.map, MapKind::Sector9);
}

#[test]
fn the_podium_story_names_each_fighters_nemesis_and_closest_rivals() {
    let mut state = rotating(MapKind::ArenaDuel, GameMode::Ffa);
    let me = join(&mut state, 1, "Probe", Role::Human);
    let linda = bot(&mut state, 2, "Aunt Linda");
    let jev = join(&mut state, 3, "Jev", Role::Agent);
    join(&mut state, 4, "Couch", Role::Spectator);
    for _ in 0..5 {
        state.session_book.record("Aunt Linda", "Probe");
    }
    state.session_book.record("Probe", "Aunt Linda");
    state.session_book.record("Probe", "Jev");
    state.session_book.record("Probe", "Jev");
    state.session_book.record("Jev", "Probe");
    // The long book is not this session's.
    state.head_to_head.record("Couch", "Probe");
    state.end_round("Frag limit reached".into());
    let story = state.snapshot().podium.unwrap().story;
    assert_eq!(
        story.iter().map(|s| s.id).collect::<Vec<_>>(),
        [me, linda, jev],
        "seated fighters only, in id order"
    );
    let mine = &story[0];
    assert_eq!(mine.kind, FighterKind::Human);
    assert_eq!(mine.nemesis.as_deref(), Some("Aunt Linda"));
    assert_eq!(
        mine.rivals
            .iter()
            .map(|r| (r.name.as_str(), r.kind, r.won, r.lost))
            .collect::<Vec<_>>(),
        [
            ("Aunt Linda", FighterKind::Bot, 1, 5),
            ("Jev", FighterKind::Agent, 2, 1)
        ]
    );
    assert_eq!(story[1].kind, FighterKind::Bot);
    assert_eq!(story[1].nemesis, None, "Linda is ahead of everyone");
    assert_eq!(story[2].nemesis.as_deref(), Some("Probe"));
}

#[test]
fn the_desk_lists_and_switches_the_rotation() {
    let mut fixed = GameState::with_map(MapKind::ArenaDuel, false);
    assert!(fixed.set_rotation(MapKind::LowWater, false).is_err());
    assert!(fixed.desk_rotation().contains("No rotation"));

    let mut state = rotating(MapKind::Sector9, GameMode::Ctf);
    let table = state.desk_rotation();
    assert!(
        table.contains("2 Compliance Yard: on, cannot host this mode"),
        "{table}"
    );
    assert!(table.contains("4 Sector 9 Transit Hall: on"), "{table}");
    let said = state.set_rotation(MapKind::Directive17, false).unwrap();
    assert!(said.contains("out of the rotation"), "{said}");
    assert!(state
        .desk_rotation()
        .contains("3 Directive 17 Substation: off"));
    let said = state.set_rotation(MapKind::ComplianceYard, true).unwrap();
    assert!(said.contains("cannot host"), "{said}");
    let said = state.set_rotation(MapKind::Directive17, true).unwrap();
    assert!(said.contains("is in the rotation"), "{said}");
}
