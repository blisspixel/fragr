//! Versioned solo-run document. Disk transport is local-only and separate.
use crate::inventory::{Inventory, SavedEquipment};
use crate::protocol::{
    BodyKind, CampaignRules, CampaignRunStatus, EquipmentPolicy, MissionId, WeaponType,
    CAMPAIGN_CONTINUES, CAMPAIGN_RULES_REVISION,
};
use crate::sim::{GameState, Player, PLAYER_MAX_ARMOR, PLAYER_MAX_HP};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

mod legacy;
pub(crate) mod store;
use legacy::{
    RunDocumentV10, RunDocumentV2, RunDocumentV3, RunDocumentV4, RunDocumentV5, RunDocumentV6,
    RunDocumentV7, RunDocumentV8, RunDocumentV9,
};

/// Version 11 freezes historical gun ownership while preparing Repeater.
/// Actual archive choices and unknown v9 history remain unchanged.
pub(super) const RUN_FILE_VERSION: u32 = 11;
const M02_MISSION: &str = "persons_unknown";
const M03_MISSION: &str = "scheduled_service";
const M04_MISSION: &str = "notice_to_vacate";
const M05_MISSION: &str = "no_forwarding_address";
const M06_MISSION: &str = "port_of_entry";
const M07_MISSION: &str = "declared_goods";
const M09_MISSION: &str = "passenger_manifest";
const M10_MISSION: &str = "common_carrier";
const M08_MISSION: &str = "custodian_of_record";

pub(crate) use crate::protocol::M08Outcome;

#[derive(Debug, Clone, PartialEq, Eq, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct M06Outcome {
    pub prisoner_route_marked: bool,
}

/// Completed yard choices remain immutable throughout M04.
#[derive(Debug, Clone, PartialEq, Eq, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct M03Outcome {
    pub liberated_cars: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct M04Outcome {
    pub rescued_patients: Vec<String>,
    pub photos_completed: u32,
}

#[derive(Debug, Clone, PartialEq, Eq, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct M05Outcome {
    pub released_workers: Vec<String>,
    pub evacuated_workers: Vec<String>,
}

impl M05Outcome {
    fn validate(&self) -> Result<(), &'static str> {
        let mut seen = std::collections::HashSet::new();
        if !matches!(self.released_workers.len(), 0 | 3)
            || self.released_workers.iter().any(|id| {
                !matches!(
                    id.as_str(),
                    "splice" | "workshop_agent_a" | "workshop_agent_b"
                ) || !seen.insert(id)
            })
        {
            return Err("invalid saved workshop rescue");
        }
        seen.clear();
        if self.evacuated_workers.len() > self.released_workers.len()
            || self
                .evacuated_workers
                .iter()
                .any(|id| !self.released_workers.contains(id) || !seen.insert(id))
        {
            return Err("saved evacuation is not a subset of released workers");
        }
        Ok(())
    }
}

impl M04Outcome {
    fn validate(&self) -> Result<(), &'static str> {
        M03Outcome {
            liberated_cars: self.rescued_patients.clone(),
        }
        .validate()?;
        if self.photos_completed > 1_000_000 {
            return Err("invalid saved photograph count");
        }
        Ok(())
    }
}

impl M03Outcome {
    fn validate(&self) -> Result<(), &'static str> {
        let mut seen = std::collections::HashSet::new();
        if self.liberated_cars.len() > 4
            || self.liberated_cars.iter().any(|id| {
                id.is_empty()
                    || id.len() > 64
                    || !id
                        .bytes()
                        .all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == b'_')
                    || !seen.insert(id)
            })
        {
            return Err("invalid saved recall-car outcome");
        }
        Ok(())
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct SavedEntry {
    pub hp: i32,
    pub armor: i32,
    pub equipment: SavedEquipment,
}

impl SavedEntry {
    pub fn initial() -> Self {
        Self {
            hp: PLAYER_MAX_HP,
            armor: 0,
            equipment: Inventory::new(EquipmentPolicy::Discovery)
                .saved_equipment(WeaponType::Fists)
                .expect("initial discovery equipment is valid"),
        }
    }

    pub fn from_player(player: &Player) -> Result<Self, &'static str> {
        let entry = Self {
            hp: player.hp,
            armor: player.armor,
            equipment: player
                .inventory
                .saved_equipment(player.weapon)
                .ok_or("player equipment cannot be saved")?,
        };
        entry.validate()?;
        Ok(entry)
    }

    fn validate(&self) -> Result<(), &'static str> {
        if !(1..=PLAYER_MAX_HP).contains(&self.hp) || !(0..=PLAYER_MAX_ARMOR).contains(&self.armor)
        {
            return Err("invalid campaign entry health or armor");
        }
        self.equipment.validate()
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Deserialize, Serialize)]
#[serde(tag = "kind", rename_all = "snake_case", deny_unknown_fields)]
pub(crate) enum SavedStep {
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
    Abandoned {
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
pub(crate) struct RunDocument {
    pub version: u32,
    pub id: Uuid,
    pub starting_continues: u8,
    pub remaining_continues: u8,
    pub level_start_continues: u8,
    pub body: Option<BodyKind>,
    pub rules: CampaignRules,
    pub content_sha256: [u8; 32],
    pub step: SavedStep,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub m03_outcome: Option<M03Outcome>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub m04_outcome: Option<M04Outcome>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub m05_outcome: Option<M05Outcome>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub m06_outcome: Option<M06Outcome>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub m08_outcome: Option<M08Outcome>,
}

impl RunDocument {
    pub fn stage_mission(&self) -> MissionId {
        match &self.step {
            SavedStep::MissionEntry { mission, .. }
            | SavedStep::PendingContinue { mission, .. }
            | SavedStep::Failed { mission, .. }
            | SavedStep::Abandoned { mission, .. } => *mission,
            SavedStep::AwaitingMission {
                completed_mission, ..
            } => *completed_mission,
        }
    }

    #[cfg(test)]
    pub fn promote_m02(&self, m02_hash: [u8; 32]) -> Result<Self, &'static str> {
        self.promote_next(MissionId::PersonsUnknown, m02_hash)
    }

    pub fn promote_next(
        &self,
        mission: MissionId,
        content_hash: [u8; 32],
    ) -> Result<Self, &'static str> {
        let (previous, next) = match mission {
            MissionId::PersonsUnknown => (MissionId::RecallNotice, M02_MISSION),
            MissionId::ScheduledService => (MissionId::PersonsUnknown, M03_MISSION),
            MissionId::NoticeToVacate => (MissionId::ScheduledService, M04_MISSION),
            MissionId::NoForwardingAddress => (MissionId::NoticeToVacate, M05_MISSION),
            MissionId::PortOfEntry => (MissionId::NoForwardingAddress, M06_MISSION),
            MissionId::CustodianOfRecord => (MissionId::DeclaredGoods, M08_MISSION),
            MissionId::PassengerManifest => (MissionId::CustodianOfRecord, M09_MISSION),
            MissionId::DeclaredGoods => (MissionId::PortOfEntry, M07_MISSION),
            MissionId::RecallNotice => return Err("a campaign transition cannot return to M01"),
        };
        let SavedStep::AwaitingMission {
            completed_mission,
            next_mission,
            exit,
        } = &self.step
        else {
            return Err("campaign run is not awaiting a mission");
        };
        if *completed_mission != previous
            || next_mission != next
            || (!matches!(
                mission,
                MissionId::NoticeToVacate
                    | MissionId::NoForwardingAddress
                    | MissionId::PortOfEntry
                    | MissionId::DeclaredGoods
                    | MissionId::CustodianOfRecord
                    | MissionId::PassengerManifest
            ) && self.m03_outcome.is_some())
        {
            return Err("unsupported saved campaign transition");
        }
        let mut entry = exit.clone();
        // Personal supply identities belong to the old map. The weapons and
        // ammunition they granted remain in the carried equipment.
        entry.equipment.personal_claims.clear();
        let mut promoted = self.clone();
        promoted.content_sha256 = content_hash;
        promoted.level_start_continues = self.remaining_continues;
        // Only the completed M05 edge enters Episode II. Reopening a promoted
        // entry or retrying it never passes this edge again. M07 continues the
        // same episode with whatever allowance M06 left.
        if mission == MissionId::PortOfEntry {
            promoted.remaining_continues = CAMPAIGN_CONTINUES;
            promoted.level_start_continues = CAMPAIGN_CONTINUES;
        }
        promoted.step = SavedStep::MissionEntry { mission, entry };
        promoted.validate(content_hash)?;
        Ok(promoted)
    }
    pub fn new(id: Uuid, rules: CampaignRules, content_sha256: [u8; 32]) -> Self {
        Self {
            version: RUN_FILE_VERSION,
            id,
            starting_continues: CAMPAIGN_CONTINUES,
            remaining_continues: CAMPAIGN_CONTINUES,
            level_start_continues: CAMPAIGN_CONTINUES,
            body: None,
            rules,
            content_sha256,
            step: SavedStep::MissionEntry {
                mission: MissionId::RecallNotice,
                entry: SavedEntry::initial(),
            },
            m03_outcome: None,
            m04_outcome: None,
            m05_outcome: None,
            m06_outcome: None,
            m08_outcome: None,
        }
    }

