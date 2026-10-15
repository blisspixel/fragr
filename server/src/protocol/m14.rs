//! Launch Authority: ordered combined-arms objectives and resolved challenge receipts.
use super::{
    CampaignDifficulty, M12AidVehicle, MapPresentation, MissionObjective, MissionObjectiveAction,
    MissionPhase, Region3, UseTarget,
};
use crate::movement::Solid;
use serde::{Deserialize, Serialize};

pub const M14_OBJECTIVE_IDS: [&str; 6] = [
    "arrival",
    "depot_secured",
    "road_secured",
    "approach_secured",
    "walker_disabled",
    "gantry_secured",
];
/// Fallen parts relative to accepted machine feet, min XYZ followed by max XYZ.
pub const M14_FALLEN_PARTS: [[f32; 6]; 5] = [
    [-3.0, 0.0, -2.0, 3.0, 1.6, 2.0],
    [-3.6, 0.0, -2.6, -1.8, 0.55, -1.4],
    [-3.6, 0.0, 1.4, -1.8, 0.55, 2.6],
    [1.8, 0.0, -2.6, 3.6, 0.55, -1.4],
    [1.8, 0.0, 1.4, 3.6, 0.55, 2.6],
];

#[derive(Debug, Clone, PartialEq, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct M14MapGeometry {
    pub objectives: Vec<MissionObjective>,
    pub departure: UseTarget,
    pub boarding: Region3,
    pub jeep: M12AidVehicle,
    pub walker_solids: [usize; 5],
    pub fallen: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct M14ChallengeState {
    pub depot_secured: bool,
    pub walker_disabled: bool,
    pub jeep_preserved: bool,
    pub on_foot: bool,
}
impl Default for M14ChallengeState {
    fn default() -> Self {
        Self {
            depot_secured: false,
            walker_disabled: false,
            jeep_preserved: true,
            on_foot: true,
        }
    }
}
impl M14ChallengeState {
    pub fn validate(&self) -> Result<(), &'static str> {
        if self.walker_disabled && !self.depot_secured {
            return Err("M14 disable precedes depot clearance");
        }
        Ok(())
    }
    pub fn brief_completed(&self, difficulty: CampaignDifficulty) -> bool {
        self.depot_secured
            && (difficulty == CampaignDifficulty::Assisted
                || self.walker_disabled
                    && self.jeep_preserved
                    && (difficulty != CampaignDifficulty::Severe || self.on_foot))
    }
}

#[derive(Debug, Clone, PartialEq, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct M14ObjectiveState {
    pub completed: Vec<String>,
    #[serde(
        default,
        deserialize_with = "super::m11::present",
        skip_serializing_if = "Option::is_none"
    )]
    pub current: Option<MissionObjective>,
    pub challenges: M14ChallengeState,
    pub jeep_id: u32,
    pub support_stage: u8,
    pub first_cycle_complete: bool,
    pub machine_fallen: bool,
}

