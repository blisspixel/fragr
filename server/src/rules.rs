//! The rule set a server runs: a mode plus host mutators, validated once at
//! start and carried in `MatchConfig`. The sim asks it questions; the wire
//! shape readers see is `protocol::MatchRules`.
use crate::protocol::{GameMode, MatchRules, Mutator, Team, TeamScores, WeaponType};

/// Lives each fighter has per round under Two Lives.
pub const TWO_LIVES: u8 = 2;
/// Default frag limit for a team round: side frags, not fighter frags.
pub const TEAM_FRAG_LIMIT: u32 = 25;
/// Weapon pads come back on the rule sheet's slower team clock.
pub const TEAM_WEAPON_RESPAWN_TICKS: u32 = 20 * 30;
/// No Host reaction lands within eight seconds of the last one.
pub const REACTION_GAP_TICKS: u64 = 20 * 8;
/// A streak this long is worth a line when it ends.
pub const STREAK_WORTH_ENDING: u32 = 3;
/// A side this far behind that draws level is a comeback.
pub const COMEBACK_DEFICIT: u32 = 4;

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct RuleSet {
    mode: GameMode,
    mutators: Vec<Mutator>,
    friendly_fire: bool,
}

impl RuleSet {
    /// Refuse combinations that contradict each other, so a host learns at
    /// start rather than in the middle of a confusing round.
    pub fn new(mode: GameMode, mutators: &[Mutator], friendly_fire: bool) -> Result<Self, String> {
        let mut mutators = mutators.to_vec();
        mutators.sort_unstable();
        mutators.dedup();
        let only: Vec<Mutator> = mutators
            .iter()
            .copied()
            .filter(|m| m.only_weapon().is_some())
            .collect();
        if only.len() > 1 {
            return Err(format!(
                "choose one weapon mutator, not {}",
                only.iter()
                    .map(|m| m.id())
                    .collect::<Vec<_>>()
                    .join(" and ")
            ));
        }
        if mutators.contains(&Mutator::GoldenRail) {
            if mutators.contains(&Mutator::LicenceToKill) {
                return Err(
                    "golden-rail needs one weapon to be special; licence-to-kill makes every hit kill"
                        .into(),
                );
            }
            if let Some(m) = only.first().filter(|m| **m != Mutator::RailOnly) {
                return Err(format!(
                    "golden-rail is a Railgun and cannot run with {}",
                    m.id()
                ));
            }
        }
        if friendly_fire && !mode.teams() {
            return Err("friendly fire needs a team mode".into());
        }
        Ok(Self {
            mode,
            mutators,
            friendly_fire,
        })
    }

    pub fn mode(&self) -> GameMode {
        self.mode
    }

    pub fn mutators(&self) -> &[Mutator] {
        &self.mutators
    }

    pub fn has(&self, mutator: Mutator) -> bool {
        self.mutators.contains(&mutator)
    }

    pub fn teams(&self) -> bool {
        self.mode.teams()
    }

    pub fn friendly_fire(&self) -> bool {
        self.friendly_fire
    }

    /// Plain free-for-all: what every server ran before rule sets.
    pub fn is_plain(&self) -> bool {
        *self == Self::default()
    }

    pub fn only_weapon(&self) -> Option<WeaponType> {
        self.mutators.iter().find_map(|m| m.only_weapon())
    }

    /// Lives per fighter per round, None when unlimited.
    pub fn lives(&self) -> Option<u8> {
        self.has(Mutator::TwoLives).then_some(TWO_LIVES)
    }

    pub fn name(&self) -> String {
        if self.mutators.is_empty() {
            return self.mode.name().to_string();
        }
        let twists: Vec<&str> = self.mutators.iter().map(|m| m.name()).collect();
        format!("{}: {}", self.mode.name(), twists.join(", "))
    }

    pub fn wire(&self) -> MatchRules {
        MatchRules {
            mode: self.mode,
            name: self.name(),
            mutators: self.mutators.clone(),
            friendly_fire: self.friendly_fire,
            lives: self.lives(),
        }
    }

