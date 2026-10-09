use super::*;
use crate::protocol::{
    CampaignActor, EnemyKind, EnemyPhase, Role, ShotImpact, ShotTrace, WeaponType,
};

fn encounter_document() -> serde_json::Value {
    serde_json::json!({"version":1,"map_id":1098,"name":"Assessor volley fixture","half_extent":30,
        "ground":"concrete","equipment":"discovery","solids":[],
        "spawns":[{"id":"entry","feet":[0,0,0],"yaw":0}],
        "landmarks":[{"id":"exit","feet":[20,0,20]}],
        "encounters":[{"id":"court","regions":[{"min":[-2,0,-2],"max":[2,2,2]}],
            "enemies":[{"id":"assessor","kind":"assessor","feet":[9,4,0],"yaw":std::f32::consts::PI,
                "hover":{"volume":{"min":[8,3,-2],"max":[10,5,2]},"band":[3,5],"patrol":[[9,4,-1],[9,4,1]],"approach":[0,0,0]}}]}]})
}

fn encounter() -> (crate::session::GameSession, Uuid) {
    let map = crate::maps::AuthoredMap::read(
        serde_json::to_vec(&encounter_document())
            .unwrap()
            .as_slice(),
    )
    .unwrap();
    let mut session = crate::session::GameSession::with_authored_map(map);
    let id = Uuid::from_u128(2001);
    session.state.add_player(id, "Visitor".into(), Role::Agent);
    session.tick_messages(0.05);
    (session, id)
}

fn identity(kind: EnemyKind, phase: EnemyPhase) -> Option<CampaignActor> {
    Some(CampaignActor::Union {
        kind,
        phase,
        phase_started: 0,
        phase_ends: 40,
        seated: false,
    })
}

fn world() -> (GameState, Arena) {
    let map = crate::maps::AuthoredMap::read(
        serde_json::to_vec(&serde_json::json!({
            "version":1,"map_id":1099,"name":"Canister contact fixture","half_extent":30,
            "ground":"concrete","equipment":"discovery","solids":[],
            "spawns":[{"id":"entry","feet":[-20,0,-20],"yaw":0}],
            "landmarks":[{"id":"exit","feet":[20,0,20]}]
        }))
        .unwrap()
        .as_slice(),
    )
    .unwrap();
    let mut state = GameState::with_authored_map(map);
    for i in 1..=3 {
        state.add_player(Uuid::from_u128(i), format!("Body {i}"), Role::Agent);
        let player = state.players.last_mut().unwrap();
        player.x = -20.0;
        player.z = -20.0 + i as f32 * 2.0;
        player.y = PLAYER_FLOOR_Y;
    }
    state.players[0].campaign = identity(EnemyKind::Assessor, EnemyPhase::Firing);
    state.players[0].y = PLAYER_FLOOR_Y + 4.0;
    state.players[0].hp = 240;
    state.players[1].campaign = Some(CampaignActor::Participant {});
    state.players[1].x = 10.0;
    state.players[1].z = 0.0;
    let arena = state.current_arena().into_owned();
    (state, arena)
}

fn canister(position: [f32; 3], velocity: [f32; 3]) -> Canister {
    Canister {
        id: 1,
        owner_id: Uuid::from_u128(1),
        position,
        velocity,
        launched_at: 0,
        age_ticks: 0,
    }
}

#[test]
fn assessor_ballistic_root_hits_committed_point_without_tracking() {
    for target in [[8.0, 1.22, 0.0], [24.0, 1.22, 0.0], [12.0, 7.0, 8.0]] {
        let origin = [0.0, 4.6, 0.0];
        let velocity = launch_velocity(origin, target).unwrap();
        assert!((velocity.iter().map(|v| v * v).sum::<f32>().sqrt() - SPEED).abs() < 0.0001);
        let time = (target[0] - origin[0]) / velocity[0];
        let landed: [f32; 3] = std::array::from_fn(|i| {
            origin[i] + velocity[i] * time
                - if i == 1 {
                    0.5 * GRAVITY * time * time
                } else {
                    0.0
                }
        });
        for i in 0..3 {
            assert!((landed[i] - target[i]).abs() < 0.0001);
        }
    }
    for target in [
        [0.0, 1.0, 0.0],
        [25.0, 1.0, 0.0],
        [10.0, 100.0, 0.0],
        [f32::NAN, 0.0, 0.0],
    ] {
        assert!(launch_velocity([0.0, 4.6, 0.0], target).is_none());
    }
}

