//! Compliance Yard: a Union records and inspection block. Map id 2, a small
//! free-for-all and team map for four to eight.
//!
//! Nine rooms that each do one job of the Office's compliance bureaucracy,
//! wrapped in a service corridor. The rooms differ in size and in what fills
//! them, so a player can say where they are by looking: the Records stacks
//! (staggered shelving aisles, close range), the Inspection hall (the gantry
//! and the Rail, looking into the court through an open window), the Evidence
//! lockup (a cage block to circle), the Intake queue (waist-high queue rails),
//! the Sorting court (the open middle, a raised sorting table and the armour),
//! the Relay room (a cabinet wall splitting a lane from an aisle), the
//! Weighbridge (a low platform), the Clerks' offices (two small rooms) and the
//! Dock (a loading platform).
//!
//! The partitions jog rather than run in straight lines, and no doorway
//! shares a line with the doorway across its room: the old block's aligned
//! doors made six 110 m firing lines through three rooms and the corridor.
//! Each room's exits lead to different neighbours, so a retreat is a choice.
//! The corridor is a chicane of parked trolley stacks that overlap across its
//! width, so it carries circulation rather than another long lane.
//! `tests.rs` beside this file measures the longest sightline, walks every
//! door both ways with the bots' own navigator and checks exits per room.
use super::{armor_pad, health_pad, stair_length, stair_run, weapon_pad, MapDef};
use crate::movement::{Solid, WALL_TOP};
use crate::protocol::{
    MapDecoration, MapDecorationKind, MapFace, MapPresentation, MapSurface, WeaponType,
};
use std::sync::OnceLock;

#[cfg(test)]
mod tests;

/// Half width of the playable square: the block is 72 m across inside a
/// corridor about seven and a half metres wide.
pub(crate) const HALF: f32 = 44.0;
/// The block's outer wall line.
pub(crate) const BLOCK: f32 = 36.0;
/// Half the thickness of every partition.
const THICK: f32 = 0.3;
/// Half the width of every doorway: 4.5 m openings.
const DOOR: f32 = 2.25;
/// The inspection gantry's deck.
pub(crate) const GANTRY_TOP: f32 = 2.8;
/// The court's sorting table, the Weighbridge and the Dock platform.
pub(crate) const TABLE_TOP: f32 = 1.5;
pub(crate) const PLATFORM_TOP: f32 = 1.5;
/// The window sill between the Inspection hall and the court: out of a
/// jump's reach from either floor, low enough for the gantry to see over.
pub(crate) const SILL_TOP: f32 = 2.3;
/// Shelving and cabinets: over a standing eye, under the walls.
const SHELF_TOP: f32 = 2.6;
/// Queue rails and counters: half cover.
const RAIL_TOP: f32 = 1.0;

/// A room by name, its floor rectangle (min x, min z, max x, max z).
#[cfg(test)]
pub(crate) const ROOMS: [(&str, [f32; 4]); 9] = [
    ("records", [-36.0, -36.0, -12.0, -12.0]),
    ("inspection", [-12.0, -36.0, 14.0, -16.0]),
    ("lockup", [14.0, -36.0, 36.0, -8.0]),
    ("intake", [-36.0, -12.0, -12.0, 14.0]),
    ("court", [-12.0, -16.0, 14.0, 12.0]),
    ("relay", [14.0, -8.0, 36.0, 14.0]),
    ("weighbridge", [-36.0, 14.0, -8.0, 36.0]),
    ("offices", [-8.0, 12.0, 12.0, 36.0]),
    ("dock", [12.0, 14.0, 36.0, 36.0]),
];

struct Builder {
    solids: Vec<Solid>,
    surfaces: Vec<MapSurface>,
    decorations: Vec<MapDecoration>,
}

impl Builder {
    fn add(&mut self, solid: Solid, surface: MapSurface) -> usize {
        self.solids.push(solid);
        self.surfaces.push(surface);
        self.solids.len() - 1
    }

