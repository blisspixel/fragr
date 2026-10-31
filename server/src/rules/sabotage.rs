//! Sabotage match arithmetic: which half a round belongs to, when sides swap,
//! what wins the match and when a level match goes to sudden death. Pure functions of the
//! format and the round count, so every edge is a unit test rather than a
//! long simulation.
use crate::protocol::{SabotageFormat, Team, TeamScores, WeaponType};

/// Every Sabotage clock, at the 20 Hz simulation. Fields, not constants, so a
/// host or a test can shape them; the defaults are the design's numbers.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SabotageConfig {
    /// Optional host profile. Dead and parked fighters still occupy seats.
    pub five_vs_five: bool,
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
            five_vs_five: false,
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
    /// The match is level after its last extra period: this one round
    /// decides it. Each Sabotage round has a winner, so there is never a
    /// second.
    pub sudden_death: bool,
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
            sudden_death: false,
        };
    }
    let extra = format.extra_half_rounds();
    let into = round - regulation - 1;
    let period = into / (extra * 2) + 1;
    if let Some(limit) = format.extra_periods().filter(|limit| period > *limit) {
        // Level after every extra period: one round, same sides as the last.
        return RoundSlot {
            period: limit + 1,
            half: 1,
            half_rounds: 1,
            swap_after: false,
            rounds_to_win: half + limit * extra + 1,
            sudden_death: true,
        };
    }
    let within = into % (extra * 2) + 1;
    RoundSlot {
        period,
        half: if within <= extra { 1 } else { 2 },
        half_rounds: extra,
        swap_after: within == extra,
        rounds_to_win: half + (period - 1) * extra + extra + 1,
        sudden_death: false,
    }
}

/// What a match is after a round. There is no draw: a match level after its
/// last extra period plays a sudden death round.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MatchOutcome {
    Continue,
    Won(Team),
}

/// The match after `played` rounds with `score` round wins by uniform.
pub fn match_outcome(format: SabotageFormat, played: u32, score: TeamScores) -> MatchOutcome {
    if played == 0 {
        return MatchOutcome::Continue;
    }
    let slot = round_slot(format, played);
    Team::ALL
        .into_iter()
        .find(|team| score.get(*team) >= slot.rounds_to_win)
        .map_or(MatchOutcome::Continue, MatchOutcome::Won)
}

/// The side one round win from the match while `round` is played, if any.
/// A sudden death round is everybody's match point, so it names nobody.
pub fn match_point(format: SabotageFormat, round: u32, score: TeamScores) -> Option<Team> {
    let slot = round_slot(format, round);
    if slot.sudden_death {
        return None;
    }
    Team::ALL
        .into_iter()
        .find(|team| score.get(*team) + 1 >= slot.rounds_to_win)
}

/// The resupply ladder's top rung.
pub const RESUPPLY_MAX_TIER: u32 = 3;

/// The resupply ladder after a round: a loss climbs one rung, a win steps
/// one back down, the way the Counter-Strike loss bonus climbs and steps
/// back. No currency: the rung is what a side's fallen are reissued.
pub fn resupply_after(rung: u32, won: bool) -> u32 {
    if won {
        rung.saturating_sub(1)
    } else {
        (rung + 1).min(RESUPPLY_MAX_TIER)
    }
}

/// The rung a side's fallen are actually reissued at this round: its
/// ladder, but only while the side is not ahead on rounds. A side in front
/// that drops one round earns nothing from it.
pub fn resupply_tier(rung: u32, own: u32, other: u32) -> u32 {
    if own > other {
        0
    } else {
        rung.min(RESUPPLY_MAX_TIER)
    }
}

/// What a fallen fighter is reissued at a rung, on top of the empty start:
/// the guns, then the armour. Tuned on the bots-only survey: stronger kits
/// (full armour, a Railgun) all but removed three-round deficits but sent
/// three matches in four to extra time.
pub fn resupply_kit(tier: u32) -> (&'static [WeaponType], i32) {
    match tier {
        0 => (&[], 0),
        1 => (&[WeaponType::Flechette], 0),
        2 => (&[WeaponType::Flechette], 50),
        _ => (&[WeaponType::Flechette, WeaponType::Scatter], 50),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_resupply_ladder_climbs_on_a_loss_and_steps_back_on_a_win() {
        let mut rung = 0;
        for expected in [1, 2, 3, 3] {
            rung = resupply_after(rung, false);
            assert_eq!(rung, expected);
        }
        rung = resupply_after(rung, true);
        assert_eq!(rung, 2, "a win steps one rung down, not to the floor");
        assert_eq!(resupply_after(0, true), 0);
        // Only a side that is not in front draws on its ladder.
        assert_eq!(resupply_tier(2, 1, 3), 2);
        assert_eq!(resupply_tier(2, 2, 2), 2);
        assert_eq!(resupply_tier(2, 3, 1), 0);
        assert_eq!(resupply_tier(9, 0, 4), RESUPPLY_MAX_TIER);
        assert_eq!(resupply_kit(0), (&[][..], 0));
        assert_eq!(resupply_kit(1), (&[WeaponType::Flechette][..], 0));
        assert_eq!(resupply_kit(2), (&[WeaponType::Flechette][..], 50));
        assert_eq!(
            resupply_kit(3),
            (&[WeaponType::Flechette, WeaponType::Scatter][..], 50)
        );
    }

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
        // Level after the extra pair: no draw, one sudden death round.
        assert_eq!(
            match_outcome(short, 10, score(5, 5)),
            MatchOutcome::Continue
        );
        assert_eq!(
            match_outcome(short, 11, score(5, 6)),
            MatchOutcome::Won(Team::Coalition)
        );
        assert_eq!(
            match_outcome(short, 11, score(6, 5)),
            MatchOutcome::Won(Team::Union)
        );
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
    fn a_level_short_match_plays_one_sudden_death_round_and_match_points_are_named() {
        let short = SabotageFormat::Short;
        let decider = round_slot(short, 11);
        assert!(decider.sudden_death);
        assert_eq!(
            (decider.period, decider.half, decider.half_rounds),
            (2, 1, 1)
        );
        assert!(!decider.swap_after, "the decider keeps the last sides");
        assert_eq!(decider.rounds_to_win, 6);
        assert!((1..=10).all(|round| !round_slot(short, round).sudden_death));
        // The full match plays extra periods until decided instead.
        assert!((1..=60).all(|round| !round_slot(SabotageFormat::Match, round).sudden_death));

        assert_eq!(match_point(short, 1, score(0, 0)), None);
        assert_eq!(match_point(short, 6, score(4, 1)), Some(Team::Union));
        assert_eq!(match_point(short, 8, score(3, 4)), Some(Team::Coalition));
        // 4-4 goes to the extra pair, where the target is six.
        assert_eq!(match_point(short, 9, score(4, 4)), None);
        assert_eq!(match_point(short, 10, score(5, 4)), Some(Team::Union));
        assert_eq!(match_point(short, 11, score(5, 5)), None);
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
