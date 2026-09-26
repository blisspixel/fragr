//! Rule sets: team deathmatch, the GoldenEye-style mutators, lives and the
//! Host's reactions, each as a seeded rule on the authoritative sim.
use crate::maps::AuthoredMap;
use crate::protocol::{
    Action, GameEvent, GameMode, HostReactionKind, LookAt, Mutator, Role, ServerMessage, Team,
    WeaponType,
};
use crate::rules::RuleSet;
use crate::session::GameSession;
use crate::sim::{GameState, MapKind, MatchConfig, RoundState, PLAYER_FLOOR_Y};
use uuid::Uuid;

fn rules(mode: GameMode, mutators: &[Mutator]) -> RuleSet {
    RuleSet::new(mode, mutators, false).unwrap()
}

fn config(rules: RuleSet) -> MatchConfig {
    MatchConfig {
        frag_limit: Some(rules.default_frag_limit()),
        time_limit_ticks: Some(20 * 120),
        boss_spawn_ticks: None,
        compliance_ping_ticks: None,
        rules,
        ..MatchConfig::default()
    }
}

/// A flat, open 32 metre room: every fight here is a clear line.
fn range(rules: RuleSet) -> GameState {
    let json = serde_json::json!({
        "version":1,"map_id":1005,"name":"Rules range","half_extent":16,"ground":"concrete",
        "equipment":"full_arsenal","solids":[],
        "spawns":[
            {"id":"west","feet":[-10,0,0],"yaw":0},
            {"id":"east","feet":[10,0,0],"yaw":0},
            {"id":"north","feet":[0,0,-10],"yaw":0},
            {"id":"south","feet":[0,0,10],"yaw":0}
        ],
        "landmarks":[{"id":"middle","feet":[0,0,0]}]
    });
    let mut state = GameState::with_authored_map(
        AuthoredMap::read(serde_json::to_vec(&json).unwrap().as_slice()).unwrap(),
    );
    state.seed(11);
    state.apply_config(config(rules));
    state
}

fn arena(map: MapKind, rules: RuleSet) -> GameState {
    let mut state = GameState::with_map(map, false);
    state.seed(11);
    state.apply_config(config(rules));
    state
}

fn join(state: &mut GameState, n: u128, role: Role) -> Uuid {
    let id = Uuid::from_u128(n);
    state.add_player(id, format!("F{n}"), role);
    id
}

fn player(state: &GameState, id: Uuid) -> &crate::sim::Player {
    state.players.iter().find(|p| p.id == id).unwrap()
}

fn place(state: &mut GameState, id: Uuid, x: f32, z: f32) {
    let p = state.players.iter_mut().find(|p| p.id == id).unwrap();
    p.x = x;
    p.z = z;
    p.y = PLAYER_FLOOR_Y;
    p.vy = 0.0;
}

/// Put the pair four metres apart and fire until the shooter lands a shot.
/// Returns the damage the shot dealt.
fn shoot(state: &mut GameState, shooter: Uuid, target: Uuid) -> i32 {
    state.spawn_shields.clear();
    place(state, shooter, 0.0, 0.0);
    place(state, target, 4.0, 0.0);
    for _ in 0..60 {
        state.set_action(
            shooter,
            Action {
                fire: true,
                look_at: Some(LookAt {
                    player_id: Some(target),
                    ..Default::default()
                }),
                ..Default::default()
            },
        );
        state.tick(0.05);
        if let Some(shot) = state
            .shot_results
            .iter()
            .find(|shot| shot.shooter_id == shooter && shot.target_id == Some(target))
        {
            let damage = shot.damage;
            state.set_action(shooter, Action::default());
            return damage;
        }
    }
    panic!("the shooter never hit");
}

/// One hit is lethal: the victim is set to one point of health first.
fn kill(state: &mut GameState, shooter: Uuid, victim: Uuid) {
    {
        let p = state.players.iter_mut().find(|p| p.id == victim).unwrap();
        p.hp = 1;
        p.armor = 0;
    }
    shoot(state, shooter, victim);
    assert!(player(state, victim).hp <= 0, "the victim should be down");
}

