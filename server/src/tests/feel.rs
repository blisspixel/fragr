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

#[test]
fn arena_weapon_raise_blocks_both_guns_and_resets_bloom_only_when_ready() {
    for (weapon, ticks) in [
        (WeaponType::Flechette, 5),
        (WeaponType::Scatter, 4),
        (WeaponType::Rail, 7),
    ] {
        let (mut state, id) = arena_with(Role::Agent);
        let p = state.players.iter_mut().find(|p| p.id == id).unwrap();
        p.inventory.grant_weapon(weapon);
        p.bloom = 0.8;
        p.since_shot = 0;
        state.set_action(
            id,
            Action {
                weapon_swap: Some(weapon),
                fire: true,
                ..Action::default()
            },
        );
        state.tick(DT_LIVE);
        let ready = state.tick + ticks;
        assert_eq!(body(&state, id).weapon_ready_at, Some(ready));
        assert_eq!(body(&state, id).weapon, weapon);
        while state.tick < ready {
            assert!(
                state.shot_results.iter().all(|shot| shot.shooter_id != id),
                "neither gun fires during its raise"
            );
            assert_eq!(
                body(&state, id).bloom,
                0.8,
                "the selection has not bought an accuracy reset"
            );
            state.tick(DT_LIVE);
        }
        let shot = state
            .shot_results
            .iter()
            .find(|shot| shot.shooter_id == id)
            .expect("held trigger fires at the deadline");
        assert_eq!(shot.trace.as_ref().unwrap().weapon, weapon);
        assert_eq!(body(&state, id).weapon_ready_at, None);
        assert_eq!(body(&state, id).bloom, weapon.bloom_per_shot());
    }
}

#[test]
fn raise_deadline_survives_input_reset_and_only_a_different_owned_gun_restarts_it() {
    let (mut state, id) = arena_with(Role::Agent);
    state.players[0].inventory.grant_weapon(WeaponType::Rail);
    state.players[0].inventory.grant_weapon(WeaponType::Scatter);
    state.set_action(
        id,
        Action {
            weapon_swap: Some(WeaponType::Rail),
            ..Action::default()
        },
    );
    state.tick(DT_LIVE);
    let ready = body(&state, id).weapon_ready_at;
    state.players[0].clear_input();
    assert_eq!(
        body(&state, id).weapon_ready_at,
        ready,
        "resume cannot skip a raise"
    );
    for requested in [WeaponType::Rail, WeaponType::Sniper] {
        state.set_action(
            id,
            Action {
                weapon_swap: Some(requested),
                ..Action::default()
            },
        );
        state.tick(DT_LIVE);
        assert_eq!(body(&state, id).weapon, WeaponType::Rail);
        assert_eq!(body(&state, id).weapon_ready_at, ready);
    }
    state.set_action(
        id,
        Action {
            weapon_swap: Some(WeaponType::Scatter),
            ..Action::default()
        },
    );
    state.tick(DT_LIVE);
    assert_eq!(body(&state, id).weapon_ready_at, Some(state.tick + 4));
    state.players[0].hp = 0;
    state.tick(DT_LIVE);
    assert_eq!(body(&state, id).weapon_ready_at, None);
    state.issue_kit(id);
    assert_eq!(body(&state, id).bloom, 0.0);
}

#[test]
fn a_rocket_cannot_bypass_the_weapon_raise() {
    let (mut state, id) = arena_with(Role::Agent);
    state.players[0].inventory.grant_weapon(WeaponType::Rocket);
    state.set_action(
        id,
        Action {
            weapon_swap: Some(WeaponType::Rocket),
            fire: true,
            ..Action::default()
        },
    );
    state.tick(DT_LIVE);
    let ready = body(&state, id).weapon_ready_at.unwrap();
    while state.tick < ready {
        assert!(state.snapshot().rockets.is_empty());
        state.tick(DT_LIVE);
    }
    assert!(!state.snapshot().rockets.is_empty());
}

#[test]
fn a_found_gun_uses_its_own_raise_instead_of_an_unrelated_old_deadline() {
    let (mut state, id) = arena_with(Role::Agent);
    state.players[0].inventory.grant_weapon(WeaponType::Scatter);
    state.players[0].select_weapon(WeaponType::Scatter, true, state.tick);
    super::stand_on_pad(&mut state, id, "larak_rail");
    state.set_action(
        id,
        Action {
            fire: true,
            ..Action::default()
        },
    );
    state.tick(DT_LIVE);
    let aim = state.aim_state(id).unwrap();
    assert_eq!(aim.weapon, WeaponType::Rail);
    assert_eq!(aim.raise_ready_at, Some(state.tick + 7));
    aim.validate_for(Some(id), None).unwrap();
    assert!(state.shot_results.iter().all(|shot| shot.shooter_id != id));
}

