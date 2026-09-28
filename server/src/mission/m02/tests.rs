use super::*;
use crate::maps::AuthoredMap;
use crate::protocol::Role;

fn state() -> GameState {
    GameState::with_authored_map(
        AuthoredMap::read(include_bytes!("../../../maps/test/m02-wire-fixture.json").as_slice())
            .unwrap(),
    )
}

fn progress(state: &GameState) -> (usize, u8, MissionPhase, u32) {
    let run = state.mission.as_ref().unwrap();
    let m02 = run.m02.as_ref().unwrap();
    (m02.index, m02.gate_mask, run.phase, run.attempt)
}

#[test]
fn small_m02_fixture_omits_bundled_side_ward_evacuation() {
    let state = state();
    let mission = state.mission_state().unwrap();
    assert!(mission.m02.as_ref().unwrap().evacuation.is_none());
    let json = serde_json::to_value(&mission).unwrap();
    assert!(json["m02"].get("evacuation").is_none());
    mission.validate(state.tick).unwrap();
    assert!(!state.map.has_m02_side_ward());
    let map = serde_json::to_value(state.map_info()).unwrap();
    assert!(map.get("m02_side_ward").is_none());
}

fn read_m02_map(
    reader: &mut MissionClient,
    map: crate::protocol::ServerMessage,
) -> Result<(), &'static str> {
    let crate::protocol::ServerMessage::MapInfo {
        map_id,
        m02_objectives,
        m02_side_ward,
        mission,
        half_extent,
        solids,
        presentation,
        ..
    } = map
    else {
        panic!("expected authored MapInfo");
    };
    reader.replace_map_with_id(
        map_id,
        m02_objectives,
        m02_side_ward,
        mission.as_ref(),
        half_extent,
        &solids,
        presentation.as_ref(),
    )
}

#[test]
fn rust_mission_reader_requires_evacuation_exactly_when_map_authors_side_ward() {
    let mut small = MissionClient::default();
    let state = state();
    let map = state.map_info();
    let mut bad_map = map.clone();
    if let crate::protocol::ServerMessage::MapInfo {
        m02_objectives,
        m02_side_ward,
        ..
    } = &mut bad_map
    {
        *m02_objectives = None;
        *m02_side_ward = true;
    }
    assert!(read_m02_map(&mut small, bad_map).is_err());
    assert!(small.state.is_none());
    read_m02_map(&mut small, map).unwrap();
    let mission = state.mission_state().unwrap();
    small.observe(state.tick, mission.clone()).unwrap();
    let mut unexpected = mission;
    unexpected.m02.as_mut().unwrap().evacuation = Some(crate::protocol::M02EvacuationState::held());
    assert!(small.observe(state.tick, unexpected).is_err());

    let map = crate::maps::AuthoredSource::Mission(MissionId::PersonsUnknown)
        .load()
        .unwrap();
    let bundled = GameState::with_authored_map(map);
    let mut reader = MissionClient::default();
    read_m02_map(&mut reader, bundled.map_info()).unwrap();
    let mission = bundled.mission_state().unwrap();
    let mut missing = mission.clone();
    missing.m02.as_mut().unwrap().evacuation = None;
    assert!(reader.observe(bundled.tick, missing).is_err());
    reader.observe(bundled.tick, mission).unwrap();
    let previous = reader.state.clone();
    let mut opened = GameState::with_authored_map(match &bundled.map {
        crate::maps::RuntimeMap::Authored(map) => map.clone(),
        _ => unreachable!(),
    });
    opened.map = opened.map.prepared_gate_world(1).unwrap();
    read_m02_map(&mut reader, opened.map_info()).unwrap();
    assert_eq!(
        reader.state, previous,
        "gate map update retains the side-ward contract"
    );
    let mut marker_flip = opened.map_info();
    if let crate::protocol::ServerMessage::MapInfo { m02_side_ward, .. } = &mut marker_flip {
        *m02_side_ward = false;
    }
    assert!(read_m02_map(&mut reader, marker_flip).is_err());
    assert_eq!(
        reader.state, previous,
        "invalid marker flip leaves reader state intact"
    );
}