fn events(state: &mut GameState) -> Vec<GameEvent> {
    state.take_events()
}

fn reactions(events: &[GameEvent]) -> Vec<HostReactionKind> {
    events
        .iter()
        .filter_map(|event| match event {
            GameEvent::HostReaction { kind, .. } => Some(*kind),
            _ => None,
        })
        .collect()
}

/// Let respawn timers run out without anyone shooting.
fn wait(state: &mut GameState, ticks: u32) {
    for _ in 0..ticks {
        state.tick(0.05);
    }
}

#[test]
fn joiners_fill_the_short_side_through_one_path() {
    let mut state = arena(MapKind::ArenaDuel, rules(GameMode::Tdm, &[]));
    let roles = [
        Role::Human,
        Role::Agent,
        Role::Agent,
        Role::Human,
        Role::Agent,
    ];
    let ids: Vec<Uuid> = roles
        .iter()
        .enumerate()
        .map(|(i, role)| join(&mut state, i as u128 + 1, *role))
        .collect();
    let teams: Vec<Team> = ids
        .iter()
        .map(|id| player(&state, *id).team.unwrap())
        .collect();
    assert_eq!(
        teams,
        [
            Team::Coalition,
            Team::Union,
            Team::Coalition,
            Team::Union,
            Team::Coalition
        ]
    );
    assert_eq!(state.team_counts(), [2, 3]);
    // Free-for-all has no sides.
    let mut ffa = arena(MapKind::ArenaDuel, RuleSet::default());
    let solo = join(&mut ffa, 1, Role::Human);
    assert_eq!(player(&ffa, solo).team, None);
}

#[test]
fn round_start_rebalances_rule_bots_before_people() {
    let mut session = GameSession::with_map(MapKind::ArenaDuel, false);
    session
        .state
        .apply_config(config(rules(GameMode::Tdm, &[])));
    session.spawn_bots(4);
    let human = Uuid::from_u128(900);
    session.state.add_player(human, "Human".into(), Role::Human);
    assert_eq!(session.state.team_counts(), [2, 3]);
    // Two leave from one side: 2 against 1 is still fair, 3 against 1 is not.
    let union: Vec<Uuid> = session
        .state
        .players
        .iter()
        .filter(|p| p.team == Some(Team::Union))
        .map(|p| p.id)
        .collect();
    for id in &union {
        session.state.remove_player(*id);
    }
    assert_eq!(session.state.team_counts(), [0, 3]);
    session.state.start_round();
    assert_eq!(session.state.team_counts(), [1, 2]);
    let moved = session
        .state
        .players
        .iter()
        .find(|p| p.team == Some(Team::Union))
        .unwrap();
    assert!(session.bots.iter().any(|b| b.player_id == moved.id));
    assert_eq!(player(&session.state, human).team, Some(Team::Coalition));
}

#[test]
fn each_side_spawns_in_its_own_half() {
    for map in MapKind::ALL {
        let mut state = arena(map, rules(GameMode::Tdm, &[]));
        for n in 1..=8 {
            join(&mut state, n, Role::Agent);
        }
        for p in &state.players {
            let side = crate::rules::spawn_side(p.x);
            assert_eq!(side, p.team, "{} on {:?} spawned at x {}", p.name, map, p.x);
        }
        // A respawn keeps the half.
        let victim = state.players[0].id;
        state.round_state = RoundState::Active;
        let team = player(&state, victim).team;
        {
            let p = state.players.iter_mut().find(|p| p.id == victim).unwrap();
            p.hp = 0;
            p.respawn_timer = Some(1);
        }
        state.tick(0.05);
        state.tick(0.05);
        let respawned = player(&state, victim);
        assert!(respawned.respawn_timer.is_none());
        assert_eq!(crate::rules::spawn_side(respawned.x), team, "{map:?}");
    }
}

