//! Integration and unit tests for the Article Blade foundation.
use super::*;
use crate::maps::AuthoredMap;
use crate::protocol::{
    Action, ArticleBladeInfo, ArticleBladePhase, CampaignActor, EnemyKind, EnemyPhase, Role,
    WeaponType,
};
use crate::sim::GameState;
use uuid::Uuid;

#[test]
fn test_authored_m15_blade_range_loads_and_initializes_plinth() {
    let map = AuthoredMap::read(
        include_bytes!("../../../../server/maps/test/m15_blade_range.json").as_slice(),
    )
    .expect("m15_blade_range.json must load and validate");

    assert!(map.article_blade().is_some());
    let blade_info = map.article_blade().unwrap();
    assert_eq!(blade_info.pickup_id, "stadium_blade");
    assert_eq!(blade_info.feet, [0.0, 0.4, 0.0]);
    assert_eq!(blade_info.return_ticks, 300);

    let sim = GameState::with_authored_map(map);
    assert!(sim.article_blade.is_some());
    let plinth = sim.article_blade.as_ref().unwrap();
    assert!(plinth.is_available());
    assert_eq!(plinth.holder(), None);
    assert_eq!(plinth.return_in(), None);

    let snap = sim.snapshot();
    assert!(snap.article_blade.is_some());
    let blade_snap = snap.article_blade.as_ref().unwrap();
    assert_eq!(blade_snap.phase, ArticleBladePhase::Available);
    assert_eq!(blade_snap.uses_left, 0);
    assert_eq!(blade_snap.holder, None);
    assert_eq!(blade_snap.return_in, None);

    let pickup = snap
        .pickups
        .iter()
        .find(|p| p.id == "stadium_blade")
        .expect("blade plinth must project an ordinary weapon pickup");
    assert!(pickup.available);
    assert_eq!(pickup.weapon, "Article Blade");
    assert_eq!(pickup.y, 0.8); // floor 0.4 + 0.4 pickup elevation
}

#[test]
fn test_plinth_approach_and_claim_atomic() {
    let map = AuthoredMap::read(
        include_bytes!("../../../../server/maps/test/m15_blade_range.json").as_slice(),
    )
    .expect("m15_blade_range.json must load");
    let mut sim = GameState::with_authored_map(map);

    let p1 = Uuid::new_v4();
    let p2 = Uuid::new_v4();
    sim.add_player(p1, "Contender1".into(), Role::Human);
    sim.add_player(p2, "Contender2".into(), Role::Human);

    // Initial tick: contenders spawn outside the plinth pad.
    sim.set_action(p1, Action::default());
    sim.set_action(p2, Action::default());
    sim.tick(0.05);

    // Both players step onto the plinth at [0, 0.4, 0].
    sim.players[0].x = 0.0;
    sim.players[0].y = 0.4;
    sim.players[0].z = 0.0;

    sim.players[1].x = 0.0;
    sim.players[1].y = 0.4;
    sim.players[1].z = 0.0;

    sim.tick(0.05);

    // Exactly one player received the blade.
    let p1_blade = sim.players[0].inventory.owns(WeaponType::ArticleBlade);
    let p2_blade = sim.players[1].inventory.owns(WeaponType::ArticleBlade);
    assert!(
        p1_blade ^ p2_blade,
        "exactly one contender claims the blade"
    );

    let holder_id = if p1_blade { p1 } else { p2 };
    let holder_idx = if p1_blade { 0 } else { 1 };
    let plinth = sim.article_blade.as_ref().unwrap();
    assert_eq!(plinth.holder(), Some(holder_id));
    assert_eq!(sim.players[holder_idx].inventory.article_blade_uses(), 12);
    assert_eq!(sim.players[holder_idx].weapon, WeaponType::ArticleBlade);

    let snap = sim.snapshot();
    let blade_snap = snap.article_blade.as_ref().unwrap();
    assert_eq!(blade_snap.phase, ArticleBladePhase::Held);
    assert_eq!(blade_snap.holder, Some(holder_id));
    assert_eq!(blade_snap.uses_left, 12);

    let pickup = snap
        .pickups
        .iter()
        .find(|p| p.id == "stadium_blade")
        .unwrap();
    assert!(!pickup.available);
}

