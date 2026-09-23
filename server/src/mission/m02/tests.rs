use super::*;
use crate::maps::AuthoredMap;
use crate::protocol::Role;
use serde_json::json;

fn state() -> GameState {
    let document = json!({
        "version":1,"map_id":1002,"name":"M02 transition fixture","half_extent":8,
        "ground":"concrete","equipment":"discovery",
        "solids":[
            {"id":"ceiling","min":[-8,3,-8],"max":[8,4,8],"surface":"enamel"},
            {"id":"divider_west","min":[-8,0,-0.5],"max":[-1.5,3,0.5],"surface":"enamel"},
            {"id":"ward_gate","min":[-1.5,0,-0.5],"max":[1.5,3,0.5],"surface":"lift_panel"},
            {"id":"divider_east","min":[1.5,0,-0.5],"max":[8,3,0.5],"surface":"enamel"}
        ],
        "spawns":[{"id":"entry","feet":[0,0,-4],"yaw":0}],
        "landmarks":[{"id":"gallery","feet":[0,0,-3]}],
        "m02":{
            "objectives":[
                {"id":"ward_reached","action":{"kind":"arrival","region":{"min":[-1,0,-5],"max":[1,1,-3]},"feet":[0,0,-4]}},
                {"id":"correction_stopped","after":"ward_reached","action":{"kind":"use",
                 "panel":{"solid":"ceiling","face":"down","center":[0,-3],"size":[0.5,0.5],"kind":"terminal"},
                 "approach":[0,0,-3]}},
                {"id":"party_departed","after":"correction_stopped","action":{"kind":"arrival",
                 "region":{"min":[-1,0,3],"max":[1,1,5]},"feet":[0,0,4]}}
            ],
            "gates":[{"id":"ward_release","solid":"ward_gate","lift":4,"after":"correction_stopped"}]
        }
    });
    GameState::with_authored_map(
        AuthoredMap::read(serde_json::to_vec(&document).unwrap().as_slice()).unwrap(),
    )
}

fn progress(state: &GameState) -> (usize, u8, MissionPhase, u32) {
    let run = state.mission.as_ref().unwrap();
    let m02 = run.m02.as_ref().unwrap();
    (m02.index, m02.gate_mask, run.phase, run.attempt)
}

#[test]
fn arrival_and_use_advance_once_per_tick_and_select_the_prepared_world() {
    let mut state = state();
    let id = Uuid::new_v4();
    state.add_player(id, "Walker".into(), Role::Human);
    assert!(state.mission_state().is_none());
    state.players[0].interaction_requested = true;
    state.tick(0.05);
    assert_eq!(progress(&state), (0, 0, MissionPhase::Briefing, 1));
    assert!(state.acknowledge_m02(id, 1));
    assert!(!state.acknowledge_m02(id, 1));
    state.tick(0.05);
    assert_eq!(progress(&state), (1, 0, MissionPhase::FindTransfer, 1));
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
    assert_eq!(progress(&state), (2, 1, MissionPhase::FindTransfer, 1));
    assert_eq!(state.map.arena().solids[2].bottom, 4.0);
    state.players[0].interaction_requested = true;
    state.tick(0.05);
    assert_eq!(progress(&state), (2, 1, MissionPhase::FindTransfer, 1));
    [state.players[0].x, state.players[0].y, state.players[0].z] = [0.0, PLAYER_FLOOR_Y, 4.0];
    state.tick(0.05);
    assert_eq!(progress(&state), (3, 1, MissionPhase::Departed, 1));
    state.tick(0.05);
    assert_eq!(progress(&state), (3, 1, MissionPhase::Departed, 1));
}

#[test]
fn unready_and_dead_participants_cannot_trigger_and_retry_restores_entry() {
    let mut state = state();
    assert_eq!(
        state.enable_campaign_run(),
        Err("durable campaign runs require M01 mission geometry")
    );
    let id = Uuid::new_v4();
    state.add_player(id, "Walker".into(), Role::Human);
    assert!(!state.acknowledge_m02(id, 2));
    assert!(state.acknowledge_m02(id, 1));
    state.players[0].hp = 0;
    state.advance_m02();
    assert_eq!(progress(&state), (0, 0, MissionPhase::FindTransfer, 1));
    state.players[0].hp = 100;
    state.advance_m02();
    assert_eq!(progress(&state), (1, 0, MissionPhase::FindTransfer, 1));
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
    assert_eq!(progress(&state), (1, 0, MissionPhase::FindTransfer, 1));
    let player = &mut state.players[0];
    [player.x, player.y, player.z] = [0.0, PLAYER_FLOOR_Y, -3.0];
    (player.yaw, player.pitch) =
        crate::combat::aim_at([player.x, crate::movement::EYE_HEIGHT, player.z], point).unwrap();
    player.interaction_requested = true;
    player.hp = 0;
    state.advance_m02();
    assert_eq!(progress(&state), (1, 0, MissionPhase::FindTransfer, 1));
    state.players[0].hp = 100;
    state.players[0].yaw = 0.0;
    state.players[0].pitch = 0.0;
    state.players[0].interaction_requested = true;
    state.advance_m02();
    assert_eq!(progress(&state), (1, 0, MissionPhase::FindTransfer, 1));
    (state.players[0].yaw, state.players[0].pitch) =
        crate::combat::aim_at([0.0, crate::movement::EYE_HEIGHT, -3.0], point).unwrap();
    state.players[0].interaction_requested = true;
    state.advance_m02();
    assert_eq!(progress(&state), (2, 1, MissionPhase::FindTransfer, 1));
    state.reset_mission();
    assert_eq!(progress(&state), (0, 0, MissionPhase::FindTransfer, 2));
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
