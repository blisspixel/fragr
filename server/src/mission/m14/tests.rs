use super::*;
use crate::maps::AuthoredMap;
use crate::protocol::{Action, Role};
use crate::session::GameSession;
use std::sync::{Arc, OnceLock};
const MAP: &str = include_str!("../../../maps/m14-launch-authority.json");
fn map() -> Arc<AuthoredMap> {
    static MAP_CACHE: OnceLock<Arc<AuthoredMap>> = OnceLock::new();
    MAP_CACHE
        .get_or_init(|| AuthoredMap::read(MAP.as_bytes()).unwrap())
        .clone()
}
const INFANTRY_SEEDS: [u64; 3] = [1011, 1013, 1021];
fn session() -> (GameSession, Uuid) {
    session_role(Role::Agent)
}
fn session_role(role: Role) -> (GameSession, Uuid) {
    session_seeded(role, 1014)
}
fn session_seeded(role: Role, seed: u64) -> (GameSession, Uuid) {
    let mut s = GameSession::with_authored_map(map());
    s.state.use_replay_ids();
    s.state.seed(seed);
    let id = Uuid::from_u128(1014);
    s.state.add_player(id, "Launch infantry".into(), role);
    if role == Role::Human {
        s.state.arm_joined_magazines(id);
    }
    assert!(s.state.acknowledge_mission(
        id,
        MissionReady {
            id: MissionId::LaunchAuthority,
            attempt: 1
        }
    ));
    (s, id)
}
fn tick(s: &mut GameSession) {
    s.tick_messages(0.05);
    s.state
        .mission_state()
        .unwrap()
        .validate(s.state.tick)
        .unwrap();
}
fn place(s: &mut GameSession, id: Uuid, feet: [f32; 3]) {
    let p = s.state.players.iter_mut().find(|p| p.id == id).unwrap();
    [p.x, p.y, p.z] = [feet[0], feet[1] + PLAYER_FLOOR_Y, feet[2]];
    p.vy = 0.0;
    p.clear_input();
}
fn clear_enemies(s: &mut GameSession) {
    for i in 0..s.state.players.len() {
        let p = &s.state.players[i];
        if !p.is_participant() && p.hp > 0 {
            let damage = p.hp + p.armor;
            s.state.environmental_self_damage(i, damage);
        }
    }
}
fn battle_fixture() -> (GameSession, Uuid) {
    let (mut s, id) = session();
    tick(&mut s);
    for at in [[-25.0, 0.0, -36.0], [-24.0, 0.0, -13.0], [-22.0, 0.0, 16.0]] {
        place(&mut s, id, at);
        tick(&mut s);
        clear_enemies(&mut s);
        tick(&mut s);
        tick(&mut s);
    }
    assert_eq!(
        s.state
            .mission
            .as_ref()
            .unwrap()
            .m14
            .as_ref()
            .unwrap()
            .index,
        4
    );
    place(&mut s, id, [-14.0, 0.0, 28.0]);
    tick(&mut s);
    (s, id)
}
fn disable(s: &mut GameSession) {
    let w = &mut s.state.walker.as_mut().unwrap().state;
    w.hp = 0;
    w.stage = 3;
    w.phase = WalkerPhase::Disabled;
    w.phase_started = s.state.tick;
    w.phase_ends = s.state.tick;
    w.shells.clear();
}

#[test]
fn m14_loads_prepared_intact_and_fallen_routes() {
    let map = AuthoredMap::read(MAP.as_bytes()).expect("connected launch works loads");
    let runtime = RuntimeMap::Authored(map);
    let g = runtime.m14_geometry().unwrap();
    assert!(!g.fallen);
    assert_eq!(
        runtime.campaign_mission_id(),
        Some(MissionId::LaunchAuthority)
    );
    let fallen = runtime.prepared_m14_world([8.0, 0.0, 26.0]).unwrap();
    assert!(fallen.m14_geometry().unwrap().fallen);
    assert!(fallen.walker_geometry().is_none());
}

