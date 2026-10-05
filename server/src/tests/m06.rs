use crate::maps::{AuthoredMap, AuthoredSource};
use crate::protocol::{
    Action, MissionId, MissionObjectiveAction, MissionPhase, MissionReady, Role,
};
use crate::session::GameSession;
use crate::sim::PLAYER_FLOOR_Y;
use std::sync::{Arc, OnceLock};
use uuid::Uuid;

fn map() -> Arc<AuthoredMap> {
    static MAP: OnceLock<Arc<AuthoredMap>> = OnceLock::new();
    MAP.get_or_init(|| {
        AuthoredSource::Mission(MissionId::PortOfEntry)
            .load()
            .expect("bundled M06 route proof")
    })
    .clone()
}
fn advance(s: &mut GameSession, ticks: usize) {
    for _ in 0..ticks {
        s.tick_messages(0.05);
    }
}
fn fixture() -> (GameSession, Uuid) {
    let mut s = GameSession::with_authored_map(map());
    s.state.seed(42);
    let id = Uuid::from_u128(6006);
    s.state.add_player(id, "Visitor".into(), Role::Human);
    assert!(s.state.acknowledge_mission(
        id,
        MissionReady {
            id: MissionId::PortOfEntry,
            attempt: 1
        }
    ));
    advance(&mut s, 1);
    (s, id)
}
fn place(s: &mut GameSession, id: Uuid, feet: [f32; 3]) {
    let p = s.state.players.iter_mut().find(|p| p.id == id).unwrap();
    p.x = feet[0];
    p.y = feet[1] + PLAYER_FLOOR_Y;
    p.z = feet[2];
    p.vy = 0.0;
    p.clear_input();
}
fn clear(s: &mut GameSession, id: Uuid, index: usize) {
    let group = s.state.map.encounters()[index].clone();
    let g = s.state.map.m06_geometry().unwrap();
    let step = if index < 6 {
        &g.objectives[index]
    } else {
        &g.service
    };
    let MissionObjectiveAction::Arrival { feet, .. } = step.action else {
        panic!("arrival");
    };
    place(s, id, feet);
    advance(s, 1);
    for e in &group.enemies {
        let p = s
            .state
            .players
            .iter_mut()
            .find(|p| p.name == e.id)
            .expect("eligible current group spawned");
        p.hp = 0;
        s.state
            .encounters
            .hit(p.id, [p.x, p.y - PLAYER_FLOOR_Y, p.z], s.state.tick, true);
    }
    advance(s, 2);
    assert!(s.state.encounters.is_complete(index));
}

#[test]
fn bundled_port_of_entry_routes() {
    let map = crate::maps::RuntimeMap::Authored(map());
    assert_eq!(map.id(), 1006);
    let g = map.m06_geometry().unwrap();
    assert_eq!(g.objectives.len(), 6);
    assert_eq!(map.encounters().len(), 7);
    assert!(map
        .presentation_ref()
        .unwrap()
        .solids
        .contains(&crate::protocol::MapSurface::InspectionGlass));
}

#[test]
fn m06_future_lessons_are_absent_and_optional_marker_needs_clear_and_actual_arrival() {
    let (mut s, id) = fixture();
    let initial: Vec<_> = s
        .state
        .players
        .iter()
        .filter(|p| p.is_campaign_enemy())
        .map(|p| p.name.as_str())
        .collect();
    assert_eq!(initial.len(), 4);
    assert!(!initial.contains(&"rail_sweeper"));
    for i in 0..3 {
        clear(&mut s, id, i);
    }
    assert!(!s.state.m06_prisoner_route_marked());
    let service = s.state.map.m06_geometry().unwrap().service;
    let MissionObjectiveAction::Arrival { feet, .. } = service.action else {
        panic!("arrival");
    };
    place(&mut s, id, feet);
    advance(&mut s, 1);
    assert!(
        !s.state.m06_prisoner_route_marked(),
        "approach alone cannot mark a guarded route"
    );
    let guards = s.state.map.encounters()[6].enemies.clone();
    for guard in guards {
        let p = s
            .state
            .players
            .iter_mut()
            .find(|p| p.name == guard.id)
            .unwrap();
        p.hp = 0;
        s.state.encounters.hit(p.id, feet, s.state.tick, true);
    }
    place(&mut s, id, [-13.0, 0.0, 2.0]);
    advance(&mut s, 2);
    assert!(s.state.encounters.is_complete(6));
    assert!(
        !s.state.m06_prisoner_route_marked(),
        "remote clear cannot invent physical approach"
    );
    place(&mut s, id, feet);
    advance(&mut s, 1);
    assert!(s.state.m06_prisoner_route_marked());
    assert_eq!(
        s.state
            .mission_state()
            .unwrap()
            .m06
            .unwrap()
            .completed
            .len(),
        3
    );
    s.state.reset_mission();
    s.state.reset_campaign_encounters();
    assert!(!s.state.m06_prisoner_route_marked());
    assert!(s
        .state
        .mission_state()
        .unwrap()
        .m06
        .unwrap()
        .completed
        .is_empty());
}

