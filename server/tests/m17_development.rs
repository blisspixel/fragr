use fragr_server::maps::{AuthoredMap, RuntimeMap};
use fragr_server::movement::{BODY_HEIGHT, CONTACT_EPSILON};
use fragr_server::navigation::{NavigationGoal, Navigator, RouteStatus, SEARCH_LIMIT};
use fragr_server::protocol::{Action, EquipmentPolicy, Role};
use fragr_server::sim::{GameState, PLAYER_FLOOR_Y};
use serde_json::{json, Value};
use std::sync::Arc;
use uuid::Uuid;

const SOURCE: &[u8] = include_bytes!("../maps/test/m17_forever_office_development.json");

const ROUTE: [&str; 8] = [
    "civic_approach",
    "occupied_public_hall",
    "administration_ring",
    "command_galleries",
    "assembly_chamber",
    "frontal_kill_lane",
    "flank_bypass",
    "later_exit",
];

fn document() -> Value {
    serde_json::from_slice(SOURCE).unwrap()
}

fn feet(value: &Value) -> [f32; 3] {
    std::array::from_fn(|index| value[index].as_f64().unwrap() as f32)
}

fn point(map: &AuthoredMap, id: &str) -> [f32; 3] {
    map.landmark(id)
        .unwrap_or_else(|| panic!("missing route landmark {id}"))
}

fn assert_complete(world: &RuntimeMap, from: [f32; 3], to: [f32; 3], label: &str) {
    let forward = world.navigation().route(from, to, SEARCH_LIMIT);
    let back = world.navigation().route(to, from, SEARCH_LIMIT);
    assert_eq!(
        forward.status,
        RouteStatus::Complete,
        "{label} forward {from:?} -> {to:?}"
    );
    assert_eq!(
        back.status,
        RouteStatus::Complete,
        "{label} return {to:?} -> {from:?}"
    );
}

#[test]
fn forever_office_development_is_not_a_mission() {
    assert!(
        !SOURCE.contains(&b'\r'),
        "development map must use LF line endings"
    );
    let text = std::str::from_utf8(SOURCE).unwrap().to_ascii_lowercase();
    assert!(!text.contains("denial"));
    assert!(!text.contains("voss"));
    let map = AuthoredMap::read(SOURCE).expect("forever office development");
    let world = RuntimeMap::Authored(map.clone());
    assert_eq!(world.id(), 1017);
    assert_eq!(world.name(), "Peace Without Interruption (development)");
    assert!(GameState::with_authored_map(map.clone())
        .mission_state()
        .is_none());
    assert!(world.mission().is_none());
    assert_eq!(world.equipment_policy(), EquipmentPolicy::Discovery);
    let value = document();
    assert_eq!(value["version"], 1);
    assert_eq!(value["map_id"], 1017);
    assert_eq!(value["equipment"], "discovery");
    for key in [
        "mission", "m02", "m03", "m04", "m05", "m06", "m07", "m08", "m09", "m10", "m11", "m12",
        "m13",
    ] {
        assert!(value.get(key).is_none(), "{key} is a mission key");
    }
    let allowed = [
        "clerk",
        "sweeper",
        "heavy_sweeper",
        "notary",
        "turret",
        "auditor",
        "enforcer",
        "assessor",
    ];
    for enemy in value["encounters"]
        .as_array()
        .unwrap()
        .iter()
        .flat_map(|group| group["enemies"].as_array().unwrap())
    {
        let kind = enemy["kind"].as_str().unwrap();
        assert!(allowed.contains(&kind), "unsupported enemy kind {kind}");
    }
    for id in ROUTE {
        assert!(map.landmark(id).is_some(), "missing route landmark {id}");
    }
}

#[test]
fn forever_office_route_landmarks_stay_reachable() {
    let map = AuthoredMap::read(SOURCE).expect("forever office development");
    let world = RuntimeMap::Authored(map.clone());
    let value = document();
    let entry = feet(&value["spawns"][0]["feet"]);
    let civic = point(&map, "civic_approach");
    let hall = point(&map, "occupied_public_hall");
    let ring = point(&map, "administration_ring");
    let galleries = point(&map, "command_galleries");
    let lane = point(&map, "frontal_kill_lane");
    let flank = point(&map, "flank_bypass");
    let wrap = point(&map, "north_wrap");
    let chamber = point(&map, "assembly_chamber");
    let exit = point(&map, "later_exit");
    for (label, from, to) in [
        ("entry", entry, civic),
        ("approach", civic, hall),
        ("flank ring", hall, ring),
        ("flank galleries", ring, galleries),
        ("flank passage", galleries, flank),
        ("flank wrap", flank, wrap),
        ("flank exit", wrap, exit),
        ("flank chamber", flank, chamber),
        ("kill lane", hall, lane),
        ("lane chamber", lane, chamber),
        ("chamber exit", chamber, exit),
    ] {
        assert_complete(&world, from, to, label);
    }
    let west = world.navigation().route(galleries, flank, SEARCH_LIMIT);
    assert!(
        west.points
            .iter()
            .all(|step| step[0] < -6.0 && step[2] > 2.0),
        "gallery flank left the west wing: {:?}",
        west.points
    );
    let around = world.navigation().route(flank, wrap, SEARCH_LIMIT);
    assert!(
        around
            .points
            .iter()
            .all(|step| step[0] < -10.0 && step[2] > 18.0),
        "north wrap detoured out of the flank: {:?}",
        around.points
    );
    let frontal = world.navigation().route(lane, chamber, SEARCH_LIMIT);
    assert!(
        frontal
            .points
            .iter()
            .all(|step| step[0].abs() < 5.0 && step[2] > 4.0),
        "frontal lane detoured through the flank: {:?}",
        frontal.points
    );
    let mut cleared = value;
    cleared["encounters"] = json!([]);
    let empty = AuthoredMap::read(serde_json::to_vec(&cleared).unwrap().as_slice()).unwrap();
    walk(
        empty,
        &[
            civic, hall, ring, galleries, flank, wrap, exit, chamber, lane, hall, civic,
        ],
    );
}

fn walk(map: Arc<AuthoredMap>, destinations: &[[f32; 3]]) {
    let mut state = GameState::with_authored_map(map);
    let id = Uuid::from_u128(1017);
    state.add_player(id, "Forever Office route".into(), Role::Human);
    state.start_round();
    let mut navigator = Navigator::default();
    for destination in destinations {
        let mut arrived = false;
        for _ in 0..2400 {
            let player = state.players.iter().find(|player| player.id == id).unwrap();
            let feet = [player.x, player.y - PLAYER_FLOOR_Y, player.z];
            if (feet[0] - destination[0]).hypot(feet[2] - destination[2]) <= 0.35
                && (feet[1] - destination[1]).abs() <= 0.04
            {
                arrived = true;
                break;
            }
            let action = navigator.steer(
                state.map.navigation(),
                feet,
                NavigationGoal {
                    feet: *destination,
                    combat: false,
                },
                Action::default(),
                state.tick,
                true,
            );
            assert!(!action.jump, "office route required a jump at {feet:?}");
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
                "body entered an office solid"
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
