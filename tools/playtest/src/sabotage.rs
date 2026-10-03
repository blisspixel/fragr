//! Seeded bots-only Sabotage survey: whole matches of rule bots on the
//! authoritative session, no sockets, as fast as the machine runs them. It
//! measures whether the round loop works for both sides (plants, defuses,
//! detonations, eliminations and clock wins) and whether any round sticks.
//! A survey is objective-loop evidence, never a human fun verdict.
use fragr_server::protocol::{
    GameEvent, GameMode, SabotageEventKind, SabotageFormat, SabotageReason, ServerMessage, Team,
};
use fragr_server::rules::{RuleSet, SabotageConfig};
use fragr_server::session::GameSession;
use fragr_server::sim::{MapKind, MatchConfig};
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;

/// What to survey.
#[derive(Debug, Clone)]
pub struct SurveyConfig {
    pub seeds: Vec<u64>,
    /// Rule bots in the match; they split evenly between the sides.
    pub bots: usize,
    pub format: SabotageFormat,
    /// Hard stop per match, in ticks, so a stuck match fails rather than hangs.
    pub max_ticks: u64,
}

impl Default for SurveyConfig {
    fn default() -> Self {
        Self {
            seeds: (40..56).collect(),
            bots: 8,
            format: SabotageFormat::Short,
            max_ticks: 20 * 60 * 40,
        }
    }
}

/// One decided round.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct RoundRecord {
    pub seed: u64,
    pub round: u32,
    pub winner: Option<Team>,
    pub reason: SabotageReason,
    /// The round's length from the bell, seconds.
    pub seconds: f64,
    pub planted: bool,
    pub frags: u32,
}

/// One match per seed.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct MatchRecord {
    pub seed: u64,
    pub rounds: u32,
    pub finished: bool,
    /// The uniform that won, absent for a draw or an unfinished match.
    pub winner: Option<Team>,
    pub seconds: f64,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq)]
pub struct SurveyReport {
    pub matches: Vec<MatchRecord>,
    pub rounds: Vec<RoundRecord>,
    pub plants_started: u32,
    pub plants: u32,
    pub plants_interrupted: u32,
    pub defuses_started: u32,
    pub defuses: u32,
    pub detonations: u32,
    pub charge_drops: u32,
    pub charge_pickups: u32,
    pub swaps: u32,
    /// Round wins by side and by reason, as "side:reason".
    pub wins: BTreeMap<String, u32>,
    /// Deaths by the victim's side and the callout where they fell, as "side:callout".
    pub deaths: BTreeMap<String, u32>,
    /// Charge drops by the callout where the charge fell.
    pub drop_callouts: BTreeMap<String, u32>,
    /// Deaths by side on a 10 metre grid, as "side:x,z" of the cell's centre.
    pub death_grid: BTreeMap<String, u32>,
    /// Fighters without a usable gun when weapons went live, by side.
    pub unarmed_at_live: BTreeMap<String, u32>,
    pub attacker_round_share: f64,
    pub mean_round_seconds: f64,
    pub longest_round_seconds: f64,
}

fn reason_id(reason: SabotageReason) -> &'static str {
    reason.id()
}

/// Run every seed and fold the facts into one report.
pub fn run_survey(config: &SurveyConfig) -> SurveyReport {
    let mut report = SurveyReport::default();
    for &seed in &config.seeds {
        survey_seed(config, seed, &mut report);
    }
    let attacker = report
        .rounds
        .iter()
        .filter(|r| r.winner == Some(Team::Coalition))
        .count();
    let total = report.rounds.len().max(1);
    report.attacker_round_share = attacker as f64 / total as f64;
    report.mean_round_seconds = report.rounds.iter().map(|r| r.seconds).sum::<f64>() / total as f64;
    report.longest_round_seconds = report.rounds.iter().map(|r| r.seconds).fold(0.0, f64::max);
    report
}

