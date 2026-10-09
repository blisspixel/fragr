//! Strict historical save shapes. Versions before 6 have no grenade fields.
use super::*;

/// Exact v10 shape. It records M08 choices but predates Repeater ownership.
#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct RunDocumentV10 {
    pub version: u32,
    pub id: Uuid,
    pub starting_continues: u8,
    pub remaining_continues: u8,
    pub level_start_continues: u8,
    pub body: Option<BodyKind>,
    pub rules: CampaignRules,
    pub content_sha256: [u8; 32],
    #[serde(deserialize_with = "deserialize_pre_repeater_step")]
    pub step: SavedStep,
    #[serde(default)]
    pub m03_outcome: Option<M03Outcome>,
    #[serde(default)]
    pub m04_outcome: Option<M04Outcome>,
    #[serde(default)]
    pub m05_outcome: Option<M05Outcome>,
    #[serde(default)]
    pub m06_outcome: Option<M06Outcome>,
    #[serde(default)]
    pub m08_outcome: Option<M08Outcome>,
}

/// Version 11 has the identical exact fields. Its supported stages still
/// refuse Repeater; neither historical format recorded M09 crew outcomes.
pub(crate) type RunDocumentV11 = RunDocumentV10;

impl RunDocumentV10 {
    pub fn upgrade(self, hashes: store::ContentHashes) -> Result<RunDocument, &'static str> {
        self.upgrade_version(hashes, 10)
    }

    pub fn upgrade_v11(self, hashes: store::ContentHashes) -> Result<RunDocument, &'static str> {
        self.upgrade_version(hashes, 11)
    }

    fn upgrade_version(
        self,
        hashes: store::ContentHashes,
        expected_version: u32,
    ) -> Result<RunDocument, &'static str> {
        if self.version != expected_version || self.rules.revision != PRE_ASSESSOR_RULES_REVISION {
            return Err("unsupported historical campaign rules");
        }
        let completed_m09 = matches!(&self.step, SavedStep::AwaitingMission {
            completed_mission: MissionId::PassengerManifest, next_mission, ..
        } if next_mission == M10_MISSION);
        let mut document = RunDocument {
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
            m05_outcome: self.m05_outcome,
            m06_outcome: self.m06_outcome,
            m08_outcome: self.m08_outcome,
            m09_outcome: completed_m09.then_some(M09Outcome::HistoricalUnrecorded {}),
            m10_transit: None,
            m11_outcome: None,
            m12_outcome: None,
        };
        document.migrate_historical_rockets()?;
        document.validate(
            *hashes[..9]
                .get(store::stage_index(document.stage_mission()))
                .ok_or("mission was not supported by this historical version")?,
        )?;
        Ok(document)
    }
}

fn pre_repeater_step(step: SavedStep) -> Result<SavedStep, &'static str> {
    let step = super::legacy_v14::pre_arc_step(step)?;
    if matches!(
        &step,
        SavedStep::MissionEntry {
            mission: MissionId::CommonCarrier,
            ..
        } | SavedStep::PendingContinue {
            mission: MissionId::CommonCarrier,
            ..
        } | SavedStep::Failed {
            mission: MissionId::CommonCarrier,
            ..
        } | SavedStep::Abandoned {
            mission: MissionId::CommonCarrier,
            ..
        } | SavedStep::AwaitingMission {
            completed_mission: MissionId::CommonCarrier,
            ..
        }
    ) {
        return Err("historical saves cannot contain M10");
    }
    let entry = match &step {
        SavedStep::MissionEntry { entry, .. }
        | SavedStep::PendingContinue { entry, .. }
        | SavedStep::Failed { entry, .. }
        | SavedStep::Abandoned { entry, .. } => entry,
        SavedStep::AwaitingMission { exit, .. } => exit,
    };
    if entry.equipment.selected == WeaponType::Repeater
        || entry.equipment.weapons.contains(&WeaponType::Repeater)
    {
        return Err("historical saves cannot carry Repeater");
    }
    Ok(step)
}

