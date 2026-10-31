use super::*;
use crate::maps::AuthoredMap;
use crate::protocol::{Action, LookAt, Role, UseTarget};
use crate::session::GameSession;
use std::sync::{Arc, OnceLock};

const MAP: &str = include_str!("../../../maps/m17-peace-without-interruption.json");

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
    s.state.seed(1017);
    let id = Uuid::from_u128(1017);
    s.state.add_player(id, "Coalition operative".into(), role);
    if role == Role::Human {
        s.state.arm_joined_magazines(id);
    }
    assert!(s.state.acknowledge_mission(
        id,
        MissionReady {
            id: MissionId::PeaceWithoutInterruption,
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
        .replace_map_with_m17(
            map.m17_geometry().as_ref(),
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
fn office_lifecycle_progresses_from_breach_to_departure() {
    let (mut s, id) = session();
    tick(&mut s);
    let state = s.state.mission_state().unwrap();
    let m17 = state.m17.unwrap();
    assert_eq!(m17.completed.len(), 0);
    assert_eq!(m17.current.as_ref().unwrap().id, "approach_breached");
    assert!(!m17.challenges.approach_breached);
    assert!(!m17.core_unsealed);
    assert!(!m17.voss_captured);
    assert!(!m17.kessel_secured);

    let g = s.state.map.m17_geometry().unwrap();

    // Clear outer approach defenders
    clear_enemies(&mut s);
    tick(&mut s);

    // 0 -> 1: Approach breached (arrive at public hall)
    place(&mut s, id, [0.0, 0.0, -17.0]);
    tick(&mut s);
    let m17 = s.state.mission_state().unwrap().m17.unwrap();
    assert_eq!(m17.completed, vec!["approach_breached"]);
    assert_eq!(m17.current.as_ref().unwrap().id, "hall_secured");
    assert!(m17.challenges.approach_breached);

    // 1 -> 2: Clear public hall defenders
    tick(&mut s);
    clear_enemies(&mut s);
    tick(&mut s);
    let m17 = s.state.mission_state().unwrap().m17.unwrap();
    assert_eq!(m17.completed, vec!["approach_breached", "hall_secured"]);
    assert_eq!(m17.current.as_ref().unwrap().id, "kessel_secured");

    // 2 -> 3: Take Registrar Kessel into custody at committee desk
    interact(&mut s, id, &g.kessel_desk);
    let m17 = s.state.mission_state().unwrap().m17.unwrap();
    assert_eq!(
        m17.completed,
        vec!["approach_breached", "hall_secured", "kessel_secured"]
    );
    assert_eq!(m17.current.as_ref().unwrap().id, "core_unsealed");
    assert!(m17.challenges.kessel_secured);
    assert!(m17.kessel_secured);

    // 3 -> 4: Override security core seal at gallery console
    interact(&mut s, id, &g.core_override);
    let m17 = s.state.mission_state().unwrap().m17.unwrap();
    assert_eq!(
        m17.completed,
        vec![
            "approach_breached",
            "hall_secured",
            "kessel_secured",
            "core_unsealed"
        ]
    );
    assert_eq!(m17.current.as_ref().unwrap().id, "core_defeated");
    assert!(m17.core_unsealed);

    // 4 -> 5: Core defense eliminated
    place(&mut s, id, [0.0, 0.0, 26.0]);
    tick(&mut s);
    clear_enemies(&mut s);
    tick(&mut s);
    let m17 = s.state.mission_state().unwrap().m17.unwrap();
    assert_eq!(
        m17.completed,
        vec![
            "approach_breached",
            "hall_secured",
            "kessel_secured",
            "core_unsealed",
            "core_defeated"
        ]
    );
    assert_eq!(m17.current.as_ref().unwrap().id, "voss_captured");
    assert!(m17.challenges.core_defeated);

    // 5 -> 6: Confront Chancellor Voss at executive rostrum; the coalition
    // comes for her and walks her out.
    interact(&mut s, id, &g.voss_rostrum);
    assert!(facts(&s).custody_started.is_some());
    for _ in 0..400 {
        if facts(&s).voss_captured {
            break;
        }
        tick(&mut s);
    }
    let m17 = s.state.mission_state().unwrap().m17.unwrap();
    assert_eq!(m17.completed.len(), 6);
    assert_eq!(m17.current.as_ref().unwrap().id, "party_departed");
    assert!(m17.voss_captured);
    assert!(m17.challenges.voss_captured);

    // 6 -> Departed: Assemble at later exit
    place(&mut s, id, [24.0, 0.0, 38.0]);
    interact(&mut s, id, &g.departure);
    let state = s.state.mission_state().unwrap();
    assert_eq!(state.phase, MissionPhase::Departed);
    let m17 = state.m17.unwrap();
    assert!(m17.completed.contains(&"party_departed".to_string()));
}

fn current(s: &GameSession) -> String {
    s.state
        .mission_state()
        .unwrap()
        .m17
        .unwrap()
        .current
        .unwrap()
        .id
}

/// Breach the approach and clear the hall, leaving the ring and Kessel open.
fn through_the_hall(s: &mut GameSession, id: Uuid) {
    tick(s);
    clear_enemies(s);
    tick(s);
    place(s, id, [0.0, 0.0, -17.0]);
    tick(s);
    tick(s);
    clear_enemies(s);
    tick(s);
    assert_eq!(current(s), "kessel_secured");
}

#[test]
fn service_stair_reaches_the_galleries_without_skipping_the_ring_or_the_console() {
    let (mut s, id) = session();
    through_the_hall(&mut s, id);
    let g = s.state.map.m17_geometry().unwrap();
    // The runner's line arrives on the east gallery and walks to the console
    // before the ring has fallen or Kessel is in custody: nothing advances,
    // the override refuses and the bulkhead stays shut.
    place(&mut s, id, [-10.0, 3.0, 8.0]);
    tick(&mut s);
    interact(&mut s, id, &g.core_override);
    assert_eq!(current(&s), "kessel_secured");
    let m17 = s.state.mission_state().unwrap().m17.unwrap();
    assert!(!m17.core_unsealed);
    assert_eq!(s.state.map.m17_stage(), 0);

    // The ring fight is the required alternative to Kessel's custody.
    place(&mut s, id, [-30.0, 0.0, -8.0]);
    tick(&mut s);
    clear_enemies(&mut s);
    tick(&mut s);
    assert_eq!(current(&s), "kessel_secured");
    // Standing on the floor beneath the console is not reaching the galleries.
    let below = [
        g.core_override.approach[0],
        0.0,
        g.core_override.approach[2] - 2.0,
    ];
    place(&mut s, id, below);
    tick(&mut s);
    assert_eq!(current(&s), "kessel_secured");
    // Climbing to the console deck is.
    place(&mut s, id, g.core_override.approach);
    tick(&mut s);
    assert_eq!(current(&s), "core_unsealed");
    assert!(!s.state.mission_state().unwrap().m17.unwrap().kessel_secured);
}

#[test]
fn the_override_is_used_on_the_gallery_and_opens_the_bulkhead() {
    let (mut s, id) = session();
    through_the_hall(&mut s, id);
    let g = s.state.map.m17_geometry().unwrap();
    interact(&mut s, id, &g.kessel_desk);
    assert_eq!(current(&s), "core_unsealed");
    // From the floor under the deck the console cannot be worked.
    let point = g
        .core_override
        .point(
            s.state.map.presentation_ref().unwrap(),
            &s.state.map.arena().solids,
        )
        .unwrap();
    place(&mut s, id, [point[0], 0.0, 13.0]);
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
    tick(&mut s);
    assert_eq!(current(&s), "core_unsealed");
    assert_eq!(s.state.map.m17_stage(), 0);
    let bulkhead_shut = |s: &GameSession| {
        s.state
            .map
            .arena()
            .blocked_body_at(-18.25, 19.0, 3.0, 3.0 + crate::movement::BODY_HEIGHT)
    };
    assert!(bulkhead_shut(&s));
    interact(&mut s, id, &g.core_override);
    assert_eq!(current(&s), "core_defeated");
    assert_eq!(s.state.map.m17_stage(), 1);
    assert!(!bulkhead_shut(&s));
}

#[test]
fn latch_follows_the_party_from_the_authored_start() {
    let (mut s, id) = session();
    tick(&mut s);
    let start = s.state.map.m17_objectives().unwrap().companion_start;
    let latch = s
        .state
        .players
        .iter()
        .find(|p| p.is_campaign_companion())
        .expect("Latch is with the party");
    assert!((latch.x - start[0]).hypot(latch.z - start[2]) < 0.5);
    assert!(latch.hp > 0);
    // Latch keeps up with the party on the level's ordinary routes.
    let away = [0.0, 0.0, -30.0];
    let before = (latch.x - away[0]).hypot(latch.z - away[2]);
    place(&mut s, id, away);
    for _ in 0..200 {
        clear_enemies(&mut s);
        tick(&mut s);
    }
    let latch = s
        .state
        .players
        .iter()
        .find(|p| p.is_campaign_companion())
        .unwrap();
    let after = (latch.x - away[0]).hypot(latch.z - away[2]);
    assert!(
        after < before - 1.0 && after < 9.0,
        "Latch follows: {before} -> {after}"
    );
    // A map that puts Latch in a wall is refused.
    let mut wrong: serde_json::Value = serde_json::from_str(MAP).unwrap();
    wrong["m17"]["companion_start"] = serde_json::json!([500.0, 0.0, 0.0]);
    assert!(AuthoredMap::read(serde_json::to_vec(&wrong).unwrap().as_slice()).is_err());
}

fn facts(s: &GameSession) -> crate::protocol::M17ObjectiveState {
    s.state.mission_state().unwrap().m17.unwrap()
}

fn figures(s: &GameSession, kind: crate::protocol::FigureKind) -> Vec<(Uuid, [f32; 3], i32)> {
    s.state
        .players
        .iter()
        .filter(|p| p.campaign == Some(CampaignActor::Figure { kind }))
        .map(|p| (p.id, [p.x, p.y - PLAYER_FLOOR_Y, p.z], p.hp))
        .collect()
}

fn voss(s: &GameSession) -> (Uuid, [f32; 3], i32) {
    let found = figures(s, crate::protocol::FigureKind::Voss);
    assert_eq!(found.len(), 1, "exactly one Voss");
    found[0]
}

fn escort(s: &GameSession) -> Vec<(Uuid, [f32; 3], i32)> {
    figures(s, crate::protocol::FigureKind::Coalition)
}

fn near(a: [f32; 3], b: [f32; 3], within: f32) -> bool {
    (a[0] - b[0]).hypot(a[2] - b[2]) < within
}

/// Drive an attempt through the core fight to the rostrum objective.
fn to_the_rostrum(s: &mut GameSession, id: Uuid) {
    through_the_hall(s, id);
    let g = s.state.map.m17_geometry().unwrap();
    interact(s, id, &g.kessel_desk);
    interact(s, id, &g.core_override);
    place(s, id, [0.0, 0.0, 26.0]);
    tick(s);
    clear_enemies(s);
    tick(s);
    assert_eq!(current(s), "voss_captured");
}

#[test]
fn voss_stands_at_her_rostrum_alive_and_is_nobodys_target() {
    let (mut s, id) = session();
    tick(&mut s);
    let custody = s.state.map.m17_objectives().unwrap().custody.clone();
    let (voss_id, at, hp) = voss(&s);
    assert!(near(at, custody.voss, 0.01) && hp > 0);
    assert!(escort(&s).is_empty(), "nobody has come for her yet");
    // The world and the clearing of rooms never touch her.
    clear_enemies(&mut s);
    tick(&mut s);
    assert_eq!(voss(&s).2, hp);
    // Shots at her do not land: she is taken alive or not at all.
    to_the_rostrum(&mut s, id);
    place(&mut s, id, [at[0] - 4.0, 0.0, at[2] - 3.0]);
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
                    player_id: Some(voss_id),
                    ..Default::default()
                }),
                ..Default::default()
            },
        );
        tick(&mut s);
        fired += usize::from(s.state.players.iter().any(|p| p.id == id && p.just_fired));
    }
    assert!(fired > 0, "the participant really fired");
    assert_eq!(voss(&s).2, hp);
    assert!(facts(&s).custody_started.is_none(), "a shot is not custody");
    // She is never a party member, a target or a departure requirement.
    let state = s.state.mission_state().unwrap();
    assert!(state.party.iter().all(|m| m.id != voss_id));
    let me = s.state.players.iter().find(|p| p.id == id).unwrap();
    let her = s.state.players.iter().find(|p| p.id == voss_id).unwrap();
    assert!(
        !crate::protocol::hostile(me.campaign, her.campaign)
            && !crate::protocol::hostile(her.campaign, me.campaign)
    );
}

