//! Portable completed habitat facts, independent of a process's tick origin.
use super::*;

#[derive(Debug, Clone, PartialEq, Eq, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct M12Outcome {
    pub shelter_opened: bool,
    pub workers_released: bool,
    pub pump_health: [u16; 2],
    pub assessor_wreck_union_kills: u8,
    pub pumps_intact_at_route_secure: bool,
}

pub(super) fn present<'de, D: serde::Deserializer<'de>>(
    decoder: D,
) -> Result<Option<M12Outcome>, D::Error> {
    M12Outcome::deserialize(decoder).map(Some)
}

impl M12Outcome {
    pub(super) fn capture(
        challenges: &crate::protocol::M12ChallengeState,
        completed_at: u64,
    ) -> Result<Self, &'static str> {
        challenges.validate(completed_at)?;
        challenges
            .shelter_route_secured_at
            .ok_or("completed M12 lacks the shelter-route receipt")?;
        let outcome = Self {
            shelter_opened: challenges.shelter_opened,
            workers_released: challenges.workers_released,
            pump_health: challenges.pump_health,
            assessor_wreck_union_kills: challenges.assessor_wreck_union_kills,
            pumps_intact_at_route_secure: challenges.pumps_intact_at_route_secure(),
        };
        outcome.validate()?;
        Ok(outcome)
    }

    pub(super) fn validate(&self) -> Result<(), &'static str> {
        if self.pump_health.iter().any(|health| *health > 100)
            || self.assessor_wreck_union_kills > 3
            || (!self.pumps_intact_at_route_secure && self.pump_health == [100, 100])
        {
            return Err("invalid saved habitat challenge receipt");
        }
        Ok(())
    }
}
