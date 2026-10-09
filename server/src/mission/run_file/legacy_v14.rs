//! Exact pre-Arc document, independent of later current-document additions.
use super::*;

#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct RunDocumentV14 {
    version: u32,
    id: Uuid,
    starting_continues: u8,
    remaining_continues: u8,
    level_start_continues: u8,
    body: Option<BodyKind>,
    rules: CampaignRules,
    content_sha256: [u8; 32],
    #[serde(deserialize_with = "deserialize_pre_arc_step")]
    step: SavedStep,
    #[serde(default)]
    m03_outcome: Option<M03Outcome>,
    #[serde(default)]
    m04_outcome: Option<M04Outcome>,
    #[serde(default)]
    m05_outcome: Option<M05Outcome>,
    #[serde(default)]
    m06_outcome: Option<M06Outcome>,
    #[serde(default)]
    m08_outcome: Option<M08Outcome>,
    #[serde(default)]
    m09_outcome: Option<M09Outcome>,
    #[serde(default)]
    m10_transit: Option<crate::protocol::M10Transit>,
    #[serde(default, deserialize_with = "m11_outcome::present")]
    m11_outcome: Option<M11Outcome>,
}

pub(super) fn pre_arc_step(step: SavedStep) -> Result<SavedStep, &'static str> {
    let equipment = match &step {
        SavedStep::MissionEntry { entry, .. }
        | SavedStep::PendingContinue { entry, .. }
        | SavedStep::Failed { entry, .. }
        | SavedStep::Abandoned { entry, .. } => &entry.equipment,
        SavedStep::AwaitingMission { exit, .. } => &exit.equipment,
    };
    if equipment.selected == WeaponType::Arc || equipment.weapons.contains(&WeaponType::Arc) {
        return Err("historical saves cannot carry Arc");
    }
    Ok(step)
}

fn deserialize_pre_arc_step<'de, D: serde::Deserializer<'de>>(
    decoder: D,
) -> Result<SavedStep, D::Error> {
    pre_arc_step(SavedStep::deserialize(decoder)?).map_err(serde::de::Error::custom)
}

impl RunDocumentV14 {
    pub fn upgrade(self, hashes: store::ContentHashes) -> Result<RunDocument, &'static str> {
        if self.version != 14 || self.rules.revision != PRE_ASSESSOR_RULES_REVISION {
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
            m05_outcome: self.m05_outcome,
            m06_outcome: self.m06_outcome,
            m08_outcome: self.m08_outcome,
            m09_outcome: self.m09_outcome,
            m10_transit: self.m10_transit,
            m11_outcome: self.m11_outcome,
            m12_outcome: None,
        };
        if store::stage_index(document.stage_mission()) >= 11 {
            return Err("mission was not supported by version 14");
        }
        document.validate(
            *hashes
                .get(store::stage_index(document.stage_mission()))
                .ok_or("mission was not supported by version 14")?,
        )?;
        Ok(document)
    }
}
