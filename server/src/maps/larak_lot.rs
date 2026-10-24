//! Larak Lot: a half-collapsed multistorey car park on the Perimeter, an old
//! black-budget range that nobody will sign off with the power still on,
//! where the league settles debts. Map id 1, the FFA and Duel home for 2 to 8.
//!
//! Five walking levels round one atrium. The centre bays fell in and became
//! the Pit (0.0), the stage. The Lane, Stands and Impound sit on level 1
//! (1.5), the Toll plaza, Bridge and Crane landing on level 2 (3.0), the
//! Gallery balcony on level 3 (4.5) and the Roof (6.0) is open to the sky.
//! The directory admits four levels and calls level 1 the lowest; the Pit is
//! the fifth, the one nobody numbered, and the Low Ramp tunnel runs down to it
//! past the Rail on its landing (0.5); the Custody Plate sits in the Roof's valet circle in
//! the opposite corner. Falling to the Rail takes about 14 s, climbing back to
//! the Plate about 17 s, so holding both is a plan rather than a habit.
//!
//! Every stair is a run of 2 m treads with a 0.5 m rise; there is no sloped
//! collision. Five slabs have a floor beneath them (the Bridge, the Low Ramp
//! lid, two bay ceilings and the Toll canopy); no pad or spawn sits under any
//! of them. The geometry is a one-to-one port of the measured box model in the
//! design spec, with the tops of a few thin parts raised past the 20 Hz jump
//! apex (about 1.3 m) so no wall top becomes a perch.
//!
//! Spawns are an explicit table rather than a ring: twelve slots, each within
//! five seconds of a weapon pad, none in sight of the Plate or the Rail, none
//! closer than ten seconds to the Plate. `tests.rs` beside this file measures
//! those gates with the server's own collision and line of sight.
use super::{armor_pad, health_pad, weapon_pad, MapDef};
use crate::movement::Solid;
use crate::protocol::{
    MapDecoration, MapDecorationKind, MapFace, MapPresentation, MapSurface, WeaponType,
};
use std::f32::consts::{FRAC_PI_2, FRAC_PI_4, PI};
use std::sync::OnceLock;

#[cfg(test)]
mod tests;

/// Half width of the playable square. The lot itself is 72 x 56 m; the strip
/// outside it is filled by the exterior wall bands.
pub(crate) const HALF: f32 = 38.0;

/// Walking levels, painted on the columns in each quarter's colour.
pub(crate) const PIT: f32 = 0.0;
pub(crate) const RAIL_LANDING: f32 = 0.5;
pub(crate) const LEVEL_1: f32 = 1.5;
pub(crate) const LEVEL_2: f32 = 3.0;
pub(crate) const LEVEL_3: f32 = 4.5;
pub(crate) const ROOF: f32 = 6.0;

/// Tops that must stay out of reach of a jump from the Roof (6.0 + 1.3).
const ROOF_WALL: f32 = 7.6;
const VALET_BARRIER: f32 = 7.4;
/// The Low Ramp's north wall: a sight screen over the lid, 1.5 m over the
/// Toll steps so no jump reaches it.
const RAMP_SCREEN: f32 = 4.0;
/// The Stands' front seat rows: 0.9 m over the deck, half cover a fighter can
/// shoot over or hop.
const STANDS_ROW: f32 = LEVEL_1 + 0.9;
/// The shear walls between the Stands and the Lane and Impound: soffit
/// height, 3.1 m over the deck and out of any jump's reach, with a 3 m door.
const SHEAR_WALL: f32 = 4.6;
const SHEAR_SOUTH: f32 = 14.0;
const SHEAR_DOOR: (f32, f32) = (19.0, 22.0);

/// The Custody Plate, the lot's power item: +100 armour to 150, the excess
/// draining a point a second, on the rule sheet's 35 s heavy plate clock.
pub(crate) const PLATE_ID: &str = "larak_custody_plate";
pub(crate) const RAIL_ID: &str = "larak_rail";
/// The Rocket Launcher in the Pit behind the Stack, free-for-all and Duel
/// only.
pub(crate) const ROCKET_ID: &str = "larak_rocket_pit";

