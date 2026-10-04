//! The launch berth's ordered fights, physical crew release and boarding hatch.
use super::{
    MapDecorationKind, MapPresentation, MissionObjective, MissionObjectiveAction, Region3,
    UseTarget,
};
use crate::movement::Solid;
use serde::{Deserialize, Serialize};

/// A cabinet copy is secured evidence, not proof of restoration or identity.
/// Historical v9 bytes never recorded these choices. Keep that absence honest.
#[derive(Debug, Clone, PartialEq, Eq, Deserialize, Serialize)]
#[serde(tag = "kind", rename_all = "snake_case", deny_unknown_fields)]
pub enum M08Outcome {
    Recorded {
        custody_released: bool,
        recovered_mind_secured: bool,
        captives_evacuated: bool,
    },
    HistoricalUnrecorded {},
}

impl M08Outcome {
    pub(crate) fn validate(&self) -> Result<(), &'static str> {
        if matches!(
            self,
            Self::Recorded {
                custody_released: false,
                captives_evacuated: true,
                ..
            }
        ) {
            return Err("saved custody evacuation requires actual release");
        }
        Ok(())
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct M09CrewState {
    pub id: String,
    pub feet: [f32; 3],
    pub aboard: bool,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct M09ObjectiveState {
    pub completed: Vec<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub current: Option<MissionObjective>,
    pub crew_released: bool,
    pub crew: Vec<M09CrewState>,
    pub hatch_open: bool,
    pub charge_falls: u8,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub carried_archive: Option<M08Outcome>,
}

impl super::MissionState {
    pub(super) fn validate_m09(&self) -> Result<(), &'static str> {
        let f = self.m09.as_ref().ok_or("M09 facts missing")?;
        let ids: Vec<&str> = M09_OBJECTIVE_IDS
            .into_iter()
            .chain(["party_departed"])
            .collect();
        if self.m02.is_some()
            || self.m03.is_some()
            || self.m04.is_some()
            || self.m05.is_some()
            || self.m06.is_some()
            || self.m07.is_some()
            || self.m08.is_some()
            || !matches!(
                self.phase,
                super::MissionPhase::Briefing
                    | super::MissionPhase::InProgress
                    | super::MissionPhase::Departed
            )
            || f.completed.len() > ids.len()
            || f.completed.iter().zip(&ids).any(|(a, b)| a != b)
            || (self.phase == super::MissionPhase::Departed) != (f.completed.len() == ids.len())
            || f.current.is_some() != (f.completed.len() < ids.len())
            || f.crew_released != (f.completed.len() >= 3)
            || f.hatch_open != (f.completed.len() >= 7)
            || f.charge_falls > 7
            || self.phase == super::MissionPhase::Briefing
                && (!f.completed.is_empty() || f.charge_falls > 0)
            || !(3..=5).contains(&f.crew.len())
            || f.crew.iter().enumerate().any(|(i, c)| {
                (i < 3 && c.id != M09_CREW_IDS[i])
                    || (i == 3 && !matches!(c.id.as_str(), "edda" | "splice"))
                    || (i == 4 && (f.crew[3].id != "edda" || c.id != "splice"))
                    || c.feet.iter().any(|v| !v.is_finite() || v.abs() > 512.0)
                    || c.feet[1] < 0.0
                    || c.aboard && (!f.hatch_open || !f.crew_released)
            })
        {
            return Err("invalid M09 ordered facts or crew");
        }
        if let Some(history) = &f.carried_archive {
            history.validate()?;
        }
        if let Some(current) = &f.current {
            let index = f.completed.len();
            if current.id != ids[index]
                || !matches!(
                    (&current.action, index),
                    (MissionObjectiveAction::Arrival { .. }, 0 | 1 | 3..=7)
                        | (MissionObjectiveAction::Use { .. }, 2 | 8)
                )
            {
                return Err("invalid M09 current step");
            }
            match &current.action {
                MissionObjectiveAction::Arrival { region, feet }
                    if !region.valid(512.0)
                        || !region.contains(*feet)
                        || feet.iter().any(|v| !v.is_finite() || v.abs() > 512.0) =>
                {
                    return Err("invalid M09 arrival");
                }
                MissionObjectiveAction::Use { target }
                    if target.decoration >= super::MAX_MAP_DECORATIONS
                        || target
                            .approach
                            .iter()
                            .any(|v| !v.is_finite() || v.abs() > 512.0)
                        || target.approach[1] < 0.0 =>
                {
                    return Err("invalid M09 use");
                }
                _ => {}
            }
        }
        Ok(())
    }
}

pub const M09_OBJECTIVE_IDS: [&str; 8] = [
    "loading_cleared",
    "lesson_cleared",
    "crew_freed",
    "gantry_one_cleared",
    "gantry_two_cleared",
    "gantry_three_cleared",
    "clamps_released",
    "hatch_cleared",
];
pub const M09_CREW_STEP: usize = 2;
pub const M09_CREW_IDS: [&str; 5] = ["tern", "berth_crew_a", "berth_crew_b", "edda", "splice"];

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct M09CrewGeometry {
    pub id: String,
    /// Supported authored route. Eligibility advances with the cleared climb.
    pub route: Vec<[f32; 3]>,
    pub held_until: Vec<u8>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct M09MapGeometry {
    /// Seven arrivals, excluding the actual crew-release Use at index two.
    pub objectives: Vec<MissionObjective>,
    pub crew_release: UseTarget,
    pub crew: Vec<M09CrewGeometry>,
    pub departure: UseTarget,
    pub boarding: Region3,
    pub companion_start: [f32; 3],
    pub hatch: usize,
    pub hatch_open: bool,
}

impl M09MapGeometry {
    pub fn step(&self, index: usize) -> Option<MissionObjective> {
        match index {
            0 | 1 => self.objectives.get(index).cloned(),
            M09_CREW_STEP => Some(MissionObjective {
                id: M09_OBJECTIVE_IDS[M09_CREW_STEP].into(),
                action: MissionObjectiveAction::Use {
                    target: self.crew_release.clone(),
                },
            }),
            3..=7 => self.objectives.get(index - 1).cloned(),
            8 => Some(MissionObjective {
                id: "party_departed".into(),
                action: MissionObjectiveAction::Use {
                    target: self.departure.clone(),
                },
            }),
            _ => None,
        }
    }

    pub fn validate(
        &self,
        half: f32,
        solids: &[Solid],
        presentation: Option<&MapPresentation>,
    ) -> Result<(), &'static str> {
        let point = |p: &[f32; 3]| {
            p.iter().all(|v| v.is_finite())
                && p[0].abs() <= half
                && p[2].abs() <= half
                && (0.0..=512.0).contains(&p[1])
        };
        let presentation = presentation.ok_or("M09 presentation missing")?;
        let ids = M09_OBJECTIVE_IDS
            .iter()
            .enumerate()
            .filter(|(i, _)| *i != M09_CREW_STEP)
            .map(|(_, id)| *id);
        if !half.is_finite() || half <= 0.0 || self.objectives.len() != 7
            || self.objectives.iter().zip(ids).any(|(s, id)| s.id != id || !matches!(&s.action, MissionObjectiveAction::Arrival {region, feet} if region.valid(half) && point(feet) && region.contains(*feet)))
            || !point(&self.companion_start) || !self.boarding.valid(half)
            || !self.boarding.contains(self.departure.approach)
            || self.hatch >= solids.len() || self.crew.len() != M09_CREW_IDS.len()
            || self.crew.iter().zip(M09_CREW_IDS).any(|(c, id)| c.id != id
                || !(2..=32).contains(&c.route.len()) || c.route.len() != c.held_until.len()
                || c.route.iter().any(|p| !point(p))
                || c.held_until.first() != Some(&0) || c.held_until.iter().any(|stage| *stage > 8)
                || c.held_until.iter().skip(1).any(|stage| *stage < 3)
                || c.held_until.last().is_none_or(|stage| *stage < 7)
                || c.held_until.windows(2).any(|w| w[1] < w[0])
                || !c.route.last().is_some_and(|p| self.boarding.contains(*p)))
        { return Err("invalid M09 geometry"); }
        for control in [&self.crew_release, &self.departure] {
            if !point(&control.approach)
                || control.point(presentation, solids).is_none()
                || presentation
                    .decorations
                    .get(control.decoration)
                    .is_none_or(|p| {
                        p.kind != MapDecorationKind::LiftControl || p.solid == self.hatch
                    })
            {
                return Err("invalid M09 physical control");
            }
        }
        if self.crew_release == self.departure {
            return Err("M09 release and departure require separate controls");
        }
        let hatch = solids[self.hatch];
        if self.hatch_open && hatch.bottom < self.boarding.max[1] + crate::movement::BODY_HEIGHT
            || !self.hatch_open
                && (hatch.bottom > self.departure.approach[1]
                    || hatch.top < self.departure.approach[1] + crate::movement::BODY_HEIGHT)
        {
            return Err("M09 hatch flag disagrees with its blocking body");
        }
        Ok(())
    }
}
