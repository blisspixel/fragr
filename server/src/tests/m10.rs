//! Authored authority fixtures, not an ordinary combat playthrough.
use crate::maps::{AuthoredMap, AuthoredSource};
use crate::protocol::{
    Action, CampaignDifficulty, LookAt, MissionId, MissionObjectiveAction, MissionPhase,
    MissionReady, Role,
};
use crate::session::GameSession;
use crate::sim::PLAYER_FLOOR_Y;
use std::sync::{Arc, OnceLock};
use uuid::Uuid;

fn map() -> Arc<AuthoredMap> {
    static MAP: OnceLock<Arc<AuthoredMap>> = OnceLock::new();
    MAP.get_or_init(|| {
        AuthoredSource::Mission(MissionId::CommonCarrier)
            .load()
            .unwrap()
    })
    .clone()
}
fn fixture(difficulty: CampaignDifficulty) -> (GameSession, Uuid) {
    let mut s = GameSession::with_authored_map(map());
    s.state.seed(42);
    s.state.set_campaign_difficulty(difficulty).unwrap();
    let id = Uuid::from_u128(1010);
    s.state.add_player(id, "Ship visitor".into(), Role::Human);
    (s, id)
}
fn ready(s: &mut GameSession, id: Uuid) {
    assert!(s.state.acknowledge_mission(
        id,
        MissionReady {
            id: MissionId::CommonCarrier,
            attempt: 1
        }
    ));
}
fn place(s: &mut GameSession, id: Uuid, feet: [f32; 3]) {
    let p = s.state.players.iter_mut().find(|p| p.id == id).unwrap();
    [p.x, p.y, p.z] = [feet[0], feet[1] + PLAYER_FLOOR_Y, feet[2]];
    p.vy = 0.0;
    let held_use = p.pending_action.interact;
    p.clear_input();
    p.pending_action.interact = held_use;
}
fn tick(s: &mut GameSession, n: usize) {
    for _ in 0..n {
        s.tick_messages(0.05);
    }
}
fn use_control(s: &mut GameSession, id: Uuid, down: bool) {
    let target = s.state.map.m10_geometry().unwrap().departure;
    place(s, id, target.approach);
    let point = target
        .point(
            s.state.map.presentation_ref().unwrap(),
            &s.state.map.arena().solids,
        )
        .unwrap();
    s.state.set_action(
        id,
        Action {
            interact: down,
            look_at: Some(LookAt {
                x: Some(point[0]),
                y: Some(point[1]),
                z: Some(point[2]),
                player_id: None,
            }),
            ..Action::default()
        },
    );
    tick(s, 1);
}
fn clear_boundary(s: &mut GameSession, id: Uuid, index: usize) {
    let g = s.state.map.m10_geometry().unwrap();
    let MissionObjectiveAction::Arrival { feet, .. } = g.objectives[index].action else {
        panic!("arrival")
    };
    place(s, id, feet);
    tick(s, 1);
    let group = s.state.map.encounters()[index].enemies.clone();
    for enemy in group {
        let p = s
            .state
            .players
            .iter_mut()
            .find(|p| p.name == enemy.id)
            .expect("actual current group");
        p.hp = 0;
        s.state
            .encounters
            .hit(p.id, [p.x, p.y - PLAYER_FLOOR_Y, p.z], s.state.tick, true);
    }
    tick(s, 2);
    assert!(s.state.encounters.is_complete(index));
}

#[test]
fn m10_safe_entry_readiness_does_not_start_fights_or_clone_crew() {
    let (mut s, id) = fixture(CampaignDifficulty::Standard);
    tick(&mut s, 40);
    assert_eq!(
        s.state.mission_state().unwrap().phase,
        MissionPhase::Briefing
    );
    assert!(
        !s.state
            .players
            .iter()
            .any(|p| s.state.encounters.is_active_enemy(p.id)),
        "dormant roster remains unavailable until a deliberate crossing"
    );
    ready(&mut s, id);
    tick(&mut s, 40);
    assert!(
        !s.state
            .players
            .iter()
            .any(|p| s.state.encounters.is_active_enemy(p.id)),
        "dormant roster remains unavailable until a deliberate crossing"
    );
    let p = s.state.players.iter().find(|p| p.id == id).unwrap();
    assert_eq!(p.hp, 100);
    assert_eq!(
        s.state
            .players
            .iter()
            .filter(|p| p.is_campaign_companion())
            .count(),
        1
    );
    let f = s.state.mission_state().unwrap().m10.unwrap();
    assert!(f.passengers.is_empty());
    assert!(matches!(
        f.transit,
        crate::protocol::M10Transit::HistoricalUnrecorded {}
    ));
    assert_eq!(f.pilot, s.state.map.m10_geometry().unwrap().pilot);
    place(&mut s, id, [0.0, 2.0, -12.0]);
    tick(&mut s, 1);
    assert_eq!(
        s.state
            .players
            .iter()
            .filter(|p| s.state.encounters.is_active_enemy(p.id))
            .count(),
        4
    );
    assert!(s
        .state
        .mission_state()
        .unwrap()
        .m10
        .unwrap()
        .completed
        .is_empty());
}

