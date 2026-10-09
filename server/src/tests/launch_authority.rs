//! Static battlefield authoring gates. The input driver uses ordinary finite
//! inventory, authoritative movement and resolved gunfire without body resets.
use crate::maps::{AuthoredMap, RuntimeMap};
use crate::navigation::Navigator;
use crate::protocol::{Action, GameEvent, LookAt, Role, ServerMessage, WeaponType};
use crate::session::GameSession;
use crate::sim::PLAYER_FLOOR_Y;
use crate::vehicles::{vehicle_step, VehicleInput, VehicleMotion};
use std::sync::{Arc, OnceLock};
use uuid::Uuid;

#[derive(Default)]
struct CombatEvidence {
    shots: usize,
    kills: std::collections::HashSet<String>,
    enemy_shots: usize,
    claimed_supplies: std::collections::HashSet<String>,
}

fn map() -> Arc<AuthoredMap> {
    static MAP: OnceLock<Arc<AuthoredMap>> = OnceLock::new();
    MAP.get_or_init(|| {
        AuthoredMap::read(
            include_bytes!("../../maps/test/launch_authority_development.json").as_slice(),
        )
        .expect("strict Launch Authority development source")
    })
    .clone()
}

#[test]
fn launch_authority_development_has_explicit_fleet_ordered_guards_and_infantry_routes() {
    let world = RuntimeMap::Authored(map());
    assert!(world.has_authored_vehicles());
    assert!(world.mission().is_none());
    assert_eq!(world.encounters().len(), 5);
    assert_eq!(
        world
            .encounters()
            .iter()
            .map(|g| g.enemies.len())
            .sum::<usize>(),
        20
    );
    let (x, z, _, y) = world.spawn(0.0);
    let start = [x, y, z];
    for name in [
        "west_infantry_flank",
        "east_infantry_flank",
        "gantry_control_approach",
        "depot_roof_flank",
        "marksman_flank",
        "apron_resupply_approach",
        "apron_resupply",
        "trench_south_mouth",
        "trench_lane",
        "trench_bunker_west",
        "trench_bunker_east",
        "trench_north_mouth",
    ] {
        let feet = map().landmark(name).unwrap();
        assert_eq!(
            world
                .navigation()
                .route(start, feet, crate::navigation::SEARCH_LIMIT)
                .status,
            crate::navigation::RouteStatus::Complete,
            "foot route to {name}"
        );
    }
    let final_region = &world.encounters()[4].regions[0];
    for pad in world
        .pickups()
        .iter()
        .filter(|p| p.id.starts_with("apron_"))
    {
        assert!(!final_region.contains([pad.x, pad.floor, pad.z]));
        assert!(pad.x + crate::sim::PLAYER_RADIUS < final_region.min[0]);
    }
    for name in ["apron_resupply_approach", "apron_resupply"] {
        assert!(!final_region.contains(map().landmark(name).unwrap()));
    }
    assert!(
        crate::combat::line_of_sight([-46., 3.6, -52.], [5., 27., 41.], &world.arena().solids),
        "gantry frame must be visible from the freight lift"
    );
    let lane = map().landmark("trench_lane").unwrap();
    let eye = [lane[0], lane[1] + crate::movement::EYE_HEIGHT, lane[2]];
    let solids = &world.arena().solids;
    // The parapet covers a standing eye. The lane itself stays open.
    assert!(
        !crate::combat::line_of_sight([-4., crate::movement::EYE_HEIGHT, lane[2]], eye, solids),
        "standing fire from the west field must stop in the trench parapet"
    );
    assert!(
        !crate::combat::line_of_sight([4., crate::movement::EYE_HEIGHT, lane[2]], eye, solids),
        "standing fire from the east field must stop in the trench parapet"
    );
    assert!(
        crate::combat::line_of_sight(
            [lane[0], crate::movement::EYE_HEIGHT, lane[2] - 2.],
            [lane[0], crate::movement::EYE_HEIGHT, lane[2] + 2.],
            solids,
        ),
        "the trench lane stays open along its length"
    );
    assert!(!world
        .arena()
        .blocked_at(lane[0], lane[2], crate::movement::STEP_UP));
    assert!(world
        .arena()
        .blocked_at(-0.5, lane[2], crate::movement::STEP_UP));
    assert!(world
        .arena()
        .blocked_at(1.5, lane[2], crate::movement::STEP_UP));
    for point in [[0., 0., 25.], [-24., 0., 27.], [26., 0., 27.]] {
        assert!(
            !world
                .arena()
                .blocked_at(point[0], point[2], crate::movement::STEP_UP),
            "open crossing blocked at {point:?}"
        );
    }
    for id in ["trench_west_bullets", "trench_east_medkit"] {
        assert!(world.pickups().iter().any(|pad| pad.id == id), "{id}");
    }
    let kinds = |name: &str| {
        world
            .encounters()
            .iter()
            .find(|group| group.id == name)
            .unwrap()
            .enemies
            .iter()
            .map(|enemy| enemy.kind)
            .collect::<Vec<_>>()
    };
    assert_eq!(
        kinds("depot_defense"),
        vec![
            crate::protocol::EnemyKind::Clerk,
            crate::protocol::EnemyKind::Clerk,
            crate::protocol::EnemyKind::Sweeper,
            crate::protocol::EnemyKind::Sweeper,
            crate::protocol::EnemyKind::Turret,
        ]
    );
    assert_eq!(
        kinds("berm_watch"),
        vec![
            crate::protocol::EnemyKind::Clerk,
            crate::protocol::EnemyKind::Clerk,
            crate::protocol::EnemyKind::RangedSweeper,
            crate::protocol::EnemyKind::Turret,
        ]
    );
}

