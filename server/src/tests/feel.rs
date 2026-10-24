//! The feel pass through the real simulation: momentum across ticks, the
//! ground dodge and its cooldown, first-shot accuracy with bloom, and the
//! campaign keeping its tuned movement and cones.
use crate::movement::{DODGE_COOLDOWN_TICKS, DODGE_SPEED, DT_LIVE, GROUND_ACCEL, TOP_SPEED};
use crate::protocol::{Action, Role, ServerMessage, WeaponType};
use crate::sim::{GameState, PLAYER_FLOOR_Y};
use uuid::Uuid;

fn arena_with(role: Role) -> (GameState, Uuid) {
    let mut state = GameState::new();
    state.config.boss_spawn_ticks = None;
    state.config.compliance_ping_ticks = None;
    state.start_round();
    let id = Uuid::new_v4();
    state.add_player(id, "Runner".into(), role);
    let player = state.players.iter_mut().find(|p| p.id == id).unwrap();
    player.x = 0.0;
    player.z = 0.0;
    player.y = PLAYER_FLOOR_Y;
    player.vy = 0.0;
    player.yaw = 0.0;
    player.pitch = 0.0;
    (state, id)
}

fn body(state: &GameState, id: Uuid) -> &crate::sim::Player {
    state.players.iter().find(|p| p.id == id).unwrap()
}

fn forward(seq: Option<u32>) -> Action {
    Action {
        forward: true,
        yaw: Some(0.0),
        seq,
        ..Action::default()
    }
}

#[test]
fn a_run_accelerates_carries_momentum_and_slides_to_rest() {
    let (mut state, id) = arena_with(Role::Agent);
    state.set_action(id, forward(None));
    state.tick(DT_LIVE);
    let first = body(&state, id).vx;
    assert!(
        (first - GROUND_ACCEL * DT_LIVE * TOP_SPEED).abs() < 1e-4,
        "{first}"
    );
    state.tick(DT_LIVE);
    state.tick(DT_LIVE);
    assert!((body(&state, id).vx - TOP_SPEED).abs() < 1e-4);
    state.set_action(id, Action::default());
    let released = body(&state, id).x;
    let mut ticks = 0;
    while body(&state, id).vx > 0.0 && ticks < 10 {
        state.tick(DT_LIVE);
        ticks += 1;
    }
    let slide = body(&state, id).x - released;
    assert_eq!(ticks, 3, "a released run rests three ticks later");
    assert!(slide > 0.1 && slide < 0.2, "{slide}");
}

#[test]
fn momentum_resets_after_a_tick_that_did_not_move_the_body() {
    let (mut state, id) = arena_with(Role::Agent);
    state.set_action(id, forward(None));
    for _ in 0..3 {
        state.tick(DT_LIVE);
    }
    // A reset of input ownership (respawn, resume, continue) is a new body.
    state
        .players
        .iter_mut()
        .find(|p| p.id == id)
        .unwrap()
        .clear_input();
    state.set_action(
        id,
        Action {
            right: true,
            yaw: Some(0.0),
            ..Action::default()
        },
    );
    state.tick(DT_LIVE);
    assert!(body(&state, id).vx.abs() < 1e-6, "{}", body(&state, id).vx);
}

#[test]
fn a_dodge_press_throws_the_body_once_and_the_ack_carries_the_cooldown() {
    let (mut state, id) = arena_with(Role::Human);
    // Press and release inside one tick: the latch still dodges.
    state.set_action(
        id,
        Action {
            right: true,
            dodge: true,
            yaw: Some(0.0),
            seq: Some(1),
            ..Action::default()
        },
    );
    state.set_action(
        id,
        Action {
            right: true,
            yaw: Some(0.0),
            seq: Some(2),
            ..Action::default()
        },
    );
    state.tick(DT_LIVE);
    let thrown = body(&state, id);
    assert!((thrown.vz - DODGE_SPEED).abs() < 1e-4, "{}", thrown.vz);
    assert!(thrown.vy > 0.0 && thrown.y > PLAYER_FLOOR_Y);
    assert_eq!(thrown.dodge_cooldown, DODGE_COOLDOWN_TICKS);
    let ServerMessage::Ack {
        movement: Some(movement),
        ..
    } = &state.input_acks()[0].1
    else {
        panic!("a numbered human gets a movement Ack");
    };
    assert_eq!(movement.version, 2, "arena play is the fighter model");
    assert_eq!(movement.dodge_cooldown, DODGE_COOLDOWN_TICKS);
    // Land, then press again inside the cooldown: nothing.
    for _ in 0..8 {
        state.tick(DT_LIVE);
    }
    assert_eq!(body(&state, id).y, PLAYER_FLOOR_Y, "landed");
    state.set_action(
        id,
        Action {
            right: true,
            dodge: true,
            yaw: Some(0.0),
            seq: Some(3),
            ..Action::default()
        },
    );
    state.tick(DT_LIVE);
    assert!(
        body(&state, id).vz <= TOP_SPEED + 1e-4,
        "{}",
        body(&state, id).vz
    );
    // After the cooldown the next press dodges.
    for seq in 4..20 {
        state.set_action(
            id,
            Action {
                right: true,
                yaw: Some(0.0),
                seq: Some(seq),
                ..Action::default()
            },
        );
        state.tick(DT_LIVE);
    }
    state.set_action(
        id,
        Action {
            right: true,
            dodge: true,
            yaw: Some(0.0),
            seq: Some(20),
            ..Action::default()
        },
    );
    state.tick(DT_LIVE);
    assert!((body(&state, id).vz - DODGE_SPEED).abs() < 1e-4);
}

