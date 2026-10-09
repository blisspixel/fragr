//! Sabotage: every round rule and its failure paths as seeded ticks on the
//! authoritative sim, plus the Sector 9 layout and its measured routes.
use crate::protocol::{
    Action, ChargeStatus, GameEvent, GameMode, Mutator, ProgressKind, Role, SabotageEventKind,
    SabotageFormat, SabotagePhase, SabotageReason, ServerMessage, SiteId, Team, WeaponType,
};
use crate::rules::{RuleSet, SabotageConfig};
use crate::sim::{
    BotBehavior, BotController, GameState, MapKind, MatchConfig, RoundState, PLAYER_FLOOR_Y,
};
use uuid::Uuid;

const A: [f32; 3] = [-38.0, 0.0, -27.0];
const B: [f32; 3] = [-38.0, 0.0, 27.0];

fn config(sabotage: SabotageConfig, mutators: &[Mutator]) -> MatchConfig {
    MatchConfig {
        frag_limit: None,
        time_limit_ticks: None,
        boss_spawn_ticks: None,
        compliance_ping_ticks: None,
        rules: RuleSet::new(GameMode::Sabotage, mutators, false).unwrap(),
        sabotage,
        ..MatchConfig::default()
    }
}

/// Short clocks keep the seeded ticks quick; every rule reads them.
fn quick() -> SabotageConfig {
    SabotageConfig {
        muster_ticks: 4,
        live_ticks: 400,
        plant_ticks: 60,
        charge_ticks: 300,
        defuse_ticks: 120,
        round_end_ticks: 3,
        swap_end_ticks: 5,
        ..SabotageConfig::default()
    }
}

fn arena(sabotage: SabotageConfig) -> GameState {
    let mut state = GameState::with_map(MapKind::Sector9, false);
    state.seed(11);
    state.apply_config(config(sabotage, &[]));
    state
}

fn join(state: &mut GameState, n: u128) -> Uuid {
    let id = Uuid::from_u128(n);
    state.add_player(id, format!("S{n}"), Role::Agent);
    id
}

/// Two a side, the round open and muster over.
fn two_a_side(sabotage: SabotageConfig) -> (GameState, Vec<Uuid>) {
    let mut state = arena(sabotage);
    let ids: Vec<Uuid> = (1..=4).map(|n| join(&mut state, n)).collect();
    state.start_round();
    let muster = state.config.sabotage.muster_ticks;
    run(&mut state, muster + 1);
    assert_eq!(phase(&state), SabotagePhase::Live);
    (state, ids)
}

fn run(state: &mut GameState, ticks: u32) -> Vec<GameEvent> {
    let mut events = Vec::new();
    for _ in 0..ticks {
        state.tick(0.05);
        events.extend(state.take_events());
    }
    events
}

fn phase(state: &GameState) -> SabotagePhase {
    state.sabotage.as_ref().unwrap().phase
}

fn side(state: &GameState, team: Team) -> Vec<Uuid> {
    state
        .players
        .iter()
        .filter(|p| p.team == Some(team))
        .map(|p| p.id)
        .collect()
}

fn carrier(state: &GameState) -> Uuid {
    state
        .sabotage
        .as_ref()
        .and_then(|s| s.charge.as_ref())
        .and_then(|c| c.carrier)
        .expect("a carrier")
}

fn player(state: &GameState, id: Uuid) -> &crate::sim::Player {
    state.players.iter().find(|p| p.id == id).unwrap()
}

fn put(state: &mut GameState, id: Uuid, at: [f32; 3]) {
    let p = state.players.iter_mut().find(|p| p.id == id).unwrap();
    p.x = at[0];
    p.y = at[1] + PLAYER_FLOOR_Y;
    p.z = at[2];
    p.vy = 0.0;
}

fn hold_use(state: &mut GameState, id: Uuid) {
    state.set_action(
        id,
        Action {
            interact: true,
            ..Action::default()
        },
    );
}

fn release(state: &mut GameState, id: Uuid) {
    state.set_action(id, Action::default());
}

fn kinds(events: &[GameEvent]) -> Vec<SabotageEventKind> {
    events
        .iter()
        .filter_map(|e| match e {
            GameEvent::Sabotage { kind, .. } => Some(*kind),
            _ => None,
        })
        .collect()
}

fn round_end(events: &[GameEvent]) -> Option<(Option<Team>, crate::protocol::SabotageResult)> {
    events.iter().find_map(|e| match e {
        GameEvent::RoundEnd {
            winning_team,
            sabotage: Some(result),
            ..
        } => Some((*winning_team, result.clone())),
        _ => None,
    })
}

/// The carrier stands in A with Use held until the charge is planted.
fn plant_at_a(state: &mut GameState) -> Uuid {
    let id = carrier(state);
    put(state, id, A);
    hold_use(state, id);
    let needed = state.config.sabotage.plant_ticks;
    let events = run(state, needed + 1);
    assert!(
        kinds(&events).contains(&SabotageEventKind::Planted),
        "{events:?}"
    );
    release(state, id);
    id
}

#[test]
fn muster_holds_a_mine_the_same_way_it_holds_a_throw() {
    let mut state = arena(quick());
    let id = join(&mut state, 1);
    state.start_round();
    assert_eq!(phase(&state), SabotagePhase::Muster);
    {
        let player = state.players.iter_mut().find(|p| p.id == id).unwrap();
        assert_eq!(player.inventory.grant_grenades(1), 1);
        assert_eq!(player.inventory.grant_mines(1), 1);
    }
    state.set_action(
        id,
        Action {
            fire: true,
            throw_grenade: true,
            place_mine: true,
            ..Action::default()
        },
    );
    state.tick(0.05);
    assert_eq!(phase(&state), SabotagePhase::Muster);
    assert!(state.snapshot().grenades.is_empty());
    assert!(state.snapshot().mines.is_empty());
    assert!(state.snapshot().shot_results.is_empty());
    assert_eq!(player(&state, id).inventory.grenades(), 1);
    assert_eq!(player(&state, id).inventory.mines(), 1);

    let muster_ticks = state.config.sabotage.muster_ticks;
    run(&mut state, muster_ticks);
    assert_eq!(phase(&state), SabotagePhase::Live);
    assert!(state.snapshot().mines.is_empty());
    state.set_action(
        id,
        Action {
            place_mine: true,
            ..Action::default()
        },
    );
    state.tick(0.05);
    assert_eq!(state.snapshot().mines.len(), 1);
    assert_eq!(state.snapshot().mines[0].owner_id, id);
    assert_eq!(player(&state, id).inventory.mines(), 0);
}

