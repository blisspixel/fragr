use crate::maps::AuthoredMap;
use crate::protocol::{Action, CampaignActor, EnemyKind, EnemyPhase, LookAt, Role, WeaponType};
use crate::session::GameSession;
use crate::sim::PLAYER_FLOOR_Y;
use serde_json::json;
use uuid::Uuid;

fn session() -> (GameSession, Uuid) {
    fixture(false)
}

fn fixture(cover: bool) -> (GameSession, Uuid) {
    let mut doc = json!({
        "version":1,"map_id":1000,"name":"Encounter fixture","half_extent":12,
        "ground":"concrete","equipment":"discovery","solids":[],
        "spawns":[{"id":"entry","feet":[0,0,-6],"yaw":1.5707964}],
        "landmarks":[{"id":"exit","feet":[0,0,10]}],
        "encounters":[{
            "id":"intake","regions":[{"min":[-2,0,-2],"max":[2,2,2]}],
            "enemies":[{"id":"clerk","kind":"clerk","feet":[0,0,4],"yaw":4.712389}]
        },{
            "id":"backup","after":"intake","regions":[{"min":[-2,0,-2],"max":[2,2,2]}],
            "enemies":[
                {"id":"sweeper_a","kind":"sweeper","feet":[-3,0,6],"yaw":4.712389},
                {"id":"sweeper_b","kind":"sweeper","feet":[3,0,6],"yaw":4.712389}
            ]
        }]
    });
    if cover {
        doc["solids"] = json!([{"id":"cover","min":[0.5,0,1],"max":[1.5,3,3],"surface":"enamel"}]);
    }
    let map = AuthoredMap::read(serde_json::to_vec(&doc).unwrap().as_slice()).unwrap();
    let mut session = GameSession::with_authored_map(map);
    session.state.seed(42);
    let id = Uuid::from_u128(100);
    session.state.add_player(id, "Visitor".into(), Role::Human);
    (session, id)
}

fn advance(session: &mut GameSession, ticks: usize) {
    for _ in 0..ticks {
        session.tick_messages(0.05);
    }
}

fn enter(session: &mut GameSession, id: Uuid) -> Uuid {
    let player = session
        .state
        .players
        .iter_mut()
        .find(|p| p.id == id)
        .unwrap();
    player.x = 0.0;
    player.z = 0.0;
    advance(session, 1);
    session
        .state
        .players
        .iter()
        .find(|p| p.is_campaign_enemy())
        .unwrap()
        .id
}

fn phase(session: &GameSession, id: Uuid) -> EnemyPhase {
    match session
        .state
        .players
        .iter()
        .find(|p| p.id == id)
        .unwrap()
        .campaign
        .unwrap()
    {
        CampaignActor::Union { phase, .. } => phase,
        CampaignActor::Participant {} => panic!("expected enemy"),
    }
}

fn shoot(session: &mut GameSession, shooter: Uuid, target: Uuid) {
    let player = session
        .state
        .players
        .iter_mut()
        .find(|p| p.id == shooter)
        .unwrap();
    player.inventory.grant_weapon(WeaponType::Tack);
    player.weapon = WeaponType::Tack;
    player.fire_cooldown = 0;
    session.state.set_action(
        shooter,
        Action {
            fire: true,
            look_at: Some(LookAt {
                player_id: Some(target),
                ..Default::default()
            }),
            ..Default::default()
        },
    );
    session.state.tick(0.05);
    session.state.set_action(shooter, Action::default());
}