#[test]
fn launch_authority_native_jeep_drives_registered_circuit_without_pose_changes() {
    let world = RuntimeMap::Authored(map());
    let (kind, position, yaw) = world.vehicle_spawns()[0];
    assert_eq!(kind, crate::protocol::VehicleKind::Jeep);
    let mut motion = VehicleMotion {
        position,
        yaw,
        speed: 0.,
        vy: 0.,
    };
    let mut goals = vec![[-24., 0., -12.], [-45., 0., -12.]];
    for index in 0..13 {
        goals.push(map().landmark(&format!("circuit_{index:02}")).unwrap());
    }
    goals.push(map().landmark("circuit_00").unwrap());
    let mut distance = 0.;
    for goal in goals {
        let mut arrived = false;
        for _ in 0..1800 {
            let dx = goal[0] - motion.position[0];
            let dz = goal[2] - motion.position[2];
            if dx.hypot(dz) < 2.8 {
                arrived = true;
                break;
            }
            let wanted = dz.atan2(dx);
            let delta = (wanted - motion.yaw + std::f32::consts::PI)
                .rem_euclid(std::f32::consts::TAU)
                - std::f32::consts::PI;
            let before = motion.position;
            motion = vehicle_step(
                motion,
                VehicleInput {
                    forward: motion.speed < 4.0,
                    left: delta < -0.07,
                    right: delta > 0.07,
                    ..Default::default()
                },
                0.05,
                world.arena(),
            );
            distance += (before[0] - motion.position[0]).hypot(before[2] - motion.position[2]);
        }
        assert!(
            arrived,
            "circuit stopped before {goal:?} at {:?}, yaw {}",
            motion.position, motion.yaw
        );
        assert_eq!(motion.position[1], 0.0, "circuit should remain grounded");
    }
    assert!(
        distance > 400.,
        "whole circuit lost its battlefield scale: {distance}"
    );
    eprintln!("Launch Authority native circuit: {distance:.2}m without pose changes");
}

fn feet(s: &GameSession, id: Uuid) -> [f32; 3] {
    let me = s.state.players.iter().find(|p| p.id == id).unwrap();
    [me.x, me.y - PLAYER_FLOOR_Y, me.z]
}

