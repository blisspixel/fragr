//! Match rule sets on the wire: the mode, its mutators, the sides and the
//! Host's reactions. The server validates a rule set once at start
//! (`crate::rules::RuleSet`); these are the shapes readers see.
use super::WeaponType;
use serde::{Deserialize, Serialize};

/// How a round is scored.
#[derive(
    Debug, Clone, Copy, Default, PartialEq, Eq, Hash, Serialize, Deserialize, clap::ValueEnum,
)]
#[serde(rename_all = "snake_case")]
pub enum GameMode {
    /// Free-for-all: every fighter for themselves.
    #[default]
    Ffa,
    /// Team deathmatch: the Union against the free coalition.
    Tdm,
}

impl GameMode {
    pub const ALL: [Self; 2] = [Self::Ffa, Self::Tdm];

    /// The wire and command-line id.
    pub const fn id(self) -> &'static str {
        match self {
            Self::Ffa => "ffa",
            Self::Tdm => "tdm",
        }
    }

    /// The English label for logs and the status line. Clients key their own.
    pub const fn name(self) -> &'static str {
        match self {
            Self::Ffa => "Free-for-all",
            Self::Tdm => "Team Deathmatch",
        }
    }

    pub const fn teams(self) -> bool {
        matches!(self, Self::Tdm)
    }
}

/// A host rule twist on top of a mode. Every one is a host setting.
#[derive(
    Debug,
    Clone,
    Copy,
    PartialEq,
    Eq,
    PartialOrd,
    Ord,
    Hash,
    Serialize,
    Deserialize,
    clap::ValueEnum,
)]
#[serde(rename_all = "kebab-case")]
#[value(rename_all = "kebab-case")]
pub enum Mutator {
    /// Everyone holds the Railgun with unlimited cells.
    RailOnly,
    /// Everyone holds the Shotgun with unlimited shells.
    ShotgunOnly,
    /// Fists only: the old Slappers Only.
    FistsOnly,
    /// Any hit that deals damage kills.
    LicenceToKill,
    /// One golden Railgun that kills in one hit and returns when its holder dies.
    GoldenRail,
    /// Two lives each per round; the last fighter or side standing wins.
    TwoLives,
}

impl Mutator {
    pub const ALL: [Self; 6] = [
        Self::RailOnly,
        Self::ShotgunOnly,
        Self::FistsOnly,
        Self::LicenceToKill,
        Self::GoldenRail,
        Self::TwoLives,
    ];

    /// The wire and command-line id.
    pub const fn id(self) -> &'static str {
        match self {
            Self::RailOnly => "rail-only",
            Self::ShotgunOnly => "shotgun-only",
            Self::FistsOnly => "fists-only",
            Self::LicenceToKill => "licence-to-kill",
            Self::GoldenRail => "golden-rail",
            Self::TwoLives => "two-lives",
        }
    }

    pub const fn name(self) -> &'static str {
        match self {
            Self::RailOnly => "Rail Only",
            Self::ShotgunOnly => "Shotgun Only",
            Self::FistsOnly => "Fists Only",
            Self::LicenceToKill => "Licence to Kill",
            Self::GoldenRail => "Golden Rail",
            Self::TwoLives => "Two Lives",
        }
    }

    /// The one weapon a weapon-only mutator hands everybody.
    pub const fn only_weapon(self) -> Option<WeaponType> {
        match self {
            Self::RailOnly => Some(WeaponType::Rail),
            Self::ShotgunOnly => Some(WeaponType::Scatter),
            Self::FistsOnly => Some(WeaponType::Fists),
            _ => None,
        }
    }
}

/// A side in a team mode. The Union wears black and red; the free coalition
/// wears bone, leather and ember.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Team {
    Union,
    Coalition,
}

impl Team {
    pub const ALL: [Self; 2] = [Self::Union, Self::Coalition];

    pub const fn index(self) -> usize {
        match self {
            Self::Union => 0,
            Self::Coalition => 1,
        }
    }

    pub const fn other(self) -> Self {
        match self {
            Self::Union => Self::Coalition,
            Self::Coalition => Self::Union,
        }
    }

    pub const fn id(self) -> &'static str {
        match self {
            Self::Union => "union",
            Self::Coalition => "coalition",
        }
    }

    pub const fn name(self) -> &'static str {
        match self {
            Self::Union => "The Union",
            Self::Coalition => "The Free Coalition",
        }
    }
}

/// Side frags for the current round.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct TeamScores {
    pub union: u32,
    pub coalition: u32,
}

impl TeamScores {
    pub fn get(self, team: Team) -> u32 {
        match team {
            Team::Union => self.union,
            Team::Coalition => self.coalition,
        }
    }

    pub fn add(&mut self, team: Team) {
        match team {
            Team::Union => self.union = self.union.saturating_add(1),
            Team::Coalition => self.coalition = self.coalition.saturating_add(1),
        }
    }

