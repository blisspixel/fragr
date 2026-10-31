use super::*;
use crate::maps::AuthoredMap;
use crate::protocol::{
    Action, CampaignActor, ControlDomain, LookAt, M18ObjectiveState, Role, UseTarget,
    M18_HEADS_TURN_TICKS, M18_LATCH_LOOKS_TICKS, M18_TURN_TICKS,
};
use crate::session::GameSession;
use std::sync::{Arc, OnceLock};

const MAP: &str = include_str!("../../../maps/m18-all-systems-normal.json");

fn map() -> Arc<AuthoredMap> {
    static MAP_CACHE: OnceLock<Arc<AuthoredMap>> = OnceLock::new();
    MAP_CACHE
        .get_or_init(|| AuthoredMap::read(MAP.as_bytes()).unwrap())
        .clone()
}

fn session() -> (GameSession, Uuid) {
    session_role(Role::Agent)
}

fn session_role(role: Role) -> (GameSession, Uuid) {
    let mut s = GameSession::with_authored_map(map());
    s.state.use_replay_ids();
    s.state.seed(1018);
    let id = Uuid::from_u128(1018);
    s.state.add_player(id, "Coalition operative".into(), role);
    if role == Role::Human {
        s.state.arm_joined_magazines(id);
    }
    assert!(s.state.acknowledge_mission(
        id,
        MissionReady {
            id: MissionId::AllSystemsNormal,
            attempt: 1,
        }
    ));
    (s, id)
}

fn tick(s: &mut GameSession) {
    s.tick_messages(0.05);
    let map = &s.state.map;
    crate::protocol::validate_decorations(
        &map.presentation_ref().unwrap().decorations,
        &map.arena().solids,
    )
    .unwrap();
    let mut reader = MissionClient::default();
    reader
        .replace_map_with_id(
            map.id(),
            None,
            false,
            None,
            map.half_extent(),
            &map.arena().solids,
            map.presentation_ref(),
        )
        .unwrap();
    reader
        .replace_map_with_m18(
            map.m18_geometry().as_ref(),
            map.half_extent(),
            &map.arena().solids,
            map.presentation_ref(),
        )
        .unwrap();
    reader
        .observe(s.state.tick, s.state.mission_state().unwrap())
        .unwrap();
    s.state
        .mission_state()
        .unwrap()
        .validate(s.state.tick)
        .unwrap();
}

fn place(s: &mut GameSession, id: Uuid, feet: [f32; 3]) {
    let p = s.state.players.iter_mut().find(|p| p.id == id).unwrap();
    [p.x, p.y, p.z] = [feet[0], feet[1] + PLAYER_FLOOR_Y, feet[2]];
    p.vy = 0.0;
    p.clear_input();
}

fn interact(s: &mut GameSession, id: Uuid, target: &UseTarget) {
    let point = target
        .point(
            s.state.map.presentation_ref().unwrap(),
            &s.state.map.arena().solids,
        )
        .unwrap();
    place(s, id, target.approach);
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
    tick(s);
}

fn clear_enemies(s: &mut GameSession) {
    for i in 0..s.state.players.len() {
        let p = &s.state.players[i];
        if !p.is_participant() && p.hp > 0 {
            let damage = p.hp + p.armor;
            s.state.environmental_self_damage(i, damage);
        }
    }
}

