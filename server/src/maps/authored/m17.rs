//! Peace Without Interruption: validate the Forever Office and its prepared worlds.
use super::{encounters::EncounterDefinition, identity, invalid, standing};
use crate::movement::{Arena, Solid, EYE_HEIGHT};
use crate::navigation::{Navigation, RouteStatus, SEARCH_LIMIT};
use crate::protocol::{
    M17MapGeometry, MapPresentation, MissionObjective, MissionObjectiveAction, Region3, UseTarget,
    M17_OBJECTIVE_IDS, USE_DISTANCE,
};
use serde::Deserialize;
use std::{
    collections::{HashMap, HashSet},
    io,
    sync::Arc,
};

pub(crate) const GROUPS: [&str; 6] = [
    "approach_watch",
    "hall_occupation",
    "ring_holding",
    "lane_defense",
    "gallery_watch",
    "core_defense",
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
    kessel_desk: UseTarget,
    core_override: UseTarget,
    voss_rostrum: UseTarget,
    core_seal: String,
    gallery_bulkhead: String,
    /// Where Latch stands with the party when the level begins.
    companion_start: [f32; 3],
}

#[derive(Debug, Clone)]
pub(crate) struct Prepared {
    pub(crate) geometry: M17MapGeometry,
    pub(crate) sealed: Arena,
    pub(crate) unsealed: Arena,
    pub(crate) concluded: Arena,
    pub(crate) navigation: Arc<Navigation>,
    pub(crate) unsealed_navigation: Arc<Navigation>,
    pub(crate) concluded_navigation: Arc<Navigation>,
    pub(crate) companion_start: [f32; 3],
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
            &[Clerk, Sweeper],
            &[Clerk, Clerk, Enforcer, Auditor],
            &[Sweeper, Sweeper, Enforcer],
            &[Turret, Turret, HeavySweeper],
            &[Clerk, Clerk, Enforcer],
            &[HeavySweeper, Assessor, Enforcer, Auditor],
        ];
        if definitions.len() != 6
            || definitions.iter().enumerate().any(|(i, g)| {
                g.id != GROUPS[i]
                    || g.enemies.len() != roles[i].len()
                    || roles[i].iter().any(|kind| {
                        g.enemies.iter().filter(|e| e.kind == *kind).count()
                            != roles[i].iter().filter(|k| **k == *kind).count()
                    })
            })
        {
            return Err(invalid("M17 requires six exact encounter rosters"));
        }
        if self.objectives.len() != M17_OBJECTIVE_IDS.len() {
            return Err(invalid(
                "M17 requires six ordered Forever Office objectives",
            ));
        }
        let mut objectives = Vec::with_capacity(6);
        for (i, def) in self.objectives.into_iter().enumerate() {
            let expected_id = M17_OBJECTIVE_IDS[i];
            let obj = match def {
                ObjectiveDefinition::Arrival {
                    id,
                    arrival,
                    approach,
                } => {
                    if id != expected_id {
                        return Err(invalid("M17 objective id mismatch"));
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
                        return Err(invalid("M17 objective id mismatch"));
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

        let core_seal = *ids
            .get(&self.core_seal)
            .ok_or_else(|| invalid("M17 core seal missing"))?;
        let gallery_bulkhead = *ids
            .get(&self.gallery_bulkhead)
            .ok_or_else(|| invalid("M17 gallery bulkhead missing"))?;

        let geometry = M17MapGeometry {
            objectives,
            departure: self.departure,
            boarding: self.boarding,
            kessel_desk: self.kessel_desk,
            core_override: self.core_override,
            voss_rostrum: self.voss_rostrum,
            core_unsealed: false,
            voss_captured: false,
        };
        geometry
            .validate(arena.half, &arena.solids, Some(presentation))
            .map_err(invalid)?;

        // Verify use points are reachable
        for target in [
            &geometry.kessel_desk,
            &geometry.core_override,
            &geometry.voss_rostrum,
            &geometry.departure,
        ] {
            let point = target
                .point(presentation, &arena.solids)
                .ok_or_else(|| invalid("M17 use target point missing"))?;
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
                return Err(invalid("M17 use target approach out of reach"));
            }
        }

        let navigation = Navigation::shared(arena.clone()).map_err(invalid)?;
        if !standing(arena, start)
            || navigation
                .route(start, geometry.kessel_desk.approach, SEARCH_LIMIT)
                .status
                != RouteStatus::Complete
        {
            return Err(invalid("M17 start cannot reach kessel desk"));
        }
        if !standing(arena, self.companion_start)
            || navigation
                .route(
                    self.companion_start,
                    geometry.kessel_desk.approach,
                    SEARCH_LIMIT,
                )
                .status
                != RouteStatus::Complete
        {
            return Err(invalid(
                "M17 Latch must start on the party's ordinary route",
            ));
        }
        // The override console stands on the raised north gallery: the party must
        // climb one of the ordinary stairs to reach it.
        if geometry.core_override.approach[1] < 2.5
            || !standing(arena, geometry.core_override.approach)
            || navigation
                .route(start, geometry.core_override.approach, SEARCH_LIMIT)
                .status
                != RouteStatus::Complete
        {
            return Err(invalid("M17 start cannot climb to the gallery console"));
        }

        // Unsealed arena (core override triggered): core seal lowered/opened
        let mut unsealed = arena.clone();
        unsealed.solids[core_seal] = Solid {
            min_x: -3.0,
            bottom: 0.0,
            min_z: 18.0,
            max_x: 3.0,
            top: 0.1,
            max_z: 20.0,
        };
        // The override also opens the gallery bulkhead: its threshold stays at
        // deck height and the outer court stair carries the party down to the
        // security core.
        let bulkhead = arena.solids[gallery_bulkhead];
        if (bulkhead.top - 7.0).abs() > f32::EPSILON || bulkhead.bottom != 0.0 {
            return Err(invalid("M17 gallery bulkhead must start closed"));
        }
        unsealed.solids[gallery_bulkhead] = Solid {
            top: geometry.core_override.approach[1],
            ..bulkhead
        };
        let unsealed_navigation = Navigation::shared(unsealed.clone()).map_err(invalid)?;
        if unsealed_navigation
            .route(
                geometry.core_override.approach,
                geometry.voss_rostrum.approach,
                SEARCH_LIMIT,
            )
            .status
            != RouteStatus::Complete
            || unsealed_navigation
                .route(start, geometry.voss_rostrum.approach, SEARCH_LIMIT)
                .status
                != RouteStatus::Complete
        {
            return Err(invalid("M17 unsealed arena cannot reach voss rostrum"));
        }

        // Concluded arena: exit route to departure
        let concluded = unsealed.clone();
        let concluded_navigation = Navigation::shared(concluded.clone()).map_err(invalid)?;
        if concluded_navigation
            .route(
                geometry.voss_rostrum.approach,
                geometry.departure.approach,
                SEARCH_LIMIT,
            )
            .status
            != RouteStatus::Complete
        {
            return Err(invalid(
                "M17 concluded arena cannot reach departure approach",
            ));
        }

        Ok(Prepared {
            companion_start: self.companion_start,
            geometry,
            sealed: arena.clone(),
            unsealed,
            concluded,
            navigation,
            unsealed_navigation,
            concluded_navigation,
        })
    }
}
