use super::*;
use crate::protocol::Role;
use crate::sim::MapKind;
use uuid::Uuid;

fn pair(map: MapKind, feet: [[f32; 3]; 2]) -> GameState {
    let mut game = GameState::with_map(map, false);
    for (index, feet) in feet.into_iter().enumerate() {
        let id = Uuid::from_u128(900 + index as u128);
        game.add_player(id, format!("Contact {index}"), Role::Human);
        let player = game.players.last_mut().unwrap();
        player.x = feet[0];
        player.y = feet[1] + PLAYER_FLOOR_Y;
        player.z = feet[2];
        player.vy = 0.0;
    }
    game
}

#[test]
fn glancing_actor_contact_cannot_project_a_walker_into_a_parked_hull() {
    let mut game = pair(MapKind::ArenaDuel, [[-2.42, 0.0, -0.8], [-2.72, 0.0, 0.2]]);
    game.add_jeep([0.0; 3], 0.0).unwrap();
    let before = game.contact_bodies();
    game.players[0].z = -0.55;
    let arena = game.current_arena().into_owned();
    let mut proposals = before.clone();
    proposals[0].proposed.z = -0.55;
    let old_projection = resolve(&proposals, 0.05, &arena);
    assert!(
        old_projection[0].x > -2.4,
        "fixture must expose missing hull projection: {:?}",
        old_projection[0]
    );
    game.resolve_player_contacts(before, 0.05, &arena);
    assert!(game.players[0].x <= -2.4);
    assert!(
        game.players[0].z > -0.8,
        "legal tangential movement remains available"
    );
}

#[test]
fn touching_swimmers_retain_buoyant_support_after_actor_projection() {
    let feet = 2.2 - crate::movement::water::SWIM_DRAFT;
    let mut game = pair(
        MapKind::HoldfastAtoll,
        [[-0.6, feet, 80.0], [0.6, feet, 80.3]],
    );
    let before = game.contact_bodies();
    game.players[0].x += 0.25;
    let arena = game.current_arena().into_owned();
    let mut proposals = before.clone();
    proposals[0].proposed.x += 0.25;
    let old_projection = resolve(&proposals, 0.05, &arena);
    assert!(
        old_projection[0].y < feet - 0.01,
        "fixture must reproject contact"
    );
    game.resolve_player_contacts(before, 0.05, &arena);
    for player in &game.players {
        assert!((player.y - PLAYER_FLOOR_Y - feet).abs() < 0.0001);
        assert_eq!(player.vy, 0.0);
    }
}