#[test]
fn m14_controller_rejects_static_changes_and_preserves_exact_retry_world() {
    let runtime = RuntimeMap::Authored(map());
    let g = runtime.m14_geometry().unwrap();
    let mut client = MissionClient::default();
    let accept = |client: &mut MissionClient, world: &RuntimeMap| {
        client.replace_map_with_m14(
            world.m14_geometry().as_ref(),
            world.half_extent(),
            &world.arena().solids,
            world.presentation_ref(),
        )
    };
    accept(&mut client, &runtime).unwrap();
    let mut walls = runtime.arena().solids.clone();
    walls[0].max_x += 0.1;
    assert!(client
        .replace_map_with_m14(
            Some(&g),
            runtime.half_extent(),
            &walls,
            runtime.presentation_ref()
        )
        .is_err());
    let mut panels = runtime.presentation_ref().unwrap().clone();
    panels.decorations[2].center[0] += 0.1;
    assert!(client
        .replace_map_with_m14(
            Some(&g),
            runtime.half_extent(),
            &runtime.arena().solids,
            Some(&panels)
        )
        .is_err());
    let fallen = runtime.prepared_m14_world([8.4, 0.0, 28.0]).unwrap();
    accept(&mut client, &fallen).unwrap();
    let mut wrong = fallen.arena().solids.clone();
    wrong[g.walker_solids[1]].min_x += 0.01;
    assert!(fallen
        .m14_geometry()
        .unwrap()
        .validate(fallen.half_extent(), &wrong, fallen.presentation_ref())
        .is_err());
    let shifted = runtime.prepared_m14_world([8.5, 0.0, 28.0]).unwrap();
    assert!(
        accept(&mut client, &shifted).is_err(),
        "a settled wreck cannot slide"
    );
    accept(&mut client, &runtime).unwrap();
}

#[test]
fn m14_resolved_fire_waits_for_encounter_activation_then_takes_normal_plate_damage() {
    let (mut s, id) = session();
    tick(&mut s);
    place(&mut s, id, [-1.0, 0.0, 24.6]);
    let fire = Action {
        fire: true,
        weapon_swap: Some(crate::protocol::WeaponType::Flechette),
        look_at: Some(crate::protocol::LookAt {
            x: Some(5.0),
            y: Some(1.4),
            z: Some(24.6),
            player_id: None,
        }),
        ..Default::default()
    };
    s.state.set_action(id, fire.clone());
    tick(&mut s);
    assert_eq!(s.state.walker.as_ref().unwrap().state.hp, 900);
    assert!(
        !s.state
            .mission_state()
            .unwrap()
            .m14
            .unwrap()
            .challenges
            .walker_disabled
    );
    s.state.set_action(id, Action::default());
    for _ in 0..10 {
        tick(&mut s);
    }
    let progress = s.state.mission.as_mut().unwrap().m14.as_mut().unwrap();
    progress.index = 4;
    progress.challenges.depot_secured = true;
    s.state.set_action(id, fire);
    tick(&mut s);
    assert_eq!(
        s.state.walker.as_ref().unwrap().state.hp,
        894,
        "normal 25-point rifle hit meets quarter plate"
    );
}

