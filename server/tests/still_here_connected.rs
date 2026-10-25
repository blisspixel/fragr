//! Still Here: the survival-gated epilogue over the public session API.
use fragr_server::maps::{AuthoredSource, RuntimeMap};
use fragr_server::protocol::{
    MissionId, MissionPhase, MissionReady, Role, ServerMessage, STILL_HERE_GAMEPLAY_VERSION,
};
use fragr_server::session::GameSession;
use uuid::Uuid;

#[test]
fn still_here_canonical_source_and_connected_loop() {
    let map = AuthoredSource::Mission(MissionId::StillHere)
        .load()
        .expect("canonical epilogue map");
    let world = RuntimeMap::Authored(map.clone());
    assert_eq!(world.id(), 1021);
    assert_eq!(world.name(), "Still Here");
    assert_eq!(
        MissionId::StillHere.gameplay_version(),
        STILL_HERE_GAMEPLAY_VERSION
    );
    assert_eq!(STILL_HERE_GAMEPLAY_VERSION, 57);
    assert_eq!(
        fragr_server::protocol::GAMEPLAY_VERSION,
        STILL_HERE_GAMEPLAY_VERSION
    );
    // A campaign stage list without the epilogue; every playable mission with it.
    assert!(!MissionId::ALL.contains(&MissionId::StillHere));
    assert_eq!(MissionId::PLAYABLE.last(), Some(&MissionId::StillHere));
    assert_eq!(
        &MissionId::PLAYABLE[..MissionId::ALL.len()],
        &MissionId::ALL
    );
    assert!(!world.has_encounters(), "nothing in the refuge fights");

    let mut session = GameSession::with_authored_map(map);
    session.state.seed(1021);
    let id = Uuid::from_u128(1021);
    session
        .state
        .add_player(id, "Still Here".into(), Role::Human);
    assert!(session.state.acknowledge_mission(
        id,
        MissionReady {
            id: MissionId::StillHere,
            attempt: 1,
        }
    ));
    session.tick_messages(0.05);
    let state = session.state.mission_state().expect("mission state");
    state.validate(session.state.tick).expect("valid epilogue");
    assert_eq!(state.phase, MissionPhase::InProgress);
    assert!(state.run.is_none());
    let facts = state.epilogue.expect("epilogue facts");
    assert_eq!(facts.current.unwrap().id, "stay_with_latch");
    assert_eq!(
        facts.refuge,
        Default::default(),
        "a development room carries no rescues"
    );
    assert!(facts.blocking.iter().any(|p| p.id == "latch"));
    let ServerMessage::MapInfo {
        epilogue: Some(geometry),
        ..
    } = session.state.map_info()
    else {
        panic!("MapInfo carries the refuge geometry");
    };
    assert!(!geometry.later);
    let wire = serde_json::to_value(session.state.map_info()).unwrap();
    assert_eq!(wire["epilogue"]["later"], false);
    assert_eq!(
        serde_json::from_str::<MissionId>("\"still_here\"").unwrap(),
        MissionId::StillHere
    );
}
