//! Owning authority fixtures, not an ordinary combat playthrough.
use super::*;
use crate::maps::{AuthoredMap, AuthoredSource};
use crate::protocol::{Action, CampaignDifficulty, LookAt, MissionReady, Role};
use crate::session::GameSession;
use std::sync::{Arc, OnceLock};

fn map() -> Arc<AuthoredMap> {
    static MAP: OnceLock<Arc<AuthoredMap>> = OnceLock::new();
    MAP.get_or_init(|| {
        AuthoredSource::Mission(MissionId::RightOfSearch)
            .load()
            .unwrap()
    })
    .clone()
}

fn fixture(difficulty: CampaignDifficulty) -> (GameSession, Uuid) {
    let mut s = GameSession::with_authored_map(map());
    s.state.seed(42);
    s.state.set_campaign_difficulty(difficulty).unwrap();
    let id = Uuid::from_u128(1111);
    s.state.add_player(id, "Tender visitor".into(), Role::Human);
    (s, id)
}

fn tick(s: &mut GameSession, count: usize) {
    for _ in 0..count {
        s.tick_messages(0.05);
        s.state
            .mission_state()
            .unwrap()
            .validate(s.state.tick)
            .unwrap();
    }
}

fn ready(s: &mut GameSession, id: Uuid) {
    assert!(s.state.acknowledge_mission(
        id,
        MissionReady {
            id: MissionId::RightOfSearch,
            attempt: 1,
        }
    ));
}

#[test]
fn m11_controller_binds_current_geometry_and_waits_after_map_replacement() {
    let (mut s, id) = fixture(CampaignDifficulty::Standard);
    ready(&mut s, id);
    let map = s.state.map.clone();
    let g = map.m11_geometry().unwrap();
    let mut controller = crate::mission::MissionClient::default();
    controller
        .replace_map_with_m11(
            Some(&g),
            map.half_extent(),
            &map.arena().solids,
            map.presentation_ref(),
        )
        .unwrap();
    let intent = Action {
        forward: true,
        fire: true,
        place_remote_mine: true,
        ..Action::default()
    };
    let mut navigator = crate::navigation::Navigator::default();
    let waiting = controller.steer(
        &mut navigator,
        map.navigation(),
        id,
        &s.state.snapshot(),
        intent.clone(),
    );
    assert!(!waiting.forward && !waiting.fire && !waiting.place_remote_mine);
    let initial = s.state.mission_state().unwrap();
    controller.observe(s.state.tick, initial.clone()).unwrap();
    let mut forged = initial.clone();
    if let MissionObjectiveAction::Arrival { feet, .. } = &mut forged
        .m11
        .as_mut()
        .unwrap()
        .current
        .as_mut()
        .unwrap()
        .action
    {
        feet[0] += 0.2;
    }
    assert!(controller.observe(s.state.tick, forged).is_err());
    controller
        .replace_map_with_id(
            1011,
            None,
            false,
            None,
            map.half_extent(),
            &map.arena().solids,
            map.presentation_ref(),
        )
        .unwrap();
    controller
        .replace_map_with_m11(
            Some(&g),
            map.half_extent(),
            &map.arena().solids,
            map.presentation_ref(),
        )
        .unwrap();
    let waiting = controller.steer(
        &mut navigator,
        map.navigation(),
        id,
        &s.state.snapshot(),
        intent,
    );
    assert!(!waiting.forward && !waiting.fire && !waiting.place_remote_mine);
    controller.observe(s.state.tick, initial).unwrap();
    let mut changed = g;
    changed.companion_start[0] += 0.2;
    assert!(controller
        .replace_map_with_m11(
            Some(&changed),
            map.half_extent(),
            &map.arena().solids,
            map.presentation_ref()
        )
        .is_err());
}

fn place(s: &mut GameSession, id: Uuid, feet: [f32; 3]) {
    let actor = s.state.players.iter_mut().find(|p| p.id == id).unwrap();
    [actor.x, actor.y, actor.z] = [feet[0], feet[1] + PLAYER_FLOOR_Y, feet[2]];
    actor.vy = 0.0;
    let held = actor.pending_action.interact;
    actor.clear_input();
    actor.pending_action.interact = held;
}

fn arrival(s: &mut GameSession, id: Uuid, index: usize) {
    let g = s.state.map.m11_geometry().unwrap();
    let MissionObjectiveAction::Arrival { feet, .. } = g.objectives[index].action else {
        panic!("arrival")
    };
    place(s, id, feet);
    tick(s, 1);
}

