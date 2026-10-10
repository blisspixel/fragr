use fragr_server::maps::{AuthoredMap, RuntimeMap};
use fragr_server::navigation::{RouteStatus, SEARCH_LIMIT};
use fragr_server::protocol::EquipmentPolicy;
use fragr_server::sim::GameState;
use serde_json::Value;

const SOURCE: &[u8] = include_bytes!("../maps/test/m15_civic_pressure_development.json");

const LANDMARKS: [&str; 6] = ["entry", "bowl", "arming", "exit", "podium", "placard_67"];

const KINDS: [&str; 9] = [
    "clerk",
    "sweeper",
    "heavy_sweeper",
    "notary",
    "turret",
    "auditor",
    "enforcer",
    "assessor",
    "crawler",
];

#[test]
fn civic_pressure_development_loads_the_stadium_graybox_without_a_mission() {
    assert!(
        !SOURCE.contains(&b'\r'),
        "development map must use LF line endings"
    );
    let text = std::str::from_utf8(SOURCE).expect("utf-8 map");
    assert!(!text.contains("article"));
    assert!(!text.contains("blade"));
    let value: Value = serde_json::from_slice(SOURCE).expect("json");
    assert_eq!(value["version"], 1);
    assert_eq!(value["map_id"], 1015);
    assert_eq!(value["name"], "Civic Pressure Valve (development)");
    assert_eq!(value["equipment"], "discovery");
    assert!(value.get("mission").is_none());
    assert!(value.get("m13").is_none());
    assert!(value.get("vehicles").is_none());
    let solids = value["solids"].as_array().expect("solids");
    assert!(solids.iter().any(|solid| solid["id"] == "gate_west_leaf"));
    assert!(solids.iter().any(|solid| solid["id"] == "gate_east_leaf"));
    assert!(solids.iter().any(|solid| solid["id"] == "plinth"));
    assert!(solids.iter().any(|solid| solid["id"] == "podium_block"));
    assert!(solids.iter().any(|solid| solid["id"] == "placard_post_67"));
    let encounters = value["encounters"].as_array().expect("encounters");
    assert!(encounters.len() >= 2);
    let mut previous: Option<&str> = None;
    for encounter in encounters {
        let id = encounter["id"].as_str().expect("encounter id");
        match previous {
            None => assert!(encounter.get("after").is_none()),
            Some(earlier) => assert_eq!(encounter["after"].as_str(), Some(earlier)),
        }
        for enemy in encounter["enemies"].as_array().expect("enemies") {
            let kind = enemy["kind"].as_str().expect("kind");
            assert!(KINDS.contains(&kind), "unexpected enemy kind {kind}");
        }
        previous = Some(id);
    }
    for supply in value["supplies"].as_array().expect("supplies") {
        let grant = &supply["grant"];
        if grant["kind"] == "weapon" {
            let weapon = grant["weapon"].as_str().expect("weapon");
            assert!(
                matches!(weapon, "tack" | "flechette" | "scatter" | "rail"),
                "unexpected weapon {weapon}"
            );
        }
    }

    let map = AuthoredMap::read(SOURCE).expect("civic pressure development map");
    let world = RuntimeMap::Authored(map.clone());
    assert_eq!(world.id(), 1015);
    assert_eq!(world.name(), "Civic Pressure Valve (development)");
    assert_eq!(world.equipment_policy(), EquipmentPolicy::Discovery);
    assert!(GameState::with_authored_map(map.clone())
        .mission_state()
        .is_none());
    assert!(world.mission().is_none());
    assert!(!world.has_authored_vehicles());
    let entry = map.landmark("entry").expect("entry");
    for id in LANDMARKS {
        let feet = map
            .landmark(id)
            .unwrap_or_else(|| panic!("missing landmark {id}"));
        assert_eq!(
            world.navigation().route(entry, feet, SEARCH_LIMIT).status,
            RouteStatus::Complete,
            "{id} is not on a walking route from entry"
        );
    }
}
