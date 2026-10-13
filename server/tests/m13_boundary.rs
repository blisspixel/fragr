//! M13 joins use the production socket, and controller facts stay map-bound.
use fragr_server::maps::{AuthoredMap, AuthoredSource};
use fragr_server::mission::MissionClient;
use fragr_server::navigation::Navigator;
use fragr_server::protocol::{
    Action, AmmoPool, InteractionKind, InteractionPrompt, M13LiftPhase, M13MapGeometry, MissionId,
    MissionPhase, MissionReady, MissionState, Role, ServerMessage, WeaponType, M13_OBJECTIVE_IDS,
    M13_WORKER_RESPONSES,
};
use fragr_server::session::GameSession;
use fragr_server::sim::PLAYER_FLOOR_Y;
use std::sync::{Arc, OnceLock};
use uuid::Uuid;

fn canonical_map() -> Arc<AuthoredMap> {
    static MAP: OnceLock<Arc<AuthoredMap>> = OnceLock::new();
    MAP.get_or_init(|| {
        AuthoredSource::Mission(MissionId::WeightOfPermission)
            .load()
            .unwrap()
    })
    .clone()
}

fn bind(client: &mut MissionClient, session: &GameSession) -> M13MapGeometry {
    let ServerMessage::MapInfo {
        map_id,
        m13,
        half_extent,
        solids,
        presentation,
        ..
    } = session.state.map_info()
    else {
        panic!("map info")
    };
    client
        .replace_map_with_id(
            map_id,
            None,
            false,
            None,
            half_extent,
            &solids,
            presentation.as_ref(),
        )
        .unwrap();
    client
        .replace_map_with_m13(m13.as_ref(), half_extent, &solids, presentation.as_ref())
        .unwrap();
    m13.unwrap()
}

fn fixture() -> (GameSession, Uuid, MissionClient, M13MapGeometry) {
    let mut session = GameSession::with_authored_map(canonical_map());
    let id = Uuid::from_u128(13002);
    session
        .state
        .add_player(id, "Foundry controller".into(), Role::Agent);
    assert!(session.state.acknowledge_mission(
        id,
        MissionReady {
            id: MissionId::WeightOfPermission,
            attempt: 1
        }
    ));
    let mut client = MissionClient::default();
    let geometry = bind(&mut client, &session);
    (session, id, client, geometry)
}

// These are arranged wire states over the actual prepared map, isolating the
// controller boundary. Separate campaign tests own combat and the full route.
fn progress(
    session: &GameSession,
    geometry: &M13MapGeometry,
    count: usize,
    tick: u64,
    phase: M13LiftPhase,
    top: f32,
) -> MissionState {
    let mut state = session.state.mission_state().unwrap();
    state.phase = MissionPhase::InProgress;
    state.changed_at = tick;
    state.prompts.clear();
    let facts = state.m13.as_mut().unwrap();
    facts.completed = M13_OBJECTIVE_IDS
        .iter()
        .take(count)
        .map(|id| (*id).into())
        .collect();
    facts.current = Some(if count < M13_OBJECTIVE_IDS.len() {
        geometry.objectives[count].clone()
    } else {
        geometry.departure_objective()
    });
    facts.overseer_surrendered = count >= 3;
    facts.relay_disabled = count >= 5;
    facts.challenges.supports_cleared = count >= 6;
    facts.challenges.workers = (count >= 3).then_some(M13_WORKER_RESPONSES);
    facts.lift.phase = phase;
    facts.lift.top = top;
    facts.lift.tick = tick;
    facts.lift.returning = phase == M13LiftPhase::Returning;
    facts.hazard_phase = geometry.cycle.phase(tick);
    state.validate(tick).unwrap();
    state
}