    pub fn validate(&self, content_sha256: [u8; 32]) -> Result<(), &'static str> {
        let completed_m03 = matches!(
            self.stage_mission(),
            MissionId::NoticeToVacate
                | MissionId::NoForwardingAddress
                | MissionId::PortOfEntry
                | MissionId::DeclaredGoods
                | MissionId::CustodianOfRecord
                | MissionId::PassengerManifest
        ) || matches!(&self.step, SavedStep::AwaitingMission {
            completed_mission: MissionId::ScheduledService, next_mission, ..
        } if next_mission == M04_MISSION);
        if completed_m03 != self.m03_outcome.is_some() {
            return Err("saved recall-car outcome does not match completed M03");
        }
        if let Some(outcome) = &self.m03_outcome {
            outcome.validate()?;
        }
        let completed_m04 = matches!(
            self.stage_mission(),
            MissionId::NoForwardingAddress
                | MissionId::PortOfEntry
                | MissionId::DeclaredGoods
                | MissionId::CustodianOfRecord
                | MissionId::PassengerManifest
        ) || matches!(&self.step, SavedStep::AwaitingMission {
            completed_mission: MissionId::NoticeToVacate, next_mission, ..
        } if next_mission == M05_MISSION);
        if completed_m04 != self.m04_outcome.is_some() {
            return Err("saved clinic outcome does not match completed M04");
        }
        if let Some(outcome) = &self.m04_outcome {
            outcome.validate()?;
        }
        let completed_m05 = matches!(
            self.stage_mission(),
            MissionId::PortOfEntry
                | MissionId::DeclaredGoods
                | MissionId::CustodianOfRecord
                | MissionId::PassengerManifest
        ) || matches!(&self.step, SavedStep::AwaitingMission {
            completed_mission: MissionId::NoForwardingAddress, next_mission, ..
        } if next_mission == M06_MISSION);
        if completed_m05 != self.m05_outcome.is_some() {
            return Err("saved workshop outcome does not match completed M05");
        }
        if let Some(outcome) = &self.m05_outcome {
            outcome.validate()?;
        }
        let completed_m06 = matches!(
            self.stage_mission(),
            MissionId::DeclaredGoods | MissionId::CustodianOfRecord | MissionId::PassengerManifest
        ) || matches!(&self.step, SavedStep::AwaitingMission {
                completed_mission: MissionId::PortOfEntry, next_mission, ..
            } if next_mission == M07_MISSION);
        if completed_m06 != self.m06_outcome.is_some() {
            return Err("saved prisoner-route outcome does not match completed M06");
        }
        let completed_m08 = self.stage_mission() == MissionId::PassengerManifest
            || matches!(&self.step, SavedStep::AwaitingMission {
            completed_mission: MissionId::CustodianOfRecord, next_mission, ..
        } if next_mission == M09_MISSION);
        if completed_m08 != self.m08_outcome.is_some() {
            return Err("saved custody outcome does not match completed M08");
        }
        if let Some(outcome) = &self.m08_outcome {
            outcome.validate()?;
        }
        if self.version != RUN_FILE_VERSION
            || self.id.is_nil()
            || self.starting_continues != CAMPAIGN_CONTINUES
            || self.remaining_continues > self.starting_continues
            || self.level_start_continues > self.starting_continues
            || self.remaining_continues > self.level_start_continues
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
            SavedStep::Abandoned { mission, entry } => self.validate_mission(*mission, entry),
            SavedStep::AwaitingMission {
                completed_mission,
                next_mission,
                exit,
            } => {
                if !matches!(
                    (*completed_mission, next_mission.as_str()),
                    (MissionId::RecallNotice, M02_MISSION)
                        | (MissionId::PersonsUnknown, M03_MISSION)
                        | (MissionId::ScheduledService, M04_MISSION)
                        | (MissionId::NoticeToVacate, M05_MISSION)
                        | (MissionId::NoForwardingAddress, M06_MISSION)
                        | (MissionId::PortOfEntry, M07_MISSION)
                        | (MissionId::DeclaredGoods, M08_MISSION)
                        | (MissionId::CustodianOfRecord, M09_MISSION)
                        | (MissionId::PassengerManifest, M10_MISSION)
                ) {
                    return Err("unsupported saved campaign transition");
                }
                if *completed_mission == MissionId::RecallNotice
                    && self.level_start_continues != CAMPAIGN_CONTINUES
                {
                    return Err("M01 run has the wrong continue baseline");
                }
                Self::validate_carried_finds(
                    exit,
                    matches!(
                        *completed_mission,
                        MissionId::DeclaredGoods
                            | MissionId::CustodianOfRecord
                            | MissionId::PassengerManifest
                    ),
                    matches!(
                        *completed_mission,
                        MissionId::CustodianOfRecord | MissionId::PassengerManifest
                    ),
                )?;
                exit.validate()
            }
        }
    }

    fn validate_mission(&self, mission: MissionId, entry: &SavedEntry) -> Result<(), &'static str> {
        if mission == MissionId::RecallNotice && self.level_start_continues != CAMPAIGN_CONTINUES {
            return Err("M01 run has the wrong continue baseline");
        }
        Self::validate_carried_finds(
            entry,
            matches!(
                mission,
                MissionId::CustodianOfRecord | MissionId::PassengerManifest
            ),
            matches!(
                mission,
                MissionId::CustodianOfRecord | MissionId::PassengerManifest
            ),
        )?;
        entry.validate()
    }

    /// The Sniper Rifle is first found in Declared Goods. Only the exit of a
    /// completed M07 or a later stage can carry it; every earlier stage,
    /// including an M07 entry or retry, refuses a forged copy.
    fn validate_carried_finds(
        entry: &SavedEntry,
        sniper_found: bool,
        mines_found: bool,
    ) -> Result<(), &'static str> {
        if entry.equipment.weapons.contains(&WeaponType::Repeater)
            || entry.equipment.selected == WeaponType::Repeater
        {
            return Err("Repeater ownership requires its unbuilt campaign stage");
        }
        if !mines_found && entry.equipment.proximity_mines != 0 {
            return Err("saved equipment carries mines before their mission");
        }
        if !sniper_found
            && (entry.equipment.weapons.contains(&WeaponType::Sniper)
                || entry.equipment.selected == WeaponType::Sniper)
        {
            return Err("saved equipment carries a weapon its stage cannot contain");
        }
        Ok(())
    }

    pub fn attempt(&self) -> u32 {
        u32::from(self.level_start_continues - self.remaining_continues) + 1
    }
}

