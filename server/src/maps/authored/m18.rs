//! All Systems Normal: validate the transit concourse and prepared worlds.
use super::{encounters::EncounterDefinition, identity, invalid, standing};
use crate::movement::{Arena, Solid, EYE_HEIGHT};
use crate::navigation::{Navigation, RouteStatus, SEARCH_LIMIT};
use crate::protocol::{
    M18MapGeometry, MapPresentation, MissionObjective, MissionObjectiveAction, Region3, UseTarget,
    M18_OBJECTIVE_IDS, USE_DISTANCE,
};
use serde::Deserialize;
use std::{
    collections::{HashMap, HashSet},
    io,
    sync::Arc,
};

pub(crate) const GROUPS: [&str; 5] = [
    "square_uprising",
    "collector_escort",
    "stair_ambush",
    "overlook_sentries",
    "concourse_defense",
];

#[derive(Debug, Deserialize)]
#[serde(tag = "kind", rename_all = "snake_case", deny_unknown_fields)]
enum ObjectiveDefinition {
    Arrival {
        id: String,
        arrival: Region3,
        approach: [f32; 3],
    },
    Use {
        id: String,
        target: UseTarget,
    },
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub(super) struct Definition {
    objectives: Vec<ObjectiveDefinition>,
    departure: UseTarget,
    boarding: Region3,
    depot_station: UseTarget,
    overlook_console: UseTarget,
    maint_gate: String,
    roadblock_rubble: String,
    departure_gate: String,
}

#[derive(Debug, Clone)]
pub(crate) struct Prepared {
    pub(crate) geometry: M18MapGeometry,
    pub(crate) maint_gate: usize,
    pub(crate) departure_gate: usize,
    pub(crate) initial: Arena,
    pub(crate) presentation: MapPresentation,
    pub(crate) ruptured: Arena,
    pub(crate) concluded: Arena,
    pub(crate) navigation: Arc<Navigation>,
    pub(crate) ruptured_navigation: Arc<Navigation>,
    pub(crate) concluded_navigation: Arc<Navigation>,
}

impl Definition {
    pub(super) fn prepare(
        self,
        arena: &Arena,
        definitions: &[EncounterDefinition],
        presentation: &MapPresentation,
        ids: &HashMap<String, usize>,
        start: [f32; 3],
        seen: &mut HashSet<String>,
    ) -> io::Result<Prepared> {
        use crate::protocol::EnemyKind::*;
        let roles: [&[crate::protocol::EnemyKind]; 5] = [
            &[Clerk, Clerk, Sweeper, Sweeper, Enforcer],
            &[HeavySweeper, Assessor, Auditor],
            &[Turret, Sweeper, Sweeper],
            &[Enforcer, Enforcer, Sweeper],
            &[HeavySweeper, HeavySweeper, Notary, Enforcer],
        ];
        if definitions.len() != 5
            || definitions.iter().enumerate().any(|(i, g)| {
                g.id != GROUPS[i]
                    || g.enemies.len() != roles[i].len()
                    || roles[i].iter().any(|kind| {
                        g.enemies.iter().filter(|e| e.kind == *kind).count()
                            != roles[i].iter().filter(|k| **k == *kind).count()
                    })
            })
        {
            return Err(invalid("M18 requires five exact encounter rosters"));
        }
        if self.objectives.len() != M18_OBJECTIVE_IDS.len() {
            return Err(invalid("M18 requires six ordered recovery objectives"));
        }
        let mut objectives = Vec::with_capacity(6);
        for (i, def) in self.objectives.into_iter().enumerate() {
            let expected_id = M18_OBJECTIVE_IDS[i];
            let obj = match def {
                ObjectiveDefinition::Arrival {
                    id,
                    arrival,
                    approach,
                } => {
                    if id != expected_id {
                        return Err(invalid("M18 objective id mismatch"));
                    }
                    identity(&id, seen)?;
                    MissionObjective {
                        id,
                        action: MissionObjectiveAction::Arrival {
                            region: arrival,
                            feet: approach,
                        },
                    }
                }
                ObjectiveDefinition::Use { id, target } => {
                    if id != expected_id {
                        return Err(invalid("M18 objective id mismatch"));
                    }
                    identity(&id, seen)?;
                    MissionObjective {
                        id,
                        action: MissionObjectiveAction::Use { target },
                    }
                }
            };
            objectives.push(obj);
        }

        let maint_gate = *ids
            .get(&self.maint_gate)
            .ok_or_else(|| invalid("M18 maint gate solid missing"))?;
        let roadblock_rubble = *ids
            .get(&self.roadblock_rubble)
            .ok_or_else(|| invalid("M18 roadblock rubble missing"))?;
        let departure_gate = *ids
            .get(&self.departure_gate)
            .ok_or_else(|| invalid("M18 departure gate solid missing"))?;

        let geometry = M18MapGeometry {
            objectives,
            departure: self.departure,
            boarding: self.boarding,
            depot_station: self.depot_station,
            overlook_console: self.overlook_console,
            roadblock_active: false,
            concourse_evac_completed: false,
        };
        geometry
            .validate(arena.half, &arena.solids, Some(presentation))
            .map_err(invalid)?;

        // Verify use targets are within reach
        for target in [
            &geometry.depot_station,
            &geometry.overlook_console,
            &geometry.departure,
        ] {
            let point = target
                .point(presentation, &arena.solids)
                .ok_or_else(|| invalid("M18 use target point missing"))?;
            let eye = [
                target.approach[0],
                target.approach[1] + EYE_HEIGHT,
                target.approach[2],
            ];
            let dx = point[0] - eye[0];
            let dy = point[1] - eye[1];
            let dz = point[2] - eye[2];
            let dist = (dx * dx + dy * dy + dz * dz).sqrt();
            if dist > USE_DISTANCE + 0.6 {
                return Err(invalid("M18 use target approach out of reach"));
            }
        }

        let navigation = Navigation::shared(arena.clone()).map_err(invalid)?;
        if !standing(arena, start)
            || navigation
                .route(start, geometry.depot_station.approach, SEARCH_LIMIT)
                .status
                != RouteStatus::Complete
        {
            return Err(invalid("M18 start cannot reach depot station"));
        }

        // Ruptured arena: maintenance gate opened (lowered)
        let mut ruptured = arena.clone();
        ruptured.solids[roadblock_rubble].top = 4.5;
        ruptured.solids[maint_gate] = Solid {
            min_x: -19.0,
            bottom: 0.0,
            min_z: 14.0,
            max_x: -17.0,
            top: 0.1,
            max_z: 18.0,
        };
        let ruptured_navigation = Navigation::shared(ruptured.clone()).map_err(invalid)?;
        if ruptured_navigation
            .route(start, geometry.overlook_console.approach, SEARCH_LIMIT)
            .status
            != RouteStatus::Complete
        {
            return Err(invalid("M18 ruptured arena cannot reach overlook console"));
        }

        // Concluded arena: departure gate opened
        let mut concluded = ruptured.clone();
        concluded.solids[departure_gate] = Solid {
            min_x: 60.0,
            bottom: 4.5,
            min_z: -4.0,
            max_x: 62.0,
            top: 4.6,
            max_z: 4.0,
        };
        let concluded_navigation = Navigation::shared(concluded.clone()).map_err(invalid)?;
        if concluded_navigation
            .route(
                geometry.overlook_console.approach,
                geometry.departure.approach,
                SEARCH_LIMIT,
            )
            .status
            != RouteStatus::Complete
        {
            return Err(invalid(
                "M18 concluded arena cannot reach departure approach",
            ));
        }

        Ok(Prepared {
            geometry,
            maint_gate,
            departure_gate,
            initial: arena.clone(),
            presentation: presentation.clone(),
            ruptured,
            concluded,
            navigation,
            ruptured_navigation,
            concluded_navigation,
        })
    }
}
