use super::*;
use crate::protocol::{Action, AmmoPool, LookAt, Role, WeaponType};

const MAP: &str = include_str!("../../../maps/test/walker_foundation_development.json");

fn session() -> (crate::session::GameSession, Uuid) {
    let map = crate::maps::AuthoredMap::read(MAP.as_bytes()).unwrap();
    let mut session = crate::session::GameSession::with_authored_map(map);
    let id = Uuid::from_u128(1048);
    session.state.add_player(id, "Infantry".into(), Role::Agent);
    session.tick_messages(0.05);
    (session, id)
}

#[test]
fn walker_range_loads_strict_body_and_complete_infantry_routes() {
    let (session, _) = session();
    let geometry = session.state.map.walker_geometry().unwrap();
    geometry
        .validate(40.0, &session.state.map.arena().solids)
        .unwrap();
    session
        .state
        .walker
        .as_ref()
        .unwrap()
        .state
        .validate(session.state.tick)
        .unwrap();
    assert!(session.state.map.is_campaign());
    assert_eq!(
        session.state.snapshot().host_line,
        "Campaign development: this mission slice is still being built."
    );
    assert_eq!(
        session.state.walker.as_ref().unwrap().state.phase,
        Phase::Dormant
    );
}

fn place(session: &mut crate::session::GameSession, id: Uuid, feet: [f32; 3]) {
    let p = session
        .state
        .players
        .iter_mut()
        .find(|p| p.id == id)
        .unwrap();
    p.x = feet[0];
    p.y = feet[1] + PLAYER_FLOOR_Y;
    p.z = feet[2];
    p.vy = 0.0;
    session.state.spawn_shields.remove(&id);
}

fn advance(session: &mut crate::session::GameSession, ticks: usize) {
    for _ in 0..ticks {
        session.tick_messages(0.05);
        session
            .state
            .walker
            .as_ref()
            .unwrap()
            .state
            .validate(session.state.tick)
            .unwrap();
    }
}

#[test]
fn walker_warning_locks_lane_then_launches_real_shells_and_recovers() {
    let (mut session, id) = session();
    place(&mut session, id, [-12.0, 0.0, -8.0]);
    advance(&mut session, 1);
    assert_eq!(
        session.state.walker.as_ref().unwrap().state.phase,
        Phase::StompWarning
    );
    let initial_hp = session.state.players[0].hp;
    advance(&mut session, 31);
    assert_eq!(session.state.players[0].hp, initial_hp);
    advance(&mut session, 5);
    let warning = session.state.walker.as_ref().unwrap().state.clone();
    assert_eq!(warning.phase, Phase::ArtilleryWarning);
    assert_eq!(warning.shells_left, 36);
    place(&mut session, id, [-22.0, 0.0, -20.0]);
    advance(&mut session, 20);
    assert_eq!(
        session
            .state
            .walker
            .as_ref()
            .unwrap()
            .state
            .artillery_targets,
        warning.artillery_targets
    );
    advance(&mut session, 21);
    let fired = session.state.walker.as_ref().unwrap().state.clone();
    assert_eq!(fired.phase, Phase::Artillery);
    assert_eq!(fired.shells_left, 35);
    assert_eq!(fired.shells.len(), 1);
    let origin = fired.shells[0].position;
    advance(&mut session, 1);
    assert_ne!(
        session.state.walker.as_ref().unwrap().state.shells[0].position,
        origin
    );
    advance(&mut session, 15);
    assert_eq!(session.state.walker.as_ref().unwrap().state.shells_left, 33);
    advance(&mut session, 115);
    let w = &session.state.walker.as_ref().unwrap().state;
    assert_eq!(w.phase, Phase::Recovery);
    assert_eq!(w.feet, [8.0, 0.0, 0.0]);
    assert!(w.shells.is_empty());
}