#[test]
fn m14_activation_staging_fast_kill_fall_and_retry_use_one_owner() {
    let (mut s, id) = battle_fixture();
    assert_eq!(
        s.state.walker.as_ref().unwrap().state.phase,
        WalkerPhase::StompWarning
    );
    assert!(!s
        .state
        .players
        .iter()
        .any(|p| s.state.encounters.registered_in_group(p.id, 3)));
    disable(&mut s);
    tick(&mut s);
    let p = s.state.mission_state().unwrap().m14.unwrap();
    assert_eq!(p.support_stage, 1);
    assert!(p.machine_fallen);
    assert!(s.state.walker.is_none());
    tick(&mut s);
    assert!(s
        .state
        .players
        .iter()
        .any(|p| s.state.encounters.registered_in_group(p.id, 3)));
    assert!(!s
        .state
        .players
        .iter()
        .any(|p| s.state.encounters.registered_in_group(p.id, 4)));
    clear_enemies(&mut s);
    tick(&mut s);
    tick(&mut s);
    assert_eq!(
        s.state.mission_state().unwrap().m14.unwrap().support_stage,
        2
    );
    assert!(s
        .state
        .players
        .iter()
        .any(|p| s.state.encounters.registered_in_group(p.id, 4)));
    assert!(!s
        .state
        .players
        .iter()
        .any(|p| s.state.encounters.registered_in_group(p.id, 5)));
    s.state.players.iter_mut().find(|p| p.id == id).unwrap().hp = 0;
    tick(&mut s);
    assert!(!s.state.map.m14_geometry().unwrap().fallen);
    assert_eq!(s.state.walker.as_ref().unwrap().state.hp, 900);
    assert_eq!(s.state.vehicles.len(), 1);
    assert_eq!(s.state.vehicles[0].state.id, 1);
}

#[test]
fn m14_support_waits_for_full_first_recovery_and_receipts_freeze_at_disable() {
    let (mut s, id) = battle_fixture();
    let w = &mut s.state.walker.as_mut().unwrap().state;
    w.hp = 590;
    w.stage = 2;
    for _ in 0..600 {
        if s.state.walker.as_ref().unwrap().state.phase == WalkerPhase::ArtilleryWarning {
            place(&mut s, id, [-14.0, 0.0, 40.0]);
        }
        tick(&mut s);
        let p = s.state.mission_state().unwrap().m14.unwrap();
        if p.first_cycle_complete {
            assert_eq!(p.support_stage, 1);
            break;
        }
        assert_eq!(
            p.support_stage, 0,
            "accepted early damage cannot skip the first recovery lesson"
        );
        assert!(!s
            .state
            .players
            .iter()
            .any(|p| s.state.encounters.registered_in_group(p.id, 3)));
    }
    assert!(
        s.state
            .mission_state()
            .unwrap()
            .m14
            .unwrap()
            .first_cycle_complete
    );
    s.state.vehicles[0].assign(crate::protocol::VehicleSeat::Driver, Some(id));
    s.state.advance_m14();
    assert!(
        !s.state
            .mission_state()
            .unwrap()
            .m14
            .unwrap()
            .challenges
            .on_foot
    );
    disable(&mut s);
    s.state.advance_m14();
    let receipt = s.state.mission_state().unwrap().m14.unwrap().challenges;
    assert!(receipt.jeep_preserved);
    assert!(!receipt.on_foot);
    s.state.vehicles[0].damage(500, None);
    s.state.advance_m14();
    assert_eq!(
        s.state.mission_state().unwrap().m14.unwrap().challenges,
        receipt
    );
}

#[test]
fn m14_fall_waits_for_living_body_but_not_abandoned_or_destroyed_jeep() {
    for alive in [false, true] {
        let (mut s, id) = battle_fixture();
        let feet = s.state.walker.as_ref().unwrap().state.feet;
        s.state.vehicles[0].state.position = feet;
        if !alive {
            s.state.vehicles[0].damage(500, None);
        }
        place(&mut s, id, feet);
        disable(&mut s);
        s.state.advance_m14();
        assert!(
            !s.state.map.m14_geometry().unwrap().fallen,
            "no crushing body switch"
        );
        place(&mut s, id, [-14.0, 0.0, 28.0]);
        s.state.advance_m14();
        assert!(
            s.state.map.m14_geometry().unwrap().fallen,
            "empty hull cannot permanently hold mission"
        );
        assert_eq!(
            s.state
                .map
                .navigation()
                .route(
                    [-14.0, 0.0, 28.0],
                    [5.0, 0.0, 44.5],
                    crate::navigation::SEARCH_LIMIT
                )
                .status,
            crate::navigation::RouteStatus::Complete
        );
        if alive {
            place(&mut s, id, [feet[0] - 2.0, 0.0, feet[2]]);
            s.state.set_action(
                id,
                Action {
                    interact: true,
                    ..Default::default()
                },
            );
            tick(&mut s);
            assert!(
                s.state.vehicle_seat(id).is_none(),
                "fallen solid must refuse new boarding through the wreck"
            );
        }
    }
}

