//! Versioned participant records. Ratios are derived from counts by presenters.
use super::{CampaignRules, CampaignRunState, MissionId, Role, WeaponType};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

pub const RECORD_VERSION: u32 = 1;
pub const RECORD_TICKS_PER_SECOND: u32 = 20;
const MAX_EXACT_JSON_INTEGER: u64 = (1_u64 << 53) - 1;

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn retained_weapon_counts_preserve_legacy_indices_and_new_melee_effort() {
        let mut counts = CombatCounts {
            alive_ticks: 10,
            ..Default::default()
        };
        counts.weapons[WeaponType::Rail.index()].attacks = 2;
        let legacy = serde_json::to_value(&counts).unwrap();
        assert_eq!(legacy["weapons"].as_array().unwrap().len(), 5);
        assert_eq!(
            serde_json::from_value::<CombatCounts>(legacy.clone()).unwrap(),
            counts
        );
        counts.weapons[WeaponType::Shiv.index()].attacks = 3;
        counts.validate().unwrap();
        let current = serde_json::to_value(&counts).unwrap();
        assert_eq!(current["weapons"].as_array().unwrap().len(), 6);
        assert_eq!(
            current["weapons"][WeaponType::Rail.index()],
            legacy["weapons"][WeaponType::Rail.index()]
        );
        assert_eq!(
            serde_json::from_value::<CombatCounts>(current.clone()).unwrap(),
            counts
        );
        for length in [0, 4, 7] {
            let mut malformed = current.clone();
            let slots = malformed["weapons"].as_array_mut().unwrap();
            let slot = slots[0].clone();
            slots.resize(length, slot);
            assert!(serde_json::from_value::<CombatCounts>(malformed).is_err());
        }
        let mut malformed = current;
        malformed["weapons"][5]["unexpected"] = true.into();
        assert!(serde_json::from_value::<CombatCounts>(malformed).is_err());
    }
}

#[derive(Debug, Default, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct WeaponCounts {
    pub attacks: u64,
    pub damaging_attacks: u64,
    pub kills: u64,
    pub hp_damage: u64,
    pub armor_damage: u64,
}

#[derive(Debug, Default, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct CombatCounts {
    /// Ticks alive and admitted to an active simulation frame, including death's frame.
    pub alive_ticks: u64,
    pub deaths: u64,
    pub hp_lost: u64,
    pub armor_lost: u64,
    pub dry_triggers: u64,
    /// Indexed by WeaponType::index(), in WeaponType::ALL order.
    #[serde(with = "weapon_counts")]
    pub weapons: [WeaponCounts; WeaponType::ALL.len()],
}

/// Preserve the five original slots on old arcade records. The sixth slot is
/// appended only when used; deserializing history never changes an old index.
mod weapon_counts {
    use super::*;
    use serde::de::{Error, SeqAccess, Visitor};

    pub fn serialize<S: serde::Serializer>(
        counts: &[WeaponCounts; WeaponType::ALL.len()],
        serializer: S,
    ) -> Result<S::Ok, S::Error> {
        let length = if counts[WeaponType::Shiv.index()] == WeaponCounts::default() {
            5
        } else {
            WeaponType::ALL.len()
        };
        counts[..length].serialize(serializer)
    }

    pub fn deserialize<'de, D: serde::Deserializer<'de>>(
        deserializer: D,
    ) -> Result<[WeaponCounts; WeaponType::ALL.len()], D::Error> {
        struct Counts;
        impl<'de> Visitor<'de> for Counts {
            type Value = [WeaponCounts; WeaponType::ALL.len()];
            fn expecting(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                f.write_str("five legacy or six current weapon counters")
            }
            fn visit_seq<A: SeqAccess<'de>>(self, mut seq: A) -> Result<Self::Value, A::Error> {
                let mut counts = [WeaponCounts::default(); WeaponType::ALL.len()];
                for (index, count) in counts.iter_mut().enumerate() {
                    match seq.next_element()? {
                        Some(value) => *count = value,
                        None if index == 5 => return Ok(counts),
                        None => return Err(A::Error::invalid_length(index, &self)),
                    }
                }
                if seq.next_element::<serde::de::IgnoredAny>()?.is_some() {
                    return Err(A::Error::invalid_length(7, &self));
                }
                Ok(counts)
            }
        }
        deserializer.deserialize_seq(Counts)
    }
}

