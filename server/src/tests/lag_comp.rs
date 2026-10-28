//! Bounded hitscan lag compensation (#434 stage 5): the view a human client
//! reports is admitted against the newest server tick, clamped to 200 ms and
//! never stretched across a broken history.

use crate::protocol::{Action, ClientMessage, EquipmentPolicy, Role, ShotResult, WeaponType};
use crate::sim::rewind::{RewindStats, MAX_REWIND_TICKS};
use crate::sim::{GameState, PLAYER_FLOOR_Y};
use uuid::Uuid;

const SHOOTER: Uuid = Uuid::from_u128(0x10c0);
const TARGET: Uuid = Uuid::from_u128(0x10c1);
/// A strafer's step per tick: 7 m/s at 20 Hz.
const STEP: f32 = 0.35;

fn lane(target_role: Role) -> GameState {
    let mut state = GameState::new();
    state.seed(7);
    state.start_round();
    state.pickups.clear();
    state.add_player(SHOOTER, "shooter".into(), Role::Human);
    state.add_player(TARGET, "target".into(), target_role);
    // The target starts west of the lane so its strafe stays in the open.
    for (id, x, z) in [(SHOOTER, 0.0, -8.0), (TARGET, -3.0, 8.0)] {
        let p = state.players.iter_mut().find(|p| p.id == id).unwrap();
        [p.x, p.y, p.z] = [x, PLAYER_FLOOR_Y, z];
        p.vy = 0.0;
    }
    state.spawn_shields.clear();
    let shooter = state.players.iter_mut().find(|p| p.id == SHOOTER).unwrap();
    shooter.inventory = crate::inventory::Inventory::new(EquipmentPolicy::Discovery);
    shooter.inventory.grant_weapon(WeaponType::Rail);
    shooter.weapon = WeaponType::Rail;
    state
}

fn target_feet(state: &GameState) -> [f32; 3] {
    let p = state.players.iter().find(|p| p.id == TARGET).unwrap();
    [p.x, p.y - PLAYER_FLOOR_Y, p.z]
}

/// Tick with the target carried `STEP` along x before each tick, and return
/// the feet recorded at the end of every tick, by tick.
fn strafe(state: &mut GameState, ticks: u64) -> Vec<(u64, [f32; 3])> {
    let mut seen = Vec::new();
    for _ in 0..ticks {
        let p = state.players.iter_mut().find(|p| p.id == TARGET).unwrap();
        p.x += STEP;
        state.tick(0.0);
        seen.push((state.tick, target_feet(state)));
    }
    seen
}

fn feet_at(seen: &[(u64, [f32; 3])], view: f64) -> [f32; 3] {
    let from = view.floor() as u64;
    let a = seen.iter().find(|(t, _)| *t == from).unwrap().1;
    let b = seen.iter().find(|(t, _)| *t == from + 1).unwrap().1;
    let w = (view - from as f64) as f32;
    std::array::from_fn(|i| a[i] + (b[i] - a[i]) * w)
}

/// Fire one Rail shot at `point` with the given view; the target keeps
/// strafing through the firing tick.
fn fire_at(state: &mut GameState, point: [f32; 3], view_tick: Option<f64>) -> Vec<ShotResult> {
    let eye = {
        let p = state.players.iter().find(|p| p.id == SHOOTER).unwrap();
        [
            p.x,
            p.y - PLAYER_FLOOR_Y + crate::combat::stance_eye(None, false),
            p.z,
        ]
    };
    let (yaw, pitch) = crate::combat::aim_at(eye, point).unwrap();
    state.set_action(
        SHOOTER,
        Action {
            fire: true,
            yaw: Some(yaw),
            pitch: Some(pitch),
            view_tick,
            ..Default::default()
        },
    );
    let p = state.players.iter_mut().find(|p| p.id == TARGET).unwrap();
    p.x += STEP;
    state.tick(0.0);
    state
        .shot_results
        .iter()
        .filter(|shot| shot.shooter_id == SHOOTER)
        .cloned()
        .collect()
}

fn hit(results: &[ShotResult]) -> bool {
    results.iter().any(|shot| shot.target_id == Some(TARGET))
}

fn chest(feet: [f32; 3]) -> [f32; 3] {
    crate::combat::aim_point_for(feet, None, false)
}

