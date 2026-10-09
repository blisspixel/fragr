use super::*;
use crate::navigation::{NavigationGoal, Navigator};
use crate::protocol::{
    Action, ChargeStatus, GameEvent, GameMode, Role, SabotageEventKind, SabotagePhase,
    SabotageReason, ServerMessage,
};
use crate::rules::{RuleSet, SabotageConfig};
use crate::session::GameSession;
use crate::sim::{GameState, MapKind, MatchConfig, PLAYER_FLOOR_Y};
use uuid::Uuid;

fn config() -> MatchConfig {
    MatchConfig {
        frag_limit: None,
        time_limit_ticks: None,
        boss_spawn_ticks: None,
        compliance_ping_ticks: None,
        rules: RuleSet::new(GameMode::Sabotage, &[], false).unwrap(),
        sabotage: SabotageConfig {
            five_vs_five: true,
            ..Default::default()
        },
        ..Default::default()
    }
}
fn feet(state: &GameState, id: Uuid) -> [f32; 3] {
    let p = state.players.iter().find(|p| p.id == id).unwrap();
    [p.x, p.y - PLAYER_FLOOR_Y, p.z]
}
fn tick(state: &mut GameState, count: u32) -> Vec<GameEvent> {
    let mut events = vec![];
    for _ in 0..count {
        state.tick(0.05);
        events.extend(state.take_events());
    }
    events
}
fn walk(state: &mut GameState, id: Uuid, goal: [f32; 3], bound: u32) -> u32 {
    let navigation = crate::maps::navigation(MapKind::LowWater);
    let mut nav = Navigator::default();
    for elapsed in 0..bound {
        let here = feet(state, id);
        if (here[0] - goal[0]).hypot(here[2] - goal[2]) < 0.4 && (here[1] - goal[1]).abs() < 0.1 {
            state.set_action(id, Action::default());
            return elapsed;
        }
        let arena = state.walking_arena(crate::maps::arena(MapKind::LowWater));
        let action = nav.steer_with_visibility(
            navigation,
            here,
            NavigationGoal {
                feet: goal,
                combat: false,
            },
            Action {
                forward: true,
                ..Default::default()
            },
            state.tick,
            true,
            &arena.solids,
        );
        assert!(!action.jump, "town routes use ordinary walking");
        let action = nav.avoid_bodies(&arena, id, &state.contact_bodies(), action, state.tick);
        state.set_action(id, action);
        tick(state, 1);
    }
    panic!(
        "Low Water walk {:?} -> {goal:?} exceeded {bound} ticks",
        feet(state, id)
    );
}
fn route(from: [f32; 3], to: [f32; 3]) -> u32 {
    let mut state = GameState::with_map(MapKind::LowWater, false);
    state.config.time_limit_ticks = None;
    state.config.boss_spawn_ticks = None;
    state.config.compliance_ping_ticks = None;
    let id = Uuid::from_u128(100);
    state.add_player(id, "Town route".into(), Role::Agent);
    state.start_round();
    let p = &mut state.players[0];
    p.x = from[0];
    p.y = from[1] + PLAYER_FLOOR_Y;
    p.z = from[2];
    p.vy = 0.0;
    walk(&mut state, id, to, 1600)
}
fn event(events: &[GameEvent], expected: SabotageEventKind) -> bool {
    events
        .iter()
        .any(|e| matches!(e, GameEvent::Sabotage {kind, ..} if *kind == expected))
}
fn ten() -> GameState {
    let mut state = GameState::with_map(MapKind::LowWater, false);
    state.seed(71);
    state.apply_config(config());
    for i in 1..=10 {
        state.add_player(
            Uuid::from_u128(i),
            format!("Town{i}"),
            if i == 1 { Role::Human } else { Role::Agent },
        );
    }
    state.start_round();
    tick(&mut state, 201);
    assert_eq!(
        state.snapshot().sabotage.unwrap().phase,
        SabotagePhase::Live
    );
    state
}