#[test]
fn authored_enemies_activate_once_clear_in_order_and_never_respawn() {
    let (mut session, id) = session();
    advance(&mut session, 20);
    assert_eq!(session.state.players.len(), 4);
    assert_eq!(session.state.players[0].hp, 100);
    assert!(session.state.shot_results.is_empty());
    let prepared: Vec<_> = session
        .state
        .players
        .iter()
        .filter(|p| p.is_campaign_enemy())
        .map(|p| p.id)
        .collect();
    for &enemy in &prepared {
        assert_eq!(phase(&session, enemy), EnemyPhase::Idle);
    }
    let clerk = enter(&mut session, id);
    assert_eq!(session.state.players.len(), 4);
    assert_eq!(
        session
            .state
            .players
            .iter()
            .filter(|p| p.is_campaign_enemy())
            .map(|p| p.id)
            .collect::<Vec<_>>(),
        prepared
    );
    assert_eq!(session.state.scores.len(), 1);
    for _ in 0..3 {
        shoot(&mut session, id, clerk);
    }
    assert_eq!(phase(&session, clerk), EnemyPhase::Dead);
    assert!(session
        .state
        .players
        .iter()
        .find(|p| p.id == clerk)
        .unwrap()
        .respawn_timer
        .is_none());
    let snapshot = session.state.snapshot();
    assert!(snapshot.players.iter().any(|p| p.id == clerk && p.hp == 0));
    assert_eq!(session.state.scores[&id], 0);
    assert!(session.state.take_events().iter().all(|event| !matches!(
        event,
        crate::protocol::GameEvent::Frag { .. } | crate::protocol::GameEvent::Killstreak { .. }
    )));
    advance(&mut session, 1);
    assert_eq!(
        session
            .state
            .players
            .iter()
            .filter(|p| p.is_campaign_enemy() && p.hp > 0)
            .count(),
        2
    );
    // Freeze controller input so this checks lifecycle without killing the participant.
    for _ in 0..80 {
        session.state.tick(0.05);
    }
    assert!(!session.state.players.iter().any(|p| p.id == clerk));
    assert_eq!(session.state.players.len(), 3);
    assert_eq!(
        session
            .state
            .snapshot()
            .players
            .iter()
            .filter(|p| p.is_participant())
            .count(),
        1
    );
}

#[test]
fn shooting_a_dormant_group_wakes_existing_guards_without_waiting_for_its_dependency() {
    let (mut session, id) = session();
    advance(&mut session, 1);
    let guards: Vec<_> = session
        .state
        .players
        .iter()
        .filter(|p| p.is_campaign_enemy())
        .map(|p| p.id)
        .collect();
    assert_eq!(guards.len(), 3);
    shoot(&mut session, id, guards[1]);
    assert_eq!(phase(&session, guards[1]), EnemyPhase::Hit);
    assert_eq!(phase(&session, guards[0]), EnemyPhase::Idle);
    advance(&mut session, 6);
    assert_eq!(phase(&session, guards[1]), EnemyPhase::Windup);
    assert_eq!(phase(&session, guards[2]), EnemyPhase::Windup);
    assert_eq!(phase(&session, guards[0]), EnemyPhase::Idle);
    assert_eq!(
        session
            .state
            .players
            .iter()
            .filter(|p| p.is_campaign_enemy())
            .map(|p| p.id)
            .collect::<Vec<_>>(),
        guards
    );
}

