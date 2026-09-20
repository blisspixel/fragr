use super::*;
use crate::navigation::{NavigationGoal, Navigator};
use crate::protocol::{Action, Role, ServerMessage};
use crate::session::GameSession;
use crate::sim::PLAYER_FLOOR_Y;
use serde_json::{json, Value};
use uuid::Uuid;

const M01: &str = include_str!("../../../maps/m01-recall-notice.json");

fn small() -> Value {
    json!({
        "version":1,"map_id":1000,"name":"Authored fixture","half_extent":8,"ground":"concrete",
        "solids":[{"id":"ceiling","min":[-8,3,-8],"max":[8,4,8],"surface":"enamel"}],
        "spawns":[{"id":"entry","feet":[0,0,-4],"yaw":0}],
        "landmarks":[{"id":"destination","feet":[0,0,4]}]
    })
}

fn decode(value: &Value) -> io::Result<Arc<AuthoredMap>> {
    AuthoredMap::read(serde_json::to_vec(value).unwrap().as_slice())
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
        }),
        1
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
    assert_eq!(snapshot.mode_name, "Traversal blockout");
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
                if (feet[0] - destination[0]).hypot(feet[2] - destination[2]) < 0.75
                    && (feet[1] - destination[1]).abs() < 0.1
                {
                    arrived = true;
                    break;
                }
                let action = navigator.steer(
                    &map.navigation,
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
                    !map.arena.solids.iter().any(|solid| {
                        solid.covers(player.x, player.z)
                            && solid.top > feet + CONTACT_EPSILON
                            && solid.bottom < feet + BODY_HEIGHT - CONTACT_EPSILON
                    }),
                    "body entered a volume on route to {name} at {:?}",
                    [player.x, feet, player.z]
                );
            }
            assert!(arrived, "{role:?} could not reach {name}");
        }
    }
}
