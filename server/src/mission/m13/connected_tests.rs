//! Arranged encounter progress isolates physical control and transport authority.
use super::*;
use crate::maps::{AuthoredMap, RuntimeMap};
use crate::protocol::*;
use crate::sim::GameState;
use std::sync::{Arc, OnceLock};
fn map() -> Arc<AuthoredMap> {
    static MAP: OnceLock<Arc<AuthoredMap>> = OnceLock::new();
    MAP.get_or_init(|| {
        AuthoredMap::read(include_bytes!("../../../maps/m13-weight-of-permission.json").as_slice())
            .unwrap()
    })
    .clone()
}
fn fixture() -> (GameState, Uuid) {
    let mut s = GameState::with_authored_map(map());
    let id = Uuid::from_u128(1313);
    s.add_player(id, "Foundry controls".into(), Role::Human);
    assert!(s.acknowledge_mission(
        id,
        MissionReady {
            id: MissionId::WeightOfPermission,
            attempt: 1
        }
    ));
    (s, id)
}
fn place(s: &mut GameState, id: Uuid, feet: [f32; 3]) {
    let p = s.players.iter_mut().find(|p| p.id == id).unwrap();
    p.x = feet[0];
    p.y = feet[1] + PLAYER_FLOOR_Y;
    p.z = feet[2];
    p.vy = 0.0;
    p.clear_input();
}
fn ready_lift(s: &mut GameState, id: Uuid) {
    let g = s.map.m13_geometry().unwrap();
    place(s, id, g.departure.approach);
    let p = s.mission.as_mut().unwrap().m13.as_mut().unwrap();
    p.index = 6;
    p.surrendered = true;
    s.foundry.as_mut().unwrap().relay_disabled = true;
}
fn use_target(s: &mut GameState, id: Uuid, target: UseTarget) {
    let point = target
        .point(s.map.presentation_ref().unwrap(), &s.current_arena().solids)
        .unwrap();
    s.set_action(id, Action::default());
    s.set_action(
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
    s.tick(0.05);
}
#[test]
fn connected_geometry_and_protocol_reject_malformed_controls_and_receipts() {
    let map = RuntimeMap::Authored(map());
    let g = map.m13_geometry().unwrap();
    g.validate(
        map.arena().half,
        &map.arena().solids,
        map.presentation_ref(),
    )
    .unwrap();
    let mut bad = g.clone();
    bad.protected.push(bad.relay);
    assert!(bad
        .validate(
            map.arena().half,
            &map.arena().solids,
            map.presentation_ref()
        )
        .is_err());
    let mut bad = g.clone();
    bad.cycle.period = 0;
    assert!(bad
        .validate(
            map.arena().half,
            &map.arena().solids,
            map.presentation_ref()
        )
        .is_err());
    let mut bad = g.clone();
    bad.objectives.swap(0, 1);
    assert!(bad
        .validate(
            map.arena().half,
            &map.arena().solids,
            map.presentation_ref()
        )
        .is_err());
    let mut bad = g.clone();
    bad.departure = g.release.clone();
    assert!(bad
        .validate(
            map.arena().half,
            &map.arena().solids,
            map.presentation_ref()
        )
        .is_err());
    let (s, _) = fixture();
    let state = s.mission_state().unwrap();
    state.validate(s.tick).unwrap();
    for mutate in 0..6 {
        let mut bad = state.clone();
        let f = bad.m13.as_mut().unwrap();
        match mutate {
            0 => f.relay_disabled = true,
            1 => f.challenges.workers_arrived[0] = true,
            2 => f.challenges.workers = Some([M13WorkerResponse::Volunteered; 3]),
            3 => f.lift.tick += 1,
            4 => f.lift.returning = true,
            _ => f.completed.push("rocket_found".into()),
        }
        assert!(bad.validate(s.tick).is_err(), "case {mutate}");
    }
}
#[test]
fn lift_requires_fresh_use_and_supported_entire_party() {
    let (mut s, id) = fixture();
    let g = s.map.m13_geometry().unwrap();
    ready_lift(&mut s, id);
    let other = Uuid::from_u128(1314);
    s.add_player(other, "Late participant".into(), Role::Human);
    use_target(&mut s, id, g.departure.clone());
    assert_eq!(s.foundry.as_ref().unwrap().lift_phase, lift::Phase::Parked);
    assert!(s.acknowledge_mission(
        other,
        MissionReady {
            id: MissionId::WeightOfPermission,
            attempt: 1
        }
    ));
    place(&mut s, other, [-0.9, g.parked_top, 49.0]);
    s.players.iter_mut().find(|p| p.id == id).unwrap().x = 0.5;
    s.tick(0.05);
    assert_eq!(
        s.foundry.as_ref().unwrap().lift_phase,
        lift::Phase::Parked,
        "held use cannot arm after late readiness"
    );
    use_target(&mut s, id, g.departure.clone());
    assert_eq!(s.foundry.as_ref().unwrap().lift_phase, lift::Phase::Moving);
    assert_eq!(s.mission.as_ref().unwrap().m13.as_ref().unwrap().index, 7);
    s.mission_state().unwrap().validate(s.tick).unwrap();
}
#[test]
fn departing_rider_returns_physically_and_reboarding_requires_new_use() {
    let (mut s, id) = fixture();
    let g = s.map.m13_geometry().unwrap();
    ready_lift(&mut s, id);
    use_target(&mut s, id, g.departure.clone());
    for _ in 0..20 {
        s.tick(0.05);
    }
    let raised = s.foundry.as_ref().unwrap().lift_top;
    assert!(raised > g.parked_top + 1.0);
    let joiner = Uuid::from_u128(1315);
    s.add_player(joiner, "Joining while lift travels".into(), Role::Human);
    s.tick(0.05);
    assert!(s.foundry.as_ref().unwrap().returning);
    assert!(s.foundry.as_ref().unwrap().lift_top < raised);
    s.remove_player(joiner);
    for _ in 0..80 {
        s.tick(0.05);
        s.mission_state().unwrap().validate(s.tick).unwrap();
        if s.foundry.as_ref().unwrap().lift_phase == lift::Phase::Parked {
            break;
        }
    }
    assert_eq!(s.foundry.as_ref().unwrap().lift_phase, lift::Phase::Parked);
    assert!((s.players[0].y - PLAYER_FLOOR_Y - g.parked_top).abs() < 0.001);
    assert_eq!(s.mission.as_ref().unwrap().m13.as_ref().unwrap().index, 7);
    s.tick(0.05);
    assert_eq!(s.foundry.as_ref().unwrap().lift_phase, lift::Phase::Parked);
    use_target(&mut s, id, g.departure.clone());
    for _ in 0..170 {
        s.tick(0.05);
        if s.mission_departed() {
            break;
        }
    }
    assert!(s.mission_departed());
    let top = s.foundry.as_ref().unwrap().lift_top;
    let damage = s.foundry.as_ref().unwrap().hazard_hurt;
    for _ in 0..5 {
        s.tick(0.05);
    }
    assert_eq!(s.foundry.as_ref().unwrap().lift_top, top);
    assert_eq!(s.foundry.as_ref().unwrap().hazard_hurt, damage);
}
#[test]
fn relay_refuses_early_hits_and_protected_feed_and_hazards_freeze_outside_play() {
    let (mut s, id) = fixture();
    let gates = s.map.m13_gates().unwrap().clone();
    let host = s.map.arena().solids[gates.relay];
    let end = [host.max_x, 1.4, (host.min_z + host.max_z) * 0.5];
    s.damage_foundry_relay(id, gates.relay, end, [1.0, 0.0, 0.0], 100);
    assert!(!s.foundry.as_ref().unwrap().relay_disabled);
    s.mission.as_mut().unwrap().m13.as_mut().unwrap().index = 4;
    s.damage_foundry_relay(id, gates.protected[0], end, [1.0, 0.0, 0.0], 100);
    assert!(!s.foundry.as_ref().unwrap().relay_disabled);
    s.damage_foundry_relay(id, gates.relay, end, [1.0, 0.0, 0.0], 100);
    assert!(s.foundry.as_ref().unwrap().relay_disabled);
    let feet = [
        (gates.hazard.min[0] + gates.hazard.max[0]) * 0.5,
        gates.hazard.min[1],
        (gates.hazard.min[2] + gates.hazard.max[2]) * 0.5,
    ];
    place(&mut s, id, feet);
    s.tick = 159;
    s.mission.as_mut().unwrap().phase = MissionPhase::Briefing;
    s.tick_foundry_hazards();
    assert_eq!(s.foundry.as_ref().unwrap().hazard_hurt, 0);
    s.mission.as_mut().unwrap().phase = MissionPhase::InProgress;
    s.tick_foundry_hazards();
    assert!(s.foundry.as_ref().unwrap().hazard_hurt > 0);
    let hurt = s.foundry.as_ref().unwrap().hazard_hurt;
    s.mission.as_mut().unwrap().phase = MissionPhase::Departed;
    s.tick_foundry_hazards();
    assert_eq!(s.foundry.as_ref().unwrap().hazard_hurt, hurt);
}
#[test]
fn worker_choices_preserve_distinct_grounded_arrivals_and_decline() {
    let (mut s, id) = fixture();
    let g = s.map.m13_geometry().unwrap();
    place(&mut s, id, g.release.approach);
    use_target(&mut s, id, g.release.clone());
    assert!(s.foundry.as_ref().unwrap().workers.is_none());
    s.mission
        .as_mut()
        .unwrap()
        .m13
        .as_mut()
        .unwrap()
        .surrendered = true;
    use_target(&mut s, id, g.release.clone());
    assert_eq!(
        s.foundry.as_ref().unwrap().workers,
        Some(M13_WORKER_RESPONSES)
    );
    let start = s
        .mission
        .as_ref()
        .unwrap()
        .m13
        .as_ref()
        .unwrap()
        .worker_feet;
    assert_eq!(start, g.workers);
    place(&mut s, id, [-10.0, 0.3, 0.0]);
    for _ in 0..300 {
        s.advance_m13();
    }
    let p = s.mission.as_ref().unwrap().m13.as_ref().unwrap();
    assert_eq!(p.arrived, [true, true, false]);
    assert_eq!(p.worker_feet[2], g.workers[2]);
    for i in 0..2 {
        assert!(
            (p.worker_feet[i][0] - g.worker_destinations[i][0])
                .hypot(p.worker_feet[i][2] - g.worker_destinations[i][2])
                <= 0.06
        );
    }
    assert_ne!(p.worker_feet[0], start[0]);
}

#[test]
fn native_foundry_fact_vectors_match_client_fixture() {
    let (mut s, id) = fixture();
    let g = s.map.m13_geometry().unwrap();
    let mut valid = Vec::new();
    for n in 0..=8 {
        let run = s.mission.as_mut().unwrap();
        run.phase = if n == 8 {
            MissionPhase::Departed
        } else {
            MissionPhase::InProgress
        };
        let p = run.m13.as_mut().unwrap();
        p.index = n.min(7);
        p.surrendered = n >= 3;
        let gates = s.foundry.as_mut().unwrap();
        gates.relay_disabled = n >= 5;
        gates.lift_phase = if n == 8 {
            lift::Phase::Arrived
        } else if n == 7 {
            lift::Phase::Moving
        } else {
            lift::Phase::Parked
        };
        gates.lift_top = if n == 8 { g.lift_top } else { g.parked_top };
        let state = s.mission_state().unwrap();
        state.validate(s.tick).unwrap();
        valid.push(serde_json::json!({"name":format!("ordered_{n}"),"tick":s.tick,"state":state}));
    }
    s.mission.as_mut().unwrap().phase = MissionPhase::InProgress;
    for (name, phase, returning) in [
        ("returning", lift::Phase::Returning, true),
        ("blocked_return", lift::Phase::Blocked, true),
        ("parked_again", lift::Phase::Parked, false),
    ] {
        let f = s.foundry.as_mut().unwrap();
        f.lift_phase = phase;
        f.returning = returning;
        f.lift_top = if phase == lift::Phase::Parked {
            g.parked_top
        } else {
            g.parked_top + 1.0
        };
        let state = s.mission_state().unwrap();
        state.validate(s.tick).unwrap();
        valid.push(serde_json::json!({"name":name,"tick":s.tick,"state":state}));
    }
    let mut invalid = Vec::new();
    for name in [
        "early_relay",
        "invented_arrival",
        "invented_choice",
        "stale_lift_tick",
        "illegal_return",
        "unknown_field",
    ] {
        let mut v = valid[0]["state"].clone();
        match name {
            "early_relay" => v["m13"]["relay_disabled"] = true.into(),
            "invented_arrival" => v["m13"]["challenges"]["workers_arrived"][0] = true.into(),
            "invented_choice" => {
                v["m13"]["challenges"]["workers"] =
                    serde_json::json!(["volunteered", "volunteered", "volunteered"])
            }
            "stale_lift_tick" => v["m13"]["lift"]["tick"] = 1.into(),
            "illegal_return" => v["m13"]["lift"]["returning"] = true.into(),
            _ => v["m13"]["made_up"] = true.into(),
        }
        assert!(serde_json::from_value::<MissionState>(v.clone())
            .map_or(true, |state| state.validate(s.tick).is_err()));
        invalid.push(serde_json::json!({"name":name,"tick":s.tick,"state":v}));
    }
    let document = serde_json::json!({"map_info":s.map_info(),"participant":id,"valid":valid,"invalid":invalid});
    let path = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../client/golden/m13_fact_vectors.json");
    let bytes = serde_json::to_vec_pretty(&document).unwrap();
    if std::env::var_os("FRAGR_UPDATE_M13_FACTS").is_some() {
        std::fs::write(&path, &bytes).unwrap();
    }
    assert!(
        bytes == std::fs::read(path).unwrap(),
        "native M13 fixture changed"
    );
}

#[test]
fn jump_off_returns_and_descent_obstruction_keeps_its_direction() {
    let (mut s, id) = fixture();
    let g = s.map.m13_geometry().unwrap();
    ready_lift(&mut s, id);
    use_target(&mut s, id, g.departure.clone());
    for _ in 0..40 {
        s.tick(0.05);
    }
    s.set_action(
        id,
        Action {
            jump: true,
            ..Default::default()
        },
    );
    s.tick(0.05);
    assert!(s.foundry.as_ref().unwrap().returning);
    assert!(!s.mission_departed());
    // Arrange a second ready living body immediately below the descending deck.
    // This isolates swept descent obstruction after the actual jump request.
    let blocker = Uuid::from_u128(1316);
    s.add_player(blocker, "Descent obstruction".into(), Role::Human);
    assert!(s.acknowledge_mission(
        blocker,
        MissionReady {
            id: MissionId::WeightOfPermission,
            attempt: 1
        }
    ));
    let top = s.foundry.as_ref().unwrap().lift_top;
    place(
        &mut s,
        blocker,
        [0.0, top - 0.3 - crate::movement::BODY_HEIGHT + 0.01, 49.0],
    );
    s.advance_foundry_lift(0.05);
    assert_eq!(s.foundry.as_ref().unwrap().lift_phase, lift::Phase::Blocked);
    assert!(s.foundry.as_ref().unwrap().returning);
    assert_eq!(s.foundry.as_ref().unwrap().lift_top, top);
    s.remove_player(blocker);
    s.advance_foundry_lift(0.05);
    assert!(s.foundry.as_ref().unwrap().lift_top < top);
    assert!(s.foundry.as_ref().unwrap().returning);
}

#[test]
fn foundry_tier_brief_requires_choice_support_and_actual_hazard_receipts() {
    let mut challenge = M13ChallengeState::default();
    assert!(!challenge.brief_completed(CampaignDifficulty::Assisted));
    challenge.workers = Some(M13_WORKER_RESPONSES);
    assert!(challenge.brief_completed(CampaignDifficulty::Assisted));
    assert!(!challenge.brief_completed(CampaignDifficulty::Standard));
    challenge.supports_cleared = true;
    assert!(challenge.brief_completed(CampaignDifficulty::Standard));
    assert!(challenge.brief_completed(CampaignDifficulty::Severe));
    challenge.hazard_hurt = 1;
    assert!(!challenge.brief_completed(CampaignDifficulty::Severe));
    assert!(challenge.brief_completed(CampaignDifficulty::Standard));
}

#[test]
fn foundry_loader_requires_registered_fights_people_and_finite_rocket() {
    let source: serde_json::Value = serde_json::from_slice(include_bytes!(
        "../../../maps/m13-weight-of-permission.json"
    ))
    .unwrap();
    for case in 0..7 {
        let mut bad = source.clone();
        match case {
            0 => {
                bad["encounters"][5]["enemies"]
                    .as_array_mut()
                    .unwrap()
                    .pop();
            }
            1 => bad["encounters"][5]["enemies"][0]["feet"][1] = 0.3.into(),
            2 => bad["encounters"][3]["enemies"][0]["kind"] = "clerk".into(),
            3 => bad["m13"]["connected"]["overseer"] = serde_json::json!([-17.0, 0.3, 8.5]),
            4 => {
                bad["m13"]["connected"]["worker_destinations"][0] =
                    serde_json::json!([-35.0, 0.3, 5.2])
            }
            5 => {
                bad["supplies"]
                    .as_array_mut()
                    .unwrap()
                    .retain(|s| s["id"] != "office_rocket");
            }
            _ => bad["map_id"] = 1014.into(),
        }
        assert!(
            AuthoredMap::read(serde_json::to_vec(&bad).unwrap().as_slice()).is_err(),
            "invalid source case {case}"
        );
    }
}
