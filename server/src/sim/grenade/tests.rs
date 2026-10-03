use super::*;

fn arena(solids: Vec<Solid>) -> Arena {
    Arena { half: 20.0, solids }
}

fn grenade(position: [f32; 3], velocity: [f32; 3]) -> Grenade {
    Grenade {
        id: 1,
        owner_id: Uuid::from_u128(1),
        position,
        velocity,
        fuse_ticks: FUSE_TICKS,
        launched_at: 0,
        bounce_count: 0,
    }
}

#[test]
fn swept_contact_cannot_tunnel_through_thin_wall() {
    let mut world = arena(vec![Solid {
        min_x: 0.0,
        max_x: 0.01,
        min_z: -10.0,
        max_z: 10.0,
        bottom: 0.0,
        top: 10.0,
    }]);
    world.half = 200.0;
    let mut device = grenade([-3.0, 2.0, 0.0], [1000.0, 0.0, 0.0]);
    advance(&mut device, 0.05, &world);
    assert!(device.position[0] < -RADIUS);
    assert!(device.velocity[0] < 0.0);
    assert_eq!(device.bounce_count, 1);
    assert!(clear_sphere(device.position, &world));
}

#[test]
fn floor_roof_and_bounds_bounce_use_sphere_clearance() {
    let world = arena(vec![Solid {
        min_x: -5.0,
        max_x: 5.0,
        min_z: -5.0,
        max_z: 5.0,
        bottom: 3.0,
        top: 3.2,
    }]);
    let mut device = grenade([0.0, 2.0, 0.0], [0.0, 60.0, 0.0]);
    advance(&mut device, 0.05, &world);
    assert!(device.position[1] < 3.0 - RADIUS);
    assert!(device.velocity[1] < 0.0);
    let mut floor = grenade([18.0, 0.5, 0.0], [60.0, -20.0, 0.0]);
    advance(&mut floor, 0.05, &world);
    assert!(floor.position[0] < 20.0 - RADIUS);
    assert!(floor.position[1] > RADIUS);
    assert!(clear_sphere(floor.position, &world));
}

#[test]
fn a_resting_grenade_does_not_invent_repeated_bounces_and_bad_delta_is_safe() {
    let world = arena(vec![]);
    let mut device = grenade([0.0, RADIUS + CONTACT_EPSILON, 0.0], [0.0; 3]);
    for _ in 0..40 {
        advance(&mut device, 0.05, &world);
    }
    assert_eq!(device.bounce_count, 0);
    assert!(device.position[1] >= RADIUS);
    let position = device.position;
    advance(&mut device, f32::NAN, &world);
    advance(&mut device, -1.0, &world);
    assert_eq!(device.position, position);
}

#[test]
fn blast_distance_uses_actual_cylinder_and_raised_notary_box() {
    assert_eq!(
        closest_body_point([0.0, 1.0, 0.0], [0.0; 3], None),
        [0.0, 1.0, 0.0]
    );
    assert_eq!(
        closest_body_point([3.0, 5.0, 0.0], [0.0; 3], None),
        [0.5, 1.8, 0.0]
    );
    let notary = crate::protocol::CampaignActor::Union {
        kind: crate::protocol::EnemyKind::Notary,
        phase: crate::protocol::EnemyPhase::Idle,
        phase_started: 0,
        phase_ends: 0,
        seated: false,
    };
    let point = closest_body_point([3.0, 0.0, 3.0], [0.0, 4.0, 0.0], Some(notary));
    assert_eq!(point, [0.65, 4.0, 0.65]);
}

fn combat() -> (GameState, Uuid, Uuid) {
    let map = crate::maps::AuthoredMap::read(
        serde_json::to_vec(&serde_json::json!({
            "version":1,"map_id":1099,"name":"Grenade fixture","half_extent":20,
            "ground":"concrete","equipment":"discovery","solids":[],
            "spawns":[{"id":"entry","feet":[0,0,-6],"yaw":0}],
            "landmarks":[{"id":"exit","feet":[0,0,10]}]
        }))
        .unwrap()
        .as_slice(),
    )
    .unwrap();
    let mut state = GameState::with_authored_map(map);
    state.seed(42);
    let a = Uuid::from_u128(1);
    let b = Uuid::from_u128(2);
    state.add_player(a, "Thrower".into(), crate::protocol::Role::Human);
    state.add_player(b, "Target".into(), crate::protocol::Role::Agent);
    for (i, player) in state.players.iter_mut().enumerate() {
        player.x = i as f32 * 8.0;
        player.z = 0.0;
        player.y = PLAYER_FLOOR_Y;
        player.yaw = 0.0;
    }
    state.players[0].inventory.grant_grenades(6);
    (state, a, b)
}