#[test]
fn collector_rubble_waits_for_solo_and_party_bodies_to_walk_clear() {
    for paired in [false, true] {
        let (mut s, id) = session_role(Role::Human);
        tick(&mut s);
        let g = s.state.map.m18_geometry().unwrap();
        interact(&mut s, id, &g.depot_station);
        clear_enemies(&mut s);
        place(&mut s, id, [-35.0, 0.0, 0.0]);
        tick(&mut s);
        tick(&mut s);
        clear_enemies(&mut s);
        let occupying = if paired {
            let partner = Uuid::from_u128(1819);
            s.state
                .add_player(partner, "Rubble partner".into(), Role::Human);
            assert!(s.state.acknowledge_mission(
                partner,
                MissionReady {
                    id: MissionId::AllSystemsNormal,
                    attempt: 1
                }
            ));
            place(&mut s, id, [-14.0, 0.0, 0.0]);
            partner
        } else {
            id
        };
        place(&mut s, occupying, [-8.0, 0.1, 0.0]);
        let intact = s.state.map.clone();
        for _ in 0..4 {
            tick(&mut s);
        }
        assert_eq!(
            s.state.map, intact,
            "a living body refuses the whole collision change"
        );
        assert!(
            !s.state
                .mission_state()
                .unwrap()
                .m18
                .unwrap()
                .roadblock_active
        );
        // Leave the slab through the ordinary walking action, without relocation.
        s.state.set_action(
            occupying,
            Action {
                forward: true,
                yaw: Some(std::f32::consts::PI),
                ..Default::default()
            },
        );
        for _ in 0..30 {
            tick(&mut s);
        }
        let state = s.state.mission_state().unwrap().m18.unwrap();
        assert!(state.roadblock_active);
        assert_eq!(state.completed.len(), 3);
        for p in s.state.players.iter().filter(|p| p.is_participant()) {
            let feet = p.y - PLAYER_FLOOR_Y;
            assert!(p.hp > 0);
            assert!(!s.state.map.arena().blocked_body_at(p.x, p.z, feet, feet));
        }
    }
}

#[test]
fn recovery_lifecycle_progresses_from_checkin_to_departure() {
    let (mut s, id) = session();
    tick(&mut s);
    let state = s.state.mission_state().unwrap();
    let m18 = state.m18.unwrap();
    assert_eq!(m18.completed.len(), 0);
    assert_eq!(m18.current.as_ref().unwrap().id, "aid_checkin");
    assert!(!m18.challenges.aid_delivered);
    assert!(!m18.roadblock_active);
    assert!(!m18.overlook_witnessed);
    assert!(!m18.concourse_secured);

    let g = s.state.map.m18_geometry().unwrap();

    // Objective 0: aid_checkin
    interact(&mut s, id, &g.depot_station);
    let m18 = s.state.mission_state().unwrap().m18.unwrap();
    assert_eq!(m18.completed, vec!["aid_checkin"]);
    assert_eq!(m18.current.as_ref().unwrap().id, "square_defense");
    assert!(m18.aid_delivered);
    assert!(m18.challenges.aid_delivered);

    // Objective 1: square_defense
    clear_enemies(&mut s);
    place(&mut s, id, [-35.0, 0.0, 0.0]);
    tick(&mut s);
    let m18 = s.state.mission_state().unwrap().m18.unwrap();
    assert_eq!(m18.completed, vec!["aid_checkin", "square_defense"]);
    assert_eq!(m18.current.as_ref().unwrap().id, "collector_breach");
    assert!(m18.challenges.square_defended);

    // Objective 2: collector_breach
    tick(&mut s);
    clear_enemies(&mut s);
    place(&mut s, id, [-14.0, 0.0, 0.0]);
    tick(&mut s);
    let m18 = s.state.mission_state().unwrap().m18.unwrap();
    assert_eq!(
        m18.completed,
        vec!["aid_checkin", "square_defense", "collector_breach"]
    );
    assert_eq!(m18.current.as_ref().unwrap().id, "service_ascent");
    assert!(m18.roadblock_active);

    // Objective 3: service_ascent
    tick(&mut s);
    clear_enemies(&mut s);
    place(&mut s, id, [18.0, 3.0, 20.0]);
    tick(&mut s);
    let m18 = s.state.mission_state().unwrap().m18.unwrap();
    assert_eq!(
        m18.completed,
        vec![
            "aid_checkin",
            "square_defense",
            "collector_breach",
            "service_ascent"
        ]
    );
    assert_eq!(m18.current.as_ref().unwrap().id, "overlook_recon");

    // Objective 4: overlook_recon
    tick(&mut s);
    clear_enemies(&mut s);
    interact(&mut s, id, &g.overlook_console);
    let m18 = s.state.mission_state().unwrap().m18.unwrap();
    assert_eq!(
        m18.completed,
        vec![
            "aid_checkin",
            "square_defense",
            "collector_breach",
            "service_ascent",
            "overlook_recon"
        ]
    );
    assert_eq!(m18.current.as_ref().unwrap().id, "concourse_evac");
    assert!(m18.overlook_witnessed);
    assert!(m18.challenges.overlook_witnessed);

    // Objective 5: concourse_evac
    tick(&mut s);
    clear_enemies(&mut s);
    place(&mut s, id, [53.0, 4.5, 0.0]);
    tick(&mut s);
    let m18 = s.state.mission_state().unwrap().m18.unwrap();
    assert_eq!(
        m18.completed,
        vec![
            "aid_checkin",
            "square_defense",
            "collector_breach",
            "service_ascent",
            "overlook_recon",
            "concourse_evac"
        ]
    );
    assert_eq!(m18.current.as_ref().unwrap().id, "party_departed");
    assert!(m18.concourse_secured);
    assert!(m18.challenges.concourse_secured);

    // Departure
    interact(&mut s, id, &g.departure);
    assert_eq!(
        s.state.mission.as_ref().unwrap().phase,
        MissionPhase::Departed
    );
    let m18 = s.state.mission_state().unwrap().m18.unwrap();
    assert_eq!(m18.completed.len(), 7);
    assert!(m18.current.is_none());
}