#[test]
fn friendly_fire_is_off_by_default_and_a_team_kill_scores_nothing() {
    let mut state = range(rules(GameMode::Tdm, &[]));
    let a = join(&mut state, 1, Role::Human);
    let b = join(&mut state, 2, Role::Agent);
    let c = join(&mut state, 3, Role::Agent);
    assert_eq!(player(&state, a).team, player(&state, c).team);
    assert_ne!(player(&state, a).team, player(&state, b).team);
    // The shot stops on the teammate, who takes nothing.
    assert_eq!(shoot(&mut state, a, c), 0);
    assert_eq!(player(&state, c).hp, 100);
    // The enemy takes the full hit.
    assert_eq!(shoot(&mut state, a, b), WeaponType::Flechette.damage());

    let mut ff = range(RuleSet::new(GameMode::Tdm, &[], true).unwrap());
    let a = join(&mut ff, 1, Role::Human);
    join(&mut ff, 2, Role::Agent);
    let c = join(&mut ff, 3, Role::Agent);
    assert_eq!(shoot(&mut ff, a, c), WeaponType::Flechette.damage());
    ff.take_events();
    kill(&mut ff, a, c);
    let frags: Vec<GameEvent> = events(&mut ff)
        .into_iter()
        .filter(|e| matches!(e, GameEvent::Frag { .. }))
        .collect();
    assert_eq!(frags.len(), 1);
    assert!(matches!(
        &frags[0],
        GameEvent::Frag { killer_score: 0, killer_team: Some(k), victim_team: Some(v), .. } if k == v
    ));
    assert_eq!(ff.scores[&a], 0);
    assert_eq!(ff.team_scores.max(), 0);
}

#[test]
fn side_frags_decide_the_round_and_a_level_clock_is_a_draw() {
    let mut state = range(rules(GameMode::Tdm, &[]));
    state.config.frag_limit = Some(2);
    let a = join(&mut state, 1, Role::Human);
    let b = join(&mut state, 2, Role::Agent);
    let team_a = player(&state, a).team.unwrap();
    kill(&mut state, a, b);
    assert_eq!(state.team_scores.get(team_a), 1);
    assert_eq!(state.round_state, RoundState::Active);
    wait(&mut state, 70);
    kill(&mut state, a, b);
    assert_eq!(state.team_scores.get(team_a), 2);
    state.tick(0.05);
    assert_eq!(state.round_state, RoundState::Ended);
    let end = events(&mut state)
        .into_iter()
        .find_map(|e| match e {
            GameEvent::RoundEnd {
                winning_team,
                team_scores,
                host_line,
                ..
            } => Some((winning_team, team_scores, host_line)),
            _ => None,
        })
        .unwrap();
    assert_eq!(end.0, Some(team_a));
    assert_eq!(end.1.unwrap().get(team_a), 2);
    assert!(end.2.contains("TAKE THE ROUND, 2 TO 0"), "{}", end.2);

    let mut level = range(rules(GameMode::Tdm, &[]));
    join(&mut level, 1, Role::Human);
    join(&mut level, 2, Role::Agent);
    level.config.time_limit_ticks = Some(3);
    wait(&mut level, 4);
    let end = events(&mut level)
        .into_iter()
        .find_map(|e| match e {
            GameEvent::RoundEnd {
                winning_team,
                host_line,
                ..
            } => Some((winning_team, host_line)),
            _ => None,
        })
        .unwrap();
    assert_eq!(end.0, None);
    assert!(end.1.contains("LEVEL AT THE BELL"));
}

