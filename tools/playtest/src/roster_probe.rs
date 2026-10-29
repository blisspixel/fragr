//! Planner reach on a floor with dropped guns: the regression tests for the
//! wave 11 roster stall (a planner leaning on cover at a gun it could not
//! walk to), and the offline stall probe that found it (ignored; run with
//! `cargo test -p fragr-playtest --release --lib probe_planner_stalls --
//! --ignored --nocapture`, `PROBE_SEEDS=1,2,3` to narrow, `PROBE_MAP` and
//! `PROBE_AGENTS` for another roster case). The probe steers each agent
//! through the same loadout controller and navigator as a roster client and
//! counts stalls with the roster's own rule, so what it finds is what the
//! roster gate trips on.
use super::*;
use fragr_server::net::GameCommand;
use fragr_server::protocol::{BodyKind, Role, ServerMessage};
use fragr_server::sim::MapKind;

#[test]
#[ignore]
fn probe_planner_stalls_on_directive_17() {
    let seeds: Vec<u64> = std::env::var("PROBE_SEEDS")
        .ok()
        .map(|s| s.split(',').filter_map(|v| v.parse().ok()).collect())
        .unwrap_or_else(|| (1..=60).collect());
    let map = std::env::var("PROBE_MAP")
        .ok()
        .and_then(|raw| MapKind::from_cli(&raw))
        .unwrap_or(MapKind::Directive17);
    let agents: usize = std::env::var("PROBE_AGENTS")
        .ok()
        .and_then(|raw| raw.parse().ok())
        .unwrap_or(6);
    // The roster's agents steer through the loadout controller and the
    // navigation graph after their policy, exactly as `run_agent` does;
    // `PROBE_RAW=1` drives the bare policy instead.
    let wire = std::env::var("PROBE_RAW").is_err();
    let tiers = [Policy::Reflex, Policy::Planner];
    let world = fragr_server::navigation::Navigation::shared(fragr_server::movement::Arena {
        half: map.half_extent(),
        solids: map.solids(),
    })
    .expect("navigation");
    let mut stalls = 0;
    for seed in seeds {
        let mut session = fragr_server::session::GameSession::with_map(map, false);
        session.state.use_replay_ids();
        session.state.seed(seed);
        let cfg = fragr_server::sim::MatchConfig {
            frag_limit: Some(8),
            time_limit_ticks: Some(20 * 60),
            ..Default::default()
        };
        session.state.apply_config(cfg);
        let arena = Arena {
            solids: map.solids(),
            half_extent: map.half_extent(),
        };
        let fighters: Vec<(Uuid, Policy)> = (0..agents)
            .map(|n| (Uuid::from_u128(1000 + n as u128), tiers[n % 2]))
            .collect();
        for (n, (id, policy)) in fighters.iter().enumerate() {
            session.apply_command(GameCommand::Connected {
                id: Uuid::from_u128(2000 + n as u128),
                role: Role::Agent,
                name: format!("{}-{}", policy.name(), n + 1),
                player_id: Some(*id),
                body: BodyKind::Human,
            });
        }
        let mut steering: std::collections::HashMap<
            Uuid,
            (
                fragr_server::navigation::Navigator,
                fragr_server::mission::MissionClient,
            ),
        > = Default::default();
        // The harness's own stall rule: under `IDLE_EPSILON` a snapshot,
        // not firing, broken by a death.
        let mut last: std::collections::HashMap<Uuid, ((f32, f32), u64)> = Default::default();
        for _ in 0..20 * 62 {
            let snapshot = session
                .tick_messages(0.05)
                .into_iter()
                .find_map(|m| match m {
                    ServerMessage::Snapshot(s) => Some(s),
                    _ => None,
                });
            let Some(snapshot) = snapshot else { continue };
            // Exercise the same rounded observations as connected clients;
            // full-precision positions conceal near-edge steering failures.
            let snapshot: Snapshot = if wire {
                serde_json::from_slice(&serde_json::to_vec(&snapshot).unwrap()).unwrap()
            } else {
                snapshot
            };
            if snapshot.round_state.as_deref() != Some("Active") {
                continue;
            }
            for (id, policy) in &fighters {
                let Some(me) = snapshot.players.iter().find(|p| p.id == *id) else {
                    last.remove(id);
                    continue;
                };
                let raw = policy_action(*policy, *id, &snapshot, &arena);
                let loadout = session
                    .state
                    .players
                    .iter()
                    .find(|p| p.id == *id)
                    .and_then(|p| p.inventory.state(*id, p.weapon, snapshot.tick));
                let controlled = if wire {
                    fragr_server::inventory::control_action_with_target_filter(
                        *id,
                        &snapshot,
                        loadout.as_ref(),
                        raw.clone(),
                        false,
                        |_, _| true,
                    )
                } else {
                    raw.clone()
                };
                let action = if wire {
                    let (navigator, client) = steering.entry(*id).or_default();
                    client.steer_with_equipment(
                        navigator,
                        &world,
                        *id,
                        &snapshot,
                        controlled.clone(),
                        loadout.as_ref(),
                    )
                } else {
                    raw.clone()
                };
                let pos = (me.x, me.z);
                let entry = last.entry(*id).or_insert((pos, snapshot.tick));
                let moved = (pos.0 - entry.0 .0).hypot(pos.1 - entry.0 .1);
                entry.0 = pos;
                if moved >= IDLE_EPSILON || me.just_fired {
                    entry.1 = snapshot.tick;
                } else if snapshot.tick - entry.1 == 100 {
                    stalls += 1;
                    let near: Vec<String> = snapshot
                        .pickups
                        .iter()
                        .filter(|p| (p.x - me.x).hypot(p.z - me.z) < 20.0)
                        .map(|p| {
                            format!(
                                "{} {} d{:.1} y{:.1}",
                                p.id,
                                p.weapon,
                                (p.x - me.x).hypot(p.z - me.z),
                                p.y
                            )
                        })
                        .collect();
                    let bag: Vec<String> = session
                        .state
                        .players
                        .iter()
                        .find(|p| p.id == *id)
                        .map(|p| {
                            WeaponType::ALL
                                .into_iter()
                                .filter(|w| p.inventory.owns(*w))
                                .map(|w| {
                                    format!(
                                        "{w:?}:{}",
                                        w.ammo_pool().map_or(0, |pool| p.inventory.carried(pool))
                                    )
                                })
                                .collect()
                        })
                        .unwrap_or_default();
                    let aim = |a: &Action| {
                        a.look_at.as_ref().map(|l| {
                            (
                                l.x.map(|v| (v * 10.0).round() / 10.0),
                                l.z.map(|v| (v * 10.0).round() / 10.0),
                                l.player_id.map(|p| p.as_u128().wrapping_sub(999)),
                            )
                        })
                    };
                    println!(
                        "seed {seed} tick {} {} stuck at ({:.1},{:.1}) y {:.2} hp {} weapon {} raw fwd {} back {} l {} r {} fire {} look {:?} control fwd {} look {:?} driven fwd {} back {} l {} r {} yaw {:?} look {:?} near {near:?} bag {bag:?}",
                        snapshot.tick,
                        me.name,
                        me.x,
                        me.z,
                        me.y,
                        me.hp,
                        me.weapon,
                        raw.forward,
                        raw.back,
                        raw.left,
                        raw.right,
                        raw.fire,
                        aim(&raw),
                        controlled.forward,
                        aim(&controlled),
                        action.forward,
                        action.back,
                        action.left,
                        action.right,
                        action.yaw,
                        aim(&action),
                    );
                }
                session.apply_command(GameCommand::Action {
                    player_id: *id,
                    action,
                });
            }
        }
    }
    println!("probe: {stalls} stalls over 5 s");
}

