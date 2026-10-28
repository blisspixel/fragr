use super::*;
use crate::session::GameSession;
use crate::sim::MapKind;
use serde_json::json;

fn object(value: Value) -> Object {
    match value {
        Value::Object(object) => object,
        other => panic!("not an object: {other}"),
    }
}

fn world(tick: u64, players: Value, extra: Value) -> Object {
    let mut world = object(json!({"type": "snapshot", "tick": tick, "players": players}));
    world.extend(object(extra));
    world
}

/// A seeded match: every tick's world, encoded as the tick encodes it.
fn match_worlds(map: MapKind, bots: usize, ticks: u64) -> Vec<(ServerMessage, String)> {
    let mut session = GameSession::with_map(map, false);
    session.state.seed(42);
    session.state.use_replay_ids();
    session.state.config = crate::bench::fixture_config();
    session.spawn_bots(bots);
    let mut worlds = Vec::new();
    for _ in 0..ticks {
        for message in session.tick_messages(crate::run::TICK.as_secs_f32()) {
            if matches!(message, ServerMessage::Snapshot(_)) {
                let text = serde_json::to_string(&message).unwrap();
                worlds.push((message, text));
            }
        }
    }
    worlds
}

#[test]
fn every_delta_of_a_fought_match_rebuilds_the_full_world_exactly() {
    let worlds = match_worlds(MapKind::ArenaDuel, 12, 400);
    assert!(worlds.len() > 300);
    let mut encoder = WorldEncoder::default();
    let mut reader = WorldReader::new();
    let (mut deltas, mut delta_bytes, mut full_bytes) = (0, 0, 0);
    for (index, (message, text)) in worlds.iter().enumerate() {
        let encoded = encoder
            .observe(message, text)
            .expect("a snapshot is a world");
        let ServerMessage::Snapshot(snapshot) = message else {
            unreachable!()
        };
        assert_eq!(encoded.tick, snapshot.tick);
        full_bytes += text.len();
        let frame = match (&encoded.delta, index) {
            (None, 0) => text.as_str(),
            (Some(delta), _) => {
                assert_eq!(Some(delta.base), reader.tick());
                deltas += 1;
                delta_bytes += delta.text.len();
                delta.text.as_str()
            }
            (None, _) => text.as_str(),
        };
        let read = reader.read(frame).unwrap();
        // The rebuilt world is the full world: it encodes to the same text.
        assert_eq!(
            serde_json::to_string(&read).unwrap(),
            *text,
            "tick {}",
            snapshot.tick
        );
    }
    assert_eq!(
        deltas,
        worlds.len() - 1,
        "every world after the first has a delta"
    );
    // The measured point of the change: a fought world costs well under half.
    assert!(
        delta_bytes * 2 < full_bytes,
        "{delta_bytes} delta bytes against {full_bytes} full"
    );
}

#[test]
fn joins_leaves_and_dropped_fields_round_trip() {
    let base = world(
        7,
        json!([
            {"id": "a", "name": "Ash", "x": 1.0, "ping": 30, "team": "red"},
            {"id": "b", "name": "Bo", "x": 2.0}
        ]),
        json!({"pickups": [1, 2], "host_line": "Hello", "mvp": null}),
    );
    let next = world(
        8,
        json!([
            {"id": "c", "name": "Cy", "x": 9.0},
            {"id": "a", "name": "Ash", "x": 1.5, "team": "red", "golden": true}
        ]),
        json!({"pickups": [1, 2], "mvp": "Ash", "sudden_death": true}),
    );
    let delta = encode(&base, &next).unwrap();
    assert_eq!(
        Value::Object(delta.clone()),
        json!({
            "type": "snapshot_delta",
            "base": 7,
            "tick": 8,
            "set": {"mvp": "Ash", "sudden_death": true},
            "unset": ["host_line"],
            "players": [
                {"id": "c", "name": "Cy", "x": 9.0},
                {"id": "a", "x": 1.5, "golden": true, "unset": ["ping"]}
            ]
        })
    );
    assert_eq!(apply(&base, &delta).unwrap(), next);
}

#[test]
fn worlds_without_a_sound_delta_get_none() {
    let base = world(3, json!([{"id": "a"}]), json!({}));
    // Time must advance.
    assert!(encode(&base, &world(3, json!([]), json!({}))).is_none());
    assert!(encode(&base, &world(2, json!([]), json!({}))).is_none());
    // Every roster entry needs one unique string id.
    assert!(encode(
        &base,
        &world(4, json!([{"id": "a"}, {"id": "a"}]), json!({}))
    )
    .is_none());
    assert!(encode(&base, &world(4, json!([{"id": 5}]), json!({}))).is_none());
    assert!(encode(&base, &world(4, json!([{"name": "x"}]), json!({}))).is_none());
    assert!(encode(&base, &world(4, json!({}), json!({}))).is_none());
    // Only worlds.
    let mut other = world(4, json!([]), json!({}));
    other.insert("type".into(), "map_info".into());
    assert!(encode(&base, &other).is_none());
    assert!(encode(&other, &base).is_none());
}

