use crate::maps::{AuthoredMap, AuthoredSource};
use crate::protocol::{
    Action, CampaignDifficulty, LookAt, M05TramPhase, MissionId, MissionPhase, MissionReady, Role,
};
use crate::session::GameSession;
use crate::sim::PLAYER_FLOOR_Y;
use std::sync::{Arc, OnceLock};
use uuid::Uuid;

fn map() -> Arc<AuthoredMap> {
    static MAP: OnceLock<Arc<AuthoredMap>> = OnceLock::new();
    MAP.get_or_init(|| {
        AuthoredSource::Mission(MissionId::NoForwardingAddress)
            .load()
            .expect("bundled M05 route proof")
    })
    .clone()
}
fn fixture() -> (GameSession, Uuid) {
    let mut s = GameSession::with_authored_map(map());
    s.state.seed(42);
    s.state
        .set_campaign_difficulty(CampaignDifficulty::Standard)
        .unwrap();
    let id = Uuid::from_u128(5005);
    s.state.add_player(id, "Visitor".into(), Role::Human);
    assert!(s.state.acknowledge_mission(
        id,
        MissionReady {
            id: MissionId::NoForwardingAddress,
            attempt: 1
        }
    ));
    advance(&mut s, 1);
    (s, id)
}
fn advance(s: &mut GameSession, ticks: usize) {
    for _ in 0..ticks {
        s.tick_messages(0.05);
    }
}
fn place(s: &mut GameSession, id: Uuid, feet: [f32; 3]) {
    let p = s.state.players.iter_mut().find(|p| p.id == id).unwrap();
    p.x = feet[0];
    p.y = feet[1] + PLAYER_FLOOR_Y;
    p.z = feet[2];
    p.vy = 0.0;
    p.clear_input();
}
fn clear(s: &mut GameSession, index: usize) {
    let group = s.state.map.encounters()[index].clone();
    let id = s
        .state
        .players
        .iter()
        .find(|p| p.is_participant())
        .unwrap()
        .id;
    // Enter through a clear authored objective approach, rather than a solid boundary.
    let p = s.state.map.m05_geometry().unwrap().objectives[index].clone();
    let crate::protocol::MissionObjectiveAction::Arrival { feet: approach, .. } = p.action else {
        panic!("arrival");
    };
    place(s, id, approach);
    advance(s, 1);
    for e in &group.enemies {
        let p = s
            .state
            .players
            .iter_mut()
            .find(|p| p.name == e.id)
            .expect("current group spawned");
        p.hp = 0;
        s.state
            .encounters
            .hit(p.id, [p.x, p.y - PLAYER_FLOOR_Y, p.z], s.state.tick, true);
    }
    advance(s, 2);
    assert!(s.state.encounters.is_complete(index));
}
fn rescued_tram() -> (GameSession, Uuid) {
    let (mut s, id) = fixture();
    for i in 0..3 {
        clear(&mut s, i);
    }
    place(&mut s, id, [-19.0, 0.0, 1.5]);
    advance(&mut s, 2);
    assert_eq!(
        s.state.m05_released_worker_ids(),
        crate::protocol::M05_WORKER_IDS
    );
    assert!(s.state.m05_evacuated_worker_ids().is_empty());
    // Clear the trench before measuring isolated platform behavior.
    clear(&mut s, 3);
    place(&mut s, id, [0.0, 1.0, 6.0]);
    advance(&mut s, 1);
    (s, id)
}

