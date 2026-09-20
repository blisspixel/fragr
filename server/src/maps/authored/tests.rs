use super::*;
use crate::navigation::{NavigationGoal, Navigator};
use crate::protocol::{Action, Role, ServerMessage};
use crate::session::GameSession;
use crate::sim::PLAYER_FLOOR_Y;
use serde_json::{json, Value};
use uuid::Uuid;

const M01: &str = include_str!("../../../maps/m01-recall-notice.json");

pub(super) fn small() -> Value {
    json!({
        "version":1,"map_id":1000,"name":"Authored fixture","half_extent":8,"ground":"concrete",
        "solids":[{"id":"ceiling","min":[-8,3,-8],"max":[8,4,8],"surface":"enamel"}],
        "spawns":[{"id":"entry","feet":[0,0,-4],"yaw":0}],
        "landmarks":[{"id":"destination","feet":[0,0,4]}]
    })
}

pub(super) fn decode(value: &Value) -> io::Result<Arc<AuthoredMap>> {
    AuthoredMap::read(serde_json::to_vec(value).unwrap().as_slice())
}

#[test]
fn decorations_resolve_solid_ids_and_reach_the_wire() {
    let mut doc = small();
    let detail = json!({"solid":"ceiling", "face":"down", "center":[0,0],
        "size":[4,0.25], "kind":"strip_light"});
    doc["decorations"] = json!([detail]);
    let map = decode(&doc).unwrap();
    assert_eq!(map.presentation.decorations[0].solid, 0);
    let session = GameSession::with_authored_map(map);
    let wire = serde_json::to_value(session.state.map_info()).unwrap();
    assert_eq!(wire["geometry_version"], 2);
    assert_eq!(wire["presentation"]["decorations"][0]["solid"], 0);
    assert_eq!(
        wire["presentation"]["decorations"][0]["kind"],
        "strip_light"
    );
    for (field, bad) in [
        ("solid", json!("missing")),
        ("size", json!([17, 1])),
        ("center", json!([20, 0])),
        ("kind", json!("unknown")),
        ("extra", json!(true)),
    ] {
        let mut malformed = doc.clone();
        malformed["decorations"][0][field] = bad;
        assert!(decode(&malformed).is_err());
    }
    doc["decorations"] = json!(vec![detail.clone(); crate::protocol::MAX_MAP_LIGHTS + 1]);
    assert!(decode(&doc).is_err());
    doc["decorations"] = json!(vec![detail; crate::protocol::MAX_MAP_DECORATIONS + 1]);
    assert!(decode(&doc).is_err());
}

#[test]
fn supplies_validate_grants_claims_clearance_and_reachability() {
    let mut doc = small();
    doc["equipment"] = json!("discovery");
    let supply = json!({"id":"supply","feet":[0,0,1],"claim":"contested",
        "grant":{"kind":"ammo","pool":"darts","amount":30}});
    doc["supplies"] = json!([supply]);
    assert!(decode(&doc).is_ok());
    for grant in [
        json!({"kind":"weapon","weapon":"tack"}),
        json!({"kind":"health","amount":25}),
        json!({"kind":"armor","amount":50}),
    ] {
        let mut valid = doc.clone();
        valid["supplies"][0]["grant"] = grant;
        assert!(decode(&valid).is_ok());
    }
    let mut invalids = Vec::new();
    for grant in [
        json!({"kind":"weapon","weapon":"fists"}),
        json!({"kind":"weapon","weapon":"unknown"}),
        json!({"kind":"ammo","pool":"darts","amount":0}),
        json!({"kind":"ammo","pool":"darts","amount":121}),
        json!({"kind":"ammo","pool":"tacks","amount":-1}),
        json!({"kind":"ammo","pool":"cores","amount":1.5}),
        json!({"kind":"health","amount":101}),
        json!({"kind":"armor","amount":0}),
        json!({"kind":"weapon","weapon":"tack","amount":1}),
    ] {
        let mut bad = doc.clone();
        bad["supplies"][0]["grant"] = grant;
        invalids.push(bad);
    }
    for (key, value) in [
        ("id", json!("ceiling")),
        ("feet", json!([0, 1, 0])),
        ("claim", json!("personal")),
        ("unexpected", json!(true)),
    ] {
        let mut bad = doc.clone();
        bad["supplies"][0][key] = value;
        invalids.push(bad);
    }
    let mut bad = doc.clone();
    bad["equipment"] = json!("full_arsenal");
    invalids.push(bad);
    let mut bad = doc.clone();
    bad["supplies"] = json!(vec![doc["supplies"][0].clone(); 129]);
    invalids.push(bad);
    let mut blocked = doc.clone();
    blocked["landmarks"][0]["feet"] = json!([0, 0, -3]);
    blocked["solids"].as_array_mut().unwrap().push(json!({
        "id":"divider","min":[-8,0,-1],"max":[8,3,0],"surface":"enamel"
    }));
    assert!(decode(&blocked)
        .unwrap_err()
        .to_string()
        .contains("unreachable"));
    for bad in invalids {
        assert!(decode(&bad).is_err(), "accepted {bad}");
    }
}

