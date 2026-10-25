//! The Larak Lot design gates, measured with the server's own collision, line
//! of sight and movement step rather than a second model.
//!
//! Route times come from a layered Dijkstra over one-metre cells with
//! eight-way moves at `TOP_SPEED`: a lower bound on a real fighter, who turns
//! corners and stops to shoot. The spec's box model reported the same numbers
//! before this port; `measured_table` prints the table recorded in the plan.
use super::*;
use crate::combat::line_of_sight;
use crate::movement::{Arena, MoveInput, MoveState, BODY_HEIGHT, STEP_UP, TOP_SPEED};
use crate::sim::{MapKind, PickupKind, PICKUP_CLAIM_HEIGHT};
use std::collections::{BinaryHeap, HashMap};

const DUCK_EYE: f32 = crate::movement::DUCK_EYE_HEIGHT;
const EYE: f32 = crate::movement::EYE_HEIGHT;

fn world() -> &'static Arena {
    crate::maps::arena(MapKind::ArenaDuel)
}

fn pad(id: &str) -> crate::sim::ArenaPickup {
    MapKind::ArenaDuel
        .pickups()
        .into_iter()
        .find(|p| p.id == id)
        .unwrap_or_else(|| panic!("pad {id}"))
}

fn feet(p: &crate::sim::ArenaPickup) -> [f32; 3] {
    [p.x, p.floor, p.z]
}

/// Cell key: centre x and z (each a half-integer, stored doubled) and the
/// floor height in centimetres.
type Cell = (i32, i32, i32);

fn key(x: f32, z: f32, floor: f32) -> Cell {
    (
        (x * 2.0).round() as i32,
        (z * 2.0).round() as i32,
        (floor * 100.0).round() as i32,
    )
}

#[derive(PartialEq)]
struct Entry(f32, f32, f32, f32);

impl Eq for Entry {}

impl PartialOrd for Entry {
    fn partial_cmp(&self, other: &Self) -> Option<std::cmp::Ordering> {
        Some(self.cmp(other))
    }
}

impl Ord for Entry {
    fn cmp(&self, other: &Self) -> std::cmp::Ordering {
        other.0.total_cmp(&self.0)
    }
}

/// Metres to every reachable (cell, floor) from `from` (feet).
fn distances(from: [f32; 3]) -> HashMap<Cell, f32> {
    let arena = world();
    let blocked = |x: f32, z: f32, floor: f32| {
        x.abs() > arena.half - 0.5
            || z.abs() > arena.half - 0.5
            || arena.blocked_body_at(x, z, floor, floor + STEP_UP)
    };
    let mut best = HashMap::new();
    let mut queue = BinaryHeap::new();
    // Seed every clear cell centre within a metre of the feet.
    for (x, z, offset) in near_cells(from) {
        let floor = arena.support_height(x, z, from[1] + STEP_UP);
        if blocked(x, z, floor) || (floor - from[1]).abs() > STEP_UP {
            continue;
        }
        let k = key(x, z, floor);
        if best.get(&k).is_none_or(|known| offset < *known) {
            best.insert(k, offset);
            queue.push(Entry(offset, x, z, floor));
        }
    }
    while let Some(Entry(d, x, z, floor)) = queue.pop() {
        if best.get(&key(x, z, floor)).is_some_and(|known| *known < d) {
            continue;
        }
        for (dx, dz) in [
            (1.0f32, 0.0f32),
            (-1.0, 0.0),
            (0.0, 1.0),
            (0.0, -1.0),
            (1.0, 1.0),
            (1.0, -1.0),
            (-1.0, 1.0),
            (-1.0, -1.0),
        ] {
            let (nx, nz) = (x + dx, z + dz);
            if blocked(nx, nz, floor)
                || (dx != 0.0
                    && dz != 0.0
                    && (blocked(x + dx, z, floor) || blocked(x, z + dz, floor)))
            {
                continue;
            }
            let next = arena.support_height(nx, nz, floor + STEP_UP);
            let nd = d + dx.hypot(dz);
            let k = key(nx, nz, next);
            if best.get(&k).is_none_or(|known| nd < *known) {
                best.insert(k, nd);
                queue.push(Entry(nd, nx, nz, next));
            }
        }
    }
    best
}

/// Cell centres within a metre of a point, with their distance from it.
fn near_cells(at: [f32; 3]) -> Vec<(f32, f32, f32)> {
    let mut out = Vec::new();
    for dx in [-1.0f32, 0.0, 1.0] {
        for dz in [-1.0f32, 0.0, 1.0] {
            let x = (at[0] + dx - 0.5).round() + 0.5;
            let z = (at[2] + dz - 0.5).round() + 0.5;
            let offset = (x - at[0]).hypot(z - at[2]);
            if offset <= 1.0 && !out.iter().any(|(a, b, _)| *a == x && *b == z) {
                out.push((x, z, offset));
            }
        }
    }
    out
}

/// Seconds at top speed from a distance field to `to` (feet).
fn seconds_to(field: &HashMap<Cell, f32>, to: [f32; 3]) -> f32 {
    near_cells(to)
        .into_iter()
        .flat_map(|(x, z, offset)| {
            let (kx, kz) = ((x * 2.0).round() as i32, (z * 2.0).round() as i32);
            field
                .iter()
                .filter(move |((cx, cz, floor), _)| {
                    *cx == kx && *cz == kz && (*floor as f32 / 100.0 - to[1]).abs() <= STEP_UP
                })
                .map(move |(_, d)| *d + offset)
        })
        .fold(f32::INFINITY, f32::min)
        / TOP_SPEED
}

