//! A complete canonical M12 attempt driven only by ordinary finite human input.
use fragr_server::combat::{line_of_sight, target_height};
use fragr_server::maps::AuthoredSource;
use fragr_server::movement::{BODY_HEIGHT, CONTACT_EPSILON, EYE_HEIGHT};
use fragr_server::navigation::{NavigationGoal, Navigator};
use fragr_server::protocol::{
    Action, AmmoPool, CampaignActor, GameEvent, LookAt, MissionId, MissionPhase, MissionReady,
    PlayerState, RecordStatus, Role, ServerMessage, WeaponType,
};
use fragr_server::session::GameSession;
use fragr_server::sim::PLAYER_FLOOR_Y;
use serde_json::Value;
use std::collections::HashSet;
use uuid::Uuid;

const ROUTE: &[u8] = include_bytes!("../../client/qa/m12_terms_of_cooperation.json");

fn point(value: &Value) -> [f32; 3] {
    std::array::from_fn(|i| value[i].as_f64().unwrap() as f32)
}
fn points(value: &Value) -> Vec<[f32; 3]> {
    value
        .as_array()
        .map(|values| values.iter().map(point).collect())
        .unwrap_or_default()
}
fn names(value: &Value) -> Vec<String> {
    value
        .as_array()
        .map(|values| values.iter().map(|v| v.as_str().unwrap().into()).collect())
        .unwrap_or_default()
}
fn aim(target: &PlayerState) -> [f32; 3] {
    let height = if fragr_server::combat::is_assessor(target.campaign) {
        0.5
    } else {
        0.9
    };
    [
        target.x,
        target.y - PLAYER_FLOOR_Y + target_height(target.campaign) * height,
        target.z,
    ]
}
fn look(point: [f32; 3]) -> LookAt {
    LookAt {
        x: Some(point[0]),
        y: Some(point[1]),
        z: Some(point[2]),
        player_id: None,
    }
}
fn near(from: [f32; 3], to: [f32; 3]) -> bool {
    (from[0] - to[0]).hypot(from[2] - to[2]) <= 0.3 && (from[1] - to[1]).abs() <= 0.05
}

