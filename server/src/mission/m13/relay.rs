//! One resolved face hit disables the relay. The protected feed is not a target.
use crate::movement::Solid;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Hit {
    Relay,
    Protected,
    Other,
}

pub fn classify(solid: usize, relay: usize, protected: &[usize]) -> Hit {
    if solid == relay {
        Hit::Relay
    } else if protected.contains(&solid) {
        Hit::Protected
    } else {
        Hit::Other
    }
}

/// The impact lies on one axis-aligned face. A point inside the housing, or a
/// reach toward it, is not a shot.
pub fn on_face(end: [f32; 3], normal: [f32; 3], solid: &Solid) -> bool {
    let min = [solid.min_x, solid.bottom, solid.min_z];
    let max = [solid.max_x, solid.top, solid.max_z];
    if (0..3).any(|axis| {
        !end[axis].is_finite()
            || !normal[axis].is_finite()
            || end[axis] < min[axis] - 0.001
            || end[axis] > max[axis] + 0.001
    }) {
        return false;
    }
    (0..3).any(|axis| {
        (normal[axis].abs() - 1.0).abs() < 0.001
            && (0..3)
                .filter(|other| *other != axis)
                .all(|other| normal[other].abs() < 0.001)
            && (end[axis]
                - if normal[axis] < 0.0 {
                    min[axis]
                } else {
                    max[axis]
                })
            .abs()
                < 0.001
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn housing() -> Solid {
        Solid {
            min_x: -36.8,
            max_x: -35.7,
            min_z: 9.0,
            max_z: 11.0,
            bottom: 0.3,
            top: 2.0,
        }
    }

    #[test]
    fn only_a_face_impact_is_the_relay() {
        let solid = housing();
        assert!(on_face([-35.7, 1.0, 10.0], [1.0, 0.0, 0.0], &solid));
        assert!(!on_face([-36.2, 1.0, 10.0], [1.0, 0.0, 0.0], &solid));
        assert!(!on_face([-35.7, 1.0, 10.0], [0.0, 1.0, 0.0], &solid));
        assert!(!on_face([-30.0, 1.0, 10.0], [1.0, 0.0, 0.0], &solid));
        assert_eq!(classify(3, 3, &[4, 5]), Hit::Relay);
        assert_eq!(classify(4, 3, &[4, 5]), Hit::Protected);
        assert_eq!(classify(9, 3, &[4, 5]), Hit::Other);
    }
}