#[test]
fn test_exact_nine_tick_cadence_and_twelve_uses_exhaustion() {
    let map = AuthoredMap::read(
        include_bytes!("../../../../server/maps/test/m15_blade_range.json").as_slice(),
    )
    .expect("m15_blade_range.json must load");
    let mut sim = GameState::with_authored_map(map);

    let holder_id = Uuid::new_v4();
    let target_id = Uuid::new_v4();
    sim.add_player(holder_id, "Swinger".into(), Role::Human);
    sim.add_player(target_id, "Target".into(), Role::Human);
    sim.spawn_shields.clear();

    // Claim blade.
    sim.article_blade.as_mut().unwrap().claim(holder_id, 10);
    sim.players[0].inventory.grant_weapon(WeaponType::Tack);
    sim.players[0].inventory.grant_article_blade(12);
    sim.players[0].weapon = WeaponType::ArticleBlade;
    sim.players[0].last_non_blade_weapon = WeaponType::Tack;

    // Place target within 1.5 m (reach is 2.0 m) on open ground.
    sim.players[0].x = 10.0;
    sim.players[0].y = crate::sim::PLAYER_FLOOR_Y;
    sim.players[0].z = 10.0;
    sim.players[0].yaw = 0.0; // facing +X

    sim.players[1].x = 11.5;
    sim.players[1].y = crate::sim::PLAYER_FLOOR_Y;
    sim.players[1].z = 10.0;
    sim.players[1].hp = 1000; // ample HP
    sim.players[1].campaign = Some(CampaignActor::Union {
        kind: EnemyKind::Sweeper,
        phase: EnemyPhase::Idle,
        phase_started: 0,
        phase_ends: 100,
        seated: false,
    });

    sim.set_action(
        holder_id,
        Action {
            fire: true,
            ..Action::default()
        },
    );
    sim.set_action(target_id, Action::default());

    // Swing 1 on tick 11.
    sim.tick(0.05);
    assert_eq!(sim.players[0].inventory.article_blade_uses(), 11);
    assert_eq!(sim.players[1].hp, 930); // 1000 - 70 base damage

    // Ticks 12..=19: held fire cannot outrun 9-tick cooldown.
    for _ in 12..=19 {
        sim.tick(0.05);
        assert_eq!(sim.players[0].inventory.article_blade_uses(), 11);
        assert_eq!(sim.players[1].hp, 930);
    }

    // Tick 20: 9 ticks after tick 11, swing 2 fires.
    sim.tick(0.05);
    assert_eq!(sim.players[0].inventory.article_blade_uses(), 10);
    assert_eq!(sim.players[1].hp, 860);

    // Fire remaining 9 swings until 1 use left.
    for swing in 3..=11 {
        for _ in 1..9 {
            sim.tick(0.05);
        }
        sim.tick(0.05);
        assert_eq!(sim.players[0].inventory.article_blade_uses(), 12 - swing);
    }
    assert_eq!(sim.players[0].inventory.article_blade_uses(), 1);

    // Wait 8 ticks before the 12th swing.
    for _ in 1..9 {
        sim.tick(0.05);
    }

    // 12th swing: resolves damage, exhausts uses, returns blade to plinth cooling,
    // and reverts holder to last_non_blade_weapon with fire_latched = true.
    let hp_before_twelfth = sim.players[1].hp;
    sim.tick(0.05);

    assert_eq!(
        sim.players[1].hp,
        hp_before_twelfth - 70,
        "12th swing hit must resolve before weapon removal"
    );
    assert_eq!(sim.players[0].inventory.article_blade_uses(), 0);
    assert!(!sim.players[0].inventory.owns(WeaponType::ArticleBlade));
    assert_eq!(
        sim.players[0].weapon,
        WeaponType::Tack,
        "exhausted blade falls back to last non-blade weapon"
    );
    assert!(
        sim.players[0].fire_latched,
        "fire must be latched so 13th held tick does not fire fallback weapon"
    );

    // Next tick with fire still held: no attack occurs on fallback weapon.
    sim.tick(0.05);
    assert!(
        sim.shot_results.is_empty(),
        "fire remains latched so fallback weapon does not fire while trigger held"
    );

    // Releasing fire unlatches trigger.
    sim.set_action(
        holder_id,
        Action {
            fire: false,
            ..Action::default()
        },
    );
    sim.tick(0.05);
    assert!(!sim.players[0].fire_latched);

    // Plinth is now Cooling.
    let plinth = sim.article_blade.as_ref().unwrap();
    assert_eq!(plinth.holder(), None);
    assert!(matches!(
        plinth.phase(),
        ArticleBladePlinthPhase::Cooling { .. }
    ));
}