fn place(session: &mut GameSession, id: Uuid, feet: [f32; 3], tick: u64) {
    session.state.tick = tick;
    let player = session
        .state
        .players
        .iter_mut()
        .find(|p| p.id == id)
        .unwrap();
    [player.x, player.y, player.z] = [feet[0], feet[1] + PLAYER_FLOOR_Y, feet[2]];
    player.vy = 0.0;
    session.state.set_action(id, Action::default());
}

fn idle(action: &Action) {
    assert_eq!(
        serde_json::to_value(action).unwrap(),
        serde_json::to_value(Action::default()).unwrap()
    );
}

#[test]
fn foundry_map_rebind_requires_fresh_facts_before_a_new_lift_use() {
    let (mut session, id, mut client, geometry) = fixture();
    let mut state = progress(
        &session,
        &geometry,
        6,
        100,
        M13LiftPhase::Parked,
        geometry.parked_top,
    );
    state.party[0].aboard = true;
    state.prompts.push(InteractionPrompt {
        player_id: id,
        kind: InteractionKind::ObjectiveUse,
    });
    place(&mut session, id, geometry.departure.approach, 100);
    client.observe(100, state.clone()).unwrap();
    let snapshot = session.state.snapshot();
    let mut navigator = Navigator::default();
    let first = client.steer(
        &mut navigator,
        session.state.map.navigation(),
        id,
        &snapshot,
        Action::default(),
    );
    assert!(
        first.interact,
        "a ready party at the real deck control can use it"
    );
    assert!(client.live_visibility_solids().is_some());
    bind(&mut client, &session);
    assert!(
        client.live_visibility_solids().is_none(),
        "rebinding hides stale moving collision"
    );
    idle(&client.steer(
        &mut navigator,
        session.state.map.navigation(),
        id,
        &snapshot,
        Action {
            forward: true,
            fire: true,
            interact: true,
            ..Default::default()
        },
    ));
    assert_eq!(
        client.state.as_ref(),
        Some(&state),
        "rebind retains facts only for comparison"
    );
    client.observe(100, state).unwrap();
    assert!(client.live_visibility_solids().is_some());
    assert!(
        client
            .steer(
                &mut navigator,
                session.state.map.navigation(),
                id,
                &snapshot,
                Action::default()
            )
            .interact,
        "fresh accepted facts release steering and permit a fresh press"
    );
}

#[test]
fn foundry_moving_returning_and_blocked_decks_freeze_rider_intent() {
    for (phase, returning) in [
        (M13LiftPhase::Moving, false),
        (M13LiftPhase::Returning, true),
        (M13LiftPhase::Blocked, false),
        (M13LiftPhase::Blocked, true),
    ] {
        let (mut session, id, mut client, geometry) = fixture();
        let top = geometry.parked_top + 1.0;
        let mut state = progress(&session, &geometry, 7, 100, phase, top);
        state.m13.as_mut().unwrap().lift.returning = returning;
        state.party[0].aboard = true;
        client.observe(100, state).unwrap();
        place(
            &mut session,
            id,
            [
                geometry.departure.approach[0],
                top,
                geometry.departure.approach[2],
            ],
            100,
        );
        let intent = Action {
            forward: true,
            jump: true,
            fire: true,
            interact: true,
            throw_grenade: true,
            weapon_swap: Some(WeaponType::Rocket),
            look_at: Some(fragr_server::protocol::LookAt {
                x: Some(30.0),
                y: Some(2.0),
                z: Some(40.0),
                player_id: None,
            }),
            ..Default::default()
        };
        idle(&client.steer(
            &mut Navigator::default(),
            session.state.map.navigation(),
            id,
            &session.state.snapshot(),
            intent,
        ));
        let visible = client.live_visibility_solids().unwrap();
        assert!((visible[geometry.deck].top - top).abs() < 0.0001);
        assert!(
            (visible[geometry.deck].top
                - visible[geometry.deck].bottom
                - (session.state.map.arena().solids[geometry.deck].top
                    - session.state.map.arena().solids[geometry.deck].bottom))
                .abs()
                < 0.0001
        );
        for (index, solid) in visible.iter().enumerate() {
            if index != geometry.deck {
                assert_eq!(solid, &session.state.map.arena().solids[index]);
            }
        }
    }
}

