use super::tests::{decode, small};
use serde_json::json;

fn document() -> serde_json::Value {
    let mut doc = small();
    doc["equipment"] = json!("discovery");
    doc["encounters"] = json!([{
        "id":"intake", "regions":[{"min":[-2,0,-2],"max":[2,2,0]}],
        "enemies":[{"id":"clerk","kind":"clerk","feet":[0,0,3],"yaw":0}]
    }, {
        "id":"reinforcements", "after":"intake",
        "regions":[{"min":[-2,0,0],"max":[2,2,2]}],
        "enemies":[{"id":"sweeper","kind":"sweeper","feet":[2,0,3],"yaw":0}]
    }]);
    doc
}

#[test]
fn encounter_dependencies_and_placements_validate_before_startup() {
    let doc = document();
    let map = decode(&doc).unwrap();
    assert_eq!(map.encounters.len(), 2);
    let region = &map.encounters[0].regions[0];
    assert!(region.contains([-2.0, 0.0, -2.0]));
    assert!(region.contains([2.0, 2.0, 0.0]));
    assert!(!region.contains([0.0, 3.0, -1.0]));
    for (pointer, value) in [
        ("/equipment", json!("full_arsenal")),
        ("/encounters/0/id", json!("ceiling")),
        ("/encounters/1/after", json!("reinforcements")),
        ("/encounters/1/after", json!("missing")),
        ("/encounters/1/after", json!("clerk")),
        ("/encounters/1/id", json!("intake")),
        ("/encounters/0/regions", json!([])),
        ("/encounters/0/enemies", json!([])),
        ("/encounters/0/regions/0/min", json!([0, 0, 0])),
        ("/encounters/0/regions/0/max", json!([9, 2, 0])),
        ("/encounters/0/regions/0/min", json!([-2, -1, -2])),
        ("/encounters/0/enemies/0/id", json!("entry")),
        ("/encounters/0/enemies/0/kind", json!("crawler")),
        ("/encounters/0/enemies/0/feet", json!([0, 1, 0])),
        ("/encounters/0/enemies/0/yaw", json!(7)),
    ] {
        let mut bad = doc.clone();
        *bad.pointer_mut(pointer).unwrap() = value;
        assert!(decode(&bad).is_err(), "accepted {pointer}");
    }
    for pointer in [
        "/encounters/0",
        "/encounters/0/regions/0",
        "/encounters/0/enemies/0",
    ] {
        let mut bad = doc.clone();
        bad.pointer_mut(pointer).unwrap()["unexpected"] = json!(true);
        assert!(decode(&bad).is_err());
    }
    let mut forward = doc.clone();
    forward["encounters"][0]["after"] = json!("reinforcements");
    assert!(decode(&forward).is_err());
}

#[test]
fn encounter_counts_and_unreachable_enemies_are_rejected() {
    let doc = document();
    for (pointer, count) in [
        ("/encounters", 33),
        ("/encounters/0/regions", 65),
        ("/encounters/0/enemies", 65),
    ] {
        let mut bad = doc.clone();
        let entries = bad.pointer_mut(pointer).unwrap();
        *entries = json!(vec![entries[0].clone(); count]);
        assert!(decode(&bad).unwrap_err().to_string().contains("bounded"));
    }
    let mut blocked = doc;
    blocked["landmarks"][0]["feet"] = json!([0, 0, -3]);
    blocked["solids"].as_array_mut().unwrap().push(json!({
        "id":"divider","min":[-8,0,-1],"max":[8,3,0],"surface":"enamel"
    }));
    assert!(decode(&blocked)
        .unwrap_err()
        .to_string()
        .contains("unreachable"));
}
