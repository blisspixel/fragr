//! Lunar curfew town, crater cut and depot freight departure, with every
//! retained earlier outcome.
use super::{
    MapDecorationKind, MapPresentation, MissionObjective, MissionObjectiveAction, MissionPhase,
    MissionState, Region3, UseTarget, M05_WORKER_IDS,
};
use crate::movement::Solid;
use serde::{Deserialize, Serialize};

pub const M07_OBJECTIVE_IDS: [&str; 5] = [
    "ring_cleared",
    "plaza_cleared",
    "post_cleared",
    "window_cleared",
    "cut_cleared",
];

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct M07MapGeometry {
    pub objectives: Vec<MissionObjective>,
    pub departure: UseTarget,
    pub boarding: Region3,
    pub companion_start: [f32; 3],
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct M07ObjectiveState {
    pub completed: Vec<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub current: Option<MissionObjective>,
    pub carried_recall_cars: Vec<String>,
    pub carried_patients: Vec<String>,
    pub carried_photos: u32,
    pub carried_released_workers: Vec<String>,
    pub carried_evacuated_workers: Vec<String>,
    pub carried_prisoner_route_marked: bool,
}

impl M07MapGeometry {
    pub fn validate(
        &self,
        half: f32,
        solids: &[Solid],
        presentation: Option<&MapPresentation>,
    ) -> Result<(), &'static str> {
        let point = |p: [f32; 3]| {
            p.iter().all(|v| v.is_finite())
                && p[0].abs() <= half
                && p[2].abs() <= half
                && (0.0..=512.0).contains(&p[1])
        };
        let arrival = |s: &MissionObjective| {
            matches!(&s.action, MissionObjectiveAction::Arrival {region, feet}
                if region.valid(half) && point(*feet) && region.contains(*feet))
        };
        let presentation = presentation.ok_or("M07 presentation missing")?;
        if !half.is_finite()
            || half <= 0.0
            || self.objectives.len() != M07_OBJECTIVE_IDS.len()
            || self
                .objectives
                .iter()
                .zip(M07_OBJECTIVE_IDS)
                .any(|(s, id)| s.id != id || !arrival(s))
            || !self.boarding.valid(half)
            || !point(self.companion_start)
            || !point(self.departure.approach)
            || !self.boarding.contains(self.departure.approach)
            || self.departure.point(presentation, solids).is_none()
            || presentation
                .decorations
                .get(self.departure.decoration)
                .is_none_or(|p| {
                    !matches!(
                        p.kind,
                        MapDecorationKind::LiftControl | MapDecorationKind::M07DepotFreight
                    )
                })
        {
            return Err("invalid M07 geometry");
        }
        Ok(())
    }
}

impl MissionState {
    pub(super) fn validate_m07(&self) -> Result<(), &'static str> {
        let f = self.m07.as_ref().ok_or("M07 facts missing")?;
        let order = |i: usize| {
            if i == M07_OBJECTIVE_IDS.len() {
                "party_departed"
            } else {
                M07_OBJECTIVE_IDS[i]
            }
        };
        let total = M07_OBJECTIVE_IDS.len() + 1;
        if self.m02.is_some()
            || self.m03.is_some()
            || self.m04.is_some()
            || self.m05.is_some()
            || self.m06.is_some()
            || !matches!(
                self.phase,
                MissionPhase::Briefing | MissionPhase::InProgress | MissionPhase::Departed
            )
            || f.completed.len() > total
            || f.completed.iter().enumerate().any(|(i, id)| id != order(i))
            || (self.phase == MissionPhase::Departed) != (f.completed.len() == total)
            || f.current.is_some() != (f.completed.len() < total)
            || self.phase == MissionPhase::Briefing && !f.completed.is_empty()
            || f.carried_photos > 1_000_000
        {
            return Err("invalid M07 objective facts");
        }
        if let Some(current) = &f.current {
            let i = f.completed.len();
            let point =
                |p: &[f32; 3]| p.iter().all(|v| v.is_finite() && v.abs() <= 512.0) && p[1] >= 0.0;
            if current.id != order(i)
                || !matches!(
                    (&current.action, i == M07_OBJECTIVE_IDS.len()),
                    (MissionObjectiveAction::Arrival { .. }, false)
                        | (MissionObjectiveAction::Use { .. }, true)
                )
            {
                return Err("invalid M07 current objective");
            }
            match &current.action {
                MissionObjectiveAction::Arrival { region, feet }
                    if !region.valid(512.0) || !point(feet) || !region.contains(*feet) =>
                {
                    return Err("invalid M07 arrival target");
                }
                MissionObjectiveAction::Use { target }
                    if !point(&target.approach)
                        || target.decoration >= super::MAX_MAP_DECORATIONS =>
                {
                    return Err("invalid M07 use target");
                }
                _ => {}
            }
        }
        let identities = |list: &[String], allowed: &[&str]| {
            let mut seen = std::collections::HashSet::new();
            list.len() <= allowed.len()
                && list
                    .iter()
                    .all(|id| allowed.contains(&id.as_str()) && seen.insert(id))
        };
        for list in [&f.carried_recall_cars, &f.carried_patients] {
            let mut seen = std::collections::HashSet::new();
            if list.len() > 4
                || list
                    .iter()
                    .any(|id| !super::m04::valid_id(id) || !seen.insert(id))
            {
                return Err("invalid M07 historical outcomes");
            }
        }
        if !identities(&f.carried_released_workers, &M05_WORKER_IDS)
            || !matches!(f.carried_released_workers.len(), 0 | 3)
            || !identities(&f.carried_evacuated_workers, &M05_WORKER_IDS)
            || f.carried_evacuated_workers
                .iter()
                .any(|id| !f.carried_released_workers.contains(id))
        {
            return Err("invalid M07 carried outcomes");
        }
        Ok(())
    }
}
