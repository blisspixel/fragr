//! The rule bots' difficulty ladder, measured: seeded Duels between every
//! pair of rungs on the duel floor, the yard and the river, each seed played
//! twice with the seats swapped so a callsign's personality never decides the
//! book. A higher rung should take 65 to 80 percent of its Duels against the
//! rung below (`docs/plans/fun-craft-targets.md`, bots), and no rung should
//! walk back and forth undecided for more than one moving window in twenty.
//! Behaviour evidence for rule bots, never a human "felt fair" verdict.
use crate::sight::{spread, DitherTracker, Spread};
use fragr_server::protocol::GameMode;
use fragr_server::rules::RuleSet;
use fragr_server::session::GameSession;
use fragr_server::sim::{BotSkill, MapKind, MatchConfig};
use serde::{Deserialize, Serialize};

/// Each rung beats the one below this often, as a share of decided Duels.
pub const STEP_SHARE: (f64, f64) = (0.65, 0.80);
/// Dithering windows per moving window, at most.
pub const DITHER_SHARE: f64 = 0.05;

#[derive(Debug, Clone)]
pub struct LadderConfig {
    pub maps: Vec<MapKind>,
    pub seeds: Vec<u64>,
    /// Live Duel length, ticks.
    pub round_ticks: u32,
    /// Rungs to pit against each other, lowest first.
    pub rungs: Vec<BotSkill>,
}

impl Default for LadderConfig {
    fn default() -> Self {
        Self {
            maps: vec![
                MapKind::ArenaDuel,
                MapKind::ComplianceYard,
                MapKind::LowWater,
            ],
            seeds: (1..13).collect(),
            round_ticks: 20 * 120,
            rungs: BotSkill::ALL.to_vec(),
        }
    }
}

/// One pairing of rungs over every map, seed and seat order.
#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq)]
pub struct PairRecord {
    pub higher: String,
    pub lower: String,
    pub duels: u32,
    pub higher_wins: u32,
    pub lower_wins: u32,
    pub level: u32,
    /// Higher rung wins plus half the level Duels, per Duel.
    pub higher_share: f64,
    pub higher_frags: u32,
    pub lower_frags: u32,
}

/// One rung's own numbers across every Duel it played.
#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq)]
pub struct RungRecord {
    pub rung: String,
    pub duels: u32,
    pub frags_per_minute: f64,
    pub moving_windows: u64,
    pub dither_windows: u64,
    pub dither_share: f64,
    /// Seconds from a sighting of an opponent to this rung's first hit on
    /// it, for sightings that led to one inside three seconds.
    pub sight_to_hit_s: Spread,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq)]
pub struct LadderReport {
    pub maps: Vec<String>,
    pub seeds: Vec<u64>,
    pub round_seconds: f64,
    pub pairs: Vec<PairRecord>,
    pub rungs: Vec<RungRecord>,
}

#[derive(Default)]
struct RungTally {
    duels: u32,
    frags: u32,
    live_ticks: u64,
    dither: DitherTracker,
    sight_to_hit: Vec<f64>,
}

struct Duel {
    frags: [u32; 2],
}