#[test]
fn ingress_short_tap_held_and_duplicate_sequence_are_counted_once() {
    use crate::protocol::Action;
    let (mut state, owner, _) = combat();
    state.set_action(
        owner,
        Action {
            throw_grenade: true,
            seq: Some(1),
            ..Default::default()
        },
    );
    state.set_action(
        owner,
        Action {
            seq: Some(2),
            ..Default::default()
        },
    );
    state.tick(0.05);
    assert_eq!(state.players[0].inventory.grenades(), 5);
    assert_eq!(state.grenades.len(), 1);
    assert_eq!(state.grenades[0].fuse_ticks, 40);
    state.set_action(
        owner,
        Action {
            throw_grenade: true,
            seq: Some(1),
            ..Default::default()
        },
    );
    for _ in 0..20 {
        state.tick(0.05);
    }
    assert_eq!(state.players[0].inventory.grenades(), 5);
    state.set_action(
        owner,
        Action {
            throw_grenade: true,
            seq: Some(3),
            ..Default::default()
        },
    );
    state.tick(0.05);
    for _ in 0..20 {
        state.tick(0.05);
    }
    assert_eq!(state.players[0].inventory.grenades(), 4);
    assert_eq!(
        state.player_record(owner).unwrap().total.grenades.attacks,
        2
    );
    state
        .player_record(owner)
        .unwrap()
        .validate_for(Some(owner), None)
        .unwrap();
}

#[test]
fn grenade_fuse_is_exact_and_a_dead_owner_keeps_the_launched_device() {
    let (mut state, owner, _) = combat();
    state.set_action(
        owner,
        crate::protocol::Action {
            throw_grenade: true,
            ..Default::default()
        },
    );
    state.tick(0.05);
    state.players[0].hp = 0;
    for _ in 0..39 {
        state.tick(0.05);
    }
    assert_eq!(state.grenades.len(), 1);
    assert_eq!(state.grenades[0].fuse_ticks, 1);
    state.tick(0.05);
    assert!(state.grenades.is_empty());
    assert_eq!(state.explosion_results.len(), 1);
    assert_eq!(state.explosion_results[0].owner_id, owner);
    state.tick(0.05);
    assert!(state.explosion_results.is_empty());
}

#[test]
fn explosion_effective_armor_hp_self_death_and_posthumous_credit() {
    let (mut state, owner, target) = combat();
    state.tick(0.05);
    state.players[0].hp = 30;
    state.players[0].armor = 20;
    state.players[0].killstreak = 3;
    state.players[1].x = 1.0;
    state.players[1].hp = 10;
    state.players[1].armor = 17;
    state.players[0].statistics.grenade_attack();
    state.resolve_explosion(&grenade([0.0, 0.5, 0.0], [0.0; 3]), &arena(vec![]));
    assert_eq!(state.explosion_results[0].hits.len(), 2);
    assert!(state.players[0].hp <= 0);
    assert!(state.players[1].hp <= 0);
    assert_eq!(state.scores[&owner], 1);
    assert_eq!(state.players[0].killstreak, 1);
    let record = state.player_record(owner).unwrap();
    assert_eq!(record.total.hp_lost, 30);
    assert_eq!(record.total.armor_lost, 20);
    assert_eq!(record.total.grenades.hp_damage, 10);
    assert_eq!(record.total.grenades.armor_damage, 17);
    assert_eq!(record.total.grenades.kills, 1);
    assert_eq!(record.total.grenades.damaging_attacks, 1);
    assert_eq!(
        record.total.weapons,
        [crate::protocol::WeaponCounts::default(); 7]
    );
    record.validate_for(Some(owner), None).unwrap();
    let events = state.take_events();
    assert_eq!(
        events
            .iter()
            .filter(|e| matches!(e, crate::protocol::GameEvent::Frag { .. }))
            .count(),
        1
    );
    assert_eq!(state.player_record(target).unwrap().total.deaths, 1);
}

#[test]
fn full_cover_and_radius_limit_block_blast_and_leave_clears_devices() {
    let (mut state, owner, _) = combat();
    state.players[0].x = -8.0;
    state.players[1].x = 2.0;
    let wall = Solid {
        min_x: 0.8,
        max_x: 1.0,
        min_z: -5.0,
        max_z: 5.0,
        bottom: 0.0,
        top: 4.0,
    };
    state.resolve_explosion(&grenade([0.0, 0.5, 0.0], [0.0; 3]), &arena(vec![wall]));
    assert_eq!(state.players[1].hp, 100);
    assert!(state.explosion_results[0].hits.is_empty());
    state.set_action(
        owner,
        crate::protocol::Action {
            throw_grenade: true,
            ..Default::default()
        },
    );
    state.tick(0.05);
    assert_eq!(state.grenades.len(), 1);
    state.remove_player(owner);
    assert!(state.grenades.is_empty());
}

