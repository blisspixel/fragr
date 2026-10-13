//! Exact pre-foundry document. Future optional fields cannot appear in it.
use super::*;

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct RunDocumentBeforeFoundry {
    version: u32,
    id: Uuid,
    starting_continues: u8,
    remaining_continues: u8,
    level_start_continues: u8,
    body: Option<BodyKind>,
    rules: CampaignRules,
    content_sha256: [u8; 32],
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
    #[serde(default, deserialize_with = "m12_outcome::present")]
    m12_outcome: Option<M12Outcome>,
}

impl RunDocumentBeforeFoundry {
    pub(super) fn upgrade(self) -> Result<RunDocument, &'static str> {
        if !matches!(self.version, 15 | 16) || self.rules.revision != CAMPAIGN_RULES_REVISION {
            return Err("unsupported historical campaign rules");
        }
        let mut document = RunDocument {
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
            m06_outcome: self.m06_outcome,
            m08_outcome: self.m08_outcome,
            m09_outcome: self.m09_outcome,
            m10_transit: self.m10_transit,
            m11_outcome: self.m11_outcome,
            m12_outcome: self.m12_outcome,
            m13_outcome: None,
        };
        if document.stage_mission() == MissionId::WeightOfPermission {
            return Err("M13 was not supported before version 17");
        }
        if self.version == 15 {
            document.migrate_historical_rockets()?;
        }
        Ok(document)
    }
}
