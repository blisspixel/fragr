use crate::maps::AuthoredMap;
use crate::net::GameCommand;
use crate::protocol::{Action, AmmoPool, LoadoutState, Role, ServerMessage, WeaponType};
use crate::session::{GameSession, Recipient};
use crate::sim::{GameState, PLAYER_FLOOR_Y};
use uuid::Uuid;

fn mission() -> GameSession {
    GameSession::with_authored_map(
        AuthoredMap::read(include_bytes!("../../maps/m01-recall-notice.json").as_slice()).unwrap(),
    )
}

fn join(session: &mut GameSession, role: Role) -> Uuid {
    let id = Uuid::new_v4();
    session.apply_command(GameCommand::Connected {
        body: crate::protocol::BodyKind::Human,
        id,
        role,
        name: format!("Participant {role:?}"),
        player_id: (role != Role::Spectator).then_some(id),
    });
    if role != Role::Spectator {
        let mission = session.state.mission_state().unwrap();
        assert!(session.state.acknowledge_mission(
            id,
            crate::protocol::MissionReady {
                id: mission.id,
                attempt: mission.attempt,
            }
        ));
    }
    id
}

fn move_to(session: &mut GameSession, id: Uuid, feet: [f32; 3]) {
    let player = session
        .state
        .players
        .iter_mut()
        .find(|p| p.id == id)
        .unwrap();
    [player.x, player.y, player.z] = [feet[0], feet[1] + PLAYER_FLOOR_Y, feet[2]];
    player.pending_action = Action::default();
}

fn equipment(session: &GameSession, id: Uuid) -> LoadoutState {
    let player = session.state.players.iter().find(|p| p.id == id).unwrap();
    let loadout = player
        .inventory
        .state(id, player.weapon, session.state.tick)
        .unwrap();
    loadout.validate().unwrap();
    loadout
}

#[test]
fn shared_controller_uses_owned_ammunition_and_recovers_from_empty_weapons() {
    use crate::inventory::control_action;
    let mut session = mission();
    let id = join(&mut session, Role::Agent);
    let opponent = join(&mut session, Role::Human);
    move_to(&mut session, opponent, [0.0, 0.0, -34.0]);
    let player = session
        .state
        .players
        .iter_mut()
        .find(|p| p.id == id)
        .unwrap();
    player.inventory.grant_weapon(WeaponType::Tack);
    player.weapon = WeaponType::Tack;
    for _ in 0..12 {
        assert!(player.inventory.try_fire(WeaponType::Tack));
    }
    let snapshot = session.state.snapshot();
    let loadout = equipment(&session, id);
    let intent = Action {
        weapon_swap: Some(WeaponType::Rail),
        fire: true,
        ..Default::default()
    };
    let action = control_action(id, &snapshot, Some(&loadout), intent.clone());
    assert!(
        !action.fire,
        "no hostile in reach: route to supply, do not shoot"
    );
    assert!(
        action.weapon_swap.is_none(),
        "unowned requests cannot bypass discovery"
    );
    let unchanged = control_action(id, &snapshot, None, intent.clone());
    assert_eq!(
        serde_json::to_value(unchanged).unwrap(),
        serde_json::to_value(intent).unwrap()
    );
    let mut dry = loadout.clone();
    for count in &mut dry.ammo {
        count.rounds = 0;
    }
    let action = control_action(id, &snapshot, Some(&dry), Action::default());
    assert_eq!(action.weapon_swap, Some(WeaponType::Fists));
    assert!(!action.fire);
    assert!(
        action.forward && action.look_at.as_ref().unwrap().player_id.is_none(),
        "seek a supply instead of firing an empty gun"
    );
    let mut dry_held = dry.clone();
    dry_held.selected = WeaponType::Tack;
    let action = control_action(
        id,
        &snapshot,
        Some(&dry_held),
        Action {
            fire: true,
            ..Default::default()
        },
    );
    assert!(
        !action.fire && action.weapon_swap == Some(WeaponType::Fists),
        "an empty gun is put away rather than dry fired"
    );
    let mut close = snapshot.clone();
    close.pickups.clear();
    let me = close.players.iter().find(|p| p.id == id).unwrap().clone();
    let enemy = close.players.iter_mut().find(|p| p.id == opponent).unwrap();
    enemy.x = me.x + 1.4;
    enemy.z = me.z;
    let ally_action = control_action(id, &close, Some(&dry), Action::default());
    assert!(
        !ally_action.fire,
        "another participant is not a melee target"
    );
    // M01 now has campaign allegiance. Test ammunition exhaustion against an
    // actual opposing identity, not the cooperating participant above.
    close
        .players
        .iter_mut()
        .find(|p| p.id == opponent)
        .unwrap()
        .campaign = Some(crate::protocol::CampaignActor::Union {
        kind: crate::protocol::EnemyKind::Clerk,
        phase: crate::protocol::EnemyPhase::Idle,
        phase_started: close.tick,
        phase_ends: close.tick,
    });
    let action = control_action(id, &close, Some(&dry), Action::default());
    assert!(action.fire && action.forward && !action.back);
    close.players.iter_mut().find(|p| p.id == id).unwrap().hp = 0;
    let action = control_action(
        id,
        &close,
        Some(&dry),
        Action {
            fire: true,
            ..Default::default()
        },
    );
    assert!(!action.fire && !action.forward);
}

