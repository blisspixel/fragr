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
    pub level_start_continues: u8,
}

impl CampaignRunState {
    pub fn validate_attempt(&self, attempt: u32) -> Result<(), &'static str> {
        if self.id.is_nil()
            || self.level_start_continues > CAMPAIGN_CONTINUES
            || self.continues > self.level_start_continues
            || attempt != u32::from(self.level_start_continues - self.continues) + 1
            || (self.status == CampaignRunStatus::Continue && self.continues == 0)
            || (self.status == CampaignRunStatus::Failed && self.continues != 0)
        {
            return Err("invalid campaign run identity or allowance");
        }
        Ok(())
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct MissionContinue {
    pub id: MissionId,
    pub run_id: Uuid,
    pub attempt: u32,
}

/// Revision changes whenever campaign difficulty semantics change. Revision 2
/// removed magazines and reloading: guards no longer pause to reload and a
/// scatter blast is seven pellets. Revision 3 adds Notary photograph timing;
/// earlier enemy timings remain unchanged.
pub const CAMPAIGN_RULES_REVISION: u32 = 3;

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
    PersonsUnknown,
    ScheduledService,
    NoticeToVacate,
    NoForwardingAddress,
    PortOfEntry,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(rename_all = "snake_case")]
pub enum MissionPhase {
    #[default]
    Briefing,
    FindTransfer,
    ReachLift,
    InProgress,
    Departed,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum InteractionKind {
    TransferRecord,
    LiftDeparture,
    ObjectiveUse,
    ClinicShutter,
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

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "snake_case", deny_unknown_fields)]
pub enum MissionObjectiveAction {
    Arrival {
        region: Region3,
        feet: [f32; 3],
    },
    Use {
        target: UseTarget,
    },
    Shoot {
        solid: usize,
        approach: [f32; 3],
        aim: [f32; 3],
    },
}

