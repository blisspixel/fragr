//! Peace Without Interruption: ordered Forever Office objectives and resolved challenge receipts.
use super::{
    CampaignDifficulty, MapPresentation, MissionObjective, MissionObjectiveAction, MissionPhase,
    Region3, UseTarget,
};
use crate::movement::Solid;
use serde::{Deserialize, Serialize};

pub const M17_OBJECTIVE_IDS: [&str; 6] = [
    "approach_breached",
    "hall_secured",
    "kessel_secured",
    "core_unsealed",
    "core_defeated",
    "voss_captured",
];

#[derive(Debug, Clone, PartialEq, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct M17MapGeometry {
    pub objectives: Vec<MissionObjective>,
    pub departure: UseTarget,
    pub boarding: Region3,
    pub kessel_desk: UseTarget,
    pub core_override: UseTarget,
    pub voss_rostrum: UseTarget,
    pub core_unsealed: bool,
    pub voss_captured: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, Deserialize, Serialize, Default)]
#[serde(deny_unknown_fields)]
pub struct M17ChallengeState {
    pub approach_breached: bool,
    pub kessel_secured: bool,
    pub core_defeated: bool,
    pub voss_captured: bool,
}

impl M17ChallengeState {
    pub fn validate(&self) -> Result<(), &'static str> {
        if self.core_defeated && !self.approach_breached {
            return Err("M17 core defeat precedes approach breach");
        }
        if self.voss_captured && !self.core_defeated {
            return Err("M17 Voss capture precedes core defeat");
        }
        Ok(())
    }

    pub fn brief_completed(&self, difficulty: CampaignDifficulty) -> bool {
        self.approach_breached
            && (difficulty == CampaignDifficulty::Assisted
                || self.core_defeated
                    && (difficulty != CampaignDifficulty::Severe || self.kessel_secured))
    }
}

#[derive(Debug, Clone, PartialEq, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct M17ObjectiveState {
    pub completed: Vec<String>,
    #[serde(
        default,
        deserialize_with = "super::m11::present",
        skip_serializing_if = "Option::is_none"
    )]
    pub current: Option<MissionObjective>,
    pub challenges: M17ChallengeState,
    pub core_unsealed: bool,
    pub voss_captured: bool,
    pub kessel_secured: bool,
    pub brief_completed: bool,
}

fn point(p: [f32; 3], half: f32) -> bool {
    p.iter().all(|v| v.is_finite())
        && p[0].abs() <= half
        && p[2].abs() <= half
        && (0.0..=512.0).contains(&p[1])
}

impl M17MapGeometry {
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
        half_extent: f32,
        solids: &[Solid],
        presentation: Option<&MapPresentation>,
    ) -> Result<(), &'static str> {
        let p = presentation.ok_or("M17 requires panel presentation")?;
        if self.objectives.len() != M17_OBJECTIVE_IDS.len() {
            return Err("M17 requires six ordered objectives");
        }
        for (i, obj) in self.objectives.iter().enumerate() {
            if obj.id != M17_OBJECTIVE_IDS[i] {
                return Err("unexpected M17 objective order");
            }
            match &obj.action {
                MissionObjectiveAction::Arrival { region, feet } => {
                    if !region.valid(half_extent)
                        || !point(*feet, half_extent)
                        || !region.contains(*feet)
                    {
                        return Err("invalid M17 objective arrival region or feet");
                    }
                }
                MissionObjectiveAction::Use { target } => {
                    if !point(target.approach, half_extent)
                        || target.decoration >= super::MAX_MAP_DECORATIONS
                        || target.point(p, solids).is_none()
                    {
                        return Err("M17 objective decoration misses solid or invalid approach");
                    }
                }
                _ => return Err("unexpected M17 objective action"),
            }
        }
        if !self.boarding.valid(half_extent) {
            return Err("invalid M17 boarding region");
        }
        if !point(self.departure.approach, half_extent) || self.departure.point(p, solids).is_none()
        {
            return Err("M17 departure decoration misses solid");
        }
        if !point(self.kessel_desk.approach, half_extent)
            || self.kessel_desk.point(p, solids).is_none()
        {
            return Err("M17 kessel desk decoration misses solid");
        }
        if !point(self.core_override.approach, half_extent)
            || self.core_override.point(p, solids).is_none()
        {
            return Err("M17 core override decoration misses solid");
        }
        if !point(self.voss_rostrum.approach, half_extent)
            || self.voss_rostrum.point(p, solids).is_none()
        {
            return Err("M17 voss rostrum decoration misses solid");
        }
        Ok(())
    }
}

impl M17ObjectiveState {
    pub fn validate(&self, phase: MissionPhase, tick: u64) -> Result<(), &'static str> {
        self.challenges.validate()?;
        let n = super::mission::validate_ordered_progress(
            &self.completed,
            self.current.as_ref(),
            &M17_OBJECTIVE_IDS,
            &[2, 3, 5],
            phase,
            tick,
        )?;
        if self.kessel_secured != self.challenges.kessel_secured
            || self.voss_captured != self.challenges.voss_captured
            || (n >= 1) != self.challenges.approach_breached
            || (n >= 4) != self.core_unsealed
            || (n >= 5) != self.challenges.core_defeated
            || (n >= 6) != self.voss_captured
        {
            return Err("M17 facts disagree with ordered progress");
        }
        if phase == MissionPhase::Briefing
            && (!self.completed.is_empty()
                || self.core_unsealed
                || self.voss_captured
                || self.kessel_secured)
        {
            return Err("briefing M17 cannot carry progress");
        }
        if phase == MissionPhase::Departed {
            if !self.core_unsealed || !self.voss_captured {
                return Err("departed M17 must have core unsealed and voss captured");
            }
            if tick == 0 {
                return Err("departed M17 requires non-zero tick");
            }
        }
        Ok(())
    }
}