/// A lone planner on Directive 17's north corridor, south of the cover block
/// at (0, -38), with nothing on the floor but what a test adds.
fn lone_planner() -> (fragr_server::sim::GameState, Uuid, Arena) {
    let mut state = fragr_server::sim::GameState::with_map(MapKind::Directive17, false);
    state.start_round();
    state.pickups.clear();
    let id = Uuid::from_u128(77);
    state.add_player(id, "planner-1".into(), Role::Agent);
    let me = state.players.iter_mut().find(|p| p.id == id).unwrap();
    me.x = 0.0;
    me.z = -42.0;
    me.y = fragr_server::sim::PLAYER_FLOOR_Y;
    let arena = Arena {
        solids: MapKind::Directive17.solids(),
        half_extent: MapKind::Directive17.half_extent(),
    };
    (state, id, arena)
}

fn drop_at(state: &mut fragr_server::sim::GameState, x: f32, z: f32, floor: f32) {
    let serial = state.dropped_guns.len() as u32 + 1;
    state
        .dropped_guns
        .push(fragr_server::sim::drops::DroppedGun {
            serial,
            weapon: WeaponType::Scatter,
            rounds: 6,
            x,
            y: floor + 0.4,
            z,
            floor,
            expires_at: 100_000,
        });
}

fn aims_at(action: &Action, x: f32, z: f32) -> bool {
    action
        .look_at
        .as_ref()
        .is_some_and(|look| look.x == Some(x) && look.z == Some(z))
}