impl GameState {
    pub(crate) fn campaign_run_document(&self) -> Result<Option<RunDocument>, &'static str> {
        let Some(run) = self.mission.as_ref() else {
            return Ok(None);
        };
        let Some(solo) = run.solo.as_ref() else {
            return Ok(None);
        };
        let content_sha256 = self
            .map
            .content_sha256()
            .ok_or("campaign run requires authored content")?;
        let entry = solo.saved_entry().unwrap_or_else(SavedEntry::initial);
        let mission = self
            .map
            .campaign_mission_id()
            .ok_or("campaign run requires mission geometry")?;
        let step = match solo.state.status {
            CampaignRunStatus::Playing => SavedStep::MissionEntry { mission, entry },
            CampaignRunStatus::Continue => SavedStep::PendingContinue { mission, entry },
            CampaignRunStatus::Failed => SavedStep::Failed { mission, entry },
            CampaignRunStatus::Complete => SavedStep::AwaitingMission {
                completed_mission: mission,
                next_mission: match mission {
                    MissionId::RecallNotice => M02_MISSION,
                    MissionId::PersonsUnknown => M03_MISSION,
                    MissionId::ScheduledService => M04_MISSION,
                    MissionId::NoticeToVacate => M05_MISSION,
                    MissionId::NoForwardingAddress => M06_MISSION,
                    MissionId::PortOfEntry => M07_MISSION,
                    MissionId::CustodianOfRecord => M09_MISSION,
                    MissionId::PassengerManifest => M10_MISSION,
                    MissionId::DeclaredGoods => M08_MISSION,
                }
                .into(),
                exit: solo
                    .saved_exit()
                    .ok_or("completed run has no saved exit")?
                    .clone(),
            },
            CampaignRunStatus::Abandoned => SavedStep::Abandoned { mission, entry },
        };
        let document = RunDocument {
            version: RUN_FILE_VERSION,
            id: solo.state.id,
            starting_continues: CAMPAIGN_CONTINUES,
            remaining_continues: solo.state.continues,
            level_start_continues: solo.state.level_start_continues,
            body: solo.body(),
            rules: run.rules,
            content_sha256,
            step,
            m03_outcome: if solo.state.status == CampaignRunStatus::Complete
                && mission == MissionId::ScheduledService
            {
                Some(M03Outcome {
                    liberated_cars: self.m03_liberated_car_ids(),
                })
            } else if matches!(
                mission,
                MissionId::NoticeToVacate
                    | MissionId::NoForwardingAddress
                    | MissionId::PortOfEntry
                    | MissionId::DeclaredGoods
                    | MissionId::CustodianOfRecord
                    | MissionId::PassengerManifest
            ) {
                Some(M03Outcome {
                    liberated_cars: solo.carried_recall_cars.clone(),
                })
            } else {
                None
            },
            m04_outcome: if solo.state.status == CampaignRunStatus::Complete
                && mission == MissionId::NoticeToVacate
            {
                Some(M04Outcome {
                    rescued_patients: self.m04_rescued_patient_ids(),
                    photos_completed: self.m04_photos_completed(),
                })
            } else if matches!(
                mission,
                MissionId::NoForwardingAddress
                    | MissionId::PortOfEntry
                    | MissionId::DeclaredGoods
                    | MissionId::CustodianOfRecord
                    | MissionId::PassengerManifest
            ) {
                Some(M04Outcome {
                    rescued_patients: solo.carried_patients.clone(),
                    photos_completed: solo.carried_photos,
                })
            } else {
                None
            },
            m05_outcome: if solo.state.status == CampaignRunStatus::Complete
                && mission == MissionId::NoForwardingAddress
            {
                Some(M05Outcome {
                    released_workers: self.m05_released_worker_ids(),
                    evacuated_workers: self.m05_evacuated_worker_ids(),
                })
            } else if matches!(
                mission,
                MissionId::PortOfEntry
                    | MissionId::DeclaredGoods
                    | MissionId::CustodianOfRecord
                    | MissionId::PassengerManifest
            ) {
                Some(M05Outcome {
                    released_workers: solo.carried_released_workers.clone(),
                    evacuated_workers: solo.carried_evacuated_workers.clone(),
                })
            } else {
                None
            },
            m06_outcome: if solo.state.status == CampaignRunStatus::Complete
                && mission == MissionId::PortOfEntry
            {
                Some(M06Outcome {
                    prisoner_route_marked: self.m06_prisoner_route_marked(),
                })
            } else if matches!(
                mission,
                MissionId::DeclaredGoods
                    | MissionId::CustodianOfRecord
                    | MissionId::PassengerManifest
            ) {
                Some(M06Outcome {
                    prisoner_route_marked: solo.carried_prisoner_route_marked,
                })
            } else {
                None
            },
            m08_outcome: if solo.state.status == CampaignRunStatus::Complete
                && mission == MissionId::CustodianOfRecord
            {
                let progress = run.m08.as_ref().ok_or("completed M08 lacks progress")?;
                Some(M08Outcome::Recorded {
                    custody_released: progress.custody_released,
                    recovered_mind_secured: progress.recovered_mind_secured,
                    captives_evacuated: progress.captives_evacuated,
                })
            } else if mission == MissionId::PassengerManifest {
                solo.carried_archive.clone()
            } else {
                None
            },
        };
        document.validate(content_sha256)?;
        Ok(Some(document))
    }
}

#[cfg(test)]
pub(super) fn historical_value(document: &RunDocument) -> serde_json::Value {
    let mut value = serde_json::to_value(document).unwrap();
    remove_historical_grenades(&mut value);
    value
}

#[cfg(test)]
pub(super) fn remove_historical_grenades(value: &mut serde_json::Value) {
    remove_historical_mines(value);
    for entry_key in ["entry", "exit"] {
        if let Some(equipment) = value
            .get_mut("step")
            .and_then(|step| step.get_mut(entry_key))
            .and_then(|entry| entry.get_mut("equipment"))
            .and_then(serde_json::Value::as_object_mut)
        {
            assert_eq!(
                equipment
                    .get("grenades")
                    .and_then(serde_json::Value::as_u64),
                Some(0)
            );
            equipment.remove("grenades");
        }
    }
}

