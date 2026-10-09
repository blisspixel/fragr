use fragr_server::maps::{AuthoredMap, RuntimeMap};
use fragr_server::movement::{BODY_HEIGHT, CONTACT_EPSILON, EYE_HEIGHT};
use fragr_server::navigation::{NavigationGoal, Navigator, RouteStatus, SEARCH_LIMIT};
use fragr_server::protocol::{
    Action, AmmoPool, CampaignActor, EnemyPhase, LookAt, Role, ServerMessage, WeaponType,
};
use fragr_server::session::GameSession;
use fragr_server::sim::PickupKind;
use fragr_server::sim::{GameState, PLAYER_FLOOR_Y};
use serde_json::{json, Value};
use sha2::Digest;
use std::collections::HashSet;
use std::sync::Arc;
use uuid::Uuid;

const SOURCE: &[u8] = include_bytes!("../maps/test/m13_foundry_development.json");

fn document() -> Value {
    serde_json::from_slice(SOURCE).unwrap()
}

fn point(value: &Value) -> [f32; 3] {
    std::array::from_fn(|i| value[i].as_f64().unwrap() as f32)
}

fn empty_map() -> Arc<AuthoredMap> {
    let mut value = document();
    value["encounters"] = json!([]);
    AuthoredMap::read(serde_json::to_vec(&value).unwrap().as_slice()).unwrap()
}

fn feet(state: &GameState, id: Uuid) -> [f32; 3] {
    let player = state.players.iter().find(|p| p.id == id).unwrap();
    [player.x, player.y - PLAYER_FLOOR_Y, player.z]
}

fn walk(state: &mut GameState, id: Uuid, destinations: &[[f32; 3]]) {
    let mut navigator = Navigator::default();
    for destination in destinations {
        let mut arrived = false;
        for _ in 0..1800 {
            let from = feet(state, id);
            if (from[0] - destination[0]).hypot(from[2] - destination[2]) <= 0.3
                && (from[1] - destination[1]).abs() <= 0.04
            {
                arrived = true;
                break;
            }
            let action = navigator.steer(
                state.map.navigation(),
                from,
                NavigationGoal {
                    feet: *destination,
                    combat: false,
                },
                Action::default(),
                state.tick,
                true,
            );
            assert!(!action.jump, "ordinary foundry route requires a jump");
            state.set_action(id, action);
            state.tick(0.05);
            state.take_events();
            let from = feet(state, id);
            assert!(
                !state.current_arena().solids.iter().any(|solid| {
                    solid.covers(from[0], from[2])
                        && solid.top > from[1] + CONTACT_EPSILON
                        && solid.bottom < from[1] + BODY_HEIGHT - CONTACT_EPSILON
                }),
                "ordinary walking entered a foundry solid at {from:?}"
            );
        }
        assert!(
            arrived,
            "route stalled at {:?} before {destination:?}",
            feet(state, id)
        );
    }
}

