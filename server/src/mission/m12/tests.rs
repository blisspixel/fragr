//! Authority fixtures use explicit initial placements; the played route is a separate test.
use super::*;
use crate::maps::{AuthoredMap, AuthoredSource};
use crate::protocol::{Action, CampaignDifficulty, LookAt, MissionReady, Role, WeaponType};
use crate::session::GameSession;
use std::sync::{Arc, OnceLock};
fn map() -> Arc<AuthoredMap> {
    static MAP: OnceLock<Arc<AuthoredMap>> = OnceLock::new();
    MAP.get_or_init(|| {
        AuthoredSource::Mission(MissionId::TermsOfCooperation)
            .load()
            .unwrap()
    })
    .clone()
}
fn fixture() -> (GameSession, Uuid) {
    let mut s = GameSession::with_authored_map(map());
    s.state.seed(1012);
    let id = Uuid::from_u128(1212);
    s.state
        .add_player(id, "Habitat authority fixture".into(), Role::Human);
    assert!(s.state.acknowledge_mission(
        id,
        MissionReady {
            id: MissionId::TermsOfCooperation,
            attempt: 1
        }
    ));
    (s, id)
}
fn place(s: &mut GameSession, id: Uuid, feet: [f32; 3]) {
    let a = s.state.players.iter_mut().find(|p| p.id == id).unwrap();
    [a.x, a.y, a.z] = [feet[0], feet[1] + PLAYER_FLOOR_Y, feet[2]];
    a.vy = 0.0;
    a.clear_input();
}
fn tick(s: &mut GameSession) {
    s.tick_messages(0.05);
    s.state
        .mission_state()
        .unwrap()
        .validate(s.state.tick)
        .unwrap();
}
#[test]
fn m12_canonical_geometry_preserves_pump_indices_and_prepares_real_door_and_aid_routes() {
    let runtime = RuntimeMap::Authored(map());
    let g = runtime.m12_geometry().unwrap();
    assert_eq!(runtime.id(), 1012);
    assert_eq!(g.pumps[0].solids, [88, 89, 90]);
    assert_eq!(g.pumps[1].solids, [92, 93, 94]);
    assert_eq!(g.objectives.len(), 6);
    assert_eq!(g.aid_vehicles.len(), 2);
    for kind in [0, 1] {
        let mut overlap = g.clone();
        let people = if kind == 0 {
            &mut overlap.shelter_people
        } else {
            &mut overlap.workers
        };
        people[1] = people[0];
        assert!(
            overlap
                .validate(
                    runtime.half_extent(),
                    &runtime.arena().solids,
                    runtime.presentation_ref()
                )
                .is_err(),
            "overlapping civilians must also fail the authoritative schema"
        );
    }
    let opened = runtime.prepared_m12_world().unwrap();
    assert!(opened.m12_geometry().unwrap().shelter_open);
    assert_eq!(opened.content_sha256(), runtime.content_sha256());
    assert!(
        runtime.arena().solids[g.shelter_door].top < opened.arena().solids[g.shelter_door].bottom
    );
    for feet in &g.shelter_people {
        assert_ne!(
            runtime
                .navigation()
                .route([0.0, 0.3, -32.0], *feet, crate::navigation::SEARCH_LIMIT)
                .status,
            crate::navigation::RouteStatus::Complete
        );
        assert_eq!(
            opened
                .navigation()
                .route([0.0, 0.3, -32.0], *feet, crate::navigation::SEARCH_LIMIT)
                .status,
            crate::navigation::RouteStatus::Complete
        );
    }
}
#[test]
fn m12_strict_source_rejects_missing_lesson_wrong_roles_and_blocked_aid() {
    let base: serde_json::Value = serde_json::from_slice(include_bytes!(
        "../../../maps/m12-terms-of-cooperation.json"
    ))
    .unwrap();
    let changes = [
        ("/encounters/1/enemies/0/armor", serde_json::json!(0)),
        ("/encounters/2/enemies/3/kind", serde_json::json!("notary")),
        (
            "/m12/aid_vehicles/0/feet",
            serde_json::json!([-7.0, 0.3, 33.0]),
        ),
        (
            "/m12/objectives/0/requires_encounter",
            serde_json::json!("court_defense"),
        ),
        (
            "/m12/shelter_people/0",
            serde_json::json!([0.0, 0.3, -32.0]),
        ),
    ];
    for (pointer, value) in changes {
        let mut broken = base.clone();
        *broken.pointer_mut(pointer).unwrap() = value;
        assert!(
            AuthoredMap::read(serde_json::to_vec(&broken).unwrap().as_slice()).is_err(),
            "{pointer}"
        );
    }
}
#[test]
fn m12_normal_resolved_rays_damage_registered_pump_and_invalid_receipts_do_not() {
    let (mut s, id) = fixture();
    let original = s.state.mission_state().unwrap().m12.unwrap().challenges;
    s.state
        .damage_m12_pump(id, 88, [-4.0, 1.5, 15.0], [0.0, 0.0, -1.0], 25);
    s.state
        .damage_m12_pump(id, 88, [-4.0, 1.5, 16.5], [0.0, 0.0, 0.0], 25);
    s.state
        .damage_m12_pump(Uuid::nil(), 88, [-4.0, 1.5, 16.5], [0.0, 0.0, -1.0], 25);
    assert_eq!(
        s.state.mission_state().unwrap().m12.unwrap().challenges,
        original
    );
    place(&mut s, id, [-4.0, 0.3, 14.0]);
    s.state
        .players
        .iter_mut()
        .find(|p| p.id == id)
        .unwrap()
        .inventory
        .grant_weapon(WeaponType::Tack);
    s.state.set_action(
        id,
        Action {
            weapon_swap: Some(WeaponType::Tack),
            look_at: Some(LookAt {
                x: Some(-4.0),
                y: Some(1.5),
                z: Some(16.5),
                player_id: None,
            }),
            fire: true,
            ..Action::default()
        },
    );
    tick(&mut s);
    let c = s.state.mission_state().unwrap().m12.unwrap().challenges;
    assert!(c.pump_health[0] < 100);
    assert_eq!(c.pump_health[1], 100);
    assert_eq!(c.first_pump_damage_at, Some(s.state.tick));
    assert!(s
        .state
        .shot_results
        .iter()
        .filter_map(|r| r.trace.as_ref())
        .any(
            |t| matches!(t.impact, crate::protocol::ShotImpact::Solid { .. })
                && (t.end[2] - 16.5).abs() < 0.001
        ));
}

