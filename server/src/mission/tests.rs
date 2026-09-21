use super::*;
use crate::maps::AuthoredMap;
use crate::protocol::{Action, LookAt, Role};
use crate::session::GameSession;
use serde_json::{json, Value};
use std::sync::Arc;
use uuid::Uuid;

pub(super) fn definition() -> Value {
    json!({
        "version":1,"map_id":1001,"name":"Mission fixture","half_extent":8,"ground":"concrete",
        "equipment":"discovery",
        "solids":[
            {"id":"ceiling","min":[-8,3,-8],"max":[8,4,8],"surface":"enamel"},
            {"id":"west","min":[-8,0,0],"max":[-2,3,1],"surface":"enamel"},
            {"id":"east","min":[2,0,0],"max":[8,3,1],"surface":"enamel"},
            {"id":"gate","min":[-2,0,0],"max":[2,3,1],"surface":"lift_panel"},
            {"id":"desk","min":[-4,0,-3],"max":[-2,1.2,-2],"surface":"service_steel"},
            {"id":"exit","min":[2,0,4],"max":[4,1.2,5],"surface":"service_steel"}
        ],
        "spawns":[{"id":"entry","feet":[0,0,-6],"yaw":1.5707964}],
        "landmarks":[{"id":"destination","feet":[0,0,3]}],
        "mission":{
            "id":"recall_notice",
            "gate":{"solid":"gate","lift":3},
            "boarding":{"min":[-6,0,1.5],"max":[6,0.5,7]},
            "record":{"panel":{"solid":"desk","face":"up","center":[0,0],"size":[1.8,0.8],"kind":"terminal"},"approach":[-3,0,-4]},
            "departure":{"panel":{"solid":"exit","face":"up","center":[0,0],"size":[1.8,0.8],"kind":"lift_control"},"approach":[3,0,3]}
        }
    })
}

fn decode(value: &Value) -> std::io::Result<Arc<AuthoredMap>> {
    AuthoredMap::read(serde_json::to_vec(value).unwrap().as_slice())
}

fn session() -> GameSession {
    GameSession::with_authored_map(decode(&definition()).unwrap())
}

fn add(state: &mut GameState, role: Role) -> Uuid {
    let id = Uuid::new_v4();
    state.add_player(id, format!("Player {}", state.players.len()), role);
    let mission = state.mission_state().unwrap();
    assert!(state.acknowledge_mission(
        id,
        MissionReady {
            id: mission.id,
            attempt: mission.attempt
        }
    ));
    id
}

fn approach(state: &mut GameState, id: Uuid, record: bool) -> Action {
    let geometry = state.map.mission().unwrap();
    let target = if record {
        &geometry.record
    } else {
        &geometry.departure
    };
    let point = target
        .point(
            state.map.presentation_ref().unwrap(),
            &state.map.arena().solids,
        )
        .unwrap();
    let player = state.players.iter_mut().find(|p| p.id == id).unwrap();
    [player.x, player.y, player.z] = target.approach;
    player.y += PLAYER_FLOOR_Y;
    (player.yaw, player.pitch) = crate::combat::aim_at(
        [
            player.x,
            player.y - PLAYER_FLOOR_Y + crate::movement::EYE_HEIGHT,
            player.z,
        ],
        point,
    )
    .unwrap();
    Action {
        interact: true,
        look_at: Some(LookAt {
            x: Some(point[0]),
            y: Some(point[1]),
            z: Some(point[2]),
            player_id: None,
        }),
        ..Action::default()
    }
}

fn use_record(state: &mut GameState, id: Uuid) {
    let action = approach(state, id, true);
    state.set_action(id, action);
    state.tick(0.05);
    assert_eq!(
        state.mission_state().unwrap().phase,
        MissionPhase::ReachLift
    );
}

#[test]
fn authored_gate_precomputes_real_closed_and_open_routes() {
    let state = session().state;
    let map = &state.map;
    let opened = map.opened_route().unwrap();
    let target = map.mission().unwrap().departure.approach;
    let start = [0., 0., -6.];
    assert_ne!(
        map.navigation()
            .route(start, target, crate::navigation::SEARCH_LIMIT)
            .status,
        crate::navigation::RouteStatus::Complete
    );
    assert_eq!(
        opened
            .navigation()
            .route(start, target, crate::navigation::SEARCH_LIMIT)
            .status,
        crate::navigation::RouteStatus::Complete
    );
    assert_eq!(map.id(), opened.id());
    assert_ne!(map, &opened);
    assert!(opened.opened_route().is_none());
    assert_eq!(map.arena().solids[3].bottom, 0.);
    assert_eq!(opened.arena().solids[3].bottom, 3.);
}

