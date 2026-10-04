//! Seeded encounter-boundary checks, separate from ordinary-input playthroughs.
use crate::maps::{AuthoredMap, AuthoredSource};
use crate::protocol::{
    Action, CampaignActor, CampaignDifficulty, EnemyPhase, LookAt, M09ObjectiveState, MissionId,
    MissionObjectiveAction, MissionPhase, MissionReady, Role, ServerMessage,
};
use crate::session::GameSession;
use crate::sim::PLAYER_FLOOR_Y;
use std::sync::{Arc, OnceLock};
use uuid::Uuid;

fn map() -> Arc<AuthoredMap> {
    static MAP: OnceLock<Arc<AuthoredMap>> = OnceLock::new();
    MAP.get_or_init(|| {
        AuthoredSource::Mission(MissionId::PassengerManifest)
            .load()
            .unwrap()
    })
    .clone()
}
fn fixture(difficulty: CampaignDifficulty) -> (GameSession, Uuid) {
    let mut s = GameSession::with_authored_map(map());
    s.state.seed(42);
    s.state.set_campaign_difficulty(difficulty).unwrap();
    let id = Uuid::from_u128(9009);
    s.state.add_player(id, "Visitor".into(), Role::Human);
    assert!(s.state.acknowledge_mission(
        id,
        MissionReady {
            id: MissionId::PassengerManifest,
            attempt: 1
        }
    ));
    // Boundary fixtures explicitly enter the authored loading lane. Readiness
    // alone leaves the actual low-resource mission entry out of combat.
    place(&mut s, id, [-35.0, 0.0, -39.0]);
    advance(&mut s, 1);
    (s, id)
}
fn advance(s: &mut GameSession, ticks: usize) {
    for _ in 0..ticks {
        s.tick_messages(0.05);
    }
}
fn facts(s: &GameSession) -> M09ObjectiveState {
    s.state.mission_state().unwrap().m09.unwrap()
}
fn place(s: &mut GameSession, id: Uuid, feet: [f32; 3]) {
    let p = s.state.players.iter_mut().find(|p| p.id == id).unwrap();
    [p.x, p.y, p.z] = [feet[0], feet[1] + PLAYER_FLOOR_Y, feet[2]];
    p.vy = 0.0;
    p.clear_input();
}
fn clear(s: &mut GameSession, id: Uuid, index: usize) -> Vec<ServerMessage> {
    let g = s.state.map.m09_geometry().unwrap();
    let step = g.step(index).unwrap();
    let feet = match step.action {
        MissionObjectiveAction::Arrival { feet, .. } => feet,
        MissionObjectiveAction::Use { target } => target.approach,
        _ => panic!("berth step"),
    };
    place(s, id, feet);
    advance(s, 1);
    let enemies = s.state.map.encounters()[index].enemies.clone();
    for enemy in enemies {
        let p = s
            .state
            .players
            .iter_mut()
            .find(|p| p.name == enemy.id)
            .expect("eligible current group");
        p.hp = 0;
        s.state
            .encounters
            .hit(p.id, [p.x, p.y - PLAYER_FLOOR_Y, p.z], s.state.tick, true);
    }
    let mut messages = s.tick_messages(0.05);
    messages.extend(s.tick_messages(0.05));
    assert!(s.state.encounters.is_complete(index));
    messages
}
fn use_at(s: &mut GameSession, id: Uuid, crew: bool, press: bool) {
    let g = s.state.map.m09_geometry().unwrap();
    let target = if crew { g.crew_release } else { g.departure };
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
            look_at: Some(LookAt {
                x: Some(point[0]),
                y: Some(point[1]),
                z: Some(point[2]),
                player_id: None,
            }),
            interact: press,
            ..Action::default()
        },
    );
    advance(s, 1);
}

#[test]
fn m09_ordered_crew_use_and_hatch_keep_future_guards_unavailable() {
    let (mut s, id) = fixture(CampaignDifficulty::Standard);
    assert_eq!(
        s.state
            .players
            .iter()
            .filter(|p| p.is_campaign_enemy())
            .count(),
        5
    );
    clear(&mut s, id, 0);
    clear(&mut s, id, 1);
    use_at(&mut s, id, true, true);
    assert!(
        !facts(&s).crew_released,
        "a press before the office clears is consumed"
    );
    clear(&mut s, id, 2);
    assert_eq!(facts(&s).completed.len(), 2);
    assert!(!s
        .state
        .players
        .iter()
        .any(|p| p.name == s.state.map.encounters()[3].enemies[0].id));
    // An actual released edge, not the prior failed press, advances the crew gate.
    use_at(&mut s, id, true, false);
    use_at(&mut s, id, true, true);
    assert!(facts(&s).crew_released);
    assert_eq!(facts(&s).completed.len(), 3);
    assert_eq!(
        facts(&s)
            .crew
            .iter()
            .map(|c| c.id.as_str())
            .collect::<Vec<_>>(),
        ["tern", "berth_crew_a", "berth_crew_b"]
    );
    for index in 3..7 {
        clear(&mut s, id, index);
    }
    assert!(facts(&s).hatch_open);
    assert!(s.state.map.m09_geometry().unwrap().hatch_open);
    assert_eq!(facts(&s).completed.len(), 7);
    assert_eq!(s.state.map.id(), 1009);
}