#[test]
fn foundry_is_a_strict_standalone_slice_and_all_authored_destinations_return() {
    let map = AuthoredMap::read(SOURCE).expect("strict foundry development source");
    let world = RuntimeMap::Authored(map.clone());
    assert_eq!(world.id(), 1013);
    assert_eq!(world.name(), "The Weight of Permission (development)");
    assert_eq!(world.solids().len(), 121);
    let value = document();
    assert_eq!(value["encounters"].as_array().unwrap().len(), 5);
    assert_eq!(
        value["encounters"]
            .as_array()
            .unwrap()
            .iter()
            .map(|g| g["enemies"].as_array().unwrap().len())
            .sum::<usize>(),
        22
    );
    let state = GameState::with_authored_map(map);
    assert!(state.mission_state().is_none());
    assert!(matches!(
        state.map_info(),
        ServerMessage::MapInfo { mission: None, .. }
    ));
    assert!(state.vehicles.is_empty());
    let entry = point(&value["spawns"][0]["feet"]);
    let destinations = value["landmarks"]
        .as_array()
        .unwrap()
        .iter()
        .chain(value["supplies"].as_array().unwrap())
        .map(|p| point(&p["feet"]))
        .chain(
            value["encounters"]
                .as_array()
                .unwrap()
                .iter()
                .flat_map(|group| group["enemies"].as_array().unwrap())
                .map(|enemy| {
                    point(if enemy.get("hover").is_some() {
                        &enemy["hover"]["approach"]
                    } else {
                        &enemy["feet"]
                    })
                }),
        );
    let mut routes = 0;
    for destination in destinations {
        for (from, to) in [(entry, destination), (destination, entry)] {
            assert_eq!(
                world.navigation().route(from, to, SEARCH_LIMIT).status,
                RouteStatus::Complete,
                "unreachable {from:?} to {to:?}"
            );
            routes += 1;
        }
    }
    assert_eq!(routes, 118);
    let final_min = point(&value["encounters"][4]["regions"][0]["min"]);
    for stock in state
        .pickups
        .iter()
        .filter(|stock| stock.id.starts_with("staging_"))
    {
        assert!(stock.z + fragr_server::sim::PLAYER_RADIUS < final_min[2]);
    }
    println!("foundry strict development source: 121 solids, 22 guards, 19 finite stocks, {routes} return routes");
}

#[test]
fn foundry_floor_ring_and_both_gallery_stairs_use_actual_supported_walking() {
    let mut state = GameState::with_authored_map(empty_map());
    let id = Uuid::from_u128(1013);
    state.add_player(id, "Foundry ordinary route".into(), Role::Human);
    state.start_round();
    walk(
        &mut state,
        id,
        &[
            [0., 0.3, -40.],
            [-23., 0.3, -29.],
            [-34., 0.3, -23.],
            [-34., 0.3, 24.],
            [-23.5, 0.3, 15.],
            [-23.5, 3.3, 29.5],
            [-23.5, 3.3, 49.],
            [0., 3.3, 52.],
            [23.5, 3.3, 49.],
            [23.5, 3.3, 29.5],
            [23.5, 0.3, 15.],
            [21., 0.3, 6.],
            [10., 0.3, 1.],
            [-10., 0.3, 1.],
            [-21., 0.3, 6.],
            [-20., 0.3, -8.],
            [0., 0.3, -23.],
            [20., 0.3, -8.],
            [29., 0.3, -25.],
            [0., 0.3, -40.],
            [0., 0.3, -49.],
        ],
    );
    assert_eq!(state.players.iter().find(|p| p.id == id).unwrap().hp, 100);
    assert!(state.tick > 1000);
    println!(
        "foundry ordinary floor/ring/two-stair loop: {} ticks, no jump or body reset",
        state.tick
    );
}

#[test]
fn foundry_loader_rejects_missing_stairs_bad_support_and_unknown_actor() {
    let mut stairs = document();
    stairs["solids"]
        .as_array_mut()
        .unwrap()
        .retain(|solid| !solid["id"].as_str().unwrap().starts_with("gallery_stair_"));
    assert!(AuthoredMap::read(serde_json::to_vec(&stairs).unwrap().as_slice()).is_err());
    let mut unsupported = document();
    unsupported["supplies"][0]["feet"] = json!([0, 2, -49]);
    assert!(AuthoredMap::read(serde_json::to_vec(&unsupported).unwrap().as_slice()).is_err());
    let mut unknown = document();
    unknown["encounters"][1]["enemies"][0]["kind"] = json!("assessor");
    assert!(AuthoredMap::read(serde_json::to_vec(&unknown).unwrap().as_slice()).is_err());
}

const SUCCESSOR: &[u8] = include_bytes!("../maps/m13-weight-of-permission.json");

fn successor() -> Value {
    serde_json::from_slice(SUCCESSOR).unwrap()
}