impl CombatCounts {
    pub fn weapon(&self, weapon: WeaponType) -> &WeaponCounts {
        &self.weapons[weapon.index()]
    }

    pub fn attacks(&self) -> u64 {
        self.weapons.iter().map(|weapon| weapon.attacks).sum()
    }

    pub fn kills(&self) -> u64 {
        self.weapons.iter().map(|weapon| weapon.kills).sum()
    }

    pub fn validate(&self) -> Result<(), &'static str> {
        let mut counts = vec![
            self.alive_ticks,
            self.deaths,
            self.hp_lost,
            self.armor_lost,
            self.dry_triggers,
        ];
        for weapon in &self.weapons {
            counts.extend([
                weapon.attacks,
                weapon.damaging_attacks,
                weapon.kills,
                weapon.hp_damage,
                weapon.armor_damage,
            ]);
        }
        if counts.iter().any(|count| *count > MAX_EXACT_JSON_INTEGER) {
            return Err("record count is not an exact JSON integer");
        }
        for column in 0..5 {
            let sum: u64 = self
                .weapons
                .iter()
                .map(|weapon| {
                    [
                        weapon.attacks,
                        weapon.damaging_attacks,
                        weapon.kills,
                        weapon.hp_damage,
                        weapon.armor_damage,
                    ][column]
                })
                .sum();
            if sum > MAX_EXACT_JSON_INTEGER {
                return Err("record weapon total is not an exact JSON integer");
            }
        }
        if self.attacks() > self.alive_ticks
            || self.deaths > self.alive_ticks
            || self.dry_triggers > self.alive_ticks
        {
            return Err("record contains more actions than active frames");
        }
        if self.weapons.iter().any(|weapon| {
            weapon.kills > weapon.damaging_attacks || weapon.damaging_attacks > weapon.attacks
        }) {
            return Err("inconsistent attack counts");
        }
        Ok(())
    }

    pub fn contains(&self, other: &Self) -> bool {
        self.alive_ticks >= other.alive_ticks
            && self.deaths >= other.deaths
            && self.hp_lost >= other.hp_lost
            && self.armor_lost >= other.armor_lost
            && self.dry_triggers >= other.dry_triggers
            && self.weapons.iter().zip(&other.weapons).all(|(a, b)| {
                a.attacks >= b.attacks
                    && a.damaging_attacks >= b.damaging_attacks
                    && a.kills >= b.kills
                    && a.hp_damage >= b.hp_damage
                    && a.armor_damage >= b.armor_damage
            })
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "snake_case", deny_unknown_fields)]
pub enum RecordScope {
    Arena {
        round: u32,
    },
    Mission {
        mission: MissionId,
        attempt: u32,
        rules: CampaignRules,
        run: Option<CampaignRunState>,
    },
    Practice {
        round: u32,
    },
}