#[test]
fn malformed_mission_authoring_fails_before_runtime() {
    for (pointer, bad) in [
        ("/mission/gate/solid", json!("missing")),
        ("/mission/gate/lift", json!(0)),
        ("/mission/gate/lift", json!(0.5)),
        ("/mission/record/panel/solid", json!("missing")),
        ("/mission/record/panel/solid", json!("gate")),
        ("/mission/record/panel/kind", json!("lift_control")),
        ("/mission/record/panel/size", json!([17, 1])),
        ("/mission/record/approach", json!([-3, 0, -7])),
        ("/mission/record/approach", json!([-3, 0, -2.5])),
        ("/mission/departure/approach", json!([3, 0, -1])),
        ("/mission/boarding/min", json!([6, 0, 1.5])),
        ("/equipment", json!("full_arsenal")),
    ] {
        let mut doc = definition();
        *doc.pointer_mut(pointer).unwrap() = bad;
        assert!(decode(&doc).is_err(), "accepted {pointer}: {doc}");
    }
    let mut doc = definition();
    doc["mission"]["script"] = json!("arbitrary");
    assert!(decode(&doc).is_err());
    let mut doc = definition();
    doc["solids"][3]["min"] = json!([-1, 2.9, 0]);
    assert!(
        decode(&doc).is_err(),
        "a gate that never blocks is not a mission gate"
    );
}

#[test]
fn tap_opens_gate_once_and_held_use_cannot_depart() {
    let mut session = session();
    let id = add(&mut session.state, Role::Human);
    let closed = session.state.map.clone();
    let action = approach(&mut session.state, id, true);
    session.state.set_action(id, action.clone());
    session.state.set_action(
        id,
        Action {
            interact: false,
            ..action
        },
    );
    let messages = session.tick_messages(0.05);
    assert_ne!(closed, session.state.map);
    assert!(matches!(
        messages[0],
        ServerMessage::MapInfo {
            mission: Some(_),
            ..
        }
    ));
    assert!(
        matches!(&messages[1], ServerMessage::Mission { state, .. } if state.phase == MissionPhase::ReachLift)
    );
    assert!(matches!(messages[2], ServerMessage::Snapshot(_)));
    let action = approach(&mut session.state, id, false);
    // A fresh press after the release is legal.
    session.state.set_action(id, action);
    session.state.tick(0.05);
    assert!(session.state.mission_departed());
    let revision = session.state.mission_state().unwrap().changed_at;
    session.state.tick(0.05);
    assert_eq!(session.state.mission_state().unwrap().changed_at, revision);

    let mut state = self::session().state;
    let id = add(&mut state, Role::Agent);
    use_record(&mut state, id);
    let held = approach(&mut state, id, false);
    state.set_action(id, held.clone());
    for _ in 0..3 {
        state.tick(0.05);
    }
    assert!(
        !state.mission_departed(),
        "held use crossed into a second control"
    );
    state.set_action(
        id,
        Action {
            interact: false,
            ..held.clone()
        },
    );
    state.set_action(id, held);
    state.tick(0.05);
    assert!(state.mission_departed());
}