fn spawn_feet(slot: &[f32; 4]) -> [f32; 3] {
    [slot[0], slot[1], slot[2]]
}

/// Whether a fighter at `from` (feet) can see a pad lying at `target` (feet)
/// standing or crouched, at the pad's low, middle or high glow.
fn sees(from: [f32; 3], target: [f32; 3], solids: &[Solid]) -> bool {
    [EYE, DUCK_EYE].into_iter().any(|eye| {
        [0.4, 1.0, 1.6].into_iter().any(|h| {
            line_of_sight(
                [from[0], from[1] + eye, from[2]],
                [target[0], target[1] + h, target[2]],
                solids,
            )
        })
    })
}

const SW_LANE: [f32; 3] = [-34.5, LEVEL_1, 19.5];
const NE_ROOF: [f32; 3] = [34.5, ROOF, -21.5];
const NW_TOLL: [f32; 3] = [-34.5, LEVEL_2, -26.5];
const SE_IMPOUND: [f32; 3] = [34.5, LEVEL_1, 20.5];

#[test]
fn larak_layout_validates_and_keeps_the_episode_origin_clear() {
    assert_eq!(
        crate::maps::validate(MapKind::ArenaDuel),
        Vec::<String>::new()
    );
    let origin = world().support_height(0.0, 0.0, STEP_UP);
    assert_eq!(origin, PIT);
    assert!(!world().blocked_at(0.0, 0.0, STEP_UP));
    // The painted Settlement Circle is the Episode 0 jammer ring: clear Pit.
    for i in 0..16 {
        let a = i as f32 * std::f32::consts::TAU / 16.0;
        let r = crate::sim::EP0_JAMMER_RADIUS - 1.0;
        assert_eq!(
            world().support_height(a.cos() * r, a.sin() * r, STEP_UP),
            PIT
        );
    }
    assert!(world().solids.len() < 160, "{}", world().solids.len());
}

#[test]
fn larak_every_pad_and_spawn_reachable() {
    assert_eq!(
        crate::maps::unreachable(MapKind::ArenaDuel),
        Vec::<String>::new()
    );
    let from_origin = distances([0.5, PIT, 0.5]);
    for p in MapKind::ArenaDuel.pickups() {
        assert!(
            seconds_to(&from_origin, feet(&p)).is_finite(),
            "{} unreachable",
            p.id
        );
    }
    for slot in &SPAWNS {
        assert!(
            seconds_to(&from_origin, spawn_feet(slot)).is_finite(),
            "{slot:?} unreachable"
        );
    }
}

#[test]
fn larak_pads_and_spawns_have_headroom_and_no_claim_from_above() {
    // The Rail lies in the Low Ramp tunnel and the Booths Scatter under the
    // Toll canopy by design; some spawns stand in the covered bays. Every
    // slab over one keeps more than standing room, and its top is out of
    // reach (`larak_overlaps_unreachable_tops`), so nothing is claimed or
    // spawned on from above.
    let roomy = |x: f32, z: f32, floor: f32| {
        world().ceiling_height(x, z, floor) - floor >= BODY_HEIGHT + 0.6
    };
    for p in MapKind::ArenaDuel.pickups() {
        assert!(roomy(p.x, p.z, p.floor), "{} lacks headroom", p.id);
        assert_eq!(world().support_height(p.x, p.z, p.floor + STEP_UP), p.floor);
        assert!(!world().blocked_at(p.x, p.z, p.floor + STEP_UP), "{}", p.id);
        let above = world()
            .solids
            .iter()
            .filter(|s| s.bottom > p.floor + 0.01 && s.covers(p.x, p.z))
            .map(|s| s.top - p.floor)
            .fold(f32::INFINITY, f32::min);
        assert!(
            above > PICKUP_CLAIM_HEIGHT,
            "{} is claimable from above",
            p.id
        );
    }
    for slot in &SPAWNS {
        assert!(roomy(slot[0], slot[2], slot[1]), "{slot:?}");
    }
    // Only the named overlaps cover anything at all.
    let overlaps = world().solids.iter().filter(|s| s.bottom > 0.0).count();
    assert_eq!(
        overlaps, 6,
        "Bridge, lid, two bay ceilings, canopy, cruiser"
    );
}

#[test]
fn larak_spawn_never_sees_power_item() {
    let solids = &world().solids;
    let rocket = MapKind::ArenaDuel
        .scrap_pads()
        .into_iter()
        .find(|p| p.id == ROCKET_ID)
        .expect("the Pit Rocket");
    for target in [feet(&pad(PLATE_ID)), feet(&pad(RAIL_ID)), feet(&rocket)] {
        for slot in &SPAWNS {
            assert!(
                !sees(spawn_feet(slot), target, solids),
                "spawn {slot:?} sees the power item at {target:?}"
            );
        }
    }
}

#[test]
fn larak_rail_plate_no_los() {
    let solids = &world().solids;
    let (rail, plate) = (feet(&pad(RAIL_ID)), feet(&pad(PLATE_ID)));
    assert!(!sees(rail, plate, solids));
    assert!(!sees(plate, rail, solids));
}

