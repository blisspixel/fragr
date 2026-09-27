use super::*;
use crate::navigation::RouteStatus;
use serde_json::{json, Value};

fn fixture() -> Value {
    json!({
        "version":1,"map_id":1002,"name":"M02 objective fixture","half_extent":8,
        "ground":"concrete","equipment":"discovery",
        "solids":[
            {"id":"ceiling","min":[-8,3,-8],"max":[8,4,8],"surface":"enamel"},
            {"id":"divider_west","min":[-8,0,-0.5],"max":[-1.5,3,0.5],"surface":"enamel"},
            {"id":"ward_gate","min":[-1.5,0,-0.5],"max":[1.5,3,0.5],"surface":"lift_panel"},
            {"id":"divider_east","min":[1.5,0,-0.5],"max":[8,3,0.5],"surface":"enamel"}
        ],
        "spawns":[{"id":"entry","feet":[0,0,-4],"yaw":0}],
        "landmarks":[{"id":"gallery","feet":[0,0,-3]}],
        "m02":{
            "objectives":[
                {"id":"ward_reached","action":{"kind":"arrival","region":{"min":[-1,0,-5],"max":[1,1,-3]},"feet":[0,0,-4]}},
                {"id":"correction_stopped","after":"ward_reached","action":{"kind":"use",
                 "panel":{"solid":"ceiling","face":"down","center":[0,-3],"size":[0.5,0.5],"kind":"terminal"},
                 "approach":[0,0,-3]}},
                {"id":"party_departed","after":"correction_stopped","action":{"kind":"arrival",
                 "region":{"min":[-1,0,3],"max":[1,1,5]},"feet":[0,0,4]}}
            ],
            "gates":[{"id":"ward_release","solid":"ward_gate","lift":4,"after":"correction_stopped","signals":[
                {"solid":"ward_gate","face":"north","center":[0,0.8],"size":[0.5,0.5],"kind":"gate_locked"},
                {"solid":"divider_west","face":"north","center":[-2.75,0.8],"size":[0.5,0.5],"kind":"gate_locked"}]}]
        }
    })
}

fn read(doc: &Value) -> io::Result<Arc<AuthoredMap>> {
    AuthoredMap::read(serde_json::to_vec(doc).unwrap().as_slice())
}

#[test]
fn bundled_guard_shells_require_a_step_off_every_gallery_spawn() {
    let map = AuthoredMap::read(include_str!("../../../maps/m02-persons-unknown.json").as_bytes())
        .unwrap();
    let shells = map
        .supplies
        .iter()
        .find(|supply| supply.id == "guard_room_shells")
        .unwrap();
    assert_eq!(shells.floor, 3.0);
    for spawn in &map.spawns {
        assert!(
            (spawn.feet[0] - shells.x).hypot(spawn.feet[2] - shells.z)
                > crate::sim::PICKUP_CLAIM_RADIUS + crate::movement::RADIUS,
            "{} starts inside the optional shell pickup reach",
            spawn.id
        );
    }
    assert_eq!(
        map.navigation
            .route(
                map.spawns[0].feet,
                [shells.x, shells.floor, shells.z],
                crate::navigation::SEARCH_LIMIT
            )
            .status,
        RouteStatus::Complete
    );
    // The shells stay on the open gallery path just north of the first guard trigger.
    assert!(shells.x > -3.0 && shells.z > -30.6 && shells.z < -26.0);
}