#[test]
fn empty_muster_waits_for_the_delayed_first_fighter_without_scoring() {
    for five_vs_five in [false, true] {
        for role in [Role::Human, Role::Agent] {
            let mut state = arena(SabotageConfig {
                five_vs_five,
                ..quick()
            });
            state.start_round();
            let events = run(&mut state, 1000);
            let wire = state.snapshot().sabotage.unwrap();
            assert_eq!((wire.round, wire.phase), (1, SabotagePhase::Muster));
            assert_eq!((wire.score.union, wire.score.coalition), (0, 0));
            assert_eq!(wire.clock_ticks, 4);
            assert!(state.sabotage.as_ref().unwrap().result.is_none());
            assert!(!kinds(&events).contains(&SabotageEventKind::Live));
            assert!(round_end(&events).is_none());

            let id = Uuid::from_u128(1);
            state.add_player(id, "Delayed first fighter".into(), role);
            assert!(player(&state, id).standing());
            run(&mut state, 3);
            assert_eq!(phase(&state), SabotagePhase::Muster);
            let events = run(&mut state, 1);
            assert_eq!(phase(&state), SabotagePhase::Live);
            assert!(kinds(&events).contains(&SabotageEventKind::Live));
            assert!(player(&state, id).standing());
            assert!(round_end(&events).is_none());
        }
    }
}

#[test]
fn parked_only_muster_keeps_full_clock_until_a_fighter_returns() {
    let mut state = arena(quick());
    let id = join(&mut state, 1);
    state.start_round();
    run(&mut state, 2);
    state.players[0].detached = true;
    let events = run(&mut state, 1000);
    let wire = state.snapshot().sabotage.unwrap();
    assert_eq!(
        (wire.round, wire.phase, wire.clock_ticks),
        (1, SabotagePhase::Muster, 4)
    );
    assert_eq!((wire.score.union, wire.score.coalition), (0, 0));
    assert!(state.sabotage.as_ref().unwrap().result.is_none());
    assert!(round_end(&events).is_none());
    state.players[0].detached = false;
    run(&mut state, 3);
    assert_eq!(phase(&state), SabotagePhase::Muster);
    run(&mut state, 1);
    assert_eq!(phase(&state), SabotagePhase::Live);
    assert!(player(&state, id).standing());
}

#[test]
fn a_parked_body_is_not_a_sabotage_fight() {
    let (mut state, ids) = two_a_side(quick());
    let held = carrier(&state);
    let bot = ids
        .iter()
        .copied()
        .find(|id| player(&state, *id).team == Some(Team::Coalition) && *id != held)
        .expect("a coalition fighter who is not carrying");
    let ghost = ids
        .iter()
        .copied()
        .find(|id| player(&state, *id).team == Some(Team::Union))
        .expect("a union fighter");
    put(&mut state, bot, A);
    put(&mut state, ghost, [A[0] + 1.2, A[1], A[2]]);
    state.players.iter_mut().find(|p| p.id == bot).unwrap().yaw = 0.0;
    let controller = BotController::new(bot, BotBehavior::Compliance);
    let live = controller.intent(&state);
    assert!(
        live.action.fire,
        "a standing enemy at arm's length is a fight"
    );
    state
        .players
        .iter_mut()
        .find(|p| p.id == ghost)
        .unwrap()
        .detached = true;
    let parked = controller.intent(&state);
    assert!(!parked.action.fire, "a parked resume body is not a fight");
}

#[test]
fn a_round_opens_in_muster_with_side_spawns_and_one_carrier() {
    let mut state = arena(SabotageConfig::default());
    let ids: Vec<Uuid> = (1..=6).map(|n| join(&mut state, n)).collect();
    assert_eq!(
        state.wire_sabotage(),
        None,
        "no round state before the first round"
    );
    state.start_round();
    let layout = MapKind::Sector9.sabotage_layout().unwrap();
    let sab = state.sabotage.as_ref().unwrap();
    assert_eq!((sab.round, sab.phase), (1, SabotagePhase::Muster));
    for id in &ids {
        let p = player(&state, *id);
        let team = p.team.unwrap();
        assert!(
            layout.in_muster(team.index(), p.x, p.z),
            "{} outside its zone",
            p.name
        );
        assert_eq!(p.weapon, WeaponType::Fists, "every life starts empty");
        assert!(!p.inventory.owns(WeaponType::Tack));
        assert_eq!(p.lives, Some(1));
    }
    assert_eq!(side(&state, Team::Union).len(), 3);
    let carrier = carrier(&state);
    assert_eq!(player(&state, carrier).team, Some(Team::Coalition));
    let wire = state.snapshot().sabotage.unwrap();
    assert_eq!(wire.phase, SabotagePhase::Muster);
    assert_eq!(wire.clock_ticks, 200);
    assert_eq!(wire.charge.unwrap().status, ChargeStatus::Carried);
    assert_eq!((wire.alive.union, wire.alive.coalition), (3, 3));
    assert_eq!((wire.half, wire.half_rounds, wire.rounds_to_win), (1, 4, 5));
    assert_eq!(state.snapshot().round_time_left, Some(10));
    match state.map_info() {
        ServerMessage::MapInfo {
            sabotage: Some(map),
            rules: Some(rules),
            ..
        } => {
            assert!(map.validate().is_ok());
            assert_eq!(rules.mode, GameMode::Sabotage);
            assert_eq!(rules.lives, Some(1));
        }
        other => panic!("{other:?}"),
    }
    // Personal spawn pistols join the map's own pads.
    assert_eq!(
        state
            .pickups
            .iter()
            .filter(|p| p.id.starts_with("sabotage_tack"))
            .count(),
        2
    );
}