#[test]
fn m14_parked_notary_lesson_uses_real_boarding_seat_and_mounted_fire() {
    let (mut s, id) = session_role(Role::Human);
    tick(&mut s);
    // Isolate the accepted depot-clear checkpoint, then use only ordinary actions.
    place(&mut s, id, [-25.0, 0.0, -36.0]);
    tick(&mut s);
    clear_enemies(&mut s);
    tick(&mut s);
    tick(&mut s);
    assert_eq!(
        s.state
            .mission_state()
            .unwrap()
            .m14
            .unwrap()
            .completed
            .len(),
        2
    );
    place(&mut s, id, [-25.6, 0.0, -24.0]);
    s.state.set_action(
        id,
        Action {
            interact: true,
            ..Default::default()
        },
    );
    tick(&mut s);
    assert_eq!(
        s.state.vehicle_seat(id),
        Some((0, crate::protocol::VehicleSeat::Driver))
    );
    s.state.set_action(
        id,
        Action {
            seat: Some(crate::protocol::VehicleSeat::Gunner),
            ..Default::default()
        },
    );
    tick(&mut s);
    assert_eq!(
        s.state.vehicle_seat(id),
        Some((0, crate::protocol::VehicleSeat::Gunner))
    );
    let parked = s.state.vehicles[0].state.position;
    let original = s
        .state
        .players
        .iter()
        .find(|p| p.id == id)
        .unwrap()
        .inventory
        .state(id, crate::protocol::WeaponType::Flechette, s.state.tick)
        .unwrap();
    for _ in 0..600 {
        if s.state.encounters.is_complete(1) {
            break;
        }
        let target = s
            .state
            .players
            .iter()
            .find(|p| p.hp > 0 && s.state.encounters.registered_in_group(p.id, 1))
            .map(|p| p.id);
        s.state.set_action(
            id,
            Action {
                fire: s.state.tick % 60 < 40,
                look_at: target.map(|target| crate::protocol::LookAt {
                    player_id: Some(target),
                    x: None,
                    y: None,
                    z: None,
                }),
                ..Default::default()
            },
        );
        tick(&mut s);
    }
    assert!(
        s.state.encounters.is_complete(1),
        "parked mounted weapon must clear both authored Notaries"
    );
    assert_eq!(s.state.vehicles[0].state.position, parked);
    let p = s.state.players.iter().find(|p| p.id == id).unwrap();
    assert_eq!(
        p.inventory.state(id, p.weapon, s.state.tick).unwrap().ammo,
        original.ammo
    );
    assert!(
        s.state
            .mission_state()
            .unwrap()
            .m14
            .unwrap()
            .challenges
            .on_foot,
        "pre-boss driving lesson does not spoil on-foot boss brief"
    );
}

