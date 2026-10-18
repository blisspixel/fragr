use super::*;
use crate::maps::AuthoredMap;
use crate::protocol::{Action, LookAt, Role, UseTarget};
use crate::session::GameSession;
use std::sync::{Arc, OnceLock};

const MAP: &str = include_str!("../../../maps/m16-freedom-of-movement.json");

fn map() -> Arc<AuthoredMap> {
    static MAP_CACHE: OnceLock<Arc<AuthoredMap>> = OnceLock::new();
    MAP_CACHE
        .get_or_init(|| AuthoredMap::read(MAP.as_bytes()).unwrap())
        .clone()
}

fn session() -> (GameSession, Uuid) {
    session_role(Role::Agent)
}

fn session_role(role: Role) -> (GameSession, Uuid) {
    let mut s = GameSession::with_authored_map(map());
    s.state.use_replay_ids();
    s.state.seed(1016);
    let id = Uuid::from_u128(1016);
    s.state.add_player(id, "Avenue rider".into(), role);
    if role == Role::Human {
        s.state.arm_joined_magazines(id);
    }
    assert!(s.state.acknowledge_mission(
        id,
        MissionReady {
            id: MissionId::FreedomOfMovement,
            attempt: 1,
        }
    ));
    (s, id)
}

fn tick(s: &mut GameSession) {
    s.tick_messages(0.05);
    let map = &s.state.map;
    crate::protocol::validate_decorations(
        &map.presentation_ref().unwrap().decorations,
        &map.arena().solids,
    )
    .unwrap();
    let mut reader = MissionClient::default();
    reader
        .replace_map_with_id(
            map.id(),
            None,
            false,
            None,
            map.half_extent(),
            &map.arena().solids,
            map.presentation_ref(),
        )
        .unwrap();
    reader
        .replace_map_with_m16(
            map.m16_geometry().as_ref(),
            map.half_extent(),
            &map.arena().solids,
            map.presentation_ref(),
        )
        .unwrap();
    reader
        .observe(s.state.tick, s.state.mission_state().unwrap())
        .unwrap();
    s.state
        .mission_state()
        .unwrap()
        .validate(s.state.tick)
        .unwrap();
}

fn place(s: &mut GameSession, id: Uuid, feet: [f32; 3]) {
    let p = s.state.players.iter_mut().find(|p| p.id == id).unwrap();
    [p.x, p.y, p.z] = [feet[0], feet[1] + PLAYER_FLOOR_Y, feet[2]];
    p.vy = 0.0;
    p.clear_input();
}

fn interact(s: &mut GameSession, id: Uuid, target: &UseTarget) {
    let point = target
        .point(
            s.state.map.presentation_ref().unwrap(),
            &s.state.map.arena().solids,
        )
        .unwrap();
    place(s, id, target.approach);
    s.state.set_action(
        id,
        Action {
            interact: true,
            look_at: Some(LookAt {
                x: Some(point[0]),
                y: Some(point[1]),
                z: Some(point[2]),
                player_id: None,
            }),
            ..Default::default()
        },
    );
    tick(s);
}

fn clear_enemies(s: &mut GameSession) {
    for i in 0..s.state.players.len() {
        let p = &s.state.players[i];
        if !p.is_participant() && p.hp > 0 {
            let damage = p.hp + p.armor;
            s.state.environmental_self_damage(i, damage);
        }
    }
}

#[test]
fn avenue_lifecycle_progresses_from_ride_to_departure() {
    let (mut s, id) = session();
    tick(&mut s);
    let state = s.state.mission_state().unwrap();
    let m16 = state.m16.unwrap();
    assert_eq!(m16.completed.len(), 0);
    assert_eq!(m16.current.as_ref().unwrap().id, "ride_started");
    assert!(!m16.challenges.ride_started);
    assert!(!m16.checkpoint_lifted);
    assert!(!m16.doors_open);

    let g = s.state.map.m16_geometry().unwrap();

    // 0 -> 1: Ride started (reach avenue lane)
    place(&mut s, id, [-30.0, 0.0, 0.0]);
    tick(&mut s);
    let m16 = s.state.mission_state().unwrap().m16.unwrap();
    assert_eq!(m16.completed, vec!["ride_started"]);
    assert_eq!(m16.current.as_ref().unwrap().id, "barricade_broken");
    assert!(m16.challenges.ride_started);

    // 1 -> 2: Clear first stretch and arrive at barricade
    clear_enemies(&mut s);
    place(&mut s, id, [-9.5, 0.0, 0.0]);
    tick(&mut s);
    let m16 = s.state.mission_state().unwrap().m16.unwrap();
    assert_eq!(m16.completed, vec!["ride_started", "barricade_broken"]);
    assert_eq!(m16.current.as_ref().unwrap().id, "green_wave_triggered");

    // 2 -> 3: Clear barricade post and trigger green wave at checkpoint
    clear_enemies(&mut s);
    place(&mut s, id, [10.5, 0.0, 0.0]);
    tick(&mut s);
    let m16 = s.state.mission_state().unwrap().m16.unwrap();
    assert_eq!(
        m16.completed,
        vec!["ride_started", "barricade_broken", "green_wave_triggered"]
    );
    assert_eq!(m16.current.as_ref().unwrap().id, "bus_freed");
    assert!(m16.challenges.green_wave_triggered);
    assert!(m16.checkpoint_lifted);

    // 3 -> 4: Free prison bus detainees via emergency release
    interact(&mut s, id, &g.bus_release);
    let m16 = s.state.mission_state().unwrap().m16.unwrap();
    assert_eq!(
        m16.completed,
        vec![
            "ride_started",
            "barricade_broken",
            "green_wave_triggered",
            "bus_freed"
        ]
    );
    assert_eq!(m16.current.as_ref().unwrap().id, "forecourt_secured");
    assert!(m16.challenges.bus_freed);
    assert!(m16.bus_freed);

    // 4 -> 5: Forecourt assault cleared
    clear_enemies(&mut s);
    place(&mut s, id, [26.5, 0.0, 0.0]);
    tick(&mut s);
    let m16 = s.state.mission_state().unwrap().m16.unwrap();
    assert_eq!(
        m16.completed,
        vec![
            "ride_started",
            "barricade_broken",
            "green_wave_triggered",
            "bus_freed",
            "forecourt_secured"
        ]
    );
    assert_eq!(m16.current.as_ref().unwrap().id, "doors_reached");
    assert!(m16.forecourt_secured);

    // 5 -> 6: Reach Forever Office chamber doors
    place(&mut s, id, [37.0, 0.0, 0.0]);
    tick(&mut s);
    let m16 = s.state.mission_state().unwrap().m16.unwrap();
    assert_eq!(m16.completed.len(), 6);
    assert_eq!(m16.current.as_ref().unwrap().id, "party_departed");
    assert!(m16.doors_open);

    // 6 -> Departed
    interact(&mut s, id, &g.departure);
    let state = s.state.mission_state().unwrap();
    assert_eq!(state.phase, MissionPhase::Departed);
    let m16 = state.m16.unwrap();
    assert!(m16.completed.contains(&"party_departed".to_string()));
}