    /// The frag limit a host gets without naming one.
    pub fn default_frag_limit(&self) -> u32 {
        if self.teams() {
            TEAM_FRAG_LIMIT
        } else {
            10
        }
    }
}

/// The side a joiner takes: the smaller one, then the one behind on frags,
/// then the coalition. Humans, agents and rule bots all come through here.
pub fn choose_team(counts: [usize; 2], scores: TeamScores) -> Team {
    let [union, coalition] = counts;
    if union != coalition {
        return if union < coalition {
            Team::Union
        } else {
            Team::Coalition
        };
    }
    match scores.leader() {
        Some(leader) => leader.other(),
        None => Team::Coalition,
    }
}

/// Which half of the map a spawn point belongs to. The Union holds negative
/// X and the coalition positive X; a point on the line belongs to neither.
pub fn spawn_side(x: f32) -> Option<Team> {
    if x < -0.5 {
        Some(Team::Union)
    } else if x > 0.5 {
        Some(Team::Coalition)
    } else {
        None
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn plain_rules_are_the_old_free_for_all() {
        let plain = RuleSet::default();
        assert!(plain.is_plain());
        assert_eq!(plain.name(), "Free-for-all");
        assert_eq!(plain.lives(), None);
        assert_eq!(plain.only_weapon(), None);
        assert_eq!(plain.default_frag_limit(), 10);
        assert!(!RuleSet::new(GameMode::Tdm, &[], false).unwrap().is_plain());
    }

    #[test]
    fn mutators_sort_dedupe_and_name_themselves() {
        let rules = RuleSet::new(
            GameMode::Tdm,
            &[Mutator::TwoLives, Mutator::RailOnly, Mutator::TwoLives],
            true,
        )
        .unwrap();
        assert_eq!(rules.mutators(), &[Mutator::RailOnly, Mutator::TwoLives]);
        assert_eq!(rules.name(), "Team Deathmatch: Rail Only, Two Lives");
        assert_eq!(rules.only_weapon(), Some(WeaponType::Rail));
        assert_eq!(rules.lives(), Some(2));
        assert_eq!(rules.default_frag_limit(), TEAM_FRAG_LIMIT);
        let wire = rules.wire();
        assert!(wire.friendly_fire);
        assert_eq!(wire.lives, Some(2));
    }

    #[test]
    fn contradictory_rules_refuse_to_start() {
        for bad in [
            vec![Mutator::RailOnly, Mutator::FistsOnly],
            vec![Mutator::GoldenRail, Mutator::LicenceToKill],
            vec![Mutator::GoldenRail, Mutator::ShotgunOnly],
            vec![Mutator::GoldenRail, Mutator::FistsOnly],
        ] {
            assert!(RuleSet::new(GameMode::Ffa, &bad, false).is_err(), "{bad:?}");
        }
        assert!(RuleSet::new(GameMode::Ffa, &[], true).is_err());
        assert!(RuleSet::new(
            GameMode::Ffa,
            &[Mutator::GoldenRail, Mutator::RailOnly],
            false
        )
        .is_ok());
    }

    #[test]
    fn joiners_fill_the_short_side_then_the_losing_side() {
        let level = TeamScores::default();
        assert_eq!(choose_team([2, 1], level), Team::Coalition);
        assert_eq!(choose_team([1, 2], level), Team::Union);
        assert_eq!(choose_team([1, 1], level), Team::Coalition);
        let union_ahead = TeamScores {
            union: 3,
            coalition: 1,
        };
        assert_eq!(choose_team([2, 2], union_ahead), Team::Coalition);
        let coalition_ahead = TeamScores {
            union: 0,
            coalition: 5,
        };
        assert_eq!(choose_team([2, 2], coalition_ahead), Team::Union);
    }

    #[test]
    fn spawn_halves_split_on_x() {
        assert_eq!(spawn_side(-10.0), Some(Team::Union));
        assert_eq!(spawn_side(10.0), Some(Team::Coalition));
        assert_eq!(spawn_side(0.0), None);
    }
}