#[test]
fn use_requires_live_participant_range_aim_and_clear_sight() {
    for rejection in ["range", "aim", "wall", "dead", "npc"] {
        let mut state = session().state;
        let id = add(&mut state, Role::Human);
        add(&mut state, Role::Agent);
        let mut action = approach(&mut state, id, true);
        let player = &mut state.players[0];
        match rejection {
            "range" => player.z = -7.,
            "aim" => {
                player.yaw += std::f32::consts::PI;
                action.look_at = None;
            }
            "wall" => {
                player.z = -2.5;
                player.y = PLAYER_FLOOR_Y - 1.;
            }
            "dead" => {
                player.hp = 0;
                player.respawn_timer = Some(50);
            }
            "npc" => {
                player.campaign = Some(CampaignActor::Union {
                    kind: crate::protocol::EnemyKind::Clerk,
                    phase: crate::protocol::EnemyPhase::Idle,
                    phase_started: 0,
                    phase_ends: 0,
                })
            }
            _ => unreachable!(),
        }
        state.set_action(id, action);
        // No physics rescue from the deliberately obstructed eye in this case.
        if rejection == "wall" {
            state.advance_mission();
        } else {
            state.tick(0.05);
        }
        assert_eq!(
            state.mission_state().unwrap().phase,
            MissionPhase::FindTransfer,
            "{rejection}"
        );
        assert!(!state.players[0].interaction_requested);
    }
}

#[test]
fn party_progress_survives_one_departure_and_waits_for_everyone_aboard() {
    let mut state = session().state;
    let human = add(&mut state, Role::Human);
    let agent = add(&mut state, Role::Agent);
    use_record(&mut state, human);
    state.set_action(human, Action::default());
    let action = approach(&mut state, human, false);
    state.set_action(human, action.clone());
    state.tick(0.05);
    assert_eq!(state.mission_state().unwrap().party.len(), 2);
    assert!(!state.mission_departed());
    state.players.iter_mut().find(|p| p.id == agent).unwrap().hp = 0;
    state.tick(0.05);
    assert_eq!(
        state.mission_state().unwrap().phase,
        MissionPhase::ReachLift
    );
    state.remove_player(agent);
    assert_eq!(state.mission_state().unwrap().attempt, 1);
    state.set_action(
        human,
        Action {
            interact: false,
            ..action.clone()
        },
    );
    state.set_action(human, action);
    state.tick(0.05);
    assert!(state.mission_departed());
}

#[test]
fn wipe_resets_gate_and_attempt_once_and_last_leave_uses_same_path() {
    let mut state = session().state;
    let id = add(&mut state, Role::Human);
    let closed = state.map.clone();
    use_record(&mut state, id);
    state.players[0].hp = 0;
    state.players[0].respawn_timer = Some(10);
    for _ in 0..4 {
        state.tick(0.05);
    }
    assert_eq!(state.map, closed);
    assert_eq!(state.mission_state().unwrap().attempt, 2);
    assert_eq!(
        state.mission_state().unwrap().phase,
        MissionPhase::FindTransfer
    );
    for _ in 0..8 {
        state.tick(0.05);
    }
    assert!(state.players[0].hp > 0);
    state.set_action(id, Action::default());
    use_record(&mut state, id);
    state.remove_player(id);
    assert_eq!(state.map, closed);
    assert_eq!(state.mission_state().unwrap().attempt, 3);
    for _ in 0..3 {
        state.tick(0.05);
    }
    assert_eq!(state.mission_state().unwrap().attempt, 3);
    assert!(state.mission_state().unwrap().party.is_empty());
}

#[test]
fn shared_wire_controller_walks_and_departs_as_a_mixed_party() {
    drive_party(session(), 2, false);
}

#[test]
fn shared_party_controller_completes_actual_m01_with_discovered_equipment() {
    for (size, difficulty) in [
        (2, CampaignDifficulty::Standard),
        (4, CampaignDifficulty::Standard),
        (2, CampaignDifficulty::Assisted),
        (2, CampaignDifficulty::Severe),
    ] {
        let map = AuthoredMap::read(include_bytes!("../../maps/m01-recall-notice.json").as_slice())
            .unwrap();
        let mut session = GameSession::with_authored_map(map);
        session.state.set_campaign_difficulty(difficulty).unwrap();
        session.state.seed(67);
        drive_party(session, size, false);
    }
}

#[test]
fn solo_controller_finishes_actual_m01_with_combat_and_open_gate_retries() {
    let map =
        AuthoredMap::read(include_bytes!("../../maps/m01-recall-notice.json").as_slice()).unwrap();
    let mut session = GameSession::with_authored_map(map);
    session.state.enable_campaign_run().unwrap();
    session.state.seed(67);
    drive_party(session, 1, true);
}