#[test]
fn muster_holds_fighters_in_the_zone_and_weapons_cold() {
    let mut state = arena(SabotageConfig {
        muster_ticks: 60,
        ..quick()
    });
    let ids: Vec<Uuid> = (1..=2).map(|n| join(&mut state, n)).collect();
    state.start_round();
    let layout = MapKind::Sector9.sabotage_layout().unwrap();
    let attacker = side(&state, Team::Coalition)[0];
    // Face the yard's east edge and run at it while firing.
    state
        .players
        .iter_mut()
        .find(|p| p.id == attacker)
        .unwrap()
        .yaw = 0.0;
    state.set_action(
        attacker,
        Action {
            forward: true,
            fire: true,
            yaw: Some(0.0),
            ..Action::default()
        },
    );
    let events = run(&mut state, 50);
    let p = player(&state, attacker);
    assert!(
        layout.in_muster(Team::Coalition.index(), p.x, p.z),
        "left the yard at {}",
        p.x
    );
    assert!(
        p.x > layout.muster[1][2] - 1.0,
        "walked to the zone edge, x {}",
        p.x
    );
    assert!(
        !events
            .iter()
            .any(|e| matches!(e, GameEvent::Hit { .. } | GameEvent::Frag { .. })),
        "no weapon is live in muster"
    );
    assert!(state.shot_results.is_empty());
    let events = run(&mut state, 12);
    assert!(kinds(&events).contains(&SabotageEventKind::Live));
    let p = player(&state, attacker);
    assert!(p.x > layout.muster[1][2], "free to leave once live");
    let _ = ids;
}

#[test]
fn the_spawn_pistol_arms_each_life_and_survivors_can_take_it_again() {
    let (mut state, _) = two_a_side(quick());
    let defender = side(&state, Team::Union)[0];
    put(&mut state, defender, [-55.0, 0.0, 0.0]);
    run(&mut state, 1);
    let p = player(&state, defender);
    assert!(p.inventory.owns(WeaponType::Tack));
    assert!(p.inventory.claimed("sabotage_tack_union"));
    assert!(state.equipment_policy() == crate::protocol::EquipmentPolicy::Discovery);
    // A second visit in the same life takes nothing.
    put(&mut state, defender, [-60.0, 0.0, 9.0]);
    run(&mut state, 1);
    put(&mut state, defender, [-55.0, 0.0, 0.0]);
    let before = player(&state, defender).inventory.revision();
    run(&mut state, 1);
    assert_eq!(player(&state, defender).inventory.revision(), before);
    // The survivor carries the pistol into the next round and may claim again.
    state.end_round("test".into());
    run(&mut state, 10);
    let p = player(&state, defender);
    assert!(p.inventory.owns(WeaponType::Tack), "carried forward");
    assert!(
        !p.inventory.claimed("sabotage_tack_union"),
        "claims reset each round"
    );
}

#[test]
fn the_carrier_plants_after_three_seconds_of_held_use() {
    let (mut state, _) = two_a_side(quick());
    let id = carrier(&state);
    put(&mut state, id, A);
    hold_use(&mut state, id);
    let events = run(&mut state, 1);
    assert_eq!(kinds(&events), vec![SabotageEventKind::PlantStarted]);
    let progress = state.snapshot().sabotage.unwrap().progress.unwrap();
    assert_eq!(progress.kind, ProgressKind::Plant);
    assert_eq!((progress.player_id, progress.site), (id, SiteId::A));
    assert_eq!(progress.needed, 60);
    let events = run(&mut state, 59);
    assert!(
        !kinds(&events).contains(&SabotageEventKind::Planted),
        "not before 3 s"
    );
    let events = run(&mut state, 1);
    assert!(kinds(&events).contains(&SabotageEventKind::Planted));
    let wire = state.snapshot().sabotage.unwrap();
    assert_eq!(wire.phase, SabotagePhase::Planted);
    let charge = wire.charge.unwrap();
    assert_eq!(
        (charge.status, charge.site, charge.carrier),
        (ChargeStatus::Planted, Some(SiteId::A), None)
    );
    assert_eq!(
        wire.clock_ticks, 300,
        "the charge's clock replaces the round's"
    );
    assert!(wire.progress.is_none());
}

#[test]
fn release_movement_damage_or_leaving_the_site_restarts_a_plant() {
    for case in ["release", "move", "damage", "outside", "death"] {
        let (mut state, _) = two_a_side(quick());
        let id = carrier(&state);
        let defender = side(&state, Team::Union)[0];
        put(&mut state, id, B);
        hold_use(&mut state, id);
        run(&mut state, 30);
        match case {
            "release" => release(&mut state, id),
            "move" => state.set_action(
                id,
                Action {
                    interact: true,
                    left: true,
                    ..Action::default()
                },
            ),
            "damage" => {
                state.hit_for_test(defender, id, 10);
            }
            "outside" => put(&mut state, id, [B[0], 0.0, B[2] + 3.5]),
            _ => {
                assert!(state.hit_for_test(defender, id, 500));
            }
        }
        let events = run(&mut state, 1);
        assert!(
            kinds(&events).contains(&SabotageEventKind::PlantInterrupted),
            "{case}: {events:?}"
        );
        assert!(state.sabotage.as_ref().unwrap().hold.is_none(), "{case}");
        let events = run(&mut state, 60);
        assert!(
            !kinds(&events).contains(&SabotageEventKind::Planted),
            "{case}"
        );
        if case == "death" {
            let charge = state.snapshot().sabotage.unwrap().charge.unwrap();
            assert_eq!(
                charge.status,
                ChargeStatus::Dropped,
                "the charge falls with its carrier"
            );
        }
    }
}

