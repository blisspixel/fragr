//! Strict historical save shapes. Versions before 6 have no grenade fields.
use super::*;

/// Version 6 includes real grenade counts but cannot represent playable M06.
/// Decode its exact fields before upgrading; do not default away equipment or
/// accept future outcomes under a historical version number.
#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct RunDocumentV6 {
    pub version: u32,
    pub id: Uuid,
    pub starting_continues: u8,
    pub remaining_continues: u8,
    pub level_start_continues: u8,
    pub body: Option<BodyKind>,
    pub rules: CampaignRules,
    pub content_sha256: [u8; 32],
    pub step: SavedStep,
    #[serde(default)]
    pub m03_outcome: Option<M03Outcome>,
    #[serde(default)]
    pub m04_outcome: Option<M04Outcome>,
    #[serde(default)]
    pub m05_outcome: Option<M05Outcome>,
}

impl RunDocumentV6 {
    pub fn upgrade(self, hashes: [[u8; 32]; 5]) -> Result<RunDocument, &'static str> {
        if self.version != 6 || self.rules.revision != CAMPAIGN_RULES_REVISION {
            return Err("unsupported historical campaign rules");
        }
        let document = RunDocument {
            version: RUN_FILE_VERSION,
            id: self.id,
            starting_continues: self.starting_continues,
            remaining_continues: self.remaining_continues,
            level_start_continues: self.level_start_continues,
            body: self.body,
            rules: self.rules,
            content_sha256: self.content_sha256,
            step: self.step,
            m03_outcome: self.m03_outcome,
            m04_outcome: self.m04_outcome,
            m05_outcome: self.m05_outcome,
            m06_outcome: None,
        };
        let hash = match document.stage_mission() {
            MissionId::RecallNotice => hashes[0],
            MissionId::PersonsUnknown => hashes[1],
            MissionId::ScheduledService => hashes[2],
            MissionId::NoticeToVacate => hashes[3],
            MissionId::NoForwardingAddress => hashes[4],
            MissionId::PortOfEntry => return Err("M06 was not supported by version 6"),
        };
        document.validate(hash)?;
        Ok(document)
    }
}

/// Historical equipment had no grenade field. Decode its exact shape before
/// assigning zero; a forged old count must never become a carried unlock.
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct LegacyEquipment {
    selected: WeaponType,
    weapons: Vec<WeaponType>,
    ammo: Vec<crate::protocol::AmmoCount>,
    personal_claims: Vec<String>,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct LegacyEntry {
    hp: i32,
    armor: i32,
    equipment: LegacyEquipment,
}

impl From<LegacyEntry> for SavedEntry {
    fn from(old: LegacyEntry) -> Self {
        Self {
            hp: old.hp,
            armor: old.armor,
            equipment: SavedEquipment {
                selected: old.equipment.selected,
                weapons: old.equipment.weapons,
                ammo: old.equipment.ammo,
                personal_claims: old.equipment.personal_claims,
                grenades: 0,
            },
        }
    }
}

#[derive(Deserialize)]
#[serde(tag = "kind", rename_all = "snake_case", deny_unknown_fields)]
enum LegacyStep {
    MissionEntry {
        mission: MissionId,
        entry: LegacyEntry,
    },
    PendingContinue {
        mission: MissionId,
        entry: LegacyEntry,
    },
    Failed {
        mission: MissionId,
        entry: LegacyEntry,
    },
    Abandoned {
        mission: MissionId,
        entry: LegacyEntry,
    },
    AwaitingMission {
        completed_mission: MissionId,
        next_mission: String,
        exit: LegacyEntry,
    },
}

fn deserialize_legacy_step<'de, D: serde::Deserializer<'de>>(
    decoder: D,
) -> Result<SavedStep, D::Error> {
    Ok(match LegacyStep::deserialize(decoder)? {
        LegacyStep::MissionEntry { mission, entry } => SavedStep::MissionEntry {
            mission,
            entry: entry.into(),
        },
        LegacyStep::PendingContinue { mission, entry } => SavedStep::PendingContinue {
            mission,
            entry: entry.into(),
        },
        LegacyStep::Failed { mission, entry } => SavedStep::Failed {
            mission,
            entry: entry.into(),
        },
        LegacyStep::Abandoned { mission, entry } => SavedStep::Abandoned {
            mission,
            entry: entry.into(),
        },
        LegacyStep::AwaitingMission {
            completed_mission,
            next_mission,
            exit,
        } => SavedStep::AwaitingMission {
            completed_mission,
            next_mission,
            exit: exit.into(),
        },
    })
}

#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct RunDocumentV5 {
    pub version: u32,
    pub id: Uuid,
    pub starting_continues: u8,
    pub remaining_continues: u8,
    pub level_start_continues: u8,
    pub body: Option<BodyKind>,
    pub rules: CampaignRules,
    pub content_sha256: [u8; 32],
    #[serde(deserialize_with = "deserialize_legacy_step")]
    pub step: SavedStep,
    #[serde(default)]
    pub m03_outcome: Option<M03Outcome>,
    #[serde(default)]
    pub m04_outcome: Option<M04Outcome>,
}

