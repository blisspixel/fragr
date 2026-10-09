//! Arc outcomes use the ordinary server shot and finite human reload paths.
use super::GameState;
use crate::maps::AuthoredMap;
use crate::protocol::{Action, AmmoPool, LookAt, Role, ShotImpact, WeaponType};
use serde_json::json;
use uuid::Uuid;

fn arena(wall: bool) -> (GameState, Uuid, Uuid) {
    let map = AuthoredMap::read(serde_json::to_vec(&json!({
        "version": 1, "map_id": 1000, "name": "Arc fixture", "half_extent": 40,
        "ground": "concrete", "equipment": "discovery",
        "solids": if wall { json!([{ "id":"wall", "min":[4,0,-2], "max":[4.3,3,2], "surface":"enamel" }]) } else { json!([]) },
        "spawns": [{"id":"entry", "feet":[0,0,-8], "yaw":0}],
        "landmarks": [{"id":"exit", "feet":[0,0,30]}]
    })).unwrap().as_slice()).unwrap();
    let mut state = GameState::with_authored_map(map);
    state.seed(42);
    let shooter = Uuid::from_u128(1);
    let target = Uuid::from_u128(2);
    state.add_player(shooter, "Shooter".into(), Role::Human);
    state.add_player(target, "Target".into(), Role::Agent);
    for (index, player) in state.players.iter_mut().enumerate() {
        player.x = index as f32 * 8.0;
        player.z = 0.0;
    }
    state.players[0].inventory.grant_weapon(WeaponType::Arc);
    state.players[0].weapon = WeaponType::Arc;
    (state, shooter, target)
}

fn aim(state: &mut GameState, id: Uuid, x: f32, y: f32, fire: bool, reload: bool) {
    state.set_action(
        id,
        Action {
            fire,
            reload,
            look_at: Some(LookAt {
                player_id: None,
                x: Some(x),
                y: Some(y),
                z: Some(0.0),
            }),
            ..Action::default()
        },
    );
}

fn cells(state: &GameState, id: Uuid) -> u16 {
    state
        .players
        .iter()
        .find(|p| p.id == id)
        .unwrap()
        .inventory
        .state(id, WeaponType::Arc, state.tick)
        .unwrap()
        .ammo(AmmoPool::Cells)
}

#[test]
fn resolved_arc_bypasses_ordinary_armor_and_keeps_separate_effective_records() {
    let (mut state, shooter, _) = arena(false);
    state.players[1].armor = 100;
    aim(&mut state, shooter, 8.0, 0.9, true, false);
    state.tick(0.05);
    assert_eq!((state.players[1].hp, state.players[1].armor), (82, 100));
    let shot = &state.shot_results[0];
    assert!(shot.hit);
    assert_eq!(shot.damage, 18);
    assert_eq!(shot.trace.as_ref().unwrap().weapon, WeaponType::Arc);
    assert_eq!(cells(&state, shooter), 39);
    let record = state.player_record(shooter).unwrap();
    let arc = record.total.weapon(WeaponType::Arc);
    assert_eq!(
        (arc.attacks, arc.connects, arc.hp_damage, arc.armor_damage),
        (1, 1, 18, 0)
    );
    assert_eq!(record.total.weapon(WeaponType::Rail).attacks, 0);
    assert!(record.record_for_version(2).is_err());

    let (mut bullet, shooter, _) = arena(false);
    bullet.players[0]
        .inventory
        .grant_weapon(WeaponType::Flechette);
    bullet.players[0].weapon = WeaponType::Flechette;
    bullet.players[1].armor = 100;
    aim(&mut bullet, shooter, 8.0, 0.9, true, false);
    bullet.tick(0.05);
    assert_eq!((bullet.players[1].hp, bullet.players[1].armor), (100, 75));
}