pub const M03_MAST_MAX_HP: i32 = 40;
pub const M03_MAX_CARS: usize = 4;

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct M03MastGeometry {
    pub solid: usize,
    pub approach: [f32; 3],
    pub aim: [f32; 3],
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct M03CarGeometry {
    pub id: String,
    pub release: Region3,
    pub held: [[f32; 3]; 2],
    pub safe: [[f32; 3]; 2],
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct M03MapGeometry {
    pub mast_shutdown: bool,
    pub mast: M03MastGeometry,
    pub departure: UseTarget,
    pub boarding: Region3,
    pub cars: Vec<M03CarGeometry>,
    pub companion_start: [f32; 3],
}

fn mission_identifier(id: &str) -> bool {
    !id.is_empty()
        && id.len() <= 64
        && id
            .bytes()
            .all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == b'_')
}

impl M03MapGeometry {
    pub fn validate(
        &self,
        half: f32,
        solids: &[Solid],
        presentation: Option<&MapPresentation>,
    ) -> Result<(), &'static str> {
        let presentation = presentation.ok_or("M03 requires presentation")?;
        let pod = solids
            .get(self.mast.solid)
            .ok_or("M03 mast solid is missing")?;
        let valid_point = |point: [f32; 3]| {
            point.iter().all(|v| v.is_finite())
                && point[0].abs() <= half
                && point[2].abs() <= half
                && (0.0..=crate::movement::MAX_HALF_EXTENT * 2.0).contains(&point[1])
        };
        if !valid_point(self.mast.approach)
            || !valid_point(self.mast.aim)
            || !valid_point(self.companion_start)
            || !self.boarding.valid(half)
            || !self.boarding.contains(self.departure.approach)
            || !valid_point(self.departure.approach)
            || self.cars.is_empty()
            || self.cars.len() > M03_MAX_CARS
        {
            return Err("invalid M03 geometry");
        }
        if !self.mast_shutdown
            && !(self.mast.aim[0] >= pod.min_x
                && self.mast.aim[0] <= pod.max_x
                && self.mast.aim[1] >= pod.bottom
                && self.mast.aim[1] <= pod.top
                && self.mast.aim[2] >= pod.min_z
                && self.mast.aim[2] <= pod.max_z)
        {
            return Err("M03 mast aim misses registered pod");
        }
        if presentation
            .decorations
            .get(self.departure.decoration)
            .is_none_or(|panel| {
                !matches!(
                    panel.kind,
                    MapDecorationKind::LiftControl | MapDecorationKind::M03BoardTrain
                )
            })
            || self.departure.point(presentation, solids).is_none()
        {
            return Err("invalid M03 departure control");
        }
        let mut ids = std::collections::HashSet::new();
        for car in &self.cars {
            if !mission_identifier(&car.id)
                || !ids.insert(&car.id)
                || !car.release.valid(half)
                || car
                    .held
                    .iter()
                    .chain(&car.safe)
                    .any(|point| !valid_point(*point))
                || car
                    .held
                    .iter()
                    .zip(car.safe)
                    .any(|(held, safe)| (held[1] - safe[1]).abs() > 0.01)
            {
                return Err("invalid M03 car geometry");
            }
        }
        Ok(())
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct M03CarState {
    pub id: String,
    pub released: bool,
    pub captives: [[f32; 3]; 2],
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct M03ObjectiveState {
    pub mast_hp: i32,
    pub mast_secured: bool,
    pub train_secured: bool,
    pub cars: Vec<M03CarState>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub current: Option<MissionObjective>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct MissionObjective {
    pub id: String,
    pub action: MissionObjectiveAction,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct M02ObjectiveState {
    pub completed: Vec<String>,
    pub total: u8,
    pub gate_mask: u8,
    /// Authoritative ward encounter is complete; correction has stopped.
    pub ward_secured: bool,
    /// Optional side ward guards are defeated; captives may free themselves.
    pub side_ward_secured: bool,
    /// Present on maps that author the optional side-ward encounter.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub evacuation: Option<M02EvacuationState>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub current: Option<MissionObjective>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum M02EvacuationPhase {
    Held,
    Freeing,
    Ready,
    Moving,
    Waiting,
    Evacuated,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct M02EvacuationState {
    pub phase: M02EvacuationPhase,
    /// Grounded world feet, in the same coordinate frame as authored map feet.
    pub captives: [[f32; 3]; 2],
    pub evacuated: bool,
}

impl M02EvacuationState {
    pub const HELD_FEET: [[f32; 3]; 2] = [[22.6, 0.0, 9.0], [24.5, 0.0, 9.0]];
    pub const WAIT_FEET: [[f32; 3]; 2] = [[-5.2, 0.0, 11.0], [-3.5, 0.0, 11.0]];

    pub fn held() -> Self {
        Self {
            phase: M02EvacuationPhase::Held,
            captives: Self::HELD_FEET,
            evacuated: false,
        }
    }

    fn valid(&self, side_ward_secured: bool, briefing: bool) -> bool {
        const DOCK_SAFE_MIN: [f32; 3] = [-2.5, 0.0, 19.0];
        const DOCK_SAFE_MAX: [f32; 3] = [4.0, 1.0, 23.0];
        self.evacuated == (self.phase == M02EvacuationPhase::Evacuated)
            && (side_ward_secured || self.phase == M02EvacuationPhase::Held)
            && (!briefing || self.phase == M02EvacuationPhase::Held)
            && (self.phase != M02EvacuationPhase::Held
                || self
                    .captives
                    .iter()
                    .zip(Self::HELD_FEET)
                    .all(|(feet, held)| (0..3).all(|axis| (feet[axis] - held[axis]).abs() <= 0.01)))
            && (self.phase != M02EvacuationPhase::Waiting
                || self
                    .captives
                    .iter()
                    .zip(Self::WAIT_FEET)
                    .all(|(feet, wait)| (0..3).all(|axis| (feet[axis] - wait[axis]).abs() <= 0.25)))
            && self.captives.iter().all(|feet| {
                feet.iter()
                    .all(|v| v.is_finite() && v.abs() <= crate::movement::MAX_HALF_EXTENT)
                    && (self.phase != M02EvacuationPhase::Evacuated
                        || (0..3).all(|axis| {
                            feet[axis] >= DOCK_SAFE_MIN[axis] && feet[axis] <= DOCK_SAFE_MAX[axis]
                        }))
            })
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
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
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub m02: Option<M02ObjectiveState>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub m03: Option<M03ObjectiveState>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub m04: Option<super::M04ObjectiveState>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub m05: Option<super::M05ObjectiveState>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub m06: Option<super::M06ObjectiveState>,
}

impl MissionState {
    pub fn validate(&self, tick: u64) -> Result<(), &'static str> {
        if self.id != MissionId::PortOfEntry && self.m06.is_some() {
            return Err("M06 facts require M06 mission");
        }
        if self.id != MissionId::NoForwardingAddress && self.m05.is_some() {
            return Err("M05 facts require M05 mission");
        }
        if self.id != MissionId::NoticeToVacate && self.m04.is_some() {
            return Err("M04 facts require M04 mission");
        }
        match self.id {
            MissionId::RecallNotice => {
                if self.m02.is_some()
                    || self.m03.is_some()
                    || self.phase == MissionPhase::InProgress
                {
                    return Err("M01 cannot carry M02 objective state");
                }
            }
            MissionId::PersonsUnknown => {
                if self.m03.is_some() {
                    return Err("M02 cannot carry M03 state");
                }
                self.validate_m02()?;
            }
            MissionId::ScheduledService => self.validate_m03()?,
            MissionId::NoticeToVacate => self.validate_m04()?,
            MissionId::NoForwardingAddress => self.validate_m05(tick)?,
            MissionId::PortOfEntry => self.validate_m06()?,
        }
        if let Some(run) = self.run {
            run.validate_attempt(self.attempt)?;
            if self.party.len() > 1
                || (run.status == CampaignRunStatus::Complete)
                    != (self.phase == MissionPhase::Departed)
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
                MissionPhase::InProgress => {
                    (self.id == MissionId::PortOfEntry
                        && prompt.kind == InteractionKind::ObjectiveUse
                        && self.m06.as_ref().is_some_and(|f| f.completed.len() == 6)
                        && !self.party.is_empty()
                        && self.party.iter().all(|p| p.alive && p.ready && p.aboard))
                        || (self.id == MissionId::NoForwardingAddress
                            && prompt.kind == InteractionKind::ObjectiveUse
                            && self
                                .m05
                                .as_ref()
                                .is_some_and(|f| f.completed.len() == 6 && f.freight_open)
                            && !self.party.is_empty()
                            && self.party.iter().all(|p| p.alive && p.ready && p.aboard))
                        || (self.id == MissionId::NoticeToVacate
                            && self.m04.as_ref().is_some_and(|m04| {
                                (prompt.kind == InteractionKind::ClinicShutter
                                    && m04.clinic_secured
                                    && !m04.clinic_open)
                                    || (prompt.kind == InteractionKind::ObjectiveUse
                                        && m04.completed.len() == 6
                                        && !self.party.is_empty()
                                        && self
                                            .party
                                            .iter()
                                            .all(|p| p.alive && p.ready && p.aboard))
                            }))
                        || (self.id == MissionId::ScheduledService
                            && prompt.kind == InteractionKind::ObjectiveUse
                            && self
                                .m03
                                .as_ref()
                                .is_some_and(|m03| m03.mast_hp == 0 && m03.train_secured)
                            && !self.party.is_empty()
                            && self.party.iter().all(|p| p.alive && p.ready && p.aboard))
                        || (prompt.kind == InteractionKind::ObjectiveUse
                            && self.id == MissionId::PersonsUnknown
                            && self
                                .m02
                                .as_ref()
                                .and_then(|m02| m02.current.as_ref())
                                .is_some_and(|current| {
                                    matches!(current.action, MissionObjectiveAction::Use { .. })
                                        && (current.id != "companion_released"
                                            || self
                                                .m02
                                                .as_ref()
                                                .is_some_and(|m02| m02.ward_secured))
                                }))
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

    fn validate_m03(&self) -> Result<(), &'static str> {
        let state = self.m03.as_ref().ok_or("M03 state is missing")?;
        if self.m02.is_some()
            || !matches!(
                self.phase,
                MissionPhase::Briefing | MissionPhase::InProgress | MissionPhase::Departed
            )
            || !(0..=M03_MAST_MAX_HP).contains(&state.mast_hp)
            || (state.mast_hp < M03_MAST_MAX_HP && !state.mast_secured)
            || state.cars.is_empty()
            || state.cars.len() > M03_MAX_CARS
            || (self.phase == MissionPhase::Briefing
                && (state.mast_hp != M03_MAST_MAX_HP
                    || state.mast_secured
                    || state.train_secured
                    || state.cars.iter().any(|car| car.released)))
            || (self.phase == MissionPhase::Departed
                && (state.mast_hp != 0 || !state.train_secured))
        {
            return Err("invalid M03 progression");
        }
        let mut ids = std::collections::HashSet::new();
        for car in &state.cars {
            if !mission_identifier(&car.id)
                || !ids.insert(&car.id)
                || car.captives.iter().any(|point| point[1] < 0.0)
                || car.captives.iter().flatten().any(|value| {
                    !value.is_finite() || value.abs() > crate::movement::MAX_HALF_EXTENT * 2.0
                })
            {
                return Err("invalid M03 car state");
            }
        }
        if let Some(current) = &state.current {
            match &current.action {
                MissionObjectiveAction::Shoot {
                    solid,
                    approach,
                    aim,
                } if *solid < crate::movement::MAX_SOLIDS
                    && approach.iter().chain(aim).all(|value| {
                        value.is_finite() && value.abs() <= crate::movement::MAX_HALF_EXTENT * 2.0
                    })
                    && approach[1] >= 0.0
                    && aim[1] >= 0.0 => {}
                MissionObjectiveAction::Use { target }
                    if target.decoration < super::MAX_MAP_DECORATIONS
                        && target.approach.iter().all(|value| value.is_finite()) => {}
                _ => return Err("invalid M03 objective target"),
            }
        }
        match (&state.current, self.phase, state.mast_hp) {
            (None, MissionPhase::Departed, 0) => {}
            (Some(current), _, hp)
                if hp > 0
                    && current.id == "mast_disabled"
                    && matches!(current.action, MissionObjectiveAction::Shoot { .. }) => {}
            (Some(current), _, 0)
                if current.id == "party_departed"
                    && matches!(current.action, MissionObjectiveAction::Use { .. }) => {}
            _ => return Err("invalid M03 current objective"),
        }
        Ok(())
    }

    fn validate_m02(&self) -> Result<(), &'static str> {
        let m02 = self.m02.as_ref().ok_or("M02 objective state is missing")?;
        if !matches!(
            self.phase,
            MissionPhase::Briefing | MissionPhase::InProgress | MissionPhase::Departed
        ) || !(1..=8).contains(&m02.total)
            || m02.completed.len() > usize::from(m02.total)
            || m02.gate_mask > 7
            || (self.phase == MissionPhase::Departed)
                != (m02.completed.len() == usize::from(m02.total))
            || m02.current.is_some() != (m02.completed.len() < usize::from(m02.total))
            || (self.phase == MissionPhase::Briefing
                && (!m02.completed.is_empty()
                    || m02.gate_mask != 0
                    || m02.ward_secured
                    || m02.side_ward_secured))
            || (m02.completed.iter().any(|id| id == "companion_released") && !m02.ward_secured)
            || (m02.side_ward_secured && !m02.ward_secured)
            || (m02.side_ward_secured && m02.evacuation.is_none())
            || m02.evacuation.as_ref().is_some_and(|evacuation| {
                !evacuation.valid(m02.side_ward_secured, self.phase == MissionPhase::Briefing)
            })
        {
            return Err("invalid M02 objective progress");
        }
        let valid_id = |id: &str| {
            !id.is_empty()
                && id.len() <= 64
                && id
                    .bytes()
                    .all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == b'_')
        };
        let mut seen = std::collections::HashSet::new();
        if m02
            .completed
            .iter()
            .any(|id| !valid_id(id) || !seen.insert(id))
        {
            return Err("invalid M02 completed objective ids");
        }
        if let Some(current) = &m02.current {
            if !valid_id(&current.id) || !seen.insert(&current.id) {
                return Err("invalid M02 current objective id");
            }
            match &current.action {
                MissionObjectiveAction::Arrival { region, feet } => {
                    if !region.valid(crate::movement::MAX_HALF_EXTENT)
                        || !region.contains(*feet)
                        || feet.iter().any(|v| !v.is_finite())
                    {
                        return Err("invalid M02 arrival objective");
                    }
                }
                MissionObjectiveAction::Use { target } => {
                    if target.decoration >= super::MAX_MAP_DECORATIONS
                        || target.approach.iter().any(|v| !v.is_finite())
                    {
                        return Err("invalid M02 use objective");
                    }
                }
                MissionObjectiveAction::Shoot { .. } => {
                    return Err("M02 cannot contain a shoot objective")
                }
            }
        }
        if m02
            .completed
            .iter()
            .filter(|id| id.as_str() == "party_departed")
            .count()
            != usize::from(self.phase == MissionPhase::Departed)
            || m02
                .completed
                .last()
                .is_some_and(|id| id == "party_departed")
                != (self.phase == MissionPhase::Departed)
            || m02.current.as_ref().is_some_and(|current| {
                current.id == "party_departed"
                    && (m02.completed.len() + 1 != usize::from(m02.total)
                        || !matches!(current.action, MissionObjectiveAction::Arrival { .. }))
            })
        {
            return Err("M02 departure must be the final objective");
        }
        Ok(())
    }
}

#[cfg(test)]
mod m02_wire_tests {
    use super::*;

    fn state() -> MissionState {
        MissionState {
            id: MissionId::PersonsUnknown,
            run: None,
            rules: CampaignRules::default(),
            attempt: 1,
            phase: MissionPhase::InProgress,
            changed_at: 2,
            party: vec![MissionMember {
                id: Uuid::from_u128(1),
                name: "Walker".into(),
                ready: true,
                alive: true,
                aboard: false,
            }],
            prompts: vec![],
            m03: None,
            m04: None,
            m05: None,
            m06: None,
            m02: Some(M02ObjectiveState {
                completed: vec!["ward_reached".into()],
                total: 3,
                gate_mask: 0,
                ward_secured: true,
                side_ward_secured: false,
                evacuation: Some(M02EvacuationState::held()),
                current: Some(MissionObjective {
                    id: "companion_released".into(),
                    action: MissionObjectiveAction::Use {
                        target: UseTarget {
                            decoration: 0,
                            approach: [0.0, 0.0, 0.0],
                        },
                    },
                }),
            }),
        }
    }

    #[test]
    fn m02_state_roundtrips_and_rejects_wrong_phase_and_departure_order() {
        let valid = state();
        valid.validate(2).unwrap();
        let json = serde_json::to_string(&valid).unwrap();
        let decoded: MissionState = serde_json::from_str(&json).unwrap();
        decoded.validate(2).unwrap();
        let mut missing_fact: serde_json::Value = serde_json::from_str(&json).unwrap();
        missing_fact["m02"]
            .as_object_mut()
            .unwrap()
            .remove("ward_secured");
        assert!(serde_json::from_value::<MissionState>(missing_fact).is_err());
        let mut wrong_fact: serde_json::Value = serde_json::from_str(&json).unwrap();
        wrong_fact["m02"]["ward_secured"] = serde_json::json!(1);
        assert!(serde_json::from_value::<MissionState>(wrong_fact).is_err());
        let mut missing_side: serde_json::Value = serde_json::from_str(&json).unwrap();
        missing_side["m02"]
            .as_object_mut()
            .unwrap()
            .remove("side_ward_secured");
        assert!(serde_json::from_value::<MissionState>(missing_side).is_err());
        let mut wrong_side: serde_json::Value = serde_json::from_str(&json).unwrap();
        wrong_side["m02"]["side_ward_secured"] = serde_json::json!(1);
        assert!(serde_json::from_value::<MissionState>(wrong_side).is_err());
        let mut missing_evacuation: serde_json::Value = serde_json::from_str(&json).unwrap();
        missing_evacuation["m02"]
            .as_object_mut()
            .unwrap()
            .remove("evacuation");
        let fixture_without_side: MissionState =
            serde_json::from_value(missing_evacuation).unwrap();
        fixture_without_side.validate(2).unwrap();
        let mut missing_after_side_clear = fixture_without_side.clone();
        missing_after_side_clear
            .m02
            .as_mut()
            .unwrap()
            .side_ward_secured = true;
        assert!(missing_after_side_clear.validate(2).is_err());
        let mut extra_captive: serde_json::Value = serde_json::from_str(&json).unwrap();
        extra_captive["m02"]["evacuation"]["captives"] =
            serde_json::json!([[22.6, 0, 9], [24.5, 0, 9], [0, 0, 0]]);
        assert!(serde_json::from_value::<MissionState>(extra_captive).is_err());
        let mut wrong_phase: serde_json::Value = serde_json::from_str(&json).unwrap();
        wrong_phase["m02"]["evacuation"]["phase"] = serde_json::json!("teleported");
        assert!(serde_json::from_value::<MissionState>(wrong_phase).is_err());
        let mut dishonest = valid.clone();
        dishonest
            .m02
            .as_mut()
            .unwrap()
            .evacuation
            .as_mut()
            .unwrap()
            .evacuated = true;
        assert!(dishonest.validate(2).is_err());
        let mut displaced = valid.clone();
        displaced
            .m02
            .as_mut()
            .unwrap()
            .evacuation
            .as_mut()
            .unwrap()
            .captives[0][0] = 1.0;
        assert!(displaced.validate(2).is_err());
        let mut false_wait = valid.clone();
        let evacuation = false_wait
            .m02
            .as_mut()
            .unwrap()
            .evacuation
            .as_mut()
            .unwrap();
        evacuation.phase = M02EvacuationPhase::Waiting;
        assert!(false_wait.validate(2).is_err());
        let mut premature_side = valid.clone();
        premature_side.m02.as_mut().unwrap().side_ward_secured = true;
        premature_side.m02.as_mut().unwrap().ward_secured = false;
        assert!(premature_side.validate(2).is_err());
        let mut invalid = valid.clone();
        invalid.phase = MissionPhase::FindTransfer;
        assert!(invalid.validate(2).is_err());
        invalid = valid.clone();
        invalid.m02.as_mut().unwrap().current.as_mut().unwrap().id = "party_departed".into();
        assert!(invalid.validate(2).is_err());
        invalid = valid.clone();
        invalid.m02.as_mut().unwrap().completed[0] = "party_departed".into();
        assert!(invalid.validate(2).is_err());
        invalid = valid.clone();
        invalid.prompts.push(InteractionPrompt {
            player_id: invalid.party[0].id,
            kind: InteractionKind::ObjectiveUse,
        });
        invalid.validate(2).unwrap();
        invalid
            .m02
            .as_mut()
            .unwrap()
            .current
            .as_mut()
            .unwrap()
            .action = MissionObjectiveAction::Arrival {
            region: Region3 {
                min: [0.0, 0.0, 0.0],
                max: [1.0, 1.0, 1.0],
            },
            feet: [0.5, 0.0, 0.5],
        };
        assert!(invalid.validate(2).is_err());
    }

    #[test]
    fn m01_state_omits_optional_m02_field() {
        let mut m01 = state();
        m01.id = MissionId::RecallNotice;
        m01.phase = MissionPhase::FindTransfer;
        m01.m02 = None;
        m01.validate(2).unwrap();
        assert!(!serde_json::to_string(&m01).unwrap().contains("m02"));
    }

    #[test]
    fn ward_victory_is_required_for_release_progress_and_prompt() {
        let mut before = state();
        before.m02.as_mut().unwrap().ward_secured = false;
        before.validate(2).unwrap();
        before.prompts.push(InteractionPrompt {
            player_id: before.party[0].id,
            kind: InteractionKind::ObjectiveUse,
        });
        assert!(before.validate(2).is_err());
        before.prompts.clear();
        let m02 = before.m02.as_mut().unwrap();
        m02.completed.push("companion_released".into());
        m02.current.as_mut().unwrap().id = "party_departed".into();
        m02.current.as_mut().unwrap().action = MissionObjectiveAction::Arrival {
            region: Region3 {
                min: [0.0, 0.0, 0.0],
                max: [1.0, 1.0, 1.0],
            },
            feet: [0.5, 0.0, 0.5],
        };
        assert!(before.validate(2).is_err());
        before.m02.as_mut().unwrap().ward_secured = true;
        before.validate(2).unwrap();
    }
}