#[test]
fn assessor_visible_canister_travels_then_bursts_on_body_after_owner_death() {
    let (mut state, arena) = world();
    state.players[0].hp = 0;
    state.assessor_canisters.push(canister(
        [0.0, 1.22, 0.0],
        launch_velocity([0.0, 1.22, 0.0], [10.0, 1.22, 0.0]).unwrap(),
    ));
    for tick in 1..30 {
        state.tick = tick;
        state.tick_assessor_canisters(0.05, &arena, &[], &[]);
        if !state.explosion_results.is_empty() {
            break;
        }
        assert_eq!(state.players[1].hp, 100, "no hitscan or early damage");
        assert_eq!(state.assessor_canister_states().len(), 1);
    }
    assert!(state.assessor_canisters.is_empty());
    assert_eq!(state.explosion_results.len(), 1);
    assert!(state.players[1].hp < 100);
    assert!(state.explosion_results[0]
        .hits
        .iter()
        .any(|hit| hit.target_id == state.players[1].id));
    assert!(
        state.shot_results.is_empty(),
        "an actual canister is never a Fists ray"
    );
}

#[test]
fn assessor_canister_sweeps_thin_cover_and_blocks_blast_through_it() {
    let (mut state, mut arena) = world();
    arena.solids.push(Solid {
        min_x: 8.0,
        max_x: 8.01,
        min_z: -5.0,
        max_z: 5.0,
        bottom: 0.0,
        top: 6.0,
    });
    state
        .assessor_canisters
        .push(canister([7.8, 1.0, 0.0], [32.0, 0.0, 0.0]));
    state.tick = 1;
    state.tick_assessor_canisters(0.05, &arena, &[], &[]);
    assert!(state.assessor_canisters.is_empty());
    assert_eq!(state.explosion_results.len(), 1);
    assert!(state.explosion_results[0].position[0] < 8.0 - grenade::RADIUS);
    assert_eq!(
        state.players[1].hp, 100,
        "actual cover screens the nearby blast"
    );
    assert!(state.explosion_results[0].hits.is_empty());
}

#[test]
fn assessor_dodge_and_finite_age_never_leave_an_invisible_hit() {
    let (mut state, arena) = world();
    state.players[1].z = 5.0;
    let velocity = launch_velocity([0.0, 4.6, 0.0], [10.0, 1.22, 0.0]).unwrap();
    state
        .assessor_canisters
        .push(canister([0.0, 4.6, 0.0], velocity));
    for tick in 1..80 {
        state.tick = tick;
        state.tick_assessor_canisters(0.05, &arena, &[], &[]);
    }
    assert!(state.assessor_canisters.is_empty());
    assert_eq!(
        state.players[1].hp, 100,
        "a sideways dodge escapes the committed low arc"
    );
    state.explosion_results.clear();
    let mut expired = canister([0.0, 20.0, 0.0], [0.0; 3]);
    expired.age_ticks = 79;
    state.assessor_canisters.push(expired);
    state.tick += 1;
    state.tick_assessor_canisters(0.05, &arena, &[], &[]);
    assert!(state.assessor_canisters.is_empty());
    assert!(
        state.explosion_results.is_empty(),
        "expiry creates no blast or hit"
    );
}

#[test]
fn assessor_wreck_hits_only_union_bodies_and_preserves_immunity_and_cover() {
    let (mut state, arena) = world();
    state.players[0].hp = 0;
    state.players[0].x = 0.0;
    state.players[0].z = 0.0;
    state.players[0].y = PLAYER_FLOOR_Y;
    state.players[1].x = 0.0;
    state.players[1].z = 0.8;
    state.players[2].campaign = identity(EnemyKind::Clerk, EnemyPhase::Idle);
    state.players[2].x = 1.2;
    state.players[2].z = 0.0;
    let owner = state.players[0].id;
    state.resolve_assessor_wreck(owner);
    assert_eq!(state.players[1].hp, 100);
    assert!(state.players[2].hp < 100);
    assert_eq!(state.explosion_results[0].hits.len(), 1);
    state.players[2].hp = 100;
    state.spawn_shields.insert(state.players[2].id, 20);
    state.resolve_assessor_wreck(owner);
    assert_eq!(state.players[2].hp, 100);
    state.spawn_shields.clear();
    let mut covered = arena;
    covered.solids.push(Solid {
        min_x: 0.3,
        max_x: 0.4,
        min_z: -2.0,
        max_z: 2.0,
        bottom: 0.0,
        top: 3.0,
    });
    state.resolve_blast(
        &grenade::Blast {
            id: 50,
            owner_id: owner,
            position: [0.0, grenade::RADIUS, 0.0],
            radius: 1.5,
            peak: 45.0,
            source: grenade::BlastSource::AssessorWreck,
        },
        &covered,
    );
    assert_eq!(state.players[2].hp, 100);
}