#[test]
fn weapon_only_mutators_hand_everyone_one_weapon_with_no_pads() {
    for (mutator, weapon) in [
        (Mutator::RailOnly, WeaponType::Rail),
        (Mutator::ShotgunOnly, WeaponType::Scatter),
        (Mutator::FistsOnly, WeaponType::Fists),
    ] {
        let mut state = arena(MapKind::ArenaDuel, rules(GameMode::Ffa, &[mutator]));
        state.start_round();
        assert!(
            state.pickups.iter().all(|pad| pad.kind.weapon().is_none()),
            "{mutator:?} left a weapon pad"
        );
        assert!(!state.pickups.is_empty(), "health and armour stay");
        let a = join(&mut state, 1, Role::Human);
        assert_eq!(player(&state, a).weapon, weapon);
        state.set_action(
            a,
            Action {
                weapon_swap: Some(WeaponType::Flechette),
                ..Default::default()
            },
        );
        state.tick(0.05);
        assert_eq!(player(&state, a).weapon, weapon, "{mutator:?} swap refused");
        let snapshot = state.snapshot();
        assert_eq!(snapshot.players[0].weapon, weapon.name());
    }
}

#[test]
fn rail_only_respawns_with_the_rail_and_fires_forever() {
    let mut state = range(rules(GameMode::Ffa, &[Mutator::RailOnly]));
    let a = join(&mut state, 1, Role::Human);
    let b = join(&mut state, 2, Role::Agent);
    for _ in 0..3 {
        wait(&mut state, 25);
        assert_eq!(shoot(&mut state, a, b), WeaponType::Rail.damage());
        wait(&mut state, 70);
        let p = state.players.iter_mut().find(|p| p.id == b).unwrap();
        p.hp = 100;
    }
    kill(&mut state, a, b);
    wait(&mut state, 70);
    assert_eq!(player(&state, b).weapon, WeaponType::Rail);
}

#[test]
fn licence_to_kill_makes_any_damaging_hit_a_kill() {
    let mut state = range(rules(GameMode::Ffa, &[Mutator::LicenceToKill]));
    let a = join(&mut state, 1, Role::Human);
    let b = join(&mut state, 2, Role::Agent);
    {
        let p = state.players.iter_mut().find(|p| p.id == b).unwrap();
        p.armor = 100;
    }
    let damage = shoot(&mut state, a, b);
    assert!(damage >= 200, "{damage}");
    assert!(player(&state, b).hp <= 0);
    assert_eq!(state.scores[&a], 1);
    // A teammate is still safe with friendly fire off.
    let mut team = range(rules(GameMode::Tdm, &[Mutator::LicenceToKill]));
    let a = join(&mut team, 1, Role::Human);
    join(&mut team, 2, Role::Agent);
    let c = join(&mut team, 3, Role::Agent);
    assert_eq!(shoot(&mut team, a, c), 0);
    assert_eq!(player(&team, c).hp, 100);
}

#[test]
fn the_golden_rail_kills_in_one_hit_and_returns_when_its_holder_dies() {
    let mut arena_state = arena(
        MapKind::ArenaDuel,
        rules(GameMode::Ffa, &[Mutator::GoldenRail]),
    );
    arena_state.start_round();
    let rail_pad = MapKind::ArenaDuel
        .pickups()
        .into_iter()
        .find(|pad| pad.kind == crate::sim::PickupKind::Weapon(WeaponType::Rail))
        .unwrap();
    let gold = arena_state.golden_rail.clone().unwrap();
    assert_eq!(
        (gold.x, gold.z, gold.floor),
        (rail_pad.x, rail_pad.z, rail_pad.floor)
    );
    assert!(arena_state
        .pickups
        .iter()
        .all(|pad| pad.kind != crate::sim::PickupKind::Weapon(WeaponType::Rail)));
    let wire = arena_state.snapshot();
    let pad = wire
        .pickups
        .iter()
        .find(|p| p.kind == "golden_rail")
        .unwrap();
    assert!(pad.available);
    assert_eq!(pad.weapon, "Rail");

    let mut state = range(rules(GameMode::Ffa, &[Mutator::GoldenRail]));
    state.start_round();
    let a = join(&mut state, 1, Role::Human);
    let b = join(&mut state, 2, Role::Agent);
    let c = join(&mut state, 3, Role::Agent);
    state.take_events();
    // The range has no Railgun pad, so the gold waits in the middle.
    place(&mut state, a, 0.0, 0.0);
    place(&mut state, b, 8.0, 8.0);
    place(&mut state, c, -8.0, -8.0);
    state.tick(0.05);
    assert!(player(&state, a).golden);
    assert_eq!(player(&state, a).weapon, WeaponType::Rail);
    assert_eq!(state.golden_rail.as_ref().unwrap().holder, Some(a));
    let taken = events(&mut state);
    assert_eq!(reactions(&taken), [HostReactionKind::GoldenRail]);
    assert!(taken
        .iter()
        .any(|e| matches!(e, GameEvent::Pickup { kind, .. } if kind == "golden_rail")));
    assert!(state
        .snapshot()
        .players
        .iter()
        .any(|p| p.id == a && p.golden));
    // One golden hit through full armour.
    {
        let p = state.players.iter_mut().find(|p| p.id == b).unwrap();
        p.armor = 100;
    }
    wait(&mut state, 20);
    shoot(&mut state, a, b);
    assert!(player(&state, b).hp <= 0);
    // The holder dies: the gold goes home and the holder's glow goes out.
    wait(&mut state, 25);
    {
        let p = state.players.iter_mut().find(|p| p.id == c).unwrap();
        p.weapon = WeaponType::Rail;
    }
    kill(&mut state, c, a);
    assert!(!player(&state, a).golden);
    assert_eq!(state.golden_rail.as_ref().unwrap().holder, None);
    // Leaving also returns it.
    place(&mut state, c, 0.0, 0.0);
    state.tick(0.05);
    assert_eq!(state.golden_rail.as_ref().unwrap().holder, Some(c));
    state.remove_player(c);
    assert_eq!(state.golden_rail.as_ref().unwrap().holder, None);
}