#[test]
fn a_shot_at_100_ms_rtt_misses_in_the_present_and_lands_rewound() {
    // 100 ms round trip, the two-tick buffer and half a tick of render phase:
    // the client drew the target 4.5 ticks before the firing tick.
    for (view, expect_hit) in [(None, false), (Some(()), true)] {
        let mut state = lane(Role::Agent);
        let seen = strafe(&mut state, 12);
        let received_at = state.tick;
        let drawn = received_at as f64 - 3.5;
        let results = fire_at(
            &mut state,
            chest(feet_at(&seen, drawn)),
            view.map(|_| drawn),
        );
        assert_eq!(hit(&results), expect_hit, "view {view:?}: {results:?}");
        if expect_hit {
            // The 4.5-tick lag exceeds the bound; the residual half tick of
            // movement (0.175 m) stays inside the body.
            assert_eq!(
                state.rewind_stats,
                RewindStats {
                    accepted: 1,
                    rewinds: 1,
                    clamped: 1,
                    ..RewindStats::default()
                }
            );
            // Damage applied once, through the ordinary path.
            let hp = state.players.iter().find(|p| p.id == TARGET).unwrap().hp;
            assert_eq!(results.len(), 1);
            assert!(results[0].damage > 0);
            assert_eq!(results[0].target_hp_after, Some(hp));
        } else {
            assert_eq!(state.rewind_stats, RewindStats::default());
        }
    }
}

#[test]
fn a_view_beyond_the_bound_is_clamped_to_200_ms() {
    let mut state = lane(Role::Agent);
    let seen = strafe(&mut state, 16);
    let received_at = state.tick;
    let claimed = received_at as f64 - 10.0;
    // Aimed where the client claims it looked: a 550 ms rewind is refused.
    let results = fire_at(&mut state, chest(feet_at(&seen, claimed)), Some(claimed));
    assert!(!hit(&results), "{results:?}");
    assert_eq!(state.rewind_stats.clamped, 1);

    // Aimed at the bound itself: the firing tick less four ticks.
    let mut state = lane(Role::Agent);
    let seen = strafe(&mut state, 16);
    let received_at = state.tick;
    let bound = (received_at + 1 - MAX_REWIND_TICKS) as f64;
    let results = fire_at(
        &mut state,
        chest(feet_at(&seen, bound)),
        Some(received_at as f64 - 10.0),
    );
    assert!(hit(&results), "{results:?}");
    assert_eq!(state.rewind_stats.clamped, 1);
    assert_eq!(state.rewind_stats.rewinds, 1);
}

#[test]
fn a_forged_view_is_refused_and_the_shot_tests_the_present() {
    for forged in [1.0, 0.25, 40.0] {
        let mut state = lane(Role::Agent);
        let seen = strafe(&mut state, 12);
        let received_at = state.tick;
        // A tick the server has not produced: no client drew it.
        let future = received_at as f64 + forged;
        let past = chest(feet_at(&seen, received_at as f64 - 3.0));
        let results = fire_at(&mut state, past, Some(future));
        assert!(!hit(&results), "{forged}: {results:?}");
        assert_eq!(
            state.rewind_stats,
            RewindStats {
                refused: 1,
                ..RewindStats::default()
            }
        );
    }
    // Negative, and present aim with a refused view still lands.
    let mut state = lane(Role::Agent);
    strafe(&mut state, 12);
    let mut now = target_feet(&state);
    now[0] += STEP;
    let results = fire_at(&mut state, chest(now), Some(-1.0));
    assert!(hit(&results), "{results:?}");
    assert_eq!(state.rewind_stats.refused, 1);
    assert_eq!(state.rewind_stats.rewinds, 0);
}

