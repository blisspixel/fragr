//! Common Carrier collision and objective bindings, prepared before readiness.
use super::{encounters::EncounterDefinition, identity, invalid, standing};
use crate::movement::{Arena, EYE_HEIGHT};
use crate::navigation::{Navigation, RouteStatus, SEARCH_LIMIT};
use crate::protocol::{
    EnemyKind, M10MapGeometry, M10PassengerGeometry, MapDecoration, MapPresentation,
    MissionObjective, MissionObjectiveAction, Region3, UseTarget, M10_OBJECTIVE_IDS, USE_DISTANCE,
};
use serde::Deserialize;
use std::{
    collections::{HashMap, HashSet},
    io,
    sync::Arc,
};

pub(crate) const GROUPS: [&str; 4] = [
    "forward_boarders",
    "service_crawlers",
    "aft_boarders",
    "passenger_defense",
];
pub(crate) const OBJECTIVES: [&str; 4] = M10_OBJECTIVE_IDS;

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub(super) struct Definition {
    objectives: Vec<Objective>,
    departure: Departure,
    pilot: [f32; 3],
    companion_start: [f32; 3],
    passengers: Vec<M10PassengerGeometry>,
}
#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct Objective {
    id: String,
    arrival: Region3,
    approach: [f32; 3],
    requires_encounter: String,
}
#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct Departure {
    panel: MapDecoration<String>,
    approach: [f32; 3],
    boarding: Region3,
    requires_encounter: String,
}
#[derive(Debug, Clone)]
pub(crate) struct Prepared {
    pub(crate) geometry: M10MapGeometry,
    pub(crate) navigation: Arc<Navigation>,
}

impl Definition {
    pub(super) fn prepare(
        self,
        arena: &Arena,
        ids: &HashMap<String, usize>,
        definitions: &[EncounterDefinition],
        presentation: &mut MapPresentation,
        start: [f32; 3],
        seen: &mut HashSet<String>,
    ) -> io::Result<Prepared> {
        let roles: [&[EnemyKind]; 4] = [
            &[
                EnemyKind::Clerk,
                EnemyKind::Clerk,
                EnemyKind::Sweeper,
                EnemyKind::Sweeper,
            ],
            &[
                EnemyKind::Crawler,
                EnemyKind::Crawler,
                EnemyKind::Crawler,
                EnemyKind::Clerk,
                EnemyKind::Sweeper,
            ],
            &[
                EnemyKind::HeavySweeper,
                EnemyKind::Sweeper,
                EnemyKind::Clerk,
                EnemyKind::Notary,
            ],
            &[
                EnemyKind::Clerk,
                EnemyKind::Clerk,
                EnemyKind::Sweeper,
                EnemyKind::Enforcer,
            ],
        ];
        if definitions.len() != GROUPS.len()
            || definitions.iter().enumerate().any(|(i, group)| {
                group.id != GROUPS[i]
                    || group.after.as_deref() != i.checked_sub(1).map(|p| GROUPS[p])
                    || group.enemies.len() != roles[i].len()
                    || roles[i].iter().any(|kind| {
                        group.enemies.iter().filter(|e| e.kind == *kind).count()
                            != roles[i].iter().filter(|r| **r == *kind).count()
                    })
            })
            || self.objectives.len() != OBJECTIVES.len()
            || self.departure.requires_encounter != GROUPS[3]
        {
            return Err(invalid("M10 requires its four ordered ship defense groups"));
        }
        let navigation = Navigation::shared(arena.clone()).map_err(invalid)?;
        let reachable = |feet| {
            standing(arena, feet)
                && navigation.route(start, feet, SEARCH_LIMIT).status == RouteStatus::Complete
        };
        let mut objectives = Vec::new();
        for (i, objective) in self.objectives.into_iter().enumerate() {
            identity(&objective.id, seen)?;
            if objective.id != OBJECTIVES[i]
                || objective.requires_encounter != GROUPS[i]
                || !objective.arrival.valid(arena.half)
                || !objective.arrival.contains(objective.approach)
                || !reachable(objective.approach)
            {
                return Err(invalid(
                    "M10 objective must bind its ordered group and reachable arrival",
                ));
            }
            objectives.push(MissionObjective {
                id: objective.id,
                action: MissionObjectiveAction::Arrival {
                    region: objective.arrival,
                    feet: objective.approach,
                },
            });
        }
        if !reachable(self.companion_start)
            || !reachable(self.pilot)
            || !reachable(self.departure.approach)
            || !self.departure.boarding.valid(arena.half)
            || !self.departure.boarding.contains(self.departure.approach)
            || self.passengers.len() != 4
            || self
                .passengers
                .iter()
                .zip(["berth_crew_a", "berth_crew_b", "edda", "splice"])
                .any(|(p, id)| p.id != id || !reachable(p.feet))
        {
            return Err(invalid(
                "M10 crew and confirmation require supported ship routes",
            ));
        }
        for passenger in &self.passengers {
            identity(&format!("m10_{}", passenger.id), seen)?;
        }
        let host = *ids
            .get(&self.departure.panel.solid)
            .ok_or_else(|| invalid("M10 confirmation host missing"))?;
        let target = UseTarget {
            decoration: presentation.decorations.len(),
            approach: self.departure.approach,
        };
        presentation
            .decorations
            .push(self.departure.panel.with_solid(host));
        let point = target
            .point(presentation, &arena.solids)
            .ok_or_else(|| invalid("M10 confirmation panel invalid"))?;
        let eye = [
            target.approach[0],
            target.approach[1] + EYE_HEIGHT,
            target.approach[2],
        ];
        if (0..3)
            .map(|i| (eye[i] - point[i]).powi(2))
            .sum::<f32>()
            .sqrt()
            > USE_DISTANCE
            || !crate::combat::line_of_sight(eye, point, &arena.solids)
        {
            return Err(invalid("M10 confirmation must be physically usable"));
        }
        let geometry = M10MapGeometry {
            objectives,
            departure: target,
            boarding: self.departure.boarding,
            pilot: self.pilot,
            companion_start: self.companion_start,
            passengers: self.passengers,
        };
        geometry
            .validate(arena.half, &arena.solids, Some(presentation))
            .map_err(invalid)?;
        Ok(Prepared {
            geometry,
            navigation,
        })
    }
}
