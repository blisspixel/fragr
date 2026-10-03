//! Sabotage match arithmetic: which half a round belongs to, when sides swap,
//! what wins the match and when a level match is a draw. Pure functions of the
//! format and the round count, so every edge is a unit test rather than a
//! long simulation.
use crate::protocol::{SabotageFormat, Team, TeamScores};

/// Every Sabotage clock, at the 20 Hz simulation. Fields, not constants, so a
/// host or a test can shape them; the defaults are the design's numbers.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SabotageConfig {
    pub format: SabotageFormat,
    /// Held in the spawn zones before weapons go live.
    pub muster_ticks: u32,
    /// The round clock before a plant.
    pub live_ticks: u32,
    /// Standing with Use held to plant.
    pub plant_ticks: u32,
    /// The planted charge's clock.
    pub charge_ticks: u32,
    /// Standing with Use held to defuse.
    pub defuse_ticks: u32,
    /// The result card between rounds.
    pub round_end_ticks: u32,
    /// The result card before a side swap, long enough to read the notice.
    pub swap_end_ticks: u32,
}

impl Default for SabotageConfig {
    fn default() -> Self {
        Self {
            format: SabotageFormat::default(),
            muster_ticks: 20 * 10,
            live_ticks: 20 * 105,
            plant_ticks: 20 * 3,
            charge_ticks: 20 * 35,
            defuse_ticks: 20 * 6,
            round_end_ticks: 20 * 5,
            swap_end_ticks: 20 * 8,
        }
    }
}

/// Where one round sits in a match.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct RoundSlot {
    /// Extra period, 0 in regulation.
    pub period: u32,
    /// 1 or 2 within the period.
    pub half: u8,
    /// Rounds in each half of this period.
    pub half_rounds: u32,
    /// The last round of a half that is followed by a swap. Regulation's
    /// second half flows into extra time without one, as in Counter-Strike.
    pub swap_after: bool,
    /// Round wins that take the match while this round is played.
    pub rounds_to_win: u32,
}

/// The slot of the `round`-th round of a match, counting from 1.
pub fn round_slot(format: SabotageFormat, round: u32) -> RoundSlot {
    let half = format.half_rounds();
    let regulation = half * 2;
    let round = round.max(1);
    if round <= regulation {
        return RoundSlot {
            period: 0,
            half: if round <= half { 1 } else { 2 },
            half_rounds: half,
            swap_after: round == half,
            rounds_to_win: half + 1,
        };
    }
    let extra = format.extra_half_rounds();
    let into = round - regulation - 1;
    let period = into / (extra * 2) + 1;
    let within = into % (extra * 2) + 1;
    RoundSlot {
        period,
        half: if within <= extra { 1 } else { 2 },
        half_rounds: extra,
        swap_after: within == extra,
        rounds_to_win: half + (period - 1) * extra + extra + 1,
    }
}

/// What a match is after a round.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MatchOutcome {
    Continue,
    Won(Team),
    Draw,
}

