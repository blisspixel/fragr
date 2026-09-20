//! The map roster, as data.
//!
//! Every layout lives here and nothing else in the server knows what a map
//! looks like. `sim.rs` asks this module for a `MapDef` and gets bounds, a
//! spawn ring, solids and pads; `MapInfo` carries the same solids to the
//! client and to agents, so there is exactly one copy of the geometry.
//!
//! Layouts are generated from the numbers that matter (ring radii, room
//! pitch, terrace depths) rather than listed box by box, because a list of a
//! hundred and fifty boxes hides the three numbers that actually decide how a
//! map plays. The builders below are the vocabulary: a wall with doors in it,
//! a flight of steps, a terrace ring with stair notches, a pocket of cover
//! around a spawn point.
//!
//! Two rules are absolute and have broken the playtest three times when they
//! were merely remembered instead of tested. The origin must stay walkable:
//! it is the drone's spawn and the fallback when every point on the spawn ring
//! is blocked. And no solid may sit on a spawn point. `validate` and the
//! reachability flood fill in `tests.rs` assert both for every map in the
//! roster, so a layout mistake fails a test rather than a round.

use crate::movement::{Solid, WALL_TOP};
#[cfg(test)]
use crate::movement::{RADIUS, STEP_UP};
use crate::protocol::WeaponType;
use crate::sim::{ArenaPickup, MapKind, PickupKind, ARMOR_PAD_AMOUNT, HEALTH_PAD_AMOUNT};
use std::f32::consts::PI;
use std::sync::OnceLock;

mod authored;
pub(crate) use authored::encounters::EnemyPlacement;
mod runtime;
pub use authored::AuthoredMap;
pub use runtime::RuntimeMap;

/// One authored-map loader for editable files and registered bundled missions.
#[derive(Debug, Clone)]
pub enum AuthoredSource {
    File(std::path::PathBuf),
    Mission(crate::protocol::MissionId),
}

impl AuthoredSource {
    pub fn load(&self) -> std::io::Result<std::sync::Arc<AuthoredMap>> {
        match self {
            Self::File(path) => AuthoredMap::load(path),
            Self::Mission(crate::protocol::MissionId::RecallNotice) => {
                AuthoredMap::read(include_bytes!("../maps/m01-recall-notice.json").as_slice())
            }
        }
    }
}

/// Immutable collision geometry shared by live movement, navigation and the
/// wire map. Conversion from the authoring layout happens once per map.
pub(crate) fn arena(kind: MapKind) -> &'static crate::movement::Arena {
    static ARENAS: [OnceLock<crate::movement::Arena>; MapKind::ALL.len()] =
        [const { OnceLock::new() }; MapKind::ALL.len()];
    ARENAS[kind.index()].get_or_init(|| {
        let layout = def(kind);
        crate::movement::Arena {
            half: layout.half_extent,
            solids: layout.solids.clone(),
        }
    })
}

struct NavigationCache {
    maps: [OnceLock<std::sync::Arc<crate::navigation::Navigation>>; MapKind::ALL.len()],
}

impl NavigationCache {
    const fn new() -> Self {
        Self {
            maps: [const { OnceLock::new() }; MapKind::ALL.len()],
        }
    }

    fn get(&self, kind: MapKind) -> &crate::navigation::Navigation {
        self.maps[kind.index()].get_or_init(|| {
            crate::navigation::Navigation::shared(arena(kind).clone())
                .expect("the tested map roster must satisfy navigation bounds")
        })
    }

    fn prepare(&self, kind: MapKind, rotate: bool) {
        if rotate {
            for map in MapKind::ALL {
                self.get(map);
            }
        } else {
            self.get(kind);
        }
    }
}

static NAVIGATION: NavigationCache = NavigationCache::new();

pub(crate) fn navigation(kind: MapKind) -> &'static crate::navigation::Navigation {
    NAVIGATION.get(kind)
}

/// Prepare only playable maps before readiness. A fixed-map session must not
/// wait for unrelated large maps, and rotation must not build during a tick.
pub(crate) fn prepare_navigation(kind: MapKind, rotate: bool) {
    NAVIGATION.prepare(kind, rotate);
}

#[cfg(test)]
mod navigation_cache_tests {
    use super::*;

    #[test]
    fn fixed_session_prepares_only_its_map_and_reuses_it() {
        let cache = NavigationCache::new();
        let chosen = MapKind::ArenaDuel;
        cache.prepare(chosen, false);
        for map in MapKind::ALL {
            assert_eq!(cache.maps[map.index()].get().is_some(), map == chosen);
        }
        assert!(std::ptr::eq(cache.get(chosen), cache.get(chosen)));
    }

    #[test]
    fn rotation_prepares_every_map_before_play() {
        let cache = NavigationCache::new();
        cache.prepare(MapKind::ComplianceYard, true);
        assert!(cache.maps.iter().all(|map| map.get().is_some()));
    }
}

/// Everything the simulation needs to run one map.
pub(crate) struct MapDef {
    /// Half width of the playable square, centred on the origin.
    pub(crate) half_extent: f32,
    /// Radius of the ring fighters spawn on.
    pub(crate) spawn_radius: f32,
    pub(crate) solids: Vec<Solid>,
    pub(crate) pickups: Vec<ArenaPickup>,
}

// ---------------------------------------------------------------------------
// Vocabulary
// ---------------------------------------------------------------------------