#[test]
fn two_lives_eliminates_and_the_last_fighter_wins() {
    let mut state = range(rules(GameMode::Ffa, &[Mutator::TwoLives]));
    state.config.frag_limit = Some(50);
    state.round_state = RoundState::Warmup;
    let a = join(&mut state, 1, Role::Human);
    let b = join(&mut state, 2, Role::Agent);
    let c = join(&mut state, 3, Role::Agent);
    state.start_round();
    assert_eq!(player(&state, b).lives, Some(2));
    kill(&mut state, a, b);
    assert_eq!(player(&state, b).lives, Some(1));
    assert!(player(&state, b).respawn_timer.is_some());
    wait(&mut state, 70);
    kill(&mut state, a, b);
    assert!(player(&state, b).eliminated);
    wait(&mut state, 100);
    assert!(player(&state, b).respawn_timer.is_none() && player(&state, b).eliminated);
    assert!(state.snapshot().players.iter().all(|p| p.id != b));
    assert_eq!(state.round_state, RoundState::Active);
    // A late joiner enters with one life.
    let late = join(&mut state, 4, Role::Agent);
    assert_eq!(player(&state, late).lives, Some(1));
    kill(&mut state, a, late);
    kill(&mut state, a, c);
    wait(&mut state, 70);
    state.take_events();
    kill(&mut state, a, c);
    state.tick(0.05);
    assert_eq!(state.round_state, RoundState::Ended);
    let end = events(&mut state)
        .into_iter()
        .find_map(|e| match e {
            GameEvent::RoundEnd {
                winner,
                reason,
                host_line,
                ..
            } => Some((winner, reason, host_line)),
            _ => None,
        })
        .unwrap();
    assert_eq!(end.0.as_deref(), Some("F1"));
    assert_eq!(end.1, "Last fighter standing");
    assert!(end.2.contains("LAST ONE STANDING. F1"));
    // The next round brings everyone back with two lives.
    state.start_round();
    for id in [a, b, c, late] {
        let p = player(&state, id);
        assert!(!p.eliminated && p.respawn_timer.is_none() && p.hp > 0);
        assert_eq!(p.lives, Some(2));
    }
    // No drone referees a lives round.
    state.config.boss_spawn_ticks = Some(1);
    wait(&mut state, 5);
    assert!(state.boss_id.is_none());
}

