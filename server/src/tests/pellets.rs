//! Scatter blasts are seven seeded pellets, each a ray against cover and
//! fighters, with damage summed per struck fighter.
use crate::maps::AuthoredMap;
use crate::protocol::{
    Action, AmmoPool, GameEvent, Role, ShotImpact, ShotResult, WeaponType, SCATTER_PELLETS,
};
use crate::sim::{GameState, PLAYER_FLOOR_Y};
use uuid::Uuid;

const SHOOTER: Uuid = Uuid::from_u128(1);

/// A flat authored room with optional solids. Full arsenal unless `discovery`.
fn range(solids: serde_json::Value, discovery: bool) -> GameState {
    let json = serde_json::json!({
        "version":1,"map_id":1004,"name":"Pellet range","half_extent":16,"ground":"concrete",
        "equipment": if discovery { "discovery" } else { "full_arsenal" },
        "solids": solids,
        "spawns":[{"id":"entry","feet":[0,0,0],"yaw":0}],
        "landmarks":[{"id":"far","feet":[6,0,0]}]
    });
    let mut state = GameState::with_authored_map(
        AuthoredMap::read(serde_json::to_vec(&json).unwrap().as_slice()).unwrap(),
    );
    state.seed(7);
    state.add_player(SHOOTER, "Shooter".into(), Role::Human);
    place(&mut state, SHOOTER, [0.0, 0.0, 0.0]);
    state.players[0].weapon = WeaponType::Scatter;
    state
}

fn place(state: &mut GameState, id: Uuid, feet: [f32; 3]) {
    let player = state.players.iter_mut().find(|p| p.id == id).unwrap();
    player.x = feet[0];
    player.y = feet[1] + PLAYER_FLOOR_Y;
    player.z = feet[2];
    player.yaw = 0.0;
    player.pitch = 0.0;
}

fn target(state: &mut GameState, n: u128, feet: [f32; 3]) -> Uuid {
    let id = Uuid::from_u128(100 + n);
    state.add_player(id, format!("Target {n}"), Role::Agent);
    place(state, id, feet);
    id
}

/// Fire one blast aimed straight down +X and return its results.
fn blast(state: &mut GameState) -> Vec<ShotResult> {
    for _ in 0..40 {
        state.set_action(
            SHOOTER,
            Action {
                fire: true,
                yaw: Some(0.0),
                pitch: Some(0.0),
                ..Default::default()
            },
        );
        state.tick(0.05);
        let results: Vec<ShotResult> = state
            .shot_results
            .iter()
            .filter(|shot| shot.shooter_id == SHOOTER)
            .cloned()
            .collect();
        if !results.is_empty() {
            state.set_action(SHOOTER, Action::default());
            state.tick(0.05);
            return results;
        }
    }
    panic!("the scatter gun never fired");
}

fn pellets(results: &[ShotResult]) -> usize {
    results
        .iter()
        .map(|shot| shot.trace.as_ref().unwrap().pellets.len())
        .sum()
}

fn hp(state: &GameState, id: Uuid) -> i32 {
    state.players.iter().find(|p| p.id == id).unwrap().hp
}

fn distance(origin: [f32; 3], end: [f32; 3]) -> f32 {
    (0..3)
        .map(|axis| (end[axis] - origin[axis]).powi(2))
        .sum::<f32>()
        .sqrt()
}