#[test]
fn assessor_plate_uses_front_underbody_recovery_and_arc_bypass() {
    let (mut state, _) = world();
    let victim = &mut state.players[0];
    victim.x = 0.0;
    victim.z = 0.0;
    victim.yaw = 0.0;
    let mut trace = ShotTrace {
        vehicle_id: None,
        weapon: WeaponType::Tack,
        origin: [10.0, 4.6, 0.0],
        end: [0.0, 4.6, 0.0],
        impact: ShotImpact::Fighter {
            normal: [1.0, 0.0, 0.0],
        },
        pellets: vec![],
    };
    assert_eq!(state.shielded(0, 25, Some(&trace)), 13);
    trace.origin = [-10.0, 4.6, 0.0];
    trace.impact = ShotImpact::Fighter {
        normal: [-1.0, 0.0, 0.0],
    };
    assert_eq!(
        state.shielded(0, 25, Some(&trace)),
        13,
        "closed rear before recovery"
    );
    state.players[0].campaign = identity(EnemyKind::Assessor, EnemyPhase::Recovery);
    assert_eq!(state.shielded(0, 25, Some(&trace)), 25);
    trace.origin = [-10.0, 1.0, 0.0];
    trace.impact = ShotImpact::Fighter {
        normal: [0.0, -1.0, 0.0],
    };
    assert_eq!(state.shielded(0, 25, Some(&trace)), 13);
    trace.impact = ShotImpact::Fighter {
        normal: [0.0, 0.0, 1.0],
    };
    assert_eq!(
        state.shielded(0, 25, Some(&trace)),
        25,
        "side face stays exposed"
    );
    trace.impact = ShotImpact::Fighter {
        normal: [0.0, 1.0, 0.0],
    };
    assert_eq!(
        state.shielded(0, 25, Some(&trace)),
        25,
        "upper face stays exposed"
    );
    trace.weapon = WeaponType::Arc;
    trace.impact = ShotImpact::Fighter {
        normal: [1.0, 0.0, 0.0],
    };
    assert_eq!(state.shielded(0, 18, Some(&trace)), 18);
    assert_eq!(state.shielded(0, 45, None), 45);
    let point = grenade::closest_body_point_stance(
        [3.0, 0.0, 3.0],
        [0.0, 4.0, 0.0],
        state.players[0].campaign,
        false,
    );
    assert_eq!(point, [1.3, 4.0, 1.3]);
}

#[test]
fn assessor_mixed_scatter_faces_commit_each_plate_before_one_armor_share() {
    use crate::protocol::PelletTrace;
    let (mut state, _) = world();
    state.players[0].x = 0.0;
    state.players[0].z = 0.0;
    state.players[0].yaw = 0.0;
    let pellets = vec![
        PelletTrace {
            end: [1.3, 4.6, 0.0],
            impact: ShotImpact::Fighter {
                normal: [1.0, 0.0, 0.0],
            },
        },
        PelletTrace {
            end: [0.0, 4.6, 1.3],
            impact: ShotImpact::Fighter {
                normal: [0.0, 0.0, 1.0],
            },
        },
        PelletTrace {
            end: [-1.3, 4.6, 0.0],
            impact: ShotImpact::Fighter {
                normal: [-1.0, 0.0, 0.0],
            },
        },
    ];
    let trace = ShotTrace {
        vehicle_id: None,
        weapon: WeaponType::Scatter,
        origin: [2.0, 4.6, 0.0],
        end: pellets[0].end,
        impact: pellets[0].impact.clone(),
        pellets,
    };
    assert_eq!(
        state.shielded(0, 30, Some(&trace)),
        20,
        "front5 + side10 + closedrear5"
    );
    state.players[0].campaign = identity(EnemyKind::Assessor, EnemyPhase::Recovery);
    assert_eq!(
        state.shielded(0, 30, Some(&trace)),
        25,
        "rear vents open without stripping front armor"
    );
    state.players[0].armor = 10;
    let (hp, armor, killed) = state.resolve_fighter_hit(1, 0, 30, Some(trace));
    assert_eq!((hp, armor, killed), (15, 10, false));
    assert_eq!(state.players[0].hp, 225);
}

