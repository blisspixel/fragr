//! Held crouch: a shorter shot volume, a slower step, and a ceiling that keeps it.
use crate::combat::{aim_at, HEAD_DAMAGE_SCALE, TORSO_HEIGHT};
use crate::movement::{
    ducked_stance, live_step_with_height, Arena, MoveInput, MoveState, Solid, BODY_HEIGHT, DT_LIVE,
    DUCK_HEIGHT, DUCK_SPEED_SCALE, EYE_HEIGHT, TOP_SPEED,
};
use crate::protocol::{Action, EquipmentPolicy, Role, ServerMessage, WeaponType};
use crate::sim::{GameState, PLAYER_FLOOR_Y};
use uuid::Uuid;

fn place(state: &mut GameState, id: Uuid, x: f32) {
    let player = state.players.iter_mut().find(|p| p.id == id).unwrap();
    player.x = x;
    player.z = 0.0;
    player.y = PLAYER_FLOOR_Y;
    player.yaw = 0.0;
    player.pitch = 0.0;
    player.vy = 0.0;
}

#[test]
fn duck_shortens_the_body_and_a_level_ray_misses() {
    let shoot = |duck: bool, pitch: Option<f32>| -> i32 {
        let mut state = GameState::new();
        state.start_round();
        let shooter = Uuid::new_v4();
        let target = Uuid::new_v4();
        state.add_player(shooter, "Shooter".into(), Role::Agent);
        state.add_player(target, "Victim".into(), Role::Agent);
        place(&mut state, shooter, 0.0);
        place(&mut state, target, 5.0);
        let pitched = pitch.unwrap_or(0.0);
        {
            let shooter_player = state.players.iter_mut().find(|p| p.id == shooter).unwrap();
            // The arcade kit does not carry the Sniper. One pellet keeps the
            // ray inside the short chest and over the short crown.
            shooter_player.inventory = crate::inventory::Inventory::new(EquipmentPolicy::Discovery);
            shooter_player.inventory.grant_weapon(WeaponType::Sniper);
            shooter_player.weapon = WeaponType::Sniper;
            shooter_player.pitch = pitched;
            shooter_player.fire_cooldown = 0;
        }
        let before = state.players.iter().find(|p| p.id == target).unwrap().hp;
        state.set_action(
            shooter,
            Action {
                fire: true,
                ..Action::default()
            },
        );
        state.set_action(
            target,
            Action {
                duck,
                ..Action::default()
            },
        );
        state.tick(0.05);
        before - state.players.iter().find(|p| p.id == target).unwrap().hp
    };

    let body = WeaponType::Sniper.damage();
    let drop = BODY_HEIGHT - DUCK_HEIGHT;
    let chest = aim_at([0.0, EYE_HEIGHT, 0.0], [5.0, TORSO_HEIGHT - drop, 0.0])
        .unwrap()
        .1;
    assert_eq!(
        shoot(true, Some(0.0)),
        0,
        "standing eye clears a ducked body"
    );
    assert_eq!(
        shoot(true, Some(chest)),
        body,
        "the ducked chest is a body shot"
    );
    assert_eq!(
        shoot(false, Some(0.0)),
        body * HEAD_DAMAGE_SCALE,
        "the same level ray still hits a standing face"
    );
}

#[test]
fn duck_slows_one_step_and_the_snapshot_omits_a_stand() {
    let step = |duck: bool| -> f32 {
        let mut state = GameState::new();
        state.start_round();
        let id = Uuid::new_v4();
        state.add_player(id, "Walker".into(), Role::Agent);
        place(&mut state, id, 0.0);
        state.set_action(
            id,
            Action {
                forward: true,
                duck,
                ..Action::default()
            },
        );
        state.tick(DT_LIVE);
        state.players.iter().find(|p| p.id == id).unwrap().x
    };

    let standing = step(false);
    let ducked = step(true);
    assert!((standing - TOP_SPEED * DT_LIVE).abs() < 0.02, "{standing}");
    assert!(
        (ducked - TOP_SPEED * DUCK_SPEED_SCALE * DT_LIVE).abs() < 0.02,
        "{ducked}"
    );

    let mut state = GameState::new();
    state.start_round();
    let id = Uuid::new_v4();
    state.add_player(id, "Walker".into(), Role::Agent);
    place(&mut state, id, 0.0);
    state.set_action(
        id,
        Action {
            duck: true,
            ..Action::default()
        },
    );
    state.tick(DT_LIVE);
    let snap = serde_json::to_value(state.snapshot()).unwrap();
    assert_eq!(snap["players"][0]["ducking"], true);
    state.set_action(id, Action::default());
    state.tick(DT_LIVE);
    let stood = serde_json::to_value(state.snapshot()).unwrap();
    assert!(stood["players"][0].get("ducking").is_none());
    assert!(!state.players[0].ducking);

    state.players[0].is_boss = true;
    state.set_action(
        id,
        Action {
            duck: true,
            ..Action::default()
        },
    );
    state.tick(DT_LIVE);
    assert!(!state.players[0].ducking, "a boss stays standing");
}

