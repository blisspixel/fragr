use super::*;
use crate::maps::AuthoredMap;
use crate::protocol::{Action, LookAt, Role, UseTarget};
use crate::session::GameSession;
use std::sync::{Arc, OnceLock};

const MAP: &str = include_str!("../../../maps/m17-peace-without-interruption.json");

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
    s.state.seed(1017);
    let id = Uuid::from_u128(1017);
    s.state.add_player(id, "Coalition operative".into(), role);
    if role == Role::Human {
        s.state.arm_joined_magazines(id);
    }
    assert!(s.state.acknowledge_mission(
        id,
        MissionReady {
            id: MissionId::PeaceWithoutInterruption,
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
        .replace_map_with_m17(
            map.m17_geometry().as_ref(),
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
fn office_lifecycle_progresses_from_breach_to_departure() {
    let (mut s, id) = session();
    tick(&mut s);
    let state = s.state.mission_state().unwrap();
    let m17 = state.m17.unwrap();
    assert_eq!(m17.completed.len(), 0);
    assert_eq!(m17.current.as_ref().unwrap().id, "approach_breached");
    assert!(!m17.challenges.approach_breached);
    assert!(!m17.core_unsealed);
    assert!(!m17.voss_captured);
    assert!(!m17.kessel_secured);

    let g = s.state.map.m17_geometry().unwrap();

    // Clear outer approach defenders
    clear_enemies(&mut s);
    tick(&mut s);

    // 0 -> 1: Approach breached (arrive at public hall)
    place(&mut s, id, [0.0, 0.0, -17.0]);
    tick(&mut s);
    let m17 = s.state.mission_state().unwrap().m17.unwrap();
    assert_eq!(m17.completed, vec!["approach_breached"]);
    assert_eq!(m17.current.as_ref().unwrap().id, "hall_secured");
    assert!(m17.challenges.approach_breached);

    // 1 -> 2: Clear public hall defenders
    tick(&mut s);
    clear_enemies(&mut s);
    tick(&mut s);
    let m17 = s.state.mission_state().unwrap().m17.unwrap();
    assert_eq!(m17.completed, vec!["approach_breached", "hall_secured"]);
    assert_eq!(m17.current.as_ref().unwrap().id, "kessel_secured");

    // 2 -> 3: Take Registrar Kessel into custody at committee desk
    interact(&mut s, id, &g.kessel_desk);
    let m17 = s.state.mission_state().unwrap().m17.unwrap();
    assert_eq!(
        m17.completed,
        vec!["approach_breached", "hall_secured", "kessel_secured"]
    );
    assert_eq!(m17.current.as_ref().unwrap().id, "core_unsealed");
    assert!(m17.challenges.kessel_secured);
    assert!(m17.kessel_secured);

    // 3 -> 4: Override security core seal at gallery console
    interact(&mut s, id, &g.core_override);
    let m17 = s.state.mission_state().unwrap().m17.unwrap();
    assert_eq!(
        m17.completed,
        vec![
            "approach_breached",
            "hall_secured",
            "kessel_secured",
            "core_unsealed"
        ]
    );
    assert_eq!(m17.current.as_ref().unwrap().id, "core_defeated");
    assert!(m17.core_unsealed);

    // 4 -> 5: Core defense eliminated
    place(&mut s, id, [0.0, 0.0, 26.0]);
    tick(&mut s);
    clear_enemies(&mut s);
    tick(&mut s);
    let m17 = s.state.mission_state().unwrap().m17.unwrap();
    assert_eq!(
        m17.completed,
        vec![
            "approach_breached",
            "hall_secured",
            "kessel_secured",
            "core_unsealed",
            "core_defeated"
        ]
    );
    assert_eq!(m17.current.as_ref().unwrap().id, "voss_captured");
    assert!(m17.challenges.core_defeated);

    // 5 -> 6: Confront Chancellor Voss at executive rostrum
    interact(&mut s, id, &g.voss_rostrum);
    let m17 = s.state.mission_state().unwrap().m17.unwrap();
    assert_eq!(m17.completed.len(), 6);
    assert_eq!(m17.current.as_ref().unwrap().id, "party_departed");
    assert!(m17.voss_captured);
    assert!(m17.challenges.voss_captured);

    // 6 -> Departed: Assemble at later exit
    place(&mut s, id, [24.0, 0.0, 38.0]);
    interact(&mut s, id, &g.departure);
    let state = s.state.mission_state().unwrap();
    assert_eq!(state.phase, MissionPhase::Departed);
    let m17 = state.m17.unwrap();
    assert!(m17.completed.contains(&"party_departed".to_string()));
}