#[test]
fn arrival_and_use_advance_once_per_tick_and_select_the_prepared_world() {
    let mut state = state();
    let id = Uuid::new_v4();
    state.add_player(id, "Walker".into(), Role::Human);
    assert_eq!(state.mission_state().unwrap().id, MissionId::PersonsUnknown);
    state.players[0].interaction_requested = true;
    state.tick(0.05);
    assert_eq!(progress(&state), (0, 0, MissionPhase::Briefing, 1));
    assert!(state.acknowledge_mission(
        id,
        MissionReady {
            id: MissionId::PersonsUnknown,
            attempt: 1,
        }
    ));
    assert!(!state.acknowledge_mission(
        id,
        MissionReady {
            id: MissionId::PersonsUnknown,
            attempt: 1,
        }
    ));
    state.tick(0.05);
    assert_eq!(progress(&state), (1, 0, MissionPhase::InProgress, 1));
    let step = state.map.m02_objectives().unwrap().objective(1).unwrap();
    let point = step
        .control
        .as_ref()
        .unwrap()
        .point(
            state.map.presentation_ref().unwrap(),
            &state.map.arena().solids,
        )
        .unwrap();
    let player = &mut state.players[0];
    [player.x, player.y, player.z] = [0.0, PLAYER_FLOOR_Y, -3.0];
    (player.yaw, player.pitch) =
        crate::combat::aim_at([player.x, crate::movement::EYE_HEIGHT, player.z], point).unwrap();
    player.interaction_requested = true;
    state.tick(0.05);
    assert_eq!(progress(&state), (2, 1, MissionPhase::InProgress, 1));
    assert_eq!(state.map.arena().solids[2].bottom, 4.0);
    state.players[0].interaction_requested = true;
    state.tick(0.05);
    assert_eq!(progress(&state), (2, 1, MissionPhase::InProgress, 1));
    [state.players[0].x, state.players[0].y, state.players[0].z] = [0.0, PLAYER_FLOOR_Y, 4.0];
    state.tick(0.05);
    assert_eq!(progress(&state), (3, 1, MissionPhase::Departed, 1));
    state.tick(0.05);
    assert_eq!(progress(&state), (3, 1, MissionPhase::Departed, 1));
}

#[test]
fn durable_solo_m02_departure_saves_m03_pending_and_survives_owner_drop() {
    let mut state = state();
    state.enable_campaign_run().unwrap();
    let id = Uuid::new_v4();
    state.add_player(id, "Runner".into(), Role::Agent);
    assert!(state.acknowledge_m02(id, 1));
    state.tick(0.05);
    assert_eq!(progress(&state).0, 1);
    let target = state
        .map
        .m02_objectives()
        .unwrap()
        .objective(1)
        .unwrap()
        .control
        .as_ref()
        .unwrap()
        .point(
            state.map.presentation_ref().unwrap(),
            &state.map.arena().solids,
        )
        .unwrap();
    let player = &mut state.players[0];
    [player.x, player.y, player.z] = [0.0, PLAYER_FLOOR_Y, -3.0];
    (player.yaw, player.pitch) =
        crate::combat::aim_at([player.x, crate::movement::EYE_HEIGHT, player.z], target).unwrap();
    player.interaction_requested = true;
    state.tick(0.05);
    assert_eq!(progress(&state).0, 2);
    state.players[0].hp = 63;
    state.players[0].armor = 9;
    [state.players[0].x, state.players[0].y, state.players[0].z] = [0.0, PLAYER_FLOOR_Y, 4.0];
    state.tick(0.05);
    assert_eq!(
        state.mission_state().unwrap().run.unwrap().status,
        crate::protocol::CampaignRunStatus::Complete
    );
    let before = state.campaign_run_document().unwrap().unwrap();
    let crate::mission::run_file::SavedStep::AwaitingMission {
        completed_mission,
        next_mission,
        exit,
    } = &before.step
    else {
        panic!("M02 departure must wait for M03");
    };
    assert_eq!(*completed_mission, MissionId::PersonsUnknown);
    assert_eq!(next_mission, "scheduled_service");
    assert_eq!((exit.hp, exit.armor), (63, 9));
    state.remove_player(id);
    assert_eq!(state.campaign_run_document().unwrap(), Some(before));
}

#[test]
fn wire_projection_has_current_objective_and_prompts_for_all_eligible_members() {
    let mut state = state();
    let first = Uuid::from_u128(11);
    let second = Uuid::from_u128(12);
    state.add_player(first, "First".into(), Role::Human);
    state.add_player(second, "Second".into(), Role::Agent);
    let ready = MissionReady {
        id: MissionId::PersonsUnknown,
        attempt: 1,
    };
    assert!(state.acknowledge_mission(first, ready));
    assert_eq!(state.mission_state().unwrap().phase, MissionPhase::Briefing);
    assert!(state.acknowledge_mission(second, ready));
    state.tick(0.05);
    let step = state.map.m02_objectives().unwrap().objective(1).unwrap();
    let point = step
        .control
        .as_ref()
        .unwrap()
        .point(
            state.map.presentation_ref().unwrap(),
            &state.map.arena().solids,
        )
        .unwrap();
    for player in &mut state.players {
        [player.x, player.y, player.z] = [0.0, PLAYER_FLOOR_Y, -3.0];
        (player.yaw, player.pitch) =
            crate::combat::aim_at([0.0, crate::movement::EYE_HEIGHT, -3.0], point).unwrap();
    }
    let wire = state.mission_state().unwrap();
    wire.validate(state.tick).unwrap();
    let m02 = wire.m02.unwrap();
    assert_eq!(m02.completed, ["ward_reached"]);
    assert_eq!(m02.current.unwrap().id, "correction_stopped");
    assert_eq!(wire.prompts.len(), 2);
    assert!(wire
        .prompts
        .iter()
        .all(|prompt| prompt.kind == InteractionKind::ObjectiveUse));
    state.players[1].hp = 0;
    assert_eq!(state.mission_state().unwrap().prompts.len(), 1);
}

