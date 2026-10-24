//! Portable launch-work receipts. Process clocks and live machinery stay out.
use super::*;
use crate::protocol::{M14ObjectiveState, MissionPhase};

#[derive(Debug, Clone, PartialEq, Eq, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct M14Outcome {
    pub depot_secured: bool,
    pub walker_disabled: bool,
    pub jeep_preserved: bool,
    pub on_foot: bool,
}

impl M14Outcome {
    pub(super) fn capture(state: &M14ObjectiveState, tick: u64) -> Result<Self, &'static str> {
        state.validate(MissionPhase::Departed, tick)?;
        if !state.machine_fallen {
            return Err("completed launch works lack the actual fallen-world receipt");
        }
        let outcome = Self {
            depot_secured: state.challenges.depot_secured,
            walker_disabled: state.challenges.walker_disabled,
            jeep_preserved: state.challenges.jeep_preserved,
            on_foot: state.challenges.on_foot,
        };
        outcome.validate()?;
        Ok(outcome)
    }

    pub(super) fn validate(&self) -> Result<(), &'static str> {
        if !self.depot_secured || !self.walker_disabled {
            return Err("completed launch works lack their required resolved receipts");
        }
        Ok(())
    }
}