#[test]
fn foundry_lift_speed_refuses_teleport_and_accepts_physical_return_then_reboard() {
    let (mut session, id, mut client, geometry) = fixture();
    let old = progress(
        &session,
        &geometry,
        7,
        100,
        M13LiftPhase::Moving,
        geometry.parked_top + 1.0,
    );
    client.observe(100, old.clone()).unwrap();
    let impossible = progress(
        &session,
        &geometry,
        7,
        101,
        M13LiftPhase::Moving,
        geometry.parked_top + 4.0,
    );
    assert!(client.observe(101, impossible).is_err());
    assert_eq!(client.state.as_ref(), Some(&old));
    let returning = progress(
        &session,
        &geometry,
        7,
        101,
        M13LiftPhase::Returning,
        geometry.parked_top + 0.925,
    );
    client.observe(101, returning.clone()).unwrap();
    let mut blocked = progress(
        &session,
        &geometry,
        7,
        102,
        M13LiftPhase::Blocked,
        geometry.parked_top + 0.925,
    );
    blocked.m13.as_mut().unwrap().lift.returning = true;
    client.observe(102, blocked).unwrap();
    let mut parked = progress(
        &session,
        &geometry,
        7,
        120,
        M13LiftPhase::Parked,
        geometry.parked_top,
    );
    parked.party[0].aboard = true;
    parked.prompts.push(InteractionPrompt {
        player_id: id,
        kind: InteractionKind::ObjectiveUse,
    });
    client.observe(120, parked).unwrap();
    place(&mut session, id, geometry.departure.approach, 120);
    let mut navigator = Navigator::default();
    let snapshot = session.state.snapshot();
    assert!(
        client
            .steer(
                &mut navigator,
                session.state.map.navigation(),
                id,
                &snapshot,
                Action::default()
            )
            .interact
    );
    assert!(
        !client
            .steer(
                &mut navigator,
                session.state.map.navigation(),
                id,
                &snapshot,
                Action::default()
            )
            .interact,
        "reboarding must not hold use across successive control calls"
    );
}

#[test]
fn foundry_workers_require_real_route_positions_and_monotonic_arrival_receipts() {
    let (session, _, mut client, geometry) = fixture();
    let released = progress(
        &session,
        &geometry,
        3,
        100,
        M13LiftPhase::Parked,
        geometry.parked_top,
    );
    client.observe(100, released.clone()).unwrap();
    for kind in 0..3 {
        let mut invalid = released.clone();
        let facts = invalid.m13.as_mut().unwrap();
        match kind {
            0 => facts.worker_feet[0][2] += 0.2,
            1 => facts.challenges.workers_arrived[0] = true,
            _ => {
                facts.challenges.workers = None;
                facts.worker_feet[0][0] += 0.2;
            }
        }
        assert!(
            client.observe(100, invalid).is_err(),
            "invalid worker case {kind}"
        );
        assert_eq!(client.state.as_ref(), Some(&released));
    }
    let mut arrived = progress(
        &session,
        &geometry,
        3,
        400,
        M13LiftPhase::Parked,
        geometry.parked_top,
    );
    arrived.m13.as_mut().unwrap().worker_feet[0] = geometry.worker_destinations[0];
    arrived.m13.as_mut().unwrap().challenges.workers_arrived[0] = true;
    client.observe(400, arrived.clone()).unwrap();
    let mut rewound = arrived.clone();
    rewound.m13.as_mut().unwrap().challenges.workers_arrived[0] = false;
    assert!(client.observe(400, rewound).is_err());
    assert_eq!(client.state.as_ref(), Some(&arrived));
    let mut rewound = arrived.clone();
    rewound.m13.as_mut().unwrap().worker_feet[0][0] -= 0.2;
    assert!(client.observe(400, rewound).is_err());
    assert_eq!(client.state.as_ref(), Some(&arrived));
}