/// Spawn separation from the power items is a path length. The lot was laid
/// out at 5 m/s with 10 s to the Plate and 4.5 s to the Rail; the arena now
/// runs at 6 m/s (#463), which shortens every route alike, so the gate keeps
/// the authored distances rather than the seconds.
#[test]
fn larak_spawn_power_distance() {
    const PLATE_MIN_PATH: f32 = 50.0;
    const RAIL_MIN_PATH: f32 = 22.5;
    let (rail, plate) = (feet(&pad(RAIL_ID)), feet(&pad(PLATE_ID)));
    for slot in &SPAWNS {
        let field = distances(spawn_feet(slot));
        let to_plate = seconds_to(&field, plate) * TOP_SPEED;
        let to_rail = seconds_to(&field, rail) * TOP_SPEED;
        assert!(
            to_plate >= PLATE_MIN_PATH,
            "{slot:?} is {to_plate:.1} m from the Plate"
        );
        assert!(
            to_rail >= RAIL_MIN_PATH,
            "{slot:?} is {to_rail:.1} m from the Rail"
        );
    }
}

#[test]
fn larak_every_spawn_within_5s_of_weapon_pad() {
    let weapons: Vec<_> = MapKind::ArenaDuel
        .pickups()
        .into_iter()
        .filter(|p| matches!(p.kind, PickupKind::Weapon(_)))
        .collect();
    assert_eq!(weapons.len(), 5);
    for slot in &SPAWNS {
        let field = distances(spawn_feet(slot));
        let nearest = weapons
            .iter()
            .map(|w| seconds_to(&field, feet(w)))
            .fold(f32::INFINITY, f32::min);
        assert!(nearest <= 5.0, "{slot:?} is {nearest:.1} s from a weapon");
    }
}

#[test]
fn larak_corner_to_corner_under_25s() {
    let (rail, plate) = (feet(&pad(RAIL_ID)), feet(&pad(PLATE_ID)));
    for (from, to) in [
        (SW_LANE, NE_ROOF),
        (NE_ROOF, SW_LANE),
        (NW_TOLL, SE_IMPOUND),
        (SE_IMPOUND, NW_TOLL),
        (rail, plate),
        (plate, rail),
    ] {
        let t = seconds_to(&distances(from), to);
        assert!(t < 25.0, "{from:?} to {to:?} takes {t:.1} s");
        assert!(
            t > 8.0,
            "{from:?} to {to:?} is suspiciously short: {t:.1} s"
        );
    }
}

/// Seconds of the 20 Hz jump arc spent with the feet at least `rise` above
/// the take-off floor, counting the landing tick a swept fall still catches.
fn airtime_above(rise: f32) -> Option<f32> {
    let dt = crate::movement::DT_LIVE;
    let flat = Arena {
        half: 20.0,
        solids: Vec::new(),
    };
    let mut state = MoveState {
        x: 0.0,
        z: 0.0,
        y: 0.0,
        vx: 0.0,
        vz: 0.0,
        vy: 0.0,
        yaw: 0.0,
    };
    let mut last = None;
    let mut previous = 0.0f32;
    for tick in 1..40 {
        let input = MoveInput {
            jump: tick == 1,
            ..MoveInput::default()
        };
        state = crate::movement::live_step(state, &input, 0.0, dt, &flat);
        if previous >= rise || state.y >= rise {
            last = Some(tick as f32 * dt);
        }
        previous = state.y;
        if state.y <= 0.0 && tick > 1 {
            break;
        }
    }
    last
}

fn rect_gap(a: &Solid, b: &Solid) -> f32 {
    let dx = (a.min_x - b.max_x).max(b.min_x - a.max_x).max(0.0);
    let dz = (a.min_z - b.max_z).max(b.min_z - a.max_z).max(0.0);
    dx.hypot(dz)
}

#[test]
fn larak_overlaps_unreachable_tops() {
    let solids = &world().solids;
    let reach = crate::maps::Reach::from_origin(MapKind::ArenaDuel);
    // The slabs with a floor beneath them, and every wall top within a jump
    // of a deck that would otherwise become a perch.
    let perches: Vec<&Solid> = solids
        .iter()
        .filter(|s| {
            // The Bridge is a deck; every other raised slab is a lid.
            (s.bottom > 0.0 && s.top != LEVEL_2)
                || [3.4, ROOF_WALL, 9.0].contains(&s.top)
                || (s.top == RAMP_SCREEN && s.max_z - s.min_z < 1.0)
                || (s.min_x >= 36.0 || s.max_x <= -36.0 || s.min_z >= 28.0 || s.max_z <= -28.0)
        })
        .collect();
    assert!(perches.len() >= 14, "{}", perches.len());
    // Ground, plus every solid top a fighter actually reaches.
    let mut launches: Vec<Solid> = solids
        .iter()
        .copied()
        .filter(|s| {
            let cx = (s.min_x + s.max_x) * 0.5;
            let cz = (s.min_z + s.max_z) * 0.5;
            reach
                .floor_near(cx, cz, s.top)
                .is_some_and(|f| (f - s.top).abs() < 0.01)
        })
        .collect();
    launches.push(Solid {
        min_x: -HALF,
        max_x: HALF,
        min_z: -HALF,
        max_z: HALF,
        bottom: 0.0,
        top: 0.0,
    });
    for perch in perches {
        assert!(
            reach
                .floor_near(
                    (perch.min_x + perch.max_x) * 0.5,
                    (perch.min_z + perch.max_z) * 0.5,
                    perch.top
                )
                .is_none_or(|f| (f - perch.top).abs() > 0.01),
            "{perch:?} is walked onto"
        );
        for launch in &launches {
            if launch == perch || launch.top >= perch.top {
                continue;
            }
            let Some(air) = airtime_above(perch.top - launch.top) else {
                continue;
            };
            let gap = rect_gap(launch, perch);
            assert!(
                gap > air * TOP_SPEED,
                "{perch:?} is a {gap:.2} m jump from {launch:?} ({:.2} m)",
                air * TOP_SPEED
            );
        }
    }
}