/// Depth of one tread, in metres. Two metres rather than a realistic step
/// because collision is a circle of half a metre: the next tread up blocks the
/// last half metre of the one below it, so a shallower tread leaves too little
/// standing room and the reachability flood fill cannot find a foot on it.
const TREAD: f32 = 2.0;
/// Tallest riser a flight of steps uses. Under `STEP_UP`, so every tread is
/// walked onto rather than jumped onto.
const RISE: f32 = 0.5;

/// How much ground a flight climbing `from` to `to` takes up.
fn stair_length(from: f32, to: f32) -> f32 {
    treads(from, to) as f32 * TREAD
}

fn treads(from: f32, to: f32) -> usize {
    (((to - from) / RISE).ceil() as usize).max(1)
}

/// A flight of steps starting at `(x, z)` and climbing in `(dx, dz)`, which
/// must be one of the four axis directions. The first tread's near edge is at
/// the start point and the last tread's far edge is `stair_length` away, at
/// `to`, which is where the deck it serves has to begin.
fn stair_run(x: f32, z: f32, dx: f32, dz: f32, half_across: f32, from: f32, to: f32) -> Vec<Solid> {
    let n = treads(from, to);
    let rise = (to - from) / n as f32;
    let (hx, hz) = if dx != 0.0 {
        (TREAD / 2.0, half_across)
    } else {
        (half_across, TREAD / 2.0)
    };
    (0..n)
        .map(|i| {
            let along = TREAD * (i as f32 + 0.5);
            Solid::from_center_top(
                x + dx * along,
                z + dz * along,
                hx,
                hz,
                from + rise * (i as f32 + 1.0),
            )
        })
        .collect()
}

/// Which way a wall runs.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Along {
    X,
    Z,
}

/// Where the openings in a wall are: their centres along the run, and how wide
/// each one is either side of that.
#[derive(Debug, Clone, Copy)]
struct Doors<'a> {
    at: &'a [f32],
    half: f32,
}

/// A wall on `line` running between the two ends of `span`, with an opening at
/// each door. Every room in the roster is made of these, which is how "no dead
/// ends" turns into arithmetic: a room with two doors in its walls has two
/// exits by construction.
fn wall_with_doors(
    along: Along,
    line: f32,
    span: (f32, f32),
    half_thick: f32,
    top: f32,
    doors: Doors<'_>,
) -> Vec<Solid> {
    let (from, to) = span;
    let mut cuts: Vec<(f32, f32)> = doors
        .at
        .iter()
        .map(|d| (d - doors.half, d + doors.half))
        .collect();
    cuts.sort_by(|a, b| a.0.total_cmp(&b.0));
    let mut out = Vec::new();
    let mut cursor = from;
    for (lo, hi) in cuts {
        if lo > cursor + 0.05 {
            out.push(segment(along, line, cursor, lo.min(to), half_thick, top));
        }
        cursor = cursor.max(hi);
    }
    if to > cursor + 0.05 {
        out.push(segment(along, line, cursor, to, half_thick, top));
    }
    out
}

fn segment(along: Along, line: f32, a: f32, b: f32, half_thick: f32, top: f32) -> Solid {
    let mid = (a + b) * 0.5;
    let half = (b - a) * 0.5;
    match along {
        Along::X => Solid::from_center_top(mid, line, half, half_thick, top),
        Along::Z => Solid::from_center_top(line, mid, half_thick, half, top),
    }
}

/// Which side of a deck a flight of steps arrives on.
#[derive(Debug, Clone, Copy)]
enum Side {
    North,
    South,
    East,
    West,
}

/// A pocket of cover around every point on the spawn ring: a block behind, and
/// a block off each shoulder, open toward the middle of the map.
///
/// This is the load-bearing piece of every layout. When the arena doubled once
/// before and the cover did not move with it, fighters arrived in open ground
/// and the harness reported four spawn deaths in eight frags. The blocks are
/// set back far enough that the spawn point itself stays clear with a
/// fighter's radius to spare, which is the thing `validate` checks.
fn spawn_pockets(count: usize, radius: f32, out: &mut Vec<Solid>) {
    for i in 0..count {
        let angle = PI * 2.0 * (i as f32) / count as f32;
        let (ox, oz) = (angle.cos(), angle.sin());
        let (tx, tz) = (-oz, ox);
        let (sx, sz) = (ox * radius, oz * radius);
        out.push(Solid::from_center(sx + ox * 5.5, sz + oz * 5.5, 2.5, 2.5));
        out.push(Solid::from_center(sx + tx * 6.0, sz + tz * 6.0, 1.8, 1.8));
        out.push(Solid::from_center(sx - tx * 6.0, sz - tz * 6.0, 1.8, 1.8));
    }
}

/// A raised deck with a flight of steps up to it from each of `sides`. Returns
/// the deck and its stairs, so a caller gets a platform that is reachable by
/// construction rather than by hope.
fn deck_with_stairs(
    cx: f32,
    cz: f32,
    half_x: f32,
    half_z: f32,
    top: f32,
    stair_half: f32,
    sides: &[Side],
) -> Vec<Solid> {
    let mut out = vec![Solid::from_center_top(cx, cz, half_x, half_z, top)];
    for side in sides {
        let run = stair_length(0.0, top);
        let (x, z, dx, dz) = match side {
            Side::North => (cx, cz - half_z - run, 0.0, 1.0),
            Side::South => (cx, cz + half_z + run, 0.0, -1.0),
            Side::East => (cx + half_x + run, cz, -1.0, 0.0),
            Side::West => (cx - half_x - run, cz, 1.0, 0.0),
        };
        out.extend(stair_run(x, z, dx, dz, stair_half, 0.0, top));
    }
    out
}