#[test]
fn two_lives_in_teams_ends_on_the_last_side_and_calls_the_last_one_standing() {
    let mut state = range(rules(GameMode::Tdm, &[Mutator::TwoLives]));
    state.config.frag_limit = Some(50);
    state.round_state = RoundState::Warmup;
    let ids: Vec<Uuid> = (1..=5).map(|n| join(&mut state, n, Role::Agent)).collect();
    state.start_round();
    let coalition: Vec<Uuid> = ids
        .iter()
        .copied()
        .filter(|id| player(&state, *id).team == Some(Team::Coalition))
        .collect();
    let union: Vec<Uuid> = ids
        .iter()
        .copied()
        .filter(|id| player(&state, *id).team == Some(Team::Union))
        .collect();
    assert_eq!((coalition.len(), union.len()), (3, 2));
    let shooter = coalition[0];
    // Knock one Union fighter out: the other is the last one standing.
    kill(&mut state, shooter, union[0]);
    wait(&mut state, 70);
    state.take_events();
    wait(&mut state, 200);
    kill(&mut state, shooter, union[0]);
    let beats = events(&mut state);
    assert!(beats.iter().any(|e| matches!(
        e,
        GameEvent::HostReaction {
            kind: HostReactionKind::LastStanding,
            team: Some(Team::Union),
            ..
        }
    )));
    kill(&mut state, shooter, union[1]);
    wait(&mut state, 70);
    wait(&mut state, 200);
    kill(&mut state, shooter, union[1]);
    state.tick(0.05);
    assert_eq!(state.round_state, RoundState::Ended);
    let winning = events(&mut state).into_iter().find_map(|e| match e {
        GameEvent::RoundEnd {
            winning_team,
            reason,
            ..
        } => Some((winning_team, reason)),
        _ => None,
    });
    assert_eq!(
        winning,
        Some((Some(Team::Coalition), "Last side standing".to_string()))
    );
}

#[test]
fn first_blood_streaks_and_comebacks_are_called_with_a_gap() {
    let mut state = range(rules(GameMode::Tdm, &[]));
    state.config.frag_limit = Some(50);
    let a = join(&mut state, 1, Role::Human);
    let b = join(&mut state, 2, Role::Agent);
    state.take_events();
    kill(&mut state, a, b);
    let first = events(&mut state);
    assert!(first.iter().any(|e| matches!(
        e,
        GameEvent::HostReaction { kind: HostReactionKind::FirstBlood, variant: 0, player: Some(p), other: Some(o), .. }
            if p == "F1" && o == "F2"
    )));
    // B's side falls four behind, then draws level: a comeback.
    for _ in 0..3 {
        wait(&mut state, 70);
        kill(&mut state, a, b);
    }
    assert_eq!(state.team_scores.get(player(&state, a).team.unwrap()), 4);
    // A is on a four streak; B ends it, but only after the eight second gap.
    wait(&mut state, 70);
    state.take_events();
    kill(&mut state, b, a);
    let ended = reactions(&events(&mut state));
    assert_eq!(ended, [HostReactionKind::StreakEnded]);
    for _ in 0..3 {
        wait(&mut state, 70);
        kill(&mut state, b, a);
    }
    assert_eq!(state.team_scores.leader(), None);
    let calls: Vec<HostReactionKind> = reactions(&events(&mut state));
    assert_eq!(calls, [HostReactionKind::Comeback]);
    // Inside the gap a second beat is held back.
    let mut quick = range(rules(GameMode::Ffa, &[]));
    let a = join(&mut quick, 1, Role::Human);
    let b = join(&mut quick, 2, Role::Agent);
    kill(&mut quick, a, b);
    assert!(!quick_react(&mut quick));
    for _ in 0..crate::rules::REACTION_GAP_TICKS {
        quick.tick(0.05);
    }
    assert!(quick_react(&mut quick));
}

fn quick_react(state: &mut GameState) -> bool {
    state.take_events();
    state.react(HostReactionKind::StreakEnded, None, None, None)
}