/// Sixteen fighters on twelve slots: the first twelve take the table, the
/// rest find clear floor beside it, and no two bodies share a point.
#[test]
fn larak_crowded_roster_never_stacks_bodies() {
    let mut state = crate::sim::GameState::with_map(MapKind::ArenaDuel, false);
    for i in 0..16 {
        state.add_player(
            uuid::Uuid::new_v4(),
            format!("Crowd{i}"),
            crate::protocol::Role::Agent,
        );
    }
    let bodies: Vec<[f32; 3]> = state
        .players
        .iter()
        .map(|p| [p.x, p.y - crate::sim::PLAYER_FLOOR_Y, p.z])
        .collect();
    assert_eq!(bodies.len(), 16);
    for (i, a) in bodies.iter().enumerate() {
        let floor = world().support_height(a[0], a[2], a[1] + STEP_UP);
        assert!((floor - a[1]).abs() < 0.01, "fighter {i} floats at {a:?}");
        for b in &bodies[i + 1..] {
            let apart = (a[0] - b[0]).hypot(a[2] - b[2]);
            assert!(
                apart >= 2.0 * crate::sim::PLAYER_RADIUS || (a[1] - b[1]).abs() >= BODY_HEIGHT,
                "{a:?} and {b:?} overlap"
            );
        }
    }
    let on_table = bodies
        .iter()
        .filter(|a| {
            SPAWNS
                .iter()
                .any(|s| (s[0] - a[0]).abs() < 0.01 && (s[2] - a[2]).abs() < 0.01)
        })
        .count();
    assert_eq!(
        on_table,
        SPAWNS.len(),
        "every slot is used before the overflow"
    );
}

/// A respawn avoids the slot an opponent is standing beside, even round a
/// corner with no line of sight.
#[test]
fn larak_respawn_avoids_an_opponent_round_the_corner() {
    let mut state = crate::sim::GameState::with_map(MapKind::ArenaDuel, false);
    let lurker = uuid::Uuid::new_v4();
    let arriving = uuid::Uuid::new_v4();
    state.add_player(lurker, "Lurker".into(), crate::protocol::Role::Agent);
    state.add_player(arriving, "Arriving".into(), crate::protocol::Role::Agent);
    for slot in &SPAWNS {
        // Park the lurker two metres beside this slot, then respawn the other.
        let p = state.players.iter_mut().find(|p| p.id == lurker).unwrap();
        p.x = slot[0] + 2.0;
        p.z = slot[2];
        p.y = crate::sim::PLAYER_FLOOR_Y + slot[1];
        let (x, z, _, _) = state.select_spawn(arriving, None, None).unwrap();
        assert!(
            (x - slot[0]).hypot(z - slot[2]) > 0.01,
            "respawned beside the lurker at {slot:?}"
        );
        let lurker_at = (slot[0] + 2.0, slot[2]);
        assert!((x - lurker_at.0).hypot(z - lurker_at.1) > 12.0);
    }
}

#[test]
fn larak_bridge_armor_out_of_pit_claim() {
    let armor = pad("larak_armor_bridge");
    assert_eq!(armor.floor, LEVEL_2);
    // The Pit runs beneath the Bridge with standing room.
    assert_eq!(world().support_height(armor.x, armor.z, STEP_UP), PIT);
    assert!(!world().blocked_body_at(armor.x, armor.z, PIT, STEP_UP));
    assert!(armor.floor - PIT > PICKUP_CLAIM_HEIGHT);
    // The Gallery is a level higher but too far away to reach it.
    let gallery_edge = -10.0;
    assert!((armor.z - gallery_edge).abs() > crate::sim::PICKUP_CLAIM_RADIUS);

    let mut state = crate::sim::GameState::with_map(MapKind::ArenaDuel, false);
    state.config = crate::sim::MatchConfig {
        warmup_ticks: 1,
        boss_spawn_ticks: None,
        compliance_ping_ticks: None,
        ..crate::sim::MatchConfig::default()
    };
    state.start_round();
    let id = uuid::Uuid::new_v4();
    state.add_player(id, "Under".into(), crate::protocol::Role::Human);
    let place = |state: &mut crate::sim::GameState, floor: f32| {
        let p = state.players.iter_mut().find(|p| p.id == id).unwrap();
        p.x = armor.x;
        p.z = armor.z;
        p.y = crate::sim::PLAYER_FLOOR_Y + floor;
        p.armor = 0;
    };
    place(&mut state, PIT);
    state.tick(0.05);
    let claimed = |state: &crate::sim::GameState| {
        !state
            .pickups
            .iter()
            .find(|p| p.id == armor.id)
            .unwrap()
            .available
    };
    assert!(!claimed(&state), "the Bridge armour is taken from the Pit");
    place(&mut state, LEVEL_2);
    state.tick(0.05);
    assert!(claimed(&state), "the Bridge armour is taken on the Bridge");
}

