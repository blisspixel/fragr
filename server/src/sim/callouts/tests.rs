//! Objective callouts: who says what to which side, and the spacing that
//! keeps them rare and clear of the Host.
use super::super::{BotBehavior, BotController, GameState, MapKind, MatchConfig, PLAYER_FLOOR_Y};
use super::{CALLOUT_AFTER_HOST_TICKS, CALLOUT_GAP_TICKS, CALLOUT_STALE_TICKS};
use crate::protocol::{Action, GameEvent, GameMode, Role, SabotagePhase, SiteId, Team};
use crate::roster::{objective_line, ObjectiveCall, Reach};
use crate::rules::{RuleSet, SabotageConfig};
use uuid::Uuid;

/// A line said to a side, with the tick it was said on.
#[derive(Debug, Clone, PartialEq)]
struct Said {
    tick: u64,
    speaker: Uuid,
    text: String,
    team: Option<Team>,
}

fn put(state: &mut GameState, id: Uuid, x: f32, z: f32, yaw: f32) {
    let player = state.players.iter_mut().find(|p| p.id == id).unwrap();
    player.x = x;
    player.z = z;
    player.y = PLAYER_FLOOR_Y;
    player.vy = 0.0;
    player.yaw = yaw;
}

fn name(state: &GameState, id: Uuid) -> String {
    state
        .players
        .iter()
        .find(|p| p.id == id)
        .unwrap()
        .name
        .clone()
}

fn side(state: &GameState, team: Team) -> Vec<Uuid> {
    state
        .players
        .iter()
        .filter(|p| p.team == Some(team))
        .map(|p| p.id)
        .collect()
}

/// Tick `ticks` times, letting the rule bots look first, and keep what was
/// said to a side and when the Host last called.
fn run(state: &mut GameState, ticks: u32) -> (Vec<Said>, Option<u64>) {
    let mut said = Vec::new();
    let mut host = None;
    for _ in 0..ticks {
        let bots = state.bots.clone();
        state.update_bot_senses(&bots);
        state.tick(0.05);
        for event in state.take_events() {
            match event {
                GameEvent::Speak {
                    player_id,
                    text,
                    team: Some(team),
                    ..
                } => said.push(Said {
                    tick: state.tick,
                    speaker: player_id,
                    text,
                    team: Some(team),
                }),
                GameEvent::HostReaction { .. } => host = Some(state.tick),
                _ => {}
            }
        }
    }
    (said, host)
}

/// A live Sector 9 CTF round with four named rule bots, two a side, all
/// parked far from both stands and from each other's sight.
fn ctf_room(names: [&str; 4]) -> GameState {
    let mut state = GameState::with_map(MapKind::Sector9, false);
    state.seed(5);
    state.apply_config(MatchConfig {
        frag_limit: None,
        capture_limit: Some(3),
        time_limit_ticks: Some(20 * 180),
        boss_spawn_ticks: None,
        compliance_ping_ticks: None,
        rules: RuleSet::new(GameMode::Ctf, &[], false).unwrap(),
        ..MatchConfig::default()
    });
    for (n, callsign) in names.into_iter().enumerate() {
        let id = Uuid::from_u128(n as u128 + 1);
        state.add_player(id, callsign.into(), Role::Agent);
        state
            .bots
            .push(BotController::new(id, BotBehavior::Balanced));
    }
    state.start_round();
    state.spawn_shields.clear();
    for (n, id) in state
        .players
        .iter()
        .map(|p| p.id)
        .collect::<Vec<_>>()
        .into_iter()
        .enumerate()
    {
        // Out on the far south hall, facing the wall.
        put(
            &mut state,
            id,
            -20.0 + n as f32 * 10.0,
            80.0,
            std::f32::consts::FRAC_PI_2,
        );
    }
    state
}

fn stand(state: &GameState, team: Team) -> [f32; 3] {
    state.snapshot().flags.unwrap()[team.index()].stand
}

#[test]
fn a_rule_bot_that_takes_the_flag_tells_its_own_side_once_after_the_host() {
    let mut state = ctf_room(["Hermes", "Nightfall", "Pi", "Static Kid"]);
    let runner = side(&state, Team::Coalition)[0];
    let union = stand(&state, Team::Union);
    put(&mut state, runner, union[0], union[2], 0.0);
    let (said, host) = run(&mut state, 200);
    let taken_at = state.tick - 200 + 1;
    assert_eq!(said.len(), 1, "one call for one moment: {said:?}");
    let call = &said[0];
    assert_eq!(call.speaker, runner);
    assert_eq!(call.team, Some(Team::Coalition), "said to its own side");
    assert_eq!(
        Some(call.text.clone()),
        objective_line(&name(&state, runner), ObjectiveCall::HaveFlag)
    );
    if let Some(host) = host.filter(|at| *at <= call.tick) {
        assert!(
            call.tick >= host + CALLOUT_AFTER_HOST_TICKS,
            "the call waits for the Host: host {host}, call {}",
            call.tick
        );
    }
    assert!(call.tick - taken_at <= CALLOUT_STALE_TICKS);
}

