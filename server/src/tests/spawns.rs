use crate::combat::{line_of_sight, FIGHTER_HEIGHT};
use crate::movement::EYE_HEIGHT;
use crate::protocol::{Role, WeaponType};
use crate::sim::{GameState, MapKind, PLAYER_FLOOR_Y};
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
