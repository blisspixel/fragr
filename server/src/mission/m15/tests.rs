use super::*;
use crate::maps::AuthoredMap;
use crate::protocol::{Action, LookAt, Role, UseTarget, WeaponType};
use crate::session::GameSession;
use std::sync::{Arc, OnceLock};

const MAP: &str = include_str!("../../../maps/m15-civic-pressure-valve.json");

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
    s.state.seed(1015);
    let id = Uuid::from_u128(1015);
    s.state.add_player(id, "Stadium entrant".into(), role);
    if role == Role::Human {
        s.state.arm_joined_magazines(id);
    }
    assert!(s.state.acknowledge_mission(
        id,
        MissionReady {
            id: MissionId::CivicPressureValve,
            attempt: 1,
        }
    ));
    (s, id)
}

fn tick(s: &mut GameSession) {
    s.tick_messages(0.05);
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
        if !p.is_participant() && !p.campaign.is_some_and(CampaignActor::is_entrant) && p.hp > 0 {
            let damage = p.hp + p.armor;
            s.state.environmental_self_damage(i, damage);
        }
    }
}

#[test]
fn pen_arming_arms_entrants_and_sets_assisted_challenge() {
    let (mut s, id) = session();
    tick(&mut s);
    let state = s.state.mission_state().unwrap();
    let m15 = state.m15.unwrap();
    assert_eq!(m15.completed.len(), 0);
    assert_eq!(m15.current.as_ref().unwrap().id, "pen_armed");
    assert!(!m15.challenges.pen_armed);
    assert!(m15.armed_entrants.is_empty());

    let g = s.state.map.m15_geometry().unwrap();
    interact(&mut s, id, &g.arming_crate);

    let state = s.state.mission_state().unwrap();
    let m15 = state.m15.unwrap();
    assert!(m15.challenges.pen_armed);
    assert_eq!(m15.completed, vec!["pen_armed"]);
    assert_eq!(m15.current.as_ref().unwrap().id, "pen_cleared");
    assert_eq!(m15.armed_entrants, vec![4, 12, 44, 71]);

    // Check all entrants are armed with Tack and have ammo
    for placard in [4, 12, 44, 71] {
        let entrant = s
            .state
            .players
            .iter()
            .find(|p| {
                p.campaign
                    == Some(CampaignActor::Entrant {
                        placard,
                        armed: true,
                    })
            })
            .unwrap();
        assert_eq!(entrant.weapon, WeaponType::Tack);
        let loadout = entrant
            .inventory
            .state(entrant.id, entrant.weapon, s.state.tick)
            .unwrap();
        assert_eq!(loadout.ammo(crate::protocol::AmmoPool::Bullets), 110);
    }
}

#[test]
fn pen_clear_and_tunnel_arrival_closes_tunnel_and_advances_stage() {
    let (mut s, id) = session();
    tick(&mut s);

    let g = s.state.map.m15_geometry().unwrap();
    interact(&mut s, id, &g.arming_crate);

    // Spawn and clear pen gate encounter (encounter 0)
    tick(&mut s);
    clear_enemies(&mut s);
    tick(&mut s);

    // Move into tunnel arrival area (completes pen_cleared)
    place(&mut s, id, [0.0, 0.0, -16.0]);
    tick(&mut s);

    // Step forward out of the tunnel onto the stadium floor (traps entrants/party inside arena)
    place(&mut s, id, [0.0, 0.0, 0.0]);
    tick(&mut s);

    let state = s.state.mission_state().unwrap();
    let m15 = state.m15.unwrap();
    assert!(m15.tunnel_closed);
    assert_eq!(m15.completed, vec!["pen_armed", "pen_cleared"]);
    assert_eq!(m15.current.as_ref().unwrap().id, "blade_lesson_won");
}

#[test]
fn blade_lesson_tracking_checks_hits_and_disqualification() {
    let (mut s, id) = session();
    tick(&mut s);

    let g = s.state.map.m15_geometry().unwrap();
    interact(&mut s, id, &g.arming_crate);

    // Clear encounter 0 and advance tunnel
    tick(&mut s);
    clear_enemies(&mut s);
    tick(&mut s);
    place(&mut s, id, [0.0, 0.0, -16.0]);
    tick(&mut s);
    place(&mut s, id, [0.0, 0.0, 0.0]);
    tick(&mut s);

    // Now in stage 1, encounter 1 (floor_lifts) spawns
    tick(&mut s);

    // Verify Article Blade plinth is available
    assert!(s.state.article_blade.is_some());

    // Disqualify by dealing damage with a non-blade weapon to an enemy in group 1
    let enemy_idx = s
        .state
        .players
        .iter()
        .position(|p| s.state.encounters.enemy_in_group(p.id, 1))
        .unwrap();
    let enemy_id = s.state.players[enemy_idx].id;
    s.state
        .record_m15_damage(id, enemy_id, Some(WeaponType::Repeater), 20, false);

    let progress = s.state.mission.as_ref().unwrap().m15.as_ref().unwrap();
    assert!(progress.blade_disqualified);

    // Clear remaining enemies in encounter 1
    clear_enemies(&mut s);
    tick(&mut s);

    let state = s.state.mission_state().unwrap();
    let m15 = state.m15.unwrap();
    assert!(!m15.challenges.blade_wave_won);
    assert_eq!(m15.completed.len(), 3);
}