#[test]
fn assessor_refused_capacity_and_serial_never_consume_finite_launch_stock() {
    let (mut session, id) = encounter();
    let owner = session
        .state
        .players
        .iter()
        .find(|p| crate::combat::is_assessor(p.campaign))
        .unwrap()
        .id;
    assert!(
        !session.state.launch_assessor_canister(owner),
        "windup cannot emit a round"
    );
    while session.state.assessor_canisters.is_empty() {
        session.state.spawn_shields.insert(id, 20);
        session.tick_messages(0.05);
        assert!(session.state.tick < 40);
    }
    let first = session.state.assessor_canisters.pop().unwrap();
    let serial = session.state.projectile_serial;
    for index in 0..6 {
        let mut round = canister([0.0, 10.0, 0.0], [0.0; 3]);
        round.id = 100 + index;
        round.owner_id = owner;
        session.state.assessor_canisters.push(round);
    }
    assert!(
        !session.state.launch_assessor_canister(owner),
        "six live per owner is a refusal, not a debit"
    );
    session.state.assessor_canisters.clear();
    for index in 0..64 {
        let mut round = canister([0.0, 10.0, 0.0], [0.0; 3]);
        round.id = 200 + index;
        round.owner_id = Uuid::from_u128(3000 + u128::from(index));
        session.state.assessor_canisters.push(round);
    }
    assert!(
        !session.state.launch_assessor_canister(owner),
        "global cap refuses before stock or serial changes"
    );
    session.state.assessor_canisters.clear();
    session.state.projectile_serial = u32::MAX;
    assert!(
        !session.state.launch_assessor_canister(owner),
        "serial overflow never wraps"
    );
    session.state.projectile_serial = serial;
    session.state.assessor_canisters.push(first);
    let mut launches = 1;
    for _ in 0..1200 {
        session.state.spawn_shields.insert(id, 20);
        session.tick_messages(0.05);
        launches += session
            .state
            .assessor_canister_states()
            .iter()
            .filter(|c| c.age_ticks == 0)
            .count();
    }
    assert_eq!(
        launches, 30,
        "every failed launch leaves its canister available"
    );
}

#[test]
fn assessor_lost_target_or_heavy_stagger_cancels_unlaunched_volley() {
    for stagger in [false, true] {
        let (mut session, id) = encounter();
        let owner = session
            .state
            .players
            .iter()
            .find(|p| crate::combat::is_assessor(p.campaign))
            .unwrap()
            .id;
        while !matches!(
            session
                .state
                .players
                .iter()
                .find(|p| p.id == owner)
                .unwrap()
                .campaign,
            Some(CampaignActor::Union {
                phase: EnemyPhase::Windup,
                ..
            })
        ) {
            session.tick_messages(0.05);
            assert!(session.state.tick < 5);
        }
        if stagger {
            session
                .state
                .players
                .iter_mut()
                .find(|p| p.id == owner)
                .unwrap()
                .hp -= 40;
        } else {
            // Keep the attempt alive while the committed target dies. A whole
            // party wipe correctly removes this encounter before it can report
            // a cancellation phase, which is a different recovery contract.
            let reserve = Uuid::from_u128(2002);
            session
                .state
                .add_player(reserve, "Reserve outside sight".into(), Role::Agent);
            let reserve = session
                .state
                .players
                .iter_mut()
                .find(|p| p.id == reserve)
                .unwrap();
            reserve.x = -25.0;
            reserve.z = -25.0;
            session
                .state
                .players
                .iter_mut()
                .find(|p| p.id == id)
                .unwrap()
                .hp = 0;
        }
        session.tick_messages(0.05);
        let phase = match session
            .state
            .players
            .iter()
            .find(|p| p.id == owner)
            .unwrap()
            .campaign
            .unwrap()
        {
            CampaignActor::Union { phase, .. } => phase,
            _ => panic!("drone identity lost"),
        };
        assert_eq!(
            phase,
            if stagger {
                EnemyPhase::Hit
            } else {
                EnemyPhase::Recovery
            }
        );
        assert!(session.state.assessor_canisters.is_empty());
        for _ in 0..15 {
            session.tick_messages(0.05);
            assert!(session.state.assessor_canisters.is_empty());
        }
    }
}