#[test]
fn moving_precision_and_scatter_shots_match_the_published_cone() {
    for (weapon, cone) in [
        (WeaponType::Rail, 0.012_f32),
        (WeaponType::Sniper, 0.004),
        (WeaponType::Scatter, 0.190),
    ] {
        let (mut state, id) = arena_with(Role::Agent);
        state.players[0].inventory.grant_weapon(weapon);
        state.players[0].weapon = weapon;
        state.set_action(id, forward(None));
        for _ in 0..3 {
            state.tick(DT_LIVE);
        }
        let aim = state.aim_state(id).unwrap();
        assert_eq!(aim.cone_microradians, (cone * 1_000_000.0).round() as u32);
        const SEED: u64 = 0xA11;
        state.restart_stream(SEED);
        state.set_action(
            id,
            Action {
                forward: true,
                fire: true,
                yaw: Some(0.0),
                pitch: Some(0.0),
                ..Action::default()
            },
        );
        state.tick(DT_LIVE);
        let expected = dispersed_angle(cone, preview_samples(SEED));
        assert!(expected > 0.001);
        assert!(
            (shot_angle(&state, id) - expected).abs() < 0.0001,
            "{weapon:?} actual resolved ray uses the full moving cone"
        );
        assert_eq!(
            state.aim_state(id).unwrap().cone_microradians,
            aim.cone_microradians
        );
    }
}

