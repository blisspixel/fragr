use crate::maps::{AuthoredSource, RuntimeMap};
use crate::protocol::MissionId;
use crate::protocol::{Action, LookAt, MissionPhase, MissionReady, Role, WeaponType};
use crate::session::GameSession;
use serde_json::json;
use uuid::Uuid;

fn document() -> serde_json::Value {
    json!({"version":1,"map_id":1003,"name":"Scheduled fixture","half_extent":20,"ground":"concrete","equipment":"discovery",
        "solids":[{"id":"pod","min":[7.5,3,3.5],"max":[8.5,4,4.5],"surface":"service_steel"},{"id":"control","min":[-1,0,8],"max":[1,2,9],"surface":"service_steel"}],
        "spawns":[{"id":"entry","feet":[0,0,0],"yaw":0}],"landmarks":[{"id":"mast_approach","feet":[4,0,4]}],
        "encounters":[
            {"id":"mast_watch","regions":[{"min":[-20,0,-20],"max":[20,2,20]}],"enemies":[{"id":"mast_guard","kind":"clerk","feet":[12,0,-8],"yaw":0}]},
            {"id":"train_watch","regions":[{"min":[-20,0,-20],"max":[20,2,20]}],"enemies":[{"id":"train_guard","kind":"clerk","feet":[12,0,-12],"yaw":0}]},
            {"id":"car_watch","regions":[{"min":[-20,0,-20],"max":[20,2,20]}],"enemies":[{"id":"car_guard","kind":"clerk","feet":[-12,0,-12],"yaw":0}]}],
        "m03":{"mast":{"solid":"pod","approach":[4,0,4],"aim":[8,3.5,4],"requires_encounter":"mast_watch","fallen":[{"solid":"pod","min":[7.5,0,3.5],"max":[8.5,0.4,4.5]}]},
            "departure":{"panel":{"solid":"control","face":"north","center":[0,0],"size":[0.8,0.8],"kind":"m03_board_train"},"approach":[0,0,6],"boarding":{"min":[-3,0,4],"max":[3,2,8]},"requires_encounter":"train_watch"},
            "companion_start":[-2,0,0],"cars":[{"id":"platform_car","requires_encounter":"car_watch","release":{"min":[-6,0,-2],"max":[-3,2,2]},"held":[[-5,0,0],[-5,0,1]],"safe":[[-8,0,0],[-8,0,1]]}]}})
}
fn fixture() -> (GameSession, Uuid) {
    let map = crate::maps::AuthoredMap::read(serde_json::to_vec(&document()).unwrap().as_slice())
        .unwrap();
    let mut session = GameSession::with_authored_map(map);
    session.state.seed(42);
    let id = Uuid::from_u128(3003);
    session.state.add_player(id, "Visitor".into(), Role::Human);
    (session, id)
}
fn ready(session: &mut GameSession, id: Uuid) {
    assert!(session.state.acknowledge_mission(
        id,
        MissionReady {
            id: MissionId::ScheduledService,
            attempt: 1
        }
    ));
    session.tick_messages(0.05);
}
fn place(session: &mut GameSession, id: Uuid, feet: [f32; 3]) {
    let player = session
        .state
        .players
        .iter_mut()
        .find(|p| p.id == id)
        .unwrap();
    player.x = feet[0];
    player.y = feet[1] + crate::sim::PLAYER_FLOOR_Y;
    player.z = feet[2];
    player.clear_input();
}
fn clear_group(session: &mut GameSession, index: usize) {
    let feet = session.state.map.encounters()[index].enemies[0].feet;
    for p in &mut session.state.players {
        if p.is_campaign_enemy() && (p.x - feet[0]).abs() < 0.1 && (p.z - feet[2]).abs() < 0.1 {
            p.hp = 0;
        }
    }
    session.tick_messages(0.05);
    assert!(session.state.encounters.is_complete(index));
}
fn shoot_pod(session: &mut GameSession, id: Uuid) {
    let point = session.state.map.m03_geometry().unwrap().mast.aim;
    let player = session
        .state
        .players
        .iter_mut()
        .find(|p| p.id == id)
        .unwrap();
    player.inventory.grant_weapon(WeaponType::Rail);
    player.weapon = WeaponType::Rail;
    player.fire_cooldown = 0;
    session.state.set_action(
        id,
        Action {
            fire: true,
            look_at: Some(LookAt {
                x: Some(point[0]),
                y: Some(point[1]),
                z: Some(point[2]),
                player_id: None,
            }),
            ..Default::default()
        },
    );
    session.state.tick(0.05);
    session.state.set_action(id, Action::default());
}
#[test]
fn m03_real_shot_requires_mast_defenders_and_switches_prepared_world() {
    let (mut session, id) = fixture();
    assert_eq!(
        session.state.mission_state().unwrap().phase,
        MissionPhase::Briefing
    );
    assert!(!session.state.acknowledge_mission(
        id,
        MissionReady {
            id: MissionId::RecallNotice,
            attempt: 1
        }
    ));
    ready(&mut session, id);
    place(&mut session, id, [4., 0., 4.]);
    shoot_pod(&mut session, id);
    assert_eq!(
        session.state.mission_state().unwrap().m03.unwrap().mast_hp,
        40
    );
    clear_group(&mut session, 0);
    shoot_pod(&mut session, id);
    let state = session.state.mission_state().unwrap();
    state.validate(session.state.tick).unwrap();
    assert_eq!(state.m03.unwrap().mast_hp, 0);
    assert!(session.state.map.m03_geometry().unwrap().mast_shutdown);
    assert!(session
        .state
        .players
        .iter()
        .any(|p| p.is_campaign_companion()));
}
#[test]
fn m03_optional_car_requires_clear_and_approach_then_walks_without_departure_gate() {
    let (mut session, id) = fixture();
    ready(&mut session, id);
    place(&mut session, id, [-5., 0., 0.]);
    session.state.advance_m03_captives(0.05);
    assert!(session.state.m03_liberated_car_ids().is_empty());
    place(&mut session, id, [0., 0., 0.]);
    clear_group(&mut session, 2);
    place(&mut session, id, [0., 0., 0.]);
    session.state.advance_m03_captives(0.05);
    assert!(session.state.m03_liberated_car_ids().is_empty());
    place(&mut session, id, [-5., 0., 0.]);
    session.state.advance_m03_captives(0.05);
    assert_eq!(session.state.m03_liberated_car_ids(), vec!["platform_car"]);
    let first = session.state.mission_state().unwrap().m03.unwrap().cars[0].captives;
    assert!(first[0][0] < -5. && first[0][0] > -8.);
    for _ in 0..40 {
        session.state.advance_m03_captives(0.05);
    }
    assert!(
        (session.state.mission_state().unwrap().m03.unwrap().cars[0].captives[0][0] + 8.).abs()
            < 0.01
    );
    session.state.reset_mission();
    assert!(session.state.m03_liberated_car_ids().is_empty());
    assert!(!session.state.map.m03_geometry().unwrap().mast_shutdown);
}
#[test]
fn m03_departure_consumes_early_press_and_requires_final_clear_and_entire_party() {
    let (mut session, id) = fixture();
    ready(&mut session, id);
    clear_group(&mut session, 0);
    place(&mut session, id, [4., 0., 4.]);
    shoot_pod(&mut session, id);
    place(&mut session, id, [0., 0., 6.]);
    let point = session
        .state
        .map
        .m03_geometry()
        .unwrap()
        .departure
        .point(
            session.state.map.presentation_ref().unwrap(),
            &session.state.map.arena().solids,
        )
        .unwrap();
    let aim = Action {
        interact: true,
        look_at: Some(LookAt {
            x: Some(point[0]),
            y: Some(point[1]),
            z: Some(point[2]),
            player_id: None,
        }),
        ..Default::default()
    };
    session.state.set_action(id, aim.clone());
    session.state.tick(0.05);
    assert!(!session.state.mission_departed());
    assert!(
        !session
            .state
            .players
            .iter()
            .find(|p| p.id == id)
            .unwrap()
            .interaction_requested
    );
    session.state.set_action(id, Action::default());
    clear_group(&mut session, 1);
    let late = Uuid::from_u128(3004);
    session.state.add_player(late, "Late".into(), Role::Agent);
    session.state.set_action(id, aim.clone());
    session.state.tick(0.05);
    assert!(!session.state.mission_departed());
    assert!(session.state.acknowledge_mission(
        late,
        MissionReady {
            id: MissionId::ScheduledService,
            attempt: 1
        }
    ));
    place(&mut session, late, [0., 0., 6.]);
    session.state.set_action(id, Action::default());
    session.state.tick(0.05);
    session.state.set_action(id, aim);
    session.state.tick(0.05);
    assert!(session.state.mission_departed());
    assert!(session.state.m03_liberated_car_ids().is_empty());
    session
        .state
        .mission_state()
        .unwrap()
        .validate(session.state.tick)
        .unwrap();
}