fn clear_group(s: &mut GameSession, group: usize) {
    // Terminal HP/encounter fixtures isolate the mission boundary, without
    // pretending that this is a finite-loadout combat witness.
    for placement in s.state.map.encounters()[group].enemies.clone() {
        let p = s
            .state
            .players
            .iter_mut()
            .find(|p| p.name == placement.id)
            .unwrap();
        p.hp = 0;
        s.state
            .encounters
            .hit(p.id, [p.x, p.y - PLAYER_FLOOR_Y, p.z], s.state.tick, true);
    }
    tick(s, 2);
    assert!(s.state.encounters.is_complete(group));
}

fn through_records(s: &mut GameSession, id: Uuid) {
    ready(s, id);
    arrival(s, id, 0);
    clear_group(s, 0);
    arrival(s, id, 1);
    arrival(s, id, 2);
    clear_group(s, 1);
    tick(s, 1);
    arrival(s, id, 3);
    clear_group(s, 2);
    tick(s, 1);
    assert_eq!(
        s.state
            .mission_state()
            .unwrap()
            .m11
            .unwrap()
            .completed
            .len(),
        4
    );
}

fn use_target(s: &mut GameSession, id: Uuid, target: &UseTarget, down: bool) {
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

#[test]
fn m11_live_readiness_safe_entry_and_three_neutrals_are_authoritative() {
    let (mut s, id) = fixture(CampaignDifficulty::Standard);
    tick(&mut s, 40);
    assert_eq!(
        s.state.mission_state().unwrap().phase,
        MissionPhase::Briefing
    );
    let mut bodies = Vec::new();
    s.state.append_civilian_contacts(&mut bodies);
    assert!(bodies.is_empty());
    ready(&mut s, id);
    tick(&mut s, 40);
    assert!(!s.state.encounters.is_awake(0));
    assert_eq!(s.state.players.iter().find(|p| p.id == id).unwrap().hp, 100);
    s.state.append_civilian_contacts(&mut bodies);
    assert_eq!(bodies.len(), 3);
    for (index, body) in bodies.iter().enumerate() {
        assert_eq!(body.key, format!("m11/transfer/{index}"));
        assert_eq!(
            [body.from.x, body.from.y, body.from.z],
            s.state.map.m11_geometry().unwrap().transfer_people[index]
        );
        assert_eq!(body.from, body.proposed);
        assert_eq!(body.radius, crate::movement::RADIUS);
        assert_eq!(body.height, crate::movement::BODY_HEIGHT);
    }
    assert_eq!(
        s.state
            .players
            .iter()
            .filter(|p| p.is_campaign_companion())
            .count(),
        1
    );
    let facts = s.state.mission_state().unwrap().m11.unwrap();
    assert_eq!(facts.challenges, M11ChallengeState::default());
    assert!(s.state.map.requires_m11_contract());
}

#[test]
fn m11_live_physical_choices_signal_miss_and_fresh_party_exit_remain_distinct() {
    let (mut s, id) = fixture(CampaignDifficulty::Severe);
    through_records(&mut s, id);
    let g = s.state.map.m11_geometry().unwrap();
    use_target(&mut s, id, &g.transfer_release, true);
    use_target(&mut s, id, &g.records_document, false);
    use_target(&mut s, id, &g.records_document, true);
    let facts = s.state.mission_state().unwrap().m11.unwrap();
    assert!(facts.challenges.transfer_released && facts.challenges.records_read);
    let start = facts.challenges.counter_boarding_started.unwrap();
    assert_eq!(facts.challenges.signal_due, Some(start + 1200));
    assert!(!facts.challenges.brief_completed(CampaignDifficulty::Severe));
    clear_group(&mut s, 3);
    arrival(&mut s, id, 4);
    // Controlled late clock fixture proves missing the brief is not a hidden
    // fail, reset or departure lock. No ticks are rewound.
    s.state.tick = start + 1200;
    arrival(&mut s, id, 5);
    let facts = s.state.mission_state().unwrap().m11.unwrap();
    assert_eq!(facts.completed.len(), 6);
    assert!(facts.challenges.bridge_taken_at.unwrap() >= facts.challenges.signal_due.unwrap());
    assert!(!facts.challenges.brief_completed(CampaignDifficulty::Severe));
    use_target(&mut s, id, &g.departure, false);
    assert_eq!(
        s.state.mission_state().unwrap().phase,
        MissionPhase::InProgress
    );
    use_target(&mut s, id, &g.departure, true);
    assert_eq!(
        s.state.mission_state().unwrap().phase,
        MissionPhase::Departed
    );
    assert_eq!(
        s.state
            .mission_state()
            .unwrap()
            .m11
            .unwrap()
            .completed
            .len(),
        7
    );
    let mut bodies = Vec::new();
    s.state.append_civilian_contacts(&mut bodies);
    assert!(bodies.is_empty());
}

#[test]
fn m11_live_one_resolved_charge_counts_registered_deaths_not_separate_blasts_or_overkill() {
    let (mut s, id) = fixture(CampaignDifficulty::Standard);
    through_records(&mut s, id);
    place(&mut s, id, [-4.0, 0.3, -24.3]);
    s.state.test_remote_blast(
        id,
        1,
        [0.0, 0.42, 13.2],
        crate::sim::remote_mine::BLAST_RADIUS,
        crate::sim::remote_mine::BLAST_DAMAGE,
    );
    let snapshot = s.state.snapshot();
    let result = snapshot.explosions.last().unwrap();
    let named: HashSet<_> = result
        .hits
        .iter()
        .filter(|h| h.killed)
        .filter(|h| s.state.encounters.registered_in_group(h.target_id, 3))
        .map(|h| h.target_id)
        .collect();
    assert_eq!(named.len(), 3);
    assert_eq!(
        s.state
            .mission_state()
            .unwrap()
            .m11
            .unwrap()
            .challenges
            .counter_boarder_blast_kills,
        3
    );
    s.state.test_remote_blast(
        id,
        2,
        [0.0, 0.42, 13.2],
        crate::sim::remote_mine::BLAST_RADIUS,
        crate::sim::remote_mine::BLAST_DAMAGE,
    );
    assert!(
        !s.state
            .snapshot()
            .explosions
            .last()
            .unwrap()
            .hits
            .iter()
            .any(|h| h.killed && named.contains(&h.target_id)),
        "dead lives cannot create overkill credit"
    );
    assert_eq!(
        s.state
            .mission_state()
            .unwrap()
            .m11
            .unwrap()
            .challenges
            .counter_boarder_blast_kills,
        3
    );

    let (mut s, id) = fixture(CampaignDifficulty::Standard);
    through_records(&mut s, id);
    place(&mut s, id, [-4.0, 0.3, -24.3]);
    // Narrow resolver fixtures discriminate attribution of separate blast
    // identities. They do not claim ordinary charge balance or placement.
    for (serial, z) in [(1, 11.8), (2, 13.2), (3, 14.6)] {
        s.state
            .test_remote_blast(id, serial, [0.0, 0.42, z], 0.6, 120.0);
        assert_eq!(
            s.state
                .snapshot()
                .explosions
                .last()
                .unwrap()
                .hits
                .iter()
                .filter(|h| h.killed)
                .count(),
            1
        );
    }
    assert_eq!(
        s.state
            .mission_state()
            .unwrap()
            .m11
            .unwrap()
            .challenges
            .counter_boarder_blast_kills,
        1,
        "three separate charge outcomes cannot be summed into one blast"
    );
    let before = s.state.mission_state().unwrap().m11.unwrap().challenges;
    s.state.test_blast(id, [0.0, 0.42, 16.0], 4.0, 1000.0);
    assert_eq!(
        s.state.mission_state().unwrap().m11.unwrap().challenges,
        before,
        "ordinary grenade deaths do not credit the remote lesson"
    );
    s.state.reset_mission();
    let reset = s.state.mission_state().unwrap();
    assert_eq!(reset.attempt, 2);
    assert_eq!(reset.m11.unwrap().challenges, M11ChallengeState::default());
}

#[test]
fn m11_live_departure_requires_every_ready_living_aboard_member_and_a_fresh_use() {
    let (mut s, id) = fixture(CampaignDifficulty::Standard);
    through_records(&mut s, id);
    clear_group(&mut s, 3);
    arrival(&mut s, id, 4);
    arrival(&mut s, id, 5);
    let other = Uuid::from_u128(1112);
    s.state
        .add_player(other, "Late tender visitor".into(), Role::Human);
    let target = s.state.map.m11_geometry().unwrap().departure;
    use_target(&mut s, id, &target, true);
    assert_eq!(
        s.state.mission_state().unwrap().phase,
        MissionPhase::InProgress
    );
    ready(&mut s, other);
    use_target(&mut s, id, &target, false);
    use_target(&mut s, id, &target, true);
    assert_eq!(
        s.state.mission_state().unwrap().phase,
        MissionPhase::InProgress,
        "ready outside the stern still refuses departure"
    );
    place(&mut s, other, [16.0, 1.5, 28.3]);
    use_target(&mut s, id, &target, true);
    assert_eq!(
        s.state.mission_state().unwrap().phase,
        MissionPhase::InProgress,
        "held refused use must not become a fresh request after the other member boards"
    );
    use_target(&mut s, id, &target, false);
    use_target(&mut s, id, &target, true);
    assert_eq!(
        s.state.mission_state().unwrap().phase,
        MissionPhase::Departed
    );
    assert_eq!(s.state.mission_state().unwrap().party.len(), 2);
}

#[test]
fn m11_live_wire_refuses_null_missing_and_cross_mission_facts() {
    let (mut s, id) = fixture(CampaignDifficulty::Standard);
    let state = s.state.mission_state().unwrap();
    let original = serde_json::to_value(&state).unwrap();
    let mut bad = original.clone();
    bad["m11"] = serde_json::Value::Null;
    assert!(serde_json::from_value::<MissionState>(bad).is_err());
    let mut bad = original.clone();
    bad.as_object_mut().unwrap().remove("m11");
    assert!(serde_json::from_value::<MissionState>(bad)
        .unwrap()
        .validate(0)
        .is_err());
    let mut bad = original;
    bad["id"] = "common_carrier".into();
    assert!(serde_json::from_value::<MissionState>(bad)
        .unwrap()
        .validate(0)
        .is_err());
    ready(&mut s, id);
    tick(&mut s, 1);
    let state = s.state.mission_state().unwrap();
    assert_eq!(
        serde_json::from_value::<MissionState>(serde_json::to_value(&state).unwrap()).unwrap(),
        state
    );
    let info = s.state.map_info();
    let wire = serde_json::to_value(info).unwrap();
    assert!(wire.get("m11").is_some());
    let mut bad = wire;
    bad["m11"] = serde_json::Value::Null;
    assert!(serde_json::from_value::<ServerMessage>(bad).is_err());
}
#[tokio::test]
async fn m11_real_admission_refuses_all_old_roles_and_delivers_map_before_facts() {
    use futures_util::{SinkExt, StreamExt};
    use std::time::Duration;
    use tokio_tungstenite::{connect_async, tungstenite::Message};
    let (ready_tx, ready_rx) = tokio::sync::oneshot::channel();
    let (stop_tx, stop_rx) = tokio::sync::oneshot::channel();
    let server = tokio::spawn(crate::run::run_server(
        crate::run::ServerOptions {
            bind: "127.0.0.1:0".into(),
            bots: 0,
            authored: Some(AuthoredSource::Mission(MissionId::RightOfSearch)),
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
        crate::protocol::RELOAD_GAMEPLAY_VERSION,
        crate::protocol::M11_GAMEPLAY_VERSION,
        crate::protocol::ASSESSOR_GAMEPLAY_VERSION,
        crate::protocol::GAMEPLAY_VERSION,
    ] {
        for role in ["human", "agent", "spectator"] {
            let (mut socket, _) = connect_async(format!("ws://{address}")).await.unwrap();
            socket.send(Message::Text(serde_json::json!({"type":"hello","role":role,"name":"Tender reader","gameplay_version":version,"geometry_version":crate::protocol::GEOMETRY_VERSION}).to_string())).await.unwrap();
            tokio::time::timeout(Duration::from_secs(5), async {
                let mut welcomed = false;
                let mut mapped = false;
                loop {
                    let Message::Text(text) = socket.next().await.unwrap().unwrap() else {
                        continue;
                    };
                    let value: serde_json::Value = serde_json::from_str(&text).unwrap();
                    if version < crate::protocol::ASSESSOR_GAMEPLAY_VERSION {
                        assert_eq!(value["type"], "error");
                        assert_eq!(value["code"], "unsupported_gameplay");
                        assert!(value["message"].as_str().unwrap().contains(&format!(
                            "version {}",
                            crate::protocol::ASSESSOR_GAMEPLAY_VERSION
                        )));
                        break;
                    }
                    match value["type"].as_str().unwrap() {
                        "welcome" => welcomed = true,
                        "map_info" => {
                            assert!(welcomed);
                            assert!(value["m11"].is_object());
                            mapped = true;
                        }
                        "mission" => {
                            assert!(welcomed && mapped);
                            assert_eq!(value["state"]["id"], "right_of_search");
                            break;
                        }
                        "error" => panic!("supported reader refused: {value}"),
                        _ => {}
                    }
                }
            })
            .await
            .expect("bounded all-role M11 admission");
            let _ = socket.close(None).await;
        }
    }
    stop_tx.send(()).unwrap();
    server.await.unwrap().unwrap();
}
