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

fn current(s: &GameSession) -> String {
    s.state
        .mission_state()
        .unwrap()
        .m17
        .unwrap()
        .current
        .unwrap()
        .id
}

/// Breach the approach and clear the hall, leaving the ring and Kessel open.
fn through_the_hall(s: &mut GameSession, id: Uuid) {
    tick(s);
    clear_enemies(s);
    tick(s);
    place(s, id, [0.0, 0.0, -17.0]);
    tick(s);
    tick(s);
    clear_enemies(s);
    tick(s);
    assert_eq!(current(s), "kessel_secured");
}

#[test]
fn service_stair_reaches_the_galleries_without_skipping_the_ring_or_the_console() {
    let (mut s, id) = session();
    through_the_hall(&mut s, id);
    let g = s.state.map.m17_geometry().unwrap();
    // The runner's line arrives on the east gallery and walks to the console
    // before the ring has fallen or Kessel is in custody: nothing advances,
    // the override refuses and the bulkhead stays shut.
    place(&mut s, id, [-10.0, 3.0, 8.0]);
    tick(&mut s);
    interact(&mut s, id, &g.core_override);
    assert_eq!(current(&s), "kessel_secured");
    let m17 = s.state.mission_state().unwrap().m17.unwrap();
    assert!(!m17.core_unsealed);
    assert_eq!(s.state.map.m17_stage(), 0);

    // The ring fight is the required alternative to Kessel's custody.
    place(&mut s, id, [-30.0, 0.0, -8.0]);
    tick(&mut s);
    clear_enemies(&mut s);
    tick(&mut s);
    assert_eq!(current(&s), "kessel_secured");
    // Standing on the floor beneath the console is not reaching the galleries.
    let below = [
        g.core_override.approach[0],
        0.0,
        g.core_override.approach[2] - 2.0,
    ];
    place(&mut s, id, below);
    tick(&mut s);
    assert_eq!(current(&s), "kessel_secured");
    // Climbing to the console deck is.
    place(&mut s, id, g.core_override.approach);
    tick(&mut s);
    assert_eq!(current(&s), "core_unsealed");
    assert!(!s.state.mission_state().unwrap().m17.unwrap().kessel_secured);
}

#[test]
fn the_override_is_used_on_the_gallery_and_opens_the_bulkhead() {
    let (mut s, id) = session();
    through_the_hall(&mut s, id);
    let g = s.state.map.m17_geometry().unwrap();
    interact(&mut s, id, &g.kessel_desk);
    assert_eq!(current(&s), "core_unsealed");
    // From the floor under the deck the console cannot be worked.
    let point = g
        .core_override
        .point(
            s.state.map.presentation_ref().unwrap(),
            &s.state.map.arena().solids,
        )
        .unwrap();
    place(&mut s, id, [point[0], 0.0, 13.0]);
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
    tick(&mut s);
    assert_eq!(current(&s), "core_unsealed");
    assert_eq!(s.state.map.m17_stage(), 0);
    let bulkhead_shut = |s: &GameSession| {
        s.state
            .map
            .arena()
            .blocked_body_at(-18.25, 19.0, 3.0, 3.0 + crate::movement::BODY_HEIGHT)
    };
    assert!(bulkhead_shut(&s));
    interact(&mut s, id, &g.core_override);
    assert_eq!(current(&s), "core_defeated");
    assert_eq!(s.state.map.m17_stage(), 1);
    assert!(!bulkhead_shut(&s));
}

#[test]
fn latch_follows_the_party_from_the_authored_start() {
    let (mut s, id) = session();
    tick(&mut s);
    let start = s.state.map.m17_objectives().unwrap().companion_start;
    let latch = s
        .state
        .players
        .iter()
        .find(|p| p.is_campaign_companion())
        .expect("Latch is with the party");
    assert!((latch.x - start[0]).hypot(latch.z - start[2]) < 0.5);
    assert!(latch.hp > 0);
    // Latch keeps up with the party on the level's ordinary routes.
    let away = [0.0, 0.0, -30.0];
    let before = (latch.x - away[0]).hypot(latch.z - away[2]);
    place(&mut s, id, away);
    for _ in 0..200 {
        clear_enemies(&mut s);
        tick(&mut s);
    }
    let latch = s
        .state
        .players
        .iter()
        .find(|p| p.is_campaign_companion())
        .unwrap();
    let after = (latch.x - away[0]).hypot(latch.z - away[2]);
    assert!(
        after < before - 1.0 && after < 9.0,
        "Latch follows: {before} -> {after}"
    );
    // A map that puts Latch in a wall is refused.
    let mut wrong: serde_json::Value = serde_json::from_str(MAP).unwrap();
    wrong["m17"]["companion_start"] = serde_json::json!([500.0, 0.0, 0.0]);
    assert!(AuthoredMap::read(serde_json::to_vec(&wrong).unwrap().as_slice()).is_err());
}
