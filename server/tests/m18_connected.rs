//! All Systems Normal: connected Episode V Recovery Square integration tests.
use fragr_server::maps::{AuthoredSource, RuntimeMap};
use fragr_server::protocol::{
    EquipmentPolicy, MissionId, MissionPhase, MissionReady, Role, ServerMessage,
};
use fragr_server::session::GameSession;
use uuid::Uuid;

#[test]
fn all_systems_normal_canonical_source_and_connected_loop() {
    let map = AuthoredSource::Mission(MissionId::AllSystemsNormal)
        .load()
        .expect("canonical m18 map");
    let world = RuntimeMap::Authored(map.clone());
    assert_eq!(world.id(), 1018);
    assert_eq!(world.name(), "All Systems Normal");
    assert_eq!(world.equipment_policy(), EquipmentPolicy::Discovery);

    let g = world.m18_geometry().expect("m18 geometry in canonical map");
    assert_eq!(g.objectives.len(), 6);
    assert!(!g.roadblock_active);
    assert!(!g.concourse_evac_completed);

    let ruptured = world
        .prepared_m18_world(1)
        .expect("prepared ruptured world");
    let ruptured_g = ruptured.m18_geometry().expect("ruptured geometry");
    assert!(ruptured_g.roadblock_active);

    let concluded = world
        .prepared_m18_world(2)
        .expect("prepared concluded world");
    let concluded_g = concluded.m18_geometry().expect("concluded geometry");
    assert!(concluded_g.roadblock_active);
    assert!(concluded_g.concourse_evac_completed);

    let mut session = GameSession::with_authored_map(map);
    session.state.seed(1018);
    let player_id = Uuid::from_u128(1018);
    session
        .state
        .add_player(player_id, "Recovery Operative".into(), Role::Human);
    session.state.arm_joined_magazines(player_id);

    assert!(session.state.acknowledge_mission(
        player_id,
        MissionReady {
            id: MissionId::AllSystemsNormal,
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
    assert_eq!(state.id, MissionId::AllSystemsNormal);

    let m18 = state.m18.expect("m18 progress");
    assert_eq!(m18.completed.len(), 0);
    assert_eq!(m18.current.as_ref().unwrap().id, "aid_checkin");
    assert!(!m18.challenges.aid_delivered);
    assert!(!m18.challenges.square_defended);
    assert!(!m18.challenges.collector_neutralized);
    assert!(!m18.challenges.overlook_witnessed);
    assert!(!m18.challenges.concourse_secured);
    assert!(!m18.roadblock_active);
    assert!(!m18.aid_delivered);
    assert!(!m18.overlook_witnessed);
    assert!(!m18.concourse_secured);

    // Verify map info broadcast carries M18 geometry
    let map_info = session.state.map_info();
    assert!(matches!(map_info, ServerMessage::MapInfo { .. }));

    // Mission ID protocol conversions
    assert_eq!(
        serde_json::from_str::<MissionId>("\"all_systems_normal\"").unwrap(),
        MissionId::AllSystemsNormal
    );
    assert_eq!(MissionId::ALL.len(), 18);
    assert!(MissionId::ALL.contains(&MissionId::AllSystemsNormal));
}