fn hostiles(s: &GameSession) -> Vec<(Uuid, crate::protocol::EnemyKind, ControlDomain, f32)> {
    s.state
        .players
        .iter()
        .filter(|p| p.hp > 0)
        .filter_map(|p| match p.campaign {
            Some(CampaignActor::Hostile { kind, control, .. }) => {
                Some((p.id, kind, control, p.yaw))
            }
            _ => None,
        })
        .collect()
}

fn latch(s: &GameSession) -> &crate::sim::Player {
    s.state
        .players
        .iter()
        .find(|p| p.is_campaign_companion())
        .expect("Latch is with the party in Level 18")
}

fn facts(s: &GameSession) -> M18ObjectiveState {
    s.state.mission_state().unwrap().m18.unwrap()
}

fn angle_between(a: f32, b: f32) -> f32 {
    let d = (a - b).rem_euclid(std::f32::consts::TAU);
    d.min(std::f32::consts::TAU - d)
}

#[test]
fn the_square_works_until_the_delivery_and_then_turns_without_latch() {
    let (mut s, id) = session_role(Role::Human);
    tick(&mut s);
    let g = s.state.map.m18_geometry().unwrap();
    // Latch arrives with the party, beside the depot.
    let start = s.state.map.m18_objectives().unwrap().companion_start;
    let at = latch(&s);
    assert!((at.x - start[0]).hypot(at.z - start[2]) < 0.5);
    // The square is at work. Walking through it does not raise anyone.
    place(&mut s, id, [-32.0, 0.0, 0.0]);
    for _ in 0..40 {
        tick(&mut s);
    }
    assert!(!s.state.encounters.is_awake(0), "nobody works on guard");
    let before = hostiles(&s);
    assert_eq!(before.len(), 5);
    assert!(before.iter().all(|(_, _, c, _)| *c == ControlDomain::Union));
    assert!(facts(&s).turn_started.is_none());
    let hp = s.state.players.iter().find(|p| p.id == id).unwrap().hp;

    interact(&mut s, id, &g.depot_station);
    let started = facts(&s)
        .turn_started
        .expect("the delivery begins the turn");
    assert_eq!(started, s.state.tick);
    assert!(facts(&s).aid_delivered);
    // Everyone stops. Control has not passed yet.
    while s.state.tick < started + M18_HEADS_TURN_TICKS - 1 {
        tick(&mut s);
        assert!(hostiles(&s)
            .iter()
            .all(|(_, _, c, _)| *c == ControlDomain::Union));
    }
    // The heads come round together, toward the overlook, and the machines
    // are the Inheritance's. The supervisor is a person and stays one.
    tick(&mut s);
    tick(&mut s);
    let toward = g.overlook_console.approach;
    for (body, kind, control, yaw) in hostiles(&s) {
        let p = s.state.players.iter().find(|p| p.id == body).unwrap();
        if kind.is_union_machine() {
            assert_eq!(control, ControlDomain::Absorbed, "{kind:?}");
            let bearing = (toward[2] - p.z).atan2(toward[0] - p.x);
            assert!(
                angle_between(yaw, bearing) < 0.05,
                "{kind:?} {yaw} {bearing}"
            );
            let wire = serde_json::to_value(p.campaign.unwrap()).unwrap();
            assert_eq!(wire["side"], "inheritance");
        } else {
            assert_eq!(kind, crate::protocol::EnemyKind::Clerk);
            assert_eq!(control, ControlDomain::Union);
        }
    }
    // Latch does not turn with them: after a beat Latch looks at the party.
    while s.state.tick < started + M18_LATCH_LOOKS_TICKS + 2 {
        tick(&mut s);
    }
    let me = s.state.players.iter().find(|p| p.id == id).unwrap();
    let l = latch(&s);
    let to_me = (me.z - l.z).atan2(me.x - l.x);
    assert!(angle_between(l.yaw, to_me) < 0.05, "{} {to_me}", l.yaw);
    assert!(matches!(l.campaign, Some(CampaignActor::Companion { .. })));
    // Nothing fires while the turn holds.
    while s.state.tick < started + M18_TURN_TICKS - 1 {
        tick(&mut s);
        assert!(!s.state.encounters.is_awake(0));
    }
    assert_eq!(s.state.players.iter().find(|p| p.id == id).unwrap().hp, hp);
    assert!(s.state.m18_latch_quiet(), "no callouts over the turn");
    // Then they move again, together, and the supervisor runs.
    tick(&mut s);
    tick(&mut s);
    assert!(s.state.encounters.is_awake(0));
    let supervisor = hostiles(&s)
        .into_iter()
        .find(|(_, kind, ..)| *kind == crate::protocol::EnemyKind::Clerk)
        .unwrap()
        .0;
    assert!(s.state.encounters.stood_down(supervisor));
    for (body, kind, ..) in hostiles(&s) {
        if kind.is_union_machine() {
            assert!(
                s.state.encounters.aware(body),
                "{kind:?} moves with one purpose"
            );
        }
    }
    // Every machine placed after the turn is the Inheritance's from the start.
    clear_enemies(&mut s);
    place(&mut s, id, [-35.0, 0.0, 0.0]);
    tick(&mut s);
    tick(&mut s);
    assert_eq!(facts(&s).completed.len(), 2);
    let later = hostiles(&s);
    assert_eq!(later.len(), 3, "the clinic route group is placed");
    assert!(later
        .iter()
        .all(|(_, _, c, _)| *c == ControlDomain::Absorbed));
}