#[test]
fn a_point_blank_blast_lands_every_pellet_and_two_blasts_kill() {
    let mut state = range(serde_json::json!([]), false);
    let victim = target(&mut state, 1, [2.0, 0.0, 0.0]);
    let first = blast(&mut state);
    assert_eq!(first.len(), 1, "every pellet struck the same fighter");
    let shot = &first[0];
    let trace = shot.trace.as_ref().unwrap();
    assert!(shot.hit && !shot.killed);
    assert_eq!(trace.pellets.len(), SCATTER_PELLETS);
    assert_eq!(
        (trace.end, &trace.impact),
        (trace.pellets[0].end, &trace.pellets[0].impact)
    );
    assert!(trace
        .pellets
        .iter()
        .all(|pellet| matches!(pellet.impact, ShotImpact::Fighter { .. })));
    assert_eq!(shot.damage, 70, "seven full pellets, Doom's average blast");
    assert_eq!(hp(&state, victim), 30);
    state.take_events();

    let second = blast(&mut state);
    assert_eq!(second.len(), 1);
    assert!(second[0].killed);
    assert_eq!(
        second[0].damage, 70,
        "result damage includes overkill; records do not"
    );
    let frags = state
        .take_events()
        .into_iter()
        .filter(|event| matches!(event, GameEvent::Frag { .. }))
        .count();
    assert_eq!(frags, 1, "seven lethal pellets are one frag");
    assert_eq!(state.scores.get(&SHOOTER), Some(&1));
}

#[test]
fn every_pellet_falls_off_by_its_own_distance() {
    let mut state = range(serde_json::json!([]), false);
    let victim = target(&mut state, 1, [9.0, 0.0, 0.0]);
    let results = blast(&mut state);
    assert_eq!(pellets(&results), SCATTER_PELLETS);
    let hit = results
        .iter()
        .find(|shot| shot.hit)
        .expect("some pellets land at nine units");
    let trace = hit.trace.as_ref().unwrap();
    let expected: i32 = trace
        .pellets
        .iter()
        .map(|pellet| WeaponType::Scatter.damage_at(distance(trace.origin, pellet.end)))
        .sum();
    assert_eq!(hit.damage, expected);
    assert_eq!(100 - hp(&state, victim), expected);
    assert!(
        trace.pellets.iter().all(|pellet| WeaponType::Scatter
            .damage_at(distance(trace.origin, pellet.end))
            < WeaponType::Scatter.damage()),
        "past four units every pellet is below full damage"
    );
    assert!(
        hit.damage < 70 / 2,
        "a nine unit blast is far weaker than point blank"
    );
    // A pellet that misses keeps flying and records where it stopped.
    for miss in results.iter().filter(|shot| !shot.hit) {
        assert_eq!(miss.damage, 0);
        assert!(miss.target_id.is_none());
        assert!(!miss.trace.as_ref().unwrap().pellets.is_empty());
    }
}

#[test]
fn cover_stops_pellets_and_a_partial_wall_splits_the_blast() {
    // A full wall between shooter and target stops every pellet.
    let wall =
        serde_json::json!([{"id":"wall","min":[1.2,0,-2],"max":[1.4,3,2],"surface":"enamel"}]);
    let mut state = range(wall, false);
    let victim = target(&mut state, 1, [2.5, 0.0, 0.0]);
    let results = blast(&mut state);
    assert_eq!(results.len(), 1);
    assert!(!results[0].hit);
    assert_eq!(pellets(&results), SCATTER_PELLETS);
    assert!(results[0]
        .trace
        .as_ref()
        .unwrap()
        .pellets
        .iter()
        .all(|pellet| matches!(pellet.impact, ShotImpact::Solid { .. })
            && (pellet.end[0] - 1.2).abs() < 0.001));
    assert_eq!(hp(&state, victim), 100);

    // A waist-high wall at the muzzle covers only the lower part of the cone.
    let low =
        serde_json::json!([{"id":"sill","min":[1.2,0,-2],"max":[1.4,1.6,2],"surface":"enamel"}]);
    let mut state = range(low, false);
    let victim = target(&mut state, 1, [3.5, 0.0, 0.0]);
    let results = blast(&mut state);
    assert_eq!(pellets(&results), SCATTER_PELLETS);
    let landed: usize = results
        .iter()
        .filter(|shot| shot.hit)
        .map(|shot| shot.trace.as_ref().unwrap().pellets.len())
        .sum();
    assert!(
        (1..SCATTER_PELLETS).contains(&landed),
        "the sill stops some pellets and not others, {landed} landed"
    );
    assert_eq!(
        results.last().map(|shot| shot.hit),
        Some(false),
        "misses come last"
    );
    assert_eq!(100 - hp(&state, victim), 10 * landed as i32);
}

