use crate::combat::{line_of_sight, FIGHTER_HEIGHT};
use crate::movement::EYE_HEIGHT;
use crate::protocol::{Action, LookAt, Role, WeaponType};
use crate::sim::{GameState, MapKind, RoundState, PLAYER_FLOOR_Y, SPAWN_SHIELD_TICKS};
use uuid::Uuid;

#[test]
fn tripoint_opening_places_a_full_roster_behind_cover() {
    let mut state = GameState::with_map(MapKind::TripointWorks, false);
    for index in 0..16 {
        state.add_player(
            Uuid::from_u128(index + 1),
            format!("Fighter {index}"),
            if index % 2 == 0 {
                Role::Human
            } else {
                Role::Agent
            },
        );
    }
    let solids = state.map.solids();
    let navigation = state.map.navigation();
    for player in &state.players {
        crate::navigation::tests::assert_server_walks(
            MapKind::TripointWorks,
            navigation,
            [player.x, player.y - PLAYER_FLOOR_Y, player.z],
            [0.0; 3],
        );
        for other in state.players.iter().filter(|p| p.id != player.id) {
            let distance = (player.x - other.x).hypot(player.z - other.z);
            assert!(distance >= crate::movement::RADIUS * 2.0);
            if distance > WeaponType::Rail.range_units() {
                continue;
            }
            let eye = [other.x, other.y - PLAYER_FLOOR_Y + EYE_HEIGHT, other.z];
            for height in [FIGHTER_HEIGHT * 0.5, EYE_HEIGHT] {
                let target = [player.x, player.y - PLAYER_FLOOR_Y + height, player.z];
                assert!(
                    !line_of_sight(eye, target, &solids),
                    "{} opens exposed to {} at {distance:.2} m: {target:?} from {eye:?}",
                    player.name,
                    other.name,
                );
            }
        }
    }
}

/// Two fighters walking at each other for the two-second spawn window close
/// twenty metres, and the scatter gun reaches twelve more.
const CONTACT_RANGE: f32 = 2.0 * crate::movement::TOP_SPEED * 2.0 + 12.0;

/// The mixed-client roster each map is played with in `tools/playtest_roster.sh`.
const PLAYTEST_ROSTER: [(MapKind, u128); 6] = [
    (MapKind::ArenaDuel, 2),
    (MapKind::ComplianceYard, 6),
    (MapKind::Directive17, 6),
    (MapKind::Sector9, 8),
    (MapKind::ReclamationGulch, 12),
    (MapKind::TripointWorks, 16),
];

/// Whether a fighter standing at `from` has a shot at a fighter at `to`, both
/// given as feet, inside the range the spawn selector treats as a threat.
fn threatens(from: [f32; 3], to: [f32; 3], solids: &[crate::movement::Solid]) -> bool {
    let distance = (from[0] - to[0]).hypot(from[2] - to[2]);
    let eye = [from[0], from[1] + EYE_HEIGHT, from[2]];
    distance <= crate::sim::SPAWN_THREAT_RANGE
        && [FIGHTER_HEIGHT * 0.5, EYE_HEIGHT]
            .into_iter()
            .any(|height| line_of_sight(eye, [to[0], to[1] + height, to[2]], solids))
}

fn feet(player: &crate::sim::Player) -> [f32; 3] {
    [player.x, player.y - PLAYER_FLOOR_Y, player.z]
}

#[test]
fn threat_range_covers_every_weapon_and_the_safe_window() {
    for weapon in [
        WeaponType::Fists,
        WeaponType::Tack,
        WeaponType::Flechette,
        WeaponType::Rail,
        WeaponType::Scatter,
    ] {
        assert!(weapon.range_units() < crate::sim::SPAWN_THREAT_RANGE);
    }
}