/// The match after `played` rounds with `score` round wins by uniform.
pub fn match_outcome(format: SabotageFormat, played: u32, score: TeamScores) -> MatchOutcome {
    if played == 0 {
        return MatchOutcome::Continue;
    }
    let slot = round_slot(format, played);
    for team in Team::ALL {
        if score.get(team) >= slot.rounds_to_win {
            return MatchOutcome::Won(team);
        }
    }
    let regulation = format.half_rounds() * 2;
    if played < regulation {
        return MatchOutcome::Continue;
    }
    let period_rounds = format.extra_half_rounds() * 2;
    let period_end = played == regulation || (played - regulation).is_multiple_of(period_rounds);
    if !period_end || score.leader().is_some() {
        return MatchOutcome::Continue;
    }
    let periods_played = (played - regulation) / period_rounds;
    match format.extra_periods() {
        Some(limit) if periods_played >= limit => MatchOutcome::Draw,
        _ => MatchOutcome::Continue,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn score(union: u32, coalition: u32) -> TeamScores {
        TeamScores { union, coalition }
    }

    #[test]
    fn regulation_halves_swap_once_and_set_the_target() {
        for (format, half) in [(SabotageFormat::Short, 4), (SabotageFormat::Match, 8)] {
            for round in 1..=half * 2 {
                let slot = round_slot(format, round);
                assert_eq!(slot.period, 0);
                assert_eq!(slot.half, if round <= half { 1 } else { 2 });
                assert_eq!(slot.half_rounds, half);
                assert_eq!(slot.swap_after, round == half, "{format:?} round {round}");
                assert_eq!(slot.rounds_to_win, half + 1);
            }
        }
        assert_eq!(
            round_slot(SabotageFormat::Short, 0),
            round_slot(SabotageFormat::Short, 1)
        );
    }

    #[test]
    fn extra_periods_swap_at_their_own_half_and_raise_the_target() {
        // Short: one round each side after 4-4.
        let ninth = round_slot(SabotageFormat::Short, 9);
        assert_eq!((ninth.period, ninth.half, ninth.half_rounds), (1, 1, 1));
        assert!(ninth.swap_after);
        assert_eq!(ninth.rounds_to_win, 6);
        let tenth = round_slot(SabotageFormat::Short, 10);
        assert_eq!((tenth.period, tenth.half, tenth.swap_after), (1, 2, false));
        // Match: halves of three, first to four of the period.
        let seventeenth = round_slot(SabotageFormat::Match, 17);
        assert_eq!((seventeenth.period, seventeenth.half), (1, 1));
        assert_eq!(seventeenth.rounds_to_win, 12);
        assert!(round_slot(SabotageFormat::Match, 19).swap_after);
        assert!(!round_slot(SabotageFormat::Match, 22).swap_after);
        let second = round_slot(SabotageFormat::Match, 23);
        assert_eq!(
            (second.period, second.half, second.rounds_to_win),
            (2, 1, 15)
        );
    }

    #[test]
    fn the_match_is_won_at_the_target_and_not_before() {
        let short = SabotageFormat::Short;
        assert_eq!(match_outcome(short, 0, score(0, 0)), MatchOutcome::Continue);
        assert_eq!(match_outcome(short, 4, score(4, 0)), MatchOutcome::Continue);
        assert_eq!(
            match_outcome(short, 5, score(5, 0)),
            MatchOutcome::Won(Team::Union)
        );
        assert_eq!(
            match_outcome(short, 7, score(2, 5)),
            MatchOutcome::Won(Team::Coalition)
        );
        assert_eq!(match_outcome(short, 8, score(4, 4)), MatchOutcome::Continue);
        assert_eq!(match_outcome(short, 9, score(5, 4)), MatchOutcome::Continue);
        assert_eq!(
            match_outcome(short, 10, score(6, 4)),
            MatchOutcome::Won(Team::Union)
        );
        assert_eq!(match_outcome(short, 10, score(5, 5)), MatchOutcome::Draw);
        let full = SabotageFormat::Match;
        assert_eq!(
            match_outcome(full, 15, score(9, 6)),
            MatchOutcome::Won(Team::Union)
        );
        assert_eq!(match_outcome(full, 16, score(8, 8)), MatchOutcome::Continue);
        assert_eq!(
            match_outcome(full, 21, score(12, 9)),
            MatchOutcome::Won(Team::Union)
        );
        assert_eq!(
            match_outcome(full, 22, score(11, 11)),
            MatchOutcome::Continue
        );
        assert_eq!(
            match_outcome(full, 26, score(11, 15)),
            MatchOutcome::Won(Team::Coalition)
        );
        assert_eq!(
            match_outcome(full, 28, score(14, 14)),
            MatchOutcome::Continue
        );
    }

    #[test]
    fn default_clocks_are_the_designed_times() {
        let config = SabotageConfig::default();
        assert_eq!(config.muster_ticks, 200);
        assert_eq!(config.live_ticks, 2100);
        assert_eq!(config.plant_ticks, 60);
        assert_eq!(config.charge_ticks, 700);
        assert_eq!(config.defuse_ticks, 120);
        assert_eq!(config.round_end_ticks, 100);
        assert!(config.swap_end_ticks > config.round_end_ticks);
    }
}