#[test]
fn a_planner_never_walks_at_a_dropped_gun_it_cannot_reach_straight() {
    // Behind the cover block: the straight walk leans on the block.
    let (mut state, id, arena) = lone_planner();
    drop_at(&mut state, 0.0, -34.0, 0.0);
    let action = planner_action(id, &state.snapshot(), &arena);
    assert!(!aims_at(&action, 0.0, -34.0), "{action:?}");

    // Up on a quadrant deck: no straight walk climbs three metres.
    let (mut state, id, arena) = lone_planner();
    drop_at(&mut state, -22.0, -42.0, 0.0);
    state.dropped_guns[0].floor = 3.0;
    state.dropped_guns[0].y = 3.4;
    let action = planner_action(id, &state.snapshot(), &arena);
    assert!(!aims_at(&action, -22.0, -42.0), "{action:?}");

    // Standing on one the server would not hand over: it moves on.
    let (mut state, id, arena) = lone_planner();
    drop_at(&mut state, 0.5, -42.0, 0.0);
    let action = planner_action(id, &state.snapshot(), &arena);
    assert!(!aims_at(&action, 0.5, -42.0), "{action:?}");

    // On its own floor in the open: it goes for it.
    let (mut state, id, arena) = lone_planner();
    drop_at(&mut state, 6.0, -44.0, 0.0);
    let action = planner_action(id, &state.snapshot(), &arena);
    assert!(aims_at(&action, 6.0, -44.0) && action.forward, "{action:?}");
}

#[test]
fn a_planner_strafes_round_cover_on_the_way_to_a_pad() {
    let (mut state, id, arena) = lone_planner();
    let mut full = fragr_server::sim::GameState::with_map(MapKind::Directive17, false);
    full.start_round();
    state.pickups = full
        .pickups
        .into_iter()
        .filter(|pad| pad.id == "scrap_flechette_n")
        .collect();
    let pad = state.pickups[0].clone();
    let me = state.players.iter_mut().find(|p| p.id == id).unwrap();
    me.x = pad.x;
    me.z = -42.0;
    let action = planner_action(id, &state.snapshot(), &arena);
    assert!(aims_at(&action, pad.x, pad.z), "{action:?}");
    assert!(
        action.forward && (action.left || action.right),
        "{action:?}"
    );
    // With the lane open it walks straight.
    let me = state.players.iter_mut().find(|p| p.id == id).unwrap();
    me.x = pad.x + 4.0;
    me.z = pad.z;
    let action = planner_action(id, &state.snapshot(), &arena);
    assert!(
        action.forward && !action.left && !action.right,
        "{action:?}"
    );
}

#[test]
fn a_fighter_slides_along_a_kerb_it_can_see_over() {
    let mut state = fragr_server::sim::GameState::new();
    state.start_round();
    let (me, foe) = (Uuid::from_u128(1), Uuid::from_u128(2));
    state.add_player(me, "reflex-1".into(), Role::Agent);
    state.add_player(foe, "reflex-2".into(), Role::Agent);
    for (id, z) in [(me, 0.0), (foe, 12.0)] {
        let p = state.players.iter_mut().find(|p| p.id == id).unwrap();
        p.x = 0.0;
        p.z = z;
        p.y = fragr_server::sim::PLAYER_FLOOR_Y;
    }
    // Knee high across the lane, well under the eye line.
    let kerb = fragr_server::movement::Solid::from_center_top(0.0, 1.5, 3.0, 0.2, 0.6);
    let open = Arena {
        solids: Vec::new(),
        half_extent: 25.0,
    };
    let kerbed = Arena {
        solids: vec![kerb],
        half_extent: 25.0,
    };
    let snapshot = state.snapshot();
    let straight = reflex_action(me, &snapshot, &open);
    assert!(
        straight.forward && !straight.left && !straight.right,
        "{straight:?}"
    );
    let snagged = reflex_action(me, &snapshot, &kerbed);
    assert!(
        snagged.forward && (snagged.left || snagged.right),
        "{snagged:?}"
    );
    let planned = planner_action(me, &snapshot, &kerbed);
    assert!(planned.left || planned.right, "{planned:?}");
}