#[test]
fn authoring_rejects_unknown_fields_and_invalid_placements() {
    let mut cases = Vec::new();
    for (field, value) in [
        ("version", json!(2)),
        ("map_id", json!(1)),
        ("name", json!("\nprivate")),
        ("ground", json!("arbitrary_asset_path")),
        ("half_extent", json!(513)),
        ("spawns", json!([])),
        ("landmarks", json!([])),
        ("unexpected", json!(true)),
    ] {
        let mut doc = small();
        doc[field] = value;
        cases.push(doc);
    }
    for (field, value) in [
        ("feet", json!([0, 3, 0])),
        ("feet", json!([0, 1, 0])),
        ("feet", json!([8, 0, 0])),
        ("yaw", json!(-1)),
        ("id", json!("ceiling")),
        ("id", json!("InvalidName")),
        ("unrecognized", json!(0)),
    ] {
        let mut doc = small();
        doc["spawns"][0][field] = value;
        cases.push(doc);
    }
    for (field, value) in [
        ("max", json!([-8, 4, 8])),
        ("min", json!([-8, -1, -8])),
        ("unknown", json!(0)),
    ] {
        let mut doc = small();
        doc["solids"][0][field] = value;
        cases.push(doc);
    }
    let mut doc = small();
    doc["landmarks"][0]["feet"] = json!([0, 1, 0]);
    cases.push(doc);
    for doc in cases {
        assert!(decode(&doc).is_err(), "accepted {doc}");
    }
    assert!(decode(&small()).is_ok());
    assert!(crate::protocol::validate_map_presentation(
        Some(&crate::protocol::MapPresentation {
            ground: crate::protocol::MapSurface::Concrete,
            solids: Vec::new(),
            decorations: Vec::new(),
        }),
        &[crate::movement::Solid::from_center(0.0, 0.0, 1.0, 1.0)]
    )
    .is_err());
}

#[test]
fn authoring_bounds_streams_and_requires_reachable_landmarks() {
    let oversized = io::repeat(b' ');
    assert!(AuthoredMap::read(oversized)
        .unwrap_err()
        .to_string()
        .contains("1 MiB"));
    let private = b"{\"secret_not_for_logs\":true}";
    let error = AuthoredMap::read(private.as_slice())
        .unwrap_err()
        .to_string();
    assert!(!error.contains("secret_not_for_logs"));
    let mut doc = small();
    doc["solids"].as_array_mut().unwrap().push(json!({
        "id":"divider","min":[-8,0,-1],"max":[8,3,1],"surface":"enamel"
    }));
    assert!(decode(&doc)
        .unwrap_err()
        .to_string()
        .contains("unreachable"));
    doc = small();
    doc["spawns"] = json!(vec![doc["spawns"][0].clone(); MAX_PLACEMENTS + 1]);
    assert!(decode(&doc).is_err());
}