#[test]
fn m06_required_exit_does_not_require_service_but_requires_whole_ready_living_party() {
    let (mut s, id) = fixture();
    for i in 0..6 {
        clear(&mut s, id, i);
    }
    assert!(!s.state.encounters.is_complete(6));
    assert!(!s.state.m06_prisoner_route_marked());
    let peer = Uuid::from_u128(6060);
    s.state.add_player(peer, "Peer".into(), Role::Human);
    let spectator = Uuid::from_u128(6061);
    s.apply_command(crate::net::GameCommand::Connected {
        body: crate::protocol::BodyKind::Human,
        id: spectator,
        role: Role::Spectator,
        name: "Watcher".into(),
        player_id: None,
    });
    let g = s.state.map.m06_geometry().unwrap();
    place(&mut s, id, g.departure.approach);
    let point = g
        .departure
        .point(
            s.state.map.presentation_ref().unwrap(),
            &s.state.map.arena().solids,
        )
        .unwrap();
    let aim = crate::protocol::LookAt {
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
    assert!(
        s.state.mission_state().unwrap().prompts.is_empty(),
        "unready peer blocks departure"
    );
    assert!(s.state.acknowledge_mission(
        peer,
        MissionReady {
            id: MissionId::PortOfEntry,
            attempt: 1
        }
    ));
    place(&mut s, peer, g.departure.approach);
    s.state
        .players
        .iter_mut()
        .find(|p| p.id == peer)
        .unwrap()
        .hp = 0;
    advance(&mut s, 1);
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
    s.state
        .players
        .iter_mut()
        .find(|p| p.id == peer)
        .unwrap()
        .respawn_timer = None;
    advance(&mut s, 1);
    assert_eq!(s.state.mission_state().unwrap().prompts.len(), 1);
    s.state.set_action(
        id,
        Action {
            look_at: Some(aim),
            interact: true,
            ..Action::default()
        },
    );
    advance(&mut s, 1);
    let state = s.state.mission_state().unwrap();
    assert_eq!(state.phase, MissionPhase::Departed);
    assert_eq!(
        state.party.len(),
        2,
        "spectators do not join the departure party"
    );
    assert_eq!(
        state.m06.unwrap().completed.last().unwrap(),
        "party_departed"
    );
}

#[test]
fn m06_strict_authoring_rejects_glass_roster_branch_and_control_failures() {
    let original: serde_json::Value =
        serde_json::from_slice(include_bytes!("../../maps/m06_port_of_entry.json")).unwrap();
    for failure in ["unknown", "order", "service", "turret", "ground", "control"] {
        let mut d = original.clone();
        match failure {
            "unknown" => d["m06"]["phantom"] = serde_json::json!(true),
            "order" => d["m06"]["objectives"][0]["id"] = serde_json::json!("customs_cleared"),
            "service" => d["encounters"][3]["after"] = serde_json::json!("service_branch"),
            "turret" => d["encounters"][3]["enemies"][0]["kind"] = serde_json::json!("clerk"),
            "ground" => d["ground"] = serde_json::json!("inspection_glass"),
            _ => d["m06"]["departure"]["approach"] = serde_json::json!([-37, 0, -34]),
        }
        assert!(
            AuthoredMap::read(serde_json::to_vec(&d).unwrap().as_slice()).is_err(),
            "{failure}"
        );
    }
}

#[test]
fn m06_wire_and_controller_refuse_stale_targets_regressions_and_invented_passengers() {
    let (mut s, id) = fixture();
    let map = s.state.map.clone();
    let g = map.m06_geometry().unwrap();
    let initial = s.state.mission_state().unwrap();
    for failure in ["nan", "region", "kind", "marker"] {
        let mut bad = initial.clone();
        let f = bad.m06.as_mut().unwrap();
        match failure {
            "nan" => {
                if let MissionObjectiveAction::Arrival { feet, .. } =
                    &mut f.current.as_mut().unwrap().action
                {
                    feet[0] = f32::NAN;
                }
            }
            "region" => {
                if let MissionObjectiveAction::Arrival { region, .. } =
                    &mut f.current.as_mut().unwrap().action
                {
                    region.min[0] = region.max[0] + 1.0;
                }
            }
            "kind" => {
                f.current.as_mut().unwrap().action = MissionObjectiveAction::Use {
                    target: g.departure.clone(),
                }
            }
            _ => f.prisoner_route_marked = true,
        }
        assert!(bad.validate(s.state.tick).is_err(), "{failure}");
    }
    let mut client = crate::mission::MissionClient::default();
    client
        .replace_map_with_m06(
            Some(&g),
            map.half_extent(),
            &map.arena().solids,
            map.presentation_ref(),
        )
        .unwrap();
    let mut nav = crate::navigation::Navigator::default();
    let blocked = client.steer(
        &mut nav,
        map.navigation(),
        id,
        &s.state.snapshot(),
        Action {
            fire: true,
            throw_grenade: true,
            forward: true,
            ..Action::default()
        },
    );
    assert!(!blocked.fire && !blocked.throw_grenade && !blocked.forward);
    client.observe(s.state.tick, initial.clone()).unwrap();
    let mut false_passengers = initial.clone();
    false_passengers
        .m06
        .as_mut()
        .unwrap()
        .carried_evacuated_workers
        .push("splice".into());
    assert!(false_passengers.validate(s.state.tick).is_err());
    let mut forged_target = initial.clone();
    if let MissionObjectiveAction::Arrival { feet, .. } = &mut forged_target
        .m06
        .as_mut()
        .unwrap()
        .current
        .as_mut()
        .unwrap()
        .action
    {
        feet[0] += 1.0;
    }
    assert!(client.observe(s.state.tick, forged_target).is_err());
    clear(&mut s, id, 0);
    client
        .observe(s.state.tick, s.state.mission_state().unwrap())
        .unwrap();
    assert!(
        client.observe(s.state.tick, initial).is_err(),
        "same-attempt prefix cannot regress"
    );
    client
        .replace_map_with_id(
            1006,
            None,
            false,
            None,
            map.half_extent(),
            &map.arena().solids,
            map.presentation_ref(),
        )
        .unwrap();
    client
        .replace_map_with_m06(
            Some(&g),
            map.half_extent(),
            &map.arena().solids,
            map.presentation_ref(),
        )
        .unwrap();
    let refused = client.steer(
        &mut nav,
        map.navigation(),
        id,
        &s.state.snapshot(),
        Action {
            fire: true,
            ..Action::default()
        },
    );
    assert!(
        !refused.fire,
        "MapInfo invalidates stale facts before the next Mission message"
    );
    client
        .observe(s.state.tick, s.state.mission_state().unwrap())
        .unwrap();
    s.state.reset_mission();
    s.state.reset_campaign_encounters();
    client
        .observe(s.state.tick, s.state.mission_state().unwrap())
        .unwrap();
}

#[test]
fn m06_real_long_rail_shot_uses_discovered_cells_and_preserves_misses_and_range() {
    let (mut s, id) = fixture();
    clear(&mut s, id, 0);
    assert!(!s
        .state
        .players
        .iter()
        .find(|p| p.id == id)
        .unwrap()
        .inventory
        .owns(crate::protocol::WeaponType::Rail));
    let MissionObjectiveAction::Arrival { feet, .. } =
        s.state.map.m06_geometry().unwrap().objectives[1].action
    else {
        panic!("arrival");
    };
    place(&mut s, id, feet);
    advance(&mut s, 1);
    let target = s
        .state
        .players
        .iter()
        .find(|p| p.name == "rail_sweeper")
        .unwrap()
        .id;
    let target_feet = {
        let p = s.state.players.iter().find(|p| p.id == target).unwrap();
        [p.x, p.y - PLAYER_FLOOR_Y, p.z]
    };
    let equipment = |s: &GameSession| {
        let p = s.state.players.iter().find(|p| p.id == id).unwrap();
        p.inventory.state(id, p.weapon, s.state.tick).unwrap()
    };
    assert_eq!(
        equipment(&s).shots(crate::protocol::WeaponType::Rail),
        Some(10)
    );
    assert!(s
        .state
        .players
        .iter()
        .find(|p| p.id == id)
        .unwrap()
        .inventory
        .claimed("rail_confiscated"));
    s.state.set_action(
        id,
        Action {
            weapon_swap: Some(crate::protocol::WeaponType::Rail),
            fire: true,
            look_at: Some(crate::protocol::LookAt {
                x: Some(target_feet[0]),
                y: Some(0.9),
                z: Some(target_feet[2] + 4.0),
                player_id: None,
            }),
            ..Action::default()
        },
    );
    advance(&mut s, 1);
    assert_eq!(
        s.state.players.iter().find(|p| p.id == target).unwrap().hp,
        80,
        "ordinary aim error misses"
    );
    assert_eq!(
        equipment(&s).shots(crate::protocol::WeaponType::Rail),
        Some(9)
    );
    place(&mut s, id, [target_feet[0] - 62.0, 0.0, target_feet[2]]);
    s.state
        .players
        .iter_mut()
        .find(|p| p.id == id)
        .unwrap()
        .fire_cooldown = 0;
    s.state.set_action(
        id,
        Action {
            fire: true,
            look_at: Some(crate::protocol::LookAt {
                player_id: Some(target),
                ..Default::default()
            }),
            ..Action::default()
        },
    );
    advance(&mut s, 1);
    assert_eq!(
        s.state.players.iter().find(|p| p.id == target).unwrap().hp,
        80,
        "beyond60metres remains out of range"
    );
    assert_eq!(
        equipment(&s).shots(crate::protocol::WeaponType::Rail),
        Some(8)
    );
    place(&mut s, id, feet);
    s.state
        .players
        .iter_mut()
        .find(|p| p.id == id)
        .unwrap()
        .fire_cooldown = 0;
    s.state.seed(42);
    s.state.set_action(
        id,
        Action {
            fire: true,
            look_at: Some(crate::protocol::LookAt {
                player_id: Some(target),
                ..Default::default()
            }),
            ..Action::default()
        },
    );
    advance(&mut s, 1);
    let shot = s
        .state
        .shot_results
        .iter()
        .find(|r| r.shooter_id == id)
        .unwrap();
    assert_eq!(shot.target_id, Some(target));
    assert!(shot.killed);
    assert_eq!(shot.damage, 80);
    assert_eq!(
        equipment(&s).shots(crate::protocol::WeaponType::Rail),
        Some(7)
    );
    assert_eq!(crate::protocol::WeaponType::Rail.range_units(), 60.0);
    assert_eq!(crate::protocol::WeaponType::Rail.spread_radians(), 0.012);
}

#[test]
fn m06_registered_glass_stops_real_rail_and_reflects_counted_grenade() {
    let (mut s, id) = fixture();
    place(&mut s, id, [-32.0, 0.0, 18.0]);
    let point = [-37.0, 1.4, 18.0];
    assert!(!crate::combat::line_of_sight(
        [-32.0, 1.4, 18.0],
        point,
        &s.state.map.arena().solids
    ));
    let p = s.state.players.iter_mut().find(|p| p.id == id).unwrap();
    p.inventory.grant_weapon(crate::protocol::WeaponType::Rail);
    p.inventory.grant_grenades(1);
    p.weapon = crate::protocol::WeaponType::Rail;
    s.state.set_action(
        id,
        Action {
            fire: true,
            look_at: Some(crate::protocol::LookAt {
                x: Some(point[0]),
                y: Some(point[1]),
                z: Some(point[2]),
                player_id: None,
            }),
            ..Action::default()
        },
    );
    advance(&mut s, 1);
    let trace = s
        .state
        .shot_results
        .iter()
        .find(|r| r.shooter_id == id)
        .unwrap()
        .trace
        .as_ref()
        .unwrap();
    assert!(matches!(
        trace.impact,
        crate::protocol::ShotImpact::Solid { .. }
    ));
    assert!(
        (trace.end[0] + 34.0).abs() < 0.001,
        "the registered family pressure pane owns impact"
    );
    s.state.set_action(
        id,
        Action {
            throw_grenade: true,
            yaw: Some(std::f32::consts::PI),
            pitch: Some(0.0),
            ..Action::default()
        },
    );
    let mut reflected = false;
    for _ in 0..12 {
        advance(&mut s, 1);
        let snapshot = s.state.snapshot();
        let grenade = snapshot.grenades.iter().find(|g| g.owner_id == id).unwrap();
        assert!(
            grenade.position[0] >= -33.881,
            "continuous sweep cannot tunnel through glass"
        );
        reflected |= grenade.bounce_count > 0;
    }
    assert!(reflected, "a real contact supplies bounce evidence");
}

#[test]
fn m06_companion_follows_but_does_not_fire_at_registered_solo_lessons() {
    let (mut s, id) = fixture();
    clear(&mut s, id, 0);
    let MissionObjectiveAction::Arrival { feet, .. } =
        s.state.map.m06_geometry().unwrap().objectives[1].action
    else {
        panic!("arrival");
    };
    place(&mut s, id, feet);
    advance(&mut s, 1);
    let ally = s
        .state
        .players
        .iter()
        .find(|p| p.is_campaign_companion())
        .unwrap()
        .id;
    place(&mut s, id, [20.0, 0.0, -11.0]);
    place(&mut s, ally, [20.0, 0.0, -12.5]);
    let (_, intent) = s.state.m02_companion_intent().unwrap();
    assert!(
        !intent.action.fire,
        "nearby active Rail lesson target receives no ally shots"
    );
    assert!(
        intent.goal.is_some(),
        "the companion still follows through the port"
    );
    clear(&mut s, id, 1);
    clear(&mut s, id, 2);
    place(&mut s, id, [-20.0, 3.0, 16.0]);
    advance(&mut s, 1);
    place(&mut s, ally, [-20.0, 3.0, 14.0]);
    let (_, intent) = s.state.m02_companion_intent().unwrap();
    assert!(
        !intent.action.fire,
        "the isolated Turret remains the participant's lesson"
    );
    assert!(
        intent.goal.is_none(),
        "a supported 2 m stand-off holds rather than closing the player's body"
    );
    assert!(
        !intent.action.forward
            && !intent.action.back
            && !intent.action.left
            && !intent.action.right
    );
}

#[test]
fn m06_authored_turret_charges_fires_cancels_on_cover_and_takes_a_real_rear_flank() {
    use crate::protocol::{CampaignActor, EnemyPhase, LookAt, WeaponType};
    fn phase(s: &GameSession, id: Uuid) -> (EnemyPhase, u64, u64) {
        match s
            .state
            .players
            .iter()
            .find(|p| p.id == id)
            .unwrap()
            .campaign
            .unwrap()
        {
            CampaignActor::Union {
                phase,
                phase_started,
                phase_ends,
                ..
            } => (phase, phase_started, phase_ends),
            _ => panic!("turret identity"),
        }
    }
    fn until(s: &mut GameSession, turret: Uuid, wanted: EnemyPhase) {
        for _ in 0..80 {
            if phase(s, turret).0 == wanted {
                return;
            }
            advance(s, 1);
        }
        panic!("authored Turret never reached {wanted:?}");
    }
    let (mut s, id) = fixture();
    for i in 0..3 {
        clear(&mut s, id, i);
    }
    let turret = s
        .state
        .players
        .iter()
        .find(|p| p.name == "intro_turret")
        .unwrap()
        .id;
    let home = {
        let p = s.state.players.iter().find(|p| p.id == turret).unwrap();
        [p.x, p.y - PLAYER_FLOOR_Y, p.z]
    };
    place(&mut s, id, [4.0, 0.0, 16.0]);
    until(&mut s, turret, EnemyPhase::Windup);
    let (_, started, end) = phase(&s, turret);
    assert_eq!(end - started, 26, "Standard timing is unchanged");
    place(&mut s, id, [0.0, 0.0, 10.0]);
    advance(&mut s, 1);
    assert_eq!(phase(&s, turret).0, EnemyPhase::Recovery);
    while s.state.tick <= end + 2 {
        advance(&mut s, 1);
        assert!(
            s.state.shot_results.iter().all(|r| r.shooter_id != turret),
            "real cover cancels the committed shot"
        );
    }
    place(&mut s, id, [4.0, 0.0, 16.0]);
    until(&mut s, turret, EnemyPhase::Windup);
    let end = phase(&s, turret).2;
    let mut fired = None;
    while s.state.tick <= end + 1 {
        advance(&mut s, 1);
        if let Some(shot) = s.state.shot_results.iter().find(|r| r.shooter_id == turret) {
            fired = Some(shot.clone());
        }
    }
    let shot = fired.expect("charge resolves an actual Rail shot");
    assert_eq!(shot.target_id, Some(id));
    assert_eq!(shot.damage, 80);
    assert_eq!(shot.trace.as_ref().unwrap().weapon, WeaponType::Rail);
    place(&mut s, id, [0.0, 0.0, 10.0]);
    until(&mut s, turret, EnemyPhase::Idle);
    place(&mut s, id, [-20.0, 3.0, 16.0]);
    let mut head_changed = false;
    let first_yaw = s.state.players.iter().find(|p| p.id == turret).unwrap().yaw;
    for _ in 0..40 {
        advance(&mut s, 1);
        assert_eq!(
            phase(&s, turret).0,
            EnemyPhase::Idle,
            "rear flank stays behind the actual head sweep"
        );
        assert!(s.state.shot_results.iter().all(|r| r.shooter_id != turret));
        head_changed |=
            (s.state.players.iter().find(|p| p.id == turret).unwrap().yaw - first_yaw).abs() > 0.1;
    }
    assert!(head_changed, "the fixed body has a real sweeping head");
    place(&mut s, id, [4.0, 0.0, 16.0]);
    until(&mut s, turret, EnemyPhase::Windup);
    let committed_end = phase(&s, turret).2;
    s.state.set_action(
        id,
        Action {
            weapon_swap: Some(WeaponType::Rail),
            fire: true,
            look_at: Some(LookAt {
                player_id: Some(turret),
                ..Default::default()
            }),
            ..Action::default()
        },
    );
    advance(&mut s, 1);
    assert_eq!(
        s.state.players.iter().find(|p| p.id == turret).unwrap().hp,
        20
    );
    s.state.set_action(id, Action::default());
    advance(&mut s, 1);
    assert_eq!(phase(&s, turret).0, EnemyPhase::Hit);
    assert!(
        s.state.tick < committed_end,
        "the real heavy hit interrupts the charge"
    );
    place(&mut s, id, [0.0, 0.0, 10.0]);
    advance(&mut s, 22);
    until(&mut s, turret, EnemyPhase::Idle);
    place(&mut s, id, [-20.0, 3.0, 16.0]);
    s.state.set_action(
        id,
        Action {
            fire: true,
            look_at: Some(LookAt {
                player_id: Some(turret),
                ..Default::default()
            }),
            ..Action::default()
        },
    );
    advance(&mut s, 1);
    assert_eq!(phase(&s, turret).0, EnemyPhase::Dead);
    let p = s.state.players.iter().find(|p| p.id == turret).unwrap();
    assert_eq!(
        [p.x, p.y - PLAYER_FLOOR_Y, p.z],
        home,
        "Turret never moves its fixed body"
    );
}

#[tokio::test]
async fn m06_capability_refusal_and_map_before_mission_snapshot_hold_for_all_roles() {
    use futures_util::{SinkExt, StreamExt};
    use std::time::Duration;
    use tokio_tungstenite::{connect_async, tungstenite::Message};
    let (ready_tx, ready_rx) = tokio::sync::oneshot::channel();
    let (stop_tx, stop_rx) = tokio::sync::oneshot::channel();
    let server = tokio::spawn(crate::run::run_server(
        crate::run::ServerOptions {
            bind: "127.0.0.1:0".into(),
            bots: 0,
            authored: Some(AuthoredSource::Mission(MissionId::PortOfEntry)),
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
        crate::protocol::M05_GAMEPLAY_VERSION,
        crate::protocol::M06_GAMEPLAY_VERSION,
    ] {
        for role in ["human", "agent", "spectator"] {
            let (mut socket, _) = connect_async(format!("ws://{address}")).await.unwrap();
            socket
                .send(Message::Text(
                    serde_json::json!({
                        "type":"hello", "role":role, "name":"PortProbe", "gameplay_version":version,
                        "geometry_version":crate::protocol::GEOMETRY_VERSION
                    })
                    .to_string(),
                ))
                .await
                .unwrap();
            tokio::time::timeout(Duration::from_secs(5), async {
                let mut saw_map = false;
                let mut saw_mission = false;
                let mut saw_welcome = false;
                loop {
                    let message = socket.next().await.unwrap().unwrap();
                    let Message::Text(text) = message else {
                        continue;
                    };
                    let value: serde_json::Value = serde_json::from_str(&text).unwrap();
                    if version < crate::protocol::M06_GAMEPLAY_VERSION {
                        assert_eq!(
                            value["type"], "error",
                            "retired M06 reader receives no welcome/geometry/state"
                        );
                        assert_eq!(value["code"], "unsupported_gameplay");
                        break;
                    }
                    match value["type"].as_str().unwrap() {
                        "welcome" => saw_welcome = true,
                        "map_info" => {
                            assert_eq!(value["map_id"], 1006);
                            assert!(value["m06"].is_object());
                            saw_map = true;
                        }
                        "mission" => {
                            assert!(
                                saw_map,
                                "mission facts overtake initial geometry for {role}"
                            );
                            assert_eq!(value["state"]["id"], "port_of_entry");
                            saw_mission = true;
                        }
                        "snapshot" => {
                            assert!(
                                saw_map && saw_mission && saw_welcome,
                                "snapshot overtakes initial boundaries for {role}"
                            );
                            break;
                        }
                        "error" => panic!("current reader rejected: {value}"),
                        _ => {}
                    }
                }
            })
            .await
            .expect("bounded Port of Entry role admission");
            let _ = socket.close(None).await;
        }
    }
    stop_tx.send(()).unwrap();
    server.await.unwrap().unwrap();
}

#[test]
fn m06_turret_shot_from_the_floor_passes_its_gallery_arrival_at_customs() {
    // The Turret's arrival spot is on the west gallery. A player who destroys
    // it from the floor and walks on into customs used to leave the objective
    // line on the Turret, and the transit never offered departure.
    let (mut s, id) = fixture();
    for i in 0..3 {
        clear(&mut s, id, i);
    }
    let turret = s.state.map.encounters()[3].clone();
    let floor = [0.0, 0.0, 10.0];
    place(&mut s, id, floor);
    advance(&mut s, 1);
    for e in &turret.enemies {
        let p = s
            .state
            .players
            .iter_mut()
            .find(|p| p.name == e.id)
            .expect("Turret spawned");
        p.hp = 0;
        s.state
            .encounters
            .hit(p.id, [p.x, p.y - PLAYER_FLOOR_Y, p.z], s.state.tick, true);
    }
    advance(&mut s, 4);
    let progress = |s: &GameSession| {
        let state = s.state.mission_state().unwrap();
        state.validate(s.state.tick).expect("shared reader accepts");
        state.m06.unwrap().completed.len()
    };
    assert!(s.state.encounters.is_complete(3));
    assert_eq!(
        progress(&s),
        3,
        "the Turret arrival still waits while customs sleeps"
    );
    let customs = s.state.map.m06_geometry().unwrap().objectives[4].clone();
    let MissionObjectiveAction::Arrival { feet, .. } = customs.action else {
        panic!("arrival");
    };
    place(&mut s, id, feet);
    advance(&mut s, 3);
    assert!(s.state.encounters.is_awake(4));
    assert_eq!(
        progress(&s),
        4,
        "entering customs passes the gallery arrival"
    );
}
