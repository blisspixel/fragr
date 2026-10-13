//! Canonical foundry traversal, finite human input and actual lift departure.
use fragr_server::combat::{line_of_sight, target_height};
use fragr_server::maps::AuthoredSource;
use fragr_server::mission::MissionClient;
use fragr_server::movement::{
    self, Arena, MoveInput, MoveState, BODY_HEIGHT, CONTACT_EPSILON, EYE_HEIGHT,
};
use fragr_server::navigation::{NavigationGoal, Navigator};
use fragr_server::protocol::{
    Action, AmmoPool, CampaignActor, EnemyPhase, LookAt, MissionId, MissionPhase, MissionReady,
    PlayerState, RecordStatus, Role, ServerMessage, WeaponType,
};
use fragr_server::session::GameSession;
use fragr_server::sim::PLAYER_FLOOR_Y;
use serde_json::Value;
use std::collections::HashSet;
use uuid::Uuid;

fn point(value: &Value) -> [f32; 3] {
    std::array::from_fn(|i| value[i].as_f64().unwrap() as f32)
}
fn points(value: &Value) -> Vec<[f32; 3]> {
    value
        .as_array()
        .map(|a| a.iter().map(point).collect())
        .unwrap_or_default()
}
fn names(value: &Value) -> Vec<String> {
    value
        .as_array()
        .map(|a| a.iter().map(|v| v.as_str().unwrap().into()).collect())
        .unwrap_or_default()
}
fn look(p: [f32; 3]) -> LookAt {
    LookAt {
        x: Some(p[0]),
        y: Some(p[1]),
        z: Some(p[2]),
        player_id: None,
    }
}
fn aim(p: &PlayerState) -> [f32; 3] {
    [
        p.x,
        p.y - PLAYER_FLOOR_Y
            + target_height(p.campaign)
                * if fragr_server::combat::is_assessor(p.campaign) {
                    0.5
                } else {
                    0.9
                },
        p.z,
    ]
}
fn near(a: [f32; 3], b: [f32; 3]) -> bool {
    (a[0] - b[0]).hypot(a[2] - b[2]) <= 0.3 && (a[1] - b[1]).abs() <= 0.05
}
fn safe_strafe(me: &PlayerState, arena: &Arena, yaw: f32, left: bool) -> bool {
    let start = MoveState {
        x: me.x,
        y: me.y - PLAYER_FLOOR_Y,
        z: me.z,
        vx: 0.0,
        vy: 0.0,
        vz: 0.0,
        yaw,
    };
    let input = MoveInput {
        left,
        right: !left,
        yaw,
        ..MoveInput::default()
    };
    let mut body = start;
    for _ in 0..8 {
        body = movement::live_step(body, &input, movement::TOP_SPEED, movement::DT_LIVE, arena);
        if body.y < start.y - 0.2 {
            return false;
        }
    }
    (body.x - start.x).hypot(body.z - start.z) > 0.1
}
struct Attempt {
    session: GameSession,
    id: Uuid,
    client: MissionClient,
    killed: HashSet<String>,
    rocket_ticks: HashSet<u64>,
    rocket_ids: HashSet<u32>,
    resolved_rocket_ids: HashSet<u32>,
    rocket_effective_damage: u64,
    last_gallery_guard_held: bool,
    reloads: HashSet<u64>,
    enemy_attacks: usize,
}
impl Attempt {
    fn tick(&mut self, action: Action, label: &str) {
        let before = self
            .session
            .state
            .players
            .iter()
            .find(|p| p.id == self.id)
            .map(|p| (p.hp, p.armor));
        assert!(
            !action.jump,
            "{label}: required route must use ordinary walking"
        );
        self.session.state.set_action(self.id, action);
        let messages = self.session.tick_messages(0.05);
        for message in messages {
            if let ServerMessage::MapInfo {
                map_id,
                m13,
                half_extent,
                solids,
                presentation,
                ..
            } = message
            {
                self.client
                    .replace_map_with_id(
                        map_id,
                        None,
                        false,
                        None,
                        half_extent,
                        &solids,
                        presentation.as_ref(),
                    )
                    .unwrap();
                self.client
                    .replace_map_with_m13(m13.as_ref(), half_extent, &solids, presentation.as_ref())
                    .unwrap();
            }
        }
        let state = &self.session.state;
        let mission = state.mission_state().unwrap();
        self.client
            .observe(state.tick, mission)
            .unwrap_or_else(|e| panic!("{label} tick {}: {e}", state.tick));
        let snapshot = state.snapshot();
        for p in &snapshot.players {
            if p.hp <= 0 && matches!(p.campaign, Some(CampaignActor::Union { .. })) {
                self.killed.insert(p.name.clone());
            }
        }
        for shot in &snapshot.shot_results {
            if shot.shooter_id != self.id {
                self.enemy_attacks += 1;
            }
            if shot.killed {
                if let Some(target) = &shot.target {
                    self.killed.insert(target.clone());
                }
            }
        }
        for rocket in &snapshot.rockets {
            if rocket.owner_id == self.id {
                self.rocket_ticks
                    .insert(state.tick - u64::from(rocket.age_ticks));
                self.rocket_ids.insert(rocket.id);
            }
        }
        for explosion in &snapshot.explosions {
            if self.rocket_ids.contains(&explosion.id)
                && self.resolved_rocket_ids.insert(explosion.id)
            {
                self.rocket_effective_damage += explosion
                    .hits
                    .iter()
                    .filter(|hit| {
                        snapshot.players.iter().any(|p| {
                            p.id == hit.target_id
                                && matches!(p.campaign, Some(CampaignActor::Union { .. }))
                        })
                    })
                    .map(|hit| u64::from(hit.hp_damage) + u64::from(hit.armor_damage))
                    .sum::<u64>();
            }
        }
        let live_supports = snapshot
            .players
            .iter()
            .filter(|p| {
                p.hp > 0
                    && matches!(
                        p.name.as_str(),
                        "gallery_clerk_west"
                            | "gallery_clerk_east"
                            | "gallery_clerk_back"
                            | "gallery_heavy"
                            | "gallery_marksman"
                    )
            })
            .count();
        if live_supports > 0 {
            assert!(!state.mission_state().unwrap().m13.unwrap().challenges.supports_cleared,"{label}: a registered live gallery defender must keep its support-position receipt false");
            self.last_gallery_guard_held |= live_supports == 1;
        }
        let me = state.players.iter().find(|p| p.id == self.id).unwrap();
        if before.is_some_and(|(hp, armor)| me.hp < hp || me.armor < armor) {
            eprintln!(
                "{label}: damage at {} pose {:?} HP{} armor{} shots {:?} explosions {:?}",
                state.tick,
                [me.x, me.y, me.z],
                me.hp,
                me.armor,
                snapshot.shot_results,
                snapshot.explosions
            );
        }
        assert!(
            me.hp > 0,
            "{label}: player died at tick {}, player {:?}, rocket damage {}, shots {:?}, living defenders {:?}",
            state.tick,
            snapshot.players.iter().find(|p| p.id == self.id),
            self.rocket_effective_damage,
            snapshot.shot_results,
            snapshot.players.iter().filter(|p| p.hp > 0 && matches!(p.campaign, Some(CampaignActor::Union { .. }))).collect::<Vec<_>>()
        );
        let feet_y = me.y - PLAYER_FLOOR_Y;
        assert!(
            !state
                .current_arena()
                .solids
                .iter()
                .any(|s| s.covers(me.x, me.z)
                    && s.top > feet_y + CONTACT_EPSILON
                    && s.bottom < feet_y + BODY_HEIGHT - CONTACT_EPSILON),
            "{label}: body entered collision at [{},{},{}]",
            me.x,
            feet_y,
            me.z
        );
        let loadout = me.inventory.state(self.id, me.weapon, state.tick).unwrap();
        for magazine in &loadout.loaded {
            if let Some(tick) = magazine.ready_at {
                self.reloads.insert(tick);
            }
        }
    }
    fn walk_and_fight(
        &mut self,
        route: &[[f32; 3]],
        targets: &[String],
        weapon: WeaponType,
        clear: bool,
        label: &str,
    ) {
        let mut navigator = Navigator::default();
        let mut waypoint = 0;
        let entry = self
            .session
            .state
            .players
            .iter()
            .find(|p| p.id == self.id)
            .unwrap();
        let anchor = [entry.x, entry.z];
        let mut evade_left = true;
        let mut evade_started = None;
        for _ in 0..3600 {
            let state = &self.session.state;
            let snapshot = state.snapshot();
            let me = snapshot.players.iter().find(|p| p.id == self.id).unwrap();
            let feet = [me.x, me.y - PLAYER_FLOOR_Y, me.z];
            while waypoint < route.len() && near(feet, route[waypoint]) {
                waypoint += 1;
            }
            if clear && targets.iter().all(|id| self.killed.contains(id))
                || !clear && waypoint == route.len()
            {
                self.tick(Action::default(), label);
                return;
            }
            if clear && waypoint == route.len() {
                waypoint = 0;
            }
            let eye = [feet[0], feet[1] + EYE_HEIGHT, feet[2]];
            let arena = state.current_arena();
            let target = snapshot
                .players
                .iter()
                .filter(|p| {
                    p.hp > 0
                        && targets.contains(&p.name)
                        && (p.x - me.x).hypot(p.z - me.z) < weapon.range_units().min(35.0)
                        && line_of_sight(eye, aim(p), &arena.solids)
                })
                .min_by(|a, b| {
                    (a.x - me.x)
                        .hypot(a.z - me.z)
                        .total_cmp(&(b.x - me.x).hypot(b.z - me.z))
                });
            let mut action = if let Some(target) = target {
                let yaw = (target.z - me.z).atan2(target.x - me.x);
                let tell = snapshot
                    .players
                    .iter()
                    .filter(|p| {
                        p.hp > 0
                            && matches!(
                                p.campaign,
                                Some(CampaignActor::Union {
                                    phase: EnemyPhase::Windup
                                        | EnemyPhase::Leaping
                                        | EnemyPhase::Firing,
                                    ..
                                })
                            )
                            && line_of_sight(eye, aim(p), &arena.solids)
                    })
                    .min_by(|a, b| {
                        (a.x - me.x)
                            .hypot(a.z - me.z)
                            .total_cmp(&(b.x - me.x).hypot(b.z - me.z))
                    });
                let mut evade = false;
                if let Some(CampaignActor::Union { phase_started, .. }) =
                    tell.and_then(|p| p.campaign)
                {
                    if evade_started != Some(phase_started) {
                        evade_started = Some(phase_started);
                        let (dx, dz) = movement::wish_dir(
                            &MoveInput {
                                left: evade_left,
                                right: !evade_left,
                                ..MoveInput::default()
                            },
                            yaw,
                        );
                        let offset = [me.x - anchor[0], me.z - anchor[1]];
                        if offset[0].hypot(offset[1]) > 1.0 && offset[0] * dx + offset[1] * dz > 0.0
                        {
                            evade_left = !evade_left;
                        }
                        if !safe_strafe(me, &arena, yaw, evade_left)
                            && safe_strafe(me, &arena, yaw, !evade_left)
                        {
                            evade_left = !evade_left;
                        }
                    }
                    // Preserve one direction through a committed tell, like
                    // rendered QA. Periodic reversals re-enter a locked blast.
                    evade = safe_strafe(me, &arena, yaw, evade_left);
                }
                Action {
                    look_at: Some(look(aim(target))),
                    weapon_swap: Some(weapon),
                    fire: true,
                    left: evade && evade_left,
                    right: evade && !evade_left,
                    ..Action::default()
                }
            } else {
                assert!(
                    !route.is_empty(),
                    "{label}: combat needs a registered search route"
                );
                navigator.steer(
                    state.map.navigation(),
                    feet,
                    NavigationGoal {
                        feet: route[waypoint.min(route.len() - 1)],
                        combat: false,
                    },
                    Action::default(),
                    state.tick,
                    true,
                )
            };
            if action.fire {
                let p = state.players.iter().find(|p| p.id == self.id).unwrap();
                let loadout = p.inventory.state(self.id, p.weapon, state.tick).unwrap();
                assert!(
                    loadout.owns(weapon),
                    "{label}: weapon was not physically claimed"
                );
                assert!(
                    weapon
                        .ammo_pool()
                        .is_some_and(|pool| loadout.ammo(pool) > 0),
                    "{label}: finite {weapon:?} exhausted"
                );
                if loadout.shots(weapon) == Some(0) {
                    action.fire = false;
                    action.reload = state.tick.is_multiple_of(2);
                }
            }
            self.tick(action, label);
        }
        let p = self
            .session
            .state
            .players
            .iter()
            .find(|p| p.id == self.id)
            .unwrap();
        panic!(
            "{label}: stalled at [{},{},{}] waypoint {waypoint}, remaining {:?}",
            p.x,
            p.y - PLAYER_FLOOR_Y,
            p.z,
            targets
                .iter()
                .filter(|t| !self.killed.contains(*t))
                .collect::<Vec<_>>()
        );
    }
    fn use_control(&mut self, key: &str, label: &str) {
        let state = &self.session.state;
        let g = state.map.m13_geometry().unwrap();
        let target = match key {
            "workers_released" => &g.release,
            "lift_boarded" | "party_departed" => &g.departure,
            _ => panic!("unknown control {key}"),
        };
        let point = target
            .point(
                state.map.presentation_ref().unwrap(),
                &state.current_arena().solids,
            )
            .unwrap();
        self.tick(
            Action {
                look_at: Some(look(point)),
                ..Action::default()
            },
            label,
        );
        assert!(
            self.session
                .state
                .mission_state()
                .unwrap()
                .prompts
                .iter()
                .any(|p| p.player_id == self.id),
            "{label}: no real physical Use prompt; point {point:?}, mission {:?}, player {:?}",
            self.session.state.mission_state(),
            self.session
                .state
                .snapshot()
                .players
                .iter()
                .find(|p| p.id == self.id)
        );
        self.tick(
            Action {
                look_at: Some(look(point)),
                interact: true,
                ..Action::default()
            },
            label,
        );
        self.tick(
            Action {
                look_at: Some(look(point)),
                ..Action::default()
            },
            label,
        );
    }
    fn single_shot(&mut self, weapon: WeaponType, aim: [f32; 3], label: &str) {
        let pool = weapon.ammo_pool().expect("authored finite shot");
        let player = self
            .session
            .state
            .players
            .iter()
            .find(|p| p.id == self.id)
            .unwrap();
        let loadout = player
            .inventory
            .state(self.id, player.weapon, self.session.state.tick)
            .unwrap();
        assert!(loadout.owns(weapon), "{label}: weapon must be claimed");
        let before = loadout.ammo(pool);
        assert!(before > 0, "{label}: shot requires real finite ammo");
        for _ in 0..80 {
            let state = &self.session.state;
            let p = state.players.iter().find(|p| p.id == self.id).unwrap();
            let current = p.inventory.state(self.id, p.weapon, state.tick).unwrap();
            let reload = current.shots(weapon) == Some(0);
            self.tick(
                Action {
                    look_at: Some(look(aim)),
                    weapon_swap: Some(weapon),
                    fire: !reload,
                    reload: reload && state.tick.is_multiple_of(2),
                    ..Action::default()
                },
                label,
            );
            let state = &self.session.state;
            let p = state.players.iter().find(|p| p.id == self.id).unwrap();
            if p.inventory
                .state(self.id, p.weapon, state.tick)
                .unwrap()
                .ammo(pool)
                < before
            {
                self.tick(Action::default(), label);
                return;
            }
        }
        panic!("{label}: bounded ordinary reload/fire never consumed ammunition");
    }
}

