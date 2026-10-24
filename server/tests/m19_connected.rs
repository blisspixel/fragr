//! Planned Works: connected Episode V concourse, Low Water and trench.
use fragr_server::maps::{AuthoredSource, RuntimeMap};
use fragr_server::protocol::{
    EquipmentPolicy, MissionId, MissionPhase, MissionReady, Role, ServerMessage,
    M19_GAMEPLAY_VERSION, M19_OBJECTIVE_IDS,
};
use fragr_server::session::GameSession;
use uuid::Uuid;

#[test]
fn planned_works_canonical_source_and_connected_loop() {
    let map = AuthoredSource::Mission(MissionId::PlannedWorks)
        .load()
        .expect("canonical m19 map");
    let world = RuntimeMap::Authored(map.clone());
    assert_eq!(world.id(), 1019);
    assert_eq!(world.name(), "Planned Works");
    assert_eq!(world.equipment_policy(), EquipmentPolicy::Discovery);
    assert_eq!(
        MissionId::PlannedWorks.gameplay_version(),
        M19_GAMEPLAY_VERSION
    );

    let g = world.m19_geometry().expect("m19 geometry in canonical map");
    assert_eq!(g.objectives.len(), M19_OBJECTIVE_IDS.len());
    assert!(!g.gate_open);
    assert!(!g.jet_hops.is_empty());
    assert!(g.jetpack_ceiling > 6.0);
    let open = world.prepared_m19_world(1).expect("prepared open world");
    assert!(open.m19_geometry().unwrap().gate_open);

    let mut session = GameSession::with_authored_map(map);
    session.state.seed(1019);
    let player = Uuid::from_u128(1019);
    session
        .state
        .add_player(player, "Works Operative".into(), Role::Human);
    session.state.arm_joined_magazines(player);
    assert!(session.state.acknowledge_mission(
        player,
        MissionReady {
            id: MissionId::PlannedWorks,
            attempt: 1,
        }
    ));
    session.tick_messages(0.05);
    let state = session.state.mission_state().expect("mission state");
    state
        .validate(session.state.tick)
        .expect("valid mission state");
    assert_eq!(state.phase, MissionPhase::InProgress);
    assert_eq!(state.id, MissionId::PlannedWorks);
    let m19 = state.m19.expect("m19 progress");
    assert!(m19.completed.is_empty());
    assert_eq!(m19.current.as_ref().unwrap().id, "concourse_stores");
    assert!(!m19.jetpack_taken && !m19.latch_departed && !m19.gate_open);

    let ServerMessage::MapInfo { m19, .. } = session.state.map_info() else {
        panic!("map info");
    };
    assert_eq!(m19.as_ref(), Some(&g));
    assert_eq!(
        serde_json::from_str::<MissionId>("\"planned_works\"").unwrap(),
        MissionId::PlannedWorks
    );
    assert!(serde_json::from_str::<MissionId>("\"local_exception\"").is_err());
    assert_eq!(MissionId::ALL.len(), 19);
    assert_eq!(MissionId::ALL.last(), Some(&MissionId::PlannedWorks));
}