/// The arena fighter model (`movement::fighter_step`, 6 m/s with momentum)
/// is what a fighter on the lot runs. A full run off the Gallery lip drops
/// into the Pit; a running jump taken before the lip carries onto the Bridge.
#[test]
fn larak_gallery_bridge_gap_jump() {
    let arena = world();
    let run = |jump_at: Option<f32>| {
        let mut state = MoveState {
            x: 2.0,
            z: -16.0,
            y: LEVEL_3,
            vx: 0.0,
            vz: 0.0,
            vy: 0.0,
            yaw: FRAC_PI_2,
        };
        let mut jumped = false;
        for _ in 0..60 {
            let jump = !jumped && jump_at.is_some_and(|at| state.z >= at);
            jumped |= jump;
            // Run along the Gallery and steer through the air; let go on
            // landing so the body stays where it came down.
            let on_gallery = state.y >= LEVEL_3 - 0.01;
            let airborne = state.vy != 0.0;
            let input = MoveInput {
                forward: on_gallery || airborne,
                jump,
                yaw: FRAC_PI_2,
                ..MoveInput::default()
            };
            state = crate::movement::fighter_step(
                state,
                &input,
                TOP_SPEED,
                crate::movement::DT_LIVE,
                arena,
            );
        }
        state
    };
    for jump_at in [-10.8, -10.5] {
        let jumped = run(Some(jump_at));
        assert_eq!(jumped.y, LEVEL_2, "the running jump lands on the Bridge");
        assert!((-7.4..=-5.0).contains(&jumped.z), "{jumped:?}");
    }
    let walked = run(None);
    assert_eq!(walked.y, PIT, "running off the Gallery drops into the Pit");
}

#[test]
fn larak_spawn_slots_wrap_and_face_their_quarter() {
    let map = crate::maps::RuntimeMap::BuiltIn(MapKind::ArenaDuel);
    assert_eq!(map.spawn_slots(), SPAWNS.len());
    let mut seen = Vec::new();
    for slot in 0..SPAWNS.len() {
        let angle = slot as f32 * std::f32::consts::TAU / SPAWNS.len() as f32;
        let point = map.spawn(angle);
        assert!(!seen.contains(&point), "slot {slot} aliases another");
        assert_eq!(map.spawn(angle + std::f32::consts::TAU), point);
        seen.push(point);
        // Facing: the first two metres ahead are open floor at the same level.
        let (x, z, yaw, floor) = point;
        let ahead = (x + yaw.cos() * 2.0, z + yaw.sin() * 2.0);
        assert!(
            !world().blocked_body_at(ahead.0, ahead.1, floor, floor + STEP_UP),
            "slot {slot} faces a wall"
        );
        assert!(callout_at(x, floor, z).is_some(), "slot {slot} is unnamed");
    }
}

#[test]
fn larak_callouts_name_every_pad_and_separate_the_bridge_from_the_pit() {
    for p in MapKind::ArenaDuel.pickups() {
        assert!(callout_at(p.x, p.floor, p.z).is_some(), "{}", p.id);
    }
    assert_eq!(callout_at(0.0, LEVEL_2, -6.5), Some("bridge"));
    assert_eq!(callout_at(0.0, PIT, -6.5), Some("pit"));
    assert_eq!(callout_at(31.0, ROOF, -22.0), Some("sign"));
    assert_eq!(callout_at(-20.0, RAIL_LANDING, 6.0), Some("low_ramp"));
    let ids: std::collections::HashSet<_> = CALLOUTS.iter().map(|c| c.id).collect();
    assert_eq!(ids.len(), CALLOUTS.len());
}

#[test]
fn larak_presentation_matches_collision_and_budgets() {
    let presentation = presentation();
    assert_eq!(presentation.solids.len(), world().solids.len());
    crate::protocol::validate_map_presentation(Some(presentation), &world().solids)
        .expect("valid presentation");
    // The REPOSSESSION hangs above the highest reachable head.
    let hung = world()
        .solids
        .iter()
        .find(|s| s.bottom >= 10.0)
        .expect("the hung cruiser");
    assert!(hung.bottom > ROOF + BODY_HEIGHT + 1.3);
}

#[test]
fn larak_pads_run_the_rule_sheet_and_the_plate_its_own_clock() {
    let ffa = crate::rules::RuleSet::default();
    let tdm = crate::rules::RuleSet::new(crate::protocol::GameMode::Tdm, &[], false).unwrap();
    assert_eq!(pad(PLATE_ID).clock(&ffa), 700);
    assert_eq!(pad(PLATE_ID).clock(&tdm), 700);
    assert_eq!(pad(RAIL_ID).clock(&ffa), 500);
    assert_eq!(pad("larak_scatter_booths").clock(&ffa), 300);
    assert_eq!(pad("larak_armor_bridge").clock(&ffa), 500);
    assert_eq!(pad("larak_health_toll").clock(&ffa), 500);
    assert_eq!(
        pad(RAIL_ID).clock(&tdm),
        crate::rules::TEAM_WEAPON_RESPAWN_TICKS
    );
    assert_eq!(
        pad("larak_health_toll").clock(&tdm),
        crate::sim::HEALTH_PICKUP_RESPAWN_TICKS
    );
    let plate = pad(PLATE_ID);
    assert_eq!(plate.kind, PickupKind::Plate);
    assert_eq!(plate.amount, crate::sim::PLATE_AMOUNT);
    // The Rocket is the lot's one free-for-all pad, on the power clock.
    let rocket = MapKind::ArenaDuel
        .scrap_pads()
        .into_iter()
        .find(|p| p.id == ROCKET_ID)
        .expect("the Pit Rocket");
    assert_eq!(
        rocket.kind,
        PickupKind::Weapon(crate::protocol::WeaponType::Rocket)
    );
    assert_eq!(
        rocket.clock(&ffa),
        crate::rules::FFA_POWER_WEAPON_RESPAWN_TICKS
    );
    assert_eq!(rocket.floor, PIT);
}