#[test]
fn securing_voss_brings_the_coalition_who_walk_her_out() {
    let (mut s, id) = session();
    to_the_rostrum(&mut s, id);
    let g = s.state.map.m17_geometry().unwrap();
    let custody = s.state.map.m17_objectives().unwrap().custody.clone();
    interact(&mut s, id, &g.voss_rostrum);
    let started = facts(&s)
        .custody_started
        .expect("custody begins at the use");
    assert!(started <= s.state.tick && s.state.tick - started <= 1);
    // Two coalition people come in from beyond the east door; she is not yet
    // in custody and the rostrum asks nothing more.
    let people = escort(&s);
    assert_eq!(people.len(), 2);
    assert!(people.iter().all(|(_, at, _)| at[0] > 16.0));
    let m17 = facts(&s);
    assert!(!m17.voss_captured && m17.completed.len() == 5);
    assert!(s.state.mission_state().unwrap().prompts.is_empty());
    // Using the rostrum again restarts nothing.
    interact(&mut s, id, &g.voss_rostrum);
    assert_eq!(facts(&s).custody_started, Some(started));
    assert_eq!(escort(&s).len(), 2);
    // They walk to her side while she stands where she was.
    let mut captured_at = None;
    for _ in 0..400 {
        tick(&mut s);
        if facts(&s).voss_captured {
            captured_at = Some(s.state.tick);
            break;
        }
        assert!(
            near(voss(&s).1, custody.voss, 0.01),
            "she waits at the rostrum"
        );
    }
    let captured_at = captured_at.expect("the coalition takes her");
    assert!(captured_at - started >= crate::protocol::M17_CUSTODY_TAKEN_TICKS);
    let ends: Vec<[f32; 3]> = custody.walk_in.iter().map(|r| *r.last().unwrap()).collect();
    assert!(escort(&s)
        .iter()
        .all(|(_, at, _)| ends.iter().any(|end| near(*at, *end, 0.2))));
    // She is in custody now: the objective line moves to the departure, and
    // the executive world is installed.
    let m17 = facts(&s);
    assert_eq!(m17.completed.len(), 6);
    assert!(m17.challenges.voss_captured);
    assert_eq!(s.state.map.m17_stage(), 2);
    // They walk her out together, alive, to where they wait.
    for _ in 0..600 {
        tick(&mut s);
    }
    let holds: Vec<[f32; 3]> = custody
        .walk_out
        .iter()
        .map(|r| *r.last().unwrap())
        .collect();
    let (_, at, hp) = voss(&s);
    assert!(near(at, holds[0], 0.05) && hp > 0, "Voss waits under guard");
    for (_, at, hp) in escort(&s) {
        assert!(hp > 0 && holds[1..].iter().any(|h| near(at, *h, 0.05)));
    }
    // The party leaves past them.
    place(&mut s, id, [24.0, 0.0, 38.0]);
    interact(&mut s, id, &g.departure);
    assert_eq!(
        s.state.mission_state().unwrap().phase,
        MissionPhase::Departed
    );
}