#[test]
fn walker_joint_counter_and_covered_blasts_use_registered_current_world() {
    let (mut session, id) = session();
    let g = session.state.map.walker_geometry().unwrap();
    session.state.damage_walker_shot(id, g.solids[1], 100);
    assert_eq!(
        session.state.walker.as_ref().unwrap().state.hp,
        900,
        "sleeping equipment does not skip its first tell"
    );
    session.state.walker.as_mut().unwrap().phase(
        Phase::Recovery,
        session.state.tick,
        WALKER_RECOVERY,
    );
    session.state.damage_walker_shot(id, g.solids[0], 100);
    assert_eq!(session.state.walker.as_ref().unwrap().state.hp, 875);
    session
        .state
        .damage_walker_shot(Uuid::nil(), g.solids[1], 100);
    session.state.damage_walker_shot(id, 8, 100);
    assert_eq!(session.state.walker.as_ref().unwrap().state.hp, 875);
    session.state.damage_walker_shot(id, g.solids[1], 100);
    assert_eq!(session.state.walker.as_ref().unwrap().state.hp, 775);
    let mut arena = session.state.current_arena().into_owned();
    session
        .state
        .damage_walker_blast(id, [-3.1, 1.0, -1.4], 4.0, 100.0, None, &arena);
    assert_eq!(session.state.walker.as_ref().unwrap().state.hp, 678);
    arena.solids.push(Solid {
        min_x: -3.2,
        max_x: -3.15,
        min_z: -3.0,
        max_z: 3.0,
        bottom: 0.0,
        top: 5.0,
    });
    session
        .state
        .damage_walker_blast(id, [-3.3, 1.0, -1.4], 4.0, 100.0, None, &arena);
    assert_eq!(
        session.state.walker.as_ref().unwrap().state.hp,
        678,
        "cover blocks splash"
    );
    session.state.walker.as_mut().unwrap().state.feet = [8.0, 0.0, 0.0];
    let translated = session.state.current_arena();
    assert_eq!(translated.solids[g.solids[1]].min_x, 5.0);
    assert_eq!(session.state.map.arena().solids[g.solids[1]].min_x, -3.0);
}

#[test]
fn walker_stomp_warns_then_resolves_once_with_cover_and_inactive_immunity() {
    let (mut session, id) = session();
    place(&mut session, id, [-5.0, 0.0, 0.0]);
    advance(&mut session, 1);
    advance(&mut session, 31);
    assert_eq!(session.state.players[0].hp, 100);
    advance(&mut session, 1);
    assert!(session.state.players[0].hp < 100);
    let hp = session.state.players[0].hp;
    advance(&mut session, 3);
    assert_eq!(session.state.players[0].hp, hp);
    let mut arena = session.state.current_arena().into_owned();
    arena.solids.push(Solid {
        min_x: -4.0,
        max_x: -3.8,
        min_z: -1.0,
        max_z: 1.0,
        bottom: 0.0,
        top: 3.0,
    });
    session
        .state
        .walker_blast([0.0, 0.15, 0.0], 7.0, 55.0, &arena);
    assert_eq!(session.state.players[0].hp, hp);
    session.state.players[0].detached = true;
    let arena = session.state.current_arena().into_owned();
    session
        .state
        .walker_blast([-5.0, 0.15, 0.0], 7.0, 55.0, &arena);
    assert_eq!(session.state.players[0].hp, hp);
}

#[test]
fn walker_blocked_relocation_preserves_body_and_still_exposes_recovery() {
    let (mut session, id) = session();
    place(&mut session, id, [3.4, 0.0, -1.4]);
    let w = session.state.walker.as_mut().unwrap();
    w.next_station = 1;
    w.phase(Phase::Relocating, session.state.tick, 400);
    advance(&mut session, 1);
    let w = &session.state.walker.as_ref().unwrap().state;
    assert_eq!(w.feet, [0.0, 0.0, 0.0]);
    assert_eq!(w.phase, Phase::Recovery);
    assert_eq!(session.state.players[0].hp, 100);
}

