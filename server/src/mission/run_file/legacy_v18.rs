//! Exact pre-stadium document. Later outcomes cannot be smuggled into history.
use super::*;

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct RunDocumentBeforeStadium {
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
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub m09_outcome: Option<M09Outcome>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub m10_transit: Option<crate::protocol::M10Transit>,
    #[serde(
        default,
        deserialize_with = "m11_outcome::present",
        skip_serializing_if = "Option::is_none"
    )]
    pub m11_outcome: Option<M11Outcome>,
    #[serde(
        default,
        deserialize_with = "m12_outcome::present",
        skip_serializing_if = "Option::is_none"
    )]
    pub m12_outcome: Option<M12Outcome>,
    #[serde(
        default,
        deserialize_with = "m13_outcome::present",
        skip_serializing_if = "Option::is_none"
    )]
    pub m13_outcome: Option<M13Outcome>,
    #[serde(
        default,
        deserialize_with = "m14_outcome::present",
        skip_serializing_if = "Option::is_none"
    )]
    pub m14_outcome: Option<M14Outcome>,
}

impl RunDocumentBeforeStadium {
    pub(super) fn upgrade(self) -> Result<RunDocument, &'static str> {
        if self.version != 18 || self.rules.revision != CAMPAIGN_RULES_REVISION {
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
            m06_outcome: self.m06_outcome,
            m08_outcome: self.m08_outcome,
            m09_outcome: self.m09_outcome,
            m10_transit: self.m10_transit,
            m11_outcome: self.m11_outcome,
            m12_outcome: self.m12_outcome,
            m13_outcome: self.m13_outcome,
            m14_outcome: self.m14_outcome,
            m15_outcome: None,
        };
        if store::stage_index(document.stage_mission()) >= 14 {
            return Err("M15 was not supported before version 19");
        }
        Ok(document)
    }
}