#[test]
fn the_wire_carries_a_fractional_view_and_refuses_a_malformed_one() {
    let parsed: ClientMessage =
        serde_json::from_str(r#"{"type":"action","fire":true,"view_tick":1234.5}"#).unwrap();
    let ClientMessage::Action(action) = parsed else {
        panic!("not an action");
    };
    assert_eq!(action.view_tick, Some(1234.5));
    let text = serde_json::to_string(&Action::default()).unwrap();
    assert!(!text.contains("view_tick"), "{text}");
    for bad in [
        r#"{"type":"action","view_tick":"12"}"#,
        r#"{"type":"action","view_tick":null,"view_lerp":0.5}"#,
        r#"{"type":"action","view_tick":[1]}"#,
    ] {
        assert!(serde_json::from_str::<ClientMessage>(bad).is_err(), "{bad}");
    }
}

#[test]
fn nothing_changes_without_latency_or_without_a_view() {
    // A still target: whatever the view, the drawn body is the present one,
    // and the shot, its damage and its trace are identical.
    let run = |view: Option<f64>| {
        let mut state = lane(Role::Agent);
        for _ in 0..8 {
            state.tick(0.0);
        }
        let point = chest(target_feet(&state));
        let received_at = state.tick as f64;
        let view = view.map(|lag: f64| received_at - lag);
        let eye = [0.0, crate::combat::stance_eye(None, false), -8.0];
        let (yaw, pitch) = crate::combat::aim_at(eye, point).unwrap();
        state.set_action(
            SHOOTER,
            Action {
                fire: true,
                yaw: Some(yaw),
                pitch: Some(pitch),
                view_tick: view,
                ..Default::default()
            },
        );
        state.tick(0.0);
        (state.shot_results.clone(), state.rewind_stats)
    };
    let (present, stats) = run(None);
    assert!(hit(&present));
    assert_eq!(stats, RewindStats::default());
    for lag in [0.0, 1.0, 2.5] {
        let (rewound, stats) = run(Some(lag));
        assert_eq!(rewound, present, "lag {lag}");
        assert_eq!(stats.rewinds, 1);
        assert_eq!(stats.discontinuities, 0);
    }
}

#[test]
fn a_broken_history_is_tested_in_the_present() {
    let mut state = lane(Role::Agent);
    let seen = strafe(&mut state, 12);
    let received_at = state.tick;
    // A respawn or placement since the view starts a new movement epoch.
    state
        .players
        .iter_mut()
        .find(|p| p.id == TARGET)
        .unwrap()
        .reset_movement_baseline();
    let drawn = received_at as f64 - 2.0;
    let results = fire_at(&mut state, chest(feet_at(&seen, drawn)), Some(drawn));
    assert!(!hit(&results), "{results:?}");
    assert_eq!(state.rewind_stats.discontinuities, 1);
}

#[test]
fn an_agent_view_is_ignored() {
    let mut state = lane(Role::Agent);
    state
        .players
        .iter_mut()
        .find(|p| p.id == SHOOTER)
        .unwrap()
        .role = Role::Agent;
    let seen = strafe(&mut state, 12);
    let drawn = state.tick as f64 - 2.0;
    let results = fire_at(&mut state, chest(feet_at(&seen, drawn)), Some(drawn));
    assert!(!hit(&results), "{results:?}");
    assert_eq!(state.rewind_stats, RewindStats::default());
}

#[test]
fn the_head_band_follows_the_rewound_body() {
    // The target was a metre up (a jump) when drawn and has landed since.
    let mut state = lane(Role::Human);
    for lift in [1.0, 1.0, 1.0, 0.6, 0.2, 0.0] {
        let p = state.players.iter_mut().find(|p| p.id == TARGET).unwrap();
        p.y = PLAYER_FLOOR_Y + lift;
        state.tick(0.0);
    }
    let drawn = state.tick as f64 - 3.0;
    let feet = [-3.0, 1.0, 8.0];
    let head = [
        feet[0],
        feet[1] + crate::combat::target_height(None) - 0.1,
        feet[2],
    ];
    let results = fire_at(&mut state, head, Some(drawn));
    assert!(hit(&results), "{results:?}");
    assert!(results[0].head, "{results:?}");
    // In the present the same ray passes over the landed head.
    let mut state = lane(Role::Human);
    for lift in [1.0, 1.0, 1.0, 0.6, 0.2, 0.0] {
        let p = state.players.iter_mut().find(|p| p.id == TARGET).unwrap();
        p.y = PLAYER_FLOOR_Y + lift;
        state.tick(0.0);
    }
    let results = fire_at(&mut state, head, None);
    assert!(!hit(&results), "{results:?}");
}

#[test]
fn cover_stays_in_the_present() {
    // A wall standing now between the shooter and the drawn body stops the
    // rewound ray; without it the same rewound ray meets the target.
    let shoot = |walled: bool| {
        let mut state = lane(Role::Agent);
        let seen = strafe(&mut state, 12);
        let drawn = state.tick as f64 - 2.0;
        let point = chest(feet_at(&seen, drawn));
        let solids = if walled {
            vec![crate::movement::Solid::from_center_top(
                point[0] * 0.5,
                0.0,
                1.0,
                0.2,
                3.0,
            )]
        } else {
            Vec::new()
        };
        let arena = crate::movement::Arena { solids, half: 60.0 };
        let eye = [0.0, crate::combat::stance_eye(None, false), -8.0];
        let (yaw, pitch) = crate::combat::aim_at(eye, point).unwrap();
        state.set_action(
            SHOOTER,
            Action {
                fire: true,
                yaw: Some(yaw),
                pitch: Some(pitch),
                view_tick: Some(drawn),
                ..Default::default()
            },
        );
        let shooter = state.players.iter().position(|p| p.id == SHOOTER).unwrap();
        state.players[shooter].yaw = yaw;
        state.players[shooter].pitch = pitch;
        let struck = state.hitscan_target_next_tick(shooter, &arena);
        (struck, state.players.iter().position(|p| p.id == TARGET))
    };
    let (struck, _) = shoot(true);
    assert_eq!(struck, None, "the wall stops it");
    let (struck, target) = shoot(false);
    assert_eq!(struck, target);
}

#[test]
fn status_publishes_the_rewind_counters_and_names_nobody() {
    // A clamped rewind, a refused view and a broken history, stamped the way
    // the tick loop stamps the served status.
    let mut session = crate::session::GameSession::new();
    session.state = lane(Role::Agent);
    let seen = strafe(&mut session.state, 16);
    let drawn = session.state.tick as f64 - 10.0;
    fire_at(
        &mut session.state,
        chest(feet_at(&seen, drawn)),
        Some(drawn),
    );
    // Release the trigger and let the Rail cycle before each later shot.
    let rest = |state: &mut GameState| {
        state.set_action(SHOOTER, Action::default());
        for _ in 0..60 {
            state.tick(0.0);
        }
    };
    rest(&mut session.state);
    let seen = strafe(&mut session.state, 8);
    session
        .state
        .players
        .iter_mut()
        .find(|p| p.id == TARGET)
        .unwrap()
        .reset_movement_baseline();
    let drawn = session.state.tick as f64 - 2.0;
    fire_at(
        &mut session.state,
        chest(feet_at(&seen, drawn)),
        Some(drawn),
    );
    rest(&mut session.state);
    let future = session.state.tick as f64 + 2.0;
    fire_at(&mut session.state, [0.0, 1.0, 8.0], Some(future));
    let expected = RewindStats {
        accepted: 2,
        refused: 1,
        rewinds: 2,
        clamped: 1,
        discontinuities: 1,
    };
    assert_eq!(session.state.rewind_stats, expected);

    let totals = std::sync::Arc::new(crate::metrics::TrafficCounters::default());
    let mut tracker = crate::metrics::StatusTracker::new(totals, crate::run::TICK);
    let now = std::time::Instant::now();
    tracker.refresh(now, &[]);
    let mut live = session.state.live_status(0);
    tracker.apply(&mut live, now);
    session.stamp_ops(&mut live);
    let served = crate::metrics::served_status(&live, true, crate::metrics::process_uptime());
    let body = serde_json::to_string(&served).unwrap();
    let json: serde_json::Value = serde_json::from_str(&body).unwrap();
    assert_eq!(
        json["ops"]["rewind"],
        serde_json::json!({
            "accepted": 2,
            "refused": 1,
            "rewinds": 2,
            "clamped": 1,
            "discontinuities": 1
        })
    );
    // Counts only: neither fighter's id nor callsign reaches the body.
    for forbidden in [
        SHOOTER.to_string(),
        TARGET.to_string(),
        "shooter".into(),
        "target".into(),
    ] {
        assert!(!body.contains(&forbidden), "{forbidden}: {body}");
    }
    // An older body without the block reads as zeros.
    let mut old = json.clone();
    old["ops"].as_object_mut().unwrap().remove("rewind");
    let parsed: crate::protocol::LiveStatus = serde_json::from_value(old).unwrap();
    assert_eq!(parsed.ops.unwrap().rewind, RewindStats::default());
    // Before the tracker's first refresh there is no block to stamp.
    let mut bare = session.state.live_status(0);
    session.stamp_ops(&mut bare);
    assert!(bare.ops.is_none());
}