#[test]
fn low_water_layout_is_original_clear_supported_and_has_safe_five_side_slots() {
    let kind = MapKind::LowWater;
    assert!(
        crate::maps::validate(kind).is_empty(),
        "{:?}",
        crate::maps::validate(kind)
    );
    assert!(
        crate::maps::unreachable(kind).is_empty(),
        "{:?}",
        crate::maps::unreachable(kind)
    );
    let layout = kind.sabotage_layout().unwrap();
    layout.wire.validate().unwrap();
    let arena = crate::maps::arena(kind);
    crate::protocol::validate_map_presentation(Some(presentation()), &arena.solids).unwrap();
    for site in &layout.wire.sites {
        assert_eq!(
            layout.wire.callout_at(site.center[0], site.center[2]),
            Some(if site.id == SiteId::A {
                "clinic_steps"
            } else {
                "tram_stop"
            })
        );
        for x in -6..=6 {
            for z in -6..=6 {
                let (dx, dz) = (x as f32 * 0.5, z as f32 * 0.5);
                if dx.hypot(dz) <= site.radius {
                    let (x, z) = (site.center[0] + dx, site.center[2] + dz);
                    assert!(!arena.blocked_at(x, z, STREET + crate::movement::STEP_UP));
                    assert_eq!(
                        arena.support_height(x, z, STREET + crate::movement::STEP_UP),
                        STREET
                    );
                }
            }
        }
        for at in layout.holds[site.id.index()]
            .iter()
            .chain(&layout.stages[site.id.index()])
        {
            assert!(
                !arena.blocked_at(at[0], at[2], at[1] + crate::movement::STEP_UP),
                "blocked {at:?}"
            );
            assert_eq!(
                arena.support_height(at[0], at[2], at[1] + crate::movement::STEP_UP),
                at[1]
            );
        }
    }
    for side in 0..2 {
        assert_eq!(layout.spawns[side].len(), 5);
        for [x, floor, z, _] in &layout.spawns[side] {
            assert!(layout.in_muster(side, *x, *z));
            assert_eq!(*floor, STREET);
            assert!(!arena.blocked_at(*x, *z, *floor + crate::movement::STEP_UP));
            for [ox, ofloor, oz, _] in &layout.spawns[1 - side] {
                assert!(
                    !crate::combat::line_of_sight(
                        [*x, *floor + 1.6, *z],
                        [*ox, *ofloor + 1.6, *oz],
                        &arena.solids
                    ),
                    "exposed spawn {x},{z}->{ox},{oz}"
                );
            }
        }
    }
    assert!(kind.ctf_stands().is_none());
    assert_eq!(MapKind::from_cli("low_water"), Some(kind));
    assert_eq!(kind.id(), 8);
}

#[test]
fn low_water_side_swapped_routes_trench_bridges_supplies_and_retakes_use_real_movement() {
    let layout = MapKind::LowWater.sabotage_layout().unwrap();
    let sites = &layout.wire.sites;
    let mut routes = 0;
    for side in 0..2 {
        for (slot, [x, y, z, _]) in layout.spawns[side].iter().enumerate() {
            for site in sites {
                let ticks = route([*x, *y, *z], site.center);
                routes += 1;
                eprintln!(
                    "low_water side{side} slot{slot} -> {:?}: {ticks} ticks",
                    site.id
                );
                assert!(ticks < if side == 0 { 200 } else { 360 });
            }
        }
    }
    for site in sites {
        for at in layout.stages[site.id.index()]
            .iter()
            .chain(&layout.holds[site.id.index()])
        {
            route(*at, site.center);
            routes += 1;
        }
        for flank in [[-30.0, 0.0, 0.0], [30.0, 0.0, 0.0], [0.0, STREET, 30.0]] {
            route(flank, site.center);
            routes += 1;
        }
    }
    for x in [-30.0, 30.0] {
        for sign in [-1.0, 1.0] {
            for (from, to) in [
                ([x, 0.0, 0.0], [x, STREET, sign * 17.0]),
                ([x, STREET, sign * 17.0], [x, 0.0, 0.0]),
            ] {
                route(from, to);
                routes += 1;
            }
        }
    }
    for x in [-22.0, 8.0, 22.0] {
        route([x, STREET, -7.0], [x, STREET, 7.0]);
        route([x, STREET, 7.0], [x, STREET, -7.0]);
        routes += 2;
    }
    for pad in &town().map.pickups {
        route([0.0, 0.0, 0.0], [pad.x, pad.floor, pad.z]);
        routes += 1;
    }
    for (from, to) in [
        (sites[0].center, sites[1].center),
        (sites[1].center, sites[0].center),
    ] {
        let ticks = route(from, to);
        assert!(ticks < 280);
        routes += 1;
        eprintln!("low_water retake {from:?}->{to:?}: {ticks} ticks");
    }
    eprintln!("low_water movement routes: {routes}");
}

