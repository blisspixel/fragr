//! Low Water town arena: the clinic, the repair market and the tram trench,
//! with a Union checkpoint across the south bank. Map id 8, the team and
//! Sabotage town for eight to ten.
//!
//! Two street banks stand 3 m over the dry tram trench, crossed by three
//! bridges, with a stair return at each end of each bank. The two Sabotage
//! sites are different places to take and to hold:
//!
//! - A, Clinic Steps, is a close forecourt. A low ambulance wall faces the
//!   clinic bridge, so the attack from the bridge jinks through its gate,
//!   turns west past the steps or east round the triage canopy's screen, and the west stair return
//!   comes up out of the trench right beside the site. Close range, three
//!   short ways in, hidden from both overwatch decks.
//! - B, Tram Stop, is an open platform under a shelter roof. The defence
//!   watches it from the depot's loading dock, the attack from the water tank
//!   deck across the trench. Long range, overlooked from both sides.
//!
//! The trench is a chicane, not a lane: a stopped tram against the north wall
//! and a sleeper shed against the south wall overlap across its width, two
//! bridge piers stand against alternate walls, and the tram's roof is a step
//! down from the north bank. The banks no longer
//! repeat one stall and screen four times: a repair stall and counter and the
//! water tank deck on the north bank, the canopy, the ticket kiosk, the tram
//! shelter and the dock on the south bank.
use super::{armor_pad, health_pad, stair_run, weapon_pad, MapDef, SabotageLayout};
use crate::movement::Solid;
use crate::protocol::{
    Callout, MapDecoration, MapDecorationKind, MapFace, MapPresentation, MapSurface, SabotageMap,
    SabotageSite, SiteId, Team, WeaponType,
};
use std::f32::consts::FRAC_PI_2;
use std::sync::OnceLock;

#[cfg(test)]
mod tests;

const STREET: f32 = 3.0;
const HALF: f32 = 42.0;
/// The water tank deck on the north bank, two metres over the street.
pub(crate) const TANK_DECK: f32 = 5.0;
/// The depot's loading dock on the south bank, one and a half over it.
pub(crate) const DOCK: f32 = 4.5;
/// The stopped tram's roof, half a metre under the north bank.
pub(crate) const TRAM_ROOF: f32 = 2.5;
/// The trench chicane: the tram against the north wall and the sleeper shed
/// against the south wall, overlapping across the trench (x0, z0, x1, z1).
pub(crate) const TRAM: [f32; 4] = [-17.0, -4.0, -5.0, 0.4];
pub(crate) const SHED: [f32; 4] = [12.0, -0.4, 17.0, 4.0];
/// Bridge piers, one against each trench wall (x0, z0, x1, z1).
pub(crate) const PIERS: [[f32; 4]; 2] = [[-23.0, 0.0, -21.0, 4.0], [21.0, -4.0, 23.0, 0.0]];

struct Town {
    map: MapDef,
    presentation: MapPresentation,
}