/// Explicit spawn slots: x, floor, z, yaw. Yaw 0 faces east (+x), a quarter
/// turn faces south (+z). Each faces into its quarter's way out.
pub(crate) const SPAWNS: [[f32; 4]; 12] = [
    [-33.0, LEVEL_2, -27.0, FRAC_PI_4],      // S1 TOLL north
    [-33.5, LEVEL_2, -15.5, FRAC_PI_2],      // S2 TOLL cashier
    [-27.0, LEVEL_2, -15.0, FRAC_PI_2],      // S3 BOOTHS
    [-17.0, LEVEL_2, -23.0, 0.0],            // S4 SPIRAL foot
    [-3.0, LEVEL_3, -26.0, FRAC_PI_2],       // S5 SPIRAL landing
    [-27.5, LEVEL_1, 27.0, 3.0 * FRAC_PI_2], // S6 LANE south
    [-35.0, LEVEL_1, 21.0, 0.0],             // S7 LANE van
    [-5.0, LEVEL_1, 25.0, 3.0 * FRAC_PI_2],  // S8 STANDS west
    [7.0, LEVEL_1, 23.0, 3.0 * FRAC_PI_2],   // S9 STANDS east
    [13.0, LEVEL_1, 26.0, 3.0 * FRAC_PI_2],  // S10 IMPOUND west
    [2.5, LEVEL_1, 24.5, 3.0 * FRAC_PI_2],   // S11 STANDS tote
    [25.0, LEVEL_1, 26.0, 3.0 * FRAC_PI_2],  // S12 IMPOUND cage
];

/// One named place: an id that clients key to their own words, the ground
/// rectangle (lowest x, z to highest x, z) and the band of feet heights it
/// covers, so the Bridge and the Pit beneath it are different places.
#[cfg(test)]
#[derive(Debug, Clone, Copy)]
pub(crate) struct Callout {
    pub(crate) id: &'static str,
    pub(crate) min: [f32; 2],
    pub(crate) max: [f32; 2],
    pub(crate) floors: [f32; 2],
}

#[cfg(test)]
const fn callout(id: &'static str, min: [f32; 2], max: [f32; 2], floors: [f32; 2]) -> Callout {
    Callout {
        id,
        min,
        max,
        floors,
    }
}

/// Seventeen callouts from the fiction, most specific first. The client's
/// painted callout signs (`WORLD_LARAK_*`) mirror these ids.
#[cfg(test)]
pub(crate) const CALLOUTS: [Callout; 17] = [
    callout("stack", [3.0, 2.0], [9.5, 9.0], [0.0, 0.9]),
    callout("bridge", [-10.0, -7.4], [10.0, -5.0], [2.5, 3.5]),
    callout("pay_door", [-22.0, 9.0], [-16.0, 13.0], [0.4, 1.6]),
    callout("low_ramp", [-26.0, 2.0], [-10.0, 10.0], [0.0, 1.1]),
    callout("booths", [-32.0, -18.0], [-16.0, -12.0], [2.5, 3.5]),
    callout("sign", [24.0, -28.0], [36.0, -15.0], [5.5, 9.0]),
    callout("fire_stair", [18.0, -10.0], [30.0, -8.0], [3.2, 6.1]),
    callout("stair_b", [32.0, -10.0], [36.0, 8.0], [1.6, 6.1]),
    callout("spiral", [-10.0, -28.0], [4.0, -20.0], [3.0, 6.1]),
    callout("pit", [-10.0, -10.0], [10.0, 10.0], [0.0, 1.1]),
    callout("gallery", [-10.0, -20.0], [10.0, -10.0], [4.0, 5.0]),
    callout("roof", [4.0, -28.0], [36.0, -10.0], [5.5, 9.0]),
    callout("toll", [-36.0, -28.0], [-10.0, -4.0], [1.6, 6.0]),
    callout("crane", [10.0, -10.0], [30.0, 0.0], [2.5, 5.0]),
    callout("lane", [-36.0, -4.0], [-10.0, 28.0], [0.9, 4.0]),
    callout("stands", [-10.0, 6.0], [10.0, 28.0], [0.4, 4.0]),
    callout("impound", [10.0, 0.0], [36.0, 28.0], [0.4, 4.0]),
];

