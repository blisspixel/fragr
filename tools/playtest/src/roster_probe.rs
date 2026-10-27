//! Planner reach on a floor with dropped guns: the regression tests for the
//! wave 11 roster stall (a planner leaning on cover at a gun it could not
//! walk to), and the offline stall probe that found it (ignored; run with
//! `cargo test -p fragr-playtest --release --lib probe_planner_stalls --
//! --ignored --nocapture`, `PROBE_SEEDS=1,2,3` to narrow).
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
    let tiers = [Policy::Reflex, Policy::Planner];
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
            if snapshot.round_state.as_deref() != Some("Active") {
                continue;
            }
            for (id, policy) in &fighters {
                let Some(me) = snapshot.players.iter().find(|p| p.id == *id) else {
                    last.remove(id);
                    continue;
                };
                let action = policy_action(*policy, *id, &snapshot, &arena);
                let pos = (me.x, me.z);
                let entry = last.entry(*id).or_insert((pos, snapshot.tick));
                let moved = (pos.0 - entry.0 .0).hypot(pos.1 - entry.0 .1);
                if moved >= 0.05 || me.just_fired {
                    *entry = (pos, snapshot.tick);
                } else if snapshot.tick - entry.1 == 100 {
                    let near: Vec<String> = snapshot
                        .pickups
                        .iter()
                        .filter(|p| (p.x - me.x).hypot(p.z - me.z) < 20.0)
                        .map(|p| format!("{} {} y{:.1} avail {}", p.id, p.weapon, p.y, p.available))
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
                    println!(
                        "seed {seed} tick {} {} stuck at ({:.1},{:.1}) y {:.2} hp {} weapon {} fwd {} l {} r {} fire {} look {:?} near {near:?} bag {bag:?}",
                        snapshot.tick,
                        me.name,
                        me.x,
                        me.z,
                        me.y,
                        me.hp,
                        me.weapon,
                        action.forward,
                        action.left,
                        action.right,
                        action.fire,
                        action.look_at.as_ref().map(|l| (l.x, l.z, l.player_id))
                    );
                }
                session.apply_command(GameCommand::Action {
                    player_id: *id,
                    action,
                });
            }
        }
    }
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