fn weapon_pad(id: &str, weapon: WeaponType, x: f32, z: f32, floor: f32) -> ArenaPickup {
    ArenaPickup {
        claim: crate::protocol::SupplyClaim::Contested,
        id: id.to_string(),
        kind: PickupKind::Weapon(weapon),
        amount: 0,
        x,
        y: floor + 0.4,
        z,
        floor,
        available: true,
        respawn_timer: None,
    }
}

fn health_pad(id: &str, x: f32, z: f32, floor: f32) -> ArenaPickup {
    ArenaPickup {
        claim: crate::protocol::SupplyClaim::Contested,
        id: id.to_string(),
        kind: PickupKind::Health,
        amount: HEALTH_PAD_AMOUNT,
        x,
        y: floor + 0.4,
        z,
        floor,
        available: true,
        respawn_timer: None,
    }
}

fn armor_pad(id: &str, x: f32, z: f32, floor: f32) -> ArenaPickup {
    ArenaPickup {
        claim: crate::protocol::SupplyClaim::Contested,
        id: id.to_string(),
        kind: PickupKind::Armor,
        amount: ARMOR_PAD_AMOUNT,
        x,
        y: floor + 0.4,
        z,
        floor,
        available: true,
        respawn_timer: None,
    }
}

// ---------------------------------------------------------------------------
// The roster
// ---------------------------------------------------------------------------

/// Arena Duel: a municipal assembly floor, certified for use as an arena.
///
/// Rosette flow. A clear hub at the origin sits inside a broken gantry ring
/// that is a wall from the floor and a firing step from above, so the middle
/// is a room you fight into rather than a field you cross. Eight spokes run
/// out through the gantry gaps to the spawn rim. The rail sits on the north
/// gantry with nothing on it to hide behind, which is `MAP-DESIGN` rule two:
/// the best thing in the worst place.
fn arena_duel() -> MapDef {
    let half = 70.0;
    let spawn = 42.0;
    let gantry_top = 2.6;
    let mut s = Vec::with_capacity(160);

    // The gantry ring, four segments with the diagonals left open.
    for (cx, cz, hx, hz) in [
        (0.0, -19.0, 13.0, 1.8),
        (0.0, 19.0, 13.0, 1.8),
        (19.0, 0.0, 1.8, 13.0),
        (-19.0, 0.0, 1.8, 13.0),
    ] {
        s.push(Solid::from_center_top(cx, cz, hx, hz, gantry_top));
    }
    // One flight up from the hub and one from the field per segment. Inner
    // approaches form a pinwheel: crossing perpendicular flights makes their
    // taller side faces block an otherwise ordinary walk up the first tread.
    let run = stair_length(0.0, gantry_top);
    for (sx, sz, dx, dz) in [
        (7.0, -17.2 + run, 0.0, -1.0),
        (7.0, -20.8 - run, 0.0, 1.0),
        (-7.0, 17.2 - run, 0.0, 1.0),
        (-7.0, 20.8 + run, 0.0, -1.0),
        (17.2 - run, 7.0, 1.0, 0.0),
        (20.8 + run, -7.0, -1.0, 0.0),
        (-17.2 + run, -7.0, -1.0, 0.0),
        (-20.8 - run, 7.0, 1.0, 0.0),
    ] {
        s.extend(stair_run(sx, sz, dx, dz, 1.6, 0.0, gantry_top));
    }

    // Pillar ring at mid field, between the gantry and the spawn rim.
    for i in 0..8 {
        let angle = PI * 2.0 * (i as f32) / 8.0;
        s.push(Solid::from_center(
            angle.cos() * 31.0,
            angle.sin() * 31.0,
            2.0,
            2.0,
        ));
    }

    spawn_pockets(8, spawn, &mut s);

    // Outer walls set in from the boundary, so the corners are rooms.
    for (cx, cz, hx, hz) in [
        (0.0, -56.0, 18.0, 0.8),
        (0.0, 56.0, 18.0, 0.8),
        (56.0, 0.0, 0.8, 18.0),
        (-56.0, 0.0, 0.8, 18.0),
    ] {
        s.push(Solid::from_center(cx, cz, hx, hz));
    }
    for (cx, cz) in [(50.0, 50.0), (-50.0, 50.0), (50.0, -50.0), (-50.0, -50.0)] {
        s.push(Solid::from_center(cx, cz, 2.5, 2.5));
    }

    MapDef {
        half_extent: half,
        spawn_radius: spawn,
        solids: s,
        pickups: vec![
            weapon_pad("pad_rail", WeaponType::Rail, 0.0, -19.0, gantry_top),
            weapon_pad("pad_scatter", WeaponType::Scatter, -25.0, 25.0, 0.0),
            weapon_pad("pad_flechette", WeaponType::Flechette, 25.0, 25.0, 0.0),
            health_pad("pad_health_n", -25.0, -25.0, 0.0),
            health_pad("pad_health_s", 25.0, -25.0, 0.0),
            armor_pad("pad_armor", 12.0, -12.0, 0.0),
        ],
    }
}