#[test]
fn foundry_relay_steering_selects_finite_ray_ammo_or_actual_supply() {
    use fragr_server::inventory::Inventory;
    use fragr_server::protocol::{EquipmentPolicy, MissionObjectiveAction};
    let (mut session, id, mut client, geometry) = fixture();
    let MissionObjectiveAction::Shoot { approach, aim, .. } = geometry.objectives[4].action else {
        panic!("relay")
    };
    let state = progress(
        &session,
        &geometry,
        4,
        100,
        M13LiftPhase::Parked,
        geometry.parked_top,
    );
    client.observe(100, state).unwrap();
    place(&mut session, id, approach, 100);
    let mut inventory = Inventory::new(EquipmentPolicy::Discovery);
    inventory.grant_weapon(WeaponType::Rocket);
    inventory.grant_weapon(WeaponType::Tack);
    let held = inventory.state(id, WeaponType::Rocket, 100).unwrap();
    let snapshot = session.state.snapshot();
    let mut navigator = Navigator::default();
    let shot = client.steer_with_equipment(
        &mut navigator,
        session.state.map.navigation(),
        id,
        &snapshot,
        Action::default(),
        Some(&held),
    );
    assert_eq!(shot.weapon_swap, Some(WeaponType::Tack));
    assert!(shot.fire && !shot.reload);
    let target = shot.look_at.unwrap();
    assert_eq!(
        [target.x.unwrap(), target.y.unwrap(), target.z.unwrap()],
        aim
    );
    assert_eq!(
        held,
        inventory.state(id, WeaponType::Rocket, 100).unwrap(),
        "controller cannot spend or grant ammunition"
    );
    let mut human = Inventory::new(EquipmentPolicy::Discovery);
    human.grant_weapon(WeaponType::Flechette);
    human.grant_ammo(AmmoPool::Bullets, 30);
    human.arm_magazines();
    while human.try_fire(WeaponType::Flechette) {}
    let empty_tube = human.state(id, WeaponType::Flechette, 100).unwrap();
    let reload = client.steer_with_equipment(
        &mut navigator,
        session.state.map.navigation(),
        id,
        &snapshot,
        Action::default(),
        Some(&empty_tube),
    );
    assert!(reload.reload && !reload.fire);
    assert!(human.request_reload(WeaponType::Flechette, 100));
    human.finish_reload(100 + u64::from(WeaponType::Flechette.reload_ticks().unwrap()));
    let loaded = human.state(id, WeaponType::Flechette, 150).unwrap();
    let shot = client.steer_with_equipment(
        &mut navigator,
        session.state.map.navigation(),
        id,
        &snapshot,
        Action::default(),
        Some(&loaded),
    );
    assert!(shot.fire && !shot.reload);
    while inventory.try_fire(WeaponType::Tack) {}
    let dry = inventory.state(id, WeaponType::Rocket, 100).unwrap();
    let mut resupply = snapshot.clone();
    let bullets = resupply
        .pickups
        .iter()
        .find(|p| p.kind == "ammo" && p.pool == Some(AmmoPool::Bullets) && p.available)
        .unwrap()
        .clone();
    resupply.pickups = vec![bullets.clone()];
    let action = client.steer_with_equipment(
        &mut navigator,
        session.state.map.navigation(),
        id,
        &resupply,
        Action::default(),
        Some(&dry),
    );
    assert!(
        !action.fire && !action.throw_grenade && action.weapon_swap != Some(WeaponType::Rocket)
    );
    assert!(
        action.forward || action.back || action.left || action.right,
        "dry relay resupply to {bullets:?} returned {action:?}"
    );
    // Navigation may replace the supply aim with a waypoint yaw. Exercise its
    // actual discrete movement against the canonical collision to prove where
    // this resupply intent goes, without relying on private route memory.
    use fragr_server::movement::{live_step, MoveInput, MoveState, TOP_SPEED};
    let floor = session
        .state
        .map
        .navigation()
        .coordinate_floor([bullets.x, bullets.y, bullets.z])
        .unwrap();
    let mut body = MoveState {
        x: approach[0],
        y: approach[1],
        z: approach[2],
        vx: 0.0,
        vy: 0.0,
        vz: 0.0,
        yaw: 0.0,
    };
    let mut reached = false;
    for tick in 101..1101 {
        if (body.x - bullets.x).hypot(body.z - bullets.z) < 0.6 && (body.y - floor).abs() < 0.05 {
            reached = true;
            break;
        }
        resupply.tick = tick;
        let player = resupply.players.iter_mut().find(|p| p.id == id).unwrap();
        player.x = body.x;
        player.y = body.y + PLAYER_FLOOR_Y;
        player.z = body.z;
        player.yaw = body.yaw;
        let action = client.steer_with_equipment(
            &mut navigator,
            session.state.map.navigation(),
            id,
            &resupply,
            Action::default(),
            Some(&dry),
        );
        assert!(!action.fire && !action.throw_grenade && !action.place_mine);
        let yaw = action.yaw.unwrap_or_else(|| {
            action
                .look_at
                .as_ref()
                .and_then(|p| Some((p.z? - body.z).atan2(p.x? - body.x)))
                .unwrap_or(body.yaw)
        });
        body = live_step(
            body,
            &MoveInput {
                forward: action.forward,
                back: action.back,
                left: action.left,
                right: action.right,
                jump: action.jump,
                yaw,
                ..MoveInput::default()
            },
            TOP_SPEED,
            0.05,
            session.state.map.arena(),
        );
    }
    assert!(
        reached,
        "dry relay route stopped at {body:?}; supply {bullets:?}"
    );
    resupply.pickups.clear();
    idle(&client.steer_with_equipment(
        &mut navigator,
        session.state.map.navigation(),
        id,
        &resupply,
        Action::default(),
        Some(&dry),
    ));
    idle(&client.steer_with_equipment(
        &mut navigator,
        session.state.map.navigation(),
        id,
        &resupply,
        Action::default(),
        None,
    ));
    assert_eq!(dry, inventory.state(id, WeaponType::Rocket, 100).unwrap());
}

