//! Ledge heights against the jump (#525).
//!
//! A ledge a little above a step reads as a step and stops the player dead; a
//! ledge just under a standing jump's reach is clearable only from a clean
//! jump; one just over it looks jumpable and is not. All three are "maybe"
//! ledges that make movement feel unreliable, which is why arena shooters keep
//! obstacles clearly below a step, clearly a jump, or clearly a wall.
//!
//! The scan walks every edge of every solid top in every arena map and
//! campaign level, stands a fighter just outside it on the highest floor
//! there, and measures the rise to the top. A rise in the band from above
//! [`STEP_UP`] to just under [`WALL`] is reported,
//! grouped into runs along the edge. The reach is measured, not assumed: a
//! fighter on the live 20 Hz step runs at a block and jumps at every phase.

use super::{AuthoredSource, MapKind};
use crate::movement::{
    fighter_step, Arena, MoveInput, MoveState, Solid, BODY_HEIGHT, DT_LIVE, RADIUS, STEP_UP,
    TOP_SPEED,
};
use serde::Serialize;

/// Sub-band widths: a rise within this of the step reads as a step, and
/// within this of the reach is marginal on either side.
pub const NEAR: f32 = 0.15;
/// The lowest top that reads clearly as a wall (#538). Anything between the
/// reach and this still looks jumpable and is not.
pub const WALL: f32 = 1.5;
/// Spacing of the probe points along an edge.
const SPACING: f32 = 0.25;
/// A top narrower than a body is a rail or a lip, not somewhere to land.
const MIN_TOP: f32 = 2.0 * RADIUS;

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum Band {
    /// Just above a step: reads as one, needs a jump.
    StepPlus,
    /// A plain jump, inside the band but clear of both ends.
    Jump,
    /// Just under the reach: only a clean jump clears it.
    Marginal,
    /// Just over the reach: looks jumpable, is not.
    FalseHope,
}

impl Band {
    pub const ALL: [Band; 4] = [Band::StepPlus, Band::Jump, Band::Marginal, Band::FalseHope];

    /// Whether the band is ambiguous to a player, not merely a jump.
    pub fn ambiguous(self) -> bool {
        self != Band::Jump
    }

    fn of(rise: f32, reach: f32) -> Option<Band> {
        if rise <= STEP_UP + 0.001 || rise >= WALL - 0.001 {
            None
        } else if rise <= STEP_UP + NEAR {
            Some(Band::StepPlus)
        } else if rise > reach {
            Some(Band::FalseHope)
        } else if rise > reach - NEAR {
            Some(Band::Marginal)
        } else {
            Some(Band::Jump)
        }
    }
}

/// One run of probe points along one edge in one band.
#[derive(Debug, Clone, Serialize)]
pub struct Ledge {
    pub solid: usize,
    pub side: &'static str,
    /// The top the edge rises to, and its footprint: lowest x, z, highest x, z.
    pub top: f32,
    pub extent: [f32; 4],
    pub band: Band,
    pub rise_min: f32,
    pub rise_max: f32,
    pub length_m: f32,
    /// The run's midpoint on the floor outside the edge, x and z.
    pub at: [f32; 2],
    /// Where the run starts, x and z.
    #[serde(skip)]
    from: [f32; 2],
}

#[derive(Debug, Clone, Serialize)]
pub struct MapLedges {
    pub label: String,
    pub name: String,
    pub solids: usize,
    pub ledges: Vec<Ledge>,
}

impl MapLedges {
    pub fn count(&self, band: Band) -> usize {
        self.ledges.iter().filter(|l| l.band == band).count()
    }

    pub fn ambiguous_length(&self) -> f32 {
        self.ledges
            .iter()
            .filter(|l| l.band.ambiguous())
            .map(|l| l.length_m)
            .fold(0.0, |total, length| total + length)
    }
}

#[derive(Debug, Clone, Serialize)]
pub struct LedgeReport {
    pub step_up: f32,
    /// The highest top a standing running jump lands on, measured.
    pub jump_reach: f32,
    pub near: f32,
    pub maps: Vec<MapLedges>,
}

