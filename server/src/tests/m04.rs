use crate::maps::{AuthoredMap, AuthoredSource, RuntimeMap};
use crate::protocol::{
    Action, CampaignActor, CampaignDifficulty, EnemyKind, EnemyPhase, InteractionKind, LookAt,
    MissionId, MissionPhase, MissionReady, Role, WeaponType,
};
use crate::session::GameSession;
use serde_json::json;
use uuid::Uuid;

#[tokio::test]
async fn live_campaign_rules_refuse_old_readers_and_deliver_geometry_first() {
    use futures_util::{SinkExt, StreamExt};
    use std::time::Duration;
    use tokio_tungstenite::{connect_async, tungstenite::Message};
    for (mission, retired) in [
        (MissionId::RecallNotice, 8),
        (MissionId::PersonsUnknown, 18),
        (MissionId::ScheduledService, 24),
        (MissionId::NoticeToVacate, 24),
    ] {
        let (ready_tx, ready_rx) = tokio::sync::oneshot::channel();
        let (stop_tx, stop_rx) = tokio::sync::oneshot::channel();
        let server = tokio::spawn(crate::run::run_server(
            crate::run::ServerOptions {
                bind: "127.0.0.1:0".into(),
                bots: 0,
                authored: Some(AuthoredSource::Mission(mission)),
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
        for version in [
            retired,
            25,
            26,
            crate::protocol::ASSESSOR_GAMEPLAY_VERSION,
            crate::protocol::GAMEPLAY_VERSION,
        ] {
            for role in ["human", "agent", "spectator"] {
                let (mut socket, _) = connect_async(format!("ws://{address}")).await.unwrap();
                socket.send(Message::Text(json!({"type":"hello","role":role,"name":"NoticeProbe","gameplay_version":version,"geometry_version":crate::protocol::GEOMETRY_VERSION}).to_string())).await.unwrap();
                tokio::time::timeout(Duration::from_secs(5), async {
                    let (mut map, mut welcome, mut mission_seen, mut snapshot) =
                        (false, false, false, false);
                    loop {
                        let message = socket.next().await.unwrap().unwrap();
                        let Message::Text(text) = message else {
                            continue;
                        };
                        let value: serde_json::Value = serde_json::from_str(&text).unwrap();
                        if version < crate::protocol::ASSESSOR_GAMEPLAY_VERSION {
                            assert_eq!(value["type"], "error", "retired reader received state");
                            assert_eq!(value["code"], "unsupported_gameplay");
                            assert!(value["message"].as_str().unwrap().contains(&format!(
                                "version {}",
                                crate::protocol::ASSESSOR_GAMEPLAY_VERSION
                            )));
                            break;
                        }
                        match value["type"].as_str().unwrap() {
                            "map_info" => {
                                if mission == MissionId::NoticeToVacate {
                                    assert_eq!(value["map_id"], 1004);
                                    assert_eq!(value["m04"]["clinic_open"], false);
                                }
                                map = true;
                            }
                            "welcome" => {
                                welcome = true;
                            }
                            "mission" => {
                                assert!(map, "mission overtook geometry");
                                assert_eq!(
                                    value["state"]["id"],
                                    serde_json::to_value(mission).unwrap()
                                );
                                assert_eq!(
                                    value["state"]["rules"]["revision"],
                                    crate::protocol::CAMPAIGN_RULES_REVISION
                                );
                                mission_seen = true;
                            }
                            "snapshot" => {
                                assert!(map && welcome, "snapshot overtook admission");
                                snapshot = true;
                            }
                            "error" => panic!("current reader rejected: {value}"),
                            _ => {}
                        }
                        if mission_seen && snapshot {
                            break;
                        }
                    }
                })
                .await
                .expect("bounded current campaign admission");
                let _ = socket.close(None).await;
            }
        }
        stop_tx.send(()).unwrap();
        server.await.unwrap().unwrap();
    }
}

fn document() -> serde_json::Value {
    let ids = crate::protocol::M04_OBJECTIVE_IDS;
    let encounters:Vec<_>=ids.iter().enumerate().map(|(i,id)|{
        let enemy=if i==1 {json!({"id":"notary","kind":"notary","feet":[8,4,0],"yaw":std::f32::consts::PI,
            "hover":{"volume":{"min":[7,3.5,-2],"max":[9,5,2]},"band":[3.5,5],"patrol":[[8,4,-1],[8,4,1]],"approach":[0.0,0.0,0.0]}})}
            else {json!({"id":format!("guard_{i}"),"kind":"clerk","feet":[-12,0,-12],"yaw":0})};
        let mut group=json!({"id":format!("group_{i}"),"regions":[{"min":[-20,0,-20],"max":[20,2,20]}],"enemies":[enemy]});
        if i>0 {group["after"]=json!(format!("group_{}",i-1));} let _=id;group
    }).collect();
    let objectives:Vec<_>=ids.iter().enumerate().map(|(i,id)|json!({"id":id,"arrival":{"min":[-2,0,-2],"max":[2,2,2]},"approach":[0.0,0.0,0.0],"requires_encounter":format!("group_{i}")})).collect();
    json!({"version":1,"map_id":1004,"name":"Notice fixture","half_extent":20,"ground":"concrete","equipment":"discovery",
        "solids":[{"id":"shutter","min":[-5,0,-1],"max":[-4,2,1],"surface":"service_steel"},
            {"id":"clinic_switch","min":[3,0,3],"max":[4,2,4],"surface":"service_steel"},
            {"id":"roof_switch","min":[3,0,7],"max":[4,2,8],"surface":"service_steel"}],
        "spawns":[{"id":"entry","feet":[0.0,0.0,0.0],"yaw":0}],"landmarks":[{"id":"safe","feet":[-8,0,2]}],"encounters":encounters,
        "m04":{"clinic":{"panel":{"solid":"clinic_switch","face":"west","center":[0,0],"size":[0.8,0.8],"kind":"terminal"},"approach":[1.5,0,3.5],"gate":{"solid":"shutter","lift":3},"requires_encounter":"group_2","release":{"min":[-9,0,-2],"max":[-6,2,3]}},
            "patients":[{"id":"edda","held":[-8,0,0],"route":[[-8,0,0],[-8,0,2]]}],"objectives":objectives,
            "departure":{"panel":{"solid":"roof_switch","face":"west","center":[0,0],"size":[0.8,0.8],"kind":"lift_control"},"approach":[1.5,0,7.5],"boarding":{"min":[-1,0,5],"max":[5,2,10]},"requires_encounter":"group_5"},"companion_start":[-2,0,0]}})
}
fn fixture(difficulty: CampaignDifficulty) -> (GameSession, Uuid) {
    let map = AuthoredMap::read(serde_json::to_vec(&document()).unwrap().as_slice()).unwrap();
    let mut s = GameSession::with_authored_map(map);
    s.state.seed(42);
    s.state.set_campaign_difficulty(difficulty).unwrap();
    let id = Uuid::from_u128(4004);
    s.state.add_player(id, "Visitor".into(), Role::Human);
    assert!(s.state.acknowledge_mission(
        id,
        MissionReady {
            id: MissionId::NoticeToVacate,
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
fn body(s: &GameSession, id: Uuid) -> &crate::sim::Player {
    s.state.players.iter().find(|p| p.id == id).unwrap()
}
fn place(s: &mut GameSession, id: Uuid, feet: [f32; 3]) {
    let p = s.state.players.iter_mut().find(|p| p.id == id).unwrap();
    p.x = feet[0];
    p.y = feet[1] + crate::sim::PLAYER_FLOOR_Y;
    p.z = feet[2];
    p.clear_input();
}
fn clear(s: &mut GameSession, index: usize) {
    let name = s.state.map.encounters()[index].enemies[0].id.clone();
    let id = s.state.players.iter().find(|p| p.name == name).unwrap().id;
    let p = s.state.players.iter_mut().find(|p| p.id == id).unwrap();
    p.hp = 0;
    let feet = [p.x, p.y - crate::sim::PLAYER_FLOOR_Y, p.z];
    s.state.encounters.hit(id, feet, s.state.tick, true);
    advance(s, 1);
    assert!(s.state.encounters.is_complete(index));
}
fn notary(s: &mut GameSession) -> Uuid {
    clear(s, 0);
    let id = s
        .state
        .players
        .iter()
        .find(|p| crate::combat::is_notary(p.campaign))
        .unwrap()
        .id;
    for _ in 0..80 {
        advance(s, 1);
        if matches!(
            body(s, id).campaign,
            Some(CampaignActor::Union {
                phase: EnemyPhase::Windup,
                ..
            })
        ) {
            return id;
        }
    }
    panic!("Notary never flashes");
}
fn shoot(s: &mut GameSession, id: Uuid, target: Uuid, weapon: WeaponType) {
    let p = s.state.players.iter_mut().find(|p| p.id == id).unwrap();
    p.inventory.grant_weapon(weapon);
    p.weapon = weapon;
    p.fire_cooldown = 0;
    s.state.set_action(
        id,
        Action {
            fire: true,
            look_at: Some(LookAt {
                player_id: Some(target),
                ..Default::default()
            }),
            ..Default::default()
        },
    );
    s.state.tick(0.05);
    s.state.set_action(id, Action::default());
}
fn use_control(s: &mut GameSession, id: Uuid, target: &crate::protocol::UseTarget) {
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
    s.tick_messages(0.05);
    s.state.set_action(id, Action::default());
}

#[test]
fn bundled_notice_to_vacate_routes() {
    let map = AuthoredSource::Mission(MissionId::NoticeToVacate)
        .load()
        .unwrap();
    let runtime = RuntimeMap::Authored(map);
    assert_eq!(runtime.id(), 1004);
    let g = runtime.m04_geometry().unwrap();
    assert!(!g.clinic_open);
    assert_eq!(g.objectives.len(), 6);
    let opened = runtime.prepared_m04_world().unwrap();
    assert!(opened.m04_geometry().unwrap().clinic_open);
    assert_eq!(runtime.content_sha256(), opened.content_sha256());
    assert_eq!(runtime.arena().solids.len(), opened.arena().solids.len());
}

#[test]
fn notary_each_tier_locks_hover_and_counts_only_first_actual_round() {
    for difficulty in [
        CampaignDifficulty::Assisted,
        CampaignDifficulty::Standard,
        CampaignDifficulty::Severe,
    ] {
        let (mut s, id) = fixture(difficulty);
        let drone = notary(&mut s);
        assert_eq!(body(&s, drone).hp, 50);
        let origin = [body(&s, drone).x, body(&s, drone).y, body(&s, drone).z];
        let end = match body(&s, drone).campaign.unwrap() {
            CampaignActor::Union { phase_ends, .. } => phase_ends,
            _ => panic!(),
        };
        if let CampaignActor::Union {
            phase_started,
            kind,
            ..
        } = body(&s, drone).campaign.unwrap()
        {
            assert_eq!(kind, EnemyKind::Notary);
            assert_eq!(
                end - phase_started,
                crate::encounters::enemy::attack_timing(kind, difficulty).0
            );
        }
        while s.state.tick + 1 < end {
            advance(&mut s, 1);
            assert_eq!(body(&s, id).hp, 100);
            assert_eq!(s.state.m04_photos_completed(), 0);
            assert_eq!(
                [body(&s, drone).x, body(&s, drone).y, body(&s, drone).z],
                origin
            );
        }
        advance(&mut s, 1);
        assert!(body(&s, drone).just_fired);
        assert_eq!(s.state.m04_photos_completed(), 1);
        assert_eq!(body(&s, id).hp, 80);
        advance(&mut s, 10);
        assert_eq!(s.state.m04_photos_completed(), 1);
        assert_eq!(body(&s, id).hp, 40);
    }
}
#[test]
fn notary_strafe_cover_and_hit_spoil_the_photograph() {
    for variant in 0..3 {
        let (mut s, id) = fixture(CampaignDifficulty::Standard);
        let drone = notary(&mut s);
        let end = match body(&s, drone).campaign.unwrap() {
            CampaignActor::Union { phase_ends, .. } => phase_ends,
            _ => panic!(),
        };
        if variant == 0 {
            place(&mut s, id, [0.0, 0.0, 4.0]);
        } else if variant == 1 {
            place(&mut s, id, [2.0, 0.0, 3.8]);
        } else {
            shoot(&mut s, id, drone, WeaponType::Tack);
            assert_eq!(body(&s, drone).hp, 30);
        }
        while s.state.tick <= end + 1 {
            advance(&mut s, 1);
        }
        assert_eq!(s.state.m04_photos_completed(), 0, "variant {variant}");
        assert_eq!(body(&s, id).hp, 100);
    }
}
#[test]
fn notary_real_raised_box_kill_falls_to_support_without_damage() {
    let (mut s, id) = fixture(CampaignDifficulty::Standard);
    let drone = notary(&mut s);
    let [x, z] = [body(&s, drone).x, body(&s, drone).z];
    shoot(&mut s, id, drone, WeaponType::Rail);
    assert!(body(&s, drone).hp <= 0);
    assert!(body(&s, drone).y > crate::sim::PLAYER_FLOOR_Y + 3.0);
    let mut previous = body(&s, drone).y;
    let mut landed = false;
    for _ in 0..32 {
        advance(&mut s, 1);
        let Some(p) = s.state.players.iter().find(|p| p.id == drone) else {
            break;
        };
        assert!(p.y <= previous);
        previous = p.y;
        assert_eq!([p.x, p.z], [x, z]);
        if (p.y - crate::sim::PLAYER_FLOOR_Y).abs() < 0.001 {
            landed = true;
            break;
        }
    }
    assert!(landed);
    assert_eq!(body(&s, id).hp, 100);
    assert_eq!(s.state.m04_photos_completed(), 0);
    advance(&mut s, 22);
    assert!(s.state.players.iter().all(|p| p.id != drone));
}

#[test]
fn notary_shot_box_has_raised_underbody_and_wide_square_edges() {
    let identity = Some(CampaignActor::Union {
        kind: EnemyKind::Notary,
        phase: EnemyPhase::Idle,
        phase_started: 0,
        phase_ends: 0,
        seated: false,
    });
    let feet = [8.0, 4.0, 0.0];
    for (y, z, hit) in [
        (4.35, 0.6, true),
        (4.35, 0.66, false),
        (4.71, 0.0, false),
        (3.99, 0.0, false),
        (1.4, 0.0, false),
    ] {
        let ray = crate::combat::Ray {
            origin: [0.0, y, z],
            direction: [1.0, 0.0, 0.0],
        };
        assert_eq!(
            ray.actor(feet, identity, 20.0).is_some(),
            hit,
            "y={y}, z={z}"
        );
    }
}
#[test]
fn m04_future_groups_do_not_exist_before_their_prerequisite() {
    let (mut s, _) = fixture(CampaignDifficulty::Standard);
    assert!(s
        .state
        .players
        .iter()
        .all(|p| p.name != "notary" && p.name != "guard_2"));
    clear(&mut s, 0);
    assert!(s.state.players.iter().any(|p| p.name == "notary"));
    assert!(s.state.players.iter().all(|p| p.name != "guard_2"));
}
#[test]
fn m04_released_patient_waits_on_registered_route_then_resumes() {
    let (mut s, id) = fixture(CampaignDifficulty::Standard);
    for group in 0..6 {
        clear(&mut s, group);
    }
    let control = s.state.map.m04_geometry().unwrap().clinic.control.clone();
    use_control(&mut s, id, &control);
    place(&mut s, id, [-8.0, 0.0, 0.0]);
    advance(&mut s, 1);
    place(&mut s, id, [-7.6, 0.0, 1.1]);
    let g = s.state.map.m04_geometry().unwrap();
    let mut client = crate::mission::MissionClient::default();
    client
        .replace_map_with_m04(
            Some(&g),
            s.state.map.half_extent(),
            &s.state.map.arena().solids,
            s.state.map.presentation_ref(),
        )
        .unwrap();
    for _ in 0..30 {
        advance(&mut s, 1);
        client
            .observe(s.state.tick, s.state.mission_state().unwrap())
            .unwrap();
    }
    assert!(s.state.mission_state().unwrap().m04.unwrap().patients[0].feet[2] < 1.1);
    s.state.set_action(
        id,
        Action {
            back: true,
            yaw: Some(0.0),
            ..Action::default()
        },
    );
    advance(&mut s, 8);
    s.state.set_action(id, Action::default());
    assert!(body(&s, id).x < -9.0);
    for _ in 0..60 {
        advance(&mut s, 1);
        client
            .observe(s.state.tick, s.state.mission_state().unwrap())
            .unwrap();
    }
    let feet = s.state.mission_state().unwrap().m04.unwrap().patients[0].feet;
    assert!((feet[0] + 8.0).hypot(feet[2] - 2.0) < 0.01);
    assert_eq!(
        s.state.mission_state().unwrap().phase,
        MissionPhase::InProgress
    );
}

#[test]
fn m04_optional_clinic_uses_real_prompt_and_routes_reset_on_retry() {
    assert_eq!(
        serde_json::to_value(InteractionKind::ClinicShutter).unwrap(),
        json!("clinic_shutter")
    );
    let (mut s, id) = fixture(CampaignDifficulty::Standard);
    let g = s.state.map.m04_geometry().unwrap();
    use_control(&mut s, id, &g.clinic.control);
    assert!(!s.state.map.m04_geometry().unwrap().clinic_open);
    place(&mut s, id, [0.0, 0.0, 0.0]);
    for group in 0..3 {
        clear(&mut s, group);
    }
    use_control(&mut s, id, &g.clinic.control);
    assert!(s.state.map.m04_geometry().unwrap().clinic_open);
    assert!(s.state.m04_rescued_patient_ids().is_empty());
    place(&mut s, id, g.patients[0].held);
    advance(&mut s, 1);
    assert_eq!(s.state.m04_rescued_patient_ids(), ["edda"]);
    advance(&mut s, 10);
    let facts = s.state.mission_state().unwrap().m04.unwrap();
    assert!(facts.patients[0].feet[2] > 0.0 && facts.patients[0].feet[2] < 2.0);
    s.state.reset_mission();
    s.state.reset_campaign_encounters();
    assert!(!s.state.map.m04_geometry().unwrap().clinic_open);
    assert!(s.state.m04_rescued_patient_ids().is_empty());
    assert_eq!(s.state.m04_photos_completed(), 0);
}

#[test]
fn m04_clinic_world_change_precedes_new_facts_and_snapshot() {
    let (mut s, id) = fixture(CampaignDifficulty::Standard);
    for group in 0..3 {
        clear(&mut s, group);
    }
    let target = s.state.map.m04_geometry().unwrap().clinic.control;
    place(&mut s, id, target.approach);
    let point = target
        .point(
            s.state.map.presentation_ref().unwrap(),
            &s.state.map.arena().solids,
        )
        .unwrap();
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
    let messages = s.tick_messages(0.05);
    let map=messages.iter().position(|message|matches!(message,crate::protocol::ServerMessage::MapInfo{m04:Some(g),..} if g.clinic_open)).unwrap();
    let mission=messages.iter().position(|message|matches!(message,crate::protocol::ServerMessage::Mission{state,..} if state.m04.as_ref().is_some_and(|f|f.clinic_open))).unwrap();
    let snapshot = messages
        .iter()
        .position(|message| matches!(message, crate::protocol::ServerMessage::Snapshot(_)))
        .unwrap();
    assert!(map < mission && mission < snapshot);
}
#[test]
fn m04_shared_roof_exit_requires_fresh_use_every_ready_living_member() {
    let (mut s, id) = fixture(CampaignDifficulty::Standard);
    let g = s.state.map.m04_geometry().unwrap();
    use_control(&mut s, id, &g.departure);
    assert_eq!(
        s.state.mission_state().unwrap().phase,
        MissionPhase::InProgress
    );
    place(&mut s, id, [0.0, 0.0, 0.0]);
    for group in 0..6 {
        clear(&mut s, group);
        advance(&mut s, 1);
    }
    let other = Uuid::from_u128(4005);
    s.state.add_player(other, "Peer".into(), Role::Agent);
    use_control(&mut s, id, &g.departure);
    assert_eq!(
        s.state.mission_state().unwrap().phase,
        MissionPhase::InProgress
    );
    assert!(s.state.acknowledge_mission(
        other,
        MissionReady {
            id: MissionId::NoticeToVacate,
            attempt: 1
        }
    ));
    place(&mut s, other, g.departure.approach);
    let p = s.state.players.iter_mut().find(|p| p.id == other).unwrap();
    p.hp = 0;
    use_control(&mut s, id, &g.departure);
    assert_eq!(
        s.state.mission_state().unwrap().phase,
        MissionPhase::InProgress
    );
    let p = s.state.players.iter_mut().find(|p| p.id == other).unwrap();
    p.hp = 100;
    p.respawn_timer = None;
    use_control(&mut s, id, &g.departure);
    let state = s.state.mission_state().unwrap();
    assert_eq!(state.phase, MissionPhase::Departed);
    assert_eq!(
        state.m04.as_ref().unwrap().completed.last().unwrap(),
        "party_departed"
    );
    assert!(state.m04.as_ref().unwrap().current.is_none());
    state.validate(s.state.tick).unwrap();
}

#[test]
fn notary_dry_or_invalid_target_never_creates_a_photograph() {
    for variant in 0..3 {
        let (mut s, id) = fixture(CampaignDifficulty::Standard);
        let drone = notary(&mut s);
        let rear = Uuid::from_u128(4005);
        if variant == 0 {
            let p = s.state.players.iter_mut().find(|p| p.id == drone).unwrap();
            while p.inventory.try_fire(WeaponType::Tack) {}
        } else if variant == 1 {
            s.state.add_player(rear, "Rear witness".into(), Role::Agent);
            assert!(s.state.acknowledge_mission(
                rear,
                MissionReady {
                    id: MissionId::NoticeToVacate,
                    attempt: 1,
                }
            ));
            place(&mut s, rear, [-2.0, 0.0, 0.0]);
            s.state.spawn_shields.remove(&rear);
            s.state.spawn_shields.insert(id, 100);
        } else {
            s.state.set_action(id, Action::default());
            let p = s.state.players.iter_mut().find(|p| p.id == id).unwrap();
            p.campaign = None;
        }
        let mut bursts = Vec::new();
        for _ in 0..20 {
            advance(&mut s, 1);
            bursts.extend(
                s.state
                    .shot_results
                    .iter()
                    .filter(|r| r.shooter_id == drone)
                    .cloned(),
            );
        }
        assert_eq!(s.state.m04_photos_completed(), 0);
        if variant == 1 {
            assert!(
                !bursts.is_empty(),
                "shield does not erase actual emitted burst"
            );
            assert!(
                bursts.iter().all(|r| r.target_id == Some(id)
                    && r.hit
                    && r.damage == 0
                    && matches!(
                        r.trace.as_ref().unwrap().impact,
                        crate::protocol::ShotImpact::Fighter { .. }
                    )),
                "actual protected-burst facts: {bursts:?}"
            );
            assert_eq!(body(&s, id).hp, 100);
            assert_eq!(
                body(&s, rear).hp,
                100,
                "opaque shield stops burst before rear agent"
            );
        } else {
            assert!(
                bursts.is_empty(),
                "dry or invalid target must not emit burst"
            );
        }
    }
}

#[test]
fn notary_launch_and_lethal_player_ray_commit_the_same_frame() {
    let (mut s, id) = fixture(CampaignDifficulty::Standard);
    let drone = notary(&mut s);
    let end = match body(&s, drone).campaign.unwrap() {
        CampaignActor::Union { phase_ends, .. } => phase_ends,
        _ => panic!(),
    };
    while s.state.tick + 1 < end {
        advance(&mut s, 1);
    }
    let p = s.state.players.iter_mut().find(|p| p.id == id).unwrap();
    p.inventory.grant_weapon(WeaponType::Rail);
    p.weapon = WeaponType::Rail;
    p.fire_cooldown = 0;
    s.state.set_action(
        id,
        Action {
            fire: true,
            look_at: Some(LookAt {
                player_id: Some(drone),
                ..Default::default()
            }),
            ..Default::default()
        },
    );
    advance(&mut s, 1);
    assert!(body(&s, drone).hp <= 0);
    assert_eq!(body(&s, id).hp, 80);
    assert_eq!(s.state.m04_photos_completed(), 1);
}

#[test]
fn notary_hover_stays_bounded_and_refuses_an_overhead_attack() {
    let (mut s, id) = fixture(CampaignDifficulty::Standard);
    let drone = notary(&mut s);
    place(&mut s, id, [8.0, 0.0, 0.0]);
    for _ in 0..80 {
        advance(&mut s, 1);
        let p = body(&s, drone);
        assert!((7.0..=9.0).contains(&p.x));
        assert!((-2.0..=2.0).contains(&p.z));
        assert!((3.5..=5.0).contains(&(p.y - crate::sim::PLAYER_FLOOR_Y)));
    }
    assert_eq!(body(&s, id).hp, 100);
    assert_eq!(s.state.m04_photos_completed(), 0);
}

#[test]
fn m04_authoring_rejects_unsafe_flight_and_unreachable_or_forged_contracts() {
    for case in 0..17 {
        let mut doc = document();
        match case {
            0 => doc["encounters"][1]["enemies"][0]["hover"]["band"] = json!([5, 3]),
            1 => doc["encounters"][1]["enemies"][0]["hover"]["patrol"] = json!([[8, 4, 0]]),
            2 => doc["encounters"][1]["enemies"][0]["hover"]["approach"] = json!([19, 0, -19]),
            3 => doc["encounters"][1]["enemies"][0]["hover"]["volume"]["min"] = json!([3, 0, 3]),
            4 => doc["encounters"][1]["enemies"][0]
                .as_object_mut()
                .unwrap()
                .remove("hover")
                .map(|_| ())
                .unwrap(),
            5 => doc["encounters"][2]
                .as_object_mut()
                .unwrap()
                .remove("after")
                .map(|_| ())
                .unwrap(),
            6 => doc["m04"]["patients"][0]["route"] = json!([[-8, 0, 0], [-8, 1, 2]]),
            7 => doc["m04"]["patients"][0]["route"] = json!([[-8, 0, 0], [3.5, 0, 3.5]]),
            8 => doc["m04"]["objectives"][2]["requires_encounter"] = json!("group_1"),
            9 => doc["m04"]["departure"]["requires_encounter"] = json!("group_4"),
            10 => doc["m04"]["clinic"]["gate"]["lift"] = json!(0),
            11 => doc["m04"]["unknown"] = json!(true),
            12 => doc["m04"]["patients"][0]["route"] = json!([[-8, 0, 0], [-8, 0, 0]]),
            13 => doc["m04"]["patients"][0]["route"] = json!([[-8, 0, 0], [-8, 0, 2], [-8, 0, 1]]),
            14 => {
                doc["m04"]["patients"][0]["route"] =
                    json!([[-8, 0, 0], [-6, 0, 2], [-8, 0, 2], [-6, 0, 0]])
            }
            15 => {
                doc["solids"][0]["min"] = json!([7, 0, -1]);
                doc["solids"][0]["max"] = json!([9, 2, 1]);
            }
            _ => doc["m04"]["clinic"]["requires_encounter"] = json!("group_0"),
        }
        assert!(
            AuthoredMap::read(serde_json::to_vec(&doc).unwrap().as_slice()).is_err(),
            "unsafe authoring case {case}"
        );
    }
}

#[test]
fn m04_wire_and_controller_bind_targets_routes_progress_and_world_handoffs() {
    let (mut s, id) = fixture(CampaignDifficulty::Standard);
    let initial = s.state.map.clone();
    let mut controller = crate::mission::MissionClient::default();
    controller
        .replace_map_with_m04(
            initial.m04_geometry().as_ref(),
            initial.half_extent(),
            &initial.arena().solids,
            initial.presentation_ref(),
        )
        .unwrap();
    let state = s.state.mission_state().unwrap();
    state.validate(s.state.tick).unwrap();
    controller.observe(s.state.tick, state.clone()).unwrap();
    let encoded = serde_json::to_value(&state).unwrap();
    assert_eq!(
        serde_json::from_value::<crate::protocol::MissionState>(encoded.clone()).unwrap(),
        state
    );
    for key in [
        "completed",
        "clinic_secured",
        "clinic_open",
        "patients_released",
        "patients",
        "photos_completed",
        "carried_recall_cars",
    ] {
        let mut invalid = encoded.clone();
        invalid["m04"].as_object_mut().unwrap().remove(key);
        assert!(serde_json::from_value::<crate::protocol::MissionState>(invalid).is_err());
    }
    let mut invalid = state.clone();
    invalid
        .m04
        .as_mut()
        .unwrap()
        .current
        .as_mut()
        .unwrap()
        .action = crate::protocol::MissionObjectiveAction::Arrival {
        region: crate::protocol::Region3 {
            min: [-1.0, 0.0, -1.0],
            max: [1.0, 2.0, 1.0],
        },
        feet: [19.0, 0.0, 19.0],
    };
    assert!(controller.observe(s.state.tick, invalid).is_err());
    let mut invalid = state.clone();
    invalid.m04.as_mut().unwrap().patients[0].feet[0] += 0.1;
    assert!(controller.observe(s.state.tick, invalid).is_err());
    for group in 0..3 {
        clear(&mut s, group);
    }
    let target = s.state.map.m04_geometry().unwrap().clinic.control;
    use_control(&mut s, id, &target);
    let opened = s.state.map.clone();
    controller
        .replace_map_with_id(
            1004,
            None,
            false,
            None,
            opened.half_extent(),
            &opened.arena().solids,
            opened.presentation_ref(),
        )
        .unwrap();
    controller
        .replace_map_with_m04(
            opened.m04_geometry().as_ref(),
            opened.half_extent(),
            &opened.arena().solids,
            opened.presentation_ref(),
        )
        .unwrap();
    let mut navigator = crate::navigation::Navigator::default();
    let pending = controller.steer(
        &mut navigator,
        opened.navigation(),
        id,
        &s.state.snapshot(),
        Action::default(),
    );
    assert!(!pending.forward && !pending.fire && !pending.interact && pending.look_at.is_none());
    controller
        .observe(s.state.tick, s.state.mission_state().unwrap())
        .unwrap();
    place(&mut s, id, [-8.0, 0.0, 0.0]);
    advance(&mut s, 5);
    let moving = s.state.mission_state().unwrap();
    controller.observe(s.state.tick, moving.clone()).unwrap();
    let mut invalid = moving.clone();
    invalid.m04.as_mut().unwrap().patients[0].feet[0] += 0.06;
    assert!(controller.observe(s.state.tick, invalid).is_err());
    let mut invalid = moving.clone();
    invalid.m04.as_mut().unwrap().patients_released = false;
    invalid.m04.as_mut().unwrap().patients[0].feet = [-8.0, 0.0, 0.0];
    assert!(controller.observe(s.state.tick, invalid).is_err());
    let mut invalid = moving;
    invalid
        .m04
        .as_mut()
        .unwrap()
        .carried_recall_cars
        .push("forged".into());
    assert!(controller.observe(s.state.tick, invalid).is_err());
}