/// The callout for a fighter's feet, or none outside every named place.
#[cfg(test)]
pub(crate) fn callout_at(x: f32, floor: f32, z: f32) -> Option<&'static str> {
    CALLOUTS
        .iter()
        .find(|c| {
            x >= c.min[0]
                && x <= c.max[0]
                && z >= c.min[1]
                && z <= c.max[1]
                && floor >= c.floors[0]
                && floor <= c.floors[1]
        })
        .map(|c| c.id)
}

struct Lot {
    map: MapDef,
    presentation: MapPresentation,
}

/// Builds solids and their surface kits in one order, so the presentation can
/// never disagree with collision about which slab is which.
#[derive(Default)]
struct Builder {
    solids: Vec<Solid>,
    surfaces: Vec<MapSurface>,
    decorations: Vec<MapDecoration>,
}

impl Builder {
    /// A box from x0..x1, z0..z1, bottom..top. Returns its solid index.
    fn slab(
        &mut self,
        (x0, x1): (f32, f32),
        (z0, z1): (f32, f32),
        (bottom, top): (f32, f32),
        surface: MapSurface,
    ) -> usize {
        self.solids.push(Solid {
            min_x: x0,
            max_x: x1,
            min_z: z0,
            max_z: z1,
            bottom,
            top,
        });
        self.surfaces.push(surface);
        self.solids.len() - 1
    }

    /// A box from the ground to `top`.
    fn block(&mut self, x: (f32, f32), z: (f32, f32), top: f32, surface: MapSurface) -> usize {
        self.slab(x, z, (0.0, top), surface)
    }