#[test]
fn personal_discovery_equips_each_participant_including_late_arrivals() {
    let mut session = mission();
    let a = join(&mut session, Role::Human);
    let b = join(&mut session, Role::Agent);
    join(&mut session, Role::Spectator);
    assert_eq!(equipment(&session, a).selected, WeaponType::Fists);
    session.state.set_action(
        a,
        Action {
            weapon_swap: Some(WeaponType::Rail),
            ..Default::default()
        },
    );
    session.tick_messages(0.05);
    assert_eq!(equipment(&session, a).selected, WeaponType::Fists);
    for id in [a, b] {
        move_to(&mut session, id, [0.0, 0.0, -26.0]);
    }
    let public = session.tick_messages(0.05);
    assert!(!public
        .iter()
        .any(|message| matches!(message, ServerMessage::Loadout(_))));
    for id in [a, b] {
        let loadout = equipment(&session, id);
        assert_eq!(loadout.selected, WeaponType::Tack);
        assert!(loadout.owns(WeaponType::Tack));
        assert_eq!(loadout.ammo(AmmoPool::Bullets), 50);
        assert_eq!(loadout.personal_claims, ["bay_tack"]);
    }
    assert!(
        session
            .state
            .pickups
            .iter()
            .find(|pad| pad.id == "bay_tack")
            .unwrap()
            .available
    );
    let private = session.take_unicasts();
    assert!(private
        .iter()
        .filter_map(|(recipient, message)| match message {
            ServerMessage::Loadout(loadout) => Some((*recipient, loadout)),
            _ => None,
        })
        .all(|(recipient, loadout)| recipient == Recipient::Player(loadout.player_id)));
    session.tick_messages(0.05);
    assert_eq!(equipment(&session, a).ammo(AmmoPool::Bullets), 50);
    assert!(!session
        .take_unicasts()
        .iter()
        .any(|(_, message)| matches!(message, ServerMessage::Loadout(_))));
    let late = join(&mut session, Role::Human);
    move_to(&mut session, late, [0.0, 0.0, -26.0]);
    session.tick_messages(0.05);
    assert_eq!(equipment(&session, late).selected, WeaponType::Tack);
}

#[test]
fn contested_ammo_has_one_winner_and_repeat_weapon_discovery_does_not_re_equip() {
    let mut session = mission();
    let a = join(&mut session, Role::Human);
    let b = join(&mut session, Role::Agent);
    for id in [a, b] {
        move_to(&mut session, id, [0.0, 0.0, -26.0]);
    }
    session.tick_messages(0.05);
    for id in [a, b] {
        move_to(&mut session, id, [-4.0, 0.0, -23.0]);
    }
    session.tick_messages(0.05);
    let grants = [
        equipment(&session, a).ammo(AmmoPool::Bullets),
        equipment(&session, b).ammo(AmmoPool::Bullets),
    ];
    assert_eq!(grants.iter().sum::<u16>(), 120);
    assert!(grants.contains(&70) && grants.contains(&50));
    for id in [a, b] {
        move_to(&mut session, id, [6.0, 0.0, -9.0]);
    }
    session.tick_messages(0.05);
    assert_eq!(equipment(&session, a).selected, WeaponType::Flechette);
    session.state.set_action(
        a,
        Action {
            weapon_swap: Some(WeaponType::Tack),
            ..Default::default()
        },
    );
    session.tick_messages(0.05);
    assert_eq!(equipment(&session, a).selected, WeaponType::Tack);
    move_to(&mut session, a, [-17.0, 0.0, -14.0]);
    session.tick_messages(0.05);
    assert_eq!(equipment(&session, a).selected, WeaponType::Tack);
    // Two Flechette pickups on top of the Tack and one bullet box, all one count.
    let bullets = equipment(&session, a).ammo(AmmoPool::Bullets);
    assert!(bullets == 50 + 60 + 60 || bullets == 50 + 20 + 60 + 60);
    assert!(equipment(&session, a)
        .personal_claims
        .contains(&"service_flechette".into()));
}