    fn boxed(&mut self, min: [f32; 2], max: [f32; 2], top: f32, surface: MapSurface) -> usize {
        self.add(
            Solid::from_center_top(
                (min[0] + max[0]) * 0.5,
                (min[1] + max[1]) * 0.5,
                (max[0] - min[0]) * 0.5,
                (max[1] - min[1]) * 0.5,
                top,
            ),
            surface,
        )
    }

    /// An axis-aligned wall from `a` to `b` with a doorway centred on each
    /// of `doors` (absolute coordinates along the run). Returns the index of
    /// every segment, west or north first.
    fn wall(&mut self, a: [f32; 2], b: [f32; 2], doors: &[f32], surface: MapSurface) -> Vec<usize> {
        let along_x = a[1] == b[1];
        let (line, from, to) = if along_x {
            (a[1], a[0].min(b[0]), a[0].max(b[0]))
        } else {
            (a[0], a[1].min(b[1]), a[1].max(b[1]))
        };
        let along = if along_x {
            super::Along::X
        } else {
            super::Along::Z
        };
        // Extend each run by the wall's half thickness so corners close.
        super::wall_with_doors(
            along,
            line,
            (from - THICK, to + THICK),
            THICK,
            WALL_TOP,
            super::Doors {
                at: doors,
                half: DOOR,
            },
        )
        .into_iter()
        .map(|solid| self.add(solid, surface))
        .collect()
    }

    fn panel(
        &mut self,
        solid: usize,
        face: MapFace,
        center: [f32; 2],
        size: [f32; 2],
        kind: MapDecorationKind,
    ) {
        self.decorations.push(MapDecoration {
            solid,
            face,
            center,
            size,
            kind,
        });
    }
}

struct Yard {
    map: MapDef,
    presentation: MapPresentation,
}

fn yard() -> &'static Yard {
    static YARD: OnceLock<Yard> = OnceLock::new();
    YARD.get_or_init(build_yard)
}