#[test]
fn the_rostrum_refuses_before_the_core_falls_and_from_afar() {
    let (mut s, id) = session();
    through_the_hall(&mut s, id);
    let g = s.state.map.m17_geometry().unwrap();
    interact(&mut s, id, &g.kessel_desk);
    interact(&mut s, id, &g.core_override);
    // The core's defenders still stand: securing her is not offered.
    interact(&mut s, id, &g.voss_rostrum);
    assert!(facts(&s).custody_started.is_none());
    assert!(escort(&s).is_empty());
    place(&mut s, id, [0.0, 0.0, 26.0]);
    tick(&mut s);
    clear_enemies(&mut s);
    tick(&mut s);
    assert_eq!(current(&s), "voss_captured");
    // From across the chamber a Use press is not custody.
    let point = g
        .voss_rostrum
        .point(
            s.state.map.presentation_ref().unwrap(),
            &s.state.map.arena().solids,
        )
        .unwrap();
    place(&mut s, id, [-10.0, 0.0, 22.0]);
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
    tick(&mut s);
    assert!(facts(&s).custody_started.is_none());
    assert!(escort(&s).is_empty());
}

#[test]
fn somebody_in_the_way_holds_the_walk_and_nobody_walks_through_them() {
    let (mut s, id) = session();
    to_the_rostrum(&mut s, id);
    let g = s.state.map.m17_geometry().unwrap();
    interact(&mut s, id, &g.voss_rostrum);
    let custody = s.state.map.m17_objectives().unwrap().custody.clone();
    // Stand in the east doorway on the first escort's way in.
    let doorway = custody.walk_in[0][0];
    for _ in 0..30 {
        tick(&mut s);
    }
    let hold = [doorway[0] + 1.6, 0.0, doorway[2]];
    let mut stuck = Vec::new();
    for _ in 0..200 {
        place(&mut s, id, hold);
        tick(&mut s);
        stuck.push(escort(&s)[0].1);
    }
    // The walk stops short of the person and does not pass through.
    let last = *stuck.last().unwrap();
    assert!(stuck[stuck.len() - 40..]
        .iter()
        .all(|at| near(*at, last, 0.001)));
    for (_, at, _) in escort(&s) {
        assert!(!near(at, hold, 2.0 * crate::movement::RADIUS));
    }
    assert!(!facts(&s).voss_captured);
    // Step aside and they come on.
    place(&mut s, id, g.voss_rostrum.approach);
    for _ in 0..400 {
        tick(&mut s);
        if facts(&s).voss_captured {
            break;
        }
    }
    assert!(facts(&s).voss_captured);
}