#[test]
fn only_the_carrier_plants_and_only_attackers_carry() {
    let (mut state, _) = two_a_side(quick());
    let id = carrier(&state);
    let other = side(&state, Team::Coalition)
        .into_iter()
        .find(|p| *p != id)
        .unwrap();
    let defender = side(&state, Team::Union)[0];
    put(&mut state, other, A);
    hold_use(&mut state, other);
    let events = run(&mut state, 80);
    assert!(
        kinds(&events).is_empty(),
        "a non-carrier cannot plant: {events:?}"
    );
    // Carrier dies; a defender stands on the charge, an attacker takes it.
    put(&mut state, id, [-20.0, 0.0, 0.0]);
    assert!(state.hit_for_test(defender, id, 500));
    let events = run(&mut state, 1);
    assert!(kinds(&events).contains(&SabotageEventKind::ChargeDropped));
    put(&mut state, defender, [-20.0, 0.0, 0.0]);
    run(&mut state, 20);
    let charge = state.snapshot().sabotage.unwrap().charge.unwrap();
    assert_eq!(
        charge.status,
        ChargeStatus::Dropped,
        "defenders cannot carry"
    );
    put(&mut state, other, [-20.5, 0.0, 0.3]);
    let events = run(&mut state, 1);
    assert!(kinds(&events).contains(&SabotageEventKind::ChargeTaken));
    assert_eq!(carrier(&state), other);
}

#[test]
fn a_dropped_charge_waits_out_its_grace_before_anyone_takes_it() {
    let (mut state, _) = two_a_side(quick());
    let id = carrier(&state);
    let other = side(&state, Team::Coalition)
        .into_iter()
        .find(|p| *p != id)
        .unwrap();
    put(&mut state, id, [-10.0, 0.0, 0.0]);
    put(&mut state, other, [-10.4, 0.0, 0.2]);
    state.remove_player(id);
    assert!(kinds(&state.take_events()).contains(&SabotageEventKind::ChargeDropped));
    let charge = state.snapshot().sabotage.unwrap().charge.unwrap();
    assert_eq!(
        charge.status,
        ChargeStatus::Dropped,
        "a leave drops the charge"
    );
    assert_eq!(charge.position, [-10.0, 0.0, 0.0]);
    let events = run(&mut state, 9);
    assert!(!kinds(&events).contains(&SabotageEventKind::ChargeTaken));
    let events = run(&mut state, 1);
    assert!(kinds(&events).contains(&SabotageEventKind::ChargeTaken));
    assert_eq!(carrier(&state), other);
}

#[test]
fn a_defender_defuses_after_six_seconds_and_the_union_wins() {
    let (mut state, _) = two_a_side(quick());
    plant_at_a(&mut state);
    let defender = side(&state, Team::Union)[0];
    put(&mut state, defender, [A[0] + 1.0, 0.0, A[2]]);
    hold_use(&mut state, defender);
    let events = run(&mut state, 1);
    assert!(kinds(&events).contains(&SabotageEventKind::DefuseStarted));
    let events = run(&mut state, 119);
    assert!(round_end(&events).is_none(), "not before 6 s");
    let events = run(&mut state, 1);
    assert!(kinds(&events).contains(&SabotageEventKind::Defused));
    let (winner, result) = round_end(&events).unwrap();
    assert_eq!(winner, Some(Team::Union));
    assert_eq!(result.reason, SabotageReason::Defused);
    assert_eq!((result.score.union, result.score.coalition), (1, 0));
    assert_eq!(state.round_state, RoundState::Ended);
    let charge = state.snapshot().sabotage.unwrap().charge.unwrap();
    assert_eq!(charge.status, ChargeStatus::Defused);
    assert!(state
        .ended_host_line
        .as_deref()
        .is_some_and(|line| line.contains("DEFUSED")));
}

#[test]
fn an_interrupted_defuse_loses_all_progress() {
    let (mut state, _) = two_a_side(quick());
    plant_at_a(&mut state);
    let defender = side(&state, Team::Union)[0];
    put(&mut state, defender, [A[0], 0.0, A[2] + 1.0]);
    hold_use(&mut state, defender);
    run(&mut state, 100);
    release(&mut state, defender);
    let events = run(&mut state, 1);
    assert!(kinds(&events).contains(&SabotageEventKind::DefuseInterrupted));
    hold_use(&mut state, defender);
    let events = run(&mut state, 100);
    assert!(round_end(&events).is_none(), "progress started over");
    let events = run(&mut state, 21);
    assert_eq!(
        round_end(&events).unwrap().1.reason,
        SabotageReason::Defused
    );
}

#[test]
fn one_defuser_at_a_time_and_a_dead_defuser_never_finishes() {
    let (mut state, _) = two_a_side(quick());
    let attacker = plant_at_a(&mut state);
    let defenders = side(&state, Team::Union);
    put(&mut state, defenders[0], [A[0] + 1.0, 0.0, A[2]]);
    put(&mut state, defenders[1], [A[0] - 1.0, 0.0, A[2]]);
    hold_use(&mut state, defenders[0]);
    hold_use(&mut state, defenders[1]);
    let events = run(&mut state, 1);
    assert_eq!(
        kinds(&events)
            .iter()
            .filter(|k| **k == SabotageEventKind::DefuseStarted)
            .count(),
        1
    );
    let first = state
        .snapshot()
        .sabotage
        .unwrap()
        .progress
        .unwrap()
        .player_id;
    run(&mut state, 118);
    // Killed on the tick the defuse would finish: it does not count.
    assert!(state.hit_for_test(attacker, first, 500));
    let events = run(&mut state, 1);
    assert!(kinds(&events).contains(&SabotageEventKind::DefuseInterrupted));
    assert!(round_end(&events).is_none());
    // The other defender starts from nothing.
    let events = run(&mut state, 1);
    assert!(kinds(&events).contains(&SabotageEventKind::DefuseStarted));
    assert_ne!(
        state
            .snapshot()
            .sabotage
            .unwrap()
            .progress
            .unwrap()
            .player_id,
        first
    );
}

#[test]
fn killing_every_attacker_after_a_plant_does_not_win_and_the_charge_detonates() {
    let (mut state, _) = two_a_side(quick());
    plant_at_a(&mut state);
    let defender = side(&state, Team::Union)[0];
    for attacker in side(&state, Team::Coalition) {
        assert!(state.hit_for_test(defender, attacker, 500));
    }
    let events = run(&mut state, 1);
    assert!(
        round_end(&events).is_none(),
        "a defender still has to defuse"
    );
    assert_eq!(state.snapshot().sabotage.unwrap().alive.coalition, 0);
    let events = run(&mut state, 300);
    assert!(kinds(&events).contains(&SabotageEventKind::Detonated));
    let (winner, result) = round_end(&events).unwrap();
    assert_eq!(
        (winner, result.reason),
        (Some(Team::Coalition), SabotageReason::Detonation)
    );
    assert_eq!(
        state.snapshot().sabotage.unwrap().charge.unwrap().status,
        ChargeStatus::Detonated
    );
}