fn drive_party(mut session: GameSession, size: usize, retry_after_record: bool) {
    let ids: Vec<_> = (0..size)
        .map(|index| {
            add(
                &mut session.state,
                if index % 2 == 0 {
                    Role::Human
                } else {
                    Role::Agent
                },
            )
        })
        .collect();
    let mut clients: Vec<_> = (0..size).map(|_| MissionClient::default()).collect();
    let mut navigators: Vec<_> = (0..size)
        .map(|_| crate::navigation::Navigator::default())
        .collect();
    let mut maps_seen = 0;
    // The authored twenty-guard mission is larger than the minimal gate fixture.
    // This bounds completion, not a speedrun or difficulty acceptance claim.
    let max_ticks = if session.state.map.has_encounters() {
        if retry_after_record {
            8000
        } else {
            4000
        }
    } else {
        1600
    };
    let mut deaths = 0;
    let mut forced_death = false;
    let mut dead = std::collections::HashSet::new();
    for _ in 0..max_ticks {
        let messages = session.tick_messages(0.05);
        for player in session.state.players.iter().filter(|p| ids.contains(&p.id)) {
            if player.hp <= 0 {
                if dead.insert(player.id) {
                    deaths += 1;
                }
            } else {
                dead.remove(&player.id);
            }
        }
        for message in messages {
            match message {
                ServerMessage::MapInfo {
                    mission,
                    half_extent,
                    solids,
                    presentation,
                    ..
                } => {
                    maps_seen += 1;
                    for client in &mut clients {
                        client
                            .replace_map(
                                mission.as_ref(),
                                half_extent,
                                &solids,
                                presentation.as_ref(),
                            )
                            .unwrap();
                    }
                    for navigator in &mut navigators {
                        navigator.clear();
                    }
                }
                ServerMessage::Mission { tick, state } => {
                    state.validate(tick).unwrap();
                    for client in &mut clients {
                        client.observe(tick, state.clone()).unwrap();
                    }
                    if let Some(request) = clients[0].continuation(Some(ids[0])) {
                        assert!(session.state.continue_mission(ids[0], request));
                        assert_eq!(
                            session.state.players[0].weapon,
                            crate::protocol::WeaponType::Fists
                        );
                        assert_eq!(
                            session.state.mission_state().unwrap().phase,
                            MissionPhase::FindTransfer
                        );
                    }
                }
                ServerMessage::Snapshot(snapshot) => {
                    for index in 0..size {
                        let id = ids[index];
                        let Some(player) = snapshot.players.iter().find(|p| p.id == id) else {
                            assert!(session
                                .state
                                .players
                                .iter()
                                .any(|p| p.id == id && p.respawn_timer.is_some()));
                            continue;
                        };
                        let visible = |target: &crate::protocol::PlayerState| {
                            crate::combat::line_of_sight(
                                [
                                    player.x,
                                    player.y - PLAYER_FLOOR_Y + crate::movement::EYE_HEIGHT,
                                    player.z,
                                ],
                                [
                                    target.x,
                                    target.y - PLAYER_FLOOR_Y + crate::combat::FIGHTER_HEIGHT * 0.5,
                                    target.z,
                                ],
                                &session.state.map.arena().solids,
                            )
                        };
                        let target = snapshot
                            .players
                            .iter()
                            .filter(|p| player.is_hostile_to(p))
                            .min_by(|a, b| {
                                (!visible(a)).cmp(&(!visible(b))).then_with(|| {
                                    (a.x - player.x)
                                        .hypot(a.z - player.z)
                                        .total_cmp(&(b.x - player.x).hypot(b.z - player.z))
                                })
                            });
                        let intent = target.map_or_else(Action::default, |target| Action {
                            look_at: Some(LookAt {
                                player_id: Some(target.id),
                                ..Default::default()
                            }),
                            fire: true,
                            weapon_swap: retry_after_record
                                .then_some(crate::protocol::WeaponType::Flechette),
                            forward: (target.x - player.x).hypot(target.z - player.z) > 10.,
                            // Sidestep visible fights instead of standing still
                            // while several guards fire at the solo probe.
                            left: retry_after_record && visible(target) && snapshot.tick % 40 < 20,
                            right: retry_after_record
                                && visible(target)
                                && snapshot.tick % 40 >= 20,
                            ..Action::default()
                        });
                        let body = session.state.players.iter().find(|p| p.id == id).unwrap();
                        let loadout = body.inventory.state(id, body.weapon, snapshot.tick);
                        let intent = crate::inventory::control_action_with_objective(
                            id,
                            &snapshot,
                            loadout.as_ref(),
                            intent,
                            true,
                        );
                        let action = clients[index].steer(
                            &mut navigators[index],
                            session.state.map.navigation(),
                            ids[index],
                            &snapshot,
                            intent,
                        );
                        session.state.set_action(ids[index], action);
                    }
                }
                _ => {}
            }
        }
        if retry_after_record
            && !forced_death
            && session.state.mission_state().unwrap().phase == MissionPhase::ReachLift
        {
            // Inject only the fatal outcome. Both complete routes, weapon discovery,
            // combat, panel use and the retry request use the shared live controllers.
            session
                .state
                .players
                .iter_mut()
                .find(|p| p.id == ids[0])
                .unwrap()
                .hp = 0;
            forced_death = true;
        }
        if session.state.mission_departed() {
            break;
        }
    }
    assert!(
        session.state.mission_departed(),
        "{:?}; {:?}",
        session.state.mission_state(),
        session.state.snapshot().players
    );
    assert_eq!(maps_seen, if retry_after_record { 4 } else { 2 });
    if retry_after_record {
        assert!(forced_death);
        let state = session.state.mission_state().unwrap();
        // One death is injected at the lift. The other two are combat deaths.
        // The file-stack sweeper is no longer shot from the records approach,
        // so this seeded controller spends that extra life and finishes on its
        // last continue. Every death stays charged.
        assert_eq!(deaths, 3, "{state:?}");
        assert_eq!(state.attempt, 4);
        let run = state.run.unwrap();
        assert_eq!(run.continues, 0);
        assert_eq!(run.status, crate::protocol::CampaignRunStatus::Complete);
    }
    eprintln!(
        "Mission party size={size}: ticks={}, individual deaths={deaths}, attempt={}",
        session.state.tick,
        session.state.mission_state().unwrap().attempt
    );
    let state = session.state.mission_state().unwrap();
    assert_eq!(state.party.len(), size);
    assert!(state
        .party
        .iter()
        .all(|member| member.alive && member.aboard));
    let before: Vec<_> = session
        .state
        .players
        .iter()
        .map(|p| [p.x, p.y, p.z])
        .collect();
    for id in ids {
        session.state.set_action(
            id,
            Action {
                forward: true,
                fire: true,
                ..Action::default()
            },
        );
    }
    session.tick_messages(0.05);
    assert_eq!(
        before,
        session
            .state
            .players
            .iter()
            .map(|p| [p.x, p.y, p.z])
            .collect::<Vec<_>>()
    );
    assert!(session.state.shot_results.is_empty());
}

