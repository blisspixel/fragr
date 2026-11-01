//! Walking times over each map's navigation graph, at the frozen top speed:
//! the corner to corner crossings and, on a Sabotage map, how long each side
//! takes to reach each site and how long a defender takes to rotate between
//! them. A route is the graph's own path pulled tight by straight walks, the
//! way a fighter actually runs it, so the seconds are a floor for a body that
//! never stops. Design evidence only: a map's feel still needs a player.
use super::MapKind;
use crate::movement::TOP_SPEED;
use crate::navigation::{Navigation, RouteStatus, SEARCH_LIMIT};
use serde::Serialize;

/// A partial route is continued from where its search budget ran out, at
/// most this many times, before the leg counts as unreachable.
const ROUTE_LEGS: usize = 12;
/// Grid step, in metres, of the search for a corner's standing point.
const CORNER_STEP: f32 = 2.0;

/// One timed walk.
#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct Leg {
    pub from: String,
    pub to: String,
    /// Walked length, metres; `None` when the graph finds no way.
    pub metres: Option<f32>,
    pub seconds: Option<f32>,
}

/// Sabotage approach times, A first.
#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct SabotageTiming {
    /// Mean shortest walk from the attackers' spawn points to each site.
    pub attackers: [Option<f32>; 2],
    /// The same walk by the rule bots' staged route: the lane approach when
    /// the layout calls for one, the stage, then the site.
    pub attack_route: [Option<f32>; 2],
    /// Mean shortest walk from the defenders' spawn points to each site.
    pub defenders: [Option<f32>; 2],
    /// Site to site, the defenders' rotation.
    pub rotation: Option<f32>,
}

#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct MapTiming {
    pub map: String,
    pub map_id: u32,
    /// The two diagonals between the standing points nearest the corners.
    pub crossings: Vec<Leg>,
    pub sabotage: Option<SabotageTiming>,
}

/// The CS lineage targets the Sabotage seconds are read against
/// (`docs/plans/fun-craft-targets.md`, map timing).
pub const ATTACKER_SECONDS: (f32, f32) = (15.0, 25.0);
pub const DEFENDER_SECONDS: (f32, f32) = (8.0, 12.0);
pub const ROTATION_SECONDS: (f32, f32) = (10.0, 18.0);

fn flat(a: [f32; 3], b: [f32; 3]) -> f32 {
    (a[0] - b[0]).hypot(a[2] - b[2])
}

/// Walked metres from `from` to `to`, or `None` when no route completes.
pub fn walk_metres(world: &Navigation, from: [f32; 3], to: [f32; 3]) -> Option<f32> {
    let mut start = from;
    let mut points = vec![from];
    for _ in 0..ROUTE_LEGS {
        let route = world.route(start, to, SEARCH_LIMIT);
        match route.status {
            RouteStatus::Complete => {
                points.extend(route.points);
                return Some(pulled_length(world, &points));
            }
            RouteStatus::BudgetExhausted => {
                let last = *route.points.last()?;
                if flat(last, start) < 1.0 {
                    return None;
                }
                points.extend(route.points);
                start = last;
            }
            RouteStatus::Unreachable | RouteStatus::InvalidPoint => return None,
        }
    }
    None
}

/// The polyline pulled tight: from each point, straight to the furthest
/// later point a body can walk to directly.
fn pulled_length(world: &Navigation, points: &[[f32; 3]]) -> f32 {
    let mut metres = 0.0;
    let mut here = 0;
    while here + 1 < points.len() {
        let mut next = here + 1;
        for later in (here + 2..points.len()).rev() {
            if world.walkable(points[here], points[later]) {
                next = later;
                break;
            }
        }
        metres += flat(points[here], points[next]);
        here = next;
    }
    metres
}

fn seconds(metres: Option<f32>) -> Option<f32> {
    metres.map(|metres| metres / TOP_SPEED)
}

fn mean(values: impl Iterator<Item = Option<f32>>) -> Option<f32> {
    let mut total = 0.0;
    let mut count = 0.0;
    for value in values {
        total += value?;
        count += 1.0;
    }
    (count > 0.0).then(|| total / count)
}

/// The standing point nearest a corner of the playable square that a body
/// can walk to from `reference`.
fn corner_point(
    world: &Navigation,
    kind: MapKind,
    sign: [f32; 2],
    reference: [f32; 3],
) -> Option<[f32; 3]> {
    let half = kind.half_extent() - 1.0;
    let reach = kind.half_extent() * 0.6;
    let steps = (reach / CORNER_STEP) as i32;
    let mut candidates = Vec::new();
    for i in 0..=steps {
        for j in 0..=steps {
            let x = sign[0] * (half - i as f32 * CORNER_STEP);
            let z = sign[1] * (half - j as f32 * CORNER_STEP);
            let corner = [sign[0] * half, 0.0, sign[1] * half];
            let point = [x, 0.0, z];
            candidates.push((flat(point, corner), point));
        }
    }
    candidates.sort_by(|a, b| a.0.total_cmp(&b.0));
    candidates.into_iter().find_map(|(_, point)| {
        let floor = world.coordinate_floor(point)?;
        let feet = [point[0], floor, point[2]];
        walk_metres(world, reference, feet).map(|_| feet)
    })
}

