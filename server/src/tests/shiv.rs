//! The pool-less Shiv: melee combat, authored secrets and shared agent choices.
use crate::inventory::control_action;
use crate::maps::AuthoredMap;
use crate::protocol::{Action, LookAt, Role, WeaponType};
use crate::sim::GameState;
use uuid::Uuid;

fn document(wall: bool, supplies: serde_json::Value) -> serde_json::Value {
    let solids = if wall {
        serde_json::json!([{"id":"wall","min":[1,0,-1],"max":[1.3,3,1],"surface":"enamel"}])
    } else {
        serde_json::json!([])
    };
    serde_json::json!({
        "version":1,"map_id":1004,"name":"Shiv fixture","half_extent":8,"ground":"concrete",
        "equipment":"discovery","solids":solids,"supplies":supplies,
        "spawns":[{"id":"entry","feet":[0,0,0],"yaw":0}],
        "landmarks":[{"id":"far","feet":[5,0,0]}]
    })
}

fn read(json: &serde_json::Value) -> std::io::Result<std::sync::Arc<AuthoredMap>> {
    AuthoredMap::read(serde_json::to_vec(json).unwrap().as_slice())
}

fn fixture(wall: bool, shiv: bool) -> GameState {
    let supplies = if shiv {
        serde_json::json!([{
            "id":"cache_shiv","feet":[5,0,0],"grant":{"kind":"weapon","weapon":"shiv"},
            "claim":"personal","secret":true
        }])
    } else {
        serde_json::json!([])
    };
    GameState::with_authored_map(read(&document(wall, supplies)).unwrap())
}

/// A fighter at the origin facing +X and a bare target `distance` ahead.
fn duel(wall: bool, weapon: WeaponType, distance: f32) -> GameState {
    let mut state = fixture(wall, false);
    let a = Uuid::new_v4();
    state.add_player(a, "Cutter".into(), Role::Human);
    state.add_player(Uuid::new_v4(), "Target".into(), Role::Agent);
    state.players[0].x = 0.4;
    state.players[0].z = 0.0;
    state.players[1].x = 0.4 + distance;
    state.players[1].z = 0.0;
    if weapon != WeaponType::Fists {
        assert!(state.players[0].inventory.grant_weapon(weapon));
    }
    state.players[0].weapon = weapon;
    state.set_action(
        a,
        Action {
            fire: true,
            yaw: Some(0.0),
            ..Default::default()
        },
    );
    state
}

#[test]
fn the_shiv_reaches_past_fists_but_not_through_cover() {
    for (wall, distance, weapon, damage) in [
        (false, 1.6, WeaponType::Shiv, 35),
        (false, 2.4, WeaponType::Shiv, 35),
        (false, 2.4, WeaponType::Fists, 0),
        (false, 3.0, WeaponType::Shiv, 0),
        (true, 1.8, WeaponType::Shiv, 0),
    ] {
        let mut state = duel(wall, weapon, distance);
        state.tick(0.05);
        assert_eq!(state.shot_results.len(), 1);
        let shot = &state.shot_results[0];
        assert_eq!(
            shot.hit,
            damage > 0,
            "{weapon:?} at {distance}, wall {wall}"
        );
        assert_eq!(state.players[1].hp, 100 - damage);
        let trace = shot.trace.as_ref().unwrap();
        assert_eq!(trace.weapon, weapon);
        assert!(trace.pellets.is_empty());
        let reach = ((trace.end[0] - trace.origin[0]).powi(2)
            + (trace.end[1] - trace.origin[1]).powi(2)
            + (trace.end[2] - trace.origin[2]).powi(2))
        .sqrt();
        assert!(reach <= weapon.range_units() + 1e-4);
    }
}

#[test]
fn three_quick_cuts_kill_a_bare_fighter_that_takes_five_punches() {
    let mut kills = Vec::new();
    for weapon in [WeaponType::Shiv, WeaponType::Fists] {
        let mut state = duel(false, weapon, 1.2);
        let mut attacks = 0;
        let mut killed_at = None;
        for tick in 0..60 {
            state.tick(0.05);
            attacks += state.shot_results.len();
            if state.players[1].hp <= 0 {
                killed_at = Some(tick);
                break;
            }
        }
        kills.push((attacks, killed_at.unwrap()));
    }
    // Cuts at ticks 0, 6 and 12 (0.60 s); punches at 0, 8, 16, 24, 32 (1.60 s).
    assert_eq!(kills, [(3, 12), (5, 32)]);
    assert!(WeaponType::Shiv.damage() > WeaponType::Fists.damage());
    assert!(WeaponType::Shiv.cooldown_ticks() < WeaponType::Fists.cooldown_ticks());
    assert_eq!(WeaponType::Shiv.ammo_pool(), None);
}