#[test]
fn m10_places_only_the_current_ordered_group_before_its_actual_activation() {
    let (mut s, id) = fixture(CampaignDifficulty::Standard);
    ready(&mut s, id);
    tick(&mut s, 40);
    for (index, expected_total) in [4, 9, 13, 17].into_iter().enumerate() {
        let definitions = s.state.map.encounters();
        let expected: Vec<_> = definitions[..=index]
            .iter()
            .flat_map(|g| g.enemies.iter().map(|e| e.id.clone()))
            .collect();
        let actual: Vec<_> = s
            .state
            .players
            .iter()
            .filter(|p| p.is_campaign_enemy())
            .map(|p| p.name.clone())
            .collect();
        assert_eq!(actual.len(), expected_total);
        assert!(expected.iter().all(|name| actual.contains(name)));
        assert!(
            definitions[index + 1..]
                .iter()
                .flat_map(|g| &g.enemies)
                .all(|e| !actual.contains(&e.id)),
            "future guards cannot block or be shot awake"
        );
        let current: Vec<_> = s
            .state
            .players
            .iter()
            .filter(|p| definitions[index].enemies.iter().any(|e| e.id == p.name))
            .collect();
        assert_eq!(current.len(), [4, 5, 4, 4][index]);
        assert!(current
            .iter()
            .all(|p| p.hp > 0 && s.state.contact_eligible(p)));
        assert!(
            current
                .iter()
                .all(|p| !s.state.encounters.is_active_enemy(p.id)),
            "placement is not activation; deliberate entry still owns the next fight"
        );
        // Explicit authority fixture, not a combat playthrough. The existing
        // helper crosses the real trigger and resolves this group's deaths.
        clear_boundary(&mut s, id, index);
    }
    assert_eq!(
        s.state
            .mission_state()
            .unwrap()
            .m10
            .unwrap()
            .completed
            .len(),
        4
    );
}

#[test]
fn m10_departure_requires_each_group_all_ready_living_aboard_and_a_fresh_use() {
    for difficulty in [CampaignDifficulty::Standard, CampaignDifficulty::Severe] {
        let (mut s, id) = fixture(difficulty);
        ready(&mut s, id);
        use_control(&mut s, id, true);
        assert!(s.state.mission_state().unwrap().prompts.is_empty());
        for i in 0..4 {
            clear_boundary(&mut s, id, i);
        }
        assert_eq!(
            s.state
                .mission_state()
                .unwrap()
                .m10
                .unwrap()
                .completed
                .len(),
            4
        );
        let peer = Uuid::from_u128(1011);
        s.state.add_player(peer, "Peer".into(), Role::Agent);
        use_control(&mut s, id, false);
        assert!(s.state.mission_state().unwrap().prompts.is_empty());
        ready(&mut s, peer);
        place(&mut s, peer, [0.0, 2.0, 14.0]);
        tick(&mut s, 1);
        assert!(s.state.mission_state().unwrap().prompts.is_empty());
        use_control(&mut s, id, true);
        assert!(s.state.mission_state().unwrap().prompts.is_empty());
        place(&mut s, peer, [0.7, 4.8, -16.0]);
        tick(&mut s, 1);
        let prompts = s.state.mission_state().unwrap().prompts;
        assert_eq!(
            prompts.len(),
            1,
            "only the aimed physical control gives a prompt"
        );
        assert_eq!(prompts[0].player_id, id);
        use_control(&mut s, id, true);
        assert_eq!(
            s.state.mission_state().unwrap().phase,
            MissionPhase::InProgress,
            "holding Use through party arrival cannot confirm"
        );
        s.state
            .players
            .iter_mut()
            .find(|p| p.id == peer)
            .unwrap()
            .hp = 0;
        tick(&mut s, 1);
        assert!(
            s.state.mission_state().unwrap().prompts.is_empty(),
            "dead peer blocks departure"
        );
        s.state
            .players
            .iter_mut()
            .find(|p| p.id == peer)
            .unwrap()
            .hp = 100;
        use_control(&mut s, id, false);
        use_control(&mut s, id, true);
        let f = s.state.mission_state().unwrap();
        assert_eq!(f.phase, MissionPhase::Departed);
        assert_eq!(
            f.m10.as_ref().unwrap().completed.last().unwrap(),
            "party_departed"
        );
        f.validate(s.state.tick).unwrap();
    }
}