fn deserialize_pre_repeater_step<'de, D: serde::Deserializer<'de>>(
    decoder: D,
) -> Result<SavedStep, D::Error> {
    pre_repeater_step(convert_step(LegacyStep::<PreRemoteEquipment>::deserialize(
        decoder,
    )?))
    .map_err(serde::de::Error::custom)
}

/// Exact version 9 shape, including real finite mines but no archive outcomes.
#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct RunDocumentV9 {
    pub version: u32,
    pub id: Uuid,
    pub starting_continues: u8,
    pub remaining_continues: u8,
    pub level_start_continues: u8,
    pub body: Option<BodyKind>,
    pub rules: CampaignRules,
    pub content_sha256: [u8; 32],
    #[serde(deserialize_with = "deserialize_pre_repeater_step")]
    pub step: SavedStep,
    #[serde(default)]
    pub m03_outcome: Option<M03Outcome>,
    #[serde(default)]
    pub m04_outcome: Option<M04Outcome>,
    #[serde(default)]
    pub m05_outcome: Option<M05Outcome>,
    #[serde(default)]
    pub m06_outcome: Option<M06Outcome>,
}

impl RunDocumentV9 {
    pub fn upgrade(self, hashes: store::ContentHashes) -> Result<RunDocument, &'static str> {
        if self.version != 9 || self.rules.revision != PRE_ASSESSOR_RULES_REVISION {
            return Err("unsupported historical campaign rules");
        }
        if matches!(
            &self.step,
            SavedStep::MissionEntry {
                mission: MissionId::PassengerManifest,
                ..
            } | SavedStep::PendingContinue {
                mission: MissionId::PassengerManifest,
                ..
            } | SavedStep::Failed {
                mission: MissionId::PassengerManifest,
                ..
            } | SavedStep::Abandoned {
                mission: MissionId::PassengerManifest,
                ..
            } | SavedStep::AwaitingMission {
                completed_mission: MissionId::PassengerManifest,
                ..
            }
        ) {
            return Err("M09 was not supported by version 9");
        }
        let completed_m08 = matches!(&self.step, SavedStep::AwaitingMission {
            completed_mission: MissionId::CustodianOfRecord, next_mission, ..
        } if next_mission == M09_MISSION);
        let mut document = RunDocument {
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
            m05_outcome: self.m05_outcome,
            m06_outcome: self.m06_outcome,
            m08_outcome: completed_m08.then_some(M08Outcome::HistoricalUnrecorded {}),
            m09_outcome: None,
            m10_transit: None,
            m11_outcome: None,
            m12_outcome: None,
        };
        document.migrate_historical_rockets()?;
        document.validate(
            *hashes[..8]
                .get(store::stage_index(document.stage_mission()))
                .ok_or("mission was not supported by this historical version")?,
        )?;
        Ok(document)
    }
}

/// Version 8 supports M07 and its pending M08 edge, with no saved mines.
#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct RunDocumentV8 {
    pub version: u32,
    pub id: Uuid,
    pub starting_continues: u8,
    pub remaining_continues: u8,
    pub level_start_continues: u8,
    pub body: Option<BodyKind>,
    pub rules: CampaignRules,
    pub content_sha256: [u8; 32],
    #[serde(deserialize_with = "deserialize_pre_mine_step")]
    pub step: SavedStep,
    #[serde(default)]
    pub m03_outcome: Option<M03Outcome>,
    #[serde(default)]
    pub m04_outcome: Option<M04Outcome>,
    #[serde(default)]
    pub m05_outcome: Option<M05Outcome>,
    #[serde(default)]
    pub m06_outcome: Option<M06Outcome>,
}

impl RunDocumentV8 {
    pub fn upgrade(self, hashes: store::ContentHashes) -> Result<RunDocument, &'static str> {
        if self.version != 8 || self.rules.revision != PRE_ASSESSOR_RULES_REVISION {
            return Err("unsupported historical campaign rules");
        }
        let mut document = RunDocument {
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
            m05_outcome: self.m05_outcome,
            m06_outcome: self.m06_outcome,
            m08_outcome: None,
            m09_outcome: None,
            m10_transit: None,
            m11_outcome: None,
            m12_outcome: None,
        };
        let mission = document.stage_mission();
        if matches!(
            mission,
            MissionId::CustodianOfRecord | MissionId::PassengerManifest | MissionId::CommonCarrier
        ) {
            return Err("M08 was not supported by version 8");
        }
        document.migrate_historical_rockets()?;
        document.validate(
            *hashes[..7]
                .get(store::stage_index(mission))
                .ok_or("mission was not supported by this historical version")?,
        )?;
        Ok(document)
    }
}