/// Whether a fighter running at a block of `rise` and jumping at some tick
/// of its approach ends up standing on it.
fn clears(rise: f32) -> bool {
    // Find which way "forward" runs at yaw 0, then put the block there.
    let open = Arena {
        half: 50.0,
        solids: Vec::new(),
    };
    let still = MoveState {
        x: 0.0,
        z: 0.0,
        y: 0.0,
        vx: 0.0,
        vz: 0.0,
        vy: 0.0,
        yaw: 0.0,
    };
    let forward = MoveInput {
        forward: true,
        ..MoveInput::default()
    };
    let probe = fighter_step(still, &forward, TOP_SPEED, DT_LIVE, &open);
    let (dx, dz) = (probe.x.signum(), probe.z.signum());
    let along_x = probe.x.abs() > probe.z.abs();
    // The face 3 m ahead, the top long enough that the run never leaves it.
    let (near, long) = (3.0, 20.0);
    let block = if along_x {
        Solid::from_center_top(dx * (near + long), 0.0, long, 4.0, rise)
    } else {
        Solid::from_center_top(0.0, dz * (near + long), 4.0, long, rise)
    };
    let arena = Arena {
        half: 50.0,
        solids: vec![block],
    };
    (0..12).any(|jump_at| {
        let mut state = still;
        (0..40).any(|tick| {
            let input = MoveInput {
                jump: tick == jump_at,
                ..forward
            };
            state = fighter_step(state, &input, TOP_SPEED, DT_LIVE, &arena);
            (state.y - rise).abs() < 0.001 && state.vy <= 0.0
        })
    })
}

/// The standing running jump's reach on the live step, to the centimetre.
pub fn jump_reach() -> f32 {
    let (mut low, mut high) = (STEP_UP, 3.0f32);
    while high - low > 0.005 {
        let mid = (low + high) / 2.0;
        if clears(mid) {
            low = mid;
        } else {
            high = mid;
        }
    }
    (low * 100.0).floor() / 100.0
}

/// Grid spacing of the reach flood.
const CELL: f32 = 0.5;
/// Side of the solid buckets that keep the flood's queries local.
const BUCKET: f32 = 4.0;

/// Every floor a fighter can get to from where it starts, by grid cell: a
/// layered flood fill that walks and steps like the movement step, drops off
/// any edge and climbs anything up to the measured jump reach. It
/// over-reaches on purpose (no run-up or headroom check on a climb), so the
/// gate it feeds errs toward reporting a ledge, never toward hiding one. A
/// top that nothing reaches (a parapet behind a wall) is not a ledge anyone
/// stands beside.
pub struct Reached {
    span: i32,
    floors: Vec<Vec<f32>>,
}