#[test]
fn mission_observation_rejects_invalid_and_stale_shared_state() {
    let mut state = session().state;
    let id = add(&mut state, Role::Human);
    approach(&mut state, id, true);
    state.tick(0.05);
    let valid = state.mission_state().unwrap();
    valid.validate(state.tick).unwrap();
    let wire = serde_json::to_string(&ServerMessage::Mission {
        tick: state.tick,
        state: valid.clone(),
    })
    .unwrap();
    assert!(matches!(
        serde_json::from_str::<ServerMessage>(&wire).unwrap(),
        ServerMessage::Mission { .. }
    ));
    for change in [
        "attempt",
        "future",
        "duplicate",
        "name",
        "dead_aboard",
        "wrong_prompt",
        "unknown_member",
        "completed_prompt",
    ] {
        let mut invalid = valid.clone();
        match change {
            "attempt" => invalid.attempt = 0,
            "future" => invalid.changed_at = state.tick + 1,
            "duplicate" => invalid.party.push(invalid.party[0].clone()),
            "name" => invalid.party[0].name = "bad\nname".into(),
            "dead_aboard" => {
                invalid.party[0].alive = false;
                invalid.party[0].aboard = true;
            }
            "wrong_prompt" => invalid.prompts[0].kind = InteractionKind::LiftDeparture,
            "unknown_member" => invalid.prompts[0].player_id = Uuid::nil(),
            "completed_prompt" => invalid.phase = MissionPhase::Departed,
            _ => unreachable!(),
        }
        assert!(invalid.validate(state.tick).is_err(), "accepted {change}");
    }
    let mut observer = MissionClient::default();
    assert!(observer.observe(state.tick, valid.clone()).is_err());
    observer
        .replace_map(
            state.map.mission(),
            state.map.half_extent(),
            &state.map.arena().solids,
            state.map.presentation_ref(),
        )
        .unwrap();
    observer.observe(state.tick, valid.clone()).unwrap();
    assert!(observer.observe(0, valid.clone()).is_err());
    let mut next = valid.clone();
    next.attempt = 2;
    observer.observe(state.tick, next).unwrap();
    assert!(observer.observe(state.tick, valid).is_err());
    observer.replace_map(None, 8., &[], None).unwrap();
    assert!(observer.state.is_none());
}

