use super::*;
use crate::protocol::{validate_map_presentation, MapPresentation, MapSurface};
use serde_json::json;

fn panel() -> MapDecoration {
    MapDecoration {
        solid: 0,
        face: MapFace::North,
        center: [0.0, 0.0],
        size: [2.0, 1.0],
        kind: MapDecorationKind::RecordsSign,
    }
}

#[test]
fn face_extents_and_finite_rectangles_are_enforced() {
    let solid = Solid::from_center_volume(2.0, 4.0, 3.0, 5.0, 1.0, 5.0);
    for (face, dimensions) in [
        (MapFace::North, [6.0, 4.0]),
        (MapFace::South, [6.0, 4.0]),
        (MapFace::West, [10.0, 4.0]),
        (MapFace::East, [10.0, 4.0]),
        (MapFace::Up, [6.0, 10.0]),
        (MapFace::Down, [6.0, 10.0]),
    ] {
        assert_eq!(face.dimensions(&solid), dimensions);
        let detail = MapDecoration {
            face,
            size: dimensions,
            ..panel()
        };
        assert!(validate_decorations(std::slice::from_ref(&detail), &[solid]).is_ok());
        for axis in 0..2 {
            let mut outside = detail.clone();
            outside.center[axis] = 0.001;
            assert!(validate_decorations(&[outside], &[solid]).is_err());
        }
    }
    for value in [f32::NAN, f32::INFINITY, f32::NEG_INFINITY] {
        for axis in 0..2 {
            let mut detail = panel();
            detail.center[axis] = value;
            assert!(validate_decorations(&[detail], &[solid]).is_err());
            let mut detail = panel();
            detail.size[axis] = value;
            assert!(validate_decorations(&[detail], &[solid]).is_err());
        }
    }
    for size in [-1.0, 0.0, 0.124, 16.01] {
        assert!(validate_decorations(
            &[MapDecoration {
                size: [size, 1.0],
                ..panel()
            }],
            &[solid]
        )
        .is_err());
    }
    assert!(validate_decorations(
        &[MapDecoration {
            solid: 1,
            ..panel()
        }],
        &[solid]
    )
    .is_err());
    assert!(validate_decorations(
        &[panel()],
        &[Solid {
            top: f32::NAN,
            ..solid
        }]
    )
    .is_err());
    assert!(validate_decorations(
        &[panel()],
        &[Solid {
            top: solid.bottom,
            ..solid
        }]
    )
    .is_err());
}

#[test]
fn light_and_panel_budgets_are_independent() {
    let solids = [Solid::from_center(0.0, 0.0, 8.0, 8.0)];
    assert!(validate_decorations(&vec![panel(); MAX_MAP_DECORATIONS], &solids).is_ok());
    assert!(validate_decorations(&vec![panel(); MAX_MAP_DECORATIONS + 1], &solids).is_err());
    let light = MapDecoration {
        kind: MapDecorationKind::StripLight,
        ..panel()
    };
    assert!(validate_decorations(&vec![light.clone(); MAX_MAP_LIGHTS], &solids).is_ok());
    assert!(validate_decorations(&vec![light; MAX_MAP_LIGHTS + 1], &solids).is_err());
}

#[test]
fn wire_is_strict_but_old_presentation_stays_unchanged() {
    let mut value = serde_json::to_value(panel()).unwrap();
    for (field, bad) in [
        ("kind", json!("res://script.gd")),
        ("face", json!("diagonal")),
        ("solid", json!(-1)),
        ("solid", json!("ceiling")),
        ("center", json!([0, 0, 0])),
        ("size", json!(null)),
        ("extra", json!(1)),
    ] {
        let mut malformed = value.clone();
        malformed[field] = bad;
        assert!(serde_json::from_value::<MapDecoration>(malformed).is_err());
    }
    value["solid"] = json!("ceiling");
    let authored: MapDecoration<String> = serde_json::from_value(value).unwrap();
    assert_eq!(authored.with_solid(0), panel());
    let old = json!({"ground":"concrete", "solids":["enamel"]});
    let mut presentation: MapPresentation = serde_json::from_value(old.clone()).unwrap();
    assert!(presentation.decorations.is_empty());
    assert_eq!(serde_json::to_value(&presentation).unwrap(), old);
    let solids = [Solid::from_center(0.0, 0.0, 8.0, 8.0)];
    presentation.decorations.push(panel());
    assert!(validate_map_presentation(Some(&presentation), &solids).is_ok());
    presentation.decorations[0].solid = 1;
    assert!(validate_map_presentation(Some(&presentation), &solids).is_err());
    assert!(validate_map_presentation(None, &solids).is_ok());
    assert_eq!(presentation.ground, MapSurface::Concrete);
}