#[test]
fn foundry_controller_requires_registered_facts_and_rejects_worker_teleport() {
    let map = AuthoredSource::Mission(MissionId::WeightOfPermission)
        .load()
        .unwrap();
    let mut session = GameSession::with_authored_map(map);
    let id = Uuid::from_u128(13001);
    session
        .state
        .add_player(id, "Foundry boundary".into(), Role::Agent);
    let mut client = MissionClient::default();
    let state = session.state.mission_state().unwrap();
    assert!(client.observe(session.state.tick, state.clone()).is_err());
    let ServerMessage::MapInfo {
        map_id,
        m13,
        half_extent,
        solids,
        presentation,
        ..
    } = session.state.map_info()
    else {
        panic!("map info")
    };
    client
        .replace_map_with_id(
            map_id,
            None,
            false,
            None,
            half_extent,
            &solids,
            presentation.as_ref(),
        )
        .unwrap();
    client
        .replace_map_with_m13(m13.as_ref(), half_extent, &solids, presentation.as_ref())
        .unwrap();
    assert!(!client.participating(id));
    client.observe(session.state.tick, state.clone()).unwrap();
    assert!(client.readiness(Some(id)).is_some());
    let mut forged = state.clone();
    forged.m13.as_mut().unwrap().worker_feet[2][0] += 2.0;
    assert!(
        client.observe(session.state.tick, forged).is_err(),
        "declined worker cannot teleport"
    );
    let mut forged = state.clone();
    forged.m13.as_mut().unwrap().current.as_mut().unwrap().id = "party_departed".into();
    assert!(
        client.observe(session.state.tick, forged).is_err(),
        "ordered objectives cannot skip"
    );
    let mut changed = m13.unwrap();
    changed.overseer[0] += 0.1;
    assert!(
        client
            .replace_map_with_m13(Some(&changed), half_extent, &solids, presentation.as_ref())
            .is_err(),
        "same mission map cannot move its people"
    );
    assert_eq!(
        client.state,
        Some(state),
        "invalid input never replaces accepted facts"
    );
}