#[test]
fn m09_departure_requires_final_clear_fresh_use_and_all_ready_living_aboard() {
    let (mut s, id) = fixture(CampaignDifficulty::Standard);
    for index in 0..3 {
        clear(&mut s, id, index);
    }
    use_at(&mut s, id, true, false);
    use_at(&mut s, id, true, true);
    for index in 3..7 {
        clear(&mut s, id, index);
    }
    use_at(&mut s, id, false, true);
    assert!(s.state.mission_state().unwrap().prompts.is_empty());
    clear(&mut s, id, 7);
    use_at(&mut s, id, false, false);
    let peer = Uuid::from_u128(9090);
    s.state.add_player(peer, "Peer".into(), Role::Agent);
    assert!(s.state.mission_state().unwrap().prompts.is_empty());
    assert!(s.state.acknowledge_mission(
        peer,
        MissionReady {
            id: MissionId::PassengerManifest,
            attempt: 1
        }
    ));
    assert!(
        s.state.mission_state().unwrap().prompts.is_empty(),
        "a ready peer outside the ship blocks departure"
    );
    let g = s.state.map.m09_geometry().unwrap();
    place(&mut s, peer, [3.0, 12.0, -26.0]);
    advance(&mut s, 1);
    assert_eq!(s.state.mission_state().unwrap().prompts.len(), 1);
    use_at(&mut s, id, false, true);
    let state = s.state.mission_state().unwrap();
    assert_eq!(state.phase, MissionPhase::Departed);
    state.validate(s.state.tick).unwrap();
    let map = s.state.map.clone();
    let g = map.m09_geometry().unwrap();
    let mut controller = crate::mission::MissionClient::default();
    controller
        .replace_map_with_m09(
            Some(&g),
            map.half_extent(),
            &map.arena().solids,
            map.presentation_ref(),
        )
        .unwrap();
    controller.observe(s.state.tick, state.clone()).unwrap();
    assert_eq!(
        state.m09.unwrap().completed.last().unwrap(),
        "party_departed"
    );
    assert!(g.boarding.contains([3.0, 12.0, -26.0]));
}

#[test]
fn m09_real_lesson_charge_descent_counts_once_without_player_frag() {
    let (mut s, id) = fixture(CampaignDifficulty::Severe);
    clear(&mut s, id, 0);
    place(&mut s, id, [-19.0, 4.0, -31.0]);
    let name = s.state.map.encounters()[1].enemies[0].id.clone();
    let mut told = false;
    for _ in 0..80 {
        advance(&mut s, 1);
        if s.state
            .players
            .iter()
            .find(|p| p.name == name)
            .is_some_and(|p| {
                matches!(
                    p.campaign,
                    Some(CampaignActor::Union {
                        phase: EnemyPhase::Windup,
                        ..
                    })
                )
            })
        {
            told = true;
            break;
        }
    }
    assert!(told, "actual office-landing windup");
    place(&mut s, id, [-19.0, 4.0, -28.0]);
    for _ in 0..120 {
        advance(&mut s, 1);
        if facts(&s).charge_falls == 1 {
            break;
        }
    }
    assert_eq!(facts(&s).charge_falls, 1);
    let enemy = s.state.players.iter().find(|p| p.name == name).unwrap();
    assert_eq!(enemy.hp, 0);
    assert!(enemy.y - PLAYER_FLOOR_Y < 1.5);
    assert_eq!(s.state.scores.get(&id).copied().unwrap_or(0), 0);
    advance(&mut s, 20);
    assert_eq!(facts(&s).charge_falls, 1);
}

