//! Small translating-platform helper. Ordinary movement integration is unchanged.
use crate::movement::{Arena, MoveState, Solid, BODY_HEIGHT, RADIUS};

pub(crate) const SUPPORT_EPSILON: f32 = 0.05;
pub(crate) fn supported(body: MoveState, tram: Solid, jumping: bool) -> bool {
    !jumping
        && body.vy.abs() <= 0.001
        && (body.y - tram.top).abs() <= SUPPORT_EPSILON
        && tram.covers(body.x, body.z)
}
pub(crate) fn carried(body: MoveState, delta_z: f32, other: &Arena) -> Option<MoveState> {
    if !delta_z.is_finite() || delta_z.abs() > 0.0751 {
        return None;
    }
    let to = body.z + delta_z;
    if body.x.abs() > other.half - RADIUS || to.abs() > other.half - RADIUS {
        return None;
    }
    // Sweep the complete body, including its old and new radius footprints.
    if other.solids.iter().any(|s| {
        body.x + RADIUS > s.min_x
            && body.x - RADIUS < s.max_x
            && body.z.min(to) - RADIUS < s.max_z
            && body.z.max(to) + RADIUS > s.min_z
            && body.y + BODY_HEIGHT > s.bottom
            && body.y < s.top
    }) {
        return None;
    }
    Some(MoveState { z: to, ..body })
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn shared_m05_tram_carrier_goldens() {
        let fixture: serde_json::Value = serde_json::from_str(include_str!(
            "../../../../client/golden/m05_tram_vectors.json"
        ))
        .unwrap();
        let tram: Solid = serde_json::from_value(fixture["tram"].clone()).unwrap();
        for case in fixture["cases"].as_array().unwrap() {
            let mut body = fixture["body"].clone();
            for (key, value) in case["body"].as_object().unwrap() {
                body[key] = value.clone();
            }
            let body: MoveState = serde_json::from_value(body).unwrap();
            assert_eq!(
                supported(body, tram, case["jump"].as_bool().unwrap()),
                case["supported"].as_bool().unwrap(),
                "{}",
                case["name"]
            );
            let arena = Arena {
                half: fixture["half"].as_f64().unwrap() as f32,
                solids: serde_json::from_value(case["solids"].clone()).unwrap(),
            };
            let actual = carried(body, case["delta"].as_f64().unwrap() as f32, &arena).map(|b| b.z);
            let expected = case["carried_z"].as_f64().map(|v| v as f32);
            assert_eq!(actual.is_some(), expected.is_some(), "{}", case["name"]);
            if let (Some(actual), Some(expected)) = (actual, expected) {
                assert!((actual - expected).abs() < 0.0001, "{}", case["name"]);
            }
        }
    }
    #[test]
    fn rider_support_jump_edge_and_swept_clearance() {
        let tram = Solid::from_center_top(0.0, 0.0, 1.5, 2.0, 1.0);
        let body = MoveState {
            x: 0.0,
            y: 1.0,
            z: 0.0,
            vx: 0.0,
            vz: 0.0,
            vy: 0.0,
            yaw: 0.0,
        };
        assert!(supported(body, tram, false));
        assert!(!supported(body, tram, true));
        assert!(
            supported(MoveState { x: 1.4, ..body }, tram, false),
            "ordinary movement supports center feet near a deck edge"
        );
        assert!(!supported(MoveState { x: 1.6, ..body }, tram, false));
        assert!(!supported(MoveState { vy: 1.0, ..body }, tram, false));
        let mut world = Arena {
            half: 20.0,
            solids: Vec::new(),
        };
        assert_eq!(carried(body, 0.05, &world).unwrap().z, 0.05);
        world
            .solids
            .push(Solid::from_center_volume(0.0, 0.0, 3.0, 3.0, 2.0, 3.0));
        assert!(
            carried(body, 0.05, &world).is_none(),
            "ceiling blocks rider"
        );
        assert!(carried(
            body,
            0.2,
            &Arena {
                half: 20.0,
                solids: Vec::new()
            }
        )
        .is_none());
    }
}