#[test]
fn an_omitted_duck_matches_standing_and_stays_off_the_wire() {
    let json = serde_json::to_string(&Action::default()).unwrap();
    assert!(!json.contains("duck"));
    let held = Action {
        duck: true,
        ..Action::default()
    };
    assert!(serde_json::to_string(&held)
        .unwrap()
        .contains("\"duck\":true"));
    let decoded: Action = serde_json::from_str(r#"{"forward":true}"#).unwrap();
    assert!(!decoded.duck);

    let welcome: ServerMessage =
        serde_json::from_str(r#"{"type":"welcome","role":"spectator","player_id":null}"#).unwrap();
    match welcome {
        ServerMessage::Welcome { duck, .. } => assert!(!duck),
        _ => panic!("welcome"),
    }

    let mut plain = GameState::new();
    let mut explicit = GameState::new();
    plain.start_round();
    explicit.start_round();
    let id = Uuid::from_u128(7);
    plain.add_player(id, "Walker".into(), Role::Agent);
    explicit.add_player(id, "Walker".into(), Role::Agent);
    place(&mut plain, id, 0.0);
    place(&mut explicit, id, 0.0);
    plain.set_action(
        id,
        Action {
            forward: true,
            ..Action::default()
        },
    );
    explicit.set_action(
        id,
        Action {
            forward: true,
            duck: false,
            ..Action::default()
        },
    );
    plain.tick(DT_LIVE);
    explicit.tick(DT_LIVE);
    let left = plain.players.iter().find(|p| p.id == id).unwrap().x;
    let right = explicit.players.iter().find(|p| p.id == id).unwrap().x;
    assert!((left - right).abs() < 0.0001);
}

#[test]
fn a_low_slab_blocks_the_standing_body_and_keeps_a_duck() {
    let slab = Solid::from_center_volume(2.0, 0.0, 1.0, 2.0, 1.5, 3.0);
    let arena = Arena {
        half: 32.0,
        solids: vec![slab],
    };
    assert!(!arena.fits_height(2.0, 0.0, 0.0, BODY_HEIGHT));
    assert!(arena.fits_height(2.0, 0.0, 0.0, DUCK_HEIGHT));
    assert!(ducked_stance(true, false, true));
    assert!(ducked_stance(false, true, false));
    assert!(!ducked_stance(false, true, true));
    assert!(!ducked_stance(false, false, false));

    let input = MoveInput {
        forward: true,
        back: false,
        left: false,
        right: false,
        jump: false,
        yaw: 0.0,
        speed_scale: 1.0,
    };
    let mut tall = MoveState {
        x: 0.0,
        z: 0.0,
        y: 0.0,
        vx: 0.0,
        vz: 0.0,
        vy: 0.0,
        yaw: 0.0,
    };
    let mut short = tall;
    for _ in 0..50 {
        tall = live_step_with_height(tall, &input, TOP_SPEED, DT_LIVE, &arena, BODY_HEIGHT);
        short = live_step_with_height(
            short,
            &input,
            TOP_SPEED * DUCK_SPEED_SCALE,
            DT_LIVE,
            &arena,
            DUCK_HEIGHT,
        );
    }
    assert!(tall.x < 1.0, "standing stops at the beam, x={}", tall.x);
    assert!(short.x > 3.5, "a duck walks under the beam, x={}", short.x);
}