#[test]
fn m09_geometry_precedes_facts_and_malformed_order_or_fake_crew_is_refused() {
    let (mut s, id) = fixture(CampaignDifficulty::Standard);
    for index in 0..3 {
        clear(&mut s, id, index);
    }
    use_at(&mut s, id, true, false);
    use_at(&mut s, id, true, true);
    for index in 3..6 {
        clear(&mut s, id, index);
    }
    let messages = clear(&mut s, id, 6);
    let geometry = messages
        .iter()
        .position(|m| matches!(m, ServerMessage::MapInfo { m09: Some(g), .. } if g.hatch_open))
        .expect("actual opened world broadcast");
    let mission = messages.iter().position(
        |m| matches!(m,ServerMessage::Mission{state,..} if state.m09.as_ref().is_some_and(|f|f.hatch_open)),
    ).expect("actual opened mission facts");
    assert!(
        geometry < mission,
        "opened facts cannot overtake their collision world"
    );
    let original = s.state.mission_state().unwrap();
    original.validate(s.state.tick).unwrap();
    for mutate in 0..4 {
        let mut state = original.clone();
        let f = state.m09.as_mut().unwrap();
        match mutate {
            0 => f.crew_released = false,
            1 => f.hatch_open = false,
            2 => f.completed.push("lesson_cleared".into()),
            _ => f.crew[0].id = "union_pilot".into(),
        }
        assert!(state.validate(s.state.tick).is_err());
    }
}

#[test]
fn m09_controller_refuses_stale_world_facts_and_forged_crew_routes() {
    let (mut s, id) = fixture(CampaignDifficulty::Standard);
    let map = s.state.map.clone();
    let g = map.m09_geometry().unwrap();
    let mut client = crate::mission::MissionClient::default();
    client
        .replace_map_with_m09(
            Some(&g),
            map.half_extent(),
            &map.arena().solids,
            map.presentation_ref(),
        )
        .unwrap();
    let mut nav = crate::navigation::Navigator::default();
    let wanted = Action {
        fire: true,
        forward: true,
        throw_grenade: true,
        ..Action::default()
    };
    let before = client.steer(
        &mut nav,
        map.navigation(),
        id,
        &s.state.snapshot(),
        wanted.clone(),
    );
    assert!(!before.fire && !before.forward && !before.throw_grenade);
    let initial = s.state.mission_state().unwrap();
    client.observe(s.state.tick, initial.clone()).unwrap();
    for failure in 0..3 {
        let mut bad = initial.clone();
        let f = bad.m09.as_mut().unwrap();
        match failure {
            0 => f.crew[0].feet[0] += 0.5,
            1 => f.crew[0].feet = g.crew[0].route[5],
            _ => f.current = g.step(1),
        }
        assert!(client.observe(s.state.tick, bad).is_err());
    }
    for index in 0..3 {
        clear(&mut s, id, index);
    }
    use_at(&mut s, id, true, false);
    use_at(&mut s, id, true, true);
    for index in 3..7 {
        clear(&mut s, id, index);
    }
    let opened = s.state.map.clone();
    let opened_g = opened.m09_geometry().unwrap();
    let current = s.state.mission_state().unwrap();
    assert!(
        client.observe(s.state.tick, current.clone()).is_err(),
        "opened facts cannot bind a closed hatch"
    );
    client
        .replace_map_with_id(
            1009,
            None,
            false,
            None,
            opened.half_extent(),
            &opened.arena().solids,
            opened.presentation_ref(),
        )
        .unwrap();
    client
        .replace_map_with_m09(
            Some(&opened_g),
            opened.half_extent(),
            &opened.arena().solids,
            opened.presentation_ref(),
        )
        .unwrap();
    let stale = client.steer(
        &mut nav,
        opened.navigation(),
        id,
        &s.state.snapshot(),
        wanted,
    );
    assert!(
        !stale.fire && !stale.forward && !stale.throw_grenade,
        "MapInfo requires matching fresh mission facts"
    );
    client.observe(s.state.tick, current.clone()).unwrap();
    let mut regressed = current.clone();
    regressed.m09.as_mut().unwrap().charge_falls = 1;
    client.observe(s.state.tick, regressed).unwrap();
    assert!(client.observe(s.state.tick, current.clone()).is_err());
    let mut carry = current;
    carry.m09.as_mut().unwrap().carried_archive =
        Some(crate::protocol::M08Outcome::HistoricalUnrecorded {});
    assert!(
        client.observe(s.state.tick, carry).is_err(),
        "history cannot appear mid attempt"
    );
    let archive = AuthoredSource::Mission(MissionId::CustodianOfRecord)
        .load()
        .unwrap();
    let archive = crate::maps::RuntimeMap::Authored(archive);
    assert!(client
        .replace_map_with_m08(
            archive.m08_geometry().as_ref(),
            archive.half_extent(),
            &archive.arena().solids,
            archive.presentation_ref()
        )
        .is_err());
}