#[test]
fn m10_controller_requires_fresh_map_bound_facts_and_keeps_carried_history() {
    let (mut s, id) = fixture(CampaignDifficulty::Standard);
    ready(&mut s, id);
    let map = s.state.map.clone();
    let g = map.m10_geometry().unwrap();
    let mut client = crate::mission::MissionClient::default();
    client
        .replace_map_with_m10(
            Some(&g),
            map.half_extent(),
            &map.arena().solids,
            map.presentation_ref(),
        )
        .unwrap();
    let mut nav = crate::navigation::Navigator::default();
    let intent = Action {
        forward: true,
        fire: true,
        throw_grenade: true,
        ..Action::default()
    };
    let a = client.steer(
        &mut nav,
        map.navigation(),
        id,
        &s.state.snapshot(),
        intent.clone(),
    );
    assert!(!a.forward && !a.fire && !a.throw_grenade);
    let initial = s.state.mission_state().unwrap();
    client.observe(s.state.tick, initial.clone()).unwrap();
    for mutation in 0..3 {
        let mut bad = initial.clone();
        let f = bad.m10.as_mut().unwrap();
        match mutation {
            0 => f.pilot[0] += 0.5,
            1 => f.current = Some(g.objectives[1].clone()),
            _ => f.carried_archive = Some(crate::protocol::M08Outcome::HistoricalUnrecorded {}),
        }
        assert!(client.observe(s.state.tick, bad).is_err());
    }
    client
        .replace_map_with_id(
            1010,
            None,
            false,
            None,
            map.half_extent(),
            &map.arena().solids,
            map.presentation_ref(),
        )
        .unwrap();
    client
        .replace_map_with_m10(
            Some(&g),
            map.half_extent(),
            &map.arena().solids,
            map.presentation_ref(),
        )
        .unwrap();
    let a = client.steer(&mut nav, map.navigation(), id, &s.state.snapshot(), intent);
    assert!(!a.forward && !a.fire && !a.throw_grenade);
    client.observe(s.state.tick, initial).unwrap();
    let mut changed = g;
    changed.pilot[0] += 0.5;
    assert!(client
        .replace_map_with_m10(
            Some(&changed),
            map.half_extent(),
            &map.arena().solids,
            map.presentation_ref()
        )
        .is_err());
}

#[tokio::test]
async fn m10_real_admission_refuses_all_old_roles_and_delivers_map_before_facts() {
    use futures_util::{SinkExt, StreamExt};
    use std::time::Duration;
    use tokio_tungstenite::{connect_async, tungstenite::Message};
    let (ready_tx, ready_rx) = tokio::sync::oneshot::channel();
    let (stop_tx, stop_rx) = tokio::sync::oneshot::channel();
    let server = tokio::spawn(crate::run::run_server(
        crate::run::ServerOptions {
            bind: "127.0.0.1:0".into(),
            bots: 0,
            authored: Some(AuthoredSource::Mission(MissionId::CommonCarrier)),
            ..Default::default()
        },
        async {
            let _ = stop_rx.await;
        },
        Some(ready_tx),
    ));
    let address = tokio::time::timeout(Duration::from_secs(30), ready_rx)
        .await
        .unwrap()
        .unwrap();
    for version in [
        crate::protocol::REPEATER_GAMEPLAY_VERSION,
        crate::protocol::M10_GAMEPLAY_VERSION,
    ] {
        for role in ["human", "agent", "spectator"] {
            let (mut socket, _) = connect_async(format!("ws://{address}")).await.unwrap();
            socket.send(Message::Text(serde_json::json!({"type":"hello","role":role,"name":"Ship reader","gameplay_version":version,"geometry_version":crate::protocol::GEOMETRY_VERSION}).to_string())).await.unwrap();
            tokio::time::timeout(Duration::from_secs(5), async {
                let mut welcomed = false;
                let mut mapped = false;
                loop {
                    let Message::Text(text) = socket.next().await.unwrap().unwrap() else {
                        continue;
                    };
                    let value: serde_json::Value = serde_json::from_str(&text).unwrap();
                    if version < crate::protocol::M10_GAMEPLAY_VERSION {
                        assert_eq!(value["type"], "error");
                        assert_eq!(value["code"], "unsupported_gameplay");
                        assert!(value["message"].as_str().unwrap().contains("36"));
                        break;
                    }
                    match value["type"].as_str().unwrap() {
                        "welcome" => welcomed = true,
                        "map_info" => {
                            assert!(welcomed);
                            assert!(value["m10"].is_object());
                            mapped = true;
                        }
                        "mission" => {
                            assert!(welcomed && mapped);
                            assert_eq!(value["state"]["id"], "common_carrier");
                            break;
                        }
                        "error" => panic!("supported reader refused: {value}"),
                        _ => {}
                    }
                }
            })
            .await
            .expect("bounded all-role M10 admission");
            let _ = socket.close(None).await;
        }
    }
    stop_tx.send(()).unwrap();
    server.await.unwrap().unwrap();
}