#[test]
fn floor_officer_uses_the_reachable_upper_mezzanine() {
    let map = AuthoredMap::read(include_str!("../../../maps/m02-persons-unknown.json").as_bytes())
        .unwrap();
    let officer = map
        .encounters
        .iter()
        .find(|encounter| encounter.id == "floor_crew")
        .unwrap()
        .enemies
        .iter()
        .find(|enemy| enemy.id == "floor_officer")
        .unwrap();
    assert_eq!(officer.kind, crate::protocol::EnemyKind::Clerk);
    assert!(
        officer.feet[1] >= 2.5,
        "officer must own the upper sightline"
    );
    assert!((-14.0..=-6.0).contains(&officer.feet[0]));
    assert!((1.0..=14.0).contains(&officer.feet[2]));
    assert_eq!(
        map.arena
            .support_height(officer.feet[0], officer.feet[2], officer.feet[1] + 0.01),
        officer.feet[1]
    );
    assert_eq!(
        map.navigation
            .route(
                [-4.0, 0.0, -5.0],
                officer.feet,
                crate::navigation::SEARCH_LIMIT
            )
            .status,
        RouteStatus::Complete
    );
    assert!(map.navigation.line_of_sight(
        [-4.0, crate::movement::EYE_HEIGHT, -5.0],
        [officer.feet[0], officer.feet[1] + 0.9, officer.feet[2]]
    ));
}

#[test]
fn side_ward_is_reachable_but_the_dock_route_stays_on_the_floor() {
    let map = AuthoredMap::read(include_str!("../../../maps/m02-persons-unknown.json").as_bytes())
        .unwrap();
    let opened = map.m02.as_ref().unwrap().world(1).unwrap().1;
    let entry = [0.0, 3.0, -31.0];
    assert_eq!(
        map.navigation
            .route(
                [-16.7, 0.0, -21.9],
                [7.0, 0.0, -11.0],
                crate::navigation::SEARCH_LIMIT
            )
            .status,
        RouteStatus::Complete
    );
    let branch = map
        .landmarks
        .iter()
        .find(|place| place.id == "side_ward")
        .unwrap()
        .feet;
    assert_eq!(
        map.navigation
            .route(entry, branch, crate::navigation::SEARCH_LIMIT)
            .status,
        RouteStatus::Unreachable,
        "the side ward must wait for Latch's release"
    );
    assert_eq!(
        opened
            .route(entry, branch, crate::navigation::SEARCH_LIMIT)
            .status,
        RouteStatus::Complete
    );
    assert_eq!(
        opened
            .route(
                [7.0, 0.0, -11.0],
                [5.0, 0.0, -5.5],
                crate::navigation::SEARCH_LIMIT
            )
            .status,
        RouteStatus::Complete,
        "the floor-entry recovery is reachable after release"
    );
    assert_eq!(
        map.navigation
            .route([-4.0, 0.0, -5.0], branch, crate::navigation::SEARCH_LIMIT)
            .status,
        RouteStatus::Complete
    );
    let dock = map.navigation.route(
        [-4.0, 0.0, -5.0],
        [0.0, 0.0, 21.0],
        crate::navigation::SEARCH_LIMIT,
    );
    assert_eq!(dock.status, RouteStatus::Complete);
    assert!(dock.points.iter().all(|point| point[0] < 15.0));
    assert!(map
        .navigation
        .line_of_sight([18.5, crate::movement::EYE_HEIGHT, 4.0], [23.4, 1.45, 8.8]));
    let side = map
        .encounters
        .iter()
        .find(|encounter| encounter.id == "side_ward_guards")
        .unwrap();
    assert_eq!(side.after.as_deref(), Some("ward_guards"));
    assert_eq!(side.enemies.len(), 2);
    assert!(map
        .encounters
        .iter()
        .filter(|encounter| matches!(encounter.id.as_str(), "floor_crew" | "dock_watch"))
        .all(|encounter| encounter.after.as_deref() != Some("side_ward_guards")));
}

#[test]
fn m02_worlds_are_prepared_and_the_closed_gate_blocks_departure() {
    let map = read(&fixture()).unwrap();
    let closed = crate::maps::RuntimeMap::Authored(map.clone());
    let wire = crate::sim::GameState::with_authored_map(map).map_info();
    assert!(matches!(
        wire,
        crate::protocol::ServerMessage::MapInfo {
            m02_objectives: Some(3),
            ..
        }
    ));
    let initial_hash = closed.content_sha256();
    let opened = closed.prepared_gate_world(1).unwrap();
    assert_eq!(initial_hash, opened.content_sha256());
    assert_eq!(closed.arena().solids[2].bottom, 0.0);
    assert_eq!(opened.arena().solids[2].bottom, 4.0);
    assert_eq!(
        closed
            .navigation()
            .route(
                [0.0, 0.0, -4.0],
                [0.0, 0.0, 4.0],
                crate::navigation::SEARCH_LIMIT
            )
            .status,
        RouteStatus::Unreachable
    );
    assert_eq!(
        opened
            .navigation()
            .route(
                [0.0, 0.0, -4.0],
                [0.0, 0.0, 4.0],
                crate::navigation::SEARCH_LIMIT
            )
            .status,
        RouteStatus::Complete
    );
    assert!(closed.prepared_gate_world(2).is_none());
    assert!(closed.opened_route().is_none());
    assert!(closed.mission().is_none());
    assert!(closed.is_campaign());
}

