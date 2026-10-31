//! All Systems Normal: ordered Episode V recovery, rupture, and transit evacuation objectives.
use super::{
    CampaignDifficulty, MapPresentation, MissionObjective, MissionObjectiveAction, MissionPhase,
    Region3, UseTarget,
};
use crate::movement::Solid;
use serde::{Deserialize, Serialize};

/// The turn: ticks from the delivery, when every Union machine stops, until
/// the same bodies move again under Inheritance control. Nothing attacks and
/// nothing absorbed moves while it lasts.
pub const M18_TURN_TICKS: u64 = 60;
/// Ticks into the turn when every stopped machine's head comes round to the
/// same bearing at once and its control passes to the Inheritance.
pub const M18_HEADS_TURN_TICKS: u64 = 10;
/// Ticks into the turn when Latch, who does not turn with them, looks at the
/// party instead.
pub const M18_LATCH_LOOKS_TICKS: u64 = 24;

pub const M18_OBJECTIVE_IDS: [&str; 6] = [
    "aid_checkin",
    "square_defense",
    "collector_breach",
    "service_ascent",
    "overlook_recon",
    "concourse_evac",
];

#[derive(Debug, Clone, PartialEq, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct M18MapGeometry {
    pub objectives: Vec<MissionObjective>,
    pub departure: UseTarget,
    pub boarding: Region3,
    pub depot_station: UseTarget,
    pub overlook_console: UseTarget,
    pub roadblock_active: bool,
    pub concourse_evac_completed: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, Deserialize, Serialize, Default)]
#[serde(deny_unknown_fields)]
pub struct M18ChallengeState {
    pub aid_delivered: bool,
    pub square_defended: bool,
    pub collector_neutralized: bool,
    pub overlook_witnessed: bool,
    pub concourse_secured: bool,
}

impl M18ChallengeState {
    pub fn validate(&self) -> Result<(), &'static str> {
        if self.concourse_secured && !self.square_defended {
            return Err("M18 concourse security precedes square defense");
        }
        if self.overlook_witnessed && !self.square_defended {
            return Err("M18 overlook witness precedes square defense");
        }
        Ok(())
    }

    pub fn brief_completed(&self, difficulty: CampaignDifficulty) -> bool {
        self.square_defended
            && (difficulty == CampaignDifficulty::Assisted
                || self.concourse_secured
                    && (difficulty != CampaignDifficulty::Severe
                        || (self.aid_delivered
                            && self.collector_neutralized
                            && self.overlook_witnessed)))
    }
}

#[derive(Debug, Clone, PartialEq, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct M18ObjectiveState {
    pub completed: Vec<String>,
    #[serde(
        default,
        deserialize_with = "super::m11::present",
        skip_serializing_if = "Option::is_none"
    )]
    pub current: Option<MissionObjective>,
    pub challenges: M18ChallengeState,
    pub roadblock_active: bool,
    pub aid_delivered: bool,
    pub overlook_witnessed: bool,
    pub concourse_secured: bool,
    pub brief_completed: bool,
    /// The tick the delivery was made and the turn began; null before it.
    pub turn_started: Option<u64>,
}

fn point(p: [f32; 3], half: f32) -> bool {
    p.iter().all(|v| v.is_finite())
        && p[0].abs() <= half
        && p[2].abs() <= half
        && (0.0..=512.0).contains(&p[1])
}

impl M18MapGeometry {
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
        let p = presentation.ok_or("M18 requires panel presentation")?;
        if self.objectives.len() != M18_OBJECTIVE_IDS.len() {
            return Err("M18 requires six ordered objectives");
        }
        for (i, obj) in self.objectives.iter().enumerate() {
            if obj.id != M18_OBJECTIVE_IDS[i] {
                return Err("unexpected M18 objective order");
            }
            match &obj.action {
                MissionObjectiveAction::Arrival { region, feet } => {
                    if !region.valid(half_extent)
                        || !point(*feet, half_extent)
                        || !region.contains(*feet)
                    {
                        return Err("invalid M18 objective arrival region or feet");
                    }
                }
                MissionObjectiveAction::Use { target } => {
                    if !point(target.approach, half_extent)
                        || target.decoration >= super::MAX_MAP_DECORATIONS
                        || target.point(p, solids).is_none()
                    {
                        return Err("M18 objective decoration misses solid or invalid approach");
                    }
                }
                _ => return Err("unexpected M18 objective action"),
            }
        }
        if !self.boarding.valid(half_extent) {
            return Err("invalid M18 boarding region");
        }
        if !point(self.departure.approach, half_extent) || self.departure.point(p, solids).is_none()
        {
            return Err("M18 departure decoration misses solid");
        }
        if !point(self.depot_station.approach, half_extent)
            || self.depot_station.point(p, solids).is_none()
        {
            return Err("M18 depot station decoration misses solid");
        }
        if !point(self.overlook_console.approach, half_extent)
            || self.overlook_console.point(p, solids).is_none()
        {
            return Err("M18 overlook console decoration misses solid");
        }
        Ok(())
    }
}

impl M18ObjectiveState {
    pub fn validate(&self, phase: MissionPhase, tick: u64) -> Result<(), &'static str> {
        self.challenges.validate()?;
        let n = super::mission::validate_ordered_progress(
            &self.completed,
            self.current.as_ref(),
            &M18_OBJECTIVE_IDS,
            &[0, 4],
            phase,
            tick,
        )?;
        if (n >= 1) != self.challenges.aid_delivered
            || self.aid_delivered != self.challenges.aid_delivered
            || (n >= 2) != self.challenges.square_defended
            || (n >= 3) != self.challenges.collector_neutralized
            || (n >= 5) != self.overlook_witnessed
            || self.overlook_witnessed != self.challenges.overlook_witnessed
            || (n >= 6) != self.concourse_secured
            || self.concourse_secured != self.challenges.concourse_secured
            || (n >= 3) != self.roadblock_active
        {
            return Err("M18 facts disagree with ordered progress");
        }
        if self.turn_started.is_some() != self.aid_delivered
            || self.turn_started.is_some_and(|at| at > tick)
        {
            return Err("M18 turn disagrees with the delivery");
        }
        if phase == MissionPhase::Briefing
            && (!self.completed.is_empty()
                || self.roadblock_active
                || self.overlook_witnessed
                || self.concourse_secured)
        {
            return Err("briefing M18 cannot carry progress");
        }
        if phase == MissionPhase::Departed {
            if !self.concourse_secured {
                return Err("departed M18 must have concourse secured");
            }
            if tick == 0 {
                return Err("departed M18 requires non-zero tick");
            }
        }
        Ok(())
    }
}