#[test]
fn assessor_cleanup_and_strict_wire_retain_serial_without_devices() {
    let (mut state, _) = world();
    state.projectile_serial = 99;
    state
        .assessor_canisters
        .push(canister([0.0, 4.0, 0.0], [12.0, 0.0, 0.0]));
    let fact = state.assessor_canister_states().remove(0);
    fact.validate().unwrap();
    for (position, velocity, age, id, owner) in [
        ([f32::NAN, 0.0, 0.0], [0.0; 3], 0, 1, Uuid::from_u128(1)),
        ([0.0; 3], [33.0, 0.0, 0.0], 0, 1, Uuid::from_u128(1)),
        ([0.0; 3], [0.0; 3], 80, 1, Uuid::from_u128(1)),
        ([0.0; 3], [0.0; 3], 0, 0, Uuid::from_u128(1)),
        ([0.0; 3], [0.0; 3], 0, 1, Uuid::nil()),
    ] {
        assert!(AssessorCanisterState {
            id,
            owner_id: owner,
            position,
            velocity,
            age_ticks: age
        }
        .validate()
        .is_err());
    }
    state.clear_traveling_shots();
    assert!(state.assessor_canisters.is_empty());
    assert_eq!(state.projectile_serial, 99);
    state
        .assessor_canisters
        .push(canister([0.0, 4.0, 0.0], [12.0, 0.0, 0.0]));
    state.remove_player(Uuid::from_u128(1));
    assert!(state.assessor_canisters.is_empty());
    assert_eq!(state.projectile_serial, 99);
}

#[test]
fn assessor_authored_hover_proves_full_body_band_approach_and_one_per_group() {
    let doc = encounter_document();
    let decode = |value: &serde_json::Value| {
        crate::maps::AuthoredMap::read(serde_json::to_vec(value).unwrap().as_slice())
    };
    assert!(
        crate::maps::RuntimeMap::Authored(decode(&doc).unwrap()).encounters()[0].enemies[0]
            .hover
            .is_some()
    );
    for (pointer, value) in [
        (
            "/encounters/0/enemies/0/hover/band",
            serde_json::json!([2.5, 5]),
        ),
        (
            "/encounters/0/enemies/0/hover/band",
            serde_json::json!([3, 8]),
        ),
        (
            "/encounters/0/enemies/0/hover/approach",
            serde_json::json!([9, 0, 0]),
        ),
    ] {
        let mut bad = doc.clone();
        *bad.pointer_mut(pointer).unwrap() = value;
        assert!(decode(&bad).is_err(), "rejected {pointer}");
    }
    let mut clipped = doc.clone();
    clipped["solids"] =
        serde_json::json!([{"id":"lip","min":[6.9,3.1,-1],"max":[7.1,3.5,1],"surface":"concrete"}]);
    assert!(
        decode(&clipped).is_err(),
        "1.3m half-width catches a clip missed by the Notary box"
    );
    let mut duplicate = doc.clone();
    let mut other = duplicate["encounters"][0]["enemies"][0].clone();
    other["id"] = "second".into();
    duplicate["encounters"][0]["enemies"]
        .as_array_mut()
        .unwrap()
        .push(other);
    assert!(decode(&duplicate).is_err());
}

#[test]
fn assessor_session_commits_three_real_rounds_six_ticks_apart_and_stops_at_thirty() {
    let (mut session, id) = encounter();
    let mut launched = Vec::new();
    let mut locked_position = None;
    let mut phases = std::collections::BTreeMap::new();
    for _ in 0..1200 {
        session.state.spawn_shields.insert(id, 20);
        session.tick_messages(0.05);
        for fact in session.state.assessor_canister_states() {
            fact.validate().unwrap();
            if fact.age_ticks == 0 {
                launched.push((session.state.tick, fact.id));
            }
        }
        let drone = session
            .state
            .players
            .iter()
            .find(|p| crate::combat::is_assessor(p.campaign))
            .unwrap();
        if let Some(CampaignActor::Union { phase, .. }) = drone.campaign {
            *phases.entry(format!("{phase:?}")).or_insert(0usize) += 1;
        }
        if matches!(
            drone.campaign,
            Some(CampaignActor::Union {
                phase: EnemyPhase::Windup | EnemyPhase::Firing,
                ..
            })
        ) {
            let position = [drone.x, drone.y, drone.z];
            if let Some((previous_tick, previous)) = locked_position {
                if session.state.tick == previous_tick + 1 {
                    assert_eq!(
                        position, previous,
                        "locked body never moves while launching"
                    );
                }
            }
            locked_position = Some((session.state.tick, position));
        } else {
            locked_position = None;
        }
    }
    assert_eq!(
        launched.len(),
        30,
        "phases={phases:?}; players={:?}",
        session.state.snapshot().players
    );
    assert_eq!(
        launched[0].0, 26,
        "full Standard windup before the first actual launch"
    );
    for volley in launched.as_chunks::<3>().0 {
        assert_eq!(volley[1].0 - volley[0].0, 6);
        assert_eq!(volley[2].0 - volley[1].0, 6);
    }
    assert!(launched.windows(2).all(|pair| pair[0].1 < pair[1].1));
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
    assert!(session.state.shot_results.is_empty());
    assert!(session.state.assessor_canisters.is_empty());
}

