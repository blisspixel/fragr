//! Freedom of Movement: ordered ceremonial avenue objectives and resolved challenge receipts.
use super::{
    CampaignDifficulty, MapPresentation, MissionObjective, MissionObjectiveAction, MissionPhase,
    Region3, UseTarget,
};
use crate::movement::Solid;
use serde::{Deserialize, Serialize};

pub const M16_OBJECTIVE_IDS: [&str; 6] = [
    "ride_started",
    "barricade_broken",
    "green_wave_triggered",
    "bus_freed",
    "forecourt_secured",
    "doors_reached",
];

#[derive(Debug, Clone, PartialEq, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct M16Motorcycle {
    pub feet: [f32; 3],
    pub yaw: f32,
}

#[derive(Debug, Clone, PartialEq, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct M16MapGeometry {
    pub objectives: Vec<MissionObjective>,
    pub departure: UseTarget,
    pub boarding: Region3,
    pub bus_release: UseTarget,
    pub motorcycle: M16Motorcycle,
    pub checkpoint_lifted: bool,
    pub doors_open: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, Deserialize, Serialize, Default)]
#[serde(deny_unknown_fields)]
pub struct M16ChallengeState {
    pub ride_started: bool,
    pub green_wave_triggered: bool,
    pub bus_freed: bool,
}

impl M16ChallengeState {
    pub fn validate(&self) -> Result<(), &'static str> {
        if self.green_wave_triggered && !self.ride_started {
            return Err("M16 green wave trigger precedes ride start");
        }
        Ok(())
    }

    pub fn brief_completed(&self, difficulty: CampaignDifficulty) -> bool {
        self.ride_started
            && (difficulty == CampaignDifficulty::Assisted
                || self.green_wave_triggered
                    && (difficulty != CampaignDifficulty::Severe || self.bus_freed))
    }
}

#[derive(Debug, Clone, PartialEq, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct M16ObjectiveState {
    pub completed: Vec<String>,
    #[serde(
        default,
        deserialize_with = "super::m11::present",
        skip_serializing_if = "Option::is_none"
    )]
    pub current: Option<MissionObjective>,
    pub challenges: M16ChallengeState,
    pub checkpoint_lifted: bool,
    pub doors_open: bool,
    pub bus_freed: bool,
    pub forecourt_secured: bool,
}

fn point(p: [f32; 3], half: f32) -> bool {
    p.iter().all(|v| v.is_finite())
        && p[0].abs() <= half
        && p[2].abs() <= half
        && (0.0..=512.0).contains(&p[1])
}

impl M16MapGeometry {
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
        let p = presentation.ok_or("M16 requires panel presentation")?;
        if self.objectives.len() != M16_OBJECTIVE_IDS.len() {
            return Err("M16 requires six ordered objectives");
        }
        for (i, obj) in self.objectives.iter().enumerate() {
            if obj.id != M16_OBJECTIVE_IDS[i] {
                return Err("unexpected M16 objective order");
            }
            match &obj.action {
                MissionObjectiveAction::Arrival { region, feet } => {
                    if !region.valid(half_extent)
                        || !point(*feet, half_extent)
                        || !region.contains(*feet)
                    {
                        return Err("invalid M16 objective arrival region or feet");
                    }
                }
                MissionObjectiveAction::Use { target } => {
                    if !point(target.approach, half_extent)
                        || target.decoration >= super::MAX_MAP_DECORATIONS
                        || target.point(p, solids).is_none()
                    {
                        return Err("M16 objective decoration misses solid or invalid approach");
                    }
                }
                _ => return Err("unexpected M16 objective action"),
            }
        }
        if !self.boarding.valid(half_extent) {
            return Err("invalid M16 boarding region");
        }
        if !point(self.departure.approach, half_extent) || self.departure.point(p, solids).is_none()
        {
            return Err("M16 departure decoration misses solid");
        }
        if !point(self.bus_release.approach, half_extent)
            || self.bus_release.point(p, solids).is_none()
        {
            return Err("M16 bus release decoration misses solid");
        }
        if !point(self.motorcycle.feet, half_extent) {
            return Err("invalid M16 motorcycle placement");
        }
        Ok(())
    }
}

impl M16ObjectiveState {
    pub fn validate(&self, phase: MissionPhase, tick: u64) -> Result<(), &'static str> {
        self.challenges.validate()?;
        let n = super::mission::validate_ordered_progress(
            &self.completed,
            self.current.as_ref(),
            &M16_OBJECTIVE_IDS,
            &[3],
            phase,
            tick,
        )?;
        if self.bus_freed != self.challenges.bus_freed
            || (n >= 1) != self.challenges.ride_started
            || (n >= 3) != self.checkpoint_lifted
            || self.checkpoint_lifted != self.challenges.green_wave_triggered
            || (n >= 5) != self.forecourt_secured
            || (n >= 6) != self.doors_open
        {
            return Err("M16 facts disagree with ordered progress");
        }
        if phase == MissionPhase::Briefing
            && (!self.completed.is_empty()
                || self.checkpoint_lifted
                || self.doors_open
                || self.bus_freed
                || self.forecourt_secured)
        {
            return Err("briefing M16 cannot carry progress");
        }
        if phase == MissionPhase::Departed {
            if !self.doors_open || !self.forecourt_secured {
                return Err("departed M16 must have forecourt secured and doors open");
            }
            if tick == 0 {
                return Err("departed M16 requires non-zero tick");
            }
        }
        Ok(())
    }
}
