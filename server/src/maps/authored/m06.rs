//! One static port world, ordered lessons and an independent service branch.
use super::{encounters::EncounterDefinition, identity, invalid, standing};
use crate::movement::{Arena, EYE_HEIGHT};
use crate::navigation::{Navigation, RouteStatus, SEARCH_LIMIT};
use crate::protocol::{
    EnemyKind, M06MapGeometry, MapDecoration, MapPresentation, MissionObjective,
    MissionObjectiveAction, Region3, UseTarget, M06_OBJECTIVE_IDS, M06_SERVICE_ID, USE_DISTANCE,
};
use serde::Deserialize;
use std::{
    collections::{HashMap, HashSet},
    io,
    sync::Arc,
};

pub(crate) const REQUIRED_GROUPS: [&str; 6] = [
    "freight_ingress",
    "rail_lane",
    "loading_heavy",
    "turret_intro",
    "customs_hold",
    "exit_watch",
];

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub(super) struct Definition {
    objectives: Vec<Objective>,
    service: Objective,
    departure: Departure,
    companion_start: [f32; 3],
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
    pub(crate) geometry: M06MapGeometry,
    pub(crate) encounters: [usize; 6],
    pub(crate) service_encounter: usize,
    pub(crate) departure_encounter: usize,
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
        if definitions.len() != 7
            || definitions.iter().take(6).enumerate().any(|(i, g)| {
                g.id != REQUIRED_GROUPS[i]
                    || g.after.as_deref() != i.checked_sub(1).map(|p| REQUIRED_GROUPS[p])
            })
            || definitions[6].id != "service_branch"
            || definitions[6].after.as_deref() != Some("loading_heavy")
            || definitions[1].enemies.len() != 1
            || definitions[1].enemies[0].kind != EnemyKind::Sweeper
            || definitions[2].enemies.len() != 1
            || definitions[2].enemies[0].kind != EnemyKind::HeavySweeper
            || definitions[3].enemies.len() != 1
            || definitions[3].enemies[0].kind != EnemyKind::Turret
            || definitions[5]
                .enemies
                .iter()
                .filter(|e| e.kind == EnemyKind::Turret)
                .count()
                != 1
            || definitions
                .iter()
                .flat_map(|g| &g.enemies)
                .filter(|e| e.kind == EnemyKind::Turret)
                .count()
                != 2
        {
            return Err(invalid("M06 requires six ordered groups, an independent service branch and isolated Rail/Turret lessons"));
        }
        if self.objectives.len() != 6
            || self.service.id != M06_SERVICE_ID
            || self.service.requires_encounter != "service_branch"
            || self.departure.requires_encounter != "exit_watch"
        {
            return Err(invalid("M06 objective or departure binding mismatch"));
        }
        let mut objectives = Vec::with_capacity(6);
        for (i, s) in self.objectives.into_iter().enumerate() {
            identity(&s.id, seen)?;
            if s.id != M06_OBJECTIVE_IDS[i] || s.requires_encounter != REQUIRED_GROUPS[i] {
                return Err(invalid("M06 objective chain mismatch"));
            }
            objectives.push(MissionObjective {
                id: s.id,
                action: MissionObjectiveAction::Arrival {
                    region: s.arrival,
                    feet: s.approach,
                },
            });
        }
        identity(&self.service.id, seen)?;
        let host = *ids
            .get(&self.departure.panel.solid)
            .ok_or_else(|| invalid("M06 departure host missing"))?;
        let decoration = presentation.decorations.len();
        presentation
            .decorations
            .push(self.departure.panel.with_solid(host));
        let geometry = M06MapGeometry {
            objectives,
            service: MissionObjective {
                id: self.service.id,
                action: MissionObjectiveAction::Arrival {
                    region: self.service.arrival,
                    feet: self.service.approach,
                },
            },
            departure: UseTarget {
                decoration,
                approach: self.departure.approach,
            },
            boarding: self.departure.boarding,
            companion_start: self.companion_start,
        };
        geometry
            .validate(arena.half, &arena.solids, Some(presentation))
            .map_err(invalid)?;
        let navigation = Navigation::shared(arena.clone()).map_err(invalid)?;
        for feet in geometry
            .objectives
            .iter()
            .chain(std::iter::once(&geometry.service))
            .filter_map(|s| {
                if let MissionObjectiveAction::Arrival { feet, .. } = &s.action {
                    Some(*feet)
                } else {
                    None
                }
            })
            .chain([geometry.departure.approach, geometry.companion_start])
        {
            if !standing(arena, feet)
                || navigation.route(start, feet, SEARCH_LIMIT).status != RouteStatus::Complete
            {
                return Err(invalid(&format!(
                    "M06 objective or companion feet {feet:?} unsupported or unreachable"
                )));
            }
        }
        let target = geometry
            .departure
            .point(presentation, &arena.solids)
            .ok_or_else(|| invalid("M06 departure control missing"))?;
        let approach = geometry.departure.approach;
        let eye = [approach[0], approach[1] + EYE_HEIGHT, approach[2]];
        let distance = (0..3)
            .map(|i| (eye[i] - target[i]).powi(2))
            .sum::<f32>()
            .sqrt();
        if distance <= 0.0
            || distance > USE_DISTANCE
            || !crate::combat::line_of_sight(eye, target, &arena.solids)
        {
            return Err(invalid(
                "M06 departure approach must see the reachable control",
            ));
        }
        Ok(Prepared {
            geometry,
            encounters: [0, 1, 2, 3, 4, 5],
            service_encounter: 6,
            departure_encounter: 5,
            navigation,
        })
    }
}