#[test]
fn walker_exhausted_artillery_keeps_stomp_counter_and_full_party_reset() {
    let (mut session, id) = session();
    place(&mut session, id, [-12.0, 0.0, -8.0]);
    let w = session.state.walker.as_mut().unwrap();
    w.state.shells_left = 0;
    w.phase(Phase::Stomp, session.state.tick, 4);
    advance(&mut session, 4);
    assert_eq!(
        session.state.walker.as_ref().unwrap().state.phase,
        Phase::Recovery
    );
    advance(&mut session, 60);
    assert_eq!(
        session.state.walker.as_ref().unwrap().state.phase,
        Phase::StompWarning
    );
    session.state.players[0].hp = 0;
    advance(&mut session, 1);
    let w = &session.state.walker.as_ref().unwrap().state;
    assert_eq!(w.phase, Phase::Dormant);
    assert_eq!(w.shells_left, 36);
    assert_eq!(w.hp, 900);
    assert!(w.shells.is_empty());
}

#[test]
fn walker_resolved_finite_infantry_fire_disables_all_three_stages() {
    let (mut session, id) = session();
    let p = &mut session.state.players[0];
    assert!(p.inventory.grant_weapon(WeaponType::Flechette));
    p.inventory.grant_ammo(AmmoPool::Bullets, 200);
    p.weapon = WeaponType::Flechette;
    place(&mut session, id, [-10.0, 0.0, -1.4]);
    let mut stages = std::collections::HashSet::new();
    for _ in 0..1200 {
        // The isolated damage fixture holds recovery so it measures ordinary
        // finite resolved fire; the separate cycle test checks actual timing.
        let w = session.state.walker.as_mut().unwrap();
        if w.state.hp == 0 {
            break;
        }
        stages.insert(w.state.stage);
        w.phase(Phase::Recovery, session.state.tick, 60);
        session.state.set_action(
            id,
            Action {
                fire: true,
                look_at: Some(LookAt {
                    x: Some(-2.4),
                    y: Some(1.4),
                    z: Some(-1.4),
                    ..Default::default()
                }),
                ..Default::default()
            },
        );
        advance(&mut session, 1);
    }
    assert_eq!(session.state.walker.as_ref().unwrap().state.hp, 0);
    assert_eq!(stages.len(), 3);
    assert!(session.state.players[0]
        .inventory
        .needs_ammo(AmmoPool::Bullets));
    assert_eq!(session.state.players[0].hp, 100);
}

#[test]
fn walker_authoring_rejects_malformed_or_obstructed_machine() {
    let doc: serde_json::Value = serde_json::from_str(MAP).unwrap();
    for (pointer, value) in [
        ("/walker/solids/0", serde_json::json!("missing")),
        ("/walker/solids/1", serde_json::json!("walker_torso")),
        ("/walker/stations/1", serde_json::json!([0, 0, 0])),
        ("/walker/stations/1/1", serde_json::json!(1)),
        ("/walker/stations/1/0", serde_json::json!(-18)),
        ("/walker/approach", serde_json::json!([0, 4, 0])),
        ("/solids/0/min/1", serde_json::json!(1)),
        ("/solids/1/min/1", serde_json::json!(1)),
        ("/equipment", serde_json::json!("full")),
    ] {
        let mut invalid = doc.clone();
        *invalid.pointer_mut(pointer).unwrap() = value;
        assert!(
            crate::maps::AuthoredMap::read(serde_json::to_vec(&invalid).unwrap().as_slice())
                .is_err(),
            "accepted {pointer}"
        );
    }
    let mut decorated = doc;
    decorated["decorations"] = serde_json::json!([{
        "solid":"walker_torso", "face":"north", "kind":"strip_light",
        "center":[0.0,1.0], "size":[1.0,0.2]
    }]);
    let error = crate::maps::AuthoredMap::read(serde_json::to_vec(&decorated).unwrap().as_slice())
        .unwrap_err();
    assert!(
        error.to_string().contains("static map decorations"),
        "{error}"
    );
}

