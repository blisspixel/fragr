use fragr_server::maps::{AuthoredMap, RuntimeMap};
use fragr_server::movement::{BODY_HEIGHT, CONTACT_EPSILON, EYE_HEIGHT};
use fragr_server::navigation::{NavigationGoal, Navigator, RouteStatus, SEARCH_LIMIT};
use fragr_server::protocol::{Action, CampaignActor, LookAt, Role, ServerMessage, WeaponType};
use fragr_server::session::GameSession;
use fragr_server::sim::{GameState, PLAYER_FLOOR_Y};
use serde_json::{json, Value};
use std::collections::HashSet;
use std::sync::Arc;
use uuid::Uuid;

const SOURCE: &[u8] = include_bytes!("../maps/test/m12_habitat_development.json");

fn document() -> Value {
    serde_json::from_slice(SOURCE).unwrap()
}

fn feet(value: &Value) -> [f32; 3] {
    std::array::from_fn(|i| value[i].as_f64().unwrap() as f32)
}

fn unpopulated() -> Arc<AuthoredMap> {
    let mut value = document();
    value["encounters"] = json!([]);
    AuthoredMap::read(serde_json::to_vec(&value).unwrap().as_slice()).unwrap()
}

fn state(map: Arc<AuthoredMap>) -> (GameState, Uuid) {
    let mut state = GameState::with_authored_map(map);
    state.seed(1012);
    let id = Uuid::from_u128(1012);
    state.add_player(id, "Habitat development route".into(), Role::Human);
    state.start_round();
    (state, id)
}

fn walk(state: &mut GameState, id: Uuid, destinations: &[[f32; 3]]) {
    let mut navigator = Navigator::default();
    for destination in destinations {
        let mut arrived = false;
        for _ in 0..1500 {
            let player = state.players.iter().find(|p| p.id == id).unwrap();
            let feet = [player.x, player.y - PLAYER_FLOOR_Y, player.z];
            if (feet[0] - destination[0]).hypot(feet[2] - destination[2]) <= 0.3
                && (feet[1] - destination[1]).abs() <= 0.04
            {
                arrived = true;
                break;
            }
            let action = navigator.steer(
                state.map.navigation(),
                feet,
                NavigationGoal {
                    feet: *destination,
                    combat: false,
                },
                Action::default(),
                state.tick,
                true,
            );
            assert!(!action.jump, "habitat ordinary route requires a jump");
            state.set_action(id, action);
            state.tick(0.05);
            state.take_events();
            let player = state.players.iter().find(|p| p.id == id).unwrap();
            assert_eq!(player.hp, 100, "route changed health");
            let bottom = player.y - PLAYER_FLOOR_Y;
            assert!(
                !state.current_arena().solids.iter().any(|solid| {
                    solid.covers(player.x, player.z)
                        && solid.top > bottom + CONTACT_EPSILON
                        && solid.bottom < bottom + BODY_HEIGHT - CONTACT_EPSILON
                }),
                "body entered a habitat solid"
            );
        }
        let player = state.players.iter().find(|p| p.id == id).unwrap();
        assert!(
            arrived,
            "route stalled at {:?} before {destination:?}",
            [player.x, player.y - PLAYER_FLOOR_Y, player.z]
        );
    }
}

#[test]
fn habitat_development_is_a_strict_discovery_slice_without_mission_unlock() {
    let map = AuthoredMap::read(SOURCE).unwrap();
    let runtime = RuntimeMap::Authored(map);
    assert_eq!(runtime.id(), 1012);
    assert_eq!(runtime.name(), "Terms of Cooperation (development)");
    assert_eq!(runtime.solids().len(), 104);
    let value = document();
    assert_eq!(value["supplies"].as_array().unwrap().len(), 18);
    assert_eq!(value["encounters"].as_array().unwrap().len(), 4);
    assert_eq!(
        value["encounters"]
            .as_array()
            .unwrap()
            .iter()
            .map(|group| group["enemies"].as_array().unwrap().len())
            .sum::<usize>(),
        15
    );
    let state = GameState::with_authored_map(AuthoredMap::read(SOURCE).unwrap());
    assert!(state.mission_state().is_none());
    assert!(matches!(
        state.map_info(),
        ServerMessage::MapInfo { mission: None, .. }
    ));
    assert_eq!(state.snapshot().mode_name, "Campaign development");
    assert!(state.vehicles.is_empty());
}

#[test]
fn habitat_every_stock_enemy_approach_and_named_room_has_a_return_route() {
    let value = document();
    let runtime = RuntimeMap::Authored(AuthoredMap::read(SOURCE).unwrap());
    let entry = feet(&value["spawns"][0]["feet"]);
    let destinations = value["landmarks"]
        .as_array()
        .unwrap()
        .iter()
        .chain(value["supplies"].as_array().unwrap())
        .map(|point| feet(&point["feet"]))
        .chain(
            value["encounters"]
                .as_array()
                .unwrap()
                .iter()
                .flat_map(|group| group["enemies"].as_array().unwrap())
                .map(|enemy| {
                    feet(if enemy.get("hover").is_some() {
                        &enemy["hover"]["approach"]
                    } else {
                        &enemy["feet"]
                    })
                }),
        );
    let mut count = 0;
    for destination in destinations {
        for (from, to) in [(entry, destination), (destination, entry)] {
            assert_eq!(
                runtime.navigation().route(from, to, SEARCH_LIMIT).status,
                RouteStatus::Complete,
                "unreachable {from:?} to {to:?}"
            );
            count += 1;
        }
    }
    assert_eq!(count, 90);
}