/// Version 7 has the prior fields but cannot represent playable M07, its
/// pending level 8 edge or a carried Sniper Rifle. Decode its exact shape and
/// refuse anything only version 8 can mean before upgrading.
#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct RunDocumentV7 {
    pub version: u32,
    pub id: Uuid,
    pub starting_continues: u8,
    pub remaining_continues: u8,
    pub level_start_continues: u8,
    pub body: Option<BodyKind>,
    pub rules: CampaignRules,
    pub content_sha256: [u8; 32],
    #[serde(deserialize_with = "deserialize_pre_mine_step")]
    pub step: SavedStep,
    #[serde(default)]
    pub m03_outcome: Option<M03Outcome>,
    #[serde(default)]
    pub m04_outcome: Option<M04Outcome>,
    #[serde(default)]
    pub m05_outcome: Option<M05Outcome>,
    #[serde(default)]
    pub m06_outcome: Option<M06Outcome>,
}

impl RunDocumentV7 {
    pub fn upgrade(self, hashes: store::ContentHashes) -> Result<RunDocument, &'static str> {
        if self.version != 7 || self.rules.revision != PRE_ASSESSOR_RULES_REVISION {
            return Err("unsupported historical campaign rules");
        }
        let mut document = RunDocument {
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
            m05_outcome: self.m05_outcome,
            m06_outcome: self.m06_outcome,
            m08_outcome: None,
            m09_outcome: None,
            m10_transit: None,
            m11_outcome: None,
            m12_outcome: None,
        };
        let mission = document.stage_mission();
        if matches!(
            mission,
            MissionId::DeclaredGoods | MissionId::CustodianOfRecord
        ) {
            return Err("mission was not supported by version 7");
        }
        document.migrate_historical_rockets()?;
        document.validate(
            *hashes[..6]
                .get(store::stage_index(mission))
                .ok_or("mission was not supported by this historical version")?,
        )?;
        Ok(document)
    }
}

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
    #[serde(deserialize_with = "deserialize_pre_mine_step")]
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
        if self.version != 6 || self.rules.revision != PRE_ASSESSOR_RULES_REVISION {
            return Err("unsupported historical campaign rules");
        }
        let mut document = RunDocument {
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
            m05_outcome: self.m05_outcome,
            m06_outcome: None,
            m08_outcome: None,
            m09_outcome: None,
            m10_transit: None,
            m11_outcome: None,
            m12_outcome: None,
        };
        let hash = match document.stage_mission() {
            MissionId::RecallNotice => hashes[0],
            MissionId::PersonsUnknown => hashes[1],
            MissionId::ScheduledService => hashes[2],
            MissionId::NoticeToVacate => hashes[3],
            MissionId::NoForwardingAddress => hashes[4],
            MissionId::PortOfEntry => return Err("M06 was not supported by version 6"),
            MissionId::DeclaredGoods
            | MissionId::CustodianOfRecord
            | MissionId::PassengerManifest
            | MissionId::CommonCarrier
            | MissionId::RightOfSearch
            | MissionId::TermsOfCooperation => return Err("M08 was not supported by version 6"),
        };
        document.migrate_historical_rockets()?;
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

impl From<LegacyEquipment> for SavedEquipment {
    fn from(old: LegacyEquipment) -> Self {
        Self {
            selected: old.selected,
            weapons: old.weapons,
            ammo: old.ammo,
            grenades: 0,
            proximity_mines: 0,
            remote_mines: 0,
            personal_claims: old.personal_claims,
        }
    }
}