/// Compliance Yard: a records and inspection block.
///
/// Pretzel flow, and the GoldenEye Facility answer. Nine rooms on a three by
/// three grid, every one with four doors, wrapped in a perimeter service
/// corridor that closes every loop. No sightline anywhere is longer than a
/// room and a doorway, so the scatter gun is right almost everywhere and the
/// rail is nearly furniture. The inspection gantry over the north room is the
/// only high ground, and the only place the rail earns its slot.
fn compliance_yard() -> MapDef {
    let half = 55.0;
    let spawn = 26.0;
    let thick = 0.6;
    let door = 2.5;
    let mut s = Vec::with_capacity(120);

    // Interior partitions and the block's own outer wall, on the same pitch.
    for line in [-36.0f32, -12.0, 12.0, 36.0] {
        for along in [Along::Z, Along::X] {
            s.extend(wall_with_doors(
                along,
                line,
                (-36.0, 36.0),
                thick,
                WALL_TOP,
                Doors {
                    at: &[-24.0, 0.0, 24.0],
                    half: door,
                },
            ));
        }
    }

    // The inspection gantry in the north room, with a flight at each end.
    let gantry_top = 2.8;
    s.push(Solid::from_center_top(0.0, -30.0, 8.0, 2.5, gantry_top));
    let run = stair_length(0.0, gantry_top);
    for x in [-6.0f32, 6.0] {
        s.extend(stair_run(x, -27.5 + run, 0.0, -1.0, 1.5, 0.0, gantry_top));
    }

    // Two low inspection platforms in the far corner rooms, reachable from
    // both sides so neither is a corner to die in.
    for cx in [-24.0f32, 24.0] {
        let top = 1.4;
        let run = stair_length(0.0, top);
        s.push(Solid::from_center_top(cx, 24.0, 4.0, 4.0, top));
        s.extend(stair_run(cx - 4.0 - run, 24.0, 1.0, 0.0, 1.5, 0.0, top));
        s.extend(stair_run(cx + 4.0 + run, 24.0, -1.0, 0.0, 1.5, 0.0, top));
    }

    // Filing stacks in the middle room, off the origin and off the doors.
    for (cx, cz) in [(-6.5, -6.5), (6.5, -6.5), (-6.5, 6.5), (6.5, 6.5)] {
        s.push(Solid::from_center(cx, cz, 1.6, 1.6));
    }

    // Pallets in the perimeter corridor, placed off the spawn ring rather than
    // on it: a fighter arriving in a nineteen metre corridor wants something
    // to put between itself and the far end, and nothing on the point it
    // arrives at.
    for (cx, cz) in [
        (46.0, 20.0),
        (46.0, -20.0),
        (-46.0, 20.0),
        (-46.0, -20.0),
        (20.0, 46.0),
        (-20.0, 46.0),
        (20.0, -46.0),
        (-20.0, -46.0),
    ] {
        s.push(Solid::from_center(cx, cz, 2.0, 2.0));
    }

    MapDef {
        half_extent: half,
        spawn_radius: spawn,
        solids: s,
        pickups: vec![
            weapon_pad("pad_rail", WeaponType::Rail, 0.0, -30.0, gantry_top),
            weapon_pad("pad_scatter", WeaponType::Scatter, -24.0, -24.0, 0.0),
            weapon_pad("pad_flechette", WeaponType::Flechette, 24.0, -24.0, 0.0),
            health_pad("pad_health_n", -24.0, 0.0, 0.0),
            health_pad("pad_health_s", 24.0, 0.0, 0.0),
            armor_pad("pad_armor", 0.0, 6.0, 0.0),
        ],
    }
}

/// Directive 17 Substation: a decommissioned transformer bowl, terraces still
/// numbered.
///
/// Fishbowl flow, and the Q3DM17 answer. Three square terraces step down to a
/// pit at the origin, and because a shot only has to clear the tops between
/// two fighters, every metre of the pit is visible from every metre of every
/// rim. The rail lies on the pit floor. Taking it means standing at the bottom
/// of a bowl with three terraces of people looking at you, and the way out is
/// one of eight stair notches, because falling in is fast and climbing out is
/// not.
fn directive_17() -> MapDef {
    let half = 75.0;
    let spawn = 50.0;
    let mut s = Vec::with_capacity(140);

    // Four quadrant decks around a pit, with a cross of ground corridors
    // between them on the axes. An earlier version of this map used concentric
    // terrace rings, which read beautifully and pinned the playtest agents
    // against a metre and a half of riser for forty seconds at a time: from a
    // quadrant deck every route to the bowl is either a ramp or a drop, and
    // there is no wall an agent can face and have no answer to.
    let deck_top = 3.0;
    let run = stair_length(0.0, deck_top);
    for (sx, sz) in [(1.0f32, 1.0f32), (1.0, -1.0), (-1.0, 1.0), (-1.0, -1.0)] {
        let (cx, cz) = (sx * 40.0, sz * 40.0);
        s.push(Solid::from_center_top(cx, cz, 20.0, 20.0, deck_top));
        // Three flights up each inner face rather than one. With a single
        // flight per face an agent walking at a target across the pit meets
        // three metres of deck wall and has no way to know the stairs are
        // twenty metres to its left.
        for offset in [-12.0f32, 0.0, 12.0] {
            s.extend(stair_run(
                cx + offset,
                cz - sz * (20.0 + run),
                0.0,
                sz,
                4.0,
                0.0,
                deck_top,
            ));
            s.extend(stair_run(
                cx - sx * (20.0 + run),
                cz + offset,
                sx,
                0.0,
                4.0,
                0.0,
                deck_top,
            ));
        }
    }

    // Service cover: on the decks, which is the map's tight ground, and in
    // the corridors, which are its long ones.
    for (sx, sz) in [(1.0f32, 1.0f32), (1.0, -1.0), (-1.0, 1.0), (-1.0, -1.0)] {
        s.push(Solid::from_center_top(
            sx * 52.0,
            sz * 52.0,
            5.0,
            5.0,
            deck_top + 3.5,
        ));
        s.push(Solid::from_center_top(
            sx * 30.0,
            sz * 58.0,
            3.0,
            3.0,
            deck_top + 3.5,
        ));
    }
    for (cx, cz) in [(38.0f32, 0.0f32), (-38.0, 0.0), (0.0, 38.0), (0.0, -38.0)] {
        s.push(Solid::from_center(cx, cz, 3.0, 3.0));
    }

    MapDef {
        half_extent: half,
        spawn_radius: spawn,
        solids: s,
        pickups: vec![
            weapon_pad("pad_rail", WeaponType::Rail, 0.0, -7.0, 0.0),
            weapon_pad("pad_scatter", WeaponType::Scatter, -60.0, 0.0, 0.0),
            weapon_pad("pad_flechette", WeaponType::Flechette, 60.0, 0.0, 0.0),
            health_pad("pad_health_n", -40.0, -40.0, deck_top),
            health_pad("pad_health_s", 40.0, 40.0, deck_top),
            armor_pad("pad_armor", 0.0, 7.0, 0.0),
        ],
    }
}