#[test]
fn elimination_decides_before_a_plant_and_only_for_the_attack_after_it() {
    // Attack wiped before a plant: the Union.
    let (mut state, _) = two_a_side(quick());
    let defender = side(&state, Team::Union)[0];
    for attacker in side(&state, Team::Coalition) {
        state.hit_for_test(defender, attacker, 500);
    }
    let (winner, result) = round_end(&run(&mut state, 1)).unwrap();
    assert_eq!(
        (winner, result.reason),
        (Some(Team::Union), SabotageReason::Elimination)
    );
    // Defence wiped before a plant: the coalition.
    let (mut state, _) = two_a_side(quick());
    let attacker = side(&state, Team::Coalition)[0];
    for defender in side(&state, Team::Union) {
        state.hit_for_test(attacker, defender, 500);
    }
    let (winner, _) = round_end(&run(&mut state, 1)).unwrap();
    assert_eq!(winner, Some(Team::Coalition));
    // Defence wiped after a plant: the coalition, without waiting.
    let (mut state, _) = two_a_side(quick());
    let attacker = plant_at_a(&mut state);
    for defender in side(&state, Team::Union) {
        state.hit_for_test(attacker, defender, 500);
    }
    let (winner, result) = round_end(&run(&mut state, 1)).unwrap();
    assert_eq!(
        (winner, result.reason),
        (Some(Team::Coalition), SabotageReason::Elimination)
    );
}

#[test]
fn a_double_wipe_goes_to_the_defence_before_a_plant_and_the_attack_after() {
    let (mut state, _) = two_a_side(quick());
    let (attack, defence) = (side(&state, Team::Coalition), side(&state, Team::Union));
    for (a, d) in attack.iter().zip(&defence) {
        state.hit_for_test(*a, *d, 500);
        state.hit_for_test(*d, *a, 500);
    }
    let (winner, _) = round_end(&run(&mut state, 1)).unwrap();
    assert_eq!(winner, Some(Team::Union));
    let (mut state, _) = two_a_side(quick());
    plant_at_a(&mut state);
    let (attack, defence) = (side(&state, Team::Coalition), side(&state, Team::Union));
    for (a, d) in attack.iter().zip(&defence) {
        state.hit_for_test(*a, *d, 500);
        state.hit_for_test(*d, *a, 500);
    }
    let (winner, result) = round_end(&run(&mut state, 1)).unwrap();
    assert_eq!(
        (winner, result.reason),
        (Some(Team::Coalition), SabotageReason::Elimination)
    );
}

#[test]
fn the_clock_wins_for_the_defence_but_a_plant_on_its_last_tick_counts() {
    let (mut state, _) = two_a_side(quick());
    let started = state.sabotage.as_ref().unwrap().phase_started;
    let id = carrier(&state);
    // Plant so it completes exactly on the last live tick.
    let live = u64::from(state.config.sabotage.live_ticks);
    while state.tick + 1 < started + live - 60 {
        run(&mut state, 1);
    }
    put(&mut state, id, A);
    hold_use(&mut state, id);
    let events = run(&mut state, 61);
    assert_eq!(state.tick, started + live);
    assert!(
        kinds(&events).contains(&SabotageEventKind::Planted),
        "{events:?}"
    );
    assert!(round_end(&events).is_none());
    // Without a plant the same clock ends the round for the Union.
    let (mut state, _) = two_a_side(quick());
    let events = run(&mut state, 400);
    let (winner, result) = round_end(&events).unwrap();
    assert_eq!(
        (winner, result.reason),
        (Some(Team::Union), SabotageReason::Time)
    );
}

#[test]
fn a_defuse_finishing_on_the_detonation_tick_wins() {
    let (mut state, _) = two_a_side(SabotageConfig {
        charge_ticks: 150,
        ..quick()
    });
    plant_at_a(&mut state);
    let planted = state
        .sabotage
        .as_ref()
        .and_then(|s| s.charge.as_ref())
        .and_then(|c| c.planted)
        .unwrap()
        .1;
    let defender = side(&state, Team::Union)[0];
    while state.tick + 1 < planted + 150 - 120 {
        run(&mut state, 1);
    }
    put(&mut state, defender, [A[0] + 1.0, 0.0, A[2]]);
    hold_use(&mut state, defender);
    let events = run(&mut state, 121);
    assert_eq!(state.tick, planted + 150);
    let (winner, result) = round_end(&events).unwrap();
    assert_eq!(
        (winner, result.reason),
        (Some(Team::Union), SabotageReason::Defused)
    );
    assert!(!kinds(&events).contains(&SabotageEventKind::Detonated));
}

/// Tick until `n` more rounds are decided, and stop on the deciding tick.
/// With nobody acting, each round goes to the Union on the clock.
fn time_out_rounds(state: &mut GameState, n: u32) -> Vec<GameEvent> {
    let mut all = Vec::new();
    let mut decided = 0;
    for _ in 0..100_000 {
        let events = run(state, 1);
        decided += events
            .iter()
            .filter(|e| matches!(e, GameEvent::RoundEnd { .. }))
            .count() as u32;
        all.extend(events);
        if decided == n {
            break;
        }
    }
    assert_eq!(decided, n, "rounds stuck");
    all
}

#[test]
fn sides_swap_at_half_and_the_score_swaps_with_the_fighters() {
    let mut state = arena(SabotageConfig {
        live_ticks: 20,
        ..quick()
    });
    let ids: Vec<Uuid> = (1..=4).map(|n| join(&mut state, n)).collect();
    state.start_round();
    let first_union = side(&state, Team::Union);
    let events = time_out_rounds(&mut state, 3);
    assert_eq!(state.sabotage.as_ref().unwrap().score.union, 3);
    assert!(!kinds(&events).contains(&SabotageEventKind::SidesSwapped));
    // The fourth round ends the half.
    let events = time_out_rounds(&mut state, 1);
    let (_, result) = round_end(&events).unwrap();
    assert!(result.sides_swap && !result.match_over);
    assert_eq!(result.round, 4);
    assert_eq!(
        state.sabotage_end_delay(),
        Some(5),
        "the swap card holds longer"
    );
    let events = run(&mut state, 5);
    assert!(kinds(&events).contains(&SabotageEventKind::SidesSwapped));
    let sab = state.sabotage.as_ref().unwrap();
    assert_eq!(sab.round, 5);
    assert_eq!(
        (sab.score.union, sab.score.coalition),
        (0, 4),
        "the score follows the people"
    );
    for id in &first_union {
        assert_eq!(player(&state, *id).team, Some(Team::Coalition));
    }
    let wire = state.snapshot().sabotage.unwrap();
    assert_eq!((wire.half, wire.round), (2, 5));
    let _ = ids;
}