#[test]
fn hidden_peers_investigate_a_hit_then_dispatch_once_on_room_entry() {
    let doc = json!({
        "version":1,"map_id":1000,"name":"Hidden alarm fixture","half_extent":16,
        "ground":"concrete","equipment":"discovery",
        "solids":[{"id":"divider","min":[-1,0,-8],"max":[1,3,8],"surface":"enamel"}],
        "spawns":[{"id":"entry","feet":[-6,0,-6],"yaw":1.5707964}],
        "landmarks":[{"id":"exit","feet":[0,0,12]}],
        "encounters":[{
            "id":"prior","regions":[{"min":[-14,0,-14],"max":[-12,2,-12]}],
            "enemies":[{"id":"clerk","kind":"clerk","feet":[0,0,-10],"yaw":0}]
        },{
            "id":"room","after":"prior","regions":[{"min":[-8,0,0],"max":[-4,2,2]}],
            "enemies":[
                {"id":"sentry","kind":"sweeper","feet":[-6,0,6],"yaw":4.712389},
                {"id":"hidden","kind":"sweeper","feet":[6,0,6],"yaw":4.712389}
            ]
        }]
    });
    let map = AuthoredMap::read(serde_json::to_vec(&doc).unwrap().as_slice()).unwrap();
    let mut session = GameSession::with_authored_map(map);
    let id = Uuid::from_u128(100);
    session.state.add_player(id, "Visitor".into(), Role::Human);
    advance(&mut session, 1);
    let guards: Vec<_> = session
        .state
        .players
        .iter()
        .filter(|p| p.is_campaign_enemy())
        .map(|p| p.id)
        .collect();
    assert_eq!(guards.len(), 3);
    assert!(session.state.enemy_intents().is_empty());

    // Kill the sentry outside both entry regions. The surviving peer cannot
    // see the attacker across the divider, but must investigate the hit.
    session
        .state
        .players
        .iter_mut()
        .find(|p| p.id == guards[1])
        .unwrap()
        .hp = 20;
    shoot(&mut session, id, guards[1]);
    assert_eq!(phase(&session, guards[1]), EnemyPhase::Dead);
    let investigation = session
        .state
        .enemy_intents()
        .into_iter()
        .find(|(enemy, _)| *enemy == guards[2])
        .unwrap()
        .1;
    assert_eq!(investigation.goal.unwrap().feet, [-6.0, 0.0, 6.0]);
    assert_eq!(phase(&session, guards[2]), EnemyPhase::Moving);
    assert_eq!(phase(&session, guards[0]), EnemyPhase::Idle);

    // The entry alarm dispatches this already active group even though its
    // ordinary dependency is incomplete. It must not track an unseen player.
    let player = session
        .state
        .players
        .iter_mut()
        .find(|p| p.id == id)
        .unwrap();
    player.x = -6.0;
    player.z = 1.0;
    session.state.update_encounters();
    let dispatched = session
        .state
        .enemy_intents()
        .into_iter()
        .find(|(enemy, _)| *enemy == guards[2])
        .unwrap()
        .1;
    assert_eq!(dispatched.goal.unwrap().feet, [-6.0, 0.0, 1.0]);
    session
        .state
        .players
        .iter_mut()
        .find(|p| p.id == id)
        .unwrap()
        .x = -7.0;
    session.state.update_encounters();
    let repeated = session
        .state
        .enemy_intents()
        .into_iter()
        .find(|(enemy, _)| *enemy == guards[2])
        .unwrap()
        .1;
    assert_eq!(repeated.goal.unwrap().feet, [-6.0, 0.0, 1.0]);
    assert_eq!(session.state.players.len(), 4);
    assert_eq!(phase(&session, guards[0]), EnemyPhase::Idle);
    assert!(session
        .state
        .shot_results
        .iter()
        .all(|shot| shot.shooter_id == id));
}

#[test]
fn clerk_windup_is_visible_and_aim_commits_before_a_dodge() {
    let (mut session, id) = session();
    let clerk = enter(&mut session, id);
    advance(&mut session, 1);
    assert_eq!(phase(&session, clerk), EnemyPhase::Windup);
    advance(&mut session, 11);
    assert_eq!(session.state.players[0].hp, 100);
    assert!(session.state.shot_results.is_empty());
    session.state.players[0].x = 2.0;
    advance(&mut session, 1);
    assert!(session
        .state
        .shot_results
        .iter()
        .any(|shot| shot.shooter_id == clerk));
    assert_eq!(
        session.state.players[0].hp, 100,
        "windup must leave a real evasion opportunity"
    );
    advance(&mut session, 1);
    assert_eq!(phase(&session, clerk), EnemyPhase::Recovery);
}

#[test]
fn stationary_participant_is_damaged_by_the_same_authoritative_ray() {
    let (mut session, id) = session();
    let clerk = enter(&mut session, id);
    advance(&mut session, 13);
    let shot = session
        .state
        .shot_results
        .iter()
        .find(|shot| shot.shooter_id == clerk)
        .unwrap();
    assert_eq!(shot.target_id, Some(id));
    assert_eq!(shot.damage, 20);
    assert_eq!(session.state.players[0].hp, 80);
    assert_eq!(shot.trace.as_ref().unwrap().weapon, WeaponType::Tack);
}

#[test]
fn a_lethal_trade_retains_the_dead_guards_resolved_shot() {
    let (mut session, id) = session();
    let clerk = enter(&mut session, id);
    advance(&mut session, 12);
    for player in &mut session.state.players {
        player.hp = 20;
    }
    let participant = &mut session.state.players[0];
    participant.inventory.grant_weapon(WeaponType::Tack);
    participant.weapon = WeaponType::Tack;
    session.state.set_action(
        id,
        Action {
            fire: true,
            look_at: Some(LookAt {
                player_id: Some(clerk),
                ..Default::default()
            }),
            ..Default::default()
        },
    );
    advance(&mut session, 1);
    assert_eq!(session.state.shot_results.len(), 2);
    assert!(session.state.shot_results.iter().all(|shot| shot.killed));
    assert!(session
        .state
        .shot_results
        .iter()
        .any(|shot| shot.shooter_id == clerk && shot.target_id == Some(id)));
    assert_eq!(phase(&session, clerk), EnemyPhase::Dead);
    assert!(session.state.players[0].respawn_timer.is_some());
}