/// Sector 9 Transit Hall: a freight interchange.
///
/// Figure eight flow, and the Dust II answer. Two long halls either side of a
/// mid plaza, joined by three doors each way with the middle one on the
/// straight line between them, so two fighters holding forward from opposite
/// halls meet at Mid Doors after about five seconds. A service corridor runs
/// right round the outside of the building, which is what turns a chase into a
/// loop instead of a corner. The rail is on the East Hall inspection deck,
/// seen down the whole length of the hall.
fn sector_9() -> MapDef {
    let half = 100.0;
    let spawn = 55.0;
    let thick = 0.7;
    let mut s = Vec::with_capacity(120);

    // The building shell, with a service corridor between it and the boundary.
    for line in [-80.0f32, 80.0] {
        s.extend(wall_with_doors(
            Along::Z,
            line,
            (-80.0, 80.0),
            thick,
            WALL_TOP,
            Doors {
                at: &[-40.0, 40.0],
                half: 3.5,
            },
        ));
        s.extend(wall_with_doors(
            Along::X,
            line,
            (-80.0, 80.0),
            thick,
            WALL_TOP,
            Doors {
                at: &[-40.0, 0.0, 40.0],
                half: 3.5,
            },
        ));
    }
    // Mid Doors: the chokepoint, and two service doors well off the line.
    for line in [-26.0f32, 26.0] {
        s.extend(wall_with_doors(
            Along::Z,
            line,
            (-80.0, 80.0),
            thick,
            WALL_TOP,
            Doors {
                at: &[-58.0, 0.0, 58.0],
                half: 3.0,
            },
        ));
    }

    // One inspection deck per hall, placed through the origin from each other
    // rather than mirrored, so the halls read differently and still play fair.
    for (cx, cz) in [(58.0f32, 34.0f32), (-58.0, -34.0)] {
        s.extend(deck_with_stairs(
            cx,
            cz,
            8.0,
            5.0,
            2.0,
            2.5,
            &[Side::North, Side::South],
        ));
    }
    // Freight stacks down each hall.
    for (cx, cz) in [
        (40.0f32, -40.0f32),
        (66.0, -20.0),
        (44.0, 62.0),
        (-40.0, 40.0),
        (-66.0, 20.0),
        (-44.0, -62.0),
    ] {
        s.push(Solid::from_center(cx, cz, 4.0, 4.0));
    }
    // Mid, with the hub itself left open.
    for (cx, cz) in [(-12.0, -12.0), (12.0, -12.0), (-12.0, 12.0), (12.0, 12.0)] {
        s.push(Solid::from_center(cx, cz, 2.5, 2.5));
    }

    MapDef {
        half_extent: half,
        spawn_radius: spawn,
        solids: s,
        pickups: vec![
            weapon_pad("pad_rail", WeaponType::Rail, 58.0, 34.0, 2.0),
            weapon_pad("pad_scatter", WeaponType::Scatter, -58.0, -34.0, 2.0),
            weapon_pad("pad_flechette", WeaponType::Flechette, 0.0, -60.0, 0.0),
            health_pad("pad_health_n", -90.0, 0.0, 0.0),
            health_pad("pad_health_s", 90.0, 0.0, 0.0),
            armor_pad("pad_armor", 0.0, 14.0, 0.0),
        ],
    }
}