#[test]
fn walker_trigger_accepts_any_active_participant_and_committed_last_shot() {
    let (mut session, id) = session();
    place(&mut session, id, [0.0, 0.0, -15.0]);
    let second = Uuid::from_u128(1049);
    session
        .state
        .add_player(second, "Second".into(), Role::Agent);
    place(&mut session, second, [20.0, 0.0, 0.0]);
    advance(&mut session, 1);
    assert_eq!(
        session.state.walker.as_ref().unwrap().state.phase,
        Phase::StompWarning
    );
    // Deferred traces have already been accepted before another resolved shot
    // kills their shooter in the same tick. Their committed impact remains.
    session
        .state
        .players
        .iter_mut()
        .find(|p| p.id == id)
        .unwrap()
        .hp = 0;
    let g = session.state.map.walker_geometry().unwrap();
    session.state.damage_walker_shot(id, g.solids[1], 100);
    assert_eq!(session.state.walker.as_ref().unwrap().state.hp, 875);
}

#[test]
fn walker_rocket_direct_requires_actual_registered_contact() {
    let (mut session, id) = session();
    session
        .state
        .walker
        .as_mut()
        .unwrap()
        .phase(Phase::Recovery, session.state.tick, 60);
    let arena = session.state.current_arena().into_owned();
    let before = session.state.walker.as_ref().unwrap().state.hp;
    session
        .state
        .damage_walker_blast(id, [-3.12, 0.12, -1.4], 4.0, 45.0, None, &arena);
    let splash = before - session.state.walker.as_ref().unwrap().state.hp;
    assert!(splash > 0 && splash <= 45);
    let before = session.state.walker.as_ref().unwrap().state.hp;
    session
        .state
        .damage_walker_blast(id, [-3.12, 0.12, -1.4], 4.0, 45.0, Some((8, 65)), &arena);
    assert_eq!(
        before - session.state.walker.as_ref().unwrap().state.hp,
        splash
    );
    let before = session.state.walker.as_ref().unwrap().state.hp;
    session
        .state
        .damage_walker_blast(id, [-3.12, 0.12, -1.4], 4.0, 45.0, Some((1, 65)), &arena);
    assert_eq!(
        before - session.state.walker.as_ref().unwrap().state.hp,
        splash + 65
    );
}

