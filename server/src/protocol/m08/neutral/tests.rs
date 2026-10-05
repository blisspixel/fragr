use super::*;
use crate::maps::AuthoredSource;
use crate::protocol::MissionId;
use serde::Deserialize;

#[derive(Deserialize)]
struct Vectors {
    cases: Vec<Vector>,
}
#[derive(Deserialize)]
struct Vector {
    name: String,
    half: f32,
    solids: Vec<Solid>,
    presentation: MapPresentation,
    expected: Expected,
}
#[derive(Deserialize)]
struct Expected {
    renn: [f32; 3],
    held: [[f32; 3]; 4],
    released: [[f32; 3]; 4],
}

#[test]
fn m08_neutral_shared_panel_vectors_and_authored_archive_agree() {
    let vectors: Vectors = serde_json::from_str(include_str!(
        "../../../../../client/golden/m08_neutral_body_vectors.json"
    ))
    .unwrap();
    for vector in vectors.cases {
        let layout =
            M08NeutralLayout::read(vector.half, &vector.solids, &vector.presentation).unwrap();
        for (actual, expected) in std::iter::once(layout.renn)
            .chain(layout.held)
            .chain(layout.released)
            .zip(
                std::iter::once(vector.expected.renn)
                    .chain(vector.expected.held)
                    .chain(vector.expected.released),
            )
        {
            for axis in 0..3 {
                assert!(
                    (actual[axis] - expected[axis]).abs() < 0.00001,
                    "{} {actual:?} != {expected:?}",
                    vector.name
                );
            }
        }
        if vector.name == "authored_archive" {
            let map = crate::maps::RuntimeMap::Authored(
                AuthoredSource::Mission(MissionId::CustodianOfRecord)
                    .load()
                    .unwrap(),
            );
            let actual = M08NeutralLayout::read(
                map.arena().half,
                &map.arena().solids,
                map.presentation_ref().unwrap(),
            )
            .unwrap();
            assert_eq!(
                actual, layout,
                "goldens bind actual authored panel placement"
            );
            let old_renn = [actual.renn[0], actual.renn[1], actual.renn[2] - 0.02];
            assert!(
                map.arena()
                    .blocked_body_at(old_renn[0], old_renn[2], old_renn[1], old_renn[1]),
                "negative control reproduces inherited 12 mm desk overlap"
            );
            for old_x in [-3.0, 3.0] {
                let old = [old_x, 0.0, actual.released[0][2]];
                assert!(
                    map.arena().blocked_body_at(old[0], old[2], old[1], old[1]),
                    "negative control reproduces inherited outer crate overlap"
                );
            }
            for pair in actual.released.windows(2) {
                assert!(
                    pair[1][0] - pair[0][0] >= 1.49,
                    "released bodies remain separated"
                );
            }
            for feet in std::iter::once(actual.renn)
                .chain(actual.held)
                .chain(actual.released)
            {
                assert!(
                    !map.arena()
                        .blocked_body_at(feet[0], feet[2], feet[1], feet[1]),
                    "neutral feet inside solid: {feet:?}"
                );
                assert!(
                    (map.arena().support_height(feet[0], feet[2], feet[1]) - feet[1]).abs() < 0.001,
                    "neutral feet unsupported: {feet:?}"
                );
            }
        }
    }
}

#[test]
fn m08_neutral_rejects_missing_duplicate_invalid_and_outside_panels() {
    let map = crate::maps::RuntimeMap::Authored(
        AuthoredSource::Mission(MissionId::CustodianOfRecord)
            .load()
            .unwrap(),
    );
    let arena = map.arena();
    let original = map.presentation_ref().unwrap();
    for kind in [
        MapDecorationKind::M08Registry,
        MapDecorationKind::M08BayRelease,
        MapDecorationKind::M08FreightDeparture,
    ] {
        let mut missing = original.clone();
        missing.decorations.retain(|d| d.kind != kind);
        assert!(M08NeutralLayout::read(arena.half, &arena.solids, &missing).is_err());
        let mut duplicate = original.clone();
        duplicate.decorations.push(
            original
                .decorations
                .iter()
                .find(|d| d.kind == kind)
                .unwrap()
                .clone(),
        );
        assert!(M08NeutralLayout::read(arena.half, &arena.solids, &duplicate).is_err());
    }
    let mut bad = original.clone();
    bad.decorations
        .iter_mut()
        .find(|d| d.kind == MapDecorationKind::M08Registry)
        .unwrap()
        .solid = usize::MAX;
    assert!(M08NeutralLayout::read(arena.half, &arena.solids, &bad).is_err());
    for half in [f32::NAN, 0.0, 2.0] {
        assert!(M08NeutralLayout::read(half, &arena.solids, original).is_err());
    }
}