/// Before the Directive 17, Sector 9 and Reclamation Gulch spawn pockets, the
/// playtest roster opened with two firing lanes on each of those maps (19.5 to
/// 53 m), and the network harness recorded two to three deaths in the first
/// two seconds of every round. Openings are placed before anyone moves, so
/// this is deterministic: every fighter must start screened from every other
/// fighter inside rail reach plus the safe window, clear of them, and able to
/// walk to the middle of the map.
#[test]
fn every_playtest_roster_opens_screened_and_walkable() {
    for (map, count) in PLAYTEST_ROSTER {
        let mut state = GameState::with_map(map, false);
        for index in 0..count {
            state.add_player(
                Uuid::from_u128(index + 1),
                format!("Fighter {index}"),
                if index % 2 == 0 {
                    Role::Human
                } else {
                    Role::Agent
                },
            );
        }
        let solids = state.map.solids();
        let navigation = state.map.navigation();
        for player in &state.players {
            crate::navigation::tests::assert_server_walks(map, navigation, feet(player), [0.0; 3]);
            for other in state.players.iter().filter(|p| p.id != player.id) {
                let distance = (player.x - other.x).hypot(player.z - other.z);
                assert!(distance >= crate::movement::RADIUS * 2.0);
                assert!(
                    !threatens(feet(other), feet(player), &solids),
                    "{}: {} opens in {}'s lane at {distance:.1} m",
                    map.name(),
                    player.name,
                    other.name,
                );
            }
        }
    }
}

/// A lone opponent standing on any spawn point of any map leaves room for a
/// respawn that is neither in its lane nor close enough to walk round the
/// cover inside the safe window, and the selector finds it.
#[test]
fn a_respawn_avoids_both_the_lane_and_the_corner_of_a_lone_opponent() {
    for (map, _) in PLAYTEST_ROSTER {
        let state = GameState::with_map(map, false);
        let slots = state.map.spawn_slots();
        let solids = state.map.solids();
        for slot in 0..slots {
            let mut state = GameState::with_map(map, false);
            state.config.boss_spawn_ticks = None;
            state.config.compliance_ping_ticks = None;
            let threat = Uuid::from_u128(1);
            let victim = Uuid::from_u128(2);
            state.add_player(threat, "Threat".into(), Role::Agent);
            state.add_player(victim, "Victim".into(), Role::Human);
            let (x, z, _, floor) = state
                .map
                .spawn(slot as f32 * std::f32::consts::TAU / slots as f32);
            {
                let player = &mut state.players[0];
                player.x = x;
                player.z = z;
                player.y = PLAYER_FLOOR_Y + floor;
            }
            state.start_round();
            state.players[1].respawn_timer = Some(1);
            state.tick(0.05);
            let (threat, victim) = (&state.players[0], &state.players[1]);
            let distance = (threat.x - victim.x).hypot(threat.z - victim.z);
            assert!(
                distance > CONTACT_RANGE,
                "{} slot {slot}: respawn {distance:.1} m from a lone opponent",
                map.name()
            );
            assert!(
                !threatens(feet(threat), feet(victim), &solids),
                "{} slot {slot}: respawn in a lone opponent's lane",
                map.name()
            );
        }
    }
}