#[test]
fn a_bot_that_sees_the_enemy_carrier_calls_where_it_is_once_per_carry() {
    let mut state = ctf_room(["Hermes", "Nightfall", "Pi", "Static Kid"]);
    let thief = side(&state, Team::Coalition)[0];
    let watcher = side(&state, Team::Union)[0];
    let union = stand(&state, Team::Union);
    put(&mut state, thief, union[0], union[2], 0.0);
    run(&mut state, 1);
    // The thief stops in the open hub; the watcher looks straight at it.
    put(&mut state, thief, -4.0, 0.0, 0.0);
    put(&mut state, watcher, 6.0, 0.0, std::f32::consts::PI);
    assert!(crate::combat::line_of_sight(
        super::super::fighter_eye(
            &state.players[state.players.iter().position(|p| p.id == watcher).unwrap()]
        ),
        super::super::fighter_chest(
            &state.players[state.players.iter().position(|p| p.id == thief).unwrap()]
        ),
        &state.current_arena().solids,
    ));
    let (said, _) = run(&mut state, 300);
    let calls: Vec<&Said> = said.iter().filter(|s| s.speaker == watcher).collect();
    assert_eq!(
        calls.len(),
        1,
        "once per carry, though it is seen throughout: {said:?}"
    );
    assert_eq!(calls[0].team, Some(Team::Union));
    assert_eq!(
        Some(calls[0].text.clone()),
        objective_line(
            &name(&state, watcher),
            ObjectiveCall::EnemyCarrier(Reach::Mid)
        )
    );
}

#[test]
fn nobody_calls_a_carrier_they_cannot_see() {
    let mut state = ctf_room(["Hermes", "Nightfall", "Pi", "Static Kid"]);
    let thief = side(&state, Team::Coalition)[0];
    let watcher = side(&state, Team::Union)[0];
    let union = stand(&state, Team::Union);
    put(&mut state, thief, union[0], union[2], 0.0);
    run(&mut state, 1);
    // Close, but looking the other way.
    put(&mut state, thief, -4.0, 0.0, 0.0);
    put(&mut state, watcher, 6.0, 0.0, 0.0);
    let (said, _) = run(&mut state, 300);
    assert!(
        said.iter().all(|s| s.speaker != watcher),
        "a carrier behind the bot is not called: {said:?}"
    );
}

#[test]
fn a_side_hears_one_call_per_gap_and_an_old_one_is_dropped() {
    let mut state = ctf_room(["Hermes", "Nightfall", "Pi", "Static Kid"]);
    let [first, second] = side(&state, Team::Coalition)[..] else {
        panic!("two a side");
    };
    let union = stand(&state, Team::Union);
    put(&mut state, first, union[0], union[2], 0.0);
    run(&mut state, 1);
    // A second moment for the same side right behind the first: it is
    // still true (the flag is still out) but the side has just heard one.
    state.queue_callout(second, ObjectiveCall::EnemyCarrier(Reach::Mid));
    let coalition_flag = stand(&state, Team::Coalition);
    let union_bot = side(&state, Team::Union)[0];
    put(
        &mut state,
        union_bot,
        coalition_flag[0],
        coalition_flag[2],
        0.0,
    );
    let (said, _) = run(&mut state, CALLOUT_GAP_TICKS as u32 + 40);
    let coalition: Vec<&Said> = said
        .iter()
        .filter(|s| s.team == Some(Team::Coalition))
        .collect();
    assert_eq!(coalition.len(), 1, "{said:?}");
    // A held call goes stale inside the gap.
    const { assert!(CALLOUT_STALE_TICKS < CALLOUT_GAP_TICKS) };
}

#[test]
fn a_call_that_stopped_being_true_is_never_said() {
    let mut state = ctf_room(["Hermes", "Nightfall", "Pi", "Static Kid"]);
    let runner = side(&state, Team::Coalition)[0];
    let union = stand(&state, Team::Union);
    // A Host call a moment ago holds the line back...
    state.reactions.last_tick = Some(state.tick);
    put(&mut state, runner, union[0], union[2], 0.0);
    run(&mut state, 2);
    // ...and the carrier dies before it could be said.
    let index = state.players.iter().position(|p| p.id == runner).unwrap();
    state.players[index].hp = 1;
    state.players[index].armor = 0;
    let killer = state.players.iter().position(|p| p.id != runner).unwrap();
    let _ = state.resolve_fighter_hit_for(killer, index, 500, None, false, None);
    let (said, _) = run(&mut state, 120);
    assert!(said.is_empty(), "{said:?}");
}

