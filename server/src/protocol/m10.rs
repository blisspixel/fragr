//! Working ship spaces and ordered boarding-defense targets.
use super::{
    M08Outcome, MapDecorationKind, MapPresentation, MissionObjective, MissionObjectiveAction,
    MissionPhase, MissionState, Region3, UseTarget, M09_CREW_IDS,
};
use serde::{Deserialize, Serialize};

pub const M10_OBJECTIVE_IDS: [&str; 4] = [
    "forward_secured",
    "service_secured",
    "aft_secured",
    "passengers_secured",
];

#[derive(Debug, Clone, PartialEq, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct M10PassengerGeometry {
    pub id: String,
    pub feet: [f32; 3],
}

#[derive(Debug, Clone, PartialEq, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct M10MapGeometry {
    pub objectives: Vec<MissionObjective>,
    pub departure: UseTarget,
    pub boarding: Region3,
    pub pilot: [f32; 3],
    pub companion_start: [f32; 3],
    pub passengers: Vec<M10PassengerGeometry>,
}

#[derive(Debug, Clone, PartialEq, Eq, Deserialize, Serialize)]
#[serde(tag = "kind", rename_all = "snake_case", deny_unknown_fields)]
pub enum M10Transit {
    Recorded { arrived_crew: Vec<String> },
    HistoricalUnrecorded {},
}

impl M10Transit {
    pub fn validate(&self) -> Result<(), &'static str> {
        let Self::Recorded { arrived_crew } = self else {
            return Ok(());
        };
        if !(3..=5).contains(&arrived_crew.len())
            || arrived_crew[..3]
                .iter()
                .map(String::as_str)
                .collect::<Vec<_>>()
                != M09_CREW_IDS[..3]
        {
            return Err("M10 transit requires its actual released core crew");
        }
        let mut next = 0;
        for id in arrived_crew {
            let Some(offset) = M09_CREW_IDS[next..]
                .iter()
                .position(|allowed| *allowed == id)
            else {
                return Err("M10 arrivals must be unique and canonically ordered");
            };
            next += offset + 1;
        }
        Ok(())
    }
    pub fn arrived(&self, id: &str) -> bool {
        matches!(self, Self::Recorded {arrived_crew} if arrived_crew.iter().any(|p| p == id))
    }
}

#[derive(Debug, Clone, PartialEq, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct M10ObjectiveState {
    pub completed: Vec<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub current: Option<MissionObjective>,
    pub transit: M10Transit,
    pub pilot: [f32; 3],
    pub passengers: Vec<M10PassengerGeometry>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub carried_archive: Option<M08Outcome>,
}

impl M10MapGeometry {
    pub fn validate(
        &self,
        half: f32,
        solids: &[crate::movement::Solid],
        presentation: Option<&MapPresentation>,
    ) -> Result<(), &'static str> {
        let present = presentation.ok_or("M10 presentation missing")?;
        let point = |p: [f32; 3]| {
            p.iter().all(|v| v.is_finite())
                && p[0].abs() <= half
                && p[2].abs() <= half
                && (0.0..=512.0).contains(&p[1])
        };
        if !half.is_finite() || half <= 0.0 || self.objectives.len() != M10_OBJECTIVE_IDS.len() || self.objectives.iter().zip(M10_OBJECTIVE_IDS).any(|(o,id)| o.id != id || !matches!(&o.action, MissionObjectiveAction::Arrival {region, feet} if region.valid(half) && point(*feet) && region.contains(*feet)))
            || !self.boarding.valid(half) || !self.boarding.contains(self.departure.approach) || !point(self.departure.approach) || !point(self.pilot) || !point(self.companion_start)
            || self.departure.point(present, solids).is_none() || present.decorations.get(self.departure.decoration).is_none_or(|p| p.kind != MapDecorationKind::M10ShipConfirmation)
            || self.passengers.len() != 4 || self.passengers.iter().zip(["berth_crew_a","berth_crew_b","edda","splice"]).any(|(p,id)| p.id != id || !point(p.feet)) {
            return Err("invalid M10 map geometry");
        }
        Ok(())
    }
}

impl MissionState {
    pub(super) fn validate_m10(&self) -> Result<(), &'static str> {
        let f = self.m10.as_ref().ok_or("M10 facts missing")?;
        f.transit.validate()?;
        if let Some(archive) = &f.carried_archive {
            archive.validate()?;
        }
        let order = |i: usize| {
            if i == M10_OBJECTIVE_IDS.len() {
                "party_departed"
            } else {
                M10_OBJECTIVE_IDS[i]
            }
        };
        let total = M10_OBJECTIVE_IDS.len() + 1;
        let point =
            |p: [f32; 3]| p.iter().all(|v| v.is_finite() && v.abs() <= 512.0) && p[1] >= 0.0;
        let expected: Vec<_> = ["berth_crew_a", "berth_crew_b", "edda", "splice"]
            .into_iter()
            .filter(|id| f.transit.arrived(id))
            .collect();
        if self.m02.is_some()
            || self.m03.is_some()
            || self.m04.is_some()
            || self.m05.is_some()
            || self.m06.is_some()
            || self.m07.is_some()
            || self.m08.is_some()
            || self.m09.is_some()
            || !matches!(
                self.phase,
                MissionPhase::Briefing | MissionPhase::InProgress | MissionPhase::Departed
            )
            || f.completed.len() > total
            || f.completed.iter().enumerate().any(|(i, id)| id != order(i))
            || (self.phase == MissionPhase::Departed) != (f.completed.len() == total)
            || f.current.is_some() != (f.completed.len() < total)
            || self.phase == MissionPhase::Briefing && !f.completed.is_empty()
            || !point(f.pilot)
            || f.passengers
                .iter()
                .map(|p| p.id.as_str())
                .collect::<Vec<_>>()
                != expected
            || f.passengers.iter().any(|p| !point(p.feet))
        {
            return Err("invalid M10 current ship and objective facts");
        }
        if let Some(current) = &f.current {
            let i = f.completed.len();
            if current.id != order(i)
                || !matches!(
                    (&current.action, i == M10_OBJECTIVE_IDS.len()),
                    (MissionObjectiveAction::Arrival { .. }, false)
                        | (MissionObjectiveAction::Use { .. }, true)
                )
            {
                return Err("invalid M10 current objective");
            }
            match &current.action {
                MissionObjectiveAction::Arrival { region, feet }
                    if !region.valid(512.0) || !point(*feet) || !region.contains(*feet) =>
                {
                    return Err("invalid M10 arrival")
                }
                MissionObjectiveAction::Use { target }
                    if !point(target.approach)
                        || target.decoration >= super::MAX_MAP_DECORATIONS =>
                {
                    return Err("invalid M10 confirmation")
                }
                _ => {}
            }
        }
        Ok(())
    }
}