/// With two opponents standing on spawn points, a respawn takes the widest
/// slot that neither of them can shoot into. Counting lanes out to the old
/// 100 m hitscan cap instead of the rail's reach placed 318 of 496 such
/// respawns on Directive 17, and 64 of 496 on Sector 9, closer to a fighter
/// than necessary (a sweep over every pair of even spawn points), because a
/// harmless 70 to 100 m lane disqualified the farther slot.
#[test]
fn a_respawn_takes_the_widest_slot_out_of_every_lane() {
    for map in [MapKind::Directive17, MapKind::Sector9] {
        let base = GameState::with_map(map, false);
        let slots = base.map.spawn_slots();
        let solids = base.map.solids();
        let points: Vec<[f32; 3]> = (0..slots)
            .map(|slot| {
                let (x, z, _, floor) = base
                    .map
                    .spawn(slot as f32 * std::f32::consts::TAU / slots as f32);
                [x, floor, z]
            })
            .collect();
        for first in (0..slots).step_by(4) {
            for second in ((first + 4)..slots).step_by(4) {
                let mut state = GameState::with_map(map, false);
                state.config.boss_spawn_ticks = None;
                state.config.compliance_ping_ticks = None;
                for index in 0..3 {
                    state.add_player(
                        Uuid::from_u128(index + 1),
                        format!("Fighter {index}"),
                        Role::Agent,
                    );
                }
                for (player, slot) in state.players.iter_mut().zip([first, second]) {
                    player.x = points[slot][0];
                    player.z = points[slot][2];
                    player.y = PLAYER_FLOOR_Y + points[slot][1];
                }
                state.start_round();
                state.players[2].respawn_timer = Some(1);
                state.tick(0.05);
                let foes = [feet(&state.players[0]), feet(&state.players[1])];
                let gap = |at: [f32; 3]| {
                    foes.iter()
                        .map(|foe| (foe[0] - at[0]).hypot(foe[2] - at[2]))
                        .fold(f32::MAX, f32::min)
                };
                let covered = |at: [f32; 3]| foes.iter().all(|foe| !threatens(*foe, at, &solids));
                let widest = points
                    .iter()
                    .filter(|at| covered(**at))
                    .map(|at| gap(*at))
                    .fold(0.0f32, f32::max);
                let respawn = feet(&state.players[2]);
                assert!(
                    covered(respawn),
                    "{} {first}/{second}: respawn in a lane",
                    map.name()
                );
                assert!(
                    gap(respawn) + 0.5 >= widest,
                    "{} {first}/{second}: respawn {:.1} m from a fighter, {widest:.1} m was available",
                    map.name(),
                    gap(respawn)
                );
            }
        }
    }
}

/// Real clients connect concurrently, so the order `add_player` sees them in
/// is not the roster's listed order: it depends on WebSocket and scheduler
/// timing. Shuffle that arrival order many times per map and require every
/// shuffle to open exactly as screened and clear as the listed order does.
#[test]
fn every_arrival_order_still_opens_screened_and_clear() {
    use rand::seq::SliceRandom;
    use rand::SeedableRng;
    let mut rng = rand::rngs::StdRng::seed_from_u64(12345);
    for (map, count) in PLAYTEST_ROSTER {
        let mut order: Vec<u128> = (0..count).collect();
        for trial in 0..500 {
            order.shuffle(&mut rng);
            let mut state = GameState::with_map(map, false);
            for &index in &order {
                state.add_player(
                    Uuid::from_u128(index + 1),
                    format!("Fighter {index}"),
                    if index % 2 == 0 {
                        Role::Human
                    } else {
                        Role::Agent
                    },
                );
            }
            let solids = state.map.solids();
            for player in &state.players {
                for other in state.players.iter().filter(|p| p.id != player.id) {
                    let distance = (player.x - other.x).hypot(player.z - other.z);
                    assert!(
                        distance >= crate::movement::RADIUS * 2.0,
                        "{} trial {trial} order {order:?}: {} overlaps {}",
                        map.name(),
                        player.name,
                        other.name
                    );
                    assert!(
                        !threatens(feet(other), feet(player), &solids),
                        "{} trial {trial} order {order:?}: {} opens in {}'s lane",
                        map.name(),
                        player.name,
                        other.name
                    );
                }
            }
        }
    }
}