/// The practice map stays byte-exact. The successor opens the ladle shaft,
/// keeps the checked stair cheeks, places the office rocket plus the freight
/// Assessor, and carries the optional foundry gates. It is still not a mission.
#[test]
fn foundry_successor_keeps_the_practice_bytes_and_loads_the_rocket_lesson_geometry() {
    let practice: String = sha2::Sha256::digest(SOURCE)
        .iter()
        .map(|byte| format!("{byte:02x}"))
        .collect();
    assert_eq!(
        practice,
        "4995b14d93670ff3b5e3711f3b0977205a3c28700d93662c4515047511d31943"
    );
    let value = successor();
    assert_eq!(value["map_id"], 1013);
    assert_eq!(value["name"], "The Weight of Permission");
    assert_eq!(value["m13"]["relay"], "ring_relay_housing");
    assert_eq!(value["m13"]["protected"][0], "ring_water_feed");
    assert_ne!(value["m13"]["relay"], value["m13"]["protected"][0]);
    assert_eq!(value["m13"]["quarters_encounter"], "quarters_approach");
    assert_eq!(value["m13"]["deck"], "freight_deck");
    let deck = value["solids"]
        .as_array()
        .unwrap()
        .iter()
        .find(|solid| solid["id"] == "freight_deck")
        .expect("freight deck");
    let thickness = deck["max"][1].as_f64().unwrap() - deck["min"][1].as_f64().unwrap();
    assert!((0.05..=2.0).contains(&thickness));
    let landing = value["solids"]
        .as_array()
        .unwrap()
        .iter()
        .find(|solid| solid["id"] == "lift_landing")
        .expect("lift landing");
    let landing_thickness =
        landing["max"][1].as_f64().unwrap() - landing["min"][1].as_f64().unwrap();
    assert!(landing_thickness > 2.0);
    assert_eq!(value["solids"].as_array().unwrap().len(), 158);
    let map = AuthoredMap::read(SUCCESSOR).expect("foundry successor");
    let world = RuntimeMap::Authored(map.clone());
    assert_eq!(world.id(), 1013);
    assert_eq!(world.name(), "The Weight of Permission");
    assert_eq!(world.solids().len(), 158);
    let state = GameState::with_authored_map(map.clone());
    assert!(state.mission_state().is_none());
    assert!(matches!(
        state.map_info(),
        ServerMessage::MapInfo { mission: None, .. }
    ));
    let rocket = state
        .pickups
        .iter()
        .find(|stock| stock.id == "office_rocket")
        .expect("office rocket");
    assert_eq!(rocket.kind, PickupKind::Weapon(WeaponType::Rocket));
    assert!(!rocket.secret);
    let rounds = state
        .pickups
        .iter()
        .find(|stock| stock.id == "office_rockets")
        .expect("office rockets");
    assert_eq!(
        rounds.kind,
        PickupKind::Ammo {
            pool: AmmoPool::Rockets,
            rounds: 4
        }
    );
    let freight = value["encounters"]
        .as_array()
        .unwrap()
        .iter()
        .find(|group| group["id"] == "freight_counterattack")
        .unwrap();
    let assessors = freight["enemies"]
        .as_array()
        .unwrap()
        .iter()
        .filter(|enemy| enemy["kind"] == "assessor")
        .count();
    assert_eq!(assessors, 1);
    let entry = point(&value["spawns"][0]["feet"]);
    for destination in [[17.0, 0.3, 5.0], [19.0, 0.3, 4.5], [-6.0, 0.3, 12.0]] {
        assert_eq!(
            world
                .navigation()
                .route(entry, destination, SEARCH_LIMIT)
                .status,
            RouteStatus::Complete,
            "unreachable lesson point {destination:?}"
        );
    }
    let mut bare = value.clone();
    bare["encounters"] = json!([]);
    bare.as_object_mut().unwrap().remove("m13");
    let mut state = GameState::with_authored_map(
        AuthoredMap::read(serde_json::to_vec(&bare).unwrap().as_slice()).unwrap(),
    );
    let id = Uuid::from_u128(1013);
    state.add_player(id, "Foundry successor route".into(), Role::Human);
    state.start_round();
    walk(
        &mut state,
        id,
        &[
            [0., 0.3, -40.],
            [-23., 0.3, -29.],
            [-34., 0.3, -23.],
            [-34., 0.3, 24.],
            [-23.5, 0.3, 15.],
            [-23.5, 3.3, 29.5],
            [-23.5, 3.3, 49.],
            [0., 3.3, 52.],
            [23.5, 3.3, 49.],
            [23.5, 3.3, 29.5],
            [23.5, 0.3, 15.],
            [17., 0.3, 5.],
            [21., 0.3, 6.],
            [10., 0.3, 1.],
            [-10., 0.3, 1.],
            [-21., 0.3, 6.],
            [-20., 0.3, -8.],
            [0., 0.3, -23.],
            [20., 0.3, -8.],
            [29., 0.3, -25.],
            [0., 0.3, -40.],
            [0., 0.3, -49.],
        ],
    );
    assert_eq!(state.players.iter().find(|p| p.id == id).unwrap().hp, 100);
}

