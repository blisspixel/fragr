//! A bounded mission route has two prevalidated geometry states, never tick-time baking.
use super::{invalid, standing};
use crate::movement::{Arena, EYE_HEIGHT};
use crate::navigation::{Navigation, RouteStatus, SEARCH_LIMIT};
use crate::protocol::{
    MapDecoration, MapDecorationKind, MapPresentation, MissionGeometry, MissionId, Region3,
    UseTarget, USE_DISTANCE,
};
use serde::Deserialize;
use std::collections::HashMap;
use std::io;

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub(super) struct Definition {
    id: MissionId,
    record: Control,
    departure: Control,
    gate: Gate,
    boarding: Region3,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct Control {
    panel: MapDecoration<String>,
    approach: [f32; 3],
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct Gate {
    solid: String,
    lift: f32,
}

pub(super) struct Prepared {
    pub geometry: MissionGeometry,
    pub opened: Arena,
}

impl Definition {
    pub fn prepare(
        self,
        arena: &Arena,
        solid_ids: &HashMap<String, usize>,
        presentation: &mut MapPresentation,
    ) -> io::Result<Prepared> {
        let gate = *solid_ids
            .get(&self.gate.solid)
            .ok_or_else(|| invalid("mission gate references an unknown solid"))?;
        if !self.gate.lift.is_finite() || !(0.125..=16.0).contains(&self.gate.lift) {
            return Err(invalid("mission gate lift must be finite and bounded"));
        }
        let mut opened = arena.clone();
        opened.solids[gate].bottom += self.gate.lift;
        opened.solids[gate].top += self.gate.lift;
        crate::movement::validate_geometry(opened.half, &opened.solids).map_err(invalid)?;
        let mut targets = Vec::new();
        for (control, expected) in [
            (self.record, MapDecorationKind::Terminal),
            (self.departure, MapDecorationKind::LiftControl),
        ] {
            let host = *solid_ids
                .get(&control.panel.solid)
                .ok_or_else(|| invalid("mission control references an unknown solid"))?;
            if host == gate || control.panel.kind != expected {
                return Err(invalid(
                    "mission controls need static hosts and matching panel kinds",
                ));
            }
            targets.push(UseTarget {
                decoration: presentation.decorations.len(),
                approach: control.approach,
            });
            presentation
                .decorations
                .push(control.panel.with_solid(host));
        }
        crate::protocol::validate_map_presentation(Some(presentation), &arena.solids)
            .map_err(invalid)?;
        crate::protocol::validate_map_presentation(Some(presentation), &opened.solids)
            .map_err(invalid)?;
        let geometry = MissionGeometry {
            id: self.id,
            record: targets.remove(0),
            departure: targets.remove(0),
            boarding: self.boarding,
        };
        geometry
            .validate(arena.half, &arena.solids, Some(presentation))
            .map_err(invalid)?;
        for target in [&geometry.record, &geometry.departure] {
            for world in [arena, &opened] {
                if !standing(world, target.approach) {
                    return Err(invalid(
                        "mission approach needs standing clearance in both gate states",
                    ));
                }
                let point = target
                    .point(presentation, &world.solids)
                    .ok_or_else(|| invalid("mission control has no use point"))?;
                let mut eye = target.approach;
                eye[1] += EYE_HEIGHT;
                let distance = (0..3)
                    .map(|axis| (eye[axis] - point[axis]).powi(2))
                    .sum::<f32>()
                    .sqrt();
                if distance > USE_DISTANCE
                    || !crate::combat::line_of_sight(eye, point, &world.solids)
                {
                    return Err(invalid("mission approach cannot reach and see its control"));
                }
            }
        }
        Ok(Prepared { geometry, opened })
    }
}

impl Prepared {
    pub fn validate_routes(
        &self,
        start: [f32; 3],
        closed: &Navigation,
        opened: &Navigation,
    ) -> io::Result<()> {
        let reachable = |nav: &Navigation, target| {
            nav.route(start, target, SEARCH_LIMIT).status == RouteStatus::Complete
        };
        for (valid, reason) in [
            (
                reachable(closed, self.geometry.record.approach),
                "mission record is unreachable with gate closed",
            ),
            (
                reachable(opened, self.geometry.record.approach),
                "mission record is unreachable with gate open",
            ),
            (
                !reachable(closed, self.geometry.departure.approach),
                "mission gate does not block the departure route",
            ),
            (
                reachable(opened, self.geometry.departure.approach),
                "mission gate does not open the departure route",
            ),
        ] {
            if !valid {
                return Err(invalid(reason));
            }
        }
        Ok(())
    }
}
