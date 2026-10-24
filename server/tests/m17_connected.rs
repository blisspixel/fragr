//! Peace Without Interruption: connected Forever Office integration tests.
use fragr_server::maps::{AuthoredSource, RuntimeMap};
use fragr_server::protocol::{
    EquipmentPolicy, MissionId, MissionPhase, MissionReady, Role, ServerMessage,
};
use fragr_server::session::GameSession;
use uuid::Uuid;

#[test]
fn peace_without_interruption_canonical_source_and_connected_loop() {
    let map = AuthoredSource::Mission(MissionId::PeaceWithoutInterruption)
        .load()
        .expect("canonical m17 map");
    let world = RuntimeMap::Authored(map.clone());
    assert_eq!(world.id(), 1017);
    assert_eq!(world.name(), "Peace Without Interruption");
    assert_eq!(world.equipment_policy(), EquipmentPolicy::Discovery);

    let g = world.m17_geometry().expect("m17 geometry in canonical map");
    assert_eq!(g.objectives.len(), 6);
    assert!(!g.core_unsealed);
    assert!(!g.voss_captured);

    let unsealed = world
        .prepared_m17_world(1)
        .expect("prepared unsealed world");
    let unsealed_g = unsealed.m17_geometry().expect("unsealed geometry");
    assert!(unsealed_g.core_unsealed);

    let concluded = world
        .prepared_m17_world(2)
        .expect("prepared concluded world");
    let concluded_g = concluded.m17_geometry().expect("concluded geometry");
    assert!(concluded_g.core_unsealed);

    let mut session = GameSession::with_authored_map(map);
    session.state.seed(1017);
    let player_id = Uuid::from_u128(1017);
    session
        .state
        .add_player(player_id, "Office Operative".into(), Role::Human);
    session.state.arm_joined_magazines(player_id);

    assert!(session.state.acknowledge_mission(
        player_id,
        MissionReady {
            id: MissionId::PeaceWithoutInterruption,
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
    assert_eq!(state.id, MissionId::PeaceWithoutInterruption);

    let m17 = state.m17.expect("m17 progress");
    assert_eq!(m17.completed.len(), 0);
    assert_eq!(m17.current.as_ref().unwrap().id, "approach_breached");
    assert!(!m17.challenges.approach_breached);
    assert!(!m17.challenges.kessel_secured);
    assert!(!m17.challenges.core_defeated);
    assert!(!m17.challenges.voss_captured);
    assert!(!m17.core_unsealed);
    assert!(!m17.voss_captured);
    assert!(!m17.kessel_secured);

    // Verify map info broadcast carries M17 geometry
    let map_info = session.state.map_info();
    assert!(matches!(map_info, ServerMessage::MapInfo { .. }));

    // Mission ID protocol conversions
    assert_eq!(
        serde_json::from_str::<MissionId>("\"peace_without_interruption\"").unwrap(),
        MissionId::PeaceWithoutInterruption
    );
    assert_eq!(MissionId::ALL.len(), 19);
    assert!(MissionId::ALL.contains(&MissionId::PeaceWithoutInterruption));
}
