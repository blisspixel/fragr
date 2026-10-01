//! Static lunar port objectives and retained Earth outcomes.
use super::{
    MapDecorationKind, MapPresentation, MissionObjective, MissionObjectiveAction, MissionPhase,
    MissionState, Region3, UseTarget, M05_WORKER_IDS,
};
use crate::movement::Solid;
use serde::{Deserialize, Serialize};

pub const M06_OBJECTIVE_IDS: [&str; 6] = [
    "freight_cleared",
    "rail_lane_cleared",
    "loading_cleared",
    "turret_cleared",
    "customs_cleared",
    "exit_cleared",
];
pub const M06_SERVICE_ID: &str = "prisoner_route_marked";

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct M06MapGeometry {
    pub objectives: Vec<MissionObjective>,
    pub service: MissionObjective,
    pub departure: UseTarget,
    pub boarding: Region3,
    pub companion_start: [f32; 3],
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct M06ObjectiveState {
    pub completed: Vec<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub current: Option<MissionObjective>,
    pub prisoner_route_marked: bool,
    pub carried_recall_cars: Vec<String>,
    pub carried_patients: Vec<String>,
    pub carried_photos: u32,
    pub carried_released_workers: Vec<String>,
    pub carried_evacuated_workers: Vec<String>,
}

impl M06MapGeometry {
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
        let presentation = presentation.ok_or("M06 presentation missing")?;
        if !half.is_finite()
            || half <= 0.0
            || self.objectives.len() != M06_OBJECTIVE_IDS.len()
            || self
                .objectives
                .iter()
                .zip(M06_OBJECTIVE_IDS)
                .any(|(s, id)| s.id != id || !arrival(s))
            || self.service.id != M06_SERVICE_ID
            || !arrival(&self.service)
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
                        MapDecorationKind::LiftControl | MapDecorationKind::M06TransitDeparture
                    )
                })
        {
            return Err("invalid M06 geometry");
        }
        Ok(())
    }
}

impl MissionState {
    pub(super) fn validate_m06(&self) -> Result<(), &'static str> {
        let f = self.m06.as_ref().ok_or("M06 facts missing")?;
        if self.m02.is_some()
            || self.m03.is_some()
            || self.m04.is_some()
            || self.m05.is_some()
            || !matches!(
                self.phase,
                MissionPhase::Briefing | MissionPhase::InProgress | MissionPhase::Departed
            )
            || f.completed.len() > 7
            || f.completed.iter().enumerate().any(|(i, id)| {
                id != if i == 6 {
                    "party_departed"
                } else {
                    M06_OBJECTIVE_IDS[i]
                }
            })
            || (self.phase == MissionPhase::Departed) != (f.completed.len() == 7)
            || f.current.is_some() != (f.completed.len() < 7)
            || self.phase == MissionPhase::Briefing
                && (!f.completed.is_empty() || f.prisoner_route_marked)
            || f.prisoner_route_marked && f.completed.len() < 3
            || f.carried_photos > 1_000_000
        {
            return Err("invalid M06 objective facts");
        }
        if let Some(current) = &f.current {
            let i = f.completed.len();
            let point =
                |p: &[f32; 3]| p.iter().all(|v| v.is_finite() && v.abs() <= 512.0) && p[1] >= 0.0;
            if current.id
                != if i == 6 {
                    "party_departed"
                } else {
                    M06_OBJECTIVE_IDS[i]
                }
                || !matches!(
                    (&current.action, i),
                    (MissionObjectiveAction::Arrival { .. }, 0..=5)
                        | (MissionObjectiveAction::Use { .. }, 6)
                )
            {
                return Err("invalid M06 current objective");
            }
            match &current.action {
                MissionObjectiveAction::Arrival { region, feet }
                    if !region.valid(512.0) || !point(feet) || !region.contains(*feet) =>
                {
                    return Err("invalid M06 arrival target");
                }
                MissionObjectiveAction::Use { target }
                    if !point(&target.approach)
                        || target.decoration >= super::MAX_MAP_DECORATIONS =>
                {
                    return Err("invalid M06 use target");
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
                return Err("invalid M06 historical outcomes");
            }
        }
        if !identities(&f.carried_released_workers, &M05_WORKER_IDS)
            || !matches!(f.carried_released_workers.len(), 0 | 3)
            || !identities(&f.carried_evacuated_workers, &M05_WORKER_IDS)
            || f.carried_evacuated_workers
                .iter()
                .any(|id| !f.carried_released_workers.contains(id))
        {
            return Err("invalid M06 carried outcomes");
        }
        Ok(())
    }
}
