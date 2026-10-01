//! Low Water freight departure and one bounded authoritative tram.
use super::{
    MapDecorationKind, MapPresentation, MissionObjective, MissionObjectiveAction, MissionPhase,
    MissionState, Region3, UseTarget,
};
use crate::movement::Solid;
use serde::{Deserialize, Serialize};

pub const M05_OBJECTIVE_IDS: [&str; 6] = [
    "roof_crossed",
    "grenade_lesson_cleared",
    "workshop_cleared",
    "trench_cleared",
    "heavy_cleared",
    "freight_secured",
];
pub const M05_WORKER_IDS: [&str; 3] = ["splice", "workshop_agent_a", "workshop_agent_b"];
pub type M05WorkerGeometry = super::M04PatientGeometry;
pub type M05WorkerState = super::M04PatientState;

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct M05RescueGeometry {
    pub release: Region3,
    pub captives: Vec<M05WorkerGeometry>,
}
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct M05TramGeometry {
    pub solid: usize,
    pub start: [f32; 3],
    pub end: [f32; 3],
    pub speed: f32,
    pub activation: Region3,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum M05TramPhase {
    Parked,
    Boarding,
    Moving,
    Blocked,
    Arrived,
}
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct M05TramState {
    pub phase: M05TramPhase,
    pub feet: [f32; 3],
    pub tick: u64,
}
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct M05MapGeometry {
    pub freight_open: bool,
    pub rescue: M05RescueGeometry,
    pub objectives: Vec<MissionObjective>,
    pub departure: UseTarget,
    pub boarding: Region3,
    pub companion_start: [f32; 3],
    pub tram: M05TramGeometry,
}
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct M05ObjectiveState {
    pub completed: Vec<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub current: Option<MissionObjective>,
    pub workshop_secured: bool,
    pub group_released: bool,
    pub captives: Vec<M05WorkerState>,
    pub freight_open: bool,
    pub tram: M05TramState,
    pub carried_recall_cars: Vec<String>,
    pub carried_patients: Vec<String>,
    pub carried_photos: u32,
}
impl M05TramGeometry {
    pub fn body(&self, baseline: Solid, feet: [f32; 3]) -> Solid {
        let dx = feet[0] - self.start[0];
        let dz = feet[2] - self.start[2];
        Solid {
            min_x: baseline.min_x + dx,
            max_x: baseline.max_x + dx,
            min_z: baseline.min_z + dz,
            max_z: baseline.max_z + dz,
            ..baseline
        }
    }
    pub fn valid_pose(&self, state: &M05TramState) -> bool {
        state.feet.iter().all(|v| v.is_finite())
            && (state.feet[0] - self.start[0]).abs() <= 0.001
            && (state.feet[1] - self.start[1]).abs() <= 0.001
            && state.feet[2] >= self.start[2].min(self.end[2]) - 0.001
            && state.feet[2] <= self.start[2].max(self.end[2]) + 0.001
            && (!matches!(state.phase, M05TramPhase::Parked | M05TramPhase::Boarding)
                || (state.feet[2] - self.start[2]).abs() <= 0.001)
            && (state.phase != M05TramPhase::Arrived
                || (state.feet[2] - self.end[2]).abs() <= 0.001)
    }
}
impl M05MapGeometry {
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
        let presentation = presentation.ok_or("M05 presentation missing")?;
        let body = solids
            .get(self.tram.solid)
            .ok_or("M05 tram solid missing")?;
        if !self.rescue.release.valid(half)
            || !self.boarding.valid(half)
            || !point(self.companion_start)
            || self.objectives.len() != 6
            || self.rescue.captives.len() != 3
            || !point(self.departure.approach)
            || self.departure.point(presentation, solids).is_none()
            || presentation
                .decorations
                .get(self.departure.decoration)
                .is_some_and(|p| p.solid == self.tram.solid)
            || !matches!(
                presentation.decorations[self.departure.decoration].kind,
                MapDecorationKind::LiftControl | MapDecorationKind::M05ShipDeparture
            )
            || !point(self.tram.start)
            || !point(self.tram.end)
            || !self.tram.activation.valid(half)
            || !self.tram.speed.is_finite()
            || !(0.1..=1.5).contains(&self.tram.speed)
            || self.tram.start[0] != self.tram.end[0]
            || self.tram.start[1] != self.tram.end[1]
            || !(2.0..=24.0).contains(&(self.tram.start[2] - self.tram.end[2]).abs())
            || (self.tram.start[0] - (body.min_x + body.max_x) * 0.5).abs() > 0.001
            || (self.tram.start[1] - body.bottom).abs() > 0.001
            || (self.tram.start[2] - (body.min_z + body.max_z) * 0.5).abs() > 0.001
        {
            return Err("invalid M05 geometry");
        }
        let end = self.tram.body(*body, self.tram.end);
        if [
            body.min_x, body.max_x, end.min_x, end.max_x, body.min_z, body.max_z, end.min_z,
            end.max_z,
        ]
        .iter()
        .any(|v| v.abs() > half)
        {
            return Err("M05 tram outside arena");
        }
        for (step, id) in self.objectives.iter().zip(M05_OBJECTIVE_IDS) {
            if step.id != id
                || !matches!(&step.action, MissionObjectiveAction::Arrival {region, feet}
                if region.valid(half) && point(*feet) && region.contains(*feet))
            {
                return Err("invalid M05 objective order");
            }
        }
        let mut ids = std::collections::HashSet::new();
        for (c, expected) in self.rescue.captives.iter().zip(M05_WORKER_IDS) {
            if c.id != expected
                || !ids.insert(&c.id)
                || !point(c.held)
                || !(2..=16).contains(&c.route.len())
                || !self.rescue.release.contains(c.held)
                || c.route[0] != c.held
                || c.route
                    .iter()
                    .any(|p| !point(*p) || (p[1] - c.held[1]).abs() > 0.01)
                || !self
                    .boarding
                    .contains(*c.route.last().ok_or("M05 captive route empty")?)
                || !super::m04::unambiguous_route(&c.route)
            {
                return Err("invalid M05 captive route");
            }
        }
        Ok(())
    }
}
impl MissionState {
    pub(super) fn validate_m05(&self, tick: u64) -> Result<(), &'static str> {
        let f = self.m05.as_ref().ok_or("M05 state missing")?;
        let mut ids = std::collections::HashSet::new();
        if self.m02.is_some()
            || self.m03.is_some()
            || self.m04.is_some()
            || !matches!(
                self.phase,
                MissionPhase::Briefing | MissionPhase::InProgress | MissionPhase::Departed
            )
            || f.completed.len() > 7
            || f.completed.iter().enumerate().any(|(i, id)| {
                id != if i == 6 {
                    "party_departed"
                } else {
                    M05_OBJECTIVE_IDS[i]
                }
            })
            || f.captives.len() != 3
            || f.group_released && !f.workshop_secured
            || f.completed.len() >= 3 && !f.workshop_secured
            || f.group_released && f.completed.len() < 2
            || f.freight_open && f.completed.len() < 5
            || f.tram.tick > tick
            || f.tram
                .feet
                .iter()
                .any(|v| !v.is_finite() || v.abs() > 512.0)
            || f.tram.feet[1] < 0.0
            || !f.group_released && f.tram.phase != M05TramPhase::Parked
            || f.carried_photos > 1_000_000
            || f.carried_recall_cars.len() > 4
            || f.carried_patients.len() > 4
        {
            return Err("invalid M05 facts");
        }
        for list in [&f.carried_recall_cars, &f.carried_patients] {
            ids.clear();
            if list
                .iter()
                .any(|id| !super::m04::valid_id(id) || !ids.insert(id))
            {
                return Err("invalid M05 carried outcomes");
            }
        }
        ids.clear();
        if f.captives.iter().zip(M05_WORKER_IDS).any(|(c, expected)| {
            c.id != expected
                || !ids.insert(&c.id)
                || c.feet.iter().any(|v| !v.is_finite() || v.abs() > 512.0)
                || c.feet[1] < 0.0
        }) {
            return Err("invalid M05 captives");
        }
        if self.phase == MissionPhase::Briefing
            && (!f.completed.is_empty() || f.workshop_secured || f.group_released || f.freight_open)
            || (self.phase == MissionPhase::Departed) != (f.completed.len() == 7)
            || f.current.is_some() != (f.completed.len() < 7)
        {
            return Err("invalid M05 phase");
        }
        if let Some(current) = &f.current {
            let i = f.completed.len();
            if current.id
                != if i == 6 {
                    "party_departed"
                } else {
                    M05_OBJECTIVE_IDS[i]
                }
                || !matches!(
                    (&current.action, i),
                    (MissionObjectiveAction::Arrival { .. }, 0..=5)
                        | (MissionObjectiveAction::Use { .. }, 6)
                )
            {
                return Err("invalid M05 current objective");
            }
        }
        Ok(())
    }
}