#[test]
fn habitat_both_greenhouse_flanks_bridge_and_utility_loop_use_actual_walking() {
    let (mut state, id) = state(unpopulated());
    walk(
        &mut state,
        id,
        &[
            [0.0, 0.3, -29.0],
            [0.0, 0.3, -25.7],
            [0.0, 0.3, -15.0],
            [-11.0, 0.3, -19.0],
            [-12.0, 0.3, -10.0],
            [-12.0, 0.3, 2.4],
            [-12.0, 0.3, 12.0],
            [0.0, 0.3, 22.0],
            [0.0, 0.3, 32.0],
            [16.0, 0.3, 26.0],
            [12.0, 0.3, 12.0],
            [12.0, 0.3, 2.4],
            [15.0, 0.3, -5.0],
            [0.0, 0.3, -7.0],
            [0.0, 1.3, 2.4],
            [0.0, 0.3, 10.0],
            [-17.0, 0.3, 23.0],
            [-23.0, 0.3, 6.0],
            [-23.0, 0.3, -15.0],
            [0.0, 0.3, -32.0],
        ],
    );
    assert!(state.tick > 500);
}

#[test]
fn habitat_stock_claims_need_no_scene_teleport_or_unreachable_secret() {
    let (mut state, id) = state(unpopulated());
    for supply in document()["supplies"].as_array().unwrap() {
        walk(&mut state, id, &[feet(&supply["feet"])]);
    }
    let player = state.players.iter().find(|p| p.id == id).unwrap();
    for weapon in ["arrival_pistol", "arrival_rifle", "bay_scatter", "bay_rail"] {
        assert!(player.inventory.claimed(weapon), "did not reach {weapon}");
    }
}

#[test]
fn habitat_loader_refuses_blocked_bridge_sealed_loop_and_unknown_actor() {
    for (id, lower, upper) in [
        ("bridge_crush", [-2.0, 1.3, 1.4], [2.0, 2.8, 3.4]),
        ("utility_seal", [-25.5, 0.3, -8.0], [-20.5, 3.4, 19.5]),
    ] {
        let mut bad = document();
        bad["solids"].as_array_mut().unwrap().push(json!({
            "id": id, "min": lower, "max": upper, "surface": "service_steel"
        }));
        assert!(
            AuthoredMap::read(serde_json::to_vec(&bad).unwrap().as_slice()).is_err(),
            "{id}"
        );
    }
    let mut bad = document();
    bad["encounters"][2]["enemies"][2]["kind"] = json!("unsupported_habitat_actor");
    assert!(AuthoredMap::read(serde_json::to_vec(&bad).unwrap().as_slice()).is_err());
    let mut bad = document();
    bad["supplies"][0]["id"] = bad["landmarks"][0]["id"].clone();
    assert!(AuthoredMap::read(serde_json::to_vec(&bad).unwrap().as_slice()).is_err());
}

#[test]
fn habitat_greenhouse_bridge_and_pump_towers_remain_visible_from_market() {
    let runtime = RuntimeMap::Authored(AuthoredMap::read(SOURCE).unwrap());
    let eye = [0.0, 0.3 + EYE_HEIGHT, -10.0];
    for landmark in [[0.0, 1.4, 2.4], [-5.0, 6.6, 16.1], [5.0, 6.6, 16.1]] {
        assert!(
            fragr_server::combat::line_of_sight(eye, landmark, &runtime.arena().solids),
            "hidden habitat landmark {landmark:?}"
        );
    }
}