/// Every timed walk on `kind`.
pub fn map_timing(kind: MapKind) -> MapTiming {
    let world = super::navigation(kind);
    let layout = super::sabotage_layout(kind);
    let (x, z, _, floor) = crate::sim::spawn_on_ring(kind, 0.0);
    let reference = [x, floor, z];
    let corners: Vec<Option<[f32; 3]>> = [[-1.0, -1.0], [1.0, 1.0], [1.0, -1.0], [-1.0, 1.0]]
        .into_iter()
        .map(|sign| corner_point(world, kind, sign, reference))
        .collect();
    let names = ["north-west", "south-east", "north-east", "south-west"];
    let crossings = [(0, 1), (2, 3)]
        .into_iter()
        .map(|(a, b)| {
            let metres = corners[a]
                .zip(corners[b])
                .and_then(|(from, to)| walk_metres(world, from, to));
            Leg {
                from: names[a].to_string(),
                to: names[b].to_string(),
                metres,
                seconds: seconds(metres),
            }
        })
        .collect();
    let sabotage = layout.map(|layout| {
        let sites = [layout.wire.sites[0].center, layout.wire.sites[1].center];
        let from_side = |side: usize, site: [f32; 3]| {
            seconds(mean(layout.spawns[side].iter().map(|&[x, floor, z, _]| {
                walk_metres(world, [x, floor, z], site)
            })))
        };
        let attack_route = |index: usize| {
            seconds(mean(layout.spawns[1].iter().map(|&[x, floor, z, _]| {
                let spawn = [x, floor, z];
                let stage = layout.stages[index][0];
                let approach = layout.approaches[index];
                let to_stage = if (layout.approach_needed)(spawn, approach) {
                    walk_metres(world, spawn, approach)
                        .zip(walk_metres(world, approach, stage))
                        .map(|(a, b)| a + b)
                } else {
                    walk_metres(world, spawn, stage)
                };
                to_stage
                    .zip(walk_metres(world, stage, sites[index]))
                    .map(|(a, b)| a + b)
            })))
        };
        // Union defenders are side 0, the coalition attack side 1.
        SabotageTiming {
            attackers: [from_side(1, sites[0]), from_side(1, sites[1])],
            attack_route: [attack_route(0), attack_route(1)],
            defenders: [from_side(0, sites[0]), from_side(0, sites[1])],
            rotation: seconds(walk_metres(world, sites[0], sites[1])),
        }
    });
    MapTiming {
        map: kind.name().to_string(),
        map_id: kind.id(),
        crossings,
        sabotage,
    }
}

/// Seconds outside a target band, as readable misses.
pub fn sabotage_misses(timing: &MapTiming) -> Vec<String> {
    let Some(sabotage) = &timing.sabotage else {
        return Vec::new();
    };
    let mut misses = Vec::new();
    let mut check = |what: String, value: Option<f32>, band: (f32, f32)| match value {
        Some(value) if (band.0..=band.1).contains(&value) => {}
        Some(value) => misses.push(format!(
            "{} {what}: {value:.1} s, want {:.0} to {:.0}",
            timing.map, band.0, band.1
        )),
        None => misses.push(format!("{} {what}: no route", timing.map)),
    };
    for (index, site) in ["A", "B"].into_iter().enumerate() {
        check(
            format!("attackers to {site}"),
            sabotage.attackers[index],
            ATTACKER_SECONDS,
        );
        check(
            format!("defenders to {site}"),
            sabotage.defenders[index],
            DEFENDER_SECONDS,
        );
    }
    check("rotation".to_string(), sabotage.rotation, ROTATION_SECONDS);
    misses
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn straight_open_walk_times_at_top_speed() {
        let world = super::super::navigation(MapKind::ArenaDuel);
        let timing = map_timing(MapKind::ArenaDuel);
        assert_eq!(timing.crossings.len(), 2);
        for leg in &timing.crossings {
            let metres = leg.metres.expect("Larak Lot corners connect");
            // A diagonal is never shorter than the straight line between
            // the standing points, and never absurdly longer.
            assert!(metres > 30.0, "{leg:?}");
            assert!((leg.seconds.unwrap() - metres / TOP_SPEED).abs() < 1e-3);
        }
        assert!(timing.sabotage.is_none());
        // A pulled walk across open floor is the straight line.
        let from = [0.0, 0.0, 0.0];
        let to = [6.0, 0.0, 0.0];
        if world.walkable(from, to) {
            let metres = walk_metres(world, from, to).unwrap();
            assert!((metres - 6.0).abs() < 1.5, "{metres}");
        }
    }

    #[test]
    fn a_point_outside_the_world_has_no_route() {
        let world = super::super::navigation(MapKind::ArenaDuel);
        assert_eq!(
            walk_metres(world, [0.0, 0.0, 0.0], [9999.0, 0.0, 0.0]),
            None
        );
        assert_eq!(mean([Some(1.0), None].into_iter()), None);
        assert_eq!(mean(std::iter::empty()), None);
    }
}