/// Reclamation Gulch: a materials recovery site between two weighbridge
/// stations.
///
/// Dumbbell flow, and the Blood Gulch answer. Two walled compounds at the ends
/// of a hundred and eighty metres of open ground, with a raised walkway inside
/// each so the defenders can see over their own wall, and two long flank
/// ridges that are the only way to cross the gulch without being visible from
/// both ends. This is the one map where the rail is king, and it sits on a
/// knoll in the open middle with no cover within twenty metres of it.
fn reclamation_gulch() -> MapDef {
    let half = 140.0;
    let spawn = 92.0;
    let mut s = Vec::with_capacity(120);

    // Two compounds, one at each end, identical and mirrored.
    for sign in [-1.0f32, 1.0] {
        let cz = 104.0 * sign;
        // Gulch-facing wall with a gate, back wall solid, flanks with gates.
        s.extend(wall_with_doors(
            Along::X,
            cz - 20.0 * sign,
            (-34.0, 34.0),
            0.8,
            WALL_TOP,
            Doors {
                at: &[0.0],
                half: 4.0,
            },
        ));
        s.extend(wall_with_doors(
            Along::X,
            cz + 20.0 * sign,
            (-34.0, 34.0),
            0.8,
            WALL_TOP,
            Doors { at: &[], half: 0.0 },
        ));
        let z_span = (
            (cz - 20.0 * sign).min(cz + 20.0 * sign),
            (cz - 20.0 * sign).max(cz + 20.0 * sign),
        );
        for x in [-34.0f32, 34.0] {
            s.extend(wall_with_doors(
                Along::Z,
                x,
                z_span,
                0.8,
                WALL_TOP,
                Doors {
                    at: &[cz],
                    half: 4.0,
                },
            ));
        }
        // The walkway along the back wall, with a flight up at each end.
        let top = 3.0;
        let run = stair_length(0.0, top);
        let deck_z = cz + 15.0 * sign;
        s.push(Solid::from_center_top(0.0, deck_z, 26.0, 3.0, top));
        for x in [-16.0f32, 16.0] {
            s.extend(stair_run(
                x,
                deck_z - (3.0 + run) * sign,
                0.0,
                sign,
                2.0,
                0.0,
                top,
            ));
        }
    }

    // The knoll in the middle of the gulch: the rail, and nowhere to hide.
    let knoll = 1.2;
    s.extend(deck_with_stairs(
        0.0,
        -14.0,
        6.0,
        6.0,
        knoll,
        2.0,
        &[Side::North, Side::South, Side::East, Side::West],
    ));

    // Flank ridges, the only covered way across.
    for sign in [-1.0f32, 1.0] {
        let cx = 62.0 * sign;
        let top = 2.0;
        let run = stair_length(0.0, top);
        s.push(Solid::from_center_top(cx, 0.0, 7.0, 62.0, top));
        for z in [-40.0f32, 0.0, 40.0] {
            s.extend(stair_run(
                cx - (7.0 + run) * sign,
                z,
                sign,
                0.0,
                2.5,
                0.0,
                top,
            ));
        }
        for z in [-24.0f32, 24.0] {
            s.extend(stair_run(
                cx + (7.0 + run) * sign,
                z,
                -sign,
                0.0,
                2.5,
                0.0,
                top,
            ));
        }
    }

    // Scrap piles scattered down the gulch.
    for (cx, cz) in [
        (-26.0f32, -52.0f32),
        (26.0, -52.0),
        (-26.0, 52.0),
        (26.0, 52.0),
        (-12.0, 34.0),
        (12.0, -34.0),
        (-96.0, 0.0),
        (96.0, 0.0),
    ] {
        s.push(Solid::from_center(cx, cz, 3.5, 3.5));
    }

    MapDef {
        half_extent: half,
        spawn_radius: spawn,
        solids: s,
        pickups: vec![
            weapon_pad("pad_rail", WeaponType::Rail, 0.0, -14.0, knoll),
            weapon_pad("pad_scatter", WeaponType::Scatter, 0.0, -100.0, 0.0),
            weapon_pad("pad_flechette", WeaponType::Flechette, 0.0, 100.0, 0.0),
            health_pad("pad_health_n", -62.0, 0.0, 2.0),
            health_pad("pad_health_s", 62.0, 0.0, 2.0),
            armor_pad("pad_armor", 0.0, 20.0, 0.0),
        ],
    }
}