/// Play one Duel of `skills[0]` against `skills[1]`, seats in that order.
fn duel(
    map: MapKind,
    seed: u64,
    round_ticks: u32,
    skills: [BotSkill; 2],
    tallies: &mut [RungTally; 2],
) -> Option<Duel> {
    let mut session = GameSession::with_map(map, false);
    session.state.use_replay_ids();
    session.state.seed(seed);
    let rules = RuleSet::new(GameMode::Duel, &[], false).ok()?;
    session.state.apply_config(MatchConfig {
        frag_limit: None,
        capture_limit: None,
        time_limit_ticks: Some(round_ticks),
        boss_spawn_ticks: None,
        compliance_ping_ticks: None,
        rules,
        ..MatchConfig::default()
    });
    session.spawn_bots(2);
    let ids: Vec<uuid::Uuid> = session.bots.iter().map(|bot| bot.player_id).collect();
    if ids.len() != 2 {
        return None;
    }
    for (id, skill) in ids.iter().zip(skills) {
        session.set_bot_skill_for(*id, skill);
    }
    let solids = map.solids();
    let limit = u64::from(round_ticks) + 20 * 30;
    let mut live = false;
    // Per seat: the tick it first saw the other in the current sighting.
    let mut sighted: [Option<u64>; 2] = [None, None];
    let mut dither = [DitherTracker::default(), DitherTracker::default()];
    while session.state.tick < limit {
        let mut ended = false;
        for message in session.tick_messages(0.05) {
            use fragr_server::protocol::{GameEvent, ServerMessage};
            match message {
                ServerMessage::Event(GameEvent::RoundStart { .. }) => live = true,
                ServerMessage::Event(GameEvent::RoundEnd { .. }) if live => ended = true,
                ServerMessage::Event(GameEvent::Hit {
                    shooter_id,
                    target_id,
                    ..
                }) if live && shooter_id != target_id => {
                    if let Some(seat) = ids.iter().position(|id| *id == shooter_id) {
                        if let Some(at) = sighted[seat].take() {
                            let seconds = session.state.tick.saturating_sub(at) as f64 / 20.0;
                            if seconds <= 3.0 {
                                tallies[seat].sight_to_hit.push(seconds);
                            }
                        }
                    }
                }
                _ => {}
            }
        }
        if ended {
            break;
        }
        if !live {
            continue;
        }
        for (seat, id) in ids.iter().enumerate() {
            tallies[seat].live_ticks += 1;
            let me = session.state.players.iter().find(|p| p.id == *id);
            let other = session.state.players.iter().find(|p| p.id == ids[1 - seat]);
            let looking = me.zip(other).is_some_and(|(me, other)| {
                me.hp > 0
                    && other.hp > 0
                    && me.respawn_timer.is_none()
                    && other.respawn_timer.is_none()
                    && crate::sight::sees(&solids, me, other, skills[seat].sight_metres())
            });
            match (looking, sighted[seat]) {
                (true, None) => sighted[seat] = Some(session.state.tick),
                (false, Some(_)) => sighted[seat] = None,
                _ => {}
            }
        }
        for (seat, tracker) in dither.iter_mut().enumerate() {
            tracker.observe_one(&session, &solids, ids[seat]);
        }
    }
    let frags = [0, 1].map(|seat| session.state.scores.get(&ids[seat]).copied().unwrap_or(0));
    for seat in 0..2 {
        tallies[seat].duels += 1;
        tallies[seat].frags += frags[seat];
        tallies[seat].dither.moving += dither[seat].moving;
        tallies[seat].dither.dithers += dither[seat].dithers;
    }
    Some(Duel { frags })
}

/// Every pairing of the configured rungs, higher rung first.
pub fn run_ladder(config: &LadderConfig) -> LadderReport {
    let mut pairings = Vec::new();
    for (low_index, low) in config.rungs.iter().enumerate() {
        for high in &config.rungs[low_index + 1..] {
            pairings.push((*high, *low));
        }
    }
    let results: Vec<(PairRecord, [RungTally; 2])> = std::thread::scope(|scope| {
        let handles: Vec<_> = pairings
            .iter()
            .map(|&(high, low)| {
                scope.spawn(move || {
                    let mut tallies = [RungTally::default(), RungTally::default()];
                    let mut record = PairRecord {
                        higher: high.id().to_string(),
                        lower: low.id().to_string(),
                        ..PairRecord::default()
                    };
                    for &map in &config.maps {
                        for &seed in &config.seeds {
                            for swapped in [false, true] {
                                let (skills, seat_of_high) = if swapped {
                                    ([low, high], 1)
                                } else {
                                    ([high, low], 0)
                                };
                                let mut seat_tallies = [RungTally::default(), RungTally::default()];
                                let Some(result) =
                                    duel(map, seed, config.round_ticks, skills, &mut seat_tallies)
                                else {
                                    continue;
                                };
                                let [a, b] = seat_tallies;
                                let (high_tally, low_tally) = if swapped { (b, a) } else { (a, b) };
                                for (into, from) in tallies.iter_mut().zip([high_tally, low_tally])
                                {
                                    into.duels += from.duels;
                                    into.frags += from.frags;
                                    into.live_ticks += from.live_ticks;
                                    into.dither.moving += from.dither.moving;
                                    into.dither.dithers += from.dither.dithers;
                                    into.sight_to_hit.extend(from.sight_to_hit);
                                }
                                let high_frags = result.frags[seat_of_high];
                                let low_frags = result.frags[1 - seat_of_high];
                                record.duels += 1;
                                record.higher_frags += high_frags;
                                record.lower_frags += low_frags;
                                match high_frags.cmp(&low_frags) {
                                    std::cmp::Ordering::Greater => record.higher_wins += 1,
                                    std::cmp::Ordering::Less => record.lower_wins += 1,
                                    std::cmp::Ordering::Equal => record.level += 1,
                                }
                            }
                        }
                    }
                    record.higher_share = if record.duels == 0 {
                        0.0
                    } else {
                        (f64::from(record.higher_wins) + f64::from(record.level) / 2.0)
                            / f64::from(record.duels)
                    };
                    (record, tallies)
                })
            })
            .collect();
        handles
            .into_iter()
            .map(|handle| handle.join().expect("a ladder pairing panicked"))
            .collect()
    });
    let mut rungs: Vec<(BotSkill, RungTally)> = config
        .rungs
        .iter()
        .map(|rung| (*rung, RungTally::default()))
        .collect();
    let mut pairs = Vec::new();
    for ((high, low), (record, [high_tally, low_tally])) in pairings.iter().zip(results) {
        pairs.push(record);
        for (rung, tally) in [(*high, high_tally), (*low, low_tally)] {
            if let Some((_, into)) = rungs.iter_mut().find(|(skill, _)| *skill == rung) {
                into.duels += tally.duels;
                into.frags += tally.frags;
                into.live_ticks += tally.live_ticks;
                into.dither.moving += tally.dither.moving;
                into.dither.dithers += tally.dither.dithers;
                into.sight_to_hit.extend(tally.sight_to_hit);
            }
        }
    }
    LadderReport {
        maps: config
            .maps
            .iter()
            .map(|map| map.name().to_string())
            .collect(),
        seeds: config.seeds.clone(),
        round_seconds: f64::from(config.round_ticks) / 20.0,
        pairs,
        rungs: rungs
            .into_iter()
            .map(|(rung, tally)| RungRecord {
                rung: rung.id().to_string(),
                duels: tally.duels,
                frags_per_minute: if tally.live_ticks == 0 {
                    0.0
                } else {
                    f64::from(tally.frags) / (tally.live_ticks as f64 / 20.0 / 60.0)
                },
                moving_windows: tally.dither.moving,
                dither_windows: tally.dither.dithers,
                dither_share: tally.dither.share(),
                sight_to_hit_s: spread(&tally.sight_to_hit),
            })
            .collect(),
    }
}

