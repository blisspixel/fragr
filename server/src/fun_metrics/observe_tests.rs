//! Seeded tick tests of the shared observer and the host recorder.
use super::observe::Observer;
use super::store::FunStore;
use super::HostRecorder;
use crate::protocol::{
    GameEvent, GameMode, Role, SabotageEventKind, SabotageReason, SabotageResult, ServerMessage,
    Team, TeamScores, WeaponType,
};
use crate::rules::RuleSet;
use crate::session::GameSession;
use crate::sim::{MapKind, MatchConfig};
use uuid::Uuid;

fn arcade(map: MapKind, mode: GameMode, frag_limit: Option<u32>, bots: usize) -> GameSession {
    let mut session = GameSession::with_map(map, false);
    session.state.use_replay_ids();
    session.state.seed(7);
    session.state.apply_config(MatchConfig {
        frag_limit,
        capture_limit: None,
        time_limit_ticks: Some(20 * 90),
        boss_spawn_ticks: None,
        compliance_ping_ticks: None,
        rules: RuleSet::new(mode, &[], false).unwrap(),
        ..MatchConfig::default()
    });
    session.spawn_bots(bots);
    session
}

fn play(session: &mut GameSession, observer: &mut Observer, ticks: u64) {
    for _ in 0..ticks {
        let messages = session.tick_messages(0.05);
        observer.observe(session, &messages);
        if observer.finished() {
            return;
        }
    }
}

fn event(event: GameEvent) -> ServerMessage {
    ServerMessage::Event(event)
}

fn round_start() -> GameEvent {
    GameEvent::RoundStart {
        round_number: 1,
        frag_limit: None,
        time_limit: None,
        players: Vec::new(),
        previous_winner: None,
        mode_name: crate::protocol::default_mode_name(),
        playlist: crate::protocol::default_playlist(),
        host_line: String::new(),
        rules: None,
    }
}

fn round_end(winning_team: Option<Team>, sabotage: Option<SabotageResult>) -> GameEvent {
    GameEvent::RoundEnd {
        winner: None,
        reason: "test".into(),
        final_scores: Vec::new(),
        winner_score: None,
        mvp: None,
        mvp_frags: None,
        host_line: String::new(),
        winning_team,
        team_scores: None,
        capture_scores: None,
        sabotage,
    }
}

#[test]
fn a_seeded_free_for_all_folds_into_one_finished_record() {
    let run = || {
        let mut session = arcade(MapKind::ArenaDuel, GameMode::Ffa, Some(4), 4);
        let mut observer = Observer::new(&session);
        play(&mut session, &mut observer, 20 * 120);
        observer
    };
    let observer = run();
    assert!(observer.finished(), "a frag limit of four ends the round");
    let record = observer.into_record(None);
    let tally = &record.tally;
    assert_eq!((record.map_id, record.mode), (1, GameMode::Ffa));
    assert_eq!(record.bot_tier, crate::sim::BotSkill::Regular);
    assert_eq!((record.fighters_peak, record.bots_peak), (4, 4));
    assert!(record.finished && record.match_ticks > 0);
    assert_eq!(tally.rounds, 1);
    assert!(tally.frags >= 4, "{tally:?}");
    assert!(tally.spawns >= 4 && tally.live_ticks > 0);
    let by_gun: u64 = tally.frag_weapons.0.iter().sum();
    assert!(by_gun <= tally.frags && by_gun > 0);
    assert!(tally.total_shots() > tally.hits / 2, "{tally:?}");
    // Hitscan hits name the zone they struck; a kill counts in its zone too.
    assert!(tally.zone_hits.total() > 0, "{tally:?}");
    assert!(tally.kill_zones.total() > 0, "{tally:?}");
    assert!(tally.kill_zones.total() <= tally.frags);
    assert!(tally.kill_zones.total() <= tally.zone_hits.total());
    assert!(
        tally.zone_hits.torso + tally.zone_hits.head > 0,
        "{tally:?}"
    );
    assert!(!tally.time_to_kill_ticks.is_empty());
    assert!(!tally.respawn_to_hit_ticks.is_empty());
    assert!(!tally.respawn_to_contact_ticks.is_empty());
    let distances: usize = tally.kill_distance_cm.0.iter().map(|s| s.len()).sum();
    assert!(distances > 0);
    for list in [
        &tally.time_to_kill_ticks,
        &tally.respawn_to_contact_ticks,
        &tally.respawn_to_hit_ticks,
    ] {
        assert!(
            list.0.windows(2).all(|pair| pair[0] <= pair[1]),
            "a record keeps spreads, not timelines"
        );
    }
    assert_eq!(record, run().into_record(None), "one seed, one record");
}

