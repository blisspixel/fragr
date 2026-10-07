//! Original island test venue: a horseshoe around a revetted lagoon.
use super::*;

pub(crate) const LAND_HEIGHT: f32 = 3.0;
pub(crate) const WATER: [crate::protocol::WaterRegion; 5] = [
    crate::protocol::WaterRegion {
        min: [-220.0, -220.0],
        max: [-160.0, 220.0],
        level: 2.2,
        depth: 2.2,
    },
    crate::protocol::WaterRegion {
        min: [160.0, -220.0],
        max: [220.0, 220.0],
        level: 2.2,
        depth: 2.2,
    },
    crate::protocol::WaterRegion {
        min: [-160.0, -220.0],
        max: [160.0, -140.0],
        level: 2.2,
        depth: 2.2,
    },
    crate::protocol::WaterRegion {
        min: [-160.0, 140.0],
        max: [160.0, 220.0],
        level: 2.2,
        depth: 2.2,
    },
    crate::protocol::WaterRegion {
        min: [-64.0, 20.0],
        max: [64.0, 140.0],
        level: 2.2,
        depth: 2.2,
    },
];

pub(super) fn build() -> MapDef {
    let mut solids = Vec::new();
    for (x, z) in [
        (-128.0, 64.0),
        (-124.0, -32.0),
        (124.0, -32.0),
        (128.0, 65.0),
    ] {
        solids.extend(wall_with_doors(
            Along::X,
            z - 13.0,
            (x - 12.0, x + 12.0),
            0.7,
            5.0,
            Doors {
                at: &[x],
                half: 3.0,
            },
        ));
        solids.extend(wall_with_doors(
            Along::X,
            z + 13.0,
            (x - 12.0, x + 12.0),
            0.7,
            5.0,
            Doors {
                at: &[x],
                half: 3.0,
            },
        ));
        solids.push(Solid::from_center_top(x - 12.0, z, 0.7, 13.0, 5.0));
        solids.push(Solid::from_center_top(x + 12.0, z, 0.7, 13.0, 5.0));
    }
    // Airfield hangars and terminal shoulders. The broad east-west runway
    // and its parallel service lane remain clear for the first jeep loop.
    for x in [-42.0, 42.0] {
        solids.push(Solid::from_center_top(x, -95.0, 14.0, 2.0, 7.0));
        solids.push(Solid::from_center_top(x - 14.0, -84.0, 1.0, 11.0, 7.0));
        solids.push(Solid::from_center_top(x + 14.0, -84.0, 1.0, 11.0, 7.0));
        solids.push(Solid::from_center_top(x, -33.0, 10.0, 5.0, 3.0));
    }
    // Low coastal works provide infantry cover without blocking the roads at
    // x +/-100 or the central cross-island route at z -60.
    for x in [-80.0, 80.0] {
        for z in [-110.0, -12.0, 46.0, 108.0] {
            solids.push(Solid::from_center_top(x, z, 4.0, 2.0, 1.1));
        }
    }
    solids.push(Solid::from_center_top(127.0, 112.0, 4.0, 4.0, 18.0));
    for solid in &mut solids {
        solid.bottom += LAND_HEIGHT;
        solid.top += LAND_HEIGHT;
    }
    // Real land above the shared seabed. Four broad beach steps keep every
    // shoreline recoverable on foot, including after losing a boat.
    for (low, high) in [
        ([-160.0, -140.0], [-64.0, 140.0]),
        ([64.0, -140.0], [160.0, 140.0]),
        ([-64.0, -140.0], [64.0, 20.0]),
    ] {
        solids.push(Solid {
            min_x: low[0],
            max_x: high[0],
            min_z: low[1],
            max_z: high[1],
            bottom: 0.0,
            top: LAND_HEIGHT,
        });
    }
    for step in 1..=5 {
        let run = step as f32 * 0.8;
        let top = LAND_HEIGHT - step as f32 * 0.5;
        for side in [-1.0, 1.0] {
            solids.push(Solid::from_center_top(
                side * (160.0 + run * 0.5),
                0.0,
                run * 0.5,
                140.0 + run,
                top,
            ));
            solids.push(Solid::from_center_top(
                side * (64.0 - run * 0.5),
                80.0,
                run * 0.5,
                60.0,
                top,
            ));
        }
        solids.push(Solid::from_center_top(
            0.0,
            -140.0 - run * 0.5,
            160.0 + run,
            run * 0.5,
            top,
        ));
        solids.push(Solid::from_center_top(
            0.0,
            20.0 + run * 0.5,
            64.0,
            run * 0.5,
            top,
        ));
        for side in [-1.0, 1.0] {
            solids.push(Solid::from_center_top(
                side * 112.0,
                140.0 + run * 0.5,
                48.0,
                run * 0.5,
                top,
            ));
        }
    }
    // Low docks meet the boat's gunwale. Access follows the beach steps.
    for side in [-1.0, 1.0] {
        solids.push(Solid::from_center_top(side * 63.0, 75.0, 3.8, 1.0, 2.2));
    }
    let mut map = MapDef {
        half_extent: 220.0,
        spawn_radius: 145.0,
        solids,
        pickups: vec![
            weapon_pad("harbour_scatter", WeaponType::Scatter, -105.0, 55.0, 0.0),
            weapon_pad(
                "village_flechette",
                WeaponType::Flechette,
                -100.0,
                -47.0,
                0.0,
            ),
            weapon_pad("airfield_rail", WeaponType::Rail, 0.0, -60.0, 0.0),
            weapon_pad("server_sniper", WeaponType::Sniper, 100.0, -47.0, 0.0),
            weapon_pad(
                "lighthouse_repeater",
                WeaponType::Repeater,
                105.0,
                55.0,
                0.0,
            ),
            health_pad("west_clinic", -128.0, -32.0, 0.0),
            health_pad("east_aid", 128.0, -32.0, 0.0),
            armor_pad("airfield_supplies", 0.0, -92.0, 0.0),
        ],
    };
    for pickup in &mut map.pickups {
        pickup.floor += LAND_HEIGHT;
        pickup.y += LAND_HEIGHT;
    }
    map
}

/// Fixed coastal spawn bays, still selected through ordinary threat scoring.
pub(crate) fn spawn(angle: f32) -> (f32, f32, f32, f32) {
    let slot = ((angle.rem_euclid(2.0 * PI) / (2.0 * PI) * 16.0).floor() as usize).min(15);
    let side = if slot < 8 { 1.0 } else { -1.0 };
    let z = -119.0 + (slot % 8) as f32 * 32.0;
    (
        side * 150.0,
        z,
        if side > 0.0 { PI } else { 0.0 },
        LAND_HEIGHT,
    )
}