fn advance_fighting(
    session: &mut GameSession,
    id: Uuid,
    waypoints: &[[f32; 3]],
    required: &[String],
    killed: &mut HashSet<String>,
) -> usize {
    let mut navigator = Navigator::default();
    let mut waypoint = 0;
    let mut enemy_attacks = 0;
    for _ in 0..3000 {
        let state = &session.state;
        let snapshot = state.snapshot();
        let me = snapshot.players.iter().find(|p| p.id == id).unwrap();
        assert!(
            me.hp > 0,
            "ordinary habitat participant died at tick {}",
            state.tick
        );
        let from = [me.x, me.y - PLAYER_FLOOR_Y, me.z];
        while waypoint < waypoints.len()
            && (from[0] - waypoints[waypoint][0]).hypot(from[2] - waypoints[waypoint][2]) < 0.4
            && (from[1] - waypoints[waypoint][1]).abs() < 0.05
        {
            waypoint += 1;
        }
        if waypoint == waypoints.len() && required.iter().all(|name| killed.contains(name)) {
            session.state.set_action(id, Action::default());
            return enemy_attacks;
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
        let aim_point = |target: &fragr_server::protocol::PlayerState| {
            // Precise controller aim is test input. Hits still trace through
            // the world and retain the actual weapon's spread and cooldown.
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
                fragr_server::combat::line_of_sight(
                    eye,
                    aim_point(target),
                    &state.current_arena().solids,
                )
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
            let point = aim_point(target);
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
                .expect("unfinished combat has an approach");
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
        }
        assert!(!action.jump, "habitat combat route requires a jump");
        session.state.set_action(id, action);
        session.tick_messages(0.05);
        for shot in &session.state.shot_results {
            if shot.shooter_id == id && shot.killed {
                killed.insert(shot.target.clone().unwrap());
            }
            if shot.shooter_id != id {
                enemy_attacks += 1;
            }
        }
    }
    let state = &session.state;
    let me = state.players.iter().find(|p| p.id == id).unwrap();
    panic!(
        "bounded fight stalled at [{},{},{}], waypoint {}, remaining {:?}",
        me.x,
        me.y - PLAYER_FLOOR_Y,
        me.z,
        waypoint,
        required
            .iter()
            .filter(|name| !killed.contains(*name))
            .collect::<Vec<_>>()
    );
}

#[test]
fn habitat_finite_human_kit_clears_actual_groups_and_last_participant_leave_resets_stock() {
    let mut session = GameSession::with_authored_map(AuthoredMap::read(SOURCE).unwrap());
    session.state.seed(1012);
    let id = Uuid::from_u128(1012);
    session
        .state
        .add_player(id, "Habitat combat route".into(), Role::Human);
    session.state.start_round();
    session.state.arm_joined_magazines(id);
    let mut killed = HashSet::new();
    let mut enemy_attacks = advance_fighting(
        &mut session,
        id,
        &[
            [0.0, 0.3, -29.0],
            [2.0, 0.3, -28.0],
            [0.0, 0.3, -27.5],
            [-1.4, 0.3, -25.7],
        ],
        &[],
        &mut killed,
    );
    let value = document();
    let phases: [&[[f32; 3]]; 4] = [
        &[[0.0, 0.3, -23.0]],
        &[
            [-11.0, 0.3, -13.0],
            [-11.0, 0.3, -19.0],
            [-11.0, 0.3, -17.0],
            [0.0, 0.3, -12.5],
            [10.5, 0.3, -12.5],
            [15.0, 0.3, -11.0],
            [15.0, 0.3, -8.5],
            [13.0, 0.3, -8.5],
            [15.0, 0.3, -1.5],
        ],
        &[[12.0, 0.3, 2.4], [12.0, 0.3, 10.0], [-12.0, 0.3, 8.0]],
        &[
            [-23.0, 0.3, 12.0],
            [-17.0, 0.3, 23.0],
            [-12.0, 0.3, 25.0],
            [10.0, 0.3, 20.5],
            [16.0, 0.3, 26.0],
            [0.0, 0.3, 32.0],
        ],
    ];
    for (index, waypoints) in phases.into_iter().enumerate() {
        let names = value["encounters"][index]["enemies"]
            .as_array()
            .unwrap()
            .iter()
            .map(|enemy| enemy["id"].as_str().unwrap().to_owned())
            .collect::<Vec<_>>();
        enemy_attacks += advance_fighting(&mut session, id, waypoints, &names, &mut killed);
    }
    let state = &mut session.state;
    assert_eq!(killed.len(), 15);
    let record = state.player_record(id).unwrap();
    assert_eq!(record.total.deaths, 0);
    assert!(enemy_attacks > 0, "session must drive actual enemy attacks");
    assert_eq!(
        record
            .total
            .weapons
            .iter()
            .map(|weapon| weapon.kills)
            .sum::<u64>(),
        15
    );
    assert!(record.mission_elapsed_ticks.is_none());
    assert!(state.mission_state().is_none());
    let tick = state.tick;
    state.remove_player(id);
    assert_eq!(state.tick, tick, "party reset rewound the process clock");
    assert!(state.players.is_empty());
    assert_eq!(state.pickups.iter().filter(|p| p.available).count(), 18);
    let next = Uuid::from_u128(1013);
    state.add_player(next, "Fresh habitat practice".into(), Role::Human);
    let player = state.players.iter().find(|p| p.id == next).unwrap();
    assert_eq!([player.x, player.z], [0.0, -32.0]);
    assert!((player.y - PLAYER_FLOOR_Y - 0.3).abs() < CONTACT_EPSILON);
    assert!(!player.inventory.owns(WeaponType::Rail));
    println!(
        "habitat finite-kit clear: {} ticks, 15 kills, {} HP lost, {} armor lost, {} enemy attacks, zero deaths",
        tick, record.total.hp_lost, record.total.armor_lost, enemy_attacks
    );
}
