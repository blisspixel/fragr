//! One launch berth with both boarding-hatch worlds prepared before readiness.
use super::{encounters::EncounterDefinition, identity, invalid, standing};
use crate::movement::{Arena, Solid, EYE_HEIGHT};
use crate::navigation::{Navigation, RouteStatus, SEARCH_LIMIT};
use crate::protocol::{
    EnemyKind, M09CrewGeometry, M09MapGeometry, MapDecoration, MapPresentation, MissionObjective,
    MissionObjectiveAction, Region3, UseTarget, M09_CREW_STEP, M09_OBJECTIVE_IDS, USE_DISTANCE,
};
use serde::Deserialize;
use std::{
    collections::{HashMap, HashSet},
    io,
    sync::Arc,
};

pub(crate) const REQUIRED_GROUPS: [&str; 8] = [
    "lower_loading",
    "office_lesson",
    "berth_office",
    "gantry_one",
    "gantry_two",
    "gantry_three",
    "upper_counter",
    "boarding_watch",
];
pub(crate) const LESSON_GROUP: usize = 1;

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub(super) struct Definition {
    objectives: Vec<Objective>,
    crew_release: Control,
    crew: Vec<M09CrewGeometry>,
    departure: Departure,
    hatch: Moved,
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
struct Control {
    panel: MapDecoration<String>,
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
#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct Bounds {
    min: [f32; 3],
    max: [f32; 3],
}
#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct Moved {
    solid: String,
    open: Bounds,
}

#[derive(Debug, Clone)]
pub(crate) struct Prepared {
    pub(crate) geometry: M09MapGeometry,
    pub(crate) encounters: [usize; 8],
    pub(crate) opened: Arena,
    pub(crate) navigation: Arc<Navigation>,
    pub(crate) opened_navigation: Arc<Navigation>,
}

