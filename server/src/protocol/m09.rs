//! The launch berth's ordered fights, physical crew release and boarding hatch.
use super::{
    MapDecorationKind, MapPresentation, MissionObjective, MissionObjectiveAction, Region3,
    UseTarget,
};
use crate::movement::Solid;
use serde::{Deserialize, Serialize};

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
        Ok(())
    }
}