#[test]
fn a_retry_restores_voss_at_her_rostrum_and_a_late_joiner_restages_nothing() {
    let (mut s, id) = session();
    to_the_rostrum(&mut s, id);
    let g = s.state.map.m17_geometry().unwrap();
    let custody = s.state.map.m17_objectives().unwrap().custody.clone();
    interact(&mut s, id, &g.voss_rostrum);
    for _ in 0..900 {
        tick(&mut s);
    }
    assert!(facts(&s).voss_captured);
    let started = facts(&s).custody_started;
    let before: Vec<[f32; 3]> = s
        .state
        .players
        .iter()
        .filter(|p| p.campaign.is_some_and(CampaignActor::is_figure))
        .map(|p| [p.x, p.y, p.z])
        .collect();
    // Someone joins after the beat: the three are where they wait, the
    // custody tick is unchanged and nothing comes again.
    let late = Uuid::from_u128(1018);
    s.state
        .add_player(late, "Late operative".into(), Role::Agent);
    tick(&mut s);
    tick(&mut s);
    assert_eq!(facts(&s).custody_started, started);
    assert_eq!(escort(&s).len(), 2);
    let after: Vec<[f32; 3]> = s
        .state
        .players
        .iter()
        .filter(|p| p.campaign.is_some_and(CampaignActor::is_figure))
        .map(|p| [p.x, p.y, p.z])
        .collect();
    assert_eq!(before, after);
    // Their identities ride the snapshot for every observer.
    let snapshot = serde_json::to_value(s.state.snapshot()).unwrap();
    let sides: Vec<String> = snapshot["players"]
        .as_array()
        .unwrap()
        .iter()
        .filter(|p| p["campaign"]["side"] == "figure")
        .map(|p| p["campaign"]["kind"].as_str().unwrap().to_owned())
        .collect();
    assert_eq!(sides.iter().filter(|k| *k == "voss").count(), 1);
    assert_eq!(sides.iter().filter(|k| *k == "coalition").count(), 2);
    // A retry starts the morning over: Voss at her rostrum, nobody with her.
    s.state.reset_mission();
    tick(&mut s);
    assert!(facts(&s).custody_started.is_none());
    assert!(!facts(&s).voss_captured);
    assert!(near(voss(&s).1, custody.voss, 0.01));
    assert!(escort(&s).is_empty());
}