#[test]
fn bundled_scheduled_service_routes() {
    let map = RuntimeMap::Authored(
        AuthoredSource::Mission(MissionId::ScheduledService)
            .load()
            .unwrap(),
    );
    assert_eq!(map.id(), 1003);
    assert!(!map.m03_geometry().unwrap().mast_shutdown);
    let fallen = map.prepared_m03_world().unwrap();
    assert!(fallen.m03_geometry().unwrap().mast_shutdown);
    assert_eq!(map.content_sha256(), fallen.content_sha256());
    assert_eq!(map.arena().solids.len(), fallen.arena().solids.len());
}

#[test]
fn m03_actual_cover_and_friendly_body_intercept_pod_shots() {
    let mut doc = document();
    doc["solids"]
        .as_array_mut()
        .unwrap()
        .push(json!({"id":"cover","min":[5,0,-1],"max":[6,5,2],"surface":"concrete"}));
    let map = crate::maps::AuthoredMap::read(serde_json::to_vec(&doc).unwrap().as_slice()).unwrap();
    let mut session = GameSession::with_authored_map(map);
    let id = Uuid::from_u128(3003);
    session.state.add_player(id, "Visitor".into(), Role::Human);
    ready(&mut session, id);
    clear_group(&mut session, 0);
    place(&mut session, id, [4., 0., 0.]);
    shoot_pod(&mut session, id);
    assert_eq!(
        session.state.mission_state().unwrap().m03.unwrap().mast_hp,
        40
    );
    place(&mut session, id, [4., 0., 4.]);
    let blocker = Uuid::from_u128(3004);
    session
        .state
        .add_player(blocker, "Blocker".into(), Role::Human);
    assert!(session.state.acknowledge_mission(
        blocker,
        MissionReady {
            id: MissionId::ScheduledService,
            attempt: 1
        }
    ));
    session.state.spawn_shields.remove(&blocker);
    place(&mut session, blocker, [6., 1.2, 4.]);
    shoot_pod(&mut session, id);
    assert_eq!(
        session.state.mission_state().unwrap().m03.unwrap().mast_hp,
        40
    );
    assert!(session
        .state
        .shot_results
        .iter()
        .any(|shot| shot.target_id == Some(blocker)));
}