#[test]
fn m14_ordinary_finite_infantry_controller_completes_connected_mission() {
    ordinary_infantry(Role::Agent, 0);
}
#[test]
fn m14_ordinary_human_magazines_complete_without_the_jeep() {
    ordinary_infantry(Role::Human, 1);
}
#[test]
fn m14_ordinary_finite_infantry_completes_after_jeep_destruction() {
    ordinary_infantry(Role::Agent, 2);
}
#[test]
#[ignore = "seed survey: cargo test -p fragr-server --lib seed_survey -- --ignored --nocapture"]
fn m14_ordinary_infantry_seed_survey() {
    crate::mission::route_skill::survey("M14 ordinary infantry", 1010..1026, |seed| {
        for (role, jeep) in [(Role::Agent, 0), (Role::Human, 1), (Role::Agent, 2)] {
            ordinary_infantry_seeded(role, jeep, seed);
        }
    });
}
/// The route reads tells and Walker marks, so it holds on every seed it is
/// given. These include seeds that killed the tell-blind controller.
fn ordinary_infantry(role: Role, jeep_condition: u8) {
    for seed in INFANTRY_SEEDS {
        ordinary_infantry_seeded(role, jeep_condition, seed);
    }
}
fn ordinary_infantry_seeded(role: Role, jeep_condition: u8, seed: u64) {
    let (mut s, id) = session_seeded(role, seed);
    if jeep_condition == 1 {
        s.state.vehicles.clear();
    }
    if jeep_condition == 2 {
        s.state.vehicles[0].damage(500, None);
    }
    let mut client = MissionClient::default();
    let mut navigator = crate::navigation::Navigator::default();
    let mut tells = crate::mission::route_skill::TellReader::default();
    let mut futile = crate::mission::route_skill::FutileTargets::default();
    let mut last_map = None;
    let mut reload_held = false;
    let mut navigation = None;
    for _ in 0..18000 {
        if last_map.as_ref() != Some(&s.state.map) {
            let map = &s.state.map;
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
                .replace_map_with_m14(
                    map.m14_geometry().as_ref(),
                    map.half_extent(),
                    &map.arena().solids,
                    map.presentation_ref(),
                )
                .unwrap();
            // This is exactly the topology a wire reader can reconstruct from
            // accepted MapInfo, not the server's private conservative plan.
            navigation = Some(
                crate::navigation::Navigation::shared(crate::movement::Arena {
                    half: map.half_extent(),
                    solids: map.arena().solids.clone(),
                })
                .unwrap(),
            );
            last_map = Some(map.clone());
            navigator.clear();
        }
        let world = navigation.as_ref().unwrap();
        let mission = s.state.mission_state().unwrap();
        client.observe(s.state.tick, mission.clone()).unwrap();
        if mission.phase == MissionPhase::Departed {
            break;
        }
        let snapshot = s.state.snapshot();
        let me = snapshot
            .players
            .iter()
            .find(|p| p.id == id)
            .unwrap_or_else(|| {
                panic!(
                    "route participant missing tick{} objective{:?} status{:?}",
                    s.state.tick,
                    mission.m14,
                    s.state.players.iter().find(|p| p.id == id).map(|p| (
                        p.hp,
                        p.respawn_timer,
                        p.detached,
                        p.x,
                        p.z
                    ))
                )
            });
        assert!(
            me.hp > 0,
            "ordinary M14 route died tick{} objective{:?} at [{},{},{}]",
            s.state.tick,
            mission.m14.as_ref().unwrap().completed,
            me.x,
            me.y,
            me.z
        );
        let p = s.state.players.iter().find(|p| p.id == id).unwrap();
        let loadout = p.inventory.state(id, p.weapon, s.state.tick).unwrap();
        let mut action = crate::inventory::control_action_with_target_filter(
            id,
            &snapshot,
            Some(&loadout),
            Action::default(),
            true,
            |_, other| !futile.skips(other.id, snapshot.tick),
        );
        if role == Role::Human
            && loadout
                .loaded
                .iter()
                .any(|m| m.weapon == loadout.selected && m.rounds == 0)
            && loadout
                .selected
                .ammo_pool()
                .is_some_and(|pool| loadout.ammo(pool) > 0)
        {
            action.weapon_swap = Some(loadout.selected);
            action.reload = !reload_held;
            action.fire = false;
            action.forward = false;
        }
        if role == Role::Human
            && mission.m14.as_ref().unwrap().completed.len() >= 5
            && action
                .look_at
                .as_ref()
                .is_some_and(|a| a.player_id.is_some())
        {
            action.right = (s.state.tick / 30).is_multiple_of(2);
            action.left = !action.right;
        }
        let supply = snapshot.pickups.iter().find(|p| {
            p.available
                && !loadout.personal_claims.contains(&p.id)
                && (p.id == "arrival_armor"
                    || (mission.m14.as_ref().unwrap().completed.len() == 2
                        && matches!(p.id.as_str(), "depot_rocket" | "depot_bullets")))
        });
        let health = (me.hp < 70)
            .then(|| {
                snapshot
                    .pickups
                    .iter()
                    .filter(|p| {
                        p.available && p.kind == "health" && (p.x - me.x).hypot(p.z - me.z) < 18.0
                    })
                    .min_by(|a, b| {
                        (a.x - me.x)
                            .hypot(a.z - me.z)
                            .total_cmp(&(b.x - me.x).hypot(b.z - me.z))
                    })
            })
            .flatten();
        let mut action = if let Some(supply) = health.or(supply) {
            navigator.steer(
                world,
                [me.x, me.y - PLAYER_FLOOR_Y, me.z],
                crate::navigation::NavigationGoal {
                    feet: [supply.x, supply.y, supply.z],
                    combat: false,
                },
                Action {
                    reload: action.reload,
                    ..Default::default()
                },
                s.state.tick,
                true,
            )
        } else {
            client.steer_with_equipment(
                &mut navigator,
                world,
                id,
                &snapshot,
                action,
                Some(&loadout),
            )
        };
        let selected = action.weapon_swap.unwrap_or(loadout.selected);
        if loadout.shots(selected) == Some(0)
            && loadout.ammo(
                selected
                    .ammo_pool()
                    .unwrap_or(crate::protocol::AmmoPool::Bullets),
            ) > 0
        {
            action.reload = !reload_held;
            action.fire = false;
        }
        reload_held = action.reload;
        futile.observe(&snapshot, &action);
        let action = tells.evade(&s.state, &snapshot, id, action);
        s.state.set_action(id, action);
        tick(&mut s);
        let after = s.state.players.iter().find(|p| p.id == id).unwrap();
        if after.hp < me.hp {
            eprintln!(
                "M14 hurt tick{} hp{}->{} weapon {:?} at [{:.1},{:.1}] walker{:?} target{:?} stage{:?}",
                s.state.tick,
                me.hp,
                after.hp,
                after.weapon,
                after.x,
                after.z,
                s.state.walker.as_ref().map(|w| (w.state.phase, w.state.hp)),
                s.state.walker.as_ref().map(|w| w.state.target),
                mission.m14.as_ref().map(|m| m.support_stage)
            );
        }
        if s.state.tick % 2000 == 0 {
            eprintln!("M14 route tick{} objective{:?} at [{:.1},{:.1}] hp{} ammo{} held{:?} loaded{:?} walker{:?}",s.state.tick,mission.m14.as_ref().unwrap().completed,me.x,me.z,me.hp,loadout.ammo(crate::protocol::AmmoPool::Bullets),loadout.selected,loadout.loaded,s.state.walker.as_ref().map(|w|(w.state.hp,w.state.phase)));
        }
    }
    let final_state = s.state.mission_state().unwrap();
    assert_eq!(
        final_state.phase,
        MissionPhase::Departed,
        "route ended at {:?}",
        final_state.m14
    );
    let challenges = final_state.m14.unwrap().challenges;
    assert!(challenges.on_foot);
    assert_eq!(challenges.jeep_preserved, jeep_condition == 0);
    eprintln!(
        "M14 ordinary finite infantry completed in {} ticks",
        s.state.tick
    );
}