#[test]
fn bout_victory_opens_gates_and_enables_departure() {
    let (mut s, id) = session();
    tick(&mut s);

    let g = s.state.map.m15_geometry().unwrap();
    interact(&mut s, id, &g.arming_crate);

    // Clear encounter 0 and advance through tunnel
    tick(&mut s);
    clear_enemies(&mut s);
    tick(&mut s);
    place(&mut s, id, [0.0, 0.0, -16.0]);
    tick(&mut s);
    place(&mut s, id, [0.0, 0.0, 0.0]);
    tick(&mut s);

    // Record blade hit for blade wave victory
    let progress = s.state.mission.as_mut().unwrap().m15.as_mut().unwrap();
    progress.blade_hits = 1;
    progress.blade_disqualified = false;

    // Clear encounter 1
    tick(&mut s);
    clear_enemies(&mut s);
    tick(&mut s);

    // Clear encounter 2 (tunnel wardens)
    tick(&mut s);
    clear_enemies(&mut s);
    tick(&mut s);

    // Clear encounter 3 (overhead notaries)
    tick(&mut s);
    clear_enemies(&mut s);
    tick(&mut s);

    let state = s.state.mission_state().unwrap();
    let m15 = state.m15.unwrap();
    assert_eq!(m15.current.as_ref().unwrap().id, "broadcast_secured");

    // Clear encounter 4 (booth guards)
    tick(&mut s);
    clear_enemies(&mut s);
    tick(&mut s);

    // Use broadcast booth terminal
    interact(&mut s, id, &g.booth_terminal);

    let state = s.state.mission_state().unwrap();
    let m15 = state.m15.unwrap();
    assert!(m15.broadcast_taken);
    assert_eq!(m15.current.as_ref().unwrap().id, "bout_won");

    // Clear final bout encounter 5
    tick(&mut s);
    clear_enemies(&mut s);
    tick(&mut s);

    let state = s.state.mission_state().unwrap();
    let m15 = state.m15.unwrap();
    assert!(m15.gates_open);
    assert_eq!(m15.completed.len(), 6);
    assert_eq!(m15.current.as_ref().unwrap().id, "party_departed");

    // Board departure area and depart
    interact(&mut s, id, &g.departure);

    let state = s.state.mission_state().unwrap();
    assert_eq!(state.phase, MissionPhase::Departed);
}

#[test]
fn entrants_preserved_severe_challenge_fails_if_armed_entrant_dies() {
    let (mut s, id) = session();
    tick(&mut s);

    let g = s.state.map.m15_geometry().unwrap();
    interact(&mut s, id, &g.arming_crate);

    let entrant_id = s
        .state
        .players
        .iter()
        .find(|p| {
            p.campaign
                == Some(CampaignActor::Entrant {
                    placard: 4,
                    armed: true,
                })
        })
        .unwrap()
        .id;

    // Entrant takes lethal damage
    s.state.record_m15_damage(id, entrant_id, None, 100, true);

    let state = s.state.mission_state().unwrap();
    let m15 = state.m15.unwrap();
    assert!(!m15.challenges.entrants_preserved);
    assert_eq!(m15.fallen_entrants, vec![4]);
}

#[test]
fn m15_mission_retry_resets_entrants_blade_and_gates() {
    let (mut s, id) = session();
    tick(&mut s);

    let g = s.state.map.m15_geometry().unwrap();
    interact(&mut s, id, &g.arming_crate);

    // Kill participant to trigger reset
    let p = s.state.players.iter_mut().find(|p| p.id == id).unwrap();
    p.hp = 0;
    s.state.tick(0.05);

    // Reset mission
    s.state.reset_mission();

    let state = s.state.mission_state().unwrap();
    let m15 = state.m15.unwrap();
    assert!(!m15.challenges.pen_armed);
    assert!(!m15.tunnel_closed);
    assert!(!m15.gates_open);
    assert!(m15.armed_entrants.is_empty());
    assert!(m15.fallen_entrants.is_empty());
    assert!(s.state.article_blade.is_some());
}