#[derive(Default)]
struct Evidence {
    killed: HashSet<String>,
    shots: usize,
    enemy_attacks: usize,
    reload_presses: usize,
}

fn advance(
    session: &mut GameSession,
    id: Uuid,
    waypoints: &[[f32; 3]],
    required: &[String],
    evidence: &mut Evidence,
    before_gallery: bool,
) {
    let mut navigator = Navigator::default();
    let mut waypoint = 0;
    for _ in 0..4000 {
        let state = &session.state;
        let snapshot = state.snapshot();
        let me = snapshot
            .players
            .iter()
            .find(|p| p.id == id)
            .unwrap_or_else(|| {
                panic!(
                    "foundry participant absent at tick {} feet {:?}",
                    state.tick,
                    feet(state, id)
                )
            });
        assert!(me.hp > 0, "foundry participant died at tick {}", state.tick);
        let from = feet(state, id);
        if before_gallery {
            assert!(
                from[2] < 27.0,
                "approach entered final activation before resupply at {from:?}"
            );
        }
        while waypoint < waypoints.len()
            && (from[0] - waypoints[waypoint][0]).hypot(from[2] - waypoints[waypoint][2]) < 0.4
            && (from[1] - waypoints[waypoint][1]).abs() < 0.05
        {
            waypoint += 1;
        }
        if waypoint == waypoints.len() && required.iter().all(|name| evidence.killed.contains(name))
        {
            session.state.set_action(id, Action::default());
            return;
        }
        let eye = [from[0], from[1] + EYE_HEIGHT, from[2]];
        let targets: Vec<_> = snapshot
            .players
            .iter()
            .filter(|p| {
                p.hp > 0
                    && required.contains(&p.name)
                    && matches!(p.campaign, Some(CampaignActor::Union { .. }))
            })
            .collect();
        let aim = |target: &fragr_server::protocol::PlayerState| {
            [
                target.x,
                target.y - PLAYER_FLOOR_Y
                    + fragr_server::combat::target_height(target.campaign) * 0.9,
                target.z,
            ]
        };
        let target = targets
            .iter()
            .copied()
            .filter(|target| {
                fragr_server::combat::line_of_sight(eye, aim(target), &state.current_arena().solids)
            })
            .min_by(|a, b| {
                (a.x - me.x)
                    .hypot(a.z - me.z)
                    .total_cmp(&(b.x - me.x).hypot(b.z - me.z))
            });
        let player = state.players.iter().find(|p| p.id == id).unwrap();
        let loadout = player
            .inventory
            .state(id, player.weapon, state.tick)
            .unwrap();
        let weapon = [
            WeaponType::Rail,
            WeaponType::Flechette,
            WeaponType::Tack,
            WeaponType::Scatter,
        ]
        .into_iter()
        .find(|weapon| {
            loadout.owns(*weapon)
                && weapon
                    .ammo_pool()
                    .is_some_and(|pool| loadout.ammo(pool) > 0)
        })
        .unwrap_or(WeaponType::Fists);
        let mut action = if let Some(target) = target {
            let point = aim(target);
            let distance = (target.x - me.x).hypot(target.z - me.z);
            let mut action = Action {
                look_at: Some(LookAt {
                    x: Some(point[0]),
                    y: Some(point[1]),
                    z: Some(point[2]),
                    player_id: None,
                }),
                weapon_swap: Some(weapon),
                fire: distance < weapon.range_units(),
                left: (state.tick / 16).is_multiple_of(2),
                right: !(state.tick / 16).is_multiple_of(2),
                ..Default::default()
            };
            if distance >= weapon.range_units() - 1.0 {
                action = navigator.steer(
                    state.map.navigation(),
                    from,
                    NavigationGoal {
                        feet: [target.x, target.y - PLAYER_FLOOR_Y, target.z],
                        combat: true,
                    },
                    action,
                    state.tick,
                    true,
                );
            }
            action
        } else {
            let destination = waypoints
                .get(waypoint)
                .copied()
                .or_else(|| {
                    targets
                        .first()
                        .map(|target| [target.x, target.y - PLAYER_FLOOR_Y, target.z])
                })
                .expect("unfinished foundry approach");
            navigator.steer(
                state.map.navigation(),
                from,
                NavigationGoal {
                    feet: destination,
                    combat: false,
                },
                Action {
                    weapon_swap: Some(weapon),
                    ..Default::default()
                },
                state.tick,
                true,
            )
        };
        if loadout.shots(weapon) == Some(0) && loadout.owns(weapon) {
            action.fire = false;
            action.reload = state.tick.is_multiple_of(2);
            evidence.reload_presses += usize::from(action.reload);
        }
        assert!(!action.jump, "foundry combat route requires a jump");
        session.state.set_action(id, action);
        session.tick_messages(0.05);
        if before_gallery {
            assert!(feet(&session.state, id)[2] < 27.0);
        }
        for shot in &session.state.shot_results {
            if shot.shooter_id == id {
                evidence.shots += 1;
                if shot.killed {
                    evidence.killed.insert(shot.target.clone().unwrap());
                }
            } else {
                evidence.enemy_attacks += 1;
            }
        }
    }
    panic!(
        "foundry fight stalled at {:?}, waypoint {waypoint}, remaining {:?}",
        feet(&session.state, id),
        required
            .iter()
            .filter(|name| !evidence.killed.contains(*name))
            .collect::<Vec<_>>()
    );
}