#[test]
fn participant_control_roles_are_allies_and_intercept_friendly_fire() {
    let (mut session, human) = session();
    let clerk = enter(&mut session, human);
    let agent = Uuid::from_u128(101);
    session
        .state
        .add_player(agent, "Partner".into(), Role::Agent);
    let ally = session
        .state
        .players
        .iter_mut()
        .find(|p| p.id == agent)
        .unwrap();
    ally.x = 0.0;
    ally.z = 2.0;
    shoot(&mut session, human, clerk);
    let shot = &session.state.shot_results[0];
    assert_eq!(shot.target_id, Some(agent));
    assert_eq!(shot.damage, 0);
    assert!(!shot.killed);
    assert_eq!(
        session
            .state
            .players
            .iter()
            .find(|p| p.id == agent)
            .unwrap()
            .hp,
        100
    );
    assert_eq!(
        session
            .state
            .players
            .iter()
            .find(|p| p.id == clerk)
            .unwrap()
            .hp,
        60
    );
    let snapshot = session.state.snapshot();
    let me = snapshot.players.iter().find(|p| p.id == human).unwrap();
    assert!(me.is_hostile_to(snapshot.players.iter().find(|p| p.id == clerk).unwrap()));
    assert!(!me.is_hostile_to(snapshot.players.iter().find(|p| p.id == agent).unwrap()));
}

#[test]
fn damage_interrupts_an_attack_and_dead_enemies_cannot_move_or_fire() {
    let (mut session, id) = session();
    let clerk = enter(&mut session, id);
    advance(&mut session, 10);
    shoot(&mut session, id, clerk);
    assert_eq!(phase(&session, clerk), EnemyPhase::Hit);
    advance(&mut session, 6);
    assert_eq!(session.state.players[0].hp, 100);
    assert_eq!(phase(&session, clerk), EnemyPhase::Windup);
    for _ in 0..2 {
        shoot(&mut session, id, clerk);
    }
    let enemy = session
        .state
        .players
        .iter()
        .find(|p| p.id == clerk)
        .unwrap();
    let feet = (enemy.x, enemy.y, enemy.z);
    session.state.set_action(
        clerk,
        Action {
            fire: true,
            forward: true,
            ..Default::default()
        },
    );
    session.state.tick(0.05);
    let enemy = session
        .state
        .players
        .iter()
        .find(|p| p.id == clerk)
        .unwrap();
    assert_eq!((enemy.x, enemy.y, enemy.z), feet);
    assert!(!session
        .state
        .shot_results
        .iter()
        .any(|shot| shot.shooter_id == clerk));
    shoot(&mut session, id, clerk);
    assert!(session
        .state
        .shot_results
        .iter()
        .all(|shot| shot.target_id != Some(clerk)));
}

#[test]
fn live_and_dead_enemies_cannot_consume_participant_supplies() {
    let (mut session, id) = session();
    let clerk = enter(&mut session, id);
    session.state.pickups.push(crate::sim::ArenaPickup {
        claim: crate::protocol::SupplyClaim::Contested,
        id: "health".into(),
        kind: crate::sim::PickupKind::Health,
        amount: 25,
        x: 0.0,
        y: 0.1,
        z: 4.0,
        floor: 0.0,
        available: true,
        respawn_timer: None,
    });
    session.state.tick(0.05);
    assert!(session.state.pickups[0].available);
    assert_eq!(
        session
            .state
            .players
            .iter()
            .find(|p| p.id == clerk)
            .unwrap()
            .hp,
        60
    );
    for _ in 0..3 {
        shoot(&mut session, id, clerk);
    }
    session.state.tick(0.05);
    assert!(session.state.pickups[0].available);
    session.state.players[0].hp = 50;
    session.state.set_action(
        id,
        Action {
            forward: true,
            yaw: Some(std::f32::consts::FRAC_PI_2),
            ..Default::default()
        },
    );
    for _ in 0..10 {
        session.state.tick(0.05);
    }
    assert!(!session.state.pickups[0].available);
    assert_eq!(session.state.players[0].hp, 75);
}