#[test]
fn kill_time_spawn_deaths_distance_and_contact_follow_the_events() {
    let mut session = GameSession::with_map(MapKind::ArenaDuel, false);
    let (a, b) = (Uuid::from_u128(1), Uuid::from_u128(2));
    session.state.add_player(a, "A".into(), Role::Agent);
    session.state.add_player(b, "B".into(), Role::Agent);
    for (id, x) in [(a, 0.0), (b, 3.0)] {
        let player = session
            .state
            .players
            .iter_mut()
            .find(|p| p.id == id)
            .unwrap();
        (player.x, player.z) = (x, 4.0);
    }
    let mut observer = Observer::new(&session);
    session.state.tick = 0;
    observer.message(&session, &event(round_start()));
    assert!(observer.live());
    session.state.tick = 10;
    observer.message(
        &session,
        &event(GameEvent::Hit {
            shooter: "A".into(),
            shooter_id: a,
            target: "B".into(),
            target_id: b,
            damage: 25,
            target_hp_after: 75,
        }),
    );
    session.state.tick = 40;
    observer.message(
        &session,
        &event(GameEvent::Frag {
            killer: "A".into(),
            victim: "B".into(),
            killer_score: 1,
            killer_id: Some(a),
            victim_id: Some(b),
            weapon: Some(WeaponType::Rail),
            killer_team: None,
            victim_team: None,
        }),
    );
    // A blast of one's own is a self death, never a hit or a kill time.
    observer.message(
        &session,
        &event(GameEvent::Hit {
            shooter: "A".into(),
            shooter_id: a,
            target: "A".into(),
            target_id: a,
            damage: 100,
            target_hp_after: 0,
        }),
    );
    let tally = observer.tally().clone();
    assert_eq!((tally.frags, tally.hits, tally.self_deaths), (1, 1, 1));
    assert_eq!(tally.time_to_kill_ticks.0, vec![30]);
    assert_eq!(tally.spawn_deaths, 1, "dead 2 s after the spawn");
    assert_eq!(*tally.frag_weapons.get(WeaponType::Rail), 1);
    assert_eq!(tally.kill_distance_cm.get(WeaponType::Rail).0, vec![300]);
    assert_eq!(tally.respawn_to_hit_ticks.0, vec![10, 10]);
    assert_eq!(tally.respawn_to_contact_ticks.0, vec![10, 10]);
    assert_eq!(tally.spawns, 2);
    // Outside live play nothing counts.
    observer.message(&session, &event(round_end(None, None)));
    assert!(observer.finished() && !observer.live());
    observer.message(
        &session,
        &event(GameEvent::Frag {
            killer: "A".into(),
            victim: "B".into(),
            killer_score: 2,
            killer_id: Some(a),
            victim_id: Some(b),
            weapon: Some(WeaponType::Rail),
            killer_team: None,
            victim_team: None,
        }),
    );
    assert_eq!(observer.tally().frags, 1);
}