impl Reached {
    pub fn flood(arena: &Arena, reach: f32, seeds: &[[f32; 3]]) -> Self {
        let span = (arena.half / CELL).floor() as i32;
        let width = (span * 2 + 1) as usize;
        let buckets_per_side = ((2.0 * arena.half) / BUCKET).ceil() as usize + 1;
        let bucket_of = |x: f32, z: f32| -> usize {
            let bx =
                (((x + arena.half) / BUCKET).floor().max(0.0) as usize).min(buckets_per_side - 1);
            let bz =
                (((z + arena.half) / BUCKET).floor().max(0.0) as usize).min(buckets_per_side - 1);
            bz * buckets_per_side + bx
        };
        let pad = RADIUS + CELL;
        let buckets: Vec<Arena> = (0..buckets_per_side * buckets_per_side)
            .map(|index| {
                let (bx, bz) = (index % buckets_per_side, index / buckets_per_side);
                let x0 = -arena.half + bx as f32 * BUCKET - pad;
                let z0 = -arena.half + bz as f32 * BUCKET - pad;
                let (x1, z1) = (x0 + BUCKET + 2.0 * pad, z0 + BUCKET + 2.0 * pad);
                Arena {
                    half: arena.half,
                    solids: arena
                        .solids
                        .iter()
                        .filter(|s| {
                            s.max_x >= x0 && s.min_x <= x1 && s.max_z >= z0 && s.min_z <= z1
                        })
                        .copied()
                        .collect(),
                }
            })
            .collect();
        let mut reached = Self {
            span,
            floors: vec![Vec::new(); width * width],
        };
        let mut queue = std::collections::VecDeque::new();
        let limit = arena.half - RADIUS;
        for &[x, feet, z] in seeds {
            let (ix, iz) = ((x / CELL).round() as i32, (z / CELL).round() as i32);
            if ix.abs() > span || iz.abs() > span {
                continue;
            }
            let (wx, wz) = (ix as f32 * CELL, iz as f32 * CELL);
            let floor = buckets[bucket_of(wx, wz)].support_height(wx, wz, feet + STEP_UP);
            if reached.insert(ix, iz, floor) {
                queue.push_back((ix, iz, floor));
            }
        }
        while let Some((ix, iz, floor)) = queue.pop_front() {
            for (dx, dz) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                let (nx, nz) = (ix + dx, iz + dz);
                let (wx, wz) = (nx as f32 * CELL, nz as f32 * CELL);
                if nx.abs() > span || nz.abs() > span || wx.abs() > limit || wz.abs() > limit {
                    continue;
                }
                let local = &buckets[bucket_of(wx, wz)];
                for climb in [floor + STEP_UP, floor + reach + 0.001] {
                    if local.blocked_body_at(wx, wz, floor, climb) {
                        continue;
                    }
                    let next = local.support_height(wx, wz, climb);
                    if reached.insert(nx, nz, next) {
                        queue.push_back((nx, nz, next));
                    }
                }
            }
        }
        reached
    }

    fn index(&self, ix: i32, iz: i32) -> usize {
        let width = (self.span * 2 + 1) as usize;
        ((iz + self.span) as usize) * width + (ix + self.span) as usize
    }

    fn insert(&mut self, ix: i32, iz: i32, floor: f32) -> bool {
        let cell = self.index(ix, iz);
        if self.floors[cell].iter().any(|f| (f - floor).abs() < 0.01) {
            return false;
        }
        self.floors[cell].push(floor);
        true
    }

    /// Whether a fighter reaches `floor` at some cell next to `(x, z)`.
    pub fn reaches(&self, x: f32, z: f32, floor: f32) -> bool {
        let (cx, cz) = ((x / CELL).round() as i32, (z / CELL).round() as i32);
        (-1..=1).any(|dz| {
            (-1..=1).any(|dx| {
                let (ix, iz) = (cx + dx, cz + dz);
                ix.abs() <= self.span
                    && iz.abs() <= self.span
                    && self.floors[self.index(ix, iz)]
                        .iter()
                        .any(|f| (f - floor).abs() < 0.01)
            })
        })
    }
}
/// One probe point on one edge: the floor outside, where a body stands.
struct Probe {
    out: (f32, f32),
    inside: (f32, f32),
}

fn probes(solid: &Solid, side: usize) -> Vec<Probe> {
    let gap = RADIUS + 0.05;
    let (lo, hi, fixed, inward) = match side {
        0 => (solid.min_z, solid.max_z, solid.min_x, 1.0),
        1 => (solid.min_z, solid.max_z, solid.max_x, -1.0),
        2 => (solid.min_x, solid.max_x, solid.min_z, 1.0),
        _ => (solid.min_x, solid.max_x, solid.max_z, -1.0),
    };
    let depth = if side < 2 {
        solid.max_x - solid.min_x
    } else {
        solid.max_z - solid.min_z
    };
    let into = (0.3f32).min(depth / 2.0);
    let count = (((hi - lo) - 0.2) / SPACING).floor().max(0.0) as usize + 1;
    (0..count)
        .map(|i| {
            let along = (lo + 0.1 + i as f32 * SPACING).min(hi - 0.1);
            let out = fixed - inward * gap;
            let inside = fixed + inward * into;
            if side < 2 {
                Probe {
                    out: (out, along),
                    inside: (inside, along),
                }
            } else {
                Probe {
                    out: (along, out),
                    inside: (along, inside),
                }
            }
        })
        .collect()
}

/// Whether a top is one tread of a flight: a solid beside it, sharing a face
/// at least a body wide, sits a step or less below it. Its open sides read as
/// the side of a stair (or a stack climbed by its lower block), with the way
/// up in plain view, not as a ledge to judge.
fn is_tread(arena: &Arena, solid: &Solid) -> bool {
    const TOUCH: f32 = 0.01;
    let overlap = |a0: f32, a1: f32, b0: f32, b1: f32| a1.min(b1) - a0.max(b0);
    arena.solids.iter().any(|other| {
        let drop = solid.top - other.top;
        let beside_x = ((other.max_x - solid.min_x).abs() < TOUCH
            || (other.min_x - solid.max_x).abs() < TOUCH)
            && overlap(solid.min_z, solid.max_z, other.min_z, other.max_z) >= MIN_TOP;
        let beside_z = ((other.max_z - solid.min_z).abs() < TOUCH
            || (other.min_z - solid.max_z).abs() < TOUCH)
            && overlap(solid.min_x, solid.max_x, other.min_x, other.max_x) >= MIN_TOP;
        drop > 0.001 && drop <= STEP_UP + 0.001 && (beside_x || beside_z)
    })
}