#[test]
fn m09_severe_departure_after_all_resolved_gun_kills_does_not_require_charge_falls() {
    use crate::protocol::{AmmoPool, WeaponType};
    let (mut s, id) = fixture(CampaignDifficulty::Severe);
    // Isolate the completion contract from AI tactics. A finite fixture kit
    // fires real resolved shots at all 21 bodies; no death or fall is seeded.
    let player = s.state.players.iter_mut().find(|p| p.id == id).unwrap();
    player.inventory.grant_weapon(WeaponType::Rail);
    player.inventory.grant_ammo(AmmoPool::Cells, 40);
    let mut resolved_kills = std::collections::HashSet::new();
    for index in 0..8 {
        let g = s.state.map.m09_geometry().unwrap();
        let arrival = g.step(index).unwrap();
        let feet = match arrival.action {
            MissionObjectiveAction::Arrival { feet, .. } => feet,
            MissionObjectiveAction::Use { target } => target.approach,
            _ => panic!("berth step"),
        };
        place(&mut s, id, feet);
        s.state.tick(0.05);
        let names: Vec<_> = s.state.map.encounters()[index]
            .enemies
            .iter()
            .map(|e| e.id.clone())
            .collect();
        for name in names {
            let target = s.state.players.iter().find(|p| p.name == name).unwrap();
            let target_id = target.id;
            let target_eye = [target.x, target.y, target.z];
            let arena = s.state.current_arena().into_owned();
            let approach = [[-4.0, 0.0], [4.0, 0.0], [0.0, -4.0], [0.0, 4.0]]
                .into_iter()
                .find_map(|[dx, dz]| {
                    let x = target_eye[0] + dx;
                    let z = target_eye[2] + dz;
                    let floor = arena.support_height(x, z, target_eye[1]);
                    let feet = [x, floor, z];
                    (!arena.blocked_body_at(x, z, floor, floor)
                        && crate::combat::line_of_sight(
                            [x, floor + crate::movement::EYE_HEIGHT, z],
                            target_eye,
                            &arena.solids,
                        ))
                    .then_some(feet)
                })
                .expect("supported visible isolated firing fixture");
            place(&mut s, id, approach);
            for p in &mut s.state.players {
                if p.is_campaign_enemy() {
                    p.clear_input();
                }
            }
            s.state.set_action(
                id,
                Action {
                    fire: true,
                    weapon_swap: Some(WeaponType::Rail),
                    look_at: Some(LookAt {
                        player_id: Some(target_id),
                        ..LookAt::default()
                    }),
                    ..Action::default()
                },
            );
            for _ in 0..100 {
                s.state.tick(0.05);
                if s.state.shot_results.iter().any(|shot| {
                    shot.shooter_id == id
                        && shot.target_id == Some(target_id)
                        && shot.damage > 0
                        && shot.target_hp_after.is_some_and(|hp| hp <= 0)
                }) {
                    resolved_kills.insert(target_id);
                    break;
                }
            }
            assert!(
                resolved_kills.contains(&target_id),
                "real gunfire did not defeat {name}"
            );
            s.state.set_action(id, Action::default());
        }
        place(&mut s, id, feet);
        s.state.tick(0.05);
        s.state.tick(0.05);
        if index == 2 {
            use_at(&mut s, id, true, false);
            use_at(&mut s, id, true, true);
        }
    }
    assert_eq!(resolved_kills.len(), 21);
    assert_eq!(
        facts(&s).charge_falls,
        0,
        "ordinary gun deaths cannot create optional charge-fall evidence"
    );
    use_at(&mut s, id, false, false);
    let state = s.state.mission_state().unwrap();
    state.validate(s.state.tick).unwrap();
    let map = s.state.map.clone();
    let g = map.m09_geometry().unwrap();
    let mut controller = crate::mission::MissionClient::default();
    controller
        .replace_map_with_m09(
            Some(&g),
            map.half_extent(),
            &map.arena().solids,
            map.presentation_ref(),
        )
        .unwrap();
    controller.observe(s.state.tick, state.clone()).unwrap();
    assert_eq!(
        state.prompts.len(),
        1,
        "the optional challenge cannot hide the real exit"
    );
    use_at(&mut s, id, false, true);
    assert_eq!(
        s.state.mission_state().unwrap().phase,
        MissionPhase::Departed
    );
    assert_eq!(facts(&s).charge_falls, 0);
}
