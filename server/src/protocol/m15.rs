//! Civic Pressure Valve: ordered stadium bout objectives and resolved challenge receipts.
use super::{
    CampaignDifficulty, MapPresentation, MissionObjective, MissionObjectiveAction, MissionPhase,
    Region3, UseTarget,
};
use crate::movement::Solid;
use serde::{Deserialize, Serialize};

pub const M15_OBJECTIVE_IDS: [&str; 6] = [
    "pen_armed",
    "pen_cleared",
    "blade_lesson_won",
    "wardens_cleared",
    "broadcast_secured",
    "bout_won",
];

pub const M15_ENTRANTS: [u8; 4] = [4, 12, 44, 71];

#[derive(Debug, Clone, PartialEq, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct M15MapGeometry {
    pub objectives: Vec<MissionObjective>,
    pub departure: UseTarget,
    pub boarding: Region3,
    pub arming_crate: UseTarget,
    pub booth_terminal: UseTarget,
    pub tunnel_closed: bool,
    pub gates_open: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct M15ChallengeState {
    pub pen_armed: bool,
    pub blade_wave_won: bool,
    pub entrants_preserved: bool,
}

impl Default for M15ChallengeState {
    fn default() -> Self {
        Self {
            pen_armed: false,
            blade_wave_won: false,
            entrants_preserved: true,
        }
    }
}

impl M15ChallengeState {
    pub fn validate(&self) -> Result<(), &'static str> {
        if self.blade_wave_won && !self.pen_armed {
            return Err("M15 blade wave victory precedes pen arming");
        }
        Ok(())
    }

    pub fn brief_completed(&self, difficulty: CampaignDifficulty) -> bool {
        self.pen_armed
            && (difficulty == CampaignDifficulty::Assisted
                || self.blade_wave_won
                    && (difficulty != CampaignDifficulty::Severe || self.entrants_preserved))
    }
}

#[derive(Debug, Clone, PartialEq, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct M15ObjectiveState {
    pub completed: Vec<String>,
    #[serde(
        default,
        deserialize_with = "super::m11::present",
        skip_serializing_if = "Option::is_none"
    )]
    pub current: Option<MissionObjective>,
    pub challenges: M15ChallengeState,
    pub tunnel_closed: bool,
    pub gates_open: bool,
    pub broadcast_taken: bool,
    pub wave: u8,
    pub armed_entrants: Vec<u8>,
    pub fallen_entrants: Vec<u8>,
}

fn point(p: [f32; 3], half: f32) -> bool {
    p.iter().all(|v| v.is_finite())
        && p[0].abs() <= half
        && p[2].abs() <= half
        && (0.0..=512.0).contains(&p[1])
}

impl M15MapGeometry {
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
        let presentation = presentation.ok_or("M15 presentation missing")?;
        if !half.is_finite()
            || !(2.0..=crate::movement::MAX_HALF_EXTENT).contains(&half)
            || self.objectives.len() != M15_OBJECTIVE_IDS.len()
            || self
                .objectives
                .iter()
                .zip(M15_OBJECTIVE_IDS)
                .any(|(o, id)| {
                    o.id != id
                        || match &o.action {
                            MissionObjectiveAction::Arrival { region, feet } => {
                                !region.valid(half)
                                    || !point(*feet, half)
                                    || !region.contains(*feet)
                            }
                            MissionObjectiveAction::Use { target } => {
                                !point(target.approach, half)
                                    || target.decoration >= super::MAX_MAP_DECORATIONS
                                    || target.point(presentation, solids).is_none()
                            }
                            _ => true,
                        }
                })
            || !self.boarding.valid(half)
            || !self.boarding.contains(self.departure.approach)
            || !point(self.departure.approach, half)
            || self.departure.point(presentation, solids).is_none()
            || !point(self.arming_crate.approach, half)
            || self.arming_crate.point(presentation, solids).is_none()
            || !point(self.booth_terminal.approach, half)
            || self.booth_terminal.point(presentation, solids).is_none()
        {
            return Err("invalid M15 stadium geometry");
        }
        Ok(())
    }
}

impl M15ObjectiveState {
    pub fn validate(&self, phase: MissionPhase, _tick: u64) -> Result<(), &'static str> {
        self.challenges.validate()?;
        let n = self.completed.len();
        let order = |i| {
            M15_OBJECTIVE_IDS
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
            || self.wave > 5
            || (n >= 1) != self.challenges.pen_armed
            || if self.tunnel_closed { n < 2 } else { n >= 3 }
            || (n >= 5) != self.broadcast_taken
            || (n >= 6) != self.gates_open
            || phase == MissionPhase::Briefing
                && (n != 0
                    || self.challenges != M15ChallengeState::default()
                    || self.tunnel_closed
                    || self.gates_open
                    || self.broadcast_taken
                    || self.wave != 0
                    || !self.armed_entrants.is_empty()
                    || !self.fallen_entrants.is_empty())
        {
            return Err("invalid M15 ordered progression");
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
                        (n != 0 && n != 4 && n != 6)
                            || !point(target.approach, 512.0)
                            || target.decoration >= super::MAX_MAP_DECORATIONS
                    }
                    _ => true,
                }
            {
                return Err("invalid M15 current objective");
            }
        }
        Ok(())
    }
}
