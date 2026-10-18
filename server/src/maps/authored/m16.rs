//! Freedom of Movement: validate the connected ceremonial avenue and its prepared worlds.
use super::{encounters::EncounterDefinition, identity, invalid, standing};
use crate::movement::{Arena, Solid, EYE_HEIGHT};
use crate::navigation::{Navigation, RouteStatus, SEARCH_LIMIT};
use crate::protocol::{
    M16MapGeometry, MapPresentation, MissionObjective, MissionObjectiveAction, Region3, UseTarget,
    M16_OBJECTIVE_IDS, USE_DISTANCE,
};
use serde::Deserialize;
use std::{
    collections::{HashMap, HashSet},
    io,
    sync::Arc,
};

pub(crate) const GROUPS: [&str; 5] = [
    "first_stretch",
    "barricade_post",
    "checkpoint_stand",
    "transit_stop",
    "forecourt_assault",
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
    bus_release: UseTarget,
    motorcycle: super::Placement,
    checkpoint_barrier: String,
    chamber_doors: String,
}

#[derive(Debug, Clone)]
pub(crate) struct Prepared {
    pub(crate) geometry: M16MapGeometry,
    pub(crate) checkpoint_barrier: usize,
    pub(crate) chamber_doors: usize,
    pub(crate) initial: Arena,
    pub(crate) presentation: MapPresentation,
    pub(crate) lifted: Arena,
    pub(crate) open: Arena,
    pub(crate) navigation: Arc<Navigation>,
    pub(crate) lifted_navigation: Arc<Navigation>,
    pub(crate) open_navigation: Arc<Navigation>,
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
            &[Notary],
            &[Clerk, Clerk],
            &[Turret, Clerk],
            &[Clerk, Clerk],
            &[Enforcer, Enforcer, Turret, HeavySweeper, Assessor],
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
            return Err(invalid("M16 requires five exact encounter rosters"));
        }
        if self.objectives.len() != M16_OBJECTIVE_IDS.len() {
            return Err(invalid("M16 requires six ordered avenue objectives"));
        }
        let mut objectives = Vec::with_capacity(6);
        for (i, def) in self.objectives.into_iter().enumerate() {
            let expected_id = M16_OBJECTIVE_IDS[i];
            let obj = match def {
                ObjectiveDefinition::Arrival {
                    id,
                    arrival,
                    approach,
                } => {
                    if id != expected_id {
                        return Err(invalid("M16 objective id mismatch"));
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
                        return Err(invalid("M16 objective id mismatch"));
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

        let checkpoint_barrier = *ids
            .get(&self.checkpoint_barrier)
            .ok_or_else(|| invalid("M16 checkpoint barrier missing"))?;
        let chamber_doors = *ids
            .get(&self.chamber_doors)
            .ok_or_else(|| invalid("M16 chamber doors missing"))?;

        let geometry = M16MapGeometry {
            objectives,
            departure: self.departure,
            boarding: self.boarding,
            bus_release: self.bus_release,
            motorcycle: crate::protocol::M16Motorcycle {
                feet: self.motorcycle.feet,
                yaw: self.motorcycle.yaw,
            },
            checkpoint_lifted: false,
            doors_open: false,
        };
        geometry
            .validate(arena.half, &arena.solids, Some(presentation))
            .map_err(invalid)?;

        // Verify use points are reachable
        for target in [&geometry.bus_release, &geometry.departure] {
            let point = target
                .point(presentation, &arena.solids)
                .ok_or_else(|| invalid("M16 use target point missing"))?;
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
                return Err(invalid("M16 use target approach out of reach"));
            }
        }

        let navigation = Navigation::shared(arena.clone()).map_err(invalid)?;
        if !standing(arena, start)
            || navigation
                .route(start, geometry.bus_release.approach, SEARCH_LIMIT)
                .status
                != RouteStatus::Complete
        {
            return Err(invalid("M16 start cannot reach transit bus"));
        }

        // Lifted arena (Green Wave active): checkpoint barrier lowered/lifted
        let mut lifted = arena.clone();
        lifted.solids[checkpoint_barrier] = Solid {
            min_x: 9.4,
            bottom: 0.0,
            min_z: -1.6,
            max_x: 10.8,
            top: 0.1,
            max_z: 1.6,
        };
        let lifted_navigation = Navigation::shared(lifted.clone()).map_err(invalid)?;
        let forecourt_pt = [26.5, 0.0, 0.0];
        if lifted_navigation
            .route(start, forecourt_pt, SEARCH_LIMIT)
            .status
            != RouteStatus::Complete
        {
            return Err(invalid("M16 lifted arena cannot reach forecourt"));
        }

        // Open arena (doors reached/opened): chamber doors open
        let mut open = lifted.clone();
        open.solids[chamber_doors] = Solid {
            min_x: 38.0,
            bottom: 0.0,
            min_z: -1.6,
            max_x: 40.0,
            top: 0.1,
            max_z: 1.6,
        };
        let open_navigation = Navigation::shared(open.clone()).map_err(invalid)?;
        if open_navigation
            .route(forecourt_pt, geometry.departure.approach, SEARCH_LIMIT)
            .status
            != RouteStatus::Complete
        {
            return Err(invalid("M16 open arena cannot reach departure approach"));
        }

        Ok(Prepared {
            geometry,
            checkpoint_barrier,
            chamber_doors,
            initial: arena.clone(),
            presentation: presentation.clone(),
            lifted,
            open,
            navigation,
            lifted_navigation,
            open_navigation,
        })
    }
}