struct Attempt {
    session: GameSession,
    id: Uuid,
    killed: HashSet<String>,
    enemy_attacks: usize,
    reload_deadlines: HashSet<u64>,
    aid_cells_receipt: Option<(u16, u16, i32)>,
}
impl Attempt {
    fn tick(&mut self, action: Action, label: &str) {
        assert!(
            !action.jump,
            "{label}: the walking route must not require jumping"
        );
        let before = {
            let p = self
                .session
                .state
                .players
                .iter()
                .find(|p| p.id == self.id)
                .unwrap();
            p.inventory
                .state(self.id, p.weapon, self.session.state.tick)
                .unwrap()
                .ammo(AmmoPool::Cells)
        };
        self.session.state.set_action(self.id, action);
        let messages = self.session.tick_messages(0.05);
        let state = &self.session.state;
        state.mission_state().unwrap().validate(state.tick).unwrap();
        let snapshot = state.snapshot();
        for guard in &snapshot.players {
            if guard.hp <= 0 && matches!(guard.campaign, Some(CampaignActor::Union { .. })) {
                self.killed.insert(guard.name.clone());
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
        let player = state.players.iter().find(|p| p.id == self.id).unwrap();
        assert!(
            player.hp > 0,
            "{label}: participant died at tick {}",
            state.tick
        );
        let bottom = player.y - PLAYER_FLOOR_Y;
        assert!(
            !state.current_arena().solids.iter().any(|s| {
                s.covers(player.x, player.z)
                    && s.top > bottom + CONTACT_EPSILON
                    && s.bottom < bottom + BODY_HEIGHT - CONTACT_EPSILON
            }),
            "{label}: participant entered authoritative geometry"
        );
        let loadout = player
            .inventory
            .state(self.id, player.weapon, state.tick)
            .unwrap();
        for message in &messages {
            if let ServerMessage::Event(GameEvent::Pickup {
                player_id,
                pickup_id,
                amount,
                ..
            }) = message
            {
                if *player_id == self.id && pickup_id == "aid_cells" {
                    assert!(
                        self.aid_cells_receipt.is_none(),
                        "aid stock was claimed more than once"
                    );
                    let after = loadout.ammo(AmmoPool::Cells);
                    let gained = amount.expect("resolved finite ammunition receipt");
                    assert_eq!(after, (before + 24).min(AmmoPool::Cells.capacity()));
                    assert_eq!(i32::from(after - before), gained);
                    self.aid_cells_receipt = Some((before, after, gained));
                }
            }
        }
        for magazine in &loadout.loaded {
            if let Some(deadline) = magazine.ready_at {
                self.reload_deadlines.insert(deadline);
            }
        }
    }

    fn advance(
        &mut self,
        route: &[[f32; 3]],
        targets: &[String],
        weapon: WeaponType,
        finish_combat: bool,
        label: &str,
    ) {
        let mut navigator = Navigator::default();
        let mut waypoint = 0;
        for _ in 0..3000 {
            let state = &self.session.state;
            let snapshot = state.snapshot();
            let me = snapshot.players.iter().find(|p| p.id == self.id).unwrap();
            let from = [me.x, me.y - PLAYER_FLOOR_Y, me.z];
            while waypoint < route.len() && near(from, route[waypoint]) {
                waypoint += 1;
            }
            let cleared = targets.iter().all(|name| self.killed.contains(name));
            if (finish_combat && cleared) || (!finish_combat && waypoint == route.len()) {
                self.tick(Action::default(), label);
                return;
            }
            if finish_combat && waypoint == route.len() {
                waypoint = 0;
            }
            let eye = [from[0], from[1] + EYE_HEIGHT, from[2]];
            let target = snapshot
                .players
                .iter()
                .filter(|p| {
                    p.hp > 0
                        && targets.contains(&p.name)
                        && (p.x - me.x).hypot(p.z - me.z) < weapon.range_units().min(35.0)
                        && line_of_sight(eye, aim(p), &state.current_arena().solids)
                })
                .min_by(|a, b| {
                    (a.x - me.x)
                        .hypot(a.z - me.z)
                        .total_cmp(&(b.x - me.x).hypot(b.z - me.z))
                });
            let mut action = if let Some(target) = target {
                Action {
                    look_at: Some(look(aim(target))),
                    weapon_swap: Some(weapon),
                    fire: true,
                    left: (state.tick / 16).is_multiple_of(2),
                    right: !(state.tick / 16).is_multiple_of(2),
                    ..Action::default()
                }
            } else {
                let destination = route[waypoint.min(route.len() - 1)];
                navigator.steer(
                    state.map.navigation(),
                    from,
                    NavigationGoal {
                        feet: destination,
                        combat: false,
                    },
                    Action::default(),
                    state.tick,
                    true,
                )
            };
            if action.fire {
                let player = state.players.iter().find(|p| p.id == self.id).unwrap();
                let loadout = player
                    .inventory
                    .state(self.id, player.weapon, state.tick)
                    .unwrap();
                assert!(
                    loadout.owns(weapon),
                    "{label}: {weapon:?} was not actually found"
                );
                assert!(
                    weapon
                        .ammo_pool()
                        .is_some_and(|pool| loadout.ammo(pool) > 0),
                    "{label}: finite {weapon:?} ammunition exhausted"
                );
                if loadout.shots(weapon) == Some(0) {
                    action.fire = false;
                    action.reload = state.tick.is_multiple_of(2);
                }
            }
            self.tick(action, label);
        }
        let state = &self.session.state;
        let me = state.players.iter().find(|p| p.id == self.id).unwrap();
        panic!(
            "{label}: bounded route stalled at [{},{},{}], waypoint {waypoint}, remaining {:?}",
            me.x,
            me.y - PLAYER_FLOOR_Y,
            me.z,
            targets
                .iter()
                .filter(|name| !self.killed.contains(*name))
                .collect::<Vec<_>>()
        );
    }

    fn physical_use(&mut self, key: &str, label: &str) {
        let state = &self.session.state;
        let g = state.map.m12_geometry().unwrap();
        let target = match key {
            "shelter_opened" => &g.shelter_release,
            "workers_released" => &g.worker_release,
            "coalition_commitment" => &g.commitment,
            "party_departed" => &g.departure,
            _ => panic!("unexpected M12 control {key}"),
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
            "{label}: actual physical Use prompt is absent"
        );
        self.tick(
            Action {
                look_at: Some(look(point)),
                interact: true,
                ..Action::default()
            },
            label,
        );
    }
    fn expect(&self, value: &Value) {
        let label = value["name"].as_str().unwrap();
        let state = self.session.state.mission_state().unwrap();
        let facts = state.m12.unwrap();
        if value.get("expect_m12_completed").is_some() {
            assert_eq!(
                facts.completed,
                names(&value["expect_m12_completed"]),
                "{label}"
            );
        }
        if let Some(count) = value["expect_m12_aid_count"].as_u64() {
            assert_eq!(facts.aid_vehicle_ids.len() as u64, count, "{label}");
            for id in &facts.aid_vehicle_ids {
                assert!(
                    self.session
                        .state
                        .vehicles
                        .iter()
                        .any(|v| v.state.id == *id),
                    "{label}: aid identity must refer to an actual authoritative vehicle"
                );
            }
        }
        for (key, actual) in [
            ("expect_m12_shelter_opened", facts.challenges.shelter_opened),
            (
                "expect_m12_workers_released",
                facts.challenges.workers_released,
            ),
        ] {
            if let Some(expected) = value[key].as_bool() {
                assert_eq!(actual, expected, "{label}");
            }
        }
    }
}

#[test]
fn m12_canonical_finite_human_walks_all_groups_releases_aid_and_physically_departs() {
    let map = AuthoredSource::Mission(MissionId::TermsOfCooperation)
        .load()
        .unwrap();
    let mut session = GameSession::with_authored_map(map);
    session.state.seed(1012);
    let id = Uuid::from_u128(12120);
    session
        .state
        .add_player(id, "Habitat complete ordinary route".into(), Role::Human);
    session.state.arm_joined_magazines(id);
    assert!(session.state.acknowledge_mission(
        id,
        MissionReady {
            id: MissionId::TermsOfCooperation,
            attempt: 1,
        }
    ));
    let mut attempt = Attempt {
        session,
        id,
        killed: HashSet::new(),
        enemy_attacks: 0,
        reload_deadlines: HashSet::new(),
        aid_cells_receipt: None,
    };
    let manifest: Value = serde_json::from_slice(ROUTE).unwrap();
    let mut weapon = WeaponType::Flechette;
    for value in manifest["states"].as_array().unwrap() {
        let label = value["name"].as_str().unwrap();
        if let Some(name) = value["weapon"].as_str() {
            weapon = serde_json::from_value(Value::String(name.to_lowercase())).unwrap();
        }
        let travel = names(&value["combat_travel_targets"]);
        attempt.advance(&points(&value["walk_to"]), &travel, weapon, false, label);
        if let Some(combat) = value.get("combat") {
            attempt.advance(
                &points(&combat["search_route"]),
                &names(&combat["required"]),
                weapon,
                true,
                label,
            );
        }
        if let Some(control) = value["interact"].as_str() {
            attempt.physical_use(control, label);
        }
        attempt.expect(value);
        if label == "m12_finite_aid_stock" {
            assert!(
                attempt.aid_cells_receipt.is_some(),
                "ordinary route must actually collect delivered Cells"
            );
            assert!(
                !attempt
                    .session
                    .state
                    .pickups
                    .iter()
                    .find(|p| p.id == "aid_cells")
                    .unwrap()
                    .available
            );
        }
        let me = attempt
            .session
            .state
            .players
            .iter()
            .find(|p| p.id == id)
            .unwrap();
        println!(
            "{label}: actual tick {}, HP{} armor{}",
            attempt.session.state.tick, me.hp, me.armor
        );
    }
    let state = &attempt.session.state;
    let mission = state.mission_state().unwrap();
    assert_eq!(mission.phase, MissionPhase::Departed);
    let record = state.player_record(id).unwrap();
    assert_eq!(record.status, RecordStatus::Complete);
    assert_eq!(record.total.deaths, 0);
    assert_eq!(attempt.killed.len(), 17);
    assert!(attempt.enemy_attacks > 0);
    assert!(
        !attempt.reload_deadlines.is_empty(),
        "finite human magazines must actually reload"
    );
    let player = state.players.iter().find(|p| p.id == id).unwrap();
    assert!(player.inventory.claimed("bay_arc"));
    assert!(record.total.weapons[WeaponType::Arc.index()].attacks > 0);
    let facts = mission.m12.unwrap();
    println!("M12 complete finite ordinary route: {} ticks,17 actual guard deaths,{} enemy attacks,{} reloads,{} HP/{} armor lost,0 deaths,2 real parked aid vehicles, optional wreck victims {}. Static released people remain at authored positions.",
        state.tick,attempt.enemy_attacks,attempt.reload_deadlines.len(),record.total.hp_lost,
        record.total.armor_lost,facts.challenges.assessor_wreck_union_kills);
}