#[test]
fn m02_rejects_bad_prerequisites_gate_triggers_and_budget() {
    let mut bad = fixture();
    bad["m02"]["objectives"][1]["after"] = json!("missing");
    assert!(read(&bad).unwrap_err().to_string().contains("linear"));
    let mut bad = fixture();
    bad["m02"]["objectives"][1]["after"] = json!("party_departed");
    assert!(read(&bad).is_err());
    let mut bad = fixture();
    bad["m02"]["objectives"][2]["id"] = json!("ward_reached");
    assert!(read(&bad).is_err());
    let mut bad = fixture();
    bad["m02"]["objectives"][2]["action"] = bad["m02"]["objectives"][1]["action"].clone();
    assert!(read(&bad)
        .unwrap_err()
        .to_string()
        .contains("party_departed arrival"));
    let mut bad = fixture();
    bad["m02"]["gates"][0]["after"] = json!("unknown");
    assert!(read(&bad).unwrap_err().to_string().contains("trigger"));
    let mut bad = fixture();
    bad["m02"]["gates"][0]["after"] = json!("ward_reached");
    assert!(read(&bad)
        .unwrap_err()
        .to_string()
        .contains("next required"));
    let mut bad = fixture();
    bad["m02"]["objectives"] = json!(vec![bad["m02"]["objectives"][0].clone(); 9]);
    assert!(read(&bad).unwrap_err().to_string().contains("budget"));
    let mut bad = fixture();
    bad["map_id"] = json!(1001);
    assert!(read(&bad).is_err());
}

#[test]
fn m02_rejects_an_unknown_encounter_requirement_before_readiness() {
    let mut bad = fixture();
    bad["m02"]["objectives"][1]["requires_encounter"] = json!("ward_guards");
    assert!(read(&bad)
        .unwrap_err()
        .to_string()
        .contains("unknown encounter"));
}

#[test]
fn m02_rejects_unusable_controls_and_routes() {
    let mut bad = fixture();
    bad["m02"]["objectives"][1]["action"]["panel"]["solid"] = json!("ward_gate");
    assert!(read(&bad).unwrap_err().to_string().contains("static host"));
    let mut bad = fixture();
    bad["m02"]["objectives"][1]["action"]["approach"] = json!([0, 0, 1]);
    assert!(read(&bad).is_err());
    let mut bad = fixture();
    bad["m02"]["objectives"][2]["action"]["feet"] = json!([0, 0, 6]);
    assert!(read(&bad).is_err());
    let mut bad = fixture();
    bad["m02"]["gates"][0]["lift"] = json!(1);
    assert!(read(&bad).unwrap_err().to_string().contains("unreachable"));
    let mut bad = fixture();
    bad["m02"]["gates"].as_array_mut().unwrap().clear();
    assert!(read(&bad).unwrap_err().to_string().contains("unreachable"));
    let mut bad = fixture();
    bad["solids"][2]["min"][1] = json!(3);
    bad["solids"][2]["max"][1] = json!(6);
    assert!(read(&bad)
        .unwrap_err()
        .to_string()
        .contains("next required"));
    let mut bad = fixture();
    bad["m02"]["objectives"][2]["action"]["region"]["min"][2] = json!(-4);
    assert!(read(&bad)
        .unwrap_err()
        .to_string()
        .contains("arrival region spans"));
}