#[test]
fn the_match_ends_at_the_target_and_a_new_match_starts_fresh() {
    let mut state = arena(SabotageConfig {
        live_ticks: 20,
        ..quick()
    });
    for n in 1..=2 {
        join(&mut state, n);
    }
    state.start_round();
    let union_first = side(&state, Team::Union)[0];
    // Rounds 1-4 to the Union uniform, then the swap: the same people now
    // wear the coalition uniform and lose rounds 5-8 on the clock.
    let events = time_out_rounds(&mut state, 8);
    let (_, result) = events
        .iter()
        .filter_map(|e| match e {
            GameEvent::RoundEnd {
                winning_team,
                sabotage: Some(r),
                ..
            } => Some((*winning_team, r.clone())),
            _ => None,
        })
        .next_back()
        .unwrap();
    assert_eq!(result.round, 8);
    assert_eq!((result.score.union, result.score.coalition), (4, 4));
    assert!(!result.match_over, "4-4 goes to the extra pair");
    // Extra pair: round 9 to the Union, then a swap, round 10 to the Union again.
    let events = time_out_rounds(&mut state, 2);
    let results: Vec<_> = events
        .iter()
        .filter_map(|e| match e {
            GameEvent::RoundEnd {
                sabotage: Some(r), ..
            } => Some(r.clone()),
            _ => None,
        })
        .collect();
    assert!(results[0].sides_swap, "extra time swaps at its own half");
    let last = results.last().unwrap();
    assert!(last.match_over);
    assert_eq!(
        last.match_winner, None,
        "5-5 after the extra pair is a draw"
    );
    assert!(state
        .ended_host_line
        .as_deref()
        .is_some_and(|line| line.contains("LEVEL AFTER EXTRA TIME")));
    run(&mut state, 5);
    let sab = state.sabotage.as_ref().unwrap();
    assert_eq!((sab.round, sab.score.union, sab.score.coalition), (1, 0, 0));
    let _ = union_first;
}

#[test]
fn a_side_reaching_the_target_takes_the_match() {
    let mut state = arena(SabotageConfig {
        live_ticks: 20,
        ..quick()
    });
    for n in 1..=2 {
        join(&mut state, n);
    }
    state.start_round();
    // Win rounds by elimination for whichever side holds the coalition uniform.
    let mut last = None;
    for _ in 0..5 {
        let muster = state.config.sabotage.muster_ticks;
        run(&mut state, muster + 1);
        let attacker = side(&state, Team::Coalition)[0];
        let defender = side(&state, Team::Union)[0];
        let first_person = Uuid::from_u128(1);
        let (shooter, victim) = if attacker == first_person {
            (attacker, defender)
        } else {
            (defender, attacker)
        };
        state.hit_for_test(shooter, victim, 500);
        let events = run(&mut state, 1);
        last = round_end(&events);
        if last.as_ref().is_some_and(|(_, r)| r.match_over) {
            break;
        }
        let delay = state.sabotage_end_delay().unwrap();
        run(&mut state, delay);
    }
    let (winner, result) = last.unwrap();
    assert!(result.match_over);
    assert_eq!(result.match_winner, winner);
    assert_eq!(result.score.get(winner.unwrap()), 5);
    assert!(state
        .ended_host_line
        .as_deref()
        .is_some_and(|line| line.contains("TAKE THE MATCH")));
}

#[test]
fn survivors_carry_their_arsenal_and_the_fallen_drop_their_primary() {
    let (mut state, _) = two_a_side(quick());
    let defenders = side(&state, Team::Union);
    let attackers = side(&state, Team::Coalition);
    for id in defenders.iter().chain(&attackers) {
        let p = state.players.iter_mut().find(|p| p.id == *id).unwrap();
        p.inventory.grant_weapon(WeaponType::Rail);
        p.inventory.grant_weapon(WeaponType::Tack);
        p.weapon = WeaponType::Tack;
        p.armor = 50;
    }
    put(&mut state, attackers[0], [-20.0, 0.0, 10.0]);
    assert!(state.hit_for_test(defenders[0], attackers[0], 500));
    let dropped: Vec<_> = state
        .pickups
        .iter()
        .filter(|p| p.id.starts_with("dropped_"))
        .collect();
    assert_eq!(dropped.len(), 1);
    assert_eq!(
        dropped[0].kind,
        crate::sim::PickupKind::Weapon(WeaponType::Rail)
    );
    assert!((dropped[0].x + 20.0).abs() < 0.01 && (dropped[0].z - 10.0).abs() < 0.01);
    // Anyone can take it; once taken it is gone, not respawning.
    put(&mut state, defenders[1], [-20.0, 0.0, 10.0]);
    run(&mut state, 1);
    assert!(state.pickups.iter().all(|p| !p.id.starts_with("dropped_")));
    // Weapon-only arsenals drop nothing; nothing drops twice.
    state.end_round("test".into());
    run(&mut state, 10);
    let survivor = player(&state, defenders[0]);
    assert!(
        survivor.inventory.owns(WeaponType::Rail),
        "a survivor keeps the Rail"
    );
    assert_eq!(survivor.armor, 50, "and the armour");
    assert_eq!(survivor.hp, 100);
    let fallen = player(&state, attackers[0]);
    assert!(
        !fallen.inventory.owns(WeaponType::Rail),
        "the fallen start empty"
    );
    assert_eq!((fallen.weapon, fallen.armor), (WeaponType::Fists, 0));
    assert!(!fallen.eliminated);
    assert!(state.pickups.iter().all(|p| !p.id.starts_with("dropped_")));
}