#[tokio::test]
async fn m10_registered_panels_require_current_readers_even_without_mission_facts() {
    use futures_util::{SinkExt, StreamExt};
    use std::time::Duration;
    use tokio_tungstenite::{connect_async, tungstenite::Message};
    for kind in [
        "m10_ship_confirmation",
        "m10_cargo_deck",
        "m10_passenger_deck",
        "m10_command_deck",
    ] {
        let path = std::env::temp_dir().join(format!("fragr-ship-panel-{}.json", Uuid::new_v4()));
        let source = serde_json::json!({"version":1,"map_id":1042,"name":"Registered panel boundary","half_extent":16,"ground":"concrete","equipment":"discovery",
            "solids":[{"id":"panel_host","min":[-2,0,-5],"max":[2,3,-4],"surface":"enamel"}],
            "decorations":[{"solid":"panel_host","face":"south","kind":kind,"center":[0,0],"size":[1,1]}],
            "spawns":[{"id":"entry","feet":[0,0,0],"yaw":0}], "landmarks":[{"id":"inspection","feet":[0,0,1]}]});
        let bytes = serde_json::to_vec(&source).unwrap();
        AuthoredMap::read(bytes.as_slice()).unwrap();
        std::fs::write(&path, bytes).unwrap();
        let (ready_tx, ready_rx) = tokio::sync::oneshot::channel();
        let (stop_tx, stop_rx) = tokio::sync::oneshot::channel();
        let server = tokio::spawn(crate::run::run_server(
            crate::run::ServerOptions {
                bind: "127.0.0.1:0".into(),
                bots: 0,
                authored: Some(AuthoredSource::File(path.clone())),
                ..Default::default()
            },
            async {
                let _ = stop_rx.await;
            },
            Some(ready_tx),
        ));
        let address = tokio::time::timeout(Duration::from_secs(30), ready_rx)
            .await
            .unwrap()
            .unwrap();
        for version in [35, 36] {
            for role in ["human", "agent", "spectator"] {
                let (mut socket, _) = connect_async(format!("ws://{address}")).await.unwrap();
                socket.send(Message::Text(serde_json::json!({"type":"hello","role":role,"name":"Panel reader","gameplay_version":version,"geometry_version":2}).to_string())).await.unwrap();
                tokio::time::timeout(Duration::from_secs(5), async {
                    let mut welcomed = false;
                    loop {
                        let Message::Text(text) = socket.next().await.unwrap().unwrap() else {
                            continue;
                        };
                        let value: serde_json::Value = serde_json::from_str(&text).unwrap();
                        if version == 35 {
                            assert_eq!(
                                value["type"], "error",
                                "legacy reader must be refused before Welcome for {kind}/{role}"
                            );
                            assert_eq!(value["code"], "unsupported_gameplay");
                            break;
                        }
                        match value["type"].as_str().unwrap() {
                            "welcome" => welcomed = true,
                            "map_info" => {
                                assert!(welcomed);
                                assert_eq!(value["presentation"]["decorations"][0]["kind"], kind);
                                assert!(
                                    value.get("m10").is_none(),
                                    "a registered sign never invents mission authority"
                                );
                                break;
                            }
                            "error" => panic!("current panel reader refused: {value}"),
                            _ => {}
                        }
                    }
                })
                .await
                .expect("bounded registered panel delivery");
                let _ = socket.close(None).await;
            }
        }
        stop_tx.send(()).unwrap();
        server.await.unwrap().unwrap();
        std::fs::remove_file(path).unwrap();
    }
}
