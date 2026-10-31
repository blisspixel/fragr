//! Rule bots hunting a quiet round and taking the jeeps (#517). Whole seeded
//! rounds on the authoritative session, the way the bot survey plays them.
use crate::protocol::{GameMode, Role, VehicleSeat};
use crate::rules::RuleSet;
use crate::session::GameSession;
use crate::sim::{MapKind, MatchConfig};

fn round(map: MapKind, mode: GameMode, bots: usize, seed: u64, seconds: u32) -> GameSession {
    let mut session = GameSession::with_map(map, false);
    session.state.use_replay_ids();
    session.state.seed(seed);
    session.state.apply_config(MatchConfig {
        frag_limit: None,
        capture_limit: None,
        time_limit_ticks: Some(seconds * 20),
        boss_spawn_ticks: None,
        compliance_ping_ticks: None,
        rules: RuleSet::new(mode, &[], false).unwrap(),
        ..MatchConfig::default()
    });
    session.spawn_bots(bots);
    session
}

/// Ticks until the first damaging hit between fighters, if any.
fn first_hit(session: &mut GameSession, ticks: u64) -> Option<u64> {
    let mut hp: Vec<(uuid::Uuid, i32)> = Vec::new();
    for _ in 0..ticks {
        session.tick_messages(0.05);
        let now: Vec<(uuid::Uuid, i32)> = session
            .state
            .players
            .iter()
            .filter(|player| player.role != Role::Spectator && player.respawn_timer.is_none())
            .map(|player| (player.id, player.hp))
            .collect();
        let hurt = now.iter().any(|(id, after)| {
            hp.iter()
                .any(|(before_id, before)| before_id == id && after < before)
        });
        if hurt {
            return Some(session.state.tick);
        }
        hp = now;
    }
    None
}

/// The wave 19 survey: two Duel bots on Sector 9 fired no shot in twenty
/// minutes, each walking its own pad circuit in its own hall. Hunting a quiet
/// round (sound, patrol of the middle and the power pads, glances either
/// side) brings them together inside one round on most seeds.
#[test]
fn duel_bots_on_sector_9_find_each_other() {
    let found = (1..=4).filter_map(|seed| {
        let mut session = round(MapKind::Sector9, GameMode::Duel, 2, seed, 150);
        first_hit(&mut session, 20 * 160)
    });
    assert!(
        found.count() >= 2,
        "two Duel bots should trade shots on Sector 9 in at least two of four rounds"
    );
}

/// Conquest bots ordered to a far site take an empty jeep, drive it, and
/// give the seat back: nobody stays parked in one, and no bot ever sits in
/// a gunner seat it was never offered.
#[test]
fn conquest_bots_drive_jeeps_toward_sites_and_get_out() {
    let mut session = round(MapKind::HoldfastAtoll, GameMode::Conquest, 16, 1, 150);
    let mut driven = std::collections::HashSet::new();
    let mut seated_ticks: std::collections::HashMap<uuid::Uuid, u64> = Default::default();
    let mut released = 0;
    for _ in 0..20 * 120 {
        session.tick_messages(0.05);
        let state = &session.state;
        for jeep in &state.vehicles {
            assert!(
                jeep.state.gunner.is_none(),
                "a rule bot only ever takes an empty jeep's wheel"
            );
        }
        let seated: Vec<uuid::Uuid> = state
            .players
            .iter()
            .filter(|player| {
                matches!(
                    state.vehicle_seat(player.id),
                    Some((_, VehicleSeat::Driver))
                )
            })
            .map(|player| player.id)
            .collect();
        for id in &seated {
            driven.insert(*id);
            *seated_ticks.entry(*id).or_default() += 1;
        }
        let before = seated_ticks.len();
        seated_ticks.retain(|id, _| seated.contains(id));
        released += before - seated_ticks.len();
        for (id, ticks) in &seated_ticks {
            if *ticks >= 20 * 60 {
                let (index, _) = state.vehicle_seat(*id).unwrap();
                let jeep = &state.vehicles[index].state;
                panic!(
                    "a driver gets out within a minute: tick {} jeep at {:?}, speed {}",
                    state.tick, jeep.position, jeep.speed
                );
            }
        }
    }
    assert!(!driven.is_empty(), "somebody drove");
    assert!(released > 0, "and gave the seat back");
}
