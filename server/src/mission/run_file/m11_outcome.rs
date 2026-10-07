//! Completed tender facts. Session clocks become an elapsed receipt on exit.
use super::*;

#[derive(Debug, Clone, PartialEq, Eq, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct M11Outcome {
    pub transfer_released: bool,
    pub records_read: bool,
    pub counter_boarder_blast_kills: u8,
    pub bridge_response_ticks: u64,
}

pub(super) fn present<'de, D: serde::Deserializer<'de>>(
    deserializer: D,
) -> Result<Option<M11Outcome>, D::Error> {
    M11Outcome::deserialize(deserializer).map(Some)
}

impl M11Outcome {
    pub(super) fn capture(
        challenges: &crate::protocol::M11ChallengeState,
    ) -> Result<Self, &'static str> {
        let bridge = challenges
            .bridge_taken_at
            .ok_or("completed M11 lacks bridge arrival")?;
        challenges.validate(bridge)?;
        let start = challenges
            .counter_boarding_started
            .ok_or("completed M11 lacks counter-boarding")?;
        let outcome = Self {
            transfer_released: challenges.transfer_released,
            records_read: challenges.records_read,
            counter_boarder_blast_kills: challenges.counter_boarder_blast_kills,
            bridge_response_ticks: bridge
                .checked_sub(start)
                .ok_or("invalid M11 elapsed clock")?,
        };
        outcome.validate()?;
        Ok(outcome)
    }

    pub(super) fn validate(&self) -> Result<(), &'static str> {
        if self.counter_boarder_blast_kills > 6 || self.bridge_response_ticks > (1_u64 << 53) - 1 {
            return Err("invalid saved tender challenge receipt");
        }
        Ok(())
    }
}