#[test]
fn m02_gate_signals_flip_with_their_prepared_world() {
    use crate::protocol::MapDecorationKind;
    let map = read(&fixture()).unwrap();
    let closed = crate::maps::RuntimeMap::Authored(map);
    let kinds = |map: &crate::maps::RuntimeMap| -> Vec<MapDecorationKind> {
        map.presentation_ref()
            .unwrap()
            .decorations
            .iter()
            .map(|detail| detail.kind)
            .collect()
    };
    assert_eq!(
        kinds(&closed),
        [
            MapDecorationKind::GateLocked,
            MapDecorationKind::GateLocked,
            MapDecorationKind::Terminal
        ]
    );
    let opened = closed.prepared_gate_world(1).unwrap();
    assert_eq!(
        kinds(&opened),
        [
            MapDecorationKind::GateOpen,
            MapDecorationKind::GateOpen,
            MapDecorationKind::Terminal
        ]
    );
    // The lamp on the gate rides up with it and stays on its face.
    let lamp = &opened.presentation_ref().unwrap().decorations[0];
    assert_eq!(lamp.solid, 2);
    assert!(lamp.point(&opened.arena().solids[2])[1] > 4.0);
    assert!(crate::protocol::validate_map_presentation(
        opened.presentation_ref(),
        &opened.arena().solids
    )
    .is_ok());
}

#[test]
fn m02_rejects_unlinked_or_distant_openers_and_loose_signals() {
    let mut bad = fixture();
    bad["m02"]["gates"][0]["signals"]
        .as_array_mut()
        .unwrap()
        .truncate(1);
    assert!(read(&bad)
        .unwrap_err()
        .to_string()
        .contains("matching signals"));
    let mut bad = fixture();
    bad["m02"]["gates"][0]["signals"][1]["kind"] = json!("gate_open");
    assert!(read(&bad)
        .unwrap_err()
        .to_string()
        .contains("authored locked"));
    let mut bad = fixture();
    bad["m02"]["gates"][0]["signals"][1]["solid"] = json!("missing");
    assert!(read(&bad).is_err());
    let mut bad = fixture();
    bad["m02"]["gates"][0]
        .as_object_mut()
        .unwrap()
        .remove("signals");
    assert!(read(&bad).is_err());
    let mut bad = fixture();
    bad["decorations"] = json!([
        {"solid":"divider_east","face":"north","center":[0,0],"size":[0.5,0.5],"kind":"gate_open"}
    ]);
    assert!(read(&bad)
        .unwrap_err()
        .to_string()
        .contains("belong to an M02 gate"));
    // A switch across the room from its door is a hunt, not a Doom switch.
    let mut far = fixture();
    far["half_extent"] = json!(20);
    far["solids"][0]["min"] = json!([-20, 3, -20]);
    far["solids"][0]["max"] = json!([20, 4, 20]);
    far["solids"][1]["min"][0] = json!(-20);
    far["solids"][3]["max"][0] = json!(20);
    far["m02"]["objectives"][1]["action"]["panel"]["center"] = json!([0, -14]);
    far["m02"]["objectives"][1]["action"]["approach"] = json!([0, 0, -14.5]);
    assert!(read(&far)
        .unwrap_err()
        .to_string()
        .contains("beside the control"));
    far["m02"]["objectives"][1]["action"]["panel"]["center"] = json!([0, -5]);
    far["m02"]["objectives"][1]["action"]["approach"] = json!([0, 0, -5.5]);
    assert!(read(&far).is_ok());
}

#[test]
fn m02_allows_one_required_switch_at_most() {
    let mut doc = fixture();
    let second = json!({"id":"second_switch","after":"correction_stopped","action":{"kind":"use",
        "panel":{"solid":"ceiling","face":"down","center":[1,-3],"size":[0.5,0.5],"kind":"terminal"},
        "approach":[1,0,-3]}});
    let objectives = doc["m02"]["objectives"].as_array_mut().unwrap();
    objectives.insert(2, second);
    objectives[3]["after"] = json!("second_switch");
    assert!(read(&doc)
        .unwrap_err()
        .to_string()
        .contains("at most one required use switch"));
}