#[test]
fn a_custody_walk_through_a_wall_or_into_the_boarding_area_is_refused() {
    let mut wrong: serde_json::Value = serde_json::from_str(MAP).unwrap();
    wrong["m17"]["custody"]["walk_out"][0][1] = serde_json::json!([15.0, 0.0, 22.0]);
    assert!(AuthoredMap::read(serde_json::to_vec(&wrong).unwrap().as_slice()).is_err());
    let mut uneven: serde_json::Value = serde_json::from_str(MAP).unwrap();
    uneven["m17"]["custody"]["walk_in"][0]
        .as_array_mut()
        .unwrap()
        .pop();
    assert!(AuthoredMap::read(serde_json::to_vec(&uneven).unwrap().as_slice()).is_err());
    let mut boarding: serde_json::Value = serde_json::from_str(MAP).unwrap();
    for (route, end) in [[24.0, 0.0, 38.0], [22.0, 0.0, 36.0], [26.0, 0.0, 36.0]]
        .iter()
        .enumerate()
    {
        boarding["m17"]["custody"]["walk_out"][route]
            .as_array_mut()
            .unwrap()
            .push(serde_json::json!(end));
    }
    assert!(AuthoredMap::read(serde_json::to_vec(&boarding).unwrap().as_slice()).is_err());
    let mut crowded: serde_json::Value = serde_json::from_str(MAP).unwrap();
    crowded["m17"]["custody"]["voss"] = serde_json::json!([5.4, 0.0, 30.6]);
    assert!(AuthoredMap::read(serde_json::to_vec(&crowded).unwrap().as_slice()).is_err());
}

#[test]
fn a_party_wipe_brings_voss_back_to_her_rostrum_for_the_next_attempt() {
    let (mut s, id) = session();
    to_the_rostrum(&mut s, id);
    let custody = s.state.map.m17_objectives().unwrap().custody.clone();
    let attempt = s.state.mission_state().unwrap().attempt;
    let me = s.state.players.iter().position(|p| p.id == id).unwrap();
    s.state.environmental_self_damage(me, 1000);
    for _ in 0..400 {
        tick(&mut s);
        if s.state.mission_state().unwrap().attempt > attempt
            && s.state.players.iter().any(|p| p.id == id && p.hp > 0)
            && !figures(&s, crate::protocol::FigureKind::Voss).is_empty()
        {
            break;
        }
    }
    assert!(s.state.mission_state().unwrap().attempt > attempt);
    assert!(near(voss(&s).1, custody.voss, 0.01));
    assert!(escort(&s).is_empty());
}
