use fragr_server::maps::{AuthoredMap, RuntimeMap};
use fragr_server::movement::{BODY_HEIGHT, CONTACT_EPSILON, EYE_HEIGHT};
use fragr_server::navigation::{NavigationGoal, Navigator, RouteStatus, SEARCH_LIMIT};
use fragr_server::protocol::{Action, EquipmentPolicy, Role};
use fragr_server::sim::{GameState, PLAYER_FLOOR_Y};
use serde_json::Value;
use std::sync::Arc;
use uuid::Uuid;

const SOURCE: &[u8] = include_bytes!("../maps/test/m18_recovery_development.json");

const LANDMARKS: [&str; 4] = [
    "transit_square",
    "clinic_route",
    "maintenance_escape",
    "district_overlook",
];

fn document() -> Value {
    serde_json::from_slice(SOURCE).unwrap()
}

fn feet(value: &Value) -> [f32; 3] {
    std::array::from_fn(|index| value[index].as_f64().unwrap() as f32)
}

fn unpopulated() -> Arc<AuthoredMap> {
    let mut value = document();
    value["encounters"] = serde_json::json!([]);
    AuthoredMap::read(serde_json::to_vec(&value).unwrap().as_slice()).unwrap()
}

#[test]
fn recovery_development_reads_without_a_mission() {
    assert!(
        !SOURCE.contains(&b'\r'),
        "recovery development source must stay LF only"
    );
    let text = std::str::from_utf8(SOURCE).unwrap();
    assert!(
        !text.to_ascii_lowercase().contains("collector"),
        "Collector is not an enemy kind"
    );
    let value = document();
    for key in [
        "mission", "m02", "m03", "m04", "m05", "m06", "m07", "m08", "m09", "m10", "m11", "m12",
        "m13",
    ] {
        assert!(value.get(key).is_none(), "{key} must stay absent");
    }
    assert!(value["supplies"]
        .as_array()
        .unwrap()
        .iter()
        .all(|supply| { supply["grant"]["kind"] != "weapon" }));

    let map = AuthoredMap::read(SOURCE).expect("strict recovery development source");
    let runtime = RuntimeMap::Authored(map.clone());
    assert_eq!(runtime.id(), 1018);
    assert_eq!(runtime.name(), "All Systems Normal (development)");
    assert_eq!(runtime.equipment_policy(), EquipmentPolicy::Discovery);
    assert!(GameState::with_authored_map(map.clone())
        .mission_state()
        .is_none());
    assert!(runtime.mission().is_none());
    assert_eq!(value["landmarks"].as_array().unwrap().len(), 4);
    for id in LANDMARKS {
        assert!(map.landmark(id).is_some(), "missing landmark {id}");
    }
    for id in [
        "tram_car",
        "clinic_barricade",
        "passage_lintel",
        "overlook_deck",
    ] {
        assert!(
            value["solids"]
                .as_array()
                .unwrap()
                .iter()
                .any(|solid| solid["id"] == id),
            "missing solid {id}"
        );
    }

    let square = map.landmark("transit_square").unwrap();
    let spawn = feet(&value["spawns"][0]["feet"]);
    for encounter in value["encounters"].as_array().unwrap() {
        for region in encounter["regions"].as_array().unwrap() {
            let min = feet(&region["min"]);
            let max = feet(&region["max"]);
            for point in [spawn, square] {
                let inside =
                    (0..3).all(|axis| point[axis] >= min[axis] && point[axis] <= max[axis]);
                assert!(!inside, "arrival sits inside {}", encounter["id"]);
            }
        }
        for enemy in encounter["enemies"].as_array().unwrap() {
            let kind = enemy["kind"].as_str().unwrap();
            assert!(
                kind == "sweeper" || kind == "heavy_sweeper",
                "unexpected enemy kind {kind}"
            );
            assert!(
                feet(&enemy["feet"])[2] > square[2],
                "enemy {} is not past the recovery square",
                enemy["id"]
            );
        }
    }

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
                .map(|enemy| feet(&enemy["feet"])),
        );
    for destination in destinations {
        for (from, to) in [(entry, destination), (destination, entry)] {
            assert_eq!(
                runtime.navigation().route(from, to, SEARCH_LIMIT).status,
                RouteStatus::Complete,
                "unreachable {from:?} to {to:?}"
            );
        }
    }

    let eye = [square[0], square[1] + EYE_HEIGHT, square[2]];
    let tower_face = [5.6, 8.2, 21.6];
    assert!(
        fragr_server::combat::line_of_sight(eye, tower_face, &runtime.arena().solids),
        "overlook tower is hidden from the recovery square"
    );
}

#[test]
fn recovery_route_walks_the_four_beats_without_a_jump() {
    let mut state = GameState::with_authored_map(unpopulated());
    let id = Uuid::from_u128(1018);
    state.add_player(id, "Recovery development route".into(), Role::Human);
    state.start_round();
    let mut navigator = Navigator::default();
    for destination in [
        [0.0, 0.0, -16.0],
        [2.0, 0.0, -0.5],
        [0.0, 0.0, -16.0],
        [-12.0, 0.0, -10.0],
        [-12.0, 0.0, 10.0],
        [-12.0, 3.0, 27.0],
        [-6.0, 3.0, 29.0],
    ] {
        let mut arrived = false;
        for _ in 0..1800 {
            let player = state.players.iter().find(|player| player.id == id).unwrap();
            let feet = [player.x, player.y - PLAYER_FLOOR_Y, player.z];
            if (feet[0] - destination[0]).hypot(feet[2] - destination[2]) <= 0.3
                && (feet[1] - destination[1]).abs() <= 0.04
            {
                arrived = true;
                break;
            }
            let action = navigator.steer(
                state.map.navigation(),
                feet,
                NavigationGoal {
                    feet: destination,
                    combat: false,
                },
                Action::default(),
                state.tick,
                true,
            );
            assert!(!action.jump, "ordinary recovery route requires a jump");
            state.set_action(id, action);
            state.tick(0.05);
            state.take_events();
            let player = state.players.iter().find(|player| player.id == id).unwrap();
            assert_eq!(player.hp, 100, "route changed health");
            let bottom = player.y - PLAYER_FLOOR_Y;
            assert!(
                !state.current_arena().solids.iter().any(|solid| {
                    solid.covers(player.x, player.z)
                        && solid.top > bottom + CONTACT_EPSILON
                        && solid.bottom < bottom + BODY_HEIGHT - CONTACT_EPSILON
                }),
                "body entered a recovery solid"
            );
        }
        let player = state.players.iter().find(|player| player.id == id).unwrap();
        assert!(
            arrived,
            "route stalled at {:?} before {destination:?}",
            [player.x, player.y - PLAYER_FLOOR_Y, player.z]
        );
    }
}
