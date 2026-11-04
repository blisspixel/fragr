use super::WeaponType;
use serde::{Deserialize, Deserializer, Serialize};
use uuid::Uuid;

/// Private physical aim facts, independent of finite inventory or numbered input.
/// The angle is the next shot's half cone, in millionths of a radian.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct AimState {
    pub player_id: Uuid,
    pub tick: u64,
    pub weapon: WeaponType,
    pub cone_microradians: u32,
    #[serde(
        default,
        deserialize_with = "deadline",
        skip_serializing_if = "Option::is_none"
    )]
    pub raise_ready_at: Option<u64>,
}

impl AimState {
    pub const MAX_CONE: u32 = 190_000;

    pub fn validate_for(
        &self,
        owner: Option<Uuid>,
        previous: Option<&Self>,
    ) -> Result<(), &'static str> {
        if owner != Some(self.player_id) {
            return Err("aim belongs to another participant");
        }
        const MAX_EXACT_JSON_INTEGER: u64 = (1_u64 << 53) - 1;
        if self.tick > MAX_EXACT_JSON_INTEGER
            || self
                .raise_ready_at
                .is_some_and(|ready| ready > MAX_EXACT_JSON_INTEGER)
        {
            return Err("invalid aim tick");
        }
        if self.cone_microradians > Self::MAX_CONE {
            return Err("invalid aim cone");
        }
        if self.raise_ready_at.is_some_and(|ready| {
            ready <= self.tick || ready - self.tick > u64::from(self.weapon.raise_ticks())
        }) {
            return Err("invalid weapon raise deadline");
        }
        if previous.is_some_and(|old| old.tick > self.tick) {
            return Err("aim tick moved backwards");
        }
        Ok(())
    }

    pub(crate) fn same_facts(&self, previous: &Self) -> bool {
        self.player_id == previous.player_id
            && self.weapon == previous.weapon
            && self.cone_microradians == previous.cone_microradians
            && self.raise_ready_at == previous.raise_ready_at
    }
}

fn deadline<'de, D: Deserializer<'de>>(deserializer: D) -> Result<Option<u64>, D::Error> {
    u64::deserialize(deserializer).map(Some)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn aim_refuses_wrong_owner_bad_cones_deadlines_and_stale_ticks() {
        let owner = Uuid::from_u128(1);
        let valid = AimState {
            player_id: owner,
            tick: 20,
            weapon: WeaponType::Rail,
            cone_microradians: 12_000,
            raise_ready_at: Some(27),
        };
        assert!(valid.validate_for(Some(owner), None).is_ok());
        assert!(valid.validate_for(None, None).is_err());
        assert!(valid.validate_for(Some(Uuid::nil()), None).is_err());
        let mut bad = valid.clone();
        bad.cone_microradians = AimState::MAX_CONE + 1;
        assert!(bad.validate_for(Some(owner), None).is_err());
        for deadline in [0, 20, 28, u64::MAX] {
            bad = valid.clone();
            bad.raise_ready_at = Some(deadline);
            assert!(bad.validate_for(Some(owner), None).is_err());
        }
        bad = valid.clone();
        bad.tick = u64::MAX;
        bad.raise_ready_at = None;
        assert!(bad.validate_for(Some(owner), None).is_err());
        bad = valid.clone();
        bad.tick -= 1;
        bad.raise_ready_at = None;
        assert!(bad.validate_for(Some(owner), Some(&valid)).is_err());
        let mut later = valid.clone();
        later.tick += 1;
        assert!(later.same_facts(&valid));
        later.raise_ready_at = None;
        assert!(!later.same_facts(&valid));
        let wire = serde_json::to_value(&valid).unwrap();
        assert_eq!(
            serde_json::from_value::<AimState>(wire.clone()).unwrap(),
            valid
        );
        let mut null_deadline = wire.clone();
        null_deadline["raise_ready_at"] = serde_json::Value::Null;
        assert!(serde_json::from_value::<AimState>(null_deadline).is_err());
        let mut unknown = wire;
        unknown["unknown"] = true.into();
        assert!(serde_json::from_value::<AimState>(unknown).is_err());
    }
}