#[test]
fn low_water_normal_finite_ten_player_plant_cancel_defuse_and_both_sites() {
    for site in MapKind::LowWater.sabotage_map().unwrap().sites {
        let mut state = ten();
        for p in &state.players {
            assert_eq!(p.weapon, WeaponType::Tack);
            assert_eq!(
                p.inventory.state(p.id, p.weapon, state.tick).unwrap().ammo[0].rounds,
                50
            );
        }
        let carrier = state
            .snapshot()
            .sabotage
            .unwrap()
            .charge
            .unwrap()
            .carrier
            .unwrap();
        let defender = state
            .players
            .iter()
            .find(|p| p.team == Some(Team::Union))
            .unwrap()
            .id;
        walk(&mut state, carrier, site.center, 500);
        state.set_action(
            carrier,
            Action {
                interact: true,
                ..Default::default()
            },
        );
        tick(&mut state, 20);
        assert!(state.snapshot().sabotage.unwrap().progress.unwrap().ticks >= 19);
        state.set_action(carrier, Action::default());
        let cancelled = tick(&mut state, 1);
        assert!(event(&cancelled, SabotageEventKind::PlantInterrupted));
        state.set_action(
            carrier,
            Action {
                interact: true,
                ..Default::default()
            },
        );
        let planted = tick(&mut state, 61);
        assert!(event(&planted, SabotageEventKind::Planted));
        assert_eq!(
            state.snapshot().sabotage.unwrap().charge.unwrap().site,
            Some(site.id)
        );
        walk(&mut state, carrier, [site.center[0], STREET, 24.0], 120);
        walk(&mut state, defender, site.center, 350);
        state.set_action(
            defender,
            Action {
                interact: true,
                ..Default::default()
            },
        );
        let defused = tick(&mut state, 121);
        assert!(event(&defused, SabotageEventKind::Defused));
        assert_eq!(
            state.snapshot().sabotage.unwrap().charge.unwrap().status,
            ChargeStatus::Defused
        );
        assert!(defused.iter().any(|e|matches!(e,GameEvent::RoundEnd {sabotage:Some(result),..} if result.reason==SabotageReason::Defused)));
        eprintln!(
            "low_water {:?} ordinary finite10 plant/cancel/defuse tick{}",
            site.id, state.tick
        );
    }
}