#[test]
fn m03_rejects_unregistered_impacts_and_hostile_damage() {
    let (mut session, id) = fixture();
    ready(&mut session, id);
    clear_group(&mut session, 0);
    for (shooter, solid, end, normal) in [
        (id, 1, [7.5, 3.5, 4.], [-1., 0., 0.]),
        (id, 0, [8., 3.5, 4.], [-1., 0., 0.]),
        (id, 0, [7.5, 3.5, 4.], [0., 0., 0.]),
        (Uuid::nil(), 0, [7.5, 3.5, 4.], [-1., 0., 0.]),
    ] {
        session
            .state
            .damage_m03_mast(shooter, solid, end, normal, 80);
        assert_eq!(
            session.state.mission_state().unwrap().m03.unwrap().mast_hp,
            40
        );
    }
    session
        .state
        .damage_m03_mast(id, 0, [7.5, 3.5, 4.], [-1., 0., 0.], 20);
    assert_eq!(
        session.state.mission_state().unwrap().m03.unwrap().mast_hp,
        20
    );
}

#[test]
fn m03_authoring_rejects_invalid_references_routes_and_mixed_missions() {
    for change in 0..10 {
        let mut doc = document();
        match change {
            0 => doc["m03"]["mast"]["solid"] = json!("missing"),
            1 => doc["m03"]["mast"]["requires_encounter"] = json!("missing"),
            2 => doc["m03"]["mast"]["fallen"] = json!([]),
            3 => doc["m03"]["mast"]["fallen"][0]["solid"] = json!("control"),
            4 => doc["m03"]["departure"]["requires_encounter"] = json!("mast_watch"),
            5 => doc["m03"]["cars"][0]["requires_encounter"] = json!("train_watch"),
            6 => doc["m03"]["mast"]["aim"] = json!([0, 0, 0]),
            7 => doc["m03"]["companion_start"] = json!([0, 0, 8.5]),
            8 => doc["map_id"] = json!(1004),
            _ => doc["m03"]["departure"]["approach"] = json!([0, 0, -10]),
        }
        assert!(
            crate::maps::AuthoredMap::read(serde_json::to_vec(&doc).unwrap().as_slice()).is_err(),
            "invalid case {change} was accepted"
        );
    }
}

