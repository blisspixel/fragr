//! Freedom of Movement: connected ceremonial avenue integration tests.
use fragr_server::maps::{AuthoredSource, RuntimeMap};
use fragr_server::protocol::{
    EquipmentPolicy, MissionId, MissionPhase, MissionReady, Role, ServerMessage,
};
use fragr_server::session::GameSession;
use uuid::Uuid;

#[test]
fn freedom_of_movement_canonical_source_and_connected_loop() {
    let map = AuthoredSource::Mission(MissionId::FreedomOfMovement)
        .load()
        .expect("canonical m16 map");
    let world = RuntimeMap::Authored(map.clone());
    assert_eq!(world.id(), 1016);
    assert_eq!(world.name(), "Freedom of Movement");
    assert_eq!(world.equipment_policy(), EquipmentPolicy::Discovery);

    let g = world.m16_geometry().expect("m16 geometry in canonical map");
    assert_eq!(g.objectives.len(), 6);
    assert_eq!(g.motorcycle.feet, [-38.0, 0.0, 3.2]);
    assert!(!g.checkpoint_lifted);
    assert!(!g.doors_open);

    let lifted = world
        .prepared_m16_world(1)
        .expect("prepared lifted checkpoint world");
    let lifted_g = lifted.m16_geometry().expect("lifted geometry");
    assert!(lifted_g.checkpoint_lifted);
    assert!(!lifted_g.doors_open);

    let open = world
        .prepared_m16_world(2)
        .expect("prepared open chamber doors world");
    let open_g = open.m16_geometry().expect("open doors geometry");
    assert!(open_g.checkpoint_lifted);
    assert!(open_g.doors_open);

    let mut session = GameSession::with_authored_map(map);
    session.state.seed(1016);
    let player_id = Uuid::from_u128(1016);
    session
        .state
        .add_player(player_id, "Avenue Rider".into(), Role::Human);
    session.state.arm_joined_magazines(player_id);

    assert!(session.state.acknowledge_mission(
        player_id,
        MissionReady {
            id: MissionId::FreedomOfMovement,
            attempt: 1,
        }
    ));

    session.tick_messages(0.05);
    let state = session
        .state
        .mission_state()
        .expect("in-progress mission state");
    state
        .validate(session.state.tick)
        .expect("valid mission state");
    assert_eq!(state.phase, MissionPhase::InProgress);
    assert_eq!(state.id, MissionId::FreedomOfMovement);

    let m16 = state.m16.expect("m16 progress");
    assert_eq!(m16.completed.len(), 0);
    assert_eq!(m16.current.as_ref().unwrap().id, "ride_started");
    assert!(!m16.challenges.ride_started);
    assert!(!m16.checkpoint_lifted);
    assert!(!m16.doors_open);

    // Verify map info broadcast carries M16 geometry
    let map_info = session.state.map_info();
    assert!(matches!(map_info, ServerMessage::MapInfo { .. }));

    // Mission ID protocol conversions
    assert_eq!(
        serde_json::from_str::<MissionId>("\"freedom_of_movement\"").unwrap(),
        MissionId::FreedomOfMovement
    );
    assert_eq!(MissionId::ALL.len(), 20);
    assert!(MissionId::ALL.contains(&MissionId::FreedomOfMovement));
}
