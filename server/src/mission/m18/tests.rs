use super::*;
use crate::maps::AuthoredMap;
use crate::protocol::{Action, LookAt, Role, UseTarget};
use crate::session::GameSession;
use std::sync::{Arc, OnceLock};

const MAP: &str = include_str!("../../../maps/m18-all-systems-normal.json");

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
    s.state.seed(1018);
    let id = Uuid::from_u128(1018);
    s.state.add_player(id, "Coalition operative".into(), role);
    if role == Role::Human {
        s.state.arm_joined_magazines(id);
    }
    assert!(s.state.acknowledge_mission(
        id,
        MissionReady {
            id: MissionId::AllSystemsNormal,
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
        .replace_map_with_m18(
            map.m18_geometry().as_ref(),
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
fn collector_rubble_waits_for_solo_and_party_bodies_to_walk_clear() {
    for paired in [false, true] {
        let (mut s, id) = session_role(Role::Human);
        tick(&mut s);
        let g = s.state.map.m18_geometry().unwrap();
        interact(&mut s, id, &g.depot_station);
        clear_enemies(&mut s);
        place(&mut s, id, [-35.0, 0.0, 0.0]);
        tick(&mut s);
        tick(&mut s);
        clear_enemies(&mut s);
        let occupying = if paired {
            let partner = Uuid::from_u128(1819);
            s.state
                .add_player(partner, "Rubble partner".into(), Role::Human);
            assert!(s.state.acknowledge_mission(
                partner,
                MissionReady {
                    id: MissionId::AllSystemsNormal,
                    attempt: 1
                }
            ));
            place(&mut s, id, [-14.0, 0.0, 0.0]);
            partner
        } else {
            id
        };
        place(&mut s, occupying, [-8.0, 0.1, 0.0]);
        let intact = s.state.map.clone();
        for _ in 0..4 {
            tick(&mut s);
        }
        assert_eq!(
            s.state.map, intact,
            "a living body refuses the whole collision change"
        );
        assert!(
            !s.state
                .mission_state()
                .unwrap()
                .m18
                .unwrap()
                .roadblock_active
        );
        // Leave the slab through the ordinary walking action, without relocation.
        s.state.set_action(
            occupying,
            Action {
                forward: true,
                yaw: Some(std::f32::consts::PI),
                ..Default::default()
            },
        );
        for _ in 0..30 {
            tick(&mut s);
        }
        let state = s.state.mission_state().unwrap().m18.unwrap();
        assert!(state.roadblock_active);
        assert_eq!(state.completed.len(), 3);
        for p in s.state.players.iter().filter(|p| p.is_participant()) {
            let feet = p.y - PLAYER_FLOOR_Y;
            assert!(p.hp > 0);
            assert!(!s.state.map.arena().blocked_body_at(p.x, p.z, feet, feet));
        }
    }
}

#[test]
fn recovery_lifecycle_progresses_from_checkin_to_departure() {
    let (mut s, id) = session();
    tick(&mut s);
    let state = s.state.mission_state().unwrap();
    let m18 = state.m18.unwrap();
    assert_eq!(m18.completed.len(), 0);
    assert_eq!(m18.current.as_ref().unwrap().id, "aid_checkin");
    assert!(!m18.challenges.aid_delivered);
    assert!(!m18.roadblock_active);
    assert!(!m18.overlook_witnessed);
    assert!(!m18.concourse_secured);

    let g = s.state.map.m18_geometry().unwrap();

    // Objective 0: aid_checkin
    interact(&mut s, id, &g.depot_station);
    let m18 = s.state.mission_state().unwrap().m18.unwrap();
    assert_eq!(m18.completed, vec!["aid_checkin"]);
    assert_eq!(m18.current.as_ref().unwrap().id, "square_defense");
    assert!(m18.aid_delivered);
    assert!(m18.challenges.aid_delivered);

    // Objective 1: square_defense
    clear_enemies(&mut s);
    place(&mut s, id, [-35.0, 0.0, 0.0]);
    tick(&mut s);
    let m18 = s.state.mission_state().unwrap().m18.unwrap();
    assert_eq!(m18.completed, vec!["aid_checkin", "square_defense"]);
    assert_eq!(m18.current.as_ref().unwrap().id, "collector_breach");
    assert!(m18.challenges.square_defended);

    // Objective 2: collector_breach
    tick(&mut s);
    clear_enemies(&mut s);
    place(&mut s, id, [-14.0, 0.0, 0.0]);
    tick(&mut s);
    let m18 = s.state.mission_state().unwrap().m18.unwrap();
    assert_eq!(
        m18.completed,
        vec!["aid_checkin", "square_defense", "collector_breach"]
    );
    assert_eq!(m18.current.as_ref().unwrap().id, "service_ascent");
    assert!(m18.roadblock_active);

    // Objective 3: service_ascent
    tick(&mut s);
    clear_enemies(&mut s);
    place(&mut s, id, [18.0, 3.0, 20.0]);
    tick(&mut s);
    let m18 = s.state.mission_state().unwrap().m18.unwrap();
    assert_eq!(
        m18.completed,
        vec![
            "aid_checkin",
            "square_defense",
            "collector_breach",
            "service_ascent"
        ]
    );
    assert_eq!(m18.current.as_ref().unwrap().id, "overlook_recon");

    // Objective 4: overlook_recon
    tick(&mut s);
    clear_enemies(&mut s);
    interact(&mut s, id, &g.overlook_console);
    let m18 = s.state.mission_state().unwrap().m18.unwrap();
    assert_eq!(
        m18.completed,
        vec![
            "aid_checkin",
            "square_defense",
            "collector_breach",
            "service_ascent",
            "overlook_recon"
        ]
    );
    assert_eq!(m18.current.as_ref().unwrap().id, "concourse_evac");
    assert!(m18.overlook_witnessed);
    assert!(m18.challenges.overlook_witnessed);

    // Objective 5: concourse_evac
    tick(&mut s);
    clear_enemies(&mut s);
    place(&mut s, id, [53.0, 4.5, 0.0]);
    tick(&mut s);
    let m18 = s.state.mission_state().unwrap().m18.unwrap();
    assert_eq!(
        m18.completed,
        vec![
            "aid_checkin",
            "square_defense",
            "collector_breach",
            "service_ascent",
            "overlook_recon",
            "concourse_evac"
        ]
    );
    assert_eq!(m18.current.as_ref().unwrap().id, "party_departed");
    assert!(m18.concourse_secured);
    assert!(m18.challenges.concourse_secured);

    // Departure
    interact(&mut s, id, &g.departure);
    assert_eq!(
        s.state.mission.as_ref().unwrap().phase,
        MissionPhase::Departed
    );
    let m18 = s.state.mission_state().unwrap().m18.unwrap();
    assert_eq!(m18.completed.len(), 7);
    assert!(m18.current.is_none());
}