#[test]
fn rule_bots_and_agents_leave_teammates_alone() {
    let mut state = range(rules(GameMode::Tdm, &[]));
    let bot = join(&mut state, 1, Role::Agent);
    join(&mut state, 2, Role::Agent);
    let mate = join(&mut state, 3, Role::Agent);
    state.players.retain(|p| p.id != Uuid::from_u128(2));
    place(&mut state, bot, 0.0, 0.0);
    place(&mut state, mate, 3.0, 0.0);
    let controller = crate::sim::BotController::new(bot, crate::sim::BotBehavior::Aggressive);
    let action = controller.update(&state);
    assert!(!action.fire && !action.forward);
    let snapshot = state.snapshot();
    let me = snapshot.players.iter().find(|p| p.id == bot).unwrap();
    let other = snapshot.players.iter().find(|p| p.id == mate).unwrap();
    assert_eq!(me.team, other.team);
    assert!(!me.is_hostile_to(other));
}

#[test]
fn every_reader_sees_the_same_rules() {
    let mut session = GameSession::with_map(MapKind::ArenaDuel, false);
    session.state.apply_config(config(
        RuleSet::new(GameMode::Tdm, &[Mutator::RailOnly, Mutator::TwoLives], true).unwrap(),
    ));
    session.spawn_bots(2);
    let ServerMessage::MapInfo {
        rules: Some(wire), ..
    } = session.state.map_info()
    else {
        panic!("an arena carries its rules");
    };
    assert_eq!(wire.mode, GameMode::Tdm);
    assert_eq!(wire.mutators, [Mutator::RailOnly, Mutator::TwoLives]);
    assert_eq!(wire.lives, Some(2));
    assert!(wire.friendly_fire);
    assert_eq!(wire.name, "Team Deathmatch: Rail Only, Two Lives");
    let json = serde_json::to_value(session.state.map_info()).unwrap();
    assert_eq!(json["rules"]["mode"], "tdm");
    assert_eq!(json["rules"]["mutators"][0], "rail-only");

    let status = session.state.live_status(2);
    assert_eq!(status.mode, "tdm");
    assert_eq!(status.mutators, ["rail-only", "two-lives"]);
    let status_json = serde_json::to_value(&status).unwrap();
    assert_eq!(status_json["mode"], "tdm");

    let messages = session.tick_messages(0.05);
    let snapshot = messages
        .iter()
        .find_map(|m| match m {
            ServerMessage::Snapshot(s) => Some(s.clone()),
            _ => None,
        })
        .unwrap();
    assert!(snapshot.team_scores.is_some());
    assert!(snapshot.players.iter().all(|p| p.team.is_some()));
    assert!(snapshot.players.iter().all(|p| p.lives == Some(2)));
    let json = serde_json::to_value(&snapshot).unwrap();
    assert!(json["team_scores"]["union"].is_u64());
    for _ in 0..60 {
        for message in session.tick_messages(0.05) {
            if let ServerMessage::Event(GameEvent::RoundStart { rules, .. }) = message {
                assert_eq!(rules.unwrap().mode, GameMode::Tdm);
                return;
            }
        }
    }
    panic!("no round started");
}

#[test]
fn plain_free_for_all_keeps_the_old_wire() {
    let mut state = arena(MapKind::ArenaDuel, RuleSet::default());
    join(&mut state, 1, Role::Human);
    let json = serde_json::to_value(state.snapshot()).unwrap();
    assert!(json.get("team_scores").is_none());
    assert!(json["players"][0].get("team").is_none());
    assert!(json["players"][0].get("lives").is_none());
    assert!(json["players"][0].get("golden").is_none());
    let status = serde_json::to_value(state.live_status(1)).unwrap();
    assert_eq!(status["mode"], "ffa");
    assert!(status.get("mutators").is_none());
    // Authored campaign maps carry no rules at all.
    let campaign = crate::maps::AuthoredSource::Mission(crate::protocol::MissionId::RecallNotice)
        .load()
        .unwrap();
    let state = GameState::with_authored_map(campaign);
    let json = serde_json::to_value(state.map_info()).unwrap();
    assert!(json.get("rules").is_none());
}
