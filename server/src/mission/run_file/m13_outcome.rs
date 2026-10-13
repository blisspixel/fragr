//! Portable foundry choices and actual arrivals, independent of process ticks.
use super::*;
use crate::protocol::{M13ChallengeState, M13ObjectiveState, M13WorkerResponse, MissionPhase};

#[derive(Debug, Clone, PartialEq, Eq, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct M13Outcome {
    #[serde(
        default,
        deserialize_with = "present_workers",
        skip_serializing_if = "Option::is_none"
    )]
    pub workers: Option<[M13WorkerResponse; 3]>,
    pub workers_arrived: [bool; 3],
    pub hazard_hurt: u64,
    pub supports_cleared: bool,
}

fn present_workers<'de, D: serde::Deserializer<'de>>(
    decoder: D,
) -> Result<Option<[M13WorkerResponse; 3]>, D::Error> {
    <[M13WorkerResponse; 3]>::deserialize(decoder).map(Some)
}

pub(super) fn present<'de, D: serde::Deserializer<'de>>(
    decoder: D,
) -> Result<Option<M13Outcome>, D::Error> {
    M13Outcome::deserialize(decoder).map(Some)
}

impl M13Outcome {
    pub(super) fn capture(state: &M13ObjectiveState) -> Result<Self, &'static str> {
        state.validate(MissionPhase::Departed, state.lift.tick)?;
        let outcome = Self {
            workers: state.challenges.workers,
            workers_arrived: state.challenges.workers_arrived,
            hazard_hurt: state.challenges.hazard_hurt,
            supports_cleared: state.challenges.supports_cleared,
        };
        outcome.validate()?;
        Ok(outcome)
    }

    pub(super) fn validate(&self) -> Result<(), &'static str> {
        if !self.supports_cleared {
            return Err("completed foundry lacks the gallery support-position receipt");
        }
        M13ChallengeState {
            workers: self.workers,
            workers_arrived: self.workers_arrived,
            hazard_hurt: self.hazard_hurt,
            supports_cleared: self.supports_cleared,
        }
        .validate()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::protocol::{
        M13HazardPhase, M13LiftPhase, M13LiftState, M13_OBJECTIVE_IDS, M13_WORKER_RESPONSES,
    };

    #[test]
    fn capture_requires_completed_relay_and_actual_arrived_lift() {
        let mut completed: Vec<_> = M13_OBJECTIVE_IDS.into_iter().map(str::to_owned).collect();
        completed.push("party_departed".into());
        let state = M13ObjectiveState {
            completed,
            current: None,
            challenges: M13ChallengeState {
                workers: Some(M13_WORKER_RESPONSES),
                workers_arrived: [true, false, false],
                hazard_hurt: 19,
                supports_cleared: true,
            },
            relay_disabled: true,
            overseer_surrendered: true,
            worker_feet: [[0.0; 3]; 3],
            lift: M13LiftState {
                phase: M13LiftPhase::Arrived,
                top: 14.6,
                tick: 100,
                returning: false,
            },
            hazard_phase: M13HazardPhase::Idle,
        };
        let receipt = M13Outcome::capture(&state).unwrap();
        assert_eq!(receipt.workers_arrived, [true, false, false]);
        assert_eq!(receipt.hazard_hurt, 19);
        let mut incomplete = state.clone();
        incomplete.relay_disabled = false;
        assert!(M13Outcome::capture(&incomplete).is_err());
        incomplete = state.clone();
        incomplete.lift.phase = M13LiftPhase::Moving;
        assert!(M13Outcome::capture(&incomplete).is_err());
        incomplete = state;
        incomplete.completed.pop();
        assert!(M13Outcome::capture(&incomplete).is_err());
    }
}