fn drive(
    s: &mut GameSession,
    id: Uuid,
    nav: &mut Navigator,
    goal: [f32; 3],
    evidence: &mut CombatEvidence,
    hold_fire: bool,
) {
    let snapshot = s.state.snapshot();
    let me = snapshot
        .players
        .iter()
        .find(|p| p.id == id)
        .unwrap_or_else(|| {
            panic!(
                "infantry absent at tick{} feet{:?}, hp{}, goal{goal:?}, guards{:?}",
                s.state.tick,
                feet(s, id),
                s.state.players.iter().find(|p| p.id == id).unwrap().hp,
                s.state
                    .players
                    .iter()
                    .filter(|p| p.is_campaign_enemy() && p.hp > 0)
                    .map(|p| (&p.name, p.hp, p.x, p.z))
                    .collect::<Vec<_>>()
            )
        });
    assert!(
        me.hp > 0,
        "ordinary infantry driver died at tick{} feet{:?}",
        s.state.tick,
        feet(s, id)
    );
    let player = s.state.players.iter().find(|p| p.id == id).unwrap();
    let loadout = player
        .inventory
        .state(id, player.weapon, s.state.tick)
        .unwrap();
    let eye = [
        me.x,
        me.y - PLAYER_FLOOR_Y + crate::movement::EYE_HEIGHT,
        me.z,
    ];
    let visible = snapshot
        .players
        .iter()
        .filter(|_| !hold_fire)
        .filter(|p| me.is_hostile_to(p))
        .filter(|p| s.state.encounters.is_active_enemy(p.id))
        .filter(|p| {
            let target = [
                p.x,
                p.y - PLAYER_FLOOR_Y + crate::combat::target_height(p.campaign) * 0.85,
                p.z,
            ];
            crate::combat::line_of_sight(eye, target, &s.state.map.arena().solids)
                && (p.x - me.x).hypot(p.z - me.z) < 35.
        })
        .min_by(|a, b| {
            (a.x - me.x)
                .hypot(a.z - me.z)
                .total_cmp(&(b.x - me.x).hypot(b.z - me.z))
        });
    let intent = if let Some(target) = visible {
        let point = [
            target.x,
            target.y - PLAYER_FLOOR_Y + crate::combat::target_height(target.campaign) * 0.85,
            target.z,
        ];
        let mut left = (s.state.tick / 16).is_multiple_of(2);
        // Keep the apron duel in its ordinary eastern staging lane. A tell
        // dodge must not accidentally become the explicit final advance.
        if s.state.encounters.is_awake(3) && !s.state.encounters.is_awake(4) {
            let yaw = (point[2] - me.z).atan2(point[0] - me.x);
            let side = if left { 1.0 } else { -1.0 };
            let candidate = [
                me.x + yaw.sin() * side * 0.25,
                0.,
                me.z - yaw.cos() * side * 0.25,
            ];
            let region = &s.state.map.encounters()[4].regions[0];
            if candidate[0] < region.max[0] + crate::movement::RADIUS
                && candidate[0] > region.min[0] - crate::movement::RADIUS
                && candidate[2] > region.min[2] - crate::movement::RADIUS
            {
                left = !left;
            }
        }
        Action {
            fire: true,
            weapon_swap: Some(WeaponType::Flechette),
            look_at: Some(LookAt {
                x: Some(point[0]),
                y: Some(point[1]),
                z: Some(point[2]),
                player_id: None,
            }),
            left,
            right: !left,
            ..Default::default()
        }
    } else {
        Action {
            forward: true,
            look_at: Some(LookAt {
                x: Some(goal[0]),
                y: Some(goal[1] + 1.6),
                z: Some(goal[2]),
                player_id: None,
            }),
            ..Default::default()
        }
    };
    let action = crate::inventory::control_action_with_objective(
        id,
        &snapshot,
        Some(&loadout),
        intent,
        true,
    );
    let staged_apron = !s.state.encounters.is_awake(4)
        && me.x > 24.0
        && me.z > 26.0
        && goal[0] > 24.0
        && goal[2] > 26.0;
    let action = if visible.is_some() || hold_fire || staged_apron {
        action
    } else {
        nav.steer_snapshot(s.state.map.navigation(), id, &snapshot, action)
    };
    s.state.set_action(id, action);
    for message in s.tick_messages(0.05) {
        if let ServerMessage::Event(GameEvent::Pickup {
            player_id,
            pickup_id,
            amount,
            ..
        }) = message
        {
            if player_id == id && amount.is_some_and(|gain| gain > 0) {
                evidence.claimed_supplies.insert(pickup_id);
            }
        }
    }
    assert!(
        s.state.vehicles.iter().all(|v| v.state.seat(id).is_none()),
        "infantry clear must never occupy a seat"
    );
    for shot in &s.state.shot_results {
        if shot.shooter_id == id {
            assert!(
                shot.trace
                    .as_ref()
                    .is_some_and(|trace| trace.vehicle_id.is_none()),
                "infantry fire must not use the mount"
            );
            evidence.shots += 1;
            if shot.killed {
                evidence.kills.insert(shot.target.clone().unwrap());
            }
        } else {
            evidence.enemy_shots += 1;
        }
    }
}