/// Prints the measured route table recorded in the plan. Run with
/// `cargo test -p fragr-server larak_measured_table -- --ignored --nocapture`.
#[test]
#[ignore = "prints the measurement table for the plan"]
fn larak_measured_table() {
    let (rail, plate) = (feet(&pad(RAIL_ID)), feet(&pad(PLATE_ID)));
    let solids = &world().solids;
    let t = |a: [f32; 3], b: [f32; 3]| seconds_to(&distances(a), b);
    println!("SW Lane -> NE Roof {:.1} s", t(SW_LANE, NE_ROOF));
    println!("NW Toll -> SE Impound {:.1} s", t(NW_TOLL, SE_IMPOUND));
    println!("Rail -> Plate {:.1} s", t(rail, plate));
    println!("Plate -> Rail {:.1} s", t(plate, rail));
    let origin = distances([0.5, PIT, 0.5]);
    for p in MapKind::ArenaDuel.pickups() {
        println!(
            "Pit origin -> {} {:.1} s",
            p.id,
            seconds_to(&origin, feet(&p))
        );
    }
    let weapons: Vec<_> = MapKind::ArenaDuel
        .pickups()
        .into_iter()
        .filter(|p| matches!(p.kind, PickupKind::Weapon(_)))
        .collect();
    for (i, slot) in SPAWNS.iter().enumerate() {
        let field = distances(spawn_feet(slot));
        let (nearest, id) = weapons
            .iter()
            .map(|w| (seconds_to(&field, feet(w)), w.id.clone()))
            .fold((f32::INFINITY, String::new()), |a, b| {
                if b.0 < a.0 {
                    b
                } else {
                    a
                }
            });
        println!(
            "S{} {:?} weapon {id} {nearest:.1} s, Plate {:.1} s, Rail {:.1} s, sees Plate {} Rail {}",
            i + 1,
            callout_at(slot[0], slot[1], slot[2]),
            seconds_to(&field, plate),
            seconds_to(&field, rail),
            sees(spawn_feet(slot), plate, solids),
            sees(spawn_feet(slot), rail, solids),
        );
    }
    // Spawn-to-spawn sightlines (standing eye to a standing body).
    for (i, a) in SPAWNS.iter().enumerate() {
        let seen: Vec<String> = SPAWNS
            .iter()
            .enumerate()
            .filter(|(j, b)| {
                *j != i
                    && [0.9, EYE].into_iter().any(|h| {
                        line_of_sight([a[0], a[1] + EYE, a[2]], [b[0], b[1] + h, b[2]], solids)
                    })
            })
            .map(|(j, b)| format!("S{} {:.0} m", j + 1, (a[0] - b[0]).hypot(a[2] - b[2])))
            .collect();
        println!("S{} sees {}", i + 1, seen.join(", "));
    }
    // Landmark visibility from every reachable standing cell.
    let cruiser = [
        [0.0, 9.9, 0.0],
        [1.1, 12.0, 0.0],
        [-1.1, 12.0, 0.0],
        [0.0, 12.0, 1.0],
        [0.0, 12.0, -1.0],
    ];
    let sign: Vec<[f32; 3]> = [9.0, 11.0, 13.0, 15.0]
        .into_iter()
        .map(|y| [37.0, y, -20.0])
        .collect();
    let cells: Vec<[f32; 3]> = origin
        .keys()
        .map(|(x, z, f)| [*x as f32 / 2.0, *f as f32 / 100.0 + EYE, *z as f32 / 2.0])
        .collect();
    let share = |targets: &[[f32; 3]]| {
        cells
            .iter()
            .filter(|eye| targets.iter().any(|t| line_of_sight(**eye, *t, solids)))
            .count() as f32
            / cells.len() as f32
    };
    println!("reachable standing cells {}", cells.len());
    println!("REPOSSESSION visible from {:.0}%", share(&cruiser) * 100.0);
    println!("LARAK sign visible from {:.0}%", share(&sign) * 100.0);
}

/// Writes the wire MapInfo to `FRAGR_LARAK_MAP_INFO` for the offline preview
/// in `tools/preview_larak_lot.gd`. Run with `--ignored`.
#[test]
#[ignore = "writes the MapInfo used by the offline preview"]
fn larak_write_map_info() {
    let Ok(path) = std::env::var("FRAGR_LARAK_MAP_INFO") else {
        return;
    };
    let state = crate::sim::GameState::with_map(MapKind::ArenaDuel, false);
    let message = serde_json::to_string(&state.map_info()).expect("serialize MapInfo");
    std::fs::write(path, message).expect("write MapInfo");
}

/// Share of reachable standing eyes within `range` metres that see a body
/// standing at `feet` (chest or eye height).
fn exposure(feet: [f32; 3], eyes: &[[f32; 3]], range: f32, solids: &[Solid]) -> f32 {
    let near: Vec<&[f32; 3]> = eyes
        .iter()
        .filter(|e| (e[0] - feet[0]).hypot(e[2] - feet[2]) <= range)
        .collect();
    if near.is_empty() {
        return 0.0;
    }
    near.iter()
        .filter(|eye| {
            [0.9, EYE]
                .into_iter()
                .any(|h| line_of_sight(***eye, [feet[0], feet[1] + h, feet[2]], solids))
        })
        .count() as f32
        / eyes.len() as f32
}