#[test]
fn native_launch_fact_vectors_match_client_fixture() {
    fn record(s: &GameSession, name: &str) -> serde_json::Value {
        let state = s.state.mission_state().unwrap();
        state.validate(s.state.tick).unwrap();
        serde_json::json!({"name":name,"tick":s.state.tick,"state":state,"walker":s.state.snapshot().walker,"snapshot":s.state.snapshot()})
    }
    let mut briefing = GameSession::with_authored_map(map());
    briefing.state.use_replay_ids();
    briefing.state.seed(1014);
    let id = Uuid::from_u128(1014);
    briefing
        .state
        .add_player(id, "Launch infantry".into(), Role::Agent);
    let map_info = briefing.state.map_info();
    let mut valid = vec![record(&briefing, "briefing")];
    let (mut s, id) = battle_fixture();
    valid.push(record(&s, "solo_stomp_warning"));
    // Real phase deadlines and committed shell flight, arranged encounter clearance only.
    for _ in 0..800 {
        if s.state.walker.as_ref().unwrap().state.phase == WalkerPhase::ArtilleryWarning {
            place(&mut s, id, [-14.0, 0.0, 40.0]);
        }
        tick(&mut s);
        if s.state
            .mission
            .as_ref()
            .unwrap()
            .m14
            .as_ref()
            .unwrap()
            .first_cycle_complete
        {
            break;
        }
    }
    assert!(
        s.state
            .mission
            .as_ref()
            .unwrap()
            .m14
            .as_ref()
            .unwrap()
            .first_cycle_complete
    );
    valid.push(record(&s, "first_solo_cycle_complete"));
    for _ in 0..300 {
        if !s.state.walker.as_ref().unwrap().state.shells.is_empty() {
            break;
        }
        tick(&mut s);
    }
    assert!(!s.state.walker.as_ref().unwrap().state.shells.is_empty());
    let w = &mut s.state.walker.as_mut().unwrap().state;
    w.hp = 0;
    w.stage = 3;
    w.phase = WalkerPhase::Disabled;
    w.phase_started = s.state.tick;
    w.phase_ends = s.state.tick;
    s.state.advance_m14();
    valid.push(record(&s, "disabled_shells_draining"));
    place(&mut s, id, [-40.0, 0.0, 20.0]);
    for _ in 0..120 {
        tick(&mut s);
        if s.state.walker.is_none() {
            break;
        }
    }
    assert!(s.state.walker.is_none());
    let fallen_map_info = s.state.map_info();
    valid.push(record(&s, "fallen_pad_support"));
    for _ in 0..6 {
        clear_enemies(&mut s);
        tick(&mut s);
    }
    place(&mut s, id, [5.0, 0.0, 44.5]);
    for _ in 0..4 {
        tick(&mut s);
        clear_enemies(&mut s);
    }
    tick(&mut s);
    assert_eq!(
        s.state
            .mission
            .as_ref()
            .unwrap()
            .m14
            .as_ref()
            .unwrap()
            .index,
        6
    );
    valid.push(record(&s, "gantry_secured"));
    let g = s.state.map.m14_geometry().unwrap();
    let point = g
        .departure
        .point(
            s.state.map.presentation_ref().unwrap(),
            &s.state.current_arena().solids,
        )
        .unwrap();
    s.state.set_action(
        id,
        Action {
            interact: true,
            look_at: Some(crate::protocol::LookAt {
                x: Some(point[0]),
                y: Some(point[1]),
                z: Some(point[2]),
                player_id: None,
            }),
            ..Default::default()
        },
    );
    tick(&mut s);
    assert_eq!(
        s.state.mission_state().unwrap().phase,
        MissionPhase::Departed
    );
    valid.push(record(&s, "departed"));
    let (mut retry, retry_id) = battle_fixture();
    disable(&mut retry);
    tick(&mut retry);
    retry
        .state
        .players
        .iter_mut()
        .find(|p| p.id == retry_id)
        .unwrap()
        .hp = 0;
    tick(&mut retry);
    valid.push(record(&retry, "retry_briefing"));
    let mut invalid = Vec::new();
    for name in [
        "early_disable",
        "invented_fall",
        "early_support",
        "wrong_jeep",
        "unknown_field",
    ] {
        let mut state = valid[0]["state"].clone();
        match name {
            "early_disable" => state["m14"]["challenges"]["walker_disabled"] = true.into(),
            "invented_fall" => state["m14"]["machine_fallen"] = true.into(),
            "early_support" => state["m14"]["support_stage"] = 1.into(),
            "wrong_jeep" => state["m14"]["jeep_id"] = 2.into(),
            _ => state["m14"]["invented"] = true.into(),
        }
        assert!(serde_json::from_value::<MissionState>(state.clone())
            .map_or(true, |s| s.validate(0).is_err()));
        invalid.push(serde_json::json!({"name":name,"tick":0,"state":state}));
    }
    let (mut early, _) = session();
    tick(&mut early);
    let mut possible = early.state.mission_state().unwrap();
    possible.m14.as_mut().unwrap().challenges.jeep_preserved = false;
    possible.validate(early.state.tick).unwrap();
    for name in ["early_cycle", "early_support_after_cycle", "early_on_foot"] {
        let mut state = serde_json::to_value(early.state.mission_state().unwrap()).unwrap();
        match name {
            "early_cycle" => state["m14"]["first_cycle_complete"] = true.into(),
            "early_support_after_cycle" => {
                state["m14"]["first_cycle_complete"] = true.into();
                state["m14"]["support_stage"] = 1.into();
            }
            _ => state["m14"]["challenges"]["on_foot"] = false.into(),
        }
        assert!(serde_json::from_value::<MissionState>(state.clone())
            .unwrap()
            .validate(early.state.tick)
            .is_err());
        invalid.push(serde_json::json!({"name":name,"tick":early.state.tick,"state":state}));
    }
    let document = serde_json::json!({"map_info":map_info,"fallen_map_info":fallen_map_info,"participant":id,"valid":valid,"invalid":invalid});
    let path = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../client/golden/m14_fact_vectors.json");
    let bytes = serde_json::to_vec_pretty(&document).unwrap();
    if std::env::var_os("FRAGR_UPDATE_M14_FACTS").is_some() {
        std::fs::write(&path, &bytes).unwrap();
    }
    assert!(
        bytes == std::fs::read(path).unwrap(),
        "native M14 fixture changed"
    );
}