#[test]
fn foundry_finite_human_magazines_clear_ordered_guards_and_party_reset_restores_entry() {
    let mut session = GameSession::with_authored_map(AuthoredMap::read(SOURCE).unwrap());
    session.state.seed(1013);
    let id = Uuid::from_u128(1013);
    session
        .state
        .add_player(id, "Foundry finite human route".into(), Role::Human);
    session.state.start_round();
    session.state.arm_joined_magazines(id);
    let mut evidence = Evidence::default();
    advance(
        &mut session,
        id,
        &[[2., 0.3, -46.], [-2., 0.3, -46.], [0., 0.3, -44.]],
        &[],
        &mut evidence,
        true,
    );
    let value = document();
    let phases: [&[[f32; 3]]; 5] = [
        &[
            [0., 0.3, -37.],
            [-23., 0.3, -27.],
            [-24., 0.3, -24.],
            [-20., 0.3, -23.],
            [-18., 0.3, -23.],
        ],
        &[
            [-20., 0.3, -18.],
            [-20., 0.3, -8.],
            [0., 0.3, -20.],
            [20., 0.3, -8.],
            [10., 0.3, 1.],
        ],
        &[
            [-10., 0.3, 6.],
            [-18., 0.3, 6.],
            [-24., 0.3, 6.],
            [-10., 0.3, 6.],
            [10., 0.3, 6.],
            [21., 0.3, 6.],
            [23., 0.3, 6.],
            [25., 0.3, 6.],
            [10., 0.3, 6.],
        ],
        &[
            [10., 0.3, 13.],
            [10., 0.3, 23.],
            [-11., 0.3, 22.],
            [-11., 0.3, 23.],
            [-9., 0.3, 23.],
            [-7., 0.3, 23.],
        ],
        &[
            [-23.5, 0.3, 15.],
            [-23.5, 3.3, 29.5],
            [-23.5, 3.3, 49.],
            [12., 3.3, 49.],
            [23.5, 3.3, 35.],
            [23.5, 3.3, 29.5],
            [12., 3.3, 29.5],
            [23.5, 3.3, 49.],
            [0., 3.3, 52.],
        ],
    ];
    for (index, waypoints) in phases.into_iter().enumerate() {
        let required: Vec<_> = value["encounters"][index]["enemies"]
            .as_array()
            .unwrap()
            .iter()
            .map(|enemy| enemy["id"].as_str().unwrap().to_owned())
            .collect();
        advance(
            &mut session,
            id,
            waypoints,
            &required,
            &mut evidence,
            index < 4,
        );
        if index == 3 {
            assert!(
                feet(&session.state, id)[2]
                    < point(&value["encounters"][4]["regions"][0]["min"])[2]
            );
            for authored in value["encounters"][4]["enemies"].as_array().unwrap() {
                let player = session
                    .state
                    .players
                    .iter()
                    .find(|p| p.name == authored["id"].as_str().unwrap())
                    .unwrap();
                assert!(
                    matches!(
                        player.campaign,
                        Some(CampaignActor::Union {
                            phase: EnemyPhase::Idle,
                            ..
                        })
                    ),
                    "resupply woke {}",
                    player.name
                );
                let expected = point(&authored["feet"]);
                assert!((player.x - expected[0]).hypot(player.z - expected[2]) < 0.01);
            }
            let player = session.state.players.iter().find(|p| p.id == id).unwrap();
            assert!(
                !player.inventory.claimed("ring_secret_cells"),
                "clear requires optional ring cells"
            );
            assert!(
                !session
                    .state
                    .pickups
                    .iter()
                    .find(|p| p.id == "staging_cells")
                    .unwrap()
                    .available,
                "pre-final finite cells were not usefully claimed"
            );
        }
    }
    assert_eq!(evidence.killed.len(), 22);
    assert!(evidence.enemy_attacks > 0);
    assert!(evidence.reload_presses > 0);
    let state = &mut session.state;
    let record = state.player_record(id).unwrap();
    assert_eq!(record.total.deaths, 0);
    assert_eq!(
        record
            .total
            .weapons
            .iter()
            .map(|weapon| weapon.kills)
            .sum::<u64>(),
        22
    );
    assert!(state.mission_state().is_none());
    let tick = state.tick;
    state.remove_player(id);
    assert_eq!(state.tick, tick);
    assert!(state.players.is_empty());
    assert_eq!(state.pickups.iter().filter(|p| p.available).count(), 19);
    let next = Uuid::from_u128(2013);
    state.add_player(next, "Fresh foundry practice".into(), Role::Human);
    let entry = feet(state, next);
    assert_eq!([entry[0], entry[2]], [0., -49.]);
    assert!((entry[1] - 0.3).abs() < CONTACT_EPSILON);
    assert!(!state
        .players
        .iter()
        .find(|p| p.id == next)
        .unwrap()
        .inventory
        .owns(WeaponType::Rail));
    println!("foundry finite human clear: {tick} ticks, 22 kills, {} shots, {} enemy attacks, {} reload presses, {} HP and {} armor lost, zero deaths",
        evidence.shots, evidence.enemy_attacks, evidence.reload_presses, record.total.hp_lost, record.total.armor_lost);
}