#[test]
fn indoor_spawn_and_replaced_identity_use_one_runtime_world() {
    let map = decode(&small()).unwrap();
    let mut session = GameSession::with_authored_map(map.clone());
    let id = Uuid::nil();
    session.state.add_player(id, "Walker".into(), Role::Human);
    let player = &session.state.players[0];
    assert_eq!(
        [player.x, player.y - PLAYER_FLOOR_Y, player.z],
        [0.0, 0.0, -4.0]
    );
    assert!(session.state.pickups.is_empty());
    let first = session.tick_messages(0.05);
    assert!(first.iter().any(|m| matches!(
        m,
        ServerMessage::MapInfo {
            geometry_version: 2,
            ..
        }
    )));
    assert!(!session
        .tick_messages(0.05)
        .iter()
        .any(|m| matches!(m, ServerMessage::MapInfo { .. })));
    let mut changed = small();
    changed["solids"][0]["min"][1] = json!(4);
    changed["solids"][0]["max"][1] = json!(5);
    let replacement = decode(&changed).unwrap();
    session.state.map = crate::maps::RuntimeMap::Authored(replacement);
    assert!(session
        .tick_messages(0.05)
        .iter()
        .any(|m| matches!(m, ServerMessage::MapInfo { solids,.. } if solids[0].bottom == 4.0)));
    for _ in 0..4000 {
        session.tick_messages(0.05);
    }
    assert_eq!(session.state.round_number, 1);
    assert!(session.state.boss_id.is_none());
    let snapshot = session.state.snapshot();
    assert_eq!(snapshot.map_id, map.id);
    assert_eq!(snapshot.mode_name, "Campaign development");
    assert!(snapshot.frag_limit.is_none());
}

#[test]
fn m01_routes_use_ordinary_actions_through_the_live_session() {
    let map = AuthoredMap::read(M01.as_bytes()).unwrap();
    for role in [Role::Human, Role::Agent] {
        let mut session = GameSession::with_authored_map(map.clone());
        let id = Uuid::nil();
        session.state.add_player(id, "Walker".into(), role);
        let mut navigator = Navigator::default();
        for name in [
            "confiscation_bay",
            "intake_hall",
            "under_records",
            "public_stair_entry",
            "records_balcony",
            "transfer_control",
            "transfer_record",
            "prisoner_lift",
            "transfer_control",
            "maintenance_landing",
            "maintenance_stair_entry",
            "maintenance_entry",
            "confiscation_bay",
            "maintenance_entry",
            "maintenance_stair_entry",
            "maintenance_landing",
            "records_balcony",
        ] {
            let destination = map.landmark(name).unwrap();
            let mut arrived = false;
            for _ in 0..1200 {
                let player = &session.state.players[0];
                let feet = [player.x, player.y - PLAYER_FLOOR_Y, player.z];
                let tolerance = if name == "transfer_record" { 0.4 } else { 0.75 };
                if (feet[0] - destination[0]).hypot(feet[2] - destination[2]) < tolerance
                    && (feet[1] - destination[1]).abs() < 0.1
                {
                    arrived = true;
                    break;
                }
                let action = navigator.steer(
                    session.state.map.navigation(),
                    feet,
                    NavigationGoal {
                        feet: destination,
                        combat: false,
                    },
                    Action::default(),
                    session.state.tick,
                    true,
                );
                session.state.set_action(id, action);
                session.tick_messages(0.05);
                let player = &session.state.players[0];
                let feet = player.y - PLAYER_FLOOR_Y;
                // Automatic stepping permits radius overlap with a riser's lip
                // before the feet centre reaches its tread. The body axis must
                // never cross a filled volume, including an overhead slab.
                assert!(
                    !session.state.map.arena().solids.iter().any(|solid| {
                        solid.covers(player.x, player.z)
                            && solid.top > feet + CONTACT_EPSILON
                            && solid.bottom < feet + BODY_HEIGHT - CONTACT_EPSILON
                    }),
                    "body entered a volume on route to {name} at {:?}",
                    [player.x, feet, player.z]
                );
            }
            assert!(arrived, "{role:?} could not reach {name}");
            if name == "transfer_record" {
                let geometry = session.state.map.mission().unwrap();
                let point = geometry
                    .record
                    .point(
                        session.state.map.presentation_ref().unwrap(),
                        &session.state.map.arena().solids,
                    )
                    .unwrap();
                session.state.set_action(
                    id,
                    Action {
                        interact: true,
                        look_at: Some(crate::protocol::LookAt {
                            x: Some(point[0]),
                            y: Some(point[1]),
                            z: Some(point[2]),
                            player_id: None,
                        }),
                        ..Action::default()
                    },
                );
                session.tick_messages(0.05);
                assert_eq!(
                    session.state.mission_state().unwrap().phase,
                    crate::protocol::MissionPhase::ReachLift
                );
                navigator.clear();
            }
        }
    }
}