/// Prints each slot's exposure and the least exposed candidate floor cells
/// that pass every spawn gate. Run with `--ignored --nocapture`.
#[test]
#[ignore = "prints spawn exposure for the plan"]
fn larak_spawn_exposure() {
    let solids = &world().solids;
    let origin = distances([0.5, PIT, 0.5]);
    let eyes: Vec<[f32; 3]> = origin
        .keys()
        .filter(|(x, z, _)| x.rem_euclid(2) == 1 && z.rem_euclid(2) == 1)
        .map(|(x, z, f)| [*x as f32 / 2.0, *f as f32 / 100.0 + EYE, *z as f32 / 2.0])
        .collect();
    for (i, slot) in SPAWNS.iter().enumerate() {
        println!(
            "S{} exposure {:.1}%",
            i + 1,
            exposure(spawn_feet(slot), &eyes, 40.0, solids) * 100.0
        );
    }
    let (rail, plate) = (feet(&pad(RAIL_ID)), feet(&pad(PLATE_ID)));
    let weapons: Vec<_> = MapKind::ArenaDuel
        .pickups()
        .into_iter()
        .filter(|p| matches!(p.kind, PickupKind::Weapon(_)))
        .collect();
    let mut found = Vec::new();
    for &(x, z, f) in origin.keys() {
        if (x - 1).rem_euclid(4) != 0 || (z - 1).rem_euclid(4) != 0 {
            continue;
        }
        let at = [x as f32 / 2.0, f as f32 / 100.0, z as f32 / 2.0];
        if world().ceiling_height(at[0], at[2], at[1]) - at[1] < BODY_HEIGHT + 0.6
            || callout_at(at[0], at[1], at[2]).is_none_or(|c| {
                [
                    "pit", "bridge", "crane", "roof", "sign", "low_ramp", "stack",
                ]
                .contains(&c)
            })
            || sees(at, plate, solids)
            || sees(at, rail, solids)
        {
            continue;
        }
        let field = distances(at);
        let weapon = weapons
            .iter()
            .map(|w| seconds_to(&field, feet(w)))
            .fold(f32::INFINITY, f32::min);
        if seconds_to(&field, plate) < 10.0 || seconds_to(&field, rail) < 4.5 || weapon > 5.0 {
            continue;
        }
        found.push((exposure(at, &eyes, 40.0, solids), at, weapon));
    }
    found.sort_by(|a, b| a.0.total_cmp(&b.0));
    // Farthest-point picks among the calmer candidates: each new slot is the
    // one farthest from every slot already chosen.
    let calm: Vec<[f32; 3]> = found
        .iter()
        .filter(|(e, _, _)| *e <= 0.32)
        .map(|(_, at, _)| *at)
        .collect();
    let gap =
        |a: &[f32; 3], b: &[f32; 3]| (a[0] - b[0]).hypot(a[2] - b[2]) + (a[1] - b[1]).abs() * 3.0;
    let mut picked: Vec<[f32; 3]> = vec![[-33.0, LEVEL_2, -27.0]];
    while picked.len() < 14 {
        let Some(next) = calm.iter().copied().max_by(|a, b| {
            let da = picked
                .iter()
                .map(|p| gap(a, p))
                .fold(f32::INFINITY, f32::min);
            let db = picked
                .iter()
                .map(|p| gap(b, p))
                .fold(f32::INFINITY, f32::min);
            da.total_cmp(&db)
        }) else {
            break;
        };
        let d = picked
            .iter()
            .map(|p| gap(&next, p))
            .fold(f32::INFINITY, f32::min);
        println!(
            "pick {next:?} {:?} min gap {d:.1}",
            callout_at(next[0], next[1], next[2])
        );
        picked.push(next);
    }
    let east: Vec<_> = found
        .iter()
        .filter(|(_, at, _)| at[0] > 0.0)
        .take(25)
        .collect();
    for (e, at, w) in found.iter().take(15).chain(east) {
        println!(
            "candidate {at:?} {:?} exposure {:.1}% weapon {w:.1} s",
            callout_at(at[0], at[1], at[2]),
            e * 100.0
        );
    }
}

/// Ticks for the rule bots' own navigator to walk `from` to `to` through the
/// real tick (movement, collision, stairs and body avoidance), or none if it
/// has not arrived within `limit` ticks.
fn bot_walk_ticks(from: [f32; 3], to: [f32; 3], limit: u32) -> Option<u32> {
    use crate::navigation::{NavigationGoal, Navigator};
    use crate::sim::{GameState, PLAYER_FLOOR_Y};
    let navigation = crate::maps::navigation(MapKind::ArenaDuel);
    let mut state = GameState::with_map(MapKind::ArenaDuel, false);
    state.config.time_limit_ticks = None;
    state.config.boss_spawn_ticks = None;
    state.config.compliance_ping_ticks = None;
    let id = uuid::Uuid::from_u128(1);
    state.add_player(id, "Lot Walker".into(), crate::protocol::Role::Human);
    state.start_round();
    state.players[0].x = from[0];
    state.players[0].y = from[1] + PLAYER_FLOOR_Y;
    state.players[0].z = from[2];
    let mut navigator = Navigator::default();
    for tick in 0..limit {
        let player = &state.players[0];
        let here = [player.x, player.y - PLAYER_FLOOR_Y, player.z];
        if (here[0] - to[0]).hypot(here[2] - to[2]) < 0.6 && (here[1] - to[1]).abs() < 0.2 {
            return Some(tick);
        }
        let walking = state.walking_arena(world());
        let action = navigator.steer_with_visibility(
            navigation,
            here,
            NavigationGoal {
                feet: to,
                combat: false,
            },
            crate::protocol::Action {
                forward: true,
                ..Default::default()
            },
            u64::from(tick),
            true,
            &walking.solids,
        );
        let action = navigator.avoid_bodies(
            &walking,
            id,
            &state.contact_bodies(),
            action,
            u64::from(tick),
        );
        state.set_action(id, action);
        state.tick(0.05);
        state.take_events();
    }
    None
}