#[test]
fn test_reach_and_occlusion_walls() {
    let map = AuthoredMap::read(
        include_bytes!("../../../../server/maps/test/m15_blade_range.json").as_slice(),
    )
    .expect("m15_blade_range.json must load");
    let mut sim = GameState::with_authored_map(map);

    let swinger = Uuid::new_v4();
    let target = Uuid::new_v4();
    sim.add_player(swinger, "Swinger".into(), Role::Human);
    sim.add_player(target, "Target".into(), Role::Human);

    sim.players[0].inventory.grant_article_blade(12);
    sim.players[0].weapon = WeaponType::ArticleBlade;

    // Target at 2.5 m (beyond 2.0 m reach).
    sim.players[0].x = 0.0;
    sim.players[0].y = 0.0;
    sim.players[0].z = 0.0;
    sim.players[0].yaw = 0.0;

    sim.players[1].x = 2.5;
    sim.players[1].y = 0.0;
    sim.players[1].z = 0.0;
    sim.players[1].hp = 100;

    sim.set_action(
        swinger,
        Action {
            fire: true,
            ..Action::default()
        },
    );
    sim.set_action(target, Action::default());
    sim.tick(0.05);

    assert_eq!(sim.players[1].hp, 100, "2.5 m target is beyond 2.0 m reach");
    assert_eq!(
        sim.players[0].inventory.article_blade_uses(),
        11,
        "swing is consumed even on miss"
    );

    // Occlusion check: swinger at [5, 0, 0] looking east at target at [8, 0, 0]
    // The occlusion_wall is at X in [6, 7], height 3 m.
    sim.players[0].x = 5.0;
    sim.players[0].yaw = 0.0; // facing +X
    sim.players[0].fire_latched = false;

    sim.players[1].x = 8.0;
    sim.players[1].hp = 100;

    // Advance 9 ticks for cooldown.
    for _ in 0..9 {
        sim.set_action(
            swinger,
            Action {
                fire: false,
                ..Action::default()
            },
        );
        sim.tick(0.05);
    }
    sim.set_action(
        swinger,
        Action {
            fire: true,
            ..Action::default()
        },
    );
    sim.tick(0.05);

    assert_eq!(sim.players[1].hp, 100, "occlusion wall blocks blade hit");
}

#[test]
fn test_camping_prevention_on_cooldown_return() {
    let mut plinth = ArticleBladePlinth::new(ArticleBladeInfo {
        pickup_id: "test_blade".into(),
        feet: [0.0, 0.0, 0.0],
        return_ticks: 10,
    });

    let camper = Uuid::new_v4();

    // Plinth starts cooling with 10 ticks.
    plinth.start_cooling(100);

    // Camper stands on plinth pad throughout cooling.
    for tick in 101..=110 {
        plinth.tick_active(tick);
    }

    // Cooling is finished (return_in == 0 -> Available).
    assert!(plinth.is_available());

    // Camper has not been recorded outside while available.
    assert!(
        !plinth.is_eligible_outside(camper),
        "camper cannot claim without leaving and reentering"
    );

    // Camper steps outside:
    plinth.record_outside(camper);
    assert!(
        plinth.is_eligible_outside(camper),
        "claim eligible after leaving"
    );
}