#[test]
fn a_delta_for_another_base_or_with_a_bad_shape_is_refused() {
    let base = world(10, json!([{"id": "a", "x": 1.0}]), json!({"mvp": null}));
    let good = object(json!({"type": "snapshot_delta", "base": 10, "tick": 11, "players": []}));
    assert!(apply(&base, &good).is_ok());
    let refused = |delta: Value| apply(&base, &object(delta)).unwrap_err();
    assert_eq!(
        refused(json!({"type": "snapshot_delta", "base": 9, "tick": 11, "players": []})),
        DeltaError::WrongBase { held: 10, named: 9 }
    );
    for (delta, why) in [
        (
            json!({"type": "snapshot", "base": 10, "tick": 11, "players": []}),
            "not a snapshot delta",
        ),
        (
            json!({"type": "snapshot_delta", "tick": 11, "players": []}),
            "base is not a tick",
        ),
        (
            json!({"type": "snapshot_delta", "base": 10, "players": []}),
            "tick is not a tick",
        ),
        (
            json!({"type": "snapshot_delta", "base": 10, "tick": 10, "players": []}),
            "tick does not advance",
        ),
        (
            json!({"type": "snapshot_delta", "base": 10, "tick": 11, "players": [], "x": 1}),
            "unknown delta field",
        ),
        (
            json!({"type": "snapshot_delta", "base": 10, "tick": 11, "set": [], "players": []}),
            "set is not an object",
        ),
        (
            json!({"type": "snapshot_delta", "base": 10, "tick": 11, "set": {"tick": 99}, "players": []}),
            "set names a framed field",
        ),
        (
            json!({"type": "snapshot_delta", "base": 10, "tick": 11, "unset": ["players"], "players": []}),
            "unset names a framed field",
        ),
        (
            json!({"type": "snapshot_delta", "base": 10, "tick": 11, "unset": "mvp", "players": []}),
            "unset is not a list",
        ),
        (
            json!({"type": "snapshot_delta", "base": 10, "tick": 11, "unset": [1], "players": []}),
            "unset names a non-string",
        ),
        (
            json!({"type": "snapshot_delta", "base": 10, "tick": 11}),
            "players is not a list",
        ),
        (
            json!({"type": "snapshot_delta", "base": 10, "tick": 11, "players": [3]}),
            "a roster entry is not an object",
        ),
        (
            json!({"type": "snapshot_delta", "base": 10, "tick": 11, "players": [{"x": 1}]}),
            "a roster entry has no id",
        ),
        (
            json!({"type": "snapshot_delta", "base": 10, "tick": 11, "players": [{"id": "z"}, {"id": "z"}]}),
            "a roster id repeats",
        ),
        (
            json!({"type": "snapshot_delta", "base": 10, "tick": 11, "players": [{"id": "a", "unset": ["id"]}]}),
            "unset names the id",
        ),
    ] {
        assert_eq!(refused(delta), DeltaError::Malformed(why));
    }
    let no_tick = object(json!({"type": "snapshot", "players": []}));
    assert_eq!(apply(&no_tick, &good).unwrap_err(), DeltaError::NoBase);
    for error in [
        DeltaError::NoBase,
        DeltaError::WrongBase { held: 1, named: 2 },
        DeltaError::Malformed("x"),
    ] {
        assert!(!error.to_string().is_empty());
    }
}

#[test]
fn the_reader_needs_a_base_and_forgets_it_at_a_new_map() {
    let worlds = match_worlds(MapKind::ArenaDuel, 2, 3);
    let mut encoder = WorldEncoder::default();
    let first = &worlds[0];
    encoder.observe(&first.0, &first.1);
    let second = &worlds[1];
    let delta = encoder
        .observe(&second.0, &second.1)
        .unwrap()
        .delta
        .unwrap();
    // No world yet: a delta is refused, and the reader stays empty.
    let mut reader = WorldReader::new();
    assert!(matches!(
        reader.read(&delta.text),
        Err(ReadError::Delta(DeltaError::NoBase))
    ));
    assert_eq!(reader.tick(), None);
    reader.read(&first.1).unwrap();
    assert!(matches!(
        reader.read(&delta.text).unwrap(),
        ServerMessage::Snapshot(_)
    ));
    // A map boundary forgets the world on both sides.
    let map = crate::sim::GameState::with_map(MapKind::ArenaDuel, false).map_info();
    let map_text = serde_json::to_string(&map).unwrap();
    assert!(encoder.observe(&map, &map_text).is_none());
    assert!(matches!(
        reader.read(&map_text).unwrap(),
        ServerMessage::MapInfo { .. }
    ));
    assert_eq!(reader.tick(), None);
    let third = encoder.observe(&worlds[2].0, &worlds[2].1).unwrap();
    assert!(third.delta.is_none(), "no delta reaches across a map");
    // Other messages pass through untouched; junk is an error, not a panic.
    let event = ServerMessage::Event(crate::protocol::GameEvent::Respawn {
        player: "Ash".into(),
    });
    assert!(encoder
        .observe(&event, &serde_json::to_string(&event).unwrap())
        .is_none());
    assert!(matches!(
        reader
            .read(&serde_json::to_string(&event).unwrap())
            .unwrap(),
        ServerMessage::Event(_)
    ));
    assert!(matches!(reader.read("{"), Err(ReadError::Json(_))));
    assert!(matches!(reader.read("[]"), Err(ReadError::Json(_))));
    assert!(!ReadError::Delta(DeltaError::NoBase).to_string().is_empty());
}

