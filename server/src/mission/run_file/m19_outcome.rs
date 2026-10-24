//! Portable completed Planned Works receipts. Process clocks, positions and
//! live machines stay out; only the attempt's actual brief facts are kept.
use super::*;
use crate::protocol::{M19ObjectiveState, MissionPhase};

#[derive(Debug, Clone, PartialEq, Eq, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct M19Outcome {
    pub crossing_cleared: bool,
    pub paver_interrupted: bool,
    pub strip_struck: bool,
    pub latch_departed: bool,
}

impl M19Outcome {
    pub(super) fn capture(state: &M19ObjectiveState, tick: u64) -> Result<Self, &'static str> {
        state.validate(MissionPhase::Departed, tick)?;
        let outcome = Self {
            crossing_cleared: state.challenges.crossing_cleared,
            paver_interrupted: state.challenges.paver_interrupted,
            strip_struck: state.challenges.strip_struck,
            latch_departed: state.latch_departed,
        };
        outcome.validate()?;
        Ok(outcome)
    }

    /// A completed run crossed the concourse and saw Latch go.
    pub(super) fn validate(&self) -> Result<(), &'static str> {
        if !self.crossing_cleared || !self.latch_departed {
            return Err("completed works outcome lacks its required crossing and departure");
        }
        Ok(())
    }
}