#[test]
fn late_join_receives_map_then_shared_progress_without_reset() {
    let mut session = session();
    let id = add(&mut session.state, Role::Human);
    use_record(&mut session.state, id);
    for role in [Role::Spectator, Role::Agent] {
        let connection = Uuid::new_v4();
        let player_id = (role != Role::Spectator).then(Uuid::new_v4);
        session.apply_command(crate::net::GameCommand::Connected {
            id: connection,
            role,
            name: "Late".into(),
            player_id,
        });
        let messages = session.take_unicasts();
        assert!(matches!(&messages[0].1, ServerMessage::MapInfo { .. }));
        assert!(
            matches!(&messages[1].1, ServerMessage::Mission { state, .. } if state.phase == MissionPhase::ReachLift && state.attempt == 1)
        );
    }
    assert_eq!(session.state.mission_state().unwrap().party.len(), 2);
}

#[test]
fn physical_panel_points_match_shared_presenter_goldens() {
    let golden: Value = serde_json::from_str(include_str!(
        "../../../client/golden/decoration_points.json"
    ))
    .unwrap();
    let host: crate::movement::Solid = serde_json::from_value(golden["host"].clone()).unwrap();
    for expected in golden["points"].as_array().unwrap() {
        let panel: crate::protocol::MapDecoration = serde_json::from_value(json!({
            "solid":0,"face":expected["face"],"center":golden["center"],"size":[1,1],"kind":"terminal"
        })).unwrap();
        let point = panel.point(&host);
        for (axis, actual) in point.iter().enumerate() {
            assert!(
                (f64::from(*actual) - expected["point"][axis].as_f64().unwrap()).abs() < 0.0001,
                "{expected}"
            );
        }
    }
}

#[test]
fn supplied_agents_advance_the_mission_instead_of_filling_every_reserve() {
    use crate::inventory::{control_action, control_action_with_objective};
    use crate::protocol::WeaponType;
    let mut state = session().state;
    let id = add(&mut state, Role::Agent);
    let p = &mut state.players[0];
    p.inventory.grant_weapon(WeaponType::Tack);
    p.weapon = WeaponType::Tack;
    let mut snapshot = state.snapshot();
    snapshot.pickups.push(crate::protocol::PickupState {
        claim: crate::protocol::SupplyClaim::Contested,
        pool: Some(crate::protocol::AmmoPool::Tacks),
        id: "optional_ammo".into(),
        kind: "ammo".into(),
        weapon: String::new(),
        amount: Some(12),
        x: 1.,
        y: 0.,
        z: -5.,
        available: true,
        respawn_in: None,
    });
    let p = &state.players[0];
    let supplied = p.inventory.state(id, p.weapon, state.tick).unwrap();
    assert!(
        control_action(id, &snapshot, Some(&supplied), Action::default())
            .look_at
            .is_some()
    );
    assert!(
        control_action_with_objective(id, &snapshot, Some(&supplied), Action::default(), true)
            .look_at
            .is_none()
    );
    let mut dry = supplied;
    for weapon in &mut dry.weapons {
        if weapon.weapon == WeaponType::Tack {
            weapon.magazine = Some(0);
        }
    }
    for pool in &mut dry.reserves {
        pool.rounds = 0;
    }
    assert!(
        control_action_with_objective(id, &snapshot, Some(&dry), Action::default(), true)
            .look_at
            .is_some(),
        "dry ranged weapons still need supply"
    );
}
