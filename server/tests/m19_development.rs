use fragr_server::maps::{AuthoredMap, RuntimeMap};
use fragr_server::movement::{BODY_HEIGHT, CONTACT_EPSILON};
use fragr_server::navigation::{NavigationGoal, Navigator, RouteStatus, SEARCH_LIMIT};
use fragr_server::protocol::{Action, EquipmentPolicy, Role};
use fragr_server::sim::{GameState, PLAYER_FLOOR_Y};
use serde_json::Value;
use uuid::Uuid;

const SOURCE: &[u8] = include_bytes!("../maps/test/m19_planned_works_development.json");

const LANDMARKS: &[&str] = &[
    "evacuation_concourse",
    "concourse_crossing",
    "changed_home_street",
    "roof_loop_east",
    "marked_roof_street",
    "roof_loop_west",
    "latch_departure",
    "demolition_marks",
    "trench_mouth",
];

fn document() -> Value {
    serde_json::from_slice(SOURCE).unwrap()
}

fn point(value: &Value) -> [f32; 3] {
    std::array::from_fn(|i| value[i].as_f64().unwrap() as f32)
}

fn feet(state: &GameState, id: Uuid) -> [f32; 3] {
    let player = state.players.iter().find(|player| player.id == id).unwrap();
    [player.x, player.y - PLAYER_FLOOR_Y, player.z]
}

#[test]
fn planned_works_development_is_not_a_mission_and_the_ground_route_reaches_its_landmarks() {
    let text = std::str::from_utf8(SOURCE).unwrap();
    assert!(!text.contains('\r'), "development map must stay LF only");
    assert!(!text.contains("paver"));
    assert!(!text.contains("jetpack"));
    assert!(!text.contains("\"mission\""));
    assert!(!text.contains("\"m13\""));
    let value = document();
    assert_eq!(value["version"], 1);
    assert_eq!(value["map_id"], 1019);
    assert_eq!(value["name"], "Planned Works (development)");
    assert_eq!(value["equipment"], "discovery");
    for key in [
        "mission", "m02", "m03", "m04", "m05", "m06", "m07", "m08", "m09", "m10", "m11", "m12",
        "m13",
    ] {
        assert!(value.get(key).is_none(), "{key} would make this a mission");
    }
    let map = AuthoredMap::read(SOURCE).expect("planned works development source");
    let world = RuntimeMap::Authored(map.clone());
    assert_eq!(world.id(), 1019);
    assert_eq!(world.name(), "Planned Works (development)");
    assert_eq!(world.equipment_policy(), EquipmentPolicy::Discovery);
    let state = GameState::with_authored_map(map.clone());
    assert!(state.mission_state().is_none());
    let entry = point(&value["spawns"][0]["feet"]);
    for id in LANDMARKS {
        let place = map.landmark(id).unwrap_or_else(|| panic!("missing {id}"));
        assert_eq!(place[1], 0.0, "{id} is not on the ground route");
        for (from, to) in [(entry, place), (place, entry)] {
            assert_eq!(
                world.navigation().route(from, to, SEARCH_LIMIT).status,
                RouteStatus::Complete,
                "unreachable {from:?} to {to:?} for {id}"
            );
        }
    }
    let mut bare = value;
    bare["encounters"] = serde_json::json!([]);
    let mut state = GameState::with_authored_map(
        AuthoredMap::read(serde_json::to_vec(&bare).unwrap().as_slice()).unwrap(),
    );
    let id = Uuid::from_u128(1019);
    state.add_player(id, "Planned Works ground route".into(), Role::Human);
    state.start_round();
    let mut navigator = Navigator::default();
    for name in LANDMARKS {
        let destination = map.landmark(name).unwrap();
        let mut arrived = false;
        for _ in 0..1800 {
            let from = feet(&state, id);
            if (from[0] - destination[0]).hypot(from[2] - destination[2]) <= 0.3
                && (from[1] - destination[1]).abs() <= 0.04
            {
                arrived = true;
                break;
            }
            let action = navigator.steer(
                state.map.navigation(),
                from,
                NavigationGoal {
                    feet: destination,
                    combat: false,
                },
                Action::default(),
                state.tick,
                true,
            );
            assert!(!action.jump, "ground route requires a jump at {from:?}");
            state.set_action(id, action);
            state.tick(0.05);
            state.take_events();
            let from = feet(&state, id);
            assert!(
                !state.current_arena().solids.iter().any(|solid| {
                    solid.covers(from[0], from[2])
                        && solid.top > from[1] + CONTACT_EPSILON
                        && solid.bottom < from[1] + BODY_HEIGHT - CONTACT_EPSILON
                }),
                "ordinary walking entered a solid at {from:?}"
            );
        }
        assert!(
            arrived,
            "route stalled at {:?} before {destination:?}",
            feet(&state, id)
        );
    }
    assert_eq!(
        state
            .players
            .iter()
            .find(|player| player.id == id)
            .unwrap()
            .hp,
        100
    );
}
