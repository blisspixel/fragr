//! Versioned solo-run document. Disk transport is local-only and separate.
use crate::inventory::SavedEquipment;
use crate::protocol::{CampaignRules, MissionId, CAMPAIGN_CONTINUES, CAMPAIGN_RULES_REVISION};
use crate::sim::PLAYER_MAX_ARMOR;
use serde::{Deserialize, Serialize};
use uuid::Uuid;

mod store;

pub(super) const RUN_FILE_VERSION: u32 = 1;
const NEXT_MISSION: &str = "persons_unknown";

#[derive(Debug, Clone, PartialEq, Eq, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub(super) struct SavedEntry {
    pub hp: i32,
    pub armor: i32,
    pub equipment: SavedEquipment,
}

impl SavedEntry {
    fn validate(&self) -> Result<(), &'static str> {
        if !(1..=100).contains(&self.hp) || !(0..=PLAYER_MAX_ARMOR).contains(&self.armor) {
            return Err("invalid campaign entry health or armor");
        }
        self.equipment.validate()
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Deserialize, Serialize)]
#[serde(tag = "kind", rename_all = "snake_case", deny_unknown_fields)]
pub(super) enum SavedStep {
    MissionEntry {
        mission: MissionId,
        entry: SavedEntry,
    },
    PendingContinue {
        mission: MissionId,
        entry: SavedEntry,
    },
    Failed {
        mission: MissionId,
        entry: SavedEntry,
    },
    AwaitingMission {
        completed_mission: MissionId,
        next_mission: String,
        exit: SavedEntry,
    },
}

#[derive(Debug, Clone, PartialEq, Eq, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub(super) struct RunDocument {
    pub version: u32,
    pub id: Uuid,
    pub starting_continues: u8,
    pub remaining_continues: u8,
    pub rules: CampaignRules,
    pub content_sha256: [u8; 32],
    pub step: SavedStep,
}

impl RunDocument {
    pub fn validate(&self, content_sha256: [u8; 32]) -> Result<(), &'static str> {
        if self.version != RUN_FILE_VERSION
            || self.id.is_nil()
            || self.starting_continues != CAMPAIGN_CONTINUES
            || self.remaining_continues > self.starting_continues
            || self.rules.revision != CAMPAIGN_RULES_REVISION
            || self.content_sha256 != content_sha256
        {
            return Err("incompatible campaign run identity, rules, or content");
        }
        match &self.step {
            SavedStep::MissionEntry { mission, entry } => self.validate_mission(*mission, entry),
            SavedStep::PendingContinue { mission, entry } => {
                if self.remaining_continues == 0 {
                    return Err("pending continue has no allowance");
                }
                self.validate_mission(*mission, entry)
            }
            SavedStep::Failed { mission, entry } => {
                if self.remaining_continues != 0 {
                    return Err("failed run retains a continue");
                }
                self.validate_mission(*mission, entry)
            }
            SavedStep::AwaitingMission {
                completed_mission,
                next_mission,
                exit,
            } => {
                if *completed_mission != MissionId::RecallNotice || next_mission != NEXT_MISSION {
                    return Err("unsupported saved campaign transition");
                }
                exit.validate()
            }
        }
    }

    fn validate_mission(&self, mission: MissionId, entry: &SavedEntry) -> Result<(), &'static str> {
        if mission != MissionId::RecallNotice {
            return Err("unsupported saved mission");
        }
        entry.validate()
    }

    pub fn attempt(&self) -> u32 {
        u32::from(self.starting_continues - self.remaining_continues) + 1
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::inventory::Inventory;
    use crate::protocol::{CampaignDifficulty, EquipmentPolicy, WeaponType};

    fn document() -> RunDocument {
        let inventory = Inventory::new(EquipmentPolicy::Discovery);
        RunDocument {
            version: RUN_FILE_VERSION,
            id: Uuid::from_u128(1),
            starting_continues: CAMPAIGN_CONTINUES,
            remaining_continues: CAMPAIGN_CONTINUES,
            rules: CampaignRules::new(CampaignDifficulty::Standard),
            content_sha256: [5; 32],
            step: SavedStep::MissionEntry {
                mission: MissionId::RecallNotice,
                entry: SavedEntry {
                    hp: 100,
                    armor: 0,
                    equipment: inventory.saved_equipment(WeaponType::Fists).unwrap(),
                },
            },
        }
    }

    #[test]
    fn run_document_round_trips_and_rejects_invalid_transitions() {
        let original = document();
        let bytes = serde_json::to_vec(&original).unwrap();
        let decoded: RunDocument = serde_json::from_slice(&bytes).unwrap();
        assert_eq!(decoded, original);
        decoded.validate([5; 32]).unwrap();
        assert_eq!(decoded.attempt(), 1);
        let mut pending = original.clone();
        pending.remaining_continues = 1;
        let SavedStep::MissionEntry { mission, entry } = original.step else {
            panic!("fixture must start at mission entry");
        };
        pending.step = SavedStep::PendingContinue { mission, entry };
        pending.validate([5; 32]).unwrap();
        assert_eq!(pending.attempt(), 3);
        pending.remaining_continues = 0;
        assert!(pending.validate([5; 32]).is_err());
        pending.step = SavedStep::Failed {
            mission,
            entry: match pending.step {
                SavedStep::PendingContinue { entry, .. } => entry,
                _ => unreachable!(),
            },
        };
        pending.validate([5; 32]).unwrap();
        pending.remaining_continues = 1;
        assert!(pending.validate([5; 32]).is_err());
    }

    #[test]
    fn completed_m01_is_a_distinct_pending_m02_boundary() {
        let mut saved = document();
        let SavedStep::MissionEntry { mission, entry } = saved.step else {
            panic!("fixture must start at mission entry");
        };
        saved.step = SavedStep::AwaitingMission {
            completed_mission: mission,
            next_mission: NEXT_MISSION.into(),
            exit: entry,
        };
        saved.validate([5; 32]).unwrap();
        assert!(saved.validate([6; 32]).is_err());
        if let SavedStep::AwaitingMission { next_mission, .. } = &mut saved.step {
            *next_mission = "recall_notice".into();
        }
        assert!(saved.validate([5; 32]).is_err());
        let mut value = serde_json::to_value(&saved).unwrap();
        value["unexpected"] = true.into();
        assert!(serde_json::from_value::<RunDocument>(value).is_err());
    }
}