fn arrival(s: &mut GameSession, id: Uuid, index: usize) {
    let MissionObjectiveAction::Arrival { feet, .. } =
        s.state.map.m12_geometry().unwrap().objectives[index].action
    else {
        panic!("arrival");
    };
    place(s, id, feet);
    tick(s);
}
fn clear_group(s: &mut GameSession, index: usize) {
    // Terminal HP fixtures isolate mission ordering and never establish a fought-clear claim.
    for definition in s.state.map.encounters()[index].enemies.clone() {
        let a = s
            .state
            .players
            .iter_mut()
            .find(|p| p.name == definition.id)
            .expect("group must actually be placed");
        a.hp = 0;
        s.state
            .encounters
            .hit(a.id, [a.x, a.y - PLAYER_FLOOR_Y, a.z], s.state.tick, true);
    }
    tick(s);
    tick(s);
    assert!(s.state.encounters.is_complete(index));
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
    tick(s);
}
fn through_court(s: &mut GameSession, id: Uuid) {
    arrival(s, id, 0);
    clear_group(s, 0);
    arrival(s, id, 0);
    arrival(s, id, 1);
    clear_group(s, 1);
    s.state
        .players
        .iter_mut()
        .find(|p| p.id == id)
        .unwrap()
        .inventory
        .grant_weapon(WeaponType::Arc);
    arrival(s, id, 1);
    arrival(s, id, 2);
    clear_group(s, 2);
    arrival(s, id, 2);
    arrival(s, id, 3);
    clear_group(s, 3);
    arrival(s, id, 3);
    assert_eq!(
        s.state
            .mission_state()
            .unwrap()
            .m12
            .unwrap()
            .completed
            .len(),
        4
    );
}
#[test]
fn m12_shared_facts_match_the_client_vectors_and_optional_briefs() {
    let vectors: Vec<serde_json::Value> = serde_json::from_slice(include_bytes!(
        "../../../../client/golden/m12_fact_vectors.json"
    ))
    .unwrap();
    assert_eq!(vectors.len(), 31);
    for vector in vectors {
        let valid = serde_json::from_value::<M12ObjectiveState>(vector["state"].clone())
            .and_then(|f| {
                let phase = serde_json::from_value(vector["phase"].clone())?;
                Ok(f.validate(phase, vector["tick"].as_u64().unwrap()).is_ok())
            })
            .unwrap_or(false);
        assert_eq!(
            valid,
            vector["valid"].as_bool().unwrap(),
            "{}",
            vector["id"]
        );
        if let Some(briefs) = vector["briefs"].as_object() {
            let f: M12ObjectiveState = serde_json::from_value(vector["state"].clone()).unwrap();
            for (difficulty, result) in briefs {
                assert_eq!(
                    f.challenges.brief_completed(
                        serde_json::from_value(serde_json::json!(difficulty)).unwrap()
                    ),
                    result.as_bool().unwrap(),
                    "{} / {difficulty}",
                    vector["id"]
                );
            }
        }
    }
}
#[test]
fn m12_authority_requires_order_actual_arc_and_four_separate_encounter_clears() {
    let (mut s, id) = fixture();
    for _ in 0..20 {
        tick(&mut s);
    }
    assert_eq!(
        s.state
            .players
            .iter()
            .filter(|p| p
                .campaign
                .is_some_and(|c| matches!(c, CampaignActor::Union { .. })))
            .count(),
        4,
        "future groups remain unplaced"
    );
    let g = s.state.map.m12_geometry().unwrap();
    use_target(&mut s, id, &g.commitment, true);
    assert!(s
        .state
        .mission_state()
        .unwrap()
        .m12
        .unwrap()
        .completed
        .is_empty());
    arrival(&mut s, id, 0);
    clear_group(&mut s, 0);
    arrival(&mut s, id, 0);
    // Refuse this fixture's pickup so ordinary arrival does not legitimately find it.
    s.state
        .pickups
        .iter_mut()
        .find(|p| p.id == "bay_arc")
        .unwrap()
        .available = false;
    arrival(&mut s, id, 1);
    clear_group(&mut s, 1);
    arrival(&mut s, id, 1);
    assert_eq!(
        s.state
            .mission_state()
            .unwrap()
            .m12
            .unwrap()
            .completed
            .len(),
        1,
        "clearing the bay cannot invent finding Arc"
    );
    s.state
        .players
        .iter_mut()
        .find(|p| p.id == id)
        .unwrap()
        .inventory
        .grant_weapon(WeaponType::Arc);
    tick(&mut s);
    assert_eq!(
        s.state
            .mission_state()
            .unwrap()
            .m12
            .unwrap()
            .completed
            .len(),
        2
    );
    use_target(&mut s, id, &g.worker_release, true);
    assert!(
        !s.state
            .mission_state()
            .unwrap()
            .m12
            .unwrap()
            .challenges
            .workers_released,
        "greenhouse route not secured"
    );
}
#[test]
fn m12_real_aid_waits_for_empty_footprints_then_unlocks_actual_stock_and_fresh_use() {
    let (mut s, id) = fixture();
    through_court(&mut s, id);
    let g = s.state.map.m12_geometry().unwrap();
    assert!(s.state.vehicles.is_empty());
    for supply in s.state.pickups.iter().filter(|p| p.id.starts_with("aid_")) {
        assert!(!supply.available);
    }
    let blocker = Uuid::from_u128(1213);
    s.state
        .add_player(blocker, "Aid footprint blocker".into(), Role::Human);
    assert!(s.state.acknowledge_mission(
        blocker,
        MissionReady {
            id: MissionId::TermsOfCooperation,
            attempt: 1
        }
    ));
    place(&mut s, blocker, g.aid_vehicles[0].feet);
    arrival(&mut s, id, 4);
    assert!(s.state.vehicles.is_empty());
    assert_eq!(
        s.state
            .mission_state()
            .unwrap()
            .m12
            .unwrap()
            .completed
            .len(),
        4
    );
    place(&mut s, blocker, [0.0, 0.3, 28.0]);
    arrival(&mut s, id, 4);
    let facts = s.state.mission_state().unwrap().m12.unwrap();
    assert_eq!(facts.completed.len(), 5);
    assert_eq!(facts.aid_vehicle_ids.len(), 2);
    assert_eq!(s.state.vehicles.len(), 2);
    for (vehicle, placement) in s.state.vehicles.iter().zip(g.aid_vehicles) {
        assert!(facts.aid_vehicle_ids.contains(&vehicle.state.id));
        assert_eq!(vehicle.state.position, placement.feet);
    }
    assert_eq!(
        s.state
            .pickups
            .iter()
            .filter(|p| p.id.starts_with("aid_") && p.available)
            .count(),
        3
    );
    use_target(&mut s, id, &g.commitment, false);
    assert_eq!(
        s.state
            .mission_state()
            .unwrap()
            .m12
            .unwrap()
            .completed
            .len(),
        5
    );
    use_target(&mut s, id, &g.commitment, true);
    assert_eq!(
        s.state
            .mission_state()
            .unwrap()
            .m12
            .unwrap()
            .completed
            .len(),
        6
    );
    use_target(&mut s, id, &g.departure, false);
    use_target(&mut s, id, &g.departure, true);
    assert_eq!(
        s.state.mission_state().unwrap().phase,
        MissionPhase::InProgress,
        "fresh whole party must physically board"
    );
    place(&mut s, blocker, [0.0, 0.3, 32.0]);
    s.state
        .players
        .iter_mut()
        .find(|p| p.id == blocker)
        .unwrap()
        .hp = 0;
    use_target(&mut s, id, &g.departure, false);
    use_target(&mut s, id, &g.departure, true);
    assert_eq!(
        s.state.mission_state().unwrap().phase,
        MissionPhase::InProgress,
        "a dead boarding member cannot depart"
    );
    s.state
        .players
        .iter_mut()
        .find(|p| p.id == blocker)
        .unwrap()
        .hp = 100;
    use_target(&mut s, id, &g.departure, false);
    use_target(&mut s, id, &g.departure, true);
    assert_eq!(
        s.state.mission_state().unwrap().phase,
        MissionPhase::Departed
    );
    assert_eq!(
        s.state
            .mission_state()
            .unwrap()
            .m12
            .unwrap()
            .completed
            .len(),
        7
    );
    assert!(
        !s.state
            .mission_state()
            .unwrap()
            .m12
            .unwrap()
            .challenges
            .workers_released,
        "optional workers do not gate departure"
    );
}
#[test]
fn m12_optional_shelter_is_a_real_world_change_and_civilians_obey_lifecycle() {
    let (mut s, id) = fixture();
    let g = s.state.map.m12_geometry().unwrap();
    let mut bodies = Vec::new();
    s.state.append_civilian_contacts(&mut bodies);
    assert_eq!(bodies.len(), 6);
    for (kind, people) in [
        ("shelter_people", &g.shelter_people),
        ("workers", &g.workers),
    ] {
        for (index, feet) in people.iter().enumerate() {
            assert!(bodies.iter().any(|b| b.key == format!("m12/{kind}/{index}")
                && [b.from.x, b.from.y, b.from.z] == *feet));
        }
    }
    use_target(&mut s, id, &g.shelter_release, true);
    assert!(!s.state.map.m12_geometry().unwrap().shelter_open);
    through_court(&mut s, id);
    use_target(&mut s, id, &g.shelter_release, false);
    use_target(&mut s, id, &g.shelter_release, true);
    assert!(s.state.map.m12_geometry().unwrap().shelter_open);
    let facts = s.state.mission_state().unwrap().m12.unwrap();
    assert!(facts.challenges.shelter_opened);
    assert_eq!(facts.completed.len(), 4);
    use_target(&mut s, id, &g.worker_release, false);
    use_target(&mut s, id, &g.worker_release, true);
    assert!(
        s.state
            .mission_state()
            .unwrap()
            .m12
            .unwrap()
            .challenges
            .workers_released
    );
    s.state.mission.as_mut().unwrap().phase = MissionPhase::Departed;
    bodies.clear();
    s.state.append_civilian_contacts(&mut bodies);
    assert!(bodies.is_empty());
}
#[test]
fn m12_blast_uses_nearest_registered_part_keeps_cover_and_accepts_out_of_order_unique_serials() {
    let (mut s, id) = fixture();
    let arena = s.state.current_arena().into_owned();
    s.state
        .note_m12_blast(100, id, [-4.0, 1.5, 15.5], 3.0, 30.0, &arena);
    // The low feed, not the tower front, is nearest: sqrt(.45^2+.35^2) m.
    let health = s
        .state
        .mission_state()
        .unwrap()
        .m12
        .unwrap()
        .challenges
        .pump_health[0];
    assert_eq!(health, 76);
    s.state
        .note_m12_blast(100, id, [-4.0, 1.5, 15.5], 3.0, 30.0, &arena);
    assert_eq!(
        s.state
            .mission_state()
            .unwrap()
            .m12
            .unwrap()
            .challenges
            .pump_health[0],
        health
    );
    s.state
        .note_m12_blast(99, id, [-4.0, 1.5, 15.5], 3.0, 30.0, &arena);
    assert_eq!(
        s.state
            .mission_state()
            .unwrap()
            .m12
            .unwrap()
            .challenges
            .pump_health[0],
        52
    );
    let mut covered = arena.clone();
    covered.solids.push(Solid {
        min_x: -8.0,
        max_x: 0.0,
        min_z: 15.8,
        max_z: 16.1,
        bottom: 0.3,
        top: 7.0,
    });
    covered.solids.push(Solid {
        min_x: -4.3,
        max_x: -4.2,
        min_z: 12.0,
        max_z: 15.8,
        bottom: 0.3,
        top: 7.0,
    });
    s.state
        .note_m12_blast(101, id, [-4.0, 1.5, 15.5], 3.0, 30.0, &covered);
    assert_eq!(
        s.state
            .mission_state()
            .unwrap()
            .m12
            .unwrap()
            .challenges
            .pump_health[0],
        52
    );
}
#[test]
fn m12_challenge_chronology_same_tick_damage_fails_severe_without_gating_departure() {
    let mut c = M12ChallengeState {
        shelter_route_secured_at: Some(100),
        ..M12ChallengeState::default()
    };
    assert!(c.brief_completed(CampaignDifficulty::Assisted));
    assert!(!c.brief_completed(CampaignDifficulty::Standard));
    c.assessor_wreck_union_kills = 1;
    assert!(c.brief_completed(CampaignDifficulty::Severe));
    c.pump_health[0] = 99;
    c.first_pump_damage_at = Some(100);
    assert!(!c.brief_completed(CampaignDifficulty::Severe));
    c.first_pump_damage_at = Some(101);
    c.validate(101).unwrap();
    assert!(c.brief_completed(CampaignDifficulty::Severe));
    let mut malformed = serde_json::to_value(c).unwrap();
    malformed["first_pump_damage_at"] = serde_json::Value::Null;
    assert!(serde_json::from_value::<M12ChallengeState>(malformed).is_err());
}

