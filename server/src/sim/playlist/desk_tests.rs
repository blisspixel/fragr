use super::*;
use crate::desk::DeskVerb;
use crate::net::GameCommand;
use crate::protocol::{BodyKind, Role, SabotageReason, SabotageResult, ServerMessage, TeamScores};
use crate::session::GameSession;
use uuid::Uuid;

#[test]
fn a_queued_show_waits_and_an_invalid_replacement_keeps_it() {
    let mut state = GameState::new();
    state.start_round();
    state
        .queue_show(MapKind::Sector9, GameMode::Sabotage)
        .unwrap();
    assert!(state
        .queue_show(MapKind::ComplianceYard, GameMode::Ctf)
        .is_err());
    assert!(state
        .queue_show(MapKind::ArenaDuel, GameMode::Conquest)
        .is_err());
    assert!(state.queue_next_show().is_err());
    for _ in 0..10 {
        state.tick(0.05);
    }
    assert_eq!(state.map, MapKind::ArenaDuel);
    assert!(state
        .desk_shows()
        .contains("Queued: Sector 9 Transit Hall / Sabotage"));
    state.end_round("test".into());
    state.start_round();
    assert_eq!(state.map, MapKind::Sector9);
    assert_eq!(state.config.rules.mode(), GameMode::Sabotage);
    assert!(!state.playlist && !state.map_rotate);
    assert!(state.queued_show.is_none());
}

#[test]
fn next_cancels_a_manual_choice_and_keeps_the_night_order() {
    let mut state = GameState::new();
    state.arm_night_playlist();
    state.start_round();
    state
        .queue_show(MapKind::HoldfastAtoll, GameMode::Conquest)
        .unwrap();
    let answer = state.queue_next_show().unwrap();
    assert!(answer.contains("Compliance Yard"));
    assert!(state.queued_show.is_none());
    state.end_round("test".into());
    state.start_round();
    assert_eq!(state.map, MapKind::ComplianceYard);
    assert!(state.playlist);
    assert!(state
        .desk_shows()
        .contains("2 Compliance Yard / Free-for-all (live)"));
}

#[test]
fn a_manual_choice_replaces_an_earlier_choice_and_then_repeats() {
    let mut state = GameState::with_map(MapKind::ArenaDuel, true);
    state.config.warmup_ticks = 9;
    state.config.end_delay_ticks = 7;
    state.start_round();
    state.queue_show(MapKind::Sector9, GameMode::Ctf).unwrap();
    state
        .queue_show(MapKind::HoldfastAtoll, GameMode::Conquest)
        .unwrap();
    for _ in 0..2 {
        state.end_round("test".into());
        state.start_round();
        assert_eq!(state.map, MapKind::HoldfastAtoll);
        assert_eq!(state.config.rules.mode(), GameMode::Conquest);
        assert_eq!(state.config.time_limit_ticks, Some(12_000));
        assert_eq!(state.config.warmup_ticks, 9);
        assert_eq!(state.config.end_delay_ticks, 7);
        assert_eq!(state.vehicles.len(), 6);
    }
    assert!(!state.map_rotate && !state.playlist);
}

#[test]
fn a_manual_show_waits_through_sabotage_rounds_and_the_side_swap() {
    let mut state = GameState::with_map(MapKind::Sector9, false);
    state.apply_config(slot_config(GameMode::Sabotage, 0, 0));
    state.start_round();
    state.queue_show(MapKind::ArenaDuel, GameMode::Tdm).unwrap();
    let half = state.config.sabotage.format.half_rounds();
    for round in 1..=half {
        state.end_round("test".into());
        state.sabotage.as_mut().unwrap().result = Some(SabotageResult {
            reason: SabotageReason::Time,
            round,
            score: TeamScores::default(),
            sides_swap: round == half,
            match_over: false,
            match_winner: None,
        });
        state.start_round();
        assert_eq!(state.map, MapKind::Sector9);
        assert_eq!(state.config.rules.mode(), GameMode::Sabotage);
        assert!(state.queued_show.is_some());
    }
    state.end_round("test".into());
    state.sabotage.as_mut().unwrap().result = Some(SabotageResult {
        reason: SabotageReason::Time,
        round: half + 1,
        score: TeamScores::default(),
        sides_swap: false,
        match_over: true,
        match_winner: None,
    });
    state.start_round();
    assert_eq!(state.map, MapKind::ArenaDuel);
    assert_eq!(state.config.rules.mode(), GameMode::Tdm);
}