#[test]
fn an_authored_secret_grants_a_personal_shiv_once_and_is_counted() {
    let mut state = fixture(false, true);
    let a = Uuid::new_v4();
    let b = Uuid::new_v4();
    state.add_player(a, "First".into(), Role::Human);
    state.add_player(b, "Second".into(), Role::Agent);
    state.players[0].x = 4.5;
    state.players[1].x = -6.0;
    state.tick(0.05);
    assert!(state.players[0].inventory.owns(WeaponType::Shiv));
    assert_eq!(state.players[0].weapon, WeaponType::Shiv);
    assert!(!state.players[1].inventory.owns(WeaponType::Shiv));
    assert!(
        state.pickups[0].available,
        "a personal find stays for others"
    );
    state.players[1].x = 5.0;
    state.tick(0.05);
    assert!(state.players[1].inventory.owns(WeaponType::Shiv));
    for id in [a, b] {
        let record = state.player_record(id).unwrap();
        assert_eq!((record.total.secrets, record.attempt.secrets), (1, 1));
    }
    for _ in 0..40 {
        state.tick(0.05);
    }
    assert_eq!(state.player_record(a).unwrap().total.secrets, 1);
}

#[test]
fn authored_secret_flags_are_strict() {
    let supply = serde_json::json!([{
        "id":"cache_shiv","feet":[5,0,0],"grant":{"kind":"weapon","weapon":"shiv"},"claim":"personal"
    }]);
    let base = document(false, supply);
    let state = GameState::with_authored_map(read(&base).unwrap());
    assert!(!state.pickups[0].secret, "secret defaults to false");
    for bad in [serde_json::json!("yes"), serde_json::json!(1)] {
        let mut json = base.clone();
        json["supplies"][0]["secret"] = bad;
        assert!(read(&json).is_err());
    }
    let mut arcade = base.clone();
    arcade["equipment"] = "full_arsenal".into();
    assert!(
        read(&arcade).is_err(),
        "no Shiv supply without discovery equipment"
    );
}

#[test]
fn shared_controller_draws_the_shiv_only_when_every_gun_is_dry() {
    let mut state = fixture(false, false);
    let me = Uuid::new_v4();
    let foe = Uuid::new_v4();
    state.add_player(me, "Agent".into(), Role::Agent);
    state.add_player(foe, "Foe".into(), Role::Human);
    state.players[0].x = 0.0;
    state.players[0].z = 0.0;
    state.players[1].x = 1.5;
    state.players[1].z = 0.0;
    let player = &mut state.players[0];
    player.inventory.grant_weapon(WeaponType::Shiv);
    player.inventory.grant_weapon(WeaponType::Tack);
    player.weapon = WeaponType::Shiv;
    let snapshot = state.snapshot();
    let loadout = state.players[0]
        .inventory
        .state(me, WeaponType::Shiv, snapshot.tick)
        .unwrap();
    let action = control_action(me, &snapshot, Some(&loadout), Action::default());
    assert_eq!(
        action.weapon_swap,
        Some(WeaponType::Tack),
        "a loaded gun beats a held blade"
    );
    let mut dry = loadout.clone();
    dry.selected = WeaponType::Tack;
    for count in &mut dry.ammo {
        count.rounds = 0;
    }
    let action = control_action(
        me,
        &snapshot,
        Some(&dry),
        Action {
            fire: true,
            ..Default::default()
        },
    );
    assert_eq!(action.weapon_swap, Some(WeaponType::Shiv), "not bare fists");
    assert!(!action.forward, "already inside the Shiv's reach");
    assert!(action.fire);
    assert!(matches!(
        action.look_at,
        Some(LookAt {
            player_id: Some(id),
            ..
        }) if id == foe
    ));
    let mut fists_only = dry.clone();
    fists_only.weapons.retain(|w| *w != WeaponType::Shiv);
    let action = control_action(me, &snapshot, Some(&fists_only), Action::default());
    assert_eq!(action.weapon_swap, Some(WeaponType::Fists));
    assert!(action.forward, "fists still have to close in");
}
