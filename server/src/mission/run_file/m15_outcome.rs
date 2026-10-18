//! Portable connected stadium bout receipts. Process clocks and live machinery stay out.
use super::*;
use crate::protocol::{M15ObjectiveState, MissionPhase};

#[derive(Debug, Clone, PartialEq, Eq, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct M15Outcome {
    pub pen_armed: bool,
    pub blade_wave_won: bool,
    pub entrants_preserved: bool,
    pub broadcast_taken: bool,
    pub armed_entrants: Vec<u8>,
    pub fallen_entrants: Vec<u8>,
}

pub(super) fn present<'de, D: serde::Deserializer<'de>>(
    decoder: D,
) -> Result<Option<M15Outcome>, D::Error> {
    M15Outcome::deserialize(decoder).map(Some)
}

impl M15Outcome {
    pub(super) fn capture(state: &M15ObjectiveState, tick: u64) -> Result<Self, &'static str> {
        state.validate(MissionPhase::Departed, tick)?;
        if !state.gates_open || !state.broadcast_taken {
            return Err("completed stadium bout lacks ceremonial gate or broadcast receipt");
        }
        let outcome = Self {
            pen_armed: state.challenges.pen_armed,
            blade_wave_won: state.challenges.blade_wave_won,
            entrants_preserved: state.challenges.entrants_preserved,
            broadcast_taken: state.broadcast_taken,
            armed_entrants: state.armed_entrants.clone(),
            fallen_entrants: state.fallen_entrants.clone(),
        };
        outcome.validate()?;
        Ok(outcome)
    }

    pub(super) fn validate(&self) -> Result<(), &'static str> {
        if !self.pen_armed || !self.broadcast_taken {
            return Err("completed stadium bout lacks required receipts");
        }
        if self.blade_wave_won && !self.pen_armed {
            return Err("invalid M15 challenge progression");
        }
        Ok(())
    }
}
