use fragr_server::maps::{AuthoredMap, RuntimeMap};
use fragr_server::navigation::{RouteStatus, SEARCH_LIMIT};
use fragr_server::protocol::{EquipmentPolicy, ServerMessage};
use fragr_server::sim::GameState;
use serde_json::Value;

const SOURCE: &[u8] = include_bytes!("../maps/test/m16_freedom_development.json");

fn document() -> Value {
    serde_json::from_slice(SOURCE).unwrap()
}

fn feet(value: &Value) -> [f32; 3] {
    std::array::from_fn(|index| value[index].as_f64().unwrap() as f32)
}

#[test]
fn freedom_of_movement_development_stays_an_unconnected_foot_avenue() {
    assert!(
        !SOURCE.contains(&b'\r'),
        "development map must stay LF only"
    );
    let value = document();
    for key in [
        "mission", "m02", "m03", "m04", "m05", "m06", "m07", "m08", "m09", "m10", "m11", "m12",
        "m13", "vehicles",
    ] {
        assert!(
            value.get(key).is_none(),
            "{key} does not belong on this map"
        );
    }
    assert_eq!(value["version"], 1);
    assert_eq!(value["equipment"], "discovery");
    let map = AuthoredMap::read(SOURCE).expect("freedom development source");
    let world = RuntimeMap::Authored(map.clone());
    assert_eq!(world.id(), 1016);
    assert_eq!(world.name(), "Freedom of Movement (development)");
    assert_eq!(world.equipment_policy(), EquipmentPolicy::Discovery);
    assert!(world.mission().is_none());
    assert!(!world.has_authored_vehicles());
    let state = GameState::with_authored_map(map.clone());
    assert!(
        state.mission_state().is_none(),
        "campaign_mission_id must stay empty"
    );
    assert!(matches!(
        state.map_info(),
        ServerMessage::MapInfo { mission: None, .. }
    ));
    assert!(state.vehicles.is_empty());

    let ride_start = map.landmark("ride_start").expect("ride start");
    let barricade = map
        .landmark("side_pocket_barricade")
        .expect("barricade pocket");
    let checkpoint = map
        .landmark("side_pocket_checkpoint")
        .expect("checkpoint pocket");
    let transit = map.landmark("side_pocket_transit").expect("transit pocket");
    let forecourt = map.landmark("forecourt").expect("forecourt");
    let threshold = map.landmark("office_threshold").expect("office threshold");
    assert!(ride_start[0] < barricade[0] && ride_start[0] < transit[0]);
    assert!(barricade[0] < forecourt[0] && checkpoint[0] < forecourt[0]);
    assert!(transit[0] < forecourt[0]);
    assert!(forecourt[0] < threshold[0]);
    assert!(barricade[2] > 0.0 && transit[2] < 0.0);
    assert!(forecourt[2].abs() < 1.0 && threshold[2].abs() < 1.0);

    let entry = feet(&value["spawns"][0]["feet"]);
    let destinations = value["landmarks"]
        .as_array()
        .unwrap()
        .iter()
        .chain(value["supplies"].as_array().unwrap())
        .map(|point| feet(&point["feet"]))
        .chain(
            value["encounters"]
                .as_array()
                .unwrap()
                .iter()
                .flat_map(|group| group["enemies"].as_array().unwrap())
                .map(|enemy| {
                    feet(if enemy.get("hover").is_some() {
                        &enemy["hover"]["approach"]
                    } else {
                        &enemy["feet"]
                    })
                }),
        );
    for destination in destinations {
        for (from, to) in [(entry, destination), (destination, entry)] {
            assert_eq!(
                world.navigation().route(from, to, SEARCH_LIMIT).status,
                RouteStatus::Complete,
                "unreachable {from:?} to {to:?}"
            );
        }
    }
}