#[test]
fn actual_arc_cadence_head_band_and_range_stay_distinct() {
    let (mut state, shooter, _) = arena(false);
    aim(&mut state, shooter, 8.0, 1.65, true, false);
    let mut ticks = vec![];
    for _ in 0..4 {
        state.tick(0.05);
        if !state.shot_results.is_empty() {
            ticks.push(state.tick);
        }
    }
    assert_eq!(ticks, [1, 4]);
    assert_eq!(state.players[1].hp, 28);
    assert_eq!(
        state
            .player_record(shooter)
            .unwrap()
            .total
            .weapon(WeaponType::Arc)
            .heads,
        2
    );
    assert_eq!(cells(&state, shooter), 38);

    let (mut distant, shooter, _) = arena(false);
    distant.players[1].x = 26.0;
    aim(&mut distant, shooter, 26.0, 0.9, true, false);
    distant.tick(0.05);
    assert_eq!(distant.players[1].hp, 100);
    assert_eq!(
        cells(&distant, shooter),
        39,
        "a resolved miss still spends its Cell"
    );
    let trace = distant.shot_results[0].trace.as_ref().unwrap();
    assert!(!distant.shot_results[0].hit);
    assert_eq!(trace.impact, ShotImpact::Range);
    let end = trace.end;
    let distance = end
        .iter()
        .zip(trace.origin)
        .map(|(a, b)| (a - b).powi(2))
        .sum::<f32>()
        .sqrt();
    assert!((distance - 24.0).abs() < 0.001);
}

#[test]
fn ordinary_cover_stops_arc_instead_of_chaining_or_penetrating() {
    let (mut state, shooter, _) = arena(true);
    aim(&mut state, shooter, 8.0, 0.9, true, false);
    state.tick(0.05);
    assert_eq!(state.players[1].hp, 100);
    assert_eq!(cells(&state, shooter), 39);
    let trace = state.shot_results[0].trace.as_ref().unwrap();
    assert!(
        trace.pellets.is_empty(),
        "one ordinary ray uses the retained primary trace"
    );
    assert!(matches!(trace.impact, ShotImpact::Solid { .. }));
    assert!((4.0..=4.3).contains(&trace.end[0]));
    assert_eq!(
        state
            .player_record(shooter)
            .unwrap()
            .total
            .weapon(WeaponType::Arc)
            .damaging_attacks,
        0
    );
}

#[test]
fn arc_still_respects_spawn_protection_and_disabled_friendly_fire() {
    let (mut state, shooter, target) = arena(false);
    state.spawn_shields.insert(target, 20);
    aim(&mut state, shooter, 8.0, 0.9, true, false);
    state.tick(0.05);
    assert_eq!(state.players[1].hp, 100);
    assert_eq!(cells(&state, shooter), 39);
    assert_eq!(
        state
            .player_record(shooter)
            .unwrap()
            .total
            .weapon(WeaponType::Arc)
            .hp_damage,
        0
    );

    let (mut state, shooter, _) = arena(false);
    state.config.rules =
        crate::rules::RuleSet::new(crate::protocol::GameMode::Tdm, &[], false).unwrap();
    state.players[0].team = Some(crate::protocol::Team::Coalition);
    state.players[1].team = Some(crate::protocol::Team::Coalition);
    aim(&mut state, shooter, 8.0, 0.9, true, false);
    state.tick(0.05);
    assert_eq!(state.players[1].hp, 100);
    assert_eq!(cells(&state, shooter), 39);
    assert_eq!(
        state
            .player_record(shooter)
            .unwrap()
            .total
            .weapon(WeaponType::Arc)
            .damaging_attacks,
        0
    );
}

