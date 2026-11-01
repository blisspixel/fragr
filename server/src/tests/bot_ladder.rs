//! The rule bots' difficulty ladder through the production session: a host's
//! rung reaches every bot, and a higher rung out-fights a lower one in a
//! seeded Duel whichever seat it takes.
use crate::protocol::GameMode;
use crate::rules::RuleSet;
use crate::session::GameSession;
use crate::sim::{BotSkill, MapKind, MatchConfig};

fn duel(map: MapKind, seed: u64, seconds: u32) -> GameSession {
    let mut session = GameSession::with_map(map, false);
    session.state.use_replay_ids();
    session.state.seed(seed);
    session.state.apply_config(MatchConfig {
        frag_limit: None,
        capture_limit: None,
        time_limit_ticks: Some(seconds * 20),
        boss_spawn_ticks: None,
        compliance_ping_ticks: None,
        rules: RuleSet::new(GameMode::Duel, &[], false).unwrap(),
        ..MatchConfig::default()
    });
    session
}

#[test]
fn a_hosts_rung_reaches_every_rule_bot_present_and_future() {
    let mut session = duel(MapKind::ArenaDuel, 1, 30);
    session.state.config.rules = RuleSet::new(GameMode::Ffa, &[], false).unwrap();
    assert_eq!(session.bot_skill(), BotSkill::Regular);
    session.spawn_bots(3);
    assert!(session
        .bots
        .iter()
        .all(|bot| bot.skill == BotSkill::Regular));
    session.set_bot_skill(BotSkill::Headliner);
    assert_eq!(session.bot_skill(), BotSkill::Headliner);
    assert!(session
        .bots
        .iter()
        .all(|bot| bot.skill == BotSkill::Headliner));
    assert!(session
        .state
        .bots
        .iter()
        .all(|bot| bot.skill == BotSkill::Headliner));
    session.spawn_bots(1);
    assert_eq!(session.bots.len(), 4);
    assert!(session
        .bots
        .iter()
        .all(|bot| bot.skill == BotSkill::Headliner));
    let first = session.bots[0].player_id;
    assert!(session.set_bot_skill_for(first, BotSkill::Tourist));
    assert_eq!(session.bots[0].skill, BotSkill::Tourist);
    assert_eq!(
        session
            .state
            .bots
            .iter()
            .find(|bot| bot.player_id == first)
            .map(|bot| bot.skill),
        Some(BotSkill::Tourist)
    );
    assert!(!session.set_bot_skill_for(uuid::Uuid::from_u128(u128::MAX), BotSkill::NoCrumbs));
}

#[test]
fn the_top_rung_outfights_the_bottom_rung_from_either_seat() {
    let mut book = [0u32; 2];
    for seed in [3, 4] {
        for swapped in [false, true] {
            let mut session = duel(MapKind::ArenaDuel, seed, 120);
            session.spawn_bots(2);
            let ids: Vec<uuid::Uuid> = session.bots.iter().map(|bot| bot.player_id).collect();
            let (top, bottom) = if swapped {
                (ids[1], ids[0])
            } else {
                (ids[0], ids[1])
            };
            assert!(session.set_bot_skill_for(top, BotSkill::NoCrumbs));
            assert!(session.set_bot_skill_for(bottom, BotSkill::Tourist));
            // Read the book when the round ends, before any next round.
            'round: while session.state.tick < 20 * 160 {
                for message in session.tick_messages(0.05) {
                    if matches!(
                        message,
                        crate::protocol::ServerMessage::Event(
                            crate::protocol::GameEvent::RoundEnd { .. }
                        )
                    ) && session.state.tick > 20 * 10
                    {
                        break 'round;
                    }
                }
            }
            let score = |id| session.state.scores.get(&id).copied().unwrap_or(0);
            book[0] += score(top);
            book[1] += score(bottom);
        }
    }
    assert!(
        book[0] >= 4 && book[0] > book[1] * 2,
        "no crumbs {} to tourist {} over four Duels",
        book[0],
        book[1]
    );
}