/// Reclamation Gulch has sixteen spawn pockets; the playtest roster fills
/// twelve of them. By the pigeonhole principle at least eight of those
/// pockets sit on an immediate neighbour with no empty pocket between them,
/// 35.9 m apart. That is close enough that two fighters who each push toward
/// their nearest hostile and hold the trigger the moment a corner clears,
/// which is exactly what a reflex or planner playtest agent does at the
/// opening, can close, expose each other and trade a Railgun kill well inside
/// the two-second window `tools/playtest` classes as an opening spawn death.
///
/// `do_respawn` has always shielded a fighter for `SPAWN_SHIELD_TICKS` the
/// instant it puts them back in danger. Nothing did the same for the round's
/// opening roster: they went live with zero protection, so whichever adjacent
/// pair happened to clear its corner first could close the kill immediately.
/// A respawn under the identical closing dash survives on its shield; the
/// opening must survive it too, or the mixed-client roster's twelve-fighter
/// map trades more than the one opening death per round the gate allows.
#[test]
fn adjacent_gulch_pockets_survive_the_opening_closing_duel() {
    // Place the actual twelve-fighter roster the way the playtest harness
    // does, then take the two it packed closest together: the pair the
    // pigeonhole argument in the doc comment above says must exist.
    let mut roster = GameState::with_map(MapKind::ReclamationGulch, false);
    for index in 0..12u128 {
        roster.add_player(
            Uuid::from_u128(index + 100),
            format!("Roster {index}"),
            Role::Agent,
        );
    }
    let mut closest: Option<(f32, usize, usize)> = None;
    for (i, p) in roster.players.iter().enumerate() {
        for (j, q) in roster.players.iter().enumerate().skip(i + 1) {
            let d = (p.x - q.x).hypot(p.z - q.z);
            if closest.is_none_or(|(best, ..)| d < best) {
                closest = Some((d, i, j));
            }
        }
    }
    let (gap, i, j) = closest.expect("twelve fighters give at least one pair");
    assert!(
        (30.0..42.0).contains(&gap),
        "expected the pigeonhole-forced adjacent-pocket gap near 35.9 m, got {gap:.1}"
    );
    let (ax, az, ayaw, afloor) = (
        roster.players[i].x,
        roster.players[i].z,
        roster.players[i].yaw,
        roster.players[i].y - PLAYER_FLOOR_Y,
    );
    let (bx, bz, byaw, bfloor) = (
        roster.players[j].x,
        roster.players[j].z,
        roster.players[j].yaw,
        roster.players[j].y - PLAYER_FLOOR_Y,
    );
    let solids = roster.map.solids();
    assert!(
        !threatens([ax, afloor, az], [bx, bfloor, bz], &solids),
        "the closest pair must still open screened from each other"
    );

    // Rebuild just that pair on their own so the duel below is not muddied by
    // the other ten fighters' shots and movement.
    let mut state = GameState::with_map(MapKind::ReclamationGulch, false);
    state.config.boss_spawn_ticks = None;
    state.config.compliance_ping_ticks = None;
    let (a, b) = (Uuid::from_u128(1), Uuid::from_u128(2));
    state.add_player(a, "A".into(), Role::Agent);
    state.add_player(b, "B".into(), Role::Agent);
    for (id, x, z, yaw, floor) in [(a, ax, az, ayaw, afloor), (b, bx, bz, byaw, bfloor)] {
        let player = state.players.iter_mut().find(|p| p.id == id).unwrap();
        player.x = x;
        player.z = z;
        player.yaw = yaw;
        player.y = PLAYER_FLOOR_Y + floor;
        player.weapon = WeaponType::Rail;
    }

    // Drive the real Warmup -> Active transition: the game's own opening, not
    // a direct `start_round` call.
    for _ in 0..state.config.warmup_ticks {
        state.tick(0.05);
    }
    assert_eq!(state.round_state, RoundState::Active);
    assert!(
        state.spawn_shields.contains_key(&a) && state.spawn_shields.contains_key(&b),
        "the opening roster must be shielded exactly like a respawn"
    );

    // Both fighters push toward each other and hold the trigger every tick,
    // exactly what a reflex or planner agent does once it names the other its
    // nearest hostile. The server's own collision and line of sight decide
    // whether a shot lands, not this test.
    let mut first_death: Option<u32> = None;
    for elapsed in 0..80u32 {
        for (id, other) in [(a, b), (b, a)] {
            state.set_action(
                id,
                Action {
                    forward: true,
                    fire: true,
                    look_at: Some(LookAt {
                        player_id: Some(other),
                        x: None,
                        y: None,
                        z: None,
                    }),
                    ..Action::default()
                },
            );
        }
        state.tick(0.05);
        if first_death.is_none()
            && state
                .players
                .iter()
                .any(|p| (p.id == a || p.id == b) && p.hp <= 0)
        {
            first_death = Some(elapsed);
        }
    }
    if let Some(tick) = first_death {
        assert!(
            tick >= SPAWN_SHIELD_TICKS,
            "adjacent pockets traded an opening kill at tick {tick}, inside the {SPAWN_SHIELD_TICKS}-tick shield"
        );
    }
}
