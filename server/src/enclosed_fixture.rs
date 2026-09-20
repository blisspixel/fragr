//! Shared engineering fixture, not campaign content or a multiplayer map.

use crate::movement::{Arena, Solid};

pub(crate) fn balcony() -> Arena {
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

pub(crate) fn room() -> Arena {
    let mut arena = balcony();
    arena.solids.extend([
        Solid::from_center_volume(2.0, -5.0, 10.5, 12.5, 6.0, 6.6),
        Solid::from_center_top(-8.0, -5.0, 0.5, 12.5, 6.6),
        Solid::from_center_top(12.0, -5.0, 0.5, 12.5, 6.6),
        Solid::from_center_top(2.0, -17.0, 10.5, 0.5, 6.6),
        Solid::from_center_top(2.0, 7.0, 10.5, 0.5, 6.6),
    ]);
    arena
}