/// Tripoint Works: a reclamation plant where three jurisdictions meet.
///
/// Built for the three-cornered mode rather than for a duel. Three identical
/// compounds at a hundred and twenty degrees to each other, three capture
/// yards on the arcs between them, and a plaza in the middle that everything
/// is fastest through. The three-way problem is that whoever is ahead gets
/// attacked by both of the others, so the middle is worth taking and cannot be
/// held: it is open ground with three ridge spurs looking into it and no cover
/// on it at all, so standing in it is a commitment rather than a camp.
///
/// The compounds differ inside on purpose, so you can tell whose ground you
/// are on without reading a sign. The Continuance's is a regular grid of
/// identical stencilled slabs, laid out to a pitch. The free side's is
/// scavenged: no two blocks the same size and nothing square to anything. The
/// Inheritance's is one unbroken drum with no smaller parts anywhere near it, which
/// is what an unmarked machine builds when it is not trying to be read.
///
/// The server does not yet have three-faction spawns or zone capture; the
/// geometry is here and what is still missing is written down in
/// `docs/plans/map-roster-2026.md`.
fn tripoint_works() -> MapDef {
    let half = 160.0;
    let spawn = 105.0;
    let mut s = Vec::with_capacity(180);

    // Three compounds. Same shell, three different interiors.
    for (i, angle_deg) in [90.0f32, 210.0, 330.0].into_iter().enumerate() {
        let angle = angle_deg.to_radians();
        let (bx, bz) = (angle.cos() * 118.0, angle.sin() * 118.0);
        // The shell: four walls, a gate in each, so no compound is a trap and
        // none is easier to hold than another.
        for line in [bz - 26.0, bz + 26.0] {
            s.extend(wall_with_doors(
                Along::X,
                line,
                (bx - 26.0, bx + 26.0),
                0.8,
                WALL_TOP,
                Doors {
                    at: &[bx],
                    half: 4.0,
                },
            ));
        }
        for line in [bx - 26.0, bx + 26.0] {
            s.extend(wall_with_doors(
                Along::Z,
                line,
                (bz - 26.0, bz + 26.0),
                0.8,
                WALL_TOP,
                Doors {
                    at: &[bz],
                    half: 4.0,
                },
            ));
        }
        // A firing walkway inside every compound, same height, same two ways
        // up, so all three are equally defensible.
        s.extend(deck_with_stairs(
            bx,
            bz - 18.0,
            12.0,
            3.0,
            2.0,
            2.0,
            &[Side::East, Side::West],
        ));
        match i {
            // Continuance: a grid, to pitch, every slab the same.
            0 => {
                for dx in [-10.0f32, 10.0] {
                    for dz in [2.0f32, 14.0] {
                        s.push(Solid::from_center(bx + dx, bz + dz, 3.0, 2.0));
                    }
                }
            }
            // The free side: scavenged, no two alike, nothing square to
            // anything else.
            1 => {
                for (dx, dz, hx, hz) in [
                    (-13.0f32, 3.0f32, 4.5f32, 1.8f32),
                    (-2.0, 12.0, 2.2, 3.6),
                    (9.0, 1.0, 3.1, 2.7),
                    (14.0, 13.0, 1.6, 4.4),
                    (0.0, -2.0, 2.8, 1.5),
                ] {
                    s.push(Solid::from_center(bx + dx, bz + dz, hx, hz));
                }
            }
            // The Inheritance: one drum, no seams, no smaller parts.
            _ => s.push(Solid::from_center(bx, bz + 8.0, 9.0, 9.0)),
        }
    }

    // Three capture yards on the arcs between the compounds. Each is a raised
    // pad with three ways up and four flanking blocks, so taking one is a
    // three-sided problem rather than a doorway.
    for angle_deg in [30.0f32, 150.0, 270.0] {
        let angle = angle_deg.to_radians();
        let (zx, zz) = (angle.cos() * 62.0, angle.sin() * 62.0);
        s.extend(deck_with_stairs(
            zx,
            zz,
            8.0,
            8.0,
            2.0,
            2.5,
            &[Side::North, Side::East, Side::West],
        ));
        for (dx, dz) in [(-17.0, -17.0), (17.0, -17.0), (-17.0, 17.0), (17.0, 17.0)] {
            s.push(Solid::from_center(zx + dx, zz + dz, 3.0, 3.0));
        }
    }

    // Three ridge spurs looking into the middle, with wide gaps between them,
    // so the plaza is covered from three sides and campable from none.
    for angle_deg in [90.0f32, 210.0, 330.0] {
        let angle = angle_deg.to_radians();
        let (rx, rz) = (angle.cos() * 30.0, angle.sin() * 30.0);
        s.extend(deck_with_stairs(
            rx,
            rz,
            9.0,
            9.0,
            2.0,
            2.5,
            &[Side::North, Side::South],
        ));
    }

    MapDef {
        half_extent: half,
        spawn_radius: spawn,
        solids: s,
        pickups: vec![
            weapon_pad("pad_rail", WeaponType::Rail, 0.0, -62.0, 2.0),
            weapon_pad("pad_scatter", WeaponType::Scatter, 53.7, 31.0, 2.0),
            weapon_pad("pad_flechette", WeaponType::Flechette, -53.7, 31.0, 2.0),
            health_pad("pad_health_n", 0.0, 110.0, 0.0),
            health_pad("pad_health_s", 0.0, -118.0, 0.0),
            armor_pad("pad_armor", -14.0, 0.0, 0.0),
        ],
    }
}

// ---------------------------------------------------------------------------
// Lookup
// ---------------------------------------------------------------------------

fn build(kind: MapKind) -> MapDef {
    match kind {
        MapKind::ArenaDuel => arena_duel(),
        MapKind::ComplianceYard => compliance_yard(),
        MapKind::Directive17 => directive_17(),
        MapKind::Sector9 => sector_9(),
        MapKind::ReclamationGulch => reclamation_gulch(),
        MapKind::TripointWorks => tripoint_works(),
    }
}

/// Every map, built once. Layouts are pure functions of constants, so building
/// them on first use and handing out references costs one allocation for the
/// life of the process instead of one per collision query.
pub(crate) fn def(kind: MapKind) -> &'static MapDef {
    static DEFS: OnceLock<Vec<MapDef>> = OnceLock::new();
    let defs = DEFS.get_or_init(|| MapKind::ALL.iter().copied().map(build).collect());
    &defs[kind.index()]
}

// ---------------------------------------------------------------------------
// Validation
// ---------------------------------------------------------------------------