fn survey_seed(config: &SurveyConfig, seed: u64, report: &mut SurveyReport) {
    let mut session = GameSession::with_map(MapKind::Sector9, false);
    session.state.seed(seed);
    session.state.apply_config(MatchConfig {
        frag_limit: None,
        time_limit_ticks: None,
        boss_spawn_ticks: None,
        compliance_ping_ticks: None,
        rules: RuleSet::new(GameMode::Sabotage, &[], false).expect("plain sabotage rules"),
        sabotage: SabotageConfig {
            format: config.format,
            ..SabotageConfig::default()
        },
        ..MatchConfig::default()
    });
    session.spawn_bots(config.bots);
    let layout = MapKind::Sector9
        .sabotage_map()
        .expect("Sector 9 has a Sabotage layout");
    let callout = |x: f32, z: f32| layout.callout_at(x, z).unwrap_or("outside").to_string();
    let mut round_started: Option<u64> = None;
    let mut planted = false;
    let mut frags = 0;
    let mut rounds = 0;
    let mut finished = None;
    while session.state.tick < config.max_ticks {
        for message in session.tick_messages(0.05) {
            let ServerMessage::Event(event) = message else {
                continue;
            };
            match event {
                GameEvent::RoundStart { .. } => {
                    round_started = Some(session.state.tick);
                    planted = false;
                    frags = 0;
                }
                GameEvent::Frag {
                    ref victim,
                    victim_team,
                    ..
                } => {
                    frags += 1;
                    if let Some(p) = session.state.players.iter().find(|p| &p.name == victim) {
                        let side = victim_team.map_or("none", |t| t.id());
                        *report
                            .deaths
                            .entry(format!("{side}:{}", callout(p.x, p.z)))
                            .or_default() += 1;
                        let cell = |v: f32| (v / 10.0).floor() as i32 * 10 + 5;
                        *report
                            .death_grid
                            .entry(format!("{side}:{},{}", cell(p.x), cell(p.z)))
                            .or_default() += 1;
                    }
                }
                GameEvent::Sabotage {
                    kind: SabotageEventKind::Live,
                    ..
                } => {
                    for p in &session.state.players {
                        let armed = [
                            fragr_server::protocol::WeaponType::Tack,
                            fragr_server::protocol::WeaponType::Flechette,
                            fragr_server::protocol::WeaponType::Scatter,
                            fragr_server::protocol::WeaponType::Rail,
                        ]
                        .into_iter()
                        .any(|w| p.inventory.usable(w));
                        if !armed {
                            let side = p.team.map_or("none", |t| t.id());
                            *report.unarmed_at_live.entry(side.to_string()).or_default() += 1;
                        }
                    }
                }
                GameEvent::Sabotage { kind, .. } => match kind {
                    SabotageEventKind::PlantStarted => report.plants_started += 1,
                    SabotageEventKind::Planted => {
                        report.plants += 1;
                        planted = true;
                    }
                    SabotageEventKind::PlantInterrupted => report.plants_interrupted += 1,
                    SabotageEventKind::DefuseStarted => report.defuses_started += 1,
                    SabotageEventKind::Defused => report.defuses += 1,
                    SabotageEventKind::Detonated => report.detonations += 1,
                    SabotageEventKind::ChargeDropped => {
                        report.charge_drops += 1;
                        if let Some(charge) = session
                            .state
                            .snapshot()
                            .sabotage
                            .and_then(|state| state.charge)
                        {
                            *report
                                .drop_callouts
                                .entry(callout(charge.position[0], charge.position[2]))
                                .or_default() += 1;
                        }
                    }
                    SabotageEventKind::ChargeTaken => report.charge_pickups += 1,
                    SabotageEventKind::SidesSwapped => report.swaps += 1,
                    _ => {}
                },
                GameEvent::RoundEnd {
                    winning_team,
                    sabotage: Some(result),
                    ..
                } => {
                    rounds += 1;
                    let seconds = round_started.map_or(0.0, |at| {
                        session.state.tick.saturating_sub(at) as f64 / 20.0
                    });
                    let side = winning_team.map_or("none", |t| t.id());
                    *report
                        .wins
                        .entry(format!("{side}:{}", reason_id(result.reason)))
                        .or_default() += 1;
                    report.rounds.push(RoundRecord {
                        seed,
                        round: result.round,
                        winner: winning_team,
                        reason: result.reason,
                        seconds,
                        planted,
                        frags,
                    });
                    if result.match_over {
                        finished = Some(result.match_winner);
                    }
                }
                _ => {}
            }
        }
        if finished.is_some() {
            break;
        }
    }
    report.matches.push(MatchRecord {
        seed,
        rounds,
        finished: finished.is_some(),
        winner: finished.flatten(),
        seconds: session.state.tick as f64 / 20.0,
    });
}