#[test]
fn m13_finite_human_walks_foundry_fires_real_rockets_and_rides_to_departure() {
    let map = AuthoredSource::Mission(MissionId::WeightOfPermission)
        .load()
        .unwrap();
    let mut session = GameSession::with_authored_map(map);
    session.state.seed(1013);
    let id = Uuid::from_u128(13130);
    session
        .state
        .add_player(id, "Foundry ordinary route".into(), Role::Human);
    session.state.arm_joined_magazines(id);
    let mut client = MissionClient::default();
    let ServerMessage::MapInfo {
        map_id,
        m13,
        half_extent,
        solids,
        presentation,
        ..
    } = session.state.map_info()
    else {
        panic!("map info")
    };
    client
        .replace_map_with_id(
            map_id,
            None,
            false,
            None,
            half_extent,
            &solids,
            presentation.as_ref(),
        )
        .unwrap();
    client
        .replace_map_with_m13(m13.as_ref(), half_extent, &solids, presentation.as_ref())
        .unwrap();
    client
        .observe(session.state.tick, session.state.mission_state().unwrap())
        .unwrap();
    assert!(session.state.acknowledge_mission(
        id,
        MissionReady {
            id: MissionId::WeightOfPermission,
            attempt: 1
        }
    ));
    let mut attempt = Attempt {
        session,
        id,
        client,
        killed: HashSet::new(),
        rocket_ticks: HashSet::new(),
        rocket_ids: HashSet::new(),
        resolved_rocket_ids: HashSet::new(),
        rocket_effective_damage: 0,
        last_gallery_guard_held: false,
        reloads: HashSet::new(),
        enemy_attacks: 0,
    };
    // Read the authored QA route shared with rendered acceptance; no private
    // inventory grants, teleports, enemy deletions or objective edits.
    let path = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../client/qa/m13_weight_of_permission.json");
    let manifest: Value = serde_json::from_slice(&std::fs::read(path).unwrap()).unwrap();
    let mut weapon = WeaponType::Flechette;
    for value in manifest["states"].as_array().unwrap() {
        let label = value["name"].as_str().unwrap();
        if let Some(name) = value["weapon"].as_str() {
            weapon = serde_json::from_value(Value::String(name.to_lowercase())).unwrap();
        }
        attempt.walk_and_fight(
            &points(&value["walk_to"]),
            &names(&value["combat_travel_targets"]),
            weapon,
            false,
            label,
        );
        if let Some(combat) = value.get("combat") {
            attempt.walk_and_fight(
                &points(&combat["search_route"]),
                &names(&combat["required"]),
                weapon,
                true,
                label,
            );
        }
        if let Some(control) = value["interact"].as_str() {
            attempt.use_control(control, label);
        }
        if value["trigger"].as_str() == Some("fire") {
            attempt.single_shot(weapon, point(&value["look_at"]), label);
            if value["expect_m13_relay_disabled"].as_bool() == Some(true) {
                assert!(
                    attempt
                        .session
                        .state
                        .mission_state()
                        .unwrap()
                        .m13
                        .unwrap()
                        .relay_disabled,
                    "{label}: relay needs actual resolved hit"
                );
            }
        }
        let wait_ticks = value["wait_ticks"].as_f64().unwrap_or(0.0);
        assert!(
            (0.0..=400.0).contains(&wait_ticks) && wait_ticks.fract() == 0.0,
            "{label}: wait must be a bounded whole tick count"
        );
        for _ in 0..wait_ticks as u64 {
            attempt.tick(Action::default(), label);
        }
        if value["expect_phase"].as_str() == Some("departed") {
            for _ in 0..400 {
                if attempt.session.state.mission_state().unwrap().phase == MissionPhase::Departed {
                    break;
                }
                attempt.tick(Action::default(), label);
            }
        }
        let facts = attempt.session.state.mission_state().unwrap();
        if value.get("expect_m13_completed").is_some() {
            assert_eq!(
                facts.m13.as_ref().unwrap().completed,
                names(&value["expect_m13_completed"]),
                "{label}"
            );
        }
        let p = attempt
            .session
            .state
            .players
            .iter()
            .find(|p| p.id == id)
            .unwrap();
        println!(
            "{label}: tick {}, HP{}, armor{}, {} actual guard deaths",
            attempt.session.state.tick,
            p.hp,
            p.armor,
            attempt.killed.len()
        );
    }
    let state = &attempt.session.state;
    let mission = state.mission_state().unwrap();
    assert_eq!(mission.phase, MissionPhase::Departed);
    let facts = mission.m13.unwrap();
    assert!(
        facts.relay_disabled && facts.overseer_surrendered && facts.challenges.supports_cleared
    );
    assert!(facts.challenges.workers.is_some());
    assert_eq!(facts.challenges.workers_arrived, [true, true, false]);
    assert!(
        !attempt.rocket_ticks.is_empty(),
        "rocket lesson must actually launch a traveling rocket"
    );
    assert!(
        attempt.rocket_effective_damage > 0,
        "the traveling lesson rocket must resolve actual effective damage against Union defenders"
    );
    assert!(
        attempt.last_gallery_guard_held,
        "the last living registered gallery defender must causally retain the incomplete receipt"
    );
    assert!(
        !attempt.reloads.is_empty(),
        "finite human magazines require ordinary reloads"
    );
    assert!(
        attempt.enemy_attacks > 0,
        "real enemy combat must remain enabled"
    );
    let record = state.player_record(id).unwrap();
    assert_eq!(record.status, RecordStatus::Complete);
    assert_eq!(record.total.deaths, 0);
    assert!(
        record.total.weapon(WeaponType::Rocket).hp_damage
            + record.total.weapon(WeaponType::Rocket).armor_damage
            > 0
    );
    let p = state.players.iter().find(|p| p.id == id).unwrap();
    assert!(
        p.inventory
            .state(id, p.weapon, state.tick)
            .unwrap()
            .ammo(AmmoPool::Rockets)
            <= AmmoPool::Rockets.capacity()
    );
    println!("M13 complete ordinary route: {} ticks, {} guard deaths, {} enemy attacks, {} launches, {} reload deadlines",state.tick,attempt.killed.len(),attempt.enemy_attacks,attempt.rocket_ticks.len(),attempt.reloads.len());
}