#[test]
fn campaign_consumables_do_not_regenerate_and_party_retry_restores_them() {
    use crate::sim::PickupKind;
    for kind in [
        PickupKind::Ammo {
            pool: AmmoPool::Bullets,
            rounds: 24,
        },
        PickupKind::Health,
        PickupKind::Armor,
    ] {
        let mut session = mission();
        let a = join(&mut session, Role::Human);
        let b = join(&mut session, Role::Agent);
        let pad = session
            .state
            .pickups
            .iter_mut()
            .find(|p| p.id == "bay_bullets")
            .unwrap();
        pad.kind = kind;
        pad.amount = 25;
        pad.x = 0.0;
        pad.z = -35.0;
        for id in [a, b] {
            move_to(&mut session, id, [0.0, 0.0, -35.0]);
        }
        for player in &mut session.state.players {
            player.hp = 50;
        }
        session.tick_messages(0.05);
        let claimed = session
            .state
            .pickups
            .iter()
            .find(|p| p.id == "bay_bullets")
            .unwrap();
        assert!(!claimed.available);
        assert_eq!(claimed.respawn_timer, None, "campaign stock is finite");
        assert_eq!(
            session
                .state
                .snapshot()
                .pickups
                .iter()
                .find(|p| p.id == "bay_bullets")
                .unwrap()
                .respawn_in,
            None
        );
        for _ in 0..601 {
            session.tick_messages(0.05);
        }
        assert!(
            !session
                .state
                .pickups
                .iter()
                .find(|p| p.id == "bay_bullets")
                .unwrap()
                .available
        );
        match kind {
            PickupKind::Ammo { .. } => assert_eq!(
                equipment(&session, a).ammo(AmmoPool::Bullets)
                    + equipment(&session, b).ammo(AmmoPool::Bullets),
                24
            ),
            PickupKind::Health => {
                assert_eq!(
                    session
                        .state
                        .players
                        .iter()
                        .filter(|p| [a, b].contains(&p.id))
                        .map(|p| p.hp)
                        .sum::<i32>(),
                    125
                )
            }
            PickupKind::Armor => assert_eq!(
                session
                    .state
                    .players
                    .iter()
                    .filter(|p| [a, b].contains(&p.id))
                    .map(|p| p.armor)
                    .sum::<i32>(),
                25
            ),
            PickupKind::Weapon(_) => unreachable!("only consumables are exercised"),
        }
        for player in session
            .state
            .players
            .iter_mut()
            .filter(|p| [a, b].contains(&p.id))
        {
            player.hp = 0;
            player.respawn_timer = Some(60);
        }
        session.tick_messages(0.05);
        assert!(
            session
                .state
                .pickups
                .iter()
                .find(|p| p.id == "bay_bullets")
                .unwrap()
                .available
        );
        assert_eq!(session.state.mission_state().unwrap().attempt, 2);
    }
}

#[test]
fn shots_cooldown_ammunition_and_death_obey_one_simulation_order() {
    let mut session = mission();
    let a = join(&mut session, Role::Human);
    move_to(&mut session, a, [0.0, 0.0, -26.0]);
    session.tick_messages(0.05);
    session.state.set_action(
        a,
        Action {
            fire: true,
            yaw: Some(0.0),
            ..Default::default()
        },
    );
    session.tick_messages(0.05);
    assert_eq!(session.state.shot_results.len(), 1);
    assert!(!session.state.shot_results[0].hit);
    assert_eq!(equipment(&session, a).ammo(AmmoPool::Bullets), 49);
    let rng = session.state.rng_state;
    for _ in 0..4 {
        session.tick_messages(0.05);
        assert!(session.state.shot_results.is_empty());
    }
    assert_eq!(session.state.rng_state, rng);
    assert_eq!(equipment(&session, a).ammo(AmmoPool::Bullets), 49);
    // No reload pause: the held trigger fires on every cooldown until the
    // count is empty, one bullet per shot.
    let mut shots = 1;
    for _ in 0..400 {
        session.tick_messages(0.05);
        shots += session.state.shot_results.len();
    }
    assert_eq!(shots, 50);
    assert_eq!(equipment(&session, a).ammo(AmmoPool::Bullets), 0);
    let rng = session.state.rng_state;
    session.tick_messages(0.05);
    assert!(session.state.shot_results.is_empty());
    assert_eq!(session.state.rng_state, rng);
    assert_eq!(session.state.players[0].fire_cooldown, 0);
    assert_eq!(equipment(&session, a).dry_fire_count, 1);

    session.state.players[0].hp = 0;
    session.state.players[0].respawn_timer = Some(1);
    session.state.set_action(
        a,
        Action {
            fire: true,
            weapon_swap: Some(WeaponType::Tack),
            ..Default::default()
        },
    );
    session.tick_messages(0.05);
    let reset = equipment(&session, a);
    assert_eq!(reset.selected, WeaponType::Fists);
    assert!(reset.personal_claims.is_empty());
    assert!(!reset.owns(WeaponType::Tack));
    assert!(session.state.shot_results.is_empty());
    move_to(&mut session, a, [0.0, 0.0, -26.0]);
    session.tick_messages(0.05);
    assert_eq!(equipment(&session, a).selected, WeaponType::Tack);
}

