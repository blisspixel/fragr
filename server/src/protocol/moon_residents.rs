//! The bounded static people already drawn in the port family room and town
//! window. These are physical neutral bodies, not additional rescue facts.
use super::{MapDecorationKind, MapFace, MapPresentation, MissionId};
use crate::movement::Solid;

pub(crate) fn moon_residents(
    id: MissionId,
    half: f32,
    solids: &[Solid],
    presentation: &MapPresentation,
) -> Result<Vec<(String, [f32; 3])>, &'static str> {
    let (kind, prefix, count) = match id {
        MissionId::PortOfEntry => (MapDecorationKind::M06FamilyWindow, "m06/resident/", 2),
        MissionId::DeclaredGoods => (MapDecorationKind::M07WindowFigure, "m07/resident/", 1),
        _ => return Ok(Vec::new()),
    };
    super::validate_decorations(&presentation.decorations, solids)?;
    let mut matches = presentation.decorations.iter().filter(|d| d.kind == kind);
    let Some(detail) = matches.next() else {
        return Ok(Vec::new());
    };
    if matches.next().is_some() {
        return Err("resident panel duplicated");
    }
    let host = &solids[detail.solid];
    let out = match detail.face {
        MapFace::West => [-1.0, 0.0, 0.0],
        MapFace::East => [1.0, 0.0, 0.0],
        MapFace::North => [0.0, 0.0, -1.0],
        MapFace::South => [0.0, 0.0, 1.0],
        _ => return Err("resident panel must face a wall"),
    };
    let mut result = Vec::with_capacity(count);
    for i in 0..count {
        let feet = if id == MissionId::PortOfEntry {
            [
                (host.min_x + host.max_x) * 0.5 - out[0] * 3.0 + 0.8,
                0.0,
                (host.min_z + host.max_z) * 0.5 - out[2] * 3.0 - 0.5 + i as f32 * 3.0,
            ]
        } else {
            let point = detail.point(host);
            let thickness =
                (out[0] * (host.max_x - host.min_x) + out[2] * (host.max_z - host.min_z)).abs();
            [
                point[0] - out[0] * (0.012 + thickness + 0.7),
                host.bottom - 1.0,
                point[2] - out[2] * (0.012 + thickness + 0.7),
            ]
        };
        if !half.is_finite()
            || feet.iter().any(|v| !v.is_finite())
            || feet[0].abs() > half
            || feet[2].abs() > half
            || !(0.0..=512.0).contains(&feet[1])
        {
            return Err("resident feet outside map");
        }
        result.push((format!("{prefix}{i}"), feet));
    }
    Ok(result)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::maps::{AuthoredSource, RuntimeMap};
    #[test]
    fn moon_residents_shared_goldens_and_invalid_panels() {
        let vectors: serde_json::Value = serde_json::from_str(include_str!(
            "../../../client/golden/moon_resident_body_vectors.json"
        ))
        .unwrap();
        for case in vectors["cases"].as_array().unwrap() {
            let id = if case["map_id"] == 1006 {
                MissionId::PortOfEntry
            } else {
                MissionId::DeclaredGoods
            };
            let solids: Vec<Solid> = serde_json::from_value(case["solids"].clone()).unwrap();
            let presentation: MapPresentation =
                serde_json::from_value(case["presentation"].clone()).unwrap();
            let half = case["half_extent"].as_f64().unwrap() as f32;
            let people = moon_residents(id, half, &solids, &presentation).unwrap();
            for ((_, feet), expected) in people.iter().zip(case["expected"].as_array().unwrap()) {
                for axis in 0..3 {
                    assert!((feet[axis] - expected[axis].as_f64().unwrap() as f32).abs() < 0.00001);
                }
            }
            let mut bad = presentation.clone();
            bad.decorations.push(bad.decorations[0].clone());
            assert!(moon_residents(id, half, &solids, &bad).is_err());
            bad = presentation.clone();
            bad.decorations[0].face = MapFace::Up;
            assert!(moon_residents(id, half, &solids, &bad).is_err());
            assert!(moon_residents(id, 2.0, &solids, &presentation).is_err());
            let mut absent = presentation.clone();
            absent.decorations.clear();
            assert!(moon_residents(id, half, &solids, &absent)
                .unwrap()
                .is_empty());
            assert!(
                moon_residents(MissionId::CustodianOfRecord, half, &solids, &presentation)
                    .unwrap()
                    .is_empty()
            );
        }
    }
    #[test]
    fn moon_residents_actual_supported_room_feet_and_glass_are_authoritative() {
        for (id, expected) in [
            (
                MissionId::PortOfEntry,
                vec![[-36.7, 0.0, 17.0], [-36.7, 0.0, 20.0]],
            ),
            (MissionId::DeclaredGoods, vec![[-43.7, 0.0, -19.5]]),
        ] {
            let map = RuntimeMap::Authored(AuthoredSource::Mission(id).load().unwrap());
            let arena = map.arena();
            let people = moon_residents(
                id,
                arena.half,
                &arena.solids,
                map.presentation_ref().unwrap(),
            )
            .unwrap();
            assert_eq!(people.len(), expected.len());
            for ((_, feet), expected) in people.iter().zip(expected) {
                for axis in 0..3 {
                    assert!((feet[axis] - expected[axis]).abs() < 0.00001);
                }
                assert!(!arena.blocked_body_at(feet[0], feet[2], feet[1], feet[1]));
                assert!((arena.support_height(feet[0], feet[2], feet[1]) - feet[1]).abs() < 0.001);
                // The ordinary street-side ray reaches the existing glass
                // first. Registering residents does not remove that cover.
                let ray = crate::combat::Ray {
                    origin: [feet[0] + 8.0, feet[1] + 1.5, feet[2]],
                    direction: [-1.0, 0.0, 0.0],
                };
                assert!(arena.solids.iter().any(|s| ray.solid(s, 8.0).is_some()));
            }
        }
    }
}
