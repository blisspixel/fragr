//! Local Exception: the campaign's last level over the public session API.
use fragr_server::maps::{AuthoredSource, RuntimeMap};
use fragr_server::protocol::{
    M20CrewPhase, MissionId, MissionPhase, MissionReady, Role, ServerMessage, M20_GAMEPLAY_VERSION,
    M20_REFUGE_BASE, M20_SIX_MINUTES,
};
use fragr_server::session::GameSession;
use uuid::Uuid;

#[test]
fn local_exception_canonical_source_and_connected_loop() {
    let map = AuthoredSource::Mission(MissionId::LocalException)
        .load()
        .expect("canonical m20 map");
    let world = RuntimeMap::Authored(map.clone());
    assert_eq!(world.id(), 1020);
    assert_eq!(world.name(), "Local Exception");
    assert_eq!(
        MissionId::LocalException.gameplay_version(),
        M20_GAMEPLAY_VERSION
    );
    assert_eq!(M20_GAMEPLAY_VERSION, 56);

    let g = world.m20_geometry().expect("m20 geometry in canonical map");
    assert_eq!(g.objectives.len(), 5);
    assert!(!g.gate_open);
    assert_eq!(g.hold_ticks - g.turn_ticks, M20_SIX_MINUTES);
    let (start, turn, reprieve) = g.clock(1_000);
    assert!(start > 1_000 && start < turn && turn < reprieve);

    // The level's one door: the open world changes only the refuge gate.
    let opened = world.prepared_m20_world(1).expect("prepared open gate");
    assert!(opened.m20_geometry().unwrap().gate_open);
    assert_eq!(opened.arena().solids.len(), world.arena().solids.len());
    let moved = opened
        .arena()
        .solids
        .iter()
        .zip(&world.arena().solids)
        .filter(|(a, b)| a != b)
        .count();
    assert_eq!(moved, 1, "only the gate leaf moves");

    let mut session = GameSession::with_authored_map(map);
    session.state.seed(1020);
    let id = Uuid::from_u128(1020);
    session
        .state
        .add_player(id, "Pier Operative".into(), Role::Human);
    session.state.arm_joined_magazines(id);
    assert!(session.state.acknowledge_mission(
        id,
        MissionReady {
            id: MissionId::LocalException,
            attempt: 1,
        }
    ));
    session.tick_messages(0.05);
    let state = session.state.mission_state().expect("mission state");
    state
        .validate(session.state.tick)
        .expect("valid mission state");
    assert_eq!(state.phase, MissionPhase::InProgress);
    let m20 = state.m20.expect("m20 progress");
    assert_eq!(m20.current.as_ref().unwrap().id, "sluice_crossing");
    assert_eq!(
        m20.refuge.persons, M20_REFUGE_BASE,
        "a development room shows the base refuge"
    );
    assert!(m20.crew.iter().all(|c| c.phase == M20CrewPhase::Working));
    assert!(m20.pier_reached_at.is_none() && !m20.gate_open);

    let ServerMessage::MapInfo { m20: Some(_), .. } = session.state.map_info() else {
        panic!("MapInfo carries the pier geometry");
    };
    let wire = serde_json::to_value(ServerMessage::Snapshot(session.state.snapshot())).unwrap();
    assert!(
        wire.get("surveyor_marks").is_none(),
        "an empty mark list stays off the wire"
    );
    // Agents observing the finale read the Inheritance, never the Union.
    let hostiles: Vec<_> = wire["players"]
        .as_array()
        .unwrap()
        .iter()
        .filter_map(|p| p.get("campaign"))
        .filter(|c| c["side"] != "participant")
        .collect();
    assert!(
        !hostiles.is_empty(),
        "the lesson Surveyor stands on its tower"
    );
    assert!(hostiles.iter().all(|c| c["side"] == "inheritance"));
    assert!(hostiles
        .iter()
        .any(|c| c["kind"] == "surveyor" && c["control"] == "restoration"));
    assert_eq!(
        serde_json::from_str::<MissionId>("\"local_exception\"").unwrap(),
        MissionId::LocalException
    );
    assert_eq!(MissionId::ALL.last(), Some(&MissionId::LocalException));
}
