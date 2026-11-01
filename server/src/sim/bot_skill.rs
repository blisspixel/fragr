//! How good a rule bot is. Five rungs of the league's own ladder, from a
//! visitor who wandered in off the street to a regular who never leaves a
//! crumb. Every rung sees through the same honest gates (`bot_senses.rs`):
//! the 120 degree cone, line of sight, a reaction to every new sighting and
//! a turn limit. A rung moves only how long that reaction takes, how wide the
//! aim error is, how fast the head turns, how far the eyes reach and how well
//! the bot chooses: whether it keeps time on power pads, leads a moving body
//! with the Rocket and picks the gun for the distance. No rung reacts in
//! under 150 ms, and none sees or aims at a body it could not see.

/// A rule bot's rung, lowest first. Hosts pick one for every bot on the
/// server; `Regular` is the default and the rung every survey was tuned on.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Default, clap::ValueEnum)]
pub enum BotSkill {
    /// First night at the venue: slow to react, loose aim, slow head.
    Tourist,
    /// Has been before and mostly knows where the guns are.
    #[value(name = "walk-in")]
    WalkIn,
    /// The league's ordinary regular: the tuned default.
    #[default]
    Regular,
    /// Gets billed: quick, tight and keeps every clock.
    Headliner,
    /// Did it perfectly. Still human-quick, never inhuman.
    #[value(name = "no-crumbs")]
    NoCrumbs,
}

/// The numbers behind a rung.
#[derive(Debug, Clone, Copy, PartialEq)]
pub(crate) struct SkillProfile {
    /// Fewest ticks from a new sighting to the first shot. Three ticks is
    /// 150 ms at 20 Hz, the floor for every rung.
    pub reaction_min: u64,
    /// Extra ticks drawn on top, uniformly from zero to this.
    pub reaction_spread: u64,
    /// Aim error bound per axis, radians.
    pub aim_error: f32,
    /// Fastest head turn, radians per tick.
    pub turn_per_tick: f32,
    /// How far the eyes reach, metres.
    pub sight_range: f32,
    /// Aim error multiplier for a few ticks after being hit.
    pub flinch: f32,
    /// Keeps time on the power pad its callsign favours.
    pub keeps_time: bool,
    /// Leads a body it watched move with the Rocket.
    pub leads: bool,
    /// Changes to the right gun for the distance in a fight.
    pub picks_gun: bool,
}

/// The fastest any rung reacts, ticks: 150 ms.
pub(crate) const REACTION_FLOOR: u64 = 3;

impl BotSkill {
    pub const ALL: [BotSkill; 5] = [
        BotSkill::Tourist,
        BotSkill::WalkIn,
        BotSkill::Regular,
        BotSkill::Headliner,
        BotSkill::NoCrumbs,
    ];

    /// The command line and settings token.
    pub fn id(self) -> &'static str {
        match self {
            BotSkill::Tourist => "tourist",
            BotSkill::WalkIn => "walk-in",
            BotSkill::Regular => "regular",
            BotSkill::Headliner => "headliner",
            BotSkill::NoCrumbs => "no-crumbs",
        }
    }

    pub fn from_id(raw: &str) -> Option<Self> {
        Self::ALL.into_iter().find(|skill| skill.id() == raw)
    }

    /// The rung's place on the ladder, 0 lowest.
    pub fn rank(self) -> usize {
        Self::ALL
            .iter()
            .position(|skill| *skill == self)
            .unwrap_or(2)
    }

    /// How far this rung's eyes reach, metres.
    pub fn sight_metres(self) -> f32 {
        self.profile().sight_range
    }

    pub(crate) fn profile(self) -> SkillProfile {
        match self {
            BotSkill::Tourist => SkillProfile {
                reaction_min: 8,
                reaction_spread: 5,
                aim_error: 0.095,
                turn_per_tick: 0.06,
                sight_range: 44.0,
                flinch: 4.0,
                keeps_time: false,
                leads: false,
                picks_gun: false,
            },
            BotSkill::WalkIn => SkillProfile {
                reaction_min: 6,
                reaction_spread: 4,
                aim_error: 0.08,
                turn_per_tick: 0.075,
                sight_range: 54.0,
                flinch: 3.5,
                keeps_time: false,
                leads: true,
                picks_gun: true,
            },
            // The constants every survey through wave 20 was measured on.
            BotSkill::Regular => SkillProfile {
                reaction_min: 4,
                reaction_spread: 4,
                aim_error: 0.055,
                turn_per_tick: 0.1,
                sight_range: 64.0,
                flinch: 3.0,
                keeps_time: true,
                leads: true,
                picks_gun: true,
            },
            BotSkill::Headliner => SkillProfile {
                reaction_min: 3,
                reaction_spread: 3,
                aim_error: 0.034,
                turn_per_tick: 0.14,
                sight_range: 72.0,
                flinch: 2.0,
                keeps_time: true,
                leads: true,
                picks_gun: true,
            },
            BotSkill::NoCrumbs => SkillProfile {
                reaction_min: 3,
                reaction_spread: 1,
                aim_error: 0.01,
                turn_per_tick: 0.24,
                sight_range: 80.0,
                flinch: 1.0,
                keeps_time: true,
                leads: true,
                picks_gun: true,
            },
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rungs_climb_in_every_number_and_none_reacts_under_150_ms() {
        for pair in BotSkill::ALL.windows(2) {
            let (low, high) = (pair[0].profile(), pair[1].profile());
            assert!(
                high.reaction_min + high.reaction_spread < low.reaction_min + low.reaction_spread
            );
            assert!(high.reaction_min <= low.reaction_min);
            assert!(high.aim_error < low.aim_error);
            assert!(high.turn_per_tick > low.turn_per_tick);
            assert!(high.sight_range > low.sight_range);
            assert!(high.flinch < low.flinch);
        }
        for skill in BotSkill::ALL {
            let profile = skill.profile();
            assert!(profile.reaction_min >= REACTION_FLOOR, "{skill:?}");
            assert!(profile.reaction_min * 50 >= 150);
            assert_eq!(BotSkill::from_id(skill.id()), Some(skill));
            assert_eq!(BotSkill::ALL[skill.rank()], skill);
        }
        assert_eq!(BotSkill::default(), BotSkill::Regular);
        assert_eq!(BotSkill::from_id("elite"), None);
    }

    #[test]
    fn the_default_rung_keeps_the_surveyed_constants() {
        let regular = BotSkill::Regular.profile();
        assert_eq!((regular.reaction_min, regular.reaction_spread), (4, 4));
        assert_eq!(regular.aim_error, 0.055);
        assert_eq!(regular.turn_per_tick, 0.1);
        assert_eq!(regular.sight_range, 64.0);
    }
}
