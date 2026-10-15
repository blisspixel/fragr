//! Launch works: validate both conservative worlds and the original captured jeep.
use super::{
    encounters::EncounterDefinition, invalid, standing, vehicle_placements, walker, Placement,
};
use crate::movement::{Arena, Solid, EYE_HEIGHT};
use crate::navigation::{Navigation, RouteStatus, SEARCH_LIMIT};
use crate::protocol::{
    M12AidVehicle, M14MapGeometry, MapPresentation, MissionObjective, MissionObjectiveAction,
    Region3, UseTarget, M14_OBJECTIVE_IDS, USE_DISTANCE,
};
use serde::Deserialize;
use std::{collections::HashSet, io, sync::Arc};

pub(crate) const GROUPS: [&str; 6] = [
    "depot_defense",
    "parked_notary_lesson",
    "berm_watch",
    "pad_support",
    "gantry_support",
    "gantry_defense",
];
#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub(super) struct Definition {
    objectives: Vec<Objective>,
    departure: UseTarget,
    boarding: Region3,
    jeep: Placement,
    fallen: [Volume; 5],
}
#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct Objective {
    id: String,
    arrival: Region3,
    approach: [f32; 3],
}
#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct Volume {
    min: [f32; 3],
    max: [f32; 3],
}
#[derive(Debug, Clone)]
pub(crate) struct Prepared {
    pub(crate) geometry: M14MapGeometry,
    pub(crate) navigation: Arc<Navigation>,
    pub(crate) fallen_navigation: Arc<Navigation>,
    pub(crate) fallen: [Solid; 5],
    pub(crate) origin: [f32; 3],
}
impl Definition {
    pub(super) fn prepare(
        self,
        arena: &Arena,
        walker: &walker::Prepared,
        definitions: &[EncounterDefinition],
        presentation: &MapPresentation,
        start: [f32; 3],
        seen: &mut HashSet<String>,
    ) -> io::Result<Prepared> {
        use crate::protocol::EnemyKind::*;
        let roles: [&[crate::protocol::EnemyKind]; 6] = [
            &[Clerk, Clerk, Sweeper, Sweeper, Turret],
            &[Notary, Notary],
            &[Clerk, Clerk, RangedSweeper, Turret],
            &[Sweeper, Sweeper, Notary, Notary],
            &[Enforcer, Enforcer],
            &[Clerk, Clerk, HeavySweeper, Sweeper, Sweeper],
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
            return Err(invalid("M14 requires six exact ordered encounter rosters"));
        }
        vehicle_placements::validate(std::slice::from_ref(&self.jeep), arena, seen)?;
        let fallen = self.fallen.map(|v| Solid {
            min_x: v.min[0],
            bottom: v.min[1],
            min_z: v.min[2],
            max_x: v.max[0],
            top: v.max[1],
            max_z: v.max[2],
        });
        let torso = arena.solids[walker.geometry.solids[0]];
        let origin = walker.geometry.stations[0];
        if ((torso.min_x + torso.max_x) * 0.5 - origin[0]).abs() > 0.0001
            || ((torso.min_z + torso.max_z) * 0.5 - origin[2]).abs() > 0.0001
            || fallen
                .iter()
                .zip(crate::protocol::M14_FALLEN_PARTS)
                .any(|(s, part)| {
                    [s.min_x, s.bottom, s.min_z, s.max_x, s.top, s.max_z]
                        .iter()
                        .enumerate()
                        .any(|(i, v)| (*v - (part[i] + origin[i % 3])).abs() > 0.0001)
                })
        {
            return Err(invalid(
                "M14 requires the centered Walker and its registered folded parts",
            ));
        }
        crate::movement::validate_geometry(arena.half, &fallen).map_err(invalid)?;
        if fallen.iter().any(|s| s.bottom != 0.0 || s.top > 2.0) {
            return Err(invalid("M14 fallen machine must be grounded low cover"));
        }
        let mut conservative = walker.navigation.planning_arena().clone();
        let mut fallen_sweep = arena.clone();
        for (slot, &index) in walker.geometry.solids.iter().enumerate() {
            let mut sweep = fallen[slot];
            for station in walker.geometry.stations {
                let s = walker.geometry.translated(fallen[slot], station);
                if !walker.geometry.arena.contains([s.min_x, s.bottom, s.min_z])
                    || !walker.geometry.arena.contains([s.max_x, s.top, s.max_z])
                {
                    return Err(invalid("M14 fallen machine leaves battle arena"));
                }
                sweep.min_x = sweep.min_x.min(s.min_x);
                sweep.max_x = sweep.max_x.max(s.max_x);
                sweep.min_z = sweep.min_z.min(s.min_z);
                sweep.max_z = sweep.max_z.max(s.max_z);
            }
            if arena
                .solids
                .iter()
                .enumerate()
                .any(|(i, s)| !walker.geometry.solids.contains(&i) && walker::overlaps(sweep, *s))
            {
                return Err(invalid("M14 fallen sweep intersects static cover"));
            }
            fallen_sweep.solids[index] = sweep;
            let s = &mut conservative.solids[index];
            s.min_x = s.min_x.min(sweep.min_x);
            s.max_x = s.max_x.max(sweep.max_x);
            s.min_z = s.min_z.min(sweep.min_z);
            s.max_z = s.max_z.max(sweep.max_z);
        }
        let navigation = vehicle_placements::boarding_navigation(
            std::slice::from_ref(&self.jeep),
            &conservative,
            start,
            definitions,
        )?
        .ok_or_else(|| invalid("M14 captured jeep route missing"))?;
        let fallen_navigation = vehicle_placements::boarding_navigation(
            std::slice::from_ref(&self.jeep),
            &fallen_sweep,
            start,
            definitions,
        )?
        .ok_or_else(|| invalid("M14 fallen jeep route missing"))?;
        let objectives = self
            .objectives
            .into_iter()
            .map(|o| MissionObjective {
                id: o.id,
                action: MissionObjectiveAction::Arrival {
                    region: o.arrival,
                    feet: o.approach,
                },
            })
            .collect();
        let geometry = M14MapGeometry {
            objectives,
            departure: self.departure,
            boarding: self.boarding,
            jeep: M12AidVehicle {
                feet: self.jeep.feet,
                yaw: self.jeep.yaw,
            },
            walker_solids: walker.geometry.solids,
            fallen: false,
        };
        geometry
            .validate(arena.half, &arena.solids, Some(presentation))
            .map_err(invalid)?;
        for (objective, id) in geometry.objectives.iter().zip(M14_OBJECTIVE_IDS) {
            super::identity(id, seen)?;
            if let MissionObjectiveAction::Arrival { feet, .. } = objective.action {
                if !standing(arena, feet)
                    || [&navigation, &fallen_navigation].iter().any(|nav| {
                        nav.route(start, feet, SEARCH_LIMIT).status != RouteStatus::Complete
                    })
                {
                    return Err(invalid(&format!(
                        "M14 objective {id} requires both-world infantry access"
                    )));
                }
            }
        }
        let eye = [
            geometry.departure.approach[0],
            geometry.departure.approach[1] + EYE_HEIGHT,
            geometry.departure.approach[2],
        ];
        let point = geometry
            .departure
            .point(presentation, &arena.solids)
            .ok_or_else(|| invalid("M14 gantry terminal missing"))?;
        if !standing(arena, geometry.departure.approach)
            || (0..3)
                .map(|i| (eye[i] - point[i]).powi(2))
                .sum::<f32>()
                .sqrt()
                > USE_DISTANCE
            || !crate::combat::line_of_sight(eye, point, &arena.solids)
        {
            return Err(invalid("M14 gantry control requires supported visible Use"));
        }
        Ok(Prepared {
            geometry,
            navigation,
            fallen_navigation,
            fallen,
            origin: walker.geometry.stations[0],
        })
    }
}