/// Versions 6 through 8 required grenades but could not store mines.
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct PreMineEquipment {
    selected: WeaponType,
    weapons: Vec<WeaponType>,
    ammo: Vec<crate::protocol::AmmoCount>,
    grenades: u16,
    personal_claims: Vec<String>,
}

impl From<PreMineEquipment> for SavedEquipment {
    fn from(old: PreMineEquipment) -> Self {
        Self {
            selected: old.selected,
            weapons: old.weapons,
            ammo: old.ammo,
            grenades: old.grenades,
            proximity_mines: 0,
            remote_mines: 0,
            personal_claims: old.personal_claims,
        }
    }
}

/// Exact equipment from versions 9 through 13. Even a zero-valued forged
/// remote field is refused before assigning historical zero.
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct PreRemoteEquipment {
    selected: WeaponType,
    weapons: Vec<WeaponType>,
    ammo: Vec<crate::protocol::AmmoCount>,
    grenades: u16,
    proximity_mines: u16,
    personal_claims: Vec<String>,
}

impl From<PreRemoteEquipment> for SavedEquipment {
    fn from(old: PreRemoteEquipment) -> Self {
        Self {
            selected: old.selected,
            weapons: old.weapons,
            ammo: old.ammo,
            grenades: old.grenades,
            proximity_mines: old.proximity_mines,
            remote_mines: 0,
            personal_claims: old.personal_claims,
        }
    }
}

fn deserialize_pre_remote_step<'de, D: serde::Deserializer<'de>>(
    decoder: D,
) -> Result<SavedStep, D::Error> {
    super::legacy_v14::pre_arc_step(convert_step(LegacyStep::<PreRemoteEquipment>::deserialize(
        decoder,
    )?))
    .map_err(serde::de::Error::custom)
}

/// Exact version 13 fields, including real M10 transit and Repeater carry,
/// but no Remote Mine inventory or playable M11.
#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct RunDocumentV13 {
    pub version: u32,
    pub id: Uuid,
    pub starting_continues: u8,
    pub remaining_continues: u8,
    pub level_start_continues: u8,
    pub body: Option<BodyKind>,
    pub rules: CampaignRules,
    pub content_sha256: [u8; 32],
    #[serde(deserialize_with = "deserialize_pre_remote_step")]
    pub step: SavedStep,
    #[serde(default)]
    pub m03_outcome: Option<M03Outcome>,
    #[serde(default)]
    pub m04_outcome: Option<M04Outcome>,
    #[serde(default)]
    pub m05_outcome: Option<M05Outcome>,
    #[serde(default)]
    pub m06_outcome: Option<M06Outcome>,
    #[serde(default)]
    pub m08_outcome: Option<M08Outcome>,
    #[serde(default)]
    pub m09_outcome: Option<M09Outcome>,
    #[serde(default)]
    pub m10_transit: Option<crate::protocol::M10Transit>,
}

impl RunDocumentV13 {
    pub fn upgrade(self, hashes: store::ContentHashes) -> Result<RunDocument, &'static str> {
        if self.version != 13
            || self.rules.revision != PRE_ASSESSOR_RULES_REVISION
            || match &self.step {
                SavedStep::MissionEntry { mission, .. }
                | SavedStep::PendingContinue { mission, .. }
                | SavedStep::Failed { mission, .. }
                | SavedStep::Abandoned { mission, .. } => matches!(
                    *mission,
                    MissionId::RightOfSearch | MissionId::TermsOfCooperation
                ),
                SavedStep::AwaitingMission {
                    completed_mission, ..
                } => matches!(
                    *completed_mission,
                    MissionId::RightOfSearch | MissionId::TermsOfCooperation
                ),
            }
        {
            return Err("unsupported historical campaign rules");
        }
        let mut document = RunDocument {
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
            m05_outcome: self.m05_outcome,
            m06_outcome: self.m06_outcome,
            m08_outcome: self.m08_outcome,
            m09_outcome: self.m09_outcome,
            m10_transit: self.m10_transit,
            m11_outcome: None,
            m12_outcome: None,
        };
        document.migrate_historical_rockets()?;
        document.validate(
            *hashes[..10]
                .get(store::stage_index(document.stage_mission()))
                .ok_or("mission was not supported by this historical version")?,
        )?;
        Ok(document)
    }
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct LegacyEntry<E> {
    hp: i32,
    armor: i32,
    equipment: E,
}

