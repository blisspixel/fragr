//! Isolated ordinary-movement calibration, never earned campaign evidence.
use super::*;
use crate::campaign::{constrain, PROFILES};
use fragr_server::protocol::Role;
use fragr_server::session::GameSession;
use std::f32::consts::{FRAC_PI_2, PI};
use uuid::Uuid;

fn scene() -> (PlayerState, Snapshot, Arena, PaverStripState) {
    let mut session = GameSession::new();
    let id = Uuid::from_u128(487);
    session
        .state
        .add_player(id, "Guard fixture".into(), Role::Human);
    let snapshot = session.state.snapshot();
    let mut me = snapshot.players[0].clone();
    me.x = 5.0;
    me.y = PLAYER_FLOOR_Y;
    me.z = 0.0;
    me.yaw = 0.0;
    me.pitch = 0.0;
    let strip = PaverStripState {
        owner_id: Uuid::from_u128(8),
        origin: [0.0, 0.0, 0.0],
        yaw: 0.0,
        length: 10.0,
        half_width: 1.6,
        working: true,
        phase_started: 0,
        phase_ends: 12,
    };
    (
        me,
        snapshot,
        Arena {
            half: 64.0,
            solids: Vec::new(),
        },
        strip,
    )
}

fn keys(yaw: f32, me: &PlayerState, snapshot: &Snapshot, arena: &Arena) -> Action {
    constrain(
        Action {
            forward: true,
            yaw: Some(yaw),
            ..Default::default()
        },
        me,
        snapshot,
        PROFILES[0],
        42,
        arena,
    )
}

#[test]
fn recognized_escape_survives_generic_reverse_stop_and_scan_actions() {
    let (me, mut observed, arena, strip) = scene();
    observed.paver_strips = vec![strip];
    let shared = keys(FRAC_PI_2, &me, &observed, &arena);
    for generic in [
        keys(-FRAC_PI_2, &me, &observed, &arena),
        Action::default(),
        Action {
            yaw: Some(0.3),
            ..Default::default()
        },
    ] {
        let old = project(&me, &generic, &arena);
        assert!(old[2] <= 0.0);
        let repaired = protect(shared.clone(), generic, &me, &observed, &arena);
        assert_eq!(
            serde_json::to_value(&repaired).unwrap(),
            serde_json::to_value(&shared).unwrap()
        );
        assert!(project(&me, &repaired, &arena)[2] > 0.0);
    }
}

#[test]
fn constrained_escape_then_forward_pursuit_cannot_oscillate_back_into_live_strip() {
    let (mut me, mut observed, arena, strip) = scene();
    observed.paver_strips = vec![strip];
    me.z = 1.5;
    let escape = keys(FRAC_PI_2, &me, &observed, &arena);
    let outside = project(&me, &escape, &arena);
    assert!(!crosses(&strip, outside, outside));
    me.x = outside[0];
    me.z = outside[2];
    me.yaw = escape.yaw.unwrap();
    for _ in 0..12 {
        let pursue = keys(-FRAC_PI_2, &me, &observed, &arena);
        let old = project(&me, &pursue, &arena);
        assert!(
            crosses(&strip, old, old),
            "unguarded pursuit reproduces re-entry"
        );
        let mut retained = pursue.clone();
        retained.fire = true;
        retained.reload = true;
        let repaired = protect(pursue, retained, &me, &observed, &arena);
        let next = project(&me, &repaired, &arena);
        assert!(
            !crosses(&strip, next, next),
            "guard must not re-enter a live strip"
        );
        assert!(repaired.fire && repaired.reload);
        me.x = next[0];
        me.z = next[2];
        me.yaw = repaired.yaw.unwrap();
    }
}

#[test]
fn current_second_owner_still_blocks_ingress_after_first_retires() {
    let (mut me, mut observed, arena, first) = scene();
    me.z = 1.7;
    let second = PaverStripState {
        owner_id: Uuid::from_u128(9),
        origin: [0.0, 0.0, 3.4],
        ..first
    };
    for strips in [vec![first, second], vec![second]] {
        observed.paver_strips = strips;
        let proposed = keys(FRAC_PI_2, &me, &observed, &arena);
        let guarded = protect(proposed.clone(), proposed, &me, &observed, &arena);
        assert_eq!(project(&me, &guarded, &arena), feet(&me));
    }
    observed.paver_strips.clear();
    let proposed = keys(FRAC_PI_2, &me, &observed, &arena);
    assert_eq!(
        serde_json::to_value(protect(
            proposed.clone(),
            proposed.clone(),
            &me,
            &observed,
            &arena
        ))
        .unwrap(),
        serde_json::to_value(proposed).unwrap()
    );
}