#[tokio::test]
async fn foundry_socket_requires_capability_and_delivers_map_before_state_for_every_role() {
    use futures_util::{SinkExt, StreamExt};
    use std::time::Duration;
    use tokio_tungstenite::{connect_async, tungstenite::Message};
    let (ready_tx, ready_rx) = tokio::sync::oneshot::channel();
    let (stop_tx, stop_rx) = tokio::sync::oneshot::channel();
    let server = tokio::spawn(fragr_server::run::run_server(
        fragr_server::run::ServerOptions {
            bind: "127.0.0.1:0".into(),
            bots: 0,
            authored: Some(AuthoredSource::Mission(MissionId::WeightOfPermission)),
            ..Default::default()
        },
        async {
            let _ = stop_rx.await;
        },
        Some(ready_tx),
    ));
    let address = tokio::time::timeout(Duration::from_secs(45), ready_rx)
        .await
        .expect("bounded preparation")
        .unwrap();
    for version in [46, 47] {
        for role in ["human", "agent", "spectator"] {
            let (mut socket, _) = connect_async(format!("ws://{address}")).await.unwrap();
            socket.send(Message::Text(serde_json::json!({"type":"hello","role":role,"name":"Foundry reader","gameplay_version":version,"geometry_version":fragr_server::protocol::GEOMETRY_VERSION}).to_string())).await.unwrap();
            tokio::time::timeout(Duration::from_secs(8), async {
                let mut welcomed = false;
                let mut mapped = false;
                let mut client = MissionClient::default();
                loop {
                    let Message::Text(text) = socket.next().await.unwrap().unwrap() else {
                        continue;
                    };
                    let value: serde_json::Value = serde_json::from_str(&text).unwrap();
                    if version < 47 {
                        assert_eq!(value["type"], "error");
                        assert!(value["message"].as_str().unwrap().contains("version 47"));
                        break;
                    }
                    match value["type"].as_str().unwrap() {
                        "welcome" => welcomed = true,
                        "map_info" => {
                            assert!(welcomed);
                            let ServerMessage::MapInfo {
                                map_id,
                                m13,
                                half_extent,
                                solids,
                                presentation,
                                ..
                            } = serde_json::from_str(&text).unwrap()
                            else {
                                panic!("map")
                            };
                            assert_eq!(map_id, 1013);
                            assert!(m13.is_some());
                            client
                                .replace_map_with_id(
                                    map_id,
                                    None,
                                    false,
                                    None,
                                    half_extent,
                                    &solids,
                                    presentation.as_ref(),
                                )
                                .unwrap();
                            client
                                .replace_map_with_m13(
                                    m13.as_ref(),
                                    half_extent,
                                    &solids,
                                    presentation.as_ref(),
                                )
                                .unwrap();
                            mapped = true;
                        }
                        "mission" => {
                            assert!(welcomed && mapped, "initial map must precede foundry facts");
                            let tick = value["tick"].as_u64().unwrap();
                            let state = serde_json::from_value(value["state"].clone()).unwrap();
                            client.observe(tick, state).unwrap();
                            break;
                        }
                        "error" => panic!("supported {role} refused: {value}"),
                        _ => {}
                    }
                }
            })
            .await
            .expect("bounded foundry admission");
            let _ = socket.close(None).await;
        }
    }
    stop_tx.send(()).unwrap();
    server.await.unwrap().unwrap();
}
