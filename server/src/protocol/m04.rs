//! Bounded clinic geometry and authoritative Notice to Vacate observations.
use super::{
    MapDecorationKind, MapPresentation, MissionObjective, MissionObjectiveAction, MissionPhase,
    MissionState, Region3, UseTarget,
};
use crate::movement::Solid;
use serde::{Deserialize, Serialize};

pub const M04_OBJECTIVE_IDS: [&str; 6] = [
    "notice_board_cleared",
    "first_notary_cleared",
    "street_wave_cleared",
    "market_wave_a_cleared",
    "market_wave_b_cleared",
    "court_cleared",
];

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct M04ClinicGeometry {
    pub control: UseTarget,
    pub release: Region3,
}
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct M04PatientGeometry {
    pub id: String,
    pub held: [f32; 3],
    pub route: Vec<[f32; 3]>,
}
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct M04MapGeometry {
    pub clinic_open: bool,
    pub clinic: M04ClinicGeometry,
    pub patients: Vec<M04PatientGeometry>,
    pub objectives: Vec<MissionObjective>,
    pub departure: UseTarget,
    pub boarding: Region3,
    pub companion_start: [f32; 3],
}
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct M04PatientState {
    pub id: String,
    pub feet: [f32; 3],
}
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct M04ObjectiveState {
    pub completed: Vec<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub current: Option<MissionObjective>,
    pub clinic_secured: bool,
    pub clinic_open: bool,
    pub patients_released: bool,
    pub patients: Vec<M04PatientState>,
    pub photos_completed: u32,
    pub carried_recall_cars: Vec<String>,
}
pub(crate) fn valid_id(id: &str) -> bool {
    !id.is_empty()
        && id.len() <= 64
        && id
            .bytes()
            .all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == b'_')
}
impl M04MapGeometry {
    pub fn validate(
        &self,
        half: f32,
        solids: &[Solid],
        presentation: Option<&MapPresentation>,
    ) -> Result<(), &'static str> {
        let presentation = presentation.ok_or("M04 presentation missing")?;
        let point = |p: [f32; 3]| {
            p.iter().all(|n| n.is_finite())
                && p[0].abs() <= half
                && p[2].abs() <= half
                && (0.0..=crate::movement::MAX_HALF_EXTENT * 2.0).contains(&p[1])
        };
        if !self.clinic.release.valid(half)
            || !self.boarding.valid(half)
            || !point(self.companion_start)
            || self.clinic.control.decoration == self.departure.decoration
            || self.objectives.len() != 6
            || !(1..=4).contains(&self.patients.len())
        {
            return Err("invalid M04 geometry bounds");
        }
        for target in [&self.clinic.control, &self.departure] {
            if !point(target.approach) || target.point(presentation, solids).is_none() {
                return Err("invalid M04 control");
            }
        }
        if !matches!(
            presentation.decorations[self.clinic.control.decoration].kind,
            MapDecorationKind::Terminal
                | MapDecorationKind::LiftControl
                | MapDecorationKind::M04ClinicControl
        ) || !matches!(
            presentation.decorations[self.departure.decoration].kind,
            MapDecorationKind::LiftControl | MapDecorationKind::M04RoofDeparture
        ) {
            return Err("invalid M04 registered control kind");
        }
        for (step, id) in self.objectives.iter().zip(M04_OBJECTIVE_IDS) {
            if step.id != id {
                return Err("invalid M04 objective order");
            }
            match &step.action {
                MissionObjectiveAction::Arrival { region, feet }
                    if region.valid(half) && point(*feet) && region.contains(*feet) => {}
                _ => return Err("invalid M04 arrival"),
            }
        }
        let mut ids = std::collections::HashSet::new();
        for patient in &self.patients {
            if !valid_id(&patient.id)
                || !ids.insert(&patient.id)
                || !point(patient.held)
                || !(2..=16).contains(&patient.route.len())
                || patient
                    .route
                    .iter()
                    .any(|p| !point(*p) || (p[1] - patient.held[1]).abs() > 0.01)
                || (0..3).any(|i| (patient.route[0][i] - patient.held[i]).abs() > 0.01)
                || !unambiguous_route(&patient.route)
            {
                return Err("invalid M04 patient route");
            }
        }
        Ok(())
    }
}
// A patient position must identify one forward part of its registered route.
// Reject loops, reversals and overlapping nonadjacent tolerance corridors.
pub(crate) fn unambiguous_route(route: &[[f32; 3]]) -> bool {
    let distance = |a: [f32; 3], b: [f32; 3]| (a[0] - b[0]).hypot(a[2] - b[2]);
    let cross = |a: [f32; 3], b: [f32; 3], c: [f32; 3]| {
        (b[0] - a[0]) * (c[2] - a[2]) - (b[2] - a[2]) * (c[0] - a[0])
    };
    let point_segment = |p: [f32; 3], a: [f32; 3], b: [f32; 3]| {
        let dx = b[0] - a[0];
        let dz = b[2] - a[2];
        let t = (((p[0] - a[0]) * dx + (p[2] - a[2]) * dz) / (dx * dx + dz * dz)).clamp(0.0, 1.0);
        (p[0] - a[0] - t * dx).hypot(p[2] - a[2] - t * dz)
    };
    if route.windows(2).any(|p| distance(p[0], p[1]) <= 0.1) {
        return false;
    }
    for (i, pair) in route.windows(2).enumerate() {
        if let Some(next) = route.get(i + 2) {
            if cross(pair[0], pair[1], *next).abs() <= 0.0001
                && (pair[1][0] - pair[0][0]) * (next[0] - pair[1][0])
                    + (pair[1][2] - pair[0][2]) * (next[2] - pair[1][2])
                    < 0.0
            {
                return false;
            }
        }
        for other in route.windows(2).skip(i + 2) {
            let intersects = cross(pair[0], pair[1], other[0]) * cross(pair[0], pair[1], other[1])
                < 0.0
                && cross(other[0], other[1], pair[0]) * cross(other[0], other[1], pair[1]) < 0.0;
            if intersects
                || [
                    point_segment(pair[0], other[0], other[1]),
                    point_segment(pair[1], other[0], other[1]),
                    point_segment(other[0], pair[0], pair[1]),
                    point_segment(other[1], pair[0], pair[1]),
                ]
                .into_iter()
                .any(|d| d <= 0.1)
            {
                return false;
            }
        }
    }
    true
}
impl MissionState {
    pub(super) fn validate_m04(&self) -> Result<(), &'static str> {
        let facts = self.m04.as_ref().ok_or("M04 state missing")?;
        let mut ids = std::collections::HashSet::new();
        if self.m02.is_some()
            || self.m03.is_some()
            || !matches!(
                self.phase,
                MissionPhase::Briefing | MissionPhase::InProgress | MissionPhase::Departed
            )
            || facts.completed.len() > 7
            || facts.completed.iter().enumerate().any(|(i, id)| {
                id != if i == 6 {
                    "party_departed"
                } else {
                    M04_OBJECTIVE_IDS[i]
                }
            })
            || facts.photos_completed > 1_000_000
            || !(1..=4).contains(&facts.patients.len())
            || facts.carried_recall_cars.len() > 4
            || facts
                .carried_recall_cars
                .iter()
                .any(|id| !valid_id(id) || !ids.insert(id))
            || facts.clinic_open && !facts.clinic_secured
            || facts.patients_released && !facts.clinic_open
        {
            return Err("invalid M04 facts");
        }
        ids.clear();
        if facts.patients.iter().any(|p| {
            !valid_id(&p.id)
                || !ids.insert(&p.id)
                || p.feet
                    .iter()
                    .any(|v| !v.is_finite() || v.abs() > crate::movement::MAX_HALF_EXTENT * 2.0)
                || p.feet[1] < 0.0
        }) {
            return Err("invalid M04 patients");
        }
        if self.phase == MissionPhase::Briefing
            && (!facts.completed.is_empty()
                || facts.clinic_secured
                || facts.clinic_open
                || facts.patients_released
                || facts.photos_completed > 0)
        {
            return Err("M04 briefing cannot contain attempt progress");
        }
        if (self.phase == MissionPhase::Departed) != (facts.completed.len() == 7)
            || facts.current.is_some() != (facts.completed.len() < 7)
        {
            return Err("invalid M04 departure");
        }
        if let Some(current) = &facts.current {
            let index = facts.completed.len();
            if current.id
                != if index == 6 {
                    "party_departed"
                } else {
                    M04_OBJECTIVE_IDS[index]
                }
                || !matches!(
                    (&current.action, index),
                    (MissionObjectiveAction::Arrival { .. }, 0..=5)
                        | (MissionObjectiveAction::Use { .. }, 6)
                )
            {
                return Err("invalid M04 current objective");
            }
        }
        Ok(())
    }
}