#[test]
fn throw_and_gun_share_one_active_tick_and_refused_throw_does_not_block_gun() {
    let (mut state, owner, _) = combat();
    state.players[0]
        .inventory
        .grant_weapon(crate::protocol::WeaponType::Tack);
    state.players[0].weapon = crate::protocol::WeaponType::Tack;
    state.set_action(
        owner,
        crate::protocol::Action {
            throw_grenade: true,
            fire: true,
            ..Default::default()
        },
    );
    state.tick(0.05);
    let record = state.player_record(owner).unwrap();
    assert_eq!(record.total.attacks(), 1);
    assert_eq!(record.total.grenades.attacks, 1);
    assert!(state.shot_results.is_empty());
    state.tick(0.05);
    assert_eq!(
        state.player_record(owner).unwrap().total.weapons
            [crate::protocol::WeaponType::Tack.index()]
        .attacks,
        1
    );
    state.players[0].clear_input();
    assert!(!state.players[0].throw_requested);
    state.clear_traveling_shots();
    assert!(state.grenades.is_empty());
    assert!(state.explosion_results.is_empty());
}

#[test]
fn refused_launches_never_spend_a_count_and_dead_input_cannot_survive_respawn() {
    let (mut state, owner, _) = combat();
    let action = crate::protocol::Action {
        throw_grenade: true,
        ..Default::default()
    };
    for refusal in 0..5 {
        state.players[0].clear_input();
        state.players[0].hp = 100;
        state.players[0].detached = false;
        state.players[0].grenade_cooldown = 0;
        state.projectile_serial = 0;
        state.grenades.clear();
        match refusal {
            0 => state.players[0].hp = 0,
            1 => state.players[0].detached = true,
            2 => state.players[0].grenade_cooldown = 1,
            3 => state.projectile_serial = u32::MAX,
            _ => {
                for _ in 0..3 {
                    state.grenades.push(grenade([1.0, 2.0, 0.0], [0.0; 3]));
                }
            }
        }
        state.set_action(owner, action.clone());
        assert!(state.launch_grenades().is_empty());
        assert_eq!(state.players[0].inventory.grenades(), 6);
        assert!(!state.players[0].throw_requested);
    }
    state.clear_grenades();
    assert!(state.grenades.is_empty());
    state.projectile_serial = 1;
    state.players[0].detached = false;
    state.players[0].hp = 100;
    state.tick(0.05);
    assert_eq!(state.players[0].inventory.grenades(), 6);
    // An exhausted global budget and an invalid sphere pose are separate refusals.
    for id in 0..64 {
        let mut device = grenade([1.0, 2.0, 0.0], [0.0; 3]);
        device.owner_id = Uuid::from_u128(100 + id);
        state.grenades.push(device);
    }
    state.players[0].throw_requested = true;
    assert!(state.launch_grenades().is_empty());
    state.grenades.clear();
    state.players[0].x = f32::NAN;
    state.players[0].throw_requested = true;
    assert!(state.launch_grenades().is_empty());
    assert_eq!(state.players[0].inventory.grenades(), 6);
}

#[test]
fn empty_throw_allows_gun_fire_and_self_only_blast_has_no_outgoing_credit() {
    let (mut state, owner, _) = combat();
    while state.players[0].inventory.try_throw() {}
    state.players[0]
        .inventory
        .grant_weapon(crate::protocol::WeaponType::Tack);
    state.players[0].weapon = crate::protocol::WeaponType::Tack;
    state.set_action(
        owner,
        crate::protocol::Action {
            throw_grenade: true,
            fire: true,
            ..Default::default()
        },
    );
    state.tick(0.05);
    assert_eq!(
        state.player_record(owner).unwrap().total.grenades.attacks,
        0
    );
    assert_eq!(state.player_record(owner).unwrap().total.attacks(), 1);
    state.players[0].hp = 20;
    state.players[0].killstreak = 4;
    state.resolve_explosion(&grenade([0.0, 0.5, 0.0], [0.0; 3]), &arena(vec![]));
    assert_eq!(state.scores[&owner], 0);
    assert_eq!(state.players[0].killstreak, 0);
    assert_eq!(state.player_record(owner).unwrap().total.grenades.kills, 0);
    assert_eq!(
        state.player_record(owner).unwrap().total.grenades.hp_damage,
        0
    );
    assert!(!state
        .take_events()
        .iter()
        .any(|e| matches!(e, crate::protocol::GameEvent::Frag { .. })));
}