fn point(p: [f32; 3], half: f32) -> bool {
    p.iter().all(|v| v.is_finite())
        && p[0].abs() <= half
        && p[2].abs() <= half
        && (0.0..=512.0).contains(&p[1])
}
impl M14MapGeometry {
    pub fn departure_objective(&self) -> MissionObjective {
        MissionObjective {
            id: "party_departed".into(),
            action: MissionObjectiveAction::Use {
                target: self.departure.clone(),
            },
        }
    }
    pub fn validate(
        &self,
        half: f32,
        solids: &[Solid],
        presentation: Option<&MapPresentation>,
    ) -> Result<(), &'static str> {
        let presentation = presentation.ok_or("M14 presentation missing")?;
        if !half.is_finite()
            || !(2.0..=crate::movement::MAX_HALF_EXTENT).contains(&half)
            || self.objectives.len() != M14_OBJECTIVE_IDS.len()
            || self
                .objectives
                .iter()
                .zip(M14_OBJECTIVE_IDS)
                .any(|(o, id)| {
                    o.id != id
                        || match &o.action {
                            MissionObjectiveAction::Arrival { region, feet } => {
                                !region.valid(half)
                                    || !point(*feet, half)
                                    || !region.contains(*feet)
                            }
                            _ => true,
                        }
                })
            || !self.boarding.valid(half)
            || !self.boarding.contains(self.departure.approach)
            || !point(self.departure.approach, half)
            || self.departure.point(presentation, solids).is_none()
            || !point(self.jeep.feet, half)
            || !self.jeep.yaw.is_finite()
            || !(0.0..std::f32::consts::TAU).contains(&self.jeep.yaw)
            || self
                .walker_solids
                .iter()
                .enumerate()
                .any(|(i, s)| *s >= solids.len() || self.walker_solids[..i].contains(s))
            || self.fallen
                && self
                    .walker_solids
                    .iter()
                    .any(|i| solids[*i].bottom != 0.0 || solids[*i].top > 2.0)
        {
            return Err("invalid M14 launch geometry");
        }
        if self.fallen {
            let torso = solids[self.walker_solids[0]];
            let origin = [torso.min_x + 3.0, 0.0, torso.min_z + 2.0];
            if self
                .walker_solids
                .iter()
                .zip(M14_FALLEN_PARTS)
                .any(|(index, part)| {
                    let s = solids[*index];
                    let actual = [s.min_x, s.bottom, s.min_z, s.max_x, s.top, s.max_z];
                    actual
                        .iter()
                        .enumerate()
                        .any(|(i, v)| (*v - (part[i] + origin[i % 3])).abs() > 0.0001)
                })
            {
                return Err("M14 fallen parts require one actual translated wreck");
            }
        }
        Ok(())
    }
}
impl M14ObjectiveState {
    pub fn validate(&self, phase: MissionPhase, _tick: u64) -> Result<(), &'static str> {
        self.challenges.validate()?;
        let n = self.completed.len();
        let order = |i| {
            M14_OBJECTIVE_IDS
                .get(i)
                .copied()
                .unwrap_or("party_departed")
        };
        if !matches!(
            phase,
            MissionPhase::Briefing | MissionPhase::InProgress | MissionPhase::Departed
        ) || n > 7
            || self
                .completed
                .iter()
                .enumerate()
                .any(|(i, s)| s != order(i))
            || (phase == MissionPhase::Departed) != (n == 7)
            || self.current.is_some() != (n <= 6)
            || self.jeep_id != 1
            || self.support_stage > 2
            || n < 4
                && (self.first_cycle_complete || self.support_stage > 0 || !self.challenges.on_foot)
            || self.challenges.depot_secured != (n >= 2)
            || self.challenges.walker_disabled && n < 4
            || self.machine_fallen && !self.challenges.walker_disabled
            || n >= 5 && (!self.machine_fallen || self.support_stage != 2)
            || self.support_stage > 0
                && !self.first_cycle_complete
                && !self.challenges.walker_disabled
            || phase == MissionPhase::Briefing
                && (n != 0
                    || self.challenges != M14ChallengeState::default()
                    || self.support_stage != 0
                    || self.first_cycle_complete
                    || self.machine_fallen)
        {
            return Err("invalid M14 ordered progression");
        }
        if let Some(current) = &self.current {
            if current.id != order(n)
                || match &current.action {
                    MissionObjectiveAction::Arrival { region, feet } => {
                        n >= 6
                            || !region.valid(512.0)
                            || !point(*feet, 512.0)
                            || !region.contains(*feet)
                    }
                    MissionObjectiveAction::Use { target } => {
                        n != 6
                            || !point(target.approach, 512.0)
                            || target.decoration >= super::MAX_MAP_DECORATIONS
                    }
                    _ => true,
                }
            {
                return Err("invalid M14 current objective");
            }
        }
        Ok(())
    }
}