#[test]
fn people_and_nods_make_no_calls() {
    let mut state = ctf_room(["NODS 0412", "Nightfall", "Pi", "Static Kid"]);
    let nods = state.players[0].id;
    let union = stand(&state, Team::Union);
    let enemy = if state.players[0].team == Some(Team::Coalition) {
        union
    } else {
        stand(&state, Team::Coalition)
    };
    put(&mut state, nods, enemy[0], enemy[2], 0.0);
    let (said, _) = run(&mut state, 120);
    assert!(said.is_empty(), "NODS answer only with Articles: {said:?}");

    let mut room = ctf_room(["Hermes", "Nightfall", "Pi", "Static Kid"]);
    let person = room.players[0].id;
    room.bots.retain(|bot| bot.player_id != person);
    let enemy = stand(&room, room.players[0].team.unwrap().other());
    put(&mut room, person, enemy[0], enemy[2], 0.0);
    let (said, _) = run(&mut room, 120);
    assert!(said.is_empty(), "a person's moment is the Host's: {said:?}");
}

#[test]
fn carriers_are_placed_in_thirds_from_the_stand_they_robbed() {
    let from = [-70.0, 0.0, 0.0];
    let to = [70.0, 0.0, 0.0];
    assert_eq!(super::reach([-60.0, 0.0, 5.0], from, to), Reach::OurStand);
    assert_eq!(super::reach([0.0, 0.0, -20.0], from, to), Reach::Mid);
    assert_eq!(super::reach([50.0, 0.0, 0.0], from, to), Reach::TheirStand);
    assert_eq!(super::reach([0.0, 0.0, 0.0], from, from), Reach::Mid);
}

/// Sabotage on Sector 9 with short clocks and four named rule bots.
fn sabotage_room() -> GameState {
    let mut state = GameState::with_map(MapKind::Sector9, false);
    state.seed(11);
    state.apply_config(MatchConfig {
        frag_limit: None,
        time_limit_ticks: None,
        boss_spawn_ticks: None,
        compliance_ping_ticks: None,
        rules: RuleSet::new(GameMode::Sabotage, &[], false).unwrap(),
        sabotage: SabotageConfig {
            muster_ticks: 4,
            live_ticks: 2000,
            plant_ticks: 60,
            charge_ticks: 1200,
            defuse_ticks: 400,
            round_end_ticks: 3,
            swap_end_ticks: 5,
            ..SabotageConfig::default()
        },
        ..MatchConfig::default()
    });
    for (n, callsign) in ["Hermes", "Auditor On Duty", "Pi", "Kind Regards 07"]
        .into_iter()
        .enumerate()
    {
        let id = Uuid::from_u128(n as u128 + 1);
        state.add_player(id, callsign.into(), Role::Agent);
        state
            .bots
            .push(BotController::new(id, BotBehavior::Balanced));
    }
    state.start_round();
    for _ in 0..5 {
        state.tick(0.05);
    }
    state.take_events();
    state
}

fn hold(state: &mut GameState, id: Uuid) {
    state.set_action(
        id,
        Action {
            interact: true,
            ..Action::default()
        },
    );
}

#[test]
fn the_planter_and_the_defuser_each_tell_their_side() {
    const A: [f32; 3] = [-38.0, 0.0, -27.0];
    let mut state = sabotage_room();
    let planter = state
        .sabotage
        .as_ref()
        .and_then(|s| s.charge.as_ref())
        .and_then(|c| c.carrier)
        .expect("a carrier");
    put(&mut state, planter, A[0], A[2], 0.0);
    hold(&mut state, planter);
    let (planted, _) = run(&mut state, 61 + CALLOUT_AFTER_HOST_TICKS as u32 + 2);
    assert_eq!(
        state.sabotage.as_ref().unwrap().phase,
        SabotagePhase::Planted
    );
    state.set_action(planter, Action::default());
    let defender = side(&state, Team::Union)[0];
    put(&mut state, defender, A[0] + 1.0, A[2], 0.0);
    hold(&mut state, defender);
    let (defusing, _) = run(&mut state, CALLOUT_AFTER_HOST_TICKS as u32 + 4);

    let planted: Vec<&Said> = planted.iter().filter(|s| s.speaker == planter).collect();
    assert_eq!(planted.len(), 1, "{planted:?}");
    assert_eq!(planted[0].team, Some(Team::Coalition));
    assert_eq!(
        Some(planted[0].text.clone()),
        objective_line(&name(&state, planter), ObjectiveCall::Planted(SiteId::A))
    );
    let defusing: Vec<&Said> = defusing.iter().filter(|s| s.speaker == defender).collect();
    assert_eq!(defusing.len(), 1, "{defusing:?}");
    assert_eq!(defusing[0].team, Some(Team::Union));
    assert_eq!(
        Some(defusing[0].text.clone()),
        objective_line(&name(&state, defender), ObjectiveCall::Defusing(SiteId::A))
    );
}
