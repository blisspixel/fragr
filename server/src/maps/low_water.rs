//! Original Low Water town arena: clinic, repair market and a walkable tram trench.
use super::{armor_pad, health_pad, weapon_pad, MapDef, SabotageLayout};
use crate::movement::Solid;
use crate::protocol::{
    Callout, MapPresentation, MapSurface, SabotageMap, SabotageSite, SiteId, Team, WeaponType,
};
use std::f32::consts::FRAC_PI_2;
use std::sync::OnceLock;

#[cfg(test)]
mod tests;

const STREET: f32 = 3.0;
const HALF: f32 = 42.0;
struct Town {
    map: MapDef,
    presentation: MapPresentation,
}

fn town() -> &'static Town {
    static TOWN: OnceLock<Town> = OnceLock::new();
    TOWN.get_or_init(|| {
        let mut solids = Vec::new();
        let mut surfaces = Vec::new();
        let mut add = |min: [f32; 3], max: [f32; 3], surface: MapSurface| {
            solids.push(Solid {
                min_x: min[0],
                min_z: min[2],
                max_x: max[0],
                max_z: max[2],
                bottom: min[1],
                top: max[1],
            });
            surfaces.push(surface);
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
        // Civilian homes and clinic/depot footprints. No inaccessible inside
        // room or cosmetic collider is required by an objective.
        for (left, right) in [(-40.0, -34.0), (34.0, 40.0)] {
            for (near, far) in [(-28.0, -19.0), (18.0, 28.0)] {
                add([left, STREET, near], [right, 9.0, far], MapSurface::Enamel);
            }
        }
        add(
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
        // Repair stalls divide the long lanes. Their awnings retain standing
        // clearance and their backs stop an end-to-end spawn shot.
        for x in [-12.0, 12.0] {
            for z in [-18.0, 15.0] {
                add(
                    [x - 3.0, STREET, z - 3.0],
                    [x + 3.0, 4.0, z - 2.0],
                    MapSurface::Enamel,
                );
                add(
                    [x - 3.0, 5.6, z - 3.0],
                    [x + 3.0, 5.9, z + 3.0],
                    MapSurface::ServiceSteel,
                );
                add(
                    [x - 3.0, STREET, z + 2.7],
                    [x + 3.0, 5.6, z + 3.0],
                    MapSurface::Enamel,
                );
            }
        }
        // Clock and notice faces explain the market. The offset clock is also
        // a sight break between muster exits without obstructing the trench.
        add([-3.0, STREET, 9.0], [3.0, 8.0, 12.0], MapSurface::Enamel);
        add([-4.0, STREET, -14.0], [4.0, 5.8, -12.0], MapSurface::Enamel);
        // Short checkpoint screens prevent the five starting bodies seeing
        // the other side. Each has exits on both ends.
        add(
            [-9.0, STREET, 25.0],
            [9.0, 5.8, 26.0],
            MapSurface::ServiceSteel,
        );
        add([-9.0, STREET, -27.0], [9.0, 5.8, -26.0], MapSurface::Enamel);
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
                22.0,
                26.0,
                STREET,
            ),
            weapon_pad(
                "low_water_trench_scatter",
                WeaponType::Scatter,
                -10.0,
                0.0,
                0.0,
            ),
            weapon_pad("low_water_bridge_rail", WeaponType::Rail, 8.0, 0.0, STREET),
            health_pad("low_water_clinic_health", -24.0, 25.0, STREET),
            health_pad("low_water_market_health", 24.0, -25.0, STREET),
            armor_pad("low_water_trench_armor", 14.0, 0.0, 0.0),
        ];
        Town {
            map: MapDef {
                half_extent: HALF,
                spawn_radius: 34.0,
                solids,
                pickups,
            },
            presentation: MapPresentation {
                ground: MapSurface::ServiceSteel,
                solids: surfaces,
                decorations: vec![],
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
                point(-22.0, 12.0),
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