#[test]
fn one_blast_spreads_across_two_fighters_with_one_frag_each() {
    let mut state = range(serde_json::json!([]), false);
    // Two bodies side by side, touching at the aim line.
    let left = target(&mut state, 1, [3.0, 0.0, 0.5]);
    let right = target(&mut state, 2, [3.0, 0.0, -0.5]);
    let results = blast(&mut state);
    assert_eq!(pellets(&results), SCATTER_PELLETS);
    let struck: Vec<Uuid> = results.iter().filter_map(|shot| shot.target_id).collect();
    assert_eq!(struck.len(), 2, "each fighter gets one result: {results:?}");
    assert!(struck.contains(&left) && struck.contains(&right));
    for shot in results.iter().filter(|shot| shot.hit) {
        let count = shot.trace.as_ref().unwrap().pellets.len() as i32;
        assert_eq!(shot.damage, 10 * count);
        assert_eq!(100 - hp(&state, shot.target_id.unwrap()), shot.damage);
    }

    // Replay the same seeded blast with both nearly dead: two deaths, two
    // frags, and each death is flagged on its own fighter's result once.
    let mut state = range(serde_json::json!([]), false);
    for (n, z) in [(1, 0.5), (2, -0.5)] {
        let id = target(&mut state, n, [3.0, 0.0, z]);
        state.players.iter_mut().find(|p| p.id == id).unwrap().hp = 5;
    }
    state.take_events();
    let replay = blast(&mut state);
    assert_eq!(
        replay
            .iter()
            .map(|shot| shot.trace.clone())
            .collect::<Vec<_>>(),
        results
            .iter()
            .map(|shot| shot.trace.clone())
            .collect::<Vec<_>>(),
        "same seed, same pellets"
    );
    let results = replay;
    assert_eq!(results.iter().filter(|shot| shot.killed).count(), 2);
    let frags = state
        .take_events()
        .into_iter()
        .filter(|event| matches!(event, GameEvent::Frag { .. }))
        .count();
    assert_eq!(frags, 2);
    assert_eq!(state.scores.get(&SHOOTER), Some(&2));
}

#[test]
fn a_discovered_scatter_blast_spends_one_shell_for_seven_pellets() {
    let mut state = range(serde_json::json!([]), true);
    let player = &mut state.players[0];
    assert!(player.inventory.grant_weapon(WeaponType::Scatter));
    player.weapon = WeaponType::Scatter;
    target(&mut state, 1, [3.0, 0.0, 0.0]);
    let results = blast(&mut state);
    assert_eq!(pellets(&results), SCATTER_PELLETS);
    let loadout = state.players[0]
        .inventory
        .state(SHOOTER, WeaponType::Scatter, state.tick)
        .unwrap();
    assert_eq!(
        loadout.ammo(AmmoPool::Shells),
        WeaponType::Scatter.pickup_rounds() - 1
    );
    assert_eq!(loadout.ammo(AmmoPool::Bullets), 0);
}

#[test]
fn single_ray_weapons_carry_no_pellet_list() {
    let mut state = range(serde_json::json!([]), false);
    state.players[0].weapon = WeaponType::Rail;
    target(&mut state, 1, [6.0, 0.0, 0.0]);
    let results = blast(&mut state);
    assert_eq!(results.len(), 1);
    assert!(results[0].trace.as_ref().unwrap().pellets.is_empty());
    let wire = serde_json::to_value(&results[0]).unwrap();
    assert!(
        wire["trace"].get("pellets").is_none(),
        "omitted on the wire"
    );
}
