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
//! [`STEP_UP`] to [`FALSE_HOPE`] past the measured jump reach is reported,
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
/// How far past the reach a ledge still looks jumpable.
pub const FALSE_HOPE: f32 = NEAR;
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
        if rise <= STEP_UP + 0.001 || rise > reach + FALSE_HOPE {
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
    pub band: Band,
    pub rise_min: f32,
    pub rise_max: f32,
    pub length_m: f32,
    /// The run's midpoint on the floor outside the edge, x and z.
    pub at: [f32; 2],
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

const SIDES: [&str; 4] = ["west", "east", "north", "south"];

/// The ambiguous and jump ledges of one arena.
pub fn scan(arena: &Arena, reach: f32) -> Vec<Ledge> {
    let mut found = Vec::new();
    let limit = arena.half - RADIUS;
    for (index, solid) in arena.solids.iter().enumerate() {
        if solid.max_x - solid.min_x < MIN_TOP || solid.max_z - solid.min_z < MIN_TOP {
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
                        open.at = [(open.at[0] + ox) / 2.0, (open.at[1] + oz) / 2.0];
                    }
                    (found_band, _) => {
                        runs.extend(run.take());
                        run = found_band.map(|(band, rise)| Ledge {
                            solid: index,
                            side: name,
                            band,
                            rise_min: rise,
                            rise_max: rise,
                            length_m: SPACING,
                            at: [ox, oz],
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

/// Every arena map, then every campaign level and the epilogue.
pub fn scan_all() -> std::io::Result<LedgeReport> {
    let reach = jump_reach();
    let mut maps = Vec::new();
    for kind in MapKind::ALL {
        let arena = super::arena(kind);
        maps.push(MapLedges {
            label: format!("Map {}", kind.id()),
            name: kind.name().to_string(),
            solids: arena.solids.len(),
            ledges: scan(arena, reach),
        });
    }
    for (index, mission) in crate::protocol::MissionId::PLAYABLE.iter().enumerate() {
        let map = AuthoredSource::Mission(*mission).load()?;
        let label = if *mission == crate::protocol::MissionId::StillHere {
            "Epilogue".to_string()
        } else {
            format!("L{:02}", index + 1)
        };
        maps.push(MapLedges {
            label,
            name: map.name.clone(),
            solids: map.arena.solids.len(),
            ledges: scan(&map.arena, reach),
        });
    }
    Ok(LedgeReport {
        step_up: STEP_UP,
        jump_reach: reach,
        near: NEAR,
        maps,
    })
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
        reach + near
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
        let ledges = scan(&arena, reach);
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
        let ledges: Vec<Ledge> = scan(&arena, reach)
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
}
