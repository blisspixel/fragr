//! Portable connected Forever Office receipts. Process clocks and live machinery stay out.
use super::*;
use crate::protocol::{M17ObjectiveState, MissionPhase};

#[derive(Debug, Clone, PartialEq, Eq, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct M17Outcome {
    pub approach_breached: bool,
    pub kessel_secured: bool,
    pub core_unsealed: bool,
    pub core_defeated: bool,
    pub voss_captured: bool,
}

pub(super) fn present<'de, D: serde::Deserializer<'de>>(
    decoder: D,
) -> Result<Option<M17Outcome>, D::Error> {
    M17Outcome::deserialize(decoder).map(Some)
}

impl M17Outcome {
    pub(super) fn capture(state: &M17ObjectiveState, tick: u64) -> Result<Self, &'static str> {
        state.validate(MissionPhase::Departed, tick)?;
        if !state.core_unsealed || !state.voss_captured {
            return Err("completed office lacks core unsealed or Voss captured receipt");
        }
        let outcome = Self {
            approach_breached: state.challenges.approach_breached,
            kessel_secured: state.challenges.kessel_secured,
            core_unsealed: state.core_unsealed,
            core_defeated: state.challenges.core_defeated,
            voss_captured: state.challenges.voss_captured,
        };
        outcome.validate()?;
        Ok(outcome)
    }

    pub(super) fn validate(&self) -> Result<(), &'static str> {
        if !self.core_unsealed || !self.voss_captured {
            return Err("completed office outcome must have core unsealed and Voss captured");
        }
        if self.core_defeated && !self.approach_breached {
            return Err("office outcome core defeat precedes approach breach");
        }
        if self.voss_captured && !self.core_defeated {
            return Err("office outcome Voss capture precedes core defeat");
        }
        Ok(())
    }
}
