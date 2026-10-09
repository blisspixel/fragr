use fragr_server::maps::{AuthoredMap, RuntimeMap};
use fragr_server::navigation::{RouteStatus, SEARCH_LIMIT};
use fragr_server::protocol::EquipmentPolicy;
use fragr_server::sim::GameState;

const SOURCE: &[u8] = include_bytes!("../maps/test/m20_local_exception_development.json");

const ROUTE: &[&str] = &[
    "waterworks",
    "freight_pier",
    "refuge_approach",
    "approach_waterworks",
    "approach_freight_yard",
    "approach_tram_trench",
];

fn feet(value: &serde_json::Value) -> [f32; 3] {
    std::array::from_fn(|index| value[index].as_f64().unwrap() as f32)
}

#[test]
fn local_exception_development_loads_the_route_without_a_mission() {
    assert!(
        !SOURCE.contains(&b'\r'),
        "development map must use LF line endings"
    );
    let doc: serde_json::Value = serde_json::from_slice(SOURCE).unwrap();
    assert_eq!(doc["version"], 1);
    assert_eq!(doc["map_id"], 1020);
    assert_eq!(doc["name"], "Local Exception (development)");
    assert_eq!(doc["equipment"], "discovery");
    assert!(doc.get("mission").is_none());
    assert!(!SOURCE.windows(9).any(|bytes| bytes == b"surveyor"));
    let solid_ids: Vec<&str> = doc["solids"]
        .as_array()
        .unwrap()
        .iter()
        .map(|solid| solid["id"].as_str().unwrap())
        .collect();
    for id in [
        "waterworks_tower",
        "sluice_north",
        "sluice_south",
        "pier_north_west",
        "pier_crane",
        "refuge_gate",
        "freight_platform",
        "yard_west",
        "yard_east",
        "trench_west",
        "trench_east",
        "waterworks_approach_north",
        "waterworks_approach_south",
    ] {
        assert!(solid_ids.contains(&id), "missing solid {id}");
    }

    let map = AuthoredMap::read(SOURCE).expect("local exception development map");
    let world = RuntimeMap::Authored(map.clone());
    assert_eq!(world.id(), 1020);
    assert_eq!(world.name(), "Local Exception (development)");
    assert_eq!(world.equipment_policy(), EquipmentPolicy::Discovery);
    assert!(GameState::with_authored_map(map.clone())
        .mission_state()
        .is_none());

    let entry = feet(&doc["spawns"][0]["feet"]);
    let pier = map.landmark("freight_pier").expect("freight pier");
    for id in ROUTE {
        let place = map
            .landmark(id)
            .unwrap_or_else(|| panic!("missing route landmark {id}"));
        assert_eq!(
            world.navigation().route(entry, place, SEARCH_LIMIT).status,
            RouteStatus::Complete,
            "{id} is not reachable from the entry"
        );
        if id.starts_with("approach_") {
            let distance = (place[0] - pier[0]).hypot(place[2] - pier[2]);
            assert!(
                distance <= 14.0,
                "{id} does not meet the pier (distance {distance})"
            );
            assert_eq!(
                world.navigation().route(pier, place, SEARCH_LIMIT).status,
                RouteStatus::Complete,
                "{id} does not meet the pier by a walking route"
            );
        }
    }
}