#[cfg(test)]
pub(super) fn remove_historical_mines(value: &mut serde_json::Value) {
    for entry_key in ["entry", "exit"] {
        if let Some(equipment) = value
            .get_mut("step")
            .and_then(|step| step.get_mut(entry_key))
            .and_then(|entry| entry.get_mut("equipment"))
            .and_then(serde_json::Value::as_object_mut)
        {
            assert_eq!(
                equipment
                    .get("proximity_mines")
                    .and_then(serde_json::Value::as_u64),
                Some(0)
            );
            equipment.remove("proximity_mines");
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::inventory::Inventory;
    use crate::maps::{AuthoredMap, RuntimeMap};
    use crate::protocol::{
        AmmoPool, BodyKind, CampaignDifficulty, EquipmentPolicy, MissionContinue, MissionPhase,
        Role, WeaponType,
    };

    fn state_with_map() -> GameState {
        let map = AuthoredMap::read(
            serde_json::to_vec(&super::super::tests::definition())
                .unwrap()
                .as_slice(),
        )
        .unwrap();
        GameState::with_authored_map(map)
    }

    fn document() -> RunDocument {
        let inventory = Inventory::new(EquipmentPolicy::Discovery);
        RunDocument {
            version: RUN_FILE_VERSION,
            id: Uuid::from_u128(1),
            starting_continues: CAMPAIGN_CONTINUES,
            remaining_continues: CAMPAIGN_CONTINUES,
            level_start_continues: CAMPAIGN_CONTINUES,
            body: None,
            rules: CampaignRules::new(CampaignDifficulty::Standard),
            content_sha256: [5; 32],
            m03_outcome: None,
            m04_outcome: None,
            m05_outcome: None,
            m06_outcome: None,
            m08_outcome: None,
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

        let mut abandoned = document();
        abandoned.step = SavedStep::Abandoned {
            mission: MissionId::RecallNotice,
            entry: SavedEntry::initial(),
        };
        abandoned.validate([5; 32]).unwrap();
        assert_eq!(abandoned.remaining_continues, CAMPAIGN_CONTINUES);
    }

    #[test]
    fn no_saved_stage_before_declared_goods_carries_the_sniper() {
        let mut inventory = Inventory::new(EquipmentPolicy::Discovery);
        inventory.grant_weapon(WeaponType::Sniper);
        let forged = SavedEntry {
            hp: 100,
            armor: 0,
            equipment: inventory.saved_equipment(WeaponType::Sniper).unwrap(),
        };
        let mut saved = document();
        saved.step = SavedStep::MissionEntry {
            mission: MissionId::RecallNotice,
            entry: forged.clone(),
        };
        assert!(saved.validate([5; 32]).is_err());
        saved.step = SavedStep::AwaitingMission {
            completed_mission: MissionId::RecallNotice,
            next_mission: M02_MISSION.into(),
            exit: forged.clone(),
        };
        assert!(saved.validate([5; 32]).is_err());
        let mut unselected = forged;
        unselected.equipment.selected = WeaponType::Fists;
        saved.step = SavedStep::PendingContinue {
            mission: MissionId::RecallNotice,
            entry: unselected,
        };
        saved.remaining_continues = 1;
        assert!(saved.validate([5; 32]).is_err());
    }

    #[test]
    fn completed_m01_is_a_distinct_pending_m02_boundary() {
        let mut saved = document();
        let SavedStep::MissionEntry { mission, entry } = saved.step else {
            panic!("fixture must start at mission entry");
        };
        saved.step = SavedStep::AwaitingMission {
            completed_mission: mission,
            next_mission: M02_MISSION.into(),
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

    #[test]
    fn resumed_pending_continue_restores_dead_owner_then_spends_once() {
        let mut state = state_with_map();
        let hash = state.map.content_sha256().unwrap();
        let mut document = RunDocument::new(
            Uuid::new_v4(),
            CampaignRules::new(CampaignDifficulty::Severe),
            hash,
        );
        document.remaining_continues = 1;
        document.step = SavedStep::PendingContinue {
            mission: MissionId::RecallNotice,
            entry: SavedEntry::initial(),
        };
        state.load_campaign_run(&document).unwrap();
        let owner = Uuid::new_v4();
        state.add_player(owner, "Free agent".into(), Role::Agent);
        let mission = state.mission_state().unwrap();
        mission.validate(state.tick).unwrap();
        assert_eq!(mission.attempt, 3);
        assert_eq!(mission.run.unwrap().status, CampaignRunStatus::Continue);
        assert!(!mission.party[0].alive);
        let mut bound = document.clone();
        bound.body = Some(crate::protocol::BodyKind::Human);
        assert_eq!(state.campaign_run_document().unwrap(), Some(bound));
        let request = MissionContinue {
            id: MissionId::RecallNotice,
            run_id: document.id,
            attempt: 3,
        };
        assert!(state.continue_mission(owner, request));
        assert!(!state.continue_mission(owner, request));
        let resumed = state.campaign_run_document().unwrap().unwrap();
        assert_eq!(resumed.id, document.id);
        assert_eq!(resumed.remaining_continues, 0);
        assert_eq!(resumed.attempt(), 4);
        assert!(matches!(resumed.step, SavedStep::MissionEntry { .. }));
    }

    #[test]
    fn completed_m01_projects_live_exit_equipment_instead_of_entry() {
        let mut state = state_with_map();
        let hash = state.map.content_sha256().unwrap();
        let initial = RunDocument::new(Uuid::new_v4(), CampaignRules::default(), hash);
        state.load_campaign_run(&initial).unwrap();
        let owner = Uuid::new_v4();
        state.add_player(owner, "Run owner".into(), Role::Human);
        state.acknowledge_mission(
            owner,
            crate::protocol::MissionReady {
                id: MissionId::RecallNotice,
                attempt: 1,
            },
        );
        let player = state.players.iter_mut().find(|p| p.id == owner).unwrap();
        player.inventory.grant_weapon(WeaponType::Tack);
        player.inventory.try_fire(WeaponType::Tack);
        player.weapon = WeaponType::Tack;
        player.hp = 54;
        player.armor = 12;
        let saved_exit = SavedEntry::from_player(player).unwrap();
        let run = state.mission.as_mut().unwrap();
        run.phase = crate::protocol::MissionPhase::Departed;
        let solo = run.solo.as_mut().unwrap();
        solo.capture_exit(saved_exit);
        solo.state.status = CampaignRunStatus::Complete;
        let completed = state.campaign_run_document().unwrap().unwrap();
        completed.validate(hash).unwrap();
        match &completed.step {
            SavedStep::AwaitingMission {
                completed_mission,
                next_mission,
                exit,
            } => {
                assert_eq!(*completed_mission, MissionId::RecallNotice);
                assert_eq!(next_mission, M02_MISSION);
                assert_eq!((exit.hp, exit.armor), (54, 12));
                assert_eq!(exit.equipment.selected, WeaponType::Tack);
                assert_eq!(exit.equipment.weapons.len(), 2);
            }
            _ => panic!("completed run did not retain its live exit"),
        }
        let directory =
            std::env::temp_dir().join(format!("fragr-completed-run-{}", Uuid::new_v4()));
        let store = store::RunStore::open(&directory, hash).unwrap();
        store.save(&completed).unwrap();
        assert!(matches!(
            store::RunStore::inspect(&directory, hash).unwrap(),
            store::RunProbe::Compatible(document) if *document == completed
        ));
        assert!(state_with_map().load_campaign_run(&completed).is_err());
        state.remove_player(owner);
        assert_eq!(state.campaign_run_document().unwrap(), Some(completed));
        drop(store);
        std::fs::remove_dir_all(directory).unwrap();
    }

    #[test]
    fn m01_exit_promotes_exact_gear_and_body_into_m02_retry_anchor() {
        let m01_hash = RuntimeMap::Authored(
            crate::maps::AuthoredSource::Mission(MissionId::RecallNotice)
                .load()
                .unwrap(),
        )
        .content_sha256()
        .unwrap();
        let m02_map = crate::maps::AuthoredSource::Mission(MissionId::PersonsUnknown)
            .load()
            .unwrap();
        let m02_hash = RuntimeMap::Authored(m02_map.clone())
            .content_sha256()
            .unwrap();
        let mut inventory = Inventory::new(EquipmentPolicy::Discovery);
        inventory.grant_weapon(WeaponType::Tack);
        inventory.grant_ammo(AmmoPool::Bullets, 17);
        inventory.record_claim("bay_tack".into());
        let exit = SavedEntry {
            hp: 47,
            armor: 12,
            equipment: inventory.saved_equipment(WeaponType::Tack).unwrap(),
        };
        let exit_ammo = exit.equipment.ammo.clone();
        let mut saved = RunDocument::new(
            Uuid::new_v4(),
            CampaignRules::new(CampaignDifficulty::Severe),
            m01_hash,
        );
        saved.remaining_continues = 1;
        saved.body = Some(BodyKind::Synthetic);
        saved.step = SavedStep::AwaitingMission {
            completed_mission: MissionId::RecallNotice,
            next_mission: M02_MISSION.into(),
            exit,
        };
        saved.validate(m01_hash).unwrap();
        let promoted = saved.promote_m02(m02_hash).unwrap();
        assert_eq!(promoted.id, saved.id);
        assert_eq!(promoted.rules, saved.rules);
        assert_eq!(promoted.remaining_continues, 1);
        assert_eq!(promoted.level_start_continues, 1);
        assert_eq!(promoted.attempt(), 1);
        assert_eq!(promoted.body, Some(BodyKind::Synthetic));
        let SavedStep::MissionEntry { mission, entry } = &promoted.step else {
            panic!("expected M02 entry")
        };
        assert_eq!(*mission, MissionId::PersonsUnknown);
        assert_eq!((entry.hp, entry.armor), (47, 12));
        assert_eq!(entry.equipment.selected, WeaponType::Tack);
        assert!(entry.equipment.personal_claims.is_empty());
        assert_eq!(entry.equipment.ammo, exit_ammo);
        assert!(saved.promote_m02(m02_hash).is_ok());
        assert!(promoted.promote_m02(m02_hash).is_err());
        let mut state = GameState::with_authored_map(m02_map);
        state.load_campaign_run(&promoted).unwrap();
        let owner = Uuid::new_v4();
        state.add_player_with_body(owner, "Runner".into(), Role::Human, BodyKind::Human);
        let player = state
            .players
            .iter()
            .find(|player| player.id == owner)
            .unwrap();
        assert_eq!(player.body, BodyKind::Synthetic);
        assert_eq!(
            (player.hp, player.armor, player.weapon),
            (47, 12, WeaponType::Tack)
        );
        assert!(!player.inventory.claimed("bay_tack"));
        assert!(!player.inventory.claimed("guard_room_scatter"));
        assert_eq!(
            state
                .mission_state()
                .unwrap()
                .run
                .unwrap()
                .level_start_continues,
            1
        );
        assert!(state.acknowledge_m02(owner, 1));
        {
            let player = state
                .players
                .iter_mut()
                .find(|player| player.id == owner)
                .unwrap();
            [player.x, player.y, player.z] = [-2.1, 3.0 + crate::sim::PLAYER_FLOOR_Y, -31.0];
        }
        state.tick(0.05);
        assert!(state
            .players
            .iter()
            .find(|player| player.id == owner)
            .unwrap()
            .inventory
            .owns(WeaponType::Scatter));
        state
            .players
            .iter_mut()
            .find(|player| player.id == owner)
            .unwrap()
            .hp = 0;
        state.update_campaign_run();
        assert_eq!(
            state.mission_state().unwrap().run.unwrap().status,
            CampaignRunStatus::Continue
        );
        let request = MissionContinue {
            id: MissionId::PersonsUnknown,
            run_id: promoted.id,
            attempt: 1,
        };
        assert!(state.continue_mission(owner, request));
        assert!(!state.continue_mission(owner, request));
        let retry = state.mission_state().unwrap();
        assert_eq!(retry.attempt, 2);
        assert_eq!(retry.run.unwrap().continues, 0);
        let player = state
            .players
            .iter()
            .find(|player| player.id == owner)
            .unwrap();
        assert_eq!(
            (player.hp, player.armor, player.weapon),
            (47, 12, WeaponType::Tack)
        );
        assert!(!player.inventory.owns(WeaponType::Scatter));
        assert_eq!(state.campaign_run_document().unwrap().unwrap().attempt(), 2);
    }

    #[test]
    fn zero_continues_at_m02_entry_allows_a_first_attempt_then_fails() {
        let map = crate::maps::AuthoredSource::Mission(MissionId::PersonsUnknown)
            .load()
            .unwrap();
        let hash = RuntimeMap::Authored(map.clone()).content_sha256().unwrap();
        let mut document = RunDocument::new(Uuid::new_v4(), CampaignRules::default(), hash);
        document.remaining_continues = 0;
        document.level_start_continues = 0;
        document.step = SavedStep::MissionEntry {
            mission: MissionId::PersonsUnknown,
            entry: SavedEntry::initial(),
        };
        document.validate(hash).unwrap();
        let mut state = GameState::with_authored_map(map);
        state.load_campaign_run(&document).unwrap();
        let owner = Uuid::new_v4();
        state.add_player(owner, "Runner".into(), Role::Agent);
        assert!(state.acknowledge_m02(owner, 1));
        assert_eq!(state.mission_state().unwrap().attempt, 1);
        state
            .players
            .iter_mut()
            .find(|player| player.id == owner)
            .unwrap()
            .hp = 0;
        state.update_campaign_run();
        let run = state.mission_state().unwrap().run.unwrap();
        assert_eq!(run.status, CampaignRunStatus::Failed);
        assert_eq!(run.continues, 0);
        assert!(!state.continue_mission(
            owner,
            MissionContinue {
                id: MissionId::PersonsUnknown,
                run_id: document.id,
                attempt: 1
            }
        ));
    }

    #[test]
    fn m02_exit_promotes_exact_equipment_and_retry_allowance_into_m03() {
        let map = crate::maps::AuthoredSource::Mission(MissionId::ScheduledService)
            .load()
            .unwrap();
        let hash = RuntimeMap::Authored(map.clone()).content_sha256().unwrap();
        let mut inventory = Inventory::new(EquipmentPolicy::Discovery);
        inventory.grant_weapon(WeaponType::Flechette);
        inventory.grant_weapon(WeaponType::Scatter);
        inventory.grant_ammo(AmmoPool::Bullets, 17);
        inventory.record_claim("m02_rifle".into());
        let exit = SavedEntry {
            hp: 47,
            armor: 12,
            equipment: inventory.saved_equipment(WeaponType::Flechette).unwrap(),
        };
        let mut prior = document();
        prior.remaining_continues = 1;
        prior.body = Some(BodyKind::Synthetic);
        prior.rules = CampaignRules::new(CampaignDifficulty::Severe);
        prior.step = SavedStep::AwaitingMission {
            completed_mission: MissionId::PersonsUnknown,
            next_mission: M03_MISSION.into(),
            exit: exit.clone(),
        };
        prior.validate([5; 32]).unwrap();
        let promoted = prior
            .promote_next(MissionId::ScheduledService, hash)
            .unwrap();
        assert_eq!(
            (promoted.id, promoted.body, promoted.rules),
            (prior.id, prior.body, prior.rules)
        );
        assert_eq!(
            (
                promoted.remaining_continues,
                promoted.level_start_continues,
                promoted.attempt()
            ),
            (1, 1, 1)
        );
        let mut expected = exit;
        expected.equipment.personal_claims.clear();
        assert_eq!(
            promoted.step,
            SavedStep::MissionEntry {
                mission: MissionId::ScheduledService,
                entry: expected.clone()
            }
        );
        assert!(prior.promote_next(MissionId::PersonsUnknown, hash).is_err());
        assert!(promoted
            .promote_next(MissionId::ScheduledService, hash)
            .is_err());
        let mut state = GameState::with_authored_map(map);
        state.load_campaign_run(&promoted).unwrap();
        let owner = Uuid::new_v4();
        state.add_player_with_body(owner, "Runner".into(), Role::Human, BodyKind::Human);
        assert!(state.acknowledge_mission(
            owner,
            crate::protocol::MissionReady {
                id: MissionId::ScheduledService,
                attempt: 1
            }
        ));
        let player = state.players.iter_mut().find(|p| p.id == owner).unwrap();
        assert_eq!(player.body, BodyKind::Synthetic);
        assert_eq!(SavedEntry::from_player(player).unwrap(), expected);
        player.inventory.grant_weapon(WeaponType::Tack);
        player.hp = 0;
        state.update_campaign_run();
        let request = MissionContinue {
            id: MissionId::ScheduledService,
            run_id: prior.id,
            attempt: 1,
        };
        assert!(state.continue_mission(owner, request));
        assert!(!state.continue_mission(owner, request));
        let player = state.players.iter().find(|p| p.id == owner).unwrap();
        assert_eq!(SavedEntry::from_player(player).unwrap(), expected);
        let retry = state.mission_state().unwrap();
        assert_eq!((retry.attempt, retry.run.unwrap().continues), (2, 0));
        assert_eq!(retry.m03.unwrap().mast_hp, crate::protocol::M03_MAST_MAX_HP);
    }

    #[test]
    fn m03_completion_projects_only_released_cars_and_live_exit() {
        let map = crate::maps::AuthoredSource::Mission(MissionId::ScheduledService)
            .load()
            .unwrap();
        let hash = RuntimeMap::Authored(map.clone()).content_sha256().unwrap();
        let mut initial = document();
        initial.content_sha256 = hash;
        initial.step = SavedStep::MissionEntry {
            mission: MissionId::ScheduledService,
            entry: SavedEntry::initial(),
        };
        let mut state = GameState::with_authored_map(map);
        state.load_campaign_run(&initial).unwrap();
        let owner = Uuid::new_v4();
        state.add_player(owner, "Runner".into(), Role::Human);
        assert!(state.acknowledge_mission(
            owner,
            crate::protocol::MissionReady {
                id: MissionId::ScheduledService,
                attempt: 1,
            }
        ));
        let player = state.players.iter_mut().find(|p| p.id == owner).unwrap();
        player.hp = 38;
        player.armor = 9;
        player.inventory.grant_weapon(WeaponType::Scatter);
        player.weapon = WeaponType::Scatter;
        let exit = SavedEntry::from_player(player).unwrap();
        let run = state.mission.as_mut().unwrap();
        let progress = run.m03.as_mut().unwrap();
        progress.cars[1].released = true;
        let liberated = progress.cars[1].id.clone();
        // Project completion from the fallen world, whose authored hash must
        // remain the same save identity as the intact entry world.
        state.map = run.initial_map.prepared_m03_world().unwrap();
        run.phase = crate::protocol::MissionPhase::Departed;
        let solo = run.solo.as_mut().unwrap();
        solo.capture_exit(exit.clone());
        solo.state.status = CampaignRunStatus::Complete;
        let saved = state.campaign_run_document().unwrap().unwrap();
        saved.validate(hash).unwrap();
        assert_eq!(saved.id, initial.id);
        assert_eq!(saved.m03_outcome.unwrap().liberated_cars, [liberated]);
        assert_eq!(
            saved.step,
            SavedStep::AwaitingMission {
                completed_mission: MissionId::ScheduledService,
                next_mission: M04_MISSION.into(),
                exit,
            }
        );
    }

    #[test]
    fn completed_m03_retains_optional_choices_only_at_pending_m04_boundary() {
        let mut saved = document();
        saved.step = SavedStep::AwaitingMission {
            completed_mission: MissionId::ScheduledService,
            next_mission: M04_MISSION.into(),
            exit: SavedEntry::initial(),
        };
        assert!(saved.validate([5; 32]).is_err());
        saved.m03_outcome = Some(M03Outcome {
            liberated_cars: vec!["platform_car".into(), "roof_car".into()],
        });
        saved.validate([5; 32]).unwrap();
        assert_eq!(
            serde_json::from_slice::<RunDocument>(&serde_json::to_vec(&saved).unwrap()).unwrap(),
            saved
        );
        assert!(saved
            .promote_next(MissionId::ScheduledService, [6; 32])
            .is_err());
        for ids in [
            vec!["same".into(), "same".into()],
            vec!["bad/id".into()],
            vec!["".into()],
            vec!["A".into()],
            vec!["x".repeat(65)],
            vec!["a".into(), "b".into(), "c".into(), "d".into(), "e".into()],
        ] {
            saved.m03_outcome = Some(M03Outcome {
                liberated_cars: ids,
            });
            assert!(saved.validate([5; 32]).is_err());
        }
        let mut entry = document();
        entry.m03_outcome = Some(M03Outcome {
            liberated_cars: Vec::new(),
        });
        assert!(entry.validate([5; 32]).is_err());
    }

    #[test]
    fn released_version_three_upgrades_m02_without_inventing_m03_outcomes() {
        let mut saved = document();
        saved.version = 3;
        saved.rules.revision = 2;
        saved.remaining_continues = 2;
        saved.body = Some(BodyKind::Synthetic);
        saved.step = SavedStep::AwaitingMission {
            completed_mission: MissionId::PersonsUnknown,
            next_mission: M03_MISSION.into(),
            exit: SavedEntry::initial(),
        };
        let value = historical_value(&saved);
        let legacy: RunDocumentV3 = serde_json::from_value(value.clone()).unwrap();
        let upgraded = legacy.upgrade([7; 32], [5; 32]).unwrap();
        assert_eq!(upgraded.version, RUN_FILE_VERSION);
        assert_eq!(
            (upgraded.id, upgraded.body, upgraded.step.clone()),
            (saved.id, saved.body, saved.step)
        );
        assert!(upgraded.m03_outcome.is_none());
        assert!(serde_json::from_value::<RunDocumentV3>(value.clone())
            .unwrap()
            .upgrade([5; 32], [7; 32])
            .is_err());
        let mut forged = value;
        forged["m03_outcome"] = serde_json::json!({"liberated_cars":[]});
        assert!(serde_json::from_value::<RunDocumentV3>(forged).is_err());
    }

    pub(super) fn completed_market_document() -> RunDocument {
        let mut saved = document();
        saved.content_sha256 = [11; 32];
        saved.remaining_continues = 1;
        saved.level_start_continues = 2;
        saved.body = Some(BodyKind::Synthetic);
        let mut exit = SavedEntry::initial();
        exit.hp = 61;
        exit.armor = 7;
        exit.equipment.selected = WeaponType::Flechette;
        exit.equipment.weapons = vec![
            WeaponType::Fists,
            WeaponType::Flechette,
            WeaponType::Scatter,
        ];
        exit.equipment.ammo[0].rounds = 29;
        exit.equipment.ammo[1].rounds = 8;
        exit.equipment.personal_claims = vec!["m04_shotgun".into()];
        saved.step = SavedStep::AwaitingMission {
            completed_mission: MissionId::NoticeToVacate,
            next_mission: M05_MISSION.into(),
            exit,
        };
        saved.m03_outcome = Some(M03Outcome {
            liberated_cars: vec!["platform_car".into(), "roof_car".into()],
        });
        saved.m04_outcome = Some(M04Outcome {
            rescued_patients: vec!["patient_a".into(), "patient_b".into()],
            photos_completed: 3,
        });
        saved.validate([11; 32]).unwrap();
        saved
    }

    #[test]
    fn historical_v5_upgrades_exact_market_carry_with_no_invented_grenades() {
        let mut saved = completed_market_document();
        saved.version = 5;
        let value = historical_value(&saved);
        let old: RunDocumentV5 = serde_json::from_value(value.clone()).unwrap();
        let upgraded = old.upgrade([[5; 32], [7; 32], [9; 32], [11; 32]]).unwrap();
        assert_eq!(upgraded.version, RUN_FILE_VERSION);
        assert_eq!(upgraded.step, saved.step);
        assert_eq!(
            (upgraded.id, upgraded.body, upgraded.remaining_continues),
            (saved.id, saved.body, 1)
        );
        let carried = upgraded
            .promote_next(MissionId::NoForwardingAddress, [12; 32])
            .unwrap();
        let SavedStep::MissionEntry { mission, entry } = &carried.step else {
            panic!("M05 entry missing");
        };
        assert_eq!(*mission, MissionId::NoForwardingAddress);
        assert_eq!(
            (
                entry.hp,
                entry.armor,
                entry.equipment.selected,
                entry.equipment.grenades
            ),
            (61, 7, WeaponType::Flechette, 0)
        );
        assert!(entry.equipment.personal_claims.is_empty());
        assert_eq!(
            entry
                .equipment
                .ammo
                .iter()
                .map(|a| a.rounds)
                .collect::<Vec<_>>(),
            [29, 8, 0]
        );
        assert_eq!(carried.m03_outcome, upgraded.m03_outcome);
        assert_eq!(carried.m04_outcome, upgraded.m04_outcome);
        assert_eq!(
            (
                carried.level_start_continues,
                carried.remaining_continues,
                carried.attempt()
            ),
            (1, 1, 1)
        );
        let mut forged = value.clone();
        forged["step"]["exit"]["equipment"]["grenades"] = 0.into();
        assert!(serde_json::from_value::<RunDocumentV5>(forged).is_err());
        let mut forged = value.clone();
        forged["step"]["completed_mission"] = M05_MISSION.into();
        assert!(serde_json::from_value::<RunDocumentV5>(forged)
            .unwrap()
            .upgrade([[11; 32]; 4])
            .is_err());
        let mut forged = value.clone();
        forged["rules"]["revision"] = 2.into();
        assert!(serde_json::from_value::<RunDocumentV5>(forged)
            .unwrap()
            .upgrade([[11; 32]; 4])
            .is_err());
        let mut forged = value;
        forged["m05_outcome"] =
            serde_json::json!({"released_workers": [], "evacuated_workers": []});
        assert!(serde_json::from_value::<RunDocumentV5>(forged).is_err());
    }

    #[test]
    fn m05_entry_and_completed_outcomes_have_strict_independent_grenade_counts() {
        let mut saved = completed_market_document()
            .promote_next(MissionId::NoForwardingAddress, [12; 32])
            .unwrap();
        let SavedStep::MissionEntry { entry, .. } = &mut saved.step else {
            unreachable!();
        };
        entry.equipment.grenades = 3;
        saved.validate([12; 32]).unwrap();
        let roundtrip: RunDocument =
            serde_json::from_slice(&serde_json::to_vec(&saved).unwrap()).unwrap();
        assert_eq!(roundtrip, saved);
        let mut forged = saved.clone();
        let SavedStep::MissionEntry { entry, .. } = &mut forged.step else {
            unreachable!();
        };
        entry.equipment.grenades = 7;
        assert!(forged.validate([12; 32]).is_err());
        forged = saved.clone();
        forged.m04_outcome = None;
        assert!(forged.validate([12; 32]).is_err());
        saved.m05_outcome = Some(M05Outcome {
            released_workers: Vec::new(),
            evacuated_workers: Vec::new(),
        });
        assert!(saved.validate([12; 32]).is_err());
        let SavedStep::MissionEntry { entry, .. } = saved.step.clone() else {
            unreachable!();
        };
        saved.step = SavedStep::AwaitingMission {
            completed_mission: MissionId::NoForwardingAddress,
            next_mission: M06_MISSION.into(),
            exit: entry,
        };
        saved.validate([12; 32]).unwrap();
        saved.m05_outcome = Some(M05Outcome {
            released_workers: vec![
                "splice".into(),
                "workshop_agent_a".into(),
                "workshop_agent_b".into(),
            ],
            evacuated_workers: vec!["splice".into()],
        });
        saved.validate([12; 32]).unwrap();
        saved
            .m05_outcome
            .as_mut()
            .unwrap()
            .evacuated_workers
            .push("someone_new".into());
        assert!(saved.validate([12; 32]).is_err());
        saved.m05_outcome.as_mut().unwrap().evacuated_workers =
            vec!["splice".into(), "splice".into()];
        assert!(saved.validate([12; 32]).is_err());
        saved
            .m05_outcome
            .as_mut()
            .unwrap()
            .evacuated_workers
            .clear();
        saved.m05_outcome.as_mut().unwrap().released_workers =
            vec!["splice".into(), "splice".into()];
        assert!(saved.validate([12; 32]).is_err());
        saved.m05_outcome.as_mut().unwrap().released_workers = vec!["someone_new".into()];
        assert!(saved.validate([12; 32]).is_err());
    }

    #[test]
    fn m05_pending_continue_restores_grenades_and_prior_choices_without_rewinding() {
        let map = crate::maps::AuthoredSource::Mission(MissionId::NoForwardingAddress)
            .load()
            .unwrap();
        let hash = RuntimeMap::Authored(map.clone()).content_sha256().unwrap();
        let mut saved = completed_market_document()
            .promote_next(MissionId::NoForwardingAddress, hash)
            .unwrap();
        let SavedStep::MissionEntry { mut entry, .. } = saved.step.clone() else {
            unreachable!();
        };
        entry.equipment.grenades = 3;
        saved.step = SavedStep::PendingContinue {
            mission: MissionId::NoForwardingAddress,
            entry,
        };
        let mut state = GameState::with_authored_map(map);
        state.load_campaign_run(&saved).unwrap();
        let owner = Uuid::from_u128(5055);
        state.add_player(owner, "Workshop runner".into(), Role::Human);
        state.tick = 173;
        let player = state.players.iter_mut().find(|p| p.id == owner).unwrap();
        player.last_input_seq = Some(91);
        let revision = player.inventory.revision();
        assert_eq!(player.hp, 0);
        let before = state.mission_state().unwrap();
        let request = MissionContinue {
            id: MissionId::NoForwardingAddress,
            run_id: saved.id,
            attempt: before.attempt,
        };
        assert!(state.continue_mission(owner, request));
        assert!(!state.continue_mission(owner, request));
        let player = state.players.iter().find(|p| p.id == owner).unwrap();
        assert_eq!(
            (player.hp, player.armor, player.inventory.grenades()),
            (61, 7, 3)
        );
        assert_eq!(player.last_input_seq, Some(91));
        assert!(player.inventory.revision() >= revision);
        assert_eq!(state.tick, 173);
        let after = state.mission_state().unwrap();
        assert_eq!(after.run.unwrap().continues, 0);
        let facts = after.m05.unwrap();
        assert_eq!(facts.carried_recall_cars, ["platform_car", "roof_car"]);
        assert_eq!(facts.carried_patients, ["patient_a", "patient_b"]);
        assert_eq!(facts.carried_photos, 3);
        assert!(!facts.group_released);
        assert!(!facts.freight_open);
        assert_eq!(facts.tram.phase, crate::protocol::M05TramPhase::Parked);
        let retry = state.campaign_run_document().unwrap().unwrap();
        assert_eq!(retry.m03_outcome, saved.m03_outcome);
        assert_eq!(retry.m04_outcome, saved.m04_outcome);
        assert!(retry.m05_outcome.is_none());
    }

    fn completed_workshop_document() -> RunDocument {
        let mut saved = completed_market_document()
            .promote_next(MissionId::NoForwardingAddress, [12; 32])
            .unwrap();
        let SavedStep::MissionEntry { mut entry, .. } = saved.step.clone() else {
            panic!("missing workshop entry")
        };
        entry.equipment.grenades = 3;
        saved.step = SavedStep::AwaitingMission {
            completed_mission: MissionId::NoForwardingAddress,
            next_mission: M06_MISSION.into(),
            exit: entry,
        };
        saved.remaining_continues = 0;
        saved.m05_outcome = Some(M05Outcome {
            released_workers: vec![
                "workshop_agent_b".into(),
                "splice".into(),
                "workshop_agent_a".into(),
            ],
            evacuated_workers: vec!["workshop_agent_b".into()],
        });
        saved.validate([12; 32]).unwrap();
        saved
    }

    #[test]
    fn m06_retry_restores_exact_entry_carry_and_optional_route_without_rewinding() {
        let map = crate::maps::AuthoredSource::Mission(MissionId::PortOfEntry)
            .load()
            .unwrap();
        let hash = RuntimeMap::Authored(map.clone()).content_sha256().unwrap();
        let mut saved = completed_workshop_document()
            .promote_next(MissionId::PortOfEntry, hash)
            .unwrap();
        let SavedStep::MissionEntry { entry, .. } = saved.step.clone() else {
            panic!("missing port entry")
        };
        saved.remaining_continues = 2;
        saved.step = SavedStep::PendingContinue {
            mission: MissionId::PortOfEntry,
            entry,
        };
        let mut state = GameState::with_authored_map(map);
        state.load_campaign_run(&saved).unwrap();
        let owner = Uuid::from_u128(6066);
        state.add_player(owner, "Port runner".into(), Role::Human);
        state.tick = 173;
        let player = state.players.iter_mut().find(|p| p.id == owner).unwrap();
        assert_eq!(player.hp, 0);
        player.last_input_seq = Some(91);
        let revision = player.inventory.revision();
        let progress = state.mission.as_mut().unwrap().m06.as_mut().unwrap();
        progress.index = 3;
        progress.prisoner_route_marked = true;
        let request = MissionContinue {
            id: MissionId::PortOfEntry,
            run_id: saved.id,
            attempt: 2,
        };
        assert!(state.continue_mission(owner, request));
        assert!(!state.continue_mission(owner, request));
        let player = state.players.iter().find(|p| p.id == owner).unwrap();
        assert_eq!(
            (player.hp, player.armor, player.inventory.grenades()),
            (61, 7, 3)
        );
        assert_eq!(player.body, saved.body.unwrap());
        assert_eq!(player.last_input_seq, Some(91));
        assert!(player.inventory.revision() >= revision);
        assert_eq!(state.tick, 173);
        let after = state.mission_state().unwrap();
        assert_eq!(after.attempt, 3);
        assert_eq!(after.run.unwrap().continues, 1);
        let facts = after.m06.unwrap();
        assert!(facts.completed.is_empty());
        assert!(!facts.prisoner_route_marked);
        assert_eq!(facts.carried_recall_cars, ["platform_car", "roof_car"]);
        assert_eq!(facts.carried_patients, ["patient_a", "patient_b"]);
        assert_eq!(facts.carried_photos, 3);
        assert_eq!(
            facts.carried_released_workers,
            saved.m05_outcome.as_ref().unwrap().released_workers
        );
        assert_eq!(facts.carried_evacuated_workers, ["workshop_agent_b"]);
        let retry = state.campaign_run_document().unwrap().unwrap();
        assert_eq!(retry.m03_outcome, saved.m03_outcome);
        assert_eq!(retry.m04_outcome, saved.m04_outcome);
        assert_eq!(retry.m05_outcome, saved.m05_outcome);
        assert!(retry.m06_outcome.is_none());
        assert_eq!(retry.attempt(), 3);
    }

    #[test]
    fn m06_completion_saves_live_exit_optional_route_and_immutable_earth_choices() {
        let map = crate::maps::AuthoredSource::Mission(MissionId::PortOfEntry)
            .load()
            .unwrap();
        let hash = RuntimeMap::Authored(map.clone()).content_sha256().unwrap();
        let saved = completed_workshop_document()
            .promote_next(MissionId::PortOfEntry, hash)
            .unwrap();
        let mut state = GameState::with_authored_map(map);
        state.load_campaign_run(&saved).unwrap();
        let owner = Uuid::from_u128(6067);
        state.add_player(owner, "Transit runner".into(), Role::Human);
        let player = state.players.iter_mut().find(|p| p.id == owner).unwrap();
        assert!(player.inventory.try_throw());
        player.hp = 47;
        let exit = SavedEntry::from_player(player).unwrap();
        let run = state.mission.as_mut().unwrap();
        run.m06.as_mut().unwrap().index = 6;
        run.m06.as_mut().unwrap().prisoner_route_marked = true;
        run.phase = MissionPhase::Departed;
        let solo = run.solo.as_mut().unwrap();
        solo.capture_exit(exit.clone());
        solo.state.status = CampaignRunStatus::Complete;
        let complete = state.campaign_run_document().unwrap().unwrap();
        complete.validate(hash).unwrap();
        assert_eq!(complete.m03_outcome, saved.m03_outcome);
        assert_eq!(complete.m04_outcome, saved.m04_outcome);
        assert_eq!(complete.m05_outcome, saved.m05_outcome);
        assert_eq!(
            complete.m06_outcome,
            Some(M06Outcome {
                prisoner_route_marked: true
            })
        );
        assert_eq!(
            complete.step,
            SavedStep::AwaitingMission {
                completed_mission: MissionId::PortOfEntry,
                next_mission: M07_MISSION.into(),
                exit,
            }
        );
        state.remove_player(owner);
        assert_eq!(state.campaign_run_document().unwrap(), Some(complete));
    }

    #[test]
    fn m05_completion_projects_live_exit_and_distinct_release_boarding_facts() {
        let map = crate::maps::AuthoredSource::Mission(MissionId::NoForwardingAddress)
            .load()
            .unwrap();
        let hash = RuntimeMap::Authored(map.clone()).content_sha256().unwrap();
        let mut saved = completed_market_document()
            .promote_next(MissionId::NoForwardingAddress, hash)
            .unwrap();
        let SavedStep::MissionEntry { entry, .. } = &mut saved.step else {
            unreachable!();
        };
        entry.equipment.grenades = 3;
        let mut state = GameState::with_authored_map(map);
        state.load_campaign_run(&saved).unwrap();
        let owner = Uuid::from_u128(5056);
        state.add_player(owner, "Freight runner".into(), Role::Human);
        assert!(state.acknowledge_mission(
            owner,
            crate::protocol::MissionReady {
                id: MissionId::NoForwardingAddress,
                attempt: 1,
            }
        ));
        let player = state.players.iter_mut().find(|p| p.id == owner).unwrap();
        assert!(player.inventory.try_throw());
        player.hp = 47;
        let exit = SavedEntry::from_player(player).unwrap();
        let geometry = state.map.m05_geometry().unwrap();
        let aboard = *geometry.rescue.captives[0].route.last().unwrap();
        let run = state.mission.as_mut().unwrap();
        let progress = run.m05.as_mut().unwrap();
        progress.index = 6;
        progress.freight_open = true;
        progress.group_released = true;
        progress.captives[0].feet = aboard;
        state.map = run.initial_map.prepared_m05_world().unwrap();
        run.phase = crate::protocol::MissionPhase::Departed;
        let solo = run.solo.as_mut().unwrap();
        solo.capture_exit(exit.clone());
        solo.state.status = CampaignRunStatus::Complete;
        let complete = state.campaign_run_document().unwrap().unwrap();
        complete.validate(hash).unwrap();
        assert_eq!(complete.m03_outcome, saved.m03_outcome);
        assert_eq!(complete.m04_outcome, saved.m04_outcome);
        assert_eq!(
            complete.m05_outcome,
            Some(M05Outcome {
                released_workers: crate::protocol::M05_WORKER_IDS
                    .iter()
                    .map(|id| (*id).into())
                    .collect(),
                evacuated_workers: vec!["splice".into()],
            })
        );
        assert_eq!((exit.hp, exit.equipment.grenades), (47, 2));
        assert_eq!(
            complete.step,
            SavedStep::AwaitingMission {
                completed_mission: MissionId::NoForwardingAddress,
                next_mission: M06_MISSION.into(),
                exit,
            }
        );
        assert!(complete
            .promote_next(MissionId::NoForwardingAddress, hash)
            .is_err());
        state.remove_player(owner);
        assert_eq!(state.campaign_run_document().unwrap(), Some(complete));
    }

    #[test]
    fn completed_yard_promotes_exact_entry_and_retains_choices_through_m04() {
        let mut saved = document();
        saved.remaining_continues = 1;
        saved.level_start_continues = 2;
        saved.body = Some(BodyKind::Synthetic);
        let mut inventory = Inventory::new(EquipmentPolicy::Discovery);
        inventory.grant_weapon(WeaponType::Flechette);
        inventory.grant_ammo(AmmoPool::Bullets, 31);
        inventory.record_claim("yard_rifle".into());
        let exit = SavedEntry {
            hp: 63,
            armor: 17,
            equipment: inventory.saved_equipment(WeaponType::Flechette).unwrap(),
        };
        saved.step = SavedStep::AwaitingMission {
            completed_mission: MissionId::ScheduledService,
            next_mission: M04_MISSION.into(),
            exit: exit.clone(),
        };
        saved.m03_outcome = Some(M03Outcome {
            liberated_cars: vec!["platform_car".into()],
        });
        saved.validate([5; 32]).unwrap();
        let promoted = saved
            .promote_next(MissionId::NoticeToVacate, [6; 32])
            .unwrap();
        assert_eq!(
            (promoted.id, promoted.body, promoted.rules),
            (saved.id, saved.body, saved.rules)
        );
        assert_eq!(
            (
                promoted.remaining_continues,
                promoted.level_start_continues,
                promoted.attempt()
            ),
            (1, 1, 1)
        );
        assert_eq!(promoted.m03_outcome, saved.m03_outcome);
        let SavedStep::MissionEntry { mission, entry } = &promoted.step else {
            panic!("missing entry")
        };
        assert_eq!(*mission, MissionId::NoticeToVacate);
        assert_eq!((entry.hp, entry.armor), (63, 17));
        assert_eq!(entry.equipment.ammo, exit.equipment.ammo);
        assert_eq!(entry.equipment.weapons, exit.equipment.weapons);
        assert_eq!(entry.equipment.selected, exit.equipment.selected);
        assert!(entry.equipment.personal_claims.is_empty());
        let mut retry = promoted.clone();
        retry.step = SavedStep::PendingContinue {
            mission: *mission,
            entry: entry.clone(),
        };
        retry.validate([6; 32]).unwrap();
        retry.remaining_continues = 0;
        retry.step = SavedStep::Failed {
            mission: *mission,
            entry: entry.clone(),
        };
        retry.validate([6; 32]).unwrap();
        assert_eq!(retry.m03_outcome, promoted.m03_outcome);
        let mut completed = promoted;
        completed.step = SavedStep::AwaitingMission {
            completed_mission: MissionId::NoticeToVacate,
            next_mission: M05_MISSION.into(),
            exit,
        };
        assert!(completed.validate([6; 32]).is_err());
        completed.m04_outcome = Some(M04Outcome {
            rescued_patients: vec!["edda".into()],
            photos_completed: 3,
        });
        completed.validate([6; 32]).unwrap();
        completed.m04_outcome.as_mut().unwrap().photos_completed = 1_000_001;
        assert!(completed.validate([6; 32]).is_err());
        completed.m04_outcome.as_mut().unwrap().photos_completed = 0;
        completed.m04_outcome.as_mut().unwrap().rescued_patients =
            vec!["edda".into(), "edda".into()];
        assert!(completed.validate([6; 32]).is_err());
    }

    #[test]
    fn historical_v4_rejects_forged_rules_and_m04_before_upgrade() {
        let mut value = historical_value(&document());
        value["version"] = 4.into();
        value["rules"]["revision"] = 2.into();
        let legacy: RunDocumentV4 = serde_json::from_value(value.clone()).unwrap();
        let upgraded = legacy.upgrade([[5; 32]; 3]).unwrap();
        assert_eq!(upgraded.rules.revision, CAMPAIGN_RULES_REVISION);
        assert!(upgraded.m03_outcome.is_none() && upgraded.m04_outcome.is_none());
        value["rules"]["revision"] = 1.into();
        assert!(serde_json::from_value::<RunDocumentV4>(value.clone())
            .unwrap()
            .upgrade([[5; 32]; 3])
            .is_err());
        value["rules"]["revision"] = 2.into();
        value["step"]["mission"] = "notice_to_vacate".into();
        assert!(serde_json::from_value::<RunDocumentV4>(value.clone())
            .unwrap()
            .upgrade([[5; 32]; 3])
            .is_err());
        value["m04_outcome"] = serde_json::json!({"rescued_patients":[],"photos_completed":0});
        assert!(serde_json::from_value::<RunDocumentV4>(value).is_err());
    }

    #[test]
    fn live_m04_retry_preserves_yard_context_and_projects_pending_m05_outcome() {
        let map = crate::maps::AuthoredSource::Mission(MissionId::NoticeToVacate)
            .load()
            .unwrap();
        let hash = RuntimeMap::Authored(map.clone()).content_sha256().unwrap();
        let mut saved = document();
        saved.content_sha256 = hash;
        saved.remaining_continues = 1;
        saved.level_start_continues = 1;
        saved.body = Some(BodyKind::Synthetic);
        saved.m03_outcome = Some(M03Outcome {
            liberated_cars: vec!["roof_car".into()],
        });
        saved.step = SavedStep::MissionEntry {
            mission: MissionId::NoticeToVacate,
            entry: SavedEntry::initial(),
        };
        let mut state = GameState::with_authored_map(map);
        state.load_campaign_run(&saved).unwrap();
        let owner = Uuid::new_v4();
        state.add_player(owner, "Visitor".into(), Role::Human);
        assert!(state.acknowledge_mission(
            owner,
            crate::protocol::MissionReady {
                id: MissionId::NoticeToVacate,
                attempt: 1
            }
        ));
        let facts = state.mission_state().unwrap().m04.unwrap();
        assert_eq!(facts.carried_recall_cars, ["roof_car"]);
        {
            let progress = state.mission.as_mut().unwrap().m04.as_mut().unwrap();
            progress.photos_completed = 7;
            progress.patients_released = true;
        }
        state.players.iter_mut().find(|p| p.id == owner).unwrap().hp = 0;
        state.update_campaign_run();
        let retry = state.campaign_run_document().unwrap().unwrap();
        assert_eq!(retry.m03_outcome, saved.m03_outcome);
        assert!(retry.m04_outcome.is_none());
        assert!(state.continue_mission(
            owner,
            MissionContinue {
                id: MissionId::NoticeToVacate,
                run_id: saved.id,
                attempt: 1
            }
        ));
        let facts = state.mission_state().unwrap().m04.unwrap();
        assert_eq!(
            (facts.photos_completed, facts.patients_released),
            (0, false)
        );
        assert_eq!(facts.carried_recall_cars, ["roof_car"]);
        let live = state.campaign_run_document().unwrap().unwrap();
        assert_eq!(
            (
                live.remaining_continues,
                live.level_start_continues,
                live.attempt()
            ),
            (0, 1, 2)
        );
        assert_eq!(live.m03_outcome, saved.m03_outcome);
        let exit =
            SavedEntry::from_player(state.players.iter().find(|p| p.id == owner).unwrap()).unwrap();
        let run = state.mission.as_mut().unwrap();
        let progress = run.m04.as_mut().unwrap();
        progress.photos_completed = 3;
        progress.patients_released = true;
        let patients: Vec<String> = progress.patients.iter().map(|p| p.id.clone()).collect();
        state.map = run.initial_map.prepared_m04_world().unwrap();
        run.phase = crate::protocol::MissionPhase::Departed;
        let solo = run.solo.as_mut().unwrap();
        solo.capture_exit(exit.clone());
        solo.state.status = CampaignRunStatus::Complete;
        let complete = state.campaign_run_document().unwrap().unwrap();
        complete.validate(hash).unwrap();
        assert_eq!(complete.m03_outcome, saved.m03_outcome);
        assert_eq!(
            complete.m04_outcome,
            Some(M04Outcome {
                rescued_patients: patients,
                photos_completed: 3
            })
        );
        assert_eq!(
            complete.step,
            SavedStep::AwaitingMission {
                completed_mission: MissionId::NoticeToVacate,
                next_mission: M05_MISSION.into(),
                exit
            }
        );
        state.remove_player(owner);
        assert_eq!(state.campaign_run_document().unwrap(), Some(complete));
    }
}
