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
            "gates":[{"id":"ward_release","solid":"ward_gate","lift":4,"after":"correction_stopped"}]
        }
    })
}

fn read(doc: &Value) -> io::Result<Arc<AuthoredMap>> {
    AuthoredMap::read(serde_json::to_vec(doc).unwrap().as_slice())
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