impl<E: Into<SavedEquipment>> From<LegacyEntry<E>> for SavedEntry {
    fn from(old: LegacyEntry<E>) -> Self {
        Self {
            hp: old.hp,
            armor: old.armor,
            equipment: old.equipment.into(),
        }
    }
}

#[derive(Deserialize)]
#[serde(tag = "kind", rename_all = "snake_case", deny_unknown_fields)]
enum LegacyStep<E> {
    MissionEntry {
        mission: MissionId,
        entry: LegacyEntry<E>,
    },
    PendingContinue {
        mission: MissionId,
        entry: LegacyEntry<E>,
    },
    Failed {
        mission: MissionId,
        entry: LegacyEntry<E>,
    },
    Abandoned {
        mission: MissionId,
        entry: LegacyEntry<E>,
    },
    AwaitingMission {
        completed_mission: MissionId,
        next_mission: String,
        exit: LegacyEntry<E>,
    },
}

fn deserialize_legacy_step<'de, D: serde::Deserializer<'de>>(
    decoder: D,
) -> Result<SavedStep, D::Error> {
    pre_repeater_step(convert_step(LegacyStep::<LegacyEquipment>::deserialize(
        decoder,
    )?))
    .map_err(serde::de::Error::custom)
}

fn deserialize_pre_mine_step<'de, D: serde::Deserializer<'de>>(
    decoder: D,
) -> Result<SavedStep, D::Error> {
    pre_repeater_step(convert_step(LegacyStep::<PreMineEquipment>::deserialize(
        decoder,
    )?))
    .map_err(serde::de::Error::custom)
}

fn convert_step<E: Into<SavedEquipment>>(step: LegacyStep<E>) -> SavedStep {
    match step {
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
    }
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
        let mut document = RunDocument {
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
            m08_outcome: None,
            m09_outcome: None,
            m10_transit: None,
            m11_outcome: None,
            m12_outcome: None,
        };
        let hash = match document.stage_mission() {
            MissionId::RecallNotice => hashes[0],
            MissionId::PersonsUnknown => hashes[1],
            MissionId::ScheduledService => hashes[2],
            MissionId::NoticeToVacate => hashes[3],
            MissionId::NoForwardingAddress
            | MissionId::PortOfEntry
            | MissionId::DeclaredGoods
            | MissionId::CustodianOfRecord
            | MissionId::PassengerManifest
            | MissionId::CommonCarrier
            | MissionId::RightOfSearch
            | MissionId::TermsOfCooperation => return Err("M05 was not supported by version 5"),
        };
        document.migrate_historical_rockets()?;
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
                | MissionId::PortOfEntry
                | MissionId::DeclaredGoods
                | MissionId::CustodianOfRecord
                | MissionId::PassengerManifest
                | MissionId::CommonCarrier
                | MissionId::RightOfSearch
                | MissionId::TermsOfCooperation => {
                    return Err("mission was not supported by version 4")
                }
            },
            SavedStep::AwaitingMission {
                completed_mission, ..
            } => match completed_mission {
                MissionId::RecallNotice => hashes[0],
                MissionId::PersonsUnknown => hashes[1],
                MissionId::ScheduledService => hashes[2],
                MissionId::NoticeToVacate
                | MissionId::NoForwardingAddress
                | MissionId::PortOfEntry
                | MissionId::DeclaredGoods
                | MissionId::CustodianOfRecord
                | MissionId::PassengerManifest
                | MissionId::CommonCarrier
                | MissionId::RightOfSearch
                | MissionId::TermsOfCooperation => {
                    return Err("mission was not supported by version 4")
                }
            },
        };
        let mut document = RunDocument {
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
            m08_outcome: None,
            m09_outcome: None,
            m10_transit: None,
            m11_outcome: None,
            m12_outcome: None,
        };
        document.migrate_historical_rockets()?;
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
        let mut document = RunDocument {
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
            m08_outcome: None,
            m09_outcome: None,
            m10_transit: None,
            m11_outcome: None,
            m12_outcome: None,
        };
        let expected = match document.stage_mission() {
            MissionId::RecallNotice => m01_hash,
            MissionId::PersonsUnknown => m02_hash,
            MissionId::ScheduledService => return Err("M03 was not supported by version 3"),
            MissionId::NoticeToVacate => return Err("M04 was not supported by version 3"),
            MissionId::NoForwardingAddress
            | MissionId::PortOfEntry
            | MissionId::DeclaredGoods
            | MissionId::CustodianOfRecord
            | MissionId::PassengerManifest
            | MissionId::CommonCarrier
            | MissionId::RightOfSearch
            | MissionId::TermsOfCooperation => return Err("M05 was not supported by version 3"),
        };
        if self.version != 3 || self.rules.revision != 2 {
            return Err("unsupported legacy campaign run");
        }
        document.migrate_historical_rockets()?;
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
        let mut document = RunDocument {
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
            m08_outcome: None,
            m09_outcome: None,
            m10_transit: None,
            m11_outcome: None,
            m12_outcome: None,
        };
        document.migrate_historical_rockets()?;
        document.validate(m01_hash)?;
        Ok(document)
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct RunDocumentV12 {
    pub version: u32,
    pub id: Uuid,
    pub starting_continues: u8,
    pub remaining_continues: u8,
    pub level_start_continues: u8,
    pub body: Option<BodyKind>,
    pub rules: CampaignRules,
    pub content_sha256: [u8; 32],
    #[serde(deserialize_with = "deserialize_pre_repeater_step")]
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
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub m09_outcome: Option<M09Outcome>,
}