#[test]
fn changing_show_keeps_sockets_and_sequences_and_sends_the_new_map_first() {
    let mut session = GameSession::with_map(MapKind::ArenaDuel, false);
    session.state.config.end_delay_ticks = 1;
    session.state.config.warmup_ticks = 0;
    session.state.start_round();
    let mut roster = Vec::new();
    for role in [Role::Human, Role::Agent] {
        let client = Uuid::new_v4();
        let player = Uuid::new_v4();
        session.apply_command(GameCommand::Connected {
            id: client,
            role,
            name: format!("{role:?}"),
            player_id: Some(player),
            body: BodyKind::Human,
        });
        roster.push((client, player));
    }
    session.state.arm_joined_magazines(roster[0].1);
    session.tick_messages(0.05);
    let old_revision = session.state.players[0].inventory.revision();
    session.state.players[0].last_input_seq = Some(77);
    let old_tick = session.state.tick;
    assert!(session
        .desk(DeskVerb::Map {
            map: MapKind::ArenaDuel,
            mode: GameMode::Tdm
        })
        .text()
        .contains("Next show"));
    session.state.end_round("test".into());
    let messages = session.tick_messages(0.05);
    assert!(matches!(
        messages.first(),
        Some(ServerMessage::MapInfo { .. })
    ));
    assert!(
        matches!(messages.first(), Some(ServerMessage::MapInfo { rules: Some(rules), .. }) if rules.mode == GameMode::Tdm)
    );
    assert!(session.state.tick > old_tick);
    for (client, player) in roster {
        assert_eq!(session.client_to_player.get(&client), Some(&player));
        assert!(session.state.players.iter().any(|p| p.id == player));
    }
    let player = &session.state.players[0];
    assert_eq!(player.last_input_seq, Some(77));
    assert!(player.inventory.revision() > old_revision);
    assert!(player.inventory.armed());
    assert!(player.team.is_some());
}

#[test]
fn the_same_map_still_clears_devices_and_a_previous_restriction() {
    let mut state = GameState::new();
    state.config.rules =
        crate::rules::RuleSet::new(GameMode::Tdm, &[crate::protocol::Mutator::RailOnly], false)
            .unwrap();
    state.start_round();
    let id = Uuid::new_v4();
    state.add_player(id, "Proxy".into(), Role::Human);
    state.test_insert_grenade(id);
    state.test_insert_mine(id);
    let old_revision = state.players[0].inventory.revision();
    state.queue_show(MapKind::ArenaDuel, GameMode::Ffa).unwrap();
    state.end_round("test".into());
    state.start_round();
    assert!(state.snapshot().grenades.is_empty() && state.snapshot().mines.is_empty());
    let player = &state.players[0];
    assert!(player.team.is_none());
    assert_eq!(player.inventory.only(), None);
    assert!(player.inventory.revision() > old_revision);
}

#[test]
fn authored_and_calibration_sessions_cannot_queue_an_arcade_show() {
    let map = crate::maps::AuthoredSource::Mission(crate::protocol::MissionId::RecallNotice)
        .load()
        .unwrap();
    let mut state = GameState::with_authored_map(map);
    assert!(state.queue_show(MapKind::ArenaDuel, GameMode::Ffa).is_err());
    let mut state = GameState::new();
    state.solo_broadcast.enabled = true;
    assert!(state.queue_show(MapKind::ArenaDuel, GameMode::Ffa).is_err());
}
