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