const SIDES: [&str; 4] = ["west", "east", "north", "south"];

/// The ambiguous and jump ledges of one arena. With `reached`, only edges a
/// fighter can stand beside count.
pub fn scan(arena: &Arena, reach: f32, reached: Option<&Reached>) -> Vec<Ledge> {
    let mut found = Vec::new();
    let limit = arena.half - RADIUS;
    for (index, solid) in arena.solids.iter().enumerate() {
        if solid.max_x - solid.min_x < MIN_TOP
            || solid.max_z - solid.min_z < MIN_TOP
            || is_tread(arena, solid)
        {
            continue;
        }
        for (side, name) in SIDES.iter().enumerate() {
            let mut run: Option<Ledge> = None;
            let mut runs = Vec::new();
            for probe in probes(solid, side) {
                let (ox, oz) = probe.out;
                let (ix, iz) = probe.inside;
                let band = (ox.abs() <= limit && oz.abs() <= limit)
                    .then(|| {
                        let floor = arena.support_height(ox, oz, solid.top - 0.05);
                        let on_top = arena.support_height(ix, iz, solid.top + 0.001);
                        let standable = arena.fits_height(ox, oz, floor, BODY_HEIGHT)
                            && reached.is_none_or(|r| r.reaches(ox, oz, floor))
                            && (on_top - solid.top).abs() < 0.001
                            && arena.fits_height(ix, iz, solid.top, BODY_HEIGHT);
                        let rise = solid.top - floor;
                        standable
                            .then(|| Band::of(rise, reach).map(|band| (band, rise)))
                            .flatten()
                    })
                    .flatten();
                match (band, run.as_mut()) {
                    (Some((band, rise)), Some(open)) if open.band == band => {
                        open.rise_min = open.rise_min.min(rise);
                        open.rise_max = open.rise_max.max(rise);
                        open.length_m += SPACING;
                        open.at = [(open.from[0] + ox) / 2.0, (open.from[1] + oz) / 2.0];
                    }
                    (found_band, _) => {
                        runs.extend(run.take());
                        run = found_band.map(|(band, rise)| Ledge {
                            solid: index,
                            top: solid.top,
                            extent: [solid.min_x, solid.min_z, solid.max_x, solid.max_z],
                            side: name,
                            band,
                            rise_min: rise,
                            rise_max: rise,
                            length_m: SPACING,
                            at: [ox, oz],
                            from: [ox, oz],
                        });
                    }
                }
            }
            runs.extend(run);
            found.extend(runs);
        }
    }
    found
}

/// Where a fighter starts on an arena map: its spawn table when it has one,
/// and every pad, which a fighter must be able to stand on.
fn arena_seeds(kind: MapKind) -> Vec<[f32; 3]> {
    let def = super::def(kind);
    let table: &[[f32; 4]] = match kind {
        MapKind::ArenaDuel => &super::larak_lot::SPAWNS[..],
        MapKind::LowWater => &super::low_water::SPAWNS[..],
        _ => &[],
    };
    table
        .iter()
        .map(|[x, feet, z, _]| [*x, *feet, *z])
        .chain(
            def.pickups
                .iter()
                .chain(&def.scrap_pads)
                .map(|pad| [pad.x, pad.floor, pad.z]),
        )
        .collect()
}