fn town() -> &'static Town {
    static TOWN: OnceLock<Town> = OnceLock::new();
    TOWN.get_or_init(|| {
        let mut solids = Vec::new();
        let mut surfaces = Vec::new();
        let mut decorations: Vec<MapDecoration> = Vec::new();
        let mut add = |min: [f32; 3], max: [f32; 3], surface: MapSurface| -> usize {
            solids.push(Solid {
                min_x: min[0],
                min_z: min[2],
                max_x: max[0],
                max_z: max[2],
                bottom: min[1],
                top: max[1],
            });
            surfaces.push(surface);
            solids.len() - 1
        };
        let mut panel = |solid: usize, face: MapFace, center: [f32; 2], size: [f32; 2], kind| {
            decorations.push(MapDecoration {
                solid,
                face,
                center,
                size,
                kind,
            });
        };
        // The street is a raised bank, so the base floor is the trench. Four
        // notches carry six ordinary half-metre treads between both banks.
        for sign in [-1.0_f32, 1.0] {
            let (near, far) = if sign < 0.0 {
                (-HALF, -16.0)
            } else {
                (16.0, HALF)
            };
            add(
                [-HALF, 0.0, near],
                [HALF, STREET, far],
                MapSurface::Concrete,
            );
            let (near, far) = if sign < 0.0 {
                (-16.0, -4.0)
            } else {
                (4.0, 16.0)
            };
            for (left, right) in [(-HALF, -32.0), (-28.0, 28.0), (32.0, HALF)] {
                add(
                    [left, 0.0, near],
                    [right, STREET, far],
                    MapSurface::Concrete,
                );
            }
            for x in [-30.0, 30.0] {
                for step in 0..6 {
                    let low = 4.0 + step as f32 * 2.0;
                    let (near, far) = if sign < 0.0 {
                        (-low - 2.0, -low)
                    } else {
                        (low, low + 2.0)
                    };
                    add(
                        [x - 2.0, 0.0, near],
                        [x + 2.0, (step + 1) as f32 * 0.5, far],
                        MapSurface::Concrete,
                    );
                }
            }
        }
        // Three bridges, with a full standing trench below. Origin stays on
        // the base floor; the middle bridge is deliberately offset from it.
        for x in [-22.0, 8.0, 22.0] {
            add(
                [x - 2.0, 2.7, -4.0],
                [x + 2.0, STREET, 4.0],
                MapSurface::ServiceSteel,
            );
        }
        // The trench chicane. The tram stands against the north wall, its
        // roof a step down from the bank; the sleeper shed against the south
        // wall is a drop from the bank into the trench.
        let tram = add(
            [TRAM[0], 0.0, TRAM[1]],
            [TRAM[2], TRAM_ROOF, TRAM[3]],
            MapSurface::ServiceSteel,
        );
        add(
            [SHED[0], 0.0, SHED[1]],
            [SHED[2], 2.0, SHED[3]],
            MapSurface::Concrete,
        );
        // Piers under the west bridge's south end and the east bridge's
        // north end, so no half of the trench runs clear between obstacles.
        for pier in PIERS {
            add(
                [pier[0], 0.0, pier[1]],
                [pier[2], 2.7, pier[3]],
                MapSurface::Concrete,
            );
        }
        // Civilian homes at the four corners and the clinic and depot wings.
        // No inaccessible inside room or cosmetic collider is required by an
        // objective.
        for (left, right) in [(-40.0, -34.0), (34.0, 40.0)] {
            for (near, far) in [(-28.0, -19.0), (18.0, 28.0)] {
                add([left, STREET, near], [right, 9.0, far], MapSurface::Enamel);
            }
        }
        let clinic = add(
            [-39.0, STREET, 10.0],
            [-34.0, 7.0, 17.0],
            MapSurface::Enamel,
        );
        add(
            [34.0, STREET, 10.0],
            [39.0, 7.0, 17.0],
            MapSurface::ServiceSteel,
        );
        // Clinic steps and depot loading kerb are routes, not raised plants.
        for (left, right) in [(-28.0, -26.0), (26.0, 28.0)] {
            add([left, STREET, 15.0], [right, 3.5, 21.0], MapSurface::Enamel);
        }
        // North bank, west: the repair stall, an L of back and side wall under
        // an awning, and the repair counter by the trench, half cover.
        let stall = add(
            [-17.0, STREET, -23.0],
            [-11.0, 5.6, -22.0],
            MapSurface::Enamel,
        );
        add(
            [-17.0, STREET, -22.0],
            [-16.0, 5.6, -17.0],
            MapSurface::Enamel,
        );
        add(
            [-17.0, 5.6, -23.0],
            [-11.0, 5.9, -17.0],
            MapSurface::ServiceSteel,
        );
        add(
            [-14.0, STREET, -9.0],
            [-10.0, STREET + 1.1, -8.0],
            MapSurface::Enamel,
        );
        // North bank, east: the water tank deck, a flight up from the west,
        // the tank on its north east corner. It looks across the trench at B.
        add(
            [10.0, STREET, -24.0],
            [18.0, TANK_DECK, -16.0],
            MapSurface::Concrete,
        );
        for tread in stair_run(2.0, -19.0, 1.0, 0.0, 1.5, STREET, TANK_DECK) {
            add(
                [tread.min_x, STREET, tread.min_z],
                [tread.max_x, tread.top, tread.max_z],
                MapSurface::Concrete,
            );
        }
        let tank = add(
            [14.0, TANK_DECK, -24.0],
            [18.0, 9.0, -20.0],
            MapSurface::ServiceSteel,
        );
        // South bank at A: the ambulance bay wall facing the clinic bridge,
        // its gate a step east of the bridge's line,
        // and the triage canopy east of the site, its east side a hung screen.
        for (west, east) in [(-24.0, -20.0), (-17.0, -14.0)] {
            add([west, STREET, 9.0], [east, 6.0, 10.0], MapSurface::Concrete);
        }
        add(
            [-10.6, STREET, 13.0],
            [-10.0, 5.6, 21.0],
            MapSurface::Enamel,
        );
        add(
            [-16.0, 5.6, 13.0],
            [-10.0, 5.9, 19.0],
            MapSurface::ServiceSteel,
        );
        for (x, z) in [(-16.0, 13.0), (-16.0, 18.4)] {
            add([x, STREET, z], [x + 0.6, 5.6, z + 0.6], MapSurface::Enamel);
        }
        // South bank at B: the ticket kiosk, the tram shelter over the stop
        // with its back wall, and the depot's loading dock with a flight up
        // from the checkpoint side.
        let kiosk = add([10.5, STREET, 13.5], [13.5, 6.0, 16.5], MapSurface::Enamel);
        add(
            [18.0, 5.6, 20.0],
            [26.0, 5.9, 25.5],
            MapSurface::ServiceSteel,
        );
        add([18.0, STREET, 25.5], [26.0, 5.6, 26.5], MapSurface::Enamel);
        add(
            [28.0, STREET, 19.0],
            [34.0, DOCK, 26.0],
            MapSurface::Concrete,
        );
        for tread in stair_run(29.5, 32.0, 0.0, -1.0, 1.5, STREET, DOCK) {
            add(
                [tread.min_x, STREET, tread.min_z],
                [tread.max_x, tread.top, tread.max_z],
                MapSurface::Concrete,
            );
        }
        // The market clock is the landmark between the banks' middles; the
        // notice board explains the market from the north.
        add([-3.0, STREET, 9.0], [3.0, 8.0, 12.0], MapSurface::Enamel);
        let notice = add([-4.0, STREET, -14.0], [4.0, 5.8, -12.0], MapSurface::Enamel);
        // Short checkpoint screens prevent the five starting bodies seeing
        // the other side. Each has exits on both ends.
        let checkpoint = add(
            [-9.0, STREET, 25.0],
            [9.0, 5.8, 26.0],
            MapSurface::ServiceSteel,
        );
        add([-9.0, STREET, -27.0], [9.0, 5.8, -26.0], MapSurface::Enamel);

        // Show, don't sign: the clinic's own sign, the tank's stencil, the
        // tram vote on the kiosk, the market notices, a circled six on the
        // tram, and one Union seal on the checkpoint.
        panel(
            clinic,
            MapFace::East,
            [0.0, 1.0],
            [4.0, 1.2],
            MapDecorationKind::M04ClinicSign,
        );
        panel(
            tank,
            MapFace::South,
            [0.0, 0.0],
            [2.4, 1.2],
            MapDecorationKind::M04WaterTank,
        );
        panel(
            kiosk,
            MapFace::North,
            [0.0, 0.2],
            [2.0, 1.6],
            MapDecorationKind::M04TramVote,
        );
        panel(
            notice,
            MapFace::North,
            [0.0, 0.0],
            [3.0, 1.6],
            MapDecorationKind::M04NoticeBoard,
        );
        panel(
            stall,
            MapFace::South,
            [0.0, 0.6],
            [3.0, 1.0],
            MapDecorationKind::M04Workshop,
        );
        panel(
            tram,
            MapFace::South,
            [3.0, 0.2],
            [1.2, 1.2],
            MapDecorationKind::M04PaintLocker,
        );
        panel(
            checkpoint,
            MapFace::North,
            [0.0, 0.0],
            [1.6, 1.6],
            MapDecorationKind::UnionSeal,
        );

        let pickups = vec![
            weapon_pad(
                "low_water_clinic_rifle",
                WeaponType::Flechette,
                -22.0,
                -22.0,
                STREET,
            ),
            weapon_pad(
                "low_water_depot_rifle",
                WeaponType::Flechette,
                31.0,
                22.5,
                DOCK,
            ),
            weapon_pad(
                "low_water_trench_scatter",
                WeaponType::Scatter,
                -11.0,
                2.2,
                0.0,
            ),
            weapon_pad("low_water_bridge_rail", WeaponType::Rail, 8.0, 0.0, STREET),
            health_pad("low_water_clinic_health", -24.0, 25.0, STREET),
            health_pad("low_water_market_health", 24.0, -25.0, STREET),
            armor_pad("low_water_trench_armor", 14.5, -2.2, 0.0),
        ];
        Town {
            map: MapDef {
                half_extent: HALF,
                spawn_radius: 34.0,
                solids,
                pickups,
                scrap_pads: vec![],
            },
            presentation: MapPresentation {
                ground: MapSurface::ServiceSteel,
                solids: surfaces,
                decorations,
            },
        }
    })
}