#[test]
fn explicit_throw_preserves_world_lob_and_does_not_invent_ammunition() {
    let (state, owner, target) = combat();
    let snapshot = state.snapshot();
    let mut loadout = state.players[0]
        .inventory
        .state(owner, state.players[0].weapon, state.tick)
        .unwrap();
    let action = crate::protocol::Action {
        throw_grenade: true,
        look_at: Some(crate::protocol::LookAt {
            x: Some(10.0),
            y: Some(8.0),
            z: Some(0.0),
            player_id: None,
        }),
        ..Default::default()
    };
    let result = crate::inventory::control_action(owner, &snapshot, Some(&loadout), action.clone());
    assert!(result.throw_grenade);
    assert_eq!(
        serde_json::to_value(&result.look_at).unwrap(),
        serde_json::to_value(&action.look_at).unwrap()
    );
    loadout.grenades = 0;
    assert!(
        !crate::inventory::control_action(owner, &snapshot, Some(&loadout), action).throw_grenade
    );
    loadout.grenades = 6;
    let stale = crate::protocol::Action {
        throw_grenade: true,
        look_at: Some(crate::protocol::LookAt {
            player_id: Some(target),
            ..Default::default()
        }),
        ..Default::default()
    };
    assert!(
        !crate::inventory::control_action_with_target_filter(
            owner,
            &snapshot,
            Some(&loadout),
            stale,
            false,
            |_, _| false
        )
        .throw_grenade
    );
}

#[test]
fn grenade_staggers_heavy_once_without_changing_difficulty_tells() {
    use crate::protocol::{CampaignActor, CampaignDifficulty, EnemyKind, EnemyPhase, Role};
    for difficulty in [
        CampaignDifficulty::Assisted,
        CampaignDifficulty::Standard,
        CampaignDifficulty::Severe,
    ] {
        let expected = match difficulty {
            CampaignDifficulty::Assisted => (32, 46),
            CampaignDifficulty::Standard => (24, 34),
            CampaignDifficulty::Severe => (20, 28),
        };
        assert_eq!(
            crate::encounters::enemy::attack_timing(EnemyKind::HeavySweeper, difficulty),
            expected
        );
        let doc = serde_json::json!({"version":1,"map_id":1098,"name":"Grenade heavy fixture","half_extent":12,"ground":"concrete","equipment":"discovery","solids":[],
            "spawns":[{"id":"entry","feet":[0,0,-6],"yaw":1.5707964}],"landmarks":[{"id":"exit","feet":[0,0,10]}],
            "encounters":[{"id":"range","regions":[{"min":[-12,0,-12],"max":[12,2,12]}],"enemies":[{"id":"heavy","kind":"heavy_sweeper","feet":[0,0,4],"yaw":4.712389}]}]});
        let map =
            crate::maps::AuthoredMap::read(serde_json::to_vec(&doc).unwrap().as_slice()).unwrap();
        let mut session = crate::session::GameSession::with_authored_map(map);
        session.state.seed(42);
        session
            .state
            .add_player(Uuid::from_u128(1), "Thrower".into(), Role::Human);
        for _ in 0..10 {
            session.tick_messages(0.05);
            if session.state.players.iter().any(|p| {
                matches!(
                    p.campaign,
                    Some(CampaignActor::Union {
                        phase: EnemyPhase::Windup,
                        ..
                    })
                )
            }) {
                break;
            }
        }
        let state = &mut session.state;
        let heavy = state
            .players
            .iter()
            .position(|p| p.is_campaign_enemy())
            .unwrap();
        let CampaignActor::Union {
            phase: EnemyPhase::Windup,
            phase_started,
            phase_ends,
            ..
        } = state.players[heavy].campaign.unwrap()
        else {
            panic!("missing heavy tell");
        };
        assert_eq!(
            phase_ends - phase_started,
            crate::encounters::enemy::attack_timing(
                EnemyKind::HeavySweeper,
                CampaignDifficulty::Standard
            )
            .0
        );
        let center = [state.players[heavy].x, 0.5, state.players[heavy].z];
        state.resolve_explosion(&grenade(center, [0.0; 3]), &arena(vec![]));
        assert_eq!(state.players[heavy].hp, 60);
        session.tick_messages(0.05);
        let state = &mut session.state;
        let CampaignActor::Union {
            phase: EnemyPhase::Hit,
            phase_ends: stagger_end,
            ..
        } = state.players[heavy].campaign.unwrap()
        else {
            panic!("grenade did not stagger heavy");
        };
        // A further substantial, nonlethal blast during that same attack cannot
        // extend the interruption window.
        state.resolve_explosion(
            &grenade([center[0] + 2.7, center[1], center[2]], [0.0; 3]),
            &arena(vec![]),
        );
        session.tick_messages(0.05);
        assert!(
            matches!(session.state.players[heavy].campaign, Some(CampaignActor::Union { phase: EnemyPhase::Hit, phase_ends, .. }) if phase_ends == stagger_end)
        );
    }
}