fn wreck_fixture(covered: bool) -> (GameSession, Uuid, Uuid, Uuid) {
    let mut document: serde_json::Value = serde_json::from_slice(include_bytes!(
        "../../../maps/m12-terms-of-cooperation.json"
    ))
    .unwrap();
    // Fixed squad positions and low starting HP isolate the wreck outcome.
    // No killed fact or challenge count is injected.
    for enemy in document["encounters"][2]["enemies"]
        .as_array_mut()
        .unwrap()
        .iter_mut()
        .take(3)
    {
        enemy["seated"] = serde_json::json!(true);
    }
    if covered {
        document["encounters"][2]["enemies"][0]["feet"] = serde_json::json!([16.7, 0.3, 6.5]);
        document["solids"].as_array_mut().unwrap().push(serde_json::json!({"id":"wreck_cover_control","min":[17.3,0.3,5.4],"max":[17.4,2.7,7.6],"surface":"enamel"}));
    }
    let map = AuthoredMap::read(serde_json::to_vec(&document).unwrap().as_slice()).unwrap();
    let mut s = GameSession::with_authored_map(map);
    let id = Uuid::from_u128(1214);
    s.state
        .add_player(id, "Wreck receipt fixture".into(), Role::Human);
    assert!(s.state.acknowledge_mission(
        id,
        MissionReady {
            id: MissionId::TermsOfCooperation,
            attempt: 1
        }
    ));
    arrival(&mut s, id, 0);
    clear_group(&mut s, 0);
    arrival(&mut s, id, 0);
    s.state
        .pickups
        .iter_mut()
        .find(|p| p.id == "bay_arc")
        .unwrap()
        .available = false;
    arrival(&mut s, id, 1);
    clear_group(&mut s, 1);
    arrival(&mut s, id, 2);
    let owner = s
        .state
        .players
        .iter()
        .find(|p| p.name == "greenhouse_assessor")
        .unwrap()
        .id;
    let victim = s
        .state
        .players
        .iter()
        .find(|p| p.name == "greenhouse_clerk_west")
        .unwrap()
        .id;
    s.state
        .players
        .iter_mut()
        .find(|p| p.id == victim)
        .unwrap()
        .hp = 1;
    let drone = s.state.players.iter_mut().find(|p| p.id == owner).unwrap();
    drone.hp = 0;
    let feet = [drone.x, drone.y - PLAYER_FLOOR_Y, drone.z];
    s.state.encounters.hit(owner, feet, s.state.tick, true);
    (s, id, owner, victim)
}
#[test]
fn m12_actual_supported_identified_wreck_counts_only_its_resolved_registered_deaths() {
    let (mut s, id, owner, victim) = wreck_fixture(false);
    let mut actual = None;
    assert_eq!(
        s.state
            .mission_state()
            .unwrap()
            .m12
            .unwrap()
            .completed
            .len(),
        1,
        "real wreck may precede Arc discovery"
    );
    // Other-group deaths and living alleged victims cannot mint an outcome.
    let other = s
        .state
        .players
        .iter()
        .find(|p| p.name == "market_clerk_left")
        .unwrap()
        .id;
    s.state
        .note_m12_assessor_wreck(Uuid::nil(), 20, &[other, victim]);
    assert_eq!(
        s.state
            .mission_state()
            .unwrap()
            .m12
            .unwrap()
            .challenges
            .assessor_wreck_union_kills,
        0
    );
    for _ in 0..80 {
        tick(&mut s);
        if let Some(blast) = s
            .state
            .snapshot()
            .explosions
            .iter()
            .find(|b| b.owner_id == owner && b.radius == 1.5)
        {
            assert!(blast.hits.iter().any(|h| h.target_id == victim && h.killed));
            actual = Some(blast.id);
            break;
        }
    }
    let serial = actual.expect("actual supported fall must resolve a wreck");
    let before = s.state.mission_state().unwrap().m12.unwrap().challenges;
    assert_eq!(before.assessor_wreck_union_kills, 1);
    assert_eq!(before.pump_health, [100, 100]);
    assert!(s.state.encounters.registered_in_group(victim, 2));
    assert!(matches!(
        s.state
            .players
            .iter()
            .find(|p| p.id == victim)
            .unwrap()
            .campaign,
        Some(CampaignActor::Union {
            phase: crate::protocol::EnemyPhase::Dead,
            ..
        })
    ));
    s.state
        .note_m12_assessor_wreck(owner, serial, &[victim, victim, other, id]);
    assert_eq!(
        s.state.mission_state().unwrap().m12.unwrap().challenges,
        before,
        "duplicate, participant and other-group ids never inflate the one wreck"
    );
}
#[test]
fn m12_covered_wreck_and_unresolved_death_cannot_award_the_squad_brief() {
    let (mut s, _, owner, victim) = wreck_fixture(true);
    let mut landed = false;
    for _ in 0..80 {
        tick(&mut s);
        if let Some(blast) = s
            .state
            .snapshot()
            .explosions
            .iter()
            .find(|b| b.owner_id == owner && b.radius == 1.5)
        {
            assert!(!blast.hits.iter().any(|h| h.target_id == victim && h.killed));
            landed = true;
            break;
        }
    }
    assert!(landed);
    assert_eq!(
        s.state.players.iter().find(|p| p.id == victim).unwrap().hp,
        1
    );
    let facts = s.state.mission_state().unwrap().m12.unwrap();
    assert_eq!(facts.challenges.assessor_wreck_union_kills, 0);
    assert!(!facts
        .challenges
        .brief_completed(CampaignDifficulty::Standard));
}
#[test]
fn m12_party_reset_restores_shelter_pumps_aid_and_stock_without_rewinding_tick_or_serial() {
    let (mut s, id) = fixture();
    through_court(&mut s, id);
    let g = s.state.map.m12_geometry().unwrap();
    use_target(&mut s, id, &g.shelter_release, false);
    use_target(&mut s, id, &g.shelter_release, true);
    s.state
        .damage_m12_pump(id, 88, [-4.0, 1.5, 16.5], [0.0, 0.0, -1.0], 20);
    arrival(&mut s, id, 4);
    assert_eq!(s.state.vehicles.len(), 2);
    let tick = s.state.tick;
    let serial = s.state.current_projectile_serial();
    s.state.remove_player(id);
    assert_eq!(s.state.tick, tick);
    assert_eq!(s.state.current_projectile_serial(), serial);
    assert!(!s.state.map.m12_geometry().unwrap().shelter_open);
    assert!(s.state.vehicles.is_empty());
    assert!(s
        .state
        .pickups
        .iter()
        .filter(|p| p.id.starts_with("aid_"))
        .all(|p| !p.available));
    let facts = s.state.mission_state().unwrap().m12.unwrap();
    assert!(facts.completed.is_empty());
    assert_eq!(facts.challenges, M12ChallengeState::default());
    assert!(facts.aid_vehicle_ids.is_empty());
}