#[test]
fn hidden_unrecognized_expired_and_other_floor_strips_never_change_actions() {
    let (mut me, mut observed, arena, strip) = scene();
    for strips in [
        Vec::new(),
        vec![PaverStripState {
            phase_ends: 0,
            ..strip
        }],
        vec![PaverStripState {
            origin: [0.0, 3.0, 0.0],
            ..strip
        }],
    ] {
        observed.tick = 1;
        observed.paver_strips = strips;
        let generic = keys(-FRAC_PI_2, &me, &observed, &arena);
        let shared = keys(FRAC_PI_2, &me, &observed, &arena);
        assert_eq!(
            serde_json::to_value(protect(shared, generic.clone(), &me, &observed, &arena)).unwrap(),
            serde_json::to_value(generic).unwrap()
        );
    }
    // No inference of airborne velocity from privileged simulation facts.
    observed.paver_strips = vec![strip];
    me.y = PLAYER_FLOOR_Y + 2.0;
    let generic = keys(PI, &me, &observed, &arena);
    assert_eq!(
        serde_json::to_value(protect(
            Action::default(),
            generic.clone(),
            &me,
            &observed,
            &arena
        ))
        .unwrap(),
        serde_json::to_value(generic).unwrap()
    );
}

#[test]
fn crossing_checks_the_whole_step_and_blocked_escape_does_not_invent_a_route() {
    let (mut me, mut observed, mut arena, strip) = scene();
    assert!(crosses(&strip, [-0.1, 0.0, 1.5], [0.1, 0.0, 1.7]));
    assert!(!crosses(&strip, [-0.1, 0.0, 1.7], [0.1, 0.0, 1.9]));
    observed.paver_strips = vec![strip];
    me.z = 0.0;
    arena
        .solids
        .push(fragr_server::movement::Solid::from_center_top(
            5.0, 0.6, 4.0, 0.2, 4.5,
        ));
    let shared = keys(FRAC_PI_2, &me, &observed, &arena);
    let result = protect(
        shared.clone(),
        keys(-FRAC_PI_2, &me, &observed, &arena),
        &me,
        &observed,
        &arena,
    );
    assert_eq!(
        serde_json::to_value(&result).unwrap(),
        serde_json::to_value(shared).unwrap()
    );
    assert!(
        (project(&me, &result, &arena)[2] - me.z).abs() < 0.001,
        "blocked escape is still blocked"
    );
}

#[test]
fn retained_market_coordinates_reproduce_and_refuse_the_lethal_return_step() {
    // Baseline 6b8061b7, seed42 reference/Severe, ticks1558/1559. This is an
    // isolated movement replay of recorded public facts, not a campaign clear.
    let map = fragr_server::maps::AuthoredSource::Mission(
        fragr_server::protocol::MissionId::PlannedWorks,
    )
    .load()
    .unwrap();
    let session = GameSession::with_authored_map(map);
    let arena = session.state.map.arena();
    let (mut me, mut observed, _, _) = scene();
    me.x = 12.205_077;
    me.z = 35.681_694;
    me.yaw = 5.251_895_4;
    me.pitch = -0.119_406_745;
    observed.tick = 1558;
    observed.paver_strips = vec![PaverStripState {
        owner_id: Uuid::from_u128(8),
        origin: [1.831_232_4, 0.0, 32.016_47],
        yaw: 0.205_304_01,
        length: 14.5,
        half_width: 1.6,
        working: true,
        phase_started: 1556,
        phase_ends: 1568,
    }];
    let toward = Some(fragr_server::protocol::LookAt {
        x: Some(15.073_867),
        y: Some(0.9),
        z: Some(30.890_463),
        player_id: None,
    });
    let escape = constrain(
        Action {
            forward: true,
            yaw: Some(1.776_100_3),
            look_at: toward.clone(),
            ..Default::default()
        },
        &me,
        &observed,
        PROFILES[0],
        42,
        arena,
    );
    let outside = project(&me, &escape, arena);
    assert!(!crosses(&observed.paver_strips[0], outside, outside));
    assert!((outside[0] - 12.076_649).abs() < 1e-5);
    assert!((outside[2] - 35.896_183).abs() < 1e-5);
    me.x = outside[0];
    me.z = outside[2];
    me.yaw = escape.yaw.unwrap();
    observed.tick = 1559;
    let pursue = constrain(
        Action {
            forward: true,
            look_at: toward,
            ..Default::default()
        },
        &me,
        &observed,
        PROFILES[0],
        42,
        arena,
    );
    let old_return = project(&me, &pursue, arena);
    assert!(crosses(&observed.paver_strips[0], old_return, old_return));
    assert!((old_return[0] - 12.205_077).abs() < 1e-5);
    assert!((old_return[2] - 35.681_694).abs() < 1e-5);
    let guarded = protect(pursue.clone(), pursue.clone(), &me, &observed, arena);
    assert_eq!(project(&me, &guarded, arena), outside);
    observed.tick = 1569;
    assert_eq!(
        serde_json::to_value(protect(
            pursue.clone(),
            pursue.clone(),
            &me,
            &observed,
            arena
        ))
        .unwrap(),
        serde_json::to_value(pursue).unwrap()
    );
}
