//! Exit and optional cache gates have at most four prevalidated geometry states.
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
    #[serde(default)]
    secret: Option<Secret>,
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

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct Secret {
    control: Control,
    gate: Gate,
    inside: [f32; 3],
}

pub(super) struct SecretWorlds {
    pub closed_exit: Arena,
    pub open_exit: Arena,
    inside: [f32; 3],
}

pub(super) struct Prepared {
    pub geometry: MissionGeometry,
    pub opened: Arena,
    pub secret: Option<SecretWorlds>,
}

impl Gate {
    fn prepare(&self, arena: &Arena, ids: &HashMap<String, usize>) -> io::Result<(usize, Arena)> {
        let index = *ids
            .get(&self.solid)
            .ok_or_else(|| invalid("mission gate references an unknown solid"))?;
        if !self.lift.is_finite() || !(0.125..=16.0).contains(&self.lift) {
            return Err(invalid("mission gate lift must be finite and bounded"));
        }
        let mut opened = arena.clone();
        opened.solids[index].bottom += self.lift;
        opened.solids[index].top += self.lift;
        crate::movement::validate_geometry(opened.half, &opened.solids).map_err(invalid)?;
        Ok((index, opened))
    }
}

impl Definition {
    pub fn prepare(
        self,
        arena: &Arena,
        solid_ids: &HashMap<String, usize>,
        presentation: &mut MapPresentation,
    ) -> io::Result<Prepared> {
        let (gate, opened) = self.gate.prepare(arena, solid_ids)?;
        let (secret, secret_control, secret_gate) = if let Some(secret) = self.secret {
            let (index, closed_exit) = secret.gate.prepare(arena, solid_ids)?;
            if index == gate {
                return Err(invalid("exit and cache gates must be distinct"));
            }
            let (_, open_exit) = secret.gate.prepare(&opened, solid_ids)?;
            if !standing(&closed_exit, secret.inside) || !standing(&open_exit, secret.inside) {
                return Err(invalid(
                    "cache destination needs supported standing clearance",
                ));
            }
            (
                Some(SecretWorlds {
                    closed_exit,
                    open_exit,
                    inside: secret.inside,
                }),
                Some(secret.control),
                Some(index),
            )
        } else {
            (None, None, None)
        };
        let mut targets = Vec::new();
        for (control, expected) in [
            (self.record, MapDecorationKind::Terminal),
            (self.departure, MapDecorationKind::LiftControl),
        ]
        .into_iter()
        .chain(secret_control.map(|control| (control, MapDecorationKind::Vent)))
        {
            let host = *solid_ids
                .get(&control.panel.solid)
                .ok_or_else(|| invalid("mission control references an unknown solid"))?;
            if host == gate || Some(host) == secret_gate || control.panel.kind != expected {
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
        let geometry = MissionGeometry {
            id: self.id,
            record: targets.remove(0),
            departure: targets.remove(0),
            secret: targets.pop(),
            boarding: self.boarding,
        };
        let worlds: Vec<_> = [arena, &opened]
            .into_iter()
            .chain(secret.iter().flat_map(|s| [&s.closed_exit, &s.open_exit]))
            .collect();
        for world in &worlds {
            crate::protocol::validate_map_presentation(Some(presentation), &world.solids)
                .map_err(invalid)?;
            geometry
                .validate(world.half, &world.solids, Some(presentation))
                .map_err(invalid)?;
        }
        for target in [&geometry.record, &geometry.departure]
            .into_iter()
            .chain(geometry.secret.iter())
        {
            for world in &worlds {
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
        Ok(Prepared {
            geometry,
            opened,
            secret,
        })
    }
}

impl Prepared {
    pub fn validate_secret_routes(
        &self,
        start: [f32; 3],
        closed: &Navigation,
        opened: &Navigation,
        cache_closed_exit: &Navigation,
        cache_open_exit: &Navigation,
    ) -> io::Result<()> {
        self.validate_routes(start, cache_closed_exit, cache_open_exit)?;
        let secret = self
            .secret
            .as_ref()
            .ok_or_else(|| invalid("missing cache worlds"))?;
        let control = self
            .geometry
            .secret
            .as_ref()
            .ok_or_else(|| invalid("missing cache control"))?;
        for nav in [closed, opened] {
            if nav.route(start, control.approach, SEARCH_LIMIT).status != RouteStatus::Complete
                || nav.route(start, secret.inside, SEARCH_LIMIT).status == RouteStatus::Complete
            {
                return Err(invalid(
                    "cache control must be reachable but its reward must be gated",
                ));
            }
        }
        for nav in [cache_closed_exit, cache_open_exit] {
            if nav.route(start, secret.inside, SEARCH_LIMIT).status != RouteStatus::Complete {
                return Err(invalid("opened cache must be reachable"));
            }
        }
        Ok(())
    }

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