#[test]
fn bundled_no_forwarding_address_routes() {
    let map = crate::maps::RuntimeMap::Authored(map());
    let g = map.m05_geometry().unwrap();
    assert_eq!(map.id(), 1005);
    assert_eq!(
        map.encounters()
            .iter()
            .map(|g| g.enemies.len())
            .sum::<usize>(),
        21
    );
    assert!(!g.freight_open);
    assert!(
        map.prepared_m05_world()
            .unwrap()
            .m05_geometry()
            .unwrap()
            .freight_open
    );
    assert_eq!(g.rescue.captives.len(), 3);
    for c in g.rescue.captives {
        assert!(g.boarding.contains(*c.route.last().unwrap()));
    }
}
#[test]
fn m05_ordered_groups_rescue_and_actual_party_departure() {
    let (mut s, id) = fixture();
    assert_eq!(
        s.state
            .players
            .iter()
            .filter(|p| p.is_campaign_enemy())
            .count(),
        4
    );
    assert!(!s.state.players.iter().any(|p| p.name == "lesson_heavy"));
    for i in 0..3 {
        clear(&mut s, i);
    }
    assert!(!s.state.mission_state().unwrap().m05.unwrap().group_released);
    place(&mut s, id, [-19.0, 0.0, 1.5]);
    advance(&mut s, 2);
    assert_eq!(s.state.m05_released_worker_ids().len(), 3);
    assert!(s.state.m05_evacuated_worker_ids().is_empty());
    for i in 3..6 {
        clear(&mut s, i);
    }
    advance(&mut s, 2);
    assert!(s.state.map.m05_geometry().unwrap().freight_open);
    place(&mut s, id, [6.5, 0.0, 37.5]);
    advance(&mut s, 1);
    let g = s.state.map.m05_geometry().unwrap();
    let point = g
        .departure
        .point(
            s.state.map.presentation_ref().unwrap(),
            &s.state.map.arena().solids,
        )
        .unwrap();
    let aim = LookAt {
        x: Some(point[0]),
        y: Some(point[1]),
        z: Some(point[2]),
        player_id: None,
    };
    s.state.set_action(
        id,
        Action {
            look_at: Some(aim.clone()),
            ..Action::default()
        },
    );
    advance(&mut s, 1);
    let state = s.state.mission_state().unwrap();
    assert_eq!(state.m05.unwrap().completed.len(), 6);
    assert_eq!(state.prompts.len(), 1);
    s.state.set_action(
        id,
        Action {
            interact: true,
            look_at: Some(aim),
            ..Action::default()
        },
    );
    advance(&mut s, 1);
    assert_eq!(
        s.state.mission_state().unwrap().phase,
        MissionPhase::Departed
    );
    assert!(
        s.state.m05_evacuated_worker_ids().is_empty(),
        "release must not invent aboard captives"
    );
}
#[test]
fn m05_tram_carries_supported_rider_and_preserves_real_cover() {
    let (mut s, id) = rescued_tram();
    let g = s.state.map.m05_geometry().unwrap();
    assert_eq!(
        s.state.mission_state().unwrap().m05.unwrap().tram.phase,
        M05TramPhase::Boarding
    );
    advance(&mut s, 65);
    let state = s.state.mission_state().unwrap();
    let tram = state.m05.unwrap().tram;
    assert_eq!(tram.phase, M05TramPhase::Moving);
    assert!(tram.feet[2] > 6.0);
    let p = s.state.players.iter().find(|p| p.id == id).unwrap();
    assert!((p.z - tram.feet[2]).abs() < 0.001);
    assert!((p.y - PLAYER_FLOOR_Y - 1.0).abs() < 0.001);
    let body = s.state.current_arena().solids[g.tram.solid];
    assert!((body.min_z - (tram.feet[2] - 2.0)).abs() < 0.001);
    assert!(!crate::combat::line_of_sight(
        [-3.0, 0.5, tram.feet[2]],
        [3.0, 0.5, tram.feet[2]],
        &s.state.current_arena().solids
    ));
    assert!(
        crate::combat::line_of_sight(
            [-3.0, 0.5, 4.1],
            [3.0, 0.5, 4.1],
            &s.state.current_arena().solids
        ),
        "parked body must not remain ghost cover after tram clears it"
    );
}
#[test]
fn m05_tram_refuses_actor_obstruction_then_resumes_and_resets() {
    let (mut s, id) = rescued_tram();
    let block = Uuid::from_u128(5050);
    s.state.add_player(block, "Blocker".into(), Role::Human);
    s.state.acknowledge_mission(
        block,
        MissionReady {
            id: MissionId::NoForwardingAddress,
            attempt: 1,
        },
    );
    place(&mut s, block, [0.0, 0.0, 8.52]);
    advance(&mut s, 65);
    let tram = s.state.mission_state().unwrap().m05.unwrap().tram;
    assert_eq!(tram.phase, M05TramPhase::Blocked);
    assert_eq!(tram.feet, [0.0, 0.0, 6.0]);
    assert_eq!(
        s.state.players.iter().find(|p| p.id == block).unwrap().hp,
        100
    );
    place(&mut s, block, [5.0, 0.0, 6.0]);
    advance(&mut s, 2);
    assert!(s.state.mission_state().unwrap().m05.unwrap().tram.feet[2] > 6.0);
    place(&mut s, id, [5.0, 0.0, 6.0]);
    let z = s.state.players.iter().find(|p| p.id == id).unwrap().z;
    advance(&mut s, 2);
    assert_eq!(
        s.state.players.iter().find(|p| p.id == id).unwrap().z,
        z,
        "dismounted actor must not be dragged"
    );
    s.state.reset_mission();
    let f = s.state.mission_state().unwrap().m05.unwrap();
    assert_eq!(f.tram.phase, M05TramPhase::Parked);
    assert_eq!(f.tram.feet, [0.0, 0.0, 6.0]);
    assert!(!f.group_released);
}
#[test]
fn m05_strict_authoring_rejects_roster_route_and_tram_geometry() {
    let original: serde_json::Value =
        serde_json::from_slice(include_bytes!("../../maps/m05_no_forwarding_address.json"))
            .unwrap();
    for (path, value) in [
        ("id", serde_json::json!("fake_worker")),
        ("tram_speed", serde_json::json!(99)),
        ("heavy", serde_json::json!("clerk")),
    ] {
        let mut d = original.clone();
        match path {
            "id" => d["m05"]["rescue"]["captives"][0]["id"] = value,
            "tram_speed" => d["m05"]["tram"]["speed"] = value,
            _ => d["encounters"][4]["enemies"][0]["kind"] = value,
        };
        assert!(
            AuthoredMap::read(serde_json::to_vec(&d).unwrap().as_slice()).is_err(),
            "{path}"
        );
    }
}
#[test]
fn m05_wire_bounds_and_controller_wait_for_matching_fresh_facts() {
    let (mut s, id) = rescued_tram();
    advance(&mut s, 65);
    let map = s.state.map.clone();
    let g = map.m05_geometry().unwrap();
    let state = s.state.mission_state().unwrap();
    let mut invalid = g.clone();
    invalid.rescue.captives[0].route.truncate(4);
    assert!(invalid
        .validate(
            map.half_extent(),
            &map.arena().solids,
            map.presentation_ref()
        )
        .is_err());
    let mut facts = state.clone();
    let f = facts.m05.as_mut().unwrap();
    f.workshop_secured = false;
    assert!(
        facts.validate(s.state.tick).is_err(),
        "completed workshop cannot be unsecured"
    );
    let mut client = crate::mission::MissionClient::default();
    client
        .replace_map_with_m05(
            Some(&g),
            map.half_extent(),
            &map.arena().solids,
            map.presentation_ref(),
        )
        .unwrap();
    let mut navigator = crate::navigation::Navigator::default();
    let wanted = Action {
        forward: true,
        fire: true,
        throw_grenade: true,
        ..Action::default()
    };
    let refused = client.steer(
        &mut navigator,
        map.navigation(),
        id,
        &s.state.snapshot(),
        wanted,
    );
    assert!(!refused.forward && !refused.fire && !refused.throw_grenade);
    client.observe(s.state.tick, state.clone()).unwrap();
    let mut forged = state;
    let f = forged.m05.as_mut().unwrap();
    f.tram.feet[2] += 2.0;
    f.tram.tick += 1;
    assert!(
        client.observe(s.state.tick + 1, forged).is_err(),
        "bounded pose cannot teleport two metres in one tick"
    );
}
#[test]
fn m05_workers_walk_to_actual_boarding_without_holding_party_departure() {
    let (mut s, id) = fixture();
    for i in 0..3 {
        clear(&mut s, i);
    }
    place(&mut s, id, [-19.0, 0.0, 1.5]);
    advance(&mut s, 2);
    for i in 3..6 {
        clear(&mut s, i);
    }
    assert!(s.state.m05_evacuated_worker_ids().is_empty());
    // Actor motion, including the gate crossing, remains ordinary server integration.
    advance(&mut s, 900);
    assert_eq!(
        s.state.m05_evacuated_worker_ids(),
        crate::protocol::M05_WORKER_IDS
    );
    assert_eq!(
        s.state.mission_state().unwrap().phase,
        MissionPhase::InProgress
    );
    assert!(!s.state.mission_state().unwrap().party[0].aboard);
}
#[test]
fn m05_grenade_bounces_off_live_translated_tram() {
    let (mut s, id) = rescued_tram();
    advance(&mut s, 65);
    let tram = s.state.mission_state().unwrap().m05.unwrap().tram;
    place(&mut s, id, [3.0, 0.0, tram.feet[2]]);
    s.state
        .players
        .iter_mut()
        .find(|p| p.id == id)
        .unwrap()
        .inventory
        .grant_grenades(1);
    s.state.set_action(
        id,
        Action {
            throw_grenade: true,
            yaw: Some(std::f32::consts::PI),
            pitch: Some(-0.7),
            ..Action::default()
        },
    );
    let mut previous_x = 3.0;
    let mut contact = None;
    for _ in 0..8 {
        advance(&mut s, 1);
        let snapshot = s.state.snapshot();
        assert_eq!(snapshot.grenades.len(), 1);
        let grenade = snapshot.grenades[0].clone();
        if grenade.bounce_count > 0 {
            assert!(
                grenade.position[0] >= 1.619 && grenade.position[1] > 0.121,
                "first contact must be the live east face above the floor: {grenade:?}"
            );
            assert!(
                previous_x > grenade.position[0],
                "throw approached the east face"
            );
            contact = Some(grenade);
            break;
        }
        previous_x = grenade.position[0];
    }
    let contact = contact.expect("real tram east face must bounce the sphere");
    advance(&mut s, 1);
    assert!(
        s.state.snapshot().grenades[0].position[0] > contact.position[0],
        "east-face contact reverses horizontal travel; a floor bounce cannot prove this"
    );
}