/// Problems that fail a survey: an unfinished match, a round longer than its
/// clocks allow, and a loop that never shows a plant, a defuse, or a round
/// won by either side.
pub fn check_survey(report: &SurveyReport) -> Vec<String> {
    let mut problems = Vec::new();
    let config = SabotageConfig::default();
    // Muster, the live clock and a full charge, plus a second of slack.
    let bound =
        f64::from(config.muster_ticks + config.live_ticks + config.charge_ticks) / 20.0 + 1.0;
    for record in &report.matches {
        if !record.finished {
            problems.push(format!(
                "seed {} did not finish its match ({} rounds in {:.0} s)",
                record.seed, record.rounds, record.seconds
            ));
        }
    }
    for round in &report.rounds {
        if round.seconds > bound {
            problems.push(format!(
                "seed {} round {} lasted {:.1} s, past the {:.0} s bound",
                round.seed, round.round, round.seconds, bound
            ));
        }
    }
    if report.plants == 0 {
        problems.push("no charge was planted".into());
    }
    if report.defuses == 0 {
        problems.push("no charge was defused".into());
    }
    for side in [Team::Union, Team::Coalition] {
        if !report.rounds.iter().any(|r| r.winner == Some(side)) {
            problems.push(format!("{} never won a round", side.id()));
        }
    }
    problems
}

#[cfg(test)]
mod tests {
    use super::*;

    fn round(winner: Team, reason: SabotageReason, seconds: f64) -> RoundRecord {
        RoundRecord {
            seed: 1,
            round: 1,
            winner: Some(winner),
            reason,
            seconds,
            planted: reason != SabotageReason::Time,
            frags: 2,
        }
    }

    #[test]
    fn a_survey_needs_plants_defuses_both_winners_and_no_stuck_round() {
        let mut report = SurveyReport {
            matches: vec![MatchRecord {
                seed: 1,
                rounds: 2,
                finished: true,
                winner: Some(Team::Union),
                seconds: 200.0,
            }],
            rounds: vec![
                round(Team::Union, SabotageReason::Defused, 90.0),
                round(Team::Coalition, SabotageReason::Detonation, 120.0),
            ],
            plants: 2,
            defuses: 1,
            ..SurveyReport::default()
        };
        assert!(check_survey(&report).is_empty());
        report.defuses = 0;
        report.matches[0].finished = false;
        report.rounds[1].seconds = 500.0;
        report.rounds[1].winner = Some(Team::Union);
        let problems = check_survey(&report);
        assert_eq!(problems.len(), 4, "{problems:?}");
    }

    #[test]
    fn one_short_seed_finishes_with_real_round_results() {
        let report = run_survey(&SurveyConfig {
            seeds: vec![7],
            bots: 4,
            ..SurveyConfig::default()
        });
        assert_eq!(report.matches.len(), 1);
        let record = &report.matches[0];
        assert!(record.finished, "{report:?}");
        assert!(record.rounds >= 5);
        assert_eq!(report.rounds.len() as u32, record.rounds);
        assert!(report.rounds.iter().all(|r| r.seconds > 10.0));
    }
}
