//! Still Here: validate the refuge in both worlds before readiness. The first
//! light and years later share one solid list; each world stows the solids
//! that belong only to the other outside the square, so indices never move.
use super::{identity, invalid, standing};
use crate::movement::{Arena, Solid, EYE_HEIGHT, RADIUS};
use crate::navigation::{Navigation, RouteStatus, SEARCH_LIMIT};
use crate::protocol::{
    EpilogueMapGeometry, EpiloguePerson, EpilogueStage, MapPresentation, Region3, UseTarget,
    USE_DISTANCE,
};
use serde::Deserialize;
use std::{
    collections::{HashMap, HashSet},
    io,
    sync::Arc,
};

/// People stand clear of the authored walks by at least this much, so a
/// participant or an agent walking them never has to push through anyone.
const WALK_CLEARANCE: f32 = 0.9;
/// Two people never stand closer than this.
const PERSON_SPACING: f32 = 0.62;
const MAX_WALK: usize = 16;
/// The refuge's name in the first light, and once the world has turned.
pub(crate) const NAME: &str = "Still Here";
pub(crate) const LATER_NAME: &str = "Still Here, years later";

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct Spawn {
    feet: [f32; 3],
    yaw: f32,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub(super) struct Definition {
    latch: UseTarget,
    arrival: Region3,
    arrival_feet: [f32; 3],
    departure: UseTarget,
    later_spawn: Spawn,
    ferry_board: usize,
    /// Solids standing only in the first light: rubble, the people's
    /// barricade, the stalled tram.
    aftermath_only: Vec<String>,
    /// Solids standing only years later: rebuilt walls, planters, the bench.
    later_only: Vec<String>,
    /// The walk from the gate to Latch's table in the first light.
    aftermath_walk: Vec<[f32; 3]>,
    /// The walk from the tram stop to the quay bench years later.
    later_walk: Vec<[f32; 3]>,
    people: Vec<EpiloguePerson>,
}

#[derive(Debug, Clone)]
pub(crate) struct Prepared {
    pub(crate) geometry: EpilogueMapGeometry,
    pub(crate) aftermath: Arena,
    pub(crate) aftermath_navigation: Arc<Navigation>,
    pub(crate) later: Arena,
    pub(crate) later_navigation: Arc<Navigation>,
}

/// Stow a world's absent solids beside the square, where nothing walks,
/// shoots or routes. Indices stay put, so every decoration keeps its host,
/// and no ghost lip is left on the court the way a flattened slab would.
fn stow(arena: &Arena, solids: &[usize]) -> io::Result<Arena> {
    let offset = arena.half * 2.0 + 16.0;
    let mut world = arena.clone();
    for &index in solids {
        let solid = world.solids[index];
        world.solids[index] = Solid {
            min_x: solid.min_x + offset,
            max_x: solid.max_x + offset,
            ..solid
        };
    }
    crate::movement::validate_geometry(world.half, &world.solids).map_err(invalid)?;
    Ok(world)
}

/// A world's solid that the other world stows.
#[cfg(test)]
pub(crate) fn stowed(arena: &Arena, index: usize) -> bool {
    arena
        .solids
        .get(index)
        .is_some_and(|solid| solid.min_x > arena.half)
}

fn segment_distance(point: [f32; 3], a: [f32; 3], b: [f32; 3]) -> f32 {
    let (dx, dz) = (b[0] - a[0], b[2] - a[2]);
    let length = dx * dx + dz * dz;
    let t = if length <= f32::EPSILON {
        0.0
    } else {
        (((point[0] - a[0]) * dx + (point[2] - a[2]) * dz) / length).clamp(0.0, 1.0)
    };
    (point[0] - (a[0] + dx * t)).hypot(point[2] - (a[2] + dz * t))
}

/// Furniture a person can sit or lie on: a low solid under or beside them,
/// or the body they sit inside, like a tram's cab.
fn on_furniture(arena: &Arena, feet: [f32; 3]) -> bool {
    let within = |solid: &Solid, margin: f32| {
        feet[0] >= solid.min_x - margin
            && feet[0] <= solid.max_x + margin
            && feet[2] >= solid.min_z - margin
            && feet[2] <= solid.max_z + margin
    };
    feet.iter().all(|v| v.is_finite())
        && arena.solids.iter().any(|solid| {
            (feet[1] - solid.bottom).abs() <= 0.05
                && ((0.3..=1.3).contains(&(solid.top - solid.bottom)) && within(solid, 0.6)
                    || within(solid, -0.2))
        })
}

fn reachable_use(arena: &Arena, presentation: &MapPresentation, target: &UseTarget) -> bool {
    let Some(point) = target.point(presentation, &arena.solids) else {
        return false;
    };
    let eye = [
        target.approach[0],
        target.approach[1] + EYE_HEIGHT,
        target.approach[2],
    ];
    (0..3)
        .map(|a| (point[a] - eye[a]).powi(2))
        .sum::<f32>()
        .sqrt()
        <= USE_DISTANCE - 0.2
        && standing(arena, target.approach)
        && crate::combat::line_of_sight(eye, point, &arena.solids)
}

impl Definition {
    pub(super) fn prepare(
        self,
        arena: &Arena,
        presentation: &MapPresentation,
        ids: &HashMap<String, usize>,
        start: [f32; 3],
        seen: &mut HashSet<String>,
    ) -> io::Result<Prepared> {
        let resolve = |names: &[String]| -> io::Result<Vec<usize>> {
            names
                .iter()
                .map(|name| {
                    ids.get(name)
                        .copied()
                        .ok_or_else(|| invalid("Still Here names an unknown solid"))
                })
                .collect()
        };
        let aftermath_only = resolve(&self.aftermath_only)?;
        let later_only = resolve(&self.later_only)?;
        let geometry = EpilogueMapGeometry {
            latch: self.latch,
            arrival: self.arrival,
            arrival_feet: self.arrival_feet,
            departure: self.departure,
            later_spawn: self.later_spawn.feet,
            later_yaw: self.later_spawn.yaw,
            ferry_board: self.ferry_board,
            people: self.people,
            aftermath_only: aftermath_only.clone(),
            later_only: later_only.clone(),
            later: false,
        };
        geometry
            .validate(arena.half, &arena.solids, Some(presentation))
            .map_err(invalid)?;
        for person in &geometry.people {
            // Stage-qualified names belong to the map's identifier space once.
            identity(
                &format!(
                    "{}_{}",
                    match person.stage {
                        EpilogueStage::Aftermath => "first",
                        EpilogueStage::Later => "later",
                    },
                    person.id
                ),
                seen,
            )?;
        }
        let first = stow(arena, &later_only)?;
        let later = stow(arena, &aftermath_only)?;
        if aftermath_only
            .iter()
            .chain(&later_only)
            .any(|index| arena.solids[*index].min_x > arena.half)
        {
            return Err(invalid("Still Here world solids stand inside the square"));
        }
        if !reachable_use(&first, presentation, &geometry.latch)
            || !reachable_use(&later, presentation, &geometry.departure)
        {
            return Err(invalid("Still Here use targets need reachable approaches"));
        }
        if !geometry
            .later_slots()
            .iter()
            .all(|feet| standing(&later, *feet) && !geometry.arrival.contains(*feet))
            || !standing(&later, geometry.arrival_feet)
        {
            return Err(invalid("Still Here later walk needs supported feet"));
        }
        let walk = |world: &Arena, points: &[[f32; 3]], from: [f32; 3], to: [f32; 3]| {
            (2..=MAX_WALK).contains(&points.len())
                && points[0] == from
                && points[points.len() - 1] == to
                && points
                    .windows(2)
                    .all(|pair| crate::mission::m09_route_segment_valid(world, pair[0], pair[1]))
        };
        if !walk(&first, &self.aftermath_walk, start, geometry.latch.approach)
            || !walk(
                &later,
                &self.later_walk,
                geometry.later_spawn,
                geometry.departure.approach,
            )
            || !self
                .later_walk
                .iter()
                .any(|point| geometry.arrival.contains(*point))
        {
            return Err(invalid(
                "Still Here walks must join each world's start to its use",
            ));
        }
        for stage in [EpilogueStage::Aftermath, EpilogueStage::Later] {
            let (world, path) = match stage {
                EpilogueStage::Aftermath => (&first, &self.aftermath_walk),
                EpilogueStage::Later => (&later, &self.later_walk),
            };
            let standing_here: Vec<&EpiloguePerson> = geometry
                .people
                .iter()
                .filter(|person| person.stage == stage)
                .collect();
            for (index, person) in standing_here.iter().enumerate() {
                let clear_of_walk = path.windows(2).all(|pair| {
                    segment_distance(person.feet, pair[0], pair[1]) >= WALK_CLEARANCE + RADIUS
                });
                // Someone who stands in for an absent rescue takes their place.
                let exclusive = |other: &EpiloguePerson| {
                    person.requires.is_some() && person.requires == other.unless
                        || person.unless.is_some() && person.unless == other.requires
                };
                let apart = standing_here[index + 1..].iter().all(|other| {
                    exclusive(other)
                        || (person.feet[0] - other.feet[0]).hypot(person.feet[2] - other.feet[2])
                            >= PERSON_SPACING
                });
                let clear_of_party = stage == EpilogueStage::Aftermath
                    || geometry.later_slots().iter().all(|slot| {
                        (person.feet[0] - slot[0]).hypot(person.feet[2] - slot[2])
                            >= PERSON_SPACING + RADIUS
                    });
                // On a bench, a crate or a cot: the furniture is the body.
                let placed = if person.pose.blocks() {
                    standing(world, person.feet)
                } else {
                    on_furniture(world, person.feet)
                };
                let problem = if !placed {
                    "needs supported, clear feet"
                } else if !clear_of_walk {
                    "stands on the walk"
                } else if !apart {
                    "stands inside another person"
                } else if !clear_of_party {
                    "stands where the party arrives"
                } else {
                    continue;
                };
                return Err(invalid(&format!(
                    "Still Here person {} {problem}",
                    person.id
                )));
            }
        }
        if !geometry
            .people
            .iter()
            .any(|person| person.id == "latch" && person.stage == EpilogueStage::Aftermath)
            || !geometry
                .people
                .iter()
                .any(|person| person.id == "latch" && person.stage == EpilogueStage::Later)
            || geometry
                .people
                .iter()
                .any(|person| person.id == "latch" && person.requires.is_some())
        {
            return Err(invalid("Latch is present in both worlds, whatever the run"));
        }
        let aftermath_navigation = Navigation::shared(first.clone()).map_err(invalid)?;
        let later_navigation = Navigation::shared(later.clone()).map_err(invalid)?;
        let route = |nav: &Navigation, from: [f32; 3], to: [f32; 3]| {
            nav.route(from, to, SEARCH_LIMIT).status == RouteStatus::Complete
        };
        if !route(&aftermath_navigation, start, geometry.latch.approach)
            || !route(
                &later_navigation,
                geometry.later_spawn,
                geometry.departure.approach,
            )
        {
            return Err(invalid("Still Here walks must also navigate"));
        }
        Ok(Prepared {
            geometry,
            aftermath: first,
            aftermath_navigation,
            later,
            later_navigation,
        })
    }
}
