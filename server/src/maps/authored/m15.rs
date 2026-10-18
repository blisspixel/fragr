//! Civic Pressure Valve: validate the connected stadium bout and its three worlds.
use super::{encounters::EncounterDefinition, identity, invalid, standing};
use crate::movement::{Arena, Solid, EYE_HEIGHT};
use crate::navigation::{Navigation, RouteStatus, SEARCH_LIMIT};
use crate::protocol::{
    M15MapGeometry, MapPresentation, MissionObjective, MissionObjectiveAction, Region3, UseTarget,
    M15_OBJECTIVE_IDS, USE_DISTANCE,
};
use serde::Deserialize;
use std::{
    collections::{HashMap, HashSet},
    io,
    sync::Arc,
};

pub(crate) const GROUPS: [&str; 6] = [
    "pen_gate",
    "floor_lifts",
    "tunnel_wardens",
    "overhead_notaries",
    "booth_wardens",
    "last_wave",
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
    arming_crate: UseTarget,
    booth_terminal: UseTarget,
    tunnel_gate: String,
    gate_west_leaf: String,
    gate_east_leaf: String,
}

#[derive(Debug, Clone)]
pub(crate) struct Prepared {
    pub(crate) geometry: M15MapGeometry,
    pub(crate) tunnel_gate: usize,
    pub(crate) sealed: Arena,
    pub(crate) released: Arena,
    pub(crate) navigation: Arc<Navigation>,
    pub(crate) sealed_navigation: Arc<Navigation>,
    pub(crate) released_navigation: Arc<Navigation>,
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
        let roles: [&[crate::protocol::EnemyKind]; 6] = [
            &[Clerk, Clerk, Clerk],
            &[Sweeper, Sweeper, Sweeper],
            &[Clerk, Clerk, Enforcer],
            &[Notary, Notary],
            &[Clerk, Clerk, Auditor],
            &[HeavySweeper, Assessor, Enforcer, Enforcer],
        ];
        if definitions.len() != 6
            || definitions.iter().enumerate().any(|(i, g)| {
                g.id != GROUPS[i]
                    || g.after.as_deref() != i.checked_sub(1).map(|n| GROUPS[n])
                    || g.enemies.len() != roles[i].len()
                    || roles[i].iter().any(|kind| {
                        g.enemies.iter().filter(|e| e.kind == *kind).count()
                            != roles[i].iter().filter(|k| **k == *kind).count()
                    })
            })
        {
            return Err(invalid("M15 requires six exact ordered encounter rosters"));
        }
        if self.objectives.len() != M15_OBJECTIVE_IDS.len() {
            return Err(invalid("M15 requires six ordered bout objectives"));
        }
        let mut objectives = Vec::with_capacity(6);
        for (i, def) in self.objectives.into_iter().enumerate() {
            let expected_id = M15_OBJECTIVE_IDS[i];
            let obj = match def {
                ObjectiveDefinition::Arrival {
                    id,
                    arrival,
                    approach,
                } => {
                    if id != expected_id {
                        return Err(invalid("M15 objective id mismatch"));
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
                        return Err(invalid("M15 objective id mismatch"));
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

        let tunnel_gate = *ids
            .get(&self.tunnel_gate)
            .ok_or_else(|| invalid("M15 tunnel gate missing"))?;
        let gate_west_leaf = *ids
            .get(&self.gate_west_leaf)
            .ok_or_else(|| invalid("M15 west gate leaf missing"))?;
        let gate_east_leaf = *ids
            .get(&self.gate_east_leaf)
            .ok_or_else(|| invalid("M15 east gate leaf missing"))?;

        let geometry = M15MapGeometry {
            objectives,
            departure: self.departure,
            boarding: self.boarding,
            arming_crate: self.arming_crate,
            booth_terminal: self.booth_terminal,
            tunnel_closed: false,
            gates_open: false,
        };
        geometry
            .validate(arena.half, &arena.solids, Some(presentation))
            .map_err(invalid)?;

        // Verify use points are reachable and within distance
        for target in [
            &geometry.arming_crate,
            &geometry.booth_terminal,
            &geometry.departure,
        ] {
            let point = target
                .point(presentation, &arena.solids)
                .ok_or_else(|| invalid("M15 use target point missing"))?;
            let eye = [
                target.approach[0],
                target.approach[1] + EYE_HEIGHT,
                target.approach[2],
            ];
            let dx = point[0] - eye[0];
            let dy = point[1] - eye[1];
            let dz = point[2] - eye[2];
            let dist = (dx * dx + dy * dy + dz * dz).sqrt();
            if dist > USE_DISTANCE + 0.5 {
                return Err(invalid("M15 use target approach out of reach"));
            }
        }

        let navigation = Navigation::shared(arena.clone()).map_err(invalid)?;
        if !standing(arena, start)
            || navigation
                .route(start, geometry.arming_crate.approach, SEARCH_LIMIT)
                .status
                != RouteStatus::Complete
        {
            return Err(invalid("M15 entry cannot reach arming crate"));
        }

        // Sealed arena (stage 1): players' tunnel closed
        let mut sealed = arena.clone();
        sealed.solids[tunnel_gate] = Solid {
            min_x: -4.0,
            bottom: 0.0,
            min_z: -12.4,
            max_x: 4.0,
            top: 2.2,
            max_z: -11.6,
        };
        let sealed_navigation = Navigation::shared(sealed.clone()).map_err(invalid)?;
        let floor_center = [0.0, 0.0, 0.0];
        if sealed_navigation
            .route(floor_center, geometry.booth_terminal.approach, SEARCH_LIMIT)
            .status
            != RouteStatus::Complete
        {
            return Err(invalid("M15 sealed arena cannot reach broadcast booth"));
        }

        // Released arena (stage 2): north gates open
        let mut released = sealed.clone();
        released.solids[gate_west_leaf] = Solid {
            min_x: -4.0,
            bottom: 0.0,
            min_z: 16.2,
            max_x: -3.2,
            top: 2.0,
            max_z: 17.4,
        };
        released.solids[gate_east_leaf] = Solid {
            min_x: 3.2,
            bottom: 0.0,
            min_z: 16.2,
            max_x: 4.0,
            top: 2.0,
            max_z: 17.4,
        };
        let released_navigation = Navigation::shared(released.clone()).map_err(invalid)?;
        if released_navigation
            .route(floor_center, geometry.departure.approach, SEARCH_LIMIT)
            .status
            != RouteStatus::Complete
        {
            return Err(invalid("M15 released arena cannot reach departure"));
        }

        Ok(Prepared {
            geometry,
            tunnel_gate,
            sealed,
            released,
            navigation,
            sealed_navigation,
            released_navigation,
        })
    }
}