/// Every arena map, then every campaign level and the epilogue.
pub fn scan_all() -> std::io::Result<LedgeReport> {
    let reach = jump_reach();
    let mut maps = Vec::new();
    for kind in MapKind::ALL {
        let arena = super::arena(kind);
        let reached = Reached::flood(arena, reach, &arena_seeds(kind));
        maps.push(MapLedges {
            label: format!("Map {}", kind.id()),
            name: kind.name().to_string(),
            solids: arena.solids.len(),
            ledges: scan(arena, reach, Some(&reached)),
        });
    }
    for (index, mission) in crate::protocol::MissionId::PLAYABLE.iter().enumerate() {
        let map = AuthoredSource::Mission(*mission).load()?;
        let label = if *mission == crate::protocol::MissionId::StillHere {
            "Epilogue".to_string()
        } else {
            format!("L{:02}", index + 1)
        };
        let seeds: Vec<[f32; 3]> = map
            .spawns
            .iter()
            .map(|spawn| spawn.feet)
            .chain(map.supplies.iter().map(|pad| [pad.x, pad.floor, pad.z]))
            .collect();
        let reached = Reached::flood(&map.arena, reach, &seeds);
        maps.push(MapLedges {
            label,
            name: map.name.clone(),
            solids: map.arena.solids.len(),
            ledges: scan(&map.arena, reach, Some(&reached)),
        });
    }
    Ok(LedgeReport {
        step_up: STEP_UP,
        jump_reach: reach,
        near: NEAR,
        maps,
    })
}

/// A ledge in an ambiguous band that stays on purpose, with the reason. It
/// names the map, the top and the solid's footprint (lowest x, z, highest x,
/// z), so moving or resizing the solid drops it off the list and the gate asks
/// again.
#[derive(Debug, Clone, Copy)]
pub struct Allowed {
    pub map: &'static str,
    pub top: f32,
    pub extent: [f32; 4],
    pub reason: &'static str,
}

/// The ambiguous ledges kept on purpose (#538). Everything else in the
/// step-plus, marginal and false-hope bands fails `the_ledge_gate_holds`.
pub const ALLOWED: [Allowed; 3] = [
    Allowed {
        map: "Map 7",
        top: 2.2,
        extent: [-66.8, 74.0, -59.2, 76.0],
        reason: "west boarding dock: a quarter metre where its end overhangs the beach steps; \
                 the dock is walked onto from the shore at boat height",
    },
    Allowed {
        map: "Map 7",
        top: 2.2,
        extent: [59.2, 74.0, 66.8, 76.0],
        reason: "east boarding dock, the same quarter metre over the beach steps",
    },
    Allowed {
        map: "L14",
        top: 3.5,
        extent: [-40.3, -27.3, -30.7, -15.7],
        reason: "the depot roof's west edge runs beside the depot stair, half a metre from \
                 two treads; the flight is the way up and reads as one",
    },
];

impl Allowed {
    fn covers(&self, map: &str, ledge: &Ledge) -> bool {
        self.map == map
            && (self.top - ledge.top).abs() < 0.005
            && self
                .extent
                .iter()
                .zip(ledge.extent)
                .all(|(a, b)| (a - b).abs() < 0.005)
    }
}

/// Every ambiguous ledge the allow-list does not name, as readable lines.
pub fn unexplained(report: &LedgeReport) -> Vec<String> {
    report
        .maps
        .iter()
        .flat_map(|map| {
            map.ledges
                .iter()
                .filter(|ledge| ledge.band.ambiguous())
                .filter(|ledge| !ALLOWED.iter().any(|allowed| allowed.covers(&map.label, ledge)))
                .map(|ledge| {
                    format!(
                        "{} {}: solid {} top {:.2} {} edge, {:?} rise {:.2} to {:.2} over {:.2} m near ({:.1}, {:.1})",
                        map.label,
                        map.name,
                        ledge.solid,
                        ledge.top,
                        ledge.side,
                        ledge.band,
                        ledge.rise_min,
                        ledge.rise_max,
                        ledge.length_m,
                        ledge.at[0],
                        ledge.at[1]
                    )
                })
                .collect::<Vec<_>>()
        })
        .collect()
}