fn count(group: &EncounterDefinition, role: EnemyKind) -> usize {
    group.enemies.iter().filter(|e| e.kind == role).count()
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
        if definitions.len() != 8
            || definitions.iter().enumerate().any(|(i, g)| {
                g.id != REQUIRED_GROUPS[i]
                    || g.after.as_deref() != i.checked_sub(1).map(|p| REQUIRED_GROUPS[p])
            })
            || definitions[LESSON_GROUP].enemies.len() != 1
            || count(&definitions[LESSON_GROUP], EnemyKind::Enforcer) != 1
            || count(&definitions[0], EnemyKind::Clerk) != 2
            || count(&definitions[0], EnemyKind::Sweeper) != 2
            || count(&definitions[0], EnemyKind::Turret) != 1
            || definitions[0].enemies.len() != 5
            || definitions[2].enemies.len() != 2
            || count(&definitions[2], EnemyKind::Clerk) != 2
            || (3..=5).any(|i| {
                count(&definitions[i], EnemyKind::Enforcer) != 1
                    || count(&definitions[i], EnemyKind::Sweeper) != 1
                    || definitions[i].enemies.len() != if i == 3 { 2 } else { 3 }
                    || i > 3 && count(&definitions[i], EnemyKind::Notary) != 1
            })
            || definitions[6].enemies.len() != 4
            || count(&definitions[6], EnemyKind::Enforcer) != 2
            || count(&definitions[6], EnemyKind::Clerk) != 2
            || definitions[7].enemies.len() != 1
            || count(&definitions[7], EnemyKind::Enforcer) != 1
        {
            return Err(invalid(
                "M09 requires the isolated Enforcer lesson and eight ordered berth groups",
            ));
        }
        if self.objectives.len() != 7
            || self.crew_release.requires_encounter != REQUIRED_GROUPS[2]
            || self.departure.requires_encounter != REQUIRED_GROUPS[7]
        {
            return Err(invalid("M09 controls or objective bindings disagree"));
        }
        let hatch = *ids
            .get(&self.hatch.solid)
            .ok_or_else(|| invalid("M09 hatch missing"))?;
        let mut opened = arena.clone();
        let b = self.hatch.open;
        opened.solids[hatch] = Solid {
            min_x: b.min[0],
            bottom: b.min[1],
            min_z: b.min[2],
            max_x: b.max[0],
            top: b.max[1],
            max_z: b.max[2],
        };
        crate::movement::validate_geometry(opened.half, &opened.solids).map_err(invalid)?;
        if opened.solids[hatch] == arena.solids[hatch] {
            return Err(invalid("M09 hatch must move in the opened world"));
        }
        let ordered = (0..8).filter(|i| *i != M09_CREW_STEP);
        let mut objectives = Vec::with_capacity(7);
        for (s, i) in self.objectives.into_iter().zip(ordered) {
            identity(&s.id, seen)?;
            if s.id != M09_OBJECTIVE_IDS[i] || s.requires_encounter != REQUIRED_GROUPS[i] {
                return Err(invalid("M09 arrival chain mismatch"));
            }
            objectives.push(MissionObjective {
                id: s.id,
                action: MissionObjectiveAction::Arrival {
                    region: s.arrival,
                    feet: s.approach,
                },
            });
        }
        let mut control =
            |panel: MapDecoration<String>, approach: [f32; 3]| -> io::Result<UseTarget> {
                let host = *ids
                    .get(&panel.solid)
                    .ok_or_else(|| invalid("M09 control host missing"))?;
                let decoration = presentation.decorations.len();
                presentation.decorations.push(panel.with_solid(host));
                Ok(UseTarget {
                    decoration,
                    approach,
                })
            };
        let crew_release = control(self.crew_release.panel, self.crew_release.approach)?;
        let departure = control(self.departure.panel, self.departure.approach)?;
        let geometry = M09MapGeometry {
            objectives,
            crew_release,
            crew: self.crew,
            departure,
            boarding: self.departure.boarding,
            companion_start: self.companion_start,
            hatch,
            hatch_open: false,
        };
        for (world, hatch_open) in [(arena, false), (&opened, true)] {
            crate::protocol::validate_decorations(&presentation.decorations, &world.solids)
                .map_err(invalid)?;
            let mut world_geometry = geometry.clone();
            world_geometry.hatch_open = hatch_open;
            world_geometry
                .validate(arena.half, &world.solids, Some(presentation))
                .map_err(invalid)?;
        }
        let navigation = Navigation::shared(arena.clone()).map_err(invalid)?;
        let opened_navigation = Navigation::shared(opened.clone()).map_err(invalid)?;
        for (i, s) in geometry.objectives.iter().enumerate() {
            let MissionObjectiveAction::Arrival { feet, .. } = s.action else {
                return Err(invalid("M09 requires supported arrivals"));
            };
            // Every fight occurs outside the hatch; no future fight needs boarding.
            let supported = standing(arena, feet);
            let route = navigation.route(start, feet, SEARCH_LIMIT);
            if !supported || route.status != RouteStatus::Complete {
                return Err(invalid(&format!(
                    "M09 arrival {i} supported={supported}, route={:?}, expanded={}",
                    route.status, route.expanded
                )));
            }
        }
        for feet in [geometry.companion_start, geometry.crew_release.approach] {
            if !standing(arena, feet)
                || navigation.route(start, feet, SEARCH_LIMIT).status != RouteStatus::Complete
            {
                return Err(invalid("M09 initial route unreachable"));
            }
        }
        if !standing(&opened, geometry.departure.approach)
            || opened_navigation
                .route(start, geometry.departure.approach, SEARCH_LIMIT)
                .status
                != RouteStatus::Complete
            || navigation
                .route(start, geometry.departure.approach, SEARCH_LIMIT)
                .status
                == RouteStatus::Complete
        {
            return Err(invalid(
                "M09 boarding must be reachable only through the opened hatch",
            ));
        }
        for (target, world) in [
            (&geometry.crew_release, arena),
            (&geometry.departure, &opened),
        ] {
            let point = target
                .point(presentation, &world.solids)
                .ok_or_else(|| invalid("M09 control missing"))?;
            let p = target.approach;
            let eye = [p[0], p[1] + EYE_HEIGHT, p[2]];
            let distance = (0..3)
                .map(|i| (eye[i] - point[i]).powi(2))
                .sum::<f32>()
                .sqrt();
            if distance <= 0.0
                || distance > USE_DISTANCE
                || !crate::combat::line_of_sight(eye, point, &world.solids)
            {
                return Err(invalid("M09 approach must see the reachable control"));
            }
        }
        for crew in &geometry.crew {
            for (index, (feet, held)) in crew.route.iter().zip(&crew.held_until).enumerate() {
                let (world, nav) = if *held < 7 {
                    (arena, &navigation)
                } else {
                    (&opened, &opened_navigation)
                };
                let supported = standing(world, *feet);
                let route = nav.route(start, *feet, SEARCH_LIMIT);
                if !supported || route.status != RouteStatus::Complete {
                    return Err(invalid(&format!(
                        "M09 crew {} route {index} supported={supported}, route={:?}",
                        crew.id, route.status
                    )));
                }
            }
            // Route followers use actual shared movement. A direct segment
            // cannot cross a wall or depend on teleporting between waypoints.
            for (index, points) in crew.route.windows(2).enumerate() {
                if !crate::mission::m09_route_segment_valid(&opened, points[0], points[1]) {
                    return Err(invalid(&format!(
                        "M09 crew {} route segment {index} obstructed",
                        crew.id
                    )));
                }
            }
        }
        Ok(Prepared {
            geometry,
            encounters: [0, 1, 2, 3, 4, 5, 6, 7],
            opened,
            navigation,
            opened_navigation,
        })
    }
}