impl RunDocumentV5 {
    pub fn upgrade(self, hashes: [[u8; 32]; 4]) -> Result<RunDocument, &'static str> {
        if self.version != 5 || self.rules.revision != 3 {
            return Err("unsupported historical campaign rules");
        }
        let document = RunDocument {
            version: RUN_FILE_VERSION,
            id: self.id,
            starting_continues: self.starting_continues,
            remaining_continues: self.remaining_continues,
            level_start_continues: self.level_start_continues,
            body: self.body,
            rules: CampaignRules::new(self.rules.difficulty),
            content_sha256: self.content_sha256,
            step: self.step,
            m03_outcome: self.m03_outcome,
            m04_outcome: self.m04_outcome,
            m05_outcome: None,
            m06_outcome: None,
        };
        let hash = match document.stage_mission() {
            MissionId::RecallNotice => hashes[0],
            MissionId::PersonsUnknown => hashes[1],
            MissionId::ScheduledService => hashes[2],
            MissionId::NoticeToVacate => hashes[3],
            MissionId::NoForwardingAddress | MissionId::PortOfEntry => {
                return Err("M05 was not supported by version 5")
            }
        };
        document.validate(hash)?;
        Ok(document)
    }
}

/// Strict previous shape, decoded before applying the unchanged earlier tiers.
#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct RunDocumentV4 {
    pub version: u32,
    pub id: Uuid,
    pub starting_continues: u8,
    pub remaining_continues: u8,
    pub level_start_continues: u8,
    pub body: Option<BodyKind>,
    pub rules: CampaignRules,
    pub content_sha256: [u8; 32],
    #[serde(deserialize_with = "deserialize_legacy_step")]
    pub step: SavedStep,
    #[serde(default)]
    pub m03_outcome: Option<M03Outcome>,
}

impl RunDocumentV4 {
    pub fn upgrade(self, hashes: [[u8; 32]; 3]) -> Result<RunDocument, &'static str> {
        if self.version != 4 || self.rules.revision != 2 {
            return Err("unsupported historical campaign rules");
        }
        let expected = match &self.step {
            SavedStep::MissionEntry { mission, .. }
            | SavedStep::PendingContinue { mission, .. }
            | SavedStep::Failed { mission, .. }
            | SavedStep::Abandoned { mission, .. } => match mission {
                MissionId::RecallNotice => hashes[0],
                MissionId::PersonsUnknown => hashes[1],
                MissionId::ScheduledService => hashes[2],
                MissionId::NoticeToVacate
                | MissionId::NoForwardingAddress
                | MissionId::PortOfEntry => return Err("mission was not supported by version 4"),
            },
            SavedStep::AwaitingMission {
                completed_mission, ..
            } => match completed_mission {
                MissionId::RecallNotice => hashes[0],
                MissionId::PersonsUnknown => hashes[1],
                MissionId::ScheduledService => hashes[2],
                MissionId::NoticeToVacate
                | MissionId::NoForwardingAddress
                | MissionId::PortOfEntry => return Err("mission was not supported by version 4"),
            },
        };
        let document = RunDocument {
            version: RUN_FILE_VERSION,
            id: self.id,
            starting_continues: self.starting_continues,
            remaining_continues: self.remaining_continues,
            level_start_continues: self.level_start_continues,
            body: self.body,
            rules: CampaignRules::new(self.rules.difficulty),
            content_sha256: self.content_sha256,
            step: self.step,
            m03_outcome: self.m03_outcome,
            m04_outcome: None,
            m05_outcome: None,
            m06_outcome: None,
        };
        document.validate(expected)?;
        Ok(document)
    }
}

