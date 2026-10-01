//! Two bounded, precomputed worlds for Scheduled Service.
use super::{encounters::EncounterDefinition, identity, invalid, standing};
use crate::movement::{Arena, Solid, EYE_HEIGHT};
use crate::navigation::{Navigation, RouteStatus, SEARCH_LIMIT};
use crate::protocol::{
    M03CarGeometry, M03MapGeometry, M03MastGeometry, MapDecoration, MapDecorationKind,
    MapPresentation, Region3, UseTarget, USE_DISTANCE,
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
    mast: Mast,
    departure: Departure,
    companion_start: [f32; 3],
    cars: Vec<Car>,
}
#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct Mast {
    solid: String,
    approach: [f32; 3],
    aim: [f32; 3],
    requires_encounter: String,
    fallen: Vec<Fallen>,
}
#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct Fallen {
    solid: String,
    min: [f32; 3],
    max: [f32; 3],
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
struct Car {
    id: String,
    requires_encounter: String,
    release: Region3,
    held: [[f32; 3]; 2],
    safe: [[f32; 3]; 2],
}
#[derive(Debug, Clone)]
pub(crate) struct Prepared {
    pub(crate) geometry: M03MapGeometry,
    pub(crate) mast_encounter: usize,
    pub(crate) departure_encounter: usize,
    pub(crate) car_encounters: Vec<usize>,
    pub(crate) fallen: Arena,
    pub(crate) navigation: Arc<Navigation>,
    pub(crate) initial_navigation: Arc<Navigation>,
}
impl Definition {
    pub(super) fn prepare(
        self,
        arena: &Arena,
        ids: &HashMap<String, usize>,
        encounters: &[EncounterDefinition],
        presentation: &mut MapPresentation,
        start: [f32; 3],
        seen: &mut HashSet<String>,
    ) -> io::Result<Prepared> {
        let encounter = |id: &str| {
            encounters
                .iter()
                .position(|e| e.id == id)
                .ok_or_else(|| invalid("M03 references an unknown encounter"))
        };
        let mast_encounter = encounter(&self.mast.requires_encounter)?;
        let departure_encounter = encounter(&self.departure.requires_encounter)?;
        if mast_encounter == departure_encounter
            || self.mast.fallen.is_empty()
            || self.mast.fallen.len() > 4
        {
            return Err(invalid(
                "M03 requires distinct defender groups and bounded fallen solids",
            ));
        }
        let pod = *ids
            .get(&self.mast.solid)
            .ok_or_else(|| invalid("M03 mast pod is missing"))?;
        let mut fallen = arena.clone();
        let mut changed = HashSet::new();
        for replacement in self.mast.fallen {
            let index = *ids
                .get(&replacement.solid)
                .ok_or_else(|| invalid("M03 fallen solid is missing"))?;
            if !changed.insert(index) {
                return Err(invalid("M03 repeats a fallen solid"));
            }
            fallen.solids[index] = Solid {
                min_x: replacement.min[0],
                bottom: replacement.min[1],
                min_z: replacement.min[2],
                max_x: replacement.max[0],
                top: replacement.max[1],
                max_z: replacement.max[2],
            };
        }
        if !changed.contains(&pod) || fallen.solids[pod] == arena.solids[pod] {
            return Err(invalid("M03 mast pod must fall"));
        }
        crate::movement::validate_geometry(fallen.half, &fallen.solids).map_err(invalid)?;
        let host = *ids
            .get(&self.departure.panel.solid)
            .ok_or_else(|| invalid("M03 departure host is missing"))?;
        if changed.contains(&host)
            || !matches!(
                self.departure.panel.kind,
                MapDecorationKind::LiftControl | MapDecorationKind::M03BoardTrain
            )
        {
            return Err(invalid("M03 departure needs a fixed locomotive control"));
        }
        let departure = UseTarget {
            decoration: presentation.decorations.len(),
            approach: self.departure.approach,
        };
        presentation
            .decorations
            .push(self.departure.panel.with_solid(host));
        crate::protocol::validate_decorations(&presentation.decorations, &arena.solids)
            .map_err(invalid)?;
        crate::protocol::validate_decorations(&presentation.decorations, &fallen.solids)
            .map_err(invalid)?;
        let mut car_encounters = Vec::new();
        let mut cars = Vec::new();
        for car in self.cars {
            identity(&car.id, seen)?;
            let required = encounter(&car.requires_encounter)?;
            if required == mast_encounter
                || required == departure_encounter
                || car_encounters.contains(&required)
            {
                return Err(invalid("M03 car encounters must be independent"));
            }
            car_encounters.push(required);
            cars.push(M03CarGeometry {
                id: car.id,
                release: car.release,
                held: car.held,
                safe: car.safe,
            });
        }
        let geometry = M03MapGeometry {
            mast_shutdown: false,
            mast: M03MastGeometry {
                solid: pod,
                approach: self.mast.approach,
                aim: self.mast.aim,
            },
            departure,
            boarding: self.departure.boarding,
            cars,
            companion_start: self.companion_start,
        };
        geometry
            .validate(arena.half, &arena.solids, Some(presentation))
            .map_err(invalid)?;
        let navigation = Navigation::shared(fallen.clone()).map_err(invalid)?;
        let initial_navigation = Navigation::shared(arena.clone()).map_err(invalid)?;
        for (world, nav) in [(arena, &initial_navigation), (&fallen, &navigation)] {
            for point in std::iter::once(start)
                .chain([
                    geometry.mast.approach,
                    geometry.departure.approach,
                    geometry.companion_start,
                ])
                .chain(
                    geometry
                        .cars
                        .iter()
                        .flat_map(|car| car.held.into_iter().chain(car.safe)),
                )
            {
                if !standing(world, point)
                    || nav.route(start, point, SEARCH_LIMIT).status != RouteStatus::Complete
                {
                    return Err(invalid(
                        "M03 required feet must be supported and reachable in both worlds",
                    ));
                }
            }
            for car in &geometry.cars {
                if !car.release.contains(car.held[0]) {
                    return Err(invalid("M03 release region must cover the car"));
                }
                for (held, safe) in car.held.iter().zip(car.safe) {
                    if !nav.walkable(*held, safe) {
                        return Err(invalid("M03 captive evacuation must be a walkable segment"));
                    }
                }
            }
            let control = geometry
                .departure
                .point(presentation, &world.solids)
                .ok_or_else(|| invalid("M03 control is missing"))?;
            let eye = [
                geometry.departure.approach[0],
                geometry.departure.approach[1] + EYE_HEIGHT,
                geometry.departure.approach[2],
            ];
            let distance = (0..3)
                .map(|i| (eye[i] - control[i]).powi(2))
                .sum::<f32>()
                .sqrt();
            if distance > USE_DISTANCE || !crate::combat::line_of_sight(eye, control, &world.solids)
            {
                return Err(invalid("M03 departure approach cannot use control"));
            }
        }
        let eye = [
            geometry.mast.approach[0],
            geometry.mast.approach[1] + EYE_HEIGHT,
            geometry.mast.approach[2],
        ];
        // Check the resolved first cover identity, not just distance to the pod centre.
        let (yaw, pitch) = crate::combat::aim_at(eye, geometry.mast.aim)
            .ok_or_else(|| invalid("M03 mast aim is degenerate"))?;
        let ray = crate::combat::Ray::dispersed(eye, yaw, pitch, 0.0, [0.0, 0.0]);
        let pod_hit = ray
            .solid(&arena.solids[pod], 1000.0)
            .ok_or_else(|| invalid("M03 mast approach misses pod"))?;
        if arena.solids.iter().enumerate().any(|(index, solid)| {
            index != pod
                && ray
                    .solid(solid, pod_hit.distance)
                    .is_some_and(|hit| hit.distance <= pod_hit.distance)
        }) {
            return Err(invalid("M03 mast approach is occluded"));
        }
        Ok(Prepared {
            geometry,
            mast_encounter,
            departure_encounter,
            car_encounters,
            fallen,
            navigation,
            initial_navigation,
        })
    }
}