#[test]
fn launch_authority_every_group_clears_on_foot_with_present_absent_and_destroyed_jeep() {
    for fleet in ["present", "absent", "destroyed"] {
        let mut s = GameSession::with_authored_map(map());
        s.state.seed(42);
        let id = Uuid::from_u128(1014);
        s.state.add_player(id, "Infantry".into(), Role::Agent);
        match fleet {
            "absent" => s.state.vehicles.clear(),
            "destroyed" => {
                s.state.vehicles[0].damage(400, None);
                assert_eq!(s.state.vehicles[0].state.hp, 0);
            }
            _ => {}
        }
        let mut nav = Navigator::default();
        let mut evidence = CombatEvidence::default();
        let goals = [
            [-46., 2., -54.],
            [-46., 0., -42.],
            [-38., 0., -40.],
            [-36., 0., -40.],
            [-32., 0., -40.],
            [-32., 0., -35.8],
            [-36., 0., -35.8],
            [-25., 0., -36.],
            [-35.5, 0., -30.],
            [-35.5, 0., -21.],
            [-41.5, 0., -32.],
            [-41.5, 3.5, -16.2],
            [-35., 3.5, -20.],
            [-41.5, 3.5, -16.2],
            [-41.5, 0., -32.],
            [-26., 0., -30.],
            [-26., 0., -25.5],
            [-24., 0., -13.],
            [-9., 0., -24.],
            [-9., 0., -22.],
            [-20., 0., -12.],
            [-20., 0., 6.],
            [-20., 0., 8.],
            [-18.5, 0., 8.],
            [-22., 0., 16.],
            [-22., 0., 25.],
            [0., 0., 25.],
            [22., 0., 25.],
            [22., 0., 16.],
            [20., 0., 8.],
            [20., 0., 10.],
            [18.5, 0., 10.],
            [18.5, 0., 8.],
            [26., 0., 16.],
            [40., 0., 20.],
            [40., 0., 28.],
            [40., 0., 39.],
            [26., 0.2, 39.],
            [26., 0., 35.],
        ];
        for goal in goals {
            for step in 0..1800 {
                let from = feet(&s, id);
                if (from[0] - goal[0]).hypot(from[2] - goal[2]) < 0.5
                    && (from[1] - goal[1]).abs() < 0.3
                {
                    break;
                }
                drive(&mut s, id, &mut nav, goal, &mut evidence, false);
                assert!(
                    !s.state.encounters.is_awake(4),
                    "premature gantry awakening at {:?} toward {goal:?}",
                    feet(&s, id)
                );
                assert!(
                    step < 1799,
                    "{fleet} infantry could not reach {goal:?} from {:?}; kills{}",
                    feet(&s, id),
                    s.state
                        .players
                        .iter()
                        .filter(|p| p.is_campaign_enemy() && p.hp <= 0)
                        .count()
                );
            }
        }
        // Finish the apron fight before ordinary held-fire travel to the
        // western staging stock. Neither a supply nor its approach is a final
        // encounter trigger. No body, health or inventory values are changed.
        for _ in 0..8000 {
            if (0..4).all(|i| s.state.encounters.is_complete(i)) {
                break;
            }
            let group = (0..4)
                .find(|i| !s.state.encounters.is_complete(*i))
                .unwrap();
            let goal = s
                .state
                .players
                .iter()
                .find(|p| {
                    p.is_campaign_enemy() && p.hp > 0 && s.state.encounters.is_active_enemy(p.id)
                })
                .map(|p| [p.x, p.y - PLAYER_FLOOR_Y, p.z])
                .unwrap_or([26., 0., 36.5]);
            let goal = if group == 3 { [26., 0., 36.5] } else { goal };
            drive(&mut s, id, &mut nav, goal, &mut evidence, false);
            assert!(
                !s.state.encounters.is_awake(4),
                "apron fight crossed final trigger at {:?}",
                feet(&s, id)
            );
        }
        assert!((0..4).all(|i| s.state.encounters.is_complete(i)));
        assert!(
            !s.state.encounters.is_awake(4),
            "final fight woke before resupply"
        );
        for goal in [
            [26., 0., 27.],
            map().landmark("apron_resupply_approach").unwrap(),
            [-24., 0., 31.],
            [-24., 0., 33.],
            map().landmark("apron_resupply").unwrap(),
        ] {
            let mut arrived = false;
            for _ in 0..1800 {
                let from = feet(&s, id);
                if (from[0] - goal[0]).hypot(from[2] - goal[2]) < 0.5 {
                    arrived = true;
                    break;
                }
                drive(&mut s, id, &mut nav, goal, &mut evidence, true);
                assert!(
                    !s.state.encounters.is_awake(4),
                    "resupply woke final guards at {:?}",
                    feet(&s, id)
                );
                assert!(!s.state.map.encounters()[4].regions[0].contains(feet(&s, id)));
            }
            assert!(
                arrived,
                "{fleet}: resupply approach blocked toward {goal:?}"
            );
        }
        for stock in ["apron_bullets", "apron_shells", "apron_medkit"] {
            let pad = s.state.pickups.iter().find(|p| p.id == stock).unwrap();
            let player = s.state.players.iter().find(|p| p.id == id).unwrap();
            if evidence.claimed_supplies.contains(stock) {
                assert!(!pad.available, "claimed campaign stock stays consumed");
            } else {
                // Full bags and undamaged players correctly leave unneeded
                // stocks for later. Do not invent damage or discard inventory
                // merely to force a claim in this ordinary fought route.
                assert!(
                    match pad.kind {
                        crate::sim::PickupKind::Ammo { pool, .. } =>
                            !player.inventory.needs_ammo(pool),
                        crate::sim::PickupKind::Health => player.hp == crate::sim::PLAYER_MAX_HP,
                        _ => false,
                    },
                    "{fleet}: useful {stock} was not claimed through ordinary walking"
                );
            }
        }
        assert!(evidence.claimed_supplies.contains("apron_bullets"));
        // This is the first intentional advance into the final region.
        let final_push = [5., 0., 36.];
        for _ in 0..1800 {
            let from = feet(&s, id);
            if (from[0] - final_push[0]).hypot(from[2] - final_push[2]) < 0.5 {
                break;
            }
            drive(&mut s, id, &mut nav, final_push, &mut evidence, false);
        }
        assert!(
            s.state.encounters.is_awake(4),
            "explicit final push must wake final guards"
        );
        for _ in 0..8000 {
            if (0..5).all(|i| s.state.encounters.is_complete(i)) {
                break;
            }
            let group = (0..5)
                .find(|i| !s.state.encounters.is_complete(*i))
                .unwrap();
            let approaches = [
                [-25., 0., -36.],
                [-24., 0., -13.],
                [-22., 0., 16.],
                [5., 0., 36.],
                [5., 0., 44.5],
            ];
            let goal = s
                .state
                .players
                .iter()
                .find(|p| {
                    p.is_campaign_enemy() && p.hp > 0 && s.state.encounters.is_active_enemy(p.id)
                })
                .map(|p| {
                    if crate::combat::is_notary(p.campaign) {
                        s.state.map.encounters()[group]
                            .enemies
                            .iter()
                            .find(|e| e.id == p.name)
                            .unwrap()
                            .hover
                            .as_ref()
                            .unwrap()
                            .approach
                    } else {
                        [p.x, p.y - PLAYER_FLOOR_Y, p.z]
                    }
                })
                .unwrap_or(approaches[group]);
            drive(&mut s, id, &mut nav, goal, &mut evidence, false);
        }
        assert!(
            (0..5).all(|i| s.state.encounters.is_complete(i)),
            "{fleet}: ordered groups did not all clear, kills{:?}, phases{:?}, live{:?}",
            evidence.kills,
            (0..5)
                .map(|i| (
                    s.state.encounters.is_awake(i),
                    s.state.encounters.is_complete(i)
                ))
                .collect::<Vec<_>>(),
            s.state
                .players
                .iter()
                .filter(|p| p.is_campaign_enemy() && p.hp > 0)
                .map(|p| (&p.name, p.hp, p.x, p.z))
                .collect::<Vec<_>>()
        );
        assert_eq!(evidence.kills.len(), 20);
        if fleet == "absent" {
            assert!(s.state.vehicles.is_empty(), "removed fleet stays absent");
        }
        assert!(evidence.shots > 20);
        assert!(
            evidence.enemy_shots > 0,
            "must exercise the actual enemy controllers"
        );
        assert!(s
            .state
            .players
            .iter()
            .find(|p| p.id == id)
            .unwrap()
            .inventory
            .owns(WeaponType::Flechette));
        eprintln!(
            "Launch Authority {fleet}:20 guards,{} ordinary shots,{} enemy attacks,{} ticks,{} HP",
            evidence.shots,
            evidence.enemy_shots,
            s.state.tick,
            s.state.players.iter().find(|p| p.id == id).unwrap().hp
        );
    }
}