#[test]
fn a_bad_rebuilt_world_does_not_replace_the_held_one() {
    let worlds = match_worlds(MapKind::ArenaDuel, 2, 2);
    let mut reader = WorldReader::new();
    reader.read(&worlds[0].1).unwrap();
    let held = reader.tick();
    // A delta that applies but leaves no valid snapshot behind.
    let bad = json!({
        "type": "snapshot_delta",
        "base": held,
        "tick": held.unwrap() + 1,
        "set": {"round_state": 7},
        "players": []
    });
    assert!(matches!(
        reader.read(&bad.to_string()),
        Err(ReadError::Json(_))
    ));
    assert_eq!(reader.tick(), held);
}

#[test]
fn neither_frame_names_collide_with_a_world_field() {
    // `unset` and the framed keys must never be real field names.
    let worlds = match_worlds(MapKind::ArenaDuel, 4, 2);
    let world: Value = serde_json::from_str(&worlds[1].1).unwrap();
    let world = world.as_object().unwrap();
    for name in ["unset", "set", "base"] {
        assert!(!world.contains_key(name));
    }
    for entry in world["players"].as_array().unwrap() {
        assert!(!entry.as_object().unwrap().contains_key("unset"));
    }
}

/// The cases `client/scripts/test_snapshot_delta.gd` applies: the hand-made
/// roster case above and consecutive worlds of a seeded fight, each as base,
/// delta and the world it must rebuild.
fn client_cases() -> Value {
    let base = world(
        7,
        json!([
            {"id": "a", "name": "Ash", "x": 1.0, "ping": 30, "team": "red"},
            {"id": "b", "name": "Bo", "x": 2.0}
        ]),
        json!({"pickups": [1, 2], "host_line": "Hello", "mvp": null}),
    );
    let next = world(
        8,
        json!([
            {"id": "c", "name": "Cy", "x": 9.0},
            {"id": "a", "name": "Ash", "x": 1.5, "team": "red", "golden": true}
        ]),
        json!({"pickups": [1, 2], "mvp": "Ash", "sudden_death": true}),
    );
    let mut cases = vec![json!({
        "base": base,
        "delta": encode(&base, &next).unwrap(),
        "world": next,
    })];
    let worlds = match_worlds(MapKind::ArenaDuel, 4, 203);
    for pair in worlds[200..].windows(2) {
        let base = object(serde_json::from_str(&pair[0].1).unwrap());
        let next = object(serde_json::from_str(&pair[1].1).unwrap());
        cases.push(json!({
            "base": base,
            "delta": encode(&base, &next).unwrap(),
            "world": next,
        }));
    }
    json!({ "cases": cases })
}

/// Regenerate with `FRAGR_DELTA_GOLDEN=$PWD/client/golden/snapshot_delta_vectors.json
/// cargo test -p fragr-server --lib write_snapshot_delta_golden -- --ignored`.
#[test]
fn the_client_golden_is_the_server_delta() {
    let golden: Value = serde_json::from_str(include_str!(
        "../../../../client/golden/snapshot_delta_vectors.json"
    ))
    .expect("parse the client golden");
    assert_eq!(
        client_cases(),
        golden,
        "client/golden/snapshot_delta_vectors.json is stale; regenerate it with write_snapshot_delta_golden"
    );
}

#[test]
#[ignore = "writes the delta vectors the client harness applies"]
fn write_snapshot_delta_golden() {
    let Ok(path) = std::env::var("FRAGR_DELTA_GOLDEN") else {
        return;
    };
    let text = serde_json::to_string_pretty(&client_cases()).expect("serialize vectors");
    std::fs::write(path, text + "\n").expect("write vectors");
}

#[test]
fn a_value_reader_rebuilds_the_same_world_as_a_typed_one() {
    let worlds = match_worlds(MapKind::ArenaDuel, 4, 3);
    let mut encoder = WorldEncoder::default();
    encoder.observe(&worlds[0].0, &worlds[0].1);
    let delta = encoder
        .observe(&worlds[1].0, &worlds[1].1)
        .unwrap()
        .delta
        .unwrap();
    let mut values = WorldReader::new();
    assert!(matches!(
        values.read_value(&delta.text),
        Err(ReadError::Delta(DeltaError::NoBase))
    ));
    values.read_value(&worlds[0].1).unwrap();
    let rebuilt = values.read_value(&delta.text).unwrap();
    assert_eq!(
        rebuilt,
        serde_json::from_str::<Value>(&worlds[1].1).unwrap()
    );
    assert_eq!(values.tick(), rebuilt["tick"].as_u64());
}