#[test]
fn walker_unforced_infantry_route_uses_authored_stock_and_human_reloads() {
    for role in [Role::Agent, Role::Human] {
        let map = crate::maps::AuthoredMap::read(MAP.as_bytes()).unwrap();
        let mut session = crate::session::GameSession::with_authored_map(map);
        session.state.rng_state = 1048;
        let id = Uuid::from_u128(1048);
        session
            .state
            .add_player(id, "Walker infantry route".into(), role);
        if role == Role::Human {
            session.state.arm_joined_magazines(id);
        }
        let waypoints = [
            [-20.0, 0.0, -18.0],
            [-20.0, 0.0, 6.0],
            [-20.0, 0.0, 10.0],
            [-9.0, 0.0, 10.0],
        ];
        let mut waypoint = 0;
        let mut dodge = 10.0;
        let mut last_warning = 0;
        let mut reloads = 0;
        let mut phases = std::collections::HashSet::new();
        for step in 0..3600 {
            let p = session.state.players.iter().find(|p| p.id == id).unwrap();
            assert!(
                p.hp > 0,
                "{role:?} died at tick{} ({},{}) machine{:?}",
                session.state.tick,
                p.x,
                p.z,
                session.state.walker.as_ref().unwrap().state
            );
            let w = session.state.walker.as_ref().unwrap().state.clone();
            if w.hp == 0 {
                break;
            }
            phases.insert(format!("{:?}", w.phase));
            let loadout = p.inventory.state(id, p.weapon, session.state.tick).unwrap();
            let point = [p.x, p.y - PLAYER_FLOOR_Y, p.z];
            if waypoint < waypoints.len() && grenade::distance(point, waypoints[waypoint]) < 0.35 {
                waypoint += 1;
            }
            if w.phase == Phase::ArtilleryWarning && w.phase_started != last_warning {
                last_warning = w.phase_started;
                dodge = if point[2] > 6.0 { 2.0 } else { 10.0 };
            }
            let goal = waypoints
                .get(waypoint)
                .copied()
                .unwrap_or([-9.0, 0.0, dodge]);
            let mut action = Action::default();
            if grenade::distance(point, goal) > 0.35 {
                action.forward = true;
                action.yaw = Some((goal[2] - point[2]).atan2(goal[0] - point[0]));
                action.pitch = Some(0.0);
            } else if waypoint == waypoints.len() {
                let reloading = loadout.loaded.iter().any(|m| m.ready_at.is_some());
                let weapon = if reloading {
                    p.weapon
                } else if w.phase == Phase::Recovery && loadout.ammo(AmmoPool::Rockets) > 0 {
                    WeaponType::Rocket
                } else {
                    WeaponType::Flechette
                };
                let target = [
                    w.feet[0] - 2.4,
                    1.5,
                    w.feet[2] + if point[2] < w.feet[2] { -1.4 } else { 1.4 },
                ];
                let dx = target[0] - point[0];
                let dz = target[2] - point[2];
                action.yaw = Some(dz.atan2(dx));
                action.pitch = Some((target[1] - crate::movement::EYE_HEIGHT).atan2(dx.hypot(dz)));
                action.weapon_swap = Some(weapon);
                let empty = loadout
                    .loaded
                    .iter()
                    .any(|m| m.weapon == weapon && m.rounds == 0 && m.ready_at.is_none());
                action.reload = empty && step % 2 == 0;
                reloads += usize::from(action.reload);
                action.fire = !empty && !reloading;
            }
            session.state.set_action(id, action);
            advance(&mut session, 1);
        }
        let p = &session.state.players[0];
        let w = &session.state.walker.as_ref().unwrap().state;
        let loadout = p.inventory.state(id, p.weapon, session.state.tick).unwrap();
        assert_eq!(
            w.hp,
            0,
            "{role:?}: at {:?}, loadout {loadout:?}, walker {w:?}",
            [p.x, p.z]
        );
        assert!(
            phases.contains("Artillery")
                && phases.contains("Relocating")
                && phases.contains("Recovery")
        );
        assert!(
            loadout.personal_claims.contains(&"rifle".into())
                && loadout.personal_claims.contains(&"rocket".into())
        );
        assert!(session
            .state
            .pickups
            .iter()
            .any(|s| s.id == "west_rounds" && !s.available));
        if role == Role::Human {
            assert!(reloads > 0);
        }
        eprintln!("Walker ordinary {role:?} clear: {} ticks, {}HP, {} reload requests, bullets {}, rockets {}",session.state.tick,p.hp,reloads,loadout.ammo(AmmoPool::Bullets),loadout.ammo(AmmoPool::Rockets));
    }
}