#[test]
fn shots_ring_off_the_working_square_and_a_retry_turns_it_again() {
    let (mut s, id) = session_role(Role::Human);
    tick(&mut s);
    let g = s.state.map.m18_geometry().unwrap();
    // Before the delivery the square is at work under a ceasefire: firing on
    // a machine does not wound it and does not raise the square.
    let (sweeper, full) = s
        .state
        .players
        .iter()
        .find(|p| {
            matches!(
                p.campaign,
                Some(CampaignActor::Hostile {
                    kind: crate::protocol::EnemyKind::Sweeper,
                    ..
                })
            )
        })
        .map(|p| (p.id, p.hp))
        .unwrap();
    let at = s.state.players.iter().find(|p| p.id == sweeper).unwrap();
    let target = [at.x, at.y - PLAYER_FLOOR_Y, at.z];
    place(&mut s, id, [target[0] - 4.0, 0.0, target[2]]);
    {
        let me = s.state.players.iter_mut().find(|p| p.id == id).unwrap();
        me.inventory.grant_weapon(crate::protocol::WeaponType::Tack);
        me.inventory
            .grant_ammo(crate::protocol::AmmoPool::Bullets, 60);
        me.weapon = crate::protocol::WeaponType::Tack;
    }
    let mut fired = 0;
    for _ in 0..60 {
        s.state.set_action(
            id,
            Action {
                fire: true,
                look_at: Some(LookAt {
                    player_id: Some(sweeper),
                    ..Default::default()
                }),
                ..Default::default()
            },
        );
        tick(&mut s);
        fired += usize::from(s.state.players.iter().any(|p| p.id == id && p.just_fired));
    }
    assert!(fired > 0, "the participant really fired");
    assert_eq!(
        s.state.players.iter().find(|p| p.id == sweeper).unwrap().hp,
        full
    );
    assert!(
        !s.state.encounters.is_awake(0),
        "a shot does not start the war again"
    );
    assert!(s
        .state
        .players
        .iter()
        .find(|p| p.id == sweeper)
        .and_then(|p| p.campaign)
        .is_some_and(CampaignActor::at_work));
    // Were the square somehow raised (here by hand), the turn still stops it.
    let feet = target;
    s.state.encounters.hit(sweeper, feet, s.state.tick, false);
    tick(&mut s);
    assert!(s.state.encounters.is_awake(0));
    assert!(hostiles(&s)
        .iter()
        .all(|(_, _, c, _)| *c == ControlDomain::Union));
    assert!(facts(&s).turn_started.is_none());
    // The raised square fights: someone commits a tell on the party.
    place(&mut s, id, g.depot_station.approach);
    let telling = |s: &GameSession| {
        s.state.players.iter().any(|p| {
            matches!(
                p.campaign,
                Some(CampaignActor::Hostile {
                    phase: crate::protocol::EnemyPhase::Windup
                        | crate::protocol::EnemyPhase::Firing,
                    ..
                })
            )
        })
    };
    let mut told = false;
    for _ in 0..200 {
        tick(&mut s);
        if telling(&s) {
            told = true;
            break;
        }
    }
    assert!(told, "the raised square attacks before the delivery");
    // The delivery still turns the fight: the same bodies stop and pass.
    interact(&mut s, id, &g.depot_station);
    let started = facts(&s).turn_started.unwrap();
    let hp = s.state.players.iter().find(|p| p.id == id).unwrap().hp;
    // An awake fight stops too: no tell, burst or wound while the turn holds.
    while s.state.tick < started + M18_TURN_TICKS - 1 {
        tick(&mut s);
        assert!(s.state.players.iter().all(|p| !matches!(
            p.campaign,
            Some(CampaignActor::Hostile {
                phase: crate::protocol::EnemyPhase::Windup | crate::protocol::EnemyPhase::Firing,
                ..
            })
        )));
        assert_eq!(s.state.players.iter().find(|p| p.id == id).unwrap().hp, hp);
    }
    assert!(hostiles(&s)
        .iter()
        .filter(|(_, kind, ..)| kind.is_union_machine())
        .all(|(_, _, c, _)| *c == ControlDomain::Absorbed));
    // The whole party falls: the attempt starts over with the square at work
    // under the Union and no turn.
    let index = s.state.players.iter().position(|p| p.id == id).unwrap();
    s.state.environmental_self_damage(index, 500);
    for _ in 0..3 {
        tick(&mut s);
    }
    let reset = facts(&s);
    assert!(reset.completed.is_empty());
    assert!(reset.turn_started.is_none());
    assert!(!s.state.m18_machines_absorbed());
    assert!(hostiles(&s)
        .iter()
        .all(|(_, _, c, _)| *c == ControlDomain::Union));
}