/// Version 3 had body and level allowance, but no playable M03 or car outcome.
#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct RunDocumentV3 {
    pub version: u32,
    pub id: Uuid,
    pub starting_continues: u8,
    pub remaining_continues: u8,
    pub level_start_continues: u8,
    pub body: Option<BodyKind>,
    pub rules: CampaignRules,
    pub content_sha256: [u8; 32],
    #[serde(deserialize_with = "deserialize_legacy_step")]
    pub step: SavedStep,
}

impl RunDocumentV3 {
    pub fn upgrade(
        self,
        m01_hash: [u8; 32],
        m02_hash: [u8; 32],
    ) -> Result<RunDocument, &'static str> {
        let document = RunDocument {
            version: RUN_FILE_VERSION,
            id: self.id,
            starting_continues: self.starting_continues,
            remaining_continues: self.remaining_continues,
            level_start_continues: self.level_start_continues,
            body: self.body,
            rules: CampaignRules::new(self.rules.difficulty),
            content_sha256: self.content_sha256,
            step: self.step,
            m03_outcome: None,
            m04_outcome: None,
            m05_outcome: None,
            m06_outcome: None,
        };
        let expected = match document.stage_mission() {
            MissionId::RecallNotice => m01_hash,
            MissionId::PersonsUnknown => m02_hash,
            MissionId::ScheduledService => return Err("M03 was not supported by version 3"),
            MissionId::NoticeToVacate => return Err("M04 was not supported by version 3"),
            MissionId::NoForwardingAddress | MissionId::PortOfEntry => {
                return Err("M05 was not supported by version 3")
            }
        };
        if self.version != 3 || self.rules.revision != 2 {
            return Err("unsupported legacy campaign run");
        }
        document.validate(expected)?;
        Ok(document)
    }
}

/// The released version 2 shape is decoded explicitly. It had no body or
/// per-level baseline and could only represent M01 or its pending M02 edge.
#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct RunDocumentV2 {
    pub version: u32,
    pub id: Uuid,
    pub starting_continues: u8,
    pub remaining_continues: u8,
    pub rules: CampaignRules,
    pub content_sha256: [u8; 32],
    #[serde(deserialize_with = "deserialize_legacy_step")]
    pub step: SavedStep,
}

impl RunDocumentV2 {
    pub fn upgrade(self, m01_hash: [u8; 32]) -> Result<RunDocument, &'static str> {
        let supported = match &self.step {
            SavedStep::MissionEntry { mission, .. }
            | SavedStep::PendingContinue { mission, .. }
            | SavedStep::Failed { mission, .. }
            | SavedStep::Abandoned { mission, .. } => *mission == MissionId::RecallNotice,
            SavedStep::AwaitingMission {
                completed_mission,
                next_mission,
                ..
            } => *completed_mission == MissionId::RecallNotice && next_mission == M02_MISSION,
        };
        if self.version != 2 || self.rules.revision != 2 || !supported {
            return Err("unsupported legacy campaign run");
        }
        let document = RunDocument {
            version: RUN_FILE_VERSION,
            id: self.id,
            starting_continues: self.starting_continues,
            remaining_continues: self.remaining_continues,
            level_start_continues: CAMPAIGN_CONTINUES,
            body: None,
            rules: CampaignRules::new(self.rules.difficulty),
            content_sha256: self.content_sha256,
            step: self.step,
            m03_outcome: None,
            m04_outcome: None,
            m05_outcome: None,
            m06_outcome: None,
        };
        document.validate(m01_hash)?;
        Ok(document)
    }
}