#[test]
fn last_departure_and_party_wipe_reset_once_and_allow_retry() {
    let (mut session, id) = session();
    let first = enter(&mut session, id);
    session.state.players[0].hp = 0;
    session.state.players[0].respawn_timer = Some(5);
    advance(&mut session, 1);
    assert_eq!(session.state.players.len(), 1);
    advance(&mut session, 4);
    assert_eq!(session.state.players[0].hp, 100);
    assert_eq!(session.state.players[0].weapon, WeaponType::Fists);
    assert_eq!(session.state.players[0].y, PLAYER_FLOOR_Y);
    let second = enter(&mut session, id);
    assert_ne!(first, second);
    session.state.remove_player(id);
    assert!(session.state.players.is_empty());
    session.state.add_player(id, "Return".into(), Role::Agent);
    let third = enter(&mut session, id);
    assert_ne!(second, third);
    assert!(matches!(
        session.state.players[1].campaign,
        Some(CampaignActor::Union {
            kind: EnemyKind::Clerk,
            ..
        })
    ));
}

#[test]
fn losing_sight_cancels_the_attack_instead_of_snapping_to_an_ally() {
    let (mut session, id) = fixture(true);
    let clerk = enter(&mut session, id);
    let other = Uuid::from_u128(102);
    session
        .state
        .add_player(other, "Second visitor".into(), Role::Agent);
    let second = session
        .state
        .players
        .iter_mut()
        .find(|p| p.id == other)
        .unwrap();
    second.x = -4.0;
    second.z = 0.0;
    advance(&mut session, 12);
    assert_eq!(phase(&session, clerk), EnemyPhase::Windup);
    session.state.players[0].x = 3.0;
    advance(&mut session, 1);
    assert_eq!(phase(&session, clerk), EnemyPhase::Recovery);
    assert!(session.state.shot_results.is_empty());
    advance(&mut session, 12);
    assert_eq!(phase(&session, clerk), EnemyPhase::Windup);
    assert!(
        session.state.shot_results.is_empty(),
        "the replacement target receives a fresh tell"
    );
}

#[test]
fn sweeper_bursts_are_spaced_and_recovery_is_an_actual_opening() {
    let (mut session, id) = session();
    let clerk = enter(&mut session, id);
    for _ in 0..3 {
        shoot(&mut session, id, clerk);
    }
    session.state.players[0].hp = 1000;
    advance(&mut session, 1);
    let sweepers: Vec<_> = session
        .state
        .players
        .iter()
        .filter(|p| p.is_campaign_enemy() && p.hp > 0)
        .map(|p| p.id)
        .collect();
    let started = session.state.tick;
    let mut shots = Vec::new();
    for _ in 0..50 {
        advance(&mut session, 1);
        for shot in &session.state.shot_results {
            if sweepers.contains(&shot.shooter_id) {
                shots.push((shot.shooter_id, session.state.tick));
            }
        }
    }
    for id in sweepers {
        let ticks: Vec<_> = shots.iter().filter(|s| s.0 == id).map(|s| s.1).collect();
        assert_eq!(ticks.len(), 3, "one burst, then recovery and a new tell");
        assert_eq!(ticks[0] - started, 15);
        assert_eq!(
            ticks[1] - ticks[0],
            u64::from(WeaponType::Flechette.cooldown_ticks())
        );
        assert_eq!(
            ticks[2] - ticks[1],
            u64::from(WeaponType::Flechette.cooldown_ticks())
        );
    }
}