#[test]
fn unready_and_dead_participants_cannot_trigger_and_retry_restores_entry() {
    let mut state = state();
    let id = Uuid::new_v4();
    state.add_player(id, "Walker".into(), Role::Human);
    assert!(!state.acknowledge_m02(id, 2));
    assert!(state.acknowledge_m02(id, 1));
    state.players[0].hp = 0;
    state.advance_m02();
    assert_eq!(progress(&state), (0, 0, MissionPhase::InProgress, 1));
    state.players[0].hp = 100;
    state.advance_m02();
    assert_eq!(progress(&state), (1, 0, MissionPhase::InProgress, 1));
    let late = Uuid::new_v4();
    state.add_player(late, "Late agent".into(), Role::Agent);
    let step = state.map.m02_objectives().unwrap().objective(1).unwrap();
    let point = step
        .control
        .as_ref()
        .unwrap()
        .point(
            state.map.presentation_ref().unwrap(),
            &state.map.arena().solids,
        )
        .unwrap();
    let late_player = &mut state.players[1];
    [late_player.x, late_player.y, late_player.z] = [0.0, PLAYER_FLOOR_Y, -3.0];
    (late_player.yaw, late_player.pitch) = crate::combat::aim_at(
        [late_player.x, crate::movement::EYE_HEIGHT, late_player.z],
        point,
    )
    .unwrap();
    late_player.interaction_requested = true;
    state.advance_m02();
    assert_eq!(progress(&state), (1, 0, MissionPhase::InProgress, 1));
    let player = &mut state.players[0];
    [player.x, player.y, player.z] = [0.0, PLAYER_FLOOR_Y, -3.0];
    (player.yaw, player.pitch) =
        crate::combat::aim_at([player.x, crate::movement::EYE_HEIGHT, player.z], point).unwrap();
    player.interaction_requested = true;
    player.hp = 0;
    state.advance_m02();
    assert_eq!(progress(&state), (1, 0, MissionPhase::InProgress, 1));
    state.players[0].hp = 100;
    state.players[0].yaw = 0.0;
    state.players[0].pitch = 0.0;
    state.players[0].interaction_requested = true;
    state.advance_m02();
    assert_eq!(progress(&state), (1, 0, MissionPhase::InProgress, 1));
    (state.players[0].yaw, state.players[0].pitch) =
        crate::combat::aim_at([0.0, crate::movement::EYE_HEIGHT, -3.0], point).unwrap();
    state.players[0].interaction_requested = true;
    state.advance_m02();
    assert_eq!(progress(&state), (2, 1, MissionPhase::InProgress, 1));
    state.reset_mission();
    assert_eq!(progress(&state), (0, 0, MissionPhase::InProgress, 2));
    assert_eq!(state.map.arena().solids[2].bottom, 0.0);
    assert!(!state.acknowledge_m02(id, 1));
}

#[test]
fn departure_waits_for_every_current_participant_to_be_ready_alive_and_aboard() {
    let mut state = state();
    let first = Uuid::new_v4();
    state.add_player(first, "First".into(), Role::Human);
    assert!(state.acknowledge_m02(first, 1));
    state.tick(0.05);
    assert_eq!(progress(&state).0, 1);
    let step = state.map.m02_objectives().unwrap().objective(1).unwrap();
    let point = step
        .control
        .as_ref()
        .unwrap()
        .point(
            state.map.presentation_ref().unwrap(),
            &state.map.arena().solids,
        )
        .unwrap();
    let player = &mut state.players[0];
    [player.x, player.y, player.z] = [0.0, PLAYER_FLOOR_Y, -3.0];
    (player.yaw, player.pitch) =
        crate::combat::aim_at([player.x, crate::movement::EYE_HEIGHT, player.z], point).unwrap();
    player.interaction_requested = true;
    state.tick(0.05);
    assert_eq!(progress(&state).0, 2);
    [state.players[0].x, state.players[0].y, state.players[0].z] = [0.0, PLAYER_FLOOR_Y, 4.0];
    let second = Uuid::new_v4();
    state.add_player(second, "Second".into(), Role::Agent);
    state.tick(0.05);
    assert_eq!(
        progress(&state).0,
        2,
        "a second participant outside blocks departure"
    );
    [state.players[1].x, state.players[1].y, state.players[1].z] = [0.0, PLAYER_FLOOR_Y, 4.0];
    state.tick(0.05);
    assert_eq!(
        progress(&state).0,
        2,
        "an unready participant aboard still blocks"
    );
    assert!(state.acknowledge_m02(second, 1));
    state.players[1].hp = 0;
    state.advance_m02();
    assert_eq!(
        progress(&state).0,
        2,
        "a dead participant aboard still blocks"
    );
    state.players[1].hp = 100;
    state.tick(0.05);
    assert_eq!(progress(&state), (3, 1, MissionPhase::Departed, 1));
}