/// The duel spine and the corner-to-corner routes the timing table names.
fn spine() -> Vec<(String, [f32; 3], [f32; 3])> {
    let (rail, plate) = (feet(&pad(RAIL_ID)), feet(&pad(PLATE_ID)));
    vec![
        ("SW Lane corner to NE Roof corner".into(), SW_LANE, NE_ROOF),
        (
            "NW Toll corner to SE Impound corner".into(),
            NW_TOLL,
            SE_IMPOUND,
        ),
        ("Rail to Plate (climb)".into(), rail, plate),
        ("Plate to Rail (fall)".into(), plate, rail),
    ]
}

/// The rule bots' navigator walks the duel spine and corner to corner through
/// the real tick inside the 25 s gate the layout was built to, and reaches the
/// Plate and the Rail from a slot in every quarter.
#[test]
fn larak_bots_walk_the_spine_and_reach_the_power_items() {
    for (name, from, to) in spine() {
        let ticks = bot_walk_ticks(from, to, 25 * 20)
            .unwrap_or_else(|| panic!("a bot never finished {name} inside 25 s"));
        assert!(
            ticks > 8 * 20,
            "{name}: {ticks} ticks is suspiciously short"
        );
    }
    let (rail, plate) = (feet(&pad(RAIL_ID)), feet(&pad(PLATE_ID)));
    for slot in [SPAWNS[0], SPAWNS[4], SPAWNS[5], SPAWNS[7], SPAWNS[9]] {
        for (name, target) in [("Plate", plate), ("Rail", rail)] {
            assert!(
                bot_walk_ticks(spawn_feet(&slot), target, 30 * 20).is_some(),
                "a bot from {slot:?} never reached the {name}"
            );
        }
    }
}

/// Frags and spawn deaths (a death within two seconds of the victim's
/// respawn, the playtest harness's window) for `bots` rule bots on map 1 over
/// `seconds` of play with no frag or time limit.
fn rule_bot_spawn_deaths(bots: usize, seconds: u32, seed: u64) -> (u32, u32) {
    use crate::protocol::{GameEvent, ServerMessage};
    let mut session = crate::session::GameSession::with_map(MapKind::ArenaDuel, false);
    session.state.seed(seed);
    session.state.config.frag_limit = None;
    session.state.config.time_limit_ticks = None;
    session.spawn_bots(bots);
    session.state.start_round();
    let mut respawned: HashMap<String, u64> = HashMap::new();
    let (mut frags, mut spawn_deaths) = (0, 0);
    for _ in 0..seconds * 20 {
        for message in session.tick_messages(0.05) {
            let now = session.state.tick;
            match message {
                ServerMessage::Event(GameEvent::Respawn { player }) => {
                    respawned.insert(player, now);
                }
                ServerMessage::Event(GameEvent::Frag { victim, .. }) => {
                    frags += 1;
                    if respawned
                        .get(&victim)
                        .is_some_and(|at| now.saturating_sub(*at) <= 40)
                    {
                        spawn_deaths += 1;
                    }
                }
                _ => {}
            }
        }
    }
    (frags, spawn_deaths)
}

/// Prints the rule bots' spawn-death rate on map 1 at two to eight fighters.
#[test]
#[ignore = "prints the rule-bot spawn-death probe"]
fn larak_spawn_death_probe() {
    for bots in [2, 4, 6, 8] {
        let (mut frags, mut deaths) = (0, 0);
        for seed in [42, 67, 1993] {
            let (f, d) = rule_bot_spawn_deaths(bots, 180, seed);
            frags += f;
            deaths += d;
        }
        println!(
            "{bots} bots: {deaths} spawn deaths / {frags} frags ({:.1}%)",
            deaths as f32 * 100.0 / frags.max(1) as f32
        );
    }
}

/// Prints the timing table recorded in the plan: the layered Dijkstra lower
/// bound beside the time the rule bots' navigator takes through the tick.
#[test]
#[ignore = "prints the bot-walked timing table"]
fn larak_bot_timing_table() {
    let (rail, plate) = (feet(&pad(RAIL_ID)), feet(&pad(PLATE_ID)));
    let mut rows = spine();
    let origin = [0.5, PIT, 0.5];
    for p in MapKind::ArenaDuel.pickups() {
        rows.push((format!("Pit origin to {}", p.id), origin, feet(&p)));
    }
    for (i, slot) in SPAWNS.iter().enumerate() {
        rows.push((format!("S{} to Plate", i + 1), spawn_feet(slot), plate));
        rows.push((format!("S{} to Rail", i + 1), spawn_feet(slot), rail));
    }
    println!("| Route | Lower bound | Bot walk |");
    for (name, from, to) in rows {
        let bound = seconds_to(&distances(from), to);
        let walk = bot_walk_ticks(from, to, 60 * 20).map_or("stalled".to_string(), |t| {
            format!("{:.1} s", t as f32 / 20.0)
        });
        println!("| {name} | {bound:.1} s | {walk} |");
    }
}
