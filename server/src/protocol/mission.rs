//! Mission facts and physical use targets. Text belongs to the presenter.
use super::{MapDecorationKind, MapPresentation};
use crate::movement::Solid;
use serde::{Deserialize, Serialize};
use uuid::Uuid;

pub const MISSION_PARTY_LIMIT: usize = 4;
pub const USE_DISTANCE: f32 = 2.5;
pub const CAMPAIGN_CONTINUES: u8 = 3;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum CampaignRunStatus {
    Playing,
    Continue,
    Failed,
    Complete,
    Abandoned,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct CampaignRunState {
    pub id: Uuid,
    pub status: CampaignRunStatus,
    pub continues: u8,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct MissionContinue {
    pub id: MissionId,
    pub run_id: Uuid,
    pub attempt: u32,
}

/// Revision changes whenever campaign difficulty semantics change.
pub const CAMPAIGN_RULES_REVISION: u32 = 1;

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize, clap::ValueEnum)]
#[serde(rename_all = "snake_case")]
pub enum CampaignDifficulty {
    Assisted,
    #[default]
    Standard,
    Severe,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct CampaignRules {
    pub difficulty: CampaignDifficulty,
    pub revision: u32,
}

impl CampaignRules {
    pub fn new(difficulty: CampaignDifficulty) -> Self {
        Self {
            difficulty,
            revision: CAMPAIGN_RULES_REVISION,
        }
    }
}

impl Default for CampaignRules {
    fn default() -> Self {
        Self::new(CampaignDifficulty::default())
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum MissionId {
    RecallNotice,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(rename_all = "snake_case")]
pub enum MissionPhase {
    #[default]
    Briefing,
    FindTransfer,
    ReachLift,
    Departed,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum InteractionKind {
    TransferRecord,
    LiftDeparture,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Region3 {
    pub min: [f32; 3],
    pub max: [f32; 3],
}

impl Region3 {
    pub fn contains(&self, point: [f32; 3]) -> bool {
        (0..3).all(|axis| point[axis] >= self.min[axis] && point[axis] <= self.max[axis])
    }

    pub fn valid(&self, half_extent: f32) -> bool {
        (0..3).all(|axis| {
            let (min, max) = (self.min[axis], self.max[axis]);
            min.is_finite()
                && max.is_finite()
                && min < max
                && if axis == 1 {
                    min >= 0.0 && max <= crate::movement::MAX_HALF_EXTENT * 2.0
                } else {
                    min >= -half_extent && max <= half_extent
                }
        })
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct UseTarget {
    /// Index in MapPresentation.decorations, so the use point cannot drift from art.
    pub decoration: usize,
    pub approach: [f32; 3],
}

impl UseTarget {
    pub fn point(&self, presentation: &MapPresentation, solids: &[Solid]) -> Option<[f32; 3]> {
        let panel = presentation.decorations.get(self.decoration)?;
        Some(panel.point(solids.get(panel.solid)?))
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct MissionGeometry {
    pub id: MissionId,
    pub record: UseTarget,
    pub departure: UseTarget,
    pub boarding: Region3,
}

impl MissionGeometry {
    pub fn validate(
        &self,
        half_extent: f32,
        solids: &[Solid],
        presentation: Option<&MapPresentation>,
    ) -> Result<(), &'static str> {
        let presentation = presentation.ok_or("mission requires panel presentation")?;
        if !self.boarding.valid(half_extent) || self.record.decoration == self.departure.decoration
        {
            return Err("invalid mission boarding area or duplicate target");
        }
        for (target, kind) in [
            (&self.record, MapDecorationKind::Terminal),
            (&self.departure, MapDecorationKind::LiftControl),
        ] {
            let panel = presentation
                .decorations
                .get(target.decoration)
                .ok_or("mission references an unknown panel")?;
            if panel.kind != kind || target.point(presentation, solids).is_none() {
                return Err("invalid mission panel kind or host");
            }
            if target.approach.iter().any(|v| !v.is_finite())
                || target.approach[0].abs() > half_extent
                || target.approach[2].abs() > half_extent
                || !(0.0..=crate::movement::MAX_HALF_EXTENT * 2.0).contains(&target.approach[1])
            {
                return Err("invalid mission approach");
            }
        }
        if !self.boarding.contains(self.departure.approach) {
            return Err("departure control must be inside the boarding area");
        }
        Ok(())
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct MissionMember {
    pub id: Uuid,
    pub name: String,
    pub ready: bool,
    pub alive: bool,
    pub aboard: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct InteractionPrompt {
    pub player_id: Uuid,
    pub kind: InteractionKind,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct MissionReady {
    pub id: MissionId,
    pub attempt: u32,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct MissionState {
    pub id: MissionId,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub run: Option<CampaignRunState>,
    pub rules: CampaignRules,
    pub attempt: u32,
    pub phase: MissionPhase,
    pub changed_at: u64,
    pub party: Vec<MissionMember>,
    pub prompts: Vec<InteractionPrompt>,
}

impl MissionState {
    pub fn validate(&self, tick: u64) -> Result<(), &'static str> {
        if let Some(run) = self.run {
            if run.id.is_nil()
                || run.continues > CAMPAIGN_CONTINUES
                || self.party.len() > 1
                || self.attempt != u32::from(CAMPAIGN_CONTINUES - run.continues) + 1
                || (run.status == CampaignRunStatus::Complete)
                    != (self.phase == MissionPhase::Departed)
                || (run.status == CampaignRunStatus::Continue && run.continues == 0)
                || (run.status == CampaignRunStatus::Failed && run.continues != 0)
                || (run.status == CampaignRunStatus::Continue
                    && (self.party.len() != 1 || self.party[0].alive))
                || (run.status == CampaignRunStatus::Failed && self.party.iter().any(|p| p.alive))
                || (run.status == CampaignRunStatus::Abandoned && !self.party.is_empty())
                || (run.status != CampaignRunStatus::Playing && !self.prompts.is_empty())
            {
                return Err("invalid campaign run state");
            }
        }
        if self.rules.revision != CAMPAIGN_RULES_REVISION
            || self.attempt == 0
            || self.changed_at > tick
            || self.party.len() > MISSION_PARTY_LIMIT
            || self.prompts.len() > self.party.len()
        {
            return Err("invalid mission revision or party size");
        }
        let mut ids = std::collections::HashSet::new();
        for member in &self.party {
            if !ids.insert(member.id)
                || member.aboard
                    && (!member.alive || !member.ready || self.phase == MissionPhase::Briefing)
                || member.name.is_empty()
                || member.name.chars().count() > 48
                || member.name.chars().any(char::is_control)
            {
                return Err("invalid mission party member");
            }
        }
        ids.clear();
        for prompt in &self.prompts {
            let allowed = match self.phase {
                MissionPhase::FindTransfer => prompt.kind == InteractionKind::TransferRecord,
                MissionPhase::ReachLift => {
                    prompt.kind == InteractionKind::LiftDeparture
                        && self.party.iter().all(|p| p.alive && p.aboard)
                }
                MissionPhase::Briefing | MissionPhase::Departed => false,
            };
            if !allowed
                || !ids.insert(prompt.player_id)
                || !self
                    .party
                    .iter()
                    .any(|p| p.id == prompt.player_id && p.alive && p.ready)
            {
                return Err("invalid mission interaction prompt");
            }
        }
        Ok(())
    }
}