#[test]
fn the_wire_refuses_a_turn_without_its_delivery_or_from_the_future() {
    let (mut s, id) = session();
    tick(&mut s);
    let g = s.state.map.m18_geometry().unwrap();
    interact(&mut s, id, &g.depot_station);
    let mission = s.state.mission_state().unwrap();
    let tick_now = s.state.tick;
    mission.validate(tick_now).unwrap();
    let mut early = mission.clone();
    early.m18.as_mut().unwrap().turn_started = None;
    assert!(
        early.validate(tick_now).is_err(),
        "a delivery always starts the turn"
    );
    let mut future = mission.clone();
    future.m18.as_mut().unwrap().turn_started = Some(tick_now + 1);
    assert!(future.validate(tick_now).is_err());
    // A briefing that already turned is refused too.
    let (fresh, _) = session();
    let mut ghost = fresh.state.mission_state().unwrap();
    ghost.m18.as_mut().unwrap().turn_started = Some(0);
    assert!(ghost.validate(fresh.state.tick).is_err());
    // A map that authors a machine already absorbed is refused: the turn
    // is the only way into Inheritance control in Level 18.
    let mut wrong: serde_json::Value = serde_json::from_str(MAP).unwrap();
    wrong["encounters"][0]["enemies"][1]["control"] = serde_json::json!("absorbed");
    let error = AuthoredMap::read(serde_json::to_vec(&wrong).unwrap().as_slice()).unwrap_err();
    assert!(error.to_string().contains("turn absorbs"), "{error}");
}
