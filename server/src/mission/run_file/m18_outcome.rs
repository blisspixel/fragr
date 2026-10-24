//! Portable connected All Systems Normal receipts. Process clocks and live machinery stay out.
use super::*;
use crate::protocol::{M18ObjectiveState, MissionPhase};

#[derive(Debug, Clone, PartialEq, Eq, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct M18Outcome {
    pub aid_delivered: bool,
    pub square_defended: bool,
    pub collector_neutralized: bool,
    pub overlook_witnessed: bool,
    pub concourse_secured: bool,
}

impl M18Outcome {
    pub(super) fn capture(state: &M18ObjectiveState, tick: u64) -> Result<Self, &'static str> {
        state.validate(MissionPhase::Departed, tick)?;
        if !state.concourse_secured {
            return Err("completed recovery concourse lacks concourse secured receipt");
        }
        let outcome = Self {
            aid_delivered: state.challenges.aid_delivered,
            square_defended: state.challenges.square_defended,
            collector_neutralized: state.challenges.collector_neutralized,
            overlook_witnessed: state.challenges.overlook_witnessed,
            concourse_secured: state.challenges.concourse_secured,
        };
        outcome.validate()?;
        Ok(outcome)
    }

    pub(super) fn validate(&self) -> Result<(), &'static str> {
        if !self.concourse_secured {
            return Err("completed recovery outcome must have concourse secured");
        }
        if self.concourse_secured && !self.square_defended {
            return Err("recovery outcome concourse secured precedes square defense");
        }
        Ok(())
    }
}
