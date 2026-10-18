//! Portable connected ceremonial avenue receipts. Process clocks and live machinery stay out.
use super::*;
use crate::protocol::{M16ObjectiveState, MissionPhase};

#[derive(Debug, Clone, PartialEq, Eq, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct M16Outcome {
    pub ride_started: bool,
    pub green_wave_triggered: bool,
    pub bus_freed: bool,
    pub forecourt_secured: bool,
    pub doors_open: bool,
}

pub(super) fn present<'de, D: serde::Deserializer<'de>>(
    decoder: D,
) -> Result<Option<M16Outcome>, D::Error> {
    M16Outcome::deserialize(decoder).map(Some)
}

impl M16Outcome {
    pub(super) fn capture(state: &M16ObjectiveState, tick: u64) -> Result<Self, &'static str> {
        state.validate(MissionPhase::Departed, tick)?;
        if !state.doors_open || !state.forecourt_secured {
            return Err("completed avenue lacks chamber doors or forecourt secured receipt");
        }
        let outcome = Self {
            ride_started: state.challenges.ride_started,
            green_wave_triggered: state.challenges.green_wave_triggered,
            bus_freed: state.challenges.bus_freed,
            forecourt_secured: state.forecourt_secured,
            doors_open: state.doors_open,
        };
        outcome.validate()?;
        Ok(outcome)
    }

    pub(super) fn validate(&self) -> Result<(), &'static str> {
        if !self.doors_open || !self.forecourt_secured {
            return Err("completed avenue outcome must have doors open and forecourt secured");
        }
        if self.green_wave_triggered && !self.ride_started {
            return Err("avenue outcome green wave precedes ride start");
        }
        Ok(())
    }
}