/// What is wrong with a layout. Empty means the map is safe to play, by the
/// rules that have actually broken playtests: cover on the origin, cover on a
/// spawn point, a pad inside a wall, a pad or a spawn nobody can walk to.
#[cfg(test)]
pub(crate) fn validate(kind: MapKind) -> Vec<String> {
    let def = def(kind);
    let name = kind.name();
    let mut problems = Vec::new();

    if blocked_at(kind, 0.0, 0.0, STEP_UP) || stand_height(kind, 0.0, 0.0) != 0.0 {
        problems.push(format!("{name}: the origin is not clear, walkable floor"));
    }

    let mut clear_spawns = 0;
    let samples = 64;
    for i in 0..samples {
        let angle = PI * 2.0 * (i as f32) / samples as f32;
        let (x, z) = (
            angle.cos() * def.spawn_radius,
            angle.sin() * def.spawn_radius,
        );
        if can_stand(kind, x, z) {
            clear_spawns += 1;
        }
    }
    if clear_spawns < 8 {
        problems.push(format!(
            "{name}: only {clear_spawns} of {samples} spawn ring angles are clear"
        ));
    }
    if def.spawn_radius + RADIUS >= def.half_extent {
        problems.push(format!("{name}: the spawn ring is outside the boundary"));
    }

    for pad in &def.pickups {
        if pad.x.abs() + RADIUS > def.half_extent || pad.z.abs() + RADIUS > def.half_extent {
            problems.push(format!("{name}: pad {} is outside the boundary", pad.id));
        }
        if blocked_at(kind, pad.x, pad.z, pad.floor + STEP_UP) {
            problems.push(format!("{name}: pad {} is inside a solid", pad.id));
        }
        let stands_on = support_height(kind, pad.x, pad.z, pad.floor + STEP_UP);
        if (stands_on - pad.floor).abs() > 0.01 {
            problems.push(format!(
                "{name}: pad {} says floor {:.2} but the ground there is {stands_on:.2}",
                pad.id, pad.floor
            ));
        }
    }

    problems.extend(unreachable(kind));
    problems
}

/// The height a fighter would stand at if it were put down at `(x, z)`: the
/// top of whatever is there, or the floor. Unlike `support_height` this has no
/// ceiling, because a spawn is placed on the surface rather than arriving at
/// it from somewhere.
#[cfg(test)]
pub(crate) fn stand_height(kind: MapKind, x: f32, z: f32) -> f32 {
    support_height(kind, x, z, f32::INFINITY)
}

/// Is there room to stand at `(x, z)`? True when nothing more than a step
/// above the local surface crowds the fighter, which is the question a spawn
/// point has to answer. Asking whether the point is blocked from the base
/// floor is the wrong question on a map whose rim is a terrace.
#[cfg(test)]
pub(crate) fn can_stand(kind: MapKind, x: f32, z: f32) -> bool {
    !blocked_at(kind, x, z, stand_height(kind, x, z) + STEP_UP)
}

/// Blocked for a fighter that can climb to `climb`.
#[cfg(test)]
pub(crate) fn blocked_at(kind: MapKind, x: f32, z: f32, climb: f32) -> bool {
    arena(kind).blocked_at(x, z, climb)
}

/// The surface under `(x, z)` for a fighter that can reach `ceiling`.
pub(crate) fn support_height(kind: MapKind, x: f32, z: f32, ceiling: f32) -> f32 {
    arena(kind).support_height(x, z, ceiling)
}

/// A two and a half dimensional flood fill from the origin, stepping up and
/// down by the same rules the movement step uses, reporting anything a fighter
/// cannot walk to. This is the test that catches a sealed room, a deck with no
/// stairs, and a pit nobody can climb out of, before the playtest does.
#[cfg(test)]
pub(crate) fn unreachable(kind: MapKind) -> Vec<String> {
    let def = def(kind);
    let cell = 1.0f32;
    let span = (def.half_extent / cell).floor() as i32;
    let width = (span * 2 + 1) as usize;
    let index = |ix: i32, iz: i32| ((iz + span) as usize) * width + (ix + span) as usize;
    // Highest floor reached in each cell; -1 means never reached.
    let mut reached = vec![-1.0f32; width * width];
    let mut queue = std::collections::VecDeque::new();
    reached[index(0, 0)] = 0.0;
    queue.push_back((0i32, 0i32, 0.0f32));
    while let Some((ix, iz, floor)) = queue.pop_front() {
        if reached[index(ix, iz)] > floor + 0.01 {
            continue;
        }
        for (dx, dz) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
            let (nx, nz) = (ix + dx, iz + dz);
            if nx.abs() > span || nz.abs() > span {
                continue;
            }
            let (wx, wz) = (nx as f32 * cell, nz as f32 * cell);
            let climb = floor + STEP_UP;
            if blocked_at(kind, wx, wz, climb) {
                continue;
            }
            let next = support_height(kind, wx, wz, climb);
            if reached[index(nx, nz)] >= next - 0.01 && reached[index(nx, nz)] >= 0.0 {
                continue;
            }
            reached[index(nx, nz)] = next;
            queue.push_back((nx, nz, next));
        }
    }

    let name = kind.name();
    let mut problems = Vec::new();
    let at = |x: f32, z: f32| -> Option<f32> {
        let ix = (x / cell).round() as i32;
        let iz = (z / cell).round() as i32;
        if ix.abs() > span || iz.abs() > span {
            return None;
        }
        let v = reached[index(ix, iz)];
        (v >= 0.0).then_some(v)
    };
    for pad in &def.pickups {
        match at(pad.x, pad.z) {
            None => problems.push(format!("{name}: pad {} is unreachable", pad.id)),
            Some(floor) if (floor - pad.floor).abs() > STEP_UP => problems.push(format!(
                "{name}: pad {} sits at {:.2} but is only reachable at {floor:.2}",
                pad.id, pad.floor
            )),
            Some(_) => {}
        }
    }
    let mut reachable_spawns = 0;
    for i in 0..16 {
        let angle = PI * 2.0 * (i as f32) / 16.0;
        let (x, z) = (
            angle.cos() * def.spawn_radius,
            angle.sin() * def.spawn_radius,
        );
        if can_stand(kind, x, z) && at(x, z).is_some() {
            reachable_spawns += 1;
        }
    }
    if reachable_spawns < 8 {
        problems.push(format!(
            "{name}: only {reachable_spawns} of 16 spawn points are reachable from the origin"
        ));
    }
    problems
}