#[test]
fn assessor_supported_wreck_fires_once_and_living_collision_uses_large_raised_body() {
    let (mut session, id) = encounter();
    let drone = session
        .state
        .players
        .iter()
        .find(|p| crate::combat::is_assessor(p.campaign))
        .unwrap()
        .id;
    let contact = session
        .state
        .contact_bodies()
        .into_iter()
        .find(|b| b.key == drone.to_string())
        .unwrap();
    assert_eq!((contact.height, contact.radius), (1.2, 1.3));
    let player = session
        .state
        .players
        .iter_mut()
        .find(|p| p.id == drone)
        .unwrap();
    player.hp = 0;
    let feet = [player.x, player.y - PLAYER_FLOOR_Y, player.z];
    session
        .state
        .encounters
        .hit(drone, feet, session.state.tick, true);
    let mut wrecks = 0;
    for _ in 0..100 {
        session.tick_messages(0.05);
        wrecks += session
            .state
            .explosion_results
            .iter()
            .filter(|b| b.owner_id == drone && b.radius == 1.5)
            .count();
    }
    assert_eq!(wrecks, 1);
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

#[test]
fn assessor_landing_damage_reaches_the_registered_victim_controller_same_tick() {
    let mut doc = encounter_document();
    doc["encounters"][0]["enemies"].as_array_mut().unwrap().push(serde_json::json!({
        "id":"wreck_victim","kind":"clerk","feet":[9.8,0,0],"yaw":std::f32::consts::PI,"seated":true
    }));
    let map = crate::maps::AuthoredMap::read(serde_json::to_vec(&doc).unwrap().as_slice()).unwrap();
    let mut session = crate::session::GameSession::with_authored_map(map);
    let visitor = Uuid::from_u128(2003);
    session
        .state
        .add_player(visitor, "Landing observer".into(), Role::Agent);
    session.tick_messages(0.05);
    let owner = session
        .state
        .players
        .iter()
        .find(|p| crate::combat::is_assessor(p.campaign))
        .unwrap()
        .id;
    let victim = session
        .state
        .players
        .iter()
        .find(|p| p.name == "wreck_victim")
        .unwrap()
        .id;
    session
        .state
        .players
        .iter_mut()
        .find(|p| p.id == victim)
        .unwrap()
        .hp = 1;
    let drone = session
        .state
        .players
        .iter_mut()
        .find(|p| p.id == owner)
        .unwrap();
    drone.hp = 0;
    let feet = [drone.x, drone.y - PLAYER_FLOOR_Y, drone.z];
    session
        .state
        .encounters
        .hit(owner, feet, session.state.tick, true);
    let mut landed = false;
    for _ in 0..40 {
        session.state.spawn_shields.insert(visitor, 20);
        session.tick_messages(0.05);
        if let Some(blast) = session
            .state
            .explosion_results
            .iter()
            .find(|b| b.owner_id == owner && b.radius == 1.5)
        {
            assert!(blast.hits.iter().any(|h| h.target_id == victim && h.killed));
            assert!(session.state.encounters.registered_in_group(victim, 0));
            assert!(
                matches!(
                    session
                        .state
                        .players
                        .iter()
                        .find(|p| p.id == victim)
                        .unwrap()
                        .campaign,
                    Some(CampaignActor::Union {
                        phase: EnemyPhase::Dead,
                        ..
                    })
                ),
                "the shared resolver updates the real registered controller immediately"
            );
            landed = true;
            break;
        }
    }
    assert!(
        landed,
        "actual supported fall must produce the squad impact"
    );
}