fn dividing_wall(wall: bool, supply: bool) -> GameState {
    let solids = if wall {
        serde_json::json!([
            {"id":"wall","min":[1,0,-1],"max":[1.3,3,1],"surface":"enamel"}
        ])
    } else {
        serde_json::json!([])
    };
    let supplies = if supply {
        serde_json::json!([
            {"id":"tack","feet":[2,0,0],"grant":{"kind":"weapon","weapon":"tack"},"claim":"personal"}
        ])
    } else {
        serde_json::json!([])
    };
    let json = serde_json::json!({
        "version":1,"map_id":1003,"name":"Discovery fixture","half_extent":8,"ground":"concrete",
        "equipment":"discovery","solids":solids,"supplies":supplies,
        "spawns":[{"id":"entry","feet":[0,0,0],"yaw":0}],
        "landmarks":[{"id":"far","feet":[2,0,0]}]
    });
    GameState::with_authored_map(
        AuthoredMap::read(serde_json::to_vec(&json).unwrap().as_slice()).unwrap(),
    )
}

#[test]
fn fists_have_short_reach_and_cover_blocks_both_punches_and_supply_claims() {
    for (wall, distance, hit) in [(false, 1.6, true), (false, 2.4, false), (true, 1.8, false)] {
        let mut state = dividing_wall(wall, false);
        let a = Uuid::new_v4();
        let b = Uuid::new_v4();
        state.add_player(a, "Puncher".into(), Role::Human);
        state.add_player(b, "Target".into(), Role::Agent);
        state.players[0].x = 0.4;
        state.players[0].z = 0.0;
        state.players[1].x = 0.4 + distance;
        state.players[1].z = 0.0;
        state.set_action(
            a,
            Action {
                fire: true,
                yaw: Some(0.0),
                ..Default::default()
            },
        );
        state.tick(0.05);
        assert_eq!(state.shot_results.len(), 1);
        assert_eq!(state.shot_results[0].hit, hit);
        assert_eq!(state.players[1].hp, if hit { 80 } else { 100 });
        assert_eq!(
            state.shot_results[0].trace.as_ref().unwrap().weapon,
            WeaponType::Fists
        );
    }
    let mut state = dividing_wall(true, true);
    state.add_player(Uuid::new_v4(), "Collector".into(), Role::Human);
    state.players[0].x = 0.4;
    state.tick(0.05);
    assert_eq!(state.players[0].weapon, WeaponType::Fists);
    state.players[0].x = 2.0;
    state.tick(0.05);
    assert_eq!(state.players[0].weapon, WeaponType::Tack);
}

#[test]
fn local_rule_controller_uses_the_authored_supply_route_and_fires_owned_weapons() {
    let mut session = mission();
    session.spawn_bots(2);
    let mut shots = 0;
    for _ in 0..600 {
        session.tick_messages(0.05);
        for shot in &session.state.shot_results {
            let shooter = session
                .state
                .players
                .iter()
                .find(|p| p.id == shot.shooter_id)
                .unwrap();
            let weapon = shot.trace.as_ref().unwrap().weapon;
            assert!(shooter.inventory.owns(weapon));
            if weapon == WeaponType::Tack {
                shots += 1;
            }
        }
    }
    assert!(
        shots >= 12,
        "controllers must acquire and use the sidearm, got {shots}"
    );
}
