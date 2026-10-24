//! The free local controller completes Planned Works on every tier with a
//! carried late-campaign kit, through actual movement, strips and fire.
use crate::maps::AuthoredSource;
use crate::protocol::{CampaignDifficulty, MissionId};

pub(super) struct RouteReport {
    pub departed_tick: u64,
    pub hp: i32,
    pub objectives: Vec<(String, u64)>,
    pub hopped: bool,
    pub strip_struck: bool,
    pub paver_interrupted: bool,
    /// Wire receipts for the client readers: map infos, mission messages and
    /// snapshots carrying preparing and working strips and a thrusting pack.
    pub native: serde_json::Value,
}

pub(super) fn run_route(difficulty: CampaignDifficulty, seed: u64) -> RouteReport {
    use crate::{
        inventory::control_action_with_target_filter,
        mission::MissionClient,
        navigation::{Navigation, Navigator},
        protocol::{Action, AmmoPool, MissionPhase, MissionReady, Role, WeaponType},
        session::GameSession,
    };
    use uuid::Uuid;
    let mut session = GameSession::with_authored_map(
        AuthoredSource::Mission(MissionId::PlannedWorks)
            .load()
            .unwrap(),
    );
    session.state.set_campaign_difficulty(difficulty).unwrap();
    let id = Uuid::from_u128(1919);
    session.state.use_replay_ids();
    session.state.seed(seed);
    session.state.add_player(id, "Route".into(), Role::Agent);
    {
        // A bounded kit standing in for the carried Episode V arsenal. Never
        // replenished in combat; map supplies are the only refills.
        let player = session
            .state
            .players
            .iter_mut()
            .find(|p| p.id == id)
            .unwrap();
        for weapon in [
            WeaponType::Tack,
            WeaponType::Flechette,
            WeaponType::Repeater,
            WeaponType::Scatter,
            WeaponType::Rail,
            WeaponType::Arc,
            WeaponType::Rocket,
        ] {
            player.inventory.grant_weapon(weapon);
        }
        player.inventory.grant_ammo(AmmoPool::Bullets, 200);
        player.inventory.grant_ammo(AmmoPool::Cells, 40);
        player.weapon = WeaponType::Repeater;
    }
    assert!(session.state.acknowledge_mission(
        id,
        MissionReady {
            id: MissionId::PlannedWorks,
            attempt: 1,
        },
    ));
    let mut client = MissionClient::default();
    let mut navigator = Navigator::default();
    let mut tells = crate::mission::route_skill::TellReader::default();
    let mut previous = None;
    let mut navigation = None;
    let mut objectives = Vec::new();
    let mut hopped = false;
    let mut departed = None;
    let mut maps = Vec::new();
    let mut messages = Vec::new();
    let mut snapshots = Vec::new();
    let mut last_state = serde_json::Value::Null;
    let mut seen_preparing = false;
    let mut seen_working = false;
    let mut seen_thrust = false;
    for _ in 0..24_000 {
        let map = &session.state.map;
        if previous.as_ref() != Some(map) {
            client
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
            client
                .replace_map_with_m19(
                    map.m19_geometry().as_ref(),
                    map.half_extent(),
                    &map.arena().solids,
                    map.presentation_ref(),
                )
                .unwrap();
            maps.push(serde_json::to_value(session.state.map_info()).unwrap());
            navigation = Some(Navigation::shared(map.arena().clone()).unwrap());
            previous = Some(map.clone());
            navigator.clear();
        }
        let state = session.state.mission_state().unwrap();
        state.validate(session.state.tick).unwrap();
        client.observe(session.state.tick, state.clone()).unwrap();
        let wire = serde_json::to_value(&state).unwrap();
        if wire != last_state {
            messages.push(serde_json::json!({"map_index": maps.len() - 1,
                "message": {"type": "mission", "tick": session.state.tick, "state": wire.clone()}}));
            last_state = wire;
        }
        let facts = state.m19.as_ref().unwrap();
        if facts.completed.len() > objectives.len() {
            objectives.push((facts.completed.last().unwrap().clone(), session.state.tick));
        }
        if state.phase == MissionPhase::Departed {
            departed = Some(session.state.tick);
            break;
        }
        let player = session.state.players.iter().find(|p| p.id == id).unwrap();
        assert!(
            player.hp > 0,
            "{difficulty:?} route died at tick {} [{:.1},{:.1},{:.1}] after {objectives:?}",
            session.state.tick,
            player.x,
            player.y - crate::sim::PLAYER_FLOOR_Y,
            player.z
        );
        hopped |= player.jet_thrusting;
        let loadout = player
            .inventory
            .state(id, player.weapon, session.state.tick)
            .unwrap();
        let snapshot = session.state.snapshot();
        let solids = session.state.map.arena().solids.clone();
        let preparing = snapshot.paver_strips.iter().any(|s| !s.working);
        let working = snapshot.paver_strips.iter().any(|s| s.working);
        let thrust = snapshot.jetpacks.iter().any(|p| p.thrusting);
        if (preparing && !seen_preparing) || (working && !seen_working) || (thrust && !seen_thrust)
        {
            seen_preparing |= preparing;
            seen_working |= working;
            seen_thrust |= thrust;
            snapshots.push(serde_json::json!({"map_index": maps.len() - 1,
                "message": crate::protocol::ServerMessage::Snapshot(snapshot.clone())}));
        }
        let mut combat = control_action_with_target_filter(
            id,
            &snapshot,
            Some(&loadout),
            Action::default(),
            // The free local agent always plays with a mission objective.
            true,
            |me, other| {
                use crate::protocol::{CampaignActor, EnemyPhase};
                let awake = matches!(other.campaign, Some(CampaignActor::Hostile { phase, .. }) if !matches!(phase, EnemyPhase::Idle | EnemyPhase::Dead));
                (other.x - me.x).hypot(other.z - me.z) <= if awake { 32.0 } else { 20.0 }
                    && crate::combat::line_of_sight(
                        [
                            me.x,
                            me.y - crate::sim::PLAYER_FLOOR_Y + crate::movement::EYE_HEIGHT,
                            me.z,
                        ],
                        [
                            other.x,
                            other.y - crate::sim::PLAYER_FLOOR_Y
                                + crate::combat::aim_height(other.campaign),
                            other.z,
                        ],
                        &solids,
                    )
            },
        );
        if player.hp < 60 {
            if let Some(health) = snapshot
                .pickups
                .iter()
                .filter(|p| p.available && p.kind == "health")
                .min_by(|a, b| {
                    (a.x - player.x)
                        .hypot(a.z - player.z)
                        .total_cmp(&(b.x - player.x).hypot(b.z - player.z))
                })
            {
                combat = Action {
                    forward: true,
                    look_at: Some(crate::protocol::LookAt {
                        x: Some(health.x),
                        y: Some(health.y),
                        z: Some(health.z),
                        player_id: None,
                    }),
                    ..Default::default()
                };
            }
        }
        let mut action = client.steer_with_equipment(
            &mut navigator,
            navigation.as_ref().unwrap(),
            id,
            &snapshot,
            combat,
            Some(&loadout),
        );
        if action.fire
            && action
                .look_at
                .as_ref()
                .is_some_and(|look| look.player_id.is_some())
            && !action.forward
        {
            action.left = (session.state.tick / 20).is_multiple_of(2);
            action.right = !action.left;
        }
        let every = std::env::var("FRAGR_M19_TRACE_EVERY")
            .ok()
            .and_then(|v| v.parse::<u64>().ok())
            .unwrap_or(100);
        let window = std::env::var("FRAGR_M19_TRACE_FROM")
            .ok()
            .and_then(|v| v.parse::<u64>().ok())
            .unwrap_or(0);
        if std::env::var_os("FRAGR_M19_ROUTE_TRACE").is_some()
            && session.state.tick >= window
            && session.state.tick.is_multiple_of(every)
        {
            let enemies: Vec<String> = snapshot
                .players
                .iter()
                .filter(|p| p.hp > 0 && p.id != id)
                .map(|p| {
                    format!(
                        "{:?}@[{:.0},{:.0},{:.0}]",
                        p.campaign.map(|c| match c {
                            crate::protocol::CampaignActor::Hostile { kind, phase, .. } =>
                                format!("{kind:?}/{phase:?}"),
                            _ => "other".into(),
                        }),
                        p.x,
                        p.y - crate::sim::PLAYER_FLOOR_Y,
                        p.z
                    )
                })
                .collect();
            eprintln!(
                "t{} [{:.1},{:.1},{:.1}] hp{} obj{:?} fwd{} jump{} look{} fire{} strips{} nav{:?} yaw{:?} {:?}",
                session.state.tick,
                player.x,
                player.y - crate::sim::PLAYER_FLOOR_Y,
                player.z,
                player.hp,
                facts.current.as_ref().map(|c| c.id.clone()),
                action.forward,
                action.jump,
                action.look_at.is_some(),
                action.fire,
                snapshot.paver_strips.len(),
                navigator.debug_route(),
                action.yaw,
                enemies
            );
        }
        let action = tells.evade(&session.state, &snapshot, id, action);
        session.state.set_action(id, action);
        session.tick_messages(0.05);
    }
    let player = session.state.players.iter().find(|p| p.id == id).unwrap();
    let state = session.state.mission_state().unwrap();
    let Some(departed_tick) = departed else {
        panic!(
            "{difficulty:?} stalled at [{:.1},{:.1},{:.1}] after {objectives:?}: {:?}",
            player.x,
            player.y - crate::sim::PLAYER_FLOOR_Y,
            player.z,
            state.m19
        );
    };
    let facts = state.m19.unwrap();
    RouteReport {
        departed_tick,
        hp: player.hp,
        objectives,
        hopped,
        strip_struck: facts.challenges.strip_struck,
        paver_interrupted: facts.challenges.paver_interrupted,
        native: serde_json::json!({"maps": maps, "missions": messages, "snapshots": snapshots}),
    }
}