#[test]
fn aim_reports_bloom_recovery_and_campaign_table_without_a_raise() {
    let (mut state, id) = arena_with(Role::Agent);
    state.players[0]
        .inventory
        .grant_weapon(WeaponType::Flechette);
    state.players[0].weapon = WeaponType::Flechette;
    assert_eq!(state.aim_state(id).unwrap().cone_microradians, 0);
    state.players[0].bloom = 1.0;
    state.players[0].since_shot = 0;
    assert_eq!(state.aim_state(id).unwrap().cone_microradians, 45_000);
    for _ in 0..15 {
        state.tick(DT_LIVE);
    }
    assert_eq!(state.aim_state(id).unwrap().cone_microradians, 0);
    assert!(state.aim_state(Uuid::nil()).is_none());

    let map = crate::maps::AuthoredSource::Mission(crate::protocol::MissionId::RecallNotice)
        .load()
        .unwrap();
    let mut session = crate::session::GameSession::with_authored_map(map);
    session
        .state
        .add_player(id, "Campaign runner".into(), Role::Agent);
    let mission = session.state.mission_state().unwrap();
    assert!(session.state.acknowledge_mission(
        id,
        crate::protocol::MissionReady {
            id: mission.id,
            attempt: mission.attempt
        }
    ));
    session.state.players[0]
        .inventory
        .grant_weapon(WeaponType::Flechette);
    session.state.set_action(
        id,
        Action {
            weapon_swap: Some(WeaponType::Flechette),
            ..Action::default()
        },
    );
    session.state.tick(DT_LIVE);
    let aim = session.state.aim_state(id).unwrap();
    assert_eq!(aim.weapon, WeaponType::Flechette);
    assert_eq!(aim.cone_microradians, 45_000);
    assert_eq!(aim.raise_ready_at, None);
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
fn a_run_opens_the_cone_and_a_counter_strafe_closes_it() {
    let (mut state, id) = arena_with(Role::Agent);
    {
        let player = state.players.iter_mut().find(|p| p.id == id).unwrap();
        player.inventory.grant_weapon(WeaponType::Flechette);
        player.weapon = WeaponType::Flechette;
    }
    state.set_action(id, forward(None));
    for _ in 0..3 {
        state.tick(DT_LIVE);
    }
    let running = body(&state, id).vx.hypot(body(&state, id).vz);
    assert!(
        (running - TOP_SPEED).abs() < 1e-3,
        "the shot is taken at a full run: {running}"
    );
    // The first two samples of this stream sit off the axis. The shot must
    // match that dispersed ray, so a later change in who draws a number fails
    // the test instead of a near-zero sample pretending the cone is open.
    const SEED: u64 = 0xA11;
    state.restart_stream(SEED);
    state.set_action(
        id,
        Action {
            forward: true,
            fire: true,
            yaw: Some(0.0),
            pitch: Some(0.0),
            ..Action::default()
        },
    );
    state.tick(DT_LIVE);
    let running_shot = shot_angle(&state, id);
    let cone = WeaponType::Flechette.spread_radians();
    let expected = dispersed_angle(cone, preview_samples(SEED));
    assert!(
        expected > 1e-2,
        "the fixture seed leaves the ray: {expected}"
    );
    assert!(
        (running_shot - expected).abs() < 1e-4,
        "a full run uses the whole cone: shot {running_shot} expected {expected} cone {cone}"
    );

    let (mut state, id) = arena_with(Role::Agent);
    {
        let player = state.players.iter_mut().find(|p| p.id == id).unwrap();
        player.inventory.grant_weapon(WeaponType::Flechette);
        player.weapon = WeaponType::Flechette;
    }
    state.set_action(id, forward(None));
    for _ in 0..3 {
        state.tick(DT_LIVE);
    }
    state.set_action(
        id,
        Action {
            back: true,
            fire: true,
            yaw: Some(0.0),
            pitch: Some(0.0),
            ..Action::default()
        },
    );
    state.tick(DT_LIVE);
    let stopped = body(&state, id).vx.hypot(body(&state, id).vz);
    assert!(
        stopped <= TOP_SPEED * crate::movement::ACCURATE_SPEED_SCALE,
        "the opposite key is inside the accurate band: {stopped}"
    );
    let accurate = shot_angle(&state, id);
    assert!(
        accurate < 1e-3,
        "the counter-strafe shot is back on the aim ray: {accurate}"
    );
}

fn preview_samples(seed: u64) -> [f32; 2] {
    let mut probe = GameState::new();
    probe.restart_stream(seed);
    [probe.next_f32(), probe.next_f32()]
}

fn dispersed_angle(spread: f32, samples: [f32; 2]) -> f32 {
    let ray = crate::combat::Ray::dispersed([0.0; 3], 0.0, 0.0, spread, samples);
    ray.direction[0].clamp(-1.0, 1.0).acos()
}

fn shot_angle(state: &GameState, id: Uuid) -> f32 {
    let result = state
        .shot_results
        .iter()
        .find(|result| result.shooter_id == id)
        .expect("the tick fired");
    let trace = result.trace.as_ref().unwrap();
    let d: Vec<f32> = (0..3).map(|i| trace.end[i] - trace.origin[i]).collect();
    let length = (d[0] * d[0] + d[1] * d[1] + d[2] * d[2]).sqrt();
    let aim = [1.0_f32, 0.0, 0.0];
    let cos = (d[0] * aim[0] + d[1] * aim[1] + d[2] * aim[2]) / length;
    cos.clamp(-1.0, 1.0).acos()
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
fn a_jump_opens_the_cone_from_a_stand() {
    let (mut state, id) = arena_with(Role::Agent);
    {
        let player = state.players.iter_mut().find(|p| p.id == id).unwrap();
        player.inventory.grant_weapon(WeaponType::Flechette);
        player.weapon = WeaponType::Flechette;
    }
    const SEED: u64 = 0xA11;
    state.restart_stream(SEED);
    state.set_action(
        id,
        Action {
            jump: true,
            fire: true,
            yaw: Some(0.0),
            pitch: Some(0.0),
            ..Action::default()
        },
    );
    state.tick(DT_LIVE);
    let jumper = body(&state, id);
    assert!(jumper.vy > 0.0, "the shot leaves the floor");
    assert!(
        jumper.vx.hypot(jumper.vz) <= TOP_SPEED * crate::movement::ACCURATE_SPEED_SCALE,
        "horizontal speed stays in the accurate band, so only the jump opens the cone"
    );
    let cone = WeaponType::Flechette.spread_radians();
    let expected = dispersed_angle(cone, preview_samples(SEED));
    let angle = shot_angle(&state, id);
    assert!(
        (angle - expected).abs() < 1e-4,
        "a jump uses the whole cone: shot {angle} expected {expected} cone {cone}"
    );
}

#[test]
fn a_still_swimmer_keeps_the_aim_ray() {
    let mut state = GameState::with_map(crate::sim::MapKind::HoldfastAtoll, false);
    state.config.boss_spawn_ticks = None;
    state.config.compliance_ping_ticks = None;
    state.start_round();
    let id = Uuid::from_u128(0x5e1a);
    state.add_player(id, "Swimmer".into(), Role::Agent);
    let surface = 2.2 - crate::movement::water::SWIM_DRAFT;
    {
        let player = state.players.iter_mut().find(|p| p.id == id).unwrap();
        player.inventory.grant_weapon(WeaponType::Flechette);
        player.weapon = WeaponType::Flechette;
        player.x = 0.0;
        player.z = 80.0;
        player.y = PLAYER_FLOOR_Y + surface;
        player.vy = 0.0;
        player.yaw = 0.0;
        player.pitch = 0.0;
    }
    state.set_action(
        id,
        Action {
            yaw: Some(0.0),
            pitch: Some(0.0),
            ..Action::default()
        },
    );
    state.tick(DT_LIVE);
    let swimmer = body(&state, id);
    let feet = swimmer.y - PLAYER_FLOOR_Y;
    let dry = state
        .current_arena()
        .support_height(swimmer.x, swimmer.z, feet);
    assert!(
        feet > dry + 0.5,
        "the buoyant surface is not the dry floor: feet {feet} floor {dry}"
    );
    assert!(
        swimmer.vx.hypot(swimmer.vz) < 0.05,
        "the shot is a tread, not a swim"
    );
    const SEED: u64 = 0xA11;
    state.restart_stream(SEED);
    state.set_action(
        id,
        Action {
            fire: true,
            yaw: Some(0.0),
            pitch: Some(0.0),
            ..Action::default()
        },
    );
    state.tick(DT_LIVE);
    let angle = shot_angle(&state, id);
    let opened = dispersed_angle(
        WeaponType::Flechette.spread_radians(),
        preview_samples(SEED),
    );
    assert!(
        opened > 1e-2,
        "the fixture seed would show an open cone: {opened}"
    );
    assert!(
        angle < 1e-3,
        "treading water is ground, so the first shot stays on the aim ray: {angle}"
    );
    assert_eq!(
        state.aim_state(id).unwrap().cone_microradians,
        9_000,
        "the private readout contains only post-shot bloom, no swimming penalty"
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