#[test]
fn weapon_only_mutators_keep_their_arsenal_and_drop_nothing() {
    let mut state = GameState::with_map(MapKind::Sector9, false);
    state.seed(3);
    state.apply_config(config(quick(), &[Mutator::RailOnly]));
    for n in 1..=2 {
        join(&mut state, n);
    }
    state.start_round();
    run(&mut state, 5);
    let attacker = side(&state, Team::Coalition)[0];
    let defender = side(&state, Team::Union)[0];
    assert_eq!(player(&state, attacker).weapon, WeaponType::Rail);
    assert!(state.pickups.iter().all(|p| p.kind.weapon().is_none()));
    state.hit_for_test(defender, attacker, 500);
    assert!(state.pickups.iter().all(|p| !p.id.starts_with("dropped_")));
    assert!(RuleSet::new(GameMode::Sabotage, &[Mutator::TwoLives], false).is_err());
}

#[test]
fn a_human_magazine_survives_the_next_sabotage_round() {
    let mut state = arena(quick());
    let id = Uuid::new_v4();
    state.add_player(id, "Proxy".into(), Role::Human);
    state.arm_joined_magazines(id);
    state.start_round();
    assert!(player(&state, id).inventory.armed());
    state.end_round("round".into());
    state.players.iter_mut().find(|p| p.id == id).unwrap().hp = 0;
    state.start_round();
    assert!(player(&state, id).inventory.armed());
    assert_eq!(player(&state, id).weapon, WeaponType::Fists);
    assert!(state
        .players
        .iter_mut()
        .find(|p| p.id == id)
        .unwrap()
        .inventory
        .grant_weapon(WeaponType::Tack));
    let loadout = player(&state, id)
        .inventory
        .state(id, WeaponType::Tack, state.tick)
        .unwrap();
    assert_eq!(loadout.shots(WeaponType::Tack), Some(12));
    assert_eq!(loadout.ammo(crate::protocol::AmmoPool::Bullets), 50);
}

#[test]
fn golden_rail_under_discovery_hands_over_the_railgun() {
    let mut state = GameState::with_map(MapKind::Sector9, false);
    state.seed(5);
    state.apply_config(config(quick(), &[Mutator::GoldenRail]));
    for n in 1..=2 {
        join(&mut state, n);
    }
    state.start_round();
    run(&mut state, 5);
    let gold = state.golden_rail.clone().unwrap();
    let attacker = side(&state, Team::Coalition)[0];
    put(&mut state, attacker, [gold.x, gold.floor, gold.z]);
    run(&mut state, 1);
    let p = player(&state, attacker);
    assert!(p.golden && p.inventory.owns(WeaponType::Rail));
}

#[test]
fn joiners_spawn_in_muster_and_wait_out_a_live_round() {
    let mut state = arena(quick());
    for n in 1..=2 {
        join(&mut state, n);
    }
    state.start_round();
    let early = join(&mut state, 3);
    let p = player(&state, early);
    let layout = MapKind::Sector9.sabotage_layout().unwrap();
    assert!(!p.eliminated);
    assert!(layout.in_muster(p.team.unwrap().index(), p.x, p.z));
    run(&mut state, 5);
    let late = join(&mut state, 4);
    let p = player(&state, late);
    assert!(p.eliminated, "a live round is not joined halfway");
    assert_eq!(p.lives, Some(0));
    assert!(state.snapshot().players.iter().all(|s| s.id != late));
    state.end_round("test".into());
    run(&mut state, 4);
    assert!(!player(&state, late).eliminated, "in for the next round");
}

#[test]
fn a_lone_side_cannot_win_by_elimination_but_still_plants() {
    let mut state = arena(quick());
    let solo = join(&mut state, 1);
    state.start_round();
    run(&mut state, 5);
    assert_eq!(player(&state, solo).team, Some(Team::Coalition));
    assert_eq!(carrier(&state), solo);
    put(&mut state, solo, B);
    hold_use(&mut state, solo);
    let events = run(&mut state, 61);
    assert!(kinds(&events).contains(&SabotageEventKind::Planted));
    assert!(round_end(&events).is_none());
    let events = run(&mut state, 300);
    assert_eq!(
        round_end(&events).unwrap().1.reason,
        SabotageReason::Detonation
    );
}

#[test]
fn frags_carry_across_the_rounds_of_a_match() {
    let (mut state, _) = two_a_side(quick());
    let attacker = side(&state, Team::Coalition)[0];
    let defender = side(&state, Team::Union)[0];
    state.hit_for_test(attacker, defender, 500);
    assert_eq!(state.scores[&attacker], 1);
    state.end_round("test".into());
    run(&mut state, 5);
    assert_eq!(state.round_state, RoundState::Active);
    assert_eq!(state.scores[&attacker], 1, "kills count across the match");
}

#[test]
fn every_rule_set_message_round_trips_on_the_wire() {
    let (mut state, _) = two_a_side(quick());
    plant_at_a(&mut state);
    let snapshot = state.snapshot();
    let json = serde_json::to_string(&ServerMessage::Snapshot(snapshot)).unwrap();
    let back: ServerMessage = serde_json::from_str(&json).unwrap();
    match back {
        ServerMessage::Snapshot(snap) => {
            let sab = snap.sabotage.unwrap();
            assert_eq!(sab.phase, SabotagePhase::Planted);
            assert_eq!(sab.format, SabotageFormat::Short);
        }
        other => panic!("{other:?}"),
    }
    let json = serde_json::to_value(state.map_info()).unwrap();
    assert_eq!(json["sabotage"]["sites"][1]["id"], "b");
    assert_eq!(json["sabotage"]["attackers"], "coalition");
}