impl RecordScope {
    pub fn attempt(&self) -> u32 {
        match self {
            Self::Mission { attempt, .. } => *attempt,
            _ => 1,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum RecordStatus {
    Active,
    Continue,
    Complete,
    Failed,
    Abandoned,
}

impl RecordStatus {
    pub fn terminal(self) -> bool {
        matches!(self, Self::Complete | Self::Failed | Self::Abandoned)
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct PlayerRecord {
    pub version: u32,
    pub session_id: Uuid,
    pub player_id: Uuid,
    /// Session-local round, stable throughout all mission attempts.
    pub round: u32,
    pub tick: u64,
    pub entered_at: u64,
    pub round_started_at: u64,
    pub ticks_per_second: u32,
    pub map_id: u32,
    pub map_name: String,
    pub role: Role,
    pub scope: RecordScope,
    pub status: RecordStatus,
    pub total: CombatCounts,
    pub attempt: CombatCounts,
}

impl PlayerRecord {
    pub fn validate_for(
        &self,
        owner: Option<Uuid>,
        previous: Option<&Self>,
    ) -> Result<(), &'static str> {
        if self.version != RECORD_VERSION
            || self.ticks_per_second != RECORD_TICKS_PER_SECOND
            || owner != Some(self.player_id)
            || self.role == Role::Spectator
            || self.round == 0
            || self.tick > MAX_EXACT_JSON_INTEGER
            || self.entered_at > self.tick
            || self.round_started_at > self.entered_at
            || self.map_id == 0
            || self.map_name.is_empty()
            || self.map_name.chars().count() > 128
        {
            return Err("invalid participant record identity or version");
        }
        self.total.validate()?;
        self.attempt.validate()?;
        if self.total.alive_ticks > self.tick - self.entered_at {
            return Err("record active time exceeds participation window");
        }
        if !self.total.contains(&self.attempt) {
            return Err("attempt exceeds total effort");
        }
        match &self.scope {
            RecordScope::Arena { round } | RecordScope::Practice { round }
                if *round != self.round || self.attempt != self.total =>
            {
                return Err("inconsistent round record");
            }
            RecordScope::Mission {
                attempt,
                rules,
                run,
                ..
            } => {
                if *attempt == 0 || rules.revision != super::CAMPAIGN_RULES_REVISION {
                    return Err("unsupported mission record");
                }
                if let Some(run) = run {
                    run.validate_attempt(*attempt)?;
                    if self.status != run.status.into() {
                        return Err("inconsistent solo record");
                    }
                }
            }
            _ => {}
        }
        if let Some(old) = previous {
            if self.session_id != old.session_id || self.player_id != old.player_id {
                return Err("record identity changed within a connection");
            }
            if self.tick < old.tick || self.round < old.round {
                return Err("record moved backwards");
            }
            if self.round == old.round
                && (self.map_id != old.map_id
                    || self.entered_at != old.entered_at
                    || self.round_started_at != old.round_started_at
                    || self.map_name != old.map_name
                    || self.role != old.role
                    || !self.scope.follows(&old.scope)
                    || !self.total.contains(&old.total)
                    || self.scope.attempt() < old.scope.attempt()
                    || (self.scope.attempt() == old.scope.attempt()
                        && !self.attempt.contains(&old.attempt))
                    || (old.status.terminal()
                        && (self.status != old.status
                            || self.total != old.total
                            || self.attempt != old.attempt
                            || self.scope != old.scope)))
            {
                return Err("record regressed or rewrote a terminal result");
            }
        }
        Ok(())
    }
}

impl RecordScope {
    fn follows(&self, old: &Self) -> bool {
        match (self, old) {
            (Self::Arena { round: a }, Self::Arena { round: b })
            | (Self::Practice { round: a }, Self::Practice { round: b }) => a == b,
            (
                Self::Mission {
                    mission,
                    rules,
                    run,
                    ..
                },
                Self::Mission {
                    mission: old_mission,
                    rules: old_rules,
                    run: old_run,
                    ..
                },
            ) => {
                mission == old_mission
                    && rules == old_rules
                    && match (run, old_run) {
                        (None, None) => true,
                        (Some(run), Some(old)) => {
                            run.id == old.id && run.continues <= old.continues
                        }
                        _ => false,
                    }
            }
            _ => false,
        }
    }
}

impl From<super::CampaignRunStatus> for RecordStatus {
    fn from(status: super::CampaignRunStatus) -> Self {
        match status {
            super::CampaignRunStatus::Playing => Self::Active,
            super::CampaignRunStatus::Continue => Self::Continue,
            super::CampaignRunStatus::Complete => Self::Complete,
            super::CampaignRunStatus::Failed => Self::Failed,
            super::CampaignRunStatus::Abandoned => Self::Abandoned,
        }
    }
}