#[test]
fn m05_navigation_reserves_lane_but_uses_live_cover_for_combat() {
    use crate::navigation::{NavigationGoal, Navigator, RouteStatus, SEARCH_LIMIT};
    let map = crate::maps::RuntimeMap::Authored(map());
    let world = map.navigation();
    let geometry = map.m05_geometry().unwrap();
    let from = [-5.0, 0.0, 16.0];
    let goal = NavigationGoal {
        feet: [2.1, 0.0, 16.0],
        combat: true,
    };
    let wanted = Action {
        fire: true,
        ..Action::default()
    };
    let empty = Navigator::default().steer_with_visibility(
        world,
        from,
        goal,
        wanted.clone(),
        1,
        true,
        &map.arena().solids,
    );
    assert!(
        empty.fire,
        "the reserved lane is empty at this real tram pose"
    );
    let mut live = map.arena().clone();
    live.solids[geometry.tram.solid] = geometry
        .tram
        .body(live.solids[geometry.tram.solid], [0.0, 0.0, 16.0]);
    let blocked = Navigator::default().steer_with_visibility(
        world,
        from,
        goal,
        wanted.clone(),
        1,
        true,
        &live.solids,
    );
    assert!(
        !blocked.fire,
        "the translated tram actually blocks this descending chest shot"
    );
    let legacy = Navigator::default().steer(world, from, goal, wanted, 1, true);
    assert!(
        !legacy.fire,
        "legacy callers still use their navigation world's cover"
    );
    assert!(
        !world.walkable(from, goal.feet),
        "live sight cannot enable a route across the reserved lane"
    );
    let route = world.route([-5.0, 0.0, 6.0], [-5.0, 0.0, 30.0], SEARCH_LIMIT);
    assert_eq!(route.status, RouteStatus::Complete);
    assert!(
        route
            .points
            .iter()
            .all(|p| p[0].abs() > 1.5 || !(4.0..=30.0).contains(&p[2])),
        "ground route stays off the swept lane"
    );
    let phantom = world.route([0.0, 1.0, 10.0], [0.0, 1.0, 20.0], SEARCH_LIMIT);
    assert_ne!(
        phantom.status,
        RouteStatus::Complete,
        "a rider cannot plan along a continuous imaginary one-metre deck"
    );
}