#[test]
fn m03_shared_controller_binds_targets_and_clears_stale_shoot_on_map_transition() {
    let (mut session, id) = fixture();
    ready(&mut session, id);
    clear_group(&mut session, 0);
    place(&mut session, id, [4., 0., 4.]);
    let mut controller = crate::mission::MissionClient::default();
    let map = session.state.map.clone();
    let geometry = map.m03_geometry().unwrap();
    controller
        .replace_map_with_id(
            1003,
            None,
            false,
            None,
            map.half_extent(),
            &map.arena().solids,
            map.presentation_ref(),
        )
        .unwrap();
    controller
        .replace_map_with_m03(
            Some(&geometry),
            map.half_extent(),
            &map.arena().solids,
            map.presentation_ref(),
        )
        .unwrap();
    let state = session.state.mission_state().unwrap();
    controller
        .observe(session.state.tick, state.clone())
        .unwrap();
    let mut navigator = crate::navigation::Navigator::default();
    let shot = controller.steer(
        &mut navigator,
        map.navigation(),
        id,
        &session.state.snapshot(),
        Action::default(),
    );
    assert!(shot.fire);
    assert!(shot.look_at.is_some());
    let mut forged = state.clone();
    if let crate::protocol::MissionObjectiveAction::Shoot { aim, .. } = &mut forged
        .m03
        .as_mut()
        .unwrap()
        .current
        .as_mut()
        .unwrap()
        .action
    {
        aim[0] = 0.;
    }
    assert!(controller.observe(session.state.tick, forged).is_err());
    shoot_pod(&mut session, id);
    let fallen = session.state.map.clone();
    let geometry = fallen.m03_geometry().unwrap();
    controller
        .replace_map_with_id(
            1003,
            None,
            false,
            None,
            fallen.half_extent(),
            &fallen.arena().solids,
            fallen.presentation_ref(),
        )
        .unwrap();
    controller
        .replace_map_with_m03(
            Some(&geometry),
            fallen.half_extent(),
            &fallen.arena().solids,
            fallen.presentation_ref(),
        )
        .unwrap();
    assert!(
        !controller
            .steer(
                &mut navigator,
                fallen.navigation(),
                id,
                &session.state.snapshot(),
                Action::default()
            )
            .fire
    );
    controller
        .observe(session.state.tick, session.state.mission_state().unwrap())
        .unwrap();
    let mut rewound = session.state.mission_state().unwrap();
    rewound.m03.as_mut().unwrap().mast_hp = 40;
    assert!(controller.observe(session.state.tick, rewound).is_err());
    session.state.reset_mission();
    let map = session.state.map.clone();
    let geometry = map.m03_geometry().unwrap();
    controller
        .replace_map_with_id(
            1003,
            None,
            false,
            None,
            map.half_extent(),
            &map.arena().solids,
            map.presentation_ref(),
        )
        .unwrap();
    controller
        .replace_map_with_m03(
            Some(&geometry),
            map.half_extent(),
            &map.arena().solids,
            map.presentation_ref(),
        )
        .unwrap();
    controller
        .observe(session.state.tick, session.state.mission_state().unwrap())
        .unwrap();
}

