//! Host presets: the named rule packages a host launches in one pick (the
//! GoldenEye couch favourites, Pillar 5 of the multiplayer plan). A preset is
//! only a starting set of mutators; the host may stack compatible twists on
//! top, and `RuleSet::new` still refuses a contradiction.
//!
//! Proximity Party (Pistols and proximity mines only) is not here: the server
//! has no mines-only start kit, and a preset never promises a rule the sim
//! does not run.
use crate::protocol::Mutator;

#[derive(
    Debug,
    Clone,
    Copy,
    Default,
    PartialEq,
    Eq,
    serde::Serialize,
    serde::Deserialize,
    clap::ValueEnum,
)]
#[serde(rename_all = "kebab-case")]
#[value(rename_all = "kebab-case")]
pub enum Preset {
    /// The mode's own rules.
    #[default]
    Standard,
    /// Any damaging hit kills.
    LicenceToKill,
    /// One golden Railgun that kills in one hit.
    GoldenRail,
    /// Fists only.
    SlappersOnly,
    /// Shotguns only.
    ShotgunWedding,
}

impl Preset {
    pub const ALL: [Self; 5] = [
        Self::Standard,
        Self::LicenceToKill,
        Self::GoldenRail,
        Self::SlappersOnly,
        Self::ShotgunWedding,
    ];

    /// The command-line id.
    pub const fn id(self) -> &'static str {
        match self {
            Self::Standard => "standard",
            Self::LicenceToKill => "licence-to-kill",
            Self::GoldenRail => "golden-rail",
            Self::SlappersOnly => "slappers-only",
            Self::ShotgunWedding => "shotgun-wedding",
        }
    }

    pub const fn name(self) -> &'static str {
        match self {
            Self::Standard => "Standard",
            Self::LicenceToKill => "Licence to Kill",
            Self::GoldenRail => "Golden Rail",
            Self::SlappersOnly => "Slappers Only",
            Self::ShotgunWedding => "Shotgun Wedding",
        }
    }

    /// The mutators this preset starts from.
    pub const fn mutators(self) -> &'static [Mutator] {
        match self {
            Self::Standard => &[],
            Self::LicenceToKill => &[Mutator::LicenceToKill],
            Self::GoldenRail => &[Mutator::GoldenRail],
            Self::SlappersOnly => &[Mutator::FistsOnly],
            Self::ShotgunWedding => &[Mutator::ShotgunOnly],
        }
    }

    /// This preset's mutators with `extra` stacked on top. Duplicates are
    /// left for `RuleSet::new`, which sorts and dedupes.
    pub fn stack(self, extra: &[Mutator]) -> Vec<Mutator> {
        self.mutators().iter().chain(extra).copied().collect()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::protocol::GameMode;
    use crate::rules::RuleSet;

    #[test]
    fn every_preset_is_a_valid_rule_set_in_free_for_all() {
        for preset in Preset::ALL {
            let rules = RuleSet::new(GameMode::Ffa, preset.mutators(), false)
                .unwrap_or_else(|error| panic!("{}: {error}", preset.id()));
            assert_eq!(rules.mutators(), preset.mutators(), "{}", preset.id());
            assert!(!preset.name().is_empty());
        }
        assert_eq!(Preset::default(), Preset::Standard);
        assert_eq!(Preset::SlappersOnly.mutators(), [Mutator::FistsOnly]);
        assert_eq!(Preset::ShotgunWedding.mutators(), [Mutator::ShotgunOnly]);
    }

    #[test]
    fn presets_stack_compatible_twists_and_refuse_contradictions() {
        let wedding = Preset::ShotgunWedding.stack(&[Mutator::LicenceToKill, Mutator::TwoLives]);
        let rules = RuleSet::new(GameMode::Ffa, &wedding, false).unwrap();
        assert_eq!(
            rules.mutators(),
            [
                Mutator::ShotgunOnly,
                Mutator::LicenceToKill,
                Mutator::TwoLives
            ]
        );
        // Stacking a preset's own twist again is harmless.
        let twice = Preset::LicenceToKill.stack(&[Mutator::LicenceToKill]);
        assert_eq!(
            RuleSet::new(GameMode::Tdm, &twice, false)
                .unwrap()
                .mutators(),
            [Mutator::LicenceToKill]
        );
        for (preset, extra) in [
            (Preset::GoldenRail, Mutator::LicenceToKill),
            (Preset::GoldenRail, Mutator::FullArsenal),
            (Preset::SlappersOnly, Mutator::FullArsenal),
            (Preset::ShotgunWedding, Mutator::RailOnly),
        ] {
            assert!(
                RuleSet::new(GameMode::Ffa, &preset.stack(&[extra]), false).is_err(),
                "{} + {}",
                preset.id(),
                extra.id()
            );
        }
    }
}
