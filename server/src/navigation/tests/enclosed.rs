use super::{arena, assert_walks};
use crate::movement::{Arena, Solid};
use crate::navigation::{Navigation, RouteStatus, MAX_LAYERS, SEARCH_LIMIT};

fn balcony() -> Arena {
    let mut solids = vec![Solid::from_center_volume(4.0, 0.0, 3.0, 3.0, 2.4, 3.0)];
    for i in 0..6 {
        solids.push(Solid::from_center_top(
            4.0,
            -14.0 + i as f32 * 2.0,
            2.0,
            1.0,
            (i + 1) as f32 * 0.5,
        ));
    }
    Arena { half: 18.0, solids }
}

#[test]
fn coordinate_targets_select_the_intended_floor_without_climbing_the_ceiling() {
    let world = Navigation::new(balcony()).unwrap();
    assert_eq!(world.coordinate_floor([4.0, 1.6, 0.0]), Some(0.0));
    assert_eq!(world.coordinate_floor([4.0, 3.0, 0.0]), Some(3.0));
    assert_eq!(world.coordinate_floor([4.0, 4.6, 0.0]), Some(3.0));
    assert_eq!(world.coordinate_floor([4.0, f32::NAN, 0.0]), None);
    let filled =
        Navigation::new(arena(vec![Solid::from_center_top(0.0, 0.0, 3.0, 3.0, 3.0)])).unwrap();
    assert_eq!(filled.coordinate_floor([0.0, 1.6, 0.0]), Some(3.0));
}

#[test]
fn overlapping_floors_route_under_and_onto_a_balcony_using_real_movement() {
    let world = Navigation::new(balcony()).unwrap();
    assert!(world.walkable([-2.0, 0.0, 0.0], [9.0, 0.0, 0.0]));
    assert_walks(&world, [-2.0, 0.0, 0.0], [9.0, 0.0, 0.0]);
    let below = [4.0, 0.0, 0.0];
    let above = [4.0, 3.0, 0.0];
    assert!(!world.walkable(below, above));
    assert!(!world.walkable(above, below));
    let route = world.route(below, above, SEARCH_LIMIT);
    assert_eq!(route.status, RouteStatus::Complete, "{route:?}");
    assert!(route.points.iter().any(|point| point[2] < -14.0));
    assert_eq!(route, world.route(below, above, SEARCH_LIMIT));
    assert_walks(&world, below, above);
    assert_walks(&world, above, below);
}

#[test]
fn an_isolated_upper_floor_has_only_a_downward_exit() {
    let world = Navigation::new(arena(vec![Solid::from_center_volume(
        0.0, 0.0, 3.0, 3.0, 2.4, 3.0,
    )]))
    .unwrap();
    assert_eq!(
        world.route([0.0; 3], [0.0, 3.0, 0.0], SEARCH_LIMIT).status,
        RouteStatus::Unreachable
    );
    assert_walks(&world, [-6.0, 0.0, 0.0], [6.0, 0.0, 0.0]);
    assert_walks(&world, [0.0, 3.0, 0.0], [0.0; 3]);
}

#[test]
fn routes_require_body_headroom_including_thin_overhead_barriers() {
    for bottom in [1.79, 1.8, 2.4] {
        let world = Navigation::new(arena(vec![Solid::from_center_volume(
            0.0, 0.0, 0.001, 12.0, bottom, 3.0,
        )]))
        .unwrap();
        let from = [-4.0, 0.0, 0.0];
        let to = [4.0, 0.0, 0.0];
        assert_eq!(world.walkable(from, to), bottom >= 1.8);
        if bottom >= 1.8 {
            assert_walks(&world, from, to);
        } else {
            assert_eq!(
                world.route(from, to, SEARCH_LIMIT).status,
                RouteStatus::Unreachable
            );
        }
    }
}

#[test]
fn covered_or_interior_surfaces_are_not_walkable_layers() {
    let world = Navigation::new(arena(vec![
        Solid::from_center_top(0.0, 0.0, 3.0, 3.0, 1.0),
        Solid::from_center_volume(0.0, 0.0, 3.0, 3.0, 0.5, 3.0),
        Solid::from_center_volume(0.0, 0.0, 3.0, 3.0, 4.0, 5.0),
    ]))
    .unwrap();
    for height in [0.0, 1.0, 3.0] {
        assert_eq!(
            world
                .route([0.0, height, 0.0], [7.0, 0.0, 0.0], SEARCH_LIMIT)
                .status,
            RouteStatus::InvalidPoint,
            "floor at {height} lies inside a solid or lacks headroom"
        );
    }
    assert_walks(&world, [0.0, 5.0, 0.0], [7.0, 0.0, 0.0]);
}

#[test]
fn excessive_layers_and_invalid_vertical_bounds_fail_before_readiness() {
    let slabs = (0..MAX_LAYERS)
        .map(|i| {
            let bottom = 2.4 + i as f32 * 3.0;
            Solid::from_center_volume(0.0, 0.0, 3.0, 3.0, bottom, bottom + 0.6)
        })
        .collect();
    assert_eq!(
        Navigation::new(arena(slabs)).unwrap_err(),
        "navigation layer or node limit exceeded"
    );
    for (bottom, top) in [(f32::NAN, 3.0), (-1.0, 3.0), (3.0, 3.0), (4.0, 3.0)] {
        assert_eq!(
            Navigation::new(arena(vec![Solid::from_center_volume(
                0.0, 0.0, 3.0, 3.0, bottom, top,
            )]))
            .unwrap_err(),
            "invalid solid bounds"
        );
    }
}
