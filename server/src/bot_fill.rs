//! Arena population policy and bounded tick-owned admission coordination.
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

#[derive(
    Debug,
    Clone,
    Copy,
    Default,
    PartialEq,
    Eq,
    clap::ValueEnum,
    serde::Serialize,
    serde::Deserialize,
)]
#[serde(rename_all = "snake_case")]
pub enum BotPolicy {
    #[default]
    Fixed,
    None,
    Auto,
}

pub const ADMISSION_TIMEOUT: Duration = Duration::from_secs(2);

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AdmissionPhase {
    Pending,
    Cancelled,
    Committed,
}

/// The socket and tick owner serialize cancellation against the commit point.
pub struct AutoAdmission {
    pub phase: AdmissionPhase,
    pub deadline: Instant,
}

pub type AdmissionGate = Arc<Mutex<AutoAdmission>>;

pub fn admission_gate() -> AdmissionGate {
    Arc::new(Mutex::new(AutoAdmission {
        phase: AdmissionPhase::Pending,
        deadline: Instant::now() + ADMISSION_TIMEOUT,
    }))
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FillRefusal {
    Full,
    NextRound,
    Cancelled,
}

impl crate::run::ServerOptions {
    /// Validate the complete policy before topology work or listener binding.
    pub(crate) fn validate_bot_policy(&self) -> Result<(), &'static str> {
        match self.bot_policy {
            BotPolicy::Fixed if self.fill_target == 0 => Ok(()),
            BotPolicy::None if self.bots == 0 && self.fill_target == 0 => Ok(()),
            BotPolicy::Auto
                if self.bots == 0
                    && (1..=10).contains(&self.fill_target)
                    && self.authored.is_none()
                    && !self.campaign_run
                    && !self.solo_broadcast
                    && self.match_config.as_ref().is_some_and(|config| config.rules.mutators().is_empty())
                    && matches!(
                        self.match_config.as_ref().map(|config| config.rules.mode()),
                        Some(crate::protocol::GameMode::Tdm | crate::protocol::GameMode::Sabotage)
                    ) => Ok(()),
            _ => Err("invalid bot policy, fixed requires target zero, none requires both counts zero, and auto requires arena TDM/Sabotage, bots zero and target 1 through 10"),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::protocol::{GameMode, Mutator};
    use crate::rules::RuleSet;
    use crate::run::ServerOptions;
    use crate::sim::MatchConfig;

    fn automatic(mode: GameMode) -> ServerOptions {
        ServerOptions {
            bots: 0,
            bot_policy: BotPolicy::Auto,
            fill_target: 4,
            match_config: Some(MatchConfig {
                rules: RuleSet::new(mode, &[], false).unwrap(),
                ..Default::default()
            }),
            ..Default::default()
        }
    }

    #[test]
    fn automatic_configuration_is_exact_and_preserves_fixed_compatibility() {
        assert!(ServerOptions::default().validate_bot_policy().is_ok());
        for mode in [GameMode::Tdm, GameMode::Sabotage] {
            for target in [1, 4, 10] {
                assert!(ServerOptions {
                    fill_target: target,
                    ..automatic(mode)
                }
                .validate_bot_policy()
                .is_ok());
            }
        }
        for policy in [BotPolicy::None, BotPolicy::Fixed] {
            assert!(ServerOptions {
                bot_policy: policy,
                bots: 0,
                fill_target: 0,
                ..Default::default()
            }
            .validate_bot_policy()
            .is_ok());
            assert!(ServerOptions {
                bot_policy: policy,
                fill_target: 4,
                ..Default::default()
            }
            .validate_bot_policy()
            .is_err());
        }
        for target in [0, 11, usize::MAX] {
            assert!(ServerOptions {
                fill_target: target,
                ..automatic(GameMode::Tdm)
            }
            .validate_bot_policy()
            .is_err());
        }
        for bots in [1, 4, 10] {
            assert!(ServerOptions {
                bots,
                ..automatic(GameMode::Tdm)
            }
            .validate_bot_policy()
            .is_err());
        }
        for mode in [GameMode::Ffa, GameMode::Ctf] {
            assert!(automatic(mode).validate_bot_policy().is_err());
        }
        for flag in 0..3 {
            let mut options = automatic(GameMode::Tdm);
            match flag {
                0 => options.solo_broadcast = true,
                1 => options.campaign_run = true,
                _ => {
                    options.authored = Some(crate::maps::AuthoredSource::File("unused.json".into()))
                }
            }
            assert!(options.validate_bot_policy().is_err());
        }
        for mutator in [Mutator::TwoLives, Mutator::GoldenRail, Mutator::RailOnly] {
            let mut options = automatic(GameMode::Tdm);
            options.match_config.as_mut().unwrap().rules =
                RuleSet::new(GameMode::Tdm, &[mutator], false).unwrap();
            assert!(options.validate_bot_policy().is_err());
            options.bot_policy = BotPolicy::Fixed;
            options.fill_target = 0;
            assert!(options.validate_bot_policy().is_ok());
        }
    }
}