#[test]
fn sabotage_rounds_are_read_by_the_attack_and_the_deciding_round_ends_the_match() {
    let session = arcade(MapKind::Sector9, GameMode::Sabotage, None, 0);
    let mut observer = Observer::new(&session);
    let sabotage = |kind| {
        event(GameEvent::Sabotage {
            kind,
            player: None,
            player_id: None,
            site: None,
            score: TeamScores::default(),
        })
    };
    let result = |reason, match_over| SabotageResult {
        reason,
        round: 1,
        score: TeamScores::default(),
        sides_swap: false,
        match_over,
        match_winner: None,
    };
    observer.message(&session, &event(round_start()));
    assert!(!observer.live(), "the muster is not live play");
    observer.message(&session, &sabotage(SabotageEventKind::Live));
    assert!(observer.live());
    observer.message(&session, &sabotage(SabotageEventKind::Planted));
    observer.message(
        &session,
        &event(round_end(
            Some(Team::Coalition),
            Some(result(SabotageReason::Detonation, false)),
        )),
    );
    assert!(!observer.finished() && !observer.live());
    observer.message(&session, &event(round_start()));
    observer.message(&session, &sabotage(SabotageEventKind::Live));
    observer.message(
        &session,
        &event(round_end(
            Some(Team::Union),
            Some(result(SabotageReason::Defused, true)),
        )),
    );
    assert!(observer.finished());
    let tally = &observer.tally().sabotage;
    assert_eq!(
        (
            tally.rounds,
            tally.attack_wins,
            tally.defence_wins,
            tally.plants
        ),
        (2, 1, 1, 1)
    );
    assert_eq!((tally.by_detonation, tally.by_defuse), (1, 1));
    assert_eq!(tally.matches_decided, 1);
    assert_eq!(observer.tally().rounds, 2);
}

#[test]
fn conquest_counts_flips_and_the_sites_and_tickets_at_the_whistle() {
    let mut session = arcade(MapKind::HoldfastAtoll, GameMode::Conquest, None, 0);
    session.state.start_round();
    assert!(session.state.conquest.is_some(), "Holdfast hosts Conquest");
    let mut observer = Observer::new(&session);
    observer.message(&session, &event(round_start()));
    observer.begin_tick(&session);
    if let Some(conquest) = session.state.conquest.as_mut() {
        conquest.points[0].owner = Some(Team::Union);
        conquest.points[1].owner = Some(Team::Coalition);
        conquest.tickets = TeamScores {
            union: 40,
            coalition: 0,
        };
    }
    observer.begin_tick(&session);
    observer.message(&session, &event(round_end(Some(Team::Union), None)));
    let tally = &observer.tally().conquest;
    assert_eq!(tally.site_flips, 2);
    assert_eq!((tally.union_wins, tally.coalition_wins), (1, 0));
    assert_eq!(
        (tally.union_sites_at_end, tally.coalition_sites_at_end),
        (1, 1)
    );
    assert_eq!(
        (tally.union_tickets_left, tally.coalition_tickets_left),
        (40, 0)
    );
    assert!(observer.finished());
}

#[test]
fn a_host_recorder_files_each_match_once_and_an_unplayed_one_never() {
    let dir = std::env::temp_dir().join(format!(
        "localexception-fun-host-{}-{}",
        std::process::id(),
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos()
    ));
    let now = std::time::SystemTime::now();
    let mut recorder = HostRecorder::start(FunStore::open(&dir).unwrap(), now);
    let mut session = arcade(MapKind::ArenaDuel, GameMode::Ffa, Some(2), 4);
    for _ in 0..20 * 120 {
        let messages = session.tick_messages(0.05);
        recorder.observe(&session, &messages);
        recorder.tick_took(std::time::Duration::from_micros(400));
        recorder.after_tick(now);
        if recorder.filed() == 1 {
            break;
        }
    }
    assert_eq!(recorder.filed(), 1, "the frag limit ended one match");
    // The podium that follows is not played, so stopping files nothing more.
    for _ in 0..5 {
        let messages = session.tick_messages(0.05);
        recorder.observe(&session, &messages);
        recorder.after_tick(now);
    }
    recorder.finish(now);
    let (records, refused) = FunStore::read_all(&dir).unwrap();
    assert!(refused.is_empty(), "{refused:?}");
    assert_eq!(records.len(), 1);
    let record = &records[0];
    assert!(record.finished && record.tally.frags >= 2);
    let health = record.tick_health.as_ref().expect("the run loop timed it");
    assert!(health.ticks > 0 && health.over_budget == 0);
    assert!((300..=500).contains(&health.p50_us), "{health:?}");
    std::fs::remove_dir_all(dir).unwrap();
}