pub(super) fn build() -> MapDef {
    let map = &town().map;
    MapDef {
        half_extent: map.half_extent,
        spawn_radius: map.spawn_radius,
        solids: map.solids.clone(),
        pickups: map.pickups.clone(),
        scrap_pads: vec![],
    }
}

pub(super) fn presentation() -> &'static MapPresentation {
    &town().presentation
}

pub(super) fn sabotage() -> SabotageLayout {
    let point = |x, z| [x, STREET, z];
    let callout = |id: &str, min, max| Callout {
        id: id.into(),
        min,
        max,
    };
    SabotageLayout {
        wire: SabotageMap {
            attackers: Team::Coalition,
            sites: [
                SabotageSite {
                    id: SiteId::A,
                    center: point(-22.0, 18.0),
                    radius: 3.0,
                },
                SabotageSite {
                    id: SiteId::B,
                    center: point(22.0, 18.0),
                    radius: 3.0,
                },
            ],
            callouts: vec![
                callout("clinic_steps", [-27.0, 13.0], [-17.0, 23.0]),
                callout("tram_stop", [17.0, 13.0], [27.0, 23.0]),
                callout("checkpoint", [-16.0, 26.0], [16.0, 42.0]),
                callout("home_yard", [-16.0, -42.0], [16.0, -27.0]),
                callout("tram_trench", [-42.0, -4.0], [42.0, 4.0]),
                callout("market_clock", [-7.0, 7.0], [7.0, 16.0]),
                callout("clinic_lane", [-42.0, -42.0], [-16.0, 42.0]),
                callout("depot_lane", [16.0, -42.0], [42.0, 42.0]),
                callout("repair_market", [-42.0, -42.0], [42.0, 42.0]),
            ],
        },
        spawns: [
            vec![
                [-6.0, STREET, 32.0, -FRAC_PI_2],
                [6.0, STREET, 32.0, -FRAC_PI_2],
                [-3.0, STREET, 35.0, -FRAC_PI_2],
                [3.0, STREET, 35.0, -FRAC_PI_2],
                [0.0, STREET, 36.0, -FRAC_PI_2],
            ],
            vec![
                [-6.0, STREET, -32.0, FRAC_PI_2],
                [6.0, STREET, -32.0, FRAC_PI_2],
                [-3.0, STREET, -35.0, FRAC_PI_2],
                [3.0, STREET, -35.0, FRAC_PI_2],
                [0.0, STREET, -36.0, FRAC_PI_2],
            ],
        ],
        muster: [[-13.0, 28.0, 13.0, 41.0], [-13.0, -41.0, 13.0, -28.0]],
        approaches: [point(-22.0, -22.0), point(22.0, -22.0)],
        approach_needed: |at, approach| at[2] < -8.0 && (at[0] - approach[0]).abs() > 6.0,
        stages: [
            vec![
                point(-22.0, -10.0),
                point(-24.0, -10.0),
                point(-20.0, -10.0),
                point(-24.0, -13.0),
                point(-20.0, -13.0),
            ],
            vec![
                point(22.0, -10.0),
                point(24.0, -10.0),
                point(20.0, -10.0),
                point(24.0, -13.0),
                point(20.0, -13.0),
            ],
        ],
        holds: [
            vec![
                point(-21.0, 14.0),
                point(-18.0, 18.0),
                point(-22.0, 24.0),
                point(-26.0, 24.0),
                point(-17.0, 23.0),
            ],
            vec![
                point(22.0, 12.0),
                point(18.0, 18.0),
                point(22.0, 24.0),
                point(26.0, 24.0),
                point(17.0, 23.0),
            ],
        ],
        pads: [(-32.0, "coalition"), (32.0, "union")]
            .into_iter()
            .map(|(z, side)| crate::sim::ArenaPickup {
                claim: crate::protocol::SupplyClaim::Personal,
                ..weapon_pad(
                    &format!("sabotage_tack_{side}"),
                    WeaponType::Tack,
                    0.0,
                    z,
                    STREET,
                )
            })
            .collect(),
    }
}