#[tokio::test]
async fn live_m03_rules_three_refuses_24_and_current_reader_receives_geometry_before_state() {
    use futures_util::{SinkExt, StreamExt};
    use std::time::Duration;
    use tokio_tungstenite::{connect_async, tungstenite::Message};
    let (ready_tx, ready_rx) = tokio::sync::oneshot::channel();
    let (stop_tx, stop_rx) = tokio::sync::oneshot::channel();
    let server = tokio::spawn(crate::run::run_server(
        crate::run::ServerOptions {
            bind: "127.0.0.1:0".into(),
            bots: 0,
            authored: Some(AuthoredSource::Mission(MissionId::ScheduledService)),
            ..Default::default()
        },
        async {
            let _ = stop_rx.await;
        },
        Some(ready_tx),
    ));
    let address = tokio::time::timeout(Duration::from_secs(60), ready_rx)
        .await
        .unwrap()
        .unwrap();
    for version in [24, 25, crate::protocol::GAMEPLAY_VERSION] {
        for role in ["human", "agent", "spectator"] {
            let (mut socket, _) = connect_async(format!("ws://{address}")).await.unwrap();
            socket.send(Message::Text(json!({"type":"hello","role":role,"name":"ServiceProbe","gameplay_version":version,"geometry_version":crate::protocol::GEOMETRY_VERSION}).to_string())).await.unwrap();
            tokio::time::timeout(Duration::from_secs(5), async {
                let (mut map, mut welcome, mut mission, mut snapshot) =
                    (false, false, false, false);
                loop {
                    let message = socket.next().await.unwrap().unwrap();
                    let Message::Text(text) = message else {
                        continue;
                    };
                    let value: serde_json::Value = serde_json::from_str(&text).unwrap();
                    if version < crate::protocol::GAMEPLAY_VERSION {
                        assert_eq!(value["type"], "error", "old reader received game state");
                        assert_eq!(value["code"], "unsupported_gameplay");
                        assert!(value["message"].as_str().unwrap().contains("26"));
                        break;
                    }
                    match value["type"].as_str().unwrap() {
                        "map_info" => {
                            assert_eq!(value["map_id"], 1003);
                            assert_eq!(value["m03"]["mast_shutdown"], false);
                            map = true;
                        }
                        "welcome" => welcome = true,
                        "mission" => {
                            assert!(map, "mission overtook geometry for {role}");
                            assert_eq!(value["state"]["id"], "scheduled_service");
                            mission = true;
                        }
                        "snapshot" => {
                            assert!(
                                map && welcome,
                                "snapshot overtook initial admission for {role}"
                            );
                            snapshot = true;
                        }
                        "error" => panic!("current reader rejected: {value}"),
                        _ => {}
                    }
                    if mission && snapshot {
                        break;
                    }
                }
            })
            .await
            .expect("bounded M03 capability admission");
            let _ = socket.close(None).await;
        }
    }
    stop_tx.send(()).unwrap();
    server.await.unwrap().unwrap();
}

#[test]
fn m03_wire_rejects_missing_and_inconsistent_facts() {
    let (mut session, id) = fixture();
    ready(&mut session, id);
    let state = session.state.mission_state().unwrap();
    state.validate(session.state.tick).unwrap();
    let json = serde_json::to_value(&state).unwrap();
    let parsed: crate::protocol::MissionState = serde_json::from_value(json.clone()).unwrap();
    assert_eq!(state, parsed);
    for key in ["mast_hp", "mast_secured", "train_secured", "cars"] {
        let mut broken = json.clone();
        broken["m03"].as_object_mut().unwrap().remove(key);
        assert!(serde_json::from_value::<crate::protocol::MissionState>(broken).is_err());
    }
    for case in 0..6 {
        let mut broken = state.clone();
        let facts = broken.m03.as_mut().unwrap();
        match case {
            0 => facts.mast_hp = -1,
            1 => facts.mast_hp = 39,
            2 => facts.cars.clear(),
            3 => facts.cars[0].captives[0][1] = -1.,
            4 => facts.current = None,
            _ => facts.current.as_mut().unwrap().id = "wrong".into(),
        };
        assert!(broken.validate(session.state.tick).is_err());
    }
}

#[test]
fn m03_shared_controller_accepts_moving_captives_and_rejects_off_segment_or_rewind() {
    let (mut session, id) = fixture();
    ready(&mut session, id);
    let map = session.state.map.clone();
    let geometry = map.m03_geometry().unwrap();
    let mut controller = crate::mission::MissionClient::default();
    controller
        .replace_map_with_m03(
            Some(&geometry),
            map.half_extent(),
            &map.arena().solids,
            map.presentation_ref(),
        )
        .unwrap();
    let mut state = session.state.mission_state().unwrap();
    controller
        .observe(session.state.tick, state.clone())
        .unwrap();
    state.m03.as_mut().unwrap().cars[0].released = true;
    state.m03.as_mut().unwrap().cars[0].captives[0] = [-6.5, 0., 0.];
    controller
        .observe(session.state.tick, state.clone())
        .unwrap();
    let mut invalid = state.clone();
    invalid.m03.as_mut().unwrap().cars[0].captives[0][2] = 0.06;
    assert!(controller.observe(session.state.tick, invalid).is_err());
    let mut invalid = state.clone();
    invalid.m03.as_mut().unwrap().cars[0].released = false;
    invalid.m03.as_mut().unwrap().cars[0].captives = geometry.cars[0].held;
    assert!(controller.observe(session.state.tick, invalid).is_err());
    let mut changed = geometry.clone();
    changed.cars[0].safe[0][0] -= 1.;
    assert!(controller
        .replace_map_with_m03(
            Some(&changed),
            map.half_extent(),
            &map.arena().solids,
            map.presentation_ref()
        )
        .is_err());
}