fn build_yard() -> Yard {
    use MapSurface::{Concrete, Enamel, InspectionGlass, RecordsTile, ServiceSteel};
    let mut b = Builder {
        solids: Vec::with_capacity(160),
        surfaces: Vec::with_capacity(160),
        decorations: Vec::new(),
    };

    // The block's own outer wall. Every corridor door is off the line of the
    // partition doors inside it.
    let north = b.wall([-BLOCK, -BLOCK], [BLOCK, -BLOCK], &[-27.0, 29.0], Concrete);
    let south = b.wall(
        [-BLOCK, BLOCK],
        [BLOCK, BLOCK],
        &[-31.0, 4.5, 23.0],
        Concrete,
    );
    let west = b.wall(
        [-BLOCK, -BLOCK],
        [-BLOCK, BLOCK],
        &[-28.5, -1.0, 19.0],
        Concrete,
    );
    let east = b.wall(
        [BLOCK, -BLOCK],
        [BLOCK, BLOCK],
        &[-19.0, 7.0, 33.5],
        Concrete,
    );

    // Partitions. They jog where the rows and columns meet, so no two rooms
    // in a row share one wall line.
    let records_intake = b.wall([-BLOCK, -12.0], [-12.0, -12.0], &[-29.0], Enamel);
    b.wall([-12.0, -BLOCK], [-12.0, -12.0], &[-23.5], Enamel); // records | inspection
    let intake_court = b.wall([-12.0, -12.0], [-12.0, 14.0], &[6.0], Enamel);
    // Inspection | court: a door at the east end, and the inspection window,
    // an open bay over a sill nobody can climb, which the gantry sees over.
    let window = (-6.0, 0.5);
    b.wall([-12.0, -16.0], [window.0, -16.0], &[], Enamel);
    let sill = b.boxed(
        [window.0, -16.0 - THICK],
        [window.1, -16.0 + THICK],
        SILL_TOP,
        InspectionGlass,
    );
    b.wall([window.1, -16.0], [14.0, -16.0], &[10.5], Enamel);
    b.wall([14.0, -BLOCK], [14.0, -8.0], &[-27.0], Enamel); // inspection | lockup
    b.wall([14.0, -8.0], [14.0, 14.0], &[-3.5], Enamel); // court | relay
    b.wall([14.0, -8.0], [BLOCK, -8.0], &[18.5], Enamel); // lockup | relay
    b.wall([-BLOCK, 14.0], [-12.0, 14.0], &[-24.0], Enamel); // intake | weighbridge
    b.wall([-12.0, 12.0], [14.0, 12.0], &[3.0], Enamel); // court | offices
    b.wall([12.0, 14.0], [BLOCK, 14.0], &[31.5], Enamel); // relay | dock
    b.wall([-8.0, 12.0], [-8.0, BLOCK], &[33.0], Enamel); // weighbridge | offices
    b.wall([12.0, 12.0], [12.0, BLOCK], &[27.0], Enamel); // offices | dock

    // Records: four shelving rows, each broken twice, the breaks staggered
    // so every aisle bends and nothing sees the length of the room.
    let mut shelves = Vec::new();
    for (row, z) in [-31.0f32, -26.0, -21.0, -16.5].into_iter().enumerate() {
        let gaps: [(f32, f32); 2] = if row % 2 == 0 {
            [(-33.5, -30.0), (-22.5, -19.0)]
        } else {
            [(-28.5, -25.0), (-17.0, -12.3)]
        };
        let mut cursor = -35.7;
        for (lo, hi) in gaps.into_iter().chain([(-12.3, -12.3)]) {
            if lo > cursor + 0.5 {
                shelves.push(b.boxed([cursor, z - 0.4], [lo, z + 0.4], SHELF_TOP, RecordsTile));
            }
            cursor = hi;
        }
    }

    // Inspection: the gantry along the north wall, a flight down at each end
    // and an open front edge to drop from.
    let gantry = b.boxed([-8.0, -35.7], [10.0, -30.5], GANTRY_TOP, ServiceSteel);
    let run = stair_length(0.0, GANTRY_TOP);
    for x in [-6.5f32, 8.5] {
        for tread in stair_run(x, -30.5 + run, 0.0, -1.0, 1.5, 0.0, GANTRY_TOP) {
            b.add(tread, ServiceSteel);
        }
    }
    // An inspection bench in the hall's middle lane, cover from the window.
    b.boxed([-1.0, -24.5], [3.0, -22.5], RAIL_TOP, ServiceSteel);

    // Evidence lockup: a cage block in the middle to circle, and two
    // evidence cages against the walls.
    let cage = b.boxed([20.0, -27.0], [29.0, -18.0], WALL_TOP, RecordsTile);
    b.boxed([31.0, -35.7], [35.7, -31.0], SHELF_TOP, RecordsTile);
    b.boxed([14.3, -14.0], [17.5, -10.5], SHELF_TOP, RecordsTile);

    // Intake: a public counter and a serpentine of queue rails.
    let counter = b.boxed([-17.0, -8.0], [-15.5, 4.0], RAIL_TOP, Enamel);
    for (z, x0, x1) in [
        (-6.0f32, -33.5f32, -21.0f32),
        (-1.0, -29.0, -19.5),
        (4.0, -33.5, -21.0),
        (9.0, -29.0, -19.5),
    ] {
        b.boxed([x0, z - 0.15], [x1, z + 0.15], RAIL_TOP, ServiceSteel);
    }

    // Sorting court: the raised sorting table with a flight at each end,
    // and a confiscation cage, both off the origin (the drone's spawn).
    let table = b.boxed([-8.0, -6.0], [-3.0, 3.0], TABLE_TOP, ServiceSteel);
    let run = stair_length(0.0, TABLE_TOP);
    for tread in stair_run(-5.5, -6.0 - run, 0.0, 1.0, 2.0, 0.0, TABLE_TOP) {
        b.add(tread, ServiceSteel);
    }
    for tread in stair_run(-5.5, 3.0 + run, 0.0, -1.0, 2.0, 0.0, TABLE_TOP) {
        b.add(tread, ServiceSteel);
    }
    let court_cage = b.boxed([5.0, -11.0], [9.0, -7.0], WALL_TOP, RecordsTile);

    // Relay: a wall of relay cabinets splits the room into the west aisle and
    // the east lane, open at both ends so the room is a loop.
    let cabinets = b.boxed([23.5, -3.0], [24.5, 9.0], WALL_TOP, ServiceSteel);

    // Weighbridge: the low inspection platform, a flight from east and west.
    let deck = b.boxed([-26.0, 21.0], [-18.0, 29.0], PLATFORM_TOP, ServiceSteel);
    let run = stair_length(0.0, PLATFORM_TOP);
    for tread in stair_run(-26.0 - run, 25.0, 1.0, 0.0, 1.5, 0.0, PLATFORM_TOP) {
        b.add(tread, ServiceSteel);
    }
    for tread in stair_run(-18.0 + run, 25.0, -1.0, 0.0, 1.5, 0.0, PLATFORM_TOP) {
        b.add(tread, ServiceSteel);
    }

    // Clerks' offices: a partition with two doors makes a front and a back
    // office; desks are half cover.
    b.wall([-8.0, 24.0], [12.0, 24.0], &[-4.5, 8.0], Enamel);
    b.boxed([1.0, 16.0], [5.0, 17.2], RAIL_TOP, Enamel);
    b.boxed([-4.0, 29.5], [0.0, 30.7], RAIL_TOP, Enamel);
    let filing = b.boxed([8.0, 32.0], [11.7, 35.7], SHELF_TOP, RecordsTile);

    // Dock: the loading platform along the east wall, a flight up from the
    // Relay door, open west and south edges to drop from, and a strip of
    // floor behind it to the corridor door.
    let dock = b.boxed([26.0, 21.0], [35.7, 31.0], PLATFORM_TOP, ServiceSteel);
    let run = stair_length(0.0, PLATFORM_TOP);
    for tread in stair_run(30.5, 21.0 - run, 0.0, 1.0, 1.5, 0.0, PLATFORM_TOP) {
        b.add(tread, ServiceSteel);
    }

    // The corridor: three trolley stacks per side, alternating walls,
    // overlapping across the corridor so it reads as a chicane.
    for (along_x, sign) in [(true, -1.0f32), (true, 1.0), (false, -1.0), (false, 1.0)] {
        let inner = sign * (BLOCK + THICK);
        let outer = sign * HALF;
        for (from_inner, at) in [
            (true, -20.0f32 * sign),
            (false, 1.0 * sign),
            (true, 21.0 * sign),
        ] {
            let depth = 4.8;
            let (near, far) = if from_inner {
                (inner, inner + sign * depth)
            } else {
                (outer - sign * depth, outer)
            };
            let (lo, hi) = (near.min(far), near.max(far));
            let (min, max) = if along_x {
                ([at - 1.5, lo], [at + 1.5, hi])
            } else {
                ([lo, at - 1.5], [hi, at + 1.5])
            };
            b.boxed(min, max, 3.0, Concrete);
        }
    }

    // Guard posts fill the corridor's outer corners, so it turns rather
    // than pooling into four empty squares.
    for (sx, sz) in [(-1.0f32, -1.0f32), (1.0, -1.0), (-1.0, 1.0), (1.0, 1.0)] {
        let (x0, x1) = (sx * (HALF - 4.0), sx * HALF);
        let (z0, z1) = (sz * (HALF - 4.0), sz * HALF);
        b.boxed(
            [x0.min(x1), z0.min(z1)],
            [x0.max(x1), z0.max(z1)],
            WALL_TOP,
            Concrete,
        );
    }

    // Union paper and hardware, flush to the walls they mark: the seal over
    // the inspection window, terminals at the counter and the relay, lockers
    // in the lockup, vents, and strip lights in the rooms that need them.
    b.panel(
        sill,
        MapFace::South,
        [0.0, 0.0],
        [4.0, 1.6],
        MapDecorationKind::UnionSeal,
    );
    b.panel(
        gantry,
        MapFace::South,
        [0.0, 0.0],
        [6.0, 0.5],
        MapDecorationKind::StripLight,
    );
    b.panel(
        counter,
        MapFace::West,
        [0.0, 0.0],
        [2.0, 0.6],
        MapDecorationKind::Terminal,
    );
    b.panel(
        cage,
        MapFace::South,
        [0.0, 0.5],
        [6.0, 2.0],
        MapDecorationKind::Lockers,
    );
    b.panel(
        cage,
        MapFace::North,
        [0.0, 1.0],
        [3.0, 1.2],
        MapDecorationKind::ComplaintNotice,
    );
    b.panel(
        cabinets,
        MapFace::East,
        [0.0, 0.0],
        [2.0, 1.2],
        MapDecorationKind::Terminal,
    );
    b.panel(
        cabinets,
        MapFace::West,
        [0.0, 1.4],
        [8.0, 0.4],
        MapDecorationKind::StripLight,
    );
    b.panel(
        court_cage,
        MapFace::South,
        [0.0, 0.5],
        [2.4, 2.4],
        MapDecorationKind::UnionSeal,
    );
    b.panel(
        table,
        MapFace::East,
        [0.0, 0.0],
        [6.0, 0.4],
        MapDecorationKind::StripLight,
    );
    b.panel(
        deck,
        MapFace::North,
        [0.0, 0.0],
        [6.0, 0.4],
        MapDecorationKind::StripLight,
    );
    b.panel(
        dock,
        MapFace::West,
        [0.0, 0.0],
        [8.0, 0.4],
        MapDecorationKind::StripLight,
    );
    b.panel(
        filing,
        MapFace::North,
        [0.0, 0.2],
        [3.0, 1.6],
        MapDecorationKind::Lockers,
    );
    if let Some(&segment) = records_intake.last() {
        b.panel(
            segment,
            MapFace::South,
            [0.0, 1.2],
            [3.0, 1.2],
            MapDecorationKind::ComplaintNotice,
        );
    }
    if let Some(&segment) = intake_court.first() {
        b.panel(
            segment,
            MapFace::West,
            [0.0, 1.0],
            [2.0, 0.8],
            MapDecorationKind::Vent,
        );
    }
    if let Some(&shelf) = shelves.first() {
        b.panel(
            shelf,
            MapFace::South,
            [0.0, 0.6],
            [1.4, 0.4],
            MapDecorationKind::StripLight,
        );
    }
    for (wall, face) in [
        (&north, MapFace::South),
        (&south, MapFace::North),
        (&west, MapFace::East),
        (&east, MapFace::West),
    ] {
        if let Some(&segment) = wall.get(1) {
            b.panel(
                segment,
                face,
                [0.0, 0.8],
                [1.6, 1.6],
                MapDecorationKind::UnionSeal,
            );
        }
    }

    let pickups = vec![
        weapon_pad("pad_rail", WeaponType::Rail, -2.0, -33.0, GANTRY_TOP),
        weapon_pad("pad_scatter", WeaponType::Scatter, -24.0, -23.5, 0.0),
        weapon_pad("pad_flechette", WeaponType::Flechette, 24.5, -31.0, 0.0),
        health_pad("pad_health_n", -31.0, 1.5, 0.0),
        health_pad("pad_health_s", 31.0, 27.0, PLATFORM_TOP),
        armor_pad("pad_armor", 3.0, 6.0, 0.0),
    ];
    let scrap_pads = vec![
        weapon_pad("scrap_scatter_s", WeaponType::Scatter, 2.0, 21.0, 0.0),
        weapon_pad("scrap_scatter_n", WeaponType::Scatter, -3.0, -27.0, 0.0),
    ];
    let presentation = MapPresentation {
        ground: Concrete,
        solids: b.surfaces,
        decorations: b.decorations,
    };
    Yard {
        map: MapDef {
            half_extent: HALF,
            spawn_radius: 26.0,
            solids: b.solids,
            pickups,
            scrap_pads,
        },
        presentation,
    }
}

pub(super) fn build() -> MapDef {
    let map = &yard().map;
    MapDef {
        half_extent: map.half_extent,
        spawn_radius: map.spawn_radius,
        solids: map.solids.clone(),
        pickups: map.pickups.clone(),
        scrap_pads: map.scrap_pads.clone(),
    }
}

pub(super) fn presentation() -> &'static MapPresentation {
    &yard().presentation
}