/// Seed 1015's route stood on the trench bunker's ammunition while the Walker
/// marked three shells down the trench. Every bearing near the marks' push
/// ran into a trench wall, so the tell reader gave up at the bunker mouth and
/// the route walked back onto the pad, over and over, until the shells landed.
/// A reader that never stops inside a mark while a bearing is open walks out
/// along the trench.
#[test]
fn tell_reader_walks_out_of_a_barrage_laid_along_the_trench() {
    let (mut s, id) = session();
    s.state.players.retain(|p| p.is_participant());
    // On the pad where the route stood when the marks went down.
    place(&mut s, id, [-0.35, 0.0, 16.55]);
    let targets = [
        [1.065_708, 0.0, 20.287_428],
        [-0.347_567, 0.0, 16.545_416],
        [-1.760_843, 0.0, 12.803_404],
    ];
    let outside = |p: &crate::sim::Player| {
        targets
            .iter()
            .all(|t| (p.x - t[0]).hypot(p.z - t[2]) > crate::protocol::WALKER_SHELL_RADIUS)
    };
    let mut tells = crate::mission::route_skill::TellReader::default();
    let mut escaped = None;
    for step in 0..80 {
        let mut snapshot = s.state.snapshot();
        let walker = snapshot.walker.as_mut().expect("M14 has a Walker");
        walker.phase = WalkerPhase::ArtilleryWarning;
        walker.artillery_targets = targets;
        // The route's own step, as recorded: on south down the trench,
        // back through the marks.
        let wanted = Action {
            forward: true,
            yaw: Some(-1.459_658),
            ..Default::default()
        };
        let action = tells.evade(&s.state, &snapshot, id, wanted);
        s.state.set_action(id, action);
        s.tick_messages(0.05);
        let me = s.state.players.iter().find(|p| p.id == id).unwrap();
        assert!(me.hp > 0);
        if outside(me) {
            escaped = Some(step);
            break;
        }
    }
    let me = s.state.players.iter().find(|p| p.id == id).unwrap();
    assert!(
        escaped.is_some_and(|step| step < 60),
        "still inside the marks at [{:.2}, {:.2}]",
        me.x,
        me.z
    );
}