/// Allow-list entries that no longer match an ambiguous ledge: stale reasons
/// that would otherwise excuse the next ledge built in the same place.
pub fn stale_allowances(report: &LedgeReport) -> Vec<&'static str> {
    ALLOWED
        .iter()
        .filter(|allowed| {
            !report.maps.iter().any(|map| {
                map.ledges
                    .iter()
                    .any(|ledge| ledge.band.ambiguous() && allowed.covers(&map.label, ledge))
            })
        })
        .map(|allowed| allowed.reason)
        .collect()
}
/// The report as a Markdown table, one row per map.
pub fn table(report: &LedgeReport) -> String {
    let (step, reach, near) = (report.step_up, report.jump_reach, report.near);
    let mut out = format!(
        "Step {step:.2} m, measured jump reach {reach:.2} m. Runs of edge, by rise:\n\n\
         | Map | Name | Solids | Step-plus {step:.2} to {:.2} | Jump {:.2} to {:.2} | Marginal {:.2} to {reach:.2} | False hope {reach:.2} to {:.2} | Ambiguous edge m |\n\
         |---|---|---|---|---|---|---|---|\n",
        step + near,
        step + near,
        reach - near,
        reach - near,
        WALL
    );
    for map in &report.maps {
        out.push_str(&format!(
            "| {} | {} | {} | {} | {} | {} | {} | {:.1} |\n",
            map.label,
            map.name,
            map.solids,
            map.count(Band::StepPlus),
            map.count(Band::Jump),
            map.count(Band::Marginal),
            map.count(Band::FalseHope),
            map.ambiguous_length()
        ));
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_measured_reach_is_the_live_jump() {
        let reach = jump_reach();
        // 7 m/s up against 22 m/s^2 on the 20 Hz step peaks near 1.3 m.
        assert!((1.15..=1.35).contains(&reach), "{reach}");
        assert!(clears(reach) && !clears(reach + 0.02));
    }

    #[test]
    fn each_band_is_found_where_it_is_built() {
        let reach = jump_reach();
        let block = |x: f32, top: f32| Solid::from_center_top(x, 0.0, 1.0, 1.0, top);
        let arena = Arena {
            half: 40.0,
            solids: vec![
                block(-12.0, 0.4),                                // a step: not reported
                block(-6.0, STEP_UP + 0.1),                       // reads as a step
                block(0.0, 1.0),                                  // a plain jump
                block(6.0, reach - 0.05),                         // marginal
                block(12.0, reach + 0.1),                         // false hope
                block(18.0, 3.0),                                 // a wall: not reported
                Solid::from_center_top(24.0, 0.0, 0.1, 1.0, 1.0), // a rail
            ],
        };
        let ledges = scan(&arena, reach, None);
        let bands: std::collections::BTreeSet<(usize, Band)> =
            ledges.iter().map(|l| (l.solid, l.band)).collect();
        assert_eq!(
            bands.into_iter().collect::<Vec<_>>(),
            vec![
                (1, Band::StepPlus),
                (2, Band::Jump),
                (3, Band::Marginal),
                (4, Band::FalseHope)
            ]
        );
        // Each block's four sides, each one run the length of the side less
        // the 0.1 m ends, to the probe spacing.
        let sides = ledges.iter().filter(|l| l.solid == 2).count();
        assert_eq!(sides, 4);
        assert!(ledges.iter().all(|l| (l.length_m - 2.0).abs() <= SPACING));
        assert!(Band::StepPlus.ambiguous() && !Band::Jump.ambiguous());
    }

    #[test]
    fn a_ledge_is_measured_from_the_floor_beside_it() {
        // A deck at 0.5 beside a deck at 1.6: a 1.1 m rise, a plain jump,
        // from the lower deck; from the base floor its other sides are walls.
        let reach = jump_reach();
        let arena = Arena {
            half: 40.0,
            solids: vec![
                Solid::from_center_top(-2.0, 0.0, 2.0, 2.0, 0.5),
                Solid::from_center_top(1.0, 0.0, 1.0, 2.0, 1.6),
            ],
        };
        let ledges: Vec<Ledge> = scan(&arena, reach, None)
            .into_iter()
            .filter(|l| l.solid == 1)
            .collect();
        assert_eq!(ledges.len(), 1, "{ledges:?}");
        assert_eq!(ledges[0].side, "west");
        assert!((ledges[0].rise_min - 1.1).abs() < 1e-4 && ledges[0].band == Band::Jump);
    }

    #[test]
    fn every_map_and_level_is_scanned() {
        let report = scan_all().unwrap();
        assert_eq!(
            report.maps.len(),
            MapKind::ALL.len() + crate::protocol::MissionId::PLAYABLE.len()
        );
        assert!(report.maps.iter().all(|m| m.solids > 0));
        let text = table(&report);
        assert_eq!(text.lines().count(), 4 + report.maps.len());
        assert!(text.contains("| L01 |") && text.contains("| Epilogue |"));
    }

    /// The regression gate (#538): no reachable ledge in any arena map or
    /// campaign level sits just above a step, just under the jump's reach or
    /// between the reach and a 1.5 m wall, unless the allow-list names it with
    /// a reason, and every allowance still matches something.
    #[test]
    fn the_ledge_gate_holds() {
        let report = scan_all().unwrap();
        let unexplained = unexplained(&report);
        assert!(
            unexplained.is_empty(),
            "ambiguous ledges:\n{}",
            unexplained.join("\n")
        );
        assert!(stale_allowances(&report).is_empty());
        assert!(ALLOWED.iter().all(|allowed| !allowed.reason.is_empty()));
    }

    #[test]
    fn the_gate_names_an_ambiguous_ledge_and_a_stale_allowance() {
        let reach = jump_reach();
        let arena = Arena {
            half: 20.0,
            solids: vec![Solid::from_center_top(0.0, 0.0, 1.0, 1.0, 1.4)],
        };
        let report = LedgeReport {
            step_up: STEP_UP,
            jump_reach: reach,
            near: NEAR,
            maps: vec![MapLedges {
                label: "Test".into(),
                name: "Crate".into(),
                solids: 1,
                ledges: scan(&arena, reach, None),
            }],
        };
        let lines = unexplained(&report);
        assert_eq!(lines.len(), 4, "{lines:?}");
        assert!(lines[0].contains("Test Crate") && lines[0].contains("FalseHope"));
        // Nothing in this report matches the real allow-list.
        assert_eq!(stale_allowances(&report).len(), ALLOWED.len());
        let allowed = Allowed {
            map: "Test",
            top: 1.4,
            extent: [-1.0, -1.0, 1.0, 1.0],
            reason: "test",
        };
        assert!(report.maps[0]
            .ledges
            .iter()
            .all(|l| allowed.covers("Test", l)));
        assert!(!allowed.covers("Other", &report.maps[0].ledges[0]));
    }

    #[test]
    fn a_flight_of_treads_is_a_stair_not_a_row_of_ledges() {
        // Three treads 0.4 m apart: their open sides from the floor rise
        // 0.8 and 1.2 m, and read as the side of a stair with the way up in
        // view. The same 1.2 m block standing alone is a marginal ledge.
        let reach = jump_reach();
        let tread = |x: f32, top: f32| Solid::from_center_top(x, 0.0, 1.0, 2.0, top);
        let flight = Arena {
            half: 20.0,
            solids: vec![tread(-2.0, 0.4), tread(0.0, 0.8), tread(2.0, 1.2)],
        };
        assert!(scan(&flight, reach, None).is_empty());
        let alone = Arena {
            half: 20.0,
            solids: vec![tread(6.0, 1.2)],
        };
        assert!(scan(&alone, reach, None)
            .iter()
            .all(|l| l.band == Band::Marginal));
    }

    #[test]
    fn only_ledges_beside_a_reachable_floor_count() {
        // A 1.4 m crate inside a sealed 3 m room and another out in the open:
        // a fighter starting outside never stands beside the first.
        let reach = jump_reach();
        let mut solids = vec![
            Solid::from_center_top(-10.0, 0.0, 1.0, 1.0, 1.4),
            Solid::from_center_top(10.0, 0.0, 1.0, 1.0, 1.4),
        ];
        for (x, z, hx, hz) in [
            (10.0, -4.0, 4.2, 0.2),
            (10.0, 4.0, 4.2, 0.2),
            (6.0, 0.0, 0.2, 4.2),
            (14.0, 0.0, 0.2, 4.2),
        ] {
            solids.push(Solid::from_center_top(x, z, hx, hz, 3.0));
        }
        let arena = Arena { half: 20.0, solids };
        let reached = Reached::flood(&arena, reach, &[[-15.0, 0.0, -15.0]]);
        assert!(reached.reaches(-15.0, -15.0, 0.0));
        assert!(!reached.reaches(10.0, 2.0, 0.0));
        // The open crate's top is reached by a jump; the room's walls are not.
        assert!(reached.reaches(-10.0, 0.0, 1.4) == (1.4 <= reach));
        assert!(!reached.reaches(6.0, 0.0, 3.0));
        let ledges = scan(&arena, reach, Some(&reached));
        assert!(!ledges.is_empty() && ledges.iter().all(|l| l.solid == 0));
        // Without the flood both crates report.
        assert!(scan(&arena, reach, None).iter().any(|l| l.solid == 1));
        // A seed outside the arena is ignored rather than indexed.
        let none = Reached::flood(&arena, reach, &[[99.0, 0.0, 0.0]]);
        assert!(!none.reaches(-15.0, -15.0, 0.0));
    }
}