#[test]
fn low_water_resolved_carrier_death_drops_charge_and_only_living_attackers_recover() {
    for waiting_attacker in [false, true] {
        let mut state = ten();
        let carrier = state
            .snapshot()
            .sabotage
            .unwrap()
            .charge
            .unwrap()
            .carrier
            .unwrap();
        let defender = state
            .players
            .iter()
            .find(|p| p.team == Some(Team::Union))
            .unwrap()
            .id;
        let recovery = state
            .players
            .iter()
            .find(|p| p.team == Some(Team::Coalition) && p.id != carrier)
            .unwrap()
            .id;
        walk(&mut state, carrier, [-22.0, STREET, -18.0], 500);
        walk(&mut state, defender, [-22.0, STREET, -14.0], 500);
        if waiting_attacker {
            walk(&mut state, recovery, [-23.0, STREET, -18.0], 500);
            let waiting = feet(&state, recovery);
            let carried = feet(&state, carrier);
            assert!((waiting[0] - carried[0]).hypot(waiting[2] - carried[2]) < 1.5);
        }
        state.set_action(
            defender,
            Action {
                fire: true,
                look_at: Some(crate::protocol::LookAt {
                    player_id: Some(carrier),
                    x: None,
                    y: None,
                    z: None,
                }),
                ..Default::default()
            },
        );
        let mut events = vec![];
        for _ in 0..300 {
            events.extend(tick(&mut state, 1));
            if state.players.iter().find(|p| p.id == carrier).unwrap().hp == 0 {
                break;
            }
        }
        state.set_action(defender, Action::default());
        assert!(
            state.players.iter().find(|p| p.id == carrier).unwrap().hp == 0,
            "finite ordinary Tack fire must resolve the carrier death"
        );
        let carrier_name = &state.players.iter().find(|p| p.id == carrier).unwrap().name;
        let defender_name = &state
            .players
            .iter()
            .find(|p| p.id == defender)
            .unwrap()
            .name;
        assert!(events.iter().any(|e| matches!(e, GameEvent::Frag { victim, killer, .. } if victim == carrier_name && killer == defender_name)));
        assert!(event(&events, SabotageEventKind::ChargeDropped));
        let loose = state.snapshot().sabotage.unwrap().charge.unwrap();
        assert_eq!(loose.status, ChargeStatus::Dropped);
        let shooter = state.players.iter().find(|p| p.id == defender).unwrap();
        assert!(
            shooter
                .inventory
                .state(defender, shooter.weapon, state.tick)
                .unwrap()
                .ammo[0]
                .rounds
                < 50
        );
        tick(&mut state, 9);
        assert_eq!(
            state.snapshot().sabotage.unwrap().charge.unwrap().status,
            ChargeStatus::Dropped
        );
        if waiting_attacker {
            tick(&mut state, 1);
            assert_eq!(
                state.snapshot().sabotage.unwrap().charge.unwrap().carrier,
                Some(recovery),
                "nearby ordinary attacker waits exactly ten ticks before contact recovery"
            );
            eprintln!("low_water actual nearby attacker cannot recover resolved carrier drop until tick10: tick{}",state.tick);
            continue;
        }
        walk(&mut state, defender, loose.position, 100);
        tick(&mut state, 20);
        assert_eq!(
            state.snapshot().sabotage.unwrap().charge.unwrap().status,
            ChargeStatus::Dropped,
            "defender contact cannot claim the loose charge"
        );
        walk(&mut state, defender, [-26.0, STREET, -14.0], 100);
        walk(&mut state, recovery, loose.position, 500);
        assert_eq!(
            state.snapshot().sabotage.unwrap().charge.unwrap().carrier,
            Some(recovery)
        );
        assert_eq!(
            state.snapshot().sabotage.unwrap().phase,
            SabotagePhase::Live
        );
        eprintln!("low_water ordinary finite Tack carrier death, visible drop, defender refusal and attacker recovery: tick{}", state.tick);
    }
}

#[test]
fn low_water_ten_rule_bots_finish_a_normal_finite_match_and_swap_sides() {
    for seed in [71, 72] {
        let mut session = GameSession::with_map(MapKind::LowWater, false);
        session.state.seed(seed);
        session.state.apply_config(config());
        session.spawn_bots(10);
        session.state.start_round();
        let mut plants = 0;
        let mut defuses = 0;
        let mut drops = 0;
        let mut frags = 0;
        let mut swaps = 0;
        let mut rounds = 0;
        let mut finished = false;
        for _ in 0..36_000 {
            for message in session.tick_messages(0.05) {
                if let ServerMessage::Event(data) = message {
                    match data {
                        GameEvent::Sabotage { kind, .. } => match kind {
                            SabotageEventKind::Planted => plants += 1,
                            SabotageEventKind::Defused => defuses += 1,
                            SabotageEventKind::ChargeDropped => drops += 1,
                            SabotageEventKind::SidesSwapped => swaps += 1,
                            _ => {}
                        },
                        GameEvent::Frag { .. } => frags += 1,
                        GameEvent::RoundEnd {
                            sabotage: Some(result),
                            ..
                        } => {
                            rounds += 1;
                            finished = result.match_over;
                        }
                        _ => {}
                    }
                }
            }
            if finished {
                break;
            }
        }
        eprintln!("low_water bot match seed{seed} ticks{} rounds{rounds} plants{plants} defuses{defuses} drops{drops} frags{frags} swaps{swaps}",session.state.tick);
        assert!(finished && swaps > 0 && frags > 0 && rounds >= 5);
        assert_eq!(session.state.players.len(), 10);
    }
}