    /// A flight of 2 m treads with a 0.5 m rise from `from` toward `to`,
    /// starting at the low end. The deck at `to` is the last tread, so it is
    /// not repeated. `along_x` picks the climbing axis; `rising` is the sign
    /// of the climb along it.
    fn flight(
        &mut self,
        x: (f32, f32),
        z: (f32, f32),
        (from, to): (f32, f32),
        along_x: bool,
        rising: f32,
    ) {
        let count = ((to - from) / 0.5 - 1e-4).ceil() as usize;
        for i in 0..count {
            let top = from + 0.5 * (i as f32 + 1.0);
            if top >= to - 1e-4 {
                break;
            }
            let (lo, hi) = if along_x { x } else { z };
            let start = if rising > 0.0 {
                lo + 2.0 * i as f32
            } else {
                hi - 2.0 * (i as f32 + 1.0)
            };
            let tread = (start, start + 2.0);
            if along_x {
                self.block(tread, z, top, MapSurface::ServiceSteel);
            } else {
                self.block(x, tread, top, MapSurface::ServiceSteel);
            }
        }
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

fn lot() -> &'static Lot {
    static LOT: OnceLock<Lot> = OnceLock::new();
    LOT.get_or_init(build_lot)
}

fn build_lot() -> Lot {
    use MapDecorationKind as K;
    use MapFace as F;
    use MapSurface::{Concrete, Enamel, LiftPanel, RecordsTile, ServiceSteel};
    let mut b = Builder::default();

    // Exterior shell: the office block's wall to the north-west, the Roof
    // parapets, the viaduct embankment to the south and the street walls.
    b.block((-38.0, 4.0), (-38.0, -28.0), 9.0, Concrete);
    b.block((4.0, 38.0), (-38.0, -28.0), ROOF_WALL, Concrete);
    let viaduct = b.block((-38.0, 38.0), (28.0, 38.0), 9.0, Concrete);
    let west_wall = b.block((-38.0, -36.0), (-28.0, 28.0), 9.0, Concrete);
    b.block((36.0, 38.0), (-28.0, -10.0), ROOF_WALL, Concrete);
    let east_wall = b.block((36.0, 38.0), (-10.0, 28.0), 9.0, Concrete);

    // TOLL (NW, level 2): three old toll booths under a canopy that keeps
    // the Roof from shooting down the booth lanes.
    let toll = b.block((-36.0, -10.0), (-28.0, -4.0), LEVEL_2, Concrete);
    for x in [-30.0, -24.0, -18.0] {
        b.block((x - 1.0, x + 1.0), (-17.0, -13.0), 5.8, Enamel);
    }
    let canopy = b.slab((-34.0, -12.0), (-20.0, -10.0), (6.6, 7.0), ServiceSteel);
    b.block((-15.0, -11.0), (-26.0, -24.0), 4.4, Enamel);
    b.flight((-36.0, -28.0), (-4.0, 0.0), (LEVEL_1, LEVEL_2), false, -1.0);

    // LANE (SW, level 1) and the LOW RAMP tunnel down to the Rail.
    b.block((-36.0, -26.0), (-4.0, 28.0), LEVEL_1, Concrete);
    b.block((-26.0, -10.0), (-4.0, 2.0), LEVEL_1, Concrete);
    b.block((-26.0, -21.0), (10.0, 28.0), LEVEL_1, Concrete);
    b.block((-17.0, -10.0), (10.0, 28.0), LEVEL_1, Concrete);
    b.block((-21.0, -17.0), (12.0, 28.0), LEVEL_1, Concrete);
    b.block((-21.0, -17.0), (10.0, 12.0), 1.0, ServiceSteel); // PAY DOOR tread
                                                              // The ramp's north wall stands proud of its lid, a sight screen between
                                                              // the Stands and the Toll plaza that still leaves the lid out of reach.
    b.block((-26.0, -14.0), (1.5, 2.0), RAMP_SCREEN, Concrete);
    b.block((-26.0, -21.0), (10.0, 10.5), 3.4, Concrete);
    b.block((-17.0, -14.0), (10.0, 10.5), 3.4, Concrete);
    let lid = b.slab((-24.0, -14.0), (2.0, 10.0), (3.0, 3.4), Concrete);
    b.block((-26.0, -24.0), (2.0, 10.0), 1.0, ServiceSteel);
    b.block((-24.0, -16.0), (2.0, 10.0), RAIL_LANDING, Concrete);
    let lane_ceiling = b.slab((-36.0, -26.0), (8.0, 28.0), (4.6, 5.0), Concrete);
    for z in [14.0, 22.0] {
        b.block((-27.0, -26.0), (z - 0.5, z + 0.5), 4.6, Concrete);
    }
    b.block((-34.0, -31.8), (22.0, 27.0), 3.7, RecordsTile);

    // STANDS (south, level 1) and the bleachers down into the PIT.
    b.block((-10.0, 10.0), (10.0, 28.0), LEVEL_1, Concrete);
    b.block((-10.0, 10.0), (8.0, 10.0), 1.0, ServiceSteel);
    b.block((-10.0, 10.0), (6.0, 8.0), 0.5, ServiceSteel);
    // The bookmaker's kiosk, and its tote board running back to the viaduct
    // wall, so the level-one strip along the south wall is two bays rather
    // than one 70 m lane from the Lane to the Impound.
    b.block((-2.0, 2.0), (16.0, 19.0), 4.3, ServiceSteel);
    b.block((-0.6, 0.6), (19.0, 28.0), 4.3, ServiceSteel);
    // The bettors' front row: car seats bolted to a kerb, chest high, facing
    // the Pit. Half cover on the one deck that was otherwise a flat field.
    for x in [-6.5, 6.5] {
        b.block((x - 2.5, x + 2.5), (12.6, 13.4), STANDS_ROW, Concrete);
    }
    // Shear walls between the Stands and the bays either side, each with a
    // door: level one is three rooms rather than one 70 m lane along the
    // viaduct wall, so a fighter arriving in one is not in sight of the next.
    let mut shear = Vec::new();
    for x in [(-10.6, -10.0), (10.0, 10.6)] {
        for z in [(SHEAR_SOUTH, SHEAR_DOOR.0), (SHEAR_DOOR.1, 28.0)] {
            shear.push(b.block(x, z, SHEAR_WALL, Concrete));
        }
    }
    b.panel(
        shear[1],
        MapFace::East,
        [0.0, 0.2],
        [2.4, 1.4],
        MapDecorationKind::ComplaintNotice,
    );
    b.panel(
        shear[2],
        MapFace::West,
        [0.0, 0.6],
        [1.2, 1.2],
        MapDecorationKind::Vent,
    );

    // PIT cover: THE STACK of crushed cars on a burnt tow truck, and a sedan
    // that went in nose first when the bays fell.
    b.block((4.0, 8.4), (3.0, 8.0), 3.2, RecordsTile);
    b.block((2.0, 6.4), (-4.0, -2.0), 1.4, RecordsTile);
    b.block((-10.0, -8.0), (-4.0, 1.5), 1.0, ServiceSteel); // PIT STEPS
    b.block((-8.0, -6.0), (-4.0, 1.5), 0.5, ServiceSteel);
    b.block((-16.0, -12.0), (-2.0, 0.0), 2.0, ServiceSteel); // TOLL STEPS
    b.block((-16.0, -12.0), (-4.0, -2.0), 2.5, ServiceSteel);

    // IMPOUND (SE, level 1) with the SKIDS up from the Pit.
    b.block((14.0, 36.0), (0.0, 28.0), LEVEL_1, Concrete);
    b.block((10.0, 14.0), (0.0, 2.0), LEVEL_1, Concrete);
    b.block((10.0, 14.0), (8.0, 28.0), LEVEL_1, Concrete);
    b.block((10.0, 12.0), (2.0, 8.0), 0.5, ServiceSteel);
    b.block((12.0, 14.0), (2.0, 8.0), 1.0, ServiceSteel);
    let impound_ceiling = b.slab((14.0, 36.0), (12.0, 28.0), (4.6, 5.0), Concrete);
    for x in [20.0, 28.0] {
        for z in [16.0, 24.0] {
            b.block((x - 0.3, x + 0.3), (z - 0.3, z + 0.3), 4.6, Concrete);
        }
    }
    b.block((16.0, 20.4), (19.0, 21.0), 2.9, RecordsTile);
    b.block((23.0, 27.4), (19.0, 21.0), 2.9, RecordsTile);
    let cabin = b.block((29.0, 35.0), (23.0, 27.0), 4.3, LiftPanel);

    // STAIR B: an enclosed, blind flight up the east wall to the Roof.
    let stair_b_wall = b.block((30.0, 32.0), (-10.0, 8.0), ROOF_WALL, LiftPanel);
    b.flight((32.0, 36.0), (-10.0, 8.0), (LEVEL_1, ROOF), false, -1.0);
    b.block((32.0, 36.0), (-10.0, -8.0), ROOF, ServiceSteel);

    // The VALET CIRCLE: crash barriers round the Plate with two gaps.
    b.block((25.0, 26.0), (-27.0, -23.0), VALET_BARRIER, ServiceSteel);
    b.block((25.0, 26.0), (-21.0, -16.0), VALET_BARRIER, ServiceSteel);
    b.block((26.0, 32.0), (-17.0, -16.0), VALET_BARRIER, ServiceSteel);

    // CRANE landing (east, level 2), the exposed FIRE STAIR and the stair
    // down to the Impound.
    b.block((10.0, 30.0), (-10.0, 0.0), LEVEL_2, Concrete);
    b.flight((18.0, 30.0), (-10.0, -8.0), (LEVEL_2, ROOF), true, 1.0);
    b.block((28.0, 30.0), (-10.0, -8.0), ROOF, ServiceSteel);
    b.flight((22.0, 28.0), (0.0, 6.0), (LEVEL_1, LEVEL_2), false, -1.0);
    b.block((24.0, 26.0), (-6.0, -3.0), 4.4, RecordsTile);

    // BRIDGE over the Pit, with 2.6 m of standing room beneath it. Its north
    // edge sits 2.6 m off the Gallery lip: at the arena's 6 m/s a run off the
    // lip falls short into the Pit and only a running jump carries.
    b.slab((-10.0, 10.0), (-7.4, -5.0), (2.6, LEVEL_2), ServiceSteel);

    // GALLERY (level 3) and the covered SPIRAL climb along the north wall.
    let gallery = b.block((-10.0, 10.0), (-20.0, -10.0), LEVEL_3, Concrete);
    b.flight((-10.0, -6.0), (-28.0, -20.0), (LEVEL_2, LEVEL_3), true, 1.0);
    b.block((-6.0, 0.0), (-28.0, -20.0), LEVEL_3, Concrete);
    b.flight((0.0, 4.0), (-28.0, -20.0), (LEVEL_3, ROOF), true, 1.0);

    // ROOF (NE), open to the sky: burned sedans, a Union van on its side and
    // two sodium masts.
    b.block((4.0, 36.0), (-28.0, -20.0), ROOF, Concrete);
    b.block((10.0, 36.0), (-20.0, -10.0), ROOF, Concrete);
    b.block((14.0, 18.4), (-25.0, -23.0), 7.4, RecordsTile);
    b.block((19.0, 21.2), (-17.0, -12.0), 8.2, Enamel);
    b.block((30.0, 34.4), (-26.0, -24.0), 7.4, RecordsTile);
    for (x, z) in [(12.0, -26.5), (35.0, -19.0)] {
        b.block((x - 0.2, x + 0.2), (z - 0.2, z + 0.2), 12.0, ServiceSteel);
    }

    // THE REPOSSESSION: a Union Compliance cruiser hung nose-down over the
    // Pit from the crane hook. Its underside is above any reachable head, so
    // it only stops shots, which is the point.
    b.slab((-1.0, 1.0), (-0.9, 0.9), (10.0, 14.5), Enamel);

    // Phase-one surface detail with the registered kinds. The quarter's own
    // signs, level numbers and the landmarks are presenter work.
    b.panel(lane_ceiling, F::Down, [0.0, 2.0], [0.6, 3.0], K::StripLight);
    b.panel(
        impound_ceiling,
        F::Down,
        [0.0, 0.0],
        [3.0, 0.6],
        K::StripLight,
    );
    b.panel(lid, F::Down, [-1.0, 0.0], [3.0, 0.5], K::StripLight);
    b.panel(canopy, F::Down, [0.0, 0.0], [4.0, 0.6], K::StripLight);
    // The booths' seals are the presenter's: cut through by the league and
    // unlit, so no red panel glows behind the booth lanes.
    // One Office seal stays, on the viaduct over the Impound; the north wall
    // above the Spiral belongs to the revival.
    b.panel(toll, F::South, [10.0, 0.0], [2.0, 1.6], K::ComplaintNotice);
    b.panel(
        west_wall,
        F::East,
        [-20.0, -1.0],
        [3.0, 1.6],
        K::ComplaintNotice,
    );
    b.panel(west_wall, F::East, [4.0, -2.0], [1.4, 1.4], K::Vent);
    b.panel(lane_ceiling, F::Down, [0.0, -5.0], [1.2, 1.2], K::Vent);
    b.panel(impound_ceiling, F::Down, [6.0, 3.0], [1.2, 1.2], K::Vent);
    b.panel(cabin, F::North, [-1.5, 0.2], [1.6, 2.0], K::Lockers);
    b.panel(cabin, F::West, [0.0, 0.1], [1.4, 1.2], K::Terminal);
    b.panel(
        east_wall,
        F::West,
        [-14.0, -0.5],
        [3.0, 2.0],
        K::ComplaintNotice,
    );
    b.panel(viaduct, F::North, [26.0, -1.5], [2.2, 2.2], K::UnionSeal);
    b.panel(
        stair_b_wall,
        F::West,
        [6.0, -0.5],
        [3.0, 2.0],
        K::ComplaintNotice,
    );
    b.panel(
        gallery,
        F::South,
        [-6.0, 0.0],
        [2.0, 1.4],
        K::ComplaintNotice,
    );
    b.panel(gallery, F::South, [5.0, 0.3], [1.4, 1.4], K::Vent);

    let plate = crate::sim::ArenaPickup {
        kind: crate::sim::PickupKind::Plate,
        amount: crate::sim::PLATE_AMOUNT,
        ..armor_pad(PLATE_ID, 31.0, -22.0, ROOF)
    };
    // Every pad runs the rule sheet's clock (`crate::rules`): the Plate 35 s
    // in every mode; in free-for-all the Rail and Rocket 25 s, Shotgun and
    // Rifle 15 s, health and armour 25 s; team modes their own.
    let pickups = vec![
        plate,
        weapon_pad(RAIL_ID, WeaponType::Rail, -20.0, 6.0, RAIL_LANDING),
        weapon_pad(
            "larak_scatter_booths",
            WeaponType::Scatter,
            -21.0,
            -15.0,
            LEVEL_2,
        ),
        weapon_pad(
            "larak_scatter_stairb",
            WeaponType::Scatter,
            26.0,
            10.0,
            LEVEL_1,
        ),
        weapon_pad("larak_flechette_pit", WeaponType::Flechette, -4.0, 4.0, PIT),
        weapon_pad(
            "larak_flechette_lane",
            WeaponType::Flechette,
            -31.0,
            16.0,
            LEVEL_1,
        ),
        armor_pad("larak_armor_bridge", 0.0, -6.5, LEVEL_2),
        health_pad("larak_health_toll", -33.0, -7.0, LEVEL_2),
        health_pad("larak_health_stands", 6.0, 22.0, LEVEL_1),
        health_pad("larak_health_crane", 14.0, -3.0, LEVEL_2),
    ];

    Lot {
        map: MapDef {
            half_extent: HALF,
            // Unused by the explicit spawn table; kept inside the lot so any
            // ring-based reader still lands on real floor.
            spawn_radius: 30.0,
            solids: b.solids,
            pickups,
            // Every slot is within 5 s of a gun on the lot's own pads. The
            // one free-for-all pad is the Rocket at the bottom of the Pit, in
            // the lee of the Stack: the one patch of the stage no spawn slot
            // sees, under every deck that looks in. Splash belongs in the
            // bowl, and the launcher is the way out of it again: a rocket
            // jump clears the 1.5 m from the Gallery onto the Roof and the
            // Plate. An arsenal mode's bag cannot hold the Rocket, so it is
            // laid only where lives start on the Pistol.
            scrap_pads: vec![weapon_pad(ROCKET_ID, WeaponType::Rocket, 7.5, 2.0, PIT)],
        },
        presentation: MapPresentation {
            ground: Concrete,
            solids: b.surfaces,
            decorations: b.decorations,
        },
    }
}

pub(super) fn build() -> MapDef {
    let map = &lot().map;
    MapDef {
        half_extent: map.half_extent,
        spawn_radius: map.spawn_radius,
        solids: map.solids.clone(),
        pickups: map.pickups.clone(),
        scrap_pads: map.scrap_pads.clone(),
    }
}

pub(super) fn presentation() -> &'static MapPresentation {
    &lot().presentation
}

/// The explicit spawn slot for a selection angle, still chosen through the
/// ordinary threat scoring: (x, z, yaw, floor).
pub(crate) fn spawn(angle: f32) -> (f32, f32, f32, f32) {
    let count = SPAWNS.len();
    let slot = (angle.rem_euclid(2.0 * PI) / (2.0 * PI) * count as f32).round() as usize % count;
    let [x, floor, z, yaw] = SPAWNS[slot];
    (x, z, crate::movement::normalize_yaw(yaw), floor)
}
