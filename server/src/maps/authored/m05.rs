//! One freight gate and a clear, bounded tram lane prepared before readiness.
use super::{encounters::EncounterDefinition, identity, invalid, standing};
use crate::movement::{Arena, EYE_HEIGHT};
use crate::navigation::{Navigation, RouteStatus, SEARCH_LIMIT};
use crate::protocol::{
    EnemyKind, M05MapGeometry, M05RescueGeometry, M05TramGeometry, MapDecoration, MapPresentation,
    MissionObjective, MissionObjectiveAction, Region3, UseTarget, M05_OBJECTIVE_IDS, USE_DISTANCE,
};
use serde::Deserialize;
use std::{
    collections::{HashMap, HashSet},
    io,
    sync::Arc,
};

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub(super) struct Definition {
    freight: Freight,
    rescue: Rescue,
    objectives: Vec<Objective>,
    departure: Departure,
    companion_start: [f32; 3],
    tram: Tram,
}
#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct Gate {
    solid: String,
    lift: f32,
}
#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct Freight {
    gate: Gate,
    requires_encounter: String,
}
#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct Rescue {
    requires_encounter: String,
    release: Region3,
    captives: Vec<crate::protocol::M05WorkerGeometry>,
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
#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct Tram {
    solid: String,
    start: [f32; 3],
    end: [f32; 3],
    speed: f32,
    activation: Region3,
}
#[derive(Debug, Clone)]
pub(crate) struct Prepared {
    pub(crate) geometry: M05MapGeometry,
    pub(crate) encounters: Vec<usize>,
    pub(crate) rescue_encounter: usize,
    pub(crate) departure_encounter: usize,
    pub(crate) opened: Arena,
    pub(crate) navigation: Arc<Navigation>,
    pub(crate) initial_navigation: Arc<Navigation>,
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
        if definitions.len() != 6
            || definitions.iter().enumerate().any(|(i, g)| {
                g.after.as_deref() != i.checked_sub(1).map(|p| definitions[p].id.as_str())
            })
            || definitions[4].enemies.len() != 1
            || definitions[4].enemies[0].kind != EnemyKind::HeavySweeper
            || definitions[..4]
                .iter()
                .flat_map(|g| &g.enemies)
                .any(|e| e.kind == EnemyKind::HeavySweeper)
            || definitions.iter().any(|g| {
                g.enemies
                    .iter()
                    .filter(|e| e.kind == EnemyKind::Notary)
                    .count()
                    > 2
            })
        {
            return Err(invalid(
                "M05 requires six ordered groups and an isolated Heavy introduction",
            ));
        }
        let encounter = |id: &str| {
            definitions
                .iter()
                .position(|g| g.id == id)
                .ok_or_else(|| invalid("M05 unknown encounter"))
        };
        let rescue_encounter = encounter(&self.rescue.requires_encounter)?;
        let departure_encounter = encounter(&self.departure.requires_encounter)?;
        if rescue_encounter != 2
            || departure_encounter != 5
            || encounter(&self.freight.requires_encounter)? != 5
        {
            return Err(invalid("M05 invalid rescue or freight group"));
        }
        let gate = *ids
            .get(&self.freight.gate.solid)
            .ok_or_else(|| invalid("M05 freight gate missing"))?;
        if !self.freight.gate.lift.is_finite() || !(2.0..=8.0).contains(&self.freight.gate.lift) {
            return Err(invalid("M05 gate lift invalid"));
        }
        let mut opened = arena.clone();
        opened.solids[gate].bottom += self.freight.gate.lift;
        opened.solids[gate].top += self.freight.gate.lift;
        crate::movement::validate_geometry(opened.half, &opened.solids).map_err(invalid)?;
        let tram_solid = *ids
            .get(&self.tram.solid)
            .ok_or_else(|| invalid("M05 tram body missing"))?;
        if tram_solid == gate {
            return Err(invalid("M05 tram cannot be freight gate"));
        }
        let tram = M05TramGeometry {
            solid: tram_solid,
            start: self.tram.start,
            end: self.tram.end,
            speed: self.tram.speed,
            activation: self.tram.activation,
        };
        let host = *ids
            .get(&self.departure.panel.solid)
            .ok_or_else(|| invalid("M05 departure host missing"))?;
        if host == gate || host == tram_solid {
            return Err(invalid("M05 departure control must be stationary"));
        }
        let decoration = presentation.decorations.len();
        presentation
            .decorations
            .push(self.departure.panel.with_solid(host));
        let departure = UseTarget {
            decoration,
            approach: self.departure.approach,
        };
        let mut encounters = Vec::new();
        let mut objectives = Vec::new();
        for (i, step) in self.objectives.into_iter().enumerate() {
            identity(&step.id, seen)?;
            if i >= 6
                || step.id != M05_OBJECTIVE_IDS[i]
                || encounter(&step.requires_encounter)? != i
            {
                return Err(invalid("M05 objective chain mismatch"));
            }
            encounters.push(i);
            objectives.push(MissionObjective {
                id: step.id,
                action: MissionObjectiveAction::Arrival {
                    region: step.arrival,
                    feet: step.approach,
                },
            });
        }
        let geometry = M05MapGeometry {
            freight_open: false,
            rescue: M05RescueGeometry {
                release: self.rescue.release,
                captives: self.rescue.captives,
            },
            objectives,
            departure,
            boarding: self.departure.boarding,
            companion_start: self.companion_start,
            tram,
        };
        geometry
            .validate(arena.half, &arena.solids, Some(presentation))
            .map_err(invalid)?;
        let body = arena.solids[tram_solid];
        let end = geometry.tram.body(body, geometry.tram.end);
        let swept = crate::movement::Solid {
            min_z: body.min_z.min(end.min_z),
            max_z: body.max_z.max(end.max_z),
            ..body
        };
        for world in [arena, &opened] {
            if world.solids.iter().enumerate().any(|(i, s)| {
                i != tram_solid
                    && s.min_x < swept.max_x + 0.5
                    && s.max_x > swept.min_x - 0.5
                    && s.min_z < swept.max_z + 0.5
                    && s.max_z > swept.min_z - 0.5
                    && s.bottom < swept.top + crate::movement::BODY_HEIGHT
                    && s.top > swept.bottom + 0.01
            }) {
                return Err(invalid(
                    "M05 tram swept lane must have clear body and rider headroom",
                ));
            }
        }
        let conservative = |world: &Arena| {
            let mut w = world.clone();
            // A lane reservation is forbidden walking space, not a continuous
            // phantom tram deck. Its top is above every authored surface and
            // ordinary jump; only this prepared planning world contains it.
            w.solids[tram_solid] = crate::movement::Solid {
                top: world.solids.iter().map(|s| s.top).fold(0.0_f32, f32::max)
                    + crate::movement::WALL_TOP,
                ..swept
            };
            Navigation::new(w).map(Arc::new).map_err(invalid)
        };
        let initial_navigation = conservative(arena)?;
        let navigation = conservative(&opened)?;
        for (world, nav) in [(arena, &initial_navigation), (&opened, &navigation)] {
            for feet in std::iter::once(geometry.companion_start)
                .chain(geometry.objectives.iter().filter_map(|s| match s.action {
                    MissionObjectiveAction::Arrival { feet, .. } => Some(feet),
                    _ => None,
                }))
                .chain(geometry.rescue.captives.iter().map(|c| c.held))
            {
                if !standing(world, feet)
                    || nav.route(start, feet, SEARCH_LIMIT).status != RouteStatus::Complete
                {
                    return Err(invalid("M05 required route must be supported outside tram lane in both freight worlds"));
                }
            }
            for g in definitions {
                for e in &g.enemies {
                    if let Some(hover) = &e.hover {
                        hover.validate(world, e.feet)?;
                    } else if !standing(world, e.feet)
                        || nav.route(start, e.feet, SEARCH_LIMIT).status != RouteStatus::Complete
                    {
                        return Err(invalid("M05 enemy unreachable beside tram lane"));
                    }
                }
            }
        }
        for c in &geometry.rescue.captives {
            identity(&c.id, seen)?;
            for feet in &c.route {
                if !standing(&opened, *feet)
                    || navigation.route(start, *feet, SEARCH_LIMIT).status != RouteStatus::Complete
                {
                    return Err(invalid(&format!(
                        "M05 captive {} route point {feet:?} unsupported or unreachable",
                        c.id
                    )));
                }
            }
            for p in c.route.windows(2) {
                if !navigation.walkable(p[0], p[1]) {
                    return Err(invalid(&format!(
                        "M05 captive {} segment {:?}->{:?} blocked",
                        c.id, p[0], p[1]
                    )));
                }
            }
            if !geometry.boarding.contains(
                *c.route
                    .last()
                    .ok_or_else(|| invalid("M05 captive route empty"))?,
            ) {
                return Err(invalid("M05 captive final point must be aboard"));
            }
            if !initial_navigation.walkable(c.route[0], c.route[1]) {
                return Err(invalid(
                    "M05 held-to-release route blocked before freight opens",
                ));
            }
        }
        let target = geometry
            .departure
            .point(presentation, &opened.solids)
            .ok_or_else(|| invalid("M05 departure control missing"))?;
        let approach = geometry.departure.approach;
        let eye = [approach[0], approach[1] + EYE_HEIGHT, approach[2]];
        if !standing(&opened, approach)
            || navigation.route(start, approach, SEARCH_LIMIT).status != RouteStatus::Complete
            || !geometry.boarding.contains(approach)
            || (0..3)
                .map(|i| (eye[i] - target[i]).powi(2))
                .sum::<f32>()
                .sqrt()
                > USE_DISTANCE
            || !crate::combat::line_of_sight(eye, target, &opened.solids)
        {
            return Err(invalid(
                "M05 ship approach must be reachable and see control",
            ));
        }
        Ok(Prepared {
            geometry,
            encounters,
            rescue_encounter,
            departure_encounter,
            opened,
            navigation,
            initial_navigation,
        })
    }
}