fn golden() -> serde_json::Value {
    let (mut session, id) = session();
    let map = serde_json::to_value(session.state.map_info()).unwrap();
    let mut valid = Vec::new();
    let mut seen = std::collections::HashSet::new();
    for _ in 0..800 {
        let w = session.state.walker.as_ref().unwrap().state.clone();
        let name = serde_json::to_value(w.phase)
            .unwrap()
            .as_str()
            .unwrap()
            .to_owned();
        if seen.insert(name.clone()) {
            valid.push(
                serde_json::json!({"name":name,"map_id":1048,"tick":session.state.tick,"walker":w}),
            );
        }
        if !w.shells.is_empty() && seen.insert("traveling_shell".into()) {
            valid.push(serde_json::json!({"name":"traveling_shell","map_id":1048,"tick":session.state.tick,"walker":w}));
        }
        if w.phase == Phase::Recovery {
            break;
        }
        place(&mut session, id, [-12.0, 0.0, -8.0]);
        session.state.players[0].hp = 100;
        advance(&mut session, 1);
    }
    let joint = session.state.map.walker_geometry().unwrap().solids[1];
    for (name, damage) in [("stage_two", 350), ("stage_three", 300), ("disabled", 300)] {
        session.state.damage_walker_shot(id, joint, damage);
        let w = session.state.walker.as_ref().unwrap().state.clone();
        w.validate(session.state.tick).unwrap();
        valid.push(
            serde_json::json!({"name":name,"map_id":1048,"tick":session.state.tick,"walker":w}),
        );
    }
    let base = valid.iter().find(|v| v["name"] == "recovery").unwrap();
    let mut invalid = Vec::new();
    for (name, pointer, value) in [
        ("health_overflow", "/walker/hp", serde_json::json!(901)),
        ("wrong_stage", "/walker/stage", serde_json::json!(3)),
        ("airborne_body", "/walker/feet/1", serde_json::json!(0.1)),
        (
            "negative_stock",
            "/walker/shells_left",
            serde_json::json!(-1),
        ),
        ("wrong_duration", "/walker/phase_ends", serde_json::json!(1)),
        (
            "future_start",
            "/walker/phase_started",
            serde_json::json!(999999),
        ),
        (
            "unknown_phase",
            "/walker/phase",
            serde_json::json!("firing"),
        ),
        ("dead_recovery", "/walker/hp", serde_json::json!(0)),
    ] {
        let mut v = base.clone();
        v["name"] = serde_json::json!(name);
        *v.pointer_mut(pointer).unwrap() = value;
        invalid.push(v);
    }
    let mut blasts = Vec::new();
    for (name, feet, radius) in [
        ("stomp", [-5.0, 0.0, 0.0], WALKER_STOMP_RADIUS),
        ("shell", [-12.0, 0.0, -8.0], WALKER_SHELL_RADIUS),
    ] {
        let (mut blast_session, id) = self::session();
        place(&mut blast_session, id, feet);
        for _ in 0..160 {
            advance(&mut blast_session, 1);
            let snapshot = blast_session.state.snapshot();
            if snapshot
                .explosions
                .iter()
                .any(|blast| blast.radius == radius && !blast.hits.is_empty())
            {
                blasts.push(serde_json::json!({"name":name,"snapshot":snapshot}));
                break;
            }
        }
    }
    assert_eq!(
        blasts.len(),
        2,
        "both actual machinery blasts must hurt the stationary fixture"
    );
    let (mut vehicle_session, id) = self::session();
    place(&mut vehicle_session, id, [-17.0, 0.0, -18.0]);
    let jeep = vehicle_session
        .state
        .add_jeep([-20.0, 0.0, -18.0], 0.0)
        .unwrap();
    vehicle_session.state.damage_vehicle(jeep, 500, None);
    advance(&mut vehicle_session, 40);
    let vehicle_blast = vehicle_session.state.snapshot();
    assert_eq!(vehicle_blast.explosions.len(), 1);
    assert_eq!(vehicle_blast.explosions[0].radius, 5.0);
    assert_eq!(vehicle_blast.explosions[0].owner_id, Uuid::nil());
    assert_eq!(vehicle_blast.vehicles[0].hp, 0);
    serde_json::json!({"map":map,"valid":valid,"invalid":invalid,"blasts":blasts,"vehicle_blast":vehicle_blast})
}

#[test]
#[ignore]
fn export_walker_vectors() {
    let path = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../client/golden/walker_vectors.json");
    std::fs::write(path, serde_json::to_vec_pretty(&golden()).unwrap()).unwrap();
}

#[test]
fn walker_native_golden_matches_strict_snapshots() {
    let path = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../client/golden/walker_vectors.json");
    let bytes = std::fs::read(path).unwrap();
    // Compare the emitted wire bytes exactly. serde_json's default f64 Value
    // parser can shift the final bit of an expanded f32 decimal; comparing an
    // in-memory Value to a reparsed Value would test that parser artifact.
    assert_eq!(serde_json::to_vec_pretty(&golden()).unwrap(), bytes);
    let expected: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    for v in expected["valid"].as_array().unwrap() {
        let w: WalkerState = serde_json::from_value(v["walker"].clone()).unwrap();
        w.validate(v["tick"].as_u64().unwrap()).unwrap();
    }
    for v in expected["invalid"].as_array().unwrap() {
        assert!(serde_json::from_value::<WalkerState>(v["walker"].clone())
            .map_or(true, |w| w.validate(v["tick"].as_u64().unwrap()).is_err()));
    }
}