#[test]
fn m12_natural_health_squad_wreck_brief_uses_only_finite_resolved_input_after_controlled_entry() {
    let (mut s, id) = fixture();
    s.state.arm_joined_magazines(id);
    // Initial player placements and prerequisite HP clears isolate this one
    // challenge. The squad keeps natural authored HP, positions and controllers.
    for supply in [
        "arrival_pistol",
        "arrival_armor",
        "arrival_rifle",
        "arrival_bullets",
    ] {
        let p = s.state.pickups.iter().find(|p| p.id == supply).unwrap();
        let feet = [p.x, p.floor, p.z];
        place(&mut s, id, feet);
        tick(&mut s);
    }
    arrival(&mut s, id, 0);
    clear_group(&mut s, 0);
    arrival(&mut s, id, 0);
    arrival(&mut s, id, 1);
    clear_group(&mut s, 1);
    arrival(&mut s, id, 1);
    place(&mut s, id, [12.0, 0.3, 7.0]);
    tick(&mut s);
    let owner = s
        .state
        .players
        .iter()
        .find(|p| p.name == "greenhouse_assessor")
        .unwrap()
        .id;
    let victim = s
        .state
        .players
        .iter()
        .find(|p| p.name == "greenhouse_clerk_west")
        .unwrap()
        .id;
    assert_eq!(
        s.state.players.iter().find(|p| p.id == victim).unwrap().hp,
        60
    );
    let mut resolved = false;
    let start = s.state.tick;
    for _ in 0..400 {
        let snapshot = s.state.snapshot();
        let me = snapshot.players.iter().find(|p| p.id == id).unwrap();
        assert!(
            me.hp > 0,
            "ordinary finite challenge input died at {}",
            snapshot.tick
        );
        let squad = snapshot
            .players
            .iter()
            .find(|p| p.id == victim)
            .unwrap_or_else(|| {
                panic!(
                    "natural victim retired before wreck at {}, facts {:?}",
                    snapshot.tick,
                    s.state.mission_state().unwrap().m12
                )
            });
        let drone=snapshot.players.iter().find(|p|p.id==owner).unwrap_or_else(||panic!("drone retired without wreck kill at {}, victim HP{} at [{},{},{}], human [{},{},{}], facts {:?}",snapshot.tick,squad.hp,squad.x,squad.y,squad.z,me.x,me.y,me.z,s.state.mission_state().unwrap().m12));
        // Three ordinary 18-damage Arc hits leave six HP, enough for the
        // smallest uncovered landing hit after the living guard's own shuffle.
        let target = if squad.hp > 6 { squad } else { drone };
        let weapon = WeaponType::Arc;
        let point = [
            target.x,
            target.y - PLAYER_FLOOR_Y + crate::combat::target_height(target.campaign) * 0.5,
            target.z,
        ];
        let player = s.state.players.iter().find(|p| p.id == id).unwrap();
        let loadout = player
            .inventory
            .state(id, player.weapon, snapshot.tick)
            .unwrap();
        assert!(loadout.owns(weapon));
        let mut action = Action {
            weapon_swap: Some(weapon),
            look_at: Some(LookAt {
                x: Some(point[0]),
                y: Some(point[1]),
                z: Some(point[2]),
                player_id: None,
            }),
            fire: target.hp > 0,
            left: (snapshot.tick / 12).is_multiple_of(2),
            right: !(snapshot.tick / 12).is_multiple_of(2),
            ..Action::default()
        };
        if loadout.shots(weapon) == Some(0) {
            action.fire = false;
            action.reload = snapshot.tick.is_multiple_of(2);
        }
        s.state.set_action(id, action);
        tick(&mut s);
        for blast in &s.state.snapshot().explosions {
            if blast.owner_id == owner {
                println!("natural challenge blast: {:?}", blast);
            }
        }
        if s.state.snapshot().explosions.iter().any(|b| {
            b.owner_id == owner && b.hits.iter().any(|h| h.target_id == victim && h.killed)
        }) {
            resolved = true;
            break;
        }
    }
    let facts = s.state.mission_state().unwrap().m12.unwrap();
    assert!(
        resolved,
        "natural squad must actually die from the supported wreck, not a receipt fixture"
    );
    assert_eq!(facts.challenges.assessor_wreck_union_kills, 1);
    let player = s.state.players.iter().find(|p| p.id == id).unwrap();
    let loadout = player
        .inventory
        .state(id, player.weapon, s.state.tick)
        .unwrap();
    let record = s.state.player_record(id).unwrap();
    assert_eq!(record.total.deaths, 0);
    assert!(record.total.weapons[WeaponType::Arc.index()].attacks >= 17);
    println!("M12 natural-squad finite challenge: {} ticks, one actual supported wreck victim, {} Flechette shots, {} Arc shots, {} Cells remaining, {} HP/{} armor lost; prerequisite encounter entry is controlled",s.state.tick-start,record.total.weapons[WeaponType::Flechette.index()].attacks,record.total.weapons[WeaponType::Arc.index()].attacks,loadout.ammo(crate::protocol::AmmoPool::Cells),record.total.hp_lost,record.total.armor_lost);
}