#[test]
fn guards_spend_finite_bullets_without_reloading_and_use_melee_when_empty() {
    let (mut session, id) = session();
    let clerk = enter(&mut session, id);
    let guard = session
        .state
        .players
        .iter_mut()
        .find(|p| p.id == clerk)
        .unwrap();
    let loadout = guard
        .inventory
        .state(clerk, guard.weapon, session.state.tick)
        .unwrap();
    assert_eq!(
        loadout.shots(WeaponType::Tack),
        Some(WeaponType::Tack.pickup_rounds()),
        "a Clerk carries one Tack pickup's worth of bullets"
    );
    // One bullet short of empty: the guard keeps its Tack and has no reload pause.
    for _ in 1..WeaponType::Tack.pickup_rounds() {
        assert!(guard.inventory.try_fire(guard.weapon));
    }
    advance(&mut session, 1);
    assert_eq!(
        session
            .state
            .players
            .iter()
            .find(|p| p.id == clerk)
            .unwrap()
            .weapon,
        WeaponType::Tack
    );
    let guard = session
        .state
        .players
        .iter_mut()
        .find(|p| p.id == clerk)
        .unwrap();
    assert!(guard.inventory.try_fire(guard.weapon));
    advance(&mut session, 1);
    assert_eq!(
        session
            .state
            .players
            .iter()
            .find(|p| p.id == clerk)
            .unwrap()
            .weapon,
        WeaponType::Fists
    );
    let before = session
        .state
        .players
        .iter()
        .find(|p| p.id == clerk)
        .unwrap()
        .z;
    advance(&mut session, 15);
    let after = session
        .state
        .players
        .iter()
        .find(|p| p.id == clerk)
        .unwrap()
        .z;
    assert!(
        after < before,
        "an exhausted guard closes to melee through normal movement"
    );
}

#[test]
fn a_hit_on_an_empty_guard_does_not_leave_an_expired_pain_pose() {
    let (mut session, id) = session();
    let clerk = enter(&mut session, id);
    let guard = session
        .state
        .players
        .iter_mut()
        .find(|p| p.id == clerk)
        .unwrap();
    while guard.inventory.try_fire(guard.weapon) {}
    advance(&mut session, 1);
    shoot(&mut session, id, clerk);
    assert_eq!(phase(&session, clerk), EnemyPhase::Hit);
    advance(&mut session, 6);
    // The pain pose expires on time. An empty guard has no reload to wait
    // out, so it goes straight back to closing for melee.
    assert!(matches!(
        phase(&session, clerk),
        EnemyPhase::Moving | EnemyPhase::Recovery
    ));
    assert!(session.state.shot_results.is_empty());
    advance(&mut session, 20);
    assert!(matches!(
        phase(&session, clerk),
        EnemyPhase::Moving | EnemyPhase::Windup | EnemyPhase::Firing | EnemyPhase::Recovery
    ));
}

#[test]
fn one_fallen_participant_and_a_late_arrival_do_not_restart_active_groups() {
    let (mut session, id) = session();
    let clerk = enter(&mut session, id);
    let other = Uuid::from_u128(103);
    session
        .state
        .add_player(other, "Late visitor".into(), Role::Agent);
    session.state.players[0].hp = 0;
    session.state.players[0].respawn_timer = Some(60);
    advance(&mut session, 1);
    assert!(session.state.players.iter().any(|p| p.id == clerk));
    session.state.remove_player(id);
    assert!(session.state.players.iter().any(|p| p.id == clerk));
    session.state.remove_player(other);
    assert!(session.state.players.is_empty());
}

#[test]
fn alarm_arrival_routes_around_cover_using_the_shared_movement_controller() {
    let (mut session, id) = fixture(true);
    session.state.players[0].x = 2.0;
    session.state.players[0].z = -2.0;
    advance(&mut session, 1);
    let guard = session
        .state
        .players
        .iter()
        .find(|p| p.is_campaign_enemy())
        .unwrap()
        .id;
    let mut moving = false;
    let mut acquired = false;
    for _ in 0..120 {
        advance(&mut session, 1);
        let body = session
            .state
            .players
            .iter()
            .find(|p| p.id == guard)
            .unwrap();
        let floor = body.y - PLAYER_FLOOR_Y;
        assert!(!session
            .state
            .map
            .arena()
            .blocked_body_at(body.x, body.z, floor, floor));
        moving |= phase(&session, guard) == EnemyPhase::Moving;
        if phase(&session, guard) == EnemyPhase::Windup {
            acquired = true;
            break;
        }
    }
    assert!(
        moving && acquired,
        "alarm arrival must navigate to a real sightline"
    );
    assert_eq!(
        session
            .state
            .players
            .iter()
            .find(|p| p.id == id)
            .unwrap()
            .hp,
        100
    );
}