#[test]
fn test_holder_death_and_leave_starts_cooldown() {
    let map = AuthoredMap::read(
        include_bytes!("../../../../server/maps/test/m15_blade_range.json").as_slice(),
    )
    .expect("m15_blade_range.json must load");
    let mut sim = GameState::with_authored_map(map);

    let holder = Uuid::new_v4();
    sim.add_player(holder, "Holder".into(), Role::Human);
    sim.article_blade.as_mut().unwrap().claim(holder, 50);
    sim.players[0].inventory.grant_article_blade(10);
    sim.players[0].weapon = WeaponType::ArticleBlade;

    // Holder dies from 100 damage.
    sim.resolve_fighter_hit(0, 0, 100, None);

    assert!(!sim.players[0].inventory.owns(WeaponType::ArticleBlade));
    let plinth = sim.article_blade.as_ref().unwrap();
    assert_eq!(plinth.holder(), None);
    assert!(matches!(
        plinth.phase(),
        ArticleBladePlinthPhase::Cooling { .. }
    ));
}

#[test]
fn last_blade_swing_frag_retains_the_trace_after_fallback_selection() {
    let mut arcade: serde_json::Value = serde_json::from_slice(include_bytes!(
        "../../../../server/maps/test/m15_blade_range.json"
    ))
    .unwrap();
    // The retained range's encounter roster makes humans campaign allies.
    // This case stages an arcade frag on its same plinth and geometry.
    arcade.as_object_mut().unwrap().remove("encounters");
    let map = AuthoredMap::read(serde_json::to_vec(&arcade).unwrap().as_slice()).unwrap();
    let mut sim = GameState::with_authored_map(map);
    let owner = Uuid::from_u128(1);
    let victim = Uuid::from_u128(2);
    sim.add_player(owner, "Same".into(), Role::Human);
    sim.add_player(victim, "Same".into(), Role::Human);
    sim.spawn_shields.clear();
    sim.article_blade.as_mut().unwrap().claim(owner, 0);
    assert_eq!(sim.article_blade.as_ref().unwrap().holder(), Some(owner));
    sim.players[0].inventory.grant_weapon(WeaponType::Tack);
    sim.players[0].inventory.grant_article_blade(1);
    sim.players[0].weapon = WeaponType::ArticleBlade;
    sim.players[0].last_non_blade_weapon = WeaponType::Tack;
    for (index, player) in sim.players.iter_mut().enumerate() {
        player.x = 10.0 + index as f32 * 1.5;
        player.y = crate::sim::PLAYER_FLOOR_Y;
        player.z = 10.0;
        player.yaw = 0.0;
        player.armor = 0;
    }
    sim.players[1].hp = 70;
    sim.set_action(
        owner,
        Action {
            fire: true,
            ..Action::default()
        },
    );
    sim.tick(0.05);
    assert!(
        sim.players[1].hp <= 0,
        "hp={}, shots={:?}, phase={:?}, weapon={:?}, uses={}",
        sim.players[1].hp,
        sim.shot_results,
        sim.round_state,
        sim.players[0].weapon,
        sim.players[0].inventory.article_blade_uses()
    );
    assert_eq!(sim.players[0].weapon, WeaponType::Tack);
    assert!(sim.players[0].fire_latched);
    assert!(sim.events.iter().any(|event| matches!(event,
        crate::protocol::GameEvent::Frag { killer_id: Some(k), victim_id: Some(v), weapon: Some(WeaponType::ArticleBlade), .. }
            if *k == owner && *v == victim)));
}