#[test]
fn m05_external_controller_reconstructs_live_tram_cover() {
    let (mut s, id) = rescued_tram();
    advance(&mut s, 65);
    place(&mut s, id, [-5.0, 0.0, 16.0]);
    let map = s.state.map.clone();
    let g = map.m05_geometry().unwrap();
    let mut client = crate::mission::MissionClient::default();
    client
        .replace_map_with_m05(
            Some(&g),
            map.half_extent(),
            &map.arena().solids,
            map.presentation_ref(),
        )
        .unwrap();
    assert!(
        client.live_visibility_solids().is_none(),
        "map alone cannot invent a live tram pose"
    );
    client
        .observe(s.state.tick, s.state.mission_state().unwrap())
        .unwrap();
    let aimed_snapshot = |s: &GameSession| {
        let mut snapshot = s.state.snapshot();
        let target = snapshot
            .players
            .iter_mut()
            .find(|p| {
                matches!(
                    p.campaign,
                    Some(crate::protocol::CampaignActor::Union {
                        kind: crate::protocol::EnemyKind::Clerk,
                        ..
                    })
                )
            })
            .unwrap();
        // This isolated steering fixture supplies a living hostile at the edge
        // of the lane, without restarting the cleared encounter lifecycle.
        target.hp = 100;
        target.x = 2.1;
        target.y = PLAYER_FLOOR_Y;
        target.z = 16.0;
        let wanted = Action {
            fire: true,
            look_at: Some(LookAt {
                player_id: Some(target.id),
                x: None,
                y: None,
                z: None,
            }),
            ..Action::default()
        };
        (snapshot, wanted)
    };
    let (snapshot, wanted) = aimed_snapshot(&s);
    assert!(
        client
            .steer(
                &mut crate::navigation::Navigator::default(),
                map.navigation(),
                id,
                &snapshot,
                wanted
            )
            .fire
    );
    advance(&mut s, 167);
    let state = s.state.mission_state().unwrap();
    assert!(
        (state.m05.as_ref().unwrap().tram.feet[2] - 16.0).abs() < 1.0,
        "the real tram reaches the tested sight line"
    );
    client.observe(s.state.tick, state).unwrap();
    let solids = client.live_visibility_solids().unwrap();
    assert_eq!(
        solids[g.tram.solid],
        s.state.current_arena().solids[g.tram.solid]
    );
    let (snapshot, wanted) = aimed_snapshot(&s);
    assert!(
        !client
            .steer(
                &mut crate::navigation::Navigator::default(),
                map.navigation(),
                id,
                &snapshot,
                wanted
            )
            .fire,
        "external steering follows the current collider instead of parked cover"
    );
}
