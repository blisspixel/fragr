use super::*;

fn balcony(bottom: f32, top: f32) -> Arena {
    Arena {
        half: 10.0,
        solids: vec![Solid::from_center_volume(0.0, 0.0, 2.0, 2.0, bottom, top)],
    }
}

#[test]
fn legacy_solid_preserves_its_wire_shape() {
    let wire = serde_json::json!({
        "min_x": -2.0, "max_x": 2.0, "min_z": -2.0, "max_z": 2.0, "top": 3.0
    });
    let solid: Solid = serde_json::from_value(wire.clone()).unwrap();
    assert_eq!(solid.bottom, GROUND_Y);
    assert_eq!(serde_json::to_value(solid).unwrap(), wire);
    let raised = balcony(2.4, 3.0).solids[0];
    let encoded = serde_json::to_value(raised).unwrap();
    assert!(encoded.get("bottom").is_some());
    assert_eq!(serde_json::from_value::<Solid>(encoded).unwrap(), raised);
}

#[test]
fn walking_below_a_balcony_never_snaps_to_its_top() {
    let arena = balcony(2.4, 3.0);
    let mut state = at(-4.0, 0.0, 0.0);
    state.vx = TOP_SPEED;
    for _ in 0..32 {
        state = integrate(state, false, 0.05, &arena);
        assert_eq!(state.y, GROUND_Y);
        assert_eq!(state.vy, 0.0);
    }
    assert_eq!(state.x, 4.0);
}

#[test]
fn upper_floor_supports_walking_and_swept_landing() {
    let arena = balcony(2.4, 3.0);
    let mut state = at_y(-1.0, 0.0, 3.0, 0.0);
    state.vx = TOP_SPEED;
    for _ in 0..8 {
        state = integrate(state, false, 0.05, &arena);
        assert_eq!(state.y, 3.0);
    }
    assert_eq!(state.x, 1.0);
    let mut falling = at_y(0.0, 0.0, 5.0, 0.0);
    falling.vy = -20.0;
    falling = integrate(falling, false, 0.25, &arena);
    assert_eq!(falling.y, 3.0);
    assert_eq!(falling.vy, 0.0);
}

#[test]
fn jump_hits_underside_and_then_falls() {
    let arena = balcony(2.1, 3.0);
    let jumped = integrate(at(0.0, 0.0, 0.0), true, 0.05, &arena);
    assert!((jumped.y - (2.1 - BODY_HEIGHT)).abs() < CONTACT_EPSILON);
    assert_eq!(jumped.vy, 0.0);
    let falling = integrate(jumped, false, 0.05, &arena);
    assert!(falling.y < jumped.y);
    assert!(falling.vy < 0.0);
}

#[test]
fn upward_sweep_cannot_tunnel_through_a_thin_ceiling() {
    let arena = balcony(2.0, 2.05);
    let jumped = integrate(at(0.0, 0.0, 0.0), true, 0.25, &arena);
    assert!((jumped.y - 0.2).abs() < CONTACT_EPSILON);
    assert_eq!(jumped.vy, 0.0);
}

#[test]
fn head_contact_includes_body_radius_at_a_slab_edge() {
    let arena = balcony(2.1, 3.0);
    let jumped = integrate(at(2.4, 0.0, 0.0), true, 0.05, &arena);
    assert!((jumped.y - 0.3).abs() < CONTACT_EPSILON);
    let clear = integrate(at(2.6, 0.0, 0.0), true, 0.05, &arena);
    assert_eq!(clear.y, JUMP_SPEED * 0.05);
    assert_eq!(clear.vy, JUMP_SPEED);
}

#[test]
fn airborne_body_cannot_enter_the_side_of_a_slab() {
    let arena = balcony(2.4, 3.0);
    let mut state = at_y(-2.75, 0.0, 1.0, 0.0);
    state.vx = TOP_SPEED;
    let moved = integrate(state, false, 0.05, &arena);
    assert_eq!(moved.x, state.x);
    assert_eq!(moved.vx, 0.0);
}

#[test]
fn stepping_requires_clearance_at_the_new_foot_height() {
    for (ceiling, can_step) in [(2.2, false), (2.3, true)] {
        let mut arena = balcony(ceiling, 3.0);
        arena
            .solids
            .push(Solid::from_center_top(1.0, 0.0, 1.0, 1.0, 0.5));
        let mut state = at(-0.25, 0.0, 0.0);
        state.vx = TOP_SPEED;
        let moved = integrate(state, false, 0.05, &arena);
        assert_eq!(moved.x, if can_step { 0.0 } else { -0.25 });
        assert_eq!(moved.y, if can_step { 0.5 } else { 0.0 });
        assert!(moved.y + BODY_HEIGHT <= ceiling + CONTACT_EPSILON);
    }
}

#[test]
fn insufficient_headroom_blocks_a_grounded_approach() {
    let arena = balcony(1.7, 3.0);
    let mut state = at(-2.75, 0.0, 0.0);
    state.vx = TOP_SPEED;
    let moved = integrate(state, false, 0.05, &arena);
    assert_eq!(moved.x, state.x);
    assert_eq!(moved.y, GROUND_Y);
}

#[test]
fn shots_pass_under_the_deck_and_hit_each_surface() {
    use crate::combat::{line_of_sight, Ray};
    let arena = balcony(2.4, 3.0);
    let solid = &arena.solids[0];
    assert!(line_of_sight(
        [-4.0, EYE_HEIGHT, 0.0],
        [4.0, EYE_HEIGHT, 0.0],
        &arena.solids
    ));
    assert!(!line_of_sight(
        [-4.0, 2.7, 0.0],
        [4.0, 2.7, 0.0],
        &arena.solids
    ));
    for (origin, direction, distance, normal) in [
        ([0.0, 1.4, 0.0], [0.0, 1.0, 0.0], 1.0, [0.0, -1.0, 0.0]),
        ([0.0, 5.0, 0.0], [0.0, -1.0, 0.0], 2.0, [0.0, 1.0, 0.0]),
        ([-4.0, 2.7, 0.0], [1.0, 0.0, 0.0], 2.0, [-1.0, 0.0, 0.0]),
    ] {
        let ray = Ray { origin, direction };
        let hit = ray.solid(solid, 10.0).unwrap();
        assert!((hit.distance - distance).abs() < CONTACT_EPSILON);
        assert_eq!(hit.normal, normal);
        assert!(ray.solid(solid, distance - 0.1).is_none());
    }
}