    /// The side ahead, or None when level.
    pub fn leader(self) -> Option<Team> {
        match self.union.cmp(&self.coalition) {
            std::cmp::Ordering::Greater => Some(Team::Union),
            std::cmp::Ordering::Less => Some(Team::Coalition),
            std::cmp::Ordering::Equal => None,
        }
    }

    pub fn max(self) -> u32 {
        self.union.max(self.coalition)
    }
}

/// The rule set a server runs, as every reader sees it.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct MatchRules {
    pub mode: GameMode,
    /// English label such as "Team Deathmatch: Rail Only". Clients key their own.
    pub name: String,
    /// Sorted and unique. Omitted when none.
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub mutators: Vec<Mutator>,
    /// Team damage lands. Omitted when off, the default.
    #[serde(default, skip_serializing_if = "super::is_false")]
    pub friendly_fire: bool,
    /// Lives per fighter per round. Omitted when unlimited.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub lives: Option<u8>,
}

/// A beat the Host calls from an authoritative fact. The client owns the
/// words, keyed `HOST_REACTION_<KIND>_<VARIANT>`.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum HostReactionKind {
    FirstBlood,
    StreakEnded,
    LastStanding,
    Comeback,
    GoldenRail,
}

impl HostReactionKind {
    pub const ALL: [Self; 5] = [
        Self::FirstBlood,
        Self::StreakEnded,
        Self::LastStanding,
        Self::Comeback,
        Self::GoldenRail,
    ];

    /// Information rather than drama: never held back by the reaction gap.
    pub const fn always(self) -> bool {
        matches!(self, Self::GoldenRail)
    }
}

/// Variants per reaction kind. A variant is `0..HOST_REACTION_VARIANTS`.
pub const HOST_REACTION_VARIANTS: u8 = 3;

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ids_round_trip_through_serde_and_labels_are_distinct() {
        for mode in GameMode::ALL {
            let json = serde_json::to_string(&mode).unwrap();
            assert_eq!(json, format!("\"{}\"", mode.id()));
            assert_eq!(serde_json::from_str::<GameMode>(&json).unwrap(), mode);
        }
        let mut names = std::collections::HashSet::new();
        for mutator in Mutator::ALL {
            let json = serde_json::to_string(&mutator).unwrap();
            assert_eq!(json, format!("\"{}\"", mutator.id()));
            assert_eq!(serde_json::from_str::<Mutator>(&json).unwrap(), mutator);
            assert!(names.insert(mutator.name()));
        }
        assert!(serde_json::from_str::<Mutator>("\"low-gravity\"").is_err());
        for team in Team::ALL {
            assert_eq!(team.other().other(), team);
            assert_eq!(
                serde_json::to_string(&team).unwrap(),
                format!("\"{}\"", team.id())
            );
        }
    }

    #[test]
    fn only_weapon_mutators_name_one_weapon_each() {
        assert_eq!(Mutator::RailOnly.only_weapon(), Some(WeaponType::Rail));
        assert_eq!(
            Mutator::ShotgunOnly.only_weapon(),
            Some(WeaponType::Scatter)
        );
        assert_eq!(Mutator::FistsOnly.only_weapon(), Some(WeaponType::Fists));
        assert_eq!(Mutator::TwoLives.only_weapon(), None);
    }

    #[test]
    fn team_scores_lead_and_level() {
        let mut scores = TeamScores::default();
        assert_eq!(scores.leader(), None);
        scores.add(Team::Coalition);
        assert_eq!(scores.leader(), Some(Team::Coalition));
        scores.add(Team::Union);
        scores.add(Team::Union);
        assert_eq!(scores.leader(), Some(Team::Union));
        assert_eq!(
            (scores.get(Team::Union), scores.get(Team::Coalition)),
            (2, 1)
        );
        assert_eq!(scores.max(), 2);
    }

    #[test]
    fn match_rules_omit_defaults_on_the_wire() {
        let plain = MatchRules {
            mode: GameMode::Ffa,
            name: "Free-for-all".into(),
            mutators: vec![],
            friendly_fire: false,
            lives: None,
        };
        let json = serde_json::to_value(&plain).unwrap();
        assert_eq!(
            json,
            serde_json::json!({"mode": "ffa", "name": "Free-for-all"})
        );
        let twisted = MatchRules {
            mode: GameMode::Tdm,
            name: "Team Deathmatch: Rail Only, Two Lives".into(),
            mutators: vec![Mutator::RailOnly, Mutator::TwoLives],
            friendly_fire: true,
            lives: Some(2),
        };
        let json = serde_json::to_string(&twisted).unwrap();
        assert!(json.contains("\"mutators\":[\"rail-only\",\"two-lives\"]"));
        assert_eq!(serde_json::from_str::<MatchRules>(&json).unwrap(), twisted);
        assert!(HostReactionKind::GoldenRail.always());
        assert!(!HostReactionKind::FirstBlood.always());
    }
}