#[test]
fn shared_controller_uses_owned_arc_for_armored_nearby_targets_without_overriding_explicit_choice()
{
    let (mut state, shooter, _) = arena(false);
    state.players[0]
        .inventory
        .grant_weapon(WeaponType::Flechette);
    state.players[0].weapon = WeaponType::Flechette;
    state.players[1].armor = 50;
    let equipment = state.players[0]
        .inventory
        .state(shooter, WeaponType::Flechette, 0)
        .unwrap();
    let intent = crate::inventory::control_action(
        shooter,
        &state.snapshot(),
        Some(&equipment),
        Action::default(),
    );
    assert_eq!(intent.weapon_swap, Some(WeaponType::Arc));
    assert!(intent.fire);
    let intent = crate::inventory::control_action(
        shooter,
        &state.snapshot(),
        Some(&equipment),
        Action {
            weapon_swap: Some(WeaponType::Flechette),
            ..Action::default()
        },
    );
    assert_eq!(intent.weapon_swap, None);
    state.players[1].x = 30.0;
    let intent = crate::inventory::control_action(
        shooter,
        &state.snapshot(),
        Some(&equipment),
        Action::default(),
    );
    assert_ne!(intent.weapon_swap, Some(WeaponType::Arc));
    let mut dry = equipment.clone();
    dry.ammo
        .iter_mut()
        .find(|a| a.pool == AmmoPool::Cells)
        .unwrap()
        .rounds = 0;
    state.players[1].x = 8.0;
    let intent =
        crate::inventory::control_action(shooter, &state.snapshot(), Some(&dry), Action::default());
    assert_ne!(intent.weapon_swap, Some(WeaponType::Arc));

    // A Heavy has no implicit plate. Only its actual optional carried armor
    // makes it an Arc counter target; registered shield owners remain distinct.
    state.players[0].campaign = Some(crate::protocol::CampaignActor::Participant {});
    for (kind, armor, wants_arc) in [
        (crate::protocol::EnemyKind::HeavySweeper, 0, false),
        (crate::protocol::EnemyKind::HeavySweeper, 100, true),
        (crate::protocol::EnemyKind::Auditor, 0, true),
        (crate::protocol::EnemyKind::Assessor, 0, true),
    ] {
        state.players[1].armor = armor;
        state.players[1].campaign = Some(crate::protocol::CampaignActor::Union {
            kind,
            phase: crate::protocol::EnemyPhase::Moving,
            phase_started: 0,
            phase_ends: 100,
            seated: false,
        });
        let intent = crate::inventory::control_action(
            shooter,
            &state.snapshot(),
            Some(&equipment),
            Action::default(),
        );
        assert_eq!(
            intent.weapon_swap == Some(WeaponType::Arc),
            wants_arc,
            "kind={kind:?}, armor={armor}"
        );
    }
}

#[test]
fn ordinary_human_reload_consumes_exactly_forty_cells_and_held_reload_cannot_repeat() {
    let (mut state, shooter, _) = arena(false);
    state.arm_joined_magazines(shooter);
    assert_eq!(
        state.players[0]
            .inventory
            .state(shooter, WeaponType::Arc, 0)
            .unwrap()
            .shots(WeaponType::Arc),
        Some(12)
    );
    aim(&mut state, shooter, -30.0, 0.9, true, false);
    for _ in 0..38 {
        state.tick(0.05);
    }
    assert_eq!(cells(&state, shooter), 28);
    assert_eq!(
        state
            .player_record(shooter)
            .unwrap()
            .total
            .weapon(WeaponType::Arc)
            .attacks,
        12
    );
    aim(&mut state, shooter, -30.0, 0.9, true, true);
    for _ in 0..65 {
        state.tick(0.05);
    }
    assert_eq!(cells(&state, shooter), 16);
    assert_eq!(
        state
            .player_record(shooter)
            .unwrap()
            .total
            .weapon(WeaponType::Arc)
            .attacks,
        24
    );
    assert!(
        !state.players[0].inventory.reloading(),
        "holding R cannot automatically refill the next empty magazine"
    );
    for expected in [4, 0] {
        aim(&mut state, shooter, -30.0, 0.9, false, false);
        state.tick(0.05);
        aim(&mut state, shooter, -30.0, 0.9, true, true);
        for _ in 0..65 {
            state.tick(0.05);
        }
        assert_eq!(cells(&state, shooter), expected);
    }
    let record = state.player_record(shooter).unwrap();
    assert_eq!(record.total.weapon(WeaponType::Arc).attacks, 40);
    assert_eq!(record.total.weapon(WeaponType::Arc).damaging_attacks, 0);
    assert!(record.total.dry_triggers > 0);
    let rng = state.rng_state;
    for _ in 0..20 {
        state.tick(0.05);
    }
    assert_eq!(
        state.rng_state, rng,
        "a held empty trigger resolves no extra rays"
    );
    assert_eq!(
        state
            .player_record(shooter)
            .unwrap()
            .total
            .weapon(WeaponType::Arc)
            .attacks,
        40
    );
}