#[test]
#[ignore = "diagnostic: FRAGR_M19_ROUTE_TRACE=1 cargo test m19_route_trace -- --ignored"]
fn m19_route_trace() {
    let tier = match std::env::var("FRAGR_M19_TIER").as_deref() {
        Ok("assisted") => CampaignDifficulty::Assisted,
        Ok("severe") => CampaignDifficulty::Severe,
        _ => CampaignDifficulty::Standard,
    };
    run_route(tier, 19);
}

#[test]
#[ignore = "seed survey: cargo test -p fragr-server --lib seed_survey -- --ignored --nocapture"]
fn m19_planned_works_seed_survey() {
    crate::mission::route_skill::survey("M19 Planned Works, Standard", 10..26, |seed| {
        let report = run_route(CampaignDifficulty::Standard, seed);
        assert_eq!(report.objectives.len(), 9);
    });
}

#[test]
fn free_local_controller_completes_planned_works_on_every_tier() {
    for difficulty in [
        CampaignDifficulty::Assisted,
        CampaignDifficulty::Standard,
        CampaignDifficulty::Severe,
    ] {
        let mut report = run_route(difficulty, 19);
        eprintln!(
            "{difficulty:?}: departed tick {} hp {} hop {} interrupted {} struck {} {:?}",
            report.departed_tick,
            report.hp,
            report.hopped,
            report.paver_interrupted,
            report.strip_struck,
            report.objectives
        );
        assert_eq!(report.objectives.len(), 9);
        assert!(report.hopped, "the controller uses the jetpack lesson");
        if difficulty == CampaignDifficulty::Standard {
            // The street lesson supplies a worked strip on its own map index.
            report.native["snapshots"].as_array_mut().unwrap().push(
                serde_json::json!({"map_index": 0, "message": super::tests::working_strip_receipt()}),
            );
            let snapshots = report.native["snapshots"].as_array().unwrap();
            let any = |key: &str| {
                snapshots.iter().any(|s| {
                    s["message"][if key == "thrusting" {
                        "jetpacks"
                    } else {
                        "paver_strips"
                    }]
                    .as_array()
                    .is_some_and(|facts| {
                        facts.iter().any(|f| {
                            f[if key == "thrusting" {
                                "thrusting"
                            } else {
                                "working"
                            }] == (key != "preparing")
                        })
                    })
                })
            };
            assert!(
                any("preparing") && any("working") && any("thrusting"),
                "receipts need a preparing strip, a working strip and a thrusting pack: {}",
                snapshots.len()
            );
            let path = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
                .join("../client/golden/m19_native.json");
            let bytes = serde_json::to_string(&report.native).unwrap() + "\n";
            if std::env::var_os("FRAGR_UPDATE_M19_NATIVE").is_some() {
                std::fs::write(&path, &bytes).unwrap();
            }
            assert!(
                std::fs::read_to_string(path).unwrap() == bytes,
                "client/golden/m19_native.json is stale: rerun with FRAGR_UPDATE_M19_NATIVE=1"
            );
        }
    }
}