/// Fire `shots` times with the trigger held and return each shot's angle off
/// the aim ray, in radians.
fn held_trigger_angles(weapon: WeaponType, shots: usize) -> Vec<f32> {
    let (mut state, id) = arena_with(Role::Agent);
    {
        let player = state.players.iter_mut().find(|p| p.id == id).unwrap();
        player.inventory.grant_weapon(weapon);
        player.weapon = weapon;
        player.yaw = 0.3;
    }
    state.set_action(
        id,
        Action {
            fire: true,
            yaw: Some(0.3),
            pitch: Some(0.0),
            ..Action::default()
        },
    );
    let mut angles = Vec::new();
    for _ in 0..200 {
        state.tick(DT_LIVE);
        for result in &state.shot_results {
            if result.shooter_id != id {
                continue;
            }
            let trace = result.trace.as_ref().unwrap();
            let d: Vec<f32> = (0..3).map(|i| trace.end[i] - trace.origin[i]).collect();
            let length = (d[0] * d[0] + d[1] * d[1] + d[2] * d[2]).sqrt();
            let aim = [0.3f32.cos(), 0.0, 0.3f32.sin()];
            let cos = (d[0] * aim[0] + d[1] * aim[1] + d[2] * aim[2]) / length;
            angles.push(cos.clamp(-1.0, 1.0).acos());
        }
        if angles.len() >= shots {
            break;
        }
    }
    angles
}

#[test]
fn the_first_shot_flies_down_the_aim_ray_and_sustained_fire_blooms() {
    let angles = held_trigger_angles(WeaponType::Flechette, 8);
    assert!(angles.len() >= 8, "{angles:?}");
    assert!(angles[0] < 1e-3, "first shot exact: {angles:?}");
    let cone = WeaponType::Flechette.spread_radians();
    for (index, angle) in angles.iter().enumerate() {
        let share = (index as f32 * WeaponType::Flechette.bloom_per_shot()).min(1.0);
        assert!(
            *angle <= cone * share + 1e-3,
            "shot {index} inside {share} of the cone: {angles:?}"
        );
    }
    assert!(
        angles[5..].iter().any(|angle| *angle > 1e-3),
        "a held trigger grows a cone: {angles:?}"
    );
    let rail = held_trigger_angles(WeaponType::Rail, 3);
    assert!(rail.iter().all(|angle| *angle < 1e-3), "{rail:?}");
}

#[test]
fn a_rested_trigger_recovers_its_first_shot() {
    let (mut state, id) = arena_with(Role::Agent);
    {
        let player = state.players.iter_mut().find(|p| p.id == id).unwrap();
        player.weapon = WeaponType::Flechette;
        player.bloom = 1.0;
        player.since_shot = 0;
    }
    for _ in 0..(WeaponType::Flechette.cooldown_ticks() + 2) {
        state.tick(DT_LIVE);
    }
    assert!(
        body(&state, id).bloom > 0.99,
        "the cadence alone does not recover"
    );
    for _ in 0..8 {
        state.tick(DT_LIVE);
    }
    assert_eq!(
        body(&state, id).bloom,
        0.0,
        "a rest recovers the whole cone"
    );
}

#[test]
fn a_campaign_participant_keeps_the_immediate_step_and_has_no_dodge() {
    let map = crate::maps::AuthoredSource::Mission(crate::protocol::MissionId::RecallNotice)
        .load()
        .unwrap();
    let mut session = crate::session::GameSession::with_authored_map(map);
    let id = Uuid::from_u128(0xfee1);
    session
        .state
        .add_player(id, "Campaign runner".into(), Role::Agent);
    assert!(!session.state.arena_feel());
    assert!(!body(&session.state, id).fighter_model(session.state.arena_feel()));
    assert!(!body(&session.state, id).fighter_model(false));
    assert!(body(&session.state, id).fighter_model(true));
}