#[test]
fn the_sector_9_layout_is_clear_inside_its_zones_and_near_its_pistols() {
    use crate::movement::{RADIUS, STEP_UP};
    let map = MapKind::Sector9;
    let layout = map.sabotage_layout().unwrap();
    assert!(layout.wire.validate().is_ok());
    let arena = crate::maps::arena(map);
    let clear = |x: f32, z: f32| !arena.blocked_at(x, z, STEP_UP);
    for side in 0..2 {
        let pad = &layout.pads[side];
        assert!(
            layout.in_muster(side, pad.x, pad.z),
            "pad {side} in its zone"
        );
        assert!(clear(pad.x, pad.z));
        for slot in 0..18 {
            let [x, floor, z, _] = crate::sim::sabotage::spawn_point(layout, side, slot);
            assert_eq!(floor, 0.0);
            assert!(clear(x, z), "spawn {side}/{slot} at ({x}, {z}) is blocked");
            assert!(
                layout.in_muster(side, x, z),
                "spawn {side}/{slot} outside its zone"
            );
            if slot < layout.spawns[side].len() {
                let to_pad = (pad.x - x).hypot(pad.z - z);
                assert!(
                    to_pad <= crate::movement::TOP_SPEED * 2.0,
                    "spawn {side}/{slot} is {to_pad} m from its pistol"
                );
            }
        }
    }
    for site in &layout.wire.sites {
        let [cx, _, cz] = site.center;
        for ring in 0..=4 {
            let r = site.radius * ring as f32 / 4.0;
            for step in 0..16 {
                let angle = step as f32 * std::f32::consts::TAU / 16.0;
                let (x, z) = (cx + angle.cos() * r, cz + angle.sin() * r);
                assert!(
                    clear(x, z),
                    "plant area of {:?} blocked at ({x}, {z})",
                    site.id
                );
                assert!(
                    arena.support_height(x, z, 0.0) < 0.01,
                    "plant area of {:?} is on the floor",
                    site.id
                );
            }
        }
        assert_eq!(
            layout.wire.callout_at(cx, cz),
            Some(match site.id {
                SiteId::A => "a_frame",
                SiteId::B => "b_server",
            })
        );
        for spot in &layout.holds[site.id.index()] {
            assert!(clear(spot[0], spot[2]), "hold {spot:?} blocked");
            assert!((spot[0] - cx).hypot(spot[2] - cz) <= 8.0 + RADIUS);
        }
    }
    // Every point a fighter can stand on has a callout.
    for x in (-99..=99).step_by(9) {
        for z in (-99..=99).step_by(9) {
            assert!(layout.wire.callout_at(x as f32, z as f32).is_some());
        }
    }
    for other in MapKind::ALL
        .into_iter()
        .filter(|m| !matches!(m, MapKind::Sector9 | MapKind::LowWater))
    {
        assert!(
            other.sabotage_map().is_none(),
            "{other:?} is not built for Sabotage"
        );
    }
}

/// Ticks for one fighter to walk from `from` to `to` on Sector 9 with the
/// shared navigator and ordinary server movement, or None if it never arrives.
fn walk_ticks(from: [f32; 3], to: [f32; 3]) -> Option<u32> {
    use crate::navigation::{NavigationGoal, Navigator};
    let navigation = crate::maps::navigation(MapKind::Sector9);
    let mut state = GameState::with_map(MapKind::Sector9, false);
    state.config.time_limit_ticks = None;
    state.config.boss_spawn_ticks = None;
    state.config.compliance_ping_ticks = None;
    let id = Uuid::from_u128(77);
    state.add_player(id, "Walker".into(), Role::Agent);
    state.start_round();
    put(&mut state, id, from);
    let mut navigator = Navigator::default();
    for tick in 0..2400u32 {
        let p = &state.players[0];
        let here = [p.x, p.y - PLAYER_FLOOR_Y, p.z];
        if (here[0] - to[0]).hypot(here[2] - to[2]) < 0.5 {
            return Some(tick);
        }
        let action = navigator.steer(
            navigation,
            here,
            NavigationGoal {
                feet: to,
                combat: false,
            },
            Action {
                forward: true,
                ..Action::default()
            },
            u64::from(tick),
            true,
        );
        state.set_action(id, action);
        state.tick(0.05);
        state.take_events();
    }
    None
}

#[test]
fn sabotage_routes_meet_the_timing_targets() {
    let layout = MapKind::Sector9.sabotage_layout().unwrap();
    let seconds = |from: [f32; 3], to: [f32; 3]| {
        walk_ticks(from, to).unwrap_or_else(|| panic!("{from:?} -> {to:?} never arrives")) as f32
            / 20.0
    };
    let [a, b] = [layout.wire.sites[0].center, layout.wire.sites[1].center];
    // The attack reaches either site in 15 to 20 seconds from the yard on the
    // straight Mid Doors line (88 to 94 metres, 17.7 to 18.8 s). The navigator's two
    // metre grid adds two to three seconds of cornering, which bots also pay.
    for slot in 0..layout.spawns[1].len() {
        let [x, floor, z, _] = layout.spawns[1][slot];
        for site in [a, b] {
            let t = seconds([x, floor, z], site);
            eprintln!("attacker {slot} -> {site:?}: {t:.1} s");
            assert!(
                (15.0..=22.0).contains(&t),
                "attacker {slot} -> {site:?}: {t:.1} s"
            );
        }
    }
    // The defence reaches its nearer site in under 8 seconds.
    for slot in 0..layout.spawns[0].len() {
        let [x, floor, z, _] = layout.spawns[0][slot];
        let near = if z <= 0.0 { a } else { b };
        let t = seconds([x, floor, z], near);
        eprintln!("defender {slot} -> {near:?}: {t:.1} s");
        assert!(t < 8.0, "defender {slot} -> {near:?}: {t:.1} s");
    }
    // Rotation between the sites takes 10 to 12 seconds, both ways.
    for (from, to) in [(a, b), (b, a)] {
        let t = seconds(from, to);
        eprintln!("rotate {from:?} -> {to:?}: {t:.1} s");
        assert!(
            (10.0..=12.5).contains(&t),
            "rotate {from:?} -> {to:?}: {t:.1} s"
        );
    }
    // Every other way in is walkable: from each mid stage, through the north
    // and south mid doors, and from the West Hall's service doors.
    for side in 0..2 {
        let site = layout.wire.sites[side].center;
        for stage in &layout.stages[side] {
            seconds(*stage, site);
        }
        seconds(layout.approaches[side], layout.stages[side][0]);
        seconds([-90.0, 0.0, if side == 0 { -40.0 } else { 40.0 }], site);
        for hold in &layout.holds[side] {
            seconds(*hold, site);
        }
    }
}