impl RunDocumentV12 {
    pub fn upgrade(self, hashes: store::ContentHashes) -> Result<RunDocument, &'static str> {
        if self.version != 12 || self.rules.revision != PRE_ASSESSOR_RULES_REVISION {
            return Err("unsupported historical campaign rules");
        }
        let mut document = RunDocument {
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
            m05_outcome: self.m05_outcome,
            m06_outcome: self.m06_outcome,
            m08_outcome: self.m08_outcome,
            m09_outcome: self.m09_outcome,
            m10_transit: None,
            m11_outcome: None,
            m12_outcome: None,
        };
        document.migrate_historical_rockets()?;
        document.validate(
            *hashes[..9]
                .get(store::stage_index(document.stage_mission()))
                .ok_or("mission was not supported by this historical version")?,
        )?;
        Ok(document)
    }
}

#[cfg(test)]
mod remote_boundary_tests {
    use super::*;

    #[test]
    fn remote_historical_equipment_requires_absence_before_assigning_zero() {
        let equipment = serde_json::json!({
            "selected":"tack", "weapons":["fists","tack"],
            "ammo":[{"pool":"bullets","rounds":50},{"pool":"shells","rounds":12},{"pool":"cells","rounds":10}],
            "grenades":3,"proximity_mines":2,"personal_claims":["real_stock"]
        });
        let old = serde_json::from_value::<PreRemoteEquipment>(equipment.clone()).unwrap();
        let mut saved = SavedEquipment::from(old);
        assert_eq!(
            (saved.grenades, saved.proximity_mines, saved.remote_mines),
            (3, 2, 0)
        );
        assert_eq!(saved.selected, WeaponType::Tack);
        assert!(saved
            .ammo
            .iter()
            .all(|count| count.pool != AmmoPool::Rockets));
        saved.ammo.push(AmmoCount {
            pool: AmmoPool::Rockets,
            rounds: 0,
        });
        saved.validate().unwrap();
        for bad in [
            serde_json::json!(0),
            serde_json::json!(6),
            serde_json::Value::Null,
        ] {
            let mut forged = equipment.clone();
            forged["remote_mines"] = bad;
            assert!(serde_json::from_value::<PreRemoteEquipment>(forged).is_err());
        }
        let mut missing = equipment;
        missing.as_object_mut().unwrap().remove("proximity_mines");
        assert!(serde_json::from_value::<PreRemoteEquipment>(missing).is_err());
    }
}