/// The adjacent pairings outside the step band, rungs that dither, and a
/// ladder whose win share against the median rung is not monotonic.
pub fn check_ladder(report: &LadderReport) -> Vec<String> {
    let mut misses = Vec::new();
    let order: Vec<&str> = BotSkill::ALL.iter().map(|skill| skill.id()).collect();
    let rank = |id: &str| order.iter().position(|rung| *rung == id);
    for pair in &report.pairs {
        let adjacent = rank(&pair.higher)
            .zip(rank(&pair.lower))
            .is_some_and(|(high, low)| high == low + 1);
        if adjacent && !(STEP_SHARE.0..=STEP_SHARE.1).contains(&pair.higher_share) {
            misses.push(format!(
                "{} over {}: {:.0} percent of {} Duels, want {:.0} to {:.0}",
                pair.higher,
                pair.lower,
                pair.higher_share * 100.0,
                pair.duels,
                STEP_SHARE.0 * 100.0,
                STEP_SHARE.1 * 100.0
            ));
        }
        if !adjacent && pair.higher_share < 0.5 {
            misses.push(format!(
                "{} over {}: {:.0} percent, a higher rung must not lose the book",
                pair.higher,
                pair.lower,
                pair.higher_share * 100.0
            ));
        }
    }
    for rung in &report.rungs {
        if rung.dither_share >= DITHER_SHARE {
            misses.push(format!(
                "{}: dithers in {:.1} percent of moving windows, want under {:.0}",
                rung.rung,
                rung.dither_share * 100.0,
                DITHER_SHARE * 100.0
            ));
        }
    }
    misses
}

#[cfg(test)]
mod tests {
    use super::*;

    fn pair(higher: &str, lower: &str, share: f64) -> PairRecord {
        PairRecord {
            higher: higher.into(),
            lower: lower.into(),
            duels: 10,
            higher_share: share,
            ..PairRecord::default()
        }
    }

    #[test]
    fn the_check_reads_adjacent_steps_skips_and_dither() {
        let mut report = LadderReport {
            pairs: vec![
                pair("walk-in", "tourist", 0.7),
                pair("regular", "walk-in", 0.9),
                pair("regular", "tourist", 0.4),
            ],
            rungs: vec![RungRecord {
                rung: "regular".into(),
                dither_share: 0.06,
                ..RungRecord::default()
            }],
            ..LadderReport::default()
        };
        let misses = check_ladder(&report);
        assert_eq!(misses.len(), 3, "{misses:?}");
        assert!(misses[0].contains("regular over walk-in"));
        assert!(misses[1].contains("must not lose"));
        assert!(misses[2].contains("dithers"));
        report.pairs.truncate(1);
        report.rungs.clear();
        assert!(check_ladder(&report).is_empty());
    }

    #[test]
    fn a_short_ladder_plays_both_seats_and_tallies_every_rung() {
        let report = run_ladder(&LadderConfig {
            maps: vec![MapKind::ArenaDuel],
            seeds: vec![1],
            round_ticks: 20 * 20,
            rungs: vec![BotSkill::Tourist, BotSkill::NoCrumbs],
        });
        assert_eq!(report.pairs.len(), 1);
        let pair = &report.pairs[0];
        assert_eq!(
            (pair.higher.as_str(), pair.lower.as_str()),
            ("no-crumbs", "tourist")
        );
        assert_eq!(pair.duels, 2);
        assert_eq!(pair.higher_wins + pair.lower_wins + pair.level, 2);
        assert_eq!(report.rungs.len(), 2);
        assert!(report.rungs.iter().all(|rung| rung.duels == 2));
    }
}