#[test]
#[ignore = "diagnostic route print"]
fn m19_route_points() {
    let map = AuthoredSource::Mission(MissionId::PlannedWorks)
        .load()
        .unwrap();
    let world = crate::maps::RuntimeMap::Authored(map);
    let parse = |key: &str| -> [f32; 3] {
        let v: Vec<f32> = std::env::var(key)
            .unwrap()
            .split(',')
            .map(|v| v.parse().unwrap())
            .collect();
        [v[0], v[1], v[2]]
    };
    let route =
        world
            .navigation()
            .route(parse("FROM"), parse("TO"), crate::navigation::SEARCH_LIMIT);
    eprintln!("{:?} {} points", route.status, route.points.len());
    for p in &route.points {
        eprintln!("  {:.1},{:.1},{:.1}", p[0], p[1], p[2]);
    }
}

#[test]
#[ignore = "diagnostic steer print"]
fn m19_steer_probe() {
    use crate::navigation::{NavigationGoal, Navigator};
    use crate::protocol::Action;
    let map = AuthoredSource::Mission(MissionId::PlannedWorks)
        .load()
        .unwrap();
    let world = crate::maps::RuntimeMap::Authored(map);
    let mut navigator = Navigator::default();
    for tick in 1..5 {
        let action = navigator.steer(
            world.navigation(),
            [33.8, 0.0, 49.2],
            NavigationGoal {
                feet: [50.0, 0.0, 49.0],
                combat: false,
            },
            Action::default(),
            tick,
            true,
        );
        eprintln!(
            "{tick} fwd {} yaw {:?} {:?}",
            action.forward,
            action.yaw,
            navigator.debug_route()
        );
    }
}
